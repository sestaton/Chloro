package Chloro::Command::screen_reads;
# ABSTRACT: Extract chloroplast regions from a read set.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use Cwd                 qw(abs_path getcwd);
use IPC::System::Simple qw(system);
use Time::HiRes         qw(gettimeofday);
use Parallel::ForkManager;
use File::Basename;
use File::Spec;
use File::Temp;
use Try::Tiny;

sub opt_spec {
    return (    
	[ "infile|i=s",   "Fasta file of reads or contigs to filter."                                       ],
        [ "outfile|o=s",  "A file to place the filtered sequences."                                         ],
	[ "database|d=s", "The Fasta file to use a screening database."                                     ],
        [ "length|l=i",   "Length (integer) to be used as the lower threshold for filtering (Default: 50)." ],
	[ "threads|t=i",  "Number of threads to create (Default: 1)."                                       ],
	[ "cpu|a=i",      "Number of processors to use for each thread (Default: 1)."                       ],
	[ "seqnum|n=i",   "The number of sequences to process with each thread."                            ],  
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    elsif ($self->app->global_options->{help}) {
        $self->help;
    }
    elsif (!$opt->{infile} && !$opt->{outfile} && !$opt->{database} && !$opt->{seqnum}) {
	say "\nERROR: Required arguments not given.";
        $self->help and exit(0);
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man} ||
	$self->app->global_options->{help};

    my $blastfile = _run_screening($opt);
    my $scr_reads = _filter_hits($opt, $blastfile);
    my $result    = _repair_reads($scr_reads);
}

sub _run_screening {
    my ($opt) = @_;
    my $t0       = gettimeofday();
    my $infile   = $opt->{infile};
    my $database = $opt->{database};
    my $thread   = $opt->{threads};
    my $cpu      = $opt->{cpu};
    my $seqnum   = $opt->{seqnum};

    unless (-e $infile && -e $database) {
	say "\nERROR: Missing input files. Check that the input and database exist. Exiting.\n";
	exit(1);
    }

    my %blasts;
    $cpu //= 1;  
    $thread //= 1;
    
    my ($dbfile, $dbdir, $dbext) = fileparse($database, qr/\.[^.]*/);
    my ($file, $dir, $ext) = fileparse($infile, qr/\.[^.]*/);
    my ($db_path) = _make_blastdb($database, $dbfile, $dbdir);
    my ($seq_files, $seqct) = _split_reads($infile, $seqnum);
    my $blastfile = $file."_".$dbfile.".bln";

    open my $out, '>>', $blastfile or die "\nERROR: Could not open file: $blastfile\n"; 

    my $pm = Parallel::ForkManager->new($thread);
    $pm->run_on_finish( sub { my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data_ref) = @_;
			      for my $bl (sort keys %$data_ref) {
				  open my $report, '<', $bl or die "\nERROR: Could not open file: $bl\n";
				  print $out $_ while <$report>;
				  close $report;
				  unlink $bl;
			      }
			      my $t1 = gettimeofday();
			      my $elapsed = $t1 - $t0;
			      my $time = sprintf("%.2f",$elapsed/60);
			      say basename($ident),
			      " just finished with PID $pid and exit code: $exit_code in $time minutes";
			} );

    for my $seqs (@$seq_files) {
	$pm->start($seqs) and next;
	my $blast_out = _run_blast($seqs, $dbfile, $db_path, $cpu);
	$blasts{$blast_out} = 1;
    
	unlink $seqs;
	$pm->finish(0, \%blasts);
    }

    $pm->wait_all_children;

    close $out;

    my $t2 = gettimeofday();
    my $total_elapsed = $t2 - $t0;
    my $final_time = sprintf("%.2f",$total_elapsed/60);

    unlink glob("$db_path*");
    #say "\n========> Finished running BLAST on $seqct sequences in $final_time minutes";
    return $blastfile;
}

sub _run_blast {
    my ($subseq_file, $dbfile, $db_path, $cpu) = @_;

    my ($subfile, $subdir, $subext) = fileparse($subseq_file, qr/\.[^.]*/);

    my $suffix = ".bln";
    my $subseq_out = $subfile."_".$dbfile.$suffix;

    my @blast_cmd = "blastall ". 
	            "-p blastn ".
		    "-F F ".
		    "-i $subseq_file ".
		    "-d $db_path ".
		    "-o $subseq_out ".
		    "-a $cpu ".
		    "-m 8";

    _run_cmd(\@blast_cmd, 'blastall');
    
    return $subseq_out;
}

sub _make_blastdb {
    my ($database, $dbfile, $dbdir) = @_;

    $dbfile =~ s/\.f.*//;
    my $db = $dbfile."_chloro_blastdb";
    my $db_path = File::Spec->catfile($dbdir, $db);
    unlink $db_path if -e $db_path;
    my $format_log = 'formatdb.log';

    my @formatdb = "formatdb -p F -i $database -t $db -n $db_path 2>&1 > /dev/null";
    _run_cmd(\@formatdb, 'formatdb');
    
    unlink $format_log if -e $format_log;
    return $db_path;
}

sub _split_reads {
    my ($infile, $seqnum) = @_;

    my ($iname, $ipath, $isuffix) = fileparse($infile, qr/\.[^.]*/);
    
    my $out;
    my $count = 0;
    my $fcount = 1;
    my @split_files;
    $iname =~ s/\.fa.*//;
    
    my $cwd = getcwd();

    my $tmpiname = $iname."_".$fcount."_XXXX";
    my $fname = File::Temp->new( TEMPLATE => $tmpiname,
                                 DIR => $cwd,
				 SUFFIX => ".fasta",
				 UNLINK => 0);
    open $out, '>', $fname or die "\nERROR: Could not open file: $fname\n";
    
    push @split_files, $fname;
    my $in = _get_fh($infile);
    my @aux = undef;
    my ($name, $comm, $seq, $qual);
    while (($name, $comm, $seq, $qual) = _readfq(\*$in, \@aux)) {
	if ($count % $seqnum == 0 && $count > 0) {
	    $fcount++;
            $tmpiname = $iname."_".$fcount."_XXXX";
            my $fname = File::Temp->new( TEMPLATE => $tmpiname,
					 DIR => $cwd,
					 SUFFIX => ".fasta",
					 UNLINK => 0);
	    open $out, '>', $fname or die "\nERROR: Could not open file: $fname\n";

	    push @split_files, $fname;
	}
	say $out join "\n", ">".$name, $seq;
	$count++;
    }
    close $in; 
    close $out;
    return (\@split_files, $count);
}

sub _filter_hits {
    my ($opt, $blastfile) = @_;
    my $infile  = $opt->{infile};
    my $length  = $opt->{length};
    my $outfile = $opt->{outfile};

    $length //= 50;
    open my $in, '<', $blastfile or die "\nERROR: Could not open file: $!";
    my $fas = _get_fh($infile);
    open my $out, '>', $outfile or die "\nERROR: Could not open file: $!";
    
    my %match_range;
    
    while (my $l = <$in>) {
	chomp $l;
	my @f = split "\t", $l;
	if (@f) { # check for blank lines in input
	    next if exists $match_range{$f[0]};
	    $match_range{$f[0]} = join "|", $f[6], $f[7];
	}
    }
    close $in;
    
    my ($scrSeqCt, $validscrSeqCt) = (0, 0);
    
    my @aux = undef;
    my ($name, $comm, $seq, $qual);
    while (($name, $comm, $seq, $qual) = _readfq(\*$fas, \@aux)) {
	$scrSeqCt++ if defined $seq;
	if (exists $match_range{$name}) {
	    my ($match_start, $match_end) = split /\|/, $match_range{$name};
	    if (defined $match_start && defined $match_end) {
		my $match_length = $match_end - $match_start;
		if ($match_length >= $length) {
		    $validscrSeqCt++;
		    my $seq_match = substr $seq, $match_start, $match_length;
		    say $out join "\n", ">".$name, $seq_match;
		}
	    }
	}
    }
    close $fas;
    close $out;
    
    say "$scrSeqCt total sequences matched the target.";
    say "$validscrSeqCt were above the length threshold and were written to $outfile.";
    unlink $blastfile;
    return $outfile;
}

sub _repair_reads {
    my ($scr_reads) = @_;

    my $file = __FILE__;
    my $cmd_dir = basename(dirname(abs_path($file)));
    my $hmm_dir = basename(dirname($cmd_dir));
    my $chl_dir = basename(dirname($hmm_dir));
    my $pairfq  = File::Spec->catfile(abs_path($chl_dir), 'bin', 'pairfq_lite');

    unless (-e $pairfq) {
	die "\nERROR: 'pairfq_lite.pl' script not found. Please run the 'install_deps.sh' script before proceeding. Exiting.\n";
    }

    my ($sname, $spath, $ssuffix) = fileparse($scr_reads, qr/\.[^.]*/);

    my $ffile  = File::Spec->catfile($spath, $sname."_f".$ssuffix);
    my $rfile  = File::Spec->catfile($spath, $sname."_r".$ssuffix);
    my $fpfile = File::Spec->catfile($spath, $sname."_fp".$ssuffix);
    my $rpfile = File::Spec->catfile($spath, $sname."_rp".$ssuffix);
    my $fsfile = File::Spec->catfile($spath, $sname."_fs".$ssuffix);
    my $rsfile = File::Spec->catfile($spath, $sname."_rs".$ssuffix);
    my $ifile  = File::Spec->catfile($spath, $sname."_paired_interl".$ssuffix);
    my $sfile  = File::Spec->catfile($spath, $sname."_unpaired".$ssuffix);

    my @split_pairs = "$pairfq splitpairs ".
	              "-i $scr_reads ".
	              "-f $ffile ".
		      "-r $rfile";

    _run_cmd(\@split_pairs, 'pairfq splitpairs');

    my @make_pairs = "$pairfq makepairs ".
                      "-f $ffile ".
                      "-r $rfile ".
		      "-fp $fpfile ".
		      "-rp $rpfile ".
		      "-fs $fsfile ".
		      "-rs $rsfile";

    _run_cmd(\@make_pairs, 'pairfq makepairs');
    
    my @join_pairs = "$pairfq joinpairs ".
                      "-f $fpfile ".
                      "-r $rpfile ".
		      "-o $ifile";

    _run_cmd(\@join_pairs, 'pairfq joinpairs');

    open my $s_out, '>>', $sfile or die "\nERROR: Could not open file: $sfile\n";

    for my $singles ($fsfile, $rsfile) {
	open my $s, '<', $singles or die "\nERROR: Could not open file: $singles\n";
	while (my $l = <$s>) {
	    print $s_out $l;
	}
	close $s;
    }
    close $s_out;

    unlink $ffile;
    unlink $rfile;
    unlink $fpfile;
    unlink $rpfile;
    unlink $fsfile;
    unlink $rsfile;

    return;
}

sub _readfq {
    my ($fh, $aux) = @_;
    @$aux = [undef, 0] if (!@$aux);
    return if ($aux->[1]);
    if (!defined($aux->[0])) {
        while (<$fh>) {
            chomp;
            if (substr($_, 0, 1) eq '>' || substr($_, 0, 1) eq '@') {
                $aux->[0] = $_;
                last;
            }
        }
        if (!defined($aux->[0])) {
            $aux->[1] = 1;
            return;
        }
    }
    my ($name, $comm);
    defined $_ && do {
        ($name, $comm) = /^.(\S+)(?:\s+)(\S+)/ ? ($1, $2) : 
	                 /^.(\S+)/ ? ($1, '') : ('', '');
    };
    my $seq = '';
    my $c;
    $aux->[0] = undef;
    while (<$fh>) {
        chomp;
        $c = substr($_, 0, 1);
        last if ($c eq '>' || $c eq '@' || $c eq '+');
        $seq .= $_;
    }
    $aux->[0] = $_;
    $aux->[1] = 1 if (!defined($aux->[0]));
    return ($name, $comm, $seq) if ($c ne '+');
    my $qual = '';
    while (<$fh>) {
        chomp;
        $qual .= $_;
        if (length($qual) >= length($seq)) {
            $aux->[0] = undef;
            return ($name, $comm, $seq, $qual);
        }
    }
    $aux->[1] = 1;
    return ($name, $seq);
}

sub _run_cmd {
    my ($cmd, $name) = @_;

    my $exit_value;
    try {
        $exit_value = system([0..5], @$cmd);
    }
    catch {
        die "\nERROR: '$name' exited with exit value: $exit_value. Here is the exception: $_\n";
    };
}

sub _get_fh {
    my ($file) = @_;

    my $fh;
    if ($file =~ /\.gz$/) {
        open $fh, '-|', 'zcat', $file or die "\nERROR: Could not open file: $file\n";
    }
    elsif ($file =~ /\.bz2$/) {
        open $fh, '-|', 'bzcat', $file or die "\nERROR: Could not open file: $file\n";
    }
    else {
        open $fh, '<', $file or die "\nERROR: Could not open file: $file\n";
    }

    return $fh;
}

sub help {
    print STDERR<<END

USAGE: chloro screen_reads [-h] [-m]
    -m --man       :   Get the manual entry for a command.
    -h --help      :   Print the command usage.

Required:
    -i|infile      :   Fasta file of reads or contigs to filter.
    -o|outfile     :   A file to place the filtered sequences.
    -d|database    :   The Fasta file to use a screening database.
    -n|seqnum      :   The number of sequences to process with each thread.

Options:
    -l|length      :   Length (integer) to be used as the lower threshold for filtering (Default: 50).
    -t|threads     :   Number of threads to create (Default: 1).
    -a|cpu         :   Number of processors to use for each thread (Default: 1).

END
}

1;
__END__

=pod

=head1 NAME 
                                                                       
chloro screenreads - screen a set of NGS reads against a chlorplast refence and retain the aligned regions

=head1 SYNOPSIS    
 
chloro screenreads -i seqs.fas -d ref_cp.fas -o seqs_cp.fas -t 2 -n 100000 --cpu 2

=head1 DESCRIPTION
     
This command can accelerate screening reads by splitting an input file and 
running BLAST on multiple subsets of sequences concurrently. The size of 
the splits to make and the number of threads to create are optional. The 
input set of sequences may be in fasta or fastq format, and the files may
be compressed with gzip or bzip2.                                                                

=head1 DEPENDENCIES

The following Perl dependencies are required:

Module
IPC::System::Simple
Parallel::ForkManager
Try::Tiny

Tested with:

=over

=item *
L<Parallel::ForkManager> 0.7.9 and Perl 5.20.12 (Red Hat Enterprise Linux Server release 5.9)

=back

=head1 AUTHOR 

S. Evan Staton                                                

=head1 CONTACT
 
statonse at gmail dot com

=head1 REQUIRED ARGUMENTS

=over 2

=item -i, --infile

The file of sequences to BLAST. The format may be FASTA or FASTQ,
and may be compressed with either gzip or bzip2.

=item -o, --outfile

A file to place the screened reads.

=item -n, --seqnum

The size of the splits to create. This number determines how many 
sequences will be written to each split. 

NB: If the input sequence file has millions of sequences and a 
very small number is given fo the split value then there could 
potentially be hundreds of thousands of files created. 

=item -d, --database

The database to search against in FASTA format.

=back

=head1 OPTIONS

=over 2

=item -t, --threads

The number of BLAST threads to spawn (Default: 1).

=item -a, --cpu

The number of processors to use for each BLAST thread (Default: 1).

=item -l, --length

Length (integer) to be used as the lower threshold for filtering (Default: 50).

=item -h, --help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=cut  

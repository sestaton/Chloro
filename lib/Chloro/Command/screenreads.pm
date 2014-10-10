package Chloro::Command::screenreads;
# ABSTRACT: Extract chloroplast regions from a read set.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use IPC::System::Simple qw(system);
use LWP::UserAgent;
use File::Basename;

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
    else {
	$self->usage_error("Too few arguments.") 
	    unless $opt->{infile} && $opt->{outfile} && $opt->{database} && $opt->{seqnum};
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man};
    my $result = _run_screening($opt);
}

sub _run_screening {
    my ($opt) = @_;
    my $t0       = gettimeofday();
    my $infile   = $opt->{infile};
    my $outfile  = $opt->{outfile};
    my $database = $opt->{database};
    my $length   = $opt->{length};
    my $thread   = $opt->{thread};
    my $cpu      = $opt->{cpu};
    my $seqnum   = $opt->{seqnum};

    my %blasts;
    $cpu //= 1;  
    $thread //= 1;
    
    my ($dbfile, $dbdir, $dbext)  = fileparse($database, qr/\.[^.]*/);
    my ($db_path)           = _make_blastdb($database, $dbfile, $dbdir);
    my ($seq_files, $seqct) = _split_reads($infile, $outfile, $seqnum);

    open my $out, '>>', $outfile or die "\nERROR: Could not open file: $outfile\n"; 

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

    say "\n========> Finihsed running BLAST on $seqct sequences in $final_time minutes";
}

sub _run_blast {
    my ($subseq_file, $dbfile, $db_path, $cpu) = @_;

    my ($subfile, $subdir, $subext) = fileparse($subseq_file, qr/\.[^.]*/);

    my $suffix = ".bln";
    my $subseq_out = $subfile."_".$dbfile.$suffix;

    my (@blast_cmd, $exit_value);
    @blast_cmd = "blastall ". 
                 "-p blastn ".
		 "-e 1e-5 ". 
		 "-F F ".
		 "-i $subseq_file ".
		 "-d $db_path ".
		 "-o $subseq_out ".
		 "-a $cpu ".
		 "-m 8";

    try {
	$exit_value = system([0..5], @blast_cmd);
    }
    catch {
	"\nERROR: BLAST exited with exit value $exit_value. Here is the exception: $_\n";
    };

    return $subseq_out;
}

sub _make_blastdb {
    my ($database, $dbfile, $dbdir) = @_;

    $dbfile =~ s/\.f.*//;
    my $db      = $dbfile."_chloro_blastdb";
    my $db_path = File::Spec->catfile($dbdir, $db);
    unlink $db_path if -e $db_path;

    my $exit_value;
    try {
	$exit_value = system([0..5], "formatdb -p F -i $database -t $db -n $db_path 2>&1 > /dev/null");
    }
    catch {
	"\nERROR: formatdb exited with exit value $exit_value. Here is the exception: $_\n";
    };
    
    return $db_path;
}

sub _split_reads {
    my ($infile, $outfile, $seqnum) = @_;

    my ($iname, $ipath, $isuffix) = fileparse($infile, qr/\.[^.]*/);
    
    my $out;
    my $count = 0;
    my $fcount = 1;
    my @split_files;
    $iname =~ s/\.fa.*//;     # clean up file name like seqs.fasta.1
    
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


1;
__END__

=pod

=head1 NAME 
                                                                       
chloro screenreads - Run multiple BLAST threads concurrently

=head1 SYNOPSIS    
 
chloro screenreads -i seqs.fas -o seqs_nt.bln -t 2 -n 100000 -cpu 2

=head1 DESCRIPTION
     
This script can accelerate BLAST searches by splitting an input file and 
running BLAST on multiple subsets of sequences concurrently. The size of 
the splits to make and the number of threads to create are optional. The 
input set of sequences may be in fasta or fastq format.                                                                

=head1 DEPENDENCIES

Parallel::ForkManager is a non-core Perl library that must
be installed in order for this script to work. 

Tested with:

=over

=item *
L<Parallel::ForkManger> 0.7.9 and Perl 5.8.5 (Red Hat Enterprise Linux AS release 4 (Nahant Update 9))

=item *
L<Parallel::ForkManager> 0.7.9 and Perl 5.14.2 (Red Hat Enterprise Linux Server release 5.8 (Tikanga))

=back

=head1 AUTHOR 

S. Evan Staton                                                

=head1 CONTACT
 
statonse at gmail dot com

=head1 REQUIRED ARGUMENTS

=over 2

=item -i, --infile

The file of sequences to BLAST. The format may be Fasta or Fastq,
and may be compressed with either gzip or bzip2.

=item -o, --outfile

A file to place the BLAST results.

=item -n, --numseqs

The size of the splits to create. This number determines how many 
sequences will be written to each split. 

NB: If the input sequence file has millions of sequences and a 
very small number is given fo the split value then there could 
potentially be hundreds of thousands of files created. 

=item -d, --database

The BLAST database to search. 

=back

=head1 OPTIONS

=over 2

=item -t, --threads

The number of BLAST threads to spawn. Default is 1.

=item -a, --cpu

The number of processors to use for each BLAST thread. Default is 1.

=item -b, --num_aligns

The number of alignments to keep for each query. Default is 250.

=item -v, --num_desc

The number of descriptions to keep for each hit. Default is 500.

=item -p, --blast_prog

The BLAST program to execute. Default is blastp.

=item -bf, --blast_format

The BLAST output format. Default is 8.
NB: The only allowed options are '8' which is "blasttable" (tabular BLAST output),
'7' with is "blastxml" (BLAST XML output), and '0' which is the defaout pairwise output.

=item -e, --evalue

The e-value threshold for hits to each query. Default is 1e-5.

=item -w, --warn

Print the BLAST warnings. Defaust is no;

=item -h, --help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=cut  

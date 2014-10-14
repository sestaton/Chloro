package Chloro::Command::assemble;
# ABSTRACT: Run many chloroplast genome assemblies and pick the best one.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use IPC::System::Simple qw(system);
use Capture::Tiny qw(:all);
use File::Basename;
use File::Spec;
use Cwd qw(abs_path);
use Try::Tiny;

sub opt_spec {
    return (    
	[ "pairfile|p=s",   "A file of paired, interleaved chlorplast sequences to be assembled" ],
	[ "singletons|s=s", "The file of unpaired, singleton sequences" ], 
	[ "threads|t=i",    "The number of threads (hash steps) to execute simultaneously (Default: 1)" ],
	[ "hashs|i=i",      "The starting hash size (Default: 59)" ],
	[ "hashe|j=i",      "The maximum hash size (Default: 89)" ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    else {
	$self->usage_error("Too few arguments.") unless $opt->{pairfile};
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man};

    my $result = _run_assembly($opt);
}

sub _run_assembly {
    my ($opt) = @_;
    my $pairfile   = abs_path($opt->{pairfile});
    my $singletons = abs_path($opt->{singletons}); 
    my $hashs      = $opt->{hashs};
    my $hashe      = $opt->{hashe};
    my $thread     = $opt->{threads};

    my $file = __FILE__;
    my $cmd_dir = basename(dirname(abs_path($file)));
    my $hmm_dir = basename(dirname($cmd_dir));
    my $chl_dir = basename(dirname($hmm_dir));
    my $vel_dir = File::Spec->catdir($chl_dir, 'src', 'velvet');
    my $vo      = File::Spec->catfile(abs_path($chl_dir), 'src', 'VelvetOptimiser', 'VelvetOptimiser.pl');
    local $ENV{PATH} = "$ENV{PATH}:$vel_dir";

    my $exit_value;
    $hashs  //= 59;
    $hashe  //= 89;
    $thread //= 1;
    my ($ifile, $idir, $iext) = fileparse($pairfile, qr/\.[^.]*/);
    my $dirname = "VelvetOpt_k$hashs-k$hashe";

    my @vo_cmd = "perl $vo ".
	         "-s $hashs ".
		 "-e $hashe ".
		 "-t $thread ".
		 "-p $dirname ".
		 "-d $dirname ".
		 "-f '-fasta -shortPaired $pairfile -fasta -short $singletons'";

    my ($stdout, $stderr, @res) = capture { system([0..5], @vo_cmd); };

    say "\nERROR: VelvetOptimiser seems to have exited. Here is the message: $stderr" if $stderr;
    #try {
    #    $exit_value = capture([0..5], @vo_cmd);
    #}
    #catch {
    #    die "\nERROR: VelvetOptimiser exited with exit value $exit_value. Here is the exception: $_\n";
    #};

    return $exit_value;
}


1;
__END__

=pod

=head1 NAME
                                                                       
 chloro assemble

=head1 SYNOPSIS    

 chloro assemble

=head1 DESCRIPTION
                                                                   

=head1 AUTHOR 

S. Evan Staton, C<< <statonse at gmail.com> >>

=head1 REQUIRED ARGUMENTS

=over 2

=item -o, --outfile



=back

=head1 OPTIONS

=over 2

=item help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=back

=cut

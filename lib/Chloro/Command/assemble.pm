package Chloro::Command::assemble;
# ABSTRACT: Run many chloroplast genome assemblies and pick the best one.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use IPC::System::Simple qw(system);
use File::Basename;
use Try::Tiny;

sub opt_spec {
    return (    
	[ "infile|i=s", "A file of screened chlorplast sequences to be assembled" ],
	[ "threads|t=i", "The number of threads (hash steps) to execute simultaneously (Default: 1)" ],
	[ "hashs|s=i",  "The starting hash size (Default: 59)" ],
	[ "hashe|e=i",  "The maximum hash size (Default: 89)" ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    else {
	$self->usage_error("Too few arguments.") unless $opt->{infile};
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man};

    my $result = _run_assembly($opt);
}

sub _run_assembly {
    my ($opt) = @_;
    my $infile = $opt->{infile};
    my $hashs  = $opt->{hashs};
    my $hashe  = $opt->{hashe};
    my $thread = $opt->{threads};

    my $exit_value;
    $hashs  //= 59;
    $hashe  //= 89;
    $thread //= 1;
    my ($file, $dir, $ext) = fileparse($infile, qr/\.[^.]*/);
    my $dirname = "VelvetOpt_k$hashs-k$hashe";

    my @vo_cmd = "src/VelvetOptimiser/VelvetOptimiser.pl ".
	         "-s $hashs ".
		 "-e $hashe ".
		 "-t $thread ".
		 "-p $dirname ".
		 "-d $dirname ".
		 "-f '-fasta -shortPaired $infile'";

    try {
        $exit_value = system([0..5], @vo_cmd);
    }
    catch {
        die "\nERROR: VelvetOptimiser exited with exit value $exit_value. Here is the exception: $_\n";
    };
 
		 
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

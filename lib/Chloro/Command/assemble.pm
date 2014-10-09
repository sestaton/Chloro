package Chloro::Command::assemble;
# ABSTRACT: Run many chloroplast genome assemblies and pick the best one.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use IPC::System::Simple qw(system);
use LWP::UserAgent;
use File::Basename;

sub opt_spec {
    return (    
	[ "outfile|o=s",  "A file to place the Pfam2GO mappings" ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    else {
	$self->usage_error("Too few arguments.") unless $opt->{outfile};
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man};
    my $outfile = $opt->{outfile};

    my $result  = _fetch_mappings($outfile);
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

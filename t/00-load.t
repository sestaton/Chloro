#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use File::Spec;
use IPC::System::Simple qw(capture);
use Test::More tests => 3;

BEGIN {
    use_ok( 'Chloro' ) || print "Bail out!\n";
}

diag( "Testing Chloro $Chloro::VERSION, Perl $], $^X" );

my $cmd = File::Spec->catfile('bin', 'chloro');
ok(-x $cmd, 'Can execute chloro');

my @menu = capture([0..5], "$cmd help");

my $progs = 0;
for my $command (@menu) {
    next if $command =~ /^ *$|^Available/;
    $command =~ s/^\s+//;
    my ($prog, $desc) = split /\:/, $command;
    ++$progs if $prog;
}

is ($progs, 5, 'Correct number of subcommands listed');

done_testing();

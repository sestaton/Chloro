#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use IPC::System::Simple qw(capture);
use Test::More tests => 3;

BEGIN {
    use_ok( 'Chloro' ) || print "Bail out!\n";
}

diag( "Testing Chloro $Chloro::VERSION, Perl $], $^X" );

my $chloro = "bin/chloro";
ok(-x $chloro, 'Can execute chloro');

my @menu = capture([0..5], "bin/chloro help");

my $progs = 0;
for my $command (@menu) {
    next if $command =~ /^ *$|^Available/;
    $command =~ s/^\s+//;
    my ($prog, $desc) = split /\:/, $command;
    ++$progs if $prog;
}

is ($progs, 5, 'Correct number of subcommands listed');

done_testing();

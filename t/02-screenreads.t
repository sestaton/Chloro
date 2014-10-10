#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use IPC::System::Simple qw(capture);
use Test::More tests => 4;

my @menu = capture([0..5], "bin/chloro help screenreads");

my $opts     = 0;
my $tot      = 0;
my $scr      = 0;
my $seqnum   = 20;
my $infile   = "t/test_data/t_seqs_nt.fas";
my $outfile  = "t/test_data/t_seqs_nt_screened.fas";
my $database = "t/test_data/t_cpdna_db.fas";

for my $opt (@menu) {
    next if $opt =~ /^Err|^Usage|^chloro|^ *$/;
    $opt =~ s/^\s+//;
    next unless $opt =~ /^-/;
    my ($option, $desc) = split /\s+/, $opt;
    ++$opts if $option;
}

is( $opts, 7, 'Correct number of options for chloro screenreads' );

my @scr_results = capture([0..5], "bin/chloro screenreads -i $infile -o $outfile -d $database -n $seqnum");
ok( -e $outfile, 'Can screen reads against a chloroplast genome' );

for my $res (@scr_results) {
    if ($res =~ /(\d+) total sequences matched the target/) {
	$tot = $1;
    }
    if ($res =~ /(\d+) were above the length threshold/) {
	$scr = $1;
    }
}

is( $tot, 60, 'Expected number of reads matching index' );
is( $scr, 50, 'Expected number of matches above length threshold' );

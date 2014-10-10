#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use IPC::System::Simple qw(system capture);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use LWP::UserAgent;
use File::Copy qw(move);
use Test::More tests => 4;

my @menu = capture([0..5], "bin/chloro help screenreads");

my $opts      = 0;
my $full_test = 0;
my $infile    = "t/test_data/t_seqs_nt.fas";
#my $outfile   = "t_orfs_hmmscan-pfamA.out";
#my $domtblout = "t_orfs_hmmscan-pfamA.domtblout";
#my $tblout    = "t_orfs_hmmscan-pfamA.tblout";

for my $opt (@menu) {
    next if $opt =~ /^Err|^Usage|^chloro|^ *$/;
    $opt =~ s/^\s+//;
    next unless $opt =~ /^-/;
    my ($option, $desc) = split /\s+/, $opt;
    ++$opts if $option;
}

is($opts, 4, 'Correct number of options for chloro screenreads');

skip 'skip lengthy tests', 3 unless $full_test; 
my $db = _fetch_db();

my @result = capture([0..5], "bin/hmmer2go run -i $infile -d $db");
ok(-e $outfile,   'Expected raw output of HMMscan from hmmer2go search');
ok(-e $domtblout, 'Expected domain table output of HMMscan from hmmer2go search');
ok(-e $tblout,    'Expected hit table output of HMMscan from hmmer2go search');

unlink $outfile;
unlink $domtblout;
    

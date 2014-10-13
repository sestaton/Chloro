#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use File::Basename;
use File::Spec;
use IPC::System::Simple qw(capture);
use Test::More tests => 8;

my @menu = capture([0..5], "bin/chloro help screenreads");

my $opts     = 0;
my $tot      = 0;
my $scr      = 0;
my $seqnum   = 100000;
my $outfile  = "t/test_data/t_cpseqs_screened.fas";
my $infile = "t/test_data/t_reads.fq.bz2";
#my $database = "t/test_data/t_cpdna_db.fas";
my $database = "t/test_data/Helianthus_annuus_NC_007977.fasta";

for my $opt (@menu) {
    next if $opt =~ /^Err|^Usage|^chloro|^ *$/;
    $opt =~ s/^\s+//;
    next unless $opt =~ /^-/;
    my ($option, $desc) = split /\s+/, $opt;
    ++$opts if $option;
}

is( $opts, 7, 'Correct number of options for chloro screenreads' );

my @scr_results = capture([0..5], "bin/chloro screenreads -i $infile -o $outfile -d $database -n $seqnum -l 50");
ok( -e $outfile, 'Can screen reads against a chloroplast genome' );

for my $res (@scr_results) {
    if ($res =~ /(\d+) total sequences matched the target/) {
	$tot = $1;
    }
    if ($res =~ /(\d+) were above the length threshold/) {
	$scr = $1;
    }
}

is( $tot, 100000, 'Expected number of reads matching index' );
is( $scr, 8822, 'Expected number of matches above length threshold' );

my ($name, $path, $suffix) = fileparse($outfile, qr/\.[^.]*/);
my $ffile  = File::Spec->catfile($path, $name."_f".$suffix);
my $rfile  = File::Spec->catfile($path, $name."_r".$suffix);
my $fpfile = File::Spec->catfile($path, $name."_fp".$suffix);
my $rpfile = File::Spec->catfile($path, $name."_rp".$suffix);
my $fsfile = File::Spec->catfile($path, $name."_fs".$suffix);
my $rsfile = File::Spec->catfile($path, $name."_rs".$suffix);
my $ifile  = File::Spec->catfile($path, $name."_paired_interl".$suffix);
my $sfile  = File::Spec->catfile($path, $name."_unpaired".$suffix);

ok( -e $ifile,  'File of interleaved paired reads created' );
ok( -e $sfile,  'File of collated singleton reads created' );

my ($scount, $icount) = (0, 0);
open my $s, '<', $sfile;
while (<$s>) {
    ++$scount if /^>/;
}
close $s;

open my $i, '<', $ifile;
while (<$i>) {
    ++$icount if /^>/;
}
close $i;

is( $scount, 44, 'Correct number of unpaired reads written to singletons file' );
is( $icount, 8778, 'Correct number of paired reads written to pair file' );

unlink $outfile;
unlink $database;

done_testing();

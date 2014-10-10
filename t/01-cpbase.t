#!/usr/bin/env perl

use 5.010;
use strict;
use warnings FATAL => 'all';
use IPC::System::Simple qw(system capture);
use Test::More tests => 20;
use Data::Dump qw(dd);

my @menu = capture([0..5], "bin/chloro help cpbase");

my $opts   = 0;
my $expnum = 0;
my $sunfl_cp_genome = 'Helianthus_annuus_NC_007977.fasta';

for my $opt (@menu) {
    next if $opt =~ /^chloro|^ *$/;
    $opt =~ s/^\s+//;
    ++$opts if $opt =~ /^-/;
}

is( $opts, 10, 'Correct number of options for chloro cpbase' );

my @genomes = capture([0..5], "bin/chloro cpbase --available");

my ($genome_num) = map { /^(\d+) genomes/ } @genomes;
is( $genome_num, 342, 'Found the correct number of genomes in CpBase' );

my $dbname;
# TODO: improve these tests, make them more generic. 
# This is poorly designed because every db name 
# changes when it is returned by the web service (that part can't be fixed), 
# and the numbers are hard-coded, so they could easily break (that part needs to be fixed).
for my $db ('viridiplantae', 'non_viridiplantae', 'red lineage', 'rhodophyta', 'stramenopiles') {
    my @virid_genomes = capture([0..5], "bin/chloro cpbase -d '$db' --available");

    $dbname = $db if $db eq 'stramenopiles';
    $dbname = ucfirst($db) if $db =~ /^viridiplantae$/ || $db eq 'rhodophyta';
    $dbname = 'NOT_Viridiplantae' if $db eq 'non_viridiplantae';
    $dbname = 'Red_Lineage' if $db =~ /red lineage/;
    $expnum = 298 if $dbname =~ /^Viridiplantae$/;
    $expnum = 44  if $dbname eq 'NOT_Viridiplantae';
    $expnum = 38  if $dbname eq 'Red_Lineage';
    $expnum = 9   if $dbname eq 'Rhodophyta';
    $expnum = 15  if $dbname eq 'stramenopiles';
    my ($dbgenomes) = map { /^(\d+) $dbname/ } @virid_genomes;
    is( $dbgenomes, $expnum, "Found the correct number of genomes in $db database" );
}

my @sunfl_stats = capture([0..5], "bin/chloro cpbase -g helianthus -s annuus --statistics -d viridiplantae");
for my $sun_stat (@sunfl_stats) {
    next if $sun_stat =~ /^=/;
    my ($type, $stat) = split /\s+/, $sun_stat;
    if ($type eq 'intergenic_dist_ave') {
	is( $stat, 455, 'Correct intergenic distance returned' );
    }
    if ($type eq 'gc_content') {
	is( $stat, 37.6, 'Correct GC conent returned for sunflower' );
    }
    if ($type eq 'repeat_bases_total') {
	is( $stat, 42, 'Correct repeat bases' );
    }
    if ($type eq 'cds_len_ave') {
	is( $stat, 910, 'Correct CDS length' );
    }
    if ($type eq 'gc_skew') {
	is( $stat, -0.01, 'Correct GC skew' );
    }
    if ($type eq 'cds_bases_total') {
	is( $stat, 77358, 'Correct total CDS bases' );
    }
    if ($type eq 'seq_len_total') {
	is( $stat, 151104, 'Correct total genome length' );
    }
    if ($type eq 'rna_bases_total') {
	is( $stat, 11765, 'Correct total RNA bases' );
    }
}

my @sunfl_genome = capture([0..5], "bin/chloro cpbase -g helianthus -s annuus --assemblies -d viridiplantae");
ok( -e $sunfl_cp_genome, 'Can fetch genomes from CpBase' );
unlink $sunfl_cp_genome;

my @sunfl_lineage = capture([0..5], "bin/chloro cpbase -g helianthus -s annuus -l -d viridiplantae");

my ($order, $fam, $gen, $sp) = map { split /\t/ } @sunfl_lineage;
like( $order, qr/Asterales/, 'Correct order returned for sunflower' );
like( $fam,   qr/Asteraceae/, 'Correct family returned for sunflower' );
like( $gen,   qr/helianthus/, 'Correct genus returned for sunflower' );
like( $sp,    qr/annuus/,     'Correct species returned for sunflower' );

done_testing();

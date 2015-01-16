package Chloro::Command::cpbase_search;
# ABSTRACT: Download chloroplast genes or genomes from CpBase.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use IPC::System::Simple qw(system);
use Time::HiRes         qw(gettimeofday);
use HTTP::Tiny;
use WWW::Mechanize;
use HTML::TableExtract;
use XML::Twig;
use File::Basename;
use Pod::Usage;
no if $] >= 5.018, 'warnings', "experimental::smartmatch";

sub opt_spec {
    return (
	[ "available",       "Print the number of species available in CpBase and exit." ],
	[ "db|d=s",          "The database to search. Must be one of: viridiplantae, non_viridiplanate, 'red lineage', rhodophyta, or stramenopiles." ],
        [ "format|f=s",      "Format of the sequence file to fetch. Options are: genbank or fasta (Default: fasta)." ],
        [ "genus|g=s",       "The name of a genus query." ],
	[ "species|s=s",     "The name of a species to query." ],
        [ "statistics",      "Get assembly statistics for the specified species." ],
	[ "outfile|o=s",     "A file to log the results of each search" ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    elsif ($self->app->global_options->{help}) {
        $self->help;
    }
    elsif (!%$opt) {
	say "\nERROR: Required arguments not given.";
        $self->help and exit(0);
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man} ||
	$self->app->global_options->{help};

    my $result = _check_args($opt);
}

sub _check_args {
    my ($opt) = @_;
    
    my $outfile    = $opt->{outfile};
    my $db         = $opt->{db};
    my $format     = $opt->{format};
    my $genus      = $opt->{genus};
    my $species    = $opt->{species};
    my $statistics = $opt->{statistics};
    my $available  = $opt->{available};

    ## set defaults for search
    my $cpbase_response = "CpBase_database_response.html"; # HTML
    $format //= 'fasta';
    
    _get_lineage_for_taxon($available, $cpbase_response, $outfile) and exit(0) if $available && !$db;

    if ($statistics) {
	if (!$genus || !$species) {
	    say "\nERROR: The 'statistics' option only works when given a genus and species name and no other options.";
	    exit(1);
	}
    }

    if ((!$genus && $species) || ($genus && !$species)) {
	say "\nERROR: Can not query a species without a genus and species name. Exiting.";
	exit(1);
    }
    
    # make epithet
    my $epithet;
    $epithet = $genus."_".$species if $genus && $species;
    my %stats;
    
    # counters
    my $t0 = gettimeofday();
    my $records = 0;
    my $genomes;

    # set the CpBase database to search and type
    given ($db) {
	when (/algae/i) {             $db = "Algae"; }
	when (/red lineage/i) {       $db = "Red_Lineage"; }
	when (/rhodophyta/i) {        $db = "Rhodophyta"; }
	when (/stramenopiles/i) {     $db = "stramenopiles"; }
	when (/non_viridiplantae/i) { $db = "NOT_Viridiplantae"; }
	when (/viridiplantae/i) {     $db = "Viridiplantae"; }
	default {                     die "Invalid name for option db."; }
    }
    
    my $urlbase  = "http://chloroplast.ocean.washington.edu/tools/cpbase/run&genome_taxonomy=$db";
    my $response = HTTP::Tiny->new->get($urlbase);

    # check for a response 
    unless ($response->{success}) { 
	die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason}; 
    }             

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;
    
    my $id_map = _get_species_id($urlbase);
    my $fh     = _get_fh($outfile);

    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
    $te->parse_file($cpbase_response);

    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @elem = grep { defined } @$row;
	    if ($elem[0] =~ /(\d+) Genomes/i) {
		$genomes = $1;
		unlink $cpbase_response;
		say $fh "$genomes $db genomes available in CpBase." and exit if $available && $db;
	    }
	    else {
		my ($organism, $locus, $sequence_length, $assembled, $annotated, $added) = @elem;
		$organism =~ s/\s+/_/g;
		
		if (exists $id_map->{$organism}) {
		    if ($genus && $species && $organism =~ /\Q$epithet\E/i) {
			my $id = $id_map->{$organism};
			my $assem_stats = _get_cp_data($id);
			$stats{$organism} = $assem_stats;
			my $file = $organism."_".$locus;
			my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/$locus/files/$file";
			
			if ($format eq 'genbank') {
			    $file = $file.".gb";
			    $endpoint = $endpoint.".gb";
			}
			elsif ($format eq 'fasta') {
			    $file = $file.".fasta";
			    $endpoint = $endpoint.".fasta";
			}
			_fetch_file($file, $endpoint);
		    }
		    elsif ($genus && $organism =~ /\Q$genus\E/i) {
			my $id = $id_map->{$organism};
			my $assem_stats = _get_cp_data($id);
			$stats{$organism} = $assem_stats;
		    }
		}
	    }
	}
    }
    
    if ($statistics) {
	for my $genome (keys %stats) {
	    say $fh "====> Showing chloroplast genome statistics for: $genome";
	    for my $stat (keys %{$stats{$genome}}) {
		say $fh join "\t", $stat, $stats{$genome}{$stat};
	    }
	}
    }
    close $fh;
    unlink $cpbase_response;
}

sub _get_species_id {
    my ($urlbase) = @_;

    my %id_map;

    my $mech = WWW::Mechanize->new();
    $mech->get( $urlbase );
    my @links = $mech->links();
    for my $link ( @links ) {
	next unless defined $link->text;
	my ($g, $sp) = split /\s+/, $link->text;
	next unless defined $g && defined $sp;
	my $ep = $g."_".$sp;
	if ($link->url =~ /id=(\d+)/) {
	    $id_map{$ep} = $1;
	}
    }
    return \%id_map;
}

sub _get_cp_data {
    my ($id) = @_;
    
    my %assem_stats;
    my $cpbase_response = "CpBase_database_response_$id".".html";
    my $urlbase  = "http://chloroplast.ocean.washington.edu/tools/cpbase/run?genome_id=$id&view=genome";
    my $response = HTTP::Tiny->new->get($urlbase);

    unless ($response->{success}) {
        die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;

    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
    $te->parse_file($cpbase_response);
    
    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @elem = grep { defined } @$row;
	    if ($elem[0] =~ /GC Content/) {
		$elem[1] =~ s/%$//;
		$assem_stats{gc_content} = $elem[1];
	    }
	    elsif ($elem[0] =~ /GC Skew/) {
		$assem_stats{gc_skew} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Total Sequence Length/) {
		$elem[1] =~ s/\s.*//;
		$assem_stats{seq_len_total} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Total CDS Bases/) {
		$elem[1] =~ s/\s.*//;
		$assem_stats{cds_bases_total} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Average CDS Length/) {
		$elem[1] =~ s/\s.*//;
		$assem_stats{cds_len_ave} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Total RNA Bases/) {
		$elem[1] =~ s/\s.*//;
		$assem_stats{rna_bases_total} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Total RNA Bases/) {
		$elem[1] =~ s/\s.*//;
		$assem_stats{rna_bases_total} = $elem[1];
	    }
	    elsif ($elem[0] =~ /Average Repeat Length/) {
                $elem[1] =~ s/\s.*//;
                $assem_stats{repeat_bases_total} = $elem[1];
            }
	    elsif ($elem[0] =~ /Average Intergenic Distance/) {
                $elem[1] =~ s/\s.*//;
                $assem_stats{intergenic_dist_ave} = $elem[1];
            }
	}
    }
    unlink $cpbase_response;
    return \%assem_stats;
}

sub _get_lineage_for_taxon {
    my ($available, $cpbase_response, $outfile) = @_;

    my $fh = _get_fh($outfile);

    my %taxa;
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run";
    my $response = HTTP::Tiny->new->get($urlbase);

    unless ($response->{success}) {
        die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;

    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
    $te->parse_file($cpbase_response);

    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @elem = grep { defined } @$row;
	    if ($elem[0] =~ /(\d+) Genomes/i) {
		my $genomes = $1;
		unlink $cpbase_response;
		say $fh "$genomes genomes available in CpBase.";
	    }
	}
    }
    close $fh;

    exit;
}

sub _fetch_taxonid {
    my ($genus, $species) = @_;

    my $esearch  = "esearch_$genus"."_"."$species.xml";
    my $urlbase  = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=$genus%20$species";
    my $response = HTTP::Tiny->new->get($urlbase);

    unless ($response->{success}) {
        die "Can't get url $urlbase -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
    }

    open my $out, '>', $esearch or die "\nERROR: Could not open file: $!\n";
    say $out $response->{content};
    close $out;

    my $parser = XML::Twig->new;
    $parser->parsefile($esearch);

    my @nodes = $parser->findnodes( '/eSearchResult/IdList/Id' );
    my $id = pop(@nodes)->text();
    
    unlink $esearch;
    
    return $id;
}

sub _fetch_file {
    my ($file, $endpoint) = @_;

    unless (-e $file) {
	my $response = HTTP::Tiny->new->get($endpoint);

	# check for a response
	unless ($response->{success}) {
	    die "Can't get url $endpoint -- Status: ", $response->{status}, " -- Reason: ", $response->{reason};
	}

	# open and parse the results
	open my $out, '>', $file or die "\nERROR: Could not open file: $!\n";
	say $out $response->{content};
	close $out;
    }
}

sub _get_fh {
    my ($outfile) = @_;

    my $fh;
    if ($outfile) {
	open $fh, '>', $outfile or die "\nERROR: Could not open file: $outfile\n";;
    } 
    else {
	$fh = \*STDOUT;
    }

    return $fh;
}

sub help {
    print STDERR<<END

USAGE: chloro cpbase_search [-h] [-m]
    -m --man       :   Get the manual entry for a command.
    -h --help      :   Print the command usage.

Options:
    --available    :   Print the number of species available in CpBase and exit.
    -d|db          :   The database to search. 
                       Must be one of: viridiplantae, non_viridiplanate, 'red lineage', rhodophyta, or stramenopiles.
    -f|format      :   Format of the sequence file to fetch. Options are: Genbank or Fasta (Default: Fasta).
    -g|genus,      :   The name of a genus query.
    -s|species     :   The name of a species to query.
    --statistics   :   Get assembly statistics for the specified species.
    -o|outfile     :   A file to log the results of each search.

END
}

1;
__END__

=pod

=head1 NAME
                                                                       
 chloro cpbase_search - Download chloroplast genes or genomes from CpBase

=head1 SYNOPSIS    

 chloro cpbase_search -g helianthus -s annuus -d viridiplantae --assemblies

=head1 DESCRIPTION
                                                                   
Fetch chloroplast genomes, genomic statistics about genes, or specific gene sequences from
CpBase (http://chloroplast.ocean.washington.edu/).

=head1 AUTHOR 

S. Evan Staton, C<< <statonse at gmail.com> >>

=head1 OPTIONS

=over 2

=item --available

Print the number of species available in CpBase and exit.

=item -d, --db

The database to search. Must be one of: viridiplantae, non_viridiplanate, 'red lineage', rhodophyta, or stramenopiles.

=item -f, --format

Format of the sequence file to fetch. Options are: Genbank or Fasta (Default: Fasta).

=item -g, --genus

The name of a genus query.

=item -s, --species

The name of a species to query.

=item --statistics

Get assembly statistics for the specified species.

=item -o, --outfile

A file to log the results of each search

=item -h, --help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=back

=cut

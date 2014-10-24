package Chloro::Command::cpbase_search;
# ABSTRACT: Download chloroplast genes or genomes from CpBase.

use 5.010;
use strict;
use warnings;
use Chloro -command;
use Time::HiRes qw(gettimeofday);
use LWP::UserAgent;
use WWW::Mechanize;
use HTML::TableExtract;
use XML::LibXML;
use File::Basename;
use Try::Tiny;
use Pod::Usage;
no if $] >= 5.018, 'warnings', "experimental::smartmatch";

sub opt_spec {
    return (
	[ "all",             "Download files of the specified type for all species in the database." ],
	[ "available",       "Print the number of species available in CpBase and exit." ],
	[ "db|d=s",          "The database to search. Must be one of: viridiplantae, non_viridiplanate, 'red lineage', rhodophyta, or stramenopiles." ],
        [ "format|f=s",      "Format of the sequence file to fetch. Options are: genbank or fasta (Default: fasta)." ],
        [ "genus|g=s",       "The name of a genus query." ],
	[ "species|s=s",     "The name of a species to query." ],
        [ "statistics",      "Get assembly statistics for the specified species." ],
	[ "assemblies",      "Specifies that the chlorplast genome assemblies should be fetched." ],
        [ "lineage|l",       "Return the order, family, genus and species (tab separated) of all entries." ],
	[ "outfile|o=s",     "A file to log the results of each search" ],
	[ "rna_clusters|r",  "Download RNA clusters for the specified genes." ],
	[ "gene_clusters|c", "Fetch gene cluster information." ],
	[ "gene_name|n",     "The name of a specific gene to fetch ortholog cluster stats or alignments for." ],
	[ "alignments",      "Download ortholog alignments for a gene, or all genes." ],
	[ "sequences",       "Download RNA cluster ortholog sequences for each gene (if --all) or specific genes (if --gene_name)." ],
    );
}

sub validate_args {
    my ($self, $opt, $args) = @_;

    my $command = __FILE__;
    if ($self->app->global_options->{man}) {
	system([0..5], "perldoc $command");
    }
    else {
	$self->usage_error("Too few arguments.") if !%$opt;
    }
} 

sub execute {
    my ($self, $opt, $args) = @_;

    exit(0) if $self->app->global_options->{man};
    my $result = _check_args($opt);
}

sub _check_args {
    my ($opt) = @_;
    
    my $outfile       = $opt->{outfile};
    my $db            = $opt->{db};
    my $all           = $opt->{all};
    my $format        = $opt->{format};
    my $genus         = $opt->{genus};
    my $species       = $opt->{species};
    my $statistics    = $opt->{statistics};
    my $available     = $opt->{available};
    my $assemblies    = $opt->{assemblies};
    my $lineage       = $opt->{lineage};
    my $gene_clusters = $opt->{gene_clusters};
    my $rna_clusters  = $opt->{rna_clusters};
    my $gene_name     = $opt->{gene_name};
    my $alignments    = $opt->{alignments};
    my $sequences     = $opt->{sequences};

    ## set defaults for search
    my $cpbase_response = "CpBase_database_response.html"; # HTML
    $format      //= 'fasta';
    my $type     = 'fasta';
    my $alphabet = 'dna';
    
    _get_lineage_for_taxon($available, $cpbase_response) and exit(0) if $available && !$db;

    if ($lineage) {
	if ($db && $genus && $species) {
	    my $taxonid = _fetch_taxonid($genus, $species);
            if (defined $taxonid) {
                my ($lineage, $order, $family) = _get_lineage_from_taxonid($taxonid);
                say join "\t", $order, $family, $genus, $species if defined $order && defined $family;
            }
	}
	else {
	    say "\nERROR: 'genus' and 'species' and 'db' are required for getting the taxonomic lineage";
	}
    }

    if ($statistics) {
	if (!$genus || !$species) {
	    say "\nERROR: The 'statistics' option only works when given a genus and species name and no other options.";
	    exit(1);
	}
    }

    if ((!$db && $assemblies) || (!$db && $statistics)) {
	say "\nERROR: A database to query must be given for getting 'statistics' or 'assemblies'. ".
	    "Or, other arguments may be supplied. Exiting.";
	exit(1);
    }
    
    if ((!$genus && $species) || ($genus && !$species)) {
	say "\nERROR: Can not query a species without a genus and species name. Exiting.";
	exit(1);
    }
    
    if ($gene_clusters && $gene_name) {
	my $gene_stats = _fetch_ortholog_sets($all, $genus, $species, $gene_name, $alignments, $alphabet, $type);
	say join "\t", "Gene","Genome","Locus","Product";
	for my $gene (keys %$gene_stats) {
	    for my $genome (keys %{$gene_stats->{$gene}}) {
		for my $locus (keys %{$gene_stats->{$gene}{$genome}}) {
		    say join "\t", $gene, $genome, $locus, $gene_stats->{$gene}{$genome}{$locus};
		}
	    }
	}
	exit;
    }

    if ($rna_clusters && $gene_name) {
	_fetch_rna_clusters($all, $alignments, $type, $statistics, $sequences, $gene_name, $cpbase_response);
	exit;
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

    my $ua = LWP::UserAgent->new;
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run&genome_taxonomy=$db";
    my $response = $ua->get($urlbase);

    # check for a response
    unless ($response->is_success) {
	die "Can't get url $urlbase -- ", $response->status_line;
    }

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->content;
    close $out;

    my $id_map = _get_species_id($urlbase);

    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
    $te->parse_file($cpbase_response);

    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @elem = grep { defined } @$row;
	    if ($elem[0] =~ /(\d+) Genomes/i) {
		$genomes = $1;
		unlink $cpbase_response;
		say "$genomes $db genomes available in CpBase." and exit if $available;
	    }
	    else {
		say "\nERROR: Be advised, this command would attempt to download $genomes assemblies. ".
		    "It would be nicer to specify one species. Exiting now.\n" and exit if $assemblies && $all;
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
			_fetch_file($file, $endpoint) if $assemblies;
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
	    say "====> Showing chloroplast genome statistics for: $genome";
	    for my $stat (keys %{$stats{$genome}}) {
		say join "\t", $stat, $stats{$genome}{$stat};
	    }
	}
    }
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
    my $ua = LWP::UserAgent->new;
    my $cpbase_response = "CpBase_database_response_$id".".html";
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run?genome_id=$id&view=genome";
    my $response = $ua->get($urlbase);

    unless ($response->is_success) {
	die "Can't get url $urlbase -- ", $response->status_line;
    }

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->content;
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

sub _fetch_ortholog_sets {
    my ($all, $genus, $species, $gene_name, $alignments, $alphabet, $type) = @_;
    my %gene_stats;
    my $mech = WWW::Mechanize->new;
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run?view=u_feature_index"; 
    $mech->get($urlbase);
    my @links = $mech->links();

    for my $link ( @links ) {
        next unless defined $link && $link->url =~ /tools/;
	if ($link->url =~ /u_feature_id=(\d+)/) {
	    my $id = $1;
	    my $ua = LWP::UserAgent->new;
	    my $cpbase_response = "CpBase_database_response_gene_clusters_$id".".html";
	            
	    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run?u_feature_id=$id&view=universal_feature"; 
	    my $response = $ua->get($urlbase);
	            
	    unless ($response->is_success) {
		die "Can't get url $urlbase -- ", $response->status_line;
	    }
	            
	    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
	    say $out $response->content;
	    close $out;
	            
	    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
	    $te->parse_file($cpbase_response);
	            
	    for my $ts ($te->tables) {
		for my $row ($ts->rows) {
		    my @elem = grep { defined } @$row;
		    if (defined $elem[1] && $elem[1] eq $link->text) {
			next if $elem[0] =~ /Gene/i;
			my ($g, $sp) = split /\s+/, $elem[3] if defined $elem[3];

			if ($alignments && $all) {
			    $gene_stats{$elem[1]}{$elem[3]} = { $elem[0] => $elem[2]};
			    my ($file, $endpoint) = _make_alignment_url_from_gene($link->text, $alphabet, $type);
			    _fetch_file($file, $endpoint);
			    unlink $cpbase_response;
			}
			elsif ($alignments && 
			       defined $genus && 
			       $genus =~ /$g/ && 
			       defined $species && 
			       $species =~ /$sp/) {
			    $gene_stats{$elem[1]}{$elem[3]} = { $elem[0] => $elem[2]};
			    my ($file, $endpoint) = _make_alignment_url_from_gene($link->text, $alphabet, $type);
			    _fetch_file($file, $endpoint);
			    unlink $cpbase_response;
			}
			elsif ($alignments && 
			       defined $genus && 
			       $genus =~ /$g/ && 
			       defined $species && 
			       $species =~ /$sp/ && 
			       defined $gene_name && 
			       $gene_name =~ /$elem[0]/) {
			    $gene_stats{$elem[1]}{$elem[3]} = { $elem[0] => $elem[2]};
			    my ($file, $endpoint) = _make_alignment_url_from_gene($link->text, $alphabet, $type);
			    _fetch_file($file, $endpoint);
			    unlink $cpbase_response;
			}
			elsif ($alignments &&
			       !defined $genus && 
			       !defined $species && 
			       defined $gene_name && 
			       $gene_name =~ /$elem[1]/) {
			    $gene_stats{$elem[1]}{$elem[3]} = { $elem[0] => $elem[2]};
			    my ($file, $endpoint) = _make_alignment_url_from_gene($link->text, $alphabet, $type);
			    _fetch_file($file, $endpoint);
			    unlink $cpbase_response;
			}
			else { 
			    say join "\t", $genus, $g, $species, $sp; 
			}
		    }
		}
	    }
	    unlink $cpbase_response if -e $cpbase_response;
	}
    }
    return \%gene_stats;
}

sub _make_alignment_url_from_gene {
    my ($gene, $alphabet, $type) = @_;

    my $file = $gene."_orthologs";
    my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/tmp/$gene";
    if ($alphabet =~ /dna/i && $type =~ /fasta/i) {
	$endpoint .= "_orthologs.nt.aln.fa";
	$file .= ".nt.aln.fa";
    }
    elsif ($alphabet =~ /protein/i && $type =~ /fasta/i) {
	$endpoint .= "_orthologs.aa.aln.fa";
	$file .= ".aa.aln.fa";
    }
    elsif ($alphabet =~ /dna/i && $type =~ /clustal/i) {
	$endpoint .= "_orthologs.nt.aln.clw";
	$file .= ".nt.aln.clw";
    }
    elsif ($alphabet =~ /protein/i && $type =~ /clustal/i) {
	$endpoint .= "_orthologs.aa.aln.clw";
	$file .= ".aa.aln.clw";
    }
    else {
	die "\nERROR: Could not determine parameter options for fetching ortholog clusters. alpha: $alphabet type: $type";
    }
    
    return ($file, $endpoint)
}

sub _fetch_rna_clusters {
    my ($all, $alignments, $type, $statistics, $sequences, $gene_name, $cpbase_response) = @_;
    my $rna_cluster_stats;
    my %rna_cluster_links;
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run?view=rna_cluster_index";
    my $mech = WWW::Mechanize->new();
    $mech->get( $urlbase );
    my @links = $mech->links();
    my $gene;
    for my $link (@links) {
        next unless defined $link->text;
	if ($link->url =~ /u_feature_id=(\d+)/) {
	    my $id = $1;
	    $gene = $link->text;
	    my $url = "http://chloroplast.ocean.washington/tools/cpbase/run?u_feature_id=$id&view=universal_feature";
	    $rna_cluster_links{$gene} = $url;
	}
    }
    
    if ($statistics && $all) {
	for my $gene (keys %rna_cluster_links) {
	    my $ua = LWP::UserAgent->new;
	    my $response = $ua->get($rna_cluster_links{$gene});
	            
	    unless ($response->is_success) {
		die "Can't get url $urlbase -- ", $response->status_line;
	    }
	            
	    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
	    say $out $response->content;
	    close $out;
	            
	    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
	    $te->parse_file($cpbase_response);
	            
	    for my $ts ($te->tables) {
		for my $row ($ts->rows) {
		    my @elem = grep { defined } @$row;
		    say join q{, }, @elem;
		}
	    }
	}
    }
    elsif ($statistics && $gene_name) { 
	for my $gene (keys %rna_cluster_links) {
	    my $ua = LWP::UserAgent->new;
	    my $response = $ua->get($rna_cluster_links{$gene});
	            
	    unless ($response->is_success) {
		die "Can't get url $urlbase -- ", $response->status_line;
	    }
	            
	    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
	    say $out $response->content;
	    close $out;

	    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
	    $te->parse_file($cpbase_response);
	            
	    for my $ts ($te->tables) {
		for my $row ($ts->rows) {
		    my @elem = grep { defined } @$row;
		    say join q{, }, @elem;
		}
	    }
	}
    }
    elsif ($sequences && $all) {
	my $file = $gene."_orthologs.nt.fasta";
	my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/tmp/$file";
	_fetch_file($file, $endpoint);
    }
    elsif ($sequences && $gene_name) {
	if ($gene_name eq $gene) {
	    my $file = $gene."_orthologs.nt.fasta";
	    my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/tmp/$file";
	    _fetch_file($file, $endpoint);
	}
    }
    elsif ($alignments && $all) {
	my $file = $gene."_orthologs.nt.aln.";
	my $suf; ##TODO
	$suf = "clw" if $type =~ /cl/i;
	$suf = "fa" if $type =~ /fa/i;
	$file .= $suf;
	my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/tmp/$file";
	_fetch_file($file, $endpoint);
    }
    elsif ($alignments && $gene_name) {
	if ($gene_name eq $gene) {
	    my $suf; ##TODO
	    my $file = $gene."_orthologs.nt.aln.";
	    $suf = "clw" if $type =~ /cl/i;
	    $suf = "fa" if $type =~ /fa/i;
	    $file .= $suf;
	    my $endpoint = "http://chloroplast.ocean.washington.edu/CpBase_data/tmp/$file";
	    _fetch_file($file, $endpoint);
	}
    }
    unlink $cpbase_response;
    ## reorder control flow to if gene_name
    ##                             if sequences
    ##                             elsif alignments
    #return \%rna_cluster_stats;
}

sub _get_lineage_for_taxon {
    my ($available, $cpbase_response,) = @_;

    my %taxa;
    my $ua = LWP::UserAgent->new;
    my $urlbase = "http://chloroplast.ocean.washington.edu/tools/cpbase/run";
    my $response = $ua->get($urlbase);

    unless ($response->is_success) {
	die "Can't get url $urlbase -- ", $response->status_line;
    }

    open my $out, '>', $cpbase_response or die "\nERROR: Could not open file: $!\n";
    say $out $response->content;
    close $out;

    my $te = HTML::TableExtract->new( attribs => { border => 1 } );
    $te->parse_file($cpbase_response);

    for my $ts ($te->tables) {
	for my $row ($ts->rows) {
	    my @elem = grep { defined } @$row;
	    if ($available) {
		if ($elem[0] =~ /(\d+) Genomes/i) {
		    my $genomes = $1;
		    unlink $cpbase_response;
		    say "$genomes genomes available in CpBase." and exit(0);
		}
	    }
	    my ($organism, $locus, $sequence, $length, $assembled, $annotated, $added) = @elem;
	    my ($genus, $species) = split /\s+/, $organism;
	    next unless defined $species && length($species) > 3;
	    next if $species eq 'hybrid';
	    my $taxonid = _fetch_taxonid($genus, $species);
	    if (defined $taxonid) {
		my ($lineage, $order, $family) = _get_lineage_from_taxonid($taxonid);
		say join "\t", $order, $family, $genus, $species if defined $order && defined $family;
	    } 
	}
    }

    exit;
}

sub _get_lineage_from_taxonid {
    my ($id) = @_;
    my $esumm = "esumm_$id.xml"; 
 
    my $ua = LWP::UserAgent->new;
    my $urlbase  = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=taxonomy&id=$id";
    my $response = $ua->get($urlbase);

    unless ($response->is_success) {
	die "Can't get url $urlbase -- ", $response->status_line;
    }

    open my $out, '>', $esumm or die "\nERROR: Could not open file: $!\n";
    say $out $response->content;
    close $out;

    my $parser = XML::LibXML->new;
    my $doc    = $parser->parse_file($esumm);
    my ($order, $family, $lineage);

    for my $node ( $doc->findnodes('//TaxaSet/Taxon') ) {
	($lineage) = $node->findvalue('Lineage/text()');
	if ($lineage =~ /viridiplantae/i) {
	    ($family) = map  { s/\;$//; $_; }
	                grep { /(\w+aceae)/ } 
	                map  { split /\s+/  } $lineage;
	    
	    ($order)  = map  { s/\;$//; $_; }
	                grep { /(\w+ales)/ }
	                map  { split /\s+/  } $lineage;
	}
	else {
	    ## need method to get order/family from non-viridiplantae
	    say $lineage;
	}
    }
    unlink $esumm;

    return ($lineage, $order, $family);
}

sub _fetch_taxonid {
    my ($genus, $species) = @_;

    my $esearch = "esearch_$genus"."_"."$species.xml";
    my $ua = LWP::UserAgent->new;
    my $urlbase  = "http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=taxonomy&term=$genus%20$species";
    my $response = $ua->get($urlbase);

    unless ($response->is_success) {
	die "Can't get url $urlbase -- ", $response->status_line;
    }

    open my $out, '>', $esearch or die "\nERROR: Could not open file: $!\n";
    say $out $response->content;
    close $out;

    my $id;
    my $parser = XML::LibXML->new;
    my $doc    = $parser->parse_file($esearch);
    
    for my $node ( $doc->findnodes('//eSearchResult/IdList') ) {
	($id) = $node->findvalue('Id/text()');
    }
    
    unlink $esearch;
    
    return $id;
}

sub _fetch_file {
    my ($file, $endpoint) = @_;

    my $ua = LWP::UserAgent->new;
    unless (-e $file) {
	my $response = $ua->get($endpoint);
	
	# check for a response
	unless ($response->is_success) {
	    die "Can't get url $endpoint -- ", $response->status_line;
	}

	# open and parse the results
	open my $out, '>', $file or die "\nERROR: Could not open file: $!\n";
	say $out $response->content;
	close $out;
    }
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

=item --all

Download files of the specified type for all species in the database (applies to the --gene_clusters
and --rna_clusters options).

=item --available

Print the number of species available in CpBase and exit.

=item -d, --db

The database to search. Must be one of: viridiplantae, non_viridiplanate, 'red lineage', rhodophyta, or stramenopiles.

=item -f, --format

Format of the sequence file to fetch. Options are: genbank or fasta (Default: fasta).

=item -g, --genus

The name of a genus query.

=item -s, --species

The name of a species to query.

=item -r, --rna_clusters

Download RNA clusters for the specified genes.

=item -c, --gene_clusters

Fetch gene cluster information.

=item -n, --gene_name

The name of a specific gene to fetch ortholog cluster stats or alignments for.

=item --alignments

Download ortholog alignments for a gene, or all genes.

=item --statistics

Get assembly statistics for the specified species.

=item --sequences

Download RNA cluster ortholog sequences for each gene (if --all) or specific genes (if --gene_name).

=item --assemblies

Specifies that the chlorplast genome assemblies should be fetched.

=item -l, --lineage

Return the order, family, genus and species (tab separated) of all entries.

=item -o, --outfile

A file to log the results of each search

=item help

Print a usage statement. 

=item -m, --man

Print the full documentation.

=back

=cut

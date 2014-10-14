use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

if (eval ($ExtUtils::MakeMaker::VERSION) <= 6.55) {
    print "\n[ERROR]: ExtUtils::MakeMaker >= 6.5503 is required to build the package correctly.\n";
    print "The installed version is $ExtUtils::MakeMaker::VERSION.\n";
    print "Install the latest ExtUtils::MakeMaker and try again. Exiting.\n";
    exit(1);
}

BEGIN {
    system("chmod +x bin/chloro");
}

WriteMakefile(
    NAME             => 'Chloro',
    AUTHOR           => q{S. Evan Staton <statonse@gmail.com>},
    VERSION_FROM     => 'bin/chloro',
    LICENSE          => 'MIT',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.010,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 6.5503,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
	'LWP::UserAgent'        => 6.05,       
        'IPC::System::Simple'   => 1.21,
	'App::Cmd'              => 0.323,
	'Parallel::ForkManager' => 1.05,
	'HTML::TableExtract'    => 2.11,
	'WWW::Mechanize'        => 0,
	'XML::LibXML'           => 0,
	'Try::Tiny'             => 0,
    },
    INST_SCRIPT => 'bin',
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    test  => { TESTS => 't/*.t' },
    clean => { FILES => ['bin/pairfq_lite.pl', 'src'] },
);


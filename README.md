Chloro
======

Automated chloroplast genome assembly

[![Build Status](https://travis-ci.org/sestaton/Chloro.svg?branch=master)](https://travis-ci.org/sestaton/Chloro)

**DESCRIPTION**

`Chloro` is a command-line tool that will aid in the process of chloroplast genome assembly and annotation. The input will be NGS data from a 454 or Illumina machine (see below for more information). The general approach is to screen reads against a database of closely related chloroplast genomes, then assemble only those read portions matching the reference sequences. Next, we use the reference to transfer annotations to the assembly (not yet implemented).

**SPECIAL NOTE**

This is a work in process, and has only been tested with Illumina data. Also, the documentation may be incomplete for some commands. Currently, only VelvetOptimiser is used for assembly, though more assembly methods will be added. Please report bugs or issues that you find. See below for more information on usage and reporting issues.

**DEPENDENCIES**

The main application is written in Perl, and you must have a Perl compiled with thread support. See the wiki page on [installing dependencies](https://github.com/sestaton/Chloro/wiki/Installing-dependencies) for testing and installing dependencies.

**INSTALLATION**

`Chloro` is designed to be used in place (i.e., without needing to install it). This way using the code does not require admin privileges. Below is a script that will set up the project in the current directory and build the dependencies. 

```bash
curl -L https://api.github.com/repos/sestaton/Chloro/tarball > chloro.tar.gz
tar xzf chloro.tar.gz
mv sestaton-Chloro* Chloro
cd Chloro
./install_deps.sh

cpanm --installdeps .
```

It is a good idea to test if the installation was successful, and this can be done with the following command:

```bash
perl Makefile.PL && make test
```

If one of these commands fails, it is best to run `make clean` and resolve the issue before proceeding. The main application (called `chloro`) is in the 'bin' directory, and the usage is described below. Note that the input read data may be placed anywhere, but it is suggested that the input data is placed in the 'data' directory so that all the results are kept together in a separate directory. 
 
------------------------------------------------------------------------------------------------------------------------------------

**USAGE**

For the sake of example, we will assume that we have read data from a sunflower species, so we would start with fetching a reference from a closely related species, in this case that is *Helianthus annuus*. Also, all execution is done in the `Chloro` directory with our read data in the 'data' directory.

**1. Create a database of chloroplast genome(s)**

    ./bin/chloro cpbase_search -g helianthus -s annuus --assemblies -d viridiplantae

**2. Screen the reads against the reference database**

    ./bin/chloro screen_reads -i data/s_1_reads.fq.gz -o data/s_1_reads_screened.fasta -d Helianthus_annuus_NC_007977.fasta -n 100000 -l 50 -t 12

In the above command, the file 'Helianthus_annuus_NC_007977.fasta' was created by step 1 and is the reference chloroplast genome for the species of interest. The file 's_1_reads.fq.gz' is just an example, this would be a file of WGS reads to screen. The input may be FASTA or FASTQ, and it may be compressed with gzip or bzip2. There is no assumption about the order of reads, but it is assumed that the input contains paired-end data consisting of both forward and reverse reads in the same file.

The `-n 100000` indicates that we want to process 100,000 reads in each thread, the `-l 50` means to only keep regions over 50bp that match the reference, and the `-t 12` indicates that we want to use 12 threads for the screening. This latter option will greatly accelerate the search, but you would not want to set the thread number higher than the number of CPUs you have available.

**3. Assemble the screened reads**

    ./bin/chloro assemble -p data/s_1_reads_screened_paired_interl.fasta -s data/s_1_screened_unpaired.fasta -i 59 -j 89

In this command, the argument to the `-p` flag is the interleaved, paired reads generated by the `chloro screenreads` command, and the argument to the `-s` flag is the file of singleton (unpaired) reads generated by `chloro screenreads`. The `-i` and `-j` indicate the starting and ending hash sizes, respectively, to use for assembly.

**DOCUMENTATION**

Each subcommand can be executed with no arguments to generate a help menu. Alternatively, you may specify the help message explicitly. For example,

    chloro help assemble

More information about each command is available by accessing the full documentation at the command line. For example,

    chloro assemble --man

Also, the Chloro wiki is a source of online documentation.

**ISSUES**

Report any issues at the Chloro issue tracker: https://github.com/sestaton/Chloro/issues

**ATTRIBUTION**

This project uses the readfq library written by Heng Li. The readfq code has been modified for error handling and to parse the comment line in the Casava header.

[Pairfq](https://github.com/sestaton/Pairfq) is used for pairing reads prior to assembly.

A modified version of [VelvetOptimiser](https://github.com/Victorian-Bioinformatics-Consortium/VelvetOptimiser) is used for assembly. This code may be obtained from here: https://github.com/sestaton/VelvetOptimiser

**LICENSE AND COPYRIGHT**

Copyright (C) 2014 S. Evan Staton

This program is distributed under the MIT (X11) License, which should be distributed with the package. If not, it can be found here: http://www.opensource.org/licenses/mit-license.php


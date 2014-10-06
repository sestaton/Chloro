Chloro
======

Assisted chloroplast genome assembly

**DESCRIPTION**

This is a set of tools that will aid in the process of chloroplast genome assembly and annotation. The input will be NGS data from a 454 or Illumina machine, though the exact format will only really be important in the assembly process. The general approach is to screen reads against a database of closely related chloroplast genomes, then assemble only those read portions matching the reference sequences. Next, we use the reference to transfer annotations to the assembly.

**INSTALLATION**

`Chloro` has no automated build or install process, so the way use this software is to fetch the code and use it in place. Below is a script that will set up the project in the current directory and fetch the dependencies. 

```bash
curl -L https://api.github.com/repos/sestaton/Chloro/tarball > chloro.tar.gz
tar xzf chloro.tar.gz
mv sestaton-Chloro* Chloro
cd Chloro
./install_deps.sh
```

Running this script creates four directories: *bin*, *data*, *src*, and *scripts*. The *src* directory contains the source code for some of the programs, and we can ignore this for now. The *scripts* directory contains the code we will actually be running (explained below). The *bin* directory contains compiled programs, and we don't need to run these directly. Finally, the *data* directory is where your raw sequence files should be placed.
 
------------------------------------------------------------------------------------------------------------------------------------

**ASSEMBLY STEPS**

1. Create a database of chloroplast genomes to screen reads against.

    perl cpbase_fetch -i ....

2. Screen the reads against the reference database.

    perl parallel_blast -i ...

3. Assemble the screened reads.

    perl VelvetOptimiser.pl -i 

##PUTTING IT ALL TOGETHER

The script below will run all of the analysis steps and generate a completed assembly.

```bash
#!/bin/bash

cd `pwd`

alias velveth='bin/velveth'
alias velvetg='bin/velvetg'

#perl ./script/cpbash_fetch.pl -i ...

pb=./scripts/parallel_blast.pl
fb=./scripts/filter_reads_blast.pl
db=../screeningdb/trithuria_screendb

for file in ./*trimmed.fastq
do
  qryFile=$(echo ${file%.*})
  blastFile=${qryFile}_screendb.bln
  scrFile=${qryFile}_screened.fasta

  perl $pb -i $file -n 1000000 -d $db -o $blastFile -p blastn -bf 8 -a 2 -t 12
  perl $fb -i $file -b $blastFile -o $scrFile
done
```



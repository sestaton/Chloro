Chloro
======

Assisted chloroplast genome assembly

**DESCRIPTION**

This is a set of tools that will aid in the process of chloroplast genome assembly and annotation. The input will be NGS data from a 454 or Illumina machine, though the exact format will only really be important in the assembly process. The general approach is to screen reads against a database of closely related chloroplast genomes, then assemble only those read portions matching the reference sequences. Next, we use the reference to transfer annotations to the assembly.

**INSTALLATION**

* Install Velvet

```bash
curl -L https://api.github.com/repos/dzerbino/velvet/tarball > velvet.tar.gz
tar xzf velvet.tar.gz && cd dzerbino*
make 
```

* Install VelvetOptimiser

````bash
curl -L https://api.github.com/repos/sestaton/VelvetOptimiser/tarball > VO.tar.gz
tar xzf VO.tar.gz 
```

* Install PAGIT

This is a bit involved because it requires MUMmer to be installed, so the process is covered in detail on the wiki.

------------------------------------------------------------------------------------------------------------------------------------

**ANALYSIS STEPS**

1. Create a database of chloroplast genomes to screen reads against.

    perl cpbase_fetch -i ....

2. Screen the reads against the reference database.

    perl parallel_blast -i ...

3. Assemble the screened reads.

    perl VelvetOptimiser.pl -i 

4. 

#!/bin/bash

if [ -d data ]; then
    mkdir -p src
elif [ ! -d data ]; then
    mkdir -p data src
fi

cd src

## Velvet
curl -L https://api.github.com/repos/dzerbino/velvet/tarball > velvet.tar.gz
tar xzf velvet.tar.gz
mv dzerbino-velvet* velvet && cd velvet
make MAXKMERLENGTH=99
cd ..

## VelvetOptimiser
curl -L https://api.github.com/repos/sestaton/VelvetOptimiser/tarball > VO.tar.gz
tar xzf VO.tar.gz
mv sestaton-VelvetOptimiser* VelvetOptimiser
cd ..

## Pairfq-lite
cd bin
curl -o pairfq_lite.pl https://raw.githubusercontent.com/sestaton/Pairfq/master/scripts/pairfq_lite.pl
chmod +x pairfq_lite.pl

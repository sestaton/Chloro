#!/bin/bash

mkdir src data bin
cd src

## Velvet
curl -L https://api.github.com/repos/dzerbino/velvet/tarball > velvet.tar.gz
tar xzf velvet.tar.gz
mv dzerbino-velvet* velvet && cd velvet
make
mv velvetg ../../bin
mv velveth ../../bin
cd ..

## VelvetOptimiser
curl -L https://api.github.com/repos/sestaton/VelvetOptimiser/tarball > VO.tar.gz
tar xzf VO.tar.gz
mv sestaton-VelvetOptimiser* VelvetOptimiser
cd ..

## Pairfq-lite
cd scripts
wget https://raw.githubusercontent.com/sestaton/Pairfq/master/scripts/pairfq_lite.pl


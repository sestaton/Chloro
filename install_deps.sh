#!/bin/bash

mkdir src
cd src

## Velvet
curl -L https://api.github.com/repos/dzerbino/velvet/tarball > velvet.tar.gz
tar xzf velvet.tar.gz
mv dzerbino-velvet* velvet && cd velvet
make
cd ..

## VelvetOptimiser
curl -L https://api.github.com/repos/sestaton/VelvetOptimiser/tarball > VO.tar.gz
tar xzf VO.tar.gz
mv sestaton-VelvetOptimiser* VelvetOptimiser
sed -i 's/`velveth/..\/velvet\/velveth/' VelvetOptimiser/VelvetOpt/hwrap.pm
sed -i 's/`velvetg/..\/velvet\/velvetg/' VelvetOptimiser/VelvetOpt/gwrap.pm
cd ..

## Pairfq-lite
cd scripts
wget https://raw.githubusercontent.com/sestaton/Pairfq/master/scripts/pairfq_lite.pl


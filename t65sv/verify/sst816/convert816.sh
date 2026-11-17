#!/bin/sh
# convert816.sh <SingleStepTests-65816 checkout> <outdir>
SRC=$1; OUT=$2; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p $OUT
ls $SRC/v1/*.json | xargs -P 2 -I{} sh -c 'f={}; b=$(basename $f .json); python3 -I '"$HERE"'/sst816bin.py $f '"$OUT"'/$b.bin'
echo CONVERT_DONE

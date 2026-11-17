#!/bin/sh
# convert_all.sh <SingleStepTests-65x02 checkout> <outdir>
SRC=$1; OUT=$2; HERE=$(cd "$(dirname "$0")" && pwd)
for set in 6502 nes6502 wdc65c02 rockwell65c02 synertek65c02; do
  mkdir -p "$OUT/$set"
  ls "$SRC/$set/v1/"*.json | xargs -P 4 -I{} sh -c 'f={}; b=$(basename $f .json); python3 -I '"$HERE"'/sst2bin.py $f '"$OUT/$set"'/$b.bin'
done
echo CONVERT_DONE

#!/bin/sh
# run_lorenz_flat.sh <Lorenz-2.15/src dir> <binary> <outfile>: every C64 program of the suite in the flat shim
L=$1; BIN=$2; OUT=$3
cd "$(dirname "$0")"
ls $L/*.prg | grep -v -- "-dtv\|-plus4\|nextdisk\|template\|cpuport128" | \
  xargs -P 4 -I{} sh -c "timeout 3600 $BIN {} --max 3000000000 || true" > $OUT.tmp 2>&1
sort -k2 $OUT.tmp > $OUT; rm -f $OUT.tmp
echo "PASS: $(grep -c '^PASS' $OUT)  FAIL: $(grep -c '^FAIL' $OUT)  OTHER: $(grep -vc '^PASS\|^FAIL' $OUT)"

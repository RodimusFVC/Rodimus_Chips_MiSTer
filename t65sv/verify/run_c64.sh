#!/bin/sh
# run_c64.sh <lockstep|solo> <listfile> <outfile> [maxcycles]
# Runs programs on the mini-C64 (CIA/VIC accurate), restoring a post-boot snapshot; "*new*" programs get the 8521 CIA.
# A list line is "<prg path> [max CPU cycles]"; the per-line value overrides [maxcycles] (default 400M).
kind=$1; LIST=$(readlink -f $2); OUT=$(readlink -f $3); MAX=${4:-400000000}
cd "$(dirname "$0")/c64"
first=$(head -1 $LIST | awk '{print $1}')
for cia in old new; do
  snap=../build/boot_${kind}_$cia.snap
  [ -f $snap ] || ../build/c64_$kind $first $( [ $cia = new ] && echo --cia-new ) --save-boot $snap > /dev/null
done
awk -v m=$MAX '{print $1, ($2 ? $2 : m)}' $LIST | \
  xargs -P 4 -L 1 sh -c 'p=$0; mx=$1; case $p in *new*) c="--cia-new"; s=new;; *) c=""; s=old;; esac; timeout 10800 ../build/c64_'$kind' $p $c --boot ../build/boot_'$kind'_$s.snap --max $mx || true' > $OUT.tmp 2>&1
sort -k2 $OUT.tmp > $OUT; rm -f $OUT.tmp
echo "PASS: $(grep -c '^PASS' $OUT)  FAIL: $(grep -c '^FAIL' $OUT)  OTHER: $(grep -vc '^PASS\|^FAIL' $OUT)"

#!/bin/bash
# build_cosim.sh <A|B> <ref lineage root (rtl/vhdl layout)> <out dir> [--ref]
# Verilates every cosim kind (t48sv, or with --ref the GHDL reference netlists)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../../rtl
GEN=$HERE/../ref/gen
LIN=$1; REF=$2; OUT=$3; MODE=$4
mkdir -p $OUT
python3 $HERE/gen_cosim.py $REF $OUT $LIN $MODE
VINC=/usr/share/verilator/include
LIBS=""
for k in $(cat $OUT/kinds.txt); do
  EXTRA=""
  [ -f $OUT/$k.ref ] && EXTRA="$GEN/$(cat $OUT/$k.ref).v $HERE/../tb/harness_mem.sv"
  verilator --cc --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    -Wno-MULTIDRIVEN -Wno-UNOPTFLAT --top-module $k --prefix V$k -Mdir $OUT/obj_$k -CFLAGS "-O2 -fPIC" \
    $RTL/t48sv_blocks.sv $RTL/t48sv_decoder.sv $RTL/t48sv_core.sv $RTL/t48sv_cores.sv \
    $RTL/t48sv_t8039_notri_extrom.sv $RTL/t48sv_system.sv $RTL/t48sv_t8243.sv $EXTRA $OUT/$k.sv > $OUT/build_$k.log 2>&1 \
    || { tail -20 $OUT/build_$k.log; exit 1; }
  LIBS="$LIBS $OUT/obj_$k/V${k}__ALL.a"
  INCS="$INCS -I$OUT/obj_$k"
done
first=$(head -1 $OUT/kinds.txt)
g++ -O2 -fPIC -c -I$VINC -I$VINC/vltstd $INCS $OUT/cosim_glue.cpp -o $OUT/cosim_glue.o
echo "$OUT/cosim_glue.o $LIBS $OUT/obj_$first/verilated.o $OUT/obj_$first/verilated_threads.o -lstdc++ -lpthread -latomic" > $OUT/link.txt
echo built $(wc -l < $OUT/kinds.txt) kinds

#!/bin/bash
# build.sh <cfg> [--left <cfg2>] : verilate one lockstep configuration into build/<cfg>[_vs_<cfg2>]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=${RTL:-$HERE/../../rtl}
CFG=$1; shift
OUT=${OUTDIR:-$HERE/build}/$CFG
EXTRA=""
if [ "$1" == "--left" ]; then OUT=$HERE/build/${CFG}_vs_$2; EXTRA="$HERE/../ref/gen/$2.v"; fi
mkdir -p $OUT
python3 $HERE/gen_lockstep.py $CFG $OUT "$@"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  -Wno-MULTIDRIVEN -Wno-UNOPTFLAT --top-module lockstep -Mdir $OUT/obj -CFLAGS "-O2 -I$OUT" \
  $RTL/t48sv_blocks.sv $RTL/t48sv_decoder.sv $RTL/t48sv_core.sv $RTL/t48sv_cores.sv \
  $RTL/t48sv_t8039_notri_extrom.sv $RTL/t48sv_system.sv \
  $HERE/harness_mem.sv $HERE/../ref/gen/$CFG.v $EXTRA $OUT/lockstep.sv $HERE/tb.cpp \
  -o $OUT/Vlockstep > $OUT/build.log 2>&1 || { tail -30 $OUT/build.log; exit 1; }
echo built $OUT/Vlockstep

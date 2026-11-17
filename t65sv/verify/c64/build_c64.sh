#!/bin/sh
# build_c64.sh lockstep|solo : mini-C64 harness. Needs gen/ (see prepare_c64.sh).
set -e
cd "$(dirname "$0")"; C=$(pwd); V=$C/..
kind=${1:-lockstep}
if [ "$kind" = lockstep ]; then extra="$V/ref/ref_T65.v"; def="+define+LOCKSTEP"; else extra=""; def=""; fi
verilator --cc --exe --build -O3 -j 4 --savable -Wno-fatal -Wno-lint -Wno-style $def \
  -Mdir $V/build/obj_c64_$kind -o ../c64_$kind --top-module c64_top -CFLAGS "-O2" \
  $C/gen/vic.v $C/gen/mos6526.v $extra $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_T65.sv $V/../rtl/t65sv_variants.sv \
  $C/c64_top.sv $C/c64.cpp > $V/build/c64_$kind.log 2>&1 || { tail -30 $V/build/c64_$kind.log; exit 1; }
echo built build/c64_$kind

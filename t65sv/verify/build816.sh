#!/bin/sh
# build816.sh [rtl file]: SST 65816 harness (Verilator, state loaded through public signals)
set -e
cd "$(dirname "$0")"; V=$(pwd)
RTL=${1:-$V/../rtl/t65sv816.sv}
mkdir -p build
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style --public-flat-rw \
  -Mdir build/obj_${OUT:-sst816} -o ../${OUT:-sst816} --top-module t65sv816 -CFLAGS "-O2 -I$V/tb" $EXTRA \
  $RTL $V/tb/${CPP:-sst816.cpp} > build/${OUT:-sst816}.log 2>&1 || { grep -i error build/${OUT:-sst816}.log | head -30; tail -5 build/${OUT:-sst816}.log; exit 1; }
echo built build/${OUT:-sst816}

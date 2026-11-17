#!/bin/sh
# build816t.sh: SST 65816 harness through the integrated path t65sv_T65 #(.C816(1)) (build/sst816_t65)
set -e
cd "$(dirname "$0")"; V=$(pwd); R=$V/../rtl
mkdir -p build
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style --public-flat-rw -GC816=1\'b1 \
  -Mdir build/obj_sst816_t65 -o ../sst816_t65 --top-module t65sv_T65 -CFLAGS "-O2 -DVIA_T65" \
  $R/t65sv.sv $R/t65sv816.sv $R/t65sv_T65.sv $V/tb/sst816.cpp > build/sst816_t65.log 2>&1 || { grep -i error build/sst816_t65.log | head -30; exit 1; }
echo built build/sst816_t65

#!/bin/sh
# Build the all-variants vs MAME oracle simulator.
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O3 -j 4 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  --top-module tb_variants -Mdir build/variants -o variants \
  ../rtl/crtc6845sv.sv tb/tb_variants.sv $(pwd)/tb/variant_main.cpp -CFLAGS "-O2 -I$(pwd)/tb" >build/variants.log 2>&1 || { grep -E "error|Error" build/variants.log | head -30; exit 1; }
echo built build/variants/variants

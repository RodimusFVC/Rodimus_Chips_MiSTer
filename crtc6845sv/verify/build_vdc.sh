#!/bin/sh
# Build the VDC (8563 / 8568) vs MAME mos8563 oracle simulator.
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O3 -j 4 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  --top-module tb_vdc -Mdir build/vdc -o vdc \
  ../rtl/crtc6845sv_vdc.sv tb/tb_vdc.sv $(pwd)/tb/vdc_main.cpp -CFLAGS "-O2 -I$(pwd)/tb" >build/vdc.log 2>&1 || { grep -E "error|Error" build/vdc.log | head -30; exit 1; }
echo built build/vdc/vdc

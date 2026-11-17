#!/bin/sh
# Build the default-variant fleet-scenario simulator (lockstep model driven with the fleet games tables).
set -e
cd "$(dirname "$0")"
verilator --cc --exe --build -O3 -j 4 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  --top-module tb_lockstep -Mdir build/fleet -o fleet \
  ../rtl/crtc6845sv.sv ../rtl/crtc6845sv_mc6845.sv ref/mc6845_fixed_ghdl.v ref/mc6845_stock_ghdl.v \
  tb/tb_lockstep.sv $(pwd)/tb/fleet_main.cpp -CFLAGS "-O2 -I$(pwd)/tb" >build/fleet.log 2>&1 || { tail -30 build/lockstep.log; exit 1; }
echo built build/fleet/fleet

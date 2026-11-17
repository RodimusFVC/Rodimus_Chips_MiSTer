#!/bin/bash
# Formal bounded equivalence: GHDL-elaborated s2650_cpu (gold) vs s2650sv_s2650_cpu (gate), every output on
# every clock, all inputs free on every cycle, from the all-zero power-up state, for N clocks (default 12).
cd "$(dirname "$0")"
S=${SGS2650_DIR:-../../../ref/galaxian/rtl/cpu/s2650}
N=${1:-12}
yosys -m ghdl -q -l bmc_$N.log -p "
  ghdl --std=08 $S/base/base_pack.vhd $S/sgs2650_pack.vhd $S/sgs2650.vhd $S/s2650_cpu.vhd -e s2650_cpu;
  rename s2650_cpu gold;
  read_verilog -sv ${RTL:-../../rtl/s2650sv.sv} ../../rtl/s2650sv_s2650_cpu.sv;
  rename s2650sv_s2650_cpu gate;
  hierarchy -check; proc; flatten; memory -nomap; memory_map; opt_clean; async2sync; dffunmap;
  miter -equiv -flatten -make_outputs gold gate miter;
  hierarchy -top miter; opt -fast;
  sat -verify -seq $N -set-init-zero -prove trigger 0 -show-inputs -timeout 20000 miter" >/dev/null 2>&1
st=$?
rm -f trace.log
grep -E "SAT proof finished|SUCCESS|FAIL|failed|Timeout" bmc_$N.log | tail -3
exit $st

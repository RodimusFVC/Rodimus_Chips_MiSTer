#!/bin/bash
# GHDL (yosys ghdl plugin) conversion of the reference to Verilog: ref_a.v = s2650_cpu (fleet wrapper,
# VER_B default false), ref_b_core.v = sgs2650 with VER_B=true
cd "$(dirname "$0")"
S=${SGS2650_DIR:-../../../ref/galaxian/rtl/cpu/s2650}
yosys -m ghdl -q -p "ghdl --std=08 $S/base/base_pack.vhd $S/sgs2650_pack.vhd $S/sgs2650.vhd $S/s2650_cpu.vhd -e s2650_cpu;
  hierarchy -top s2650_cpu; rename s2650_cpu ref_s2650_cpu; write_verilog -noattr ref_a.v" >/dev/null 2>&1
yosys -m ghdl -q -p "ghdl --std=08 -gVER_B=true $S/base/base_pack.vhd $S/sgs2650_pack.vhd $S/sgs2650.vhd -e sgs2650;
  rename sgs2650 ref_sgs2650_b; write_verilog -noattr ref_b_core.v" >/dev/null 2>&1
rm -f trace.log
md5sum ref_a.v ref_b_core.v

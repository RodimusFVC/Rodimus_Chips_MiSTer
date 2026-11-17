#!/bin/bash
# GHDL simulation of the original VHDL against stimulus / outputs dumped from the converted netlist
cd "$(dirname "$0")"
S=${SGS2650_DIR:-../../../ref/galaxian/rtl/cpu/s2650}
mkdir -p work
ghdl -a --std=93c -fsynopsys --workdir=work $S/base/base_pack.vhd $S/sgs2650_pack.vhd $S/sgs2650.vhd $S/s2650_cpu.vhd tb_xcheck.vhd
ghdl -e --std=93c -fsynopsys --workdir=work tb_xcheck
for seed in ${@:-101 102 103 104}; do
  ../tb/lockstep_a_m1 dump $seed 150000 stim_$seed.txt > /dev/null
  ./tb_xcheck -gFNAME=stim_$seed.txt 2>&1 | grep -v "^.*warning\|assertion" | tail -3
  rm -f stim_$seed.txt
done
rm -f trace.log

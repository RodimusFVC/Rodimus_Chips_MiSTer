#!/bin/bash
# Yosys Cyclone V (synth_intel_alm) area / depth: reference (GHDL front end) vs s2650sv
cd "$(dirname "$0")"
S=${SGS2650_DIR:-../../../ref/galaxian/rtl/cpu/s2650}
yosys -m ghdl -q -l ref.log -p "ghdl --std=08 $S/base/base_pack.vhd $S/sgs2650_pack.vhd $S/sgs2650.vhd $S/s2650_cpu.vhd -e s2650_cpu;
  synth_intel_alm -family cyclonev -top s2650_cpu; tee -q -o ref_stat.txt stat; write_json ref.json" >/dev/null 2>&1
# s2650sv, return stack in MLAB (default) and in registers (RAS_MLAB=0: yosys ignores ramstyle, so map it to FFs)
yosys -q -l sv_m1.log -p "read_verilog -sv ../../rtl/s2650sv.sv; synth_intel_alm -family cyclonev -top s2650sv;
  tee -q -o sv_m1_stat.txt stat; write_json sv_m1.json" >/dev/null 2>&1
yosys -q -l sv_m0.log -p "read_verilog -sv ../../rtl/s2650sv.sv; chparam -set RAS_MLAB 0 s2650sv; hierarchy -top s2650sv;
  proc; memory -nomap; memory_map; synth_intel_alm -family cyclonev -top s2650sv; tee -q -o sv_m0_stat.txt stat; write_json sv_m0.json" >/dev/null 2>&1
rm -f trace.log
for f in ref sv_m1 sv_m0; do
  echo "== $f"
  awk '/MISTRAL_ALUT[0-9]/{l+=$2} /MISTRAL_ALUT_ARITH/{a=$2} /MISTRAL_FF/{f=$2} /MISTRAL_MLAB/{m=$2}
       END{printf "  LUTs %d  arith %d  (LUT+arith %d)  FFs %d  MLAB bits-cells %d\n", l, a, l+a, f, m}' ${f}_stat.txt
  python3 depth.py $f.json
done

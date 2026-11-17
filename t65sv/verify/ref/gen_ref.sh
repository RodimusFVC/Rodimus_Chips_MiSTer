#!/bin/sh
# Builds the oracle: T65 Ver 315 VHDL -> Verilog via GHDL synth (verification-only, never part of the core).
set -e
cd "$(dirname "$0")"
for f in T65.vhd:4f4b9f2bed732aa991fad4cd6ac486ae T65_ALU.vhd:e53ea5b5e62a6d7a601636255593502b \
         T65_MCode.vhd:2085d347eee208b3b4faf6a46acabd93 T65_Pack.vhd:5451562ee2ae37d76db7991034af8ee3; do
  n=${f%%:*}; m=${f##*:}
  echo "$m  $n" | md5sum -c - >/dev/null || { echo "md5 mismatch: $n"; exit 1; }
done
rm -f work-obj93.cf
ghdl -a -fsynopsys -fexplicit T65_Pack.vhd T65_ALU.vhd T65_MCode.vhd T65.vhd 2>/dev/null
ghdl --synth -fsynopsys -fexplicit --out=verilog T65 2>/dev/null > T65_ghdl_raw.v
# 'break' is an SV keyword; VHDL signal ALU_Q and instance port alu.q collapse to one net (GHDL emits it twice); prefix modules so they cannot collide with anything else.
sed -e 's/\bbreak\b/break_s/g' \
    -e 's/^module T65$/module ref_T65/' \
    -e 's/^module t65_alu$/module ref_t65_alu/' -e 's/^module t65_mcode$/module ref_t65_mcode/' \
    -e 's/^  t65_alu /  ref_t65_alu /' -e 's/^  t65_mcode /  ref_t65_mcode /' \
    -e '/assign alu_q = alu_q;/d' \
    T65_ghdl_raw.v | awk '/^  wire \[7:0\] alu_q;$/ { if (seen++) next } { print }' > ref_T65.v
echo "ref_T65.v: $(wc -l < ref_T65.v) lines"

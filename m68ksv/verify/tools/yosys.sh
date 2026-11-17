#!/bin/bash
# yosys estimate (NOT Quartus): synth_intel_alm -family cyclonev on m68ksv (CPU=$YCPU, default 68000) and, if given, fx68k;
# plus the deepest register-to-register paths of the m68ksv netlist in LUT levels (depth.py).
#   yosys.sh <out dir> [fx68k source dir]
# yosys does not take package imports inside modules: a copy with the import moved to file scope is synthesised.
set -e
HERE=$(dirname "$(realpath "$0")")
O=$(realpath -m "$1"); mkdir -p "$O"
YCPU=${YCPU:-68000}
"$HERE/mkall.sh" > /dev/null
# Note: yosys ignores ramstyle; it maps a register-file copy (m68ksv_rf, MLAB in Quartus) to an M10K or MLAB cells
# depending on whether it can merge the read-address register. The logic around it is the same either way.
sed -e '/^import m68ksv_upkg::\*;$/d' -e 's/^endpackage$/endpackage\nimport m68ksv_upkg::*;/' "$HERE/../../rtl/m68ksv_all.sv" > "$O/m68ksv_yosys.sv"
( cd "$O" && yosys -q -l m68ksv_yosys.log -p "read_verilog -sv m68ksv_yosys.sv; chparam -set CPU $YCPU m68ksv; synth_intel_alm -family cyclonev -top m68ksv; tee -o m68ksv_stat.txt stat; write_json m68ksv.json" > /dev/null )
echo "m68ksv (CPU=$YCPU):"; grep -E "Number of cells|MISTRAL_ALUT|MISTRAL_ALUT_ARITH|MISTRAL_FF|MISTRAL_M10K|MISTRAL_MLAB|MISTRAL_MUL|cells$" "$O/m68ksv_stat.txt" | head -20
python3 "$HERE/depth.py" "$O/m68ksv.json" 40 > "$O/m68ksv_depth.txt"
echo "deepest register-to-register paths (LUT levels, yosys netlist): $O/m68ksv_depth.txt"; head -9 "$O/m68ksv_depth.txt"
if [ -n "$2" ]; then
  FX=$(realpath "$2")
  ( cd "$O" && cp -f "$FX/microrom.mem" "$FX/nanorom.mem" . && yosys -q -l fx68k_yosys.log -p "read_verilog -sv $FX/fx68k.sv $FX/fx68kAlu.sv $FX/uaddrPla.sv; synth_intel_alm -family cyclonev -top fx68k; tee -o fx68k_stat.txt stat" > /dev/null )
  echo "fx68k:"; grep -E "Number of cells|MISTRAL_ALUT|MISTRAL_ALUT_ARITH|MISTRAL_FF|MISTRAL_M10K|MISTRAL_MLAB|MISTRAL_MUL|cells$" "$O/fx68k_stat.txt" | head -20
fi

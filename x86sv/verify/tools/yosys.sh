#!/bin/bash
# Cyclone V resource / depth estimate with yosys (an estimate, not Quartus): yosys.sh <out dir> [8088 | 8086 | v20 | v30 | v20e | v30e]
# Prints the cell statistics and the longest combinational path in cells, once counting carry-chain cells and once
# without them (FFs removed so every path ends at a register or pin), and without the paths into output pins.
set -e
OUT=$(realpath -m "$1"); mkdir -p "$OUT"
case "${2:-8088}" in
8088) TOP=x86sv; CP="" ;;
8086) TOP=x86sv16; CP="" ;;
v20)  TOP=x86sv; CP="chparam -set NEC 1 x86sv;" ;;
v30)  TOP=x86sv16; CP="chparam -set NEC 1 x86sv16;" ;;
v20e) TOP=x86sv; CP="chparam -set NEC 1 -set NEC8080 1 x86sv;" ;;
v30e) TOP=x86sv16; CP="chparam -set NEC 1 -set NEC8080 1 x86sv16;" ;;
*) echo "unknown config $2"; exit 1 ;;
esac
RTL=${X86SV_RTL:-$(dirname "$(realpath "$0")")/../../rtl/x86sv_all.sv}
ulimit -v 8000000
yosys -q -l "$OUT/yosys.log" -p "read_verilog -sv $RTL; $CP synth_intel_alm -family cyclonev -top $TOP; \
    tee -q -o $OUT/stat.txt stat; write_json $OUT/net.json; delete t:MISTRAL_FF; tee -q -o $OUT/ltp.txt ltp; \
    delete t:MISTRAL_ALUT_ARITH; tee -q -o $OUT/ltp_lut.txt ltp; delete t:MISTRAL_OB; tee -q -o $OUT/ltp_int.txt ltp" > /dev/null
sed -n '/cells$/,/^$/p' "$OUT/stat.txt"
echo "longest path incl. carry cells: $(grep -o 'length=[0-9]*' "$OUT/ltp.txt")"
echo "longest LUT-only path:          $(grep -o 'length=[0-9]*' "$OUT/ltp_lut.txt")"
echo "  ... register to register only:  $(grep -o 'length=[0-9]*' "$OUT/ltp_int.txt")"

#!/bin/bash
# Formal equivalence of one configuration's top (default x86sv = 8088; x86sv16 = 8086; with "nec": V20 / V30, the
# reference's parameters against NEC = 1, NEC8080 = 0) against a reference x86sv_all.sv:
#   equiv.sh <reference x86sv_all.sv> [out dir] [top] [nec]
# Both designs are flattened at RTL level and matched register by register (yosys equiv_make / equiv_simple /
# equiv_induct); exit status 0 and "Equivalence successfully proven" when every output and register is proven.
set -e
REF=$(realpath "$1")
OUT=$(realpath -m "${2:-/tmp}")
TOP=${3:-x86sv}
CP=""; [ "$4" = nec ] && CP="chparam -set NEC 1 $TOP;"
mkdir -p "$OUT"
NEW=$(dirname "$(realpath "$0")")/../../rtl/x86sv_all.sv
ulimit -v 8000000
yosys -q -l "$OUT/equiv.log" -p "
read_verilog -sv $REF; $CP hierarchy -top $TOP; proc; flatten; opt; rename $TOP gold; design -stash gold
read_verilog -sv $NEW; $CP hierarchy -top $TOP; proc; flatten; opt; rename $TOP gate; design -stash gate
design -copy-from gold -as gold gold; design -copy-from gate -as gate gate
equiv_make gold gate equiv; hierarchy -top equiv; async2sync
equiv_simple -seq 2; equiv_induct -seq 2; equiv_status -assert" > /dev/null 2>&1 || true
grep -A2 "Found [0-9]* \$equiv cells" "$OUT/equiv.log" | sed 's/^ *//'
grep -q "Equivalence successfully proven" "$OUT/equiv.log"

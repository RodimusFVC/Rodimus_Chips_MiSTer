#!/bin/sh
# equiv_c816.sh <old t65sv.sv> <new t65sv.sv> <t65sv816.sv>: formal check that the new t65sv with C816 = 0 is the
# old t65sv, for every C02 / C02_FIXED / NO_DECIMAL combination (yosys equiv_make / equiv_simple / equiv_induct).
OLD=$1; NEW=$2; E816=$3
for p in "0 0 0" "1 0 0" "2 0 0" "3 0 0" "0 0 1" "1 1 0" "2 1 0" "3 1 0"; do
  set -- $p
  yosys -q -l equiv_c816_$1$2$3.log -p "
    read_verilog -sv $OLD; hierarchy -top t65sv -chparam C02 $1 -chparam C02_FIXED $2 -chparam NO_DECIMAL $3
    proc; flatten; opt_clean; async2sync; opt -full; rename t65sv gold; design -stash gold
    read_verilog -sv $NEW $E816; hierarchy -top t65sv -chparam C02 $1 -chparam C02_FIXED $2 -chparam NO_DECIMAL $3 -chparam C816 0
    proc; flatten; opt_clean; async2sync; opt -full; rename t65sv gate; design -stash gate
    design -copy-from gold -as gold gold; design -copy-from gate -as gate gate
    equiv_make gold gate equiv; hierarchy -top equiv; equiv_simple -seq 2; equiv_induct -seq 2; equiv_status -assert" >/dev/null 2>&1 \
    && echo "C02=$1 C02_FIXED=$2 NO_DECIMAL=$3: equivalent ($(grep -o 'Of those cells [0-9]* are proven' equiv_c816_$1$2$3.log | tail -1))" \
    || echo "C02=$1 C02_FIXED=$2 NO_DECIMAL=$3: NOT PROVEN (see equiv_c816_$1$2$3.log)"
done

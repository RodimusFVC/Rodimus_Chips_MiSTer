#!/bin/sh
# area.sh: yosys Cyclone V (synth_intel_alm) cell counts + 6-LUT depth for T65 and t65sv configurations
cd "$(dirname "$0")"
R=../../rtl
sed 's/input  tri1         BCD_en/input  logic        BCD_en/' $R/t65sv_T65.sv > t65sv_T65_yosys.sv
SRC="read_verilog ../ref/ref_T65.v; read_verilog -sv $R/t65sv.sv $R/t65sv816.sv t65sv_T65_yosys.sv $R/t65sv_variants.sv fleet_tops.sv"
run() { # name top chparams
  n=$1; top=$2; cp=$3
  yosys -q -l $n.alm.log -p "$SRC; hierarchy -top $top $cp; synth_intel_alm -family cyclonev -top $top -noiopad -noclkbuf; stat" >/dev/null 2>&1
  yosys -q -l $n.lut.log -p "$SRC; hierarchy -top $top $cp; synth -flatten -top $top; abc -lut 6; opt_clean; stat; tee -o $n.lut.ltp ltp -noff" >/dev/null 2>&1
  s=$(sed -n '/Printing statistics/,$p' $n.alm.log)
  l6=$(echo "$s" | awk '/MISTRAL_ALUT6/{a=$2}/MISTRAL_ALUT5/{b=$2}/MISTRAL_ALUT4/{c=$2}/MISTRAL_ALUT3/{d=$2}/MISTRAL_ALUT2/{e=$2}/MISTRAL_ALUT_ARITH/{f=$2}/MISTRAL_FF/{g=$2}END{printf "%d %d %d %d %d %d %d", a,b,c,d,e,f,g}')
  set -- $l6
  luts=$(($1+$2+$3+$4+$5)); alm=$(( $1 + ($2+$3+$4+$5+1)/2 + ($6+1)/2 ))
  ffalm=$((($7+1)/2)); [ $ffalm -gt $alm ] && alm=$ffalm
  dep=$(grep -o "Longest topological path.*length=[0-9]*" $n.lut.ltp | grep -o "[0-9]*$")
  lut6=$(grep "\$lut" $n.lut.log | tail -1 | awk '{print $2}')
  printf "%-22s LUT6=%-4s LUT5=%-4s LUT<=4=%-4s ARITH=%-4s FF=%-4s ALM~%-4s | generic LUT6 count=%-4s depth=%s\n" $n $1 $2 $(($3+$4+$5)) $6 $7 $alm "$lut6" "$dep"
}
run t65_fleet       fleet_ref ""
run t65sv_fleet     fleet_sv  ""
run t65sv_fleet_c00 fleet_sv  "-chparam C02 0"
run t65_full        full_ref  ""
run t65sv_full_nmos full_sv   "-chparam C02 0"
run t65sv_full_wdc  full_sv   "-chparam C02 1"
run t65sv_full_rkwl full_sv   "-chparam C02 2"
run t65sv_full_sc02 full_sv   "-chparam C02 3"
run t65sv_6510      t65sv_6510 ""
run t65sv_6507      t65sv_6507 ""
run t65sv_2A03      t65sv_2A03 ""
run t65sv_65C02_wdc t65sv_65C02 ""
run t65sv_65C816    t65sv_65C816 ""
run t65sv_T65_c816  t65sv_T65 "-chparam C816 1"

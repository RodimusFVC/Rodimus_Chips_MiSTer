#!/bin/sh
# final.sh <download dir>: rebuild every non-C64 harness from rtl/ and rerun those suites (run_all.sh minus the
# C64 programs), two jobs at a time where independent. Results in results/.
cd "$(dirname "$0")"; V=$(pwd); DL=${1:?usage: final.sh <download dir>}
SB=$DL/sstbin; D=tests/dormann
mkdir -p results build
set -e
./build_lockstep.sh
./build_tb.sh progrun_ls progrun.cpp lockstep
./build_tb.sh sst_ls sst.cpp lockstep
./build_tb.sh progrun_wdc  progrun.cpp solo -GC02=1
./build_tb.sh progrun_rkwl progrun.cpp solo -GC02=2
./build_tb.sh progrun_syn  progrun.cpp solo -GC02=3
./build_tb.sh progrun_2a03 progrun.cpp solo -GC02=0 -GNO_DECIMAL=1
./build_tb.sh progrun_wdcfx progrun.cpp solo -GC02=1 -GC02_FIXED=1
./build_tb.sh sst_wdc  sst.cpp solo -GC02=1
./build_tb.sh sst_rkwl sst.cpp solo -GC02=2
./build_tb.sh sst_syn  sst.cpp solo -GC02=3
./build_tb.sh sst_2a03 sst.cpp solo -GC02=0 -GNO_DECIMAL=1
./build_tb.sh sst_wdcfx sst.cpp solo -GC02=1 -GC02_FIXED=1
./build_tb.sh c02dir c02dir.cpp solo -GC02=1
verilator --cc --exe --build -O2 -j 4 -Wno-fatal -Wno-lint -Wno-style -Mdir build/obj_port -o ../port6510 \
  --top-module t65sv_6510 $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_variants.sv $V/tb/port6510.cpp > build/port6510.log 2>&1
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style -Mdir build/obj_6507 -o ../ls6507 \
  --top-module ls6507_top $V/ref/ref_T65.v $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_variants.sv $V/tb/ls6507_top.sv \
  $V/tb/ls6507.cpp > build/ls6507.log 2>&1
./build816.sh
OUT=c816dir CPP=c816dir.cpp ./build816.sh
OUT=progrun816 CPP=progrun816.cpp ./build816.sh
./build816t.sh
set +e

echo "== lint"; ./make_all.sh; ./lint.sh > results/lint.txt 2>&1; cat results/lint.txt | tail -3

echo "== lockstep + sweep"
( for s in 1 2 3 4 5 6 7 8 9 10; do ./build/lockstep random $s 20000000 | tail -1; done > results/lockstep_random.txt ) &
./build/lockstep sweep > results/sweep.txt
wait

echo "== Dormann"
{
  ./build/progrun_ls   --hex $D/6502_functional_test.hex --start 0400 --pass 3469
  ./build/progrun_ls   --hex $D/dec_nmos_ac.hex  --start 0200 --stop 024b --check 000b=00
  ./build/progrun_ls   --hex $D/dec_nmos_all.hex --start 0200 --stop 024b --check 000b=00
  for v in "wdc c02_wdc 24f1" "rkwl c02_rkwl 2569" "syn c02_sc02 2434"; do
    set -- $v
    ./build/progrun_$1 --mode 1 --hex $D/$2.hex --start 0400 --pass $3
    ./build/progrun_$1 --mode 1 --hex $D/dec_c02_all.hex --start 0200 --stop 024b --check 000b=00
    ./build/progrun_$1 --mode 1 --hex $D/6502_functional_test.hex --start 0400 --pass 3469
  done
  ./build/progrun_wdcfx --mode 1 --hex $D/c02_wdc.hex --start 0400 --pass 24f1
  ./build/progrun_wdcfx --mode 1 --hex $D/dec_c02_all.hex --start 0200 --stop 024b --check 000b=00
  ./build/progrun_2a03 --hex $D/func_nodec.hex --start 0400 --pass 336d
  ./build/progrun_2a03 --hex $D/dec_2a03_all.hex --start 0200 --stop 024b --check 000b=00
} > results/dormann.txt 2>&1 &

echo "== directed"
{ ./build/c02dir; ./build/port6510; ./build/ls6507; } > results/directed.txt 2>&1
wait

echo "== SingleStepTests"
./build/sst_ls   --quiet $SB/6502 > results/sst_6502_lockstep.txt &
./build/sst_2a03 --quiet $SB/nes6502 > results/sst_nes6502.txt
wait
./build/sst_wdc  --mode 1 --quiet $SB/wdc65c02 > results/sst_wdc.txt &
./build/sst_rkwl --mode 1 --quiet $SB/rockwell65c02 > results/sst_rockwell.txt
wait
./build/sst_syn  --mode 1 --quiet $SB/synertek65c02 > results/sst_synertek.txt &

echo "== 65C816"
./build/sst816 --quiet $DL/sst816bin > results/sst816.txt
wait
./build/sst816_t65 --quiet $DL/sst816bin > results/sst816_via_T65.txt &
./build/c816dir > results/c816dir.txt
{ ./build/progrun816 --hex tests/dormann/6502_functional_test.hex --start 0400 --pass 3469; ./build/progrun816 --hex tests/dormann/dec_816_all.hex --start 0200 --stop 024b --check 000b=00; ./build/progrun816 --hex tests/dormann/6502_functional_test.hex --start 0400 --pass 3469 --stall 12345; } > results/dormann816.txt 2>&1
./build/sst_wdcfx --mode 1 --quiet $SB/wdc65c02 > results/sst_wdc_fixed.txt
wait

echo "== mutation"
./mutate.sh mutants1.txt > results/mutation.txt
./mutate.sh mutants2.txt > results/mutation2.txt

echo "== synthesis"
synth/area.sh > synth/area.txt
(cd synth && ./equiv_c816.sh pre816/t65sv.sv ../../rtl/t65sv.sv ../../rtl/t65sv816.sv > equiv_c816.txt)
(cd synth && yosys -q -l equiv_fold.log equiv_fold.ys > /dev/null 2>&1 && echo "equiv_fold: proven" || echo "equiv_fold: FAILED") > synth/equiv_fold.txt

echo "== coverage"
./cov.sh $DL
echo final done

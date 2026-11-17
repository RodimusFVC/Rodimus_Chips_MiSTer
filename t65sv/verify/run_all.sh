#!/bin/sh
# run_all.sh <download dir>: rebuild every harness and rerun every suite; results land in results/.
# See README.md for the one-time preparation (oracle, Dormann assembly, SST conversion, C64 inputs).
set -e
DL=${1:?usage: run_all.sh <download dir>}
cd "$(dirname "$0")"; V=$(pwd)
mkdir -p results build
SB=$DL/sstbin; L=$DL/vicetp/Lorenz-2.15/src; D=tests/dormann

echo "== build"
./build_lockstep.sh
./build_tb.sh progrun_ls progrun.cpp lockstep
./build_tb.sh sst_ls sst.cpp lockstep
./build_tb.sh c64flat_ls c64flat.cpp lockstep
./build_tb.sh progrun_wdc  progrun.cpp solo -GC02=1
./build_tb.sh progrun_rkwl progrun.cpp solo -GC02=2
./build_tb.sh progrun_syn  progrun.cpp solo -GC02=3
./build_tb.sh progrun_2a03 progrun.cpp solo -GC02=0 -GNO_DECIMAL=1
./build_tb.sh sst_wdc  sst.cpp solo -GC02=1
./build_tb.sh sst_rkwl sst.cpp solo -GC02=2
./build_tb.sh sst_syn  sst.cpp solo -GC02=3
./build_tb.sh sst_2a03 sst.cpp solo -GC02=0 -GNO_DECIMAL=1
./build_tb.sh c02dir c02dir.cpp solo -GC02=1
verilator --cc --exe --build -O2 -j 4 -Wno-fatal -Wno-lint -Wno-style -Mdir build/obj_port -o ../port6510 \
  --top-module t65sv_6510 $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_variants.sv $V/tb/port6510.cpp > build/port6510.log 2>&1
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style -Mdir build/obj_6507 -o ../ls6507 \
  --top-module ls6507_top $V/ref/ref_T65.v $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_variants.sv $V/tb/ls6507_top.sv \
  $V/tb/ls6507.cpp > build/ls6507.log 2>&1
c64/build_c64.sh lockstep
c64/build_c64.sh solo

echo "== lint"
./lint.sh > results/lint.txt 2>&1 && cat results/lint.txt

echo "== lockstep (Mode 00)"
for s in 1 2 3 4 5 6 7 8 9 10; do ./build/lockstep random $s 20000000 | tail -1; done > results/lockstep_random.txt
./build/lockstep sweep > results/sweep.txt

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
  ./build/progrun_2a03 --hex $D/func_nodec.hex --start 0400 --pass 336d
  ./build/progrun_2a03 --hex $D/dec_2a03_all.hex --start 0200 --stop 024b --check 000b=00
} > results/dormann.txt 2>&1 || true

echo "== SingleStepTests"
./build/sst_ls   --quiet $SB/6502 > results/sst_6502_lockstep.txt
./build/sst_2a03 --quiet $SB/nes6502 > results/sst_nes6502.txt
./build/sst_wdc  --mode 1 --quiet $SB/wdc65c02 > results/sst_wdc.txt
./build/sst_rkwl --mode 1 --quiet $SB/rockwell65c02 > results/sst_rockwell.txt
./build/sst_syn  --mode 1 --quiet $SB/synertek65c02 > results/sst_synertek.txt

echo "== directed variant tests"
{ ./build/c02dir; ./build/port6510; ./build/ls6507; } > results/directed.txt 2>&1 || true

echo "== Lorenz / VICE"
# flat C64 (no VIC/CIA), lockstep, every Lorenz program; then the mini-C64 (VIC-II + CIAs) for every program that
# did not pass there (including the ones that hit the 1 h limit), 40M-cycle cap
./run_lorenz_flat.sh $L ./build/c64flat_ls results/lorenz_flat_lockstep.txt
ls $L/*.prg | grep -v -- "-dtv\|-plus4\|nextdisk\|template\|cpuport128" | sort > results/lorenz_all.txt
grep '^PASS' results/lorenz_flat_lockstep.txt | awk '{print $2}' | sort | comm -23 results/lorenz_all.txt - > results/lorenz_c64_list.txt
./run_c64.sh lockstep results/lorenz_c64_list.txt results/lorenz_c64_lockstep.txt 40000000
# the 6510 wrapper's own I/O port on the mini-C64 (solo build)
for p in cpuport mmu mmufetch; do echo $L/$p.prg; done > results/lorenz_c64_solo_list.txt
./run_c64.sh solo results/lorenz_c64_solo_list.txt results/lorenz_c64_solo6510.txt 40000000
# VICE testprogs CPU: flat C64 first, then the mini-C64 for exit-code tests at the testbench's cycle budget
ls $DL/vicetp/CPU/*/*.prg | grep -v "kdormann\|jeek816" > results/vice_list.txt
xargs -P 4 -I{} sh -c 'timeout 1200 ./build/c64flat_ls {} --max 300000000 || true' < results/vice_list.txt | sort -k2 > results/vice_flat_lockstep.txt
python3 vice_c64_list.py $DL/vicetb/x64sc-testlist.txt results/vice_flat_lockstep.txt > results/vice_c64_list.txt
./run_c64.sh lockstep results/vice_c64_list.txt results/vice_c64_lockstep.txt
python3 make_tables.py $DL

echo "== 65C816"
./build816.sh
OUT=c816dir CPP=c816dir.cpp ./build816.sh
OUT=progrun816 CPP=progrun816.cpp ./build816.sh
./build816t.sh
./build/sst816 --quiet $DL/sst816bin > results/sst816.txt || true
./build/sst816_t65 --quiet $DL/sst816bin > results/sst816_via_T65.txt || true
./build/c816dir > results/c816dir.txt || true
{ ./build/progrun816 --hex tests/dormann/6502_functional_test.hex --start 0400 --pass 3469; ./build/progrun816 --hex tests/dormann/dec_816_all.hex --start 0200 --stop 024b --check 000b=00; ./build/progrun816 --hex tests/dormann/6502_functional_test.hex --start 0400 --pass 3469 --stall 12345; } > results/dormann816.txt 2>&1 || true

echo "== mutation"
./mutate.sh mutants1.txt > results/mutation.txt
./mutate.sh mutants2.txt > results/mutation2.txt

echo "== synthesis"
synth/area.sh > synth/area.txt
(cd synth && ./equiv_c816.sh pre816/t65sv.sv ../../rtl/t65sv.sv ../../rtl/t65sv816.sv > equiv_c816.txt)

echo "== coverage"
./cov.sh $DL
echo done

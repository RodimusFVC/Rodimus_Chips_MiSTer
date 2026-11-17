#!/bin/bash
# Full verification of s2650sv; logs in verify/results/. Needs the fleet sgs2650 sources (SGS2650_DIR,
# default ../ref/galaxian/rtl/cpu/s2650 next to this tree) and, for the MAME part, a MAME checkout (MAME_DIR).
# Usage: run_all.sh [quick]
cd "$(dirname "$0")"
R=results; mkdir -p $R
Q=${1:-full}
J=${JOBS:-4}
echo "== md5 of the reference sources" | tee $R/summary.txt
S=${SGS2650_DIR:-../../ref/galaxian/rtl/cpu/s2650}
(cd $S && md5sum sgs2650.vhd sgs2650_pack.vhd base/base_pack.vhd s2650_cpu.vhd) | tee -a $R/summary.txt
echo "== reference netlists (GHDL -> Verilog)" | tee -a $R/summary.txt
./refmodel/convert.sh >> $R/summary.txt 2>&1
echo "== lint" | tee -a $R/summary.txt
./make_all.sh >/dev/null && ./lint.sh 2>&1 | tail -1 | tee -a $R/summary.txt
echo "== build lockstep harnesses" | tee -a $R/summary.txt
tb/build.sh > $R/build.log 2>&1
echo "== exerciser" | tee -a $R/summary.txt
(cd exerciser && python3 gen_exerciser.py exerciser.asm && python3 asm2650.py exerciser.asm exerciser.bin exerciser.lst) | tee -a $R/summary.txt
for v in a_m1 b_m1 a_m0 b_m0; do
  tb/lockstep_$v prog exerciser/exerciser.bin 20000000 3 > $R/exerciser_$v.log 2>&1
  DUTBUS=1 tb/lockstep_$v prog exerciser/exerciser.bin 20000000 3 > $R/exerciser_alone_$v.log 2>&1
  grep -h "result" $R/exerciser_$v.log $R/exerciser_alone_$v.log | tee -a $R/summary.txt
done
echo "== directed sweeps (irq on every cycle, reset on every cycle, ack stalls on every access)" | tee -a $R/summary.txt
SEEDS=4; [ $Q = quick ] && SEEDS=1
for v in a_m1 b_m1 a_m0 b_m0; do echo "tb/lockstep_$v sweep $SEEDS > $R/sweep_$v.log 2>&1"; done | xargs -P $J -I{} bash -c "{}"
grep -h "sweep:\|sweep coverage" $R/sweep_*.log | tee -a $R/summary.txt
echo "== random lockstep" | tee -a $R/summary.txt
CYC=25000000; [ $Q = quick ] && CYC=2000000
jobs=()
for s in 1 2 3 4 5 6 7 8; do jobs+=("a_m1 $s"); done
for s in 11 12 13 14; do jobs+=("b_m1 $s"); done
for s in 21 22; do jobs+=("a_m0 $s"); done
jobs+=("b_m0 31")
[ $Q = quick ] && jobs=("a_m1 1" "b_m1 11" "a_m0 21" "b_m0 31")
printf '%s\n' "${jobs[@]}" | xargs -P $J -L 1 bash -c 'tb/lockstep_$0 random $1 '$CYC' > '$R'/random_$0_$1.log 2>&1'
grep -h "random seed\|addressing-mode\|taken classes\|instrs" $R/random_*.log | tee -a $R/summary.txt
echo "== GHDL simulation of the original VHDL vs the converted netlist" | tee -a $R/summary.txt
ghdl/run_xcheck.sh 101 102 103 104 2>&1 | grep xcheck | tee -a $R/summary.txt
echo "== yosys Cyclone V area / depth" | tee -a $R/summary.txt
synth/synth.sh 2>&1 | tee -a $R/summary.txt
echo "== formal bounded equivalence (all inputs free, from power-up)" | tee -a $R/summary.txt
N=${BMC_N:-8}; [ $Q = quick ] && N=4
formal/bmc.sh $N | sed "s/^/N=$N: /" | tee -a $R/summary.txt
if [ -n "${MAME_DIR:-}" ] || [ -d ../../ref/mame ]; then
  echo "== MAME s2650.cpp vs sgs2650" | tee -a $R/summary.txt
  mame/build.sh > $R/mame_build.log 2>&1
  INS=3000000; [ $Q = quick ] && INS=200000
  mame/mamecmp directed 4 > $R/mame_directed.log 2>&1
  mame/mamecmp random 1 $INS > $R/mame_random.log 2>&1
  head -1 $R/mame_directed.log $R/mame_random.log | tee -a $R/summary.txt
fi
echo "done: $R/summary.txt"

#!/bin/bash
# run_sweeps.sh: directed timing sweeps (every clock offset k = 0..599) per instruction class
HERE=$(cd "$(dirname "$0")" && pwd)
SW=$HERE/../sweeps
RES=$HERE/../results
jobs=()
while read cfg; do
  case $cfg in
    B_upi41*|B_t804[12]*) progs="u1_upi u2_upi_dma";;
    B_t21_core|B_t8021_notri) progs="m2_8021";;
    B_t22_core|B_t8022_notri) progs="m1_8022";;
    *) progs="c1_alu c2_imm c3_movx c4_movp c5_jmpp c6_cond c7_call c8_timer c9_exp";;
  esac
  for p in $progs; do jobs+=("$cfg $p"); done
done < $HERE/all_cfgs.txt
printf '%s\n' "${jobs[@]}" | xargs -P 4 -L 1 bash -c 'mkdir -p '$HERE'/build/$0/job_$1 && cd '$HERE'/build/$0/job_$1 && ../Vlockstep --sweep '$SW'/$1.hex --runs 600 --cycles 1500 --quiet > '$RES'/sweep_$0_$1.txt 2>&1'
grep -h RESULT $RES/sweep_*.txt > $RES/sweep_summary.txt
grep -l MISMATCH $RES/sweep_*.txt
echo done

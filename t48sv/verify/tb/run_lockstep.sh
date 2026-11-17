#!/bin/bash
# run_lockstep.sh: long random lockstep campaign over all configurations
# chunks of 50 runs x 200k cycles (10M cycles), seeds distinct per chunk
HERE=$(cd "$(dirname "$0")" && pwd)
RES=$HERE/../results
mkdir -p $RES
jobs=()
while read cfg; do
  case $cfg in A_extrom_g0_r7|A_extrom_g0_r6|A_core|B_upi41_core|A_extrom_g1_r7|A_extrom_g0_r8) n=5;; *) n=1;; esac
  for c in $(seq 1 $n); do
    for p in mixed; do jobs+=("$cfg $c $p"); done
  done
done < $HERE/all_cfgs.txt
printf '%s\n' "${jobs[@]}" | xargs -P 4 -L 1 bash -c 'cd '$HERE'/build/$0 && ./Vlockstep --runs 50 --cycles 200000 --seed $((1000+$1)) --prog $2 --quiet > '$RES'/lock_$0_$1.txt 2>&1'
cat $RES/lock_*.txt | grep RESULT > $RES/lockstep_summary.txt
grep -l MISMATCH $RES/lock_*.txt
echo done

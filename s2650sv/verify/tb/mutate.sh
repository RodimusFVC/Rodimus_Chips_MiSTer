#!/bin/bash
# Mutation check: every mutant of s2650sv must be caught by the directed sweep, the random lockstep, and
# (where the mutation changes architectural results) the exerciser run on the mutant alone.
cd "$(dirname "$0")"
for k in $(python3 mutants.py); do
  ( ./build1.sh a 1 mut/$k.sv _$k && \
    s=$(./lockstep_a_m1_$k sweep 1 | grep -c "^MISMATCH"); \
    r=$(./lockstep_a_m1_$k random 3 3000000 | grep -c "^MISMATCH"); \
    e=$(DUTBUS=1 ./lockstep_a_m1_$k prog ../exerciser/exerciser.bin 20000000 3 | grep -o "result [A-Z]*"); \
    echo "$k: sweep $([ $s -gt 0 ] && echo CAUGHT || echo missed), random $([ $r -gt 0 ] && echo CAUGHT || echo missed), exerciser $e"; \
    rm -rf obj_a_m1_$k lockstep_a_m1_$k ) &
  while [ $(jobs -r | wc -l) -ge 4 ]; do sleep 5; done
done
wait

#!/bin/sh
# mutate.sh [mutant-list]: inject single bugs into a copy of t65sv.sv and confirm the lockstep harness flags each one.
cd "$(dirname "$0")"; V=$(pwd)
mkdir -p build/mut
i=0
while IFS='@' read -r name from to; do
  case "$name" in \#*) continue;; esac
  [ -z "$name" ] && continue
  i=$((i+1))
  sed "s/$from/$to/" ../rtl/t65sv.sv > build/mut/t65sv.sv
  if cmp -s build/mut/t65sv.sv ../rtl/t65sv.sv; then echo "MUT $i $name: pattern not found"; continue; fi
  verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style -Mdir build/mut/obj -o ../lockstep_mut \
    --top-module lockstep_top $V/ref/ref_T65.v $V/build/mut/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_T65.sv $V/tb/lockstep_top.sv \
    $V/tb/lockstep.cpp > build/mut/build.log 2>&1 || { echo "MUT $i $name: build failed"; continue; }
  r=$(./build/mut/lockstep_mut random 3 2000000 | tail -1)
  case "$r" in *"mismatches=0 "*) ;; *) echo "MUT $i $name: detected by random stream"; continue;; esac
  r=$(./build/mut/lockstep_mut sweep | tail -1)
  case "$r" in *"mismatches=0 "*) echo "MUT $i $name: NOT DETECTED";; *) echo "MUT $i $name: detected by directed sweep";; esac
done < "${1:-mutants1.txt}"

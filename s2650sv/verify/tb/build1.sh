#!/bin/bash
# build one variant: build1.sh a|b 1|0 [rtl-file] [suffix]
set -e
cd "$(dirname "$0")"
V=$1; M=$2; RTLF=${3:-../../rtl/s2650sv.sv}; SUF=${4:-}
if [ $V = a ]; then VB=0; else VB=1; fi
if [ $M = 1 ]; then NM=2650${V^^}; else NM=2650${V^^}-rasregs; fi
O=obj_${V}_m$M$SUF
verilator --cc --exe --build -O3 --threads 1 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  --top-module tb_top -GVER_B=$VB -GRAS_MLAB=$M -CFLAGS "-O2 -DVARIANT_NAME=\\\"$NM$SUF\\\"" \
  -Mdir $O $RTLF ../refmodel/ref_a.v ../refmodel/ref_b_core.v ref_b_cpu.v tb_top.sv lockstep.cpp \
  -o lockstep >/dev/null
cp $O/lockstep lockstep_${V}_m$M$SUF

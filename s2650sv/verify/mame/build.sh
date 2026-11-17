#!/bin/bash
# Build the MAME comparison harness (needs a MAME checkout: MAME_DIR, default ../../../ref/mame)
set -e
cd "$(dirname "$0")"
MAME_DIR=${MAME_DIR:-$(cd ../../../ref/mame && pwd)}
S=$MAME_DIR/src/devices/cpu/s2650/s2650.cpp
verilator --cc --exe --build -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style --top-module tb_top \
  -CFLAGS "-O2 -std=c++17 -I$(pwd)/stub -I$(pwd) $EXTRA -DMAME_S2650_CPP='\"$S\"'" -Mdir obj$SUF \
  ../../rtl/s2650sv.sv ../refmodel/ref_a.v ../refmodel/ref_b_core.v ../tb/ref_b_cpu.v ../tb/tb_top.sv mamecmp.cpp \
  -o mamecmp >/dev/null
cp obj$SUF/mamecmp ./mamecmp$SUF

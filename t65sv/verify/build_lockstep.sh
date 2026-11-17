#!/bin/sh
# Builds verify/build/lockstep (oracle + t65sv in one Verilator model).
set -e
cd "$(dirname "$0")"; V=$(pwd)
[ -f ref/ref_T65.v ] || ref/gen_ref.sh
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style \
  -Mdir build/obj_lockstep -o ../lockstep --top-module lockstep_top \
 $V/ref/ref_T65.v $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_T65.sv $V/tb/lockstep_top.sv $V/tb/lockstep.cpp \
  -CFLAGS "-O2" > build/lockstep_build.log 2>&1 || { tail -30 build/lockstep_build.log; exit 1; }
echo built build/lockstep

#!/bin/bash
# build.sh <variant 0..3> <rev 0|1> : MAME mcs48.cpp (unmodified) + Verilated t48sv
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$HERE/../../rtl
MAME=${MAME:-/home/user/up/mame}
V=$1; R=$2; OUT=$HERE/build/v${V}_r${R}
mkdir -p $OUT
cp $MAME/mcs48.cpp $MAME/mcs48.h $OUT/
cat > $OUT/mcs48dsm.h <<'X'
// stub: the harness does not use the disassembler
#pragma once
class mcs48_disassembler : public util::disasm_interface { public: mcs48_disassembler(bool, bool) {} };
X
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
  --top-module mame_dut -GVARIANT=$V -GREV2023=$R -Mdir $OUT/obj -CFLAGS "-O2 -std=c++20 -I$HERE/shim -I$OUT" \
  $RTL/t48sv_blocks.sv $RTL/t48sv_decoder.sv $RTL/t48sv_core.sv $HERE/mame_dut.sv \
  $HERE/mame_cmp.cpp $OUT/mcs48.cpp -o $OUT/mame_cmp > $OUT/build.log 2>&1 || { grep -m20 error $OUT/build.log; exit 1; }
echo built $OUT/mame_cmp

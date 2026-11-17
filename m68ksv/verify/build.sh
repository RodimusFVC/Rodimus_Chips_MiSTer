#!/bin/bash
# Build the m68ksv suite runner and the directed tests: build.sh <build dir>  ->  <build dir>/harte, smoke, retry
# Regenerates the microcode / decode ROMs first (rtl/gen/m68ksv_ucode.py).
set -e
OUT=$(realpath -m "$1")
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
# M68KSV_CPU: the CPU parameter of the build (default 68000; 68008 / 68009 / 68001 = 68008 DIP48 / FN / 68EC000)
# M68KSV_RES: the RES parameter (0 = BRAM-heavy, the default; 1 = logic-heavy, checkpoint 6)
GC="-GCPU=${M68KSV_CPU:-68000} -GRES=${M68KSV_RES:-0}"
python3 "$RTL/gen/m68ksv_ucode.py"
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv_biu32.sv $RTL/m68ksv.sv"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK $GC --top-module m68ksv -Mdir "$OUT/obj" \
    -CFLAGS "-O2" -o harte $SRC "$HERE/tb/harte.cpp" > "$OUT/build.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/build.log"; exit 1; }
cp "$OUT/obj/harte" "$OUT/harte"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK $GC --top-module m68ksv -Mdir "$OUT/sobj" \
    -CFLAGS "-O2" -o smoke $SRC "$HERE/tb/smoke.cpp" > "$OUT/sbuild.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/sbuild.log"; exit 1; }
cp "$OUT/sobj/smoke" "$OUT/smoke"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK $GC --top-module m68ksv -Mdir "$OUT/robj" \
    -CFLAGS "-O2" -o retry $SRC "$HERE/tb/retry.cpp" > "$OUT/rbuild.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/rbuild.log"; exit 1; }
cp "$OUT/robj/retry" "$OUT/retry"
echo "built $OUT/harte $OUT/smoke $OUT/retry"

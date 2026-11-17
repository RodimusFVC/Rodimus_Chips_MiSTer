#!/bin/bash
# Build the 68010 lockstep against MAME's Musashi (tb/mus010.cpp) and the bus-error continuation self-check
# (tb/rerun010.cpp): mus010_build.sh <build dir>
# Verilator 4.204 (PATH default), CPU = 68010; the Musashi model is built first (musashi/build.sh, MAME source
# read-only). Run: <build dir>/mus010 -seed N -runs N -instr N [-irq] [-w W] <suite .bin ...>
# M68KSV_RES=1: build the logic-heavy setting (parameter RES, checkpoint 6; default 0)
set -e
OUT=$(realpath -m "$1")
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
"$HERE/musashi/build.sh" "$OUT/mus" > /dev/null
python3 "$RTL/gen/m68ksv_ucode.py" > /dev/null
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv.sv"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=68010 \
    +define+M68KSV_TESTLOAD --top-module m68ksv -Mdir "$OUT/obj" -CFLAGS "-O2 -std=c++20 -I$HERE/musashi -I$HERE/tb" \
    -o mus010 $SRC "$HERE/tb/mus010.cpp" "$OUT/mus/libmusashi.a" > "$OUT/build.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/build.log"; exit 1; }
cp "$OUT/obj/mus010" "$OUT/mus010"
# bus error + RTE continuation self-check (two m68ksv instances, no Musashi)
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=68010 \
    +define+M68KSV_TESTLOAD --top-module m68ksv -Mdir "$OUT/robj" -CFLAGS "-O2 -std=c++20 -I$HERE/tb" \
    -o rerun010 $SRC "$HERE/tb/rerun010.cpp" > "$OUT/rbuild.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/rbuild.log"; exit 1; }
cp "$OUT/robj/rerun010" "$OUT/rerun010"
# loop-mode directed test (no Musashi)
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=68010 \
    --top-module m68ksv -Mdir "$OUT/lobj" -CFLAGS "-O2 -std=c++20 -I$HERE/tb" \
    -o loop010 $SRC "$HERE/tb/loop010.cpp" > "$OUT/lbuild.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/lbuild.log"; exit 1; }
cp "$OUT/lobj/loop010" "$OUT/loop010"
echo "built $OUT/mus010 $OUT/rerun010 $OUT/loop010"

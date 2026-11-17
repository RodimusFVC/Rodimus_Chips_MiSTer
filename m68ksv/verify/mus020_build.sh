#!/bin/bash
# Build the 68020 / 68EC020 lockstep against MAME's Musashi (tb/mus020.cpp): mus020_build.sh <build dir> [cpu]
# Verilator 4.204 (PATH default), CPU = 68020 (or 68021 = 68EC020, run with -ec); the Musashi model is built first
# (musashi/build020.sh, MAME source read-only). Run: <build dir>/mus020 -seed N -runs N -instr N [-irq] [-w W] <suite .bin ...>
# Also builds rerun020 (bus error + RTE continuation self-check): <build dir>/rerun020_<cpu> -seed N -runs N -instr N -p P <suite .bin ...>
# M68KSV_RES=1: build the logic-heavy setting (parameter RES, checkpoint 6; default 0)
set -e
OUT=$(realpath -m "$1")
CPU=${2:-68020}
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
"$HERE/musashi/build020.sh" "$OUT/mus" > /dev/null
python3 "$RTL/gen/m68ksv_ucode.py" > /dev/null
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv_biu32.sv $RTL/m68ksv.sv"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/obj$CPU" -CFLAGS "-O2 -std=c++20 -I$HERE/musashi -I$HERE/tb" \
    -o mus020 $SRC "$HERE/tb/mus020.cpp" "$OUT/mus/libmusashi020.a" > "$OUT/build$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/build$CPU.log"; exit 1; }
cp "$OUT/obj$CPU/mus020" "$OUT/mus020_$CPU"
# rerun020: the bus error + RTE continuation self-check (two m68ksv instances, no Musashi)
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/robj$CPU" -CFLAGS "-O2 -std=c++17 -I$HERE/tb" \
    -o rerun020 $SRC "$HERE/tb/rerun020.cpp" > "$OUT/rbuild$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/rbuild$CPU.log"; exit 1; }
cp "$OUT/robj$CPU/rerun020" "$OUT/rerun020_$CPU"
echo "built $OUT/mus020_$CPU $OUT/rerun020_$CPU"

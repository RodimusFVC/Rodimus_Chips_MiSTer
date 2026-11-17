#!/bin/bash
# Build the 8-bit-bus lockstep against MAME's m68008 (tb/mame8.cpp): mame8_build.sh <build dir> [CPU]
#   CPU: 68008 (default, DIP48), 68009 (68008FN), 68001 (68EC000, run with MODE = 0). Verilator 4.204 (PATH default).
# Builds the MAME model first (mame/build.sh <build dir>/mame; MAME source read-only, $MAME_M68K).
# M68KSV_RES=1: build the logic-heavy setting (parameter RES, checkpoint 6; default 0)
set -e
OUT=$(realpath -m "$1")
CPU=${2:-68008}
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
"$HERE/mame/build.sh" "$OUT/mame" > /dev/null
python3 "$RTL/gen/m68ksv_ucode.py" > /dev/null
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv.sv"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
    +define+M68KSV_TESTLOAD --top-module m68ksv -Mdir "$OUT/obj$CPU" -CFLAGS "-O2 -std=c++20 -I$HERE/mame" \
    -o mame8 $SRC "$HERE/tb/mame8.cpp" "$OUT/mame/libmame68k.a" > "$OUT/build$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/build$CPU.log"; exit 1; }
cp "$OUT/obj$CPU/mame8" "$OUT/mame8_$CPU"
echo "built $OUT/mame8_$CPU"

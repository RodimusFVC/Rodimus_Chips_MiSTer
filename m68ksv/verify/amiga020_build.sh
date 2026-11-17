#!/bin/bash
# Build the 68020 behaviour harness (tb/amiga020.cpp: the Amiberry / WinUAE cases of verify/amiga020, REPORT.md "68020
# behaviour from WinUAE"): amiga020_build.sh <build dir> [cpu] -> <build dir>/amiga020_<cpu>; run it with no arguments
# (-v: every check). Verilator as dsz020_build.sh (the one on PATH, 4.204).
# M68KSV_RES=1: build the logic-heavy setting (parameter RES, checkpoint 6; default 0)
set -e
OUT=$(realpath -m "$1")
CPU=${2:-68020}
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
python3 "$RTL/gen/m68ksv_ucode.py" > /dev/null
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv_biu32.sv $RTL/m68ksv.sv"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/aobj$CPU" -CFLAGS "-O2 -std=c++17 -DM68KSV_HCPU=$CPU" \
    -o amiga020 $SRC "$HERE/tb/amiga020.cpp" > "$OUT/abuild$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/abuild$CPU.log"; exit 1; }
cp "$OUT/aobj$CPU/amiga020" "$OUT/amiga020_$CPU"
echo "built $OUT/amiga020_$CPU"

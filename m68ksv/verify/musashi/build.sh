#!/bin/bash
# Build the standalone Musashi 68010 model (MAME's Musashi, compiled unmodified with the harness shim):
#   build.sh <out dir>  ->  <out dir>/libmusashi.a
# MAME source (read-only oracle): $MAME_M68K or the vault's MAME tree; softfloat3 headers from its 3rdparty folder.
set -e
OUT=$(realpath -m "$1")
HERE=$(dirname "$(realpath "$0")")
MS=${MAME_SRC:-/Work/Projects/ZZZ_Obsidian_FPGA/FPGA-Brain/Projects/Mame_Source}
M=${MAME_M68K:-$MS/src/devices/cpu/m68000}
mkdir -p "$OUT"
CX="g++ -std=c++20 -O1 -fPIC -w -I $HERE/shim -I $M -I $MS/3rdparty"
$CX -c "$HERE/musashi_model.cpp" -o "$OUT/musashi_model.o" &
[ "$OUT/m68kcpu.o" -nt "$M/m68kcpu.cpp" ] || $CX -c "$M/m68kcpu.cpp" -o "$OUT/m68kcpu.o" &
[ "$OUT/m68kops.o" -nt "$M/m68kops.cpp" ] || $CX -c "$M/m68kops.cpp" -o "$OUT/m68kops.o" &
[ "$OUT/m68010.o" -nt "$M/m68010.cpp" ] || $CX -c "$M/m68010.cpp" -o "$OUT/m68010.o" &
wait
rm -f "$OUT/libmusashi.a"
ar rcs "$OUT/libmusashi.a" "$OUT/musashi_model.o" "$OUT/m68kcpu.o" "$OUT/m68kops.o" "$OUT/m68010.o"
echo "built $OUT/libmusashi.a"

#!/bin/bash
# Build the standalone MAME m68000 / m68008 model and its suite runner:  build.sh <out dir>
#   -> <out dir>/libmame68k.a (model, linked into other harnesses), <out dir>/mamesuite
# MAME source (read-only oracle, compiled unmodified): $MAME_M68K or the vault's MAME tree below.
set -e
OUT=$(realpath -m "$1")
HERE=$(dirname "$(realpath "$0")")
M=${MAME_M68K:-/Work/Projects/ZZZ_Obsidian_FPGA/FPGA-Brain/Projects/Mame_Source/src/devices/cpu/m68000}
mkdir -p "$OUT"
CX="g++ -std=c++20 -O1 -fPIC -I $HERE/shim -I $M"
$CX -c "$HERE/mame_model.cpp" -o "$OUT/mame_model.o"
[ "$OUT/sdf.o" -nt "$M/m68000-sdf.cpp" ] || $CX -c "$M/m68000-sdf.cpp" -o "$OUT/sdf.o" &
[ "$OUT/sdf8.o" -nt "$M/m68008-sdf8.cpp" ] || $CX -c "$M/m68008-sdf8.cpp" -o "$OUT/sdf8.o" &
[ "$OUT/decode.o" -nt "$M/m68000-decode.cpp" ] || $CX -c "$M/m68000-decode.cpp" -o "$OUT/decode.o" &
wait
rm -f "$OUT/libmame68k.a"
ar rcs "$OUT/libmame68k.a" "$OUT/mame_model.o" "$OUT/sdf.o" "$OUT/sdf8.o" "$OUT/decode.o"
g++ -std=c++20 -O2 "$HERE/mamesuite.cpp" "$OUT/libmame68k.a" -o "$OUT/mamesuite"
echo "built $OUT/libmame68k.a $OUT/mamesuite"

#!/bin/bash
# Build the fx68k suite probe (tb/fxprobe.cpp): fx68k_build.sh <fx68k source dir> <build dir>
# fx68k (github.com/ijor/fx68k, vendor copy, never edited) is built with Verilator 5.052 (/usr/bin/verilator):
# --no-assert (fx68kAlu.sv:313 trips a unique-case assertion at reset), -Wno-BLKANDNBLK, --public-flat-rw (the probe
# reads fx68k's registers). The fleet-default Verilator 4.204 on PATH builds fx68k too, but that model never starts a
# bus cycle; the m68ksv suite runner (build.sh) stays on 4.204.
# fx68k reads microrom.mem / nanorom.mem from the current directory: they are copied into the build dir and
# run via  fx68k_run.sh <build dir> [fxprobe options] <suite .bin files>.
set -e
FX=$(realpath "$1")
OUT=$(realpath -m "$2")
HERE=$(dirname "$(realpath "$0")")
VL=${VERILATOR5:-/usr/bin/verilator}
mkdir -p "$OUT"
# optional: MAMELIB=<dir with libmame68k.a from verify/mame/build.sh> adds the -mame mode (fx68k vs the MAME model)
EXTRA=""
if [ -n "$MAMELIB" ]; then EXTRA="-CFLAGS -DFX_MAME -CFLAGS -I$HERE/mame -CFLAGS -std=c++20 $(realpath "$MAMELIB")/libmame68k.a"; fi
"$VL" --version | grep -q "^Verilator 5" || { echo "need Verilator 5 at $VL (set VERILATOR5)"; exit 1; }
"$VL" --cc --exe --build -j 4 -O3 --no-assert --x-assign 0 --x-initial 0 -Wno-fatal -Wno-BLKANDNBLK -Wno-lint \
    -Wno-style --public-flat-rw --top-module fx68k -Mdir "$OUT/obj" -CFLAGS "-O2" -o fxprobe \
    "$FX/fx68k.sv" "$FX/fx68kAlu.sv" "$FX/uaddrPla.sv" "$HERE/tb/fxprobe.cpp" $EXTRA > "$OUT/build.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/build.log"; exit 1; }
cp "$OUT/obj/fxprobe" "$OUT/fxprobe"
cp "$FX/microrom.mem" "$FX/nanorom.mem" "$OUT/"
echo "built $OUT/fxprobe"

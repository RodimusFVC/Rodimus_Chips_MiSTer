#!/bin/bash
# Build the m68ksv / fx68k lockstep harness (tb/lockstep.cpp): lockstep_build.sh <fx68k source dir> <build dir>
# (M68KSV_CPU=68001: the 68EC000, run with MODE = 1, i.e. its 16-bit bus, against fx68k)
# Both cores are Verilated with Verilator 5.052 (/usr/bin/verilator; fx68k does not run under 4.204, see
# fx68k_build.sh) into separate model libraries (--prefix Vfx68k / Vm68ksv) and linked into one binary with one
# Verilator runtime. The m68ksv suite runner (build.sh) stays on Verilator 4.204. fx68k reads microrom.mem /
# nanorom.mem from the current directory: run from the build dir (lockstep_run.sh).
set -e
FX=$(realpath "$1")
OUT=$(realpath -m "$2")
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
VL=${VERILATOR5:-/usr/bin/verilator}
mkdir -p "$OUT"
"$VL" --version | grep -q "^Verilator 5" || { echo "need Verilator 5 at $VL (set VERILATOR5)"; exit 1; }
python3 "$RTL/gen/m68ksv_ucode.py" > /dev/null
COM="-O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -CFLAGS -O2"
"$VL" --cc --build -j 4 $COM --no-assert -Wno-BLKANDNBLK --public-flat-rw --top-module fx68k --prefix Vfx68k \
    -Mdir "$OUT/fx" "$FX/fx68k.sv" "$FX/fx68kAlu.sv" "$FX/uaddrPla.sv" > "$OUT/fx.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/fx.log"; exit 1; }
SRC="$RTL/m68ksv_upkg.sv $RTL/m68ksv_alu.sv $RTL/m68ksv_urom.sv $RTL/m68ksv_drom.sv $RTL/m68ksv_rf.sv $RTL/m68ksv_eu.sv $RTL/m68ksv_biu.sv $RTL/m68ksv.sv"
"$VL" --cc --build -j 4 $COM --public-flat-rw -GCPU=${M68KSV_CPU:-68000} -GRES=${M68KSV_RES:-0} --top-module m68ksv --prefix Vm68ksv -Mdir "$OUT/mv" $SRC > "$OUT/mv.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/mv.log"; exit 1; }
VI=$(dirname "$("$VL" --getenv VERILATOR_ROOT 2>/dev/null)/include/verilated.h")
[ -f "$VI/verilated.h" ] || VI=/usr/share/verilator/include
g++ -std=c++20 -O2 -I "$OUT/fx" -I "$OUT/mv" -I "$VI" -I "$VI/vltstd" "$HERE/tb/lockstep.cpp" \
    "$OUT/fx/Vfx68k__ALL.a" "$OUT/mv/Vm68ksv__ALL.a" "$VI/verilated.cpp" "$VI/verilated_threads.cpp" \
    -o "$OUT/lockstep" -lpthread -latomic > "$OUT/link.log" 2>&1 || { head -30 "$OUT/link.log"; exit 1; }
cp "$FX/microrom.mem" "$FX/nanorom.mem" "$OUT/"
echo "built $OUT/lockstep"

#!/bin/bash
# Build the directed 68020 tests: dynamic bus sizing (tb/dsz020.cpp), instruction cache (tb/cache020.cpp), RMC lock
# (tb/rmc020.cpp), coprocessor interface (tb/cop020.cpp) and instruction times vs the User's Manual (tb/tim020.cpp, cp5):
# dsz020_build.sh <build dir> [cpu] -> <build dir>/dsz020_<cpu>, cache020_<cpu>, rmc020_<cpu>, cop020_<cpu>, tim020_<cpu>
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
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/dobj$CPU" -CFLAGS "-O2 -std=c++17 -DM68KSV_HCPU=$CPU" \
    -o dsz020 $SRC "$HERE/tb/dsz020.cpp" > "$OUT/dbuild$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/dbuild$CPU.log"; exit 1; }
cp "$OUT/dobj$CPU/dsz020" "$OUT/dsz020_$CPU"
verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
    +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/cobj$CPU" -CFLAGS "-O2 -std=c++17 -DM68KSV_HCPU=$CPU" \
    -o cache020 $SRC "$HERE/tb/cache020.cpp" > "$OUT/cbuild$CPU.log" 2>&1 \
    || { grep -m10 -A3 "%Error\|error" "$OUT/cbuild$CPU.log"; exit 1; }
cp "$OUT/cobj$CPU/cache020" "$OUT/cache020_$CPU"
for T in rmc020 cop020 tim020; do
  [ -f "$HERE/tb/$T.cpp" ] || continue
  verilator --cc --exe --build -j 4 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -GRES=${M68KSV_RES:-0} -GCPU=$CPU \
      +define+M68KSV_TESTLOAD +define+M68KSV_SIMCHECK --top-module m68ksv -Mdir "$OUT/${T}obj$CPU" -CFLAGS "-O2 -std=c++17 -DM68KSV_HCPU=$CPU" \
      -o $T $SRC "$HERE/tb/$T.cpp" > "$OUT/${T}build$CPU.log" 2>&1 \
      || { grep -m10 -A3 "%Error\|error" "$OUT/${T}build$CPU.log"; exit 1; }
  cp "$OUT/${T}obj$CPU/$T" "$OUT/${T}_$CPU"
done
echo "built $OUT/dsz020_$CPU $OUT/cache020_$CPU $OUT/rmc020_$CPU"

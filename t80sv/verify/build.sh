#!/bin/bash
# Build the lockstep simulator for one configuration (verify/configs.py):
#   build.sh <config> <reference model dir> <build dir>
set -e
#   build.sh <config> <reference model dir> <build dir> [ref|dut]   (solo: one model only, for long programs)
CFG=$1; REFV=$(realpath "$2"); SOLO=$4; OUT=$(realpath -m "$3")/$CFG${SOLO:+_$SOLO}
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
REFCFG=$(cd "$HERE" && python3 -c "from configs import FLEET_WRAPPERS as F; print(F['$CFG'][0] if '$CFG' in F else '$CFG')")
python3 "$HERE/tb/tbgen.py" "$CFG" "$OUT" "$REFV/ref_$REFCFG.v" $SOLO
verilator --cc --exe --build -j 1 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module tb -Mdir "$OUT/obj" -CFLAGS "-O2 -I$OUT" -o sim \
    "$HERE/tb/chip_pool_pkg.sv" "$OUT/tb.sv" "$REFV/ref_$REFCFG.v" "$RTL/t80sv_fleet.sv" "$RTL/t80sv_tops.sv" "$RTL/t80sv.sv" "$RTL/t80sv_core.sv" "$RTL/t80sv_alu.sv" \
    "$RTL/t80sv_mcode.sv" "$HERE/tb/sim.cpp" > "$OUT/build.log" 2>&1 || { grep -m5 -A3 "%Error" "$OUT/build.log"; tail -5 "$OUT/build.log"; exit 1; }
echo "built $OUT/obj/sim"

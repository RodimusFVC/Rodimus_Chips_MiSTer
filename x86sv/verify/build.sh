#!/bin/bash
# Build the SingleStepTests runner, the directed tests and the fleet wrapper test: build.sh <build dir> [config]
#   config: 8088 (default) | 8086 | v20 | v30 | v20e | v30e (NEC8080 on)   -> <build dir>/sim (all configs), dsim, fleet
#   (8088 build); v20e / v30e also s80 (8080-mode suite runner) and x80 (8080 exercisers, directed 8080-mode tests)
set -e
OUT=$(realpath -m "$1")
CFG=${2:-8088}
HERE=$(dirname "$(realpath "$0")")
RTL=$HERE/../rtl
mkdir -p "$OUT"
case "$CFG" in
8088) VDEF=(); CDEF="" ;;
8086) VDEF=(+define+TB_BUS16); CDEF="-DBUS16" ;;
v20)  VDEF=(+define+TB_NEC); CDEF="-DNEC" ;;
v30)  VDEF=(+define+TB_BUS16 +define+TB_NEC); CDEF="-DBUS16 -DNEC" ;;
v20e) VDEF=(+define+TB_NEC +define+TB_E8); CDEF="-DNEC -DE8" ;;
v30e) VDEF=(+define+TB_BUS16 +define+TB_NEC +define+TB_E8); CDEF="-DBUS16 -DNEC -DE8" ;;
*) echo "unknown config $CFG"; exit 1 ;;
esac
echo "$CFG" > "$OUT/cfg"
"$HERE/tools/mkall.sh"
verilator --cc --exe --build -j 2 -O3 --x-assign 0 --x-initial 0 -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED \
    +define+X86SV_TESTLOAD "${VDEF[@]}" --top-module tb_x86 -Mdir "$OUT/obj" \
    -CFLAGS "-O2 -fno-strict-aliasing -I$HERE/tb $CDEF" -LDFLAGS "-lz" -o sim \
    "$RTL/x86sv_all.sv" "$HERE/tb/tb_x86.sv" "$HERE/tb/sim.cpp" \
    > "$OUT/build.log" 2>&1 || { grep -m10 -A3 "%Error" "$OUT/build.log"; tail -5 "$OUT/build.log"; exit 1; }
grep "%Warning" "$OUT/build.log" | head -40 || true
cp "$OUT/obj/sim" "$OUT/sim"
case "$CFG" in
v20e|v30e)
    for t in s80 x80; do
        verilator --cc --exe --build -j 2 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
            +define+X86SV_TESTLOAD "${VDEF[@]}" --top-module tb_x86 -Mdir "$OUT/${t}obj" \
            -CFLAGS "-O2 -fno-strict-aliasing -I$HERE/tb $CDEF" -LDFLAGS "-lz" -o $t \
            "$RTL/x86sv_all.sv" "$HERE/tb/tb_x86.sv" "$HERE/tb/$t.cpp" \
            > "$OUT/${t}build.log" 2>&1 || { grep -m10 -A3 "%Error\|error" "$OUT/${t}build.log"; exit 1; }
        cp "$OUT/${t}obj/$t" "$OUT/$t"
    done ;;
esac
[ "$CFG" = 8088 ] || { echo "built $OUT/sim ($CFG)"; exit 0; }
verilator --cc --exe --build -j 2 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    +define+X86SV_TESTLOAD --top-module tb_x86 -Mdir "$OUT/dobj" -CFLAGS "-O2 -fno-strict-aliasing -I$HERE/tb" -o dsim \
    "$RTL/x86sv_all.sv" "$HERE/tb/tb_x86.sv" "$HERE/tb/dsim.cpp" \
    > "$OUT/dbuild.log" 2>&1 || { grep -m10 -A3 "%Error\|error" "$OUT/dbuild.log"; exit 1; }
cp "$OUT/dobj/dsim" "$OUT/dsim"
# fleet wrappers: compiled against a copy of the master chip_pool_pkg (read only) with the proposed types appended
PKG=${X86SV_PKG:-/Work/Projects/RodimusCoresMaster_MiSTer/rtl/chip_pool_pkg.sv}
{ grep -v "^endpackage" "$PKG"; sed -n '/^\/\/ ---- to merge ----/,$p' "$HERE/../fleet_types.svh"; echo "endpackage"; } \
    > "$OUT/chip_pool_pkg.sv"
verilator --cc --exe --build -j 2 -O3 --x-assign 0 --x-initial 0 -Wno-fatal -Wno-lint -Wno-style \
    --top-module tb_fleet -Mdir "$OUT/fobj" -CFLAGS "-O2 -fno-strict-aliasing" -o fleet "$OUT/chip_pool_pkg.sv" \
    "$RTL/x86sv_all.sv" "$RTL/x86sv_fleet.sv" "$HERE/tb/tb_fleet.sv" "$HERE/tb/fleet.cpp" \
    > "$OUT/fbuild.log" 2>&1 || { grep -m10 -A3 "%Error\|error" "$OUT/fbuild.log"; exit 1; }
cp "$OUT/fobj/fleet" "$OUT/fleet"
g++ -O2 -o "$OUT/mooview" "$HERE/tb/mooview.cpp" -lz
g++ -O2 -o "$OUT/mooscan" "$HERE/tb/mooscan.cpp" -lz
g++ -O2 -o "$OUT/moocsv" "$HERE/tb/moocsv.cpp" -lz
g++ -O2 -o "$OUT/moofloat" "$HERE/tb/moofloat.cpp" -lz
echo "built $OUT/sim"

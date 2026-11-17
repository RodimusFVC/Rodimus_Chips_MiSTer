#!/bin/bash
# Regenerate the suite corrections file (expected results where fx68k and MAME agree against the SingleStepTests
# suite, see REPORT.md "fx68k vs suite vs MAME: verdicts") from scratch:
#   make_corrections.sh <work dir> [<output file>]
# Everything lands in <work dir> (downloads, converted suite, builds); the output defaults to
# <work dir>/suite_corrections.txt. Steps, each skipped when its result already exists:
#   1. download the suite (commit pinned below) and fx68k (commit pinned below) as GitHub archive zips, each into its
#      own new empty folder (downloaded data: Python reading it runs with -I, nothing is executed from those folders)
#   2. convert the suite JSON to the harness binary (tools/conv_harte.py)
#   3. build the MAME m68000 model (mame/build.sh; MAME source read-only, $MAME_M68K) and fxprobe with it (Verilator 5)
#   4. run fxprobe -mame -x suite_exclusions.txt -emit on every suite file (excluded tests are not emitted) (in parallel, $JOBS, default 8) and concatenate in file order
# Needs: curl, unzip, python3, g++, Verilator 5 (/usr/bin/verilator or $VERILATOR5).
set -e
W=$(realpath -m "$1")
OUT=$(realpath -m "${2:-$W/suite_corrections.txt}")
HERE=$(dirname "$(realpath "$0")")
SUITE_REF=e0d5ece9670205cc84a0101081837deb446f86a3
FX_REF=0602ee4627b10f301298f2673d826cdd6baa9327
JOBS=${JOBS:-8}
mkdir -p "$W"
if [ ! -d "$W/suite/680x0-$SUITE_REF/68000/v1" ]; then
    mkdir -p "$W/suite"
    curl -sSL -o "$W/suite/suite.zip" "https://github.com/SingleStepTests/680x0/archive/$SUITE_REF.zip"
    unzip -q -o "$W/suite/suite.zip" "680x0-$SUITE_REF/68000/v1/*" -d "$W/suite"
fi
if [ ! -f "$W/fx68k/fx68k-$FX_REF/fx68k.sv" ]; then
    mkdir -p "$W/fx68k"
    curl -sSL -o "$W/fx68k/fx68k.zip" "https://github.com/ijor/fx68k/archive/$FX_REF.zip"
    unzip -q -o "$W/fx68k/fx68k.zip" -d "$W/fx68k"
fi
if [ ! -f "$W/bin/UNLINK.bin" ]; then
    python3 -I "$HERE/tools/conv_harte.py" "$W/suite/680x0-$SUITE_REF/68000/v1" "$W/bin"
fi
"$HERE/mame/build.sh" "$W/mame" > /dev/null
MAMELIB="$W/mame" "$HERE/fx68k_build.sh" "$W/fx68k/fx68k-$FX_REF" "$W/fxprobe" > /dev/null
mkdir -p "$W/emit"
ls "$W/bin"/*.bin | xargs -P "$JOBS" -I{} sh -c \
    'b=$(basename {} .bin); cd "'"$W/fxprobe"'" && ./fxprobe -mame -x "'"$HERE/suite_exclusions.txt"'" -emit "'"$W/emit"'/$b.txt" {} > "'"$W/emit"'/$b.log"'
: > "$OUT"
for f in "$W/bin"/*.bin; do cat "$W/emit/$(basename "$f" .bin).txt" >> "$OUT"; done
echo "$(wc -l < "$OUT") corrections -> $OUT"

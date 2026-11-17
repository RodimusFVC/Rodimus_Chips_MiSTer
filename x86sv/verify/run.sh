#!/bin/bash
# Run SingleStepTests files against x86sv:
#   run.sh <build dir> <all | file names (e.g. 88 80.0)> [sim options]
# Test data: $X86SV_TESTS or the suite of the build's config (<build dir>/cfg: 8088 v2, 8086 v1). X86SV_JOBS (default 2) files in parallel; per-file table, then TOTAL.
# drift = tests in which floating AD7-AD0 drifted during a long idle (accepted, see REPORT.md); lane = 8086: tests in
# which only the inactive half of AD15-0 after a single-lane write differed (masked per the suite README, BHE).
B=$(realpath "$1"); shift
S=/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/x86
case "$(cat "$B/cfg" 2>/dev/null)" in
8086) D=$S/SingleStepTests_8086/v1_binary ;;
v20|v30|v20e|v30e) D=$S/SingleStepTests_V20/v1_native_binary ;;
*)    D=$S/SingleStepTests_8088/v2_binary ;;
esac
T=${X86SV_TESTS:-$D}
SEL=$1; shift
case "$SEL" in
all|"") L=(); for f in "$T"/*.MOO.gz; do n=$(basename "$f"); L+=("${n%.MOO.gz}"); done ;;
*)  L=("$SEL"); while [ $# -gt 0 ] && [ "${1:0:1}" != "-" ]; do L+=("$1"); shift; done ;;
esac
OPTS=("$@")
for n in "${L[@]}"; do echo "$n"; done | xargs -P ${X86SV_JOBS:-2} -I{} sh -c 'S=$0; D=$1; shift; ulimit -v 8000000; "$S" -q "$@" "$D/{}.MOO.gz" | tail -n +2' "$B/sim" "$T" "${OPTS[@]}" > "$B/run.out"
printf "%-14s %6s %6s %6s %6s %6s %6s %6s %6s\n" file tests pass reg mem cycles bus drift lane
grep -v "^#\|^ " "$B/run.out" | sort -k1,1 | awk '{print; for(i=2;i<=9;i++) t[i]+=$i} END {printf "%-14s %6d %6d %6d %6d %6d %6d %6d %6d\n","TOTAL",t[2],t[3],t[4],t[5],t[6],t[7],t[8],t[9]}'
grep -q "^#" "$B/run.out" && { echo; grep "^#\|^   " "$B/run.out" | head -200; }
exit 0

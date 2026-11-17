#!/bin/bash
# Rebuild and run the whole 68000 suite: run_all.sh <build dir>
# Suite (binary, converted by tools/conv_harte.py): $M68KSV_TESTS or the scratchpad copy below.
# Output: <build dir>/run_all.txt (per-file table; excluded = tests listed in suite_exclusions.txt, see REPORT.md),
# <build dir>/run_gap3.txt (whole suite again with random idle clocks between the phase enables), smoke.txt.
set -e
HERE=$(dirname "$(realpath "$0")")
B=$(realpath -m "$1")
C=${M68KSV_CORR:-/tmp/claude-1000/-Work-Projects-ZZZ-Obsidian-FPGA-FPGA-Brain/97555d84-41d7-409a-8e87-284e3bd57fe7/scratchpad/m68ksv_refs/suite_corrections.txt}
T=${M68KSV_TESTS:-/tmp/claude-1000/-Work-Projects-ZZZ-Obsidian-FPGA-FPGA-Brain/97555d84-41d7-409a-8e87-284e3bd57fe7/scratchpad/m68ksv_refs/bin68000}
"$HERE/build.sh" "$B"
ls "$T"/*.bin | xargs -P "${M68KSV_JOBS:-4}" -n 8 sh -c 'ulimit -v 4000000; "$0" -x "'"$HERE"'/suite_exclusions.txt" -c "'"$C"'" "$@" | grep -v "^#\|^TOTAL"' "$B/harte" \
    | sort > "$B/run_all.body"
{ echo "# file tests pass regfail ramfail pffail timeout cyc_ok bus_ok excluded excl_corrected_ok timed_ok corrected corr_pass corr_timed";
  cat "$B/run_all.body";
  awk '{for(i=2;i<=15;i++) t[i]+=$i} END {printf "%-16s", "TOTAL"; for(i=2;i<=15;i++) printf " %6d", t[i]; printf "\n"}' "$B/run_all.body"; } > "$B/run_all.txt"
tail -1 "$B/run_all.txt"
# the same suite with 0-3 idle clocks between the phase enables (random): the core must not depend on enable spacing
# (pass / bus-order columns; the cycle column is not meaningful there, the test-load start shifts by a micro-cycle)
ls "$T"/*.bin | xargs -P "${M68KSV_JOBS:-4}" -n 8 sh -c 'ulimit -v 4000000; "$0" -gap 3 -x "'"$HERE"'/suite_exclusions.txt" -c "'"$C"'" "$@" | grep -v "^#\|^TOTAL"' "$B/harte" \
    | sort > "$B/run_gap3.body"
awk '{for(i=2;i<=15;i++) t[i]+=$i} END {printf "%-16s", "TOTAL gap 0-3"; for(i=2;i<=15;i++) printf " %6d", t[i]; printf "\n"}' "$B/run_gap3.body" \
    | tee "$B/run_gap3.txt"
"$B/smoke" | tee "$B/smoke.txt"
"$B/retry" | tee "$B/retry.txt"

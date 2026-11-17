#!/bin/bash
# The 68000 suite on the other 68000-bus members (checkpoint 2b): run_family.sh <build dir>
#   68008 (DIP48, 8-bit bus, 20 address pins), 68008FN (22 pins), 68EC000 with MODE = 0 (8-bit) and MODE = 1 (16-bit).
# Registers / RAM / prefetch queue must match the suite (corrections as run_all.sh); on the 8-bit bus the bus order is
# compared after merging byte pairs and the cycle count against the suite's + 4 per word access (MAME m68008's rule;
# the MAME 68008 lockstep, mame8_build.sh, checks it independently). The 68EC000 16-bit run is the full 68000 check.
# Output: <build dir>/<config>/run.txt per configuration, totals on stdout; also the directed retry test per config.
set -e
HERE=$(dirname "$(realpath "$0")")
B=$(realpath -m "$1")
C=${M68KSV_CORR:-/tmp/claude-1000/-Work-Projects-ZZZ-Obsidian-FPGA-FPGA-Brain/97555d84-41d7-409a-8e87-284e3bd57fe7/scratchpad/m68ksv_refs/suite_corrections.txt}
T=${M68KSV_TESTS:-/tmp/claude-1000/-Work-Projects-ZZZ-Obsidian-FPGA-FPGA-Brain/97555d84-41d7-409a-8e87-284e3bd57fe7/scratchpad/m68ksv_refs/bin68000}
run() {   # run <name> <cpu> <harte options...>
    local n=$1 cpu=$2; shift 2
    M68KSV_CPU=$cpu "$HERE/build.sh" "$B/$n" > /dev/null
    ls "$T"/*.bin | xargs -P "${M68KSV_JOBS:-4}" -n 8 sh -c 'ulimit -v 4000000; "$0" '"$*"' -x "'"$HERE"'/suite_exclusions.txt" -c "'"$C"'" "$@" | grep -v "^TOTAL"' "$B/$n/harte" \
        | sort > "$B/$n/run.body"
    grep "^# aliased" "$B/$n/run.body" | awk '{s+=$NF} END {printf "# aliased tests skipped: %d\n", s}' > "$B/$n/run.txt"
    grep -v "^#" "$B/$n/run.body" >> "$B/$n/run.txt"
    awk '!/^#/ {for(i=2;i<=15;i++) t[i]+=$i} END {printf "%-16s", "TOTAL"; for(i=2;i<=15;i++) printf " %6d", t[i]; printf "\n"}' "$B/$n/run.body" >> "$B/$n/run.txt"
    printf "%-22s " "$n"; tail -1 "$B/$n/run.txt"
    case "$*" in *-bus8*) "$B/$n/retry" -bus8 | tail -1 ;; *) "$B/$n/retry" | tail -1 ;; esac
}
echo "# config               file tests pass regfail ramfail pffail timeout cyc_ok bus_ok excluded excl_corrected_ok timed_ok corrected corr_pass corr_timed"
run m68008        68008 -bus8 -abits 20
run m68008fn      68009 -bus8 -abits 22
run m68ec000_8bit 68001 -bus8
run m68ec000_16   68001

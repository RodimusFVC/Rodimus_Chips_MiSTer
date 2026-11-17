#!/bin/bash
# Rebuild and re-run everything: run_all.sh <build dir>
#   8088: all 323 SingleStepTests 8088 v2 files (table in <build dir>/run_all.txt), the directed tests (dsim.txt) and
#   the fleet wrapper test (fleet.txt: all five wrappers); 8086: all 323 8086 v1 files (<build dir>/8086/run_all.txt);
#   V20 / V30: all 360 V20 v1 native files (<build dir>/v20/run_all.txt, <build dir>/v30/run_all.txt);
#   V20 / V30 with NEC8080 (<build dir>/v20e, v30e): the V20 native suite (run_all.txt), the 8080-mode suite
#   verify/suites/v20_8080 (s80.txt: registers, PSW incl. MD, MD write enable, RAM, I/O writes), the directed 8080-mode
#   tests (x80dir.txt) and the 8080 exercisers TST8080 / 8080PRE / CPUTEST in 8080 mode (x80com.txt); 8080EXM
#   (about 3 hours per configuration) only with X86SV_EXM=1. Exerciser .COM files: $X86SV_COM or the local copy.
set -e
HERE=$(dirname "$(realpath "$0")")
B=$(realpath -m "$1")
COM=${X86SV_COM:-/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/x86/docs/cpu_tests_altairclone}
for c in 8088 8086 v20 v30 v20e v30e; do
    D=$B; [ $c = 8088 ] || D=$B/$c
    "$HERE/build.sh" "$D" $c
done
"$HERE/run.sh" "$B" all | tee "$B/run_all.txt"
(ulimit -v 8000000; "$B/dsim") | tee "$B/dsim.txt"
(ulimit -v 8000000; "$B/fleet") | tee "$B/fleet.txt"
for c in 8086 v20 v30 v20e v30e; do "$HERE/run.sh" "$B/$c" all > "$B/$c/run_all.txt"; tail -1 "$B/$c/run_all.txt"; done
for c in v20e v30e; do
    (cd "$HERE/suites/v20_8080" && ls *.json.gz | xargs -P "${X86SV_JOBS:-2}" -n 33 sh -c 'ulimit -v 8000000; "$0" -q -s "$@"' "$B/$c/s80") \
        | sort > "$B/$c/s80.txt"
    awk '!/^#/ {t+=$2; p+=$3; r+=$4; m+=$5; i+=$6} END {printf "%s 8080-mode suite: %d / %d pass (reg %d ram %d io %d fails)\n", c, p, t, r, m, i}' c=$c "$B/$c/s80.txt"
    (ulimit -v 8000000; "$B/$c/x80" dir) > "$B/$c/x80dir.txt"; tail -1 "$B/$c/x80dir.txt"
    : > "$B/$c/x80com.txt"
    L="TST8080 8080PRE CPUTEST"; [ "$X86SV_EXM" = 1 ] && L="$L 8080EXM"
    for t in $L; do (ulimit -v 8000000; "$B/$c/x80" com "$COM/$t.COM") >> "$B/$c/x80com.txt"; done
    grep -a "^\[x80\]\|OPERATIONAL\|complete\|TESTS OK\|PASS\|ERROR\|FAIL" "$B/$c/x80com.txt" | sed "s/^/$c /"
done

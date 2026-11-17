#!/bin/bash
# Full regression: run_all.sh <build dir> <results dir>  (after gen_ref.py + build.sh for every config)
B=$1; R=$2; HERE=$(dirname "$(realpath "$0")")
for set in random sweep zexlock i8080 zexsolo_dut; do
    python3 "$HERE/run_jobs.py" "$B" "$R" $set 4 > "$R/summary_$set.txt" 2>&1
done
echo ALLDONE > "$R/ALLDONE"

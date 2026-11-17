#!/bin/sh
# VDC oracle campaign: N seeds x M scenarios, 4 in parallel; logs in results/vdc_seed*.log
cd "$(dirname "$0")"
N=${1:-4}; M=${2:-400}
seq 1 $N | xargs -P 4 -I{} sh -c "./build/vdc/vdc {} $M > results/vdc_seed{}.log 2>&1; echo seed {} exit \$?"
grep -h RESULT results/vdc_seed*.log

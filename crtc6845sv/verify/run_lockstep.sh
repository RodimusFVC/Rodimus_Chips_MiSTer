#!/bin/sh
# Long lockstep run: N seeds x C cycles, 4 in parallel. Logs in results/<prefix>_seed*.log (prefix default lockstep_final)
cd "$(dirname "$0")"
N=${1:-16}; C=${2:-60000000}; P=${3:-lockstep_final}
seq 1 $N | xargs -P 4 -I{} sh -c "./build/lockstep/lockstep {} $C > results/${P}_seed{}.log 2>&1; echo seed {} exit \$?"
grep -h RESULT results/${P}_seed*.log | sort | uniq -c | head -50

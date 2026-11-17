#!/bin/sh
# Variant oracle: N seeds x M random stable register tables (+ the directed tables), 4 in parallel.
cd "$(dirname "$0")"
N=${1:-4}; M=${2:-400}
seq 1 $N | xargs -P 4 -I{} sh -c "./build/variants/variants {} $M > results/variants_seed{}.log 2>&1; echo seed {} exit \$?"

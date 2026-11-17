#!/bin/bash
# run.sh [edges] [seed]: build tb (all 7 variants), drive a random write stream, check every tick against model.py.
set -e
cd "$(dirname "$0")"
N=${1:-40000000}; SEED=${2:-1}
verilator --cc --exe --build -j 4 -O2 -Wno-fatal --top-module tb --Mdir obj ../rtl/sn76489sv.sv tb.sv main.cpp -o Vtb >/dev/null
mkdir -p out
python3 -I model.py stim out/stim.txt "$N" "$SEED"
./obj/Vtb out/stim.txt out/run "$N"
python3 -I model.py check out/stim.txt out/run

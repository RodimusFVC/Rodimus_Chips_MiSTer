#!/bin/sh
# synth_one.sh <top> <files...> : yosys synth_intel_alm (Cyclone V) cell stats + reg-to-reg depth
top=$1; shift
cd "$(dirname "$0")"
yosys -q -l "yosys_$top.log" -p "read_verilog -sv $*; synth_intel_alm -family cyclonev -top $top; stat; write_json net_$top.json" >/dev/null 2>&1 || { echo "yosys failed for $top"; tail -20 "yosys_$top.log"; exit 1; }
echo "== $top"
awk '/Printing statistics/{f=1} f&&/MISTRAL_(ALUT|FF|NOT|MLAB|M10K|MUL)/{print}' "yosys_$top.log" | sort | uniq
python3 depth.py "net_$top.json"

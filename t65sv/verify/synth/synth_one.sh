#!/bin/sh
# synth_one.sh <name> <top> "<read cmds>" : yosys synth_intel_alm -family cyclonev, stats + longest path
n=$1; top=$2; rd=$3
yosys -q -l $n.log -p "$rd; hierarchy -top $top; synth_intel_alm -family cyclonev -top $top -noiopad -noclkbuf; stat; tee -o $n.ltp ltp -noff" > /dev/null 2>&1
echo "== $n"; grep -E "Number of cells|MISTRAL_[A-Z0-9_]+ +[0-9]+" $n.log | tail -12; tail -2 $n.ltp

#!/bin/bash
# check.sh TAG [BASE]: rebuild both cores, run SingleStepTests and interrupt timing on both,
# check that t80sv and the VHDL give identical results and identical pins (100 tests per
# opcode file, every half T-state), and list opcodes whose result changed since run BASE.
set -e
cd "$(dirname "$0")"
T=${1:?usage: check.sh TAG [BASE]}
mkdir -p results
make sv vhdl > results/build_$T.log 2>&1 || { tail -20 results/build_$T.log; exit 1; }
make sst EXE=sv TAG=$T > /dev/null 2>&1
make sst EXE=vhdl TAG=$T > /dev/null 2>&1
for e in sv vhdl; do printf "%-5s " $e; grep '\*\*all' results/${e}_${T}_summary.md; done
cmp -s results/sv_${T}_sst.tsv results/vhdl_${T}_sst.tsv && echo "sst: sv == vhdl" || echo "sst: sv != vhdl"
cmp -s results/sv_${T}_irq.tsv results/vhdl_${T}_irq.tsv && cmp -s results/sv_${T}_irq_m1wait.tsv results/vhdl_${T}_irq_m1wait.tsv \
  && echo "irq: sv == vhdl" || echo "irq: sv != vhdl"
./obj_sv/VT80pa pindump /dev/null 100 vectors/sst_txt/*.txt > results/pins_sv_$T.txt 2>/dev/null &
./obj_vhdl/VT80pa pindump /dev/null 100 vectors/sst_txt/*.txt > results/pins_vhdl_$T.txt 2>/dev/null
wait
cmp -s results/pins_sv_$T.txt results/pins_vhdl_$T.txt && echo "pins: sv == vhdl ($(grep -c '^T ' results/pins_sv_$T.txt) tests)" \
  || echo "pins: sv != vhdl"
rm -f results/pins_sv_$T.txt results/pins_vhdl_$T.txt
if [ -n "$2" ]; then
  echo "opcodes whose result changed vs $2:"
  join -t "$(printf '\t')" <(cut -f1-5 results/sv_$2_sst.tsv | sort) <(cut -f1-5 results/sv_${T}_sst.tsv | sort) | \
    awk -F'\t' '$3!=$7 || $4!=$8 || $5!=$9 {print "  "$1": pass "$3" -> "$7", doc-fail "$4" -> "$8", undoc-fail "$5" -> "$9}'
fi

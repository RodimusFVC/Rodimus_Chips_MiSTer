#!/bin/sh
# build_tb.sh <name> <cpp> lockstep|solo [-Gparam=val ...]
#   lockstep: oracle + t65sv, all outputs compared every clock; solo: t65sv only (variants).
set -e
cd "$(dirname "$0")"; V=$(pwd)
name=$1; cpp=$2; kind=$3; shift 3
[ -f ref/ref_T65.v ] || ref/gen_ref.sh
if [ "$kind" = lockstep ]; then
  src="$V/ref/ref_T65.v $V/tb/lockstep_top.sv"; top=lockstep_top; def=-DLOCKSTEP
else
  src="$V/tb/solo_top.sv"; top=solo_top; def=
fi
mkdir -p build
verilator --cc --exe --build -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style "$@" \
  -Mdir build/obj_$name -o ../$name --top-module $top -CFLAGS "-O2 $def -I$V/tb" \
  $src $V/../rtl/t65sv.sv $V/../rtl/t65sv816.sv $V/../rtl/t65sv_T65.sv $V/../rtl/t65sv_variants.sv $V/tb/$cpp > build/$name.log 2>&1 || { tail -30 build/$name.log; exit 1; }
echo built build/$name

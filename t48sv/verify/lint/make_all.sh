#!/bin/bash
# make_all.sh: concatenate the deliverable RTL into rtl/t48sv_all.sv (everything a Quartus
# project needs except the chip_pool_pkg wrapper t48sv_mcs48_pool.sv)
RTL=$(cd "$(dirname "$0")/../../rtl" && pwd)
OUT=$RTL/t48sv_all.sv
{
  for f in t48sv_core.sv t48sv_blocks.sv t48sv_decoder.sv t48sv_cores.sv t48sv_t8039_notri_extrom.sv \
           t48sv_system.sv t48sv_tri.sv t48sv_t8243.sv; do
    echo "// ---------------------------------------------------------------- $f"
    cat $RTL/$f
    echo
  done
} > $OUT
echo wrote $OUT

#!/bin/bash
# rtl/s2650sv_all.sv = s2650sv.sv + s2650sv_s2650_cpu.sv (everything a Quartus project needs except the
# chip_pool_pkg wrapper s2650sv_pool.sv)
cd "$(dirname "$0")/../rtl"
{
  echo "// s2650sv_all.sv - generated from s2650sv.sv and s2650sv_s2650_cpu.sv by verify/make_all.sh"
  echo
  cat s2650sv.sv
  echo
  cat s2650sv_s2650_cpu.sv
} > s2650sv_all.sv
echo "rtl/s2650sv_all.sv: $(wc -l < s2650sv_all.sv) lines"

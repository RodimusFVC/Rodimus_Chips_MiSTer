#!/bin/bash
# verilator --lint-only -Wall on every top and parameter set, with the two waivers in lint.vlt
cd "$(dirname "$0")/.."
set -e
verilator --lint-only -Wall verify/lint.vlt rtl/s2650sv.sv rtl/s2650sv_s2650_cpu.sv --top-module s2650sv_s2650_cpu
for B in 0 1; do for M in 0 1; do
  verilator --lint-only -Wall verify/lint.vlt -GVER_B=1\'b$B -GRAS_MLAB=1\'b$M rtl/s2650sv.sv --top-module s2650sv
done; done
verilator --lint-only -Wall verify/lint.vlt rtl/s2650sv_all.sv --top-module s2650sv_s2650_cpu
POOL_PKG=${POOL_PKG:-../ref/galaxian/rtl/chip_pool_pkg.sv}
if [ -f $POOL_PKG ]; then verilator --lint-only -Wall -Wno-DECLFILENAME verify/lint.vlt $POOL_PKG rtl/s2650sv.sv rtl/s2650sv_pool.sv --top-module s2650sv_pool 2>&1 | grep -A3 "s2650sv" | grep -E "^%" && exit 1; fi
echo "lint clean: s2650sv_s2650_cpu, s2650sv (VER_B 0/1 x RAS_MLAB 0/1), s2650sv_all.sv, s2650sv_pool (fleet chip_pool_pkg)"

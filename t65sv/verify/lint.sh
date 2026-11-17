#!/bin/sh
# lint.sh: verilator --lint-only -Wall on every top and parameter combination.
# Waivers: -Wno-DECLFILENAME (several modules per file, needed for t65sv_all.sv),
#          -Wno-PINCONNECTEMPTY (wrappers leave unused T65 outputs unconnected on purpose).
# In-source waivers (t65sv.sv): Abort_n unused (T65 ignores it too), bit 0 of T65's nibble adders unused,
# SYNCASYNCNET on Res_n_i (T65's unreset registers hold during reset: Res_n_i is their synchronous enable).
# t65sv.sv with C816 = 1: the 6502 outputs o_* and the 65C816 registers T65's Regs/DEBUG layouts cannot carry are
# unused. t65sv816.sv: SYNCASYNCNET on Res_n (same scheme), the third micro-op lookahead's skip field.
cd "$(dirname "$0")/.."
F="verify/pool/chip_pool_pkg_stub.sv rtl/t65sv.sv rtl/t65sv816.sv rtl/t65sv_T65.sv rtl/t65sv_variants.sv rtl/t65sv_t65.sv"
W="-Wall -Wno-DECLFILENAME -Wno-PINCONNECTEMPTY"
rc=0
lint() { out=$(verilator --lint-only $W $F "$@" 2>&1); if [ -n "$out" ]; then echo "FAIL $*"; echo "$out"; rc=1; else echo "clean $*"; fi; }
for c in 0 1 2 3; do for d in 0 1; do lint --top-module t65sv_T65 -GC02=$c -GNO_DECIMAL=1\'b$d; done; done
for c in 0 1; do lint --top-module t65sv_T65 -GC02=$c -GC816=1\'b1; done
lint --top-module t65sv_T65 -GC02_FIXED=1\'b1
lint --top-module t65sv_6510
lint --top-module t65sv_6510 -GPORT_BITS=8
lint --top-module t65sv_6507
lint --top-module t65sv_2A03
for f in 1 2 3; do lint --top-module t65sv_65C02 -GFLAVOUR=$f; done
lint --top-module t65sv_t65
lint --top-module t65sv_65C816
lint --top-module t65sv816
out=$(verilator --lint-only $W rtl/t65sv_all.sv --top-module t65sv_T65 2>&1); [ -z "$out" ] && echo "clean t65sv_all.sv" || { echo "FAIL t65sv_all.sv"; echo "$out"; rc=1; }
exit $rc

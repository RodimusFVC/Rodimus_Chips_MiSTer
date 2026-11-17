#!/bin/sh
# verilator --lint-only -Wall on every top, from the per-module sources (no waivers), then on crtc6845sv_all.sv
# (waiver DECLFILENAME: one file, many modules) and the pool wrapper (waiver PINCONNECTEMPTY: .CURSOR() is left open,
# as in the fleet's own instances).
cd "$(dirname "$0")"
rc=0
for t in crtc6845sv_mc6845 crtc6845sv_mc6845_motorola crtc6845sv_hd6845s crtc6845sv_um6845r crtc6845sv_ams40489 \
         crtc6845sv_ams40226 crtc6845sv_r6545 crtc6845sv_mos6545; do
  if verilator --lint-only -Wall rtl/crtc6845sv.sv rtl/$t.sv --top-module $t; then echo "lint clean: $t"; else rc=1; fi
  if verilator --lint-only -Wall -Wno-DECLFILENAME rtl/crtc6845sv_all.sv --top-module $t; then echo "lint clean: $t (crtc6845sv_all.sv)"; else rc=1; fi
done
for v in 8 9; do
  if verilator --lint-only -Wall -GVARIANT=$v rtl/crtc6845sv_vdc.sv --top-module crtc6845sv_vdc; then echo "lint clean: crtc6845sv_vdc VARIANT=$v"; else rc=1; fi
  if verilator --lint-only -Wall -Wno-DECLFILENAME -GVARIANT=$v rtl/crtc6845sv_all.sv --top-module crtc6845sv_vdc; then echo "lint clean: crtc6845sv_vdc VARIANT=$v (crtc6845sv_all.sv)"; else rc=1; fi
done
PKG=${CHIP_POOL_PKG:-verify/pool/chip_pool_pkg.sv}
if verilator --lint-only -Wall -Wno-PINCONNECTEMPTY "$PKG" rtl/crtc6845sv.sv rtl/crtc6845sv_mc6845.sv rtl/crtc6845sv_pool.sv --top-module crtc6845sv_pool; then
  echo "lint clean: crtc6845sv_pool (waiver: PINCONNECTEMPTY)"; else rc=1; fi
exit $rc

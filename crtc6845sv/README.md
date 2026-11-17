# crtc6845sv

SystemVerilog 6845-family CRT controller. Default (`VARIANT = 0`) is cycle-identical to the fleet's `mc6845.vhd`
**with** the CRTCADJ-2026-10-24 adjust-line fix (Universal's edited copy). The fleet's stock copy differs from it
only on vertical-adjust lines whose row is below R6, which in the fleet means only Cosmic Guerilla. Variants 1-7:
Motorola MC6845, HD6845S / UM6845, UM6845R, AMS40489, 40226, R6545-1 / SY6545-1, MOS 6545-1. C128 VDC 8563 / 8568
(`crtc6845sv_vdc`, VARIANT 8 / 9).

- `rtl/crtc6845sv_all.sv`: the one file a Quartus project needs (core + every top + VDC). Drop-in
  `crtc6845sv_mc6845` keeps `mc6845`'s ports; one module per variant (`crtc6845sv_hd6845s`, `_r6545`, ...).
- `rtl/crtc6845sv_pool.sv`: wrapper on the fleet's `chip_pool_pkg` `mc6845_i_t` / `mc6845_o_t` (needs that package).
- `verify/`: lockstep against GHDL netlists of the fixed and stock VHDL (shipped in `verify/ref/`), variants and
  VDC against MAME-derived frame-level oracles, 12 fleet register tables, yosys equivalence / area.
  `docs/`: fleet register tables, upstream survey, per-variant and VDC sources. `REPORT.md`: results.

Import changes (2026-10-29), comment-only: `mc6845.vhd`'s full notice added to the `crtc6845sv.sv` /
`crtc6845sv_all.sv` headers (delivered with a one-line credit only).

**License: the 6845 core carries Mike Stirling's `mc6845.vhd` terms, which are NON-COMMERCIAL ONLY** (same class
as mb88's terms). The VDC is BSD-3 (MAME-derived). See `LICENSE`.

Hardware-verified (2026-10-29): Universal (Mr. Do's Castle family, Cosmic Guerilla), SNK6502 (all games).

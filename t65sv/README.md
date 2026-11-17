# t65sv

SystemVerilog rewrite of the T65 6502-family core (MiSTer-devel lineage, T65 Ver 315). With default parameters and
Mode `00` it is cycle- and pin-identical to T65 Mode "00" (NMOS incl. undocumented opcodes, and T65's own deviations
from silicon). Parameters add 6510 / 8500, 6507, 2A03 / 2A07, 65C02 (WDC / Rockwell / Synertek 65SC02) and 65C816;
each constant-folds away when unused.
T65 by Daniel Wallner; MikeJ, WoS, ML, SzGy and contributors.

- `rtl/t65sv_all.sv`: the one file a Quartus project needs (core + 65C816 engine + every top). Drop-in `t65sv_T65`
  keeps the T65 entity's ports (`DEBUG` packed `{I,A,X,Y,S,P}`, optional `tri1 BCD_en`). Variant tops: `t65sv_6510`,
  `t65sv_6507`, `t65sv_2A03`, `t65sv_65C02`, `t65sv_65C816`.
- `rtl/t65sv_fleet.sv`: `t65sv_t65`, the wrapper on the fleet's `chip_pool_pkg` `t65_i_t` / `t65_o_t` (needs that
  package). Delivered as `rtl/t65sv_t65.sv`; renamed on import because it collided with `t65sv_T65.sv` on
  case-insensitive file systems, and to match `t80sv_fleet.sv`.
- `verify/`: Verilator lockstep against a GHDL model of T65, SingleStepTests, Dormann, Lorenz, VICE, mutation, yosys
  equivalence / area. `REPORT.md`: results. `survey/`: the MiSTer-devel T65 copies and their diffs.

Import changes (2026-10-29), comment-only: `lint_off/on UNUSEDSIGNAL` -> `UNUSED` in `rtl/` (Verilator 4.204 rejects
the Verilator-5 code; same fix as t80sv).

Hardware-verified (2026-10-29): SNK6502 (main CPU: RDY wait states, Sync, NMI), Nintendo (2x 2A03 with DMA RDY),
Exidy (main + sound), PunchOut (2A03 sound), Gottlieb (Rev 1 sound), Centipede (main CPU, every board).

License: T65's BSD-style terms (Daniel Wallner and the other T65 authors) plus Rodimus. See `LICENSE`.

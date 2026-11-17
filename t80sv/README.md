# t80sv

SystemVerilog rewrite of the T80 Z80 core (MiSTer-devel lineage, T80 v350 / 351), cycle-identical to the VHDL in every
configuration the fleet uses, plus the Phoenix 8080 / 8085 additions (runtime `I8080` / `I8085`, RIM / SIM / SOD).
T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) Sorgelig and contributors.

- `rtl/t80sv_all.sv`: the one file a Quartus project needs (core + every drop-in top). Drop-ins keep the VHDL tops'
  ports and generics: `t80sv_T80s`, `t80sv_T80pa`, `t80sv_T80se`, `t80sv_T80sed`, `t80sv_T8080se`, `t80sv_GBse`,
  `t80sv_T80a`, `t80sv_T80as`, `t80sv_T80`; Phoenix: `t80sv_T80pa_phx`.
- `rtl/t80sv_fleet.sv`: wrappers on the fleet's `chip_pool_pkg` bus types (needs that package).
- `verify/`: Verilator lockstep harness against GHDL models of the VHDL; ZEXDOC / ZEXALL logs. `REPORT.md`: results.

Hardware-verified (2026-10-29): `T80s` (Arabian, BluePrint, CrazyClimber, ChampionBaseball), `T80se` x3 (Galaga),
`T80pa` incl. BUSRQ / BUSAK (Nintendo), Phoenix 8080 / 8085.

License: T80's BSD-style terms (Daniel Wallner and the other T80 authors) plus Rodimus. See `LICENSE`.

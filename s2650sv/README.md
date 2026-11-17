# s2650sv

SystemVerilog Signetics 2650 CPU, cycle-for-cycle identical to the fleet's `sgs2650` (TEMlib, through the
`s2650_cpu` wrapper), including the fleet's two fixes and every place sgs2650 differs from silicon / MAME
(REPORT "sgs2650 vs MAME vs the Signetics manual"). `VER_B` selects 2650A (fleet) / 2650B; `RAS_MLAB` puts the
return-address stack in one MLAB (default) or registers.

- `rtl/s2650sv_all.sv`: the one file a Quartus project needs. Drop-in `s2650sv_s2650_cpu` keeps `s2650_cpu`'s ports.
- `rtl/s2650sv_pool.sv`: wrapper on the fleet's `chip_pool_pkg` `s2650_i_t` / `s2650_o_t` (`reset` field: master,
  Galaxian, Centipede; Pacman's package has `reset_n`, one marked line to change).
- `verify/`: lockstep against GHDL netlists of the VHDL (shipped in `verify/refmodel/`), self-checking exerciser
  (480 tests), directed sweeps, formal bounded equivalence, MAME comparison, mutation, yosys area. `REPORT.md`.

Import changes (2026-10-29): `verify/lint.vlt` `UNUSEDSIGNAL` -> `UNUSED` (Verilator 4.204). RTL unchanged.
Note for local reruns: `verify/tb/lockstep.cpp` uses Verilator 5's `.data()` on a wide signal (line 497); on 4.204
drop `.data()` there.

License: sgs2650 carries no licence text; upstream (Arcadia_MiSTer) terms unconfirmed. See `LICENSE`.

Hardware-verified (2026-10-29): Centipede (Bulls Eye Darts).

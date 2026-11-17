# t48sv

SystemVerilog rewrite of Arnim Laeuger's T48: MCS-48 (8035/39/40/48/49/50, 87xx), UPI-41/41A/42, 8021/8022 and
the 8243 expander. Cycle-identical to both T48 lineages the fleet runs: **A** = r295 (2009; Nintendo, Galaxian,
Konami82, SegaG80) and **B** = the 2023+ release (DECOCassette's UPI-41, with its `sts_o` / IBF-ack edits).
`REV2023` selects the lineage. Every drop-in defaults to the one it replaces.

- `rtl/t48sv_all.sv`: the one file a Quartus project needs. Drop-ins keep the VHDL ports and generics:
  `t48sv_t8039_notri_extrom`, `t48sv_t48_core`, `t48sv_upi41_core`, `t48sv_t21_core`, `t48sv_t22_core`, the
  `system/` tops, and the `t8243` set.
- `rtl/t48sv_mcs48_pool.sv`: wrapper on the fleet's `chip_pool_pkg` `mcs48_i_t` / `mcs48_o_t` (needs that package).
- `rtl/t48sv_lint.vlt`: Verilator waivers. `verify/`: lockstep against GHDL netlists of both lineages, timing
  sweeps, the T48 verification suite, 8243 and MAME comparisons, yosys area. `REPORT.md`: results.

Import changes (2026-10-29): T48's BSD notice added to the `t48sv_core.sv` / `t48sv_all.sv` headers (comments
only; the licence requires it in derived source); `t48sv_lint.vlt` rule names `UNUSEDSIGNAL` / `UNUSEDPARAM` ->
`UNUSED` (Verilator 4.204).
Quartus 17 fix (2026-10-29, after the first fleet compile failed with 10170): the tri-state tops in
`t48sv_tri.sv` put module-level generate loops (incl. the `T48SV_QB` macro, `$bits()` bound) outside
`generate` / `endgenerate`; wrapped them and gave the macro a literal width. Tri-state tops only, no fleet use;
`t48sv_all.sv` regenerated with `verify/lint/make_all.sh` (diff = exactly those lines).

Open: which lineage new MCS-48 tops should default to (REPORT §4.2: A and B differ in RET address timing and INT
sampling).
Hardware-verified (2026-10-29): Nintendo (8039, four sound boards), SegaG80 (two 8035s).

License: T48's BSD-style terms (Arnim Laeuger) plus Rodimus. See `LICENSE`.

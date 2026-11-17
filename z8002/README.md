# z8002

## From the source header

```
 z8002.sv -- Zilog Z8002 (non-segmented Z8000) CPU core.
 Behavioural reference: MAME z8000ops.hxx / z8000tbl.hxx / z8000cpu.h (DAB table ported from MAME).
 Big-endian words; PC even; SP = R15; byte reg n -> R[n&7] high if n < 8 else low;
 FCW C=b7 Z=b6 S=b5 P/V=b4 DA=b3 H=b2; reset reads FCW @2, PC @4. NVI fully implemented.
 Not implemented (unused by Pole Position): VI / NMI accept, segmentation, wait_n, NSP/SSP swap.
```

Pool types `z8002_i_t` / `z8002_o_t` (RodimusCoresMaster `chip_pool_pkg`). `z8002.sv` `include`s its two `.svh`
tables (add `rtl/rodimus/z8002` to the include path / Quartus search path, or keep them next to it as here). The
debug outputs (`dbg_pc` / `dbg_fcw` / `dbg_ir` / `dbg_retire` / `dbg_regs`) are for test benches; `dbg_illegal`
latches an illegal opcode (Pole Position shows it on LED_USER).

Verification: Pole Position's `verilator/z8002_testsuite/` (differential suite against MAME's Z8000 core,
`verilator/z8002_audit/` illegal-opcode audit) stays in that core.

## Files

| File | md5 |
|---|---|
| `z8002.sv` | 61d9eeb7 |
| `z8002_cycle_lookup.svh` | 67730c1b |
| `z8002_dab_rom.svh` | ca593079 |

Imported 2026-11-11 from `PolePosition` (`rtl/cpu/z8002/`).

## Fleet copies

- Identical: PolePosition
- Different: -

## License

License: BSD-3-Clause (own design; MAME's Z8000 core is the behavioural reference and the source of the DAB table,
its copyright holders are credited). See `LICENSE`.

## Verification

`verify/` (moved from Arcade-PolePosition_MiSTer/verilator 2026-11-11): `testsuite/` (lockstep vs MAME z8000 core, `./bootstrap` first; residual 4627 = the regression detector), `audit/` (illegal-opcode audit), `optest/` (opcode test bench). Build in place (`make`); RTL = `../../rtl`.

# mb88

## From the source header

```
 MB88-2026-10-24: FLEET MASTER. One mb88_core.sv / mb88.sv pair for every MB88 core
 (Galaga, Arabian, Kangaroo, PolePosition, Namco6809), md5-identical everywhere.
 Master home: Arcade-Galaga_MiSTer/rtl/cpu/mb88_sv/. Edit it there, then copy out.
 Merged lineages (all fixes from every copy are present):
   Kangaroo 2026-07-10 origin: MCU-TIMER-FIX / MCU-TIMERVF-FIX (07-11), serial (07-18)
   PolePosition: TC-TIMER-FIX (07-17), O-PORT-STROBE o_wr (08-09), serial 1 shift per
     ce (SERIALRATE 09-19, HW-confirmed), IRQ_ENTRY_STALL parameter (09-23, 54xx = 3)
   Galaga 2026-10-04: ram_clr power-on RAM / stack clear input
```

## Files

| File | md5 |
|---|---|
| `mb88_core.sv` | 5baf0859 |
| `mb88.sv` | 711ed922 |

Imported 2026-10-29 from `Galaga` (`rtl/cpu/mb88_sv/`).

## Fleet copies

- Identical: Arabian, Galaga, Kangaroo, Namco6809, PolePosition
- Different: -

## License

SystemVerilog conversion of **Dar's `mb88.vhd`** (darfpga@aol.fr, http://darfpga.blogspot.fr; v0.3, 28/02/2017),
merging the Galaga, Bosconian and Xevious copies, plus many fixes by Rodimus. Dar's original terms, verbatim:

```
-- Educational use only
-- Do not redistribute synthetized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
```

These terms carry over to this derivative. They are NOT an open-source license; the license question is undecided (ask Dar / clean-room rewrite). See `LICENSE`.

## Verification

`verify/` (moved from Arcade-PolePosition_MiSTer/verilator 2026-11-11): `testsuite/` (lockstep vs MAME mb88 core, `./bootstrap` first). Build in place (`make`); RTL = `../../rtl`.

# m68ksv Quartus 17 test project

Compiles m68ksv alone (no MiSTer framework) for the MiSTer device to get ALMs, registers, M10K, DSP, fmax and slack,
and fx68k in the same top as the size reference:

- `m68ksv_qtop.sv`: the CPU on 8 KB of M10K (two byte lanes, mirrored), `cen_p` / `cen_n` = clk / 4 made inside,
  input pins registered, bus activity registered to output pins (nothing optimised away). No pin locations. On the
  8-bit bus (68008 / 68008FN; 68EC000 when `mode_pin` is low at reset) the lane is chosen by A0, data on D7-D0;
  `mode_pin` is a real input so the 68EC000 keeps both bus widths in the netlist. 68020 / 68EC020: the RAM is one
  32-bit port (four byte lanes, `dtack_pin` drives DSACK1 / DSACK0 = 32-bit port, `vpa_pin` AVEC), `mode_pin` drives
  CDIS so the instruction cache stays in the netlist. The 68020 build runs one micro-cycle per CPU clock and needs two `clk` or more
  between consecutive CPU edges (checkpoint 4b); clk / 4 satisfies that.
  Configuration by the revision's `VERILOG_MACRO`s: `M68KSV_CPU=<value>` sets the `CPU` parameter (default 68000);
  `M68KSV_RES=1` sets `RES = 1`, the logic-heavy setting (checkpoint 6: fewer M10K, more ALMs, the same behaviour);
  `M68KSV_QTOP_FX68K` builds fx68k instead.
- `files.qip`: m68ksv sources (`../../rtl/m68ksv_all.sv`), the top, the .sdc. The .qsf files list no source files.
- `fx68k.qip`: fx68k sources, used by the fx68k revision only.
- `m68ksv_qtop.sdc`: one clock, 96 MHz (10.417 ns).

Revisions (one project, `m68ksv_qtop.qpf`); each .qsf is `m68ksv_qtop.qsf` (taken from x86sv's Quartus 17.0.2
project settings) plus its extra lines:

| Revision | Configuration | Extra assignments |
|---|---|---|
| `m68ksv_qtop` | m68ksv, CPU = 68000 | none |
| `m68ksv_qtop_fx68k` | fx68k (size reference) | `QIP_FILE fx68k.qip`, `VERILOG_MACRO "M68KSV_QTOP_FX68K=1"` |
| `m68ksv_qtop_68008` | m68ksv, CPU = 68008 (DIP48: 8-bit bus, A19-A0, IPL2/0 + IPL1, no BGACK) | `VERILOG_MACRO "M68KSV_CPU=68008"` |
| `m68ksv_qtop_68008fn` | m68ksv, CPU = 68009 (68008FN / PLCC52: A21-A0, 3 IPL, BGACK) | `VERILOG_MACRO "M68KSV_CPU=68009"` |
| `m68ksv_qtop_68ec000` | m68ksv, CPU = 68001 (68EC000: MODE latch, 8- or 16-bit) | `VERILOG_MACRO "M68KSV_CPU=68001"` |
| `m68ksv_qtop_68010` | m68ksv, CPU = 68010 (16-bit bus, A23-A1, the 68000's pins) | `VERILOG_MACRO "M68KSV_CPU=68010"` |
| `m68ksv_qtop_68020` | m68ksv, CPU = 68020 (32-bit bus, A31-A0, dynamic sizing, instruction cache) | `VERILOG_MACRO "M68KSV_CPU=68020"` |
| `m68ksv_qtop_68ec020` | m68ksv, CPU = 68021 (68EC020: A23-A0) | `VERILOG_MACRO "M68KSV_CPU=68021"` |
| `m68ksv_qtop_<cpu>_lh` (`68000`, `68008`, `68008fn`, `68ec000`, `68010`, `68020`, `68ec020`) | the same CPU, `RES = 1` (logic-heavy) | that CPU's .qsf + `VERILOG_MACRO "M68KSV_RES=1"` |

fx68k sources are not in this repository. Before compiling the fx68k revision, put fx68k into `fx68k/` here:
download https://github.com/ijor/fx68k/archive/refs/heads/master.zip (master was commit
0602ee4627b10f301298f2673d826cdd6baa9327 on 2026-11-14), copy `fx68k.sv`, `fx68kAlu.sv`, `uaddrPla.sv` into
`syn/quartus/fx68k/`, and `microrom.mem`, `nanorom.mem` into `syn/quartus/` (fx68k reads them by relative path).

Run (Quartus 17.0, from this folder), one revision per run:

```bash
quartus_sh --flow compile m68ksv_qtop                         # m68ksv 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_fx68k    # fx68k
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008    # 68008 (DIP48)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn  # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000  # 68EC000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68000_lh     # logic-heavy (RES = 1): one per CPU, *_lh
```

For the 8-bit revisions also check in `map.rpt` that `m68ksv_biu` is larger than in the 68000 revision (the split-word
sequencer, `half`, `hb` and, for the 68EC000, `mode8` must exist) - a parameter-selected path Quartus optimised away
would show as an identical 68000-sized BIU.

Results: `output_files/<revision>.fit.summary` (ALMs, registers, M10K, DSP), `output_files/<revision>.sta.rpt`
("Slow 1100mV 100C Model Fmax Summary", setup slack), and `output_files/<revision>.map.rpt` ("Resource Utilization
by Entity" / "RAM Summary": `m68ksv_urom`, `m68ksv_drom1`, `m68ksv_drom2`, `m68ksv_drom3` must show block memory bits
(M10K; `m68ksv_drom4e`, 64 × 8, is logic on purpose and gives a harmless 276004 "inappropriate RAM size"; since
checkpoint 5 the 68010 revision also has `m68ksv_drom1lp_010`, the 1024 × 9 loop-mode table, which must be M10K too), the three
`m68ksv_rf` copies `rf_xn`, `rf_a`, `rf_bw` must be MLAB (32 × 32 each; `rf_dbg` disappears when `dbg_rd` is
unconnected); a 276007 "uninferred due to asynchronous read logic" anywhere is a fault).

Worst setup paths, after a compile (Quartus 17.0, from this folder):

```bash
quartus_sta -t timing_paths.tcl m68ksv_qtop          # -> output_files/m68ksv_qtop.paths.txt
quartus_sta -t timing_paths.tcl m68ksv_qtop_fx68k    # same for the fx68k revision
quartus_sta -t timing_paths.tcl m68ksv_qtop_68008    # and for each 2b revision
quartus_sta -t timing_paths.tcl m68ksv_qtop_68008fn
quartus_sta -t timing_paths.tcl m68ksv_qtop_68ec000
quartus_sta -t timing_paths.tcl m68ksv_qtop_68010
quartus_sta -t timing_paths.tcl m68ksv_qtop_68020
quartus_sta -t timing_paths.tcl m68ksv_qtop_68ec020
quartus_sta -t timing_paths.tcl m68ksv_qtop 60       # more paths
```

Checkpoint 6 (2026-11-16): seven new revisions `m68ksv_qtop_<cpu>_lh` (added to the .qpf; the existing .qsf files and
`files.qip` unchanged; `m68ksv_qtop.sv` passes `RES` only under `ifdef M68KSV_RES`). What to look at after compiling:
- RAM summary, default revisions: `m68ksv_urom` 1,024 deep on the 68000 family (10 M10K, was 2,048 / 19); the 68010's
  `m68ksv_urom_010` as two ROMs (1,024 + 512 deep, 11 + 6 M10K, was 21); 68020 unchanged. CPU M10K 16 / 24 / 30.
- RAM summary, `_lh` revisions: `m68ksv_ucs*` = one micro ROM (68010: two) and two / one / three nano ROMs, all M10K;
  `m68ksv_drom1*_lh` (and the 68010's `m68ksv_drom1lp_010_lh`) must **not** be in the RAM summary (logic, `romstyle
  "logic"`) but must show logic cells in "Resource Utilization by Entity" (a table optimised away would be a fault, the
  sega_decrypt lesson); `drom2` / `drom3` M10K. CPU M10K 7 / 10 / 12.
- Timing, `_lh` revisions and the 68010 default: the new path is `ua_*` / the next-address logic → the address port of
  the ROM read one clock ahead (`m68ksv_ucs*|mrom*`, the 68010's `m68ksv_urom_010|rom0` / `rom1`). It should not be
  the worst path. In the 68010 default, the micro-word's users now start at a register (`m68ksv_urom_010|q`) instead of
  an M10K output.

`timing_paths.tcl` selects the slow 1100 mV 100 C corner, writes the worst paths, one per endpoint (slack, data
delay, logic levels, from, to), then appends Quartus's `report_timing -detail summary` of the same paths. Written
2026-11-15 without a Quartus run (untested); if a command fails, the full report is still in `<revision>.sta.rpt`.

Checkpoint 5 (2026-11-16): no project file changed (`files.qip`, `.qsf`, `.qpf` as before; `m68ksv_all.sv`
regenerated). What to look at after compiling: ALMs against the pre-checkpoint-5 table in `REPORT.md` ("Handover
(checkpoint 5)"); the 68010 revision should show 36 M10K-mapped ROM blocks in yosys terms (the loop table added); the
68020 / 68EC020 cores ignore `STERM_n` now (the 68020 has no STERM; the test top ties it high anyway); the 68EC020
drives ECS / OCS / DBEN / IPEND constant high. Rough expectation from yosys (an estimate, not Quartus): 68000 family
about 100-140 ALMs below the pre-checkpoint-5 compile, 68010 about 250 below, 68020 / 68EC020 about 250-300 below.

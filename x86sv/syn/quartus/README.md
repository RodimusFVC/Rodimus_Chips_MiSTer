# x86sv Quartus 17 test project

Compiles x86sv alone (no MiSTer framework) for the MiSTer device to get ALMs, fmax and slack:

- `x86sv_qtop.sv`: the CPU on 8 KB of M10K, ce = clk / 4 made inside the design, input pins registered, I/O writes
  and bus activity registered to output pins (nothing optimised away). No pin locations: the fitter places them.
  The configuration comes from the revision's `VERILOG_MACRO`s: none = 8088 (`x86sv`), `X86SV_BUS16` = 8086
  (`x86sv16`, the RAM as two byte lanes), `X86SV_NEC` = V20, both = V30; `X86SV_NEC8080` adds the 8080 emulation
  mode (parameter `NEC8080`) to V20 / V30.
- `files.qip`: the source list (`../../rtl/x86sv_all.sv`, the top, the .sdc); the .qsf files list no source files.
- `x86sv_qtop.sdc`: one clock, 80 MHz. For 96 MHz change `-period 12.500` to `-period 10.417`.

Revisions (one project, `x86sv_qtop.qpf`); each .qsf is `x86sv_qtop.qsf` plus its `VERILOG_MACRO` lines:

| Revision | Configuration | Extra assignments |
|---|---|---|
| `x86sv_qtop` | 8088 | none |
| `x86sv_qtop_8086` | 8086 | `VERILOG_MACRO "X86SV_BUS16=1"` |
| `x86sv_qtop_v20` | V20 | `VERILOG_MACRO "X86SV_NEC=1"` |
| `x86sv_qtop_v30` | V30 | `VERILOG_MACRO "X86SV_BUS16=1"`, `VERILOG_MACRO "X86SV_NEC=1"` |
| `x86sv_qtop_v20_8080` | V20 + 8080 emulation mode | `VERILOG_MACRO "X86SV_NEC=1"`, `VERILOG_MACRO "X86SV_NEC8080=1"` |
| `x86sv_qtop_v30_8080` | V30 + 8080 emulation mode | `VERILOG_MACRO "X86SV_BUS16=1"`, `VERILOG_MACRO "X86SV_NEC=1"`, `VERILOG_MACRO "X86SV_NEC8080=1"` |

Run (Quartus 17.0, from this folder), one revision per run:

```bash
quartus_sh --flow compile x86sv_qtop                      # 8088
quartus_sh --flow compile x86sv_qtop -c x86sv_qtop_8086   # 8086
quartus_sh --flow compile x86sv_qtop -c x86sv_qtop_v20    # V20
quartus_sh --flow compile x86sv_qtop -c x86sv_qtop_v30    # V30
quartus_sh --flow compile x86sv_qtop -c x86sv_qtop_v20_8080   # V20 + 8080 mode
quartus_sh --flow compile x86sv_qtop -c x86sv_qtop_v30_8080   # V30 + 8080 mode
```

In the GUI: Project > Revisions, set the revision current, compile.

Results: `output_files/<revision>.fit.summary` (ALMs, registers, M10K, DSP) and `output_files/<revision>.sta.rpt`
("Slow 1100mV 100C Model Fmax Summary", setup slack per corner; the worst paths are listed under "Report Timing").

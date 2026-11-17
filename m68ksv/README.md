# m68ksv

Our own synthesizable SystemVerilog 680x0 core for the MiSTer fleet (Cyclone V, Quartus 17.0): one core for the
68000, 68008 / 68008FN, 68EC000, 68010, 68020 and 68EC020, selected by parameter `CPU`. Microcoded (microcode and
decode tables in M10K), separate bus interface unit, one clock with `cen_p` / `cen_n` phase enables.

**Where the control storage goes: parameter `RES`** (checkpoint 6; the same CPU clock for clock either way):
- `RES = 0` (default), BRAM-heavy: one wide microcode ROM and the decode tables in M10K, fewest ALMs. CPU M10K: 16
  (68000 family), 24 (68010), 30 (68020 / 68EC020).
- `RES = 1`, logic-heavy: two-level microcode (micro ROM + nano ROMs) and the opcode decode table in logic, for a
  core that is short of block RAM. CPU M10K: 7 / 10 / 12, at an estimated +130 to +200 ALMs (from yosys; not
  compiled in Quartus yet).
- Fleet wrapper: `m68ksv_fleet #(.CPU(68000), .RES(1)) cpu (...)`. Quartus test project: macro `M68KSV_RES=1`
  (revisions `m68ksv_qtop_<cpu>_lh`). Details: `DESIGN.md` 3.1, `REPORT.md` "Checkpoint 6".

Status (checkpoint 6, 2026-11-16): all seven configurations implemented, each in both `RES` settings. 68000 / 68008 / 68008FN / 68EC000: Tom Harte
68000 suite exact on registers, RAM, bus order and cycle counts (794,139 / 794,139 pure-suite tests; 202,181 / 202,182
with MAME-corrected expectations), fx68k pin-level
lockstep (68000, 68EC000) and MAME m68008 bus-cycle lockstep (8-bit members) with 0 mismatches. 68010: Musashi m68010
lockstep 0 mismatching runs, loop mode and RTE re-run directed tests. 68020 / 68EC020: Musashi m68020 lockstep 0
mismatching runs (differences classified); undefined / disputed behaviour (DIV / CHK / CHK2 flags, PACK / UNPK -(A7),
LINK A7, the address-error frame) follows WinUAE's 68020 core and an Amiberry run of `verify/amiga020` (`REPORT.md`
"68020 behaviour from WinUAE"), except the address-error SSW, which follows the MC68020 User's Manual (RB / RC;
#unverified, manual versus WinUAE); bus cycles checked against the MC68020 User's Manual (dynamic sizing,
DSACK / BERR timing, RMC, cache, coprocessor protocol); instruction times are m68ksv's own (no overlap; see
`REPORT.md` "Checkpoint 5" for the comparison with the manual's tables). Not done: CALLM / RTM, long writes as one
bus request, some coprocessor primitives. Quartus numbers come from the user's compiles (`syn/quartus/`). Start with
the "Handover (checkpoint 5)" section at the end of `REPORT.md`; `DESIGN.md` describes the microarchitecture.

| Path | Contents |
|---|---|
| `rtl/m68ksv.sv` | top: reset, phase generator, `CPU` selection |
| `rtl/m68ksv_eu.sv` | execution unit: micro-sequencer, decode pipeline, register file, address unit, exceptions |
| `rtl/m68ksv_alu.sv` | data ALU |
| `rtl/m68ksv_rf.sv` | one register-file copy (MLAB) |
| `rtl/m68ksv_biu.sv` | 68000 / 68010 16-bit bus interface (8-bit for the 68008 family / 68EC000) |
| `rtl/m68ksv_biu32.sv` | 68020 / 68EC020 32-bit bus interface: dynamic sizing, instruction cache |
| `rtl/m68ksv_upkg.sv`, `m68ksv_urom.sv`, `m68ksv_drom.sv` | generated: microword layout, microcode ROM (`RES = 1`: the two-level control store `m68ksv_ucs*` too), decode ROMs (and their logic variants) |
| `rtl/gen/m68ksv_ucode.py` | microcode + decode-table source and generator (run it after editing; `verify/build.sh` does) |
| `rtl/m68ksv_all.sv` | everything above in one file, for Quartus (`verify/tools/mkall.sh`) |
| `rtl/m68ksv_fleet.sv`, `fleet_types.svh` | wrapper on the proposed master bus type `m68k_i_t` / `m68k_o_t` |
| `verify/` | Verilator harnesses: `tb/harte.cpp` suite runner (`build.sh`, `run_all.sh`, `run_family.sh`), `tb/lockstep.cpp` fx68k lockstep, `tb/mame8.cpp` MAME m68008 lockstep, `tb/mus010.cpp` / `tb/mus020.cpp` Musashi lockstep, `tb/rerun010.cpp` / `tb/rerun020.cpp` / `tb/loop010.cpp` directed 68010 / 68020 exception tests, `tb/dsz020.cpp` / `cache020.cpp` / `rmc020.cpp` / `cop020.cpp` / `tim020.cpp` directed 68020 bus / timing tests (`dsz020_build.sh`), `tb/amiga020.cpp` 68020 behaviour against the Amiberry / WinUAE results (`amiga020_build.sh`; `amiga020/` the Amiga test program), `tools/` (suite converter, exclusions, mkall, yosys estimate, `depth.py` path depth), `suite_exclusions.txt` |
| `syn/quartus/` | Quartus 17 size / timing test project (the user compiles it; `timing_paths.tcl` lists the worst paths) |

Rerun: `M68KSV_TESTS=<converted suite dir> verify/run_all.sh <build dir>` (`M68KSV_RES=1` in front of any
`verify/*build.sh` / `run_all.sh` builds the logic-heavy setting); every gate's command is in `REPORT.md`, section
"Handover". Fleet use: `rtl/m68ksv_fleet.sv` (same section).

# t80sv: SingleStepTests/z80 bench and the four fixes it found

Four fixes to t80sv (in `../../rtl`), each made the same way in the VHDL T80 0250 that t80sv was translated from
(`vhdl/`), plus the test bench and results used to check them. The patched t80sv and the patched VHDL stay
cycle-identical to each other.

| | SingleStepTests passed (of 1,604,000) | documented-behaviour failures | undocumented-only failures |
|---|---|---|---|
| t80sv as received = VHDL T80 0250 | 1,548,992 | 4,000 | 51,008 |
| after fix 1 | 1,552,992 | 0 | 51,008 |
| after fix 2 | 1,555,202 | 0 | 48,798 |
| after fix 3 | 1,597,051 | 0 | 6,949 |
| **after fix 4** | **1,604,000** | **0** | **0** |

A test passes only if everything matches: all registers including WZ (MEMPTR) and Q, every flag bit including
bits 5 / 3, RAM, I/O, the cycle count, the order of bus cycles, and the T-state of every MREQ / IORQ / RD / WR
strobe. ZEXDOC and ZEXALL pass 67 / 67 each after the fixes, as they did before (`../zexdoc_t80sv_output.txt`, `../zexall_t80sv_output.txt`).

## Contents

| path | what |
|---|---|
| `../../rtl/` | the fixes are in `t80sv_core.sv`, `t80sv_mcode.sv` and the regenerated `t80sv_all.sv` |
| `vhdl/` | T80 0250 (`T80.vhd` md5 `cd16504e...` before the change) with the same fixes in `T80.vhd` and `T80_MCode.vhd`, for the SV-vs-VHDL comparison |
| `patches/t80sv_fixes.patch` | the t80sv diff (paths `t80sv/rtl/...`) |
| `patches/T80_vhdl_fixes.patch` | the same fixes in the VHDL (paths `vhdl/...`), for the VHDL T80 in other cores |
| this directory | the Verilator test bench (below) |
| `results/` | `*_base_*` = before the fixes, `*_final_*` = after, `sv_fixN_summary.md` after each fix |

## The fixes

**1. DD / FD INC DE, DEC DE, INC BC, DEC BC** (`DD 13`, `DD 1B`, `FD 13`, `FD 1B`; the only documented-behaviour
failures). With an IX / IY prefix, `INC DE` incremented BC and `DEC DE` decremented BC: the `RegAddrA` selection for
the 16-bit increment covered "no prefix" and "pair = HL", and fell through to `RegAddrA_r` for the other pairs. The
first branch now also takes BC and DE under a prefix (`XY_State == 00 || !IncDec_16[1]`): a prefix only replaces HL
(Sean Young, *The Undocumented Z80 Documented*, 3.2). This is on T80's longest path (microcode -> RegAddrA -> register
file -> incrementer), so it is folded into the existing branch and uses only `IncDec_16[1]`, which the HL branch
already reads; a separate branch, or one using `IncDec_16[2]`, cost 3-4 MHz in Quartus.
`t80sv_core.sv` RegAddrA; `T80.vhd` RegAddrA.

**2. Q register: SCF / CCF flag bits 5 and 3** (`37`, `3F` and their DD / FD forms). On a Zilog Z80 these bits are
`(Q xor F) or A`, where Q = F if the previous instruction changed the flags and Q = 0 if it did not (Patrik Rak's
SCF / CCF research, 2018). The test vectors give the rule exactly: in all 1,604 opcode files the final `q` is either
always F or always 0, POP AF and EX AF,AF' leave 0, and a prefix counts as an instruction of its own. Because Q is
always 0 or F, one bit is enough (`QF`, "the previous instruction wrote F"): bits 5 / 3 = `A or (F and not QF)`.
`Fw` collects the flag writes of the instruction in progress; `fw_now` lists every write to F in the main
`always_ff` / process except POP AF, EX AF,AF', DIRSet and SET / RES (which write F back unchanged). An
instruction's last flag writes happen in T1 / T2 of the next opcode fetch while IR still holds the old opcode, so Fw
passes to QF at T3 of the opcode fetch and SCF / CCF read it at T4. Only Z80 modes (0, 1); 8080 and GB unchanged.
New: `QF`, `Fw`, `fw_now`, `fw_late` (`t80sv_core.sv` and `T80.vhd`).

**3. MEMPTR (WZ)** (about 60 opcode files). WZ is only visible through flag bits 5 / 3 of `BIT n,(HL)`, but the
tests check it directly. Rules from boo_boo and Vladimir Kladov, *MEMPTR, esoteric register of the ZiLOG Z80 CPU*:

| instruction | was | now | change |
|---|---|---|---|
| LD A,(BC) / LD A,(DE) | unchanged | rr + 1 | mcode `SetWZ = 01`; core: `aDE` handles 01 |
| LD A,(nn) | unchanged | nn + 1 | mcode `SetWZ = 01` in M3; core: `aZI` with 01 |
| LD (nn),rr / LD rr,(nn) (incl. ED and DD / FD forms) | nn | nn + 1 | core: `aZI` with `Inc_WZ` also does WZ + 1 |
| RET, RET cc taken | low byte only | return address | mcode `LDW` in M3, as RETN / RETI already did |
| OUT (n),A | (A·256 + n) + 1 | A, (n + 1) & FF | mcode `SetWZ = 10` (its meaning elsewhere: low + 1, high = A) |
| RLD / RRD | unchanged | HL + 1 | mcode `SetWZ = 01`; core: `aXY` with 01 |
| CPI / CPD (and CPIR / CPDR when they stop) | unchanged | WZ + 1 / - 1 | core, at the end of M2 |

**4. Repeating block instructions** (`ED B0`–`B3`, `B8`–`BB` while they repeat). While the instruction repeats, flag
bits 5 / 3 are bits 13 / 11 of PC, which is back at the instruction. For INIR / INDR / OTIR / OTDR, H and P/V also
change, and WZ = PC + 1:
- if C: when the byte had bit 7 set (N), P ^= parity((B - 1) & 7) and H = (B & 0x0F) == 0x00; otherwise
  P ^= parity((B + 1) & 7) and H = (B & 0x0F) == 0x0F;
- if not C: P ^= parity(B & 7).

B here is the decremented B. It is latched from BusA when the INI / OUTI P/V is computed (`BTR_B`), because the VHDL
register file is a separate entity. N and C are the INI / OUTI flags already set in M3. T80 runs MCycle 4 only when
the instruction repeats, so all of this happens at the end of MCycle 4 (`BlkRep`). LDIR / CPIR already set
WZ = PC + 1. These rules are the ones current emulators use, and the test vectors check every case.

## How it was tested

### The bench

A C++ / Verilator bench that drives a module named `T80pa` the way a MiSTer core does: one T-state is one `CLK`
with `CEN_p` followed by one `CLK` with `CEN_n`, and the pins are sampled after each half. The same bench code
runs both cores:

- **t80sv**: `t80sv_T80pa` (Mode 0) through `T80pa_sv.sv`, which only renames it to `T80pa`.
- **VHDL**: `T80pa.vhd` and the rest of `vhdl/`, turned into a Verilog netlist with `ghdl --synth` (GHDL 5.1.1).
  GHDL 5.1.1 drops the concurrent `DI_Reg <= DI;` of `T80.vhd` in synthesis, so the Makefile adds it back. With
  that fix, the same flow on T80 0247 gave a netlist whose pins matched a GHDL *simulation* of the VHDL on 320,800
  tests.

Files:
- `sst_main.cpp`: the test runner (SingleStepTests, a CP/M BDOS stub for ZEX, interrupt cases, pin dump).
- `harness.h`: flat 64 KB memory, I/O ports, a bus-cycle recorder, and an optional M1 wait-state circuit.
- `cpu_t80.h`: the T80pa adapter.
- `tools/sst_convert.py`: converts the SingleStepTests JSON to text.
- `tools/sst_report.py`: writes the Markdown summaries.

**Loading a test.** The bench resets the core, then loads registers through the core's own `DIRSet` / `DIR`
port. WZ and Q are not in `DIR` / `REG`, so it writes and reads them directly:
- t80sv: `WZ` and `Fw` in `t80sv_core`, through `gen_sv/t80.vlt` and `gen_sv/t80_wz.h`.
- VHDL netlist: the netlist registers behind the `wz` and `fw` signals, found by the Makefile.

**Ending a test.** Memory not in the test reads 00 (NOP). The instruction ends at the (n+1)-th M1, where n is the
number of opcode fetches (1, or 2 with a CB / ED / DD / FD prefix, and 2 for DD CB d op).
- Final PC is the address of that M1.
- R and I are the refresh address of that M1, i.e. what the pins show.
- The other registers are read after T3 of that fetch.
- T-states are the distance between the first M1 and that one.

**What is compared:**
- A, F (documented flags and bits 5 / 3 separately), BC, DE, HL, IX, IY, SP, PC, the alternate set, I, R.
- IFF1, IFF2, IM, WZ and Q.
- RAM and I/O writes.
- T-states, and the ordered list of bus cycles (memory or I/O, read or write, address, data).
- The T-state of every strobe. SingleStepTests shows each strobe as a one-sample pulse, and T80pa's strobes
  sit at a fixed offset from that, the same for every instruction (`DELTA` in the Makefile). A strobe anywhere
  else fails.

A test fails as **documented behaviour** when anything other than flag bits 5 / 3, WZ, Q or strobe position is
wrong, using the flags the Zilog manual defines for the instruction.

**Interrupts** (`irq`): IM 0 / 1 / 2, NMI, from HALT, and the EI delay. The bench checks the acknowledge length,
the pushed PC, and the bus cycles of the acknowledge, each with and without one M1 wait state (`--m1wait`, the
SVI-328's 74LS74 circuit).

### Checks run

All of these ran after each fix, with Verilator 5.044 and GHDL 5.1.1 on macOS (arm64).

- **SingleStepTests/z80 v1** (commit `ebe1875d`), all 1,604,000 cases, on t80sv and on the VHDL. The result
  files are identical between the two after every fix (`results/sv_final_sst.tsv`, `results/vhdl_final_sst.tsv`).
- **Pin by pin**, t80sv against VHDL: the first 100 cases of every opcode file (160,400 tests). Every pin at
  every half T-state, and REG at the end, are identical. Before the fixes, t80sv against the stock VHDL was
  identical too.
- **Interrupt timing**: identical between t80sv and VHDL, and unchanged from the original, with and without the
  M1 wait state. Every case is exact against a real Z80.
- **ZEXDOC / ZEXALL** on the patched t80sv: 67 / 67 OK each (`results/sv_final_zex*.log`, about 46.7 billion
  T-states each).
- **Modes 1 / 2 / 3.** The bench built `t80sv_T80pa` with Mode 1, 2 and 3, as received and patched, and ran the
  same 160,400 test programs (executed as 8080 / GB code in modes 2 / 3).
  - Modes 2 and 3: every pin at every half T-state and REG at the end are identical. The Q and block-flag logic
    is gated to modes 0 / 1, and in the 8080 / GB paths the WZ changes only reach WZ itself, after its last use.
  - Mode 1 changes the same way as Mode 0.
- **Verilator lint** `-Wall` with `t80sv_lint.vlt`, on all 11 drop-in tops: the same two warnings as the original
  (`PROCASSINIT` on BusReq_s / BusAck, which Verilator 5.044 reports and older versions did not). Nothing new.
- **SingleStepTests with one M1 wait state** (`results/sv_final_sst_m1wait.tsv`): everything passes except
  IFF1 / IFF2 after `EI`.
  - T80 sets IFF in T2 of the next opcode fetch, and the wait state moves T2 past the bench's sample point.
  - The original T80 does the same.
  - Interrupts are still accepted at the right point: the irq case "INT low before EI" is exact. So this is a
    sample-point effect, not a bug.
- **Quartus 17.0.2** (Cyclone V 5CSEBA6U23I7, the MiSTer's), `t80sv_T80pa` / VHDL `T80pa` alone with virtual
  pins, constrained at 42.95 MHz, several fitter seeds: 0 errors for all; t80sv's `tri1` / `tri0` port defaults are
  accepted. Slow 1100 mV 100 C Fmax:

  | | ALMs | registers | Fmax (per seed) |
  |---|---|---|---|
  | t80sv as received | 1,207-1,216 | 360 | 59.7, 59.8, 60.1, 60.3 MHz |
  | t80sv patched | 1,278-1,289 | 366 | 55.2, 59.4, 60.8 MHz |
  | VHDL T80 0250 | 1,143-1,146 | 360 | 60.4, 60.4, 60.8 MHz |
  | VHDL patched | 1,211-1,215 | 366 | 60.9, 66.1 MHz |

  About +70 ALMs (6 registers: QF, Fw, BTR_B[3:0]); Fmax within the seed-to-seed spread.
- **In a full core**: the MiSTer SVI-318/328 core now uses the patched `t80sv_T80pa` in place of the VHDL T80pa
  (0247), at 3.58 MHz and in a 14.3 MHz turbo mode, with an M1 wait state, on a 42.95 MHz clock.
  - The Quartus 17.0.2 build has 0 errors and meets timing: 65.6 MHz Fmax against 60.7 MHz with the VHDL T80.
  - In that core's Verilator simulator, Disk BASIC, CP/M at 80 columns, a cartridge game and a tape load give
    the same frames as before.

### Reproducing

    cd t80sv/verify/sst
    make vectors                  # SingleStepTests (git, 1.3 GB of JSON) + ZEXDOC / ZEXALL (sha1-checked)
    ./check.sh final              # both cores: SST, irq, sv == vhdl, pins; about 3 minutes
    make sst EXE=sv TAG=x         # t80sv only -> results/sv_x_summary.md
    make sst-one OP=ed_b0         # one opcode file, first failures printed
    make zex EXE=sv               # ZEXDOC + ZEXALL, about 3 hours each (in parallel)
    make modes ORIG=/path/to/t80sv-as-received/rtl
    make lint

`make vectors` only downloads and parses data: the JSON is converted by `tools/sst_convert.py`, and the ZEX
programs run only inside the simulated CPU. The bench needs Verilator 5, python3, git and curl, and GHDL with
`--synth` for the VHDL build.

## Notes

- `t80sv_mcode.sv` is generated from `T80_MCode.vhd` by `verify/tools/mcode2sv.py`. The 8 added microcode lines
  were made by hand in both files, so regenerating from the patched VHDL should give the same SV. That script was
  not run here.
- `t80sv_all.sv` was regenerated by joining the five files with the same header and section markers. The same
  method reproduces the original file byte for byte.
- The lockstep harness in `../` was not run; everything here comes from this bench.

## References

- SingleStepTests/z80: https://github.com/SingleStepTests/z80
- Sean Young, *The Undocumented Z80 Documented*.
- boo_boo and Vladimir Kladov, *MEMPTR, esoteric register of the ZiLOG Z80 CPU*.
- Patrik Rak, SCF / CCF and the Q register (2018).
- ZEXDOC / ZEXALL: Frank Cringle, files from https://github.com/anotherlin/z80emu (`zex.sha1`).

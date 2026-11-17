# t80sv — SystemVerilog T80, cycle-identical replacement: report

T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and
contributors (MiSTer-devel lineage); T80a bus timing by Fabio Belavenuto and Charlie Ingley; Phoenix 8080 / 8085
additions by Rodimus. t80sv is a translation of that code and keeps its license (full text at the end).

**Oracle:** stock `rtl/cpu/T80/` of `RodimusFVC/Arcade-SegaG80_MiSTer` (`md5(T80.vhd)` = `cd16504e7a8cad068c5dfe891857a5f8`;
the same files byte-for-byte in all 12 fleet repos that carry a T80 folder) and the Phoenix copy
(`d4956f049a77e7532393baee8ce54b2c`). Every md5 is re-checked by `verify/gen_ref.py` before conversion. The reference
sources were not modified.

## 1. Parity table

Every top, generic, port and mode of the reference → where it lives → how it was verified. "Lockstep" = GHDL model
of that exact top + generic value vs. the t80sv drop-in, same stimulus, every output and every register (T80 core +
front end) compared after both clock edges and every async-reset change (section 3).

### Tops (drop-in modules in `rtl/t80sv_tops.sv`, same port names, same generics as parameters)

| reference top | t80sv module | generic values verified (each its own GHDL model) |
|---|---|---|
| `T80` (bare CPU entity) | `t80sv_T80` | Mode 0,1,2,3 × IOWait 0,1 (Z80 flag positions); Mode 3 × IOWait 0,1 with GB flag positions (Flag_C=4, H=5, N=6, Z=7, S=P=X=Y=0) |
| `T80` Phoenix entity | `t80sv_T80_phx` | Mode_g 0,1,2,3 × IOWait 0,1 |
| `T80s` | `t80sv_T80s` | Mode 0,1,2,3 × T2Write 0,1 × IOWait 0,1 (16) |
| `T80se` | `t80sv_T80se` | Mode 0,1,2,3 × T2Write 0,1 × IOWait 0,1 (16) |
| `T80sed` | `t80sv_T80sed` | (no generics) |
| `T80pa` | `t80sv_T80pa` | Mode 0,1,2,3 |
| `T80pa` Phoenix | `t80sv_T80pa_phx` | Mode 0,1,2,3 |
| `T8080se` | `t80sv_T8080se` | Mode 0,1,2,3 × T2Write 0,1 |
| `GBse` | `t80sv_GBse` | T2Write 0,1 × IOWait 0,1 |
| `T80a` | `t80sv_T80a` | Mode 0,1,2,3 × IOWait 0,1 |
| `T80as` | `t80sv_T80as` | Mode 0,1,2,3 |

All of them are thin wrappers over **one** module, `t80sv` (`rtl/t80sv.sv`: parameters `MODE, T2WRITE, IOWAIT, BUS,
Flag_*`; superset port list), which contains the CPU `t80sv_core` (= `T80.vhd` + `T80_Reg.vhd`), `t80sv_mcode`
(= `T80_MCode.vhd`) and `t80sv_alu` (= `T80_ALU.vhd`). `BUS` selects the front end: 0 T80s / T80se, 1 T80sed, 2 T80pa,
3 T8080se, 4 GBse, 5 T80a, 6 T80as.

### Generics / parameters

| generic | where | verified |
|---|---|---|
| `Mode` 0 Z80 / 1 fast Z80 / 2 8080 / 3 GB | `MODE` on every module; runtime `mode` signal in the core | all four values on every top that has the generic (T8080se and T80pa included) |
| `Mode_g` (Phoenix) + runtime `I8080` | `MODE` + `i8080` input: mode = 2 while I8080 = 1 on a MODE 0 build, as Phoenix | all Mode_g values; I8080 / I8085 toggled at random times in the Phoenix lockstep |
| `T2Write` 0 / ≠0 | `T2WRITE` (BUS_S, BUS_8080SE, BUS_GB) | both values on T80s, T80se, T8080se, GBse |
| `IOWait` 0 / 1 | `IOWAIT` (core; forced 1 by T80sed / T80pa / T80as as in the VHDL) | both values on T80, T80s, T80se, GBse, T80a |
| `Flag_C/N/P/X/H/Y/Z/S` (bit positions) | parameters of `t80sv`, `t80sv_core`, `t80sv_alu`, `t80sv_mcode`, `t80sv_T80` | Z80 defaults everywhere; GB mapping via GBse and `t80_m3gb_*` |

Integer generics are compared exactly as the VHDL does (`IOWait = 1`, `T2Write = 0`, `Mode` 0..3); `Mode` values above 3
are outside the reference's documented range (Phoenix declares `Mode : integer range 0 to 3`) and are not supported.

### Ports and features

| reference port / feature | t80sv | verified |
|---|---|---|
| RESET_n (async in T80 / T80s / se / sed / 8080se / GBse; sync in T80pa front end; T80a / T80as resynchronised `Reset_s`) | same per front end | lockstep incl. random async resets mid-instruction and reset held from time 0 |
| CLK / CLK_n, CEN / CLKEN | `clk`, `cen` | random enable patterns (always, random, periodic, bursty) |
| CEN_p / CEN_n (T80pa) | `cen_p`, `cen_n` | alternating, gapped, independent random, both-per-clock patterns |
| WAIT_n / READY | `wait_n` | random stretches; directed sweep at every clock offset |
| INT_n / INT (8080, active high) | `int_n` | random level / duration; IM 0 / 1 / 2 (random vectors, RST and arbitrary opcodes in IM 0); sweeps |
| NMI_n | `nmi_n` | random pulses; sweeps |
| BUSRQ_n / BUSAK_n; HOLD / HLDA | `busrq_n`, `busak_n`, `hlda` | random stretches; sweeps. T8080se ignores HOLD (core BUSRQ_n tied '1' in the VHDL) — kept |
| M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, A, DO, DI | same | every clock |
| OUT0 (OUT (C),0 vs 255) | `out0` | randomised per segment on T80s / T80pa / T80 |
| R800_mode (MULUB / MULUW) | `r800_mode`; multiplier in `t80sv_core` | randomised on T80pa / T80a / T80 |
| REG[211:0] register dump | `reg_o` / `REG` | compared every clock on T80pa / T80 tops |
| DIRSet / DIR[211:0] register load | `dirset`, `dir` | random DIRSet pulses with random DIR on T80pa / T80 tops |
| IntE (= IFF1; fleet `inte`), Stop, MC, TS, IORQ, NoRead, Write, IntCycle_n, DInst / DI split | outputs of `t80sv_core` / `t80sv_T80` | compared every clock on the bare-T80 configurations |
| STOP (GBse) | `stop` | GBse lockstep |
| T80a tri-state bus (A, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n released while BUSAK_n low; inout D) | `t80sv_T80a` (real `tri` / `inout`); `t80sv` exposes `bus_oe` / `doe` | resolved pins **and** pre-tri-state values and enables compared |
| T80as DOE | `doe` | lockstep |
| T8080se DBIN, SYNC, VAIT, HLDA, INTE, status word on DO in T1 | `dbin`, `sync`, `vait`, `hlda`, `inte`, `dout` | lockstep (Mode 0..3) |
| Phoenix I8080 / I8085 / RIM_D / SOD (8085 RIM opcode 20, SIM opcode 30) | `i8080`, `i8085`, `rim_d`, `sod` | Phoenix T80pa and T80 entity lockstep, inputs toggled at random |
| VHDL port default values (T80s: CEN, WAIT_n, INT_n, NMI_n, BUSRQ_n = '1', OUT0 = '0'; T80pa: CEN_p, CEN_n, WAIT_n, INT_n, NMI_n, BUSRQ_n = '1', OUT0, R800_mode, DIRSet = '0', DIR = 0; T80: R800_mode, out0, DIRSet, DIR; Phoenix I8080, I8085, RIM_D) | `tri1` / `tri0` input nets on the drop-ins | `verify/tests/port_defaults_tb.sv` (Tutankham-style instance leaving WAIT_n, NMI_n, BUSRQ_n, OUT0 open) |
| Undocumented Z80: SLL, DD/FD CB register copies (XYbit_undoc), IXH/IXL/IYH/IYL, OUT (C),0, IN F,(C), X/Y flags, MEMPTR (WZ) | microcode / core as T80 | random streams weighted evenly over all 7 opcode pages; coverage below |
| GB mode (LDI / LDD, LD (nn),SP, LDH, ADD SP,e, LD HL,SP+e, SWAP, STOP, RETI, GB interrupt timing, halt bug) | same microcode / core paths | GBse and T80 Mode 3 lockstep |
| T80 quirks vs silicon (SCF / CCF X/Y, etc.) | kept as T80 | acceptance is "identical to T80" |

Nothing of the reference was left out. Code that is dead in every reference top is still carried, e.g. the GB
branches of the core under `T80s` with Z80 flag positions, R800 MULU under tops that tie `R800_mode` low, the
`out0` path on T80se (no OUT0 port), and `HOLD` on T8080se.

### Fleet bus-type wrappers (`rtl/t80sv_fleet.sv`)

| type | module | replaces | verified |
|---|---|---|---|
| `z80_i_t` / `z80_o_t` | `t80sv_z80` (MODE, T2WRITE, IOWAIT) | T80s | lockstep vs T80s 0/1/1 |
| `z80r_i_t` | `t80sv_z80r` | T80s (Konami82, T2Write 1) / T80se (Galaga, T2Write 0) | both, lockstep |
| `z80w_i_t` | `t80sv_z80w` | T80s with WAIT_n | lockstep |
| `z80sed_i_t` | `t80sv_z80sed` | T80sed | lockstep |
| `z80pa_i_t` / `z80pa_o_t` | `t80sv_z80pa` (`inte` = IFF1 = REG bit 210) | T80pa | lockstep |
| `z80pa85_i_t` / `z80pa85_o_t` | `t80sv_z80pa85` | Phoenix T80pa | lockstep |

Folding the six types into one later: `t80sv` already has the superset port list (`cen` + `cen_p` / `cen_n`,
`wait_n`, `busrq_n`, `i8080`, `i8085`, `rim_d`, …) with `BUS` / `T2WRITE` as parameters, so one struct type
mapping 1:1 onto those ports plus the parameters replaces all six wrappers.

## 2. Results summary

| check | scope | result |
|---|---|---|
| Lockstep, random | 83 reference configurations (every top × every generic value) + 7 fleet wrappers; fleet configs 4 × 25 M cycles, others 2 × 5 M | **0 mismatches** (187 jobs) |
| Directed timing sweeps | every opcode of every page (7 pages Z80 modes, base + CB GB, base 8080) × INT (IM 0/1/2), NMI, WAIT, BUSRQ, INT+NMI (IM 0/1/2) × 64 clock offsets from the instruction's first M1 (covers every T-state and enable phase of the longest instruction plus the next one), 3 enable patterns | **0 mismatches** (762 jobs) |
| ZEXDOC / ZEXALL in lockstep | all 134 tests, first 4 M cycles each, on the 5 Z80 fleet configs (T80s 0/1/1, T80pa, Phoenix T80pa, T80sed, T80se 0/0/1) | **0 mismatches**; 42–44 tests per config run to completion inside the window and print OK |
| ZEXDOC / ZEXALL full | t80sv alone (T80s Mode 0), 134 runs, 93.47 G cycles | **ZEXDOC 67/67 OK, ZEXALL 67/67 OK** (`verify/zexdoc_t80sv_output.txt`, `verify/zexall_t80sv_output.txt`) |
| 8080 exercisers in lockstep | TST8080, CPUTEST, 8080PRE, 8080EXM (8080EXM bounded at 400 M cycles) on every Mode 2 configuration + Phoenix T80pa / T80 with I8080 = 1 | **0 mismatches** (84 jobs) |
| Port defaults | Tutankham-style `T80s` instance with WAIT_n, NMI_n, BUSRQ_n, OUT0 open | runs (`verify/tests/port_defaults_tb.sv`) |
| Harness sanity | mutants (flag logic, ALU SET, T80pa strobe timing) | all caught |
| Lint | `verilator --lint-only -Wall` on all 17 module tops | clean with 3 waivers (section 5) |

Total lockstep cycles: **28,990,343,160**, plus 93.5 G single-model ZEX cycles.

**Not done: a full-length ZEXDOC / ZEXALL run of the GHDL reference model.** The reference model simulates at about
0.7 M cycles/s, so the 93.5 G cycles would take roughly 26 core-hours; that did not fit the session's time and budget.
"Matches the reference's output" therefore rests on (a) the cycle-exact lockstep of every ZEX test over its first 4 M
cycles on five configurations (identical pins and identical internal registers every clock, so identical output
text for the 42–44 tests that finish inside the window), (b) 29 G further lockstep cycles of random and directed
stimulus, and (c) the T80 README's statement that this T80 passes ZEXDOC / ZEXALL, which the new core's full run
reproduces (all OK). The full reference run is one command if wanted (section 4).

### Per configuration

Columns: random lockstep cycles (jobs); sweep cases per event; sweep cycles; ZEX lockstep tests (cycles); number of
distinct opcodes executed in lockstep per page base / CB / ED / DD / FD / DDCB / FDCB (GB mode has only base and CB,
8080 mode only base; the fleet-wrapper rows are a single 5 M-cycle field-mapping check each on top of the fully
covered top they wrap).

| configuration | top | generics | random cycles (jobs) | sweep cases INT/NMI/WAIT/BUSRQ/INT+NMI | sweep cycles | ZEX lockstep tests (cycles) | opcodes hit base/CB/ED/DD/FD/DDCB/FDCB | result |
|---|---|---|---|---|---|---|---|---|
| t80s_m0_t1_w1 (fleet) | T80s | Mode=0, T2Write=1, IOWait=1 | 100,001,210 (4) | 344064/114688/114688/114688/344064 | 331,906,847 | 134 (399,978,342) | 256 256 256 256 256 256 256 | PASS |
| t80pa_m0 (fleet) | T80pa | Mode=0 | 100,001,240 (4) | 344064/114688/114688/114688/344064 | 468,385,483 | 134 (437,950,418) | 256 256 256 256 256 256 256 | PASS |
| t80se_m0_t0_w1 (fleet) | T80se | Mode=0, T2Write=0, IOWait=1 | 100,001,212 (4) | 344064/114688/114688/114688/344064 | 331,928,664 | 134 (399,978,430) | 256 256 256 256 256 256 256 | PASS |
| phx_t80pa_m0 (fleet) | T80pa (Phoenix) | Mode=0 | 100,001,136 (4) | 344064/114688/114688/114688/344064 | 468,385,483 | 134 (437,950,418) | 256 256 256 256 256 256 256 | PASS |
| t80sed (fleet) | T80sed |  | 100,001,278 (4) | 344064/114688/114688/114688/344064 | 331,914,321 | 134 (399,978,342) | 256 256 256 256 256 256 256 | PASS |
| t8080se_m2_t1 (fleet) | T8080se | Mode=2, T2Write=1 | 100,001,198 (4) | 16384/16384/16384/0/16384 | 16,013,692 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t8080se_m2_t0 (fleet) | T8080se | Mode=2, T2Write=0 | 100,001,242 (4) | 16384/16384/16384/0/16384 | 16,013,692 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80s_m0_t0_w0 | T80s | Mode=0, T2Write=0, IOWait=0 | 10,000,126 (2) | 344064/114688/114688/114688/344064 | 331,923,100 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m0_t0_w1 | T80s | Mode=0, T2Write=0, IOWait=1 | 10,000,114 (2) | 344064/114688/114688/114688/344064 | 331,928,664 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m0_t1_w0 | T80s | Mode=0, T2Write=1, IOWait=0 | 10,000,113 (2) | 344064/114688/114688/114688/344064 | 331,930,646 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m1_t0_w0 | T80s | Mode=1, T2Write=0, IOWait=0 | 10,000,139 (2) | 344064/114688/114688/114688/344064 | 331,932,683 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m1_t0_w1 | T80s | Mode=1, T2Write=0, IOWait=1 | 10,000,125 (2) | 344064/114688/114688/114688/344064 | 331,919,664 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m1_t1_w0 | T80s | Mode=1, T2Write=1, IOWait=0 | 10,000,111 (2) | 344064/114688/114688/114688/344064 | 331,925,091 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m1_t1_w1 | T80s | Mode=1, T2Write=1, IOWait=1 | 10,000,125 (2) | 344064/114688/114688/114688/344064 | 331,932,545 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80s_m2_t0_w0 | T80s | Mode=2, T2Write=0, IOWait=0 | 10,000,127 (2) | 16384/16384/16384/16384/16384 | 20,164,890 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80s_m2_t0_w1 | T80s | Mode=2, T2Write=0, IOWait=1 | 10,000,131 (2) | 16384/16384/16384/16384/16384 | 20,165,499 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80s_m2_t1_w0 | T80s | Mode=2, T2Write=1, IOWait=0 | 10,000,139 (2) | 16384/16384/16384/16384/16384 | 20,165,249 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80s_m2_t1_w1 | T80s | Mode=2, T2Write=1, IOWait=1 | 10,000,156 (2) | 16384/16384/16384/16384/16384 | 20,158,280 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80s_m3_t0_w0 | T80s | Mode=3, T2Write=0, IOWait=0 | 10,000,107 (2) | 32768/32768/32768/32768/32768 | 42,402,717 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80s_m3_t0_w1 | T80s | Mode=3, T2Write=0, IOWait=1 | 10,000,119 (2) | 32768/32768/32768/32768/32768 | 42,411,160 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80s_m3_t1_w0 | T80s | Mode=3, T2Write=1, IOWait=0 | 10,000,114 (2) | 32768/32768/32768/32768/32768 | 42,396,593 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80s_m3_t1_w1 | T80s | Mode=3, T2Write=1, IOWait=1 | 10,000,120 (2) | 32768/32768/32768/32768/32768 | 42,407,366 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80se_m0_t0_w0 | T80se | Mode=0, T2Write=0, IOWait=0 | 10,000,118 (2) | 344064/114688/114688/114688/344064 | 331,923,100 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m0_t1_w0 | T80se | Mode=0, T2Write=1, IOWait=0 | 10,000,135 (2) | 344064/114688/114688/114688/344064 | 331,930,646 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m0_t1_w1 | T80se | Mode=0, T2Write=1, IOWait=1 | 10,000,116 (2) | 344064/114688/114688/114688/344064 | 331,906,847 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m1_t0_w0 | T80se | Mode=1, T2Write=0, IOWait=0 | 10,000,117 (2) | 344064/114688/114688/114688/344064 | 331,932,683 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m1_t0_w1 | T80se | Mode=1, T2Write=0, IOWait=1 | 10,000,141 (2) | 344064/114688/114688/114688/344064 | 331,919,664 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m1_t1_w0 | T80se | Mode=1, T2Write=1, IOWait=0 | 10,000,120 (2) | 344064/114688/114688/114688/344064 | 331,925,091 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m1_t1_w1 | T80se | Mode=1, T2Write=1, IOWait=1 | 10,000,122 (2) | 344064/114688/114688/114688/344064 | 331,932,545 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80se_m2_t0_w0 | T80se | Mode=2, T2Write=0, IOWait=0 | 10,000,121 (2) | 16384/16384/16384/16384/16384 | 20,164,890 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80se_m2_t0_w1 | T80se | Mode=2, T2Write=0, IOWait=1 | 10,000,102 (2) | 16384/16384/16384/16384/16384 | 20,165,499 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80se_m2_t1_w0 | T80se | Mode=2, T2Write=1, IOWait=0 | 10,000,124 (2) | 16384/16384/16384/16384/16384 | 20,165,249 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80se_m2_t1_w1 | T80se | Mode=2, T2Write=1, IOWait=1 | 10,000,119 (2) | 16384/16384/16384/16384/16384 | 20,158,280 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80se_m3_t0_w0 | T80se | Mode=3, T2Write=0, IOWait=0 | 10,000,130 (2) | 32768/32768/32768/32768/32768 | 42,402,717 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80se_m3_t0_w1 | T80se | Mode=3, T2Write=0, IOWait=1 | 10,000,132 (2) | 32768/32768/32768/32768/32768 | 42,411,160 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80se_m3_t1_w0 | T80se | Mode=3, T2Write=1, IOWait=0 | 10,000,154 (2) | 32768/32768/32768/32768/32768 | 42,396,593 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80se_m3_t1_w1 | T80se | Mode=3, T2Write=1, IOWait=1 | 10,000,120 (2) | 32768/32768/32768/32768/32768 | 42,407,366 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t8080se_m0_t0 | T8080se | Mode=0, T2Write=0 | 10,000,133 (2) | 344064/114688/114688/0/344064 | 294,574,592 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t8080se_m0_t1 | T8080se | Mode=0, T2Write=1 | 10,000,131 (2) | 344064/114688/114688/0/344064 | 294,574,592 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80a_m0_w0 | T80a | Mode=0, IOWait=0 | 10,000,132 (2) | 344064/114688/114688/114688/344064 | 289,979,700 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80_m0_w0 | T80 | Mode=0, IOWait=0 | 10,000,127 (2) | 344064/114688/114688/114688/344064 | 331,921,271 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| phx_t80_m0_w0 | T80 (Phoenix) | Mode_g=0, IOWait=0 | 10,000,109 (2) | 344064/114688/114688/114688/344064 | 331,921,271 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80a_m0_w1 | T80a | Mode=0, IOWait=1 | 10,000,132 (2) | 344064/114688/114688/114688/344064 | 289,984,144 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80_m0_w1 | T80 | Mode=0, IOWait=1 | 10,000,126 (2) | 344064/114688/114688/114688/344064 | 331,905,703 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| phx_t80_m0_w1 | T80 (Phoenix) | Mode_g=0, IOWait=1 | 10,000,138 (2) | 344064/114688/114688/114688/344064 | 331,905,703 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80as_m0 | T80as | Mode=0 | 10,000,118 (2) | 344064/114688/114688/114688/344064 | 289,994,449 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80pa_m1 | T80pa | Mode=1 | 10,000,125 (2) | 344064/114688/114688/114688/344064 | 468,380,920 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| phx_t80pa_m1 | T80pa (Phoenix) | Mode=1 | 10,000,113 (2) | 344064/114688/114688/114688/344064 | 468,380,920 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t8080se_m1_t0 | T8080se | Mode=1, T2Write=0 | 10,000,124 (2) | 344064/114688/114688/0/344064 | 294,586,250 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t8080se_m1_t1 | T8080se | Mode=1, T2Write=1 | 10,000,124 (2) | 344064/114688/114688/0/344064 | 294,586,250 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80a_m1_w0 | T80a | Mode=1, IOWait=0 | 10,000,112 (2) | 344064/114688/114688/114688/344064 | 289,990,490 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80_m1_w0 | T80 | Mode=1, IOWait=0 | 10,000,124 (2) | 344064/114688/114688/114688/344064 | 331,918,590 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| phx_t80_m1_w0 | T80 (Phoenix) | Mode_g=1, IOWait=0 | 10,000,128 (2) | 344064/114688/114688/114688/344064 | 331,918,590 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80a_m1_w1 | T80a | Mode=1, IOWait=1 | 10,000,125 (2) | 344064/114688/114688/114688/344064 | 289,994,323 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80_m1_w1 | T80 | Mode=1, IOWait=1 | 10,000,116 (2) | 344064/114688/114688/114688/344064 | 331,929,574 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| phx_t80_m1_w1 | T80 (Phoenix) | Mode_g=1, IOWait=1 | 10,000,142 (2) | 344064/114688/114688/114688/344064 | 331,929,574 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80as_m1 | T80as | Mode=1 | 10,000,143 (2) | 344064/114688/114688/114688/344064 | 289,998,084 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| t80pa_m2 | T80pa | Mode=2 | 10,000,139 (2) | 16384/16384/16384/16384/16384 | 25,755,112 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| phx_t80pa_m2 | T80pa (Phoenix) | Mode=2 | 10,000,138 (2) | 16384/16384/16384/16384/16384 | 25,755,112 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80a_m2_w0 | T80a | Mode=2, IOWait=0 | 10,000,110 (2) | 16384/16384/16384/16384/16384 | 18,492,699 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80_m2_w0 | T80 | Mode=2, IOWait=0 | 10,000,121 (2) | 16384/16384/16384/16384/16384 | 20,159,170 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| phx_t80_m2_w0 | T80 (Phoenix) | Mode_g=2, IOWait=0 | 10,000,131 (2) | 16384/16384/16384/16384/16384 | 20,159,170 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80a_m2_w1 | T80a | Mode=2, IOWait=1 | 10,000,121 (2) | 16384/16384/16384/16384/16384 | 18,483,948 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80_m2_w1 | T80 | Mode=2, IOWait=1 | 10,000,151 (2) | 16384/16384/16384/16384/16384 | 20,162,822 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| phx_t80_m2_w1 | T80 (Phoenix) | Mode_g=2, IOWait=1 | 10,000,128 (2) | 16384/16384/16384/16384/16384 | 20,162,822 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80as_m2 | T80as | Mode=2 | 10,000,136 (2) | 16384/16384/16384/16384/16384 | 18,490,472 | 0 (0) | 256 0 0 0 0 0 0 | PASS |
| t80pa_m3 | T80pa | Mode=3 | 10,000,114 (2) | 32768/32768/32768/32768/32768 | 55,317,581 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| phx_t80pa_m3 | T80pa (Phoenix) | Mode=3 | 10,000,112 (2) | 32768/32768/32768/32768/32768 | 55,317,581 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t8080se_m3_t0 | T8080se | Mode=3, T2Write=0 | 10,000,124 (2) | 32768/32768/32768/0/32768 | 33,685,963 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t8080se_m3_t1 | T8080se | Mode=3, T2Write=1 | 10,000,129 (2) | 32768/32768/32768/0/32768 | 33,685,963 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80a_m3_w0 | T80a | Mode=3, IOWait=0 | 10,000,122 (2) | 32768/32768/32768/32768/32768 | 38,452,613 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80_m3_w0 | T80 | Mode=3, IOWait=0 | 10,000,125 (2) | 32768/32768/32768/32768/32768 | 42,407,044 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| phx_t80_m3_w0 | T80 (Phoenix) | Mode_g=3, IOWait=0 | 10,000,131 (2) | 32768/32768/32768/32768/32768 | 42,407,044 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80a_m3_w1 | T80a | Mode=3, IOWait=1 | 10,000,150 (2) | 32768/32768/32768/32768/32768 | 38,447,704 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80_m3_w1 | T80 | Mode=3, IOWait=1 | 10,000,122 (2) | 32768/32768/32768/32768/32768 | 42,407,972 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| phx_t80_m3_w1 | T80 (Phoenix) | Mode_g=3, IOWait=1 | 10,000,136 (2) | 32768/32768/32768/32768/32768 | 42,407,972 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80as_m3 | T80as | Mode=3 | 10,000,131 (2) | 32768/32768/32768/32768/32768 | 38,453,530 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| gbse_t0_w0 | GBse | T2Write=0, IOWait=0 | 10,000,131 (2) | 32768/32768/32768/32768/32768 | 42,410,444 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| gbse_t0_w1 | GBse | T2Write=0, IOWait=1 | 10,000,118 (2) | 32768/32768/32768/32768/32768 | 42,403,532 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| gbse_t1_w0 | GBse | T2Write=1, IOWait=0 | 10,000,145 (2) | 32768/32768/32768/32768/32768 | 42,407,968 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| gbse_t1_w1 | GBse | T2Write=1, IOWait=1 | 10,000,130 (2) | 32768/32768/32768/32768/32768 | 42,408,650 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80_m3gb_w0 | T80 | Mode=3, IOWait=0 GB flags | 10,000,168 (2) | 32768/32768/32768/32768/32768 | 42,404,925 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| t80_m3gb_w1 | T80 | Mode=3, IOWait=1 GB flags | 10,000,107 (2) | 32768/32768/32768/32768/32768 | 42,403,449 | 0 (0) | 256 256 0 0 0 0 0 | PASS |
| fleet_z80 | T80s | Mode=0, T2Write=1, IOWait=1 | 5,000,067 (1) | - | 0 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| fleet_z80r | T80s | Mode=0, T2Write=1, IOWait=1 | 5,000,067 (1) | - | 0 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| fleet_z80r_t0 | T80se | Mode=0, T2Write=0, IOWait=1 | 5,000,050 (1) | - | 0 | 0 (0) | 256 256 256 255 256 256 256 | PASS |
| fleet_z80w | T80s | Mode=0, T2Write=1, IOWait=1 | 5,000,071 (1) | - | 0 | 0 (0) | 256 256 255 255 256 256 256 | PASS |
| fleet_z80sed | T80sed |  | 5,000,069 (1) | - | 0 | 0 (0) | 256 256 256 256 256 256 256 | PASS |
| fleet_z80pa | T80pa | Mode=0 | 5,000,050 (1) | - | 0 | 0 (0) | 256 255 255 255 254 253 252 | PASS |
| fleet_z80pa85 | T80pa (Phoenix) | Mode=0 | 5,000,080 (1) | - | 0 | 0 (0) | 256 256 238 234 242 238 238 | PASS |

Total lockstep cycles: 28,990,343,160; failing jobs: 0 []


## 3. How the verification works

- `verify/gen_ref.py` checks both md5s, then converts each reference top with GHDL 4.1 `--synth --out=verilog`, one
  model per configuration (`verify/configs.py`). Post-processing only renames modules (so models can coexist), works
  around two GHDL Verilog-output defects (an instance-port wire colliding with a signal name; an escaped identifier
  inside a plain one) and wraps the file in `` `begin_keywords "1364-2005" `` (GHDL uses `do` as a name).
- `verify/tb/tbgen.py` generates a Verilator top holding the reference model and the t80sv drop-in of the same top
  with identical port maps. Compared after every rising edge, every falling edge (T80a / T80as use both) and every
  async reset change: all outputs, REG where present, the pre-tri-state pins and enables of T80a, and every register
  of the core (A, F, A', F', I, R, SP, PC, WZ, IR, ISet, XY_State, IM, IFF1, IFF2, HALT, Alternate, the 16 register
  file bytes, MCycle / TState / MCycles, BusA / BusB, Read_To_Reg_r, ALU_Op_r, IncDecZ, BTR / No_BTR, Auto_Wait,
  NMI_s, BusReq_s / BusAck, OldNMI_n, MULU registers, …) and of the front end (DI_Reg, CEN_pol, IntCycleD_n, T80a /
  T80as strobe generators, SOD). This is stronger than comparing architectural state at instruction boundaries:
  state is compared on every clock.
- `verify/tb/sim.cpp`: random mode (structured instruction streams with every opcode page equally likely plus raw
  random bytes, rewritten under the running CPU; INT level held for random times with random IM 0 vectors incl. RST
  and arbitrary opcodes, random IM 2 vectors; NMI pulses; WAIT stretches; BUSRQ stretches; enable patterns; async
  resets mid-instruction, reset held from time 0; random OUT0 / R800_mode; random DIRSet pulses with random DIR;
  Phoenix I8080 / I8085 / RIM_D toggled), sweep mode, CP/M .COM mode (BDOS 2 / 9 to the log, 0 or warm boot stops).

## 4. Rerun

```
verify/gen_ref.py <stock T80 dir> <phoenix T80 dir> refv              # 83 GHDL reference models
verify/build.sh <config> refv build                                    # one lockstep simulator (see configs.py)
verify/build.sh t80s_m0_t1_w1 refv build dut                           # DUT-only / reference-only builds for long programs
verify/build.sh t80s_m0_t1_w1 refv build ref
verify/tools/zexsplit.py zexdoc.com zex/split                          # one .COM per ZEX test
ZEX_SPLIT=zex/split I8080_TESTS=<8080 test dir> verify/run_all.sh build results
verify/run_jobs.py build results zexsolo_ref                           # the full reference ZEX run (~26 core-hours)
verify/summarize.py results                                            # tables above
```
Tools used: Verilator 5.020, GHDL 4.1.0, yosys 0.33. ZEX binaries: Frank Cringle's zexdoc / zexall .COM
(md5 be3691b6…, 4a32f2a6…). 8080 tests: TST8080, CPUTEST, 8080PRE, 8080EXM.

## 5. Design decisions

- **Structure-preserving translation.** t80sv keeps T80's registers, register file, microcode and nonblocking-
  assignment order one-for-one. That is the only practical way to be cycle-identical including quirks (MEMPTR, X/Y
  flags, T80-specific interrupt and WAIT timing); it also makes the code auditable line by line against the VHDL.
- **Microcode generated, not hand-typed.** `t80sv_mcode.sv`'s case body is produced from `T80_MCode.vhd` by
  `verify/tools/mcode2sv.py` (case-insensitive identifiers canonicalised; no pruning).
- **One core, runtime mode.** `mode` is a 2-bit signal = MODE, or 2 while `i8080` is high on a MODE 0 build (the
  Phoenix semantics); with `i8080` tied low it folds to a constant. `is_cc_true` follows the build MODE, as Phoenix's
  `Mode_g`.
- **VHDL don't-cares** (`"--------"` in BusA / BusB defaults, ALU Q default, MULU_Prod32[15:8] for MULUB) are 0, the
  value GHDL's netlist uses; lockstep showed no difference. Quartus is free to choose otherwise for the VHDL, so if a
  don't-care were ever observable the VHDL itself would be tool-dependent there.
- **Asynchronous resets** are written `posedge rst` with `rst = ~RESET_n`. Same hardware; in Verilator the reset also
  takes effect when RESET_n is low from time 0 (with `negedge RESET_n` it would not, and the GHDL model does reset).
  Registers without a reset in the VHDL have none here (register file, BusA / BusB, RegAddr*, IncDecZ, OldNMI_n,
  Wait_s, T80pa IntCycleD_n …); BusReq_s / BusAck keep their VHDL initial value 0.
- **T80a tri-states** live only in the pin-compatible wrapper `t80sv_T80a` (`tri` outputs, `inout D`); the shared
  core module exposes plain outputs plus `bus_oe` / `doe`.
- **Drop-in names** are `t80sv_<Top>` so they can sit in a project next to the VHDL during migration; ports and
  generic names are the VHDL ones.
- **Verilator lint waivers** (`rtl/t80sv_lint.vlt`): SYNCASYNCNET (T80 mixes its async reset with synchronous uses of
  RESET_n: `BUSAK_n = ~(BusAck & RESET_n)`, OldNMI_n / BusReq_s held in reset, T80pa's synchronous front-end reset —
  kept as the reference), DECLFILENAME (several modules per file), PINCONNECTEMPTY (outputs a drop-in top does not
  have are left open on purpose). Partial-width process-variable temporaries carry a local UNUSEDSIGNAL lint_off.

## 6. Quartus 17.0.2 / Cyclone V notes

- Written for the listed restrictions: no genvar loops (no loops at all), no assignment patterns, no size casts, no
  bit-select on expressions, every identifier declared before use, generate-if only. Fleet wrappers route outputs
  through plain wires and assign struct fields one by one (as the fleet dispatchers do).
- **To confirm in Quartus 17.0.2** (could not be run here): (1) `tri1` / `tri0` input nets on the drop-in tops
  (used to reproduce the VHDL port defaults; Verilog-2001, supported by Verilator); if Quartus objects, connect those
  pins explicitly; (2) the packed-struct ports of the fleet wrappers (same `chip_pool_pkg` types the fleet already
  compiles); (3) fitter results.
- **Resources.** Yosys generic synthesis (`synth -flatten; abc -lut 6`) of the T80s configuration: t80sv 361
  flip-flops / 2008 LUT6; the GHDL netlist of the reference T80s through the same flow: 361 flip-flops / 1683 LUT6.
  The flip-flops match exactly; the LUT difference sits in the microcode decoder (720 vs 473 LUT6 alone) and comes
  from comparing GHDL's already-optimised netlist with yosys reading the case statements, not from extra function (the
  two are equivalent cycle for cycle). Quartus synthesises both from source, so its numbers are the real comparison.
- **Timing.** Same register-to-register paths as T80 (IR → microcode → ALU / register-file write in one enable), so
  the same Fmax class as the VHDL in the fleet's 50–100 MHz enable-based designs. T80a / T80as use both clock edges by
  design (as the reference); they are not enable-based.
- `MODE` above 3 is not supported (the reference documents 0..3; Phoenix range-limits it).

## 7. Dead code kept (as required)

GB branches under non-GB tops; R800 MULUB / MULUW and DIR / DIRSet under tops that tie them off; `out0` under tops
without OUT0; T8080se's unused HOLD and its core `NMI_n` / `BUSRQ_n` tied high; Phoenix SIM's comment that the
interrupt-mask half of SIM is not modelled (not modelled here either, as the reference).

## 8. License (T80)

Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
Redistribution and use in source and synthezised forms, with or without modification, are permitted provided that the
following conditions are met: Redistributions of source code must retain the above copyright notice, this list of
conditions and the following disclaimer. Redistributions in synthesized form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation and/or other materials provided with the
distribution. Neither the name of the author nor the names of other contributors may be used to endorse or promote
products derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

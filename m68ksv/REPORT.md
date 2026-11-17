# m68ksv — report (checkpoint 6: resource-placement switch; checkpoint 5: area, 68020 bus, handover)

m68ksv is our own SystemVerilog 680x0 core (`DESIGN.md`): one core for the 68000, 68008 (DIP48), 68008FN, 68EC000,
68010, 68020 and 68EC020 (`CPU` = 68000 / 68008 / 68009 / 68001 / 68010 / 68020 / 68021). This report is the
history of nine sessions; the sections are in order. **Start with "Handover" at the end** (what each CPU is verified
against, open items, how to rerun every gate, how a fleet core instantiates it).

**Status (2026-11-16, checkpoint 6).**
- **Resource placement (checkpoint 6):** parameter `RES` picks where the control storage goes, with the same CPU clock
  for clock: `RES = 0` (default, BRAM-heavy) now takes 16 / 24 / 30 CPU M10K on the 68000 family / 68010 / 68020s
  (25 / 28 / 30 before: compacted 68000 microcode, split 68010 ROM); `RES = 1` (logic-heavy: two-level microcode,
  opcode decode in logic) takes 7 / 10 / 12 at an estimated +130 to +200 ALMs (fx68k: 6 M10K, 2,047 ALMs). Proof:
  clock-exact A/B on all seven configurations, against the start and between the settings; every suite / lockstep /
  directed gate gives byte-identical output. Not compiled in Quartus yet (section "Checkpoint 6").
- **68000 / 68008 / 68008FN / 68EC000:** Tom Harte 68000 suite exact on registers, RAM, prefetch queue, bus order and
  cycle count — 794,139 / 794,139 pure-suite tests, 202,181 / 202,182 with MAME-corrected expectations (3,739 suite
  errors handled by rule, section "Suite exclusions") — on the 68000 and on every 68000-bus member
  (`run_family.sh`); fx68k pin-level lockstep (68000, 68EC000 16-bit) and MAME m68008 bus-cycle lockstep (68008,
  68008FN, 68EC000 8-bit). Open: the 68000's run-ahead during BR / HALT waits and reset mid-instruction residue
  (fx68k rows with BR / IRQ / reset / mix show 1–4 mismatching runs, unchanged since checkpoint 2).
- **68010:** Musashi m68010 lockstep 0 mismatching runs; loop mode (`loop010`), format-8 RTE re-run (`rerun010`).
- **68020 / 68EC020:** Musashi m68020 / m68ec020 lockstep 0 mismatching runs over 13 rows (differences classified);
  bus cycles checked against the MC68020 User's Manual in checkpoint 5 (STERM removed — the 68020 has none —, DBEN /
  write-data / write-DS edges, late bus error, 68EC020 pins); directed tests `dsz020`, `cache020`, `rmc020`,
  `cop020` pass; instruction times compared with the manual's tables (`tim020`; m68ksv has no overlap, long writes
  are two requests). **Not done:** CALLM / RTM (illegal instruction), long writes as one request, most coprocessor
  primitives (protocol violation); **not passing:** `rerun020` (6 of 12 runs). **2026-11-16:** the undefined /
  disputed behaviour (DIV / CHK / CHK2 flags, DIV.L overflow N / Z, PACK / UNPK with -(A7), LINK A7, the address-error
  frame) follows WinUAE's 68020 core after an Amiberry run (section "68020 behaviour from WinUAE"; new gate `amiga020`).
- **Area (checkpoint 5 part 1):** yosys LUT + carry cells down 5–10 % on every CPU (Quartus-like flow), behaviour proved
  clock-exact (A/B);
  Quartus numbers for checkpoint 5 come from the user's compile (the pre-checkpoint-5 table is in the Handover).

## Parity table

Current status per CPU (checkpoint 5; the table was last rewritten here — the per-checkpoint sections below keep their
original wording). **V** = verified by the 68000 suite on that build (registers, RAM, prefetch queue, bus order, cycles);
**L** = verified by a lockstep oracle (fx68k pins for the 68000 / 68EC000 16-bit, MAME m68008 bus cycles for the 8-bit
members, Musashi m68010 / m68020 / m68ec020 for those); **D** = also a directed test; **C** = verified with classified
oracle differences; **A** = implemented, behaviour approximate (named); **O** = open (named); **—** = does not exist on
that CPU. 68008 / FN and 68EC000 share the 68000's execution unit and microcode (only the BIU differs), so their
instruction rows are the 68000's, verified by `run_family.sh` on each build.

| Item | 68000 | 68008 / FN | 68EC000 | 68010 | 68020 | 68EC020 | Verified by / where |
|---|---|---|---|---|---|---|---|
| 68000 instruction set, all EA modes, flags (incl. undocumented BCD N / V), prefetch queue | V, L | V, L | V, L | L (68000 suite on the 010 build: classified 010 differences) | L, C | L, C | suite, fx68k, MAME m68008, Musashi; `uc` routines in `rtl/gen/m68ksv_ucode.py` |
| 68020 undefined / disputed behaviour (DIV / CHK / CHK2 flags, DIV.L overflow, PACK / UNPK -(A7), LINK A7, address-error frame) | — | — | — | — | D, C (WinUAE, 2026-11-16) | D, C | `amiga020` (Amiberry log + WinUAE rules), `mus020` classes |
| Cycle counts / bus order | V (exact), L | V, L | V, L | L (`mus010 -cyc`, data-sheet table in "Checkpoint 3") | A (micro-routine lengths, `tim020` / `mus020 -cyc`) | A | |
| Bus pins and timing (AS, UDS / LDS / DS, R/W, FC, DTACK, VPA / VMA / E, BERR, HALT, RESET, BR / BG / BGACK) | L (every pin every phase, fx68k) | L (MAME bus cycles; DIP48: no BGACK, IPL2/0 joined) | L | L (68000 BIU, unchanged) | — | — | `m68ksv_biu.sv` |
| Bus error / address error frames, bus retry (BERR + HALT) | L, D (`retry`) | L, D | L, D | L, D (`rerun010`: format 8, RTE re-run) | C (format B), O (`rerun020` 6 / 12) | C, O | |
| BR / HALT waits | O (run-ahead residue) | O | O | O | D (`rmc020`: no grant in a locked sequence) | D | |
| Interrupts, autovector, spurious, trace, STOP, reset | L (fx68k IPL sweep; reset mid-instruction: O) | L | L | L | L (+ T0 trace, M / ISP / MSP, throwaway frame) | L | |
| 68EC000 MODE latch (8 / 16-bit) | — | — | L | — | — | — | |
| 68010: VBR, SFC / DFC, MOVEC, MOVES, RTD, MOVE from CCR, loop mode, format 0 / 8 frames, BKPT | — | — | — | L, D (`loop010`, `rerun010`) | L | L | `m68ksv_ucode010.py` |
| 68020 instructions: full extension words, bit fields, MUL.L / DIV.L, CAS / CAS2, CHK2 / CMP2, PACK / UNPK, TRAPcc, EXTB, LINK.L, Bcc.L, MSP / ISP | — | — | — | — | L, C | L, C | `m68ksv_ucode020.py` |
| CALLM / RTM | — | — | — | — | O (illegal instruction) | — (illegal instruction, as the chip) | |
| Instruction cache (CACR / CAAR, CDIS) | — | — | — | — | L, D (`cache020`) | L, D | `m68ksv_biu32.sv` |
| Dynamic bus sizing, SIZ, misaligned operands, DSACK / BERR / late BERR timing (UM section 5) | — | — | — | — | D (`dsz020`, incl. `-w 0` edges and `-be 3 / 4`), L | D, L | |
| RMC (TAS, CAS, CAS2) | — | — | — | — | D (`rmc020`) | D | |
| Coprocessor interface (CPU space, cpGEN response loop, F-line on no response) | — | — | — | — | D (`cop020`), A (other primitives: protocol violation) | D, A | |
| ECS / OCS / DBEN / IPEND / AVEC | — | — | — | — | D (ECS / OCS a quarter clock late: A) | — (not on the chip; driven high) | |
| Long operand writes | — | — | — | — | A (two word requests; UM: one) | A | |

## Checkpoint 1 result

Suite: SingleStepTests / 680x0, `68000/v1` (124 files, 1,000,060 tests), converted with
`verify/tools/conv_harte.py`. Per test the harness (`verify/tb/harte.cpp`, Verilator 4.204) resets the core, loads
D0–D7, A0–A6, USP, SSP, SR, PC and the two prefetch words through the test-load port and the initial RAM into a
16 MB memory model with immediate DTACK, runs to the next instruction boundary and compares: all 19 registers
(incl. the whole SR, USP and SSP), the prefetch queue (IR, IRC), every final RAM byte. Also recorded, not part of
the checkpoint 1 criterion: the sequence of bus cycles (read / write / TAS, FC, address, byte / word) against the
suite's transaction list ignoring idle cycles, and the instruction's cycle count.

Columns: tests = file size; compared = tests not excluded; pass = registers + prefetch queue + RAM all equal;
excluded = suite-error list (`verify/suite_exclusions.txt`), with how many pass against the corrected value; bus
order = all bus cycles equal in order, FC, address, size; cycles = exact cycle count.

| File | Tests | Compared | Pass | Excluded (corrected ok) | Bus order | Cycles |
|---|---|---|---|---|---|---|
| ABCD | 8065 | 8065 | 8065 | 0 | 8065 | 4061 |
| ADDA.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ADDA.w | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ADD.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| ADD.l | 8065 | 8065 | 8065 | 0 | 8065 | 2348 |
| ADD.w | 8065 | 8065 | 8065 | 0 | 8065 | 4710 |
| ADDX.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| ADDX.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ADDX.w | 8065 | 8065 | 8065 | 0 | 8065 | 5465 |
| AND.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| ANDItoCCR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ANDItoSR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| AND.l | 8065 | 8065 | 8065 | 0 | 8065 | 2077 |
| AND.w | 8065 | 8065 | 8065 | 0 | 8065 | 4668 |
| ASL.b | 8065 | 8063 | 8063 | 2 (0 ok) | 8065 | 8010 |
| ASL.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ASL.w | 8065 | 8065 | 8065 | 0 | 8065 | 7085 |
| ASR.b | 8065 | 6423 | 6423 | 1642 (1642 ok) | 8065 | 8014 |
| ASR.l | 8065 | 7034 | 7034 | 1031 (1031 ok) | 8065 | 0 |
| ASR.w | 8065 | 7002 | 7002 | 1063 (1063 ok) | 8065 | 7095 |
| Bcc | 8065 | 8065 | 8065 | 0 | 8065 | 5865 |
| BCHG | 8065 | 8065 | 8065 | 0 | 8065 | 6764 |
| BCLR | 8065 | 8065 | 8065 | 0 | 8065 | 6808 |
| BSET | 8065 | 8065 | 8065 | 0 | 8065 | 6750 |
| BSR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| BTST | 8065 | 8065 | 8065 | 0 | 8065 | 6663 |
| CHK | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| CLR.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| CLR.l | 8065 | 8065 | 8065 | 0 | 8065 | 3658 |
| CLR.w | 8065 | 8065 | 8065 | 0 | 8065 | 4896 |
| CMPA.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| CMPA.w | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| CMP.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| CMP.l | 8065 | 8065 | 8065 | 0 | 8065 | 568 |
| CMP.w | 8065 | 8065 | 8065 | 0 | 8065 | 5024 |
| DBcc | 8065 | 8065 | 8065 | 0 | 8065 | 4096 |
| DIVS | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| DIVU | 8065 | 8064 | 8064 | 1 (0 ok) | 8065 | 2469 |
| EOR.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| EORItoCCR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| EORItoSR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| EOR.l | 8065 | 8065 | 8065 | 0 | 8065 | 3616 |
| EOR.w | 8065 | 8065 | 8065 | 0 | 8065 | 4930 |
| EXG | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| EXT.l | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| EXT.w | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| JMP | 8065 | 8065 | 8065 | 0 | 8065 | 4259 |
| JSR | 8065 | 8065 | 8065 | 0 | 8065 | 4183 |
| LEA | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| LINK | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| LSL.b | 8065 | 8065 | 8065 | 0 | 8065 | 7994 |
| LSL.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| LSL.w | 8065 | 8065 | 8065 | 0 | 8065 | 7108 |
| LSR.b | 8065 | 8065 | 8065 | 0 | 8065 | 8008 |
| LSR.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| LSR.w | 8065 | 8065 | 8065 | 0 | 8065 | 7055 |
| MOVEA.l | 8065 | 8065 | 8065 | 0 | 8065 | 5379 |
| MOVEA.w | 8065 | 8065 | 8065 | 0 | 8065 | 5322 |
| MOVE.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVEfromSR | 8065 | 8065 | 8065 | 0 | 8065 | 5017 |
| MOVEfromUSP | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVE.l | 8065 | 8065 | 8065 | 0 | 8065 | 3270 |
| MOVEM.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| MOVEM.w | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| MOVEP.l | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVEP.w | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVE.q | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVEtoCCR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| MOVEtoSR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| MOVEtoUSP | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| MOVE.w | 8065 | 8065 | 8065 | 0 | 8065 | 3368 |
| MULS | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| MULU | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| NBCD | 8065 | 8065 | 8065 | 0 | 8065 | 6750 |
| NEG.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| NEG.l | 8065 | 8065 | 8065 | 0 | 8065 | 3669 |
| NEG.w | 8065 | 8065 | 8065 | 0 | 8065 | 4911 |
| NEGX.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| NEGX.l | 8065 | 8065 | 8065 | 0 | 8065 | 3650 |
| NEGX.w | 8065 | 8065 | 8065 | 0 | 8065 | 4979 |
| NOP | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| NOT.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| NOT.l | 8065 | 8065 | 8065 | 0 | 8065 | 3639 |
| NOT.w | 8065 | 8065 | 8065 | 0 | 8065 | 4957 |
| OR.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| ORItoCCR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ORItoSR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| OR.l | 8065 | 8065 | 8065 | 0 | 8065 | 2037 |
| OR.w | 8065 | 8065 | 8065 | 0 | 8065 | 4650 |
| PEA | 8065 | 8065 | 8065 | 0 | 8065 | 7513 |
| RESET | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| ROL.b | 8065 | 8065 | 8065 | 0 | 8065 | 8007 |
| ROL.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ROL.w | 8065 | 8065 | 8065 | 0 | 8065 | 7028 |
| ROR.b | 8065 | 8065 | 8065 | 0 | 8065 | 7990 |
| ROR.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ROR.w | 8065 | 8065 | 8065 | 0 | 8065 | 7138 |
| ROXL.b | 8065 | 8065 | 8065 | 0 | 8065 | 7989 |
| ROXL.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ROXL.w | 8065 | 8065 | 8065 | 0 | 8065 | 7082 |
| ROXR.b | 8065 | 8065 | 8065 | 0 | 8065 | 8004 |
| ROXR.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| ROXR.w | 8065 | 8065 | 8065 | 0 | 8065 | 7117 |
| RTE | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| RTR | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| RTS | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| SBCD | 8065 | 8065 | 8065 | 0 | 8065 | 4117 |
| Scc | 8065 | 8065 | 8065 | 0 | 8065 | 7424 |
| SUBA.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| SUBA.w | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| SUB.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| SUB.l | 8065 | 8065 | 8065 | 0 | 8065 | 2326 |
| SUB.w | 8065 | 8065 | 8065 | 0 | 8065 | 4737 |
| SUBX.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| SUBX.l | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| SUBX.w | 8065 | 8065 | 8065 | 0 | 8065 | 5387 |
| SWAP | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| TAS | 8065 | 8065 | 8065 | 0 | 8065 | 4144 |
| TRAP | 8065 | 8065 | 8065 | 0 | 8065 | 0 |
| TRAPV | 8065 | 8065 | 8065 | 0 | 8065 | 3970 |
| TST.b | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| TST.l | 8065 | 8065 | 8065 | 0 | 8065 | 4963 |
| TST.w | 8065 | 8065 | 8065 | 0 | 8065 | 4928 |
| UNLINK | 8065 | 8065 | 8065 | 0 | 8065 | 8065 |
| **TOTAL** | 1000060 | 996321 | 996321 | 3739 (3736 ok) | 1000060 | 551529 |

Every compared test in all 124 files passes; no tolerance or masking is applied to compared tests.

### Suite exclusions (3,739 tests, all listed in `verify/suite_exclusions.txt`)

**Accepted by the user 2026-11-15** until shown wrong. If doubt remains, settle it on real silicon: the user has 68000 Amigas available for a test program (ASR count > size on a negative operand: X / C; DIVU by zero: stacked PC + N / Z).

Generated by a rule, not by hand (`verify/tools/exclusions.py`); the harness reports them separately.

| Rule | Tests | Suite expects | m68ksv does | Tie-breaker |
|---|---|---|---|---|
| ASR.b / .w / .l, register count > operand size, negative operand | 1,642 + 1,063 + 1,031 = 3,736 | X = C = 0 | X = C = 1 (the sign bit is shifted out on every step) | MAME `m68000` (`alu_asr*`, applied once per step of the microcode loop) gives X = C = 1; Musashi agrees. All 3,736 pass when only the expected SR is corrected to X = C = 1 (column "corrected ok"). |
| ASL.b #2,D2 tests #1582 and #1760 | 2 | D2 bits 31–8 change (e.g. cdfb7fbe → 2e5e4304) | only the low byte changes (cdfb7ff8, flags 270a) | a byte shift cannot change bits 31–8; suite data error. |
| DIVU (d16,A7),D0 #5744 — the suite's only zero-divide test | 1 | stacked PC = instruction address (c00), flags N = Z = V = C = 0 | stacked PC = next instruction (c04), N = Dx[31], Z = (Dx[31:16] == 0), V = C = 0 | MAME `m68000` (divu micro-routine: `alu_sub(divisor, Dx.hi)` sets the flags, then `dvur2` stacks `pc − 2` = next instruction) — m68ksv follows it; DIVS zero divide likewise (Z = 1, others 0). |

fx68k was also built as a probe (`verify/tb/fxprobe.cpp`) to settle these, but under Verilator 4.204 it needs
`-Wno-BLKANDNBLK` (mixed blocking / non-blocking struct writes) and the built model halts at reset; the probe was not
used for any result. Getting fx68k running in Verilator 4.204 is the first task of checkpoint 2 (lockstep).
*Corrected at checkpoint 1b:* fx68k runs under Verilator 5.052 (`--no-assert`); under 4.204 the model never starts a
bus cycle. Its verdict on the three classes (all three agree with m68ksv, not with the suite) is in "Checkpoint 1b".

### Directed smoke test (`verify/tb/smoke.cpp`)

| Item | Result |
|---|---|
| Reset: SSP and PC from vectors 0 / 1, program runs | pass |
| Level-1 autovectored interrupt (IACK with VPA), handler, RTE, mask restored | pass |
| Trace after an instruction run with T set, handler entered | pass |

3 / 3 pass. Not covered by any test yet: STOP, illegal / line A / line F / privilege exceptions, spurious interrupt,
NMI edge, double-fault halt, RESET output pin timing.

### What the measured columns show (checkpoint 2 input, not chased here)

- **Bus order**: 1,000,060 / 1,000,060 tests produce exactly the suite's sequence of bus cycles (type, FC, address,
  size), including all 178,082 address-error tests (which access faults, what was done before it, the 7-word frame
  order). The suite uses data-space FC for PC-relative operand reads; m68ksv does the same now — to be checked
  against fx68k at checkpoint 2.
- **Cycles**: 551,529 / 1,000,060 exact. Known causes of the rest: idle micro-cycles not yet inserted (the suite's
  `n` entries: `.l` register ops, ADDQ to An, shifts' 2-cycle prologue, MUL / DIV data-dependent timing, address-error
  and exception idle cycles, Bcc / DBcc internal cycles), MOVEM / PEA / JMP extra or missing micro-cycles. All are
  microcode edits within the existing sequencer.

## Design decisions (checkpoint 1)

1. **Microcoded execution unit with M10K ROMs** (brief update 2026-11-14): microcode 745 × 75 bits, three decode
   ROM stages; the sequencer computes the next address at e1 and the ROM output is taken at e0, so the 1-cycle M10K
   latency never stalls. Chosen over a hand-written FSM to put the per-instruction sequences in block RAM and to make
   cycle exactness a microcode-only change.
2. **Micro-cycle = 2 CPU clocks, bus cycle = 2 micro-cycles, wait states freeze the phase generator** — the 68000's
   own structure; DTACK / arbitration / HALT never need polling in microcode.
3. **Bus cycles start at the micro-instruction's own start; dispatch happens in the last micro-cycle** (decode ROMs
   started at the final prefetch): no extra cycle per instruction.
4. **Register file in flops** (5 read + 2 write ports and the A7 swap per micro-cycle); MLAB conversion is the planned
   area lever (DESIGN.md 4). *Superseded at checkpoint 1b:* MLAB copies, see "Checkpoint 1b".
5. **One shared adder** in the ALU for all add / subtract forms; one address-unit adder; **16 × 16 multiply in a DSP
   block** (MUL cycle count will come from microcode idle steps); **divider iterative**, one bit per micro-cycle.
6. **Shifts one bit per micro-cycle** (= the 68000's 2 clocks per bit), so shift timing is exact by construction.
7. **Group-0 stacked PC = `fpc − 4`** (next prefetch address minus 4, a faulting prefetch not counted) and access word
   = IR[15:5] | R/W | I/N | FC with I/N = 1 for program fetches — derived from the suite's 178,082 address-error tests,
   which pass.
8. **Register side effects on faults follow the micro-instruction boundary**: an update made in the micro-instruction
   that starts the faulting access is kept (`(An)+` / `-(An)` reads, MOVE flags), later ones are not (MOVE `(An)+` /
   `-(An)` destinations, ADDX / SUBX `-(Ax)`); MOVEM `(An)+` sets An = An + 2 at the first read (suite behaviour).
9. **BCD**: binary add / subtract then decimal correction, V = bit 7 flipped by the correction — fitted to and
   checked on every BCD test of the suite (Musashi's V formula fails 814 ABCD tests).
10. **Suite vs tie-breaker**: where the suite disagrees with MAME's microcode-derived `m68000`, m68ksv follows MAME
    and the tests are excluded by rule (3,739, see above).
11. **CPU parameter codes**: 68000, 68008 (DIP48), 68009 (68008 PLCC52 / FN), 68001 (68EC000), 68010, 68020, 68021
    (68EC020) — integer codes because the parameter is an `int`; any value but 68000 fails elaboration in checkpoint 1.
12. **Reset input**: external reset needs `RESET_n_i` and `HALT_n_i` low together (68000 rule).
13. **Proposed master bus type**: `m68k_i_t` / `m68k_o_t` in `fleet_types.svh` (package `m68ksv_fleet_pkg` until the
    fleet merges it into `chip_pool_pkg`), superset of the 020 pins; wrapper `rtl/m68ksv_fleet.sv` (68000 mapping,
    lint-clean in Verilator; not simulated).

## Not done in checkpoint 1 (and why)

- Cycle exactness, bus-pin timing per phase (FC is driven at S2 instead of S0, address at S2 instead of S1), BERR,
  HALT / re-run, BR / BG / BGACK, E / VMA / VPA 6800 cycles, fx68k lockstep: checkpoint 2 by the brief.
- 68008 / 68008FN / 68EC000 (2b), 68010 (3), 68020 / 68EC020 (4): not started, by the brief.
- fx68k could not be run in Verilator 4.204 (see "Suite exclusions"); no fx68k number appears in this report.
  *Corrected at checkpoint 1b:* it runs under Verilator 5.052; numbers in "Checkpoint 1b".
- No Quartus run (the user compiles `syn/quartus/`). Only the 68000 revision and the fx68k revision exist yet; the
  other members get theirs when implemented.
- STOP, illegal / privilege / line A / F exceptions, spurious interrupts, NMI edge and double-fault halt are
  implemented but have no test yet.

## Resources and timing

**yosys estimate** (`verify/tools/yosys.sh`, yosys 0.66 `synth_intel_alm -family cyclonev`, top `m68ksv`,
CPU = 68000; a yosys estimate, not Quartus — yosys does not pack LUTs into ALMs):

| Cells | ALUT2 | ALUT3 | ALUT4 | ALUT5 | ALUT6 | ALUT_ARITH | FF | M10K | DSP (18 × 18) |
|---|---|---|---|---|---|---|---|---|---|
| 6,909 | 264 | 652 | 1,371 | 1,656 | 327 | 490 | 1,362 | 15 | 1 |

That is 4,270 logic LUTs + 490 carry cells. Breakdown (same tool and RTL, `-noflatten`, 6,156 cells in total because
nothing is optimised across module boundaries): EU 5,195 cells (incl. 1,296 FF), ALU 804, BIU 126, rest 31. fx68k cannot be read by yosys 0.66 (`fx68k.sv:48: Only PACKED
supported`), so the fx68k comparison has to come from the Quartus `m68ksv_qtop_fx68k` revision. fx68k's own README
quotes "just over 5,100 LEs" on Cyclone (4-input LEs), i.e. the same order as the LUT count above; whether m68ksv is
smaller in Cyclone V ALMs is open until the user compiles both.

M10K use: microcode 8 (1024 × 75 → 10-bit-wide blocks), decode 7 (drom1 4, drom2 1, drom3 / drom4e 2).
*Corrected at checkpoint 1b:* that is yosys's mapping. The user's Quartus 17.0.2 compile (2026-11-15) built the
microcode ROM (616 ALMs) and drom2 (89 ALMs) in logic; only drom1 and drom3 became M10K (5 blocks). The checkpoint 1
Quartus result: 3,214 ALMs, 1,732 registers, 13 RAM blocks (8 of them the test top's RAM), 1 DSP, 87.0 MHz (slow
1100 mV 100 C; setup slack −1.079 ns at 96 MHz) against fx68k's 2,047 ALMs / 99–100 MHz in the same top.

**Timing concerns at 96 MHz** (no STA run; superseded by "Checkpoint 1b"): the longest paths are expected to be (1) microword register → operand
selects → 16:1 register read mux → operand register (e1), (2) operand registers → shared adder → flag logic → result
register (e3), (3) RES / AUR → register-file write mux with size merge and A7 swap (e0), (4) the decode chain from
`drom2` → kind / size logic → `drom3` address and from `drom3` → dispatch mux → microcode address register. Each is a
single-`clk` path by construction; if (1)–(3) miss 96 MHz, the planned MLAB register file (registered reads) also
shortens (1).

**Quartus 17.0 pre-compile check** on `rtl/m68ksv_all.sv` (`verify/tools/mkall.sh`; checkpoint 1 file, the
checkpoint 1b output is in "Checkpoint 1b"):

```text
== pre-compile check: rtl/m68ksv_all.sv
-- module-level loops (each must sit inside generate ... endgenerate):
3051:    for (int i = 15; i >= 0; i--) if (mask[i]) m_idx = i;
3484:        for (int i = 0; i < 15; i++) R[i] <= tl_r[i];
3568:            for (int i = 0; i < 16; i++) begin
-- system-function bounds, size casts, assignment patterns:
-- set membership (inside):
-- bit-select on an expression:
== end of check
```

The three `for` hits are `for (int i ...)` loops inside `always` blocks (accepted by Quartus 17), not module-level
loops; no other hits. Verilator `--lint-only -Wall` on the RTL is clean apart from intentional width truncations and
unconnected debug pins.

## Checkpoint 1b: area and timing on Cyclone V (2026-11-15)

Starting point: the user's Quartus 17.0.2 compile of checkpoint 1 (same test top for both): m68ksv 3,214 ALMs /
1,732 registers / 13 RAM blocks / 1 DSP / 87.0 MHz; fx68k 2,047 ALMs / 1,546 registers / 14 RAM blocks / 0 DSP /
99–100 MHz. Per entity (fit.rpt): `m68ksv_eu` own logic 2,143.4 ALMs, `m68ksv_urom` 616.0 (in logic, 798 ALUTs),
`m68ksv_alu` 305.1, `m68ksv_drom2` 88.8 (in logic), `m68ksv_biu` 33.8, `m68ksv_drom4e` 4.7. Targets: ≤ 2,047 ALMs,
96 MHz with margin. **No Quartus run was made in this checkpoint; the numbers below are yosys estimates and Verilator
results. Whether the targets are met is open until the user compiles.**

### What changed (DESIGN.md has the details)

| Change | Why |
|---|---|
| urom, drom1, drom2 (and drom3) emitted as fully initialised arrays with `romstyle "M10K"` (generator `rom_module`) instead of case tables | Quartus built the partial case tables of urom (616 ALMs) and drom2 (89 ALMs) in logic; drom3, already an initialised array, did infer. drom4e (64 × 8) stays in logic on purpose (4.7 ALMs) |
| Register file in MLAB: three copies of `m68ksv_rf` (32 × 32, `ramstyle "MLAB, no_rw_check"`, read address registered every clock, no init) with a common write port; AU writes at e3 from the adder, ALU writes at e0 with the byte / word merge source read on copy BW; USP / SSP as entries 15 / 16 (no swap); fourth copy for a debug read port | the flop register file with five 16:1 × 32 read muxes and per-bit write logic was the largest item of the EU |
| Operands / bus address / write data latched at e2 (were e1); next micro-address loaded at e2 from the condition and FIN decision latched at e1; address error detected at e2 (BIU takes the address combinationally at e2 and latches A0 itself) | register-file data is valid at e2; splits condition → dispatch → microcode address into two clocks |
| Decode: class register added (drom1 → class → drom2 → drom3 → result register, 5 clocks; FIN dispatch at e2 ≥ 6 clocks after IRN) | removes the drom1-output → class logic → drom2-address and drom3-output → dispatch chains |
| ALU: op, adder controls, result-select code and no-write flag registered at e2; result from a 16-way select; X / V / C latched at e3, N / Z formed from RES at e0; BCD with one correction adder each, NBCD shares the SBCD subtractor; DIV result through the product input | removes the op decode and the flag reduction from the adder path |
| 16 × 16 multiplier with its output register (product one clock after the operands); MUL routine latches the operands one micro-instruction earlier (generator check) | the unregistered DSP sat in the ALU path |
| Write-data selection decoded at e1; MOVEM register index (`m_idx`) kept in a register; FIN decision latched at e1 and used at e0 | shorter e2 / e0 paths; one FIN decision per micro-instruction |
| Branch / PC-relative displacement − 2 on 9 / 17-bit subtractors; `BA_SPP2` (SP + 2 bus address, a 32-bit adder) removed — RTE / RTR compute SP + 2 in the address unit one micro-instruction earlier (+1 micro-cycle, not cycle-matched before either) | area |
| Debug: `dbg_r` / `dbg_usp` / `dbg_ssp` replaced by `dbg_ra` / `dbg_rd` (read port, one clock); test load writes one register per clock | a parallel register dump is not possible from MLAB |

All the hooks for the other members stay: CPU generate structure, BIU separation, 5-bit register-file address (MSP
= entry 17 for the 020), microcode / decode generator unchanged in structure.

### Suite results after the final change (Verilator 4.204, `verify/run_all.sh`)

| | Tests | Compared | Pass | Excluded (corrected ok) | Bus order | Cycles |
|---|---|---|---|---|---|---|
| Checkpoint 1b, back-to-back enables | 1,000,060 | 996,321 | 996,321 | 3,739 (3,736) | 1,000,060 | 551,529 |
| Checkpoint 1b, 0–3 random idle clocks between enables (`-gap 3`) | 1,000,060 | 996,321 | 996,321 | 3,739 (3,736) | 1,000,060 | (not meaningful) |
| Smoke test | 3 / 3 | | | | | |

The per-file table is identical to checkpoint 1's in every column (diffed). Same exclusion list, unchanged. The
m68ksv suite runner stays on Verilator 4.204 (PATH default). The gap run found one real problem on the way (a test
load ending between e1 and e2 skipped the TLFIN dispatch; fixed), which back-to-back enables alone did not show.
Checks that can fail: an operand read one phase early fails the suite through the `M68KSV_SIMCHECK` collision
garbage; a decode dispatch check one clock tighter stops on the first NOP test.

### yosys estimate before → after (`synth_intel_alm -family cyclonev`, yosys 0.66; a yosys estimate, not Quartus)

| yosys, top | LUTs (ALUT2–6) | carry cells | FF | M10K | MLAB cells (32 × 1) | DSP |
|---|---|---|---|---|---|---|
| `m68ksv` checkpoint 1 | 4,270 | 490 | 1,362 | 15 | 0 | 1 |
| `m68ksv` checkpoint 1b | 2,501 | 393 | 985 | 17 | 64 | 1 |
| `m68ksv_qtop` checkpoint 1 (test top, debug outputs unconnected) | 4,203 | 460 | 1,383 | 23 | 0 | 1 |
| `m68ksv_qtop` checkpoint 1b | 2,488 | 363 | 1,005 | 24 | 64 | 1 |

yosys ignores `ramstyle`: of the register-file copies it maps some to M10K and some to MLAB cells (64 cells = two
copies); Quartus will use 2 MLABs per copy. yosys already put the microcode ROM in M10K at checkpoint 1, so these rows
do not show the 705 ALMs of urom + drom2 that Quartus had in logic.

**Deepest register-to-register paths** (`verify/tools/depth.py` on the yosys netlist, LUT levels; an M10K output
counts 3, an MLAB read 1.5, a carry step 0.05; a structural estimate, not a timing analysis):

| | Deepest 10 endpoints |
|---|---|
| checkpoint 1 | 14.0 bus write data, 14.0 micro-address, 13.0 SR, 13.0 routine-chain register, 12.7 prefetch PC, 12.6 X flag, 12.0 ALU operand, 12.0 RES, 11.0 register file (enable / A7) |
| checkpoint 1b | 8.1 prefetch PC, 8.05 FIN decision, 8.0 BIU strobes, 8.0 ALU operand, 8.0 N / Z flags, 8.0 X V C flags, 8.0 RES, 8.0 decode result (2), 7.05 AU operand |

### Expected Quartus results (an expectation, not a measurement)

- **ALMs ≈ 1,550–1,750** for the `m68ksv_qtop` revision (fx68k: 2,047). Reasoning: at checkpoint 1 Quartus needed
  2,509 ALMs for the logic yosys counted as 4,663 LUT + carry cells in the same top (3,214 minus the 705 ALMs of urom
  and drom2, which yosys had in M10K): 0.54 ALM per yosys cell. Checkpoint 1b: 2,851 cells × 0.54 ≈ 1,530, plus
  60 ALMs for the 6 MLABs (Quartus counts them as ALMs), plus packing slack. The register count should drop to
  roughly 1,250 (yosys FF −378, and the 103 flops of the in-logic urom / drom2 go away).
- **RAM blocks ≈ 22** (test RAM 8, urom 8, drom1 4, drom2 1, drom3 1), **MLABs 6**, **DSP 1**. If `m68ksv_urom` or
  `m68ksv_drom2` still shows ALUTs and no block-memory bits in map.rpt, or a 276007 / "uninferred" message names
  `m68ksv_rf`, that is the first thing to look at.
- **Fmax ≥ 96 MHz expected, with margin.** At checkpoint 1 the deepest yosys paths were 12–14 levels and Quartus
  reached 87.0 MHz (11.5 ns); now no path is deeper than 8.1 and every chain named in the checkpoint 1 concerns was
  split at a register. Scaling naively gives ~7–8 ns. Risks that the yosys depth does not capture: the MLAB read time
  (the register-file data feeds the e2 muxes, the bus-address check and the prefetch-address adder), M10K
  clock-to-output on the decode / microcode paths, and routing in a fuller device.
- The user's `quartus_sta -t timing_paths.tcl m68ksv_qtop` (below) gives the 30 worst paths if it misses.

### Measured Quartus results (user's compile 2026-11-15 02:09, Quartus 17.0.2, 5CSEBA6U23I7, 96 MHz constraint)

| Revision | ALMs | Registers | M10K | MLAB bits | DSP | Fmax slow 100 C | Fmax slow −40 C (worst corner) | Worst setup slack |
|---|---|---|---|---|---|---|---|---|
| `m68ksv_qtop` (checkpoint 1b) | **1,583** | 1,070 | 22 | 3,072 | 1 | 115.17 MHz | **106.81 MHz** | +1.055 ns (−40 C) |
| `m68ksv_qtop_fx68k` | 2,047 | 1,546 | 14 | 0 | 0 | 100.0 MHz | 99.13 MHz | — |

Both targets met: 23 % fewer ALMs than fx68k and ~11 % above 96 MHz at the worst corner. `timing_paths.tcl` ran
cleanly on both revisions (0 errors, 0 warnings; output in `syn/quartus/output_files/<rev>.paths.txt`). m68ksv's
worst paths (slow 100 C): `xb_q` → `ccr_q` (7 levels, +1.734 ns), `c_sz` → `res`, `rf_a.ra_q` (MLAB read address) →
`fpc` (prefetch PC adder), `dv_q` → `dv_r` (divider step). fx68k's worst: `Ir` → `nanoAddr` (10 levels, +0.417 ns).

### fx68k in Verilator (probe for checkpoint 2)

**Cause of "halted 1 reset 1 as 1"**: those are the probe's printout of the `oHALTEDn`, `oRESETn` and `ASn` pins
(1 = not halted, not resetting, no strobe), not a halt. Under Verilator 5.052 with `--no-assert` and
`-Wno-BLKANDNBLK` fx68k fetches the reset vectors at system clock 422 and runs; the probe's reset sequence (pwrUp 40 clocks,
extReset 400, HALTn high, enPhi1 / enPhi2 alternating every clock) is correct per fx68k's notes. The checkpoint 1 build under
Verilator 4.204 never asserts AS and does drive `oHALTEDn` low, so 4.204 is the problem there. fx68k's files were not
edited (built from the downloaded copy, `verify/fx68k_build.sh`, which also copies microrom.mem / nanorom.mem next
to the binary because fx68k reads them by relative path).

The probe was rewritten (`verify/tb/fxprobe.cpp`): a setup program loads the test's registers and SR and jumps to
the test PC, two NOPs at the final PC, and fx68k's own registers (`--public-flat-rw`) are read when the first NOP
prefetches final PC + 4. Sample: every 80th test of all 124 files (about 100 per file) plus all 3,739 excluded tests
(`fx68k_run.sh <build> -n 100 -x verify/suite_exclusions.txt <suite>/*.bin`):

| fx68k vs suite | Run | Skipped (setup-area clash) | Registers + SR + RAM + final PC equal | Bus order equal |
|---|---|---|---|---|
| Tests without an address error | 10,243 | 3 | 10,157 (99.2 %) | 10,033 |
| Address-error tests | 2,236 | — | 635 | 2,127 (aborted cycle left out) |

Where fx68k and the suite differ (m68ksv follows the suite in all of these today; checkpoint 2 has to decide them
against fx68k / MAME):

- DIVS / DIVU flags (71 tests in the sample, e.g. N / Z on overflow) and CHK flags (3): fx68k's undocumented flags
  differ from the suite's.
- `LINK A7` (12): fx68k pushes the old A7, the suite (and m68ksv) the decremented A7.
- Address-error frames: mostly the stacked PC low word (by 2) and the access-information word; on the faulting access
  fx68k asserts AS for 2.5 clocks without data strobes, the suite and m68ksv run no cycle.
- Bus order: PC-relative operand reads are program space (FC 6) on fx68k, data space (FC 5) in the suite; RTE / RTR
  read SR (CCR) at SP before PC high at SP + 2 on fx68k, the suite the other way round; CHK taking the exception: the
  suite has one more prefetch before the frame.

**fx68k's verdict on the three disputed exclusion classes** (report only; the exclusion list is unchanged):

| Class | Suite | m68ksv | fx68k |
|---|---|---|---|
| ASR, register count > size, negative operand (3,736 tests) | X = C = 0 | X = C = 1 | X = C = 1 on all 3,736 (and every other register, RAM and SR bit equal to the corrected expectation) |
| ASL.b #2,D2 #1582 / #1760 | D2 bits 31–8 change | only the low byte changes (cdfb7ff8, SR 270a / 417c7ef4, SR 271b) | identical to m68ksv (cdfb7ff8, 270a / 417c7ef4, 271b) |
| DIVU zero divide #5744 | stacked PC c00, SR 2710 | stacked PC c04, SR 2718 | identical to m68ksv (stacked PC c04, SR 2718) |

### Quartus handover

- `rtl/m68ksv_all.sv` regenerated (`verify/tools/mkall.sh`); pre-compile check:

```text
== pre-compile check: rtl/m68ksv_all.sv
-- module-level loops (each must sit inside generate ... endgenerate):
3655:    for (int i = 15; i >= 0; i--) begin
-- system-function bounds, size casts, assignment patterns:
-- set membership (inside):
-- bit-select on an expression:
== end of check
```

  The one hit is a `for (int i ...)` inside an `always_comb` (accepted by Quartus 17). Verilator `--lint-only -Wall`
  on the test top: clean apart from the two intentional loop-index width truncations.
- Revisions `m68ksv_qtop` (m68ksv 68000) and `m68ksv_qtop_fx68k` (fx68k) as before; `m68ksv_qtop.sv` and
  `rtl/m68ksv_fleet.sv` were updated for the debug-port change; fx68k's files, `microrom.mem` / `nanorom.mem` and the
  `.qsf` / `.sdc` files are unchanged.
- New `syn/quartus/timing_paths.tcl` (`quartus_sta -t timing_paths.tcl <revision> [n]`): writes the worst n (30)
  setup paths, one per endpoint, with slack, data delay, logic levels, from and to, at the slow 1100 mV 100 C corner,
  to `output_files/<revision>.paths.txt`. Not run here (no Quartus): the Tcl uses standard TimeQuest commands but is
  untested.

### Not done in checkpoint 1b

- No Quartus result: ALMs and Fmax are expectations above.
- The address-error frame / bus-order differences between the suite and fx68k are reported, not resolved (checkpoint
  2).
- Further area items left: the division sign handling (four negations, ~80 carry cells), the 75-bit microword
  register, the AU / ALU operand muxes. Not needed for the expected area; first candidates if the compile disagrees.

## How to rerun

```bash
python3 -I verify/tools/conv_harte.py <suite>/68000/v1 <bin dir>   # once: JSON -> binary for the harness
M68KSV_TESTS=<bin dir> verify/run_all.sh <build dir>              # build, whole suite (also with enable gaps), smoke
verify/fx68k_build.sh <fx68k source dir> <fx build dir>             # fx68k probe (Verilator 5.052)
verify/fx68k_run.sh <fx build dir> -n 100 -x verify/suite_exclusions.txt <bin dir>/*.bin
verify/tools/mkall.sh                                              # rtl/m68ksv_all.sv + pre-compile check
verify/tools/yosys.sh <out dir>                                    # yosys estimate + path depth (depth.py)
python3 -I verify/tools/exclusions.py <suite>/68000/v1 > verify/suite_exclusions.txt
```

`<build dir>/run_all.txt` is the per-file table above; `harte -v N -t idx file.bin` prints failure details,
`-tr K` a per-clock bus trace.

## References (downloaded this session into the scratchpad, not into the repo)

| Reference | URL | Ref |
|---|---|---|
| Suite: SingleStepTests 680x0 (Tom Harte), `68000/v1`, 124 files, 1,000,060 tests | https://github.com/SingleStepTests/680x0/archive/e0d5ece9670205cc84a0101081837deb446f86a3.zip | commit e0d5ece9670205cc84a0101081837deb446f86a3 (2024-05-14, "Import initial tests.") |
| fx68k (Jorge Cwik) | https://github.com/ijor/fx68k/archive/refs/heads/master.zip | master = commit 0602ee4627b10f301298f2673d826cdd6baa9327 (2021-02-16) |
| MAME `src/devices/cpu/m68000/` (m68000.h ALU helpers, m68000-sdf.cpp divu / divs) | local copy `Projects/Mame_Source` | as present locally |

## Checkpoint 2 (68000 cycle- and bus-exact) + 2b (68008 / 68008FN / 68EC000) — status 2026-11-15 (second session)

Every number below was produced by a script in this session (commands in "How to rerun (checkpoint 2)"). Anything not
listed as run was not run. Verilator 4.204 for the suite / directed tests / MAME 68008 lockstep, 5.052 for the fx68k
lockstep (fx68k needs it). **Checkpoint 2 is not complete in one respect: the bus-error (`-berr`) lockstep rows still
mismatch** (register / flag side effects of the aborted instruction, see "Open"); everything else is listed below.
*(Superseded by "Checkpoint 2 completion (third session)" at the end of this report: the bus-error rows now pass, the
fitted `pb` table and `pbfit.py` are gone.)*

### Summary

| Item | Status |
|---|---|
| Suite (68000): registers / RAM / prefetch / bus order / cycles / timed lists | **done**: 794,139 / 794,139 pure-suite tests on every column; corrected tests: state 202,181 / 202,182, timed 202,181 (the one left is a probe artefact, verdict below); with 0-3 idle clocks between enables: same state / bus-order totals |
| fx68k lockstep, plain / waits / VPA / BR / HALT | **0 mismatches**, 12.8 M CPU clocks per row (table below) |
| fx68k lockstep, IPL | 1 mismatching run of 64 (12.7 M clocks) — not traced |
| fx68k lockstep, reset mid-instruction, combined | 4 / 64 runs each (class b, open) |
| fx68k lockstep, BERR | open: 48 / 64 runs (frame contents now mostly fitted; register side effects open) |
| Directed sweeps (IPL / HALT / BR / BERR on each phase per instruction class) | **done** (new `-sweep` mode): IPL 0 mismatches; HALT 8 / 64 runs, BR 3 / 64 runs (CMPM (An)+ register side effect after a bus wait, frame contents); BERR 33 / 64 runs (as the BERR row) |
| HALT + BERR bus retry | **done, manual-verified, no lockstep oracle** (`verify/tb/retry.cpp`, 8 / 8 on every configuration) |
| MV_PD I/N verdict, CHK (d8,PC,Xn) case | **resolved**: m68ksv now follows fx68k (I/N from `inExcept01`), 100 corrected tests pass; CHK case = probe artefact, m68ksv = MAME |
| 2b: 68008 / 68008FN / 68EC000 | **done**: suite state 100 % on all four builds; MAME m68008 bus-cycle lockstep 0 mismatches (12 M clocks each); 68EC000 16-bit = fx68k lockstep 0 mismatches; Quartus revisions added |
| `verify/make_corrections.sh` | **done**: regenerates `suite_corrections.txt` from scratch (downloads, conversion, builds, emit) byte-identical (md5 e66ac0b19c0ee4d69ce4df54237151e8, 202,182 lines, 106 s with 8 jobs) |
| Area guardrail (yosys) | 68000: 2,998 LUTs (2,953 before this session), 487 carry (474), 1,217 FF (1,222), 29 M10K (28), depth 10.0 (10.0); the 2b logic folds away in the 68000 build (below). No Quartus number for this session's RTL |

### Changes in this session (RTL), each lockstep- or suite-verified

| Change | Evidence |
|---|---|
| BERR (synchronised: falling then rising edge) holds the start of the next micro-cycle, in or out of a cycle (fx68k `wClk` includes `~BeI`) | an address error with BERR also asserted started its frame 2 clocks early; BERR tails 0-3 clocks after AS added to the stimulus |
| address error enters `EXC0A` / `HALTA` (one idle word more), a bus error `EXC0` / `HALT`; the spurious-IACK extra micro-cycle removed (the BERR hold provides it) | `-berr`, `-irq` rows |
| group-0 (double-fault) state ends at the second refill word after the vector fetch (`VECJMP_G0`), not at the first instruction boundary | fx68k's `rExc*` latches traced (GRP0DBG): BERR on the final refill prefetch is a bus error, not a halt |
| bus-error frame: stacked PC offset per word (`pb`, 3 bits, fitted with `verify/tools/pbfit.py` from 15,000+ collected frames; TRAPV + 2 when it traps), stacked IR / access-word IR bits / I/N of the next instruction when the faulting cycle's second word takes FIN, `bc` (stack the CCR from before the word's own flag write; live CCR keeps the new flags) | lockstep `-collect` (frames differing 2,290 → 87 of ~12,800) |
| I/N of the MOVE.W -(An) write fault = whether the next instruction traps (fx68k `inExcept01`) | 100 corrected tests now pass; lockstep known-case exemption removed |
| address error on a word that started after a bus wait (BR / HALT): stacked PC + 2 x `pl` (DBcc, JSR (d16,An) / (d8,An,Xn) / (d16,PC) / (d8,PC,Xn), MOVEM.w (d8,An,Xn) observed; MOVEM.l and (d8,PC,Xn) forms by structure) | HALT / BR sweeps; collected AE frames after a wait: all other words equal (table of 70 words) |
| odd stack: BSR.W first push faults stack fpc - 2 | final plain lockstep run (was the 1 mismatch of 64) |
| level-7 pending cleared while FC = 7 with level 7 in the level latch; that latch (`int_inl`, pending logic only) also loaded after the IACK's IRC -> IR | IPL sweep 4 / 4 mismatching → 0 / 64 |
| spurious IACK takes the data bus one clock later for IRC (fx68k) | `-irq` row |
| bus retry (HALT + BERR), 8-bit bus (68008 / 68EC000), MODE latch, A0 / DS_n / MODE pins, DIP48 IPL2/0 and BGACK, 20 / 22 address pins | retry test, family suite runs, MAME 68008 lockstep |
| stacked-PC offsets merged into one adder each (area) | suite / lockstep unchanged |

### Lockstep against fx68k (final, `verify/tb/lockstep.cpp`, seed 101, 64 runs x 400,000 phases per row)

| Stimulus | Phases compared (CPU clocks) | Mismatching runs |
|---|---|---|
| none | 25,600,000 (12,800,000) | 0 |
| `-w 3` DTACK waits | 25,600,000 (12,800,000) | 0 |
| `-irq` | 25,353,376 (12,676,688) | 1 |
| `-vpa` 6800 cycles | 25,600,000 (12,800,000) | 0 |
| `-br` BR / BG / BGACK | 25,600,000 (12,800,000) | 0 |
| `-halt` | 25,600,000 (12,800,000) | 0 |
| `-rst` reset mid-instruction | 24,539,535 (12,269,767) | 4 (class b) |
| `-w 2 -irq -vpa -br -halt -rst` | 25,085,912 (12,542,956) | 4 (class b, as `-rst`) |
| `-berr 50` (BERR on 2 % of cycles, 0-3 clock tails) | 8,543,001 (4,271,500) | 48 (open) |
| 68EC000 (CPU = 68001, MODE = 1), none | 25,600,000 (12,800,000) | 0 |
| 68EC000, `-w 2 -irq -vpa -br -halt` (32 runs) | 12,800,000 (6,400,000) | 0 |

A run stops at its first mismatch, so the phase counts are what was compared. Without the BERR row: 202.9 M phases
(101.4 M CPU clocks) for the 68000, 38.4 M phases for the 68EC000.

Bus-error data in collect mode (`-collect`: a mismatch that is only the data of a group-0 frame write is logged and
the run continues; registers / SR compared and resynced at the refill): 8 seeds x 8 runs x 400,000 phases, BERR on 1 /
12 cycles: 12,787 frames, 87 differ in some word (before this session's fit: 2,290 of 15,369); after the frames, 45
register and 35 SR differences; 22 runs stopped on a non-frame difference (register side effects of the aborted
instruction show up as different addresses later).

### Directed sweeps (`lockstep -sweep ipl|halt|br|berr`, 64 runs x 400,000 phases each, seed 101)

At each instruction boundary the next event is placed at an offset that cycles through 0-47 phases (BERR: bus cycle
0-5 after the boundary x 0-3 wait clocks) separately for each instruction class (the suite file whose opcode starts
there).

| Stimulus | Events at suite-class instructions (+ elsewhere) | Classes | Class x offset pairs covered | Phases | Mismatching runs |
|---|---|---|---|---|---|
| IPL (level 7 / random level, held 20-220 phases) | 107,638 (+4,738) | 124 / 124 | 4,053 / 5,952 | 25,600,000 | **0** |
| HALT (2-41 phases) | 252,158 (+17,121) | 124 / 124 | 5,952 / 5,952 | 23,680,464 | 8 |
| BR (then BG / BGACK) | 218,834 (+9,953) | 124 / 124 | 5,942 / 5,952 | 24,604,663 | 3 |
| BERR | 45,434 (+832) | 57 / 124 | 2,002 / 5,952 | 12,987,763 | 33 |

The sweeps found four real differences that the random rows had not (all fixed above: interrupt latch / clear,
address error after a bus wait, odd-stack BSR.W). HALT / BR residue: CMPM (An)+ register update on an address error
after a bus wait (A3 / A6 off by 2 in collect mode) and some frame contents; BERR residue as the BERR row.

### Bus retry (HALT + BERR re-run) — manual-verified, no lockstep oracle

MC68000 User's Manual 5.4.2. `verify/tb/retry.cpp` (built by `build.sh`, run by `run_all.sh` / `run_family.sh`):
BERR + HALT on a word read, a word write, the second word of a long read twice in a row, and on TAS. Checks: the
cycle after the faulted one repeats address, FC, R/W, strobes and (write) data; no bus cycle between the faulted
cycle and the re-run; the re-run starts after HALT is negated (AS 7 phases after HALT negation; BERR negated 2 clocks
before HALT); results correct and no exception; TAS with BERR + HALT takes the bus error exception and is not re-run.
**8 / 8 pass** on the 68000, and on the 68008, 68008FN, 68EC000 8-bit (byte cycles) and 16-bit builds. Not checked:
retry interacting with bus arbitration (the BIU waits for BR / BGACK as for a new cycle) — no test written.

### Verdicts (suite vs fx68k vs MAME)

| Class | Tests | Suite | fx68k = MAME | Evidence |
|---|---|---|---|---|
| `address_error_frame_timing` | 157,852 | address-error processing timed differently | same state, the 68000 timing (AS without strobes for the full cycle, frame 4 + 8 clocks later) | fx68k and MAME agree on every one |
| `address_error_fx68k_not_mame` | 20,235 | frame / side effects | fx68k ≠ MAME in state, both ≠ suite timing | 19,281: all three differ in state (no majority; m68ksv follows fx68k, the lockstep reference); 953: fx68k state = suite (MAME the odd one out). Example: MOVE.W (An)+ with odd An — suite and MAME increment An, fx68k does not (both MAME and fx68k are microcode-derived; the 68000's T3 abort timing decides; real silicon not checked) |
| `rte_rtr_sr_read_first` | 8,049 | PC read before SR | SR read first | MAME rte/rtr micro-routine order; fx68k bus order |
| `chk_flags_no_extra_prefetch` | 4,948 | CHK flags / an extra prefetch | N from Dn, Z / V / C from the bound compare, no extra prefetch | MAME chk routine; fx68k |
| `div_undocumented_flags` | 4,693 | DIVU / DIVS overflow / zero flags | MAME alu_sub flags | MAME divu / divs routines; fx68k |
| `pcrel_read_program_space` | 4,360 | PC-relative operand read in data space | program space (FC 6 / 2) | MAME `SSW_PROGRAM` on these reads; fx68k FC |
| `link_a7_pushes_old_a7` | 1,005 | LINK A7 pushes A7 − 4 | pushes the old A7 | MAME link routine; fx68k |
| `addq_subq_long_an_8_clocks` | 731 | 4 clocks short | 8 clocks | MAME; fx68k |
| `divs_late_overflow_timing` | 307 | DIVS late overflow timing | Cwik formula timing | MAME; fx68k |
| `mame_only_setup_clash` | 2 | — | test RAM overlaps the probe's setup area | not a verdict; corrected to fx68k |

Verdicts decided in this session:

| Case | Suite | MAME | fx68k | m68ksv now | Evidence / reason |
|---|---|---|---|---|---|
| MOVE.W <ea>,-(An) write address error, next instruction traps (100 tests): access-word I/N | 0 | 0 | 1 | **1 (fx68k)** | fx68k models the die's `inExcept01` latch, loaded at IR -> IRD of the final prefetch, which this routine runs before the write; MAME's SSW_N is set by hand in its exception code; the suite comes from an emulator. Amiga candidate 2 |
| CHK (d8,PC,Xn) #5948 (1 test) | frame | frame (I/N byte b6) | — (probe stopped after the first prefetch: no frame, SSP unchanged) | MAME's | the corrected expectation is an fxprobe artefact (impossible for an address error); m68ksv = MAME on state and timed list. Left in the corrections file (generated), counted as the 1 corrected failure |
| TRAPV after an instruction that overflowed internally without setting V (ADDA.L overflow, CCR V = 0) | — | traps (tests its ALU status `m_isr`) | no trap | **no trap (fx68k, manual)** | directed lockstep test (`TRAPVTEST=1`): fx68k = m68ksv; MAME 68008 lockstep sees it once per ~12 M clocks (classified, resynced). Amiga candidate 3 |
| 68008 odd word access | — | two full byte accesses (a write is performed), then the address error | — (no 8-bit oracle) | 68000 rule: one AS-only cycle, no strobe, no write | the 68008 runs the 68000 microcode and bus controller logic; MAME's 8-bit generator splits the access before its address check. No oracle can settle it; the MAME 68008 lockstep resets both models at such a point (counted) |
| Group-0 state after the vector fetch | — | — | BERR on the final refill prefetch = bus error | as fx68k | GRP0DBG trace of fx68k's latches |

### Amiga candidates (undecided or MAME-vs-fx68k behaviours worth a real 68000; the user writes the program)

Test program for all five: `verify/amiga/` (SAS/C 6.58; `m68ktest.c` + `m68ktest_a.a`, build/run in its README).

**Emulator run 2026-11-15** (Amiberry, WinUAE-based; KS 2.04 / exec V37.175; 68000, "more compatible", 24-bit
addressing, unimplemented CPU opcodes, no MMU / FPU, 7.159090 MHz cycle-exact, JIT off). Both controls passed (T2b I/N
= 0, T3b trapped). Amiberry agrees with fx68k / m68ksv on all five:

| Case | Amiberry | Agrees with |
|---|---|---|
| 1 MOVE.W (A0)+, A0 odd | A0 not incremented (frame: access $3015 = read, I/N 0, FC 5; addr buf+1; IR $3018; PC = next) | fx68k, m68ksv (not suite / MAME) |
| 2 MOVE.W D0,-(A1) odd, ILLEGAL next | I/N = 1; stacked IR = $4AFC (the prefetched ILLEGAL); A1 decremented | fx68k, m68ksv (not MAME / suite) |
| 3 TRAPV after ADDA.L overflow, V = 0 | no trap | fx68k, m68ksv (not MAME) |
| 4 DIVU by zero | stacked PC = next instruction; N 1 Z 0 (D0 $80011234) / N 0 Z 1 (D0 $00005678); V = C = 0 | MAME, fx68k, m68ksv (not suite) |
| 5 ASR.L by 40 on −1 | X = 1, C = 1 | MAME, fx68k, m68ksv (not suite) |

An emulator model, not silicon: it makes every case a 3-to-1 majority for m68ksv's current behaviour. Real 68000
Amiga run: not done. **User decision 2026-11-15:** the emulator run is accepted as good enough; a real-hardware run
happens only if a bug points back at one of these cases.

1. **MOVE.W (An)+ address error: is An incremented?** `MOVE.W (A0)+,D0` with A0 = $00001001 (odd), any SSP. Address
   error. Suite and MAME: A0 = $00001003 after the exception; fx68k (and m68ksv): A0 = $00001001. Read A0 in the
   address-error handler.
2. **I/N bit of a write fault when the next instruction traps.** `MOVE.W D0,-(A1)` with A1 = $00002003 (the write goes
   to odd $2001), immediately followed by `ILLEGAL` ($4AFC). Address error; read the access word at SSP+0 of the
   7-word frame: bit 3 (I/N). fx68k / m68ksv: 1; MAME / suite: 0. Control: the same with `NOP` next (expected 0 on
   all three; not run as a separate test).
3. **TRAPV after an internal overflow.** `MOVE.L #$7FFFFFFF,D5 / MOVEA.L #1,A6 / MOVE #0,CCR / ADDA.L D5,A6 / TRAPV /
   MOVEQ #$55,D7`. fx68k / m68ksv: no trap (D7 = $55); MAME: TRAPV trap (vector 7).
4. **DIVU by zero: stacked PC and flags** (from checkpoint 1): `DIVU (d16,A7),D0` with a zero divisor. Suite: stacked
   PC = instruction address, N = Z = 0; MAME / fx68k / m68ksv: PC of the next instruction, N = Dx bit 31, Z = (Dx high
   word = 0).
5. **ASR with count > size on a negative operand** (from checkpoint 1): `MOVEQ #-1,D0 / MOVEQ #40,D1 / ASR.L D1,D0`.
   Suite: X = C = 0; MAME / fx68k / m68ksv: X = C = 1.

### Open (not done)

- **(b) reset mid-instruction** (`-rst`, combined rows: 4 / 64 runs each): the CCR of the instruction interrupted by
  RESET differs (e.g. C, seen in a later stacked SR). m68ksv writes flags at the e0 after the ALU word; fx68k commits
  them at its own T-state; aligning that needs the flag-commit phase per micro-instruction. Not traced further.
- **BERR register / flag side effects**: which register writes of the aborted instruction fx68k commits before the bus
  error is taken differs per micro-word ((An)+ / -(An) long reads update An by 2 or 4 late; .L ALU results where only
  the low word is written - the 68000's 16-bit ALU; MUL / RMW / shift flag timing). The frame PC / IR / I/N / CCR
  fields are fitted; the register effects need a per-word "cancel / half-write" field. `-berr` rows stay open.
- **CMPM (An)+ after a bus wait** (HALT / BR sweeps): the An write on an address error (the existing `lk` rule covers
  .b / .w only).
- One `-irq` run of 64 mismatches (not traced). Spurious-interrupt / address-error coincidences remain possible.
- The BERR sweep reaches 57 of 124 classes (bus-error handling ends most runs early).
- Not run: the idle-clock (`-gap 3`) suite run on the 8-bit builds; fx68k lockstep with `-berr` and `-halt` together
  (fx68k has no retry, so that combination has no oracle); Quartus (the user compiles).

### Checkpoint 2b: 68008 / 68008FN / 68EC000

Design (DESIGN.md 6, 7, 9): one BIU with a `bus8` input — constant 1 for 68008 / 68008FN, the MODE latch (sampled
while reset is asserted) for the 68EC000, constant 0 elsewhere. An 8-bit word access = two byte cycles back to back,
the execution unit held at its second micro-word for exactly 4 clocks; IACK one byte cycle at A0 = 1; TAS one byte RMW
cycle; retry per byte cycle; no bus grant between the two byte cycles of a word. Pins: `A0`, `DS_n`, `MODE` added;
68008 drives A19-A1 (A23-A20 = 0), 68008FN A21-A1; DIP48: `IPL_n[2]` = the combined IPL2 / IPL0 pin, BGACK ignored;
68EC000 8-bit mode: data on D7-D0, UDS_n = A0, LDS_n = DS_n (MC68EC000 pin use). Execution unit and microcode
unchanged.

Suite (`verify/run_family.sh`, same corrections / exclusions as the 68000): registers / RAM / prefetch must match;
on the 8-bit bus the bus order is compared with every suite word access split into two byte cycles, and the cycle
count against the suite's + 4 per word access (MAME m68008's rule).

| Build | Tests | Pass | Cycles (suite + 4 per word) | Bus order (byte cycles) | Excluded (corrected ok) | Corrected: state pass | Retry test |
|---|---|---|---|---|---|---|---|
| 68008 (20 address pins; 2 tests skipped: two addresses alias) | 794,137 | 794,137 | 797,876 / 797,876 | 797,876 | 3,739 (3,736) | 202,181 / 202,182 | 8 / 8 |
| 68008FN (22 pins) | 794,139 | 794,139 | 797,878 / 797,878 | 797,878 | 3,739 (3,736) | 202,181 / 202,182 | 8 / 8 |
| 68EC000, MODE = 0 (8-bit) | 794,139 | 794,139 | 797,878 / 797,878 | 797,878 | 3,739 (3,736) | 202,181 / 202,182 | 8 / 8 |
| 68EC000, MODE = 1 (16-bit; timed lists too: 797,878 / 202,181) | 794,139 | 794,139 | 797,878 / 797,878 | 797,878 | 3,739 (3,736) | 202,181 / 202,182 | 8 / 8 |

(cycle / bus-order columns count the non-corrected tests; the corrected test that fails is the CHK probe artefact.)

**MAME m68008 bus-cycle lockstep** (`verify/mame8_build.sh <dir> <cpu>`, `mame8_<cpu> -cpu <cpu> -seed 7 -runs 40
-clocks 300000`): MAME's generated cycle-exact m68008 (unmodified source, the existing C++ model) and m68ksv run the
same random instruction stream (lockstep's), immediate DTACK, no interrupts; every byte cycle compared in order:
start time (S0, CPU clocks), address on the configuration's pins, FC, R/W, data. At an m68ksv address error (the
documented 68008 divergence) or MAME's TRAPV quirk both are reset with m68ksv's memory and registers and continue the
stream (counted).

| Build | CPU clocks | Byte cycles compared | Mismatching runs | Resets at an address error | at MAME's TRAPV quirk |
|---|---|---|---|---|---|
| 68008 (A19-A0) | 12,000,000 | 2,578,071 | **0** | 10,943 | 1 |
| 68008FN (A21-A0) | 12,000,000 | 2,560,932 | **0** | 11,717 | 1 |
| 68EC000, MODE = 0 (compared on A21-A0: MAME's m68008 core drives 22 bits) | 12,000,000 | 2,560,932 | **0** | 11,717 | 1 |

Harness note: the MAME model's `reset()` (our harness code, `verify/mame/mame_model.cpp`) now keeps the CCR, as fx68k
and m68ksv (Motorola leaves it undefined); without it a resync showed a CCR difference that is not a CPU behaviour.

### yosys (`verify/tools/yosys.sh`, `YCPU=<cpu>`; yosys 0.66 `synth_intel_alm -family cyclonev`; an estimate, not Quartus)

| m68ksv | LUTs (ALUT2-6) | carry | FF | M10K | MLAB cells | DSP | max depth |
|---|---|---|---|---|---|---|---|
| 68000, start of this session (cp2a snapshot) | 2,953 | 474 | 1,222 | 28 | 32 | 1 | 10.0 |
| 68000, now | 2,998 | 487 | 1,217 | 29 | 32 | 1 | 10.0 |
| 68008 | 3,018 | 487 | 1,225 | 29 | 32 | 1 | 10.0 |
| 68008FN | 3,024 | 488 | 1,226 | 29 | 32 | 1 | 10.0 |
| 68EC000 | 3,047 | 487 | 1,227 | 29 | 32 | 1 | 10.0 |

The 68000's +45 LUTs / +13 carry / +1 M10K come from this session's checkpoint 2 features (bus retry, BERR hold,
`pb` / `pl` / `bc` fields, the interrupt latch); the 2b logic folds away there: in the 68000 netlist none of `half`,
`hb`, `mode8` survives (yosys JSON netnames), `k8` / `rr` survive because the retry (a 68000 feature) uses them. The
8-bit configurations cost 20-49 LUTs more than the 68000. Quartus guardrail (68000 <= 2,047 ALMs, >= 96 MHz): last
measured 1,795 ALMs / 114.3 MHz on the checkpoint 2 RTL of the previous session; this session's RTL is not compiled.

### Files changed / new in this session

- RTL: `rtl/m68ksv.sv` (CPU check for 68008 / 68009 / 68001, bus8 / MODE latch, A0 / DS_n / MODE pins, DIP48 IPL /
  BGACK, address pins, BERR hold, level-7 clear), `rtl/m68ksv_biu.sv` (8-bit split words, bus retry, BERR hold
  output), `rtl/m68ksv_eu.sv` (group-0 state, EXC0A / HALTA, `pb` / `pl` / `bc`, IR / I/N rules, `int_inl`, spurious
  IACK data, merged stacked-PC adders), `rtl/gen/m68ksv_ucode.py` (EXC0A / HALTA / VECJMP_G0 labels, fields `pb` (3
  bits), `pl`, `bc`, fitted PB table, odd-stack BSR.W, spurious extra word removed, `-w` word dump), generated
  `rtl/m68ksv_upkg.sv`, `m68ksv_urom.sv`, `m68ksv_drom.sv`, `rtl/m68ksv_all.sv`, `verify/tb/m68ksv_ualabels.h`;
  `rtl/m68ksv_fleet.sv` (A0 / DS / MODE), `fleet_types.svh` (comments: IPL2/0, ds_n).
- Verification: `verify/make_corrections.sh` (new), `verify/run_family.sh` (new), `verify/mame8_build.sh` +
  `verify/tb/mame8.cpp` (new), `verify/tb/retry.cpp` (new), `verify/tools/pbfit.py` (new), `verify/tb/lockstep.cpp`
  (`-collect`, `-sweep`, BERR tails, 68EC000 MODE, TRAPVTEST, traces; known-case exemption removed),
  `verify/tb/harte.cpp` (`-bus8`, `-abits`), `verify/build.sh` (`M68KSV_CPU`, retry), `verify/run_all.sh` (retry),
  `verify/lockstep_build.sh` (`M68KSV_CPU`), `verify/tools/yosys.sh` (`YCPU`), `verify/mame/mame_model.cpp` (reset
  keeps the CCR).
- Quartus: `syn/quartus/m68ksv_qtop.sv` (8-bit RAM path, mode_pin), `m68ksv_qtop_68008.qsf`,
  `m68ksv_qtop_68008fn.qsf`, `m68ksv_qtop_68ec000.qsf` (each = `m68ksv_qtop.qsf` + one `VERILOG_MACRO` line),
  `m68ksv_qtop.qpf` (three revisions added), `README.md`. fx68k files byte-identical (checked against the download).
- Docs: `DESIGN.md` (5, 6, 7, 9), this report.

### Quartus (the user compiles; nothing here was run in Quartus)

```bash
cd syn/quartus
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_fx68k     # fx68k size reference
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008 DIP48
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sta -t timing_paths.tcl <revision>                     # worst paths -> output_files/<revision>.paths.txt
```

Pre-compile check on the regenerated `rtl/m68ksv_all.sv` (`verify/tools/mkall.sh`):

```text
-- module-level loops (each must sit inside generate ... endgenerate):
4801:    for (int i = 15; i >= 0; i--) begin
5013:    for (int i = 1; i < 16; i++) dv_q1 = dv_q1 + {3'd0, dv_q[i]};
5245:    for (int i = 0; i < 16; i++) mul_n = mul_n + {4'd0, mul_t[i]};
-- system-function bounds, size casts, assignment patterns:
-- set membership (inside):
-- bit-select on an expression:
```

The three hits are `for (int i ...)` inside `always_comb` (accepted by Quartus 17). Verilator `--lint-only -Wall` is
clean (apart from width / unused warnings) on `m68ksv` for all four CPU values, on `m68ksv_qtop` with each revision
macro and on `m68ksv_fleet`. Previous Quartus result (previous session's checkpoint 2 RTL, 2026-11-15 12:43): 68000
1,795 ALMs, 114.3 MHz worst corner; fx68k 2,047 ALMs, 99.1 MHz.

**Measured (user's compiles 2026-11-15 14:28 / 15:32–15:34, this session's RTL, Quartus 17.0.2, 5CSEBA6U23I7, 96 MHz):**

| Revision | ALMs | Registers | RAM blocks | DSP | Fmax slow 100 C | Fmax slow −40 C | Worst setup slack | `m68ksv_biu` ALMs |
|---|---|---|---|---|---|---|---|---|
| `m68ksv_qtop` (68000) | 1,826 | 1,315 | 33 | 1 | 122.14 MHz | 116.28 MHz | +1.817 ns | 50.6 |
| `m68ksv_qtop_68008` | 1,845 | 1,359 | 33 | 1 | 118.55 MHz | 113.15 MHz | +1.579 ns | 59.0 |
| `m68ksv_qtop_68008fn` | 1,835 | 1,305 | 33 | 1 | 119.88 MHz | 116.77 MHz | +1.853 ns | 59.2 |
| `m68ksv_qtop_68ec000` | 1,861 | 1,349 | 33 | 1 | 114.42 MHz | 109.88 MHz | +1.316 ns | 65.7 |
| `m68ksv_qtop_fx68k` (12:43 compile) | 2,047 | 1,546 | 14 | 0 | 100.0 MHz | 99.13 MHz | — | — |

All revisions meet ≤ 2,047 ALMs and 96 MHz. The 8-bit BIU paths survived synthesis (BIU larger than in the 68000
revision; 68EC000 largest, MODE latch + both widths). `timing_paths.tcl` ran on all four (exit 0); worst paths are in
the execution unit (ALU result / CCR / DIV overflow / address-unit operands, 4–8 levels), none in the BIU.

### How to rerun (checkpoint 2)

```bash
verify/make_corrections.sh <work dir>                                 # suite_corrections.txt from scratch (downloads + builds)
M68KSV_CORR=<work dir>/suite_corrections.txt M68KSV_TESTS=<work dir>/bin verify/run_all.sh <dir>   # 68000 suite, gap run, smoke, retry
verify/run_family.sh <dir>                                            # 68008 / 68008FN / 68EC000 (8 / 16) suite + retry (same env vars)
verify/lockstep_build.sh <fx68k dir> <dir>                            # Verilator 5.052; M68KSV_CPU=68001 for the 68EC000 (MODE = 1)
./lockstep [-seed N] [-runs N] [-ticks N] [-w N] [-irq] [-vpa] [-br] [-halt] [-rst] [-berr P] [-sweep ipl|halt|br|berr]
           [-collect] [-v 1..4] <suite .bin ...>                      # in <dir>; -collect: frame log + register resync
verify/mame8_build.sh <dir> [68008|68009|68001]; <dir>/mame8_<cpu> -cpu <cpu> -seed 7 -runs 40 -clocks 300000 <suite .bin ...>
PCTRACE=1 ./lockstep ... | grep '^P ' > p.txt; python3 -I verify/tools/pcderive.py verify/tb/m68ksv_ualabels.h p.txt   # PC-load points (third session)
YCPU=<cpu> verify/tools/yosys.sh <dir>; verify/tools/mkall.sh
```

The suite paths default to the scratchpad copy (`m68ksv_refs/bin68000`, `m68ksv_refs/suite_corrections.txt`); after a
reboot run `make_corrections.sh` and point `M68KSV_TESTS` / `M68KSV_CORR` at its `bin/` and output.

## Checkpoint 2 completion (third session, 2026-11-15)

Every number here was produced by a script in this session (Verilator 4.204 for the suite / family / MAME 68008 runs,
5.052 for the fx68k lockstep; yosys 0.66). Nothing was run in Quartus. Snapshot of the starting state:
scratchpad `m68ksv_cp2b_snapshot/`.

### Summary

| Goal | Result |
|---|---|
| 1. Bus error vs fx68k | **done**: `-berr 50` 0 / 64 runs (seed 101; was 48), BERR sweep 0 / 64 on four seeds (was 33); `-collect` 16,536 frames, **0** differ, no register / SR difference; `ABORTCHK` 0 register / CCR differences at 938,963 + 848,713 bus-error points. Seed 202 `-berr 50`: 1 / 64 (open, below) |
| 2. Fitted stacked-PC table replaced | **done**: `pc68`, a model of the 68000's PC register loaded where its microcode loads it (field `pu`); `pb` (fitted), `pk` (address-error table), `bc` and `verify/tools/pbfit.py` removed; the address-error PC comes from `pc68` too |
| 3. Reset mid-instruction | **partly**: the execution unit completes the micro-word whose T3 has passed (fx68k's commit point) before its reset; `-rst` 4 → 2 / 64 (the flag case fixed); 2 runs open (register-write timing outside bus-error points, below) |
| 4. IRQ / combined / HALT / BR | IPL sweep 0; `-irq` 1 / 64 (seed 101; 0 on seed 202); HALT sweep 8 → 3 / 64, BR sweep 3 / 64 (the same three runs as before); combined row 4 / 64; traced, verdicts below |
| 5. Regression | suite / smoke / retry / idle-clock / family / MAME 68008 unchanged (tables below) |

### Goal 2: how the stacked-PC table was replaced

The 68000 stacks its internal PC register (MAME's microcode-generated bus-error routine: `bser1 au = pc`), which its
microcode loads at fixed micro-words (fx68k: `au2Pc` at T1, PCL / PCH from the buses at T3). Method:

1. `lockstep` `PCTRACE`: every change of fx68k's PC register, with m68ksv's micro-word and the m68ksv values at that
   edge. fx68k's T1 coincides with m68ksv's e0, its T3 with e2.
2. `verify/tools/pcderive.py` (new): for 1.8 M + 3.4 M traced loads (8 seeds, all stimuli), every load lands on one
   m68ksv word and equals one m68ksv value there: T1: fpc / PCX / AUR; T3: fpc / fpc - 2 / fpc + 2 / PCX / AT /
   vector address. The generator's `PU` table is that output (177 entries + MOVEM word / long pairs by routine
   structure + split routines inheriting their parent's loads). Only mixed results: loads of one half (PCH / PCL)
   when fpc crosses a 64 K boundary (harmless: never at a bus-error point) and bser6's PC <- fault address (not
   modelled: any fault before the refill halts, so no frame can stack it).
3. Two loads were placed one word too early because one m68ksv word served two 68000 contexts: MUL's first count
   step and DBcc's not-taken path got their own words (no timing change).
4. Check: `PC68CHK` compares `pc68` with fx68k's PC register at every point a bus error can be taken: 938,928 points
   (seed 101) and 833,143 (seed 102 with waits / IRQ / VPA), differences only in EXC0+11..17 (after bser6, see 2).
5. The address-error PC (previously the suite-verified `pk` table): `pc68` after the faulting word equals it in
   8,304 of 8,307 lockstep address errors; the 3 others are the bus-wait cases, now field `pl` derived by the
   generator (the next word loads the PC at its T1, which fx68k runs during the wait: stack fpc). With `pk` removed
   the suite stays at 794,139 / 794,139 and 202,181 / 202,182 corrected (control: `pc68 + 2` drops the corrected
   column to 24,095).

`pc68` is history-dependent (the same word stacks different fpc offsets after different predecessors - 80 of 710 words
in a 4-run sample), which is why no per-word offset table could reach 0.

### Goal 1: register / CCR side effects

A bus error ends the cycle's second micro-word; fx68k completes that word's T3 and never runs the next. New lockstep
probes: `ABORTCHK` (registers + CCR of both CPUs at every e0 that ends a cycle's second word = what a bus error there
would leave), `WRTRACE` (write timeline of both). Starting point: 29,733 differences at 938,963 points (97 classes).
Each write was moved to the 68000's word (DESIGN.md 5): RDY4 / ALU_DN4 / XREG4 / RMW .l (low-word flags + held long
flags, `fh`), ALU_DN2 / AN2 / AN4 / RDY2L / ADDQA (low word first, `lh`), MOVEM.l / MOVEP.l / LEA abs.L to registers
(high word first, `lh` = 2), XMEM / XMEM_L / CMPM / CMPM_L / RDL_PI / MOVE to (An)+ / -(An) / LINK / UNLK / RTS / JSR /
PEA / MOVEM (An)+ (An / SP word, `lk` = 2), bit ops / BTST / NBCD / ABCD / SBCD / Scc / DBcc / EXG / MUL / shifts / MOVE
from a register (write or flag word). Result: 0 differences at 938,963 (seed 101) and 848,713 (seed 102) points; also
0 with `-w 3` (845,574), `-irq` (968,599), `-vpa` (959,595). Two bus-side fixes found by the `-berr` row: BERR on TAS's
read phase releases AS one clock after S7 (fx68k SRMC_RES), and I/N of group 1 / 2 frame pushes is 0 (the `bn` range
had spilled from EXC0 into EXC12C).

### Lockstep against fx68k (final RTL, 64 runs x 400,000 phases per row)

| Stimulus | seed 101: clocks / mismatching runs | seed 202: clocks / mismatching runs |
|---|---|---|
| none | 12,800,000 / **0** | 12,800,000 / **0** |
| `-w 3` | 12,800,000 / **0** | 12,800,000 / **0** |
| `-irq` | 12,676,688 / 1 (run 41) | 12,800,000 / **0** |
| `-vpa` | 12,800,000 / **0** | 12,800,000 / **0** |
| `-br` | 12,800,000 / **0** | 12,647,440 / 1 (run 31) |
| `-halt` | 12,800,000 / **0** | 12,800,000 / **0** |
| `-rst` | 12,436,604 / 2 (runs 8, 40) | 12,438,375 / 2 (runs 5, 33) |
| `-w 2 -irq -vpa -br -halt -rst` | 12,550,673 / 4 | 12,094,507 / 4 |
| `-berr 50` | 12,800,000 / **0** | 12,746,022 / 1 (run 47) |
| 68EC000 (MODE = 1), none | 12,800,000 / **0** | not run |
| 68EC000, `-w 2 -irq -vpa -br -halt` (32 runs) | 6,400,000 / **0** | not run |

(runs split over 8 processes, `-first`; a run stops at its first mismatch.)

### Directed sweeps (one process, 64 runs x 400,000 phases, seed 101 unless noted)

| Sweep | Events at suite classes (+ elsewhere) | Classes | Class x offset pairs | Mismatching runs (before) |
|---|---|---|---|---|
| IPL | 107,638 (+4,738) | 124 / 124 | 4,053 / 5,952 | **0** (0) |
| HALT | 275,438 (+15,943) | 124 / 124 | 5,952 / 5,952 | 3 (8) |
| BR | 218,834 (+9,953) | 124 / 124 | 5,942 / 5,952 | 3 (3, same runs 1 19 31) |
| BERR | 92,114 (+1,569) | 66 / 124 | 2,963 / 5,952 | **0** (33) |
| BERR, seeds 202 / 303 / 404 | 91,147 / 93,141 / 93,270 | 71 / 75 / 70 | 3,408 / 3,393 / 3,278 | **0 / 0 / 0** |

Note: a sweep's event schedule depends on the runs before it in the same process, so sweep runs must be compared in
one process (`lsp.sh`-style parallel splits give different runs; the previous session's numbers are reproduced with
one process: BERR 33, HALT 8, BR 3 on the starting RTL).

### Open (not done) and verdicts

- **Bus waits + run-ahead** (HALT / BR sweep residue, `-br` seed 202, and `ABORTCHK` with `-br` / `-halt`: 1,982 /
  443 differences, all in words after a cycle that waited for the bus): fx68k keeps executing micro-words that do not
  need the bus while a prefetch waits for BR / BGACK / HALT (its prefetch words do not wait for completion); m68ksv
  holds the micro-word that starts the cycle. An address / bus error on such a cycle then sees more of the 68000's
  writes than m68ksv has made (the `pl` / `lk` fields cover the PC and the (An)+ cases). Matching it needs a
  sequencer that runs ahead during arbitration - not attempted (no defined lockstep row combines BERR with BR / HALT;
  fx68k has no bus retry).
- **Reset mid-instruction** (`-rst` 2 runs per seed, combined row): after the e3 / e0 completion, the remaining cases
  are register writes that m68ksv makes one word before fx68k's T3 in words that are not bus-error points (e.g.
  ALU_DN: Dn at the e0 ending the prefetch word, fx68k at the next word's T3; run 8: an An value two lower). Exact
  reset behaviour needs every register write in the 68000's word, not only those at bus-error points - not done.
  Run 40 (seed 101) diverges 88 clocks after the reset release in a shift loop (not traced further).
- `-irq` run 41 (seed 101): not traced (also open in the previous session).
- `-berr 50` seed 202 run 47: after a register shift (ASL.W D3,D3) the STOP that follows fetches its operand one word
  later than fx68k; `-collect` shows 473 frames, 0 different, no register difference; not traced further.
- Group 1 / 2 frame-push SP timing and RTE / RTR are equal at every bus-error point; reset / run-ahead may still show
  them.

### Regression (final RTL)

| Run | Result |
|---|---|
| 68000 suite (`run_all.sh`) | 794,139 / 794,139 pure-suite on every column; corrected 202,181 / 202,182 (state and timed; the CHK #5948 probe artefact); timed 797,878 |
| idle clocks 0-3 | 794,139 pass, bus order 797,878, corrected 202,181 |
| smoke / retry | 3 / 3, 8 / 8 |
| 68008 / 68008FN / 68EC000 8-bit / 16-bit (`run_family.sh`) | 794,137 (2 aliased) / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each |
| MAME m68008 lockstep (seed 7, 40 x 300,000 clocks) | 68008 2,578,071 byte cycles, 68008FN / 68EC000 2,560,932 each: **0** mismatching runs (resets at address errors 10,943 / 11,717 / 11,717, TRAPV quirk 1 each) |
| Verilator `--lint-only -Wall` (4.204) | `m68ksv_all.sv` for all four CPU values and `m68ksv_qtop` with each revision macro: 0 errors |
| fx68k files in `syn/quartus/fx68k` | byte-identical to the download (cmp) |

### yosys (`verify/tools/yosys.sh`, `YCPU`; an estimate, not Quartus)

| m68ksv | LUTs before → after | carry | FF | M10K | DSP | depth |
|---|---|---|---|---|---|---|
| 68000 | 2,998 → 3,230 | 487 → 447 | 1,217 → 1,220 | 29 → 30 | 1 | 10.0 → 11.0 |
| 68008 | 3,018 → 3,197 | 487 → 447 | 1,225 → 1,228 | 29 → 30 | 1 | 10.0 → 11.0 |
| 68008FN | 3,024 → 3,226 | 488 → 447 | 1,226 → 1,229 | 29 → 30 | 1 | 10.0 → 11.0 |
| 68EC000 | 3,047 → 3,228 | 487 → 448 | 1,227 → 1,230 | 29 → 30 | 1 | 10.0 → 11.0 |

After goal 2 alone (pc68, `pk` / `pb` removed) the 68000 was 3,095 LUTs, depth 9.0; the side-effect alignment
(`fh` / `lh` / merge mode / EXG / MUL / reset completion) added the rest. The microcode grew from 1,091 x 92 to
1,131 x 93 bits (+1 M10K). The depth-11 path runs from the next micro-instruction's address field through the
register-file copy A read address (yosys merges the MLAB address register, so its report joins two Quartus paths).
**Guardrail risk**: the last measured 68EC000 was 1,861 ALMs / 109.9 MHz; +181 LUTs (+6 %) should stay under 2,047
ALMs, and one more LUT level is within the 109.9 → 96 MHz margin by the previous ratio, but this is not measured -
the Quartus compiles below decide it.

### Files changed / new (third session)

- RTL: `rtl/m68ksv_eu.sv` (pc68, `pu` / `fh` / `lh` / `lk` 2-bit / `pl` 1-bit, hold registers, high-word merge, EAVM
  operand, EXG Dy via the AU, `pk` / `pb` / `bc` logic removed), `rtl/m68ksv_alu.sv` (low-word X V C), `rtl/m68ksv_biu.sv`
  (TAS BERR AS release), `rtl/m68ksv.sv` (reset completion of the current micro-word), `rtl/gen/m68ksv_ucode.py`
  (fields, PU table, derived `pl`, routine changes listed above), regenerated `rtl/m68ksv_upkg.sv`, `m68ksv_urom.sv`,
  `m68ksv_drom.sv`, `rtl/m68ksv_all.sv`, `verify/tb/m68ksv_ualabels.h`.
- Verification: `verify/tb/lockstep.cpp` (`PCTRACE`, `PC68CHK`, `ABORTCHK`, `WRTRACE`, `AECHK`, `CCRTRACE`),
  `verify/tools/pcderive.py` (new), `verify/tools/pbfit.py` (removed).
- Docs: `DESIGN.md` (3, 5), this report.

### Quartus (the user compiles)

```bash
cd syn/quartus
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008 DIP48
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000 (tightest)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_fx68k     # fx68k reference (unchanged)
quartus_sta -t timing_paths.tcl <revision>                     # worst paths -> output_files/<revision>.paths.txt
```

Pre-compile check on the regenerated `rtl/m68ksv_all.sv` (`verify/tools/mkall.sh`): the same three hits as before,
`for (int i ...)` inside `always_comb` (accepted by Quartus 17); no size casts, assignment patterns, `inside` or
expression bit-selects.

**Measured (user's compiles 2026-11-15 17:31–17:35, third-session RTL, Quartus 17.0.2, 5CSEBA6U23I7, 96 MHz):**

| Revision | ALMs | Registers | RAM blocks | DSP | Fmax slow 100 C | Fmax slow −40 C | Worst setup slack | `m68ksv_biu` ALMs |
|---|---|---|---|---|---|---|---|---|
| `m68ksv_qtop` (68000) | 1,824 | 1,318 | 33 | 1 | 112.44 MHz | 108.86 MHz | +1.231 ns | 50.8 |
| `m68ksv_qtop_68008` | 1,828 | 1,328 | 33 | 1 | 116.97 MHz | 115.09 MHz | +1.728 ns | 57.8 |
| `m68ksv_qtop_68008fn` | 1,826 | 1,346 | 33 | 1 | 121.85 MHz | 120.22 MHz | +2.099 ns | 62.6 |
| `m68ksv_qtop_68ec000` | 1,849 | 1,353 | 33 | 1 | 110.28 MHz | 107.20 MHz | +1.089 ns | 65.9 |
| `m68ksv_qtop_fx68k` (12:43 compile) | 2,047 | 1,546 | 14 | 0 | 100.0 MHz | 99.13 MHz | — | — |

All revisions meet ≤ 2,047 ALMs and 96 MHz. ALMs flat vs the second session (yosys predicted +8 %; Quartus did not
see it). `timing_paths.tcl` exit 0 on all four. The worst paths now cluster on the flag logic: `c_sz` / `xa_q` /
`ad_sub_q` → `ccr_q` / `hold_xvc` (7–9 levels; the two-step long-flag write `fh`) — the first place to look if
a later checkpoint loses timing.

### How to rerun (additions)

```bash
PCTRACE=1 ./lockstep -seed N -runs R <suite .bin ...> | grep '^P ' > p.txt
python3 -I verify/tools/pcderive.py verify/tb/m68ksv_ualabels.h p.txt          # where the 68000 loads its PC
PC68CHK=1 ./lockstep ...                                                         # pc68 vs fx68k PC at bus-error points
ABORTCHK=1 ./lockstep ... | grep '^AB'                                           # register / CCR at bus-error points
WRTRACE=1 ./lockstep ... | grep '^X'                                             # write timelines
./lockstep -seed 101 -runs 64 -ticks 400000 -sweep berr <suite .bin ...>        # sweeps: one process
```

## Checkpoint 3 (68010) — fourth session, 2026-11-15

### Summary

`CPU = 68010` is implemented: MOVEC (VBR / SFC / DFC / USP, illegal code = illegal instruction), MOVES with SFC / DFC on
the bus, RTD, MOVE from CCR, privileged MOVE from SR, VBR-relative vectors, format-0 four-word frames, the format-8
29-word bus / address-error frame, RTE with format / version checks and the re-run of the faulted cycle (or software
completion via SSW.RR), loop mode, the BKPT acknowledge cycle, CLR / Scc / MOVE from SR / CCR without the read, and the
68010 timing changes listed below. 16-bit bus, 24-bit address, the 68000's pins. The 68000 / 68008 / 68008FN / 68EC000
builds are unchanged (68000 ROM modules byte-identical, suite / family / MAME / fx68k results as in the third session).
No interface change: `m68k_i_t` / `m68k_o_t` untouched (`dbg_vbr` / `dbg_sfc` / `dbg_dfc` added to the debug outputs
only, left open in `m68ksv_fleet.sv` and `m68ksv_qtop.sv`). Design: DESIGN.md 7.1.

Sources: MC68010 / MC68012 data sheet (May 1985, bitsavers) sections 5 and 7 (tables 7-1..7-22), M68000 User's
Manual rev 8 (appendix A, section 9), M68000 Programmer's Reference Manual (1992); MAME's Musashi m68010 (oracle,
compiled unmodified in the harness).

### Oracles and harnesses (new)

- `verify/musashi/` (build.sh, shim/emu.h, musashi_model.*): MAME's `m68kcpu.cpp` / `m68kops.cpp` / `m68010.cpp`
  compiled unmodified with a small framework shim; one instruction per step, `set_emmu_enable(true)` for bus errors.
- `verify/tb/mus010.cpp` (`mus010_build.sh`): instruction-boundary lockstep on D0-D7 / A0-A7 / USP / SSP / PC / SR / VBR /
  SFC / DFC and the bytes written (address, data, FC). Stream: suite opcodes + 68010 snippets (MOVE from CCR / SR, MOVEC
  incl. VBR switch and illegal codes, MOVES, RTD, BKPT, user mode, RTE format 0 / 8 frames, trace, loop-mode loops);
  `-irq` random interrupts (autovector / vector), `-w` wait states, `-cyc` cycle cross-check against Musashi.
- `verify/tb/rerun010.cpp`: two m68ksv instances, BERR injected into one (read / write / prefetch), handler = RTE
  (optionally software completion with RR set); every instruction boundary compared with the clean instance.
- `verify/tb/loop010.cpp`: directed loop-mode test (timing per class against the data-sheet tables, opcode fetches in
  loop mode, interrupt / bus error / trace / counter-writing body).

Classified (counted, resynchronised) Musashi differences — Musashi is not changed and its behaviour is accepted only
where it is the 68010's: address errors (m68ksv: format-8 frame from the 68010 microcode; Musashi's abort point
differs: odd jump targets fault one step later in Musashi, odd PC-relative operands are read unaligned by Musashi,
DBcc with an odd target and expiring count faults in m68ksv only); Musashi's DIVS $80000000/-1 quirk; RTE of a
format-8 frame not built by the same CPU (both reset); self-modifying code in the prefetch window and loops that write
their own words in loop mode (no refetch on the 68010; both reset); trace after a group-2 exception (data sheet 5.3.8:
m68ksv traces, Musashi cancels); interrupt vector entry 0 (Musashi uses vector 15); MOVES to CPU-space addresses
(harness: memory, as Musashi). Manual vs Musashi decisions (manual followed): MOVEC write 12 clocks, Scc / MOVE from SR
/ CLR memory timing, TAS -(An), shift-count clocks (Musashi omits them), MOVE.L <mem>,-(An) 20.

### Results (final RTL)

**Musashi lockstep** (`mus010`, 8 runs per row, mix = share of 68010 snippets in the stream):

| Stimulus | Boundaries compared | CPU clocks | Mismatching runs | Group-0 exceptions (frames checked: SSP / SR / format; differing) | Interrupts / trace | Loop-mode DBcc |
|---|---|---|---|---|---|---|
| seed 41, mix 25 | 80,000 | 1,271,130 | **0** | 838 (3) | 0 / 41 | 10,134 |
| seed 42, mix 25 | 80,000 | 947,491 | **0** | 757 (2) | 1 / 38 | 8,615 |
| seed 43, mix 25, `-irq -w 2` | 80,000 | 2,668,877 | **0** | 10,253 (5) | 214 / 3,147 | 3,938 |
| seed 44, mix 25, `-irq -w 2` | 80,000 | 1,383,845 | **0** | 1,770 (3) | 146 / 88 | 3,558 |
| seed 21, mix 10, `-cyc` | 160,000 | 2,013,026 | **0** | 791 (0) | 0 / 25 | 31 |
| **total** | **480,000** | 8,284,369 | **0** | 14,409 (13) | 361 / 3,339 | 26,276 |

Classified resyncs in those rows (summed): group-0 abort-point classes (odd jump target 649, odd PC-relative operand 118,
DBcc with odd target 9, stacked CCR at the abort point 371), foreign format-8 RTE 49, self-modifying code in the prefetch window
781, loop writing its own words 50, trace after a group-2 exception 2, DIVS quirk 0, vector-0 interrupt 0. The 13
group-0 frames whose SSP / SR / format word differ from Musashi's after classification are **not analysed** (all in
runs whose registers re-synchronised; no later mismatch). Cycle cross-check: 154,783 of 159,119 instruction timings
equal to Musashi's; the differing groups are the manual-vs-Musashi and approximate cases of the timing table.

**Bus error + RTE continuation self-check** (`rerun010`, BERR injected into one of two m68ksv instances):

| Run | Dispatches compared | BERR injected (read / write / prefetch) | Completed in software (RR) | Mismatching runs |
|---|---|---|---|---|
| seeds 6, 7, 9, 10, 11 (10 runs x 5,000, 1/30, `-sw`) | 127,056 | 5,082 (1,090 / 662 / 3,330) | 1,153 | **0** |
| seeds 1, 2 (8 runs x 4,000, 1/40) | 32,017 | 851 (166 / 120 / 565) | 0 | **0** |

Loop mode continued by RTE (first DBcc through the normal micro-routine): 1,365. Runs ending in a double-fault halt
(random programs): 38, of which 4 halted first in the injected instance (not root-caused).

**Loop mode** (`loop010`): loop-continued time equal to the data-sheet table for all 35 classes tested, 0 opcode
fetches of the loop words in loop mode; interrupt taken after a DBcc (stacked PC = looped instruction), loop entered
again after RTE (5 fetches as on entry); bus error + RTE: 0 refetches, result correct; T set: no loop mode; counter
written by the looped instruction: correct count, 0 fetches. 0 failures.

### 68010 feature checklist (verification status)

| Item (data sheet / UM) | Status | Verified by |
|---|---|---|
| MOVEC Rc<->Rn: SFC, DFC, USP, VBR; other codes -> illegal instruction (DS 5.x, table 7-21) | done | Musashi lockstep (snippets incl. random illegal codes and VBR switches between 3 tables) |
| MOVES with SFC / DFC on FC2-0, privileged; .b to An sign-extended | done | Musashi lockstep (written bytes compared with FC) |
| RTD #d16 | done | Musashi lockstep |
| MOVE from CCR; MOVE from SR privileged | done | Musashi lockstep (user-mode snippets) |
| VBR-relative vectors (all exceptions, interrupts, reset uses 0) | done | Musashi lockstep (VBR 0 / $800 / $C00) |
| Format-0 four-word frames (group 1 / 2, interrupts, trace) | done | Musashi lockstep (memory compare of frames) |
| Format-8 29-word frame; SSW / FA / DOB / IIB fields | done | Musashi: SSP, SR word, format / vector word of every group-0 frame (counts below); internal words: rerun010 (RTE uses them) |
| RTE: format word, format error (SP unchanged), version check, re-run of the faulted cycle, RR (software completion) | done | rerun010 (BERR on reads / writes / prefetches, with and without RR); Musashi: format 0 / 8 frames from snippets |
| Loop mode: entry (DBcc -4, table 7-3), no opcode fetches, exits (cc / count / interrupt / trace / reset / bus error), RTE without refetch | done | loop010 (0 fetches, interrupt after DBcc only, BERR + RTE without refetch, T set = no loop mode); Musashi lockstep architectural state (loop-mode DBcc counts below) |
| BKPT: breakpoint acknowledge cycle (CPU space, address 0), then illegal instruction | done | Musashi lockstep (BKPT cycle count compared) |
| CLR / Scc / MOVE from SR / CCR do not read the destination | done | suite in 010 mode (bus-order column), loop010 |
| 68010 flag / result differences found by lockstep: DIVS/DIVU overflow N/Z, divide by zero flags, CHK N, LINK A7 | done | Musashi lockstep |
| Trace after a forced exception (DS 5.3.8) | done (manual; Musashi differs, classified) | mus010 count |
| 68010 timing (table below) | done where listed; approximations listed | loop010, `mus010 -cyc`, suite in 010 mode |
| 16-bit bus, 24-bit address, same pins | done | unchanged BIU / top |

### Cycle timing (manual = MC68010 data sheet section 7; m68ksv measured; Musashi m68010 table via `mus010 -cyc`)

| Class | Manual | m68ksv | Musashi | Status |
|---|---|---|---|---|
| Bcc.b / .w not taken; taken | 6 / 10; 10 | 6 / 10; 10 | 6 / 10; 10 | matched |
| DBcc cc true / cc false / expired | 10 / 10 / 16 | 10 / 10 / 16 | 10 / 10 / 16 | matched |
| Scc Dn (true / false) | 4 / 4 | 4 / 4 | 4 / 4 | matched |
| Scc / MOVE from SR / CCR memory | 8 + non-fetching ea | d16 / d8 / abs exact; (An) / (An)+ / -(An) +2 | 68000 values | approximate for (An) / (An)+ / -(An) |
| CLR memory B/W / L (table 7-13) | 8..16 / 12..20 | = manual | 68000 values (read) | matched |
| ADD/SUB/AND/OR/EOR/ADDA/SUBA .l from Dn / An / #imm; ADDX/SUBX .l Dn | 6 (+ ea) | 6 (+ ea) | 6 | matched |
| xxxI.l #,Dn; CMPI.l #,Dn | 14; 12 | 14; 12 | 14; n/m | matched |
| ADDQ/SUBQ .w #,An / .l #,An / .l Dn | 4 / 8 / 8 | 4 / 8 / 8 | 4 / 8 / 8 | matched |
| MOVE.l Dn/An,-(An); MOVE.l mem,-(An) | 14; 20.. | 14; 20.. | 14; 22.. | matched (Musashi +2 on memory sources) |
| ANDI / ORI / EORI to CCR / SR; MOVE to CCR / SR | 16; 12 | 16; 12 | 16; n/m | matched |
| MOVE USP; MOVEC Rc->Rn / Rn->Rc | 6; 10 / 12 | 6; 10 / 12 | 6; 10 / 10 | matched (Musashi 10 for Rn->Rc) |
| MOVES (non-fetching ea added) | 16 / 20 (+ ea) | = manual (abs.W 20) | 26 (abs.W) | matched |
| RESET | 130 | 130 | 130 | matched |
| BCLR memory (dynamic / static) | 10 / 14 + ea | = manual | = | matched |
| BCHG / BSET / BCLR Dn (max values) | 8 / 8 / 10 max | 68000 data-dependent (6/8, 8/10) | 8 / 8 / 10 | approximate (manual gives maxima only) |
| CHK no trap / trap | 8 + ea / 44 + ea max | 8 + ea / 44 + ea | 10 / 52 | matched |
| MULU / MULS / DIVU / DIVS | 40 / 42 / 108 / 122 max | the 68000's data-dependent counts | fixed table | approximate (68010 algorithm timing not documented) |
| Shifts / rotates | 6 + 2n / 8 + 2n | = manual | omits 2n | matched |
| TRAP / line A / F | 38 | 38 | 42 / 4 (Musashi's step count) | matched (illegal / privilege / trace: same EXC12_010 path, not measured separately) |
| BKPT (acknowledge + illegal) | 42 | 42 | 38 | matched |
| Interrupt | 46 | not measured separately this session | - | not verified |
| Bus / address error | 126 | ~130 (suite: +80 clocks over the 68000's 50) | - | approximate (+4) |
| RTE short / long; format error | 24 / 110-112; 50 | 30 / not measured; not measured | - | short +6 (approximate); long / format error not verified |
| RTD / RTR / RTS / LINK / UNLK | 16 / 20 / 16 / 16 / 12 | = manual (68000 values) | no difference flagged | matched |
| Loop mode, loop continued (35 classes, tables 7-6/7-8/7-10/7-14/7-16/7-20) | table | = table, all 35 | no loop mode | matched |
| Loop mode, terminated (cc true / count expired) | table | +4 / +2..+8 | - | approximate (exit runs the normal DBcc exit after a 2-clock loop word) |
| Loop mode, first DBcc after RTE into a loop (no refetch) | not documented | normal DBcc time (10) | - | approximate |
| Bus-cycle structure | as 68000 except where noted | as 68000 | - | unchanged |

(n/m = not measured. Musashi column from `mus010 -seed 21 -runs 8 -instr 20000 -mix 10 -cyc` on the final RTL;
"matched" = equal to the manual where the manual gives a fixed value.)

### SingleStepTests 68000 suite on the 68010 build (`M68KSV_CPU=68010 verify/build.sh`)

With the exclusions and corrections of `run_all.sh` (pure suite 794,139 tests): **781,979 pass**; the 12,160 failing
pure tests are TRAP (8,065) and TRAPV (4,095): four-word format-0 frame (documented). Corrected (frame) tests: 9,793 /
202,182 pass; all others differ by the 68010 frame (below). Without exclusions / corrections, every one of the 202,269
register / RAM failures is classified (`cls010.py` on `harte -v`, script in the scratchpad):

| Count | Class | Documented 68010 difference? |
|---|---|---|
| 174,033 | group-0 exception: format-8 frame (29 words) instead of the 7-word frame | yes (DS 5.4) |
| 16,433 | group-1 / 2 exception: format-0 frame (4 words) instead of 3 | yes (DS 5.3) |
| 8,065 | RTE reads the format word (the suite's 68000 frames have no format word) | yes |
| 3,736 | ASR (b / w / l) with count >= operand size: X / C = the sign as in the PRM and Musashi; the suite (68000 hardware) has another value | follows MAME + PRM (68010 hardware unverified) |
| 2 | ASL.b #1582 / #1760 | suite tests excluded at the 68000 too (`byte_shift_changes_upper_bits`) |
| 0 | unexplained | — |

Timing / bus-order differences on passing pure tests (68000 build minus 68010 build, same exclusions / corrections):
all in the classes of the timing table — ADDA/SUBA.l, ADD/SUB/AND/OR/EOR.l (long register / immediate sources),
ADD.w / SUB.w (ADDQ / SUBQ .w #,An), ADDX/SUBX.l, CMP.l (CMPI.l), MOVE.l (Dn,-(An)), Bcc, DBcc, BCLR, Scc, CLR,
MOVE from SR, MOVE USP, RESET, xxxI to CCR / SR (cycle columns); bus order differs only for CLR / Scc / MOVE from SR
(no read); one DIVU test differs in cycles and bus order (not analysed).

### 68000-family regression (final RTL, this session)

| Run | Result |
|---|---|
| 68000 suite (`run_all.sh`) | 794,139 / 794,139 pure on every column; corrected 202,181 / 202,182; timed 797,878 |
| idle clocks 0-3 | 794,139 pass, bus order 797,878, corrected 202,181 |
| smoke / retry | 3 / 3, 8 / 8 |
| `run_family.sh` 68008 / 68008FN / 68EC000 8-bit / 16-bit | 794,137 / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each |
| MAME m68008 lockstep (seed 7, 40 x 300,000 clocks) | 68008 2,578,071 byte cycles, 68008FN / 68EC000 2,560,932 each: **0** mismatching runs (address-error resets 10,943 / 11,717 / 11,717, TRAPV quirk 1 each) |
| 68000 ROM modules (`m68ksv_urom.sv` / `m68ksv_drom.sv`, 68000 part) | byte-identical to the checkpoint-3 start snapshot |

fx68k lockstep (Verilator 5.052, 64 runs x 400,000 phases per row, one process per row), identical to the third
session's table in every row:

| Stimulus | seed 101: clocks / mismatching runs | seed 202 |
|---|---|---|
| none | 12,800,000 / 0 | 12,800,000 / 0 |
| `-w 3` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-irq` | 12,676,688 / 1 | 12,800,000 / 0 |
| `-vpa` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-br` | 12,800,000 / 0 | 12,647,440 / 1 |
| `-halt` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-rst` | 12,436,604 / 2 | 12,438,375 / 2 |
| `-w 2 -irq -vpa -br -halt -rst` | 12,550,673 / 4 | 12,094,507 / 4 |
| `-berr 50` | 12,800,000 / 0 | 12,746,022 / 1 |
| 68EC000 (MODE = 1), none | 12,800,000 / 0 | not run |
| 68EC000, `-w 2 -irq -vpa -br -halt` (32 runs) | 6,400,000 / 0 | not run |

Directed sweeps (`-sweep`) were not re-run this session.

### yosys (`verify/tools/yosys.sh`, `YCPU`; yosys 0.66 `synth_intel_alm -family cyclonev`; an estimate, not Quartus)

| m68ksv | LUTs (ALUT2-6) before -> after | carry | FF | M10K | DSP | depth (LUT levels) |
|---|---|---|---|---|---|---|
| 68000 | 3,230 -> 3,176 | 447 -> 448 | 1,220 -> 1,220 | 30 -> 30 | 1 | 11.0 -> 11.0 |
| 68008 | 3,197 -> 3,207 | 447 -> 448 | 1,228 -> 1,228 | 30 -> 30 | 1 | 11.0 -> 11.0 |
| 68008FN | 3,226 -> 3,210 | 447 -> 447 | 1,229 -> 1,229 | 30 -> 30 | 1 | 11.0 -> 11.0 |
| 68EC000 | 3,228 -> 3,228 | 448 -> 448 | 1,230 -> 1,230 | 30 -> 30 | 1 | 11.0 -> 11.0 |
| **68010** | — -> **4,567** | 579 | 1,530 | 34 | 1 | 11.0 (endpoint `b_ghost`: loop-window compare) |

"before" = the checkpoint-3 start snapshot (scratchpad `m68ksv_cp3_start_snapshot`) through the same script; FF and
M10K identical, LUTs within yosys noise (-54 .. +10): the 68010-only logic folds away in the 68000 family.
**Guardrail risk (68010):** with the third session's Quartus / yosys ratio (68000: 1,824 ALMs for 3,230 LUTs) the 68010
would land near 2,580 ALMs, above the ~2,200 target; Fmax is not predictable from yosys (same depth 11 as the
68000, whose Quartus Fmax was 112 MHz). Where the extra logic is: format-8 frame state (SSW, DOB, DIB, SR / AUR copies,
per-word loads from the read data, the push mux), MOVEC / VBR / SFC / DFC, loop mode (window compare, saved decode).
Not reduced in this session — the user's compile decides; first candidates if it is too big: the direct frame loads
(could go through DT like the 32-bit words) and the 24-bit loop-window compare (could compare a 3-bit tag).

### Decisions taken alone (the user could not be asked)

- Frame PC = `fpc - 4` (the 68000 lineage's prefetch PC; DS: "may be advanced by up to five words"); internal words
  of the format-8 frame are m68ksv's own layout, version 0 (DS: undocumented, only the version nibble is checked).
- Musashi is followed for undocumented flag results the 68010 manuals leave open (DIV overflow / zero divide flags,
  CHK N, LINK A7 pushing the decremented A7, MOVES.b to An sign-extended, ASR large counts); the manual is followed
  where the manuals give a value (timing table above; trace after a group-2 exception).
- RTE format 8 checks the version word and the frame's last word before loading anything (a bus error there is an
  ordinary bus error of the RTE, afterwards a double fault).
- A faulted read changes nothing on the 68010 (the 68000 path keeps its fx68k-aligned behaviour).
- Loop mode after RTE into a loop: loop words not fetched again (DS 7.1.3); the first DBcc runs the normal DBcc
  micro-routine (its fetches internal) to re-establish the counter test. After a fault on the looped instruction's
  last word with another loop entered in the handler, the loop is fetched again (state not recoverable from the frame).
- Loop-mode exit times and the RTE short frame (30 vs 24) are left approximate; MUL / DIV keep the 68000 counts.

### Open (not done / not verified)

- Interrupt / bus error / address error / format error / RTE long exception times not measured against table 7-22
  (bus / address error is ~4 clocks long, RTE short +6).
- MOVE from SR / CCR and Scc to (An) / (An)+ / -(An): +2 clocks.
- rerun010: runs that end in a double-fault halt where the injected instance halts first (counted, not root-caused).
- No 68010 lockstep at pin / phase level (fx68k has no 68010); Musashi is instruction-level.
- Quartus not run (rule); 68010 ALMs / Fmax unknown.

### Files changed / new (fourth session)

- RTL: `rtl/m68ksv_eu.sv` (68010: control registers, MOVES, frames, RTE / re-run, loop mode, timing hooks), `rtl/m68ksv_alu.sv`
  (`IS010`), `rtl/m68ksv_biu.sv` (`ghost` input: no bus cycle), `rtl/m68ksv.sv` (CPU 68010, `dbg_vbr` / `dbg_sfc` / `dbg_dfc`,
  ghost wiring), `rtl/m68ksv_fleet.sv` (new debug ports left open), `rtl/gen/m68ksv_ucode.py` (two-CPU driver, 68010
  fields / codes / decode), `rtl/gen/m68ksv_ucode010.py` (new), regenerated `rtl/m68ksv_upkg.sv`, `m68ksv_urom.sv`,
  `m68ksv_drom.sv` (68000 modules unchanged + `_010` modules), `rtl/m68ksv_all.sv`, `verify/tb/m68ksv_ualabels.h`.
- Verification: `verify/musashi/` (new: build.sh, shim/emu.h, musashi_model.h/.cpp), `verify/tb/mus010.cpp`,
  `verify/tb/rerun010.cpp`, `verify/tb/loop010.cpp`, `verify/mus010_build.sh` (all new).
- Quartus: `syn/quartus/m68ksv_qtop_68010.qsf` (new: `m68ksv_qtop.qsf` + `VERILOG_MACRO "M68KSV_CPU=68010"`),
  `m68ksv_qtop.qpf` (revision added), `m68ksv_qtop.sv` (comment, ports), `README.md`. `files.qip` unchanged (no new
  source file); fx68k files byte-identical (cmp).
- Docs: `DESIGN.md` (7, 7.1, 8, 9), this report.

### Quartus (the user compiles; nothing here was run in Quartus)

```bash
cd syn/quartus
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010 (new)
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008 DIP48
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sta -t timing_paths.tcl m68ksv_qtop_68010              # and the same for each revision above
```

Pre-compile check on the regenerated `rtl/m68ksv_all.sv` (`verify/tools/mkall.sh`): the same three `for (int i ...)`
inside `always_comb` as before; no size casts, assignment patterns, `inside` or expression bit-selects. Verilator 4.204
`--lint-only -Wall`: 0 errors for CPU 68000 / 68008 / 68009 / 68001 / 68010 and `m68ksv_qtop` with `M68KSV_CPU` 68000 /
68010.

#### Measured Quartus results (user's compiles 2026-11-15 20:58–21:14; `timing_paths.tcl` run on each)

| Revision | ALMs | Registers | RAM blocks | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold slack (min) |
|---|---|---|---|---|---|---|
| 68010 (new) | **2,493** | 1,701 | 36 | 102.56 / 102.45 MHz | +0.667 / +0.656 ns | +0.319 ns |
| 68000 | 1,833 (+9) | 1,350 (+32) | 33 | 115.63 / 113.62 MHz | +1.769 / +1.616 ns | +0.317 ns |
| 68008 | 1,837 (+9) | 1,331 (+3) | 33 | 115.00 / 110.45 MHz | +1.721 / +1.363 ns | +0.303 ns |
| 68008FN | 1,849 (+23) | 1,345 (−1) | 33 | 119.85 / 117.52 MHz | +2.073 / +1.908 ns | +0.314 ns |
| 68EC000 | 1,856 (+7) | 1,360 (+7) | 33 | 114.21 / 110.06 MHz | +1.661 / +1.331 ns | +0.313 ns |

(Changes in brackets are against the third-session compile.) 1 DSP block on every revision.

- **Fmax: every revision meets 96 MHz.**
- **68010 area misses its target.** 2,493 ALMs against the ~2,200 target, and above fx68k's 2,047. The yosys estimate
  (≈2,580) was close.
- **The 68010's worst paths are the new loop-mode logic.** `uw[25]` / `uw[24]` (micro-word) → `lm_db` / `lm` /
  `ghost` / `ghost_d[15:0]`, 7–9 levels, slack +0.67 to +1.5 ns. Next comes the familiar flag path `c_sz` → `ccr_q`.
- **68000 family:** within 7–23 ALMs of the third session, although yosys said LUTs stayed level or dropped. The
  68000 has 32 more registers than before, while yosys's FF count did not change. The worst 68000 path moved to
  `xb_q` → `dv_ov`, 6 levels; the other revisions are still on the flag paths.

### How to rerun (checkpoint 3)

```bash
verify/mus010_build.sh <dir>                    # Musashi library + mus010 + rerun010 + loop010 (Verilator 4.204, CPU=68010)
<dir>/mus010 -seed N -runs R -instr I -mix 25 [-irq] [-w W] [-cyc] [-v 1..4] <suite .bin ...>
<dir>/rerun010 -seed N -runs R -instr I -p 30 [-sw] <suite .bin ...>
<dir>/loop010
M68KSV_CPU=68010 verify/build.sh <dir>; <dir>/harte [-x verify/suite_exclusions.txt -c <corrections>] <suite .bin ...>
YCPU=68010 verify/tools/yosys.sh <dir>
```

### Area / timing pass (fifth session, 2026-11-15)

**Summary.** RTL restructuring only, no behaviour or cycle-timing change on any CPU (micro-ROMs, decode ROMs, labels
byte-identical to the fourth session). 68010 yosys LUTs 4,567 → 3,923 (−14 %, ≈ 2,142 ALMs by the 0.546 ratio; target
≤ 2,200 / ≤ 4,030 LUTs met). The loop-mode paths that limited the 68010's timing are gone from the deep end of the list
(yosys depth 11.0 → 8.25–9.25, now below the flag path `c_sz` → `ccr_q`, 10.15). The 68000 family shrank too
(3,176 → 3,045 LUTs on the 68000). Every gate is identical to the fourth session; in addition an old-vs-new
clock-exact A/B check (below) found no difference on any CPU. Quartus was not run (rule): ALM / Fmax figures here are
estimates; the user's compiles decide.

**What was cut / changed, and why** (all in `rtl/m68ksv_eu.sv` unless noted):

| Change | Why | Effect (yosys, 68010) |
|---|---|---|
| Loop-mode window decided at **e2** from the registered bus address: `lwd = ba_q[23:0] - lbase` (in the window when 0 / 2 / 4); `ghost`, `ghost_d`, `lm_db` set, loop mode off on a real fetch, all at that e2; BIU gets `ghost_s2` (combinational, S2 strobes only) and `ghost` (registered) — `m68ksv_biu.sv`, `m68ksv.sv` | the old test ran three 24-bit compares (with two `lbase + 2 / + 4` adders) on the e1 bus-address mux, decoded from `uw[25:24]` (field ba): the 68010's worst paths | −~140 LUTs (compare trees, adders, `ghost_d` mux); paths start at registers now |
| `lm` / `lm_db` updates of that e2 and the address-error capture of the loop state (`lm_f`, `lm_keep`) written last in the register block | the compare result enters the last mux before the register (phases e0..e3 exclude each other, so the order is free) | −1..2 levels |
| `in_exc_nx` (dispatch goes to an exception entry) formed per dispatch branch; the decoded entry's test registered with it (`q_exc`, `lq_exc`) | removes an 11-bit compare after the 6-way dispatch mux (interrupt → `lm`, I/N bit) | +2 FF (`lq_exc` 68010 only) |
| `loopable(IRN)` registered together with IRN (`lp_irn`) | loop-entry check (`X1_LMDZ`) starts at a register | +3 FF (68010 only) |
| ALU A / B operands: source resolved first (4-bit code `xq` / `xbq`: field xa / xb, the class's source `c_ca`, EA mode, MOVEC code), then one flat 32-bit mux | the nested muxes (`eav_x`, `ca_v`, control registers) were mapped per bit with many duplicate inputs | −~230 LUTs (68000: −~100) |
| IRC, IRN, IR, FPC, AT, FA, DT (per byte), IM (per byte), resume address (`ua_res`) written in one place each: enable = OR of causes, data mux in the causes' old priority; data selects use only e2 / `b_dv` (= e3) and word fields, `e0` (late: waits for the micro-ROM's bus request) only in the enables | the scattered assignments (frame loads, loop restore, SWDONE, ALU, AU) gave each register a long priority chain | −~330 LUTs (68000: −~60) |
| 68010 software-completed RTE (SWDONE): DIB → DT through the read-data path (`ld_d` / `ld_bd` / `ld_byte`) | one DT input path instead of two | in the DT figure above |
| Bus write data: 68010 frame words (field fx) decoded at e1 into `dws` / `dwx` / `dwh` (slot A / B words reuse the IM / RES sources); byte duplication applied after the data register (`b_dout = {dup ? r[7:0] : r[15:8], r[7:0]}`) | the frame word mux sat behind the e1-registered select, decoded from `uw` at e2; the duplication doubled the upper byte's inputs | −~85 LUTs, +2 FF |
| 68010 frame AUR copy (`aur_f`) taken from AUR one clock after the faulting word's e3 (`f8cap2`) | AUR then holds exactly the old capture value; one source less | −~20 LUTs, +1 FF; generator check added (below) |
| `rtl/gen/m68ksv_ucode.py` `check()`: a word with fx MAUR (RTE: AUR restored) is never a bus word nor the successor of one | guards the AUR capture above (negative-tested: a MAUR word after a bus word stops the generator) | ROMs unchanged |

Not changed (considered, rejected): merging DOB / DIB (−16 FF) — exact only for frames the CPU wrote itself (a frame
whose internal resume address was altered by software could push a different DIB word); sharing the `fa + 2` adder
with `ba_q + 2` (LUT-negative); FSM-encoding attributes on `dwx_q` / `dws_q` (Quartus re-encodes them one-hot); any
microcode change (frame internal words, AUR / DT leftovers are visible in format-8 frames).

**yosys** (`verify/tools/yosys.sh`, `YCPU`; yosys 0.66 `synth_intel_alm -family cyclonev`; an estimate, not Quartus;
"before" = fourth-session final RTL, snapshot `m68ksv_cp3_final_snapshot`, same script this session):

| m68ksv | LUTs before → after | carry | FF | M10K | DSP | est. ALMs (yosys × the revision's 4th-session ratio) |
|---|---|---|---|---|---|---|
| **68010** | 4,567 → **3,923** | 579 → 589 | 1,530 → 1,550 | 34 | 1 | 2,493 → **≈ 2,142** (× 0.546) |
| 68000 | 3,176 → 3,045 | 448 → 447 | 1,220 → 1,222 | 30 | 1 | 1,833 → ≈ 1,757 (× 0.577) |
| 68008 | 3,207 → 3,042 | 448 → 448 | 1,228 → 1,230 | 30 | 1 | 1,837 → ≈ 1,742 (× 0.573) |
| 68008FN | 3,210 → 3,031 | 447 → 447 | 1,229 → 1,231 | 30 | 1 | 1,849 → ≈ 1,746 (× 0.576) |
| 68EC000 | 3,228 → 3,075 | 448 → 448 | 1,230 → 1,232 | 30 | 1 | 1,856 → ≈ 1,768 (× 0.575) |

yosys LUT counts move ±20–30 for identical logic when the source text changes (measured this session: the same RTL
through two file layouts gave 4,567 and 4,587), so small differences are noise. FF: 68000 family +2 (`q_exc`, the
byte-duplication flag); 68010 +20 (those two, `lq_exc`, `lp_irn` ×3, `f8cap2`, the `dwx` code 4 → 5 bits; yosys
re-encodes `dwx_q` one-hot, so its own count grows by 13). The 68010's extra registers over the 68000 (~325 in yosys)
are architectural state (VBR, SFC / DFC, the MOVEC / MOVES extension word, the format-8 frame state, loop-mode state,
the 17 extra micro-word bits) and were not reduced; none duplicates IRC / IRD / prefetch state in a way that could be
removed without changing a frame word.

**Logic depth of the former worst paths** (`verify/tools/depth.py` on the yosys netlist, LUT levels; Quartus 68010
compile in brackets):

| Endpoint | before | after | Start of the worst path after |
|---|---|---|---|
| `lm_db` (Quartus 9 levels, +0.667 ns) | 11.00 | 9.00 | `e0` enable (bus request from the micro-ROM) |
| `ghost` / `b_ghost` (8, +1.125) | 11.00 | 8.25 | `lwd` subtractor (from `ba_q`, `lbase`) |
| `lm` (8, +1.128) | 11.00 | 9.00 | `e0` enable |
| `ghost_d[15:0]` (7, +1.16..+1.50) | 11.00 | 2.10 | `lwd` |
| `lm_f`, `lm_keep` (not in the worst 30) | 8.00 | 9.25 | `lwd` (address-error capture) |
| BIU strobes via `ghost_s2` (new) | — | 10.25 | `lwd`: 24-bit carry chain (1.2 of the 10.25) + 4 LUTs |
| `ccr_f` / `hold_xvc` (flag path, Quartus 8, +1.231) | 10.35 | 10.15 | `c_sz` (unchanged logic) |

Estimate: the 68010's worst setup path becomes the flag path `c_sz` → `ccr_q` it shares with the 68000 family (+1.231
ns in the fourth-session 68010 compile), i.e. about +1.2 ns at 96 MHz; the new deepest loop path (BIU strobes from the
window subtractor) is a carry chain from registers plus four LUT levels. Not measured — Quartus decides.

**Gates (this session's runs, final RTL; all identical to the fourth session):**

| Gate | Result |
|---|---|
| 68000 suite (`run_all.sh`) | 794,139 / 794,139 pure on every column; corrected 202,181 / 202,182; timed 797,878 |
| idle clocks 0-3 | 794,139 pass, bus order 797,878, corrected 202,181 |
| smoke / retry | 3 / 3, 8 / 8 |
| `run_family.sh` 68008 / 68008FN / 68EC000 8-bit / 16-bit | 794,137 / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each |
| MAME m68008 lockstep (seed 7, 40 x 300,000 clocks) | 68008 2,578,071 byte cycles, 68008FN / 68EC000 2,560,932 each: **0** mismatching runs (address-error resets 10,943 / 11,717 / 11,717, TRAPV quirk 1 each) |
| fx68k lockstep (Verilator 5.052, 64 runs x 400,000 phases per row) | all rows identical to the fourth-session table (below) |
| Musashi `mus010` seeds 41 / 42; 43 / 44 `-irq -w 2`; 21 `-cyc` | 0 / 0 / 0 / 0 / 0 mismatching runs; boundaries, clocks, group-0 counts (838 / 757 / 10,253 / 1,770 / 791, frames differing 3 / 2 / 5 / 3 / 0), interrupts / trace and loop-mode DBcc counts equal to the fourth-session table |
| Musashi classified differences (summed) | odd jump target 649, odd PC-relative operand 118, DBcc odd target 9, stacked CCR 371, foreign format-8 RTE 49, self-modifying code 781, loop writing its own words 50, trace after group 2: 2, DIVS quirk 0, vector 0: 0 — all equal |
| `mus010 -cyc` agreement | 154,783 / 159,119 (equal) |
| `rerun010` seeds 6, 7, 9, 10, 11 (`-sw`, 1/30) / 1, 2 (1/40) | 127,056 dispatches, 5,082 BERR (1,090 / 662 / 3,330), 1,153 RR / 32,017 dispatches, 851 BERR (166 / 120 / 565): **0** mismatching runs; loop continued by RTE 1,365; double-fault halts 38 (4 in B first) — equal |
| `loop010` | 0 failures |
| 68000 suite on the 68010 build (`M68KSV_CPU=68010 verify/build.sh`, same exclusions / corrections) | 781,979 / 794,139 pure; the 12,160 failures are TRAP 8,065 + TRAPV 4,095 (four-word frame, documented); corrected 9,793 / 202,182 — equal |
| Verilator 4.204 `--lint-only -Wall` | 0 errors for CPU 68000 / 68008 / 68009 / 68001 / 68010 and `m68ksv_qtop` with 68000 / 68010; warning list = the fourth session's minus one (`XB_ZERO` now used) |
| `verify/tools/mkall.sh` pre-compile check | the same three `for (int i ...)` in `always_comb`; nothing new |
| Generated files (`m68ksv_upkg.sv`, `m68ksv_urom.sv`, `m68ksv_drom.sv`, `m68ksv_ualabels.h`) | byte-identical to the fourth session |
| Vendor files | `syn/quartus/fx68k/*`, `microrom.mem`, `nanorom.mem` byte-identical to the fx68k download (cmp); `files.qip` unchanged |
| `DIAG` markers | none (grep over `rtl/`, `verify/`, `syn/quartus/*.sv`) |

fx68k lockstep (Verilator 5.052, 64 runs x 400,000 phases per row, one process per row), this session:

| Stimulus | seed 101: clocks / mismatching runs | seed 202 |
|---|---|---|
| none | 12,800,000 / 0 | 12,800,000 / 0 |
| `-w 3` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-irq` | 12,676,688 / 1 | 12,800,000 / 0 |
| `-vpa` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-br` | 12,800,000 / 0 | 12,647,440 / 1 |
| `-halt` | 12,800,000 / 0 | 12,800,000 / 0 |
| `-rst` | 12,436,604 / 2 | 12,438,375 / 2 |
| `-w 2 -irq -vpa -br -halt -rst` | 12,550,673 / 4 | 12,094,507 / 4 |
| `-berr 50` | 12,800,000 / 0 | 12,746,022 / 1 |
| 68EC000 (MODE = 1), none | 12,800,000 / 0 | not run |
| 68EC000, `-w 2 -irq -vpa -br -halt` (32 runs) | 6,400,000 / 0 | not run |

Every row equals the fourth-session table (the non-zero rows are the known fx68k divergences listed there).

**A/B equivalence check (new tool, scratchpad only:** `scratchpad/p5/ab/` — `ab.cpp`, `build.sh`, `run_all.sh`,
`sum.sh`). The fourth-session RTL (snapshot) and the new RTL are Verilated side by side (Verilator 4.204, `--prefix
Vold` / `Vnew`) and run the same random program (rerun010's stream: suite opcodes + 68010 snippets) from identical
memories with identical random stimulus: enable gaps 0-3, wait states, BERR on random cycles (handler: RTE, or
software completion with SSW.RR and DIB / IIB filled, then RTE), VPA autovectors, interrupts, bus requests, HALT,
reset pulses. Every clock all outputs must be equal (bus pins, `D_o` while driven, `dbg_*` incl. a rotating register
file read). Final RTL, 3 seeds x 4 runs x 4,000,000 clocks per CPU: 68000 1,121,208 instruction boundaries / 3,176 BERR;
68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 16-bit 1,121,208 / 3,176 and 8-bit 625,970 / 3,493; 68010
982,951 / 3,423 BERR, 73,194 loop-mode loop words, 1,457 software-completed RTEs: **0 mismatching runs**. Control:
the same check with one deliberate change (`ghost_d` -4 → -2) fails within 10,000 clocks.

**68000 family vs the third session (goal 3).** Quartus registers 68000 1,318 → 1,350 (+32) and ALMs +7..+23 at the
fourth session, while yosys FF and LUTs did not grow (fourth-session RTL vs the checkpoint-3 start: FF identical,
LUTs within noise). The fourth-session reports explain it: the Quartus synthesis register count (`.map.summary`) is
1,198 for the 68000, and the fitter count is `map − 32 + routability duplicates` exactly (32 = `mul_p` packed into the
DSP block; "Duplicated ... Router Logic Cell Insertion and Logic Duplication, Routability optimization" in the Fitter
Netlist Optimizations table: 184 for the 68000 → 1,198 − 32 + 184 = 1,350; 68008 1,203 − 32 + 160 = 1,331, 68008FN
1,208 − 32 + 169 = 1,345, 68EC000 1,211 − 32 + 181 = 1,360). So the +32 are registers the router duplicated in that
placement, not RTL; the ALM differences are placement / packing variation of the same kind. The third-session
reports were overwritten, so its own duplicate count cannot be shown; this is the evidence available. The 68010 logic
folds away in the 68000 family (yosys FF +2 this session, both explained above; no 68010 register survives) and the
A/B check shows no behaviour change there.

**Files changed (fifth session):** `rtl/m68ksv_eu.sv`, `rtl/m68ksv_biu.sv` (`ghost_s2` input), `rtl/m68ksv.sv`
(wiring), `rtl/gen/m68ksv_ucode.py` (one `check()` rule), regenerated `rtl/m68ksv_all.sv` (ROM modules, package and
labels regenerate byte-identical), `DESIGN.md` (4, 7, 7.1), this report. No change to `syn/quartus` (files.qip,
qsf, top), `verify/` or vendor files.

**Quartus (the user compiles; nothing here was run in Quartus):**

```bash
cd syn/quartus
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008 DIP48
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sta -t timing_paths.tcl <revision>                     # worst paths -> output_files/<revision>.paths.txt
```

#### Measured Quartus results (user's compiles 2026-11-15 22:56–23:00; `timing_paths.tcl` run on each)

| Revision | ALMs (vs fourth session) | Registers | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|
| 68010 | **2,427** (−66) | 1,706 | 112.54 / 108.54 MHz | +1.531 / +1.204 ns | +0.306 ns |
| 68000 | 1,789 (−44) | 1,311 | 110.53 / 106.01 MHz | +1.370 / +0.984 ns | +0.308 ns |
| 68008 | 1,812 (−25) | 1,335 | 115.97 / 113.22 MHz | +1.794 / +1.585 ns | +0.301 ns |
| 68008FN | 1,796 (−53) | 1,356 | 106.36 / 102.13 MHz | +1.015 / +0.626 ns | +0.307 ns |
| 68EC000 | 1,818 (−38) | 1,343 | 105.98 / 107.00 MHz | +0.981 / +1.071 ns | +0.312 ns |

- **68010 timing goal met.** The loop-mode paths (`lm`, `lm_db`, `ghost`, `ghost_d`) are gone from the worst-30
  list. The worst path is now `xb_q` → `res`, 7 levels, slack +1.53 ns.
- **68010 area goal missed.** 2,427 ALMs against the ≤ 2,200 target. yosys estimated ≈2,142, so its LUT count no longer
  predicts Quartus ALMs here (yosys −644 LUTs, Quartus −66 ALMs).
- **Where the 68010's area sits.** The fitter's hierarchy table:

  | | 68010 | 68000 |
  |---|---|---|
  | `m68ksv_eu` own logic | 2,081.6 | 1,349.3 |
  | ALU | 183.3 | 284.5 |
  | BIU | 59.3 | 54.0 |
  | Each register-file copy | ~21.5 | ~21.5 |

  The 68010 adds ≈730 ALMs to the EU's own logic.
- **68000 family.** All revisions got smaller, all meet 96 MHz, and hold passes everywhere. Setup margin shrank on
  some revisions, but every behaviour gate is identical (pass above):

  | Revision | Fourth-session slack (100 °C) | Now |
  |---|---|---|
  | 68000 | +1.77 ns | +1.37 ns |
  | 68008FN | +2.07 ns | +1.02 ns |
  | 68EC000 | +1.66 ns | +0.98 ns |

  The new worst paths run from the micro-word (`uw[70]`, `uw[86]`) or `c_sz` into `ccr_q`, 8–9 levels: the flag path
  noted in the third session.

## Checkpoint 4 (68020 / 68EC020) — sixth session, 2026-11-16

### Summary

`CPU = 68020` and `CPU = 68021` (68EC020: A23–A0) build with a new 32-bit bus interface (`rtl/m68ksv_biu32.sv`:
dynamic sizing by DSACK1 / DSACK0, STERM, SIZ, misaligned operands split, the 68020 write-data multiplexer, ECS / OCS /
DBEN / RMC / IPEND, AVEC) and a 64-line instruction cache, the 68020 instruction set except CALLM / RTM, the 68020
stacks and frames (MSP / ISP / M, formats 0 / 1 / 2 / B, RTE of 0 / 1 / 2 / 9 / A / B), T0 trace, MOVEC CACR / CAAR /
MSP / ISP, and a coprocessor probe (F-line). Design: `DESIGN.md` 7.2. Result on the final RTL:

- **Musashi m68020 / m68ec020 lockstep: 0 mismatching runs** in 72 runs / 720,000 instruction boundaries (32 / 16 /
  8-bit and STERM ports, wait states, interrupts, 68020 snippets); every Musashi difference is classified and counted
  (table below).
- **Directed tests:** dynamic sizing 48 / 48 combinations (176 bus cycles checked), instruction cache 28 / 28 cases, on
  both the 68020 and 68EC020 builds.
- **68000 family and 68010 unchanged:** every regression gate identical to the fifth session; the clock-exact A/B
  check against the start snapshot: 0 mismatching runs (288 M clocks, 5.0 M instruction boundaries).
- **Not done:** CALLM / RTM (illegal instruction), the coprocessor protocol (probe + F-line only), RMC for CAS /
  CAS2, the MC68020 cycle timing (m68ksv keeps the 68000 / 68010 micro-cycle rhythm), bus-error injection in the
  68020 lockstep. Quartus: not run (the user compiles); yosys depth on the 68020 is 15 (68000: 11) — a timing risk.

### 68020 feature checklist (verification status)

V = verified by the Musashi lockstep (random suite opcodes + 68020 snippets, all port widths); D = also by a directed
test; C = classified Musashi difference (count in the lockstep table); — = not implemented.

| Feature | Status | Where |
|---|---|---|
| 32-bit BIU: dynamic sizing (32 / 16 / 8-bit DSACK, STERM), SIZ, misaligned split, write multiplexer | V, D (`dsz020`) | `m68ksv_biu32` |
| 68EC020: A23–A0 | V (`mus020 -ec`), D | `m68ksv.sv` |
| Full extension words (scale, base / index suppress, bd 0 / 16 / 32, memory indirect pre / post, od) | V | `FEA_*`, `full_detour` (`m68ksv_ucode020.py`) |
| Bcc.L / BSR.L, CHK.L, EXTB, LINK.L, TST An / # / PC-rel, CMPI PC-rel, TRAPcc | V | ucode020, decode |
| MUL.L (DSP, 32x32 → 64), DIV.L (iterative, 32 / 64-bit dividend) | V; C (DIV.L overflow C) | `mul_l*`, `dl_*` |
| Bit fields (BFTST BFEXTU BFEXTS BFFFO BFCHG BFCLR BFSET BFINS, Dn and memory) | V | `bf_*`, `BF20R` / `BF20M` |
| CHK2 / CMP2, CAS / CAS2, PACK / UNPK | V; C (PACK -(Ay),-(A7), CAS2.W) | ucode020 |
| MOVEC CACR / CAAR / MSP / ISP (plus the 68010's) | V | `m68ksv_eu` |
| MSP / ISP / M bit, SR mask $F71F, interrupt throwaway frame (format 1) | V | `EXC_INT20_T` |
| Frames: format 0 (traps, interrupts), 2 (CHK, CHK2, TRAPV, TRAPcc, zero divide, trace), B (bus / address error) | V (0 / 2); B: frames classified (Musashi writes a mostly empty frame) | `EXC12_F2`, `EXC0_020` |
| RTE formats 0 / 1 / 2 / 9 / A / B, format error otherwise | V; C (7 / 9, foreign B, throwaway with S clear) | `RTE20` |
| T0 trace (change of flow) | V | decode bit 33, `m2 FLOW` |
| BKPT acknowledge (number on A4–A2) | V | 68010 path |
| Instruction cache 64 x 32, CACR E / F / CE / C, CAAR, CDIS | V (stale code: C), D (`cache020`) | `m68ksv_biu32` |
| Coprocessor: F-line → CPU-space probe, no response → F-line exception; cpSAVE / cpRESTORE privileged | V (BERR answer); C (privilege) | `LINEF20`, `BA_CPS` |
| CALLM / RTM | — (illegal instruction) | |
| RMC_n for CAS / CAS2 | — (TAS only) | |
| MC68020 cycle timing | — (68000 / 68010 rhythm; approximate) | |

### Oracles and harnesses (new)

- `verify/musashi/musashi_model020.h/.cpp`, `build020.sh`: MAME's Musashi m68020 / m68ec020 (`Projects/Mame_Source`,
  read-only, built unmodified) as a C++ model; every write logged per byte with its function code; the 68881 CIR
  space stubbed (no FPU). `verify/musashi/shim/emu.h` (own file) gained the unaligned 16 / 32-bit bus forms.
- `verify/tb/mus020.cpp`, `verify/mus020_build.sh`: lockstep at every instruction boundary — D0–D7, A0–A6, USP, ISP,
  MSP, SR ($F71F), PC, VBR, SFC, DFC, CACR, CAAR and every written byte with its FC. Options: `-ec`, `-port 0..4`
  (32 / 16 / 8 / STERM / random per 64-byte block), `-w`, `-irq` (vector / autovector / spurious), `-mix` / `-snip`
  (15 snippets incl. MOVEC 020, Bcc.L, EXTB / LINK.L, CHK.L / TST / CMPI, M bit), `-cyc`.
- `verify/tb/dsz020.cpp` and `verify/tb/cache020.cpp` (built by `verify/dsz020_build.sh`).
- `verify/tb/harte.cpp`: `-bus32` (32-bit memory port) and a per-file failure classification for the 68020 build.

### Musashi lockstep (final RTL, 8 runs x 10,000 instructions per row)

| Row | Stimulus | CPU clocks | Mismatching runs | Group-0 resyncs (registers equal) | Interrupts / trace | Bus cycles 32 / 16 / 8 / STERM |
|---|---|---|---|---|---|---|
| seed 51 | suite only, 32-bit | 1,633,990 | **0** | 95 (88) | 0 / 15 | 323,883 / 0 / 0 / 0 |
| seed 52 | mix 25, random ports | 1,538,257 | **0** | 137 (132) | 0 / 87 | 96,596 / 46,737 / 107,211 / 55,267 |
| seed 53 | mix 25, random ports, `-irq -w 2` | 1,702,026 | **0** | 243 (233) | 200 / 155 | 85,408 / 80,672 / 116,974 / 44,961 |
| seed 54 | same | 1,708,172 | **0** | 290 (279) | 216 / 132 | 75,905 / 121,322 / 74,694 / 42,663 |
| seed 58 | mix 25, 8-bit, `-w 1` | 3,106,446 | **0** | 104 (98) | 0 / 41 | 8 / 0 / 625,339 / 0 |
| seed 55 | mix 10, 32-bit, `-cyc` | 1,667,274 | **0** | 103 (96) | 0 / 33 | 343,684 / 0 / 0 / 0 |
| 68EC020 seed 56 | mix 25, random ports, `-irq -w 2` | 1,821,720 | **0** | 264 (254) | 239 / 138 | 44,493 / 72,126 / 171,014 / 73,933 |
| 68EC020 seed 57 | suite only, 16-bit | 1,291,414 | **0** | 79 (76) | 0 / 32 | 8 / 239,187 / 0 / 0 |
| 68EC020 seed 59 | mix 25, random ports, `-irq -w 2` | 1,994,969 | **0** | 268 (254) | 226 / 146 | 57,756 / 113,564 / 142,150 / 77,774 |
| **total** | | 16,464,268 | **0** | 1,583 (1,510) | 881 / 779 | |

Classified Musashi differences (summed over the nine rows; resync = registers / memory taken from m68ksv and the run
continues, reset = both CPUs reset because the comparison has no defined answer):

| Class | Count | Who is right |
|---|---|---|
| group-0 (address error on an odd PC: Musashi defers it to the next fetch and writes a mostly empty format A / B frame) | 1,583 resyncs; registers differ after it in 73 (not analysed) | m68ksv's frame is the 68010-derived format B; no 68020 reference frame on disk |
| odd (d16,PC) word / (d8,PC,Xn) operand (Musashi's `m68k_read_pcrelative_16` leaves bits 23–16 unmasked) | 26 / 52 resyncs | Musashi bug |
| RTE of a format-7 frame (Musashi pops a 68040 frame) / format-9 frame (Musashi: format error) | 46 resyncs | PRM: 7 is a format error on the 020, 9 is valid |
| RTE of a foreign format-B frame (m68ksv checks its version word, Musashi pops it) | 26 resets | design decision |
| RTE through a throwaway frame with S clear | 20 resets | undefined |
| self-modified code under the cache / prefetch (bytes of the instruction written since the last reset) | 34 resets | both legal (different fill times) |
| CALLM / RTM (Musashi does not model them; m68ksv: illegal) | 37 resyncs | neither |
| cpSAVE / cpRESTORE in user mode (68020: privilege violation; Musashi: F-line) | 29 resyncs | PRM |
| PACK -(Ay),-(A7) (Musashi's handler for this form differs from its other PACK forms) | 6 resyncs | Musashi |
| DIV.L overflow: C (PRM: cleared; Musashi keeps it) | 1 resync | PRM |
| trace after a group-2 exception (Musashi cancels it) | 17 resyncs | as the 68010 (checkpoint 3) |
| CAS2.W failing Dc, DIVS $80000000 / -1, vector-0 interrupt, prefetch-window SMC | 0 each | |
| coprocessor CPU-space cycles (the harness answers BERR: no coprocessor) | 3,649 cycles | — |
| resets after VBR left the vector tables or SSP left RAM (random programs) | 1,416 | — |

During development the lockstep found and drove the fixes of: full-format indirect pointer clobbering DT, CHK format 2,
MUL.L / DIV.L register field bit 15, bit-field wrap masks, CAS / CAS2 operand halves, RTE formats, LINK.L prefetch,
bit-field insert register, T0 set, a cache fill on an address-error cycle (the EU's abort is valid only in the first
micro-cycle; latched now) and the 68EC020 IACK address in the harness.

### Dynamic sizing and cache tests (final RTL, 68020 and 68EC020 builds)

| Test | 68020 | 68EC020 |
|---|---|---|
| `dsz020`: port 32 / 16 / 8 / STERM x byte / word / long x A1A0 0–3, read and write: register value, written bytes, every physical cycle's address / SIZ / R/W | 48 / 48, 176 cycles checked | 48 / 48 |
| `cache020`: hit (two calls = one call's fetches), off, freeze, CDIS (twice the fetches), stale code after a write, C clears, CE clears the line, FC2 in the tag; x 4 port widths; random waits and `-w 0` | 28 / 28 | 28 / 28 |

### Cycle timing

Not the MC68020 timing: the 68020 build runs the 68000 / 68010 micro-cycle timing (4-clock bus cycles, no overlap, a
long operand as two word cycles, cache hits as zero-wait internal cycles). `mus020 -cyc` (seed 55): **6,448 of 79,848**
instruction times equal to Musashi's m68020 table (Musashi counts the 68020's best case with the cache). Examples
(m68ksv / Musashi clocks): illegal instruction (IR $146C) 38 / 20, MOVE #,SR 16 / 10, BRA 12 / 10, ORI.L #,D0 14 / 2.
Exact: none claimed. The MC68020 tables were not on disk; building them in is open.

### 68000 suite on the 68020 build (`M68KSV_CPU=68020 verify/build.sh`, `harte -bus32`, same exclusions / corrections)

Pure 715,598 / 794,139; corrected 7,822 / 202,182. Every failure is classified by `harte` (first matching class):

| Class | Tests | Why the 68020 differs from the 68000 test |
|---|---|---|
| the 68000 took an address error | 178,087 | the 68020 has no address error on data / stack accesses (only odd instruction fetches) |
| another exception (frame) | 16,488 | format 0 / 2 frames, T0, stacked PC (TRAP 8,065 tests, TRAPV, CHK, privilege, ...) |
| SR written | 20,002 | M and T0 exist on the 68020 (ORI / ANDI / EORI to SR, MOVE to SR, RTE, STOP) |
| indexed mode with extension-word bits 10–8 set | 53,004 | scale / full format on the 68020 |
| other | 5,320 | DIVS 2,420 / DIVU 1,581 / CHK 292 (undefined flags: the 68020 rules, as Musashi), LINK A7 1,005 (pushes A7 − 4, as Musashi's 68010 / 68020), Bcc 14 (displacement $FF = Bcc.L), 8 indexed-with-immediate tests (the classifier's extension-word guess misses; not analysed) |

### Regression and A/B (final RTL)

| Gate | Result |
|---|---|
| 68000 suite (`run_all.sh`) | 794,139 / 794,139 pure on every column; corrected 202,181 / 202,182; timed 797,878 — identical |
| idle clocks 0-3, smoke, retry | 794,139 pass, bus order 797,878, corrected 202,181; 3 / 3; 8 / 8 — identical |
| `run_family.sh` 68008 / 68008FN / 68EC000 8-bit / 16-bit | 794,137 / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each — identical |
| MAME m68008 lockstep (seed 7, 40 x 300,000 clocks; 68008 / 68008FN / 68EC000) | **0** mismatching runs; outputs byte-identical to the fifth session |
| fx68k lockstep (20 rows, 64 runs x 400,000 phases) | all 20 outputs byte-identical to the fifth session |
| Musashi `mus010` seeds 41 / 42 / 43 / 44 / 21 `-cyc` | 0 mismatching runs; outputs identical (cycles 154,783 / 159,119 equal) |
| `rerun010` (7 seeds), `loop010` | 0 mismatching runs, 0 failures; outputs identical |
| 68000 suite on the 68010 build | 781,979 / 794,139 pure, corrected 9,793 — identical |
| A/B vs the start snapshot (`scratchpad/cp4/ab`, clock-exact, every output every clock): 68000, 68008, 68008FN, 68EC000 16-bit and 8-bit, 68010; 3 seeds x 4 runs x 4 M clocks each | **0 mismatching runs**: 68000 1,121,208 boundaries / 3,176 BERR; 68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 (both widths, 24 runs) 1,747,178 / 6,669; 68010 982,951 / 3,423, 73,194 loop-mode words, 1,457 software-completed RTE |
| 68000 / 68010 ROM modules | the start-snapshot `m68ksv_urom.sv` / `m68ksv_drom.sv` are byte-identical prefixes of the new files (020 modules appended); `m68ksv_upkg.sv` only gained localparams |
| Verilator 4.204 `--lint-only -Wall` | 0 errors for CPU 68000 / 68008 / 68009 / 68001 / 68010 / 68020 / 68021 and `m68ksv_qtop` with all seven; warnings 77 per CPU (start: 61) / qtop 101, 020: 99 (start: 75) — the new ones are UNUSED: ports and signals unused in a configuration, three unused parameters, unused bits |
| `verify/tools/mkall.sh` pre-compile check | no module-level loops, casts, patterns, `inside` or expression bit-selects; the procedural `for` list grew by three (bit-field find-first-one in the EU, the read-byte routing in BIU32), the same kind as the existing ones |
| Vendor files | `syn/quartus/fx68k/*`, `microrom.mem`, `nanorom.mem` byte-identical to the fx68k download; MAME source untouched; `files.qip`, `fx68k.qip`, `fleet_types.svh` unchanged |
| `DIAG` markers | none (grep over `rtl/`, `verify/`, `syn/quartus/*.sv`) |

The fx68k lockstep harness needed one change: `verify/tb/lockstep.cpp` reads three BIU internals by their Verilator
names, which moved into the generate block (`m68ksv__DOT__g_biu16__DOT__biu__DOT__...`).

### yosys (`verify/tools/yosys.sh`, `YCPU`; yosys 0.66 `synth_intel_alm -family cyclonev`; an estimate, not Quartus)

| m68ksv | LUTs (start → now) | carry | FF | M10K | DSP | depth (LUT levels) |
|---|---|---|---|---|---|---|
| 68000 | 3,045 → 3,046 | 446 | 1,222 | 30 | 1 | 11.0 |
| 68008 | 3,042 → 3,055 | 447 | 1,230 | 30 | 1 | 11.0 |
| 68008FN | 3,031 → 3,046 | 447 | 1,231 | 30 | 1 | 12.0 (start: 11.0; the same unchanged path, `e0` enable → register-file address: mapping noise) |
| 68EC000 | 3,075 → 3,069 | 448 | 1,232 | 30 | 1 | 11.0 |
| 68010 | 3,923 → 3,922 | 579 | 1,550 | 34 | 1 | 11.0 |
| **68020** | — → **6,296** | 1,167 | 2,317 | 39 | 5 | **15.0** |
| **68EC020** | — → **6,314** | 1,159 | 2,309 | 39 | 5 | **15.0** |

With the 68010's Quartus / yosys ratio (2,427 ALMs / 3,923 LUTs) the 68020 would land near 3,900 ALMs. The depth-15
path is the cache tag compare into `hit_q` / AS: yosys has no asynchronous MLAB read and builds the 64-entry array
from registers and a 64:1 mux; in Quartus it is an MLAB read + a 25-bit compare. The next paths: bit-field result
(12.55), DIV.L counter (12.1), flags (12.0). Two paths were shortened this session (CHK2 compare registered before the
flag word; read-data byte routing registered at the termination; the cache line registered at the lookup). **Timing
at 96 MHz on the 68020 revisions is a risk**; the user's compile decides.

### Decisions taken alone (the user could not be asked)

1. **The execution unit stays 16-bit at the bus.** A long operand is two word requests (high word first); the BIU
   sizes and splits each as the 68020 would. Registers / memory are the same; bus-cycle counts and timing are not.
2. **4-clock minimum bus cycle** for every 68020 cycle; STERM is a 32-bit DSACK. No 3-clock / 2-clock cycles.
3. **68000 / 68010 cycle timing on the 020** (priority 6 not reached). No MC68020 User's Manual on disk: the 020
   behaviour was written from memory and checked against Musashi; `#unverified` where Musashi is silent (write-data
   multiplexer lanes, CE, CIR offsets).
4. **Format B frame in m68ksv's own internal layout** (architected words where the PRM puts them, the 68010 format-8
   continuation state in the internal words). RTE checks m68ksv's version word; software completion = the handler
   clears DF / RB / RC in the SSW.
5. **RTE format 9 returns** (no coprocessor state), **A pops and returns**; format 1 with S clear continues on the
   user stack.
6. **Coprocessor = probe only:** line F types 0–5 run one CPU-space byte read at the CIR the 68020 addresses first
   (response $00 for cpGEN, condition $0E for cpScc / cpDBcc / cpTRAPcc / cpBcc, save $04, restore $06), result
   ignored, then the F-line exception. A real 68020 *writes* the command / condition / format word for cpGEN, cpScc,
   cpBcc and cpRESTORE. cpSAVE / cpRESTORE in user mode: privilege violation.
7. **CACR CE clears one line** (CAAR[7:2]; Musashi clears all); a frozen cache still makes long fetches on a miss.
8. **CALLM / RTM: illegal instruction.** **RMC_n: TAS only.**
9. **The PRM over Musashi** for cpSAVE / cpRESTORE privilege, DIV.L overflow C, CAS2.W, PACK -(Ay),-(A7); each
   difference is classified and counted, never hidden.
10. **The harness answers coprocessor cycles with BERR** and resets both CPUs where there is no defined answer
    (foreign format-B RTE, throwaway frame with S clear, self-modified code under the cache); counted.
11. **The 68000 suite runner and the A/B tool were extended, not the RTL tests' expectations**: `harte -bus32`
    classifies, the A/B tool copy (`scratchpad/cp4/ab/build.sh`) adds `m68ksv_biu32.sv` to the new RTL's file list.

### Open (not done / not verified)

- MC68020 cycle timing (UM tables); coprocessor protocol (CIR handshake, format 9 frames from a coprocessor); CALLM /
  RTM; RMC_n for CAS / CAS2.
- Bus errors in the 68020 lockstep: `mus020` has no BERR injection; format-B frames are exercised only by odd-PC
  address errors; the continuation logic is the 68010's (`rerun010`), a `rerun020` was not written.
- HALT / bus arbitration / reset on the 68020 build: not stimulated (the BIU32 copies the 68000 BIU's code).
- 73 group-0 resyncs with registers differing after Musashi's deferred address error: not analysed.
- Quartus: not compiled. The 68020 cache array uses `ramstyle "MLAB, no_rw_check"` with an asynchronous read — check in
  the fitter report that it landed in MLABs (not registers).
- An external 68020 single-step test suite (Harte-style) would be the next oracle; none on disk, nothing downloaded.

### Files changed / new (sixth session)

- New: `rtl/m68ksv_biu32.sv`, `rtl/gen/m68ksv_ucode020.py`, `verify/musashi/musashi_model020.h`,
  `verify/musashi/musashi_model020.cpp`, `verify/musashi/build020.sh`, `verify/tb/mus020.cpp`,
  `verify/mus020_build.sh`, `verify/tb/dsz020.cpp`, `verify/tb/cache020.cpp`, `verify/dsz020_build.sh`,
  `syn/quartus/m68ksv_qtop_68020.qsf`, `syn/quartus/m68ksv_qtop_68ec020.qsf`.
- Changed: `rtl/gen/m68ksv_ucode.py` (third pass, 020 fields / decode), `rtl/gen/m68ksv_ucode010.py` (loop mode and the
  format-8 push left out of the 020 set), `rtl/m68ksv_eu.sv`, `rtl/m68ksv.sv` (020 ports, BIU generate),
  `rtl/m68ksv_fleet.sv` (020 fields of the fleet types), generated `rtl/m68ksv_upkg.sv` / `m68ksv_urom.sv` /
  `m68ksv_drom.sv` / `verify/tb/m68ksv_ualabels.h` / `rtl/m68ksv_all.sv`, `verify/tools/mkall.sh` (+ BIU32),
  `verify/build.sh` (+ BIU32), `verify/tb/harte.cpp` (`-bus32`), `verify/tb/lockstep.cpp` (internal names),
  `verify/musashi/shim/emu.h`, `syn/quartus/m68ksv_qtop.sv` (32-bit RAM for the 020), `syn/quartus/m68ksv_qtop.qpf`
  (two revisions), `syn/quartus/README.md`, `DESIGN.md`, `REPORT.md`.

### Quartus (the user compiles; nothing here was run in Quartus)

From `syn/quartus`, one revision per run:

```bash
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

Run `verify/tools/mkall.sh` first if any `rtl/` source changed (it regenerates `rtl/m68ksv_all.sv`, which
`files.qip` reads; the copy in the tree is current).

#### First compile failed: genvar in `m68ksv_qtop.sv` (fixed 2026-11-16)

- **Error:** `m68ksv_qtop.sv(88)`, error 10170 near `genvar`. The 68020 RAM loop used `for (genvar l = ...)`, which
  Quartus 17 rejects (listed in the vault note "Quartus 17.0 SystemVerilog subset"). Verilator accepts it.
- **Fix:** `genvar l;` at module scope and `l = l + 1`.
- **Prevention:** `verify/tools/mkall.sh`'s pre-compile check now also greps for `for (genvar` in `m68ksv_all.sv` and
  in `m68ksv_qtop.sv`. Before this, it never looked at the Quartus top.

#### Measured Quartus results (user's compiles 2026-11-16 09:44–10:34; `timing_paths.tcl` run on each)

| Revision | ALMs | Registers | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|
| 68020 | **4,026** | 2,361 | 4 | 101.64 / 100.55 MHz | +0.578 / +0.472 ns | +0.235 ns |
| 68EC020 | **4,024** | 2,360 | 4 | 99.56 / **96.31** MHz | +0.373 / **+0.034** ns | +0.237 ns |
| 68010 | 2,426 | 1,727 | 1 | 113.86 / 112.46 MHz | +1.634 / +1.525 ns | +0.240 ns |
| 68000 | 1,815 | 1,334 | 1 | 113.92 / 109.53 MHz | +1.639 / +1.287 ns | +0.233 ns |
| 68008 | 1,788 | 1,337 | 1 | 121.58 / 115.35 MHz | +2.192 / +1.748 ns | +0.325 ns |
| 68008FN | 1,814 | 1,337 | 1 | 118.11 / 112.69 MHz | +1.950 / +1.543 ns | +0.244 ns |
| 68EC000 | 1,816 | 1,357 | 1 | 119.23 / 116.80 MHz | +2.030 / +1.855 ns | +0.326 ns |

- **Fmax:** every revision meets 96 MHz. The 68EC020 only just does: +0.034 ns at −40 °C.
- **68020 / 68EC020 worst paths** (all in the EU):
  - `ir` → `mul_lb` (MUL.L operand select);
  - `bcd_neg_q` / `xb_q` → `ccr_q` / `hold_xvc` (the flag path, now 10 levels);
  - `xb_q` → `res`.
  The cache is not on the worst list.
- **Instruction cache:** the cache memory (`m68ksv_biu32` `c_mem`, 57 bits wide) is an MLAB, as intended.
- **68020 area by entity:**

  | Entity | ALMs |
  |---|---|
  | `m68ksv_eu` own logic | 3,298.6 |
  | `m68ksv_biu32` | 388.8 |
  | ALU | 215.3 |

  4 DSP blocks.
- **68000 family and 68010:** behaviour is unchanged (the A/B check above), and they are within placement noise of the
  fifth session (68000 +26 ALMs, 68008 −24, 68008FN +18, 68EC000 −2, 68010 −1). Fmax rose on 68008FN and 68EC000.
- **Checkpoint 5 items:**
  - 68010 / 68020 area;
  - the flag path `→ ccr_q`, now the shared worst path on every CPU and the reason for the 68EC020's thin margin;
  - the MUL.L operand select.

### How to rerun (checkpoint 4)

```bash
verify/mus020_build.sh <dir> [68021]            # Musashi library + mus020 (CPU 68020, or 68021 = 68EC020: run with -ec)
<dir>/mus020_68020 -seed N -runs R -instr I [-mix 25 -snip 15] [-port 0..4] [-irq] [-w W] [-cyc] [-v 1..4] <suite .bin ...>
verify/dsz020_build.sh <dir> [68021]; <dir>/dsz020_68020; <dir>/cache020_68020 [-v] [-w W]
M68KSV_CPU=68020 verify/build.sh <dir>; <dir>/harte -bus32 [-x verify/suite_exclusions.txt -c <corrections>] <suite .bin ...>
YCPU=68020 verify/tools/yosys.sh <dir>
```

## Checkpoint 4b (68020 gaps, flag-path timing) — seventh session, 2026-11-16

### Summary

- **Flag path shortened, behaviour unchanged.** The flags are no longer formed in the e3 clock: the raw flag terms and a
  term index per flag are registered at e3, and `ccr_q` is a mux of registers read at the next e0 (DESIGN.md 4, "Flag
  path split"). The adder's carries come off the end of the chain, the size / sign-extension / X-input / Scc controls
  are registered at e2, the result mux puts the adder last, MUL.L takes its operands one phase later. yosys depth of
  the flag endpoints: 9–12 → **≤ 7.0** on every CPU at the timing snapshot; on the final RTL ≤ 7.0 except one
  68020 index-decode register at 8.0 (tables below). Proof: the clock-exact A/B check against the start
  snapshot, extended to the 68020 pins (`ab20`), **0 mismatching runs on all seven configurations** (8 rows, 384 M
  clocks); a deliberate change fails it (4 / 4 runs). Snapshot taken: `scratchpad/m68ksv_cp4b_timing_snapshot/`.
- **68020 bus timing.** The 68020 build now runs one micro-cycle per CPU clock (DESIGN.md 2, 7.2): a zero-wait
  **synchronous (STERM) cycle takes 2 clocks, an asynchronous (DSACK) cycle 3**, wait states whole clocks, a sized
  access's next physical cycle starts at once (3 / 2 clocks each), measured by `dsz020 -w 0` on all 168 cycles.
  **A long operand read is one 32-bit request** that the BIU sizes and splits by port and alignment; with the cache
  off, instruction fetches are long accesses with a held word. **Long writes stay two word requests** (decision 4).
  Instruction times are approximate (the 68000 micro-routine structure at one clock per micro-instruction); RESET
  asserts its output 512 clocks.
- **RMC for CAS / CAS2** (and TAS) from the first operand read to the end of the last write, no bus grant in between:
  `rmc020` 9 locked sequences × 4 port types × 2 wait settings pass, the control (lock disabled) fails.
- **Coprocessor interface:** the 68020's interface-register cycles for every coprocessor type, BERR on them → F-line
  exception, cpGEN's response loop (null / come again / busy), other primitives → protocol violation. `cop020` with a
  scripted coprocessor: 7 / 7 steps, 13 CPU-space cycles checked.
- **CALLM / RTM: not implemented** (illegal instruction on both builds); classification below.
- **68020 lockstep stimulus:** `mus020 -br -halt -rst` (bus requests, HALT, reset pulses) and a bit-field snippet: 0
  mismatching runs. Bus-error injection with RTE continuation: new self-check `rerun020` (two m68ksv instances, as
  `rerun010`). It found two pre-existing format-B bugs, both fixed (RTE lost the SR's system byte; data faults were never
  re-run); **it still has mismatching runs** (counted below, partly classified: 68020-only micro-routine state is not
  in m68ksv's format-B frame). This gate is **not met**.
- **68000 family and 68010:** every gate identical to the sixth session; A/B against the timing snapshot 0 mismatching
  runs on the final RTL.

### Timing fix: logic depth before → after (yosys 0.66 `synth_intel_alm`, `verify/tools/depth.py`, LUT levels)

"Before" = the start snapshot (sixth-session final RTL); "after" = the timing snapshot (this run, before the 68020
work); the final-RTL figures are in the yosys table further down. Flags e3 = `ccr_q` / `hold_xvc` (before) and the new
term / index registers `q_*` and `hold_xvc` (after); SR at e0 = the SR register's flag inputs (`ccr_f` / `dbg_sr`).

| CPU | flags e3 | SR at e0 | MUL.L operands `mul_la` / `mul_lb` | ALU result `res` | deepest path overall |
|---|---|---|---|---|---|
| 68000 | 10.0 → **6.3** | 10.0 → **6.0** | — | 8.2 → 8.0 | 11.0 → 10.0 |
| 68008 | 10.0 → **8.0** (`q_xi` index decode; 6.0 after the final flattening of that decode) | 9.8 → **7.0** | — | 9.0 → 7.1 | 11.0 → 10.0 |
| 68008FN | 10.0 → **6.3** | 9.0 → **6.0** | — | 9.0 → 7.1 | 12.0 → 10.0 |
| 68EC000 | 9.0 → **6.3** | 9.65 → **5.0** | — | 8.15 → 8.0 | 11.0 → 10.0 |
| 68010 | 9.0 → **7.0** | 9.0 → **7.0** | — | 10.0 → 9.0 | 11.0 → 10.0 |
| 68020 | 11.3 → **7.0** | 12.0 → **7.0** | 11.0 → **1.0** | 12.55 → 10.15 | 15.0 → 12.05 |
| 68EC020 | 12.0 → **8.0** (`q_ci` index decode; 7.0 after the flattening) | 12.0 → **6.0** | 11.0 → **1.0** | 12.55 → 10.2 | 15.0 → 14.0 (cache tag) |

The two 8.0 entries were the term-index decode (a chain of `case` overrides); it was flattened into one `case` before
the final gates (A/B-verified on the 68000 family / 68010, mus020 on the 68020): final-RTL flag endpoints are ≤ 7.0 on
six CPUs and 8.0 on the 68020 (its term-index decode, `q_ci`; yosys table). The deepest paths that remain are pre-existing kinds: the e2 operand mux (`alu.a` /
`xa_q`, 11–12), the DIVU-condition → FIN decision (`dv_q` → `cond` → `fin_t`, 12), the cache tag compare (12–14).
Quartus decides; the user's compile is the measurement.

### A/B equivalence of the timing fix (clock-exact, every output every clock; `scratchpad/cp4b/ab/`)

New for the 68020 / 68EC020: `ab20.cpp` (+ `build20.sh`) — the 68020 pins (A32, D32 in / out, SIZ, DSACK, STERM, AVEC,
RMC, ECS / OCS, DBEN, IPEND, CACR / CAAR), random port per 64-byte block, wait states, BERR, AVEC / vectored IACK,
interrupts, BR, HALT, reset, CPU-space cycles answered by BERR; program = suite opcodes + the `mus020` snippets.
Old = start snapshot, new = timing-fix RTL; 3 seeds × 4 runs × 4,000,000 clocks per row:

| Configuration | Instruction boundaries | BERR injected | Mismatching runs |
|---|---|---|---|
| 68000 | 1,121,208 | 3,176 | **0** |
| 68008 | 593,918 | 3,410 | **0** |
| 68008FN | 553,569 | 3,416 | **0** |
| 68EC000 16-bit / 8-bit | 1,121,208 / 625,970 | 3,176 / 3,493 | **0 / 0** |
| 68010 (73,194 loop-mode words, 1,457 software-completed RTE) | 982,951 | 3,423 | **0** |
| 68020 (14,795 CPU-space cycles) | 850,827 | 3,356 | **0** |
| 68EC020 | 850,827 | 3,356 | **0** |

Control: the same check with TAS setting V (one flag-index entry changed) fails in 4 of 4 runs. Final RTL vs the
timing snapshot (the 68020 changed on purpose after it): 68000 / 68008 / 68008FN / 68EC000 both widths / 68010 —
identical counts, **0 mismatching runs**.

### 68020 bus and instruction timing

What "cycle-accurate" can mean for the 68020: its instruction times overlap (a three-word prefetch queue, the
instruction cache, a pending-write buffer, execution in parallel with bus cycles), so the User's Manual gives best /
cache / worst-case counts per instruction and EA rather than one number; a single "exact" count exists only for a
defined bus and cache state. What m68ksv can match is the bus: cycle shapes, sizes, order and durations. What it
implements: the 68020's S-state bus cycles and dynamic sizing (exact in shape on its own phase grid, edge choices
below `#unverified`), long operand reads as one request, one clock per micro-instruction; instruction times are
m68ksv's micro-routine lengths (approximate; no overlap of execution with bus cycles; no exact count claimed).

| Item | m68ksv (4b) | 68020 (User's Manual, from memory) | Status |
|---|---|---|---|
| Asynchronous cycle, no wait | 3 clocks (S0 rising edge … S5), AS 2 clocks | 3 clocks | exact on `dsz020 -w 0`; edges `#unverified` |
| DSACK / BERR / AVEC sampling | falling edges from the end of S2; data latched one clock later | same (asynchronous inputs on the falling edge) | `#unverified` |
| Synchronous cycle (STERM), no wait | 2 clocks, AS 1 clock | 2 clocks | exact on `dsz020 -w 0`; STERM / data edges `#unverified` |
| Wait states | whole clocks | whole clocks | exact in shape |
| Dynamic sizing: next physical cycle | the next rising edge (3 / 2 clocks per cycle) | back to back | `#unverified` |
| Long operand read | one request, SIZ = 4, split by port / alignment | same | exact (`dsz020`) |
| Long operand write | two word requests (each split by the port) | one request | **approximate** (decision 4) |
| Instruction fetch | long (cache on: hit = 2-clock internal cycle; off: long read + held word) | long fetches, 3-word queue | approximate |
| TAS / CAS / CAS2 | RMC from the first read's S0 to the end of the last write, AS negated between, no grant | same | `#unverified` (AS between, failed CAS) |
| RESET instruction | RESET_n_o low 512 clocks | 512 clocks | `#unverified` (Musashi: 518 for the instruction) |
| ECS / OCS | one clk after S0 to S1 | S0 to S1 | approximate (one clk late) |
| Write DS | S2 | S3 | `#unverified` |
| Instruction times | micro-routine lengths | best / cache / worst tables | approximate; examples in the table below |

`mus020 -cyc` (Musashi's m68020 table = its cache-case figures; final RTL, see the lockstep table row c55):
**4,307 of 79,848** instruction times equal to Musashi's (sixth session, 68000 micro-cycle rhythm: 6,448 — most of
those matches were coincidences of a twice-as-long rhythm). Examples (m68ksv / Musashi clocks; IR): illegal instruction
($146C) 25 / 20 (was 38), MOVE #,SR ($46F8) 13 / 12, BRA ($60F6) 7 / 10 (was 12), ORI.L #,D0 ($0080) 8 / 2 (was 14),
MOVE.L abs.L,Dn ($2039) 13 / 6, ASx #,Dn ($EE2E) 3 / 6, MOVE.W reg,(d8,An,Xn) ($33A4) 14 / 12, AND.W -(Ay),Dn
($C520) 10 / 9. The remaining gap is structural: every instruction word still costs a two-micro-word fetch (the 68020
gets the second word of a long fetch, and with the cache whole instructions, at no cost) and the 68000's idle words
remain in the micro-routines. One harness artefact: the example for group $D088 prints a wrapped count (a reset inside
the measured instruction); the group's other 2,421 entries are ordinary.

### RMC, coprocessor, CALLM / RTM

- **RMC** (`verify/tb/rmc020.cpp`): TAS, CAS.L / .W / .B (equal, not equal, odd address), CAS2.L (equal, first compare
  failing), CAS2.W (second compare failing). For every interval with RMC_n low: exactly the locked sequence's cycles
  (reads, then the writes when the compares succeeded; FC, R/W, address, SIZ, sized by the port), no other cycle inside,
  RMC continuous, BR asserted throughout and BG_n never low; memory results checked. Ports 32 / 16 / 8 / STERM × waits
  0 and 0–2: **8 / 8 configurations, 9 / 9 sequences each, 0 failures** (68020 and 68EC020 builds, final gates).
  Control (lock input tied off): 9 failures. Found and fixed on the way: TAS let the bus be granted between its read and
  write (the arbiter's block dropped at the internal word), and a pending BR held the locked cycles back.
- **Coprocessor** (`verify/tb/cop020.cpp`, coprocessor model on Cp-ID 1 = 16-bit port, Cp-ID 2 absent): cpGEN with
  busy, busy, null + CA, null → completes; cpGEN on the absent Cp-ID → F-line (vector 11, format 0, PC = the
  instruction); cpGEN answered with $8900 → protocol violation (vector 13); cpBcc.W answered → protocol violation;
  cpBcc.W absent → F-line (condition register $0E); cpSAVE absent → F-line (save register $04 read); cpGEN null at
  once → completes. **7 / 7 steps, 13 CPU-space cycles exact** (address, R/W, SIZ, written word), waits 0 / 0–2 / 0–5.
  In `mus020` the harness answers coprocessor cycles with BERR; Musashi (no FPU) takes the F-line exception: no
  difference beyond the classified cpSAVE / cpRESTORE privilege case.
- **CALLM / RTM:** not implemented: illegal instruction (vector 4) on the 68020 and the 68EC020. The 68EC020 behaviour
  is the real chip's (no module support); the 68020's is a deviation (open). Musashi does not model them (`m68k_in.lst`
  callm / rtm: log only; CALLM reads its EA before the argument word): the lockstep resynchronises and counts them
  ("CALLM / RTM" column, as in checkpoint 4).

### Musashi lockstep (`mus020`, final RTL, 8 runs × 10,000 instructions per row)

| Row | Stimulus | CPU clocks | Mismatching runs | Group-0 resyncs (registers equal) | Interrupts / trace | Cycles 32 / 16 / 8 / STERM |
|---|---|---|---|---|---|---|
| seed 51 | suite only, 32-bit | 1,073,563 | **0** | 95 (88) | 0 / 15 | 248,531 / 0 / 0 / 0 |
| seed 52 | mix 25, random ports | 1,085,351 | **0** | 138 (133) | 0 / 87 | 64,470 / 46,217 / 116,874 / 39,344 |
| seed 53 | mix 25, random ports, `-irq -w 2` | 1,388,416 | **0** | 233 (225) | 276 / 153 | 61,583 / 88,263 / 130,492 / 37,011 |
| seed 54 | same | 1,260,649 | **0** | 254 (244) | 290 / 116 | 47,118 / 128,827 / 74,143 / 36,453 |
| seed 58 | mix 25, 8-bit, `-w 1` | 2,485,567 | **0** | 103 (97) | 0 / 41 | 8 / 0 / 675,869 / 0 |
| seed 55 | mix 10, 32-bit, `-cyc` | 1,114,645 | **0** | 103 (96) | 0 / 33 | 270,387 / 0 / 0 / 0 |
| 68EC020 seed 56 | mix 25, random ports, `-irq -w 2` | 1,420,777 | **0** | 221 (211) | 296 / 128 | 36,865 / 65,891 / 184,318 / 47,709 |
| 68EC020 seed 57 | suite only, 16-bit | 1,077,545 | **0** | 79 (76) | 0 / 32 | 8 / 264,322 / 0 / 0 |
| 68EC020 seed 59 | mix 25, random ports, `-irq -w 2` | 1,391,654 | **0** | 258 (245) | 301 / 144 | 27,832 / 103,653 / 138,816 / 54,434 |
| **new** seed 60 | as 53 + `-br -halt -rst` (338 bus requests, 204 HALT pulses, 3 resets) | 1,536,782 | **0** | 294 (278) | 305 / 151 | 59,799 / 84,222 / 138,317 / 63,851 |
| **new** 68EC020 seed 61 | as 56 + `-br -halt -rst` (376 / 262 / 2) | 1,906,377 | **0** | 1,747 (1,734) | 371 / 136 | 64,315 / 88,023 / 217,656 / 82,292 |
| **new** seed 62 | mix 40, 16 snippets (bit fields), `-irq -w 2` | 1,979,918 | **0** | 1,869 (1,862) | 375 / 397 | 77,813 / 78,656 / 217,763 / 73,880 |
| **new** 68EC020 seed 63 | mix 40, 16 snippets | 1,375,576 | **0** | 117 (109) | 0 / 115 | 51,784 / 62,055 / 190,858 / 44,454 |
| **total** | 1,040,000 boundaries | 19,096,820 | **0** | 5,511 (5,398) | 2,214 / 1,548 | 1,010,513 / 1,010,129 / 2,085,106 / 479,428 |

Bus requests in rows 60 / 61: 714, granted for 147,678 clocks in total; HALT pulses 466; reset pulses 5. Classified
Musashi differences summed over the 13 rows (same classes as checkpoint 4, none new): group-0 resyncs 5,511 (Musashi's
deferred address error / mostly empty frame; rows 61 and 62 are high and were not analysed per instruction), odd
(d16,PC) word 45, (d8,PC,Xn) 82, RTE of a format-7 / 9 frame 89, foreign format-B RTE 56 resets, throwaway frame with
S clear 32 resets, self-modified code under the cache / prefetch 44 resets, CALLM / RTM 63, cpSAVE / cpRESTORE in user
mode 50, PACK -(Ay),-(A7) 5, DIV.L overflow C 4, trace after a group-2 exception 24, DIVS quirk / vector 0 / CAS2.W 0;
coprocessor cycles answered by BERR 8,814; resets after VBR / SSP left the tables 906. Bus-error injection is not in
`mus020` (Musashi's 68020 frames cannot check a continuation): it is `rerun020`, next.

### Bus error + RTE continuation self-check (`rerun020`, final RTL)

Two m68ksv 68020 instances, BERR injected into B on random data reads, writes and instruction fetches (not CPU space,
not during group-0 processing / vector fetch / RTE frame reads), handler = RTE (format-B re-run); every dispatch
compared (D0–A6, USP, ISP, MSP, SR, PC, VBR, SFC, DFC, written bytes outside the frame). 4 runs × 5,000 dispatches per
seed, 1 / 30 of the cycles faulted:

| Seed | Dispatches compared | BERR injected (read / write / fetch) | Mismatching runs | `-x020` (no faults inside 68020-only routines): dispatches / BERR / mismatching runs |
|---|---|---|---|---|
| 1 | 15,171 | 642 (53 / 33 / 556) | 1 | 15,901 / 774 / 1 |
| 2 | 9,848 | 597 (110 / 14 / 473) | 2 | 10,473 / 668 / 1 |
| 3 | 4,100 | 487 (70 / 47 / 370) | 3 | 4,163 / 492 / 3 |
| **total** | 29,119 | 1,726 | **6 of 12** | 30,537 / 1,934 / **5 of 12** |

**Not passing.** Before this session's two fixes every injected data fault and most fetch faults diverged (RTE restored
SR with a zero system byte; DF was never set, so RTE skipped every data re-run); with them, 1,726 faults ran through
and 6 runs still diverge. Classes seen: a fault inside the full-format EA subroutine (seed 1: the subroutine's return
address and the indirect pointer XT are not in m68ksv's format-B frame — the re-run resumes with them lost; `-x020`
removes that one but not the others); memory differences at or just above the frame after write faults near the stack
(seeds 2 / 3) and an address high byte difference (seed 3), not root-caused. Open.

### Gates (final RTL)

| Gate | Result |
|---|---|
| 68000 suite (`run_all.sh`) | 794,139 / 794,139 pure on every column; corrected 202,181 / 202,182; timed 797,878 — identical |
| idle clocks 0–3, smoke, retry | 794,139, bus order 797,878, corrected 202,181; 3 / 3; 8 / 8 — identical |
| `run_family.sh` 68008 / 68008FN / 68EC000 8 / 16-bit | 794,137 / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each — identical (output hash equal) |
| MAME m68008 lockstep ×3 (seed 7, 40 × 300,000) | outputs byte-identical to the sixth session (0 mismatching runs) |
| fx68k lockstep, 20 rows | all 20 outputs byte-identical to the sixth session |
| `mus010` seeds 41 / 42 / 43 / 44, 21 `-cyc` | outputs identical; 0 mismatching runs; cycles 154,783 / 159,119 |
| `rerun010` (7 seeds), `loop010` | outputs identical; 0 mismatching runs, 0 failures |
| 68000 suite on the 68010 build | identical (781,979 / 794,139, corrected 9,793) |
| A/B 68000-family / 68010 vs the timing snapshot (final RTL) | **0 mismatching runs** (counts in the A/B section) |
| `mus020`, 13 rows incl. 4 new | **0 mismatching runs** (table above) |
| `dsz020` (also `-w 0` timing), `cache020` | 48 / 48 (168 cycles, 168 timed), 28 / 28 — 68020 and 68EC020 |
| `rmc020`, `cop020` (new) | 8 / 8 configurations × 9 sequences; 7 / 7 steps × 3 wait settings — both builds |
| `rerun020` (new) | **6 of 12 runs mismatching — not met** (above) |
| 68000 suite on the 68020 / 68EC020 build (`harte -bus32`) | pure 715,598 / 794,139, corrected 7,822 / 202,182 — classes as in checkpoint 4 (address error 178,087, exception frame 16,488, SR 20,002, indexed / scale 53,004, other 5,320), identical on both builds |
| Verilator 4.204 `--lint-only -Wall` | 0 errors: CPU 68000 / 68008 / 68009 / 68001 / 68010 (79 warnings each) / 68020 / 68021 (77); `m68ksv_qtop` with all seven macros (103 / 99). New warnings vs the start: UNUSED only (`R_ADD`; `bq_lw` / `bq_rmc` / `bq_lock` unused outside the 68020); gone: `bf_w1`, `u_bus` |
| `verify/tools/mkall.sh` check | no `for (genvar` in `m68ksv_all.sv` or `m68ksv_qtop.sv`, no module-level loops, casts, patterns, `inside` or expression bit-selects; the procedural `for` list (inside `always` blocks) gained the adder operand, BFFFO byte tree / BFINS mask mirror and BIU32 lane loops — the same kind as before |
| Generated ROMs | 68000 / 68010 modules of `m68ksv_urom.sv` byte-identical to the start; `m68ksv_drom.sv` byte-identical; the package only gained localparams |
| Vendor files | fx68k files, `microrom.mem`, `nanorom.mem` byte-identical to the download (`cmp`); MAME source untouched |
| `DIAG` markers | none (one temporary trace in `mus020.cpp`, tagged, removed) |

### yosys (`verify/tools/yosys.sh` equivalent, final RTL; yosys 0.66 `synth_intel_alm -family cyclonev`; an estimate, not Quartus)

| m68ksv | LUTs (start → final) | carry | FF (start → final) | M10K | DSP | flag endpoints (e3 / SR) | deepest path |
|---|---|---|---|---|---|---|---|
| 68000 | 3,046 → 3,076 | 447 | 1,222 → 1,286 | 30 | 1 | 6.3 / 7.0 (was 10.0 / 10.0) | 10.0 |
| 68008 | 3,055 → 3,095 | 448 | 1,230 → 1,294 | 30 | 1 | 6.3 / 6.0 | 10.0 |
| 68008FN | 3,046 → 3,119 | 448 | 1,231 → 1,295 | 30 | 1 | 6.3 / 5.0 | 10.0 |
| 68EC000 | 3,069 → 3,085 | 448 | 1,232 → 1,296 | 30 | 1 | 6.3 / 7.0 | 10.0 |
| 68010 | 3,922 → 4,036 | 591 | 1,550 → 1,611 | 34 | 1 | 7.0 / 7.0 (was 9.0 / 9.0) | 10.0 |
| 68020 | 6,296 → 6,591 | 1,212 | 2,317 → 2,540 | 39 | 5 | **8.0** (`q_ci`, the term-index decode from `aop`) / 6.0 (was 11.3 / 12.0) | 12.0 (e2 operand mux) |
| 68EC020 | 6,314 → 6,585 | 1,207 | 2,309 → 2,532 | 39 | 5 | 7.0 / 7.0 (was 12.0 / 12.0) | 12.0 (cache tag) |

The flag endpoints meet ≤ 7 levels everywhere except the 68020's index decode, 8.0 (an e2 → e3 path from registered
`aop`; the 68EC020 maps the same logic to 7.0). Also at 8.0 on the 68020: `hold_x0` / `hold_nzm` through the frame-load
enable (BIU `st` → `b_dv` → field fx), the same depth as the other frame-loaded registers (7–8, pre-existing structure).
FF +50–220: the flag terms (about 50), the 68020's bit-field / DIV.L / BFFFO result registers and the BIU32 state.

### Decisions taken alone (the user could not be asked)

1. **Flag path: retimed, not re-encoded.** The flags are no longer formed in the e3 clock; the raw terms and a term
   index per flag are registered at e3 and `ccr_q` is a mux of registers read at the next e0. Exact by construction
   (every input of the former e3 register is registered at the same e3), proved clock-exact by the A/B tool on all seven
   configurations. Cost: about 50 flip-flops on the 68020 (the 68010 / 68020 terms are constant in the 68000 family).
2. **`ir` → `mul_lb` and `xb_q` → `res` shortened too** (cheap): MUL.L operands from the operand registers one phase
   later; the adder entering the result mux last; the bit-field extract / find-first-one results registered every
   clock from the stage-1 registers (BF follows BFP by one micro-instruction or more). Not touched: the e2 operand mux.
3. **68020 = one micro-cycle per CPU clock** — the only way to 3-clock asynchronous / 2-clock synchronous cycles with
   m68ksv's two-micro-word bus cycles. The 68020 build needs two `clk` or more between consecutive CPU edges (CPU clock
   ≤ clk / 4); the 68000 family / 68010 keep the old phase generator. The 68020 harnesses run at clk / 4, as the Quartus
   top already does.
4. **Long operands: reads one request, writes two.** The EU forms a written long's halves in different micro-words
   (MOVE.L: the high word from the source operand, the low word from the ALU result one word later); a deferred long
   write could not be re-run from m68ksv's format-B frame. The micro-routines are unchanged, so the second half of a
   long read still costs its two micro-words (as an internal cycle).
5. **Instruction timing not tuned to the User's Manual** (not on disk). Only RESET changed (512 clocks).
6. **Bus edges chosen** (all `#unverified`): STERM on the rising edge that starts S2, data on the falling edge that ends
   it; DSACK / BERR / AVEC on falling edges from the end of S2, data one clock later; write DS at S2; ECS / OCS from one
   clk after S0 to S1; AS negated between the read and the write of TAS / CAS (RMC held).
7. **68020 interrupt decision needs the sampled level above the mask (or 7)** — with one micro-cycle per clock the level
   latch and the decision see the same sample; without it a withdrawn level was acknowledged as level 0 (`mus020 -irq`).
8. **Coprocessor: the 68020's first interface access for every type; cpGEN's response loop only**; other primitives and
   answering coprocessors on the other types → protocol violation (vector 13); cpRESTORE writes a format word of 0
   without reading its EA. Encodings of null / busy from memory (`#unverified`). A system without a coprocessor sees
   exactly the F-line exception.
9. **CAS / CAS2 with a failing compare: no write, RMC released after the reads** (`#unverified`).
10. **CALLM / RTM not implemented** (budget; no oracle).
11. **Format-B bugs fixed when `rerun020` found them**; the remaining `rerun020` mismatches are reported, not hidden and
    not excluded from the totals.
12. **`ab20` uses the `mus020` snippets** (not the 68010 ones only), so the 68020 A/B covers the 68020 instructions.

### Open (not done / not verified)

- `rerun020` mismatching runs (above): 68020-only micro-routine state not saved in m68ksv's format-B frame (full-format
  EA subroutine return address, XT, the saved extension word; possibly bit-field / CAS2 / MUL.L / DIV.L state) and
  other classes not root-caused (memory differences after write faults near the stack). Needs a frame-layout extension.
- Long writes as one request; instruction times against the User's Manual; overlap of execution and bus cycles.
- CALLM / RTM on the 68020; coprocessor primitives beyond null / busy / come again; cpScc / cpDBcc / cpTRAPcc / cpBcc /
  cpSAVE / cpRESTORE completion with a coprocessor present.
- The bus edges marked `#unverified` (no MC68020 User's Manual on disk; nothing downloaded).
- Quartus: not run (rule). The yosys depth is an estimate; the user's compile decides Fmax (≥ 96 MHz required).

### Files changed / new (seventh session)

- RTL: `rtl/m68ksv_alu.sv` (raw flag terms, 33-bit adder carries, registered adder controls, result split),
  `rtl/m68ksv_eu.sv` (flag terms / indices, e2 control registers, result source, MUL.L operands, bit-field / DIV.L
  result registers, `bq_lw` / `bq_rmc` / `bq_lock`, CAS lock, coprocessor address / conditions / write data / F-line on
  BERR / vector 13, format-B SSW, 68020 interrupt rule), `rtl/m68ksv_biu32.sv` (rewritten: 68020 S-state timing, long
  reads, held fetch word, RMC / lock, termination), `rtl/m68ksv.sv` (68020 phase generator, new BIU ports).
- Generator: `rtl/gen/m68ksv_ucode.py` (m2 RMCON / RMCOFF, c2 CPRD / CPGEN / CPNULL / CPAGAIN, d2 CPW, ms VCPV),
  `rtl/gen/m68ksv_ucode020.py` (coprocessor routine, EXC_CPV, CAS / CAS2 lock tags, RESET 512 clocks, RTE20 SR keep);
  regenerated `rtl/m68ksv_upkg.sv`, `rtl/m68ksv_urom.sv` (68000 / 68010 modules byte-identical), `rtl/m68ksv_drom.sv`
  (byte-identical), `verify/tb/m68ksv_ualabels.h`, `rtl/m68ksv_all.sv`.
- Verification: new `verify/tb/rmc020.cpp`, `verify/tb/cop020.cpp`, `verify/tb/rerun020.cpp`; changed
  `verify/tb/mus020.cpp` (clk / 4, `-br -halt -rst`, bit-field snippet), `verify/tb/dsz020.cpp` (clk / 4, long reads,
  cycle-timing checks), `verify/tb/cache020.cpp` (clk / 4), `verify/tb/harte.cpp` (`-bus32`: an idle clock after each
  enable), `verify/dsz020_build.sh` (+ rmc020, cop020), `verify/mus020_build.sh` (+ rerun020).
- Docs: `DESIGN.md` (2, 4, 7, 7.2, 8), `syn/quartus/README.md` (68020 clock-enable note), this report.
- Scratchpad only: `cp4b/ab/` (A/B tool with `ab20.cpp`, `build20.sh`, `run_ab.sh`, `run_ab16.sh`), gate scripts.
- Unchanged: `syn/quartus/files.qip`, every `.qsf` / `.qpf`, `syn/quartus/m68ksv_qtop.sv`, `fleet_types.svh`,
  `rtl/m68ksv_fleet.sv`, vendor files.

### Quartus (the user compiles; nothing here was run in Quartus)

From `syn/quartus`, after `verify/tools/mkall.sh` (the tree's `rtl/m68ksv_all.sv` is current):

```bash
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
quartus_sta -t timing_paths.tcl <revision>                     # worst paths -> output_files/<revision>.paths.txt
```

What to look at: the flag path `→ ccr_q` / `hold_xvc` should be gone from the worst-30 lists (its endpoints are now the
`q_*` term registers and `sr`); the 68EC020's thin margin came from it. New logic to watch on the 68020: the BIU32
termination / write-data paths and the e2 operand mux.

### How to rerun (checkpoint 4b)

```bash
verify/dsz020_build.sh <dir> [68021]; <dir>/dsz020_68020 [-w 0]; <dir>/cache020_68020; <dir>/rmc020_68020 -port 0..3 [-w W]; <dir>/cop020_68020 [-w W]
verify/mus020_build.sh <dir> [68021]; <dir>/mus020_68020 ... [-br] [-halt] [-rst] [-snip 16]; <dir>/rerun020_68020 -seed N -runs R -instr I -p 30 [-x020] <suite .bin ...>
scratchpad/cp4b/ab/build20.sh <old rtl> <new rtl> 68020 <dir>; <dir>/ab20 -cpu 68020 -seed N -runs R -clocks C <suite .bin ...>
```

#### Measured Quartus results (user's compiles 2026-11-16 12:31–13:08; `timing_paths.tcl` run on each)

| Revision | ALMs (vs sixth session) | Registers | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|
| 68020 | 4,128 (+102) | 2,597 | 4 | 111.72 / 109.90 MHz | +1.466 / +1.318 ns | +0.083 ns |
| 68EC020 | 4,099 (+75) | 2,574 | 4 | 111.48 / 107.71 MHz | +1.447 / +1.133 ns | +0.213 ns |
| 68010 | 2,505 (+79) | 1,865 | **4** | 113.03 / 114.00 MHz | +1.570 / +1.645 ns | +0.278 ns |
| 68000 | 1,926 (+111) | 1,501 | **4** | 117.62 / 114.47 MHz | +1.915 / +1.681 ns | +0.310 ns |
| 68008 | 1,930 (+142) | 1,488 | **4** | 114.23 / 117.61 MHz | +1.663 / +1.914 ns | +0.294 ns |
| 68008FN | 1,916 (+102) | 1,517 | **4** | 112.92 / 112.71 MHz | +1.545 / +1.561 ns | +0.272 ns |
| 68EC000 | 1,927 (+111) | 1,501 | **4** | 120.57 / 118.82 MHz | +2.001 / +2.123 ns | +0.319 ns |

- **Timing fix worked.**
  - No `→ ccr_q` / `hold_xvc` path is in any revision's worst 3.
  - The 68EC020 went from +0.034 to +1.133 ns worst slack (from 96.31 to 107.71 MHz at −40 °C).
  - Every revision is ≥ 107 MHz.
  - The 68020's minimum hold slack is +0.083 ns (−40 °C), positive but thin.
- **Regression: 020 logic no longer folds away in the 68000 family and the 68010.**
  - Every non-020 revision now uses **4 DSP blocks** (was 1). The 68000's fitter DSP table shows `Mult0` (MUL.W) plus
    three blocks of `Mult1`, which is the 68020 MUL.L product `mul_lp <= mul_la * mul_lb` (`m68ksv_eu.sv`, around line
    1248), even though its operand load is gated by `IS020`.
  - ALMs grew 79–142 and registers ~150, consistent with more 020-only state surviving.
  - Behaviour is unchanged (A/B, this section), so this is area, not function.
  - The sixth-session RTL (operands loaded at e2 from `xa_v` / `xb_v`) folded the same multiplier away.
  - Fix still to do: make the 020-only logic (MUL.L, and whatever else the extra registers turn out to be) fold away in
    non-020 builds, e.g. by gating it with `IS020` at the product / result, or with generate blocks. Prove it with the
    A/B tool and the fitter's DSP and register counts.

### Fold-away fix (2026-11-16)

Fixes the regression above: 68020-only logic surviving in the 68000-family and 68010 builds (Quartus: 4 DSP blocks,
+79–142 ALMs, ~+150 registers). Snapshot before the edit: `scratchpad/m68ksv_foldfix_start_snapshot/`; work files:
`scratchpad/ff/`. Quartus was not run (rule); the user's compile is the measurement.

**What survived and why.** Quartus 17 treats a register that is never loaded (`if (IS020 && ...)` with IS020 = 0) as
a net with no driver, value 0 (map report, warning 10030: `mul_la`, `mul_lb`, `bf_*`, `dl_*`, `c2_*q`). It still
infers the multiplier `mul_la * mul_lb` and does not fold constants through it (`Mult1`, three DSP blocks). In the
sixth session nothing read `mul_lp` outside `if (IS020)` code, so the multiplier had no fanout and was removed. Since
4b, the flag-term registers load on every e3 without an `IS020` gate (`q_mn` / `q_mz` / `q_mlv` from `mul_lp`, `q_bfn`
from `xa_q[bf_w1q]`), and the term-index mux that reads them cannot be proved never to select them. The
registered product `mul_lp` (64 FFs in fabric: the fitter's DSP table shows no output register for `Mult1`), the
multiplier and those terms therefore stayed. yosys hid this: it treats undriven nets as don't-care and folds the 0 × 0
product, so the 4b yosys table showed 1 DSP.

To reproduce the Quartus behaviour without Quartus, I wrote a "Quartus-like" yosys variant (`ff/ysq1.sh`): undriven nets and
FF power-up values set to 0, and every multiplier mapped to an opaque black box. Otherwise it is the same
`synth_intel_alm`. It matches the regression: 68000 sixth session 1 multiplier / 1,222 FF, before this fix
**2 multipliers / 1,353 FF**. The FF difference by name: `mul_lp` 64 plus one more term register on each of N, Z and V.
Register-by-register (68000 Quartus-like, before → sixth session): `mul_lp` +64, the MUL.L / bit-field terms +3, the
rest identical to the standard yosys difference (4b's flag change, below). Quartus also counts registers differently
(1,334 for the sixth-session 68000), so its +167 is not expected to match exactly.

**What changed** (`rtl/m68ksv_eu.sv` only, plus the regenerated `rtl/m68ksv_all.sv`):

1. **MUL.L in a generate block.** `if (IS020) begin : g_mull` holds `mul_la` / `mul_lb` and the multiplier; the
   `else` branch ties `mul_lp` to 0. The non-020 builds elaborate one `$mul` instead of two, so there is no
   multiplier for Quartus to keep.
2. **Flag terms gated by the CPUs that can select them.** The term vectors take `IS020 & q_mn` / `q_bfn` / `q_mz` /
   `q_bfz` / `q_c2z` / `q_mlv` / `q_c2c` and `IS010 & q_chk010`. The index decode yields N 8 9, Z 8 9 10, V 9, C 8 only
   under `if (IS020)`, and N 5 only when IS010; I enumerated every index assignment to check this. The term registers
   then have no reader and are removed.
3. **Result mux.** Sources 2 (PACK / UNPK) and 1 (EU results: EXTB, MUL.L, DIV.L, bit fields) read as source 0 unless
   IS020. Outside the 68020, `rsrc_q` is never 2 or 1, because `xsel_d` is 0. This removes the 020 result logic
   without relying on the tool proving `rsrc_q` constant.

All three are constant-folded at elaboration: identical logic in the 68020 builds and no change on any CPU's
behaviour (A/B below). Tried and dropped: also gating the 68000-family DIVZ terms `q_xb31` / `q_xbhiz` with
`!IS010` in the 68010 / 68020 builds. It saves 0–2 FFs and makes the 68020 logic differ from the old.

**yosys** (`verify/tools/yosys.sh`'s commands, all on runs made here; 6th = `m68ksv_cp4b_start_snapshot`,
before = fold-fix start snapshot, after = final RTL; DSP = MISTRAL_MUL cells; depth = `depth.py` LUT levels; flag =
deepest flag-term / term-index / `hold_xvc` endpoint, SR = deepest `sr` / `dbg_sr` endpoint):

| CPU | FF 6th / before / after | DSP | LUTs 6th / before / after | deepest 6th / before / after | flag 6th / before / after | SR | Quartus-like FF 6th / before / after | multipliers 6th / before / after |
|---|---|---|---|---|---|---|---|---|
| 68000 | 1,222 / 1,286 / **1,285** | 1 / 1 / 1 | 3,046 / 3,076 / 3,099 | 11.0 / 10.0 / 10.0 | 10.0 / 6.3 / 6.3 | 7.0 / 7.0 / 7.0 | 1,222 / 1,353 / **1,285** | 1 / **2** / **1** |
| 68008 | 1,230 / 1,294 / **1,293** | 1 / 1 / 1 | 3,055 / 3,095 / 3,083 | 11.0 / 10.0 / 10.0 | 10.0 / 6.3 / 6.3 | 7.0 / 7.0 / 7.0 | 1,230 / 1,361 / **1,293** | 1 / 2 / 1 |
| 68008FN | 1,231 / 1,295 / **1,294** | 1 / 1 / 1 | 3,046 / 3,119 / 3,060 | 12.0 / 10.0 / 10.0 | 10.0 / 6.3 / 6.3 | 8.0 / 7.0 / 7.0 | 1,231 / 1,362 / **1,294** | 1 / 2 / 1 |
| 68EC000 | 1,232 / 1,296 / **1,295** | 1 / 1 / 1 | 3,069 / 3,085 / 3,099 | 11.0 / 10.0 / 10.0 | 9.0 / 6.3 / 6.3 | 7.0 / 7.0 / 7.0 | 1,232 / 1,363 / **1,295** | 1 / 2 / 1 |
| 68010 | 1,550 / 1,611 / **1,611** | 1 / 1 / 1 | 3,922 / 4,036 / 4,011 | 11.0 / 10.0 / 10.0 | 9.0 / 7.0 / 7.0 | 7.0 / 7.0 / 7.0 | 1,550 / 1,646 / **1,611** | 1 / 2 / 1 |
| 68020 | 2,317 / 2,540 / 2,540 | 5 / 5 / 5 | 6,296 / 6,591 / 6,604 | 15.0 / 12.0 / 13.0 (cache tag) | 11.3 / 8.0 / 8.0 | 7.0 / 7.0 / 7.0 | 2,317 / 2,540 / 2,540 | 2 / 2 / 2 |
| 68EC020 | 2,309 / 2,532 / 2,532 | 5 / 5 / 5 | 6,314 / 6,585 / 6,542 | 15.0 / 12.0 / 14.0 (cache tag) | 12.0 / 7.0 / 7.0 | 7.0 / 7.0 / 7.0 | 2,309 / 2,532 / 2,532 | 2 / 2 / 2 |

- **DSP: 1 on every non-020 CPU, in both models.** In the Quartus-like model the MUL.L multiplier is gone and the FF
  count drops by 68 (68000) / 35 (68010) to the standard-yosys figure.
- **FF vs the sixth session: +63 (68000 family), +61 (68010)**: all of it 4b's flag change, which applies to every CPU.
  By name (68000):
  - term registers: X 3, N 6, Z 7, V 7, C 8 = 31 (adder / BCD / shifter / bit / TAS / CHK / MOVE.l / DIVZ terms, SR and
    held-flag copies);
  - term indices `q_xi`/`q_ni`/`q_zi`/`q_vi`/`q_ci` 19, held indices `q_hx`/`q_hv`/`q_hc` 10;
  - e2 adder / ALU controls `ad_fsz_q` 2, `ad_ysw_q` 1, `alu.cin` 1, `alu.cond` 1, `alu.sz` 2 (−2: `ad_addr_q`,
    `ad_cmpa_q` gone);
  - `hold_ld` 1, `rsrc_q` 1;
  - −5: the old `ccr_q` / `ccr_f`;
  - +1 net in mapper-named FFs.

  The 68010 has the same list with N 6 / Z 6, indices 17 and `ad_ysb_q` +1. None of these is 68020-only. The one term
  that was unreachable on the 68000 family, `q_chk010`, is now gone (N 7 → 6).
- **Depth: no flag, SR, EU or 68000-family path grew.** The 68020 / 68EC020 "deepest" moved 12.0 → 13.0 / 14.0 on the
  **BIU32 cache-tag compare** (`c_mem` → BIU32 register), a module this fix does not touch. The 68020 logic is
  unchanged: FF identical, A/B 0 mismatches. The EU's deepest endpoint went 12.0 → 11.1 (68020) and 11.1 → 12.0
  (68EC020). This is abc mapping variation: I probed it with functionally identical forms of the same RTL, and 4b
  reported this path at 12–14 across its own runs.

| Probe (yosys deepest, 68020 / 68EC020) | Result |
|---|---|
| fold-fix start RTL + one comment line (line numbers only) | 12.0 / 12.0 (unchanged) |
| final RTL, multiplier without the generate block (two forms) | 11.1 / 13.0 |
| final RTL with `mul_la` / `mul_lb` at module scope, or without the result-mux edit | 13.0 / 14.0 |
| final RTL | 13.0 / 14.0 |

I kept the generate form: it removes the multiplier in every tool, independent of fanout analysis. Quartus's own
timing on the 68020 / 68EC020 cache path decides; it was not in the 4b worst-3 lists.

**A/B** (old = fold-fix start snapshot, new = final RTL; clock-exact on every output each clock; 3 seeds × 4 runs ×
4,000,000 clocks per row, as 4b; `ff/abfin.sh`):

| Configuration | Instruction boundaries | BERR injected | Mismatching runs |
|---|---|---|---|
| 68000 | 1,121,208 | 3,176 | **0** |
| 68008 | 593,918 | 3,410 | **0** |
| 68008FN | 553,569 | 3,416 | **0** |
| 68EC000 16-bit / 8-bit | 1,121,208 / 625,970 | 3,176 / 3,493 | **0 / 0** |
| 68010 (73,194 loop-mode words, 1,457 software-completed RTE) | 982,951 | 3,423 | **0** |
| 68020 (12,276 CPU-space cycles) | 535,740 | 2,124 | **0** |
| 68EC020 | 535,740 | 2,124 | **0** |

The 68020 rows run with `ab20 -mingap 1` (CPU clock ≤ clk / 4). The 4b RTL needs two clk or more between 68020 edges
(decision 3), and with the default `-mingap 0` both builds execute 0 instructions. 4b's 68020 A/B was against the
timing snapshot, before that change. Controls: a copy with the MUL.L N term and the 68000 DIVZ N term forced to 0 fails
(68020: 2 of 4 runs; 68000: 3 of 4 runs).

**Regression (final RTL):**

| Gate | Result |
|---|---|
| `run_all.sh` | pure 794,139 / 794,139 on every column; corrected 202,181 / 202,182; gap 0–3, smoke 3 / 3, retry 8 / 8; summary identical to 4b |
| `mus010` seeds 41 / 42 / 43 / 44, 21 `-cyc`; `rerun010` (7 seeds); `loop010` | outputs byte-identical to 4b; 0 mismatching runs |
| `mus020` (13 rows) | outputs byte-identical to 4b; 0 mismatching runs (19,096,820 clocks) |
| `dsz020` (also `-w 0`), `cache020`, `rmc020`, `cop020` (68020 and 68EC020) | 48 / 48 (168 cycles, 168 timed), 28 / 28, 8 / 8 × 9 sequences, 7 / 7 × 3 wait settings; byte-identical to 4b |
| `rerun020` | byte-identical to 4b (still 6 / 12 and 5 / 12 mismatching runs, the open item above) |
| Verilator 4.204 `--lint-only -Wall` | 0 errors: CPU 68000 / 68008 / 68009 / 68001 / 68010 (79 warnings each), 68020 / 68021 (77); `m68ksv_qtop` with all seven macros (103 / 99): same counts as 4b |
| `verify/tools/mkall.sh` check | identical to the start apart from line numbers (no new loop, cast, pattern, `inside`, expression bit-select or `for (genvar`) |
| Generated files | `m68ksv_upkg.sv`, `m68ksv_urom.sv`, `m68ksv_drom.sv`, `m68ksv_ualabels.h` byte-identical to the start (generators not edited) |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/*.sv` / `.qip` |

Not run: MAME m68008 lockstep, fx68k lockstep, `run_family.sh`, 68000 suite on the 68010 / 68020 builds. The 68000
family and the 68010 are covered by the clock-exact A/B above.

**Files changed:** `rtl/m68ksv_eu.sv`, `rtl/m68ksv_all.sv` (regenerated), `DESIGN.md` (MUL.L generate, term gating
note), this report. Unchanged: `syn/quartus/files.qip`, every `.qsf` / `.qpf`, `syn/quartus/m68ksv_qtop.sv`,
`fleet_types.svh`, generators, vendor files.

**Compile** (from `syn/quartus`, the tree's `rtl/m68ksv_all.sv` is current). Expected: 1 DSP block on the 68000-family
and 68010 revisions, and ALMs / registers back near the sixth-session figures plus the 4b flag registers.

```bash
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

#### Measured Quartus results after the fold-away fix (user's compiles 2026-11-16 13:51–14:30)

| Revision | ALMs (4b → now; sixth session) | Registers (4b → now) | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|
| 68020 | 4,128 → 4,128 (4,026) | 2,597 → 2,597 | 4 | 111.72 / 109.90 MHz | +1.466 / +1.318 ns | +0.083 ns |
| 68EC020 | 4,099 → 4,099 (4,024) | 2,574 → 2,574 | 4 | 111.48 / 107.71 MHz | +1.447 / +1.133 ns | +0.213 ns |
| 68010 | 2,505 → **2,482** (2,426) | 1,865 → 1,768 | **1** | 115.01 / 108.50 MHz | +1.722 / +1.200 ns | +0.297 ns |
| 68000 | 1,926 → **1,869** (1,815) | 1,501 → 1,374 | **1** | 106.38 / 112.16 MHz | +1.017 / +1.501 ns | +0.321 ns |
| 68008 | 1,930 → **1,879** (1,788) | 1,488 → 1,407 | **1** | 115.43 / 117.22 MHz | +1.754 / +1.886 ns | +0.323 ns |
| 68008FN | 1,916 → **1,918** (1,814) | 1,517 → 1,400 | **1** | 107.94 / 112.42 MHz | +1.153 / +1.522 ns | +0.242 ns |
| 68EC000 | 1,927 → **1,901** (1,816) | 1,501 → 1,398 | **1** | 107.10 / 109.35 MHz | +1.080 / +1.272 ns | +0.323 ns |

- **The fix worked: 1 DSP block on every non-020 revision again,** and ~100–130 fewer registers than 4b.
- **The 68020 / 68EC020 results are identical to 4b,** to the ALM, register and ps. That fits the fix folding to the same
  logic in the 020 builds.
- **The remaining growth over the sixth session** (+54 to +104 ALMs, about +40 to +70 registers on the 68000 family
  and the 68010) is 4b's flag-timing registers, which every CPU uses (fold-away subsection above). It is a deliberate
  timing-for-area trade, and checkpoint 5's area pass can look at it again.
- **Timing:** every revision ≥ 106 MHz. No flag path is in any revision's worst 2.
  - The 68000's worst is `cen_p` → `ad_fsz_q` / `xa_q`, 2 levels: routing from the test top's clock enable.
  - The 68EC000's worst is `mask` → `int_lvl`, 7 levels.

## Checkpoint 5 (area, 68020 timing, handover) — eighth session, 2026-11-16

### Summary

- **Part 1, area, behaviour unchanged.** Quartus cannot fold logic through M10K ROM contents, so a decode of a
  micro-word code that a CPU's ROM set never contains still cost logic. The generator now emits per-set "code occurs"
  masks and the EU gates those decodes. Also: the N / Z flag collapse, two 1-bit replacements for 68000 address-error
  state, the 68010 loop table moved to M10K, a few merges. yosys (Quartus-like flow) LUT + carry cells **−4.7 % to
  −9.7 %**, FF −117 to −137 on every CPU; worst logic depth unchanged. Proved clock-exact by the A/B tool on all seven
  configurations (0 mismatching runs; a deliberately wrong control fails). Estimated Quartus ALMs (not measured):
  68000 ≈ 1,730, 68008 ≈ 1,784, 68008FN ≈ 1,802, 68EC000 ≈ 1,758 (all at or below the sixth session), 68010 ≈ 2,227
  (target 2,200: **probably just missed**), 68020 ≈ 3,881, 68EC020 ≈ 3,800.
- **Part 2, 68020 against the MC68020 User's Manual** (`docs/MC68020UM.pdf`; page numbers below are the manual's own).
  Every 4 / 4b `#unverified` bus item checked. Fixed: STERM removed (the MC68020 has no STERM pin, Table 3-2 p. 3-8;
  every cycle is asynchronous now), a read's DBEN at S2 (was S1), the write data at S2 (was a quarter clock after S0),
  a write's DS at S3 (was S2), BERR priority over DSACK / AVEC and the late bus error (BERR one clock after DSACK,
  Table 5-8 case 4), the 68EC020's missing pins (ECS / OCS / DBEN / IPEND negated, BGACK ignored), the null
  coprocessor primitive decode. Confirmed: 3-clock cycle, DSACK sampling at the end of S2, data latched at the end of
  S4, negation at S5, sized cycles back to back, cache organisation, RMC sequence, RESET instruction 512 clocks, the
  CPU-space coprocessor register map. Instruction times compared with the manual's tables (new `tim020`).
  **Not done:** long writes as one request (decision 3), instruction-time tuning (decision 4), CALLM / RTM (optional
  item, decision 5).
- **Gates:** every 68000-family / 68010 result identical to the previous session; A/B 0 mismatching runs on the five
  non-020 configurations against the part-1 snapshot; `mus020` 13 rows 0 mismatching runs; directed 020 tests pass
  (with new edge and bus-error checks); `rerun020` 6 of 12 (not worse); lint 0 errors.
- Snapshots: `scratchpad/m68ksv_cp5_start_snapshot/` (start), `scratchpad/m68ksv_cp5_area_snapshot/` (after part 1).

### Area changes (part 1)

Targets were chosen from yosys per-cone LUT counts (plain and Quartus-like: undriven nets 0, multipliers opaque — the
model that reproduced the fold-away regression) and the user's pre-checkpoint-5 fitter report ("Resource Utilization
by Entity": EU 1,596 ALMs / 1,255 registers on the 68000, 2,189 / 1,639 on the 68010, 3,425 / 2,184 on the 68020 plus
BIU32 358 and the cache MLAB 69; 144 / 210 / 290 router-duplicated cells). A change was kept only if yosys went down and
the A/B check passed.

1. **Micro-word code masks** (`emit_umask()` in `m68ksv_ucode.py`; `UM000_*` / `UM010_*` / `UM020_*` in
   `m68ksv_upkg.sv`; `UM_*` in the EU). For fields sq, cd, dw, ad, xa, xb, xd, ms, fx and the drom2 class field ca,
   bit k is set when code k occurs in any word of that ROM set. Gated: MS_LDAEPC (the 68000 frame-PC mux and `pc68`
   fold away on the 010 / 020), SQ_CALL / RET / BODY / RSM, CD_SUP / PD / NSET / SPUR, DW_DTL / DTH / EAVL / EAVH /
   AYL / AYH, FX_FMT8, XA_SP / AX, XB_RYE / RES, XD_RYE, AD_FPC, CA_DY / CCR. Masks count every ROM word, reachable or
   not: a format-8 / B RTE resumes at a micro-address read from memory, so a foreign frame can start any word.
2. **ROM invariants as static checks** (`check()`): no FIN / RSM word with a bus cycle; every bus word (all sets, dead
   words too) has sq NXT / BT / BF and a non-bus successor; fx LI0 never followed by an fh CM word; no x1 SRF word after
   a bus word; the 68000 EXC0 entry straight-line to the FINFO push (negative-tested). With them the format-8
   fault-address mux `s_fa` went (`fa_d` from `ba_q`; a SIMCHECK `$stop` guards the invariant) and so did `q_sr` /
   `q_hold` (copies of SR / held flags).
3. **N / Z flags: one registered bit each.** Fourteen per-term registers (`q_bitz`, `q_tasn`, `q_chkdn`, `q_mvhz`,
   `q_bfn`, `q_c2z`, ...) replaced by `q_nf` / `q_zf`: the term index is decoded at e2 (`nzsel()`), the term chosen
   at e3, the bit-test Z term enters last; `ccr_q` reads the two bits at e0 (the 4b split kept). ALU `f_bitz` =
   `!b[bnum]`. Flag endpoints stay ≤ 7 levels (68020 `q_zf` 8, as before).
4. **68000 address-error state:** `aepc` (32 bits) → `aepc_f` (1 bit: frame PC = fault PC or `pc68`), the IR copy →
   `aeir_n` (1 bit: frame IR = IRN or IR); the 68010 / 020 keep their registers.
5. **68010 loop table to M10K:** the loopable-opcode function (two copies, IRN and IR) became `m68ksv_drom1lp_010`
   (1024 × 9, two read ports), generated from the same Python function (equal over all 65,536 opcodes before the RTL
   copy was deleted). +2 M10K blocks on the 68010.
6. **Merges:** bit-field extract signed / unsigned from one source (`bf_xs` / `bf_xsq` gone); the frame-PC adder
   shared with the prefetch adder (68010 / 020).

Tried and reverted: gating codes that occur only in unreachable words (the A/B check failed on the 68010: a random
format-8 frame resumed in such a word — decision 1), a delayed `ua_res` capture (+FF), sharing the `lbase` SRF adder
(68010 worse). Not attempted (for later): a bit-field unit redesign (~900 yosys LUTs on the 68020: `bf_iq` 274,
`bf_flq` 251, `bf_mq` 181, `bf_xuq` 120), `dw_spec` mux restructuring, tying constant micro-word bits (only four).

### yosys (yosys 0.66 `synth_intel_alm -family cyclonev`; start = start snapshot, part 1 = area snapshot, final = final RTL; LUT = ALUT2–6, carry = ALUT_ARITH; an estimate, not Quartus)

Quartus-like (`scratchpad/cp5/ysq1.sh`: undriven nets 0, multipliers opaque):

| CPU | LUT start / part 1 / final | carry start / final | LUT + carry Δ | FF start / final | M10K | DSP | deepest (levels) start / final |
|---|---|---|---|---|---|---|---|
| 68000 | 3,090 / 2,846 / 2,846 | 448 / 449 | −243 (−6.9 %) | 1,285 / 1,168 | 30 | 1 | 10.0 / 10.0 |
| 68008 | 3,083 / 2,916 / 2,916 | 448 / 449 | −166 (−4.7 %) | 1,293 / 1,176 | 30 | 1 | 10.0 / 10.0 |
| 68008FN | 3,101 / 2,896 / 2,896 | 448 / 449 | −204 (−5.7 %) | 1,294 / 1,177 | 30 | 1 | 10.0 / 10.0 |
| 68EC000 | 3,108 / 2,858 / 2,858 | 449 / 448 | −251 (−7.1 %) | 1,295 / 1,178 | 30 | 1 | 10.0 / 10.0 |
| 68010 | 4,019 / 3,660 / 3,660 | 591 / 502 | −448 (−9.7 %) | 1,611 / 1,483 | 34 → 36 | 1 | 10.0 / 10.05 |
| 68020 | 6,576 / 6,209 / 6,201 | 1,068 / 1,009 | −434 (−5.7 %) | 2,540 / 2,407 | 39 | 2 | 14.0 / 13.0 |
| 68EC020 | 6,582 / 6,175 / 6,118 | 1,060 / 999 | −525 (−6.9 %) | 2,532 / 2,395 | 39 | 2 | 12.0 / 12.0 |

Plain yosys (the `verify/tools/yosys.sh` commands, `scratchpad/cp5/ys1.sh`), LUT + carry start → final: 68000 3,548 →
3,291; 68008 3,532 → 3,339; 68008FN 3,508 → 3,345; 68EC000 3,547 → 3,353; 68010 4,602 → 4,199; 68020 7,833 → 7,300;
68EC020 7,767 → 7,309. Part 2 (final vs part 1) changed only the 68020 / 68EC020 (BIU32): −3 / −54 Quartus-like.

**Depth / slack.** The worst endpoints are the same kind and depth as at the start (68000 family / 68010: `q_exc`, the
register-file MLAB address, ALU operand, ~10 levels; 68020 / 68EC020: cache tag / BIU32 and the bit-field stage,
12–13). The start RTL compiled at +1.017 to +1.754 ns worst slack (68000 family / 68010) and +1.318 / +1.133 ns
(68020 / 68EC020). No path got deeper, so the estimate is ≥ +1.0 ns on every revision — from logic depth only.

**Quartus estimate** (start ALMs − Δ(LUT + carry) × 0.57, the 0.81 Quartus / yosys ALUT and 0.70 ALM / ALUT ratios of
earlier compiles; error ~±40 ALMs): 68000 1,869 → ≈ 1,730; 68008 1,879 → ≈ 1,784; 68008FN 1,918 → ≈ 1,802; 68EC000
1,901 → ≈ 1,758; 68010 2,482 → ≈ 2,227; 68020 4,128 → ≈ 3,881; 68EC020 4,099 → ≈ 3,800. Targets: 68000 family ≤ the
sixth session (1,815 / 1,788 / 1,814 / 1,816) — met on the estimate (68008 by 4, inside the error); 68010 ≤ 2,200 —
**probably missed by ~25**; fx68k is 2,047 ALMs, the 68000 family ~250–320 below it.

### A/B equivalence (clock-exact: every output every clock, plus registers at each instruction boundary)

Tool `scratchpad/cp5/ab/` (the 4b tool; `ab20` gained `-snip 16`, a bit-field snippet mix) driven by
`scratchpad/cp5/abrun.sh`: per configuration 3 seeds × 4 runs × 4,000,000 clocks of random suite instructions with bus
errors, interrupts and waits; the 020 rows with `-mingap 1`, plus `-bf` rows (seeds 4, 5, `-mix 40 -snip 16`, 2 × 4 ×
4,000,000 clocks).

| Configuration | Part 1 (start → area snapshot): boundaries / BERR / mismatching runs | Part 2 (area snapshot → final) |
|---|---|---|
| 68000 | 1,121,208 / 3,176 / **0** | **0** (same counts) |
| 68008 | 593,918 / 3,410 / **0** | **0** |
| 68008FN | 553,569 / 3,416 / **0** | **0** |
| 68EC000 16-bit | 1,121,208 / 3,176 / **0** | **0** |
| 68EC000 8-bit | 625,970 / 3,493 / **0** | **0** |
| 68010 | 982,951 / 3,423 / **0** (73,194 loop words, 1,457 software RTE) | **0** |
| 68020 / 68EC020 | 535,740 / 2,124 / **0** each (12,276 CPU-space cycles) | differ from the first bus cycle (intended: bus edges changed) |
| 68020 / 68EC020 `-bf` | 429,329 / 1,754 / **0** each (7,914 CPU-space cycles) | differ (as above) |

Control: the tool on a scratch copy with one deliberate fault (TAS N term index wrong, tagged
`DIAG-REVERT-2026-11-16`) fails 3 of 4 runs on the first seed (68000). The tool also caught the one non-exact change
(decision 1).

### 68020 bus timing against the User's Manual (part 2)

| Item (4 / 4b status) | Manual | m68ksv now | Status |
|---|---|---|---|
| Synchronous cycle, STERM (`#unverified`) | no STERM on the MC68020 / EC020 (signal list Table 3-2, p. 3-8); minimum cycle 3 clocks, asynchronous (5.2.6 / 5.2.7 p. 5-24) | `STERM_n` ignored (port kept), every cycle asynchronous | **fixed** |
| Asynchronous cycle, no wait | 3 clocks; DSACK recognised at the falling edge ending S2, data latched at the falling edge ending S4 (5.2.6 p. 5-24; read states 5.3.1 p. 5-31 / 5-32) | same (`dsz020 -w 0`: AS 2 clocks, cycle 3) | verified |
| AS, read DS | at S1, half a clock after the cycle start (5.1.3, 5.1.5 p. 5-3 / 5-4) | same | verified |
| Write DS (`#unverified`) | one clock after AS, S3 (5.1.5 p. 5-4; write states 5.3.2 p. 5-38) | S3 (was S2) | **fixed** |
| Write data | driven at S2, half a clock after AS (5.1.4 p. 5-4, 5.3.2) | S2 (was a quarter clock after S0) | **fixed** |
| DBEN | read: S2 until DS negates; write: with AS for the whole cycle, may stay low between writes (5.1.6 p. 5-4; AC table note 5, p. 10-10) | same (was S1 for reads) | **fixed** |
| ECS / OCS (approximate) | at S0 for half a clock (5.1.1 p. 5-2) | from a quarter clock after S0 to S1 | approximate (decision 7) |
| Negation | AS, DS, DBEN negated at S5; address held through S5 (5.3.1 p. 5-32) | same | verified |
| Dynamic sizing, next cycle | the next cycle's S0 follows S5 (5.3.1) | next rising edge, back to back | verified |
| BERR vs DSACK / AVEC | BERR takes precedence (5.5.1 p. 5-55); Table 5-8 cases 3 / 4 (p. 5-54); late BERR sampled at the falling edge after DSACK is recognised (p. 5-56) | BERR with DSACK / AVEC = bus error (an IACK with AVEC + BERR was an autovector before); BERR at the latching edge = late bus error | **fixed** (new `dsz020 -be 3 / -be 4`) |
| Retry (BERR + HALT) | re-run once HALT negates (cases 5 / 6) | case 5 as before; case 6 (late BERR + HALT) taken as a bus error | case 6 approximate (decision 6) |
| RMC / read-modify-write | RMC from S0 of the first read to the end of the last write; AS negated between; no grant (5.3.3 p. 5-39..5-44) | same (`rmc020`) | verified |
| RESET instruction (`#unverified`) | RESET driven 512 clocks (5.8, Figure 5-52, p. 5-77 / 5-78) | 512 | verified |
| 68EC020 pins | no ECS, OCS, DBEN, IPEND, BGACK (Table 3-2); two-wire arbitration (5.7.2 p. 5-70) | those outputs constant high, BGACK ignored | **fixed** |
| Instruction cache | 64 long-word entries, index A7–A2, tag A31–A8 + FC2 (4.1 p. 4-1 / 4-2) | same | verified |
| Coprocessor CPU-space map | Cp-ID on A15–A13; response $00, control $02, save $04, restore $06, operation word $08, command $0A, condition $0E, operand $10 (Figures 7-4 / 7-5, p. 7-6) | same | verified |
| Null / busy primitives | null = CA PC 0 0 1 0 0 IA 0..0 PF TF (7.4.4 p. 7-31, Table 7-3 p. 7-32); busy = 1 PC 1 0 0 1 0 0 0..0 (7.4.3 p. 7-30) | null decoded on bits 13–9 (IA ignored: re-read at once, no interrupt window); busy on bits 12–8 | **fixed** (was bits 12–8 = 01000: IA = 1 gave a protocol violation) |
| Long operand write | one request, split by the bus controller | two word requests | approximate (decision 3) |

Harness changes the manual forced (old behaviour wrong): `mus020`, `dsz020`, `cache020`, `rmc020`, `rerun020` — port
type 3 was STERM, now a second 32-bit DSACK port (the four port types stay); `dsz020 -w 0` also checks the DS and DBEN
edges (68EC020: DBEN must stay high); `dsz020 -be 3` / `-be 4` check a bus error with DSACK and a late bus error on
every port / size / offset (the handler must run, the store must not); `cop020` uses the manual's busy ($A400) and,
for "a primitive m68ksv does not implement", take-preinstruction-exception ($1C30) instead of $8900 (a valid null
with IA). Controls: the new `dsz020 -w 0` and `-be` checks fail 48 / 48 each on the area-snapshot RTL.

### Instruction timing against the manual's tables (`tim020`, new)

Definition: the manual's tables (8.2 p. 8-9) assume long-aligned operands, a 32-bit bus and no wait states; **cache
case (CC)** = instruction in the cache, no overlap; **worst case (WC)** = cache disabled, no overlap. Best case needs
overlap with neighbouring instructions, which m68ksv does not do: not compared. `tim020` runs eight copies of each
instruction in a loop (32-bit DSACK port, no waits) with CACR = 1 (CC, second pass) and CACR = 0 (WC) and takes the
mean time per copy (a one-word instruction alternates between a copy that fetches the next long and one that does
not). Expected: MOVE from 8.2.6 (p. 8-20..8-28, complete); others the table entry plus the 8.2.1 fetch-EA time where
the table's footnote asks. 68020 and 68EC020 measure the same.

| Instruction | Manual table | CC m68ksv / manual | WC m68ksv / manual |
|---|---|---|---|
| NOP | 8.2.16 | 2.0/2 | 2.5/3 |
| MOVEQ #1,D1 | 8.2.9 | 2.0/2 | 2.5/3 |
| MOVE.L D1,D2 | 8.2.6 | 2.0/2 | 2.5/3 |
| MOVE.L (A0),D1 | 8.2.6 | 7.0/6 | 8.0/7 |
| MOVE.L (A0)+,D1 | 8.2.6 | 7.0/6 | 8.0/7 |
| MOVE.L -(A0),D1 | 8.2.6 | 8.0/7 | 9.0/8 |
| MOVE.L (16,A0),D1 | 8.2.6 | 9.0/7 | 11.0/9 |
| MOVE.L (xxx).L,D1 | 8.2.6 | 11.0/6 | 13.0/10 |
| MOVE.W #imm,D1 | 8.2.6 | 4.0/4 | 5.0/3 |
| MOVE.L #imm,D1 | 8.2.6 | 6.0/6 | 7.5/5 |
| MOVE.L D1,(A1) | 8.2.6 | 8.0/4 | 9.0/5 |
| MOVE.L D1,(A1)+ | 8.2.6 | 8.0/4 | 9.0/5 |
| MOVE.L D1,-(A1) | 8.2.6 | 9.0/5 | 10.0/6 |
| MOVE.L D1,(16,A1) | 8.2.6 | 10.0/5 | 12.0/7 |
| MOVE.L D1,(xxx).L | 8.2.6 | 12.0/6 | 14.0/9 |
| MOVE.W D1,(A1) | 8.2.6 | 5.0/4 | 6.0/5 |
| MOVE.L (A0),(A1) | 8.2.6 | 13.0/7 | 14.0/9 |
| MOVE.L (A0)+,(A1)+ | 8.2.6 | 13.0/7 | 14.0/9 |
| ADD.L D1,D2 | 8.2.8 | 3.0/2 | 3.5/3 |
| ADD.L (A0),D2 | 8.2.8 + 8.2.1 | 8.0/6 | 9.0/7 |
| ADD.L D2,(A1) | 8.2.8 + 8.2.1 | 13.0/8 | 14.0/10 |
| CMP.L D1,D2 | 8.2.8 | 3.0/2 | 3.5/3 |
| ADDQ.L #1,D1 | 8.2.9 | 4.0/2 | 4.5/3 |
| CLR.L D1 | 8.2.11 | 3.0/2 | 3.5/3 |
| NEG.L D1 | 8.2.11 | 3.0/2 | 3.5/3 |
| TST.L D1 | 8.2.11 | 2.0/2 | 2.5/3 |
| EXT.L D1 | 8.2.11 | 2.0/4 | 2.5/4 |
| ST D1 | 8.2.11 | 2.0/4 | 2.5/4 |
| LSL.L #1,D1 | 8.2.12 | 5.0/4 | 5.5/4 |
| LSL.L D3,D1 | 8.2.12 | 5.0/6 | 5.5/6 |
| ASR.L #1,D1 | 8.2.12 | 5.0/6 | 5.5/6 |
| ROL.L #1,D1 | 8.2.12 | 5.0/8 | 5.5/8 |
| BTST #3,D1 | 8.2.13 | 5.0/4 | 6.0/5 |
| BSET D3,D1 | 8.2.13 | 3.0/4 | 3.5/5 |
| BEQ.S (not taken) | 8.2.15 | 3.0/4 | 3.5/5 |
| BRA.S (taken) | 8.2.15 | 6.0/6 | 7.0/9 |
| DBF D4 (taken) | 8.2.15 | 5.0/6 | 6.0/9 |
| MULU.W D1,D2 | 8.2.8 | 20.0/27 | 20.5/28 |
| DIVU.W D1,D2 | 8.2.8 | 67.0/44 | 67.5/44 |
| LINK.W A6,#-8 | 8.2.16 | 10.0/5 | 12.0/7 |

Totals: 40 instructions; equal (mean within 0.5 clock) **7 CC, 0 WC**; within 2 clocks 27 CC / 25 WC; mean difference
m68ksv − manual **+1.75 CC, +1.55 WC** clocks. Slower: every long write is two word requests (+3 to +4 clocks per long
write: `MOVE.L D1,(A1)` 8 / 4 CC), a memory read costs one clock more than the manual's, and the 68000's idle
micro-words remain in some routines (DIVU.W 67 / 44, LINK). Faster: shifts / rotates (one-cycle barrel shifter, ROL
5 / 8), EXT / Scc, MULU.W (20 / 27, DSP). WC is only 0.5–2 clocks above CC in m68ksv (its long fetch overlaps the
second micro-word) where the manual adds about 1–4. Against Musashi's m68020 table (its cache-case figures, `mus020
-cyc`, row c55): **4,307 of 79,848** instruction times equal — unchanged by part 2 (the bus fixes move edges inside a
cycle, not cycle counts).

### Gates (final RTL)

All runs on the final RTL (`scratchpad/cp5/gates.sh`, `fx.sh`, `m20table.sh`; builds one after the other, then the
runs). "Identical" = output files byte-identical (suite bodies: same per-file lines) to the previous session's run.

| Gate | Result |
|---|---|
| 68000 suite (`run_all.sh` commands) | 794,139 / 794,139 pure on every column; corrected 202,181 / 202,182; timed 797,878 — identical |
| idle clocks 0–3, smoke, retry | 794,139, bus order 797,878, corrected 202,181; 3 / 3; 8 / 8 — identical |
| `run_family.sh` commands: 68008 / 68008FN / 68EC000 8 / 16-bit | 794,137 / 794,139 / 794,139 / 794,139, corrected 202,181 each, retry 8 / 8 each — identical |
| MAME m68008 lockstep ×3 (seed 7, 40 × 300,000) | 0 mismatching runs each — identical |
| fx68k lockstep, 20 rows | all 20 outputs byte-identical to the previous session (0 mismatching runs on none / w3 / vpa / halt / ec rows and berr 101, br 101, irq 202; 1–4 of 64 on berr 202, br 202, irq 101, rst, mix: open items, unchanged); built after fixing a debug print in `lockstep.cpp` that named the removed `aepc` |
| `mus010` seeds 41 / 42 / 43 / 44, 21 `-cyc` | 0 mismatching runs; cycles 154,783 / 159,119 equal — identical |
| `rerun010` (7 seeds), `loop010` | 0 mismatching runs, 0 failures — identical |
| 68000 suite on the 68010 build | 781,979 / 794,139 pure, corrected 9,793 — identical |
| A/B vs the start (part 1, all seven configurations + `-bf`) / vs the area snapshot (part 2, five non-020 configurations) | **0 mismatching runs** (A/B table) |
| `mus020`, 13 rows | **0 mismatching runs** on every row (output identical to the run before the final comment edits) |
| `dsz020` (`-w 0` with DS / DBEN edges), `-be 3`, `-be 4`; `cache020` (also `-w 0`) | 48 / 48 (168 cycles, 168 timed), 48 / 48, 48 / 48; 28 / 28 — 68020 and 68EC020 |
| `rmc020`, `cop020` | 8 / 8 configurations × 9 sequences; 7 / 7 steps × 3 wait settings — both builds |
| `tim020` (new) | runs; table above (68020 = 68EC020) |
| `rerun020` | 6 of 12 runs mismatching (`-x020`: 5 of 12) — not worse than before; open |
| 68000 suite on the 68020 / 68EC020 build (`harte -bus32`) | pure 715,598 / 794,139, corrected 7,822 / 202,182; classes address error 178,087, exception frame 16,488, SR 20,002, indexed / scale 53,004, other 5,320 — identical to 4b, both builds |
| Verilator 4.204 `--lint-only -Wall` | 0 errors: CPU 68000 / 68008 / 68009 / 68001 / 68010 (78 warnings each), 68020 / 68021 (77); `m68ksv_qtop` with all seven macros (102 / 99). New vs the area snapshot: one UNUSED (`sterm_n` in `m68ksv_biu32`, intended) |
| `verify/tools/mkall.sh` check | regenerated; no `for (genvar`, no module-level loops, casts, patterns, `inside` (comment hits only) or expression bit-selects; the procedural `for` list unchanged in kind |
| Generated ROMs | `m68ksv_urom.sv` byte-identical to the start; `m68ksv_drom.sv` = the start + the appended `m68ksv_drom1lp_010`; the package gained localparams only |
| Protected / vendor files | `files.qip`, all `.qsf` / `.qpf`, `fleet_types.svh` unchanged; fx68k `fx68k.sv`, `fx68kAlu.sv`, `uaddrPla.sv`, `microrom.mem`, `nanorom.mem` byte-identical to the download (`cmp`); MAME / Musashi source untouched |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/*.sv` (the one tagged control fault lived in a scratch copy only) |

### Decisions taken alone (the user could not be asked)

1. **Masks count every ROM word, not reachable ones.** A format-8 / B RTE can resume at any micro-address taken from
   memory, and random frames do so in the A/B runs; reachability gating is not exact and was removed after the A/B
   check failed on it.
2. **The 68010 target (2,200 ALMs) is probably missed by ~25 (estimate).** Reaching it needs a structural change (the
   68010's RTE / format-8 path or the shared result mux) whose risk did not fit next to part 2. The 68000 family meets
   its target on the estimate.
3. **Long writes stay two word requests.** The EU forms the two halves in different micro-words and drives 16 bits of
   write data (`dout`); a one-request long write needs a 32-bit write path from the EU, and a BIU that merges the two
   requests breaks the format-B re-run (a bus error on the merged cycle is reported on the second request, so RTE would
   re-run only the low word). Cost: +3 to +4 clocks per long write.
4. **Instruction times not tuned.** The gaps are structural (above); closing them means rewriting 020 micro-routines,
   which the A/B and lockstep would have to re-prove. Measured and reported instead (`tim020`).
5. **CALLM / RTM not implemented** (the optional item): still illegal instruction on the 68020; on the 68EC020 that is
   the real chip's behaviour. The manual's timing for them is in 8.2.16 (p. 8-38: CALLM type 0 28 / 30 / 36 clocks).
6. **Late BERR + HALT (case 6) is a bus error, not a retry**, and a late bus error on a sized access's earlier cycle
   ends the access after one internal clock with no further cycle. Recorded as approximate.
7. **ECS / OCS stay a quarter clock after S0** (from e1): the EU loads the address register at e0; asserting them at
   e0 needs the request decoded a micro-cycle earlier.
8. **The `STERM_n` port stays** on `m68ksv`, `m68ksv_fleet` and `fleet_types.svh` (unchanged by rule) and is ignored,
   so no instantiation breaks.

### Open (not done / not verified)

- Every checkpoint-5 Quartus number (the user compiles); the 68010 ALMs vs 2,200.
- 68020: long writes as one request; the instruction-time gaps; CALLM / RTM; coprocessor primitives other than null /
  busy (protocol violation), null IA (interrupt window) and PC (instruction address CIR); late BERR + HALT retry; ECS /
  OCS a quarter clock late; `rerun020` 6 of 12 runs.
- 68000 (unchanged since checkpoint 2): run-ahead during BR / HALT waits; reset mid-instruction register-write timing.

### Files changed / new (eighth session)

- RTL: `rtl/m68ksv_eu.sv` (masks, flags, address-error state, loop table, `s_fa`, merges, null primitive),
  `rtl/m68ksv_alu.sv` (`f_bitz`), `rtl/m68ksv_biu32.sv` (STERM, DBEN / data / DS edges, BERR priority, late bus error,
  comments now cite the manual), `rtl/m68ksv.sv` (68EC020 pins); generator `rtl/gen/m68ksv_ucode.py` (`emit_umask`,
  `check()` rules, `loopable()` and `m68ksv_drom1lp_010`); regenerated `rtl/m68ksv_upkg.sv` (masks only),
  `rtl/m68ksv_drom.sv` (`m68ksv_drom1lp_010` appended, the other modules byte-identical), `rtl/m68ksv_all.sv`;
  `rtl/m68ksv_urom.sv` byte-identical. No new RTL file (mkall list unchanged).
- Verification: `verify/tb/tim020.cpp` (new), `verify/tb/dsz020.cpp` (edge checks, `-be`), `verify/tb/cop020.cpp`,
  `mus020.cpp`, `cache020.cpp`, `rmc020.cpp`, `rerun020.cpp` (port 3), `verify/tb/lockstep.cpp` (a debug print named
  the removed `aepc`), `verify/dsz020_build.sh` (builds `tim020`, passes `-DM68KSV_HCPU`).
- Docs: `README.md`, `REPORT.md` (status, parity table, this section, Handover), `DESIGN.md` (7.2, new 7.3),
  `syn/quartus/README.md`.
- Unchanged: `syn/quartus/files.qip`, every `.qsf` / `.qpf`, `fleet_types.svh`, vendor files (`cmp`, gate table).

### Compile commands (the user; Quartus 17.0, from `syn/quartus/`)

```bash
quartus_sh --flow compile m68ksv_qtop                          # 68000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008     # 68008 (DIP48)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn   # 68008FN
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000   # 68EC000
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010     # 68010
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

## 68020 behaviour from WinUAE (Amiberry run, 2026-11-16)

### Summary

- **The user's decision:** the 68020 / 68EC020 builds follow **WinUAE's 68020 core** (Amiberry fork, source on disk at
  `/Work/Build/amiberry/src/`, read-only) wherever the PRM leaves a result undefined or m68ksv and MAME's Musashi
  disagreed. There is no real 68020 to test on; WinUAE's 68020 undefined-flag tables were derived from real hardware
  (CPUTESTER). **Rule: where a WinUAE comment and its code disagree, the code wins** (the code produced the log).
- **The Amiberry run** of `verify/amiga020` (log `verify/amiga020/m68k020.log`) settled the defined questions in
  m68ksv's favour and disagreed on DIV / CHK flags, DIV.L N / Z, PACK / UNPK with -(A7), LINK A7 and the address-error
  frame. All of those now follow WinUAE's code. The 68000 / 68008 / 68008FN / 68EC000 / 68010 builds are unchanged
  (A/B clock-exact against the start, 0 mismatching runs; their ROM contents byte-identical).
- **New gate:** `verify/tb/amiga020.cpp` (`verify/amiga020_build.sh`): 285 checks per build, 41 with the logged values,
  244 from WinUAE's rules (`verify/tb/winuae020.h`, transcribed from its code): **0 failures** on the 68020 and the
  68EC020 (the start RTL fails 191, 25 of them logged values).
- **Musashi lockstep (`mus020`):** 13 rows, **0 mismatching runs**; the new behaviours are classified Musashi
  differences, counted per class, accepted only when m68ksv's result equals WinUAE's rule computed from the operands.
- **Not changed (survey):** WinUAE's other 68020 rules where m68ksv still differs: DIV.W / DIV.L divide-by-zero flags,
  MUL.L with Dh = Dl, the BCD V flag, the stacked PC / A7 of JSR / DBcc / RTR to an odd address.
- Snapshot of the start: `scratchpad/m68ksv_winuae_start_snapshot/`; progress log `scratchpad/winuae_progress.md`.
- **Superseded the same day (the user's decision): the address-error SSW is back to the MC68020 User's Manual** (RB /
  RC set, $3066; WinUAE's $0066 is now a known, printed difference). **#unverified** - manual versus WinUAE, no real
  68020 to settle it; if evidence shows the choice is wrong, fix it. WinUAE's stacked PC and fault-address placement
  stay. See "SSW back to the manual, CHK2 margin (2026-11-16)" at the end of this section.

### The Amiberry run

Settings (given by the user): **CPU 68020, 24-bit addressing, "more compatible"** (not cycle-exact: WinUAE's table
`op_smalltbl_20`, `cpuemu_20.cpp`), **unimplemented CPU opcodes** (emulated), **MMU off, FPU off, JIT off**, CPU
frequency **14.187580 MHz**, **Kickstart 3.2.3** (exec 47.115 in the log; AttnFlags $0003 = 68020 / 68EC020 without
FPU; the instruction cache emulated, T8a). Not cycle-exact, so the run settles behaviour (flags, frames, cache), not
timing. The label argument was not given ("label: (none given)").

Each test against m68ksv before this change ("start") and Musashi (`scratchpad/amichk`: the same cases on the start RTL
and on Musashi m68020, outputs `out_rtl.txt` / `out_mus.txt`):

| Test | Amiberry (WinUAE) | m68ksv start | Musashi | m68ksv now |
|---|---|---|---|---|
| T1 DIVU.W overflow (8 rows) | V = 1, N set by a negative dividend, X Z C kept | 5 rows differ (N not set, C cleared) | as m68ksv start | all 8 equal |
| T1 DIVS.W overflow (8 rows) | C = 0, V = 1, N / Z from the low byte of the quotient magnitude unless found at the start | 3 rows differ (N / Z kept) | 4 rows differ (also $80000000 / -1: result 0, Z = 1, V = 0) | all 8 equal |
| T1 CHK.W (10 rows) | N = Dn < 0, Z = Dn = 0, V / C when trapping | 6 rows differ | as m68ksv start | all 10 equal |
| T1 CHK.L (6 rows) | as CHK.W on 32 bits | 4 rows differ | as m68ksv start | all 6 equal |
| T2a-c DIV.L 64-bit overflow | N0 Z1 V1 C0 (CCR 00 and 1F before) | N / Z kept (C cleared: agreed) | N / Z kept, C kept | equal |
| T3a / b trace before the TRAP / zero-divide handler | trace first, PC = handler | agreed | no | unchanged |
| T4a / T4d PACK -(A0),-(A7) / UNPK -(A7),-(A0) (one-byte side A7) | A7 by 2 | agreed | agreed | unchanged |
| T4b / T4c PACK -(A7),-(A0) / UNPK -(A0),-(A7) (two-byte side A7) | A7 by 2 in total | A7 by 4 | A7 by 4 | equal (bytes too) |
| T5a / b FSAVE without FPU, user / supervisor | privilege violation / F-line | agreed | F-line / F-line | unchanged |
| T6a-c RTE of format 7 / 9 / 0 | format error / pops 20 bytes / pops 8 | agreed | pops a 68040 frame / format error / pops 8 | unchanged |
| T7 JMP (A1) to an odd address | format B: SR 2700, PC = the JMP + 2, SSW $0066, fault address = data input buffer = the odd target, stage C = the word after the JMP | format B, PC = the JMP, SSW $0116, data input buffer 0 | mostly empty frame (SSW $0100, fault address 0, PC = the target) | equal on all 18 words that are not WinUAE-internal state |
| T8a / b instruction cache, CACR CE | modelled / one entry | agreed | - / whole cache | unchanged |
| T9a-e bit fields | expected values | agreed | agreed | unchanged |
| T10 LINK A7,#-8 | pushes A7 before the decrement | pushed the decremented A7 | as m68ksv start | equal |

### What changed (68020 / 68EC020 only), with the WinUAE source

| Item | WinUAE source (file, function) | m68ksv change |
|---|---|---|
| DIVU.W overflow flags | `newcpu_common.cpp` `setdivuflags` (`cpu_model >= 68020` branch), called from `gencpu.cpp` `i_DIVU` | V = 1; N set when the dividend is negative, else kept; X Z C kept (EU N term 11, C = SR) |
| DIVS.W overflow flags, incl. $80000000 / -1 | `setdivsflags` (>= 68020): `CLEAR_CZNV`, V = 1, return on "absolute overflow" (abs(dividend) >> 16 >= abs(divisor)), else N / Z of `(uae_s8)` (abs(dividend) / abs(divisor)); `i_DIVS` | N / Z terms 12 from the divider's magnitude quotient `dv_q[7:0]`, gated by the early-overflow flag `dv_ov`; C = 0 |
| DIVU.L / DIVS.L overflow flags | `newcpu_common.cpp` `m68k_divl`, `divul_overflow`, `divsl_overflow` (< 68040) | `dlo_n` / `dlo_z` registered at m2 DVLHI (N / Z term 13); V = 1, C = 0 as before |
| CHK.W / CHK.L undefined flags | `newcpu_common.cpp` `setchkundefinedflags` (68020 / 030 branch), `gencpu.cpp` `i_CHK` | N = Dn < 0 always (was: only when trapping), Z = Dn = 0, V / C of the trap test (terms V 11, C 10) |
| CHK2 / CMP2 flags | `gencpu.cpp` `i_CHK2` (bounds sign-extended, the value the sign-extended Dn part or all of An, signed compares, a wrapping range when lower > upper) + `newcpu_common.cpp` `setchk2undefinedflags` (020 / 030) | compare rewritten (was Musashi's "signed only when the lower bound's sign bit is set": C also differed when lower > upper); N / V by the six-case rule (`c2nv`; terms N 14, V 12) |
| PACK / UNPK, two-byte side | `gencpu.cpp` `i_PACK` / `i_UNPK` (`m68k_areg(regs, ...) -= 2`, one word access) | the two-byte side moves any An, A7 too, by 2 (two byte accesses at An - 1 and An - 2 through AT); `PACK20M` one micro-word longer |
| LINK A7 / LINK.L A7 | `gencpu.cpp` `i_LINK` ("smode must be first in case it is A7", `cpu_level` < 4; `cpuemu_20.cpp` `op_4e50_20_ff`) | the 68010 module's `AYLK` patch undone for the 68020: the old A7 is pushed (as the 68000 microcode) |
| Address-error frame | `newcpu.cpp` `Exception_normal` (68020 / 030 "odd PC address error (partially implemented only)": SSW = (S ? 4 : 0) \| FC \| RW \| SIZE_W), `newcpu_common.cpp` `Exception_build_stack_frame` format B (data input buffer = the fault address), `gencpu.cpp` `i_JMP` / `cpuemu_20.cpp` `op_4ed0_20_ff` (`m68k_incpci(2)` before `exception3_read_prefetch_only`) | SSW $0060 \| FC (no FB / RB / RC / DF); +$2C / +$2E = the fault address; a JMP's stacked PC = its address + 2 (`ae_jmp`, `m2 AEPC`); m68ksv's internal words unchanged. **SSW superseded the same day: RB \| RC added per the manual ($3066), #unverified** (subsection "SSW back to the manual") |

**Comment versus code (the code was followed):**
- `setdivuflags`: the comment says "68020: V=1, C=0, Z=0, N=X"; the 68020 code sets V, and N when the dividend is
  negative, and leaves C / Z / N otherwise unchanged. The log agrees with the code (CCR $1F in gives X1 N1 Z1 V1 C1).
- `divbyzero_special` (survey, not changed): the comment says "Signed: Z=1 NC=0. V=? (sometimes random!)"; the code
  clears V too (`CLEAR_CZNV`).
- `divsl_overflow`: its comment "this is still missing condition where Z is set without none of input parameters being
  zero" marks WinUAE's own rule as incomplete; m68ksv follows the code as it is.
- **The brief versus the code (T7):** the brief described the stacked PC as "target with the low bit clear". WinUAE's
  JMP handlers stack the JMP's address + 2 for every JMP mode. In the Amiga test the target directly follows
  `JMP (A1)`, so both readings give the logged value; the code was followed (decision 1). `amiga020` checks the logged
  layout and three far-target JMP modes from the code.
- WinUAE's address-error SSW differs from the MC68020 User's Manual (6.2.1, p. 6-22: an address error sets RB / RC,
  not RW / SIZE); WinUAE's own comment calls the frame "partially implemented only". Covered by the user's choice of
  reference (decision 2) - **superseded: the user put the SSW back to the manual's RB / RC (#unverified, subsection
  "SSW back to the manual")**.

### Survey: WinUAE's other 68020 branches (no change; possible follow-up)

Every `cpu_model >= 68020` / `== 68020` / `cpu_level` 2 branch in WinUAE's CPU core (`newcpu_common.cpp`, `newcpu.cpp`,
`gencpu.cpp`) that affects behaviour, and whether m68ksv's 68020 build matches. The address-error row was measured with a
scratch harness (`scratchpad/winuae/aepc`, odd target $2201).

| WinUAE branch (file, function) | 68020 rule in WinUAE's code | m68ksv 68020 | Follow-up |
|---|---|---|---|
| `newcpu_common.cpp` `divbyzero_special` (68020 / 030) | DIVU.W by zero: N = dividend bit 31, Z = dividend[31:16] = 0, V = 1, C = 0; DIVS.W by zero: Z = 1, N = V = C = 0 (comment: "V=? (sometimes random!)" - the code clears V) | flags unchanged (Musashi) | **differs** |
| `newcpu_common.cpp` `divul_divbyzero` / `divsl_divbyzero` (< 68040) | DIVU.L by zero: N = Dq bit 31, Z = Dq = 0, V = 1, C = 0; DIVS.L by zero: N = 0, Z = 1, C = 0, V kept | flags unchanged (Musashi) | **differs** |
| `newcpu_common.cpp` `m68k_mull` (020 / 030) | MULx.L 64-bit: Dl written first, then Dh: when Dh = Dl the **high** long remains (68040: the reverse) | Dh first, then Dl: the low long remains (Musashi) | **differs** (only Dh = Dl, an undefined case in the PRM) |
| `gencpu.cpp` `i_ABCD` / `i_SBCD` / `i_NBCD` (`xBCD_KEEPS_V_FLAG` = 2) | V = 0 on the 68020 / 030 ("a real 68030 clears V"); N from the result (as the 68000) | V as the 68000 (suite-verified undocumented V) | **differs** (V only) |
| `gencpu.cpp` `i_JSR` / `i_BSR` / `i_Bcc` / `i_DBcc` / `i_RTS` / `i_RTR` / `i_RTD`, odd target (`exception3_read_prefetch*`; `cpuemu_20.cpp`) | stacked PC / A7 per instruction - JSR: the odd target, A7 - 4 without the push; BSR: the BSR's address, A7 - 4; Bcc / BRA: the Bcc's address; DBcc: the odd target (Dn decremented); RTS: the RTS's address, A7 + 4; RTR: the RTR's address **+ 2**, A7 + 6; RTD: the RTD's address, A7 + 4 + d | measured (`scratchpad/winuae/aepc`): stacked PC = the instruction's address for all of them; A7: JSR unchanged, BSR - 4, RTS + 4, RTR + 6, RTD + 4 + d; SSW / fault address / data input buffer as WinUAE (this change) | BSR, Bcc / BRA, RTS, RTD **match**; JSR (PC, A7), DBcc (PC), RTR (PC) **differ** |
| `newcpu.cpp` `Exception_build_stack_frame` format B internal words | +08 / +14 / +28 / +30.. = WinUAE's MMU-030 / pipeline state, +0E stage B = its prefetch word | m68ksv's internal re-run state | not hardware: no change |
| `gencpu.cpp` `i_CHK` + `setchkundefinedflags` (020 / 030) | (this change) | matches | - |
| `gencpu.cpp` `i_CHK2` + `setchk2undefinedflags` (020 / 030) | (this change) | matches | - |
| `newcpu_common.cpp` `setdivuflags` / `setdivsflags` (>= 68020, < 68040) | (this change) | matches | - |
| `newcpu_common.cpp` `divul_overflow` / `divsl_overflow` (< 68040) | (this change; divsl_overflow comment: "still missing condition where Z is set") | matches | - |
| `gencpu.cpp` `i_PACK` / `i_UNPK` | (this change) one word access at An - 2 on the two-byte side | matches in registers / memory; two byte accesses on the bus | bus pattern only |
| `gencpu.cpp` `i_LINK` (`cpu_level` < 4) | (this change) | matches | - |
| `gencpu.cpp` `i_ADDX` / `i_SUBX` / `i_SWAP` / `i_MV2SR` / `i_EORSR` (`cpu_level >= 2`) | order of flag update vs store / prefetch / trace check only - same values | same values | none |
| `newcpu_common.cpp` `Exception_build_stack_frame_common` | format 2 for CHK / CHK2 / TRAPV / TRAPcc / zero divide / trace (nr 5, 6, 7, 9) | same | none |
| `newcpu_common.cpp` `privileged_copro_instruction` | cpSAVE / cpRESTORE in user mode: privilege violation | same (Amiberry T5a) | none |
| `newcpu_common.cpp` `m68k_movec2` / `m68k_move2c` | CACR mask $0F, C / CE cleared after use (`flush_cpu_caches`): read back as 0 | CACR E / F stored, C / CE one-clock pulses | none |
| `newcpu.cpp` `m68k_run_2_020` / `do_trace` T0 (`cpu_model >= 68020`) | T0 traces changes of flow | same set (Musashi's) | not compared in detail |
| `newcpu.cpp` `iack_cycle` (>= 68020) | interrupt vector from the device without the 68000's 4-clock read | m68ksv runs an IACK cycle (bus behaviour) | bus timing only |
| `newcpu.cpp` BKPT ($4848-$484F) | `cs_bkpthang` board option halts | breakpoint cycle + illegal (MC68020 UM) | board option |
| `gencpu.cpp` shifts (`cnt &= 63`), MOVEP, MULU / MULS.W, bit fields, CAS / CAS2 | no CPU-level branch (68000 rules, or defined flags) | same rules (suite / Amiberry T9) | none |

### Gates (final RTL)

| Gate | Result |
|---|---|
| Non-020 builds unchanged: A/B against the start snapshot (`scratchpad/cp5/ab` tool, clock-exact: every output every clock + registers at each boundary; 3 seeds x 4 runs x 4,000,000 clocks per row) | **0 mismatching runs**: 68000 1,121,208 boundaries / 3,176 bus errors; 68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 16-bit 1,121,208 / 3,176; 68EC000 8-bit 625,970 / 3,493; 68010 982,951 / 3,423 (73,194 loop words, 1,457 software RTE) - the same counts as checkpoint 5's run (same stimulus) |
| Generated ROMs | per module: `m68ksv_urom` / `_010`, every `m68ksv_drom*` 68000 / 010 module byte-identical to the start; only `m68ksv_urom_020` and `m68ksv_drom2_020` differ; package: +`FX_DIBH`, +`M2_AEPC`, masks `UM020_XA` (AYLK no longer used) / `UM020_FX` |
| `amiga020` (new), 68020 / 68EC020 | **285 / 285 checks, 0 failures** each (41 logged values, 244 WinUAE-rule rows: DIV.W 48 random + log, CHK 48 random + log, DIV.L 22, PACK / UNPK 4, JMP frames 4, LINK 2, CHK2 / CMP2 120). Control: the start RTL fails 191 (25 of the 41 logged) |
| `mus020`, 13 rows (table below) | **0 mismatching runs on every row**; the new classes counted (table) |
| 68000 suite on the 68020 / 68EC020 build (`harte -bus32`) | pure 714,838 / 794,139 (start 715,598), corrected 9,572 / 202,182 (start 7,822); failing tests by class: address error 178,087 (start 178,087), exception 16,487 (16,488), SR write 20,002 (20,002), indexed / scale 53,005 (53,004), other **22** (5,320), **winuae_ccr 4,308** (new: DIVU / DIVS / CHK.W, only the CCR differs). Every difference classified; LINK A7 now passes (the 68000 also pushes the old A7: corrected LINK 1,005 / 1,005, was 0); "other" 22 = the same Bcc / ADD.l / AND.l / CMP.l / MOVE.b / OR.l tests as before. Both builds identical. (Checkpoint 5's `.tot` totals also summed the `CLS` lines; the per-file lines and the REPORT numbers were right.) |
| `dsz020` (`-w 0`, `-be 3`, `-be 4`), `cache020` (`-w 0`), `rmc020`, `cop020` | output files byte-identical to checkpoint 5 (48 / 48, 168 cycles / 168 timed, 28 / 28, 8 x 9 sequences, 7 steps x 3) - both builds |
| `rerun020` | **6 of 12** runs mismatching (`-x020`: 5 of 12) - the same counts as checkpoint 5 (text differs only in micro-addresses after `PACK20M`) |
| Verilator 4.204 `--lint-only -Wall` | **0 errors**: 68000 / 68008 / 68009 / 68001 / 68010 78 warnings, 68020 / 68021 77; `m68ksv_qtop` with all seven macros 102 / 99 - the same counts as the start (path-normalised warning lists equal) |
| `verify/tools/mkall.sh` check | regenerated; the check output equal to checkpoint 5's apart from line numbers (procedural `for` only, no casts / patterns / `inside` / expression bit-selects / `for (genvar`) |
| yosys (plain `ys1.sh` / Quartus-like `ysq1.sh`), deepest path in LUT levels | 68020: start 12.00 / 13.00 -> now **12.00 / 12.00**; 68EC020: start 13.00 / 12.00 -> now **12.00 / 12.00** (no growth). New logic's deepest: `dlo_n` / `dlo_z` 11.20, `c2_nq` / `c2_vq` 10.25-11.00 |
| yosys size (an estimate, not Quartus) | LUT + carry: 68020 plain 7,300 -> 7,508 (+208), Quartus-like 7,210 -> 7,377 (+167); 68EC020 plain 7,309 -> 7,480 (+171), Quartus-like 7,117 -> 7,287 (+170); FF +8 each. Estimated Quartus (x 0.57): about +95 ALMs (68020 3,949 -> ~4,045; 68EC020 3,951 -> ~4,048) |
| Protected / vendor files | `files.qip`, all `.qsf` / `.qpf`, `fleet_types.svh`, fx68k, MAME / Musashi sources untouched; nothing written under `/Work/Build/amiberry/` |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/*.sv` (the temporary debug prints added to `mus020.cpp` during the run were tagged `DIAG-REVERT-2026-11-16` and removed) |
| Not run this session | Quartus (the user compiles); the 68000 suite / fx68k / MAME m68008 / `mus010` / `rerun010` on the non-020 builds (replaced by the clock-exact A/B against the start); `tim020` (no timing change intended; only PACK memory forms are one clock longer) |

`mus020` rows (8 runs x 10,000 instructions each; class counts = differences accepted because m68ksv equals WinUAE's
rule computed from the operands):

| Row | Setting | mismatching runs | group-0 resyncs start / now | DIV.W ovf | CHK | CHK2 / CMP2 flags | CHK2 trap decision | DIV.L ovf | PACK / UNPK | LINK A7 |
|---|---|---|---|---|---|---|---|---|---|---|
| m51 | 68020, port 0, no snippets | **0** | 95 / 95 | 8 | 38 | 3 | 1 | 1 | 0 | 1 |
| m52 | 68020, mixed ports, snippets | **0** | 138 / 137 | 15 | 71 | 4 | 1 | 0 | 1 | 4 |
| m53 | 68020, + IRQ, waits | **0** | 255 / 1997 | 149 | 184 | 10 | 0 | 0 | 1 | 4 |
| m54 | 68020, + IRQ, waits | **0** | 273 / 263 | 38 | 105 | 7 | 4 | 2 | 1 | 5 |
| m58 | 68020, 8-bit port, waits | **0** | 103 / 103 | 8 | 36 | 3 | 0 | 1 | 0 | 3 |
| c55 | 68020, cycles | **0** | 103 / 102 | 12 | 36 | 2 | 2 | 0 | 2 | 2 |
| e56 | 68EC020, IRQ, waits | **0** | 291 / 293 | 36 | 129 | 56 | 0 | 0 | 2 | 21 |
| e57 | 68EC020, 16-bit port | **0** | 79 / 78 | 29 | 26 | 3 | 1 | 0 | 1 | 1 |
| e59 | 68EC020, IRQ, waits | **0** | 265 / 276 | 30 | 120 | 12 | 2 | 0 | 5 | 225 |
| m60 | 68020, BR / HALT / reset | **0** | 277 / 305 | 41 | 114 | 6 | 2 | 0 | 2 | 4 |
| e61 | 68EC020, BR / HALT / reset | **0** | 266 / 263 | 38 | 4669 | 7 | 1 | 2 | 2 | 7 |
| m62 | 68020, bit fields, IRQ | **0** | 197 / 183 | 24 | 93 | 14 | 2 | 1 | 1 | 16 |
| e63 | 68EC020, bit fields | **0** | 117 / 117 | 14 | 61 | 0 | 1 | 0 | 3 | 6 |

The group-0 resync counts move because runs diverge after the first changed flag (branches go elsewhere). m53's 1,997:
one run's random program overwrote the handler at $404 (both CPUs agree on that write), so its `BRA.W` went to an odd
address over and over (Musashi takes no 68020 address error: resynchronised each time) until the stack left RAM. e61's
4,669 CHK rows: a CHK that traps repeatedly in one run, each instance checked against the rule.

### Decisions taken alone (the user could not be asked)

1. **T7 stacked PC = the JMP's address + 2 (WinUAE's code), not "the target with the low bit clear"** (the brief's
   reading of the log). Both fit the log; the code is the reference by the user's rule. Only JMP changed; the other
   change-of-flow instructions keep m68ksv's stacked PC (WinUAE's per-instruction rules are in the survey).
2. **SSW $0066 as WinUAE, although the User's Manual says RB / RC.** The user chose WinUAE. Consequence: an RTE of an
   unrepaired address-error frame now takes m68ksv's software-completion path (no DF / RB / RC) instead of re-running
   the odd fetch. No harness returns from an address error. **Superseded (the user's decision, same day): SSW = RB |
   RC | RW | SIZE word | FC ($3066) as the manual says, so RTE re-runs the fetch. #unverified** (subsection "SSW
   back to the manual").
3. **WinUAE-internal frame words are not copied** (+$08, +$0E stage B, +$14, +$28: WinUAE's MMU-030 / pipeline state):
   emulator state, not hardware, and m68ksv's re-run state lives in those slots. `amiga020` checks the other 18 of the 24
   logged words.
4. **CHK2 / CMP2: C and Z follow WinUAE too** (the brief named N / V). `i_CHK2` compares signed with a wrapping range,
   which differs from Musashi's rule only for lower > upper (and .B / .W bounds against An); same hardware-derived
   source. Counted separately in `mus020` ("trap decision").
5. **PACK / UNPK keep two byte bus accesses** (WinUAE: one word access); registers and memory are identical.
6. **Survey items not changed** (divide-by-zero flags, MUL.L with Dh = Dl, BCD V, JSR / DBcc / RTR stacked PC): item 7
   of the brief was survey-only.
7. **`mus020` classification** accepts a difference only when m68ksv's result equals WinUAE's rule computed from the
   operands (the previous comparison's registers; a memory operand from Musashi's read log - new in the model shim - or
   the (d16,PC) address directly). The old "DIV.L overflow C" class is kept and now counts 0.
8. **The 68000 suite on the 020 builds** got a sixth class, "winuae_ccr": DIVU / DIVS / CHK.W failures where only the
   CCR differs (classified by kind, not checked against the rule there; `amiga020` and `mus020` check the rule).

### Files changed / new

- RTL: `rtl/m68ksv_eu.sv` (CHK V / C terms, DIVO / DVLO N / Z terms, `dlo_*`, CHK2 compare + `c2nv`, address-error SSW /
  data input buffer / `ae_jmp` / `M2_AEPC`); generator `rtl/gen/m68ksv_ucode.py` (field codes fx `DIBH`, m2 `AEPC`),
  `rtl/gen/m68ksv_ucode020.py` (LINK / LINK.L, PACK / UNPK memory forms, `EXC0_020` +$2C / +$06); regenerated
  `rtl/m68ksv_urom.sv` (only `m68ksv_urom_020` differs), `rtl/m68ksv_drom.sv` (only `m68ksv_drom2_020`),
  `rtl/m68ksv_upkg.sv`, `rtl/m68ksv_all.sv`, `verify/tb/m68ksv_ualabels.h` (020 labels after `PACK20M` move by one).
- Verification: `verify/tb/amiga020.cpp`, `verify/amiga020_build.sh`, `verify/tb/winuae020.h` (new);
  `verify/tb/mus020.cpp` (WinUAE classes), `verify/musashi/musashi_model020.h` / `.cpp` (read log; our shim, not MAME
  code), `verify/tb/harte.cpp` (class 5).
- Docs: `REPORT.md` (status, this section, Handover), `DESIGN.md` (7.2, new 7.4, 8), `README.md`,
  `verify/amiga020/README.md`.
- Unchanged: `syn/quartus/files.qip`, every `.qsf` / `.qpf`, `fleet_types.svh`, the fx68k / MAME / Musashi sources,
  everything under `/Work/Build/amiberry/`.

### Compile commands (the user; Quartus 17.0, from `syn/quartus/`)

```bash
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

The other five revisions are clock-exact against the start (A/B) with identical ROM contents; recompiling them is not
needed for this change.

#### Measured Quartus results (user's compiles 2026-11-16 18:51 / 18:54; `timing_paths.tcl` run on each)

| Revision | ALMs (checkpoint 5 → now) | Registers | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|
| 68020 | 3,949 → **4,059** (+110) | 2,488 | 4 | 110.85 / 107.09 MHz | +1.396 / +1.079 ns | **+0.058 ns** |
| 68EC020 | 3,951 → **4,062** (+111) | 2,434 | 4 | 106.97 / 103.77 MHz | +1.069 / +0.780 ns | **+0.062 ns** |

- **Fmax:** both meet 96 MHz.
- **Area:** about +110 ALMs each (the yosys estimate was ≈ +95).
- **Worst setup paths:** now the new CHK2 / CMP2 flag terms (`xsz_q` / `xa_q` → `c2_nq` / `c2_vq`, 7 levels), then
  `uw` → `cnt` and the bit-field mask.
- **Hold:** slack is positive but the thinnest of any m68ksv revision (+0.058 / +0.062 ns at −40 °C). Watch it when the
  core is placed inside a full MiSTer design.

### How to rerun (this section)

```bash
verify/amiga020_build.sh <dir> [68021]; <dir>/amiga020_68020 [-v]     # the Amiberry / WinUAE cases
scratchpad/winuae/m20table.sh <tag>    # mus020 13 rows (+ the WinUAE class line), rerun020, directed 020 tests, amiga020
scratchpad/winuae/gates.sh             # + the 68000 suite on the 020 builds and the non-020 A/B against the start snapshot
```

### SSW back to the manual, CHK2 margin (2026-11-16)

Follow-up on the 68020 / 68EC020 builds only. Start snapshot `scratchpad/m68ksv_margin_start_snapshot/`, snapshot after
part 2 `scratchpad/m68ksv_margin_t2_snapshot/`, progress log `scratchpad/margin_progress.md`. Part 2 (timing) was done
and A/B-checked first, then part 1 (SSW).

#### Part 1: address-error SSW back to the MC68020 User's Manual — **#unverified**

- **What changed:** the address-error frame's SSW (+$0A) is now **RB | RC | RW | SIZE word | FC = $3066** in supervisor
  mode (was WinUAE's $0066). FB / FC / DF stay clear. Source: **MC68020 User's Manual, 6.2.1 "Special Status Word
  (SSW)", p. 6-22** (Figure 6-8 and the paragraph above it: "If an address error exception occurs, the fault bits written
  to the stack frame are not set ... and the rerun bits alone show the cause of the exception. Depending on the state of
  the pipeline, either RB and RC are set, or only RC is set"; RC / RB definitions p. 6-22 / 6-23).
- **Why both RB and RC:** the manual allows "RB and RC" or "only RC". Every 68020 address error is a change of flow to
  an odd address, which leaves the whole pipe to be refilled, so m68ksv sets both.
- **The low half** (RM, RW, SIZE, FC2–0) "applies to data cycles only" per the manual. It keeps WinUAE's values.
- **Consequence:** an RTE of an unrepaired address-error frame now re-runs the fetch, as the manual describes (with
  $0066 it took the software-completion path).
- **Kept from WinUAE:** the stacked PC (a JMP's address + 2, `ae_jmp` / `m2 AEPC`) and the fault address in +$10 and in
  the data input buffer +$2C.
- **#unverified - manual versus WinUAE, no real hardware to settle it:**
  - WinUAE writes $0066, and its source calls this frame "partially implemented only".
  - A run of `verify/amiga020` on a real 68020 / 68EC020 Amiga would settle it.
  - If evidence shows the choice is wrong, fix it: `DWX_SSW20` in `rtl/m68ksv_eu.sv` and `SSW_AE` in
    `verify/tb/amiga020.cpp`.
  - The same flag is in the Handover open items, `DESIGN.md` 7.2 / 7.4, `verify/amiga020/README.md` and `README.md`.
- **Harness:** `amiga020` checks the SSW word (T7 log row and the three far-target JMP rows) against $3066. It prints the
  logged WinUAE value on every run as the known difference, and counts it in the summary line:
  `known difference [log] T7 SSW (word 5): m68ksv 3066, expected 3066 (MC68020 UM 6.2.1: RB | RC), Amiberry log 0066`.

#### Part 2: CHK2 / CMP2 margin and the other new logic (no behaviour change)

All in `rtl/m68ksv_eu.sv`, 68020 builds only (`IS020`). The 68000 / 68010 logic and every generated ROM file are
unchanged.

1. **CHK2 / CMP2 in two steps.**
   - **Step 1, the compare word's e3:** registers the two 33-bit subtractions value − lower and value − upper as sign,
     bit 31 and six partial ORs of bits 30:0. It also registers the three operand signs (`c2_*1`).
   - **Step 2, every clock:** forms Z / C / N / V (`c2nv`) into `c2_cq` .. `c2_vq` one clock after the compare word.
     The flag word reads them four or more clocks later (the 020 phases are one clk apart, so the next e3 is at least
     4 clks away).
   - **Size muxes:** they use `c_sz`, which equals `xsz_q` in both CHK2 ALU words.
   - **s1 / s2** (sign of the wrapping lower − value): bit 31 XOR the OR of bits 30:0.
   - **lower > upper (`c2_lgu1`):** no longer muxed and compared in the compare word. It is one subtraction DT − XT on
     the raw bounds, with zero columns after bits 7 and 15. Those columns pass the borrow on and expose it, giving the
     8 / 16 / 32-bit compares. It is registered every clock: c_sz, XT and DT are stable from the bound reads to the end
     of the instruction. This also removed the separate size muxes of the old comparator.
2. **DIV.L overflow N / Z in two steps.** DVLHI registers the parts: Dq = 0 / < 0, Dr = 0 / < 0, 64-bit DIVS.L, divisor
   and Dr negative, and the sign plus six partial ORs of Dr + |divisor|. N / Z are formed the next clock.
3. **MUL / DIV.W idle counts** (`cnt_mul_r` / `cnt_div_r`) are registered every clock. The popcounts are no longer in
   front of `cnt` (this was the `uw` / `ir` → `cnt` path). xa_q / ir and the divider registers are stable two or more
   clocks before the e0 that loads `cnt`.
4. **Equivalence:** the CHK2 and DIV.L rewrites are **SAT-proved equal** to the one-clock logic of the start, with yosys
   `sat -prove` on extracted miters (`scratchpad/mg/eq/c2eq.sv`, `dloeq.sv`). The CHK2 proof covers all xa_q / XT / DT
   values, sizes .B / .W / .L and Dn / An. A control with one OR bit dropped fails the proof.
5. **Tried and reverted:**
   - One adder for ppc = fpc − 4 and the AEPC ppc + 2.
   - The DIV.L overflow sum folded into the DVLSTEP subtractor.
   - Both made yosys go up, so the project rule "keep only if yosys goes down" applied.
   - The other WinUAE additions (CHK V / C, DIVO N / Z, PACK / UNPK, LINK, SSW mux) are a few LUTs each. They were left
     as they were.

**Logic depth** (yosys 0.66 `synth_intel_alm`, `verify/tools/depth.py`, LUT levels; an estimate, not Quartus;
"plain" = `ys1.sh`, "Q-like" = `ysq1.sh`; start = the start snapshot, cp5 = checkpoint 5):

| Endpoint | 68020 plain: start → now | 68020 Q-like | 68EC020 plain | 68EC020 Q-like |
|---|---|---|---|---|
| `c2_nq` (CHK2 N) | 10.50 → 5.00 | 11.00 → 8.00 | 11.00 → 7.00 | 10.25 → 7.00 |
| `c2_vq` (CHK2 V) | 10.50 → 5.00 | 9.35 → 4.00 | 11.00 → 5.00 | 10.25 → 4.00 |
| `c2_cq` / `c2_zq` (C / Z) | 9.50 / 8.50 → 4.00 / 3.00 | 10.00 / 9.35 → 4.00 / 3.00 | 9.00 / 8.45 → 4.00 / 3.00 | 9.00 / 8.95 → 4.00 / 3.00 |
| CHK2 step 1 (`c2_lor6` / `c2_uor6`, `c2_lgu1`) | - → 5.10 / 4.90 | - → 5.10 / 4.90 | - → 5.10 / 4.90 | - → 5.10 / 4.90 |
| `dlo_n` / `dlo_z` (DIV.L ovf) and its step 1 | 7.20 → 3.00 (step 1 ≤ 4.00) | 11.20 → 3.00 (≤ 4.00) | 11.20 → 3.00 (≤ 5.00) | 11.20 → 3.00 (≤ 5.00) |
| `cnt` | 11.05 → 6.00 | 11.05 → 7.00 | 11.05 → 7.00 | 10.10 → 6.00 |
| worst endpoint, start → now (cp5) | 12.00 cache read → 12.00 `inl_ovr` (cp5 12.00) | 12.00 → 12.00 (13.00) | 12.00 → 13.00 cache read (13.00) | 12.00 → 12.00 (12.00) |

The worst endpoints left are the same pre-existing paths as at checkpoint 5: the instruction-cache MLAB read, the
register-file read address, and `cond` / `fin_t` → `inl_ovr`. They move between 12 and 13 with yosys noise. The CHK2
endpoints, at 7 Quartus levels in the user's compile, are now well below them: step 1 ≈ mux + subtract + one LUT, step 2
≤ 8 yosys levels from ten registers. In cp5, under Musashi's rule, the CHK2 endpoints were at 9.0–10.0.

**Size** (yosys LUT + carry / FF; noise about ±40 LUTs between nearly identical netlists):

| CPU | cp5 | start (WinUAE) | now |
|---|---|---|---|
| 68020 plain / Q-like | 7,300 / 7,210, FF 2,407 | 7,508 / 7,377, FF 2,415 | 7,504 / 7,343, FF 2,461 |
| 68EC020 plain / Q-like | 7,309 / 7,117, FF 2,395 | 7,480 / 7,287, FF 2,403 | 7,466 / 7,329, FF 2,449 |

- **Area:** the WinUAE change's +110 ALMs were **not** measurably won back. yosys stays within its noise of the start;
  the lgu rewrite alone measured −18 to −52 LUTs (intermediate runs), and the 46 new registers take some of that back.
- **Quartus target:** whether the 68EC020 reaches +1.40 ns depends on placement as well as depth. In the user's last
  68EC020 compile, the pre-existing paths `bf_w` → `bf_mq` (+1.184) and `uw` → `xa_q` (+1.207) were already under +1.40
  at 100 °C.
- **Hold:** the new step-2 / count registers add short register → 1–2 LUT → register paths. Quartus pads hold in the
  fitter, but they may become the minimum-hold paths (+0.058 / +0.062 ns now).

#### Gates (final RTL)

| Gate | Result |
|---|---|
| A/B, part 2 against the start (`scratchpad/mg/abrun.sh`: the cp5 tool with two fixes; clock-exact, every output every clock + registers at each boundary; 3 seeds × 4 runs × 4,000,000 clocks per row) | **0 mismatching runs on all seven configurations**: 68000 1,121,208 boundaries / 3,176 bus errors; 68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 16-bit 1,121,208 / 3,176; 68EC000 8-bit 625,970 / 3,493; 68010 982,951 / 3,423; 68020 and 68EC020 (`-mingap 1`) 497,572 / 2,152 each; `-bf` rows 407,671 / 1,636; new `-c2dl` rows (CHK2 / CMP2 + DIV.L snippets, `-snip 18`) 585,108 / 1,803. Controls on the `-c2dl` rows: a CHK2 N-term fault fails 12 of 12 runs, a DIV.L "Dr > divisor" fault 1 of 12 |
| A/B tool fix | checkpoint 5 removed STERM (the 68020 has none). The cp5 `ab20` still terminated port-3 cycles with STERM, so the 68020 hung after a few instructions (317 boundaries per row, not noticed before). Port 3 is now a 32-bit DSACK port, as in `mus020` |
| A/B after part 1 | 5 non-020 configurations: **0 mismatching runs** (same counts). 020 rows: every mismatching run (64) first differs in the address-error frame's SSW word (+$0A, micro-address `EXC0_020` + 82): the intended change |
| Generated files | `m68ksv_urom.sv`, `m68ksv_drom.sv`, `m68ksv_upkg.sv`, `m68ksv_ualabels.h` byte-identical to the start (all ROMs, so the 68000 / 68010 ROMs too) |
| `amiga020`, 68020 / 68EC020 | **285 / 285, 0 failures** each, plus 1 known difference printed (T7 SSW $3066 vs the logged $0066) |
| `mus020`, 13 rows | **0 mismatching runs on every row**. Classes (m51 … e63): DIV.W ovf 8 / 15 / 149 / 39 / 7 / 12 / 33 / 29 / 30 / 41 / 44 / 25 / 14; CHK 38 / 71 / 184 / 102 / 33 / 36 / 127 / 26 / 122 / 114 / 4,682 / 84 / 61; CHK2 flags 3 / 4 / 10 / 7 / 3 / 2 / 57 / 3 / 12 / 6 / 7 / 15 / 0; CHK2 trap decision 1 / 1 / 0 / 4 / 0 / 2 / 0 / 1 / 2 / 2 / 1 / 2 / 1; DIV.L ovf 1 / 0 / 0 / 2 / 1 / 0 / 0 / 0 / 0 / 0 / 3 / 1 / 0; PACK / UNPK 0 / 1 / 1 / 1 / 0 / 2 / 2 / 1 / 5 / 2 / 2 / 1 / 3; LINK A7 1 / 4 / 4 / 5 / 3 / 2 / 21 / 1 / 225 / 4 / 7 / 16 / 6. Group-0 resyncs equal to the start except m54 263 → 258, e56 293 → 296, e59 276 → 278, e61 263 → 267, m62 183 → 180: after an address error the frame's SSW word differs, and random code later reads it |
| `dsz020` (`-w 0`, `-be 3`, `-be 4`), `cache020`, `rmc020`, `cop020` | output files byte-identical to the start, both builds |
| `rerun020` | **6 of 12** runs mismatching (`-x020` 5 of 12); output files byte-identical to the start, so part 1 does not change it (it injects bus errors, not address errors) |
| 68000 suite on the 68020 / 68EC020 builds (`harte -bus32`) | pure 714,838 / 794,139, corrected 9,572 / 202,182. Failures by class, the same as the start: address error 178,087, exception 16,487, SR write 20,002, indexed / scale 53,005, other 22, winuae_ccr 4,308. Both builds identical |
| Verilator 4.204 `--lint-only -Wall` | **0 errors**. Warnings 78 (68000 family / 68010), 77 (020), `m68ksv_qtop` 102 / 99: the start's lists (path-normalised diff empty). The unused borrow-tap bits of `c2_gs` are covered by a `lint_off UNUSED` comment pair |
| `verify/tools/mkall.sh` | check output equal to the start apart from line numbers |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/*.sv` |
| Protected files | `files.qip`, `.qsf` / `.qpf`, `fleet_types.svh`, vendor files, `/Work/Build/amiberry/`: untouched |
| Not run | Quartus (the user compiles), `tim020` (no timing change intended), `mus010` / fx68k / MAME lockstep on the non-020 builds (replaced by the clock-exact A/B) |

#### Files changed

- `rtl/m68ksv_eu.sv`: CHK2 two steps and lgu, DIV.L overflow two steps, `cnt_mul_r` / `cnt_div_r`, `DWX_SSW20`.
- `rtl/gen/m68ksv_ucode020.py`: frame comment only; the generated files are unchanged.
- `rtl/m68ksv_all.sv`: regenerated.
- `verify/tb/amiga020.cpp`: `SSW_AE`, the known-difference line.
- `verify/amiga020/README.md`, `REPORT.md`, `DESIGN.md`, `README.md`.

#### Compile commands (the user; Quartus 17.0, from `syn/quartus/`)

```bash
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

The other five revisions are clock-exact against the start with identical ROMs. They do not need a recompile.

#### Measured Quartus results (user's compiles 2026-11-16 20:15 / 20:17; `timing_paths.tcl` run on each)

| Revision | ALMs (WinUAE compile → now) | Registers | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|
| 68020 | 4,059 → 4,066 | 2,483 | 105.22 / 107.20 MHz | **+0.913** / +1.089 ns | +0.185 ns |
| 68EC020 | 4,062 → 4,054 | 2,451 | 112.61 / 111.71 MHz | +1.537 / **+1.465** ns | +0.136 ns |

- **68EC020: target met.** Worst slack +1.465 ns, above the checkpoint 5 +1.40. The CHK2 / CMP2 paths are gone from both
  revisions' worst 3.
- **68020: target missed.** Worst slack +0.913 ns at 100 °C (target ≥ +1.15). The path is `bf_w` → `bf_iq` (bit-field
  insert mask, 8 levels). That logic predates the WinUAE change and is identical in the 68EC020, where it is not in
  the worst 3, so this is placement variation on a path with little margin. It is the next candidate for the same
  two-step treatment.
- **Hold improved on both:** +0.185 / +0.136 ns, up from +0.058 / +0.062.
- **Area:** unchanged within noise, as the yosys estimate said.

### Bit-field path margin (2026-11-16)

Follow-up on the 68020 / 68EC020 builds only, **no behaviour change**. Target: the 68020's worst setup path in the
20:15 compile, `bf_w[0]` → `bf_iq[28]` (+0.913 ns at 100 °C, 8 levels), off the top. Start snapshot
`scratchpad/m68ksv_bf_start_snapshot/`, progress log `scratchpad/bf_progress.md`, scripts in `scratchpad/bf/`.

#### What changed (`rtl/m68ksv_eu.sv`, bit-field unit)

- **Shift amounts registered every clock** from `bf_off` / `bf_w` / IR: `bf_o5r` (o6), `bf_ur` (o6 + width), `bf_ir5`
  ((64 − o6 − width) mod 32), `bf_xs5` (32 − width), `bf_memr` (memory form). 22 FFs.
  - Why this is safe: BFINIT loads `bf_off` / `bf_w` at its e0. BFP's e3 is three clocks later at the earliest (the
    e1 / e2 / e3 of the next word, one clk apart at the least). IR is the BF instruction throughout. The stage-2
    registers (`bf_xuq` etc.) already relied on the same fact.
- **Mask (`bf_mc` → `bf_mq`):** no more `{bf_tm, 0} >> o6`. Each mask bit is decoded directly from `bf_ur` / `bf_o5r`.
  The field is frame bits 64 − `bf_ur` .. 63 − o6, so a bit is "`bf_ur` ≥ c and o6 < c" for a constant c, plus the
  wrap term in register form.
- **Insert value (`bf_ic` → `bf_iq`):** no more shift left then shift right. It is the mask AND
  `{rot, rot[31:24]}`, where `rot` = `xa_q` rotated left by `bf_ir5`: one 32-bit rotate. The same formula covers the
  memory form, the fifth byte and the register form.
- **Funnel (`bf_fl` → `bf_flq`):** one 64 → 32 funnel by `bf_o5r` of `{xb, memory ? xt[7:0] : xb[31:24], xb[23:0]}`.
  The low 24 bits are never reached in memory form, since the offset there is < 8.
- **`bf_xu` = `bf_flq >> bf_xs5`**: the subtract is gone from in front of the shifter.
- **`bf_tm`** (top width bits) is written as per-bit compares.
  - Every compare is a small function `bf_ge(x, c)` built from AND / OR gates.
  - Why: with `>=`, yosys built one carry chain per bit. The first attempt cost +800 LUTs for that reason (`bf/ys_t1.log`).
- **Lint:** `bf_fs` / `bf_xa2` (only the top long is read) sit in a `lint_off UNUSED` pair, like `c2_gs`.

#### Equivalence (yosys SAT)

- **Setup:** `scratchpad/bf/eq/bfeq.sv` is a miter of two modules:
  - the start's one-clock logic, copied line for line from the start snapshot (each line checked verbatim);
  - the rewrite, with each register replaced by its D expression. `bf/eq/mkbody.sh` copies that text mechanically
    from the RTL.
- **Outputs compared:** `bf_fl`, `bf_tm`, `bf_lmc`, `bf_mc`, `bf_ic`, `bf_xu`, for all offsets, IR modes and data
  values, with widths 1–32.
- **Result:** `sat -prove bad 0` passes: **SUCCESS**.
- **Planted faults:** all five **FAIL**, as they should:
  - wrap term `64 − k` → `63 − k`;
  - funnel data bit 1;
  - `bf_tm` `>=` → `>`;
  - memory-mask bound 39 → 38;
  - `bf_ir5` taken from the raw offset.

#### Logic depth and size (yosys 0.66 `synth_intel_alm`, `verify/tools/depth.py` over 3,000 endpoints, LUT levels; an estimate, not Quartus; plain = `cp5/ys1.sh`, Q-like = `cp5/ysq1.sh` = `ff/ysq1.sh` + depth)

| Endpoint, start → now | 68020 plain | 68020 Q-like | 68EC020 plain | 68EC020 Q-like |
|---|---|---|---|---|
| `bf_iq` (insert value) | 11.10 → **6.00** | 11.10 → **6.00** | 10.10 → **6.00** | 11.10 → **6.00** |
| `bf_mq` (mask) | 10.00 → **4.00** | 9.00 → **4.00** | 9.00 → **4.00** | 9.00 → **5.00** |
| `bf_flq` (field) | 8.00 → **6.00** | 8.00 → **6.00** | 8.00 → **6.00** | 8.00 → **6.00** |
| `bf_tmq` (shown by yosys as `bf_lmq`) | 4.00 → 5.00 | 5.00 → 5.00 | 4.00 → 5.00 | 4.00 → 5.00 |
| `bf_w1q` | 1.25 → 1.25 | 1.25 → 1.25 | 1.25 → 1.25 | 1.25 → 1.25 |
| new registers (`bf_ir5` / `bf_ur` / `bf_o5r` / `bf_xs5`) | - → 4.00 / 3.05 / 2.00 / 1.25 | same | same | same |
| `bf_xuq` (stage 2) | 5.10 → 5.00 | 5.10 → 5.00 | 5.10 → 5.00 | 5.10 → 5.00 |
| `res` (worst into it) | 10.00 → 10.00 | 11.00 → 9.10 | 10.00 → 11.00 | 10.00 → 10.00 |
| worst endpoint | 12.00 → 13.00 | 12.00 → 12.00 | 13.00 → 12.00 | 12.00 → 13.00 |
| worst, instruction-cache read only | 12.00 → 13.00 | 12.00 → 11.00 | 13.00 → 12.00 | 12.00 → 13.00 |
| worst, all other endpoints | 12.00 → 11.45 | 12.00 → 12.00 | 11.00 → 12.00 | 12.00 → 12.00 |
| LUT + carry | 7,504 → **7,201** | 7,343 → **7,016** | 7,466 → **7,171** | 7,329 → **7,034** |
| FF | 2,461 → 2,483 | 2,461 → 2,483 | 2,449 → 2,471 | 2,449 → 2,471 |

- **Bit-field stage-1 endpoints:** all ≤ 6 levels in both flows (target met).
  - `bf_iq`'s deepest path is now the mask decode (`bf_ur` → mask → AND). The `xa_q` rotate is ≤ 4 levels.
  - `bf_tmq` gained one level (4 → 5) because abc chains the thermometer bits. It stays under 6.
- **Worst path:** no bit-field endpoint is near it.
  - The 13s are the instruction-cache MLAB read (`biu32 c_mem` → cache FF). This change does not touch that path,
    and it moved 11 ↔ 13 between these runs.
  - It was 13 at checkpoint 5 and 12 / 13 at the margin start, as the previous subsection notes.
  - The non-cache worst (register-file read address, `res`, `dt.ENA`) stays at 11–12.
  - **Strict per-run reading:** two of the four runs (68020 plain, 68EC020 Q-like) report a worst of 13 against the
    start's 12, both on that cache path.
- **Area:** −290 to −330 LUTs in all four runs, +22 FFs.

#### Gates (final RTL)

| Gate | Result |
|---|---|
| A/B against the start snapshot (`scratchpad/bf/abrun.sh` = `mg/abrun.sh` with the fixed `mg/ab` tool; clock-exact, every output every clock + registers at each boundary; 3 seeds × 4 runs × 4,000,000 clocks per row; 020 rows `-mingap 1`) | **0 mismatching runs on all seven configurations.** 68000 1,121,208 boundaries / 3,176 bus errors; 68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 16-bit 1,121,208 / 3,176; 68EC000 8-bit 625,970 / 3,493; 68010 982,951 / 3,423; 68020 and 68EC020 514,679 / 2,192 each; bit-field rows (`-mix 40 -snip 16`, 2 seeds) 416,363 / 1,649 each; CHK2 / DIV.L rows 567,216 / 1,797 each |
| A/B planted faults (`bf/abctl.sh`, 68020, 5 bit-field seeds + 3 plain seeds) | register-form mask wrap term `64 − k` → `63 − k`: bit-field rows 14 of 20 runs fail (seeds 4 / 5: 8 of 8), plain rows 4 of 12. `bf_ir5` off by one: bit-field rows 15 of 20 fail (seeds 4 / 5: 8 of 8), plain rows 9 of 12 |
| Generated files | `m68ksv_urom.sv`, `m68ksv_drom.sv`, `m68ksv_upkg.sv`, `m68ksv_ualabels.h` byte-identical to the start |
| `amiga020`, 68020 / 68EC020 | **285 / 285, 0 failures** each; the same known difference printed (T7 SSW $3066 vs the logged $0066) |
| `mus020`, 13 rows | **0 mismatching runs on every row.** All 13 output files are byte-identical to the start's run (`winuae/m20_mg`), so the class counts are the same: DIV.W ovf 8 / 15 / 149 / 39 / 7 / 12 / 33 / 29 / 30 / 41 / 44 / 25 / 14; CHK2 flags 3 / 4 / 10 / 7 / 3 / 2 / 57 / 3 / 12 / 6 / 7 / 15 / 0, and so on |
| `dsz020` (incl. `-w 0`, `-be 3`, `-be 4`), `cache020`, `rmc020`, `cop020` | output files byte-identical to the start, both builds |
| `rerun020` | **6 of 12** runs mismatching (`-x020` 5 of 12); output files byte-identical to the start |
| Verilator 4.204 `--lint-only -Wall` | **0 errors** for all seven CPUs and `m68ksv_qtop` with all seven macros. Warnings 78 / 77 (020) and qtop 102 / 99: the start's lists exactly (line-normalised diff empty for all 14) |
| `verify/tools/mkall.sh` | Same as the start, except for 4 new lines in the "loops" list. All 4 are procedural `for (int ...)` loops: one in the `bf_ge` function, three in the mask `always_comb`. They are the same kind as the 11 already listed; no module-level loop. No other new hits |
| SAT | see above: SUCCESS, 5 of 5 planted faults caught |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/*.sv` |
| Protected files | `files.qip`, `.qsf` / `.qpf`, `m68ksv_qtop.sv`, `fleet_types.svh`: byte-identical to the snapshot; vendor files and `/Work/Build/amiberry/` not touched |
| Not run | Quartus (the user compiles); the `harte -bus32` 68000 suite on the 020 builds; `tim020`; Musashi / fx68k / MAME lockstep on the non-020 builds (covered by the clock-exact A/B) |

The reference outputs for `mus020` / `amiga020` / directed tests / `rerun020` are the previous subsection's final gate
run (`winuae/m20_mg`). It was made on the same RTL as this start snapshot; it was not re-run on the snapshot.

#### Files changed

- `rtl/m68ksv_eu.sv`: bit-field stage 1 (every-clock shift registers, mask decode, rotate insert, funnel, `bf_ge`).
- `rtl/m68ksv_all.sv`: regenerated (`verify/tools/mkall.sh`).
- `DESIGN.md` (bit-field sentence), `REPORT.md` (this subsection).

#### Compile commands (the user; Quartus 17.0, from `syn/quartus/`)

```bash
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020     # 68020
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020   # 68EC020
```

- **The other five revisions don't need a recompile.** They are clock-exact against the start, and the bit-field
  logic is folded away in them.
- **Expected:** `bf_w` → `bf_iq` / `bf_mq` drop out of the worst list. The next 68020 paths are `cx` → `xa_q`
  (+1.434) and `uw` → `vec` (+1.595).
- **Not measured:** whether the 68020 reaches ≥ +1.15 ns also depends on placement.

#### Measured Quartus results (user's compiles 2026-11-16 20:48 / 20:51; `timing_paths.tcl` run on each)

| Revision | ALMs (previous compile → now) | Registers | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|
| 68020 | 4,066 → **3,926** | 2,482 | 115.22 / 113.61 MHz | +1.738 / **+1.615** ns | +0.054 ns |
| 68EC020 | 4,054 → **3,889** | 2,506 | 107.68 / 105.73 MHz | +1.130 / **+0.959** ns | +0.064 ns |

- **The bit-field path is gone from both worst lists.** Both revisions are smaller than before the WinUAE change
  (checkpoint 5: 3,949 / 3,951).
- **68020: target met** (+1.615 ns, target ≥ +1.15). The worst path is `xsz_q` → `res` (7 levels).
- **68EC020: target missed** (+0.959 ns, target +1.40; it was +1.465 in the previous compile). The worst path is
  `dl_q` → `int_lvl` (7 levels): logic this change did not touch.
- **Conclusion:** across the last three compiles the two 020 revisions, nearly identical logic, swap places by about
  ±0.5 ns. That is placement variation on 7–8-level paths, so chasing per-revision slack targets further gives little.
  Both run at ≥ 105.7 MHz, about 10 % over 96 MHz.
- **Hold:** +0.054 / +0.064 ns, positive but thin again.

## Checkpoint 6 (resource-placement switch) — 2026-11-16

### Summary

- **New parameter `RES`** on `m68ksv`, `m68ksv_eu` and `m68ksv_fleet` picks where the control storage goes. Execution is
  the same clock for clock on all seven CPUs in both settings (clock-exact A/B, 0 mismatching runs):
  - **`RES = 0`, BRAM-heavy (default):** today's design: one wide microcode ROM and the decode tables in M10K.
  - **`RES = 1`, logic-heavy (new):** two-level microcode (micro ROM + nano ROMs) and the opcode decode table `drom1` in
    logic.
- **CPU M10K, exact from the ROM shapes** (Quartus has not compiled this RTL yet):

  | CPU | start | `RES = 0` now | `RES = 1` |
  |---|---|---|---|
  | 68000 / 68008 / 68008FN / 68EC000 | 25 | **16** | **7** |
  | 68010 | 28 | **24** | **10** |
  | 68020 / 68EC020 | 30 | 30 | **12** |
  | fx68k (reference) | 6 | | |

- **Part 1 (default build smaller, no behaviour change):**
  - The 68000-family microcode is compacted from 1,131 to 703 words (identical words and tails merged), so its ROM is
    1,024 deep: 10 M10K instead of 19.
  - The 68010 ROM is split into 1,024 + 512 words: 17 M10K instead of 21.
  - The 68020 ROM (1,961 words) already fills its 2,048-deep shape.
- **Part 2 (logic-heavy):** micro ROM + nano ROMs. The micro ROM is read one clock ahead, so the micro-word reaches the
  sequencer at the same clock as today.
  - 68000: 7 CPU M10K (fx68k: 6).
  - yosys estimates **+282 LUTs** for the 68000 (+8.6 %, plain flow; +250 Quartus-like). With the project's
    yosys-to-Quartus ratio (≈ 0.57) that is ≈ **+140 to +160 ALMs**: ≈ 1,930 – 1,950 ALMs against fx68k's 2,047.
  - **These are estimates; yosys has predicted Quartus ALMs badly in this project.**
- **Logic depth** (yosys): the control store adds no depth (table "Logic depth" below).
- **Gates (final RTL):**
  - A/B: 0 mismatching runs on all seven configurations, both against the start and `RES = 1` against `RES = 0`;
    planted faults caught.
  - Every suite / lockstep / directed gate output is byte-identical to its reference: `run_all` 794,139 / 794,139
    pure and 202,181 / 202,182 corrected, `run_family`, `mus010` incl. `-cyc`, `rerun010`, `loop010`, `mus020` 13
    rows, `amiga020`, the 020 directed tests, `rerun020` 6 / 12, the 68000 suite on the 010 / 020 builds, `mame8`,
    fx68k lockstep.
  - `RES = 1`: `run_all` on the 68000, one `mus010` row and two `mus020` rows, byte-identical to `RES = 0`.
  - Lint: 0 errors. `mkall` check: nothing new.
- **Where things are:**
  - start snapshot `scratchpad/m68ksv_cp6_start_snapshot/`;
  - after part 1 `scratchpad/m68ksv_cp6_part1_snapshot/` (it holds the first, plain-mux 68010 split, replaced later);
  - progress log `scratchpad/cp6_progress.md`;
  - scripts and results in `scratchpad/cp6/`;
  - the final RTL tree as tested: `scratchpad/cp6/rtl_fin2/`.

### Part 1: the default build, cheapest M10K shapes

An M10K is 1,024 × 10 or 2,048 × 5 bits (also 512 × 20, 256 × 40). A ROM just over 1,024 words therefore costs twice
the blocks per bit.

Quartus packs only the ROM output bits the logic uses. The 68010 / 68020 builds drop `pl`, `lk` and `pu`, leaving 103 /
119 of 110 / 126 bits (from the "Registers Packed Into Inferred Megafunctions" table of their map reports). The counts
below use those widths; they reproduce the start's fitter numbers (19 / 21 / 24).

- **68000 family: compaction (option 1 of the brief).** `compact000()` in `rtl/gen/m68ksv_ucode.py`:
  - **Rule:** two words behave the same when every field except `nxt` is equal and their successors behave the same.
    - Successors are taken as `m68ksv_eu` forms them: `nxt` for NXT / CALL / BT / BF / FINC / FINNC, plus upc + 1 for
      BT / BF / CALL.
    - FIN / CONT / BODY / RET / RSM do not read `nxt`.
    - Partition refinement gives 684 classes.
  - **Pinned:** two blocks stay word for word at their addresses: the reset / exception block (RESET .. HALT_L, 78
    words) and the Bcc / BSR routines (BCC_S .. DBCC, 23 words). Why:
    - the EU compares `upc` / `ua_r` with labels there;
    - the package `UA_*` values are shared with the 68010 / 68020 ROMs;
    - the lockstep harness checks address ranges inside EXC0.
  - **Layout:** the first word of each class, in the old order. An upc + 1 successor goes right after its word, so 19
    copies were made where the class already sat elsewhere. Result: **703 words**, no gaps.
  - **Proof in the generator:** a bisimulation check from every old address:
    - the word at the new address has the same fields and sequencer code;
    - the successors are related again;
    - every label maps to a related address.

    It runs on every generation, and `check()` runs again on the new ROM.
  - **ROM:** `m68ksv_urom` is 1,024 × 93, addressed by `ua_r[UA000_W-1:0]` (new package constant `UA000_W = 10`).
    **19 → 10 M10K.**
  - **Visible changes:** only the debug output `dbg_upc` (the micro-address) and the contents of `m68ksv_drom2` /
    `m68ksv_drom3` (they hold micro-addresses).
    - The A/B harness compares `dbg_upc` through the old / new address relation the generator writes
      (`M68KSV_UAREL=<file>`).
    - Control: without the relation, the 68000 rows fail at once on `dbg_upc`.
  - **Harness labels** (`verify/tb/m68ksv_ualabels.h`):
    - `UA_*` stays at the uncompacted addresses, which are the 68010 / 68020 ROMs' addresses (`rerun010` uses
      `UA_DBCC`). These lines are byte-identical to the start.
    - New `UA0_*` lines give the compacted 68000-family ROM's addresses.
    - Every `UA_*` the 68000-family harnesses use is in a pinned block.
- **68010 / 68020: not compacted.** Their micro-addresses are architectural: a format-8 / format-B frame stores the resume
  address, and an RTE resumes at any address its frame names. Moving words would change frame contents.
- **68010: split, mux in front of a register (option 2 of the brief: "let the tail ROM's output register line up").**
  `rom_module_split`:
  - `rom0` holds 1,024 words and `rom1` 512, both read one clock ahead. The address is the value `ua_r` is loaded with
    (`ua_n`) and the clock enable is that load (`ua_ce`): the mechanism of the logic-heavy micro ROM below.
  - The select mux (`s0 = !an[10]`, `s1 = an[10] && !an[9]`, registered with the address) sits in front of a register,
    `q`. That register holds the word at the previous clock's `ua_r`, as the single ROM's output did.
  - Addresses 1,536 – 2,047 give the zero word, as the one ROM's padding did.
  - **21 → 11 + 6 = 17 M10K.**
  - **Cost:** about 110 registers. The micro-word's users now start at a register instead of an M10K output (shorter
    paths). The new path is `ua_n` → the ROM address, as in `RES = 1`.
  - **First version replaced:** a plain output mux with registered selects. yosys showed it on the 68010's new worst
    paths: `urom` → register-file read address 12.00 levels, `fwd_hit` 11.00, against a start worst of 10.00. That
    is the brief's "keep the mux off the critical paths" case.
- **68020: unchanged.** Its 1,961 words (the brief said 1,908) already fill 2,048; a 1,024 + 1,024 split costs the same.

### Part 2: the logic-heavy setting (`RES = 1`)

**Selecting it:**
- RTL: `m68ksv #(.CPU(c), .RES(1))`, or `m68ksv_fleet #(.CPU(c), .RES(1))`.
- Quartus test project: revisions `m68ksv_qtop_<cpu>_lh` (macro `M68KSV_RES=1`).
- Harness builds: `M68KSV_RES=1 verify/build.sh ...` (also the other `verify/*build.sh`).
- Any value other than 1 builds the default.

**What changes (`DESIGN.md` 3.1):**

| Storage | `RES = 0` | `RES = 1` |
|---|---|---|
| microcode | `m68ksv_urom*` (one ROM; 68010: two) | `m68ksv_ucs*`: micro ROM {nxt, nano indices, direct fields} + nano ROMs |
| `drom1` (opcode → classes); 68010 `drom1lp` | M10K | `m68ksv_drom1*_lh`, `m68ksv_drom1lp_010_lh`: the same table, `romstyle "logic"`, same output register |
| `drom2`, `drom3`, `drom4e` | M10K, M10K, logic | unchanged |

**Two-level control store** (generated by `emit_ucs`):
- **Unique words:** the 68000-family ROM has 333 distinct words if `nxt` is left out (68010: 460, 68020: 602). So `nxt`
  stays in the micro ROM, and the other fields go to nano ROMs.
- **Nano groups** (`UCS_GROUPS`) come from a search over field partitions for the fewest M10K
  (`scratchpad/cp6/an/an4.py`).
- **Padding:** in every nano ROM, index 0 is all zero, so padding addresses still give the zero word.
- **Self-check:** the generator rebuilds every micro-address's word from the tables and asserts that it equals the
  single-ROM word.

| ROM set | micro ROM | nano ROMs | total |
|---|---|---|---|
| 68000 family | 1,024 × 28: nxt (10), `lh`, 2 indices — 3 M10K | 256 × 40 (238 values: sq bus ba aa ab ad xa xd fl iq pl lk pu) + 256 × 40 (145 values: cd bs bd bf dw as op xb xs ms bn ai fh) — 1 + 1 | 5 |
| 68010 | 1,024 + 512 × 20: nxt, 1 index — 2 + 1 | 512 × 99 (460 values, every field; 92 bits used) — 5 | 8 |
| 68020 / 68EC020 | 2,048 × 34: nxt, 3 indices — 7 | 256 × 40 (225 values), 256 × 39 (191), 128 × 36 (127) — 1 + 1 + 1 | 10 |

**Timing: the extra ROM read costs no clock.**
- **Today:** `m68ksv_urom` registers `ua_r` (loaded at e2) inside the M10K. Its output is the word of the previous
  clock's `ua_r`, and the EU takes it at the next e0, two or more clocks after e2.
- **Lookahead:** the micro ROM is read one clock ahead.
  - Its address is the value `ua_r` is being loaded with (`ua_n`).
  - Its clock enable is that load (`ua_ce` = reset, test load or e2).
  - New wires in the EU: `ua_e2` / `ua_n` / `ua_ce`. `ua_r <= ua_e2` is the old expression.
- **Result:**
  - The micro ROM output always holds the micro-word of the current `ua_r`.
  - The nano ROMs register its indices at the next clock edge, as `m68ksv_urom` registers `ua_r`. `nxt` and the direct
    fields pass a register.
  - The assembled `q` therefore equals `m68ksv_urom`'s `q` in every clock.
  - Everything after `uq` is untouched: the nano outputs reach `uq`'s users exactly as the single ROM's outputs did. No
    sequencer change was needed.
- **New paths:**
  - `ua_n` → micro-ROM address: the logic of `ua_r`'s D input, 6 yosys levels on the 68000.
  - Micro-ROM output → nano-ROM address: M10K to M10K, no logic (the 68010 adds its split select).
- **Before the first reset:** the micro ROM has not been read, so `q` is the zero word (the default build shows
  `rom[0]`). The reset loads both. The A/B starts in reset and sees no difference.

**Which decode tables go to logic** (measured in yosys on standalone ROM modules with `-nobram`):
- `drom1` (1,024 × 35, 129 distinct rows): 239 LUTs; `drom2`: 189; `drom3` (two ports): 180; `drom1lp_010`: 41.
- **Chosen: only `drom1` (plus the 68010's small `drom1lp`) in logic.** 68000: 7 M10K, +250 to +282 LUTs in the
  whole design.
- **Rejected options** (estimates):
  - All three tables in logic: 5 M10K for about +370 LUTs more, about 2,150 ALMs, more than fx68k. That misses "ALMs as
    low as you can get them" under the ≤ 8 target.
  - `drom3` in logic as well: ties fx68k's 6 M10K at ≈ 2,040 ALMs. Left as an open item.

### M10K per memory, exact from the ROM shapes

CPU only; the test RAM (8 M10K) is not counted.

| Memory | 68000 family `RES 0` | `RES 1` | 68010 `RES 0` | `RES 1` | 68020 / EC020 `RES 0` | `RES 1` |
|---|---|---|---|---|---|---|
| microcode (default ROM) | 1,024 × 93: **10** (start 2,048 × 93: 19) | — | 1,024 × 103 + 512 × 103: **11 + 6** (start 2,048 × 103: 21) | — | 2,048 × 119: **24** | — |
| micro ROM | — | 1,024 × 28: **3** | — | 1,024 × 20 + 512 × 20: **2 + 1** | — | 2,048 × 34: **7** |
| nano ROMs | — | 256 × 40, 256 × 40: **1 + 1** | — | 512 × 92: **5** | — | 256 × 38, 256 × 38, 128 × 32: **1 + 1 + 1** |
| `drom1` | 1,024 × 35: **4** | logic | 1,024 × 35: **4** | logic | 1,024 × 36: **4** | logic |
| `drom1lp_010` | — | — | 1,024 × 9, 2 ports: **1** | logic | — | — |
| `drom2` | 256 × 33: **1** | **1** | 256 × 33: **1** | **1** | 256 × 34: **1** | **1** |
| `drom3` | 256 × 11, 2 ports: **1** | **1** | **1** | **1** | **1** | **1** |
| **CPU M10K** | **16** | **7** | **24** | **10** | **30** | **12** |

- Widths are the bits the RTL uses (see Part 1).
- Unchanged in both settings: the three register-file copies (MLAB, 32 × 32 each) and the 68020 instruction cache (MLAB,
  64 × 57).
- yosys reports other M10K numbers (21 / 12, 29 / 16, 39 / 20). It maps the register-file copies and the cache to M10K
  as well and packs differently, so use the table above.

### yosys (an estimate, not Quartus)

yosys 0.66 `synth_intel_alm -family cyclonev`; LUT = ALUT2–6, carry = ALUT_ARITH.
- **Flows:** "plain" = `scratchpad/cp6/ys1.sh`, "Q-like" = `ysq1.sh` (cp5's flows plus the `RES` parameter).
- **Pre-steps:** the same for every run, including the start's.
- **`RES = 1`:** yosys ignores `romstyle "logic"`, so the scripts map `g_lh.drom1*` to logic (`memory_map`) as Quartus
  is asked to.
- **Trees:** start = the start snapshot; now = the final RTL.

| CPU | start plain / Q-like | `RES = 0` now | `RES = 1` | `RES = 1` − `RES = 0` | FF start / `RES 0` / `RES 1` |
|---|---|---|---|---|---|
| 68000 | 3,303 / 3,319 | 3,295 / 3,315 | 3,577 / 3,565 | +282 / +250 | 1,168 / 1,167 / 1,214 |
| 68008 | 3,352 / 3,308 | 3,357 / 3,307 | 3,590 / 3,565 | +233 / +258 | 1,176 / 1,175 / 1,222 |
| 68008FN | 3,321 / 3,313 | 3,334 / 3,386 | 3,599 / 3,609 | +265 / +223 | 1,177 / 1,176 / 1,223 |
| 68EC000 | 3,342 / 3,350 | 3,353 / 3,353 | 3,597 / 3,632 | +244 / +279 | 1,178 / 1,177 / 1,224 |
| 68010 | 4,195 / 4,220 | 4,298 / 4,309 | 4,558 / 4,540 | +260 / +231 | 1,483 / 1,586 / 1,542 |
| 68020 | 7,222 / 7,016 | 7,195 / 7,051 | 7,545 / 7,382 | +350 / +331 | 2,483 / 2,483 / 2,530 |
| 68EC020 | 7,188 / 7,034 | 7,172 / 7,077 | 7,504 / 7,312 | +332 / +235 | 2,471 / 2,471 / 2,518 |

All numbers are LUT + carry; plain / Q-like.

- **68000 family, `RES = 0`:** the same as the start within yosys noise (±40 LUTs). The compacted ROM changes only
  ROM contents.
- **68010, `RES = 0`:** +103 / +89 LUTs and +103 FF. These are the split ROM's output register and select (about 110
  bits).
- **`RES = 1`:** +230 to +350 LUTs. Most of it is `drom1` in logic (239 LUTs measured alone). The control store adds
  about 47 FF (`nxt`, the direct fields, the micro-ROM output path).
- **Quartus ALMs:** at the project's ratio (≈ 0.57 ALM per yosys LUT, which has been unreliable here), `RES = 1` costs
  ≈ +130 to +200 ALMs. That puts the 68000 at ≈ 1,940 – 1,950 ALMs against 1,791 now and fx68k's 2,047.

### Logic depth (yosys, `verify/tools/depth.py`, LUT levels; plain / Q-like)

| CPU | worst endpoint, start | `RES = 0` now | `RES = 1` | micro-ROM address (`RES = 1`) | `ua_r` (`RES = 1`) |
|---|---|---|---|---|---|
| 68000 / 68008 / 68EC000 | 10.00 / 10.00 | 10.00 / 10.00 | 10.00 / 10.00 | 6.00 / 6.00 | 5.00 / 5.00 |
| 68008FN | 10.00 / 10.00 | 10.00 / 10.00 | 10.00 / 9.00 | 6.00 / 6.00 | 5.00 / 5.00 |
| 68010 | 10.00 / 10.00 | 10.05 / 10.00 | 10.05 / 10.00 | 8.00 / 8.00 | 7.00 / 7.00 |
| 68020 | 12.40 / 12.00 | 12.00 / 13.00 | 12.00 / 11.25 | 8.00 / 10.05 | 7.00 / 9.05 |
| 68EC020 | 12.00 / 13.00 | 12.00 / 13.00 | 14.00 / 11.35 | 8.00 / 8.00 | 7.00 / 7.00 |

- **No control-store path is near the worst.** The micro-ROM address sits one level above `ua_r` (the reset / test-load
  select in front of `ua_n`), 6 – 10 levels.
- **68010 default:** its read-ahead ROM address is at 8.00.
- **The nano-ROM outputs** start the same paths the single ROM's outputs did, at the same depth: `q_exc`, `fwd_hit` and
  the register-file read address stay at 10.00.
- **68EC020 `RES = 1` plain, 14.00:** this endpoint is the instruction-cache MLAB read in `m68ksv_biu32` (`c_mem` →
  cache register). That path is untouched; earlier checkpoints recorded it moving between 11 and 13 with yosys mapping
  noise. Without it the worst endpoint is 11.45 (a `SIZ` output). By the strict per-run reading this run's worst is
  above the start's 12.00 / 13.00. The cause is placement-free abc noise on an unchanged path, not a new path.
- **68010 default, discarded first version:** the plain-mux split gave 12.00 / 11.00 there (`urom` → register-file read
  address, `fwd_hit`). It was replaced (Part 1).

### A/B equivalence (clock-exact: every output every clock, plus registers at each instruction boundary)

Tool: `scratchpad/cp6/abrun.sh`. It is bf/abrun.sh's stimulus with the fixed `mg/ab` tool, changed in three ways: the
mkall file list, `GOLD` / `GNEW` -G options, and `-upcrel`.
- **Stimulus:** 3 seeds × 4 runs × 4,000,000 clocks per row.
- **020 rows:** `-mingap 1`, plus the bit-field rows (2 seeds) and the CHK2 / DIV.L rows (3 seeds).
- **68000-family rows against the start:** `dbg_upc` is compared through the generator's old / new address relation
  (the compaction moved micro-addresses); every other output directly.

| Run | 68000 | 68008 | 68008FN | 68EC000 16 | 68EC000 8 | 68010 | 68020 (+bf, +c2dl) | 68EC020 (+bf, +c2dl) |
|---|---|---|---|---|---|---|---|---|
| final `RES = 0` against the start snapshot | **0** | **0** | **0** | **0** | **0** | **0** | **0 / 0 / 0** | **0 / 0 / 0** |
| final `RES = 1` against final `RES = 0` | **0** | **0** | **0** | **0** | **0** | **0** | **0 / 0 / 0** | **0 / 0 / 0** |
| part 1 (before the `RES` RTL) against the start | 0 | 0 | 0 | 0 | 0 | 0 | 0 / 0 / 0 | 0 / 0 / 0 |

Mismatching runs per row.
- **Boundaries / bus errors per row:** the same in every run and the same as every A/B since checkpoint 5: 68000
  1,121,208 / 3,176; 68008 593,918 / 3,410; 68008FN 553,569 / 3,416; 68EC000 8-bit 625,970 / 3,493; 68010 982,951 /
  3,423 (73,194 loop words, 1,457 software RTE); 68020 514,679 / 2,192 (bf 416,363, c2dl 567,216).
- **Logs:** `cp6/ab_fin2.log`, `cp6/ab_lh2.log`, `cp6/ab_p1.log`. The A/B of the intermediate tree (`ab_fin`, `ab_lh1`)
  also gave 0.

**Planted-fault controls** (`scratchpad/cp6/abctl.sh`; 2 seeds × 2 runs × 2,000,000 clocks per CPU). Every one must
fail, and every one did:

| Fault | CPUs | mismatching runs |
|---|---|---|
| 68000-family nano ROM 0 entry 5: field `pu` changed | 68000, 68EC000 | 8 / 8 |
| no lookahead: micro ROM addressed by `ua_r` instead of `ua_n` (68000) | 68000 | 4 / 4 |
| 68010 nano entry 0 (the idle word) gets sq = FIN | 68010 | 4 / 4 |
| 68020 nano 0 entry 0 gets sq = FIN | 68020, 68EC020 | 8 / 8 |
| `drom1_lh` entry 0 (ORI.B row): Dn class changed | 68000 | 4 / 4 |
| `ua_ce` without e2 | 68000, 68010, 68020 | 12 / 12 |
| 68000 compacted ROM word 100: sq changed (against the start, with the relation) | 68000, 68008 | 8 / 8 |
| 68010 default read-ahead ROM addressed by `ua_r` (against the start) | 68010 | 4 / 4 |
| 68000 rows against the start **without** the `dbg_upc` relation | 68000 | 2 / 2 (`dbg_upc` only) |

Two controls did not fail, and neither shows a weakness:
- **`ua_ce` without `rst`:** 0 / 12. e2 still occurs during reset and loads `UA_RESET` through `ua_n`, so the fault is
  masked by design.
- **020 micro-ROM word 300, `nxt` changed:** 0 / 8. That word ignores `nxt`. It was replaced by the nano fault in the
  table.

### Gates (final RTL)

How the runs were made:
- **Runs:** `scratchpad/cp6/gates.sh` (outputs `cp6/g`). The late 68010 ROM change (the read-ahead split) and the
  generated-module formatting came after it, so `cp6/gates2.sh` (outputs `cp6/g2`) re-ran everything they touch on
  the final RTL: the 68010 default, and every `RES = 1` run.
- **The other `gates.sh` rows** (68000 family, 68020s) ran on RTL that differed from the final only in the 68010
  instantiation and in how the generated `m68ksv_ucs*` modules are written. In those builds both fold to the same
  logic: the 68010 branch is not elaborated there, and the ROM contents are byte-identical.
- **References:** `scratchpad/cp5/g/out` (68000 family / 68010, checkpoint 5 final) and `scratchpad/winuae/m20_bf` /
  `winuae/g/out` (68020s, the bf session = this start).

| Gate | Result |
|---|---|
| **Default (`RES = 0`)** | |
| `run_all.sh` part: 68000 suite, gap 0–3, smoke, retry | pure **794,139 / 794,139**, corrected **202,181 / 202,182**, timed 797,878; gap 0–3 the same; smoke 3 / 3, retry 8 / 8. All four outputs byte-identical to checkpoint 5 |
| `run_family.sh` part: 68008, 68008FN, 68EC000 8- and 16-bit | 794,137 / 794,139 / 794,139 / 794,139 pure, corrected 202,181 each, retry. Bodies byte-identical to checkpoint 5 |
| 68000 suite on the 68010 build | 781,979 / 794,139 pure, corrected 9,793. Byte-identical to checkpoint 5 (`g2`, final RTL) |
| 68000 suite on the 68020 / 68EC020 builds (`-bus32`) | pure 714,838, corrected 9,572; classes ae 178,087, exc 16,487, sr 20,002, idx 53,005, other 22, winuae_ccr 4,308. Equal to the reference, both builds |
| `mus010`: 4 rows + `-cyc` | **0 mismatching runs**; all five outputs byte-identical to checkpoint 5 (`g2`) |
| `rerun010` (7 seeds), `loop010` | byte-identical to checkpoint 5 (`g2`) |
| `mus020`: 13 rows | **0 mismatching runs on every row**; all 13 outputs byte-identical to the reference |
| `amiga020`, 68020 / 68EC020 | **285 / 285, 0 failures** each; byte-identical to the reference |
| `dsz020` (incl. `-w 0`, `-be 3`, `-be 4`), `cache020`, `rmc020`, `cop020` | output files byte-identical to the reference, both builds |
| `rerun020` | **6 of 12** runs mismatching (`-x020` 5 of 12): the reference's, byte-identical |
| MAME m68008 lockstep (`mame8`, 68008 / 68008FN / 68EC000) | 0 mismatching runs ×3; byte-identical to checkpoint 5 |
| fx68k lockstep (`lockstep`, 20 rows × 64 runs × 400,000 phases) | all 20 outputs byte-identical to checkpoint 5: plain / waits / VPA / HALT / EC rows 0 mismatching runs; BR 0 / 1, IRQ 1 / 0, reset 2 / 2, BERR 0 / 1, mixed 4 / 4 (the open items of checkpoint 2, unchanged) |
| A/B against the start | 0 mismatching runs, all configurations (table above) |
| **Logic-heavy (`RES = 1`)** | |
| A/B against `RES = 0` | 0 mismatching runs, all configurations; planted faults caught (tables above) |
| `run_all.sh` part on the 68000 (suite, gap 0–3, smoke, retry) | pure **794,139 / 794,139**, corrected **202,181 / 202,182**; all byte-identical to the default / checkpoint 5 (`g2`) |
| `mus010` row (seed 41) | 0 mismatching runs; byte-identical to the default's (`g2`) |
| `mus020` rows m51 (68020) and e56 (68EC020) | 0 mismatching runs; byte-identical to the default's (`g2`) |
| **Static** | |
| Verilator 4.204 `--lint-only -Wall` | **0 errors**: 7 CPUs × `RES` 0 / 1 (warnings 78 / 77 (020)), `m68ksv_qtop` × 7 CPU macros with and without `M68KSV_RES=1` (102 / 99). Warning lists equal to the start's except one `DECLFILENAME` line that now names `m68ksv_ucs` instead of `m68ksv_urom_010`, the first module in `m68ksv_urom.sv` not named after the file (`cp6/lint_fin2`) |
| `verify/tools/mkall.sh` pre-compile check (also scans `m68ksv_qtop.sv`) | the start's output exactly (line numbers aside): nothing new |
| Generator self-checks | compaction bisimulation (every old address), control-store rebuild (every micro-address, every ROM set), `check()` on the compacted ROM: pass on every generation |
| `DIAG` markers | none in `rtl/`, `verify/`, `syn/quartus/` |
| Protected files | `fleet_types.svh`, `files.qip`, the existing .qsf files, `fx68k.qip` / `fx68k/`, the Musashi / MAME sources: unchanged against the start snapshot; `/Work/Build/amiberry/` not accessed |
| Not run | **Quartus** (the user compiles); `tim020` (no timing change: every cycle-timed output above is byte-identical) |

### Decisions taken alone (the user could not be asked)

1. **68000 family: compaction, not a split.** It is the brief's preferred option, and it gives 10 M10K instead of a
   split's 10 + 3, with no output mux. The reset / exception and Bcc / BSR blocks are pinned, which keeps every
   RTL-compared address and the shared package constants: no RTL constant changed.
2. **68010 / 68020: no compaction.** Their micro-addresses are written to and read from memory (format-8 / format-B
   frames).
3. **68010 default: split ROM, read one clock ahead, mux in front of a register.** A plain output mux was tried first;
   yosys showed it on the 68010's worst paths. Cost: about 110 registers and the `ua_n` → ROM address path.
4. **68020 default: unchanged.** No cheaper shape exists.
5. **Logic-heavy microcode: two-level with lookahead, nano ROMs in M10K.**
   - Nano tables in LUTs would put a 9-input table between the M10K and `uq`: deeper `uq` paths and many more LUTs.
   - Nano ROMs in M10K, with the micro ROM read one clock ahead, keep `uq`'s timing exactly as today.
6. **Only `drom1` in logic** (plus the 68010's `drom1lp`). This gives 7 M10K at the lowest ALM cost under the ≤ 8 target
   (see "Which decode tables go to logic"). Moving `drom2` / `drom3` too stays an open option.
7. **Nano groups fixed in the generator** (`UCS_GROUPS`), taken from the search and covered by the generator's
   self-check. A later microcode change can push a group's count of distinct values past a power of two. That costs
   blocks (reported in the generated comment), never correctness.
8. **A/B relation for `dbg_upc`** (68000 family against the start): written by the generator, used only by the
   scratchpad A/B tool. `dbg_upc` is a debug output; every other output is compared directly.
9. **`m68ksv_qtop.sv`:** `RES` is passed only under `ifdef M68KSV_RES`; without the macro the instantiation text is the
   start's. Each new revision's qsf is a copy of that CPU's qsf plus one `VERILOG_MACRO` line.
10. **Harness builds take `M68KSV_RES`:** `verify/build.sh`, `mus010_build.sh`, `mus020_build.sh`, `dsz020_build.sh`,
    `amiga020_build.sh`, `mame8_build.sh`, `lockstep_build.sh`. Unset means 0, the start's behaviour.
11. **Disk full during the first gate run** (the scratchpad tmpfs, 32 GB, at 21:48). The run was stopped. To make room, I deleted
    the regenerable Verilator object directories of earlier checkpoints' build trees in the scratchpad: 604 directories
    named `obj`, `obj_old`, `obj_new`, `sobj`, `robj`, `mv` or `fxv` (list in `scratchpad/cp6/deleted_objdirs.txt`). No
    text output, script, snapshot or reference was deleted. The gate run was then repeated from the start.

### Open items

- **Quartus has not compiled any of this.** To check in the compile:
  - ALMs of the `_lh` revisions. Estimate (yosys × 0.57): +130 to +160 on the 68000 family, +130 to +150 on the 68010,
    +130 to +200 on the 020s.
  - That `m68ksv_drom1*_lh` is built in logic (`romstyle "logic"`) and not optimised away (map.rpt).
  - The new path `ua_n` → micro-ROM address in the `_lh` revisions.
  - The `ua_n` → ROM address path in the 68010 default (the same read-ahead as `RES = 1`).
- **Fewer M10K are still possible:** `drom3` in logic gives 6 (68000), and `drom2` as well gives 5, at an estimated +100 /
  +200 ALMs. A third `RES` value would be a small generator / generate change plus one more A/B run.
- **68000-family ROM width:** 91 of the 93 bits are non-constant. At ≤ 90 bits the 1,024-deep ROM would take 9 M10K, but
  that needs a field re-encoding.
- **Before the first reset:** with `RES = 1` the micro-word is zero until the first reset (`rom[0]` with `RES = 0`). This
  is harmless: a CPU is reset before use, and the fleet wrapper's reset does this.
- Open items of earlier checkpoints are unchanged: see the Handover.

### Files changed / new (checkpoint 6)

- **Generator:** `rtl/gen/m68ksv_ucode.py`:
  - `compact000()` and its bisimulation check;
  - `SHARED_UA` moved before it; `LABELS_PRE`;
  - `rom_module` (style parameter), `rom_module_split`;
  - `UCS_GROUPS`, `m10k_blocks`, `emit_ucs`;
  - `drom1*_lh` and `drom1lp_010_lh`;
  - package constant `UA000_W`;
  - labels header `UA0_*`.
- **RTL:**
  - `rtl/m68ksv_eu.sv`: parameter `RES`, `ua_ce` / `ua_n` / `ua_e2`, the `g_lh` / `g_bh` generate branches.
  - `rtl/m68ksv.sv`, `rtl/m68ksv_fleet.sv`: parameter `RES`.
- **Regenerated:**
  - `rtl/m68ksv_upkg.sv`: +`UA000_W`.
  - `rtl/m68ksv_urom.sv`: 68000 ROM compacted, 68010 ROM split, 3 new `m68ksv_ucs*` modules.
  - `rtl/m68ksv_drom.sv`: 68000 `drom2` / `drom3` contents, 4 new `_lh` modules.
  - `rtl/m68ksv_all.sv`.
  - `verify/tb/m68ksv_ualabels.h`: +`UA0_*`.
- **Quartus:**
  - `syn/quartus/m68ksv_qtop.sv`: `ifdef M68KSV_RES`, header comment.
  - New: `syn/quartus/m68ksv_qtop_{68000,68008,68008fn,68ec000,68010,68020,68ec020}_lh.qsf`.
  - `syn/quartus/m68ksv_qtop.qpf`: 7 revisions added.
  - Unchanged: the existing .qsf files and `files.qip`.
- **Harness:** `M68KSV_RES` in `verify/build.sh`, `verify/mus010_build.sh`, `verify/mus020_build.sh`,
  `verify/dsz020_build.sh`, `verify/amiga020_build.sh`, `verify/mame8_build.sh`, `verify/lockstep_build.sh`.
- **Docs:** `REPORT.md` (status, this section, Handover), `DESIGN.md` (sections 1, 3, new 3.1, 9, 10), `README.md`,
  `syn/quartus/README.md`.
- **Not touched:** `fleet_types.svh`, `files.qip`, the existing .qsf files, the fx68k / MAME / Musashi sources,
  `/Work/Build/amiberry/`.

### Compile commands (the user; Quartus 17.0, from `syn/quartus/`)

```bash
# minimum set (*): the 68000, 68010 and 68EC020 in both settings, plus every default revision whose RTL changed
quartus_sh --flow compile m68ksv_qtop                            # * 68000    default (compacted ROM)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68000_lh    # * 68000    logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010       # * 68010    default (split ROM)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68010_lh    # * 68010    logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020     # * 68EC020  default
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec020_lh  # * 68EC020  logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008       # * 68008    default (compacted ROM)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn     # * 68008FN  default (compacted ROM)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000     # * 68EC000  default (compacted ROM)
# the rest
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020       #   68020    default (ROM contents unchanged)
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008_lh    #   68008    logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68008fn_lh  #   68008FN  logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68ec000_lh  #   68EC000  logic-heavy
quartus_sh --flow compile m68ksv_qtop -c m68ksv_qtop_68020_lh    #   68020    logic-heavy
# then, for each compiled revision:  quartus_sta -t timing_paths.tcl <revision>
```

- **The 68020 default is the one revision outside the minimum set.** The EU's RTL changed for every CPU, but in the 020
  build the new wires and generate branches fold back to the start's logic, and its ROM contents are byte-identical.
  The 68EC020 default is in the minimum set, so the 68020 default can wait.
- **What to look at in the `_lh` revisions:** see `syn/quartus/README.md`.

### Measured Quartus results (user's compiles 2026-11-16 23:37 – 2026-11-17 00:05, all 14 revisions; `timing_paths.tcl` run on each)

Total RAM blocks include the test top's RAM: 8 M10K on the 16-bit / 8-bit builds and 8 on the 020 builds. CPU M10K =
total − 8.

| Revision | ALMs | Registers | RAM blocks (CPU) | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|---|
| 68000 default | **1,785** | 1,271 | 24 (**16**) | 1 | 113.77 / 116.54 MHz | +1.627 / +1.836 ns | +0.331 ns |
| 68000 logic-heavy | **1,990** | 1,331 | 15 (**7**) | 1 | 117.80 / 121.37 MHz | +1.928 / +2.178 ns | +0.325 ns |
| 68008 default | 1,798 | 1,286 | 24 (16) | 1 | 111.53 / 113.68 MHz | +1.451 / +1.620 ns | +0.261 ns |
| 68008 logic-heavy | 2,018 | 1,320 | 15 (7) | 1 | 111.57 / 109.09 MHz | +1.454 / +1.250 ns | +0.274 ns |
| 68008FN default | 1,812 | 1,281 | 24 (16) | 1 | 117.63 / 112.18 MHz | +1.916 / +1.503 ns | +0.324 ns |
| 68008FN logic-heavy | 1,998 | 1,344 | 15 (7) | 1 | 115.09 / 117.05 MHz | +1.728 / +1.874 ns | +0.330 ns |
| 68EC000 default | 1,807 | 1,294 | 24 (16) | 1 | 119.16 / 118.48 MHz | +2.025 / +1.977 ns | +0.284 ns |
| 68EC000 logic-heavy | 2,013 | 1,361 | 15 (7) | 1 | 113.83 / 119.36 MHz | +1.632 / +2.039 ns | +0.305 ns |
| 68010 default | 2,390 | 1,764 | 32 (24) | 1 | 106.72 / 110.20 MHz | +1.047 / +1.343 ns | +0.266 ns |
| 68010 logic-heavy | 2,557 | 1,705 | 18 (10) | 1 | 112.92 / 113.20 MHz | +1.561 / +1.583 ns | +0.322 ns |
| 68020 default | 3,926 | 2,482 | 38 (30) | 4 | 115.22 / 113.61 MHz | +1.738 / +1.615 ns | +0.054 ns |
| 68020 logic-heavy | 4,129 | 2,565 | 20 (12) | 4 | 110.17 / 107.84 MHz | +1.340 / +1.144 ns | +0.046 ns |
| 68EC020 default | 3,889 | 2,506 | 38 (30) | 4 | 107.68 / 105.73 MHz | +1.130 / +0.959 ns | +0.064 ns |
| 68EC020 logic-heavy | 4,102 | 2,516 | 20 (12) | 4 | 113.31 / 107.99 MHz | +1.592 / +1.157 ns | +0.050 ns |
| fx68k (reference, 2026-11-15) | 2,047 | 1,546 | 14 (**6**) | 0 | 100.00 / 99.13 MHz | +0.417 ns (worst) | |

- **Every revision ≥ 105.7 MHz.** The CPU M10K counts equal the exact table above on all 14.
- **68000:** the default build is 1,785 ALMs / 16 M10K (down from 25). Logic-heavy is 1,990 ALMs / 7 M10K. Both are
  under fx68k's 2,047 ALMs and faster than fx68k's 100 MHz; logic-heavy is within one block of fx68k's 6 M10K.
- **Logic-heavy costs** about +170 to +220 ALMs and saves 9 (68000 family), 14 (68010) or 18 (020) M10K.
- **The decode tables are really in logic, not optimised away:** `m68ksv_drom1_lh` 181.1 ALMs (68000),
  `m68ksv_drom1_010_lh` 196.7 + `drom1lp` 26.3 (68010), `m68ksv_drom1_020_lh` 189.7 (68EC020).
- **The new micro-ROM address path is not the worst path in any `_lh` revision.** The worst paths are ROM / register
  outputs into `res`, `uw`, `q_exc`, `dv_ov` and `im`, 2–10 levels.
- **The 68020 / 68EC020 defaults are identical to the previous compile** (to the ALM and ps), as expected: their logic
  folds back to the start's.
- **Hold:** still thin on the 020 builds (+0.046 to +0.064 ns), positive. Everything else is ≥ +0.26 ns.

## Handover (checkpoints 5 and 6)

### What each CPU is verified against (final RTL of checkpoint 5; checkpoint 6 changed no behaviour)

| CPU (`CPU` value) | Oracle / test | Key result |
|---|---|---|
| 68000 (68000) | Tom Harte 68000 suite (`run_all.sh`): registers, RAM, prefetch queue, bus order, cycle count; also with 0–3 random idle clocks between phase enables | 794,139 / 794,139 pure; corrected 202,181 / 202,182; timed 797,878 |
| 68000 | fx68k pin-level lockstep (`lockstep`, 20 rows: plain, waits, IRQ, VPA, BR, HALT, reset, BERR, mixed) | rows with plain / waits / VPA / HALT: 0 mismatching runs; BR / IRQ / reset / BERR / mixed rows 1–4 of 64 (open items, unchanged since checkpoint 2) |
| 68000 | directed: `smoke` 3 / 3, `retry` (bus retry) 8 / 8 | |
| 68008 (68008), 68008FN (68009), 68EC000 (68001) | the 68000 suite on each build (`run_family.sh`: 8-bit bus for the 68008s and the 68EC000 with MODE = 0, 16-bit 68EC000); MAME m68008 bus-cycle lockstep (`mame8`, 40 × 300,000 clocks each); fx68k lockstep for the 68EC000 16-bit | suite 794,137 / 794,139 / 794,139 / 794,139 pure, corrected 202,181 each; `mame8` 0 mismatching runs ×3; fx68k EC rows 0 |
| 68010 (68010) | Musashi m68010 lockstep (`mus010`, 4 rows + `-cyc`); `rerun010` (format-8 RTE re-run, 7 seeds); `loop010` (loop mode); the 68000 suite on the 010 build (classified 010 differences) | 0 mismatching runs; `-cyc` 154,783 / 159,119 times equal to Musashi; 0 failures; suite 781,979 / 794,139 pure (corrected 9,793), differences = 68010 behaviour |
| 68020 (68020), 68EC020 (68021) | Musashi m68020 / m68ec020 lockstep (`mus020`, 13 rows: random suite opcodes + 020 snippets, all port widths, IRQ, BR, HALT, reset, bit fields); directed `dsz020` (dynamic sizing, bus edges, bus errors), `cache020`, `rmc020`, `cop020`, `tim020` (manual timing); `rerun020` (format-B RTE re-run self-check); the 68000 suite with `-bus32` (classified); **2026-11-16: `amiga020`** (the Amiberry / WinUAE behaviour cases: the run's logged values and WinUAE's rules) | `mus020` 0 mismatching runs on all 13 rows (WinUAE-rule differences classified and counted); `amiga020` 285 / 285 checks; directed tests 0 failures; `rerun020` 6 of 12 runs mismatching (open); bus edges as the MC68020 User's Manual (checkpoint 5 table); undefined / disputed behaviour as WinUAE's 68020 core ("68020 behaviour from WinUAE") |

**Both `RES` settings (checkpoint 6).** `RES = 1` is clock-exact against `RES = 0` on all seven configurations (A/B,
every output every clock, 0 mismatching runs, planted faults caught). The 68000 suite (`run_all.sh`), one `mus010` row
and two `mus020` rows were also run with `RES = 1`: output byte-identical to `RES = 0`.

### Quartus before checkpoint 5 (the user's compile 2026-11-16 13:51–14:30, fold-away-fix RTL; slow 100 °C / worst corner)

| Revision | ALMs | Registers | DSP | Fmax | Worst setup slack |
|---|---|---|---|---|---|
| 68000 | 1,869 | 1,374 | 1 | 106.38 MHz | +1.017 ns |
| 68008 | 1,879 | 1,407 | 1 | 115.43 MHz | +1.754 ns |
| 68008FN | 1,918 | 1,400 | 1 | 107.94 MHz | +1.153 ns |
| 68EC000 | 1,901 | 1,398 | 1 | 107.10 MHz | +1.080 ns |
| 68010 | 2,482 | 1,768 | 1 | 115.01 MHz | +1.200 ns |
| 68020 | 4,128 | 2,597 | 4 | 111.72 MHz | +1.318 ns |
| 68EC020 | 4,099 | 2,574 | 4 | 111.48 MHz | +1.133 ns |
| fx68k (size reference) | 2,047 | | | | |

### Quartus after checkpoint 5 (the user's compiles 2026-11-16 16:59–17:14, final RTL; `timing_paths.tcl` run on each)

| Revision | ALMs (before → after) | Registers | RAM blocks | DSP | Fmax slow 100 °C / −40 °C | Setup slack 100 °C / −40 °C | Hold (min) |
|---|---|---|---|---|---|---|---|
| 68000 | 1,869 → **1,791** | 1,292 | 33 | 1 | 113.42 / 106.87 MHz | +1.600 / +1.060 ns | +0.282 ns |
| 68008 | 1,879 → **1,795** | 1,272 | 33 | 1 | 120.89 / 115.02 MHz | +2.145 / +1.723 ns | +0.327 ns |
| 68008FN | 1,918 → **1,791** | 1,291 | 33 | 1 | 120.54 / 119.30 MHz | +2.121 / +2.035 ns | +0.311 ns |
| 68EC000 | 1,901 → **1,807** | 1,303 | 33 | 1 | 119.49 / 117.47 MHz | +2.048 / +1.904 ns | +0.283 ns |
| 68010 | 2,482 → **2,299** | 1,632 | 36 | 1 | 110.08 / 109.95 MHz | +1.333 / +1.322 ns | +0.319 ns |
| 68020 | 4,128 → **3,949** | 2,456 | 38 | 4 | 107.96 / 109.35 MHz | +1.154 / +1.272 ns | +0.091 ns |
| 68EC020 | 4,099 → **3,951** | 2,417 | 38 | 4 | 111.92 / 111.25 MHz | +1.482 / +1.428 ns | +0.166 ns |

- **Every revision ≥ 106.87 MHz** with worst setup slack ≥ +1.06 ns.
- **The 68000 family is under the sixth-session sizes (1,815 / 1,788 / 1,814 / 1,816),** except the 68008 at +7. All
  four are well under fx68k's 2,047.
- **The 68010 is at 2,299: 99 ALMs over the 2,200 target.** The yosys estimate was ≈ 2,227.
- **The 68020 / 68EC020 are ≈ 150 ALMs smaller.** The 68020's worst path is now `ir` → `bf_flq` (bit-field stage 1,
  7 levels). Its minimum hold slack is +0.091 ns at −40 °C: positive, but the thinnest of any revision.

### Open items (consolidated)

- **68000 family:** run-ahead during BR / HALT waits (fx68k keeps executing bus-free micro-words while a prefetch
  waits; m68ksv holds the word; visible as address / bus-error frames after a wait and in the fx68k BR / mix rows);
  reset mid-instruction (register writes one word earlier than fx68k's T3 in non-bus-error words; `-rst` rows); `-irq`
  seed 101 run 41 and `-berr 50` seed 202 run 47 not traced; checkpoint-2 reset leftovers (reset mid-instruction CCR, 4
  of 64 runs at the time).
- **68010:** none known beyond the 68000's; 2,299 ALMs measured against the 2,200 target (99 over).
- **68020 / 68EC020:** `rerun020` 6 of 12 runs (format-B RTE re-run self-check: remaining differences after a bus
  error in some data / prefetch cases); CALLM / RTM (illegal instruction on the 68020); long writes as two word
  requests; instruction times (no overlap; `tim020`: mean +1.75 clocks over the manual's cache case); coprocessor
  primitives other than null / busy, null IA and PC; late BERR + HALT taken as a bus error; ECS / OCS a quarter clock
  late; the 68020 build needs two or more `clk` between CPU edges (below). WinUAE survey follow-ups (section "68020
  behaviour from WinUAE"): DIV.W / DIV.L divide-by-zero flags, MUL.L with Dh = Dl, the BCD V flag (WinUAE: 0 on the
  68020), the stacked PC / A7 of JSR / DBcc / RTR to an odd address. **#unverified: the address-error SSW** follows
  the MC68020 User's Manual (RB / RC set, $3066), not WinUAE ($0066, whose frame is "partially implemented only"); no
  real 68020 has settled it - if evidence (e.g. `verify/amiga020` run on a real 68020 Amiga) shows it is wrong, fix it
  (`DWX_SSW20` in `rtl/m68ksv_eu.sv`, `SSW_AE` in `verify/tb/amiga020.cpp`). The 68020 / 68EC020 need a recompile for
  the 2026-11-16 SSW / CHK2-margin change (section "SSW back to the manual, CHK2 margin").
- **Quartus:** checkpoint 5 compiled, every revision ≥ 96 MHz (table above). The 68020's hold slack is thin (+0.091 ns;
  +0.058 / +0.062 ns on the 68020 / 68EC020 after the WinUAE change). It was +0.185 / +0.136 ns after the SSW /
  CHK2-margin compile.
- **Resource-placement switch: done (checkpoint 6, section "Checkpoint 6").** Parameter `RES`: 0 = BRAM-heavy
  (default), 1 = logic-heavy.
  - CPU M10K (exact from the ROM shapes): 16 / 7 (68000 family), 24 / 10 (68010), 30 / 12 (68020s). fx68k: 6.
  - **Compiled 2026-11-17, all 14 revisions** (table in the checkpoint 6 section):
    - 68000: 1,785 ALMs / 16 M10K default and 1,990 / 7 logic-heavy, every revision ≥ 105.7 MHz;
    - `drom1` is built in logic (181–197 ALMs);
    - the micro-ROM address path is not the worst path.
  - **Open:**
    - `drom2` / `drom3` in logic would give 5 M10K (68000), estimated +200 ALMs;
    - with `RES = 1` the micro-word is zero before the first reset.
- **Hardware: not yet run in a real core.** First attempt on 2026-11-17, in a third-party Gauntlet core, not completed:
  - **Setup:**
    - test bed `/Work/Projects/Merge Project 1/Arcade-Gauntlet_MiSTer` (temporary; TG68K as its 68010);
    - adapter `rtl/lib/m68ksv/m68ksv_tg68k.sv`: 68010 build, `clk` 14.318 MHz with alternating enables aligned to the
      7.159 MHz board clock;
    - CPU select `constant USE_M68KSV` in `rtl/gauntlet/MAIN.vhd`.
  - **The core did not build as shipped:** duplicate `VGA_SL` driver; `jt51` submodule empty (jotego's jt51 copied
    byte-identical from Arcade-Williams).
  - **With m68ksv:** ROMs load; G1 / G2 show a flashing red box at the top.
  - **Not established:** there is no TG68K baseline, so the failure is not attributed to m68ksv.
  - **Abandoned:** the user deleted the test-bed core (it doesn't build from its own repo).
  - **Next:** an existing core with a known-good baseline (build its original CPU first), or our own Atari68K core.
    The adapter recipe above is enough to redo the swap.
  - Vault: [[m68ksv_2026-11-17]] (chips repo `Claude/`).

### How to rerun every gate

Paths: suite binaries `scratchpad/m68ksv_refs/bin68000` (`$M68KSV_TESTS`), corrections
`scratchpad/m68ksv_refs/suite_corrections.txt` (`$M68KSV_CORR`), fx68k source `scratchpad/m68ksv_refs/fx68k/fx68k-master`.
The build scripts run the generator: run builds one after the other, not alongside suite runs. Verilator 4.204
(`/usr/local/bin`) for the suite and directed tests, 5.052 (`/usr/bin/verilator`) inside `lockstep_build.sh` /
`mus*_build.sh` where the scripts say so. `scratchpad/cp5/gates.sh` + `fx.sh` run all of the below in that order.

```bash
# 68000 suite (+ idle clocks, smoke, retry) and the 68000-bus family
verify/run_all.sh <dir>                       # <dir>/run_all.txt, run_gap3.txt, smoke.txt, retry.txt
verify/run_family.sh <dir>                    # 68008 / 68008FN / 68EC000 8- and 16-bit
M68KSV_CPU=68010 verify/build.sh <dir>        # then <dir>/harte -x verify/suite_exclusions.txt -c <corr> <bins>
M68KSV_CPU=68020 verify/build.sh <dir>        # then <dir>/harte -bus32 ... (also 68021)
# fx68k lockstep (68000; M68KSV_CPU=68001 for the 68EC000 16-bit), from the build dir
verify/lockstep_build.sh <fx68k dir> <dir>; cd <dir>; ./lockstep -seed 101 -runs 64 -ticks 400000 [-w 3|-irq|-vpa|-br|-halt|-rst|-berr 50] <bins>
# MAME m68008 bus-cycle lockstep (68008 / 68009 / 68001)
verify/mame8_build.sh <dir> 68008; <dir>/mame8_68008 -cpu 68008 -seed 7 -runs 40 -clocks 300000 <bins>
# 68010
verify/mus010_build.sh <dir>; <dir>/mus010 -seed 41 -runs 8 -instr 10000 -mix 25 [-irq -w 2] <bins>; <dir>/mus010 -seed 21 -runs 8 -instr 20000 -mix 10 -cyc <bins>
<dir>/rerun010 -seed 6 -runs 10 -instr 5000 -p 30 -sw <bins>; <dir>/loop010
# 68020 / 68EC020 (13 mus020 rows, rerun020 and the directed tests: scratchpad/cp5/m20table.sh <tag>)
verify/mus020_build.sh <dir> [68021]; <dir>/mus020_68020 -seed 51 -runs 8 -instr 10000 -mix 0 -port 0 <bins> ...; <dir>/rerun020_68020 -seed 1 -runs 4 -instr 5000 -p 30 [-x020] <bins>
verify/dsz020_build.sh <dir> [68021]; <dir>/dsz020_68020 [-w 0] [-be 3|-be 4]; <dir>/cache020_68020 [-w 0]; <dir>/rmc020_68020 -port 0..3 -w 0|2; <dir>/cop020_68020 -w 0|2|5; <dir>/tim020_68020
verify/amiga020_build.sh <dir> [68021]; <dir>/amiga020_68020     # 2026-11-16: the Amiberry / WinUAE behaviour cases (scratchpad/winuae/m20table.sh runs it with the table)
# A/B equivalence of two RTL trees (clock-exact), all seven configurations. checkpoint 6 tool: scratchpad/cp6/abrun.sh
# (mkall file list, GOLD / GNEW = extra -G options, a 4th argument = the dbg_upc relation for the 68000-family rows)
scratchpad/cp6/abrun.sh <old rtl> <new rtl> <tag> [upc relation]   # against a pre-checkpoint-6 tree: M68KSV_UAREL=<file> python3 rtl/gen/m68ksv_ucode.py writes the relation
GNEW=-GRES=1 scratchpad/cp6/abrun.sh <rtl> <rtl> <tag>               # RES = 1 against RES = 0
# RES = 1 builds of any harness: M68KSV_RES=1 in front of verify/*build.sh / run_all.sh
# lint, Quartus-subset check, yosys
scratchpad/cp6/lint.sh <out> [tree]           # Verilator 4.204 --lint-only -Wall, 7 CPUs x RES 0 / 1 + m68ksv_qtop with 7 macros x M68KSV_RES
verify/tools/mkall.sh                         # regenerates rtl/m68ksv_all.sv and runs the Quartus 17 construct check
scratchpad/cp6/ys1.sh / ysq1.sh <tree> <cpu> <res> <out>   # yosys plain / Quartus-like with RES (res "-": a tree without RES)
```

### How a fleet core instantiates it

`rtl/m68ksv_fleet.sv` wraps `m68ksv` on the proposed master bus type in `fleet_types.svh` (`m68ksv_fleet_pkg::m68k_i_t`
/ `m68k_o_t`; to be merged into the fleet's `chip_pool_pkg` by the user — this repository does not touch the master):

```systemverilog
m68ksv_fleet #(.CPU(68000), .RES(0)) cpu (   // CPU: 68000 / 68008 / 68009 (68008FN) / 68001 (68EC000) / 68010 / 68020 /
                                            // 68021 (68EC020); RES: 0 = BRAM-heavy (default), 1 = logic-heavy
    .clk(clk_sys), .cen_p(cpu_cen_p), .cen_n(cpu_cen_n),   // CPU clock rising / falling edge enables, one clk each
    .i(m68k_i), .o(m68k_o)
);
```

- Files: `rtl/m68ksv_all.sv` (everything in one file, Quartus) or the separate `rtl/*.sv` in the order of `mkall.sh`'s
  list, plus `rtl/m68ksv_fleet.sv` and `fleet_types.svh` (the package must be compiled first).
- `cen_p` / `cen_n` mark the CPU clock's rising / falling edges inside `clk`. 68000 family / 68010: any spacing (the
  suite also runs with random idle clocks). **68020 / 68EC020: one micro-cycle per CPU clock, so there must be at
  least two `clk` between consecutive CPU edges (e.g. clk / 4: `cen_p` every fourth clock, `cen_n` two clocks later);
  clk / 2 is too fast.**
- Bus fields: 68000 / 68010 drive `o.a[23:1]`, `o.uds_n` / `o.lds_n`, `o.d[15:0]`, take `i.dtack_n`, `i.vpa_n`; the
  68008s use `o.a[0]` / `o.ds_n` and `i.d[7:0]`; the 68EC000 samples `i.mode` at reset; the 68020s use `o.a[31:0]`
  (EC020: [23:0]), `o.d` / `i.d` 32 bits, `o.ds_n`, `o.siz`, `i.dsack_n`, `i.avec_n`, `i.cdis_n`, `o.rmc_n`;
  `i.sterm_n` is ignored (no STERM on the 68020; tie it high). Unused inputs: tie to their inactive level.
- `RES` (checkpoint 6): 0 keeps the microcode and decode ROMs in M10K (fewest ALMs; 16 / 24 / 30 CPU M10K), 1 moves
  them to a two-level control store and logic (7 / 10 / 12 CPU M10K, more ALMs). Same behaviour, clock for clock.
- Synthesis: Quartus 17.0, no vendor IP; ROMs infer as M10K, the register file as MLAB (see `syn/quartus/README.md`
  for the checks after a compile).

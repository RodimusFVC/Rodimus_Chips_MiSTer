# x86sv — report (checkpoint 9: V20 / V30 8080 emulation mode)

x86sv is our own SystemVerilog 8088 / 8086 / V20 / V30 (`DESIGN.md`). Checkpoints 1-6 (8088) are below unchanged;
checkpoint 7 added the 8086 (`x86sv16`, cycle-exact) and the NEC option; checkpoint 8 fits the V20's own clock
timing and adds ADD4S / SUB4S / CMP4S, INS / EXT and the NEC MUL / DIV / AAM rules: the V20 is cycle-exact on the
whole V20 suite (section "Checkpoint 8"); checkpoint 9 adds the NEC 8080 emulation mode as option `NEC8080` with
its own model-generated suite (section "Checkpoint 9").

## Summary per configuration

| Config | Top | Suite | Files | Tests passing all comparisons | Registers | RAM | Cycles + bus |
|---|---|---|---|---|---|---|---|
| 8088 | `x86sv` | 8088 v2 | 323 / 323 | 3,007,000 / 3,007,000 | 100 % | 100 % | 100 % |
| 8086 | `x86sv16` | 8086 v1 | 323 / 323 | 646,000 / 646,000 | 100 % | 100 % | 100 % |
| V20 | `x86sv #(.NEC(1))` | V20 v1 native | 360 / 360 | 3,125,000 / 3,125,000 | 100 % | 100 % | 100 % |
| V30 | `x86sv16 #(.NEC(1))` | V20 v1 native, registers / RAM only | — | — | 100 % | 100 % | not comparable (no V30 suite) |
| V20 + 8080 | `x86sv #(.NEC(1), .NEC8080(1))` | V20 v1 native | 360 / 360 | 3,125,000 / 3,125,000 | 100 % | 100 % | 100 % |
| V20 + 8080 | same | own 8080-mode suite (`verify/suites/v20_8080`) | 264 / 264 | 657,673 / 657,673 | 100 % | 100 % | no cycle column (no document) |
| V30 + 8080 | `x86sv16 #(.NEC(1), .NEC8080(1))` | own 8080-mode suite | 264 / 264 | 657,673 / 657,673 | 100 % | 100 % | no cycle column |

Exclusions / tolerances: 8088 floating-AD drift (2,621 tests, unchanged); 8086 inactive half of AD15-0 after a
single-lane write (61,992 tests, suite README BHE rule). Nothing else is skipped or masked. Directed tests: 42 / 42
(8088). Fleet wrapper test: 21 / 21 (`x86sv_mcl86` vs `x86sv_i8088`) + 6 / 6 each for `x86sv_i8086`, `x86sv_v20`,
`x86sv_v30`. 8088 and 8086 unchanged by the later work: formal equivalence (section "Zero cost when off"). The V20
suite has no exclusion and no tolerance (drift and lane columns 0); undefined flags are compared.

## 8088 result (checkpoint 6, re-run at checkpoint 7)

| Group | Files | Tests | Pass | Drift accepted |
|---|---|---|---|---|
| ALU: 00-3D, 80-83 | 80 | 800,000 | 800,000 | 0 |
| MOV (all forms) | 28 | 280,000 | 280,000 | 0 |
| INC / DEC | 20 | 200,000 | 200,000 | 0 |
| PUSH / POP (incl. PUSHF / POPF) | 28 | 280,000 | 280,000 | 0 |
| BCD, XCHG AX, CBW / CWD, SAHF / LAHF, SALC, flag ops | 24 | 177,000 | 177,000 | 0 |
| Control transfer: Jcc (+ 60-6F aliases), JMP / CALL / RET near + far (+ C0 C1 C8 C9 aliases), LOOP / JCXZ, INT / INT3 / INTO / IRET, FF /2-/5 | 57 | 570,000 | 570,000 | 0 |
| TEST, XCHG, LEA, LDS / LES, XLAT, NOT / NEG | 18 | 180,000 | 180,000 | 0 |
| String ops with / without REP | 10 | 20,000 | 20,000 | 0 |
| Shift / rotate incl. SETMO / SETMOC (D0-D3 /0-/7) | 32 | 240,000 | 240,000 | 2,621 |
| MUL IMUL DIV IDIV (incl. divide error) AAM AAD | 10 | 100,000 | 100,000 | 0 |
| ESC | 8 | 80,000 | 80,000 | 0 |
| IN / OUT | 8 | 80,000 | 80,000 | 0 |
| **All `v2_binary` files** | **323** | **3,007,000** | **3,007,000** | **2,621** |

Every test passes all four comparisons (registers incl. every flag, RAM, cycle count, per-cycle bus / queue trace);
84,150,872 bus clocks compared. "Drift accepted" is explained below; no test is skipped and nothing is masked.
Directed tests: 42 / 42 pass (section "Directed tests"). Fleet wrapper test: 21 / 21 runs pass. `v2_undefined/` is
not in the local copy of the suite and was not run. Every number above was re-checked after each timing change.

## Method

As in checkpoint 1: `verify/tb/sim.cpp` (Verilator, own bounds-checked MOO reader `tb/moo.h`; the suite's tools are
not used). Per test: reset, load registers, flags, queue (0 or 4 bytes) and prefetch pointer through the test-only
load path (`X86SV_TESTLOAD`), run from the first first-byte QS to the next instruction's first byte, then compare
(a) all 14 registers incl. the whole FLAGS word, (b) every final RAM byte and no other byte written, (c) the cycle
count, (d) every clock's ALE, 20-bit bus, segment status, 8288 strobes, BHE, data, bus status, T-state, QS and
queue byte. `-s` / `-e K` / `-i k` print per-clock dumps or event summaries of failures.

### What the runner models from the capture rig (not exclusions; listed for review)

| Item | Why | Scope |
|---|---|---|
| AD bus value before the first bus activity of a prefetched test | Set-up residue of the rig; loaded like the registers, held by the CPU until it drives the bus | 1,503,500 prefetched tests, first 2 clocks |
| Code fetches after the instruction bytes return 0x90 | The rig serves NOP to every later fetch (suite README) | all tests |
| I/O reads return 0xFF | Suite README ("All forms of the IN instruction should return 0xFF") | E4 E5 EC ED |
| **Floating AD7-AD0 drift** | After a read, AD7-AD0 are inputs (8088 datasheet: they float). After >= 152 idle clocks the rig sees these floating lines drift from the last value towards 1 (always 0 -> 1, bit 2 first, at 152-259 clocks, not reproducible in time). The runner accepts an AD mismatch only when: both traces are in Ti, >= 128 clocks after the last T4, A19-A8 equal, and every differing bit is 0 in the CPU's value and 1 in the trace. Counted per file in the `drift` column. | 2,621 tests, only in D2 / D3 (long shift counts) |

Build note: Verilator 4.204 C++ with GCC 16 at `-O2` miscompiles the model unless `-fno-strict-aliasing` is given
(string-op files failed only in the `-O2` build; `-O1` and sanitizer builds passed). `verify/build.sh` sets the flag.

### Exclusions

None. No test is skipped, no field or flag is masked, nothing was re-baselined.

## Findings from the hardware data (behaviour fitted to the traces)

Timing is reproduced by the BIU / EU model of checkpoint 1 plus per-instruction step lists; these rules are what the
new groups needed beyond plain step lists:

- **DAA / DAS**: the high adjust condition is `AL > (AF ? 9F : 99) or CF` (not `> 99`). OF = signed overflow of the
  adjust. **AAA / AAS** take 8 clocks when adjusting, 9 when not; **CWD** 5 / 6 clocks (AX positive / negative);
  **SALC** 3 / 4 (CF 0 / 1).
- **Shifts**: by-1 forms of register operands have no execute clock (2 clocks total); by-CL forms 8 + 4n with one
  1-bit step per 4 clocks, CL not masked, count 0 leaves the flags. SHL AF = result bit 4; SHR / SAR / SETMO AF = 0;
  SETMO (D0 /6) gives all ones, CF = OF = 0.
- **MUL** = base + popcount(multiplier) + 1 if the high half is zero (MUL8 69, MUL16 117 register form).
  Flags: SF / ZF / PF of the high half, AF 0, CF = OF = high half non-zero.
- **IMUL** = base(signs) + popcount(|AL / AX|) + 1 if the high half is the sign extension; bases 79 / 90 / 93 / 80
  (8-bit) and 127 / 138 / 141 / 128 (16-bit) for (+,+) (+,-) (-,+) (-,-); -1 when the source is the most negative
  value and AL / AX is positive. SF ZF AF PF are the flags of `high + sign bit of low` (100 % of the data).
- **DIV** = base + one clock per quotient 1-bit not forced by a carry, the last bit +3 (forced: +2); bases 80 / 144.
  SF ZF AF PF OF are those of the last loop subtraction done without a carry out (or of the pre-check), CF = NOT
  quotient MSB. **IDIV** bases 101 / 100 / 105 / 104 and 165 / 164 / 169 / 168 by signs; same SF ZF AF PF, OF = CF = 0;
  a REP prefix inverts the quotient sign (suite README). **AAM** = DIV8 on {0, AL} (77 + ...), SF ZF PF from AL, the
  rest 0; **AAD** = 59 + popcount(imm), flags of the final `AL + AH*imm` add.
- **Divide error**: the pre-check (`|high| >= |divisor|`) leaves its own subtraction flags and enters INT 0 after a
  fixed delay (DIV 79 clocks total, IDIV 88-93 by signs, AAM 77); IDIV's quotient-range error comes after the full
  loop. The pushed IP is the next instruction (suite README).
- **INT / exceptions**: vector reads use segment 0 with "CS or none" status; order: vector IP, vector CS, (SUSP),
  push FLAGS, IP-correction clock, push CS, flush, first fetch, push IP. INT3 / INTO / INT n share the sequence with
  different entry delays. Far CALL / INT push CS before the flush and IP after it.
- **String ops**: one loop per element; REP re-checks CX and (CMPS / SCAS) ZF at fixed points; CX = 0 ends after
  7 clocks; F2 and F3 both repeat MOVS / STOS / LODS.
- **ESC** with a memory operand performs a dummy word read of the operand.

## Directed tests (`verify/tb/dsim.cpp`, `dsim`)

Sources: **[DS]** Intel 8088 datasheet, order 231456 (pin descriptions, "Processor Reset and Initialization",
"Interrupt Operations", Figure 9 Interrupt Acknowledge Sequence). **[PR]** iAPX 86, 88, 186 and 188 User's Manual
Programmer's Reference, order 210911-001, section 4.3 (Interrupts), Table 4-1 (priorities), Table 4-2 (state after
RESET), instruction reference (HLT, WAIT, REP, INT).

| Test | Checks | Source |
|---|---|---|
| Reset (4) | no ALE / strobes while RESET high; CS FFFF, IP 0, DS SS ES 0, flags clear; first bus cycle = code fetch at FFFF0, first T1 9 clocks after RESET falls (7-clock internal sequence + idle-bus start); execution continues | [DS] RESET pin, "Processor Reset and Initialization" (~7 clocks); [PR] Table 4-2 |
| Wait states (18) | 1, 2, 5 Tw on code fetch, byte / word memory read, memory write, I/O read, I/O write: states T1 T2 T3 Tw..Tw T4; RD / INTA / AMWC active in T2 T3 Tw; ALE only in T1; S2-S0 active in T1 T2 and in T3 / Tw while READY is low, passive in the T3 / Tw with READY high; every later bus cycle starts exactly the accumulated Tw count later than in the zero-wait run (same addresses / data) | [DS] READY, RD, WR, S2-S0 pin descriptions; "wait states (Tw) are inserted between T3 and T4" |
| INTA pair (3) | 0, 1, 3 Tw: two INTA cycles back to back, LOCK from T2 of the first to T2 of the second | [DS] Figure 9, "Interrupt Operations" |
| INTR (7) | INTA, INTA, vector from the second cycle, vector words at 4n (IP then CS), FLAGS / CS / IP pushed, return = next instruction, IF and TF cleared; masked by IF = 0; not after MOV SS / POP DS; STI enables only after the next instruction; never between prefix and instruction | [DS] INTR pin; [PR] 4.3 "External Interrupts", "Interrupt Procedures" |
| NMI (2) | type 2 without INTA, before a simultaneous INTR; edge triggered (held high = one interrupt) | [DS] NMI pin; [PR] Table 4-1 |
| Single step (2) | trap (type 1) after the instruction following the one that set TF; INT n with TF set traps before the handler's first instruction | [PR] 4.3 "Single-Step (Trap) Interrupt", Figure 4-10 |
| REP + INTR (1) | interrupt between elements, CX / DI reflect completed elements, return address = the REP prefix (the segment prefix before it is lost) | [PR] REP instruction description |
| HLT (2) | one HALT status cycle, no bus activity until INTR, return after HLT; left by NMI with IF = 0 | [DS] "HALT"; [PR] HLT |
| WAIT (2) | 4 clocks with TEST low, +5 per TEST sample while high; interrupt while waiting returns to the WAIT | [PR] WAIT (4 + 5n); [DS] "External Synchronization via TEST" |
| LOCK (1) | LOCK active from the clock after the LOCK prefix through the last bus cycle of the locked XCHG, then released | [DS] LOCK pin, "Read/Modify/Write (Semaphore) Operations via LOCK" |

**Inferred (not stated in the documents; marked here):** the clock at which INTR / NMI / TF are taken is the clock
that applies the finished instruction's write-back; after the INTA pair (and for NMI / TF directly) the interrupt
continues with the same internal sequence as INT n from its first vector read; the HALT cycle is a 4-clock cycle
without strobes after the prefetch is suspended; a REP string op is interrupted at its loop-back point (TF does not
break a REP); S5 (A18 in T2-T4) = IF, unverified because IF = 0 in every suite test; the exact reset-to-first-T1
count (the datasheet says "approximately 7 clock cycles").

## Timing restructuring and yosys Cyclone V estimate (`verify/tools/yosys.sh`)

yosys 0.66 `synth_intel_alm -family cyclonev`, test-load path off. An estimate, not Quartus; the Quartus 17 project
in `syn/quartus/` gives the real numbers.

| | Checkpoint 2 | Checkpoint 3 | Checkpoint 4 |
|---|---|---|---|
| LUT cells (ALUT2-6) | 3,177 | 3,032 (305 / 505 / 593 / 1,176 / 453) | 2,919 (338 / 544 / 639 / 1,013 / 385) |
| Carry-chain cells | 714 | 702 | 713 |
| Registers | 656 | 720 | 1,078 |
| MLAB / M10K / DSP | 8 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Longest path incl. carry cells (FFs cut) | 47 | 35 | 36 |
| Longest LUT-only path | 20 | 15 (into an output pin) | 10 |
| Longest LUT-only path, register to register | (not measured) | 14 | 10 |

abc's result moves by about one level between runs of near-identical source (it fills shorter paths up to the
longest during area recovery); checkpoint 4 measured 10-11 over its last changes.

Quartus 17 on the checkpoint-3 RTL (user run): 2,063 ALMs, 919 registers, fmax 82.23 MHz (slow 100C), all worst
paths `cls -> r[0][12] / r[3][12]` (step decode -> register-file write).

Checkpoint 3 (each change kept the suite, the directed tests and the wrapper test at 100 %; no 8088 clock moved):
interrupt acceptance no longer waits for the write-back flag mux; queue as a shift register with the head in `q0`;
MUL / DIV pre-check, negation and flags in their own registered clocks; ALU result registered (`alu_q`) with the
immediate high byte forwarded; BIU suspend independent of the same-clock EU request.

Checkpoint 4 (same rule after every change; no 8088 clock moved):

1. **Write-back decided one clock early.** In an instruction's last clock (and in the XCHG / LODS register steps) the
   EU registers per-register byte-lane enables, a one-hot source select and the values that are final then; the next
   clock applies them with an AND-OR mux (no priority chain). Port 2, SP, segment and flags likewise. This removes
   `cls -> step-done -> write enables -> register file`, the Quartus critical path.
2. **Step writes registered.** SP / SI / DI / CX updates and flags written by a step (CMPS / SCAS flags, shift-loop
   flags, divide pre-check / overflow flags, INT clearing T / I) are registered and applied one clock later; nothing
   reads them in that clock (SP is forwarded to a following stack step).
3. **Micro-ops registered.** The next step's micro-operations are decoded one clock early from a one-hot next-step
   register and the one-hot class (`k1`), and registered; the step's "what am I waiting for" is registered one-hot;
   conditions known only in the step's clock (Jcc / LOOP condition, CX = 0, ZF for REPE / REPNE, IRQ, TEST, BCD
   adjust, divide error, CWD / SALC data) are one-hot end-condition selects evaluated then. The binary step counter is
   gone.
4. **Class one-hot everywhere.** `cls` is replaced by the 48-bit one-hot `k1`; the operand width and "has ModRM" are
   registered with the opcode; the queue head's class is decoded straight from `q0` (the registered next-head class
   from checkpoint 3 let yosys share the three class decoders behind the pop mux, putting the pop in front of the
   decoder).
5. **Interrupt acceptance.** "INTR allowed and IF as the instruction leaves it" is registered with the write-back
   (IF from POPF / IRET is the only part left to the next clock: one AND with the popped word's bit 9).
6. **Queue.** Both pop cases of the queue's next state are formed in parallel and selected by the pop last.
7. **Operands.** The shifter works from a registered operand (register-form shifts by 1 and BCD adjusts compute in
   the write-back clock); one adder for add / subtract in the ALU; S / Z / P of the ALU derived from `alu_q`; the
   MUL fit test registered; the bus write data and BIU release are flat AND-OR decodes; LOOP tests CX against 1
   instead of decrementing first.

Remaining longest paths (yosys, 10 LUT levels each):

| Path | What it is |
|---|---|
| `ts` -> BIU release -> step-done -> next-step micro-op registers (`u_*`) | The step that ends this clock on bus release (T-state, READY) selects which micro-ops load. |
| `k1` -> ALU operand select -> ALU -> carry / overflow -> `alu_cq` / `alu_oq` | One ALU operation per clock with its operand mux. |
| `k1` / ModRM -> write-back lane decode -> `wb_lo` / `wb_hi` | The class decides the destination register. |
| `k1` -> bus write data select -> BIU `c_wdata` (9) | |

All four are the work of one 8088 clock in this architecture. Going further means a microcode ROM (M10K) for the
step decode, or ALU / write-data operands registered one clock earlier with the queue forwarding moved with them;
neither moves an 8088 clock, but both are larger changes than this checkpoint. The EU request -> aborted-prefetch T1
-> AD / ALE pin path is inherent to the 8088 (decided in the same clock); the wrappers register the pins.

## Checkpoint 5: MUL / DIV wait counter

Quartus 17 on the checkpoint-4 RTL (user run): 2,017 ALMs, 1,305 registers, slack +0.726 ns (slow -40C) / +1.130 ns
(slow 100C), fmax 87.95 MHz; all 400 worst setup paths end at `wcnt` (253 from the register file, 145 from `mrm`).
The wait count was loaded in the setup step from the operand signs (register file through the r/m mux) and the
ModRM-derived MUL / DIV decode, through the clock table and an adder.

- The table is now indexed by the signs registered in the setup step (`md_rneg`, `md_ssq`, most-negative source
  `md_mnq`) and loaded one step later, in the pre-check step; no count runs between the two, so the total is unchanged.
- `md_w`, `md_div`, `md_sgn` are registers (from the class and the ModRM as decoded).
- A divide iteration's extra clocks (from its quotient bit, the end of a 17-bit subtraction) are counted one clock
  later (`wq`, folded in by the post step), so no adder follows that carry chain.
- All `wcnt` updates are one flat block selected by the registered step micro-ops (no step-done in the select).

yosys: no path from `r` or `mrm` reaches `wcnt` any more (before: both did, through the operand mux, the table and the
adder); deepest path into `wcnt` 10 LUT levels / 20 cells incl. carry (from `k1` / registered MUL / DIV state; 31 with
the loop carry still in series). Whole design: 2,931 LUTs, 668 carry cells, 1,085 registers, register to register
10-11 LUT levels. Control for this change: dropping the `wq` fold fails 24-25 % of F6.6 / F7.7 (DIV / IDIV) on cycles.

## Checkpoint 6: effective address and ALU operands

Quartus 17 on the checkpoint-5 RTL (user run): slack +1.948 ns (slow -40C) / +2.102 ns (slow 100C), fmax 94.8 /
96.2 MHz; worst paths register file / `mrm` -> BIU `c_off` (EA adders) and -> `alu_cq` / `alu_aq` (operand mux).

- The bus offset uses the EA registered during S_EA in two stages (`ebq` = base + index, `eaq` = `ebq` + displacement).
  S_EA runs at least two clocks after the last displacement byte and several clocks for the forms without one, so no
  8088 clock moves; LEA keeps the combinational EA (write-back only). XLAT's BX + AL and the push address SP - 2 are
  registered the same way (XLAT reads at step 4; no stack request follows a stack update within two clocks).
- ALU operands come from the registered decode-clock operands (`sho` r/m, `reo` reg; a memory operand straight from
  `mem`), AX from a registered copy, and the ALU operation and the GRP3 TEST select are registered from the class and
  the ModRM as decoded. INC / DEC r keeps `r[op]`: it executes in the decode clock, right after the previous
  instruction's write-back.

yosys, checkpoint 5 -> 6 (LUT levels / cells incl. carry): register file -> `c_off` 6 / 22 -> 6 / 6 (plain operand
muxes: SI, DI, DX, SP; no adder); `mrm` -> `c_off` 7 / 22 -> none; register file -> `alu_cq` 8 / 23 -> 6 / 22
(INC / DEC r only); `mrm` -> `alu_cq` 8 / 23 -> none; `mrm` -> `alu_aq` 7 / 11 -> none. Whole design: 2,929 LUTs,
652 carry cells, 1,170 registers, register to register 9 LUT levels. Aimed controls: capturing `eaq` before the last
S_EA phase fails 28 % of 8A / 8B / 00 / 02 (mod = 2 forms); taking a memory ALU operand from `sho` fails 00 / 02 on
registers.

## 8086 (`x86sv16`: 16-bit BIU, EU with `BUS16`)

**SingleStepTests 8086 v1** (Intel P80C86A-2, max mode, 8288): **323 / 323 files, 646,000 / 646,000 tests pass** on
registers incl. every flag, RAM (every final byte, no other byte written), cycle count and the per-clock trace (ALE, AD19-AD0,
segment status, 8288 strobes, BHE, 16-bit data field, bus status, T-state, QS, queue byte) — every field the v1 format
carries. Excluded / masked: only the **inactive half of AD15-AD0 after a single-lane write** (from its T2 to the
next T1; the suite README's BHE rule). It is needed by 61,992 tests (`lane` column), all byte writes (00 08 10 18 20 28
30 80 82 86 88 A4 C6 D0 D2 F6.2 F6.3 FE): the CPU drives an internal 16-bit value there (the other byte of the source
register, the sign extension of an immediate, the ALU's high byte). Word writes at odd addresses are compared exactly (the 8086 drives the word
byte-swapped in both cycles, so each lane carries its byte). Reads are compared exactly (the inactive half shows the
address byte the bus holds from T1). No drift tolerance was needed (CMOS part with bus hold). Fleet wrapper
`x86sv_i8086`: 6 / 6 runs pass (below). Directed tests (`dsim`) exist for the 8088 only.

**Word string ops A5 / A7 / AB / AD / AF.** The 8088 build's register / memory differences against the 8086 data
(baseline table of checkpoint 6) are a runner artefact: the runner stops `cycles + 64` clocks after the expected
end, and the 8088 needs more clocks than the 8086 for a REP word string op, so CX / SI / DI / IP were sampled before the
loop finished. With the run limit raised (scratch build), the 8088 build shows 0 register / 0 memory failures on all
five files; the `x86sv16` build passes them completely.

### 8086 bus interface (`rtl/x86sv_biu16.sv`), fitted to the traces

- 6-byte queue (shift register, head in `q0`), word fetches at even addresses, one byte (AD15-8, BHE) at odd ones.
- Prefetch at T4 when the queue as of T3 plus the bytes this fetch brings leaves room for a word (<= 4); on the first
  idle clock after T4 a queue of 3 or more bytes waits one more clock (an empty queue after a flush does not); in Ti
  a suspend requested in the same clock already blocks the start.
- EU word at an even address = one cycle; at an odd address = two byte cycles (odd byte with BHE, then the even
  byte without); the INTA pair is always two cycles (BHE low in the first, as the datasheet says).
- AD15-0: T2 / T3 of a write carry the data (byte-swapped when the transfer starts at an odd address); in a read the
  inactive half keeps the address byte (bus hold); T4 / Ti hold the last value.
- BHE (as the rig records it) is latched at T1; an aborted prefetch T1 that follows Td with an EU request already
  pending shows `~word` of that request, otherwise BHE holds.

### EU differences (`BUS16`), fitted to the traces

The EU is the 8088's; with `BUS16` a step can start after a pre-delay (`x_dl`, a 5-bit counter that holds the step's
bus / queue / jump operations; it exists only when an option is on). Six differences:

| Instruction | 8086 | 8088 data |
|---|---|---|
| 80-83 r/m, imm (memory) | write request 1 clock later | consistent (hidden behind a prefetch) |
| 8F POP r/m (register form) | stack read 2 clocks later, end 1 clock after it | consistent |
| FF /6 /7 PUSH r/m (register form) | write 1 clock later | consistent |
| 9A CALL far | suspend 1 clock later | consistent |
| INT3 / INTO / divide error / INTR / NMI | first vector read 1 clock later | **differs** (8088 suite fails) |
| CD INT n | suspend at step 6 (waits for the bus), first vector read 2 clocks after the step | **differs** |

"Consistent" = the 8088 build with the `BUS16` EU passes those 8088 files too, i.e. the 8088 data cannot tell the two
timings apart (the 8088 bus is always busy there); the interrupt-entry timings are a real 8086 / 8088 difference
(scratch run: CC CD CE D4 F6.6 F6.7 F7.6 F7.7 then fail on the 8088). The 8088 keeps its fitted timing (logic-identical rule); the
INTR / NMI entry delay on the 8086 is inferred (the suite has no interrupts).

### 8088 unchanged

- `verify/tools/equiv.sh`: yosys formal equivalence of the 8088 top (`x86sv`) against the checkpoint-6 RTL: 3,878 /
  3,878 equivalence points proven (control: changing one term of the reference's `susp_ok` leaves 3 unproven).
- 8088 suite 3,007,000 / 3,007,000 (drift 2,621 as before), directed 42 / 42, fleet 21 / 21 + 6 / 6.
- yosys: table in "Zero cost when off; yosys per configuration".
- **8086 failing control** (shown once, reverted): odd-address write data not byte-swapped and the first-Ti wait
  removed: 00 01 89 8B A5 E8 pass 6,965 / 12,000 (memory 4,118, cycles 1,151 fails); after reverting 12,000 / 12,000.

## NEC option (`NEC`): V20 native instruction set

Parameter `NEC` of `x86sv` / `x86sv16` / `x86sv_eu` (0 = Intel). What it changes, each rule taken from the V20
traces (register forms fitted with scratch scripts on `moocsv` tables; the NEC uPD70108 / 70116 manual was not
available offline, so names follow the suite):

| Opcodes | NEC behaviour | Reg / RAM |
|---|---|---|
| 60 61 | PUSHA / POPA (POPA skips SP) | 100 % |
| 62 | BOUND: signed check of the register against the word pair; outside -> INT 5, return address = next instruction | 100 % |
| 63 66 67 | like ESC: ModRM, dummy word read of a memory operand, no effect | 100 % |
| 64 65 | REPNC / REPC prefixes: CMPS / SCAS stop on CF instead of ZF; act as REP elsewhere | 100 % |
| 68 6A | PUSH imm16 / imm8 (sign-extended) | 100 % |
| 69 6B | IMUL r, r/m, imm (flags as F7 /5, below) | 100 % |
| 6C-6F | INS / OUTS (+ REP) | 100 % |
| C0 C1 | shift / rotate r/m by imm8 (count not masked, as D2 / D3) | 100 % |
| C8 C9 | ENTER (level not masked; tests use < 32) / LEAVE | 100 % |
| D4 | AAM 0: no divide error; AH = FF, AL unchanged, flags as the other AAMs | 100 % |
| D0-D3 /6 | SHL (not the 8088's SETMO); SHL AF = 0 | 100 % |
| D5 | AAD ignores the immediate (base 10) | 100 % |
| D6 | XLAT (no SALC) | 100 % |
| F6 F7 /4 | MUL leaves SF ZF AF PF unchanged | 100 % |
| F6 F7 /5, 69 6B | IMUL: SF ZF AF PF = flags of (low half << 1) (OF CF as Intel) | 100 % |
| F6 F7 /6 | DIV: flags = SUB (dividend high, divisor) with CF = 1 (the overflow pre-check) | 100 % |
| F6 F7 /7 | IDIV: flags = test of the quotient magnitude (SF = msb, ZF, PF; AF OF CF = 0); a REP prefix does not invert the quotient | 100 % |
| 0F 20 22 26 | ADD4S / SUB4S / CMP4S: (CL + 1) / 2 bytes from DS:SI (segment override applies) with ES:DI, SI / DI / CL unchanged; per byte a binary add / subtract with carry, then decimal adjust: low digit if > 9 or nibble carry; high digit if CF, if > 9F, or if > 99 without a nibble carry. CF = last adjust, ZF = all result bytes 0, SF = AF = CF, PF = OF = 0. CMP4S writes nothing | 100 % |
| 0F 31 39 / 33 3B | INS / EXT: offset = r/m byte reg & 15, length = (reg byte reg or imm & 15) + 1; INS puts the low bits of AW (after the offset register update) into the word(s) at ES:DI, EXT loads AW from DS:SI (override applies); offset register = (offset + length) & 15, DI / SI + 2 when offset + length >= 16. Flags = SUB 15, offset + length (INS) / offset + length - 1 (EXT) | 100 % |
| 0F 10-1F | TEST1 / CLR1 / SET1 / NOT1 r/m, CL or imm (bit = count mod 8 / 16); TEST1 = flags of r/m AND mask (CF OF AF 0), the others change no flag | 100 % |
| 0F 28 2A | ROL4 / ROR4: ROL4 r/m = {r/m[3:0], AL[3:0]}, AL = {AL[3:0], r/m[7:4]}; ROR4 r/m = {AL[3:0], r/m[7:4]}, AL = old r/m; AL is written last when r/m is AL | 100 % |

**Timing:** fitted to the V20 traces at checkpoint 8 (next section); V30 timing is the V20 EU on the 8086 BIU16
with the V20 bus rules, inferred (no V30 suite).

New instruction step sequences reuse the EU's structure (one-hot steps, registered micro-ops, write-back decided one
clock early); NEC-only state (`k1` widened to 64 classes, the BOUND compare, the PUSHA / ENTER stack address) is
registered, so no new same-clock path reaches the register file or the bus address.

**NEC failing control** (checkpoint 7, shown once, reverted): SHL AF from result bit 4 again and PUSHA pushing SP
without the +8 correction: D0.4 / 60 / C9 fail 5,025 (registers) / 10,000 (RAM) of 30,000; after reverting 0 / 0.
Checkpoint 8 controls: next section.

## Checkpoint 8: V20 clock timing (milestone B)

V20 v1 native: **3,125,000 / 3,125,000 tests, 360 / 360 files** on registers incl. every flag, RAM, cycle count and
the per-clock bus / queue-status trace (the V20 format has no separate queue-content field; QS and the bus state per
clock are compared, as for the 8088). No exclusion, no tolerance, nothing masked.

Progress (whole suite, tests passing every comparison): 820,760 (checkpoint 7) -> 1,309,599 (V20 EA and
displacement pops, ALU / MOV forms) -> 1,662,668 (BIU rules: no prefetch abort, T4 request) -> 2,110,818 (jumps,
calls, returns, INT) -> 2,456,528 (stack, shifts, strings) -> 2,611,383 (MUL / DIV / AAM / AAD, NEC flags) ->
2,886,939 (IMUL imm, BCD, misc, IO, ESC) -> 3,079,000 (186 group, 63, D6, 0F bit ops, ROL4 / ROR4) -> 3,125,000
(ADD4S family, INS / EXT).

Failure classes at checkpoint 7 (the checkpoint-7 RTL re-run on the suite; every class is now 0):

| Class | Files | Files 100 % at ck7 | Tests | Failing at ck7 (any comparison) | Register fails | RAM fails |
|---|---|---|---|---|---|---|
| ALU / INC / DEC / NOT / NEG / TEST | 110 | 32 | 956,000 | 627,680 | 0 | 0 |
| shifts / rotates | 48 | 0 | 320,000 | 319,704 | 0 | 0 |
| PUSH / POP | 29 | 0 | 290,000 | 289,972 | 0 | 0 |
| jumps / calls / returns / INT | 37 | 0 | 370,000 | 277,469 | 0 | 0 |
| NEC 0F bit ops (TEST1 CLR1 SET1 NOT1) | 16 | 0 | 160,000 | 140,060 | 0 | 0 |
| MUL / DIV / AAM / AAD / IMUL imm | 12 | 0 | 120,000 | 120,000 | 52,449 | 4,538 |
| MOV / XCHG forms | 37 | 23 | 370,000 | 107,426 | 0 | 0 |
| BCD adjust, CBW / CWD, SAHF, XLAT, LEA, LDS / LES | 13 | 2 | 130,000 | 84,996 | 0 | 0 |
| ESC / undefined (63 66 67) | 11 | 0 | 110,000 | 84,935 | 0 | 0 |
| IN / OUT | 8 | 0 | 80,000 | 69,998 | 0 | 0 |
| string ops (+ REP) | 16 | 2 | 84,000 | 64,000 | 0 | 0 |
| 186: PUSHA POPA BOUND ENTER LEAVE | 5 | 0 | 42,000 | 42,000 | 0 | 0 |
| NEC INS / EXT | 4 | 0 | 40,000 | 40,000 | 40,000 | 18,767 |
| NEC ROL4 / ROR4 | 2 | 0 | 20,000 | 20,000 | 0 | 0 |
| other (flag ops, NOP, HLT, segment moves ...) | 9 | 8 | 27,000 | 10,000 | 0 | 0 |
| NEC ADD4S / SUB4S / CMP4S | 3 | 0 | 6,000 | 6,000 | 5,911 | 4,000 |
| **Total** | 360 | 67 | 3,125,000 | 2,304,240 | 98,360 | 27,305 |

### V20 rules found in the traces (all implemented)

- **BIU:** a started prefetch is never aborted, and no aborted T1 appears; an EU request arriving in a T4 blocks
  the next prefetch and goes Ti -> Td -> T1 (3 clocks); a request in the step right after an EU cycle's release may
  start T1 directly after that cycle's T4 (not after a code fetch's T4); a 3-byte queue does not prefetch at T4 when
  the EU requests the next clock (PUSHA).
- **Queue / EA:** no mode-dependent EA clocks; disp8 is popped 2 clocks after ModRM, disp16 low 1 and high 3 clocks
  after; a displacement or immediate byte that just arrived in an empty queue is popped a clock later; the operand
  request comes 2 clocks after the last displacement byte (ModRM + 3 without one). The 0F second byte is popped a
  clock after the 0F. LEA ends with its last address byte.
- **Jumps / calls / returns:** the prefetcher is suspended, the flush happens one step before the jump step if the
  bus is idle, otherwise at the jump step; the target fetch starts Td -> T1 from Ti / T4 or right after the running
  cycle's T4; a flush during a running prefetch discards its byte; no IP-correction cycle; CALL flushes with the push
  request and fetches the target after the push.
- **Execution counts:** shifts 1 clock per count (count 0: one clock less, a memory operand is not written); MUL /
  DIV fixed counts (no data dependence); IMUL imm F = last immediate pop + 37 / 41 (69) or 38 / 42 (6B) by the
  operand signs; REP CMPS reads DI first; REP STOSB ends no earlier than opcode + 12; ENTER pops the level byte in
  the T1 of the BP push and ends with the last push's T4; BOUND enters INT 5 3 clocks sooner below the lower bound
  than above the upper; POPA skips the SP slot without a bus cycle; 63 waits 48 clocks after its read; D6 (XLAT
  alias) reads 16 clocks later than D7.
- **ADD4S family:** source reads 22 clocks apart (CMP4S: next source read 14 clocks after the destination read);
  the write is posted (the next source read does not wait for it); the end counts from the last destination read,
  one clock shorter when the final carry is 1.
- **INS / EXT** (o = offset, l = length, g(n) = 12 + 3n for n >= 4, 16 + 2n below): EXT reads the word at modrm + 6
  (request), the second word 14 clocks later when o + l > 16, and ends o + 25 / o + 26 / o + 8 clocks after (l + o
  < / = / > 16). INS with o > 0 reads the word, pops an immediate o + 9 clocks later, then (o + l < 16) reads it again
  25 + o clocks after the first read and writes 2o + g(l) after that, or (o + l >= 16) writes 45 clocks after the
  first read, and (> 16) reads / writes DI + 2 (8 and g(o + l - 16) clocks apart); with o = 0 it reads at modrm + 22
  only when l < 16 and writes g(l) after the read, or l >= 5 counted from before the read (a bus-delayed read does not
  delay the write). Every INS / EXT ends 6 clocks after its last write's T1.

### Inferred where the data leave a choice

PUSH r write step (data allow steps 0-3; step 2 chosen), ALU r/m write step (2-4; 3 chosen), jump suspend steps
within their ranges, E2 (LOOP) not taken and E3 (JCXZ) taken paths, INT entry for NMI / INTR / TF (only INT n / INT3
/ INTO are in the suite), RETF / FF /5 second-read step, IDIV SF for a quotient of -128, ADD4S family with CL = 0
(no byte processed, not in the suite), INS / EXT offset or length registers with bits 4-7 set (masked to 4 bits; the
suite uses 0-15), the offset register's high nibble after INS / EXT (cleared). V30: V20 EU timing on the 8086 BIU16
with the same V20 BIU rules (no prefetch abort, T4 request, posted-write chaining) - no V30 data exist; the V30 run
on the V20 suite checks registers / RAM only (100 %; 2,314,285 tests differ in cycles, as expected for a 16-bit bus).

### Failing controls (each shown once on the V20 build, reverted, then the full run repeated)

| Control | File(s): tests / pass / reg / mem / cycles / bus |
|---|---|
| ADD4S family: Intel DAA high-digit condition | 0F20 2,000 / 1,840 / 6 / 160; 0F22 2,000 / 1,603 / 15 / 397 |
| EXT flags without the -1 | 0F33 10,000 / 2,688 / 7,312 / 0 |
| INS uses AW before the offset update | 0F31 10,000 / 8,323 / 0 / 1,677 |
| CMP4S next read counted from the source read | 0F26 2,000 / 527 / 0 / 0 / 1,473 |
| INS o = 0, l >= 5: write counted from the read | 0F39 10,000 / 9,801 / 0 / 0 / 199 |
| ENTER level byte not popped at the push T1 | C8 2,000 / 0 / 2,000 / 1,941 / 1,970 |
| BOUND INT 5 delay independent of the bound | 62 10,000 / 6,632 / 0 / 0 / 3,368 |
| POPA reads the SP slot | 61 10,000 / 0 / 10,000 / 0 / 10,000 |
| PUSHA: 3-byte queue prefetches at T4 | 60 10,000 / 5,000 / 0 / 0 / 5,000 |
| LEA ends after the EA phase (8088) | 8D 10,000 / 5,999 / 2,474 / 0 / 3,168 |
| BIU: prefetch abort applies to the V20 | 70 10,000 / 7,513 / 0 / 0 / 2,487; E8 10,000 / 7,527 / 0 / 0 / 2,473 |
| BIU: a T4 request does not block the prefetch | 00 10,000 / 4,353 / 0 / 0 / 5,647; 88 10,000 / 9,379 / 0 / 0 / 621 |

After reverting: RTL md5 identical to before the controls; full run 3,125,000 / 3,125,000.

### Structure and depth

All NEC timing is in a separate NEC step table (`if (NEC) ... else <8088 table verbatim>`) plus NEC-gated terms
(`NEC ? new : old`), so the 8088 / 8086 stay formally equivalent. New V20 state is registered: the 0F 20-3B wait
values (`bw*`, selected by the step's `u_ws`), the bit-field / BCD conditions (`bf_lt`, `bf_gt`, `bf_o0`, `bf_l5`,
`s4_n0`, `s4_n1`, the flag results), the INS field / mask (`bf_fq`, `bf_mq`) and the computed word / BCD byte (`bxv`),
so the computations end in registers instead of the step decode or `tmp`. yosys depth (register to register, LUT
levels): V20 10 (checkpoint 7: 10), V30 11 (checkpoint 7: 9), 8088 / 8086 9. The longest V20 / V30 paths are the
shared step-done chains (bus release / interrupt -> step done -> next-step registers, and -> queue pop -> queue
registers) with the wider NEC decode on them; removing single NEC blocks (the 0F 20-3B tables, their data paths, the
`lc` changes, the commit changes, the ENTER concurrent pop) moved the estimate by at most one level either way, i.e.
no single NEC block owns the extra level. The Quartus revisions (`syn/quartus/`) give the real slack.

## Checkpoint 9: 8080 emulation mode (milestone C)

Option `NEC8080` (parameter of `x86sv`, `x86sv16`, the EU and the fleet wrappers `x86sv_i8088` / `x86sv_i8086` /
`x86sv_v20` / `x86sv_v30`; valid only with `NEC`; build configs `v20e` / `v30e`).

### Sources (downloaded read-only to `/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/x86/docs/`)

| Short | Document | URL | md5 |
|---|---|---|---|
| UM | NEC V20/V30 User's Manual, Oct 1986 (µPD70108 / µPD70116), 228 pp. | https://ia903205.us.archive.org/28/items/bitsavers_necV20V30U_11351331/V20_V30_Users_Manual_Oct86.pdf | 3936fe1e4efbf2c9e1869bcf55af1108 |
| DS | NEC µPD70108 (V20) data sheet, 44 pp. | https://www.ardent-tool.com/CPU/docs/NEC/V20-V30/v20.pdf | a1b0d480be3906cc8d0f1956bcf64f4a |
| ALP | Intel 8080/8085 Assembly Language Programming Manual 9800301D (May 1981) | https://bitsavers.org/components/intel/MCS80/9800301D_8080_8085_Assembly_Language_Programming_Manual_May81.pdf | b4ce268bd9805211bed2379a616798eb |
| exercisers | TST8080.COM, 8080PRE.COM, 8080EXM.COM, CPUTEST.COM (memory images only; none of their tooling run) | https://altairclone.com/downloads/cpu_tests/ | b69f2dc4c0c95935d7f71ff1cb67dbdb, cdf1c368dd49e9d0b9a61081cf48c9d6, 748ac4f67c0a1f03831f6547c101b8dc, bfd431d8caf4439180bfdef190e1ed49 |

The UM covers the mode itself (section 8, pp. 8-1 .. 8-5; CALLN / RETEM 12-176 / 12-177; BRKEM 12-169; RETI 12-168;
POP PSW 12-151) and says the mode executes "the instruction set for the µPD8080AF"; it gives no 8080 instruction
list, no flag differences and no clock counts for 8080 instructions. The 8080 instruction semantics therefore come
from ALP chapter 3 (pp. 3-1 .. 3-66) plus ALP 1-12 (AND sets AC to the OR of bit 3), anchored by the exercisers.

### What is implemented (with the document)

| Item | Behaviour | Source |
|---|---|---|
| Mode flag | PSW bit 15 MD, 1 = native, 0 = 8080; PS3 (A19 status in T2-T4) = 1 in 8080 mode | UM 8-1, 8-2; DS p. 5 |
| Register mapping | A = AL, B CH, C CL, D DH, E DL, H BH, L BL, SP = BP; F = PSW bits 7-0 (S Z 0 AC 0 P 1 CY); AH, SP, IX, IY and the segment registers not addressable | UM fig. 8-1 / 8-2 (p. 8-1); DS p. 19 |
| Segments | code PS; memory operands and the stack DS0 | UM 8-1; DS p. 19 |
| BRKEM imm8 (`0F FF ib`, native) | push PSW (MD 1), PS, PC on SS:SP, MD = 0, MD write enabled, PS:PC from the vector; IE / BRK unchanged | UM 12-169 (flag table: MD only) |
| CALLN imm8 (`ED ED ib`, 8080) | push PSW (MD 0), PS, PC on the native SS:SP, MD = 1, PS:PC from the vector; IE / BRK unchanged | UM 12-176, 8-4 |
| RETEM (`ED FD`, 8080) | pop PC, PS, PSW from SS:SP, MD restored, MD write disabled | UM 12-177, 8-5 |
| RETI / POP PSW (native) | MD taken from the stack only while writes are enabled (between BRKEM and RETEM); otherwise MD stays 1 | UM 12-168, 12-151 |
| INT / NMI in 8080 mode | as in native mode (INTA pair for INT, IE / BRK cleared), PSW with MD 0 pushed, routine runs native, RETI returns to 8080 mode | UM 8-4 |
| HALT in 8080 mode | INT with IE = 0 releases it and execution continues after HLT in 8080 mode; with IE = 1 / NMI the interrupt is taken | UM 8-2 |
| RESET | aborts the mode: native, MD write disabled | UM 8-4 |
| 8080 instructions | all 244 documented opcodes plus the undefined ones (below) with 8080 results and flags (AC rules of ALP chapter 3 / 1-12, DAA as one correction from A, AC, CY, ALP 3-18) | ALP chapter 3 |

### RTL structure

At the opcode clock (`S_OP`) an 8080 opcode (MD = 0) is translated by one decode (`t_*`) onto an existing native class
with a native opcode and a preset ModRM, plus registered options (`e_*`), so the native step sequences run it:
MOV r,r / r,M / M,r, LDAX / STAX, LHLD / SHLD, SPHL -> `MOVRM` (LDAX / STAX / XTHL take their EA from BC / DE / BP);
MVI -> `MOVI8` / `MOVMI`; LXI -> `MOVI16`; LDA / STA -> `MOVAM`; ALU r / M -> `ALURM`, ALU imm -> `ALUAI`, DAD ->
`ALURM` ADD BX (CY only); INR / DCR -> `INCRM`; INX / DCX -> `INCR` (no flags); RLC RRC RAL RAR -> `SHIFT` by 1; CMA ->
`GRP3` NOT; STC CMC EI DI -> `FLAG`; DAA -> `BCD` with the 8080 rule; JMP / Jcc -> `JMPN`, CALL / Ccc -> `CALLN`,
RET / Rcc -> `RET`, PCHL -> `INCRM` JMP r, RST -> `INCRM` CALL r (absolute targets; Rcc not taken ends in the decode
clock); PUSH / POP rp -> `PUSHR` / `POPR` on DS0:BP (PUSH / POP PSW: A and F); XCHG / XTHL -> `XCHG`; IN / OUT ->
`IO` imm8; HLT -> `HLT`; NOP -> `XCHGA`. `ED` uses the `0F` second-byte state; BRKEM / CALLN run the INT n sequence,
RETEM the RETI sequence. The 8080 flag rules are applied at write-back: V kept, AC per the 8080 rule (registered
selects), DAD CY only. All 8080 terms are gated by the constant `NEC & NEC8080` and placed after the existing case
items, so the off configurations are formally the checkpoint-8 logic.

### Inferred points (documents silent; choice and reason)

1. **Clock counts.** No NEC document gives 8080-mode clocks. RTL: each 8080 instruction takes the step sequence of
   the native instruction it is mapped to (above), on the hardware-fitted V20 timing; the escape adds the `0F`
   second-byte clock. No cycle check is possible; the suite has no cycle column. The UM's BRKEM 50 / CALLN 58 /
   RETEM 39 clocks (V30 even 38 / 38 / 27; DS: BRKEM 58) are queue-full instruction figures, like its native ones
   (UM: BRK imm8 50, RETI 39; V20 hardware traces of the same native instructions: 62-65 / 34-35 clocks first byte
   to next first byte), so they cannot be compared with a bus-level count. RTL first-byte-to-first-byte clocks from
   an empty queue (s80 report): register ops 4, MVI 8, M operand 13, LXI 12, LDA / STA 15, LHLD / SHLD 23, INR / DCR M
   21, JMP 18, CALL 27, RET 20, RST 22, PUSH 15, POP 13, XTHL 27, BRKEM / CALLN 69, RETEM 38.
2. **V, DIR, BRK** are not changed by 8080 instructions (UM fig. 8-2 maps only the low byte); IE only by EI / DI.
3. **Undefined 8080 opcodes** 08 10 18 20 28 30 38 (NOP), CB (JMP), D9 (RET), DD FD (CALL) as on an 8080; `ED`
   + another second byte: two-byte no-op.
4. **RETEM with stacked MD 0**: MD takes the stacked bit (flag table "R"), writes disabled.
5. **BRKEM / CALLN keep IE and BRK** (UM flag tables) although DS p. 19 says BRKEM "operates exactly the same as the
   BRK instruction".
6. **Vector read before the pushes** (the V20's native INT bus order from the traces).
7. **I/O address** `00pp` for IN / OUT p (as native IN / OUT imm8; an 8080 also puts p on A15-A8).
8. **Interrupt acceptance** after 8080 instructions: the native rules (EI delays INTR by one instruction, as ALP
   3-23 documents for the 8080; none right after RETEM, as after RETI); single step (BRK) in 8080 mode not exercised.
9. **HALT left by INT with IE = 0**: one extra step restarts the prefetch (`fgo`) before the next 8080 opcode.
10. **PS3** shows MD of the clock (the first prefetches after BRKEM / CALLN may still show the old mode).
11. **Nested BRKEM** inside a CALLN / interrupt routine (UM 8-5: "normal operation cannot be expected"): runs as
    BRKEM.

Native HALT (user decision 2026-11-04, applies to every V20 / V30 build): UM 8-2 and 9-1 ("Releasing Standby Mode
with INT ... When Interrupts are Disabled (DI)") say INT also leaves a HALT entered in native mode, and execution
resumes after the HALT with no interrupt taken. Implemented for both modes in the shared NEC step table: INT releases
HALT whatever IE (`u_hold`; the registered `ie_h` is gone); the HLT step after the release carries the IRQ end
condition, so NMI / INT with IE = 1 end HLT there exactly as before (interrupt entry unchanged: directed tests M / N,
first bus cycle 25 / 29 clocks after the HALT status cycle, old and new RTL alike), while a release with nothing to
take runs one more step that restarts the prefetch (`fgo`). Directed tests L / M / N (`x80 dir`): native HALT with
IE = 0 + INT (old RTL fails it: stays halted), IE = 1 + INT, NMI. 8088 / 8086 formally identical to the pre-change RTL
(4,192 / 4,363 cells, 0 unproven); full `run_all.sh` unchanged otherwise (table under "Results").

### Reference model and suite

`verify/suites/v20_8080/gen/v20e.h` (C++, written from UM / DS / ALP only; no code shared with the RTL or its
testbench), `exer.cpp` (CP/M harness: BDOS functions 2 / 9 through CALLN to a native `OUT E0h, AL; RETI` routine),
`gen.cpp` (suite generator). Model results, before any generation:

| Exerciser | Model | Instructions |
|---|---|---|
| TST8080 | "CPU IS OPERATIONAL" | 657 |
| 8080PRE | "8080 Preliminary tests complete" | 1,064 |
| 8080EXM | 25 / 25 "PASS!" (CRCs from real 8080 silicon) | 2,919,051,529 |
| CPUTEST | "CPU TESTS OK" | 33,971,857 |

Suite: `verify/suites/v20_8080/` (README there: format, worked example, seed, provenance per field, inferred points):
264 files, 657,673 tests, 75 MB gzipped, seed `5632303830383031`, 2,500 tests per opcode file (DAA 2,048, RETEM with
stacked MD 0: 625); 30,625 tests flagged `inferred`.

### Results

| Config | 8080-mode suite (reg / PSW incl. MD / MD write enable / RAM / I/O writes) | Directed (`x80 dir`) | Exercisers in 8080 mode (`x80 com`) |
|---|---|---|---|
| V20 + NEC8080 | 657,673 / 657,673 | 44 / 44 (38 before the native-HALT tests L-N) | TST8080, 8080PRE, CPUTEST pass; 8080EXM 25 / 25 PASS (29.2e9 clocks, 277 CALLN) |
| V30 + NEC8080 | 657,673 / 657,673 | 44 / 44 (38 before the native-HALT tests L-N) | TST8080, 8080PRE, CPUTEST pass; 8080EXM 25 / 25 PASS (23.2e9 clocks, 277 CALLN) |

V30: the suite has no cycle column; s80 reports the RTL's own clocks per file (16-bit bus, inferred V30 timing).
Exercisers on the RTL (build of the final RTL, `x86sv_all.sv` md5 7ad7190ce42f2abb750e7b37f13c8302) boot natively from FFFF0, enter the mode with BRKEM, and print through CALLN (CPUTEST: 182
CALLN round trips). Directed tests (`verify/tb/x80.cpp`, each expected value with its UM / DS / ALP page): BRKEM
push / MD / PS3 / mapping / RETEM (7), segment use (3), CALLN round trip incl. stacked MD and IE (6), MD write
enable (2), INT in 8080 mode incl. EI delay (5), NMI with IE = 0 (3), HALT with INT and IE = 0 / IE = 1 / NMI (6),
nesting CALLN -> BRK n -> RETI -> RETI -> RETEM (4), RESET in 8080 mode (2).

RTL vs model mismatches found (each analysed):
- CALLN with the native stack overlapping its own interrupt vector (1 test of 1,000 in a first generation): the
  model pushed before reading the vector, the RTL reads first. The documents give no order; the V20 traces of native
  INT show the vector read first. **Model wrong**, changed; exercisers re-run (all pass), suite regenerated.
- HLT tests: the runner compared the debug IP (offset of the last opcode read) with the model's IP after HLT. **Runner**
  fixed (halted: debug IP + 1).
- Directed test G (HALT, IE = 0, INT): the RTL left HALT but its prefetcher stayed suspended (native HLT is only ever
  left through an interrupt, which flushes). **RTL wrong** against UM 8-2; fixed (a step after the halt restarts the
  prefetch).

Failing control (shown once on V20 + NEC8080, then the RTL restored to the identical md5 and everything re-run):
SUB / SBB / CMP / DCR AC rule replaced by the native one and the 8080 stack segment by SS: 90 96 98 BE D6 fail
2,500 / 2,500 each on registers, C5 / CD 2,500 / 2,500 on RAM, C9 2,500 / 2,500 on registers (80, E3, 3E unaffected
pass); TST8080 "CPU HAS FAILED! ERROR EXIT=066E"; directed test B fails.

Decisions (user, 2026-11-04): `NEC8080` stays a separate option (cost below); 8080-mode clock counts stay the mapped
native step sequences (inferred; a V20 runs 8080 opcodes through its native microcode, so real-8080 counts would be
wrong too) until a V20 capture exists; native HALT follows UM 9-1 (above).

### Cost and depth

yosys (`verify/tools/yosys.sh`, same run, LUTs = ALUT2-6): see "Zero cost when off; yosys per configuration". NEC8080
adds about 318 LUTs to the V20 (4,270 -> 4,588, +7.4 %) and 333 to the V30 (4,332 -> 4,665, +7.7 %), plus 41 registers and 32-34 carry cells: not
nearly free, so it stays a separate option (user decision 2026-11-04). Quartus (user run, 2026-11-04, final RTL): +245 ALMs
on the V20 (2,855 -> 3,100, +8.6 %), +245 on the V30 (2,891 -> 3,136, +8.5 %); both close 80 MHz (section "Quartus
17 test project").

Depth: the first complete version measured V20 + NEC8080 at 11 LUT levels FF to FF (8 endpoints at 11: step-done ->
next-step registers through the Rcc / RST step overrides and an AC mux behind the ALU) and 11-12 on the `yosys.sh`
metric. Restructured: Rcc not taken decided in the decode clock (no step override), RST mapped onto CALL r (no step
override), the 8080 AC rule moved to write-back with registered selects, the condition registered, the 8080 stack
folded into the existing SP-2 register and forwarding mux, the preset ModRM and the RST target held in their own
registers instead of loading `mrm` / `imm` in the opcode clock. After: V20 + NEC8080 10, V30 + NEC8080 11
(`yosys.sh`); checkpoint 8: V20 10, V30 11. The off configurations are formally identical to checkpoint 8 but measure
11 / 11 in the same run (abc's mapping moves by one level with the source text).

## Zero cost when off; yosys per configuration

- `verify/tools/equiv.sh <reference x86sv_all.sv> <out> [top]`: yosys formal equivalence (flatten, `opt`, register
  matching, `equiv_simple` / `equiv_induct`). Checkpoint 8 (final RTL): 8088 top `x86sv` against the checkpoint-6
  RTL (`ref_cp6`): 3,871 / 3,871 proven, 0 unproven; 8086 top `x86sv16` against the checkpoint-7 RTL (`ref_ck7`,
  snapshot taken before the first checkpoint-8 edit): 4,168 / 4,168 proven, 0 unproven. Control: one changed term in
  the reference's `susp_ok` leaves it unproven. Re-run after every NEC change; final suites: 8088 3,007,000 /
  3,007,000, directed 42 / 42, fleet pass, 8086 646,000 / 646,000.
- New code is either a separate module (`x86sv_biu16`, `x86sv16`), a generate block (step pre-delay), or terms gated
  by `BUS16` / `NEC` (constants) placed after the existing case items, so the off configuration folds to the old logic.
- **Checkpoint 9** (final RTL, `equiv.sh <ref> <out> <top> [nec]`; `nec` sets NEC = 1, NEC8080 stays 0): 8088 vs
  `ref_cp6` 3,871 / 3,871; 8086 vs `ref_ck7` 4,168 / 4,168; V20 (`x86sv`, NEC8080 off) vs `ref_ck8` 4,808 / 4,808;
  V30 (`x86sv16`, NEC8080 off) vs `ref_ck8` 4,974 / 4,974; 0 unproven in each. `ref_ck8` = the checkpoint-8 RTL,
  copied before the first checkpoint-9 edit to `.../x86/ref_ck8/` (md5 in `ref_ck8/md5.txt`; `x86sv_all.sv`
  39baf9d2440c11a76461f569b67c6986, whole tree in `ref_ck8/full/`). Two lessons kept in the RTL: 8080 terms inside
  `unique case` items (nested `if`) left internal step-decode wires unprovable, so they sit after the case statements;
  the end-condition vector keeps its checkpoint-8 width when NEC8080 is off (`ECW`). V20 native suite with NEC8080
  on: 3,125,000 / 3,125,000.

yosys 0.66 `synth_intel_alm -family cyclonev` on `rtl/x86sv_all.sv` (`verify/tools/yosys.sh <out> <config>`), no
MLAB / M10K / DSP in any configuration:

| Config | LUTs (ALUT2-6) | Carry | Registers | LUT depth reg-to-reg |
|---|---|---|---|---|
| 8088, checkpoint 6 | 2,929 | 652 | 1,170 | 9 |
| 8088, checkpoint 7 | 2,950 | 661 | 1,170 | 9 |
| 8086, checkpoint 7 | 3,033 | 661 | 1,200 | 10 |
| V20, checkpoint 7 | 3,439 | 775 | 1,205 | 10 |
| V30, checkpoint 7 | 3,510 | 778 | 1,230 | 9 |
| 8088, checkpoint 8 | 2,954 | 652 | 1,170 | 9 |
| 8086, checkpoint 8 | 3,089 | 661 | 1,200 | 9 |
| V20, checkpoint 8 | 4,281 | 966 | 1,373 | 10 |
| V30, checkpoint 8 | 4,385 | 972 | 1,398 | 11 |
| 8088, checkpoint 9 | 2,950 | 661 | 1,170 | 9 |
| 8086, checkpoint 9 | 2,990 | 670 | 1,200 | 10 |
| V20, checkpoint 9 (NEC8080 off) | 4,270 | 973 | 1,373 | 11 |
| V30, checkpoint 9 (NEC8080 off) | 4,332 | 977 | 1,398 | 11 |
| V20 + NEC8080, checkpoint 9 | 4,588 | 1,007 | 1,414 | 10 |
| V30 + NEC8080, checkpoint 9 | 4,665 | 1,009 | 1,439 | 11 |

Checkpoint 9: the four off configurations are formally the checkpoint-6 / 7 / 8 logic; their LUT and depth figures
move only with abc (the checkpoint-8 V20 text measures 10, the identical checkpoint-9 V20 logic 11; FF-to-FF LUT
levels counted on the mapped netlist: 10 with 50 endpoints at 10 vs 11 with 10 endpoints at 11). NEC8080 costs
318 / 333 LUTs, 34 / 32 carry cells and 41 registers on V20 / V30; no MLAB / M10K / DSP.

The 8088 LUT / carry counts move only with abc's noise (the design is formally identical; reading the unchanged
checkpoint-6 files plus one unused extra module already gives 2,958 LUTs); depth 9 unchanged; likewise the 8086
(formally equivalent to checkpoint 7; 3,033 -> 3,089 LUTs and depth 10 -> 9 are abc's run-to-run spread). The V20
grows by about 840 LUTs / 190 carry cells / 170 registers for the NEC timing, ADD4S family and INS / EXT (two
32-bit shifters, BCD adjust, wait values, pointers); depth: section "Checkpoint 8". No MLAB / M10K / DSP in any
configuration.

## Failing control (8088)

A deliberate break must show in the table. Run once more after the checkpoint-4 changes and reverted: AND / OR / XOR set
AF = 1 (flag break) and PUSH writes one step later (cycle break):

```text
file            tests   pass    reg    mem cycles    bus  drift
00              10000  10000      0      0      0      0      0
20              10000      0  10000      0      0      0      0
21              10000      0  10000      0      0      0      0
30              10000      0  10000      0      0      0      0
50              10000   5000      0      0   5000   5000      0
9C              10000   5000      0      0   5000   5000      0
TOTAL           60000  20000  30000      0  10000  10000      0
```

(The PUSH break shows only in the empty-queue half: with a full queue the extra clock is hidden behind a prefetch
that ends at the same clock.) After reverting, the same files pass 60,000 / 60,000.

## Fleet wrappers (`rtl/x86sv_fleet.sv`) and their test (`verify/tb/fleet.cpp`, `fleet`)

- `x86sv_mcl86` on the existing master `mcl86_i_t` / `mcl86_o_t` (drop-in for `mcl86_cpu`). `ce` = rising edge of
  `cpu_clk` seen in the `clk` domain (`cpu_clk & ~cpu_clk_q`), so the 8088 runs at the `cpu_clk` frequency with any
  `clk` / `cpu_clk` ratio >= 2. A bus cycle raises `req` (type = S2-S0, address, write data) the clock after ALE and
  drops it on `req_ack`; READY to the core stays low until the acknowledge has been seen, and the read byte is held
  from that clock. An acknowledge arriving up to `3P - 3` clocks after `req` (P = clocks per `cpu_clk`) costs no wait
  state; each further P clocks adds one Tw — exactly the 8088's READY rule. INTA and HALT cycles are requested like
  reads (like `dl2_bus`); TEST is tied low (WAIT never stalls), NMI / INTR pass through.
- `x86sv_i8088` on `i8088_i_t` / `i8088_o_t` (in the master package): the core's max-mode pins plus the ALE-latched
  cycle address / type and 8288 command strobes. Parameter `NEC` (default 0).
- `x86sv_i8086` on the proposed `i8086_i_t` / `i8086_o_t` (16-bit `din` / `dout`, ALE-latched `bhe_n`), `x86sv_v20` /
  `x86sv_v30` on `v20_*` / `v30_*` (typedef aliases of the i8088 / i8086 structs: same pins). Proposed text in
  `fleet_types.svh` below the "to merge" marker; `verify/build.sh` appends it to a scratch copy of the master package.
- Test, 16-bit and NEC wrappers: the same program with 0, 1, 3 Tw per bus cycle at ce every 1 and 3 clocks; the data
  cycles (type, address, BHE, data) must not depend on the wait states, the INTA pair must be taken, and the final
  memory must equal the 8088's (`x86sv_i8086`) or the first V20 run's (`x86sv_v20`, `x86sv_v30`; NEC MUL / DIV flags
  differ from the 8088's): 18 / 18 runs pass.
- Test: both wrappers run the same program (reset vector, ALU, memory, I/O, REP MOVSB, MUL, DIV, INT n / IRET, HLT,
  INTR through the INTA pair) for P = 3, 4, 12 and acknowledge delays D = 0, 1, 3, 6, 8, 13, 30. The `x86sv_mcl86`
  bus cycles (8088 clock of T1, type, address, write data) and final memory must equal those of `x86sv_i8088` driven
  with READY low for exactly `max(0, ceil((D + 3 - 3P) / P))` Tw per cycle: 21 / 21 pass. Control: delaying the
  wrapper's `req` by one clock fails 3 runs.
- Compiled against a scratch copy of the master `chip_pool_pkg.sv` (read only) with `fleet_types.svh` appended
  (`verify/build.sh`; `X86SV_PKG` overrides the package path).

## Quartus 17 test project (`syn/quartus/`)

x86sv on 8 KB of M10K, ce = clk / 4 generated inside, registered pins; device 5CSEBA6U23I7; `x86sv_qtop.sdc` one clock
at 80 MHz (96 MHz: `-period 10.417`); sources in `files.qip` (the .qsf files list none). One project, four revisions:
`x86sv_qtop` (8088, unchanged), `x86sv_qtop_8086`, `x86sv_qtop_v20`, `x86sv_qtop_v30`; each added .qsf is a copy of
`x86sv_qtop.qsf` plus `VERILOG_MACRO "X86SV_BUS16=1"` and / or `VERILOG_MACRO "X86SV_NEC=1"`, which `x86sv_qtop.sv`
uses to pick `x86sv` / `x86sv16` and `NEC` (8086 / V30: the RAM as two byte lanes). Every `-name` used is in the
fleet's Quartus 17.0 template (checked by script; `TIMEQUEST_MULTICORNER_ANALYSIS`, no `TIMING_ANALYZER_*`).
Build: `quartus_sh --flow compile x86sv_qtop -c <revision>` (see its README). Not run here (no Quartus); the top is
lint-clean in Verilator in all four configurations.

Checkpoint 9 adds `x86sv_qtop_v20_8080` and `x86sv_qtop_v30_8080` (listed in `x86sv_qtop.qpf` and the folder's
README): `x86sv_qtop.qsf` plus the V20 / V30 macros and `VERILOG_MACRO "X86SV_NEC8080=1"` (`x86sv_qtop.sv` passes
`NEC8080`). Every `-name` checked against the master template by script (12 names, all present; no
`TIMING_ANALYZER_*`); the top is lint-clean in Verilator for both. Compiled by the user 2026-11-04 (table below).

Quartus 17 on the checkpoint-8 RTL (user run, 2026-11-04), 80 MHz constraint:

| Revision | ALMs | Registers | M10K | DSP | Setup slack slow 100C / -40C | Fmax slow 100C / -40C |
|---|---|---|---|---|---|---|
| `x86sv_qtop` (8088) | 1,988 | 1,384 | 8 | 0 | +3.021 / +2.972 ns | 105.5 / 104.95 MHz |
| `x86sv_qtop_8086` | 2,078 | 1,421 | 8 | 0 | +2.883 / +2.817 ns | 103.98 / 103.27 MHz |
| `x86sv_qtop_v20` | 2,855 | 1,573 | 8 | 0 | +2.223 / +2.425 ns | 97.3 / 99.26 MHz |
| `x86sv_qtop_v30` | 2,891 | 1,641 | 8 | 0 | +1.876 / +2.088 ns | 94.13 / 96.04 MHz |
| `x86sv_qtop_v20_8080` (checkpoint 9) | 3,100 | 1,617 | 8 | 0 | +1.876 / +2.098 ns | 94.13 / 96.14 MHz |
| `x86sv_qtop_v30_8080` (checkpoint 9) | 3,136 | 1,682 | 8 | 0 | +1.917 / +2.206 ns | 94.49 / 97.14 MHz |

Hold, fast corners and pulse width positive in all. The 8088 (formally unchanged since checkpoint 6) moves with fitter
seed only (checkpoint-7 build: 2,001 ALMs, +2.588 ns). The NEC timing / instructions cost ~870 ALMs and ~0.8 / 1.1 ns
of slack; the 16-bit bus costs ~90 ALMs and ~0.15 ns. All four close 80 MHz with margin, so no NEC timing pass.
Checkpoint 9 rows = final checkpoint-9 RTL (with the native-HALT change, `x86sv_all.sv` md5 e06b9929; user run
2026-11-04): hold min +0.132 / +0.163 ns (fast -40C), fast-corner setup +6.23 / +6.44 ns. The run before the HALT
change gave 3,122 / 3,125 ALMs, +1.936 / +2.093 ns: the change moves the fit by seed noise only. NEC8080 costs
~245 ALMs (+8.6 % V20, +8.5 % V30) and slack moves by -0.35 / +0.04 ns against the plain V20 / V30, inside
fitter-seed noise; no 8080 timing pass needed.

## Unsure / limits

- 8080 mode (checkpoint 9): the suite is model-generated, not a capture; clock counts in the mode are inferred (no
  NEC document); the inferred points of "Checkpoint 9" are where a real V20 could differ.
- Wait states, interrupts, HLT, WAIT, LOCK and reset are checked against the documents' rules, not against hardware
  traces; the inferred points above are where a real 8088 capture could still differ by clocks.
- The floating-bus drift tolerance is a judgement about the rig (see table); 2,621 D2 / D3 tests use it.
- MUL / DIV clock counts are fitted formulas; rare cases (e.g. 16-bit MUL with a zero high half) occur only a few
  times in the data.
- Loads: the read request clock is ambiguous by one against a running prefetch (checkpoint 1); all groups fit.
- V20: the inferred points in "Checkpoint 8"; V30 timing is wholly inferred. V20 / V30 yosys depth is one / two LUT
  levels above the 8088's; Quartus: +2.22 / +1.88 ns at 80 MHz, with NEC8080 +1.88 / +1.92 ns (section "Quartus 17
test project").

## Re-run

```bash
verify/run_all.sh <build dir>        # build all six configs; 8088 suite, directed, fleet; 8086 / V20 / V30 / V20e / V30e suites; 8080-mode suite, directed, exercisers
verify/build.sh <dir> <8088|8086|v20|v30>; verify/run.sh <dir> all    # one config (suite from <dir>/cfg)
verify/run.sh <build dir> F6.6 -s    # one file, first failure dump
verify/tools/yosys.sh <out dir> <config>
verify/tools/equiv.sh <reference x86sv_all.sv> <out dir> [x86sv | x86sv16] [nec]
verify/build.sh <dir> v20e; <dir>/s80 verify/suites/v20_8080/*.json.gz   # 8080-mode suite (-s first failure)
<dir>/x80 dir; <dir>/x80 com <file.COM>                                # directed 8080-mode tests; CP/M exerciser
X86SV_EXM=1 verify/run_all.sh <build dir>                              # also 8080EXM (about 3 h per config)
```

Build dir used: `/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/x86/w3/all` (Verilator 4.204, 3 files in
parallel, `ulimit -v 8000000`). Reference RTL snapshots for `equiv.sh`: `.../x86/ref_cp6/rtl/x86sv_all.sv` (8088),
`.../x86/ref_ck7/rtl/x86sv_all.sv` (checkpoint 7, used for the 8086; `ref_ck7/full/` holds the whole checkpoint-7
tree). Per-file tables of
every configuration: `<build dir>/run_all.txt`, `<build dir>/{8086,v20,v30}/run_all.txt` (`lane` = 8086 inactive-half
mask used).

### V20 files with register / RAM failures

None (checkpoint 8; checkpoint 7 had 16, listed in "Checkpoint 8").

## Per-file table (8088, checkpoint 6 format; checkpoint 7 adds a `lane` column, all 0)

Fail columns count tests failing that comparison; `drift` counts tests that used the floating-bus tolerance.

```text
file            tests   pass    reg    mem cycles    bus  drift
00              10000  10000      0      0      0      0      0
01              10000  10000      0      0      0      0      0
02              10000  10000      0      0      0      0      0
03              10000  10000      0      0      0      0      0
04              10000  10000      0      0      0      0      0
05              10000  10000      0      0      0      0      0
06              10000  10000      0      0      0      0      0
07              10000  10000      0      0      0      0      0
08              10000  10000      0      0      0      0      0
09              10000  10000      0      0      0      0      0
0A              10000  10000      0      0      0      0      0
0B              10000  10000      0      0      0      0      0
0C              10000  10000      0      0      0      0      0
0D              10000  10000      0      0      0      0      0
0E              10000  10000      0      0      0      0      0
10              10000  10000      0      0      0      0      0
11              10000  10000      0      0      0      0      0
12              10000  10000      0      0      0      0      0
13              10000  10000      0      0      0      0      0
14              10000  10000      0      0      0      0      0
15              10000  10000      0      0      0      0      0
16              10000  10000      0      0      0      0      0
17              10000  10000      0      0      0      0      0
18              10000  10000      0      0      0      0      0
19              10000  10000      0      0      0      0      0
1A              10000  10000      0      0      0      0      0
1B              10000  10000      0      0      0      0      0
1C              10000  10000      0      0      0      0      0
1D              10000  10000      0      0      0      0      0
1E              10000  10000      0      0      0      0      0
1F              10000  10000      0      0      0      0      0
20              10000  10000      0      0      0      0      0
21              10000  10000      0      0      0      0      0
22              10000  10000      0      0      0      0      0
23              10000  10000      0      0      0      0      0
24              10000  10000      0      0      0      0      0
25              10000  10000      0      0      0      0      0
27              10000  10000      0      0      0      0      0
28              10000  10000      0      0      0      0      0
29              10000  10000      0      0      0      0      0
2A              10000  10000      0      0      0      0      0
2B              10000  10000      0      0      0      0      0
2C              10000  10000      0      0      0      0      0
2D              10000  10000      0      0      0      0      0
2F              10000  10000      0      0      0      0      0
30              10000  10000      0      0      0      0      0
31              10000  10000      0      0      0      0      0
32              10000  10000      0      0      0      0      0
33              10000  10000      0      0      0      0      0
34              10000  10000      0      0      0      0      0
35              10000  10000      0      0      0      0      0
37              10000  10000      0      0      0      0      0
38              10000  10000      0      0      0      0      0
39              10000  10000      0      0      0      0      0
3A              10000  10000      0      0      0      0      0
3B              10000  10000      0      0      0      0      0
3C              10000  10000      0      0      0      0      0
3D              10000  10000      0      0      0      0      0
3F              10000  10000      0      0      0      0      0
40              10000  10000      0      0      0      0      0
41              10000  10000      0      0      0      0      0
42              10000  10000      0      0      0      0      0
43              10000  10000      0      0      0      0      0
44              10000  10000      0      0      0      0      0
45              10000  10000      0      0      0      0      0
46              10000  10000      0      0      0      0      0
47              10000  10000      0      0      0      0      0
48              10000  10000      0      0      0      0      0
49              10000  10000      0      0      0      0      0
4A              10000  10000      0      0      0      0      0
4B              10000  10000      0      0      0      0      0
4C              10000  10000      0      0      0      0      0
4D              10000  10000      0      0      0      0      0
4E              10000  10000      0      0      0      0      0
4F              10000  10000      0      0      0      0      0
50              10000  10000      0      0      0      0      0
51              10000  10000      0      0      0      0      0
52              10000  10000      0      0      0      0      0
53              10000  10000      0      0      0      0      0
54              10000  10000      0      0      0      0      0
55              10000  10000      0      0      0      0      0
56              10000  10000      0      0      0      0      0
57              10000  10000      0      0      0      0      0
58              10000  10000      0      0      0      0      0
59              10000  10000      0      0      0      0      0
5A              10000  10000      0      0      0      0      0
5B              10000  10000      0      0      0      0      0
5C              10000  10000      0      0      0      0      0
5D              10000  10000      0      0      0      0      0
5E              10000  10000      0      0      0      0      0
5F              10000  10000      0      0      0      0      0
60              10000  10000      0      0      0      0      0
61              10000  10000      0      0      0      0      0
62              10000  10000      0      0      0      0      0
63              10000  10000      0      0      0      0      0
64              10000  10000      0      0      0      0      0
65              10000  10000      0      0      0      0      0
66              10000  10000      0      0      0      0      0
67              10000  10000      0      0      0      0      0
68              10000  10000      0      0      0      0      0
69              10000  10000      0      0      0      0      0
6A              10000  10000      0      0      0      0      0
6B              10000  10000      0      0      0      0      0
6C              10000  10000      0      0      0      0      0
6D              10000  10000      0      0      0      0      0
6E              10000  10000      0      0      0      0      0
6F              10000  10000      0      0      0      0      0
70              10000  10000      0      0      0      0      0
71              10000  10000      0      0      0      0      0
72              10000  10000      0      0      0      0      0
73              10000  10000      0      0      0      0      0
74              10000  10000      0      0      0      0      0
75              10000  10000      0      0      0      0      0
76              10000  10000      0      0      0      0      0
77              10000  10000      0      0      0      0      0
78              10000  10000      0      0      0      0      0
79              10000  10000      0      0      0      0      0
7A              10000  10000      0      0      0      0      0
7B              10000  10000      0      0      0      0      0
7C              10000  10000      0      0      0      0      0
7D              10000  10000      0      0      0      0      0
7E              10000  10000      0      0      0      0      0
7F              10000  10000      0      0      0      0      0
80.0            10000  10000      0      0      0      0      0
80.1            10000  10000      0      0      0      0      0
80.2            10000  10000      0      0      0      0      0
80.3            10000  10000      0      0      0      0      0
80.4            10000  10000      0      0      0      0      0
80.5            10000  10000      0      0      0      0      0
80.6            10000  10000      0      0      0      0      0
80.7            10000  10000      0      0      0      0      0
81.0            10000  10000      0      0      0      0      0
81.1            10000  10000      0      0      0      0      0
81.2            10000  10000      0      0      0      0      0
81.3            10000  10000      0      0      0      0      0
81.4            10000  10000      0      0      0      0      0
81.5            10000  10000      0      0      0      0      0
81.6            10000  10000      0      0      0      0      0
81.7            10000  10000      0      0      0      0      0
82.0            10000  10000      0      0      0      0      0
82.1            10000  10000      0      0      0      0      0
82.2            10000  10000      0      0      0      0      0
82.3            10000  10000      0      0      0      0      0
82.4            10000  10000      0      0      0      0      0
82.5            10000  10000      0      0      0      0      0
82.6            10000  10000      0      0      0      0      0
82.7            10000  10000      0      0      0      0      0
83.0            10000  10000      0      0      0      0      0
83.1            10000  10000      0      0      0      0      0
83.2            10000  10000      0      0      0      0      0
83.3            10000  10000      0      0      0      0      0
83.4            10000  10000      0      0      0      0      0
83.5            10000  10000      0      0      0      0      0
83.6            10000  10000      0      0      0      0      0
83.7            10000  10000      0      0      0      0      0
84              10000  10000      0      0      0      0      0
85              10000  10000      0      0      0      0      0
86              10000  10000      0      0      0      0      0
87              10000  10000      0      0      0      0      0
88              10000  10000      0      0      0      0      0
89              10000  10000      0      0      0      0      0
8A              10000  10000      0      0      0      0      0
8B              10000  10000      0      0      0      0      0
8C              10000  10000      0      0      0      0      0
8D              10000  10000      0      0      0      0      0
8E              10000  10000      0      0      0      0      0
8F              10000  10000      0      0      0      0      0
90              10000  10000      0      0      0      0      0
91              10000  10000      0      0      0      0      0
92              10000  10000      0      0      0      0      0
93              10000  10000      0      0      0      0      0
94              10000  10000      0      0      0      0      0
95              10000  10000      0      0      0      0      0
96              10000  10000      0      0      0      0      0
97              10000  10000      0      0      0      0      0
98              10000  10000      0      0      0      0      0
99              10000  10000      0      0      0      0      0
9A              10000  10000      0      0      0      0      0
9C              10000  10000      0      0      0      0      0
9D              10000  10000      0      0      0      0      0
9E              10000  10000      0      0      0      0      0
9F              10000  10000      0      0      0      0      0
A0              10000  10000      0      0      0      0      0
A1              10000  10000      0      0      0      0      0
A2              10000  10000      0      0      0      0      0
A3              10000  10000      0      0      0      0      0
A4               2000   2000      0      0      0      0      0
A5               2000   2000      0      0      0      0      0
A6               2000   2000      0      0      0      0      0
A7               2000   2000      0      0      0      0      0
A8              10000  10000      0      0      0      0      0
A9              10000  10000      0      0      0      0      0
AA               2000   2000      0      0      0      0      0
AB               2000   2000      0      0      0      0      0
AC               2000   2000      0      0      0      0      0
AD               2000   2000      0      0      0      0      0
AE               2000   2000      0      0      0      0      0
AF               2000   2000      0      0      0      0      0
B0              10000  10000      0      0      0      0      0
B1              10000  10000      0      0      0      0      0
B2              10000  10000      0      0      0      0      0
B3              10000  10000      0      0      0      0      0
B4              10000  10000      0      0      0      0      0
B5              10000  10000      0      0      0      0      0
B6              10000  10000      0      0      0      0      0
B7              10000  10000      0      0      0      0      0
B8              10000  10000      0      0      0      0      0
B9              10000  10000      0      0      0      0      0
BA              10000  10000      0      0      0      0      0
BB              10000  10000      0      0      0      0      0
BC              10000  10000      0      0      0      0      0
BD              10000  10000      0      0      0      0      0
BE              10000  10000      0      0      0      0      0
BF              10000  10000      0      0      0      0      0
C0              10000  10000      0      0      0      0      0
C1              10000  10000      0      0      0      0      0
C2              10000  10000      0      0      0      0      0
C3              10000  10000      0      0      0      0      0
C4              10000  10000      0      0      0      0      0
C5              10000  10000      0      0      0      0      0
C6              10000  10000      0      0      0      0      0
C7              10000  10000      0      0      0      0      0
C8              10000  10000      0      0      0      0      0
C9              10000  10000      0      0      0      0      0
CA              10000  10000      0      0      0      0      0
CB              10000  10000      0      0      0      0      0
CC              10000  10000      0      0      0      0      0
CD              10000  10000      0      0      0      0      0
CE              10000  10000      0      0      0      0      0
CF              10000  10000      0      0      0      0      0
D0.0            10000  10000      0      0      0      0      0
D0.1            10000  10000      0      0      0      0      0
D0.2            10000  10000      0      0      0      0      0
D0.3            10000  10000      0      0      0      0      0
D0.4            10000  10000      0      0      0      0      0
D0.5            10000  10000      0      0      0      0      0
D0.6            10000  10000      0      0      0      0      0
D0.7            10000  10000      0      0      0      0      0
D1.0            10000  10000      0      0      0      0      0
D1.1            10000  10000      0      0      0      0      0
D1.2            10000  10000      0      0      0      0      0
D1.3            10000  10000      0      0      0      0      0
D1.4            10000  10000      0      0      0      0      0
D1.5            10000  10000      0      0      0      0      0
D1.6            10000  10000      0      0      0      0      0
D1.7            10000  10000      0      0      0      0      0
D2.0             5000   5000      0      0      0      0    165
D2.1             5000   5000      0      0      0      0    165
D2.2             5000   5000      0      0      0      0    213
D2.3             5000   5000      0      0      0      0    232
D2.4             5000   5000      0      0      0      0    297
D2.5             5000   5000      0      0      0      0    310
D2.6             5000   5000      0      0      0      0    217
D2.7             5000   5000      0      0      0      0    158
D3.0             5000   5000      0      0      0      0    149
D3.1             5000   5000      0      0      0      0    134
D3.2             5000   5000      0      0      0      0    118
D3.3             5000   5000      0      0      0      0     96
D3.4             5000   5000      0      0      0      0     99
D3.5             5000   5000      0      0      0      0     76
D3.6             5000   5000      0      0      0      0    104
D3.7             5000   5000      0      0      0      0     88
D4              10000  10000      0      0      0      0      0
D5              10000  10000      0      0      0      0      0
D6              10000  10000      0      0      0      0      0
D7              10000  10000      0      0      0      0      0
D8              10000  10000      0      0      0      0      0
D9              10000  10000      0      0      0      0      0
DA              10000  10000      0      0      0      0      0
DB              10000  10000      0      0      0      0      0
DC              10000  10000      0      0      0      0      0
DD              10000  10000      0      0      0      0      0
DE              10000  10000      0      0      0      0      0
DF              10000  10000      0      0      0      0      0
E0              10000  10000      0      0      0      0      0
E1              10000  10000      0      0      0      0      0
E2              10000  10000      0      0      0      0      0
E3              10000  10000      0      0      0      0      0
E4              10000  10000      0      0      0      0      0
E5              10000  10000      0      0      0      0      0
E6              10000  10000      0      0      0      0      0
E7              10000  10000      0      0      0      0      0
E8              10000  10000      0      0      0      0      0
E9              10000  10000      0      0      0      0      0
EA              10000  10000      0      0      0      0      0
EB              10000  10000      0      0      0      0      0
EC              10000  10000      0      0      0      0      0
ED              10000  10000      0      0      0      0      0
EE              10000  10000      0      0      0      0      0
EF              10000  10000      0      0      0      0      0
F5               1000   1000      0      0      0      0      0
F6.0            10000  10000      0      0      0      0      0
F6.1            10000  10000      0      0      0      0      0
F6.2            10000  10000      0      0      0      0      0
F6.3            10000  10000      0      0      0      0      0
F6.4            10000  10000      0      0      0      0      0
F6.5            10000  10000      0      0      0      0      0
F6.6            10000  10000      0      0      0      0      0
F6.7            10000  10000      0      0      0      0      0
F7.0            10000  10000      0      0      0      0      0
F7.1            10000  10000      0      0      0      0      0
F7.2            10000  10000      0      0      0      0      0
F7.3            10000  10000      0      0      0      0      0
F7.4            10000  10000      0      0      0      0      0
F7.5            10000  10000      0      0      0      0      0
F7.6            10000  10000      0      0      0      0      0
F7.7            10000  10000      0      0      0      0      0
F8               1000   1000      0      0      0      0      0
F9               1000   1000      0      0      0      0      0
FA               1000   1000      0      0      0      0      0
FB               1000   1000      0      0      0      0      0
FC               1000   1000      0      0      0      0      0
FD               1000   1000      0      0      0      0      0
FE.0            10000  10000      0      0      0      0      0
FE.1            10000  10000      0      0      0      0      0
FF.0            10000  10000      0      0      0      0      0
FF.1            10000  10000      0      0      0      0      0
FF.2            10000  10000      0      0      0      0      0
FF.3            10000  10000      0      0      0      0      0
FF.4            10000  10000      0      0      0      0      0
FF.5            10000  10000      0      0      0      0      0
FF.6            10000  10000      0      0      0      0      0
FF.7            10000  10000      0      0      0      0      0
TOTAL          3007000 3007000      0      0      0      0   2621
```

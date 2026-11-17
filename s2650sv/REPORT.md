# s2650sv — report

SystemVerilog Signetics 2650 core, cycle-for-cycle identical to the fleet's `sgs2650` (through `s2650_cpu`),
2650A / 2650B by parameter, targeted at Quartus 17.0 / Cyclone V (5CSEBA6U23I7).

## Result in one table

| | 2650A (fleet default) | 2650B | 2650A, RAS in registers | 2650B, RAS in registers |
|---|---|---|---|---|
| Exerciser (480 tests), lockstep with the reference | PASS, 0 mismatches | PASS, 0 | PASS, 0 | PASS, 0 |
| Exerciser on s2650sv alone (s2650sv drives the bus) | PASS | PASS | PASS | PASS |
| Random lockstep cycles / mismatches | 200,000,000 (8 seeds) / 0 | 100,000,000 (4 seeds) / 0 | 50,000,000 (2 seeds) / 0 | 25,000,000 (1 seed) / 0 |
| Directed sweeps: runs / cycles / mismatches | 132,656 / 7,587,810 / 0 | 132,656 / 7,587,810 / 0 | 132,656 / 7,587,810 / 0 | 132,656 / 7,587,810 / 0 |
| Opcode × addressing mode × taken classes hit in lockstep (of 694) | 694 | 694 | 694 | 694 |

Every output (`req ad wr dw mio ene dc ph intack flag`) is compared on every clock, and R0-R3, R1'-R3', PSL,
PSU, IAR, all eight RAS entries and the state on every clock (a stronger check than at instruction boundaries).

Further evidence:
* GHDL simulation of the *original VHDL* against the GHDL-converted netlist used as oracle: 4 runs × 150,000 clocks, 19,199,399 output bits compared, 0 mismatches (601 bits were still 'U' in the VHDL in the first clocks and were not compared).
* Formal bounded equivalence (Yosys SAT miter, gold = GHDL-elaborated `s2650_cpu`, gate = `s2650sv_s2650_cpu`,
  every input free on every clock, from the all-zero power-up state): no difference on any output in the first 6 clocks for any input sequence (`bmc.sh 6`; depth 4 in 28 s, 6 in about 10 min; a mutant is found at depth 4). Six clocks from power-up cover reset plus the first one to three instructions with any opcode bytes, ack pattern, irq and ivec, so this is a bounded complement to the simulation, not a full proof.
* Mutation check: 10 deliberate bugs in s2650sv, all 10 caught by both the directed sweep and the random lockstep;
  8 of 10 also by the exerciser run on the mutant alone (the two it misses — INTACK one clock early, MIO held
  low through I/O wait states — change pin timing only, which only the lockstep sees).
* Lint: `verilator --lint-only -Wall` clean on every top and parameter set, four waivers (listed below).

## Deliverables

```
rtl/s2650sv.sv            the core (parameters VER_B, RAS_MLAB)
rtl/s2650sv_s2650_cpu.sv  drop-in for s2650_cpu: same ports, no parameters, 2650A
rtl/s2650sv_pool.sv       wrapper on chip_pool_pkg::s2650_i_t / s2650_o_t, parameter IVEC (default 8'h03)
rtl/s2650sv_all.sv        s2650sv.sv + s2650sv_s2650_cpu.sv in one file (all a Quartus project needs except the pool wrapper)
verify/                   harnesses, exerciser (source, generator, binary, listing), scripts, results/  (verify/README.md: how to rerun)
REPORT.md                 this file
```

Drop-in: replace `s2650_cpu u (...)` by `s2650sv_s2650_cpu u (...)`, same port list, and add `s2650sv_all.sv`
(or the two files) to the project instead of the four VHDL files.

## The reference

* md5 verified for all four files, and the four fleet repos (Galaxian, Pacman, Centipede, SpaceInvaders) hold
  byte-identical copies: `sgs2650.vhd 9e6f96d4…`, `sgs2650_pack.vhd d1525b11…`, `base_pack.vhd 00dc3a79…`,
  `s2650_cpu.vhd 0671e283…`.
* `s2650_cpu` passes no generic, so the fleet runs `VER_B = false` (2650A), and ties `reset_na` to '1'.
* In sgs2650, `VER_B` only decides whether PSU bits 4:3 are writable (user flags). Nothing else of the 2650B
  exists in it: LDPL / STPL (10 / 11) are decoded with length 3 but never executed (see below). s2650sv matches
  that exactly; with `VER_B = 0` the two flag registers are a constant (`generate`), nothing of the -B remains.
* Fleet instances (read from the source): Galaxian `galaxian_board.sv` ivec 03, irq / sense from the board;
  Pacman `pacman_board.sv` ivec 03; Centipede `centipede_dispatcher.sv` ivec 00; SpaceInvaders
  `galaxian_board.sv` **ivec 03** (irq 0, sense = ~cpu_nmi_n) and `zac1b1120_board.sv` **ivec 00** (irq 0, sense =
  vertical blank) — the task table has those two ivec values swapped. `flag` is unconnected everywhere.
* `chip_pool_pkg` differs per repo: Galaxian and Centipede have `s2650_i_t.reset`, **Pacman has `reset_n`**,
  SpaceInvaders has no S2650 type. `s2650sv_pool.sv` is written for `reset`; the one line to change for Pacman
  is marked in the file.

## Verification method

1. **Oracle.** `verify/refmodel/convert.sh`: the yosys GHDL plugin elaborates `s2650_cpu` (+ sgs2650, VER_B
   false) and `sgs2650` with VER_B true, written out as Verilog with no optimisation (`ref_a.v`, `ref_b_core.v`;
   deterministic, same md5 on every run). Registers keep their VHDL names, which the harness probes.
2. **Is the converted netlist faithful?** `verify/ghdl/run_xcheck.sh` dumps stimulus and the netlist's outputs
   per clock from the Verilator harness and replays the stimulus through the original VHDL in the GHDL
   simulator. Each run starts with a short program that writes every register (both banks, PSL, PSU, all eight
   RAS entries): GHDL starts signals at 'U', and `IF x = '1'` on 'U' takes a different branch than the netlist's
   power-up 0, so without it the two diverge on uninitialised PSL condition codes. Result: 4 runs × 150,000 clocks, 19,199,399 output bits compared, 0 mismatches (601 bits were still 'U' in the VHDL in the first clocks and were not compared).
3. **Lockstep** (`verify/tb`): reference and s2650sv in one Verilator model on the same inputs. Bus model as the
   fleet boards: the access shown during an ack completes, read data is presented for the next ack, reset
   restarts on a read of 0000; I/O reads return the last write XOR $5A. Random mode draws per segment: ack
   always / Bernoulli / bursts of 0..6 wait states / periodic, `dr` held or garbage on wait cycles, irq off /
   random levels / pulses, ivec fixed (03, 00, 83, 7F, 40, random) or random per cycle (indirect vectors
   included), sense toggling, resets of 1..4 clocks at random times (also mid-instruction), memory random (all
   256 opcodes) with three opcode biases. Segments restart from power-up (all registers 0, as on the FPGA).
4. **Directed sweeps** (`lockstep sweep 4`): for every opcode (register field included) × addressing variant
   (relative / branch: direct, indirect; absolute non-branch: index mode × indirect) × 4 random prologues (both
   banks, PSL, PSU with II=0 and random SP; register values biased to 00 / 01 / FF so BRN / BIR / BDR go both
   ways): a baseline run, then irq as a one-clock pulse on **each** clock of the instruction, irq held from each
   clock (direct and indirect vector), reset on each clock, ack stalled for 1, 2 and 3 clocks starting at each
   clock (each access), and the stall run again with garbage `dr`.
5. **Coverage** is counted from the reference's state: an instruction is classed by opcode, addressing variant
   and, for conditional flow, taken / not taken. 694 classes exist (576 opcode × mode); the hang opcodes count
   once.
6. **Exerciser** (below), in lockstep and on s2650sv alone.
7. **Mutation check** (`verify/tb/mutate.sh`), **formal BMC** (`verify/formal/bmc.sh`).
8. **MAME** (`verify/mame`, below).

## Exerciser

Search first: no public 2650 instruction exerciser or test ROM turned up (MAME has no CPU test ROMs for it;
WinArcadia / Ambrosia ship an assembler, not a test suite; the Signetics 2650 test board sold by cpushack has
its test program in an unpublished 2716). So one was built: `verify/exerciser/gen_exerciser.py` generates
`exerciser.asm` (assembled by `asm2650.py` into `exerciser.bin`, 32 KB, all four pages).

* 480 self-checking tests. Each sets PSL and registers, runs the instruction(s), compares R0-R3, PSL and any
  memory / PSU result with its expected table (COMR / COMA + BCFA to the fail handler). Result 'P' / 'F' on
  extended port FF and at $7FF0; console on port FE.
* Covers every opcode in every addressing mode — register, immediate, relative and absolute direct / indirect,
  absolute indexed with every index register, with and without auto increment / decrement, indirect indexed —
  every branch / branch-to-subroutine form (each conditional one taken *and* not taken in the same test),
  ZBRR / ZBSR to both ends of page 0 direct and indirect, BXA / BSXA direct and indirect, RETC / RETE both
  ways, LPSU / LPSL / SPSU / SPSL / CPSU / CPSL / PPSU / PPSL / TPSU / TPSL, WC / COM / C / IDC / OVF, DAR,
  RRR / RRL with and without WC, both register banks, 8-level call nesting, SP wrap 7→0→7, interrupts through
  two vectors (03 and 7E = $1FFE), II holding an interrupt off until CPSU, HALT left by an interrupt, sense
  (SPSU / TPSU) and flag (PPSU / CPSU looped back to sense by the test bench), all six I/O instructions,
  code / data / calls across all four 8K pages. 570 of 576 opcode × mode classes; the 6 not covered are the
  opcodes that hang sgs2650 by design (10, 11, C4-C7, below) and cannot be in a self-checking program.
* Expected values come from a Python model of sgs2650. The model also knows the Signetics manual's answer;
  18 tests check behaviour where the two differ (`exerciser_quirks.txt`), i.e. they lock in the fleet behaviour
  and would fail on silicon / MAME.
* The assembler: the public ASL macro assembler supports the 2650, but building it in this sandbox was refused
  by the session's policy (external code), so `asm2650.py` (about 300 lines, Signetics syntax) was written; the
  listing `exerciser.lst` shows every encoding.

## sgs2650 vs MAME vs the Signetics manual

MAME's `s2650.cpp` (mamedev/mame master @ b2a182f0, unmodified) is compiled against a 150-line stand-in for
the MAME device framework (`verify/mame/stub/emu.h`). For every instruction the RTL executes, MAME is loaded
with the RTL's state at that instruction's start (memory rolled back to it), runs the one instruction, and
IAR, R0-R3, R1'-R3', PSL, PSU, the logical return stack, memory writes, I/O accesses and cycles (RTL clocks
× 3 vs MAME clock count) are compared. Directed: every opcode × 8 operand-byte variants × 4 seeds after a
prologue; random: 3,010,976 instructions with interrupts (direct and indirect vectors) and HALT.
Manual = *Signetics 2650 User Manual* (transcription at amigan.yatho.com/2650UM.html).

The default (s2650sv, 2650A) follows sgs2650 in every case below.

| # | Where | sgs2650 (= s2650sv) | MAME | Manual |
|---|---|---|---|---|
| 1 | Page boundary: sequential fetch, relative EA, absolute indexed EA, second byte of an indirect pointer (all opcodes using them) | 15-bit arithmetic: carries into A14:A13 | modulo 8K inside the page | modulo 8K ("relative addressing is modulo 8K", "page boundaries cannot be indexed across", "programs cannot flow across a page boundary") |
| 2 | Signed compare (COM, PSL.COM=0), both operands negative (E0-EF) | CC inverted: e.g. COMZ R0=$FF vs R1=$FE gives LT | correct | correct |
| 3 | IDC of ADD / SUB with carry / borrow in (WC=1) (80-AF) | nibble compare of result and operand: wrong when the carry / borrow in matters (05+0F+1: IDC 0) | carry out of bit 3 | carry / borrow out of bit 3 |
| 4 | RRR / RRL (50-53, D0-D3) | OVF never changed | OVF = bit 7 changed, also with WC=0 | OVF set when bit 7 changes (WC=1 section; the RRL page says "whenever") |
| 5 | DAR (94-97) | CC from the result | CC unchanged | "CC set to a meaningless value": both fine |
| 6 | Relative branch / call taken *indirect* (18-1B, 38-3B, 58-5B, 78-7B, 98-9B incl. ZBRR, B8-BB incl. ZBSR, D8-DB, F8-FB) | 4 cycles | 5 | 3 + 2 for indirect = 5 |
| 7 | RETC taken (14-17) | 3 cycles | 5 | 3 (MAME is wrong) |
| 8 | Interrupt entry | 2 cycles (4 with indirect vector) | 3 (5) | a ZBSR is jammed: 3 (5) |
| 9 | Interrupt, indirect vector (ivec bit 7) | the pointer address is taken from the byte *read at* sext(ivec), not from ivec | pointer at sext(ivec) | pointer at sext(ivec) |
| 10 | HALT left by an interrupt | return address HALT+2 (the byte after HALT is skipped) | HALT+1 | resumes after HALT |
| 11 | STRA,R0 *a,R0,+ / *a,R0,- (opcode CC: indirect, auto inc / dec, R0 also the index) | stores R0 **before** the update; the direct form stores it after | after | increment / decrement happens before use |
| 12 | Undefined 90 / 91 | act as LPSU / LPSL | 1-byte NOP | undefined |
| 13 | Undefined B6 / B7 | act as TPSU / TPSL (2 bytes, 3 cycles) | 1-byte NOP | undefined |
| 14 | Undefined C4-C7; LDPL / STPL 10 / 11 (2650B instructions) | the CPU never leaves sIMM / sIMM2: it reads on through memory forever (until reset); interrupts are not taken | 1-byte NOP | C4-C7 undefined; 10 / 11 exist on the -B only |
| 15 | Reset | resets IAR, page, SP, II, RS, flag (+ user flags); PSL otherwise, R0-R3', RAS not reset | PSL = COM \| WC, registers and RAS cleared | — |

Counts (`verify/results/mame_directed.log`, `mame_random.log`): directed 394,657 instructions, random 3,010,976
instructions (68,952 of them touch a page boundary, all listed separately under row 1) and 159 interrupt
entries (73 direct, 86 indirect vector). Every disagreement class in both runs falls into the rows above, with
two exceptions, both from the random stimulus rather than the CPU: one direct interrupt whose vector changed
during the two-clock entry (sgs2650 samples `ivec` again in the entry clock, MAME once), and one BCFR at $1FF5
in self-modifying random code. In the directed run, which has neither interrupts nor self-modification, the
same-page disagreements are exactly rows 2-7 and 11-13 (B6 / B7, 90 / 91, 94-97, E1-EF, the IDC cases of 80-AF,
50-53 / D0-D3, RETC and indirect relative branch cycles, STRA,R0 indirect auto-indexed); nothing else.

**The open item `<AVOIR> Indirect indexé ++ / --`**: indirect indexed works as the manual says for all ALU
instructions and for STRA with R1-R3 as index — the pointer is fetched, then the index (incremented / decremented
first) is added (post-indexing), and R0 is the operand. The single deviation is #11: STRA with R0 as both
operand and index, indirect, auto increment / decrement, stores the old R0 (the direct form stores the new
one). Confirmed by MAME and pinned by exerciser tests T231 / T232.

Bus behaviour worth knowing (all identical in s2650sv, as required):
* `ene` / `dc` come from the instruction register, which loads `dr` on every clock of the opcode fetch. For
  REDC / REDD / WRTC / WRTD the access is set up in the fetch's ack clock, so with back-to-back acks `ene` / `dc`
  show the *previous* opcode's bits 2 / 6 in that clock. With at least one wait clock (every fleet board: ack
  every 3 or more clocks) the register already holds the right opcode.
* `mio` is 0 only in the clock that launches an I/O access; on its wait clocks it returns to 1 (`ph` stays 11).
  The fleet boards register `mio` at the ack, so they see 0.

## Upstream

* The current upstream copy is MiSTer-devel/Arcadia_MiSTer `rtl/s2650/` (Grabulosaure = TEMlib): `sgs2650.vhd`
  md5 `0aa39462…`, unchanged since the repo's initial commit 3e0d5c5 of 2021-10-26 (header still "DO 4/2018");
  `sgs2650_pack.vhd` and `base_pack.vhd` identical to the fleet's. temlib.org returns no page; GitHub code
  search is closed to this session, so no other copies were looked for.
* Diff fleet vs upstream, `sgs2650.vhd` only, two fleet fixes:
  1. sIO: after an I/O access the next opcode is fetched from IAR as a read (`ad_c <= iar; ph_c <= phCODE;
     wr_c <= '0'`); upstream fetched from the I/O port address, with a write strobe after WRTx.
  2. sINDIRECT2: ZBRR / ZBSR indirect added to the branch list; upstream re-read the pointer forever.
* None of the deviations in the table above are fixed upstream.

## Cyclone V area and depth (Yosys `synth_intel_alm -family cyclonev`)

| | LUTs (ALUT2-6) | carry-chain cells | FFs | MLAB (bits / 1 MLAB) | rough ALM estimate | LUT levels reg→reg | in→reg | reg→out | in→out |
|---|---|---|---|---|---|---|---|---|---|
| sgs2650 (s2650_cpu, GHDL front end) | 1064 | 302 | 170 | 15 / 1 | ≈ 766 | 11.1 | 11.1 | 11 | 11 |
| **s2650sv, RAS in MLAB (default)** | **622** | **143** | 181 | 15 / 1 | **≈ 413** | **10** | 9 | 10 | 9 |
| s2650sv, RAS in registers | 680 | 143 | 301 | 0 | ≈ 457 + FF packing | 10 | 9 | 10 | 9 |

LUT breakdown, s2650sv: 60 LUT6, 276 LUT5, 115 LUT4, 101 LUT3, 70 LUT2 (reference: 166 / 443 / 261 / 115 / 79). The
"rough ALM estimate" is LUT6 + (smaller LUTs) / 2 + carry cells / 2, ignoring Quartus packing limits; it is only
for comparing the two designs. s2650sv uses 11 more flip-flops than the reference (registered decode, 11-bit
one-hot state) and 44 % fewer LUT + carry cells.

`depth.py` counts LUT levels on the mapped netlist (a carry-chain step counts 1/20). Paths into the core
from `dr` / `ack` and out through the combinational bus outputs are listed separately because the board logic
adds its own levels to them. Quartus restructures logic itself, so treat these as relative numbers; real ALM
and timing figures come from the local Quartus 17 compile (next session). At roughly 0.6-0.9 ns per level
including routing on a -7 part, 10 levels is about 6-9 ns, so the 10 ns target looks reachable; the reference
needs one level more. Quartus timing is the real check.

## Design decisions

* **Same registers, same reset.** Every architectural register and every bus register of sgs2650 is kept,
  reset exactly as there (IAR, AD, SP, II, RS, flag, state, + user flags on the -B); everything else powers up
  0, as the reference does on the FPGA. Verified from power-up in every lockstep segment and in the BMC.
* **State** one-hot, 11 flip-flops; the sOPCODE bit is stored inverted so that the all-zero power-up state is
  sOPCODE, as in the reference.
* **Decode registered with the opcode.** sgs2650 registers a decoded record (`dec`) on the opcode fetch; s2650sv
  registers 24 one-hot decode bits plus the branch condition (`taken`) on every opcode-fetch clock, exactly when
  `ri` loads. Inside an instruction neither the registers nor PSL can change before they are used, so this is
  equivalent (checked by every run above) and takes the decode and the register-is-zero test off the critical
  path. Decoder checked against the 256-entry `sgs2650_pack` table exhaustively.
* **Flat muxes.** The next address, next IAR, register write data and next PSL are chosen by one-hot select
  vectors written in the same case structure as sgs2650, then combined in a single AND-OR level instead of a
  priority chain. One shared 8-bit ±1 (BIR / BDR, auto index), one shared 15-bit index adder (absolute,
  indirect, BXA), one ALU adder for ADD / SUB / COM.
* **Return stack**: `RAS_MLAB = 1` (default) puts the 8 × 15 stack in one MLAB (`ramstyle "MLAB, no_rw_check"`,
  asynchronous read into the `rras` register, as sgs2650's registered read). Cost: 1 MLAB (10 ALMs) instead of
  120 flip-flops plus an 8:1 × 15 read mux (`RAS_MLAB = 0`: +58 LUTs, +120 FFs in the Yosys count). No M10K, no
  DSP. Note: whether Quartus initialises MLAB contents to 0 at configuration matters only for a RETC before
  any call after power-up (the reference has the same exposure if Quartus maps its `ras` to an MLAB).
* **2650B** costs two flip-flops behind `generate if (VER_B)`; at the default they are constants.
* **Quartus 17 rules followed**: no `for (genvar ...)`, no `'{...}` patterns, no casts, no bit-select on an
  expression, every identifier declared before use, no struct ports on the core; the pool wrapper drives its
  struct output field by field from plain wires. Functions use the Verilog-2001 return-by-name form.

## Lint waivers (`verify/lint.vlt`)

* `UNUSEDSIGNAL ri[4:3]`: `ri` keeps the whole opcode as in sgs2650; those two bits only feed the decode, which
  is registered separately.
* `UNUSEDSIGNAL psu_c[7], [4:3]`: `psu_c` is the whole next PSU; bit 7 is replaced by the sense input and bits
  4:3 are constant on the 2650A.
* `DECLFILENAME` on `s2650sv_all.sv` (two modules in one file by design), `PINCONNECTEMPTY` on the pool
  wrapper's `.flag()` (unused in the fleet).

## Not done / limits

* **Quartus compile and hardware** — not available here; next session, locally.
* **ASL** could not be built here (policy), hence the own assembler.
* **Formal**: bounded to 6 clocks from power-up, not an unbounded proof. A depth-10 run was stopped after 30 minutes without an answer; the SAT cost grows steeply with depth.
* One random MAME-comparison event (BCFR at $1FF5 in self-modifying random code) disagrees in a way none of the
  classes above explains; it was not chased further (MAME is not the oracle for s2650sv, and the RTL lockstep on
  the same run reported 0 mismatches).
* `run_all.sh` was run in one go except its last stage: the session's 30-minute limit for a background job
  stopped it in the MAME stage, which was then rerun on its own (same commands, logs in `results/`).
* MAME's PSU bit-7 (sense) handling is not compared (it samples a callback; sgs2650 registers the pin).

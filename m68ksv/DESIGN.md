# m68ksv — microarchitecture

m68ksv is one synthesizable SystemVerilog core for the Motorola 68000, 68008 (DIP48 and PLCC52 / "FN"), 68EC000,
68010, 68020 and 68EC020, selected by the compile-time parameter `CPU`. It is built for Quartus 17.0.2 on the
MiSTer's Cyclone V (5CSEBA6U23I7): timing must close at 96 MHz with the CPU speed set by clock enables, and the 68000
configuration must be no bigger than fx68k compiled in the same test top. This document describes the design for
the whole family. Checkpoint 1 implements the 68000; what the other members add, and where it goes, is in "Family
plan" below.

## 1. Block structure

```text
m68ksv (CPU)                         top: reset synchroniser, phase generator, generate-if per CPU family member
├── m68ksv_eu                        execution unit
│   ├── m68ksv_urom                  microcode ROM          (M10K, synchronous read; RES = 1: m68ksv_ucs, 3.1)
│   ├── m68ksv_drom1 / drom4e        opcode -> class         (M10K / logic; RES = 1: drom1 in logic)
│   ├── m68ksv_drom2                 class -> routine kinds  (M10K)
│   ├── m68ksv_drom3                 kind x EA mode -> micro-address (M10K, two read ports)
│   ├── m68ksv_rf (x3, +1 debug)     register-file copies (MLAB, 32 x 32, common write port)
│   └── m68ksv_alu                   data ALU (one shared adder, 1-bit shifter, BCD, result select)
└── m68ksv_biu                       bus interface unit for the asynchronous 68000 bus, 16- or 8-bit (input bus8:
    constant 1 on the 68008 / 68008FN, the MODE latch on the 68EC000, constant 0 elsewhere; planned: m68ksv_biu32)
```

Rules that hold for every configuration:

- **The BIU is the only place that knows the bus width.** The execution unit asks for byte or word cycles (68020:
  byte / word / long, any alignment); the BIU splits them into physical cycles (68008: two byte cycles per word;
  68020: dynamic sizing from `DSACK_n`; `STERM_n` is ignored since checkpoint 5), runs wait states, arbitration, 6800 cycles, HALT / re-run.
  The execution unit simply does not advance while the BIU holds the phase generator (see 2).
- **`CPU` is a compile-time parameter; logic of unselected members folds away.** Each member's extra hardware
  (VBR adder, SFC / DFC, loop-mode state, the 020 cache, the 32-bit BIU, 020 EA extension sequencer) sits behind
  `generate if` on `CPU`, and each member gets its own microcode / decode ROM *contents* generated from the same
  generator (`rtl/gen/m68ksv_ucode.py`; the per-member `--cpu` option arrives with the 68010 at checkpoint 3), so
  the ROMs of other members are never instantiated. The single
  run-time choice in the whole family is the 68EC000 `MODE` latch (8- or 16-bit bus), which exists only when
  `CPU == 68001` (68EC000 code, see 9).
- Every configuration gets its own Quartus revision (`syn/quartus/`) so that a parameter-selected table that
  Quartus optimises away is caught in `map.rpt` / `fit.rpt` (the sega_decrypt lesson, vault note
  "Quartus 17.0 SystemVerilog subset").

## 2. Clocking: one clock, phase enables, micro-cycles

Inputs `clk`, `cen_p`, `cen_n`: the rising and falling edges of the emulated CPU clock as one-`clk`-wide enables
(the fx68k `enPhi1` / `enPhi2` convention; they must alternate, any spacing). No derived clocks.

The top counts phase enables into `ph` and produces `e1 e2 e3 e0` (alternating `cen_n` / `cen_p`). Four phases are
one **micro-cycle** = two CPU clocks, the 68000's own internal rhythm (T1–T4): every 68000 micro-instruction takes
two clocks and a bus cycle (S0–S7, four clocks) spans two micro-instructions. Inside a micro-cycle:

| Edge | Execution unit | BIU (bus cycle started in this micro-cycle / the next) |
|---|---|---|
| e0 | micro-instruction starts (`uw <= ROM output`); ALU write-back of the previous one (register file, SR with N / Z formed from RES now, temporaries); a bus cycle named by the new micro-instruction starts (S0) | S0 / S4 |
| e1 | branch condition, FIN decision and pending interrupt latched (`cond_q`, `fin_q`, `irq_q`); write-data source decoded; function code latched | S1 / S5 (DTACK sampled at the end of S4) |
| e2 | next micro-address loaded (`ua_r`, address-error override); operands, ALU op and adder controls latched (register-file data valid now); bus address checked (address error) and taken by the BIU; write data latched | S2: address, FC, AS (read strobes) / S6 |
| e3 | ALU result, X / V / C (and the N / Z of the few ops that do not take them from the result) and the address-unit result latched; the address-unit result written to the register file | S3 (write data) / end of S6: read data taken |

**Wait states freeze the phase generator**: in the second micro-cycle of a bus cycle `e1` is withheld until
`DTACK_n` (or `BERR_n`, `VPA_n` for IACK) is seen, in whole CPU clocks, exactly like the 68000 inserting SW states
after S4. Everything (micro-sequencer included) waits, so no micro-instruction ever has to poll the bus. Bus
arbitration and HALT use the same mechanism: a micro-instruction that wants to start a bus cycle while the bus is
granted away holds the phase generator until the bus returns (checkpoint 2).

**68020 / 68EC020 (checkpoint 4b): one micro-cycle per CPU clock.** The 68020 build generates the four phases inside
one CPU clock: e0 on `cen_p` (the rising edge), e1 one `clk` later, e2 on `cen_n` (the falling edge), e3 one `clk` later
(`m68ksv.sv` `g_ph020`). It needs two `clk` or more between consecutive CPU edges (CPU clock ≤ clk / 4: 24 MHz at
96 MHz; the Quartus test top uses clk / 4). A bus cycle still spans two micro-instructions, so a zero-wait cycle
(asynchronous, DSACK: the only kind on the 68020) takes three clocks (the BIU holds e1 of the second micro-word one
clock, section 7.2); a cache hit or the held half of a long read is an internal two-clock cycle; internal micro-instructions take one clock each. The execution unit itself is unchanged (it only
needs one `clk` or more between phases, as before).

Each register-to-register path is at most one `clk` long (STA sees single-cycle paths at 96 MHz whatever the enable
rate), and nothing may rely on more than one `clk` between consecutive phases (`cen_p` / `cen_n` may come on
consecutive clocks, as with fx68k). Checkpoint 1b split the long chains so that no single-clock path crosses two
of these stages: decode of the microword → register-file read address (registered every clock); register-file data →
operand mux → operand register (e2); operands → adder / logic → RES and X / V / C (e3); RES → N / Z → SR (e0); RES /
old value → merge → register-file write (e0); condition → FIN decision (e1) → next address (e2). The suite also runs
with random idle clocks between the enables (`harte -gap 3`, part of `run_all.sh`).

## 3. Micro-sequencer and the M10K latency

**Microcode ROM** (`m68ksv_urom`, generated): 703 words × 93 bits for the 68000 family since checkpoint 6 (1,131 before the
compaction below; 745 × 75 at checkpoint 1), synchronous read
(`always_ff q <= rom[a]` on an initialised array with `romstyle "M10K"` — the M10K template; no combinational ROM,
no mux in the data path; checkpoint 1 used a case table, which Quartus 17 built in logic for the urom and drom2,
616 + 89 ALMs). The address register is `ua_r`, loaded at **e2** with the next micro-address; the ROM output is valid
one `clk` later and is copied into the micro-instruction register `uw` at the next **e0** — at least two `clk` later
even when the enables come back to back. The next micro-address is formed at e2 from the condition and FIN decision
latched at e1:

| `sq` | Next address |
|---|---|
| NXT / CALL / RET | field `nxt` / `nxt` (return = upc + 1) / return register |
| BT / BF | `nxt` if the condition is true / false, else upc + 1; conditions read registered state only (flags, counter, MOVEM mask, divider state, IR condition code) — a branch on an ALU result is placed one micro-instruction later, as in the 68000 |
| CONT / BODY | next routine of the decoded chain (see below) |
| FIN / FINC / FINNC | instruction end (optionally conditional): dispatch the next instruction, or an interrupt / trace / privilege exception |

An address error found at e2 overrides the next address with the group-0 routine (`EXC0A`, or `HALTA` during group-0
processing; one idle micro-cycle more than a bus error's `EXC0` / `HALT` entry, see 5). The faulting micro-instruction still completes, which is how register updates made in the same
micro-cycle as the faulting access stay visible (the suite checks this, e.g. `(An)+` read faults).

**Decode** is a ROM pipeline started when the next opcode is copied from IRC to IRN at the start of the
instruction's last prefetch: `drom1` (opcode[15:6] → four class codes, one per source category Dn / An / memory /
#imm, plus a validity class for the memory modes) and `drom4e` (the 4E40–4E7F group, by opcode[5:0]) → class
register → `drom2` (class → routine kinds k1 / k2, body address, ALU op, decoded A source, size rule, privileged,
no-flags) → `drom3` (kind × EA mode → routine address, two read ports for k1 and k2) → decode result register.
Five `clk` of latency, used at the FIN micro-instruction's e2, which is at least six `clk` after IRN is loaded (FIN /
FINC / FINNC are never in the micro-cycle that starts the final prefetch; the generator asserts it). The single-step
suite does not exercise this distance (each test ends at the next boundary), so the harness build has a check
(`M68KSV_SIMCHECK`: stop if a dispatch comes less than five clocks after IRN changed); the suite exercises the
minimum distance and passes it, a check one clock tighter fails. The dispatched micro-instruction starts at the next e0, so
an instruction's first micro-instruction (and the bus cycle it names) begins right after the previous instruction's
last one: no dispatch bubble, the 68000 rhythm.

**Routine chain**: an instruction runs `[k1 routine] [k2 routine] body`, linked by CONT. k1 / k2 are effective-address
routines shared by all instructions (read B/W, read L, address only, address only for MOVEM, immediate) or
instruction-specific per-mode tables (JMP, JSR, LEA, PEA); MOVE destinations are bodies per destination mode
(the class carries the destination). This is how the 68000's own bus orders are reproduced exactly (extension-word
prefetches, `-(An)` idle cycle, long reads high word first, RMW writes low word first, MOVE's quirky orders) — the
suite's transaction order matches on all 1,000,060 tests.

**Microword fields** (93 bits, 703 words for the 68000 family): sequencing `sq nxt cd`; bus `bus ba bs bd bf dw` (op,
address source, size, read destination, function code, write data); address unit `aa ab ad as`; ALU `op xa xb xd xs
fl`; misc `ms` (mask load, counters, divider steps, vector numbers, exception entry, RESET output, ...); group-0 /
68000-timing fields `bn ai iq pl lk fh lh pu` (section 5). Field layout and codes are generated
into `m68ksv_upkg`, so microcode and RTL cannot drift apart.

**ROM shapes (checkpoint 6).** An M10K holds 1,024 × 10 or 2,048 × 5 bits, so a ROM just over 1,024 words costs twice
the blocks per bit. The generator therefore:
- **compacts the 68000-family microcode** (`compact000()` in `rtl/gen/m68ksv_ucode.py`): words whose fields (nxt aside)
  are equal and whose successors behave the same are merged (partition refinement over the sequencing graph: nxt for
  NXT / CALL / BT / BF / FINC / FINNC, upc + 1 for BT / BF / CALL, nothing for FIN / CONT / BODY / RET / RSM), then laid
  out again (an upc + 1 successor right after its word, copied where needed). 1,131 → 703 words, so the ROM is 1,024 deep
  (10 M10K instead of 19). The reset / exception block (RESET .. HALT_L) and the Bcc / BSR routines stay word for word
  at their addresses (the RTL compares `upc` / `ua_r` with those labels; package `UA_*` is shared by all ROM sets). A
  bisimulation check from every old address proves the result (same fields, successors related, labels related);
  `M68KSV_UAREL=<file>` writes the old / new address pairs for the A/B harness (`dbg_upc`). The EU addresses the ROM
  with `ua_r[UA000_W-1:0]` (10 bits).
- **does not compact the 68010 / 68020 microcode**: their micro-addresses are architectural (a format-8 / format-B frame
  stores the resume address, and an RTE resumes at any address its frame names).
- **splits the 68010 ROM** (1,451 words) into 1,024 words + a 512-word tail (`rom_module_split`: 11 + 6 M10K instead of
  21). To keep the select mux off the paths that start at the ROM output, both ROMs are read one clock ahead, as the
  `RES = 1` micro ROM (3.1: address `ua_n`, clock enable `ua_ce`); the mux sits in front of a register and `q` is that
  register, which holds the word at the previous clock's `ua_r` in every clock, as one ROM addressed by `ua_r` did.
  The micro-word's users now start at a register instead of an M10K output. Addresses 1,536 – 2,047 give the zero word,
  as the padding of one ROM did.
- **leaves the 68020 ROM as it is** (1,961 words already fill 2,048).

### 3.1 Control-storage placement: parameter `RES` (checkpoint 6)

`RES` (on `m68ksv`, `m68ksv_eu` and `m68ksv_fleet`; Quartus test top: macro `M68KSV_RES=1`, revisions `*_lh`) picks where
the control storage goes. Behaviour is the same clock for clock on every CPU (proved by the clock-exact A/B, REPORT.md
checkpoint 6):

| | RES = 0, BRAM-heavy (default) | RES = 1, logic-heavy |
|---|---|---|
| microcode | one wide ROM (`m68ksv_urom*`) | two-level control store (`m68ksv_ucs*`): micro ROM + nano ROMs |
| opcode decode `drom1` (+ 68010 `drom1lp`) | M10K | logic (`romstyle "logic"`, same output register) |
| `drom2`, `drom3` | M10K | M10K |
| CPU M10K (68000 family / 68010 / 68020) | 16 / 24 / 30 | 7 / 10 / 12 |

**Two-level control store** (generated, `emit_ucs`). The micro ROM holds, per micro-address, `nxt`, one index per
*nano group* and a few direct fields; each nano ROM holds the distinct value combinations of its group of fields
(index 0 = all zero, the padding / reset word). The groups (`UCS_GROUPS`) come from a search over field partitions for
the fewest M10K:

| ROM set | micro ROM | nano ROMs |
|---|---|---|
| 68000 family | 1,024 × 28 {nxt 10, lh, 2 indices} (3 M10K) | 256 × 40 (238 values), 256 × 40 (145 values) (1 + 1) |
| 68010 | 1,024 + 512 × 20 {nxt, 1 index} (2 + 1) | 512 × 99 (460 values) (5) |
| 68020 | 2,048 × 34 {nxt, 3 indices} (7) | 256 × 40, 256 × 39, 128 × 36 (1 + 1 + 1) |

**Timing is the BRAM-heavy design's.** A second ROM in series would cost a clock, so the micro ROM is read one clock
ahead: its address is the value `ua_r` is loaded with (`ua_n`) and its clock enable is the load (`ua_ce` = reset, test
load or e2), so its output is the micro-word of the *current* `ua_r`. The nano ROMs register those indices at the next
clock edge (inside the M10K, as `m68ksv_urom` registers `ua_r`), and `nxt` / the direct fields pass a register, so the
assembled `q` is the word at the previous clock's `ua_r` in every clock — what `m68ksv_urom`'s `q` is. Everything after
`uq` is unchanged. The new timing path is `ua_n` → micro-ROM address (`ua_r`'s D-input logic plus the reset / test-load
select: one yosys level above `ua_r`); the nano
outputs reach `uq`'s users exactly as the single ROM's outputs did. Before the first reset the micro ROM output is 0 (no
read has happened), so `q` is the zero word until then; the reset loads both.

Why microcode in M10K rather than an FSM: the 68000's behaviour is a sequence per instruction × mode; as ROM words
it costs block RAM (cheap, 15 M10K of 553) instead of ALMs, and cycle exactness (checkpoint 2) becomes an edit of the
micro-routines (insert idle micro-instructions, reorder) with no RTL change.

## 4. Datapath

| Element | Contents | Notes |
|---|---|---|
| Register file | entries 0–14 D0–D7 A0–A6, 15 USP, 16 SSP (020: + MSP) | three MLAB copies (`m68ksv_rf`) with a common write port, see below; A7 = entry 15 + S, so an S change needs no swap |
| Read ports | X (ALU A), B (ALU B), A (address unit and bus address — the generator checks they name one register), D (write data), N (index register from the extension word), W (old value for a byte / word merge) | copy XN serves X or N, copy A serves A, copy BW serves B or D (phases 0–1) and W (phases 2–3); the generator checks a micro-instruction never needs X with N or B with D |
| Address unit | one 32-bit adder `AUR = aa + ab` (An, PC, AT, SP, DT, PCX + ±1/2/4 by size with the A7 byte rule, d16, d8, Xn, branch displacements − 2 (narrow 9 / 17-bit subtractors), abs.L halves) | results to AT / An / SP / PCX, kept in AUR for the next bus address; An / SP written to the register file at e3 |
| ALU | one shared 32-bit adder for ADD SUB CMP ADDX SUBX NEG NEGX ADDA SUBA CMPA (controls decoded at e2); logic ops; BCD (10-bit, one correction adder each; NBCD on the SBCD subtractor; suite-verified undocumented N / V); 1-bit shifter (one step per micro-cycle = the 68000's 2 clocks per bit); bit ops; Scc; TAS; EXT; SWAP; result from a 16-way select on a code registered at e2 | X / V / C latched at e3; N / Z formed at e0 from RES (size and rule latched with the op), except BIT / TAS / CHK / DIVO / DIVZ which latch them at e3 |
| Multiplier | 16 × 16 in one DSP block with its output register (product one clock after the operands) | the microcode latches the operands one micro-instruction before the MUL word (generator check); MUL cycle count from microcode idle steps at checkpoint 2 |
| Divider | 32 / 16 restoring, one quotient bit per micro-cycle, signed via magnitudes, early (|dividend|.hi ≥ |divisor|) and late (signed range) overflow | 16 steps; exact 68000 DIVU / DIVS timing is checkpoint 2 |
| Temporaries | AT (effective address), DT (memory operand, assembled per word / byte), IM (immediate), RES (ALU result), PCX (stacked PC), AUR, FA / FINFO (fault address, access word), SRT (stacked SR), MASK (MOVEM), CNT, vector number | DT / IM written with size merge |
| Prefetch | `fpc` (address of the next prefetch), IR (current opcode, kept until the boundary — the group-0 frame stacks it), IRC (prefetched word), IRN (next opcode, set when the final prefetch starts) | formal PC = `fpc − 4`; the group-0 stacked PC is `fpc − 4` with a faulting prefetch not counted (= target − 4 after a jump), matching the suite |

**Register file in MLAB** (checkpoint 1b; checkpoint 1 had it in flops with five 16:1 × 32 read muxes, which was
the largest single item of the EU). Each copy (`m68ksv_rf`) is a 32 × 32 array with `ramstyle "MLAB, no_rw_check"`,
no HDL init, one write port and one read port whose address is registered every clock (`rd = mem[ra_q]`, the
registered-address template; two MLABs per copy). All copies share one write port, used on two phases: the
address-unit result at **e3** (straight from the adder; `(An)+`, `-(An)`, SP updates) and the ALU result at **e0**
(from RES; a byte / word write merges RES into the old value read on copy BW in phases 2–3; an AU write to the same
register in the same micro-instruction wins, as before). The write address / enable are computed one phase ahead
and registered. Reads are consumed at **e2** (operands, bus address, write data) and at **e0** (merge source),
never in the clock after a write at the address registered at that edge: writes happen at e3 / e0, the read
addresses that matter are registered at the edges from e1 to e2 − 1 and at e3 to e0 − 1. `M68KSV_SIMCHECK` (harness
builds) returns garbage from a copy in exactly the forbidden case, so a violation fails the suite (an early-read
control does fail). Cost: 6 MLABs (60 ALMs) for the three copies; a fourth copy serves the debug read port and
disappears when `dbg_rd` is unconnected. Stack pointers: USP and SSP are entries 15 and 16 and A7 reads / writes go to
15 + S (the S of the micro-instruction doing the access), so MOVE to SR, RTE and exception entry change S with no
copy; MOVE USP addresses the inactive one (entry 16 − S). The 68020 adds MSP as entry 17 with the same mapping
(M bit).

**Flag path split** (checkpoint 4b; behaviour unchanged, A/B-verified on every CPU). The flags of an ALU
micro-instruction are no longer formed in the e3 clock: at e3 the raw terms (adder C / V at the operand size and out
of bit 15, BCD carry / V, shifter out / V, bit-test Z, TAS N / Z, the EU ops' terms: CHK, MOVE.l steps, MUL.L, DIV,
bit fields, CHK2) are registered (`q_*`), together with a term index per flag (`q_xi` .. `q_ci`, decoded from the op
and the fh mode, which are stable since e2) and copies of SR / the held X V C. `ccr_q` is the selected terms - a mux
from registers, read only at the next e0 (`ccr_f` → `sr_n`), where it equals what the former e3 register held. The long
op's held X V C (`hold_xvc`) is loaded one clock after its e3 from the same terms (its readers are a later e3 or a frame
push). The adder's carries come from the sum bits (carry into bit k = r[k] ^ x[k] ^ y[k], out of bit 31 = bit 32 of a
33-bit sum) with the operand size and sign-extension controls registered at e2 (`ad_fsz_q`, `ad_ysw_q`, `ad_ysb_q`), the
X input and the Scc condition too (`alu_cin_q`, `cc_irq`). The ALU result mux puts the adder last (`rsrc_q`: adder /
PACK-UNPK / other EU result / other ALU result, registered at e2). MUL.L takes its operands from the operand registers
at e3 of its m2 MULL word; the bit-field extract / find-first-one results are registered every clock from the stage-1
registers (BF follows BFP by one micro-instruction or more); the BFINS N / Z masks come from the stage-1 top mask.
A term enters the term vectors (`ft_n` .. `ft_c`) only on the CPUs whose index decode can select it (68010: CHK N;
68020: MUL.L / bit-field / CHK2 terms and the WinUAE undefined-flag terms of section 7.4), and the EU / PACK-UNPK result sources only on the 68020, so that logic folds
away elsewhere (fold-away fix, REPORT.md).

**Register write and operand-mux structure** (fifth session, area / timing pass; behaviour unchanged). The ALU A and B
operands first resolve the micro-instruction's source (field xa / xb, the decoded class's source, the EA mode, the
MOVEC code) to a 4-bit data-source code, then one flat 32-bit mux selects it (`xq` / `xbq` in `m68ksv_eu`). The
heavily shared temporaries (IRC, IRN, IR, FPC, AT, FA, DT and IM per byte, the 68010 resume address) are written in one
place each: a write enable that is the OR of their causes and a data mux that keeps the causes' old priority. The data
selects use only early phase information (e2, `b_dv` = e3; the phases exclude each other) and micro-word fields; `e0`,
which waits for the micro-ROM's bus request, only gates the enables. Bus write data: the source (including the 68010
format-8 frame words of field fx) is decoded at e1 into `dws` / `dwx` / `dwh`, and the byte duplication of a byte
write is applied after the data register (`b_dout = {dup ? r[7:0] : r[15:8], r[7:0]}`). The 68010 frame's AUR copy
is taken from AUR one clock after the faulting word's e3 (the generator checks that the AUR-restoring RTE word never
ends a bus cycle). Read data and the 68010 software-completed RTE (SWDONE: DIB into DT) share one DT input path.

## 5. Exceptions

- **BERR holds the sequencer** (fx68k `wClk`): while BERR, sampled on a falling and then a rising edge, is
  asserted, the next micro-instruction does not start (e0 is withheld, in or out of a bus cycle). This replaces the
  fixed idle micro-cycle a bus error / spurious interrupt used to get. An address error enters `EXC0A` (`EXC0` + one
  idle word); a bus error enters `EXC0`, its sequencer already held while BERR was asserted.
- **Group-0 state** (double fault) is set from the group-0 entry until the second word of the refill after the vector
  fetch (`VECJMP_G0`, where fx68k clears its latch): a fault on the first refill prefetch halts, on the final one it
  is a bus / address error.
- **Group 0**: the address check runs at e1 of the first micro-cycle of a word / long access with an odd address
  (68000 / 010 / 008 rules; 68020: odd instruction fetches only); the cycle still runs with AS (and R/W low for a
  write) for its normal length but no data strobes (fx68k), as a 6800 cycle if VPA meets it. A bus error is seen in
  the cycle's second micro-cycle (`berr_now`: BERR without VPA; BERR on IACK is the spurious interrupt instead) and
  enters `EXC0` one micro-instruction later than an address error. Captured: access address, access word =
  IR[15:5] | R/W | I/N | FC, IR, stacked PC, vector 3 / 2. `EXC0` pushes PC lo, SR, PC hi, IR, address lo, access
  word, address hi, reads the vector, refills the queue. A second fault during group-0 processing halts: `HALT_n`
  four clocks after the aborted cycle.
- **Stacked PC = the 68000's PC register (`pc68`)** (checkpoint 2, third session). The 68000 stacks its internal PC
  register, which its microcode loads at particular micro-words (fx68k: AU -> PC at T1, bus -> PC at T3). m68ksv keeps
  that register: field `pu` names, per micro-word, a load at the e0 that starts the word (= fx68k T1; from fpc, PCX
  or AUR) or at its e2 (= T3; from fpc, fpc - 2, fpc + 2, PCX, AT or the vector address). The load points were
  located by aligning fx68k's PC-register transfers with m68ksv's micro-words in lockstep (`PCTRACE`,
  `verify/tools/pcderive.py`: every load lands on one word and equals one m68ksv value there) and are checked by
  comparing `pc68` with fx68k's PC register at every point a bus error can be taken (`PC68CHK`). A bus error stacks
  `pc68` as it stands after the faulting cycle's e2; an address error the same (after the faulting word), except
  after a bus wait (field `pl`, derived: the next word loads the PC at its T1, which fx68k runs during the wait):
  fpc. This replaced the earlier per-word offset tables (`pk` for address errors, the fitted `pb` for bus errors) and
  is history-dependent (the same word stacks different offsets after different predecessors), which no per-word
  table can be. Not modelled: bser6's PC <- fault address, which no frame can stack.
- **Register and CCR writes sit in the 68000's words.** A bus error ends the faulting cycle's second micro-word and
  starts `EXC0`; the 68000 likewise completes that word (T3) and never runs the next. So every register / CCR write
  is placed in the same micro-word as the 68000's (lockstep `WRTRACE` timelines; `ABORTCHK` compares registers and
  CCR with fx68k at every bus-error point - 0 differences in normal runs). Mechanisms: An / SP updates moved to the
  68000's word (with field `lk` = 2 where the 68000 writes An at the faulting word's own T3, so an address error keeps
  it; `lk` = 1: kept after a bus wait); field `lh` writes only the low word of a long result (or of any An result) and
  a later `PASS RES` word completes it, `lh` = 2 only the high word (MOVEM.l / MOVEP.l to registers, LEA abs.L); field
  `fh` splits a long op's flags as the 68000's 16-bit ALU does - `LO` writes the low word's flags (X V C out of bit 15)
  and holds the long X V C, `CM` writes the held flags later, `HD` holds them from a second op whose carry-in X is the
  one from before the `LO` word (ADDX / SUBX .l -(An)); routines whose 68000 timing differs per instruction were split
  (bit ops, CMP vs ADD / SUB, NBCD, BTST, MOVE from a register vs from memory, RTS's tail, DBcc's tail). MUL clears
  Dn's low word with the Z flag one word after its prefetch, as the 68000 does (the operand is kept in AT). Stacked IR
  / access-word IR bits / I/N: the next instruction's when the faulting cycle's second micro-word ends the instruction
  (FIN), else the current one's; I/N of a MOVE.W -(An) write fault (field `ai`) = whether the next instruction traps
  (fx68k `inExcept01`); `bn` marks the group-0 and interrupt pushes (not the group 1 / 2 frames: fx68k I/N = 0).
- **Reset mid-instruction**: the 68000 has made the writes of the micro-word whose T3 (= e2) has passed when RESET
  takes hold; the top lets the execution unit run the rest of that word (e3 and / or e0) before its reset (the BIU
  resets at once).
- **Group 1 / 2**: TRAP, TRAPV, CHK, zero divide, illegal, line A / F, privilege, trace, interrupt. Each entry sets
  PCX (instruction address, next instruction before / after the final prefetch) and the vector, then `EXC12`
  pushes PC lo, SR, PC hi; interrupts insert the IACK cycle between PC lo and SR (autovector on VPA, spurious on
  BERR, otherwise the vector number on D7–D0) and raise the mask.
- **Interrupts**: the level-7 pending flag is cleared while FC = 7 with level 7 in the level latch (fx68k), and that
  latch (`int_inl`, used only by the pending logic) is also loaded after the IACK's IRC -> IR (fx68k itlx6); the
  acknowledged level (IACK address, autovector, new mask) stays in `int_lvl`. A spurious IACK (BERR) takes the data
  bus one clock later than a DTACK cycle (fx68k) for IRC.
- **Interrupts** (fx68k timing): IPL sampled on two falling edges; pending = stable and above the mask, or a level-7
  edge. The decision is latched on e2 of the micro-instruction with field `iq` (the 68000's last IRC → IR micro-word:
  the first micro-word of the final prefetch, set automatically on NPF words; moved to another access for MOVE to
  (An)+, MOVE.L to (An) / (d16,An) / (d8,An,Xn) from a register, ADDX / SUBX / ABCD / SBCD / CMPM memory forms,
  LINK, UNLK, MOVEP to a register, MOVEM (An)+ to registers, RESET — from MAME's m68000-sdf.cpp word structure); the
  level is latched on the e0 that starts that word (if that word waits for the bus: on the first held e0 slot, the
  decision one slot later, as fx68k's T1 / T3 run during the wait). Sequence: n6, PC lo, (n2), IACK (word cycle, both strobes; the
  whole data word goes to IRC, then IR), n4 (+ one micro-cycle if spurious), SR, PC hi, vector, refill.
- **Trace** if T was set when the instruction started; a group-0 / group-1 / interrupt exception cancels the pending
  trace, TRAP / TRAPV / CHK / zero divide keep it. STOP waits in a micro-loop.
- **Reset**: S = 1, T = 0, I = 7, the CCR is kept; SSP from vector 0, PC from vector 1, refill. The first bus cycle
  starts 22 phases after `RESET_n` rises (four idle micro-instructions, phase counter restarts at e2), as fx68k.
  The RESET instruction drives `RESET_n_o` for 124 clocks from its third clock; the output changes on the e0 slot
  even when the next micro-instruction waits for the bus.

## 6. The 68000 bus (m68ksv_biu)

S0 at e0 of the first micro-cycle; address / FC / AS (and read strobes) at e2 (S2; the EU's address is
combinational and valid at e2, the BIU latches it and A0); write data at e3 (S3), write
strobes at e0 of the second micro-cycle (S4); DTACK sampled at the end of S4 (freeze until seen); read data taken at
the end of S6 (e3); strobes released at S7. TAS is one indivisible 5-micro-cycle cycle (read, internal, write with
AS held). IACK: FC = 7, A3–A1 = level, VPA → autovector, BERR → spurious. Checkpoint 2 (pins checked against fx68k
phase by phase): FC at S0, A from S1, AS / read strobes / R/W at S2, data at S3, write strobes at S4, AS / strobes
off at S7, R/W high at the next S0. BERR terminates when it was low on the falling edge before the one that would
see DTACK (fx68k: `rBerr`, then `iStop`), and only without VPA (sampled on the rising edge). E = clock / 10 (high on counts 6–9, power-up phase as fx68k); VMA on the falling
edge with count 3 when VPA is seen; the 6800 cycle ends on count 8. Arbitration (BR / BG / BGACK, HALT) holds e0
back (`bus_free`); a cycle ends, and FC / RESET output change, on the e0 slot even while e0 waits.

**Bus retry** (MC68000 User's Manual 5.4.2): BERR with HALT (sampled on the rising edge) at the termination point
ends the cycle normally (S5-S7), then the BIU waits while HALT is asserted (and while the bus is requested / granted
away) and runs the same cycle again from S0 - same address, FC, R/W, strobes, write data - while the execution unit
stays held at the cycle's second micro-word; the re-run's termination is decided again (DTACK, another retry, or a
bus error). TAS is never retried (bus error, as the manual says). No lockstep oracle (fx68k `BusRetry = 0`):
`verify/tb/retry.cpp` checks the manual's sequence.

**8-bit bus** (68008, 68EC000 MODE = 0): a byte access is one cycle (A0 = address bit 0, data on D7-D0, one data
strobe `DS_n`); a word access is two byte cycles back to back (A0 = 0, then 1). The first cycle's termination does
not release the execution unit: the BIU runs S5-S7 of the first byte and S0-S4 of the second on the raw phase
enables (`k8` = 1..8, the same sequence the retry uses) while e1 of the cycle's second micro-word stays frozen; the
second byte's termination releases it, so each word costs exactly 4 more clocks (MAME m68008's rule). IACK is a single
byte cycle at A0 = 1 (IRC = 00xx), TAS a byte RMW cycle as on the 68000. No bus grant between the two byte cycles of
a word (the word is one access for the sequencer; no oracle models arbitration there). An odd word access keeps the
68000 rule (one AS-only cycle, no strobe, no write) - MAME's m68008 instead runs both byte accesses (a write is done)
and then takes the address error; m68ksv does not copy that (REPORT.md).

## 7. Family plan (where each member's deltas live)

| Member | BIU | Execution unit / microcode | ROM contents |
|---|---|---|---|
| 68000 | `m68ksv_biu` (16-bit) | as above | `--cpu 68000` |
| 68008 / 68008FN | `m68ksv_biu` with bus8 = 1 (implemented, checkpoint 2b): every word cycle becomes two byte cycles (`DS_n`, A0), 20 / 22 address pins; DIP48: `IPL_n[2]` is the combined IPL2 / IPL0 pin, no BGACK | unchanged (the BIU stretches the bus micro-cycles; the phase freeze keeps the EU in step) | same as 68000 |
| 68EC000 | `m68ksv_biu`, bus8 = the `MODE` latch (sampled while reset is asserted; 0 = 8-bit with UDS_n = A0, LDS_n = DS_n) - the only run-time choice | unchanged | same as 68000 |
| 68010 | `m68ksv_biu` + `ghost` / `ghost_s2` inputs (loop mode: an opcode prefetch with no bus cycle) | implemented at checkpoint 3, see 7.1 | 68010 ROMs (`_010` modules), same generator |
| 68020 / 68EC020 | `m68ksv_biu32` (checkpoint 4, bus timing 4b): 32-bit data, `SIZ`, dynamic sizing (`DSACK_n` 8 / 16 / 32-bit ports, `STERM_n` ignored since checkpoint 5: the 68020 has no STERM), 3-clock asynchronous / 2-clock synchronous cycles, long operand reads as one request, misaligned operands split into cycles, `RMC_n` (TAS, CAS / CAS2), `ECS_n` / `OCS_n` / `DBEN_n`, `IPEND_n`, `AVEC_n`; the instruction cache (64 long words, `CDIS_n`); EC020 drives A23–A0 | implemented at checkpoint 4 / 4b, see 7.2 (CALLM / RTM not; coprocessor protocol: cpGEN only) | 68020 ROMs (`_020` modules), same generator |

The microcode generator keeps one source: member-specific routines and decode entries are selected by `--cpu`, so
the 68000 ROMs never pay for 020 routines (and the 020 microcode word is allowed to be wider).

### 7.1 The 68010 (checkpoint 3)

- **ROMs.** `m68ksv_ucode.py` runs itself twice (`GEN_CPU` 68000 / 68010). The 68010 microcode = the 68000 microcode
  patched in place (same word count, so every 68000 label keeps its address; `m68ksv_ucode010.py`) + routines appended
  after `N68K`. The 68010 decode first creates every 68000 class in 68000 order (CLS_* numbers the RTL names stay
  equal), then 68010 classes under new names. The driver asserts the shared labels / classes are equal. The 68000
  ROM modules are byte-identical to checkpoint 2.
- **68010-only microword fields** above the 68000's 93 bits (`sf`, `xe`, `fx`, `ly`, `rr`, `x1`; 110 bits): in the
  68000 family they are constant 0 and every use in the RTL is gated by `IS010`, so the logic folds away.
- **Control registers.** VBR (vector address = VBR + 4 x vector), SFC / DFC (field `sf` overrides the function code of a
  MOVES access), MOVEC through `cx` (the extension word) with `xa CTL` / `xe CTLW`; an invalid control-register code is
  tested in MOVEC's first word (`CRVALID`) and goes to the illegal-instruction exception.
- **Frames.** Group 1 / 2: format 0, four words (`EXC12_010`, `EXC_INT_010`). Group 0: format 8, 29 words
  (`EXC0_010`): SR, PC, format / vector, SSW (RR / IF / DF / RM / HB / BY / RW / FC), fault address, data output buffer,
  data input buffer, instruction input buffer (IRC), and 16 internal words: version 0 / resume state (`fin`, stage,
  layout of slots A / B per bus word - field `ly`, saved destination half, trace, loop-mode state, held flags), resume
  micro-address, IR, internal PC, slot A (IM or {SRT, vector}), slot B (RES or {mask, count}), the AU result, IRN, DT,
  AT. The stacked PC is the 68000's `fpc - 4` (data sheet: "may be advanced by up to five words").
- **RTE.** Reads SR, PC and the format word; format 0 returns, format 8 first reads the version word (SP + 26; wrong
  version: format error, SP unchanged) and the frame's last word, then loads the frame straight from the read data
  (field `fx` L*), re-runs the faulted cycle with the saved function code / size / destination (`rr`) unless SSW.RR is
  set (software completed it: DIB / IIB used) and resumes at the saved micro-address (`sq RSM`) or dispatches. Any
  other format: format error. A bus error during the frame reads after the validity checks is a double fault.
- **Loop mode** (data sheet 7.1.3). DBcc's first word records "displacement = -4"; at DB_T2 (branch taken) the target
  opcode (IRN) is checked against table 7-3 (`loopable()`), T clear -> `lm`, with `lbase` / `lw0` / `lw1` and the
  looped instruction's decode (`lq_*`, so its dispatch needs no new decode). In loop mode an NPE / NPF to one of the
  three loop words is a **ghost cycle**: the BIU runs no bus cycle (no AS, no wait) and the EU takes the word from
  `lw0` / `lw1` / -4. The looped instruction's FIN dispatches straight to `DBL<n>` (no interrupt there; `n` idle words =
  table time - instruction time); the loop word (`x1 LMC`, sequencer `FINC` on `LMX` = cc true or counter low word 0)
  writes Dn - 1 and dispatches the looped instruction again from `lq_first` (interrupts are taken here), or goes to
  `DBL_X` (loop mode off, the normal DBcc exits). Loop mode ends on any real opcode fetch, any exception dispatch, a
  bus / address error, reset. A bus / address error stores {after the displacement fetch, loop mode} in the frame; RTE
  restores loop mode (the loop words are not fetched again) and runs one normal DBcc (internal fetches) to re-establish
  the counter test. A looped instruction that writes the DBcc counter keeps the normal DBcc micro-routine (ghost
  fetches only).
  The window test (fifth session) is decided at **e2** from the bus address registered at e1: `lwd = ba_q[23:0] -
  lbase`, in the window when `lwd` is 0, 2 or 4 (one 24-bit subtractor; `lwd[2:1]` picks lw0 / lw1 / -4 for
  `ghost_d`). The BIU gets the decision twice: `ghost_s2` (combinational, valid at e2, used only for the S2 strobes)
  and `ghost` (registered at that e2, used for the rest of the cycle). The loop-mode updates of the cycle (lm_db on the
  displacement word, loop mode off on a real opcode fetch) are taken at the same e2 (written last in the EU's register
  block; an address error in that e2 captures the updated state into the frame). Before, the test ran on the e1 bus
  address mux (`ba_e1`) and was the 68010's worst path. `loopable(IRN)` is registered together with IRN (`lp_irn`).
- **Timing.** Where the MC68010 tables differ from the 68000 the 68010 microcode is patched (REPORT "Checkpoint 3",
  timing table): Bcc not taken, DBcc, Scc Dn, MOVE USP, RESET, xxxI to CCR / SR, long register ops (6), xxxI.l #,Dn,
  CMPI.l, ADDQ.w #,An, MOVE.l Dn,-(An), CLR / Scc / MOVE from SR / CCR without the read, BCLR on memory, CHK, BKPT,
  four-word frames.

### 7.2 The 68020 / 68EC020 (checkpoint 4)

- **ROMs.** Third generator pass (`GEN_CPU` 68020): the 68000 microcode + the 68010 patches (`m68ksv_ucode010.py`,
  without loop mode and without the format-8 push) + `m68ksv_ucode020.py` (patches and appended routines). The 68000
  and 68010 ROM modules are byte-identical prefixes of the generated files. 68020-only microword fields above the
  68010's 110 bits (126 bits): `c2` (6-bit 020 branch conditions), `xw` (index scaling on), `m2` (020 register loads:
  extension word, indirect pointer, MUL.L / DIV.L / bit-field set-up, CAS2 operand swap, RTE frame length, M clear,
  change-of-flow marker), `d2` (020 frame words); every use in the RTL is gated by `IS020`. The decode ROM `drom1`
  is 36 bits wide for the 020 (4-bit validity code: `CALT` = control alterable), `drom2` 34 (bit 33: change of flow,
  T0 trace). Flags in the RTL: `IS020` (68020 / 68021), `IS010` (68010 or 020: the 68010 machinery), `ISLM` (loop
  mode: 68010 only).
- **Bus timing (checkpoint 4b, checked against the MC68020 User's Manual in checkpoint 5).** One micro-cycle per CPU
  clock (section 2). `m68ksv_biu32` runs each access as one or more physical cycles on the 68020's S-states: S0 = the
  rising edge of the first micro-word's e0 (address, SIZ, FC, R/W from e1, the EU's address register; ECS / OCS from e1
  to the falling edge: a quarter clock after the manual's S0), S1 = its e2 (AS; a read's DS; a write's DBEN), S2 = the
  next rising edge (a read's DBEN; the write data), S3 = the next falling edge (a write's DS) — UM 5.1.3-5.1.6
  p. 5-3/5-4, 5.3.1 / 5.3.2 p. 5-31 / 5-38. Every cycle is asynchronous: the 68020 has no STERM (UM Table 3-2, p. 3-8;
  the `STERM_n` port stays for the pin list and is ignored). DSACK1 / DSACK0, AVEC and BERR are sampled on falling
  edges from the end of S2 (data latched one clock later, on the falling edge that starts S5: three clocks, UM 5.2.6
  p. 5-24); BERR takes precedence over DSACK / AVEC (UM 5.5.1, Table 5-8 case 3); BERR at the latching edge one clock
  after DSACK is a late bus error (case 4: the access ends with a bus error, on a sized access's last cycle at once,
  otherwise after one internal clock with no further cycle); wait states are whole clocks. The EU's second micro-word
  starts (e1) one clk after the rising edge before the latching falling edge, so its e2 / e3 take the data (`rb`,
  latched at that edge; a late bus error reaches it combinationally through `berr_cyc` at that edge). A sized
  access's next physical cycle starts on the next rising edge (back to back); a cache hit, the second half of a long
  read and an address-error cycle are internal (two clocks, no AS). BERR + HALT re-runs the physical cycle (not in a
  locked sequence). 68EC020 (`CPU` 68021): ECS, OCS, DBEN and IPEND stay negated and BGACK is ignored (those pins do
  not exist on it, UM Table 3-2; two-wire arbitration, 5.7.2 p. 5-70).
- **Long operands.** A read whose destination is the high word of a long operand (`bq_lw`: bus RD with bd HI) runs one
  long access (SIZ = 4, sized and split by the port); the low word is held (`lr_v`, `la`) and the following read at
  that address + 2 takes it with no bus cycle. With the cache off an instruction fetch at a long-aligned address is a
  long access the same way (the next fetch takes the held word). Long writes remain two word requests: the EU forms
  the two halves in different micro-words (for example MOVE.L: the high word from the source operand, the low word
  from the ALU result one word later), and a deferred long write could not be re-run from m68ksv's format-B frame.
  The EU and its microcode are unchanged by this (the second half's micro-words still run, as an internal cycle).
- **Locked sequences.** TAS: read, internal word, write, with RMC from the read's S0 to the end of the write, AS negated
  between them (68020 style) and no bus grant. CAS / CAS2: the microcode tags the first operand read (m2 RMCON) and
  the final prefetch (m2 RMCOFF); the EU's lock (`rmc_lk`) holds RMC and blocks the grant from that read to the end of
  the last write (or of the last read when the compare fails); a pending BR does not hold the locked cycles back.
- **Full extension words.** Every (d8,An,Xn) / (d8,PC,Xn) entry of the 68000 microcode gets a detour (`full_detour`)
  at its displacement word: bit 8 of the extension word (`c2 FULLX`) selects the brief form with scale (`xw`: index
  << scale) or the subroutine `FEA_AY` / `FEA_PC` (base / index suppress, null / word / long base displacement,
  memory indirect pre / post-indexed with null / word / long outer displacement; the indirect pointer goes to its own
  register `xt` so the caller's DT is untouched).
- **New instructions.** Bcc.L / BSR.L (displacement byte $FF), CHK.L, EXTB, LINK.L, TST An / #imm / PC-relative,
  CMPI PC-relative, TRAPcc (5xFA-5xFC), MUL.L (`mul_la` x `mul_lb` in DSP, 64-bit registered product; the multiplier
  exists only in the 68020 builds, generate block `g_mull`, elsewhere `mul_lp` = 0), DIV.L (one
  quotient bit per micro-cycle, `dl_*`; overflow / zero divide tested first), PACK / UNPK, bit fields (offset / width
  from the extension word or Dn; a 64-bit funnel `bf_d64` of the one or five bytes read, registered in stage 1 before
  the insert / extract / find-first-one stage; the shift amounts `bf_o5r` / `bf_ur` / `bf_ir5` / `bf_xs5` are
  registered every clock from offset / width after BFINIT, so stage 1 is one funnel / rotate plus masks decoded from
  them, REPORT.md "Bit-field path margin"), CHK2 / CMP2 (bounds in XT / DT, compare registered before the flag
  word), CAS / CAS2 (`cx` / `cx2` hold the two extension words, swapped by `m2 SWCX`), MOVEC CACR / CAAR / MSP / ISP.
- **Stacks and frames.** Register-file entry 17 = MSP; SSP accesses go to entry 17 when M is set. SR mask $F71F (T0,
  M). Trap-class exceptions (CHK, CHK2, TRAPV, TRAPcc, zero divide, trace) push format 2 (`EXC12_F2`, the instruction
  address in the frame); interrupts with M set push format 0 on the MSP, clear M and push a format-1 throwaway frame on
  the ISP (`EXC_INT20_T`). Bus / address error: format B, 46 words (`EXC0_020`), in m68ksv's own internal layout
  (the 68010 format-8 machinery in the B slots; the architected SR / PC / format / SSW in the 68020 layout / fault
  address / DOB / DIB where the PRM puts them). RTE (`RTE20`): formats 0 / 2 / 9 / A pop and return, 1 loops through
  the throwaway frame, B checks the version word then re-runs / resumes as the 68010, anything else: format error.
  T0 trace: decode class bit (unconditional change of flow: JMP, JSR, BSR, RTS, RTR, RTD, RTE, MOVE to SR, ...) or
  `m2 FLOW` on the taken paths of Bcc / DBcc (the set Musashi's 68020 handlers trace).
- **Instruction cache** (in `m68ksv_biu32`). 64 lines of one long word, direct mapped by A7-A2, tag = A31-A8 and FC2,
  a valid bit per line (registers: cleared in one clock by CACR C or reset), tag + data in a 64 x 57 array
  (`ramstyle MLAB`, asynchronous read by the EU's registered bus address). With CACR E set and CDIS high every
  instruction fetch is a long access at the aligned address (`lfa_q`, registered when the cycle starts): a hit runs as
  an internal cycle (ECS / OCS, no AS / DS, the line registered at the lookup, zero-wait 32-bit timing), a miss as a
  long bus read (dynamic sizing) that fills the line unless CACR F is set or the read ended in a bus error / address
  error. CE clears the line CAAR[7:2] selects. Data writes never update the cache.
- **Coprocessor interface (checkpoint 4b).** CPU-space cycles (FC 7, A19-16 = 2, Cp-ID on A15-13, the interface
  register on A4-0; `BA_CPS`): cpGEN writes the command word (its first extension word) to the command register ($0A),
  cpScc / cpDBcc / cpTRAPcc and cpBcc the condition (extension word / opcode bits 5-0) to the condition register ($0E),
  cpRESTORE a format word (0: the EA is not read) to the restore register ($06); cpSAVE reads the save register ($04)
  first (cpSAVE / cpRESTORE privileged before that). A bus error on a coprocessor cycle is the F-line exception (the EU
  routes `berr_now` with `bo_cps` to `EXC_LF`; format 0, PC = the instruction): what a system without a coprocessor
  sees. cpGEN then reads the response register ($00): null (bits 13-9 = 00100, UM 7.4.4 p. 7-31; CA clear) ends the
  instruction, null with CA (IA ignored: the response is read again at once, no interrupt window) or busy (bits 12-8 =
  00100, UM 7.4.3 p. 7-30) reads it again; (checkpoint 5: the null decode was bits 12-8 = 01000, which rejected IA = 1); any other primitive, and an answering coprocessor on the other types, is a
  coprocessor protocol violation (vector 13, `EXC_CPV`): the data-transfer / EA primitives and the conditional types'
  completion are not implemented. CALLM / RTM: illegal instruction (68020 and 68EC020).
- **Format B (checkpoint 4b fixes).** RTE keeps the SR it reads for the format-B tail (`fx LSR` on the first read: the
  tail restores SR from it); the pushed SSW has DF set for a data-cycle fault (FB / RB for an instruction fetch), so RTE
  re-runs a faulted data cycle unless the handler cleared DF. An address error's SSW (2026-11-16, section 7.4) has RB
  and RC set, FB / FC / DF clear (MC68020 UM 6.2.1 p. 6-22), so an RTE of an unrepaired address-error frame re-runs the
  fetch. #unverified (WinUAE writes no RB / RC).
- **Interrupts (68020).** The pending flag also needs the sampled level above the mask (or 7) at the decision: with one
  micro-cycle per clock the level latch (e0) and the decision (e2) see the same sample.
- **RESET instruction (68020):** RESET is asserted for 512 clocks (microcode loop, `RESETI20_L`).

### 7.4 68020 undefined behaviour from WinUAE (2026-11-16)

The 68020 / 68EC020 builds follow WinUAE's 68020 core (Amiberry fork, `src/`) where the PRM leaves a result undefined
or m68ksv and Musashi disagreed - the user's decision, after an Amiberry run of `verify/amiga020` (REPORT.md "68020
behaviour from WinUAE"). WinUAE's code, not its comments, is the reference. Only the 68020 logic changed (`IS020`
terms; the 68000 / 68010 ROM contents are byte-identical).

- **DIVU.W / DIVS.W overflow** (`newcpu_common.cpp` `setdivuflags` / `setdivsflags`): DIVU: V = 1, N set if the dividend
  is negative, X / Z / C / other N unchanged; DIVS: C = 0, V = 1, N / Z = bit 7 / zero of the quotient magnitude's low
  byte, both 0 when the overflow is found at the start (|dividend|.hi >= |divisor|, `dv_ov`). EU terms N 11 / 12, Z 12,
  C index 1 (SR) for DIVU (`fd_*`, `nzsel`).
- **DIV.L overflow** (`divul_overflow` / `divsl_overflow`): V = 1, C = 0; N / Z of Dq (N = Dq < 0, Z = Dq = 0), except
  DIVS.L with a 64-bit dividend: Dr = 0: Z = 1, N = 0; Dr < 0, divisor < 0, Dr > divisor: N = Z = 0; else Dq = 0: Z = 1,
  N = 0; else N = Dq[31] ^ Dr[31]. Registered at m2 DVLHI (`dlo_n` / `dlo_z`: `dl_q` = Dq, `xb_q` = Dr, `dl_d` / `dl_sq`
  = |divisor| / its sign; Dr > divisor via Dr + |divisor| > 0). Two steps (2026-11-16, timing): DVLHI registers the
  parts (`dlo_*1`: Dq = 0 / < 0, Dr = 0 / < 0, 64-bit DIVS.L, divisor and Dr negative, the sign and six partial ORs of
  Dr + |divisor|), the next clock N / Z; the overflow flag word comes three or more clocks later. SAT-proved equal to
  the one-clock form.
- **CHK.W / CHK.L** (`setchkundefinedflags`, 020 / 030): N = Dn < 0, Z = Dn = 0; when it traps V = overflow of
  bound - Dn and C = (Dn < 0) ? (Dn > bound or bound >= 0) : (bound >= 0), else V = C = 0. Terms V 11 / C 10
  (`chk_v20` / `chk_c20`, registered at e3 as `q_chkv` / `q_chkc`).
- **CHK2 / CMP2** (`gencpu.cpp` `i_CHK2`, `setchk2undefinedflags`): bounds sign-extended to 32 bits, the value Dn's
  sign-extended low part or all of An, signed compares; Z = equal to a bound; C (unless Z) = out of bounds, with a
  wrapping range when lower > upper (was Musashi's "signed only when the lower bound's sign bit is set"); N / V by the
  six-case rule (`c2nv`); terms N 14, V 12. Two steps (2026-11-16, timing): the compare word's e3 registers the two
  33-bit subtractions value - lower / value - upper as sign, bit 31 and six partial ORs of bits 30:0, plus the three
  operand signs (`c2_*1`); lower > upper (`c2_lgu1`) is registered every clock from the raw XT / DT (one subtraction
  with zero columns after bits 7 and 15 as borrow taps; c_sz, XT, DT are stable from the bound reads to the end of the
  instruction); the clock after the compare word registers Z / C / N / V (`c2_cq` .. `c2_vq`), which the flag word
  reads four or more clocks later. The size muxes use `c_sz` (= `xsz_q` in both CHK2 ALU words). SAT-proved equal to
  the one-clock compare.
- **PACK / UNPK** (`i_PACK` / `i_UNPK`): the two-byte side (PACK -(Ay), UNPK -(Ax)) moves An by 2 in total, A7 too (one
  word at An - 2 in WinUAE); the one-byte side keeps the A7 rule (2). m68ksv keeps its two byte accesses (An - 1, then
  An - 2) addressed through AT (`PACK20M` one micro-word longer).
- **LINK A7 / LINK.L A7** (`i_LINK`): the A7 value before the decrement is pushed (the 68010 module's `AYLK` patch is
  undone for the 68020; the 68000 microcode's behaviour).
- **Address-error frame** (`newcpu.cpp` `Exception_normal`, "68020/030 odd PC address error"): **SSW = RB | RC | RW |
  SIZE word | FC ($3066 in supervisor mode; FB / FC / DF clear; `DWX_SSW20` with `g0ae`) - RB / RC from the MC68020
  User's Manual 6.2.1 p. 6-22 (the user's decision, 2026-11-16), not WinUAE ($0066, its frame "partially implemented
  only"). #unverified: manual versus WinUAE, no real 68020 to settle it; if evidence shows it is wrong, fix it.** The
  manual allows RB + RC or only RC; m68ksv sets both (a change of flow to an odd address leaves the whole pipe to
  refill); the low half (data cycles only, per the manual) keeps WinUAE's RW / SIZE / FC. The data input buffer (+$2C) = the
  fault address (`FX_DIB` / new `FX_DIBH`); a JMP's stacked PC = the JMP's address + 2 (`ae_jmp` captured with the
  fault, `m2 AEPC` on the +$06 push word: PCX = `ppc` + 2). Other instructions keep m68ksv's stacked PC (REPORT.md
  survey). The internal words (+$08, the version word, the slots) stay m68ksv's own, so the format-B re-run works as before.
- **Timing (2026-11-16, no behaviour change):** besides the two-step CHK2 and DIV.L flags above, the MUL / DIV.W idle
  counts (`cnt_mul_r` / `cnt_div_r`, ms LDCNTMUL / LDCNTDIV) are registered every clock on the 68020 builds, so the two
  popcounts are not in front of `cnt` (xa_q / ir and the divider registers are stable two or more clocks before the
  e0 that loads `cnt`).

### 7.3 Area changes of checkpoint 5 (behaviour unchanged, proved clock-exact by the A/B tool)

- **Unused micro-word codes gated per ROM set.** Quartus cannot fold logic through M10K contents, so a decode of a
  micro-word code that no word of a CPU's ROM set contains still costs logic. The generator emits, per ROM set (000 /
  010 / 020), one mask per field (`UM<set>_<FIELD>` in `m68ksv_upkg.sv`: sq, cd, dw, ad, xa, xb, xd, ms, fx, and the
  drom2 class field `ca`), bit k set when code k occurs in any word of that set — reachable or not (a format-8 / B RTE
  can resume at any micro-address taken from memory, so every ROM word can execute). The EU gates each such decode
  with `UM_<FIELD>[code]`; the masks are constants, so a code absent from the set folds the decode away. Bit 0 is
  always set (padding / reset).
- **Static ROM invariants checked by the generator** (`check()`), which the RTL now relies on: no FIN / RSM word names
  a bus cycle; every bus word (every set, dead words too) has sq NXT / BT / BF and a non-bus successor; an fx LI0 read
  is never followed by an fh CM word; no x1 SRF word follows a bus word; the 68000 EXC0 entry is straight-line from
  EXC0A to the FINFO push (LDAEPC first). A SIMCHECK `$stop` in the EU catches a bus cycle starting in a second
  micro-word.
- **Flags.** N and Z are one registered bit each (`q_nf`, `q_zf`): the term index is decoded at e2 (`nzsel`), the
  term chosen at e3 (the bit-test Z term enters last); `ccr_q` reads them at e0 (the 4b split kept). `f_bitz` is a
  single-bit mux.
- **68000 address-error frame state.** `aepc` / the IR copy became `aepc_f` (1 bit: the frame PC is the fault PC) and
  `aeir_n` (1 bit: the frame IR is IRN) on the 68000 family; the 68010 / 020 keep their registers.
- **68010 loop table.** The loopable-opcode function moved from logic into a 1024 x 9 M10K table (`m68ksv_drom1lp_010`,
  two read ports: IRN and IR), generated from the same Python function (exhaustively equal over all 65,536 opcodes).
- **Smaller items:** the format-8 fault-address mux `s_fa` removed (the second micro-word never starts a bus cycle),
  the bit-field extract merged into the shared result mux, the frame-PC adder shared with the prefetch PC adder.

## 8. Verification hooks

- `M68KSV_TESTLOAD` (harness only, never in synthesis): a test-load port sets D0–D7 / A0–A6 / USP / SSP / SR / PC /
  prefetch queue and starts at a one-micro-instruction dispatch (`TLFIN`), so single-step tests start in the exact
  architectural state.
- Debug outputs (kept in every configuration, unconnected outputs optimise away): instruction-boundary strobe,
  micro-PC, PC, SR, IR / IRC, and a register read port `dbg_ra` / `dbg_rd` (D0–D7, A0–A6, USP, SSP; one clock of
  latency; its own register-file copy) in place of checkpoint 1's parallel `dbg_r` / `dbg_usp` / `dbg_ssp` (020: +
  MSP / ISP, VBR, SFC / DFC, CACR / CAAR). The test-load port writes the register file one entry per clock while
  `tl_en` is held (the harness holds it 20 clocks).
- `M68KSV_SIMCHECK` (harness builds only): register-file collision garbage and the decode-distance stop (above).
- Checkpoint 2: fx68k lockstep (same stimulus, every pin every phase); checkpoint 3: MAME's Musashi (m68010) built
  unmodified as a C++ model in the harness (`verify/musashi/`, `verify/tb/mus010.cpp`), the bus-error continuation
  self-check (`verify/tb/rerun010.cpp`) and the loop-mode test (`verify/tb/loop010.cpp`); checkpoint 4: Musashi m68020 /
  m68ec020 (`verify/musashi/musashi_model020.*`, `verify/tb/mus020.cpp`), the directed dynamic-sizing and cache tests
  (`verify/tb/dsz020.cpp`, `verify/tb/cache020.cpp`), and the 68000 suite on the 68020 build (`harte -bus32`).
  Checkpoint 4b: bus-cycle timing checks in `dsz020` (`-w 0`), the RMC test (`verify/tb/rmc020.cpp`), the coprocessor
  test with a scripted coprocessor (`verify/tb/cop020.cpp`), the format-B bus error + RTE self-check
  (`verify/tb/rerun020.cpp`), `mus020 -br -halt -rst` and a bit-field snippet; the 68020 harnesses run the CPU clock at
  clk / 4. 2026-11-16: `verify/tb/amiga020.cpp` (`verify/amiga020_build.sh`) - the Amiberry / WinUAE behaviour cases
  (section 7.4) with the logged values and WinUAE's rules (`verify/tb/winuae020.h`, shared with `mus020`'s
  classification).

## 9. Parameter values

`RES` (checkpoint 6, section 3.1): 0 = BRAM-heavy (default), 1 = logic-heavy. Any other value builds RES = 0's ROMs.

`CPU`: 68000, 68008 (DIP48), 68009 (68008 PLCC52 / FN — numeric code, the part has no number of its own), 68001
(68EC000 code), 68010, 68020, 68021 (68EC020 code). 68000, 68008, 68009 and 68001 are implemented (checkpoint 2b), 68010
at checkpoint 3; any other value fails elaboration on
purpose (an unknown module is instantiated) rather than silently building a 68000. Top-level pins added at 2b: `A0`,
`DS_n` (8-bit bus), `MODE` (68EC000); `A[23:1]` carries 19 / 21 address bits on the 68008 / 68008FN.

## 10. Quartus 17.0 rules applied

No `for (genvar ...)`, no module-level loops, no assignment patterns, no size casts, no bit-select on expressions,
no `inside`, every identifier declared before use, no block-local declarations in procedural blocks, packed array
ports, no struct outputs driven whole from a sub-instance (the fleet wrapper assigns fields), ROMs as synchronous
reads of initialised arrays with `romstyle "M10K"` (all entries written; RES = 1's logic ROMs: the same form with
`romstyle "logic"`), register file as MLAB arrays with a
registered read address and no init, no memory read inside a function, plain `+` / `-` for every adder. The delivered
single file is `rtl/m68ksv_all.sv` (`verify/tools/mkall.sh` builds it and runs the pre-compile grep check).

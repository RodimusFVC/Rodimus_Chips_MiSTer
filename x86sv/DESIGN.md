# x86sv — design

Our own SystemVerilog 8088 for the MiSTer fleet (Quartus 17.0, Cyclone V), built test-first against SingleStepTests
8088 v2 (cycle traces of a real NMOS 8088), with the 8086 (8086 v1 suite) and NEC V20 / V30 (V20 v1 native suite) as
compile-time options. Status and numbers: `REPORT.md`.

## 1. Structure

| Module | File | Role |
|---|---|---|
| `x86sv` | `rtl/x86sv.sv` | 8-bit top (8088, V20 with `NEC`): BIU + EU, pin-level bus outputs, LOCK |
| `x86sv16` | `rtl/x86sv16.sv` | 16-bit top (8086, V30 with `NEC`): BIU16 + EU (`BUS16`), BHE |
| `x86sv_biu16` | `rtl/x86sv_biu16.sv` | 8086 BIU: 6-byte queue, word fetches, odd-address split, BHE, byte lanes |
| `x86sv_biu` | `rtl/x86sv_biu.sv` | T-state machine incl. Tw, reset sequence, 4-byte queue, prefetch policy, EU request arbitration, INTA pair, bus pins, QS |
| `x86sv_eu` | `rtl/x86sv_eu.sv` | registers, decode, EA sequencing, per-instruction step sequences, MUL / DIV unit, shifter, BCD, interrupt acceptance, write-back |
| `x86sv_alu` | `rtl/x86sv_alu.sv` | ADD/OR/ADC/SBB/AND/SUB/XOR/CMP/INC/DEC with flags (`+`/`-` only: carry chain) |
| (generated) | `rtl/x86sv_all.sv` | the one drop-in file (`verify/tools/mkall.sh`) |
| `x86sv_mcl86`, `x86sv_i8088`, `x86sv_i8086`, `x86sv_v20`, `x86sv_v30` | `rtl/x86sv_fleet.sv` | fleet wrappers on `chip_pool_pkg` bus types (section 3); needs the package |

**Clocking.** One core clock `clk`; `ce` = one 8088 clock. Every register updates only on `ce`, so the core runs at
any core frequency and any CPU/core ratio. No derived clocks, no latches.

## 2. How exact timing is achieved

The 8088 is two machines that share the queue. x86sv models both at clock level, and the timing falls out of their
interaction instead of being looked up per instruction.

**BIU** (`x86sv_biu`). States `Ti, Td, T1, T2, T3, Tw, T4`. `Td` is an internal "address" clock: a cycle requested while
the bus is idle starts two clocks later (`Ti -> Td -> T1`). Rules (fitted to the traces, unchanged since checkpoint 1):
- At `T4` the next cycle starts at once if an EU request was already pending, else a prefetch if the queue had room
  as of `T3`; on the first idle clock after `T4` a 3-byte queue waits one more clock.
- A prefetch `T1` is abortable by an EU request or a suspend (address driven without ALE / status, A18 low).
- Reads release the EU at the data clock (`T3` / last `Tw`), writes at `T2` of the last byte. Word accesses and the
  INTA pair are two byte cycles back to back.
- `READY` is sampled in `T3` / each `Tw`; S2-S0 stay active until the `T3` / `Tw` in which READY is high.
- After reset the BIU waits 7 clocks before the first fetch (datasheet: "approximately 7 clock cycles").
- The queue is a 4-byte shift register: the head is always `q0` (a register), a fetched byte lands behind the
  remaining ones (both pop cases are formed in parallel and selected by the pop last). The EU decodes the head's
  class straight from `q0`.

**EU** (`x86sv_eu`). A step sequencer: the first-byte read is the last step of the previous instruction; the next
clock is decode (reads the ModRM byte); then the EA sequence and the instruction's step list. Each step is a small
set of micro-operations decoded from (class, step) one clock early (the class and the step are one-hot registers;
the next step's micro-operations are registered, and conditions known only in the step's own clock are registered
as one-hot end-condition selects evaluated then): queue byte to a destination, a bus cycle (address source: EA,
EA+2, stack, immediate, DX, BX+AL, vector, SI, DI; data source; memory / I/O / INTA / HALT), the three jump
operations `SUSP` / `CORR` (IP-correction clock) / `FLUSH` (optionally far: CS from a temp), loop holds (shift
counts, MUL / DIV iterations, wait counter), step jumps and the end flag. A step waits for its queue byte, bus release
or loop condition, so queue starvation, bus contention and prefix timing come out naturally. Write-back is decided
in the instruction's last clock and applied from registers in the next (the first-byte clock): per-register byte-lane
enables, a one-hot source select (ALU result, memory word, immediate, tmp, the decoded r/m or reg operand, the
shifter, BCD, or a value computed in the deciding clock), port 2 AX / DX, SP, segment, flags. Stack, SI / DI and CX
updates and flags written by a step are registered the same way and applied one clock after their step (nothing
reads them in that clock; SP is forwarded to the next stack step). The ALU result and O / A / C are registered every
clock (`alu_q`; S / Z / P are derived from `alu_q`); an immediate high byte read in the last step is forwarded from
the queue into the ALU. Register-form shifts by 1 and BCD adjusts compute in the write-back clock from registered
operands.

**MUL / DIV** iterate one bit per clock on one shared 17-bit adder, then a wait counter makes the total equal to the
8088's data-dependent count (formulas in `REPORT.md`); flags follow the hardware rules found in the traces. Setup,
divide pre-check, loop, result sign fix-up and the flag computation each have their own clocks; the wait counter
absorbs them. The counter is loaded from registered signs one step after setup, and a quotient bit's clocks are
counted one clock after its iteration, so no count is formed in the clock its data arrives.

**Interrupts.** At the clock that applies an instruction's write-back the EU may start an interrupt instead of the
next opcode: NMI (latched rising edge) over INTR (if IF) over single-step (TF at the start of the instruction).
None after MOV / POP to a segment register, INTR not after STI / IRET (iAPX 86/88 manual 4.3); prefixes never reach
this point. INTR runs the INTA pair (vector from the second cycle); then all kinds continue with the INT n sequence
from its first vector read. REP string ops and WAIT check for interrupts at their loop points (return address: the
last prefix / the WAIT). Divide errors enter the same sequence after a fitted delay.

## 3. Fleet wrappers (`rtl/x86sv_fleet.sv`)

The core's native interface is the max-mode view: `ad[19:0]` as driven each clock, `ale`, `s20` (S2-S0), `seg_s`
(S4-S3), `tstate`, 8288-style strobes `rd / wra / wr / io / inta`, `dout`, `din`, `ready`, `lock`, `qs[1:0]`, one
`clk` and `ce`. One wrapper module per bus type, named `x86sv_<bustype>`, ports `clk`, `i`, `o` (fleet standard as in
`t80sv_fleet.sv` / `t65sv_fleet.sv`):

| Module | Bus type | Use |
|---|---|---|
| `x86sv_mcl86` | `mcl86_i_t` / `mcl86_o_t` (existing master type) | drop-in for `mcl86_cpu`: same request / acknowledge bus |
| `x86sv_i8088` | `i8088_i_t` / `i8088_o_t` (master package) | full 8088 max-mode bus |
| `x86sv_i8086` | `i8086_i_t` / `i8086_o_t` (proposed, `fleet_types.svh`) | 8086 max-mode bus: 16-bit `din` / `dout`, `bhe_n` |
| `x86sv_v20`, `x86sv_v30` | `v20_*`, `v30_*` (proposed aliases of the i8088 / i8086 types) | NEC instruction set on the same pins |

**`x86sv_mcl86` semantics.** `ce` = rising edge of `cpu_clk` in the `clk` domain; the CPU runs at the `cpu_clk`
frequency (any `clk` / `cpu_clk` ratio >= 2). `req` rises the clock after ALE with `req_type` = S2-S0, `req_addr`,
`req_wdata` (write data is already valid), and drops on `req_ack`; READY to the core is the registered "acknowledged"
flag, `din` the byte latched with the acknowledge. An acknowledge within `3P - 3` clocks of `req` (P = clocks per
`cpu_clk` period) gives a zero-wait 8088 cycle; each further P clocks is one Tw. INTA (type 000, the type byte in the
second one) and HALT (011) are requested like reads, as with `dl2_bus`. TEST is tied low; `mcl86_cpu`'s
`CYC_MUL` / `CYC_SHIFT` / `FAST_BUS` have no equivalent (x86sv's timing is the 8088's at `cpu_clk`).

**`x86sv_i8088` semantics.** Pins pass through; `addr` / `cyc` hold the ALE-latched address / status through T4;
8288 commands active low (`mrdc_n amwc_n mwtc_n iorc_n aiowc_n iowc_n inta_n`); READY sampled in T3 / Tw (hold it
low to insert Tw; `din` valid in the clock READY is high).

## 4. Configurations (each option compiles to the old logic when off; `REPORT.md` has the formal proof)

| Config | Top / parameters | Adds | Verified against |
|---|---|---|---|
| 8088 | `x86sv` | 8-bit bus, 4-byte queue | SingleStepTests 8088 v2: 100 % |
| 8086 | `x86sv16` (EU `BUS16`) | 16-bit bus, word fetches, 6-byte queue, BHE, odd-address split; six EU timing differences (step pre-delay) | SingleStepTests 8086 v1: 100 % |
| V20 | `x86sv #(.NEC(1))` | V20 instruction set (classes 48-57, 0F decode state), separate NEC step table, V20 BIU rules | V20 v1 native: 100 % (registers, RAM, cycles, bus / queue trace) |
| V30 | `x86sv16 #(.NEC(1))` | both; V30 timing = V20 EU + 8086 BIU16 with the V20 BIU rules (inferred) | V20 suite, registers / RAM only: 100 % (no V30 suite) |
| V20 / V30 + 8080 mode | `x86sv` / `x86sv16 #(.NEC(1), .NEC8080(1))` | 8080 emulation mode: MD flag + write enable, BRKEM / RETEM / CALLN, 8080 opcodes translated at the opcode clock onto native classes (ModRM preset, 8080 flag rules, DS0:BP stack, absolute targets), PS3 on A19 | own model-generated suite `verify/suites/v20_8080` (657,673 tests): 100 %; 8080 exercisers; 38 directed tests. Clock counts inferred (no document) |

`BUS16` is internal to `x86sv16` (the EU parameter); `NEC` and `NEC8080` (8080 emulation mode, only with `NEC`) are
parameters of both tops and of the fleet wrappers, so several configurations can be compiled together. The EU step pre-delay (`x_dl`, a 5-bit counter that holds a step's
bus / queue / jump operations for N clocks) exists only when `BUS16` or `NEC` is set (generate block).

NEC timing: the EU's step table is `if (NEC) <V20 table> else <8088 table, verbatim>`, so the Intel configurations
keep their logic bit for bit (formal proof in `REPORT.md`). The V20 table uses the same micro-ops plus a few NEC-only
ones: `qp` (a queue byte that just arrived costs a clock), `fw` (a request right after an EU cycle starts at its T4),
`fgo` / `efl` / `wfl` (jump flush points), `pre` (the next step requests the bus), `qw` (pop a byte in the T1 of the
step's write), `pp` / `pi` / `bx` / `ws` (0F 20-3B pointers, computed value, wait value). Long data-dependent V20
waits (63, ADD4S family, INS / EXT) count down `lc`; their values are registered (`bw*`) and selected by the step.
The V20 EA (`S_EA` with `ph` / `nim`) pops displacements at the V20's clocks and has no mode-dependent clocks.

## 5. Test-only load path

`X86SV_TESTLOAD` (define) adds ports to load registers, the queue (0-4 bytes), the prefetch pointer and the AD bus
residue in one clock. Without the define those ports and their logic do not exist (the yosys estimate is built
without it).

## 6. Risks / open items

- **Timing (needs the Quartus 17 run in `syn/quartus/`):** after checkpoint 4 the longest yosys LUT-only path is 10
  levels register to register (14 at checkpoint 3; `REPORT.md` lists the remaining paths). What is left is each
  step's own work in one 8088 clock: the micro-op decode of the next step gated by step-done (BIU release from the
  T-state and READY), the ALU operand select -> ALU -> carry / overflow, and the write-back lane decode. Shortening
  those further needs a decode ROM or operands registered a clock earlier (with the queue forwarding moved with them).
  The EU request -> aborted-prefetch T1 -> pin path is inherent to the 8088's bus (it decides in the same clock); the
  wrappers register those pins.
- Not covered by the suite and checked only against the documents: wait states, INTR / NMI / TF, HLT, WAIT, LOCK,
  reset (`REPORT.md` lists which details are inferred).
- A18 is low in `T1` clocks without a bus cycle; IF is 0 in every test, so S5 (IF) in `T2`-`T4` is unverified.
- The `v2_undefined` set is not present locally; it would need the remaining undefined forms (e.g. register forms
  of LEA / LES / LDS / FF /3 /5, FE /2-/7) defined from hardware data.
- Open decisions: 8080-mode clock counts (no NEC document gives them; RTL timing inferred, `REPORT.md` checkpoint 9);
  whether to fold `NEC8080` into `NEC`; the floating-AD drift tolerance in the runner; whether the
  8088 should adopt the four `BUS16` step timings the 8088 data cannot distinguish (REPORT, 8086 EU table).
- NEC: V30 timing is inferred (no V30 suite); several V20 timing points are inferred where the data leave a choice
  (`REPORT.md`, checkpoint 8). yosys depth V20 10 / V30 11 LUT levels against 9 for the 8088 / 8086 (Quartus run of
  the `syn/quartus` revisions pending).

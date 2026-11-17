# pit8253 — verification report

Written 2026-10-30. Paths are relative to `verify/`. Build output lives outside the repo
(`/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/pit8253/`). Verilator 4.204.

## Result

| Check | Result |
|---|---|
| `verilator --lint-only -Wall` (PIT8254 = 0 and 1; SELRANGE / WIDTH not suppressed, no lint_off) | clean, no warnings |
| `fwdref.py rtl/pit8253.sv` | prints nothing |
| Lockstep, PIT8253 build (8253) | **0 divergences**, 245,979,895 clocks (2026-11-15, with the datasheet rules; 20.0 M held writes) |
| Lockstep, PIT8254 build (8254) | **0 divergences**, 245,979,953 clocks (2026-11-15, with the datasheet rules; 19.6 M held writes) |
| Mutation controls (22 single-bug RTL copies) | 22 caught, 0 survivors (2026-11-15: + `ds1_no_write_hold`, `ds2_gate_ignores_cnt`) |

**2026-11-15: two Intel datasheet rules replace MAME behaviour** (rule text in `rtl/pit8253.sv` header and README).
The reference carries them as marked deviations: rule 2 in `pit_ref.h` (`m_cnt_wr`, `DATASHEET` comments), rule 1 in
the bench's per-clk glue (`tb_pit8253.cpp`: per-counter held write applied through `pit_ref::write_to`). Everything
else in `pit_ref.h` is still MAME line for line. A read on the clk a held write lands applies its side effects after
that write (RTL read step uses the post-write state; identical to before whenever no write lands on that clk).
Each rule removed alone diverges (mutants `ds1` at cycle 6, `ds2` at cycle 1,057,247). Pre-rule RTL + kit:
`/Work/Projects/verilator_local_files/Rodimus_Chips_MiSTer/pit8253/*pre_datasheet_2026-11-15*`.

## Method

1. **Reference.** `pit_ref.h` is a line-for-line C++ transcription of MAME `pit8253.cpp` (`pit_counter_device`,
   `pit8253_device`, `pit8254_device`): `simulate()` for all six modes with MAME's generic elapsed-cycle loops,
   `adjusted_count`, the generic BCD `decrease_counter_value`, `load_count`, `readback`, `read()` (with and without
   side effects), `control_w` / `count_w` / `gate_w` / `set_clock_signal` bodies, `device_start` + `device_reset`.
   It is independent of the RTL's reductions (the RTL replaces MAME's elapsed-cycle arithmetic by the one-cycle
   cases). Source md5s are in the header of `pit_ref.h` (`pit8253.cpp` 670d97ff…, `pit8253.h` c86d0861…).
   The scheduler, `update()`, timers and attotime are omitted (see "Not reproduced"). The reference was not changed
   to fit the RTL.
2. **Lockstep.** `tb_pit8253.cpp` drives the RTL (Verilator) and the reference with the same inputs each clk, inputs
   settled with clk low before the rising edge. Per clk the reference applies: `write_gateN` for each gate pin,
   `write()` / `read()`, then `write_clkN(1); write_clkN(0)` per `clk_ce` bit. Compared **every clock**:
   `dout` vs the reference peek of address `a` (so every read, and every idle clock), `out[2:0]` vs
   `m_output_pin != 0`, and the whole counter state (control, value, count, phase, latched-count, output, gate input,
   gate-rose flag, latched-status, null count, RMSB, WMSB) per counter.
3. Both chip variants (`PIT8254 = 0 / 1`) run the same stimulus; on the 8253 the read-back command is issued too and
   must do nothing.

## What is covered

| Suite | Clocks | Content |
|---|---|---|
| directed | 1.73 M | `d_latch` counter latch mid-count (all modes × BCD × RW, three counters at different rates, second latch while latched, latch with RMSB set, junk low bits); `d_reload` reload while counting, LSB-only write then read (`~LSB`), control word between LSB and MSB, count 1 / 0 writes; `d_gate` gate low pulse at 16 start offsets × 9 lengths × 3 clk_ce rates × every mode × BCD × counter, plus gate low during programming; `d_rates` independent `clk_ce` rates (1,2,5 / 3,7,11 / random …) with mixed and equal modes; `d_readback` all 4×8×2 read-back command forms × every mode × BCD × RW (status of untouched counters, repeat while latched, RMSB set, status flags across a run); `d_stale` count left in CR by an earlier mode then retriggered; `d_midwrite` new count (0..4) written at every offset of a running count |
| sweep | 44.2 M | every mode 0..7 × binary / BCD × RW 1,2,3 × 12 / 6 / 19 counts (0,1,2,3,…, BCD digits A-F, 0x1001, 0x1234, 0x9999, 0xFFFF) × counter 0,1,2 × 5 gate behaviours (steady, low then rise, low pulses, random, regular short pulses) × 3 clk_ce rates (every clk, ÷3, random), with random reads / latch commands / reloads / read-backs inside each run |
| random | 200 M | 8 seeds × 25 M clocks: random per-counter clk_ce rate (none, ÷1, ÷2-8, random p), gate toggle rate, bus rate and count bias re-rolled every ~4000 clks; counts biased small; control words incl. latch, modes 6/7, read-back; wr/rd strobes without `cs`; rare resets |

Coverage counted by the bench (8254 build, all suites; the 8253 build is the same scale): ~12-25 M `clk_ce` events in
every mode on every counter; output toggles in every mode on every counter (m0 ≈ 150 k, m1 ≈ 155 k, m2 ≈ 880 k,
m3 ≈ 780 k, m4 ≈ 87 k, m5 ≈ 150 k per counter); every mode × phase visited (modes 0/1/5 never show phase 1 at a
clock edge because the load is absorbed in the same step — same in MAME); 1.27–4.4 M gate falling and rising edges
per mode; 0→0x9999 BCD wraps 398 k and 0→0xFFFF binary wraps 386 k; reads: unlatched RW1/2/3, latched-count 1.5 M,
status 1.1 M, `~LSB` mid-write 2.2 M, MSB-next 3.3 M, a=3 reads 6.8 M; read-back commands with 0/1/2/3 counters
selected, status-only / count-only / both; 0.85 M strobes without `cs`; 84 k resets.
(The bench decodes modes 6 / 7 through MAME's `CTRL_MODE`, so their writes are counted under modes 2 / 3.)

## The rig can fail

`run_mutants.py` makes single-bug copies of the RTL under the build dir (never in the repo), builds each, and runs
directed + sweep + 2 M random clocks. All 20 are caught, 0 survive:

| Mutant | First divergence |
|---|---|
| BCD units borrow `<` → `<=` | cyc 916, state.value |
| BCD thousands wrap +9 → +8 | cyc 935, state.value |
| BCD hundreds wrap 9 → 8 | cyc 935, state.value |
| flush ignores gate (modes 2/3 gate-low forces out high) | cyc 282291, out |
| gate rising edge latched only in modes 2/3 (not 1/5) | cyc 147933, out |
| count 1 in mode 2 → 3 (instead of 2) | cyc 15136, state.count |
| mode 3 read mask dropped | cyc 5447, dout |
| mode 3 latch mask dropped | cyc 5487, dout |
| mid-16-bit-write read not inverted | cyc 607, dout |
| mode 4/5 zero-count strobe dropped | cyc 19363, out |
| mode 2 reload at value 2 instead of 1 | cyc 3647, out |
| mode 3 high-phase end at value 1 dropped | cyc 5456, out |
| latch ignores RMSB guard | cyc 123, state.latched_count |
| reset output low | cyc 1, out |
| mode 0 MSB write keeps counting | cyc 11440, state.value |
| 8254 status bits 7/6 swapped | cyc 837717, dout |
| 8254 status not cleared by the read | cyc 837718, state |
| 8254 read-back reaches only one counter | cyc 837717, state.latched_count |
| modes 6 / 7 not aliased to 2 / 3 | cyc 12.8 M, sweep m6 |
| mode 1 output not forced low on load | cyc 147933, out |

A 21st mutant (drop the second pass of the mode 3 `do { } while` loop) first survived. That was a real finding, not
a weak bench: a probe on the reference alone (200 M random events) showed the second pass is never taken, and
tracing MAME shows why — in phase 3 the value enters at the loaded count and steps down by 2 per clock but reloads at
2 or 3, so it can never be 1, which is the only state that makes a second pass do anything. The RTL therefore has one
pass (comment in the source) and the mutant list uses a different mode 3 mutant.

## Divergences

Target 0, result **0** (both variants, all suites, all seeds). Seeds: random runs use seeds 1..8.

## Not reproduced / differences from MAME

- **Time-based path.** MAME also clocks a counter from a frequency (`m_clockin != 0`: `update()`, multi-cycle
  `simulate(n)`, `middle_of_a_cycle` compensation, `count_w` → `simulate(0)`). That path needs wall-time and cannot be
  made cycle-exact on a clock enable. The RTL is the discrete-event path (`m_clockin == 0`, CLK through `write_clkN`),
  the only one an FPGA can follow; the reference is the same path. The `m_clockin == 0` special cases in MAME
  (`flush_output` forcing OUT high in modes 2/3 while GATE is low, `edge_sensitive_gate` for mode 3, `m_gate_rose`) are
  all ported. A board that MAME drives with `set_clk<N>(frequency)` will behave identically only to the extent the two
  paths agree (not tested here).
- **One `clk_ce` = rising + falling CLK edge together.** GATE is sampled at the rising edge and used at the falling
  edge by MAME; a GATE change between the two halves of one CLK cycle cannot be expressed.
- **Event order inside one clk** (gate, write, read, clk_ce) is an interface convention; MAME orders such events by
  time. `wr` and `rd` together are not supported. A write on a counter's `clk_ce` clk is held one clk (datasheet
  rule 1), so it lands after that CLK cycle; MAME would load it before.
- **Output "undetermined" (MAME value 2)** after reset is high (1) in the RTL; it is non-zero in MAME too, and the
  extra `flush_output` MAME runs on the first `set_output(1)` cannot change the pin. The bench compares `out` as
  non-zero.
- **Unreset storage:** latch (OL), LSB holding byte and status byte are not reset; MAME clears them but they are only
  readable after being written / latched.
- `device_start` state (gate input 1, no pending gate edge, phase 0) is part of `rst`.
- FE2010 (Faraday) variant not ported.
- MAME quirks kept: count 1 → 2 (mode 2) / 0 (mode 3); mode 4/5 with a zero count strobes at once; mode 0 MSB write
  stops counting; the counter keeps counting after terminal count (BCD wraps to 9999); mode 3 reads mask bit 0.

## Resource notes

Not synthesised (no Quartus here, no yosys). Storage per counter: control 6, value 16, count 16, latch 16, LSB byte 8,
status 8 (8254 only), phase 2, latched-count 2, 8 flags = 82 flip-flops (73 on the 8253 build, status and latched-status
optimised away), 246 / 219 for the chip. Logic is one combinational block per counter (one BCD / binary decrementer,
no multipliers or dividers; MAME's `adjusted_count` arithmetic reduces to value == 1/2/3 compares) plus the read mux.

## Run

```
make -C verify            # lint, build both variants, run all suites on both
python3 -B -I verify/run_mutants.py
./obj_825x/Vpit8253 [all|directed|sweep|random] [--seed S] [--cycles N] [--seeds K]
```
Whole suite ≈ 10 s per variant (full random run included).

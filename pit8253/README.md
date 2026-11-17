# pit8253

## From the source header

```
 pit8253.sv — Intel 8253 / 8254 PIT
 Copyright (C) 2026 Rodimus
 Ported from MAME devices/machine/pit8253.cpp (Wilbert Pol, Nathan Woods, BSD-3-Clause)

 Port mapping: MAME's discrete-event path (CLK pins driven through write_clkN, m_clockin == 0). One clk_ce[n]
 pulse is one full CLK n cycle: set_clock_signal(1) (GATE sampled, rising-GATE flip-flop acted on) immediately
 followed by set_clock_signal(0) (simulate(1)). The three counters have independent clocks.
   gate[n]    write_gateN(): any change is one gate_w event (rising edge latched for modes 1, 2, 3, 5)
   cs/wr/a/din  write(): a = 0..2 count_w, a = 3 control_w (counter latch) or, 8254, the read-back command
   cs/rd/a/dout  read(): dout is combinational for address a (a = 3 reads 0); the read side effects (RMSB,
                 latched-count / latched-status counts) happen at the clock where cs & rd is high
   out[n]     m_output_pin (MAME's "undetermined" value 2 after reset reads as 1 here)
```

## Interface

`pit8253 #(PIT8254)(clk, rst, cs, wr, rd, a[1:0], din[7:0], dout[7:0], clk_ce[2:0], gate[2:0], out[2:0])`, one clock
domain. `wr` / `rd` are one-clock strobes (not together), `dout` is combinational for `a` (valid while `cs & rd`),
read side effects land on the `rd` clock. `clk_ce[n]` = one full CLK n cycle (three independent rates). Per clk the
events are applied: gate change, bus write, bus read, `clk_ce`. `PIT8254=0` 8253 (read-back command ignored),
`PIT8254=1` 8254 (read-back count / status, any mix of counters). Counter latch command on both.

## Files

| File | md5 |
|---|---|
| `rtl/pit8253.sv` | 96ad523b |

A core lists `rtl/pit8253.sv` in `files.qip`; no `.qip` of its own.

Written 2026-10-30 (new; no earlier copy in any core).

Verification: `verify/` + `REPORT.md` — Verilator lockstep against a C++ transcription of MAME `pit8253_device`
with two Intel datasheet rules on top (below), 0 divergences; 22 / 22 mutation controls caught.

**Datasheet rules (2026-11-15, Intel 8253 datasheet 231306-001; replace MAME behaviour):**
1. A count takes effect on the CLK cycle **after** the write (3-54): a write on the same clk as a counter's `clk_ce`
   reaches that counter one clk later. Settled by side-by-side runs on the Exidy sound-board stream (Venture /
   Pepper II: 281 one-CLK waveform shifts vs the core's own model) + the board schematic (/WR spans a full PIT CLK).
2. Modes 2 / 3: a GATE rise starts counting only after a count was written since the mode word (3-55). MAME free-ran
   from the stale count (Fire One gate stream).
Behaviour that also matched the datasheet already: GATE low in modes 2 / 3 forces OUT high at once (fig 6). Power-up
OUT is datasheet-undefined; this model resets it high. Previous version (MAME-exact): md5 7571d449.

## Fleet copies

- Identical: Exidy (2026-11-15; HW-confirmed 2026-11-16, Pepper II music)
- Different: SegaVICDual (7571d449, the MAME-exact version before the datasheet rules; sync pending)

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

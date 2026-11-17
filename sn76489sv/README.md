# sn76489sv

TI SN76489 family PSG: three square-wave tones, one noise channel (periodic / white), four 2 dB attenuators. Own
SystemVerilog, written 2026-11-05 because jotego's jt89 is the Sega Master System flavour (period 0 silent instead of
0x400, a 16-bit taps-0/3 LFSR for every chip) and the fleet's TI chips are not. Behaviour per variant follows MAME
0.289 `sn76496.cpp`; the verify kit proves it tick for tick.

## Files

| File | md5 |
|---|---|
| `rtl/sn76489sv.sv` | 7134c714 |

A core lists it in `files.qip` (`rtl/rodimus/sn76489sv/`) with this folder's `LICENSE`.

## Interface

Pins = master `chip_pool_pkg` `sn76489_i_t` / `sn76489_o_t` (the same as jt89's, so a jt89 pool slot takes it):
`rst`, `clk`, `ce` (the chip's CLOCK pin rate), `wr_n`, `cs_n`, `din` in; `sound`, `ready` out.

| `VARIANT` | Chip (MAME device) | LFSR | Notes |
|---|---|---|---|
| 0 | SN76489 | 15-bit, taps 0x0001 / 0x0002 | |
| 1 | SN76489A | 17-bit, taps 0x0004 / 0x0008 | |
| 2 | SN76496 (= Y2404) | 17-bit, taps 0x0004 / 0x0008 | |
| 3 | SN76494 | as SN76489A | no /8 input divider |
| 4 | SN94624 | as SN76489 | no /8 input divider |
| 5 | Sega VDP PSG | 16-bit, taps 0x0001 / 0x0008 | period 0 = 0 (TI: 0x400); register 3 latched at reset |
| 6 | NCR8496 | 16-bit, taps 0x0002 / 0x0020, XNOR | LFSR reset only when the white / periodic bit changes |

- Timing: one update tick per 16 `ce` (2 without the /8 divider); a write is taken on the `clk` edge where `/CS` and
  `/WE` are both low after either was high; `ready` is low for 32 `ce` (4) after it, restarted by a write while low.
- **Output = the real chip's:** each channel contributes its level while its output bit is high and 0 while low,
  summed: `sound` = 0..1020 (0 when silent), not jt89's +-level. The level that follows the attenuators is part of
  the sound (a game can volume-modulate an ultrasonic tone: Slither does); MiSTer's `audio_out` DC blocker removes
  the DC. A board moving from jt89 needs about x2 for the same loudness. Output polarity is not modelled (MAME negates
  the SN76489's; inaudible).
- Reset: attenuators at 15 (silent). MAME's `device_start` sets 0 (full volume), a power-up guess for a chip with no
  reset pin; jt89 and the earlier Laeuger core also start silent.
- Not implemented: Game Gear stereo, SN76494 / SN94624 have no fleet user yet (built and verified anyway).

## Verify

`verify/run.sh [edges] [seed]`: all seven variants side by side on one random write stream (latch / data bytes to
every register, periods 0-1023, noise modes), every tick compared with `verify/model.py` (MAME's algorithm in Python):
output bits, `sound` and every READY edge. 2026-11-05: seeds 1-4, 4M-40M edges, 140K writes each, 0 differences in
every variant. Mutation check: forcing period 0 to stay 0 fails every TI variant and passes Sega's, as it should.

Game check (Qix core, `verilator/sn76489_ab/`): 38 s of Slither gameplay, both PSGs, against MAME's settings: worst
2-second residual -38 dB (PSG 1) / -44 dB (PSG 2), the rest being a few clocks of write timing.

## Fleet copies

- Identical: Qix (Slither, VARIANT 0; HW 2026-11-05)
- Identical: Pac-Man (Van-Van Car, the 2650 games; VARIANT 2; HW 2026-11-06)
- Identical: SegaG80 (Sindbad Mystery; VARIANT 2; gate PASS 2026-11-05)
- Identical: Universal (Lady Bug / Mr. Do! / Space Raider VARIANT 0, Mr. Do's Castle family VARIANT 1; HW 2026-11-06)

## License

BSD-3-Clause (own work, Rodimus; behaviour from MAME `sn76496.cpp`, Nicola Salmoria). See `LICENSE`.

# pokey_cx

Atari POKEY (C012294): four audio channels, polynomial noise, timers, pot scanning, RANDOM. A from-scratch
SystemVerilog model that matches MAME 0.289 `pokey.cpp` on every POKEY clock (same internal state after every step),
proven in a Verilator lockstep rig against the unmodified MAME source. See `REPORT.md` for the verification.

## From the source header

```
 pokey_cx: Atari POKEY (C012294), cycle-exact against MAME 0.289 pokey.cpp.
 One `ce` = one POKEY clock (MAME step_one_clock). A write (`wr`) is applied BEFORE the step on the same edge,
 so "write after step k" (MAME sync_write) and write-then-step on one edge give the same result.
 pokey_glue: pokey_cx behind the port list of the Mark Watson `pokey` module, so existing board instances
 swap by changing the module name and adding parameters.
```

## Files

| File | md5 |
|---|---|
| `rtl/pokey_cx.sv` | 3993afaa |
| `rtl/pokey_glue.sv` | 7b33308b |

A core lists both in `files.qip` (`rtl/rodimus/pokey_cx/`); no `.qip` of its own.

Imported 2026-10-30 from `ThePokeyProject_MiSTer` (retired), where it was written 2026-10-14.

## Interfaces

**`pokey_glue`** (drop-in, old Mark Watson port list): parameter `POT_CMP` = pots measured by the board's external
comparator on `pot_in` (Warlords `8'h0F`, others `0`).

**`pokey_cx`** (native): `POT_CB` (pots with a `pot_r` callback, value from `pot_val`, sampled at POTGO),
`ALLPOT_CB` (ALLPOT reads return `allpot_ext`, and a read stores it), `POT_EXT` (external comparator pots; exclusive
with `POT_CB`) — per chip, from the MAME machine config. `ce` = one POKEY clock (1.512 MHz on the Centipede board);
`wr` may arrive on any `clk` edge and is applied before the step; `dout` is combinational; `reset_n` is synchronous
and gives MAME's `device_start` + `device_reset` state.

**Scope:** audio channels (8 / 16-bit linked, AUDCTL clocks, volume-only), 4 / 5 / 9 / 17-bit poly counters with
MAME's sequences and init, high-pass filters, STIMER, IRQEN / IRQST, pot scanning (POTGO, POT0-7, ALLPOT, stop at
228), SKCTL init + bit 4. **Not implemented** (no traced game uses them): keyboard scan (KBCODE reads `09`), serial
I/O (SEROUT / SERIN, two-tone, SKCTL bits 3 / 5 / 6, SOD / OCLK).

**Glue vs MAME** (none reached by any traced game): ALLPOT callback store (no read strobe on the old ports), pot
value 0 via comparator latches at the first count, a paddle moving during a scan is followed live. Use `pokey_cx`
with `ALLPOT_CB=1` for full exactness on the ALLPOT store.

## Fleet copies

- Identical: Centipede (`rtl/rodimus/pokey_cx/`; Centipede, Millipede, Warlords, Crystal Castles, Maze Invaders,
  Multipede)
- Different: -

## Verify

`verify/` = the lockstep rig (MAME reference in `verify/ref/mame_0289/`, md5-checked by the build), 12 game traces
(`verify/traces/`), directed tests, fuzz, mutation tester. From `verify/`:

```bash
make -C verilator md5 lfsr rig glue
verilator/tb_std --trace traces/centiped_play60.ptr
verilator/tb_glue_std --trace traces/centiped_play60.ptr --glue
verilator/tb_std --fuzz 1 --clocks 10000000 --fuzz-chips 2
tools/run_m12.sh 100000000 22
```

`make old` (the Mark Watson control) needs `OLD_DIR` pointed at a copy of that RTL; it is no longer in any core.
`tools/mame/run_capture.sh` needs local MAME / ROM paths to make new captures.

## Docs

`docs/`: the Atari POKEY datasheet (C012294 rev. B, `pokey_datasheet.pdf`), pinout (`pokey.gif`), Ron Fries' POKEY
emulator notes (`pokey.txt`, 1997). Reference only, not compiled.

## Credits

- **MAME** `pokey.cpp` by Brad Oliver, Eric Smith and Juergen Buchmueller: the specification this RTL is proven
  against, included unmodified in `verify/ref/mame_0289/` under its original BSD-3-Clause licence.
- **Mark Watson**: the POKEY used in the MiSTer Atari cores until now, used as the verification control.
- Atari POKEY datasheet (C012294 rev. B).

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

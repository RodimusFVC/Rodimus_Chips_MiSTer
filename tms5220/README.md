# tms5220

TI TMS5220 speech synthesizer: the Speak External (FIFO) path, a SystemVerilog port of MAME 0.289 `tms5220.cpp`
(default build, analog output via `clip_analog`), bit-exact against MAME sample for sample. `tms5220_rsws` puts it
behind the real chip's /RS /WS pins for boards that drive those from a PIA or latch.

## From the source header

```
 tms5220.sv -- TMS5220 speech synthesizer, Speak External (FIFO) path.
 Ported from MAME src/devices/sound/tms5220.cpp (default build, analog output via clip_analog,
 instant data_w / status_r). Tables: tms5220_tables.vh, generated from MAME tms5110r.hxx.
 One ce_sample = one sample (TMS clock / 80): bit-serial frame parse, one shared multiplier for the
 20 lattice products; CPU accesses wait for the sequencer so they land between samples.
 No VSM: Speak / Read Byte read all ones (as MAME with no VSM attached).
```

## Files

| File | md5 | Use |
|---|---|---|
| `rtl/tms5220.sv` | 1f11ad8d | the chip: bus-style `wr` / `rd` strobes (MAME `data_w` / `status_r`), `ce_sample` = TMS clock / 80 |
| `rtl/tms5220_tables.vh` | bbdf424e | `` `include``d by `tms5220.sv`; keep it in the same folder |
| `rtl/tms5220_rsws.sv` | 06ce49c7 | pin front end: `rs_n` / `ws_n` / `d_in` / `d_out` / `ready_n` / `int_n`, MAME's /RS /WS I/O timing (READY low 16 TMS clocks on a write, ~13 us on a read), sample enable from `CLK_HZ` / `TMS_HZ`, `pause` |

Pool type (master `chip_pool_pkg`): `tms5220rsws_i_t` / `tms5220rsws_o_t` for `tms5220_rsws` (`CLK_HZ`, `TMS_HZ`
stay instance parameters). A board that uses the bus-style `tms5220` directly has no master type yet.

Unified 2026-11-05 from the fleet's two copies: PolePosition `rtl/sound/tms5220.sv` (this file, byte-identical) and
Exidy `rtl/sound/tms5220.sv` (the same code with the comments stripped: master `codediff.py` CODE IDENTICAL); the
tables were byte-identical in both; `tms5220_rsws.sv` is Exidy's (its only copy).

## Verify

`verify/`: `make check` regenerates the tables from MAME's `tms5110r.hxx` (must equal `rtl/tms5220_tables.vh`),
extracts MAME's `tms5220.cpp` member functions verbatim into an oracle (`gen_oracle.py`) and runs the RTL against it
in lockstep on 28 s of captured Pole Position bootleg (`polepos2bi`) speech traffic: every sample, the status byte and
/INT. 2026-11-05 (here): tables identical; 209,790 samples, 0 sample / 0 status / 0 INT mismatches. Mutation check: a
one-LSB change to the unvoiced excitation gives 435 sample mismatches. `tms5220_rsws` is not in the rig (pin timing
is Exidy's port of MAME's `rsq_w` / `wsq_w`).

## Fleet copies

- Identical (`rtl/rodimus/tms5220/`, all through `tms5220_rsws`, 2026-11-11): Qix (sndPIA2; no Qix game sends it
  anything; HW 2026-11-05), Exidy (Victory speech; moved from `rtl/sound/`, regression byte-identical), PolePosition
  (bootleg speech, HW OK 2026-11-11 with READY -> Z80 WAIT_n).
- **Gotcha (HW 2026-11-11):** `tms5220_rsws` only takes a byte while /WS (or /RS) stays low for the chip's latency
  and signals it on `ready_n`. A CPU board must hold the cycle on READY (Z80: `WAIT_n = ~ready_n`); without it every
  byte is lost (polepos2bi went silent). Pole Position's bootleg = Z80 I/O port 00, wait on READY.
- Different: -

## License

BSD-3-Clause (port of MAME `tms5220.cpp`; tables from `tms5110r.hxx`). See `LICENSE`.

# pia6821

## From the source header

```
//  Interface and timing after John E. Kent's pia6821.vhd
```

## Files

| File | md5 |
|---|---|
| `pia6821.sv` | a992c343 |

Imported 2026-11-04 from `Williams` (`rtl/sound/`). The one MC6821 PIA for the fleet (user, 2026-11-04): it replaced
Exidy's copy (Williams minus `pa_pins`) and Qix's two (`pia6821_sound.sv`, `pia6821.vhd`).

- `ce` = one-clock bus strobe (writes, read side effects, CA2/CB2 strobe release); `cs` = address decode.
- `pa_pins` = 1: Port A reads the pins for output bits too (MAME `set_port_a_input_overrides_output_mask(0xff)`);
  0: latch for output bits (MAME default).
- `pa_o` / `pb_o` are the raw output latches and `ca2_o` / `cb2_o` hold their last level while the line is an input;
  a board that needs pin levels masks them with `*_oe`.
- Pool bus: `chip_pool_pkg::pia6821_i_t` / `pia6821_o_t`.
- A board whose Port A inputs can only pull low (switches) models that wired-AND itself:
  `pa_i = switches & (pa_o | ~pa_oe)` (Qix). Never put it in the chip: Williams' gen-2 bus needs the pin.
- Behaviour vs MAME: `Claude/unify/pia6821.md`.

## Fleet copies

- Identical: Williams, Exidy, Qix
- Different: -

## License

License: BSD-3-Clause (own work, Rodimus). See `LICENSE`.

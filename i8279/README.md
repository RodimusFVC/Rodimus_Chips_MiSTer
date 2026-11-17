# i8279

Intel 8279 programmable keyboard / display interface, a port of MAME `devices/machine/i8279.cpp` (own design
2026-11-15 for Sega82: Turbo / Subroc-3D / Buck Rogers score LEDs and DIP switch scan).

## Files

| File | md5 |
|---|---|
| `i8279.sv` | see `md5sum` |

## Notes

- Bus strobes `rd` / `wr` are one clock per CPU access; `ce` = the chip's CLK as an enable.
- Keyboard modes as MAME: scanned (MAME's N-key path), sensor matrix, strobed. Right-entry auto-increment not
  implemented (as MAME).
- `disp_a` / `disp_q`: a second read port on display RAM for a board's LED overlay.
- Pool type (master `chip_pool_pkg`): `i8279_i_t` / `i8279_o_t`.
- Status: sim only (Sega82 Turbo), not HW-verified.

## Fleet copies

- Sega82

## License

BSD-3-Clause (MAME-derived; the MAME copyright holder is credited). See `LICENSE`.

# m6803

## From the source header

```
 m6803 - MC6803 (MC6801 without internal ROM) in expanded multiplexed mode, around jt680x
 (Jose Tejada, 6801 microcode, unmodified). Copyright (C) 2026 Rodimus
 Timer and port behaviour based on MAME m6801 (BSD-3-Clause, Aaron Giles).
 Used by the Irem sound boards (M52-SOUND-C / M62). Addresses outside the on-chip registers (0x00-0x1F) and
 RAM (0x80-0xFF) are external (x_cs). Only ports 1 and 2 are modelled; timer = free-running counter with
 output compare and overflow; input capture and the SCI are register stubs.
 cen = crystal rate (4 x E). Port outputs are (data & ddr) | ~ddr.
```

## Files

| File | md5 |
|---|---|
| `m6803.sv` | 232ba32a |

Imported 2026-10-29 from `Irem1` (`rtl/cpu/`).

## Fleet copies

- Identical: Irem1
- Different: -

## License

License: BSD-3-Clause for the wrapper; it instantiates jt680x (GPL-3.0-or-later, not included), so a design that includes it is bound by the GPL-3. See `LICENSE`.

# z80pio

## From the source header

```
 z80pio.sv — Z80 PIO (Z8420), the parts Sega System 1 uses
 Copyright (C) 2026 Rodimus
 Written from the Z80 PIO technical manual, checked against MAME devices/machine/z80pio.cpp.
 Register select as MAME: ba_sel = A0 (0 = port A, 1 = port B), cd_sel = A1 (0 = data, 1 = control).
 Modes 0 (output), 1 (input), 2 (port A bidirectional: the output side and ARDY / ASTB; the input handshake on
 port B's lines is not modelled) and 3 (bit control).
 Interrupt control words are parsed (so a mask byte is consumed correctly) but no interrupt is driven:
 System 1 does not wire the PIO's /INT.
```

## Files

| File | md5 |
|---|---|
| `z80pio.sv` | 701fa926 |

Imported 2026-10-29 from `SegaSystem1-2` (`rtl/cpu/z80pio/`).

## Fleet copies

- Identical: SegaSystem1-2
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

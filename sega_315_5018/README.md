# sega_315_5018

## From the source header

```
 Sega 315-5018 encrypted Z80 (Yamato, Top Roller) - opcode/data decryption
 Copyright (C) 2026 Rodimus
 Port of MAME src/devices/machine/segacrpt_device.cpp (BSD-3-Clause;
 Nicola Salmoria, David Haywood). Only D3/D5/D7 of 0000-7FFF change.
   row = {A12,A8,A4,A0}                 (table pair select)
   col = {D5,D3}, mirrored when D7 set  (entry within the pair)
   out = (src & ~8'hA8) | (conv ^ xorval)
MAME: if (src & 0x80) { col = 3 - col; xorval = 0xa8; }
```

## Files

| File | md5 |
|---|---|
| `sega_315_5018.sv` | 4c46cdca |

Imported 2026-10-29 from `CrazyClimber` (`rtl/cpu/segacrypt/`).

## Fleet copies

- Identical: CrazyClimber
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

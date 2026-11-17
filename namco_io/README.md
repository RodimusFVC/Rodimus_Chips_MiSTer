# namco_io

## From the source header

```
 Namco 56XX / 58XX / 59XX custom I/O (MB8843, undumped) - behavioural model, written from MAME namco/namcoio.cpp
 (Nicola Salmoria). Kind (index 1 byte 2): 0 = 56XX, 1 = 58XX, 2 = 59XX.
 Copyright (C) 2026 Rodimus
 CPU side = the 16XX nibble buffer: 16 nibbles, read as F0 | nibble. The command in nibble 8 runs once per
 frame (run strobe, MAME customio_run 50 us after vblank) while the chip is out of reset.
 Port pins: in[3:0] pins 38-41, in[7:4] 22-25, in[11:8] 26-29, in[15:12] 30-33 (active low, as MAME's ports);
 out[3:0] pins 13-16, out[7:4] 17-20.
coin / credit state (MAME handle_coins); reset by the 4 RESET line
```

## Files

| File | md5 |
|---|---|
| `namco_io.sv` | f7201e2e |

Imported 2026-10-29 from `Namco6809` (`rtl/namco/`).

## Fleet copies

- Identical: Namco6809
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

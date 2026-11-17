# namco_15xx

## From the source header

```
 Namco 15XX waveform sound generator (8 voices) + the boards' volume DACs, written from MAME
 devices/sound/namco.cpp (namco_15xx_device; Nicola Salmoria, Aaron Giles) and the Mappy / Super Pac-Man CPU
 board schematics.
 Copyright (C) 2026 Rodimus
 Registers = the first 64 bytes of the CPU-shared sound RAM, snooped on write (8 bytes per voice):
   +2 counter MSBs (bits 4-0 = waveform step; Grobda's DAC trick), +3 volume (bits 3-0),
   +4 / +5 frequency bits 7-0 / 15-8, +6 bits 3-0 frequency 19-16, bits 6-4 waveform
 One sample per voice at 24 kHz (18.432 MHz / 768): a 20-bit phase accumulator per voice, waveform PROM
```

## Files

| File | md5 |
|---|---|
| `namco_15xx.sv` | 7054f6d8 |

Imported 2026-10-29 from `Namco6809` (`rtl/sound/`).

## Fleet copies

- Identical: Namco6809
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

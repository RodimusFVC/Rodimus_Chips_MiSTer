# tc8830f

## From the source header

```
 Toshiba TC8830F voice LSI (1-bit ADM playback), Chance Kun
 Copyright (C) 2026 Rodimus
 Written from MAME tc8830f.cpp (hap). MAME's model is marked preliminary; this follows it as-is:
 CPU-control play only (no recording, chip read, RAM or manual control).
 Commands are 4-bit nibbles on P0-P3. 1 = no-op, 2 = play, 3 = stop,
 4 ADLD1 / 5 ADLD2 + 5 nibbles = start / stop address (nibble n -> bits 4n+3..4n),
 6 CNDT + 1 nibble = bitrate, 7 LABEL + 2 nibbles = phrase: start / stop from the ROM table at
 phrase * 4 and phrase * 4 + 4 (3 bytes, little endian each), then play.
```

## Files

| File | md5 |
|---|---|
| `tc8830f.sv` | 8f265f61 |

Imported 2026-10-29 from `Konami82` (`rtl/sound/`).

## Fleet copies

- Identical: Konami82
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

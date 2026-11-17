# namco_wsg8

## From the source header

```
 namco_wsg8.sv -- Namco WSG (Waveform Sound Generator), Pole Position's 8-voice / quad-gain variant.
 Based on MAME src/devices/sound/namco.cpp (polepos_wsg_device).
 Registers (0x83C0-0x83FF), per voice ch: base = ch*4
   base+0/1   frequency (16-bit)
   base+2     [7:4] GAIN2 (rear right)
   base+3     [7:4] GAIN3 (front left), [3:0] GAIN4 (front right)
   ch*4+0x23  [7:4] GAIN1 (rear left), [3] external source (voice muted), [2:0] waveform
 Waveform ROM: 8 x 32 4-bit samples (ioctl index 2 +0x1040), value = nibble - 8.
```

## Files

| File | md5 |
|---|---|
| `namco_wsg8.sv` | a349c12a |

Imported 2026-10-29 from `PolePosition` (`rtl/namco/`).

## Fleet copies

- Identical: Namco6809, PolePosition
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

# digitalker

National Semiconductor MM54104 Digitalker speech synthesizer: 2-bit ADPCM waveforms from the speech ROM, mirrored for
the voiced modes, pitch-held playback, silences counted out. The caller supplies the 1 MHz stream tick (`ce`) and the
speech ROM (`rom_a` out / `rom_d` in, one clock read latency); the 128-byte waveform buffer is inside the chip
(`dpram_dc`, from the master).

## From the source header

```
 Based on MAME digitalk.cpp (Olivier Galibert, BSD-3-Clause)
```

## Files

| File | md5 |
|---|---|
| `digitalker.sv` | c8ea330d |

Imported 2026-11-03 from `Galaxian` (`rtl/galaxian_digitalker.sv`; ROM and stream tick moved out to the caller).

## Fleet copies

- Identical (`rtl/rodimus/digitalker/`): Galaxian (2026-11-03)

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

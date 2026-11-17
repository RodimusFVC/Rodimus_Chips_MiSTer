# adc0804

## From the source header

```
 adc0804.sv -- ADC0804 8-bit A/D converter (accelerator / brake pedals).
 Port of MAME src/devices/machine/adc0804.cpp: 74 ticks per conversion at 384 kHz (clk/128),
 a start while busy is ignored, vin is sampled at completion, read clears INTR (active low).
 Channel select (gasel: 0 = brake, 1 = accel) is done outside, at vin.
---- 384 kHz tick generator: clk_sys/128 clock-enable ---------------------
---- conversion state machine ---------------------------------------------
```

## Files

| File | md5 |
|---|---|
| `adc0804.sv` | 61fba4d2 |

Imported 2026-10-29 from `PolePosition` (`rtl/custom/`).

## Fleet copies

- Identical: PolePosition
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

# mc68705p3

## From the source header

```
Motorola MC68705P3 Microcontroller Core
Copyright (C) 2026 Rodimus
Full 6805-HMOS opcode set. Clocked at clk (20 MHz); ce_4m pulses 1/5 clk
cycles (4 MHz oscillator equivalent). Internally divided by 4 to yield a
~1 MHz machine-cycle rate. The micro-FSM advances at clk speed and idles
in WAIT until enough machine cycles have elapsed to match HMOS timing.
Memory map (11-bit address, 2KB):
  $000-$00F : I/O & timer registers
```

## Files

| File | md5 |
|---|---|
| `mc68705p3.sv` | 80eaf616 |

Imported 2026-10-29 from `Qix` (`rtl/cpu/`).

## Fleet copies

- Identical: Qix
- Different: -

## License

License: BSD-3-Clause proposed (Rodimus); lineage PENDING. See `LICENSE`.

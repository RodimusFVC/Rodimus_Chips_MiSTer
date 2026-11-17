# riot6532

## From the source header

```
 MOS 6532 RIOT (128 B RAM, two 8-bit ports, interval timer); single clock, qualified by the E enable
 Based on MAME mos6530.cpp (Curt Coder, BSD-3-Clause)
 timer write : A2=1 A4=1, A1:A0 = /1 /8 /64 /1024, A3 = timer IRQ enable; IRQ after 1 + N*P E clocks, then /1 spin
 timer read  : A2=1 A0=0, A3 = timer IRQ enable; clears the timer flag (not if set this cycle), restarts a spin
 flag read   : A2=1 A0=1 -> {timer, PA7 edge, 6'b0}; clears the edge flag
 edge control: write A2=1 A4=0: A0 = positive edge, A1 = edge IRQ enable
```

## Files

| File | md5 |
|---|---|
| `riot6532.sv` | a6bd4fa8 |

Imported 2026-10-29 from `RodimusCoresMaster` (`rtl/sound/`).

## Fleet copies

- Identical: Exidy, Gottlieb, RodimusCoresMaster
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

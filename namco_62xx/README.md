# namco_62xx

## From the source header

```
 Namco 62XX (CUS62): a Fujitsu MB88 (MAME: MB8843) in a 28-pin package with Namco's program in its mask ROM.
 Used by Gaplus. Drives an MB88 on the mb88_* pool; the 2K mask ROM (62xx.bin) is read through rom_a / rom_d
 from the core's ROM block.
 Pins: R0-R3 12/13/15/16, R4-R6 17-19, R7 20, R8/R9 21/22, R10/_IRQ 23 (one pin), K0-K3 24-27, X 2, RESET 3.
 R0-R10 are bonded: each reads as its own output latch AND the external drive (r_ext, 1 = released).
 _IRQ takes the external drive on pin 23 (r_ext[10]). R11-R15, TC and SI are not bonded: R11-R15 read back
 their latch, TC / SI are inactive.
```

Pool types `namco_62xx_i_t` / `namco_62xx_o_t` (RodimusCoresMaster `chip_pool_pkg`). The wrapper is pins only: the
board keeps the I/O bus it sits on (Gaplus: CUS16 + 2114 nibble RAM, X = 2HB, RESET, VBLANK on R10/_IRQ, IN2 on K)
and whatever hangs off the O port (Gaplus: the explosion DACs). MAME's 62XX leaves every port unconnected, so the
reference is the HW-working Gaplus behaviour from before the wrapper existed.

## Files

| File | md5 |
|---|---|
| `namco_62xx.sv` | f593f8ed |

Written 2026-11-11 in `Namco6809` (pin mapping moved out of `superpac_board.sv`); Verilator regression
byte-identical on gaplus (3000 f), gaplusd, superpac.

## Fleet copies

- Identical: Namco6809
- Different: -

## License

License: BSD-3-Clause (our own code, from the Gaplus schematic). See `LICENSE`.

# z80dma

## From the source header

```
 Zilog Z80 DMA (Z8410), the parts the Nintendo boards use
 Copyright (C) 2026 Rodimus
 From the Zilog Z80 CPU Peripherals User Manual (UM008101), DMA chapter:
   WR0-WR6 base bytes and their follow bytes in manual order; commands C3 reset, C7 / CB reset timing, CF load,
   D3 continue, 87 / 83 enable / disable DMA, B3 force ready, 8B reinit status, BF read status.
   Sequential transfer only (no search / simultaneous), A <-> B, memory or I/O, increment / decrement / fixed.
   Byte, continuous and burst modes; standard Z80 timing (memory 3 T, I/O 4 T) or the WR1 / WR2 cycle-length byte.
   Block length N moves N + 1 bytes, byte counter stops at N, address counters at start +- (N + 1) (Table 11).
```

## Files

| File | md5 |
|---|---|
| `z80dma.sv` | 813923f4 |

Imported 2026-10-29 from `Nintendo` (`rtl/cpu/`).

## Fleet copies

- Identical: Nintendo
- Different: -

## License

License: BSD-3-Clause (own work, Rodimus). See `LICENSE`.

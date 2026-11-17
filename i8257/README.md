# i8257

## From the source header

```
 Intel 8257 DMA controller (the parts the Nintendo boards use)
 Copyright (C) 2026 Rodimus
 State machine: SI -> S0 (HRQ, wait HLDA) -> S1 -> S2 -> S3 (read) -> S4 (write, advance);
 S4 goes straight to S1 while a request is pending, else drops HRQ. One state per ce (the 8257 CLK).
 Mode register: [3:0] channel enable, [4] rotating priority, [6] TC stop, [7] autoload (ch2 <- ch3).
 Transfer type from count[15:14]; rev_rw swaps read / write (DK boards).
 READY tied high, extended write not modelled. Memory and I/O are the board's: addr / memr / memw / ior / iow.
CPU port
```

## Files

| File | md5 |
|---|---|
| `i8257.sv` | 13af305a |

Imported 2026-10-29 from `Nintendo` (`rtl/cpu/`).

## Fleet copies

- Identical: Nintendo
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

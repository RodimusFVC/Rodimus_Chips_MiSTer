# i8255

## From the source header

```
 i8255.sv — Intel 8255 PPI (modes 0, 1 and 2, port C bit set / reset)
 Copyright (C) 2026 Rodimus
 Ported from MAME devices/machine/i8255.cpp (i8255_device). Each MAME call is one clocked event here: set_mode,
 set_pc_bit, write_mode0/1/2, the read side effects of read_mode1 / read_mode2 (IBF, INTR and the input latch
 cleared at the END of the read cycle, so the CPU samples the latched byte), and the handshake pins pc2_w (port B
 STB / ACK), pc4_w (port A STB), pc6_w (port A ACK), which act on a falling edge (held pending until a clock
 without a bus event, so an edge that meets a CPU access is not lost). Port C pins are MAME output_pc,
 the port C read is read_pc. Port A / B pins hold the last value MAME's out_pa / out_pb callbacks were given;
```

## Files

| File | md5 |
|---|---|
| `i8255.sv` | f9c6a3aa |

Imported 2026-10-29 from `SegaSystem1-2` (`rtl/cpu/i8255/`).

## Fleet copies

- Identical: SegaSystem1-2
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

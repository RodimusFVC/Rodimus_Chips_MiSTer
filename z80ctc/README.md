# z80ctc

## From the source header

```
 z80ctc.sv -- Z80 CTC (Z8430): 4 channels + daisy-chain IRQ
 Copyright (C) 2026 Rodimus
 Port of MAME src/devices/machine/z80ctc.cpp (license:BSD-3-Clause, copyright-holders: Wilbert Pol)
 NOT YET CHECKED AGAINST THE ZILOG Z80 CTC DATASHEET. Behaviour follows MAME, including its quirks
 (listed in the header). zc_to: ZC/TO pulse per channel at each terminal count.
```

## Files

| File | md5 |
|---|---|
| `z80ctc.sv` | 23a36930 |

Imported 2026-10-31 from `BallyMidwayMCR` (`rtl/cpu/z80ctc/ldv_z80ctc.sv`, module renamed `ldv_z80ctc` -> `z80ctc`,
header rewritten; code otherwise identical).

## Fleet copies

- Identical: - (BallyMidwayMCR moves over in its standards pass)
- Different: LaserdiscGames (`rtl/ldp/ldv1000_fw/ldv_z80ctc.sv`): same code without the `zc_to` output; moves over by
  leaving `zc_to` unconnected (its own task).

## Open

- Audit against the Zilog Z80 CTC datasheet (none on disk yet). Until then this is MAME parity, not hardware parity.

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

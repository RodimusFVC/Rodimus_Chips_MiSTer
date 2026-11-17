# eeprom_93c46

## From the source header

```
  93C46 serial EEPROM, 8-bit organisation (128 x 8)
  Copyright (C) 2026 Rodimus

 Based on MAME eepromser.cpp, eeprom.cpp (Aaron Giles, BSD-3-Clause)
  Behaviour: start bit, 2 opcode + 7 address bits, READ = dummy 0 then 8 data bits, WRITE / ERASE / ERAL / WRAL refused
  while locked (EWDS state at reset), WRAL ANDs into the cells, busy 1.75 ms write / 1 ms erase / 8 ms all.
  DO reads READY while waiting for a start bit, the data bit while reading, otherwise 1 (pull-up).
```

## Files

| File | md5 |
|---|---|
| `eeprom_93c46.sv` | 23df2c12 |

Imported 2026-11-02 from `Centipede` (`rtl/ram_rom/`). Needs `dpram_dc` (master `rtl/ram_rom/dpram_dc.sv`).
Centipede's copy is the superset of SpaceInvaders' original: the `ext_*` port (NVRAM load / save, true data) was
added for Multipede. Cores without NVRAM tie `ext_sel`/`ext_we`/`ext_addr`/`ext_din` to 0 and leave `ext_q` open;
tied off it is logically identical to the original (audit: `Claude/unify/eeprom_93c46.md`).

Known MAME difference (kept, see the audit 2.1a): `reset` re-locks the device (EWDS); MAME keeps the lock state
across a machine reset.

## Fleet copies

- Identical: Centipede (Multipede, NVRAM via `ext_*`; `rtl/rodimus/`, 2026-11-02), SpaceInvaders (invmulti, `ext_*` tied off; `rtl/rodimus/`, 2026-11-02)
- Different: -
- Same chip, other implementation: Nintendo uses jotego's `jt9346` (vendor, Braze kits)

## License

License: BSD-3-Clause (own work, Rodimus; behaviour from MAME eepromser.cpp / eeprom.cpp, Aaron Giles). See `LICENSE`.

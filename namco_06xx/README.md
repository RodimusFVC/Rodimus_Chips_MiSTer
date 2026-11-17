# namco_06xx

## From the source header

```
 Based on MAME src/mame/namco/namco06.cpp (license:BSD-3-Clause, copyright-holders: Mike Harris, Aaron Giles)
```

Namco 06XX bus interface between a Z80 and up to four MB88 customs (50XX-54XX): control register (chip-select mask,
R/W, timer divisor), NMI timer on a 48 kHz base tick (`BASE_DIV` fabric clocks; the board's 06XX clock pin is 64H),
data read = AND of the selected chips, data write = broadcast strobe (`chip_wr`). `irq_on_access` = 1 raises the chip
IRQs on the CPU's own data access instead of the timer edge (Galaga family + Xevious, HW 2026-10-05); 0 = timer edge
only. Evidence across six implementations + schematics: vault `Rodimus_Chips_MiSTer/Claude/unify/namco_06xx_evidence_2026-11-11.md`.

## Files

| File | md5 |
|---|---|
| `namco_06xx.sv` | 93d1556f |

Imported 2026-11-11 from `Galaga` (`rtl/namco/`); only the header changed (code-identical, `codeonly.py`).

## Fleet copies

- Identical: Galaga, PolePosition (2026-11-11, HW OK on both; PolePosition `irq_on_access` 0, default `BASE_DIV`.
  It replaced PolePosition's own 06XX, which restarted the timer phase on every control write: not needed on HW).
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

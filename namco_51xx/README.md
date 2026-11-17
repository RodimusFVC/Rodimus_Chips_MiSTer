# namco_51xx

## From the source header

```
 Based on MAME src/mame/namco/namco51.cpp (license:BSD-3-Clause, copyright-holders: Mike Harris, Aaron Giles)
```

Namco 51XX I/O (coins / switches): an MB88 (MB8843) on the `mb88_*` pool + its 1K mask ROM. One mailbox byte, written
by the CPU over the 06XX (`wr_en`) and by the MCU's outO (once per `ena`; CPU write wins); `data_out` = the mailbox.
K = {06XX R/W, mailbox[2:0]}, R0-R3 = `in_a` / `in_b` nibbles, TC = ~`vblank`, IRQ = `chip_sel`, P = `p_port_out`
(coin counters). What feeds `in_a` / `in_b` is board glue (Pole Position: DSWB / IN0).

## Files

| File | md5 |
|---|---|
| `namco_51xx.sv` | 63ddfd67 |

Imported 2026-11-11 from `Galaga` (`rtl/namco/`); only the header changed (code-identical, `codeonly.py`).

## Fleet copies

- Identical: Galaga, PolePosition (2026-11-11; `poleposition.sv` carries the MB88 and the `rom_addr[11:10] == 2'b00`
  slice gate. Shadow sim vs its old private-MB88 51xx on the real index-6 ROM stream, 06XX read / write traffic,
  DIP / input changes and vblank: 0 mismatching clocks in 30M on `data_out` and P, polepos + polepos2; swapped
  in_a / in_b control fails).
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

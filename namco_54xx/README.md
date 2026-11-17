# namco_54xx

## From the source header

```
 Based on MAME src/mame/namco/namco54.cpp (license:BSD-3-Clause, copyright-holders: Aaron Giles)
```

Namco 54XX noise generator: an MB88 (MB8844) on the `mb88_*` pool + its 1K mask ROM (loaded through `rom_wr` /
`rom_addr_in` / `rom_data_in`). K = command[7:4], R0 = command[3:0]; O low / high nibble and R1 drive the board's
discrete noise stages (`discrete_o0` / `discrete_o1` / `discrete_r1`, see `namco_54xx_snd`). The pool's MB88 slot
sets `IRQ_ENTRY_STALL(3)` for this chip.

## Files

| File | md5 |
|---|---|
| `namco_54xx.sv` | ff928f52 |

Imported 2026-11-11 from `Galaga` (`rtl/namco/`); only the header changed (code-identical, `codeonly.py`).

## Fleet copies

- Identical: Galaga, PolePosition (2026-11-11; PolePosition has no MB88 pool, so `poleposition.sv` carries the MB88
  next to it with `IRQ_ENTRY_STALL(3)`, `ram_clr 0` and the `rom_addr[11:10] == 2'b10` slice gate. Shadow sim vs its
  old private-MB88 54xx on the real index-6 ROM stream: 0 mismatching clocks in 20M, wrong-slice control fails).
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

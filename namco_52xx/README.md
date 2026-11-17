# namco_52xx

## From the source header

```
 Based on MAME src/mame/namco/namco52.cpp (license:BSD-3-Clause, copyright-holders: Aaron Giles)
```

Namco 52XX sample player: an MB88 (MB8843) on the `mb88_*` pool + its 1K mask ROM (loaded through `rom_wr` /
`rom_addr_in` / `rom_data_in`). K = command[3:0]; R0 / R1 read the sample ROM byte at the live 16-bit
`sample_addr` = {O, R3, R2}; P drives the board's DAC (`p_out`, see `namco_52xx_snd`). SI and TC are board pins:
Bosconian ties SI low and clocks TC from a 555, Pole Position ties both high. An out-of-range sample read (e.g. FF
above the ROM) is board glue.

## Files

| File | md5 |
|---|---|
| `namco_52xx.sv` | 207b6e23 |

Imported 2026-11-11 from `Galaga` (`rtl/namco/`); only the header changed (code-identical, `codeonly.py`).

## Fleet copies

- Identical: Galaga, PolePosition (2026-11-11; `poleposition.sv` carries the MB88, SI = TC = 1, the
  `rom_addr[11:10] == 2'b11` slice gate and the FF-from-0x8000 voice ROM read. Shadow sim vs its old private-MB88
  52xx (which registered the address) on the real index-6 / index-5 ROMs: 0 mismatching clocks in 30M, polepos +
  polepos2; wrong-slice control fails).
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

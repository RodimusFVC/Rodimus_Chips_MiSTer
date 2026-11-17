# namco_53xx

## From the source header

```
 Based on MAME src/mame/namco/namco53.cpp (license:BSD-3-Clause, copyright-holders: Aaron Giles)
```

Namco 53XX I/O reader: an MB88 (MB8843) on the `mb88_*` pool + its 1K mask ROM. K = `k_in`, R0-R3 = `in_a` /
`in_b` nibbles, `data_out` = the O port (read over the 06XX). What feeds K / R is board glue: Dig Dug = DIPs + LS259
mode bits on K, Pole Position = K 0, R0 / R1 = steering changed / direction, R2 / R3 = DSWA.

## Files

| File | md5 |
|---|---|
| `namco_53xx.sv` | 94443768 |

Imported 2026-11-11 from `Galaga` (`rtl/namco/`); only the header changed (code-identical, `codeonly.py`).

## Fleet copies

- Identical: Galaga, PolePosition (2026-11-11; the steering accumulator moved out of PolePosition's old 53xx into
  `poleposition.sv` unchanged. Shadow sim vs the old 53xx: 0 mismatching clocks in 30M with steering + DIP traffic;
  swapped-R0/R1 control fails).
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

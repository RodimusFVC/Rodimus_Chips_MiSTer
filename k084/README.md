# k084

Konami 084 custom chip: the Tutankham starfield generator (plus the board watchdog), **written by Vic20-Ian**
for the Rodimus MiSTer cores. The 084 is the Galaxian / Scramble star circuit in one package: a 17-bit LFSR clocked
twice per pixel, gated to 512 steps per visible line. Full explanation in the source header; the pin-by-pin
derivation (Stern sheet 34D-0126-S) is in `verify/summary of changes.md`.

## Files

| File | md5 |
|---|---|
| `rtl/k084.sv` | 981d4ac9 |
| `verify/verify_k084.py` | Vic20-Ian's cycle-level check of the RTL against the circuit model |
| `verify/summary of changes.md` | Vic20-Ian's derivation and change notes |

Imported 2026-10-30 from Vic20-Ian's original submission (Arcade-Tutankham, 2026-08-24; HW-confirmed there), his
text unchanged apart from the added copyright line.

## Fleet copies

- Konami82 (`rtl/rodimus/k084/`, Tutankham board). Tutankham is the only game that uses it.
- Arcade-Tutankham (deprecated core) keeps its older copy (code-identical, condensed comments).

## License

MIT, Copyright (c) 2026 Vic20-Ian. See `LICENSE`.

# hmcs40

## From the source header

```
 hmcs40 — Hitachi HMCS40-family MCU core, fixed to the HD44801 (HMCS44
 family) configuration used by the ALPHA-8201/8302/8303 protection MCU.
 Ported from MAME's cpu/hmcs40/{hmcs40.cpp,hmcs40op.cpp,hmcs40.h}
 (license BSD-3-Clause, copyright hap), staged under
 Useful Information/mame/cpu/hmcs40/. README.md in this directory carries
 the opcode-coverage proof.
 HD44801 = HMCS44 family (hmcs40.cpp:46, :113-128):
   stack_levels = 4, pcwidth = 11, prgwidth = 12 (program_2k, 4096 words),
```

## Files

| File | md5 |
|---|---|
| `hmcs40.sv` | 55a2a88b |
| `hmcs40_decoder.sv` | 2380fb60 |
| `alpha8201.sv` | f6c726cf |

Imported 2026-10-29 from `ChampionBaseball` (`rtl/cpu/hmcs40/`).

## Fleet copies

- Identical: ChampionBaseball
- Different: -

## License

License: BSD-3-Clause (MAME-derived; the MAME copyright holders are credited). See `LICENSE`.

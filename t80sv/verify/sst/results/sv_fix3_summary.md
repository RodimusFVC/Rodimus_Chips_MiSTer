# SingleStepTests/z80 results

### sv: SingleStepTests by group

| group | opcodes | tests | pass | fail (documented behaviour) | fail (undocumented flags/WZ/strobe timing only) |
|---|---|---|---|---|---|
| base (official) | 252 | 252000 | 252000 | 0 | 0 |
| CB (official) | 248 | 248000 | 248000 | 0 | 0 |
| CB (undocumented opcodes) | 8 | 8000 | 8000 | 0 | 0 |
| ED (official) | 56 | 56000 | 49051 | 0 | 6949 |
| ED (undocumented opcodes) | 24 | 24000 | 24000 | 0 | 0 |
| DD (official) | 39 | 39000 | 39000 | 0 | 0 |
| DD (undocumented opcodes) | 213 | 213000 | 213000 | 0 | 0 |
| FD (official) | 39 | 39000 | 39000 | 0 | 0 |
| FD (undocumented opcodes) | 213 | 213000 | 213000 | 0 | 0 |
| DDCB (official) | 32 | 32000 | 32000 | 0 | 0 |
| DDCB (undocumented opcodes) | 224 | 224000 | 224000 | 0 | 0 |
| FDCB (official) | 32 | 32000 | 32000 | 0 | 0 |
| FDCB (undocumented opcodes) | 224 | 224000 | 224000 | 0 | 0 |
| **all** | 1604 | 1604000 | 1597051 | 0 | 6949 |

### sv: opcodes with documented-behaviour failures

| opcode | kind | failing tests | fields | first example |
|---|---|---|---|---|

### sv: opcodes with undocumented-only failures (f53 = flag bits 5/3 or Zilog "unknown" flags)

| opcode | kind | failing tests | fields | first example |
|---|---|---|---|---|
| ED B0 | official | 749 | f53=749, q=749 | `ED_B0_0001: F exp C4 got CC` |
| ED B1 | official | 727 | f53=727, q=727 | `ED_B1_0000: F exp 2F got 27` |
| ED B2 | official | 995 | f53=930, wz=995, q=930 | `ED_B2_0000: exp 7BD8 got 6D9E` |
| ED B3 | official | 999 | f53=925, wz=999, q=925 | `ED_B3_0000: exp 5E37 got 48EB` |
| ED B8 | official | 721 | f53=721, q=721 | `ED_B8_0000: F exp 45 got 4D` |
| ED B9 | official | 762 | f53=762, q=762 | `ED_B9_0000: F exp A7 got 87` |
| ED BA | official | 996 | f53=931, wz=996, q=931 | `ED_BA_0000: exp 4777 got 6205` |
| ED BB | official | 1000 | f53=937, wz=1000, q=937 | `ED_BB_0000: exp DD60 got E09F` |


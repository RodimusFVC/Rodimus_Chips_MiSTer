# SingleStepTests/z80 results

### vhdl: SingleStepTests by group

| group | opcodes | tests | pass | fail (documented behaviour) | fail (undocumented flags/WZ/strobe timing only) |
|---|---|---|---|---|---|
| base (official) | 252 | 252000 | 241606 | 0 | 10394 |
| CB (official) | 248 | 248000 | 248000 | 0 | 0 |
| CB (undocumented opcodes) | 8 | 8000 | 8000 | 0 | 0 |
| ED (official) | 56 | 56000 | 39048 | 0 | 16952 |
| ED (undocumented opcodes) | 24 | 24000 | 22000 | 0 | 2000 |
| DD (official) | 39 | 39000 | 37000 | 0 | 2000 |
| DD (undocumented opcodes) | 213 | 213000 | 202175 | 2000 | 8825 |
| FD (official) | 39 | 39000 | 37000 | 0 | 2000 |
| FD (undocumented opcodes) | 213 | 213000 | 202163 | 2000 | 8837 |
| DDCB (official) | 32 | 32000 | 32000 | 0 | 0 |
| DDCB (undocumented opcodes) | 224 | 224000 | 224000 | 0 | 0 |
| FDCB (official) | 32 | 32000 | 32000 | 0 | 0 |
| FDCB (undocumented opcodes) | 224 | 224000 | 224000 | 0 | 0 |
| **all** | 1604 | 1604000 | 1548992 | 4000 | 51008 |

### vhdl: opcodes with documented-behaviour failures

| opcode | kind | failing tests | fields | first example |
|---|---|---|---|---|
| DD 13 | prefix on non-HL op / IXH,IXL | 1000 | b=2, c=1000, d=4, e=1000 | `DD_13_0000: exp E4 got E5` |
| DD 1B | prefix on non-HL op / IXH,IXL | 1000 | b=1, c=1000, d=1, e=1000 | `DD_1B_0000: exp 24 got 23` |
| FD 13 | prefix on non-HL op / IXH,IXL | 1000 | b=3, c=1000, d=3, e=1000 | `FD_13_0000: exp 77 got 78` |
| FD 1B | prefix on non-HL op / IXH,IXL | 1000 | b=4, c=1000, d=5, e=1000 | `FD_1B_0000: exp 99 got 98` |

### vhdl: opcodes with undocumented-only failures (f53 = flag bits 5/3 or Zilog "unknown" flags)

| opcode | kind | failing tests | fields | first example |
|---|---|---|---|---|
| 0A | official | 1000 | wz=1000 | `0A_0000: exp 5FCE got DAFA` |
| 1A | official | 1000 | wz=1000 | `1A_0000: exp 17B8 got A458` |
| 22 | official | 1000 | wz=1000 | `22_0000: exp C962 got C961` |
| 2A | official | 1000 | wz=1000 | `2A_0000: exp 4DCB got 4DCA` |
| 37 | official | 229 | f53=229 | `37_0000: F exp 2D got 25` |
| 3A | official | 1000 | wz=1000 | `3A_0000: exp 1005 got A204` |
| 3F | official | 219 | f53=219 | `3F_0001: F exp ED got CD` |
| C0 | official | 512 | wz=512 | `C0_0001: exp 6FDB got 42DB` |
| C8 | official | 498 | wz=498 | `C8_0000: exp 3337 got B937` |
| C9 | official | 996 | wz=996 | `C9_0000: exp EEC4 got 3BC4` |
| D0 | official | 484 | wz=484 | `D0_0004: exp 9B9E got 959E` |
| D3 | official | 4 | wz=4 | `D3_00BC: exp 9A00 got 9B00` |
| D8 | official | 454 | wz=454 | `D8_0000: exp E8D9 got 80D9` |
| DD 0A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `DD_0A_0000: exp B52B got E065` |
| DD 1A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `DD_1A_0000: exp C97A got 3E77` |
| DD 22 | official | 1000 | wz=1000 | `DD_22_0000: exp ECEB got ECEA` |
| DD 2A | official | 1000 | wz=1000 | `DD_2A_0000: exp 0601 got 0600` |
| DD 37 | prefix on non-HL op / IXH,IXL | 454 | f53=454 | `DD_37_0001: F exp 65 got 45` |
| DD 3A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `DD_3A_0000: exp 734F got 754E` |
| DD 3F | prefix on non-HL op / IXH,IXL | 440 | f53=440 | `DD_3F_0001: F exp 58 got 50` |
| DD C0 | prefix on non-HL op / IXH,IXL | 498 | wz=498 | `DD_C0_0001: exp 95BA got EBBA` |
| DD C8 | prefix on non-HL op / IXH,IXL | 507 | wz=507 | `DD_C8_0001: exp B179 got 9179` |
| DD C9 | prefix on non-HL op / IXH,IXL | 998 | wz=998 | `DD_C9_0000: exp D3AE got 44AE` |
| DD D0 | prefix on non-HL op / IXH,IXL | 491 | wz=491 | `DD_D0_0002: exp E884 got E084` |
| DD D3 | prefix on non-HL op / IXH,IXL | 4 | wz=4 | `DD_D3_02A7: exp 6100 got 6200` |
| DD D8 | prefix on non-HL op / IXH,IXL | 490 | wz=490 | `DD_D8_0000: exp 4224 got E124` |
| DD E0 | prefix on non-HL op / IXH,IXL | 508 | wz=508 | `DD_E0_0002: exp EC2B got 612B` |
| DD E8 | prefix on non-HL op / IXH,IXL | 475 | wz=475 | `DD_E8_0001: exp D054 got F254` |
| DD F0 | prefix on non-HL op / IXH,IXL | 462 | wz=462 | `DD_F0_0000: exp 116B got CB6B` |
| DD F8 | prefix on non-HL op / IXH,IXL | 498 | wz=498 | `DD_F8_0000: exp 2676 got C976` |
| E0 | official | 531 | wz=531 | `E0_0000: exp 34AB got 3AAB` |
| E8 | official | 521 | wz=521 | `E8_0000: exp F3DA got EEDA` |
| ED 43 | official | 1000 | wz=1000 | `ED_43_0000: exp 88EC got 88EB` |
| ED 4B | official | 1000 | wz=1000 | `ED_4B_0000: exp BCA7 got BCA6` |
| ED 53 | official | 1000 | wz=1000 | `ED_53_0000: exp CBF0 got CBEF` |
| ED 5B | official | 1000 | wz=1000 | `ED_5B_0000: exp 48CC got 48CB` |
| ED 63 | undocumented ED | 1000 | wz=1000 | `ED_63_0000: exp 116C got 116B` |
| ED 67 | official | 1000 | wz=1000 | `ED_67_0000: exp 0990 got 62E8` |
| ED 6B | undocumented ED | 1000 | wz=1000 | `ED_6B_0000: exp 8EF9 got 8EF8` |
| ED 6F | official | 1000 | wz=1000 | `ED_6F_0000: exp A682 got 8D06` |
| ED 73 | official | 1000 | wz=1000 | `ED_73_0000: exp A7DC got A7DB` |
| ED 7B | official | 1000 | wz=1000 | `ED_7B_0000: exp 7395 got 7394` |
| ED A1 | official | 1000 | wz=1000 | `ED_A1_0000: exp 90A2 got 90A1` |
| ED A9 | official | 1000 | wz=1000 | `ED_A9_0000: exp 4DF6 got 4DF7` |
| ED B0 | official | 749 | f53=749 | `ED_B0_0001: F exp C4 got CC` |
| ED B1 | official | 730 | f53=727, wz=3 | `ED_B1_0000: F exp 2F got 27` |
| ED B2 | official | 995 | f53=930, wz=995 | `ED_B2_0000: exp 7BD8 got 6D9E` |
| ED B3 | official | 999 | f53=925, wz=999 | `ED_B3_0000: exp 5E37 got 48EB` |
| ED B8 | official | 721 | f53=721 | `ED_B8_0000: F exp 45 got 4D` |
| ED B9 | official | 762 | f53=762 | `ED_B9_0000: F exp A7 got 87` |
| ED BA | official | 996 | f53=931, wz=996 | `ED_BA_0000: exp 4777 got 6205` |
| ED BB | official | 1000 | f53=937, wz=1000 | `ED_BB_0000: exp DD60 got E09F` |
| F0 | official | 467 | wz=467 | `F0_0003: exp D55C got EF5C` |
| F8 | official | 479 | wz=479 | `F8_0000: exp 0D36 got 1B36` |
| FD 0A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `FD_0A_0000: exp ACD8 got 8043` |
| FD 1A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `FD_1A_0000: exp 5D1F got C29A` |
| FD 22 | official | 1000 | wz=1000 | `FD_22_0000: exp 41CA got 41C9` |
| FD 2A | official | 1000 | wz=1000 | `FD_2A_0000: exp CFBF got CFBE` |
| FD 37 | prefix on non-HL op / IXH,IXL | 456 | f53=456 | `FD_37_0000: F exp A9 got A1` |
| FD 3A | prefix on non-HL op / IXH,IXL | 1000 | wz=1000 | `FD_3A_0000: exp BC98 got 9897` |
| FD 3F | prefix on non-HL op / IXH,IXL | 412 | f53=412 | `FD_3F_0000: F exp 69 got 49` |
| FD C0 | prefix on non-HL op / IXH,IXL | 521 | wz=521 | `FD_C0_0000: exp D662 got DB62` |
| FD C8 | prefix on non-HL op / IXH,IXL | 502 | wz=502 | `FD_C8_0000: exp 8BBD got EEBD` |
| FD C9 | prefix on non-HL op / IXH,IXL | 991 | wz=991 | `FD_C9_0001: exp 810F got F90F` |
| FD D0 | prefix on non-HL op / IXH,IXL | 496 | wz=496 | `FD_D0_0000: exp 2FE1 got 2BE1` |
| FD D3 | prefix on non-HL op / IXH,IXL | 3 | wz=3 | `FD_D3_00A5: exp 5500 got 5600` |
| FD D8 | prefix on non-HL op / IXH,IXL | 487 | wz=487 | `FD_D8_0000: exp 7608 got 1008` |
| FD E0 | prefix on non-HL op / IXH,IXL | 510 | wz=510 | `FD_E0_0000: exp FA0A got 9B0A` |
| FD E8 | prefix on non-HL op / IXH,IXL | 501 | wz=501 | `FD_E8_0001: exp 3EF1 got 88F1` |
| FD F0 | prefix on non-HL op / IXH,IXL | 470 | wz=470 | `FD_F0_0005: exp EC7A got 0C7A` |
| FD F8 | prefix on non-HL op / IXH,IXL | 488 | wz=488 | `FD_F8_0001: exp 0C4E got AD4E` |


# NEC V20 / V30 8080-emulation-mode test suite (model-generated)

Single-instruction tests for the 8080 emulation mode of the NEC µPD70108 (V20) and µPD70116 (V30): every
emulation-mode opcode, the `ED ED` (CALLN) / `ED FD` (RETEM) escapes, BRKEM, and the native <-> emulation
transitions (RETI and POP PSW with the MD write enable, INT and NMI taken in emulation mode).

> **This is not a hardware capture.** Every expected result comes from a reference model written from the NEC and
> Intel documents and checked against the 8080 instruction exercisers (whose CRCs were computed on real 8080 silicon).
> No V20 or V30 was measured. A capture from a real V20 in emulation mode (for example a future SingleStepTests
> `v1_emulation` set) supersedes this suite wherever the two differ.

## Files

- `<op>.json.gz`: 255 files, one per 8080 opcode `00`-`FF` except `ED`; 2,500 tests each (`27` DAA: 2,048 = every
  A x AC x CY combination twice).
- `ED_ED.json.gz` CALLN imm8, `ED_FD.json.gz` RETEM (stacked PSW with MD = 1, as BRKEM leaves it), `ED_xx.json.gz`
  `ED` + any other second byte, `ED_FD_md0.json.gz` RETEM with a stacked MD = 0 (625 tests).
- `0F_FF.json.gz` BRKEM imm8 (native mode, MD write disabled).
- `CF_native.json.gz` RETI and `9D_native.json.gz` POP PSW in native mode, MD write enabled (3 of 4 tests) or
  disabled, stacked MD 0 or 1.
- `INT.json.gz` / `NMI.json.gz`: one register-only 8080 instruction, then INT (INTA vector given) or NMI at its end.
  INT with IE = 0 is not taken.

264 files, 657,673 tests, 75 MB gzipped. Seed `5632303830383031` (each file's generator seed is that value XOR the
FNV-1a hash of the file name). 30,625 tests carry `"inferred": 1` (below).

Regenerate (same bytes): `g++ -O2 -std=c++17 -o gen gen/gen.cpp -lz && ./gen <out dir> 2500`.
Model self-check against the exercisers: `g++ -O2 -std=c++17 -o exer gen/exer.cpp && ./exer TST8080.COM` (also
8080PRE, 8080EXM, CPUTEST; they are not included here).

## Format

Each file is one JSON array of tests:

```json
{"idx": 0, "name": "ADD B", "bytes": [128],
 "initial": {"regs": {"ax": 18431, "bx": 3933, "cx": 18992, "dx": 30426, "cs": 19779, "ss": 11179, "ds": 15276,
                      "es": 18817, "sp": 55043, "bp": 31821, "si": 13280, "di": 16627, "ip": 48191, "flags": 30870},
             "md_we": 1,
             "i8080": {"a": 255, "f": 150, "b": 74, "c": 48, "d": 118, "e": 218, "h": 15, "l": 93, "sp": 31821, "pc": 48191},
             "ram": [[364655, 128]]},
 "final":   {"regs": {"ax": 18249, "ip": 48192, "flags": 30739}, "md_we": 1,
             "i8080": {"a": 73, "f": 19, "b": 74, "c": 48, "d": 118, "e": 218, "h": 15, "l": 93, "sp": 31821, "pc": 48192},
             "ram": []},
 "ports": []}
```

- `regs`: the native registers with Intel names (NEC: AW BW CW DW, PS SS DS0 DS1, SP BP IX IY, PC, PSW). `flags` is
  the whole 16-bit PSW: bit 15 = MD (0 = 8080 mode), bits 14-12 and 1 read 1, bits 5 and 3 read 0. `initial.regs`
  lists every register; `final.regs` only those that changed (the whole PSW if any bit changed).
- `md_we`: the MD write enable (internal state: set by BRKEM, cleared by RETEM; it decides whether RETI / POP PSW
  in native mode may change MD).
- `i8080`: the 8080 view of the same state (A = AL, F = PSW bits 7-0, B = CH, C = CL, D = DH, E = DL, H = BH,
  L = BL, SP = BP, PC = IP), in both states, for convenience.
- `ram`: `[physical address, byte]`. Initial: every byte the instruction reads, writes or fetches, in first-access
  order. Final: every byte written (with its final value).
- `bytes`: the instruction bytes fetched. `ports`: I/O writes `[port, value]` in order. `port_in`: the byte an I/O
  read returns (IN tests). `pins` (INT / NMI files): `intr`, `nmi`, `inta_vector`. `halted`: 1 when the instruction
  is HLT (the final state is the halted state). `inferred`: 1 when the result rests on an inferred point.
- There is no cycle column: no NEC document gives clock counts for the 8080 instructions in emulation mode. The
  user's manual gives BRKEM 50, CALLN 58, RETEM 39 clocks (V20; V30 even addresses 38 / 38 / 27); the data sheet
  gives BRKEM 58. These are the manual's instruction-timing figures, not bus-level counts.

State: random 16-bit registers, segment registers and IP; PSW random with BRK (single step) 0, MD 0 in emulation
mode. Edge values are forced in: A and the 8-bit registers from {00 01 0F 10 7F 80 81 FE FF 09 0A 99 9A 90 F0 8F 55
AA}, register pairs and BP from {0000 0001 FFFF FFFE 7FFF 8000 00FF 0100 FFFD 0002}, the S Z AC P CY flags all 0 or
all 1, IP / PS / DS0 near FFFF (code and data wrap within their 64 KB segment, and at the 1 MB boundary), the M
operand and immediates from the 8-bit edge set.

## Provenance, per field

| Field | Source |
|---|---|
| 8080 instruction results (registers, flags S Z AC P CY, memory) | Intel 8080/8085 Assembly Language Programming Manual 9800301D, chapter 3 (the µPD8080AF instruction set, which NEC UM section 8 says the mode executes); AND sets AC to the OR of bit 3 of the operands (ALP 1-12). The model passes TST8080, 8080PRE, 8080EXM (25 / 25 CRCs) and CPUTEST, whose expected values come from real 8080 silicon. |
| Register mapping, 8080 SP = BP, segments (code PS, data and stack DS0) | NEC V20/V30 User's Manual (Oct 1986) section 8, figures 8-1 / 8-2 (p. 8-1); data sheet p. 19 |
| BRKEM, CALLN, RETEM, MD and its write enable, RETI / POP PSW rules | UM 12-169, 12-176, 12-177, 12-168, 12-151; section 8 (pp. 8-2 .. 8-5) |
| INT / NMI in emulation mode | UM 8-4 ("the interrupt process is performed the same as in native mode"); vector before the pushes as in the V20's native interrupt bus order |
| Cycle counts | none (see above) |

## Inferred points (not settled by the documents)

1. **PSW bits outside the 8080 view.** 8080 instructions change only S Z AC P CY (UM figure 8-2 maps only the low
   byte); V, DIR and BRK keep their values, IE changes only with EI / DI. Affects the PSW of every flag-setting test.
   Compare with mask `0xF7FF` if you disagree on V.
2. **Undefined 8080 opcodes** `08 10 18 20 28 30 38` (NOP), `CB` (JMP), `D9` (RET), `DD FD` (CALL): as on an 8080
   (not part of the documented instruction set). `ED` with a second byte other than `ED` / `FD`: both bytes consumed,
   no effect (`ED_xx`). All these tests carry `inferred`.
3. **RETEM with a stacked MD of 0** (`ED_FD_md0`): MD takes the stacked bit (the RETEM flag table shows MD as
   restored), so the CPU stays in 8080 mode, with MD writes disabled.
4. **BRKEM and CALLN keep IE and BRK** (their flag tables in UM 12-169 / 12-176 list only MD; the data sheet's text
   says BRKEM "operates exactly the same as the BRK instruction", which clears IE and BRK).
5. **Vector read before the pushes** for BRKEM, CALLN, INT and NMI (only visible when the stack overlaps the vector).
6. **I/O address**: IN / OUT port p use I/O address `00pp` as the native `IN AL, imm8`; an 8080 also drives p on
   A15-A8.
7. **16-bit wrap**: word accesses at offset FFFF (LHLD, SHLD, XTHL, stack) take their second byte from offset 0000
   of the same segment, as in native mode.

## Licence

Same as x86sv (`../../../LICENSE`): terms to be set by the maintainer. The 8080 exercisers are not redistributed.

# m68k020: 68020 / 68EC020 behaviour tests for m68ksv

Settles 68020 questions where the MC68020 User's Manual is silent, or where m68ksv and MAME's Musashi disagree (REPORT.md,
checkpoints 4 / 4b / 5). Built with SAS/C 6.58 and run in Amiberry, or on a real 68020 / 68EC020 Amiga. It refuses to
run on anything but a 68020 (68030 / 68040 / 68060 have other frames and caches). Kickstart 2.0 or later.

The 68020-only instructions are `dc.w` in the assembly source, so the assembler needs no 68020 option. Every encoding
was checked with MAME's m68k disassembler.

| Test | Question | m68ksv | Musashi |
|---|---|---|---|
| T1 | Undefined / overflow flags: DIVU.W, DIVS.W overflow; CHK.W, CHK.L in and out of range (tables) | raw, compared afterwards | |
| T2a–c | DIVU.L / DIVS.L 64-bit overflow: C flag (CCR = 1F before) | C cleared | C kept |
| T3a / b | TRAP #0 / DIVU by zero with T1 set: trace exception before the handler? | yes, PC = handler | no |
| T4a–d | PACK / UNPK with -(A7) as source or destination: A7 step and bytes | raw, compared afterwards | |
| T5a | FSAVE in user mode, no FPU | privilege violation (8) | F-line (11) |
| T5b | control: FSAVE in supervisor mode, no FPU | F-line (11) | F-line (11) |
| T6a | RTE of a format-7 frame | format error (14) | pops a 68040 frame |
| T6b | RTE of a format-9 frame (runs last) | pops 20 bytes, continues | format error (14) |
| T6c | control: RTE of a format-0 frame | pops 8 bytes | pops 8 bytes |
| T7 | JMP to an odd address: address-error frame (format, status word, fault address) | format B | mostly empty frame |
| T8a | control: is the instruction cache modelled? (stale code after a write) | stale | |
| T8b | CACR CE with CAAR: one cache entry or the whole cache cleared? | one entry | whole cache |
| T9a–e | Bit fields: width 0, negative offset in memory, a field over 5 bytes, BFFFO | expected values printed | same |
| T10 | LINK A7,#-8: which A7 value is pushed? | A7 after the decrement | same |

## Amiberry settings

68020 or 68EC020 (an A1200-style config is fine), **FPU none** (otherwise T5 means nothing), MMU none, JIT off,
cycle-exact or "more compatible" (the instruction cache test T8 needs a mode that emulates the 020 cache). Kickstart
3.x. Write down the exact settings in the label.

## Build (SAS/C 6.58, in this folder)

```
asm m68k020_a.a
sc m68k020.c LINK m68k020_a.o PROGRAMNAME=m68k020
```

If `asm` rejects `CNOP 0,4` (it aligns the two cache-test subroutines to a long word), say so: the fix is a few
`nop` / `ds.w` lines.

## Run

```
m68k020 "A1200 68EC020 KS3.1 Amiberry cycle-exact, no FPU"
```

Results go to the screen and are appended to `m68k020.log` in the current directory, so run it from a writable disk.
Each test prints its raw values and, where there is a prediction, a RESULT line naming the model it agrees with.
T1 and T4 print raw values only; they are compared against m68ksv and Musashi afterwards.

The tests run in supervisor mode with interrupts masked, using their own exception handlers through the vector table
at VBR. The original vectors, USP and CACR are restored before the program returns to the CLI. An Amiberry run shows
what WinUAE's 68020 core does. That core was written independently of Musashi, and its undefined flags were matched
to real hardware, but it is still an emulator result, not real silicon.

## Result (Amiberry, 2026-11-16) and what changed

`m68k020.log` is the Amiberry run: CPU 68020, 24-bit addressing, "more compatible" (not cycle-exact), unimplemented CPU
opcodes, MMU / FPU / JIT off, 14.187580 MHz, Kickstart 3.2.3 (exec 47.115). It agreed with m68ksv on T2's C, T3, T5,
T6, T8, T9, and disagreed on T1 (flag tables), T2 (N / Z), T4b / T4c, T7 and T10. The user chose WinUAE as the
reference for the 68020's undefined behaviour; m68ksv's 68020 / 68EC020 builds now reproduce every logged value
(`REPORT.md` "68020 behaviour from WinUAE"). The permanent check is `verify/tb/amiga020.cpp` (`verify/amiga020_build.sh
<dir> [68021]`), which runs these cases on m68ksv against the logged values and against WinUAE's rules from its source.


**Known difference from the log, #unverified (2026-11-16, the user's decision): T7's special status word.** WinUAE
logged $0066 (RW, SIZE word, FC 6, no FB / RB / RC / DF; its source calls this frame "partially implemented only").
m68ksv writes **$3066**: RB and RC set as the MC68020 User's Manual says for an address error (6.2.1, p. 6-22: "the
fault bits ... are not set ... and the rerun bits alone show the cause of the exception"), so an RTE re-runs the fetch;
the low half is WinUAE's. WinUAE's stacked PC (the JMP's address + 2) and fault-address placement are kept. Nothing
settles manual versus WinUAE without a real 68020: a run of this program on a real 68020 / 68EC020 Amiga would. If
evidence shows the choice is wrong, fix it. `amiga020` checks the SSW against $3066 and prints the logged $0066 on every
run as the known difference.

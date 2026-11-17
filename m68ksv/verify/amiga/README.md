# m68ktest: real-68000 tests for m68ksv

Settles the REPORT.md "Amiga candidates" on a real 68000. Plain 68000 only (it refuses to run on 68010 and later);
Kickstart 1.3 or later. Built with SAS/C 6.58.

| Test | Question | fx68k / m68ksv | Other prediction |
|---|---|---|---|
| T1 | `MOVE.W (A0)+,D0`, A0 odd: is A0 incremented before the address error? | no | suite / MAME: yes |
| T2 | `MOVE.W D0,-(A1)` to an odd address, `ILLEGAL` next: I/N bit of the access word | 1 | MAME / suite: 0 |
| T2b | control for T2, `NOP` next | 0 | all 0 |
| T3 | `TRAPV` after an `ADDA.L` that overflowed internally (V = 0) | no trap | MAME: trap |
| T3b | control: `TRAPV` with V = 1 | trap | all trap |
| T4a/b | `DIVU 4(A7),D0` by zero: stacked PC, N, Z | next instruction; N = D0 bit 31, Z = (D0 high word = 0) | suite: the instruction, N = Z = 0 |
| T5 | `ASR.L` by 40 on −1: X and C | 1 / 1 | suite: 0 / 0 |

## Build (SAS/C 6.58, in this folder)

```
asm m68ktest_a.a
sc m68ktest.c LINK m68ktest_a.o PROGRAMNAME=m68ktest
```

A ready-built `m68ktest` (with its `.info` icon and the `.o` files) is in this folder, built by the user with SAS/C 6.58
on 2026-11-15. `m68ktest.log` / `test.out` are the Amiberry run recorded in REPORT.md ("Emulator run 2026-11-15").
The `.uaem` files are Amiberry's metadata for the host-shared folder.

## Run

```
m68ktest "A2000 KS1.3 Amiberry cycle-exact"
```

The label is free text that goes into the log: say which machine / emulator settings it ran on. Results go to the
screen and are appended to `m68ktest.log` in the current directory (so run it from a writable disk). Each test prints
the raw exception frame, the registers at the exception, and a RESULT line naming which model it agrees with.

The tests run in supervisor mode with interrupts masked for a few microseconds, using their own exception handlers;
the original vectors are restored before it returns to the CLI. An emulator run checks the program and shows which
model the emulator follows; only a real 68000 settles the questions.

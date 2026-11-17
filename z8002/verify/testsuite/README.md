# z8002 differential test suite

Exhaustive opcode-level verification of `rtl/cpu/z8002/z8002.sv` against MAME's
z8000 core, in the style of jtcores / SingleStepTests.

**Bar: MAME parity.** MAME runs Pole Position correctly, so anything that matches it
architecturally cannot be our bug. This does not claim silicon accuracy.

```bash
make bootstrap && ./bootstrap        # prove the oracle first (see below)
make suite                           # build the Verilator co-sim
./obj_dir/Vz8002_suite_tb --ctx 8    # full run, ~53 s
```

Results land in `results/summary.txt` (counts + per-handler table) and
`results/failures.txt` (sampled diffs, 2 per handler, with disassembly).

Options: `--ctx N` contexts per opcode, `--seed S`, `--begin/--end` opcode window,
`--maxfail N` sample cap. Everything is derived from `(seed, opcode, ctx)`, so a run
is exactly reproducible and no corpus file has to be stored or maintained.

## How it works

MAME's `cpu/z8000` sources are compiled **completely unmodified** out of
`Useful Stuff/mame/z8000/` (via the `mame_z8000` symlink, which exists only so make
does not have to cope with the space in "Useful Stuff"). `mame_shim/emu.h` supplies
the ~400 lines of MAME framework surface those files actually touch — device, memory
spaces, devcb, state entries — so `z8000.cpp` and `8000dasm.cpp` compile as-is.
Nothing is transcribed or reimplemented, which is the whole point: a hand-copied
oracle would carry hand-copied bugs.

For each test both models start from a **byte-identical 64 KB image**:

* FCW comes from the reset vector at `0x0002` (both models honour it),
* the 16 registers are loaded by a 16-instruction `LD Rn,#imm16` preamble at
  `0x0100` that **both models execute**, so no RTL backdoor or `verilator public`
  marker on the register file was needed,
* the instruction under test sits at `0x0140`, followed by seeded random words so
  immediate/address operands vary per context,
* the rest of memory is seeded random so loads see varied data.

State is compared **at the end of the preamble** before the instruction under test
runs. A setup divergence is therefore reported as `FAIL_SETUP` and never
misattributed to the opcode being tested.

**Compared:** R0-R15, PC, FCW, and the final contents of every address either side
wrote. Writes are compared by resulting *content*, not by transaction, because
z8002.sv implements byte stores as a word-aligned RMW (`z8002.sv:2304`) while MAME
issues a masked byte write — same architectural effect, different bus shape.

**Not compared:** cycle counts. Cycle accuracy is a deliberately deferred pass for
this core, and MAME's counts are not silicon-accurate anyway.

**Repeating block instructions:** MAME implements these as one iteration per dispatch,
rewinding PC by 4 to re-enter. Rather than assume the RTL does the same, both sides
run until PC *leaves* the instruction under test, which compares the architectural
effect without assuming an implementation.

## Trust the oracle before trusting the results

`./bootstrap` replays the byte-identical program from `verilator/z8002_optest/` and
checks the same six expectations. Those were derived by hand from `z8000ops.hxx` over
earlier sessions and two of them (the `0x5E` JP fix) are HW-corroborated. It exercises
exactly the things that would silently corrupt everything downstream: the `m_regs`
union index macros (a wrong `BYTE4_XOR_BE` permutes every register), memory word
indexing and big-endian byte order, and dispatch through MAME's own table.

All six pass. If they ever stop passing, the oracle is wrong and no result from
`Vz8002_suite_tb` means anything.

## Outcome kinds

| Kind | Meaning |
|---|---|
| `PASS` | architectural state identical |
| `FAIL_STATE` / `FAIL_MEM` | registers/PC/FCW differ / written memory differs |
| `FAIL_TIMEOUT` | RTL never left the instruction under test |
| `FAIL_ILLEGAL` | RTL asserted `dbg_illegal` |
| `FAIL_SETUP` | diverged during the preamble — not an opcode result |
| `SKIP_INVALID` | decodes to MAME's `zinvalid` |
| `SKIP_EXCLUDED` | I/O instruction (see below) |
| `SKIP_TRAP` / `SKIP_HALT` | queued an EPU/privileged/syscall trap, or halted |
| `SKIP_SELFLOOP` | the instruction branches to itself |
| `SKIP_MODECHANGE` | result flips FCW's S/N or SEG bit |

## Current state (2026-08-20)

`--ctx 8`: **465992 tested, 461365 pass, 4627 fail.** Two RTL bugs found and fixed
during the first run (DBJNZ never branched; INC/DEC by 16 added nothing) — both are
now 100% clean. What remains, grouped:

| Count | Family | Status |
|---|---|---|
| 2947 | block-string `0xB8/BA/BB` | **deliberate omission** — `z8002.sv:223-224` "zero confirmed usage, out of scope". Never asserts `dbg_illegal`, which is exactly the blind spot the trap census could not see. |
| 949 | register-overlap ordering: `pop`/`popl`/`lda`/`rldb`/`rrdb`/`call` | only when the destination IS the pointer/index/stack register (`pop r1,@r1`, `call r15`). Writeback-vs-pointer-bump order. Architecturally ambiguous — needs the Z8000 manual to settle. |
| 524 | `ldctl` | control registers read 0 in RTL |
| 118 | `sdlb` dynamic byte shift | **not used anywhere** in `Useful Stuff/disassembly` |
| 67 | `ldps` | FCW bit 15: MAME force-clears `F_SEG` on Z8002, RTL keeps it |
| 6 | `comb addr`, `iret` | same overlap/divergence classes |

## Oracle divergences — a policy, not a bug list

MAME is the emulator that **runs this game correctly**. When the RTL and MAME disagree
and MAME looks "wrong" against the architecture, that is NOT automatically MAME's bug —
it may be silicon behaviour the game depends on. Such cases are:

1. skipped as `SKIP_ORACLE_DIVERGE` so the pass rate stays meaningful,
2. documented **at the decode site in `z8002.sv`**, and
3. left as a standing decision (replicate vs keep) — never silently converged either way.

MAME's own sources are never edited.

Currently two entries, both verified against MAME's sibling handlers:

* **`MULTL rqd,@rs`** (0x1810-0x18FF) — MAME reads a register pair, not memory, and marks
  the line `//@@@`. See `z8002.sv:2446`. **Undecided.**
* **`COMB @Rd`** (0x0C10-0x0CF0) — MAME reads NIB3, always 0 in that range, so it always
  complements `@R0`. A prior session had already found this independently; see the note
  at the `0x0C` decode site.

Every occurrence of both in `Useful Stuff/disassembly` sits in a data region (incrementing
byte patterns, surrounded by `.word`/`ext0e` noise), so nothing has forced the decision yet.

## Deliberately not covered

* **`zinvalid` opcodes (5624 of 65536).** MAME's `zinvalid` only calls `logerror` —
  it is a silent no-op, so there is no defined behaviour to compare against. Decode
  legality for these is covered separately by `verilator/z8002_audit/`.
* **I/O instructions**, including the repeating block-I/O forms. The DUT wrapper has
  no I/O space (`iorq` is tapped but unmodelled), so the RTL would transact against
  program memory while the oracle uses a separate space. Lifting this needs an I/O
  model in `z8002_suite_tb.sv`; until then comparing them would measure the harness.
* **Trap-taking instructions.** MAME does not run the trap sequence until the *next*
  dispatch, so the architectural effect is not visible in a single step. Detected
  automatically via `m_irq_req`, not by an opcode list.
* **S/N and SEG mode changes.** MAME swaps in a shadow stack pointer on a
  system/normal transition; the RTL is a documented single-SP model, so a mode change
  would be a harness artefact rather than a bug. Tests keep FCW's control bits fixed
  (system mode, interrupts disabled) and skip any result that flips them.

## Files

| File | Role |
|---|---|
| `mame_shim/emu.h`, `logmacro.h` | minimal MAME framework so its sources build as-is |
| `oracle.{h,cpp}` | thin `z8002_device` subclass: set state, step one dispatch, disassemble |
| `tools/gen_opinfo.py` → `z8000_opinfo.h` | replays MAME's `init_tables()` loop over `z8000tbl.hxx` to get the authoritative handler/size/cycles map for all 65536 first words |
| `bootstrap_main.cpp` | oracle trust check (no RTL involved) |
| `z8002_suite_tb.sv` | DUT wrapper, write bus exposed |
| `suite_main.cpp` | image builder, both runners, comparison, reporting |

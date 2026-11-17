# pokey_cx — verification report

Carried over from ThePokeyProject_MiSTer (2026-10-14). Paths below are relative to `verify/`.

## Target Games

The games whose POKEY traffic was captured from MAME and replayed through the rig:

| Game | MAME set | POKEYs | Pot inputs |
|---|---|---|---|
| Centipede | `centiped` | 1 | none |
| Warlords | `warlords` | 1 | 4 paddles (POT0-3) |
| Millipede | `milliped` | 2 | DIP switches through ALLPOT (both chips) |
| Maze Invaders | `mazeinv` | 2 | DIP switches through ALLPOT (both chips) |
| Multipede | `multiped` | 2 | DIP switches through ALLPOT (both chips) |
| Crystal Castles | `ccastles` | 2 | IN1 through ALLPOT (second chip) |

Multi-chip boards need nothing special: MAME keeps all state per device, the
datasheet shows no chip-to-chip pins, and each chip is simply a separate instance.

---
## Verification

### Method

1. **Reference.** MAME 0.289 `pokey.cpp` / `pokey.h` compiled *unmodified* against a
   small shim (`ref/shim/`). The build checks the md5 of the source, so the oracle
   cannot drift from MAME.
2. **Captures.** MAME runs each game headless with a Lua script that records every
   POKEY read and write with its clock. Input devices are disabled so captures are
   deterministic (three identical runs, identical md5).
3. **Scheduling model.** `mame2ptr` places each access at the POKEY clock where MAME
   performs it (including the board's timer syncs), and scores MAME's recorded read
   values against the reference at that position. The model was fitted to the data
   and reproduces MAME's read values on every game.
4. **Lockstep.** `tb_pokey.cpp` drives the RTL and the reference with the same trace
   and compares the full state after every event and every clock.

### Results

| Run | Result |
|---|---|
| Game traces, 6 games x attract + play (normal and merged-write modes) | 24 / 24 pass |
| Game traces through `pokey_glue` with the old port protocol | 12 / 12 pass |
| Directed tests T01-T14 (registers, init, clocks, noise, linked, filters, STIMER, IRQ, pots, AUDCTL) | 26 / 26 pass |
| Random fuzz, 32 seeds x 100 M clocks x 2 chips, std + Warlords builds, normal + merged | 128 / 128 pass |
| Fuzz through `pokey_glue` | 64 / 64 pass |

### The rig can fail

A comparison that never fails proves nothing, so the rig is checked against
known-bad designs:

| Control | Result |
|---|---|
| Previous POKEY RTL (Mark Watson), audio output only | Diverges on all 7 traces that produce sound (the other 5 are silent in attract mode) |
| 23 single-bug mutants of `pokey_cx` (`tools/mutate.py`) | 23 caught, 0 survivors |
| A deliberately planted register error (`--plant`) | Caught at the planted clock |

---

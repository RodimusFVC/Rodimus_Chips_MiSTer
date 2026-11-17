# dsnd_engine

## From the source header

```
 Discrete sound engine: one small fixed-point processor that runs a per-game circuit program (MRA index 5,
 assembled by RodimusCoresMaster_MiSTer/tools/dsnd.py) once per sample, so each discrete sound board costs a
 program, not logic. TICK = clocks per sample (at least 832); out_r / sample are optional (unconnected for mono).
 How it works: README.md of this chip folder.
 Copyright (C) 2026 Rodimus
 SPDX-License-Identifier: BSD-3-Clause
```

## Files

| File | md5 |
|---|---|
| `dsnd_engine.sv` | bd33d6e6 |

`verify/` is the one verification kit for the engine (cores never copy it; their `verilator/Makefile` builds
`obj_dsnd/Vdsnd_engine` from it with their own TICK / clock, and model-only tools include `verify/dsnd_model.h`):

| File | Role |
|---|---|
| `verify/dsnd_model.h` | instruction-set model: every op 0-33, out / out_r, NOISE b[2] guard |
| `verify/dsnd_lockstep.cpp` | RTL vs model per sample on out and out_r: `--fuzz`, `--prog --len --ev / --evfile --wav`; built with `-DTICK -DCLK_HZ [-DWAV_CH=1]` |
| `verify/dsnd_optest.py` | directed programs: EXP / RCP bit windows, NOISE with and without the guard (opcodes from the master `tools/dsnd.py`) |
| `verify/mutate.py` | control mutants (guard removed, OUTR removed) that the checks must catch |
| `verify/dsnd_run.cpp` | model-only renderer (no RTL, fast): the lockstep's arguments + `--dump --regs` register dumps; `make` checks its WAVs equal the lockstep's |
| `verify/check.py`, `verify/Makefile` | `make`: everything above at TICK 832 / 917 / 1024; `make fleet`: also every shipped program of the cores in `FLEET`. Build output goes to `verilator_local_files/Rodimus_Chips_MiSTer/dsnd_engine` |

Imported 2026-10-29 from `RodimusCoresMaster` (`rtl/sound/`).

## Fleet copies

- Identical: Exidy, Galaxian, Phoenix, SegaVICDual, SpaceInvaders (Pong has no copy; the master holds no chips since 2026-10-30)
- Different: -

SpaceInvaders (old ancestor copy) moved to this file 2026-11-02: A/B over all 33 ops, WAVs byte-identical, HW pass.

2026-11-03: NOISE b[2] = SN76477 lock-up guard (new bit 1 while LFSR bits 28 and 4:0 are all 0; first user
SpaceInvaders `tools/dsnd_zac.py`). Programs with b[2] = 0 are unchanged: every shipped program of the four cores
(42 unique, 364 MRAs; NOISE operands 0-2 only) gives byte-identical WAVs on d46fe92c and 11dbdc41, RTL = model on
every sample.

2026-11-03: `verify/` merged from the three core copies (Exidy model + OUTR, Phoenix TICK, Starfire `--evfile`,
SpaceInvaders guard test). `make fleet`: 0 mismatches on random programs and every directed program at TICK 832 /
917 / 1024, both control mutants caught, all 44 shipped programs (Exidy 9, Phoenix 2, SegaVICDual 1,
SpaceInvaders 32) 0 mismatches. Each core's rebuilt `obj_dsnd` gives byte-identical WAVs and summaries to its old
copy (SpaceInvaders 30, Phoenix 2, Exidy 9 programs).

## How it works

### What it is

A small fixed-point processor that runs a per-game **circuit program** once per audio sample. A discrete sound board
(op-amps, RC networks, 555s, SN76477s, transistor stages) becomes a program loaded from the MRA, not dedicated logic,
so one engine instance serves every board of a core. Programs are written in Python against the node library in
`RodimusCoresMaster_MiSTer/tools/dsnd.py` and verified bit-exact against the C model in `verify/`.

### Timing and budget

| Item | Value |
|---|---|
| Sample period | `TICK` clocks (parameter, default 832). Sample rate = core clock / TICK (fleet: 39.936 MHz / 832 = 48 kHz, 22.578 MHz / 832 = 27.137 kHz, 44 MHz / 917, 30.937 MHz / 1024). `pause` freezes the period counter. |
| Cost | 2 clocks per instruction (E1 / E2); EXP 8 clocks, RCP 10 |
| Budget | 410 **units** per sample: 1 per instruction, EXP 4, RCP 5. A full-budget sample takes ~824 clocks, so TICK must be at least 832. |
| End of sample | at END, or after the instruction that reaches 410 units. An over-budget sample is **cut silently** (later instructions, including OUT, do not run), so the assembler asserts the static worst case. |
| `sample` | one-clock strobe at the start of each period (sources are read after it): lets a core box-average a fast source over the period |

### Numbers and output

- Q24 two's complement: 1.0 = `1 << 24`, range -128.0 .. just under +128.0. The accumulator and the state words are
  32 bits and **wrap**. Products are `(a * b) >>> 24` of the full product, truncated to 32 bits.
- Units belong to the program: volts for op-amp boards; V / mA / kΩ for transistor boards, so V = mA × kΩ stays in range.
- Output: OUT adds `acc` to `mix`; at the end of the sample `out = saturate16(mix >>> 9)`, so 1.0 = 32768 = full scale.
  OUTR adds to `mix_r`; `out_r = saturate16(mix_r >>> 9)` if any OUTR ran in the sample, else `out_r = out`
  (mono programs need no change; leave `out_r` unconnected in a mono core).

### Program image (MRA index 5 in the fleet)

- No header: the raw program. Byte `n` goes to word `n >> 3`, byte lane `n & 7` (`prog_wr` / `prog_addr[12:0]` /
  `prog_data`, written through byte enables). Each 64-bit word is little endian.
- Up to 1024 words (8192 bytes); the program counter is 10 bits. The program RAM is never cleared: execution stops at END.

| Bits | Field | Use |
|---|---|---|
| 63:56 | `op` | opcode 0-33; any other value is a NOP costing 1 unit |
| 55:48 | `a` | state address M[a]; for BIT / FAND / FOR bit 0 = invert |
| 47:40 | `b` | source select: `b[5:3]` = source byte, `b[2:0]` = bit; also the NOISE LFSR `b[1:0]` + guard `b[2]`, and RCM's coefficient address M[b] |
| 39:32 | — | 0 |
| 31:0 | `imm` | signed immediate: Q24 value, raw integer, skip count, or LDLM mask / shift |

- The assembler's init block and settings ("change") block are ordinary instructions at the start of the program, not
  a header (below).
- Cores that switch between the engine and other sound (SpaceInvaders, Exidy, SegaVICDual) set a "program present"
  flag on any index-5 byte and clear it on the index-1 load, so index 5 must come **after** index 1 in the MRA. The engine reset must cover the whole download: it clears the state memory,
  so every load re-runs the init block.

### Instruction set

`S` = source byte `src[b[5:3]]`; `sbit` = `S[b[2:0]] ^ a[0]`; adds and subtracts wrap; compares are signed.

| op | Name | Semantics |
|---|---|---|
| 0 | END | end of sample (a program word of 0 is END) |
| 1 / 2 | LD a / LDI | `acc = M[a]` / `acc = imm` |
| 3 / 4 / 5 | ADD a / SUB a / ADDI | `acc += M[a]` / `acc -= M[a]` / `acc += imm` |
| 6 / 7 | MULI / MUL a | `acc = acc * imm >> 24` / `acc = acc * M[a] >> 24` |
| 8 / 9 / 28 | ST a / STF a / STNF a | `M[a] = acc` / only if F / only if !F |
| 10 / 21 | LDIF / LDF a | if F: `acc = imm` / `acc = M[a]` |
| 11 | RC a | `acc = M[a] + (acc - M[a]) * imm >> 24; M[a] = acc` (difference in 33 bits: cannot overflow) |
| 12 | RCM a, b | RC with the coefficient `M[b]` |
| 13 / 14 | CMP a / CMPI | `F = acc >= M[a]` / `F = acc >= imm` |
| 15 / 16 | MAXI / MINI | clamp `acc` from below / above at `imm` |
| 17 / 26 / 27 | BIT / FAND / FOR | `F = sbit` / `F &= sbit` / `F \|= sbit` |
| 18 | NOT | `F = !F` |
| 19 | NOISE b | `L = lfsr[b[1:0]]` (31 bits): `nb = L[28] ^ L[0]`; with `b[2]` (SN76477 lock-up guard) `nb = 1` while `L[28]` and `L[4:0]` are all 0; `L = {nb, L[30:1]}`, `F = nb` |
| 20 / 33 | OUT / OUTR | `mix += acc` / `mix_r += acc` |
| 22 / 23 | SKF / SKNF | if F / if !F: skip `imm` words forward (relative to the next word, 10-bit wrap) |
| 24 | LDL b | `acc = S << 16` |
| 25 | ABS | `acc = \|acc\|` (INT_MIN stays) |
| 29 | LDLM b | `acc = (S & imm[7:0]) << imm[12:8]` |
| 30 | MACI a | `acc += M[a] * imm >> 24` |
| 31 | EXP | `acc = 2^acc`: degree-5 Horner on the fraction with Q28 coefficients, then a shift; ≥ 7.0 → 0x7FFFFFFF, < -24.0 → 0 |
| 32 | RCP | `acc = 1 / acc`: normalise to 0.5..1, seed 48/17 - 32/17 D, three Newton-Raphson steps in Q24; 0 → 0x7FFFFFFF, result saturated |

Skips are the only control flow (no loops, no calls); the assembler emits forward skips only. A write in E2 is
forwarded to the next instruction's read, so programs see no read-after-write hazard. `verify/dsnd_model.h` is the
exact reference for every op (EXP / RCP constants included).

### Machine state

| Item | Reset | Notes |
|---|---|---|
| State M[0..255], 32 bits | cleared (256 clocks after reset) | M[255] = the assembler's "initialised" flag |
| Program RAM, 1024 × 64 | not cleared | loaded byte-wise |
| `acc`, F | **not** cleared, persist across samples | do not rely on them at the start of a sample |
| `lfsr[0..3]`, 31 bits | 1 at power-up, **not** reset | stepped only by NOISE; do not rely on the phase after a reset |
| `pc`, `mix`, `mix_r`, budget count | 0 at the start of every sample | |
| `out`, `out_r` | 0 | change once per sample |

### Sources

`src` is 64 bits, one byte per source, `b[5:3]` selects the byte. The meaning is a contract between the core's
wiring and its programs. The assembler's conventions:

| Byte | Use |
|---|---|
| 0-4 | board sources (sound latches, input ports; per core: its `tools/dsnd_boards.py`). Names `LATCH1..4`, `LATCH0` |
| 5 | core-defined (`MISC`, e.g. VBLANK / coin / a tone bit), or OSD volumes `{music[3:0], effects[3:0]}` (level 8 = unity) when a board uses `Board.vol()` |
| 6 | Game Audio: [2:0] Timing caps, [5:3] Filter caps |
| 7 | Game Audio: [2:0] Oscillator caps, [4:3] Aged caps, [7:5] Music volume (trim pot) |

### The assembler (`RodimusCoresMaster_MiSTer/tools/dsnd.py`)

- **Rate first.** A core calls `dsnd.set_fs(clock / TICK)` before any board module loads (board modules read
  `dsnd.FS` at import): the core's `tools/dsnd_rate.py`, imported first by every board module.
- **`Prog`**: `r(name)` allocates named state registers 0..254 (one global namespace per program), `op(name, a, b, imm)`
  appends an instruction, `src(source, bit)` builds `b`, `skip_if()` / `land()` emit and patch forward skips,
  `rc` / `rc_sel` / `noise` are small building blocks, `binary()` packs the image (asserts the trailing END and ≤ 1024
  words). Helpers: `q()` (to Q24, range-checked), `k_rc(tau)`, `rc_exp`, `par`, `qmul` (the engine's exact multiply).
- **`Board(Prog)`** adds the node library: one method per discrete-circuit element (op-amp oscillators / VCOs /
  filters / integrators / one-shots in Norton and standard forms, TVCA, RC discharge, mixers, LFSR and uniform noise,
  555 astable, SN76477 SLF + VCO, Midway tone generator, filters, gain, `output(src, scale, right=)`). Each is written
  to match the discrete-netlist element of the same name, computing its constants as that element's reset does.
- **`finish()`** assembles

```text
[init block]    LD M[255]; CMPI 1; SKF over      ; once after reset: Board.init() values, _glast = -1.0, M[255] = 1
[change block]  key = src6 | src7 << 8 (| src5 << 16 when vol() is used); if key == _glast skip it, else:
                group factors (_fT / _fF / _fO = 1 / cap scale, x Aged), music / OSD volume factors,
                every kreg() rate, _glast = key, END   ; the sample that sees a settings change is silent
[body]          the circuit, END
```

  and asserts `worst_path() <= 410`: the exact static longest path in units (both skip branches, EXP 4, RCP 5,
  `jump()` = always taken), covering the init and change blocks.
- **Settings.** `kreg(reg, k, group)` puts a rate scaled by a Game Audio group into the change block, so scaling costs
  nothing per sample (clamped at 1.0 unless `clamp=False`, for slopes and phase steps). A rate per sample scales by
  1 / C (smaller cap = faster). Crystal-derived clocks stay unscaled. A board with no group, kreg, music or volume
  input gets no change block.

### Writing a board program

1. **Reference first**: the schematic, traced; the discrete netlist where one exists (what it models, what it plays as
   samples, what it leaves out); samples are measurement targets only, never played.
2. **ngspice deck** of the traced circuit (models: `RodimusCoresMaster_MiSTer/tools/spice/`), and a float prototype
   (same equations and order as the program) when the circuit is not a stock node.
3. **Program** with `Board` nodes, in the core's `tools/dsnd_<board>.py`, registered in its `tools/dsnd_boards.py`.
4. **Compare** against the references: the core's capture scripts (`RodimusCoresMaster_MiSTer/tools/mame_*.lua` log
   port writes as events), `verify/dsnd_run` (model only, register dumps) for iteration; envelopes, levels, pitch,
   decay.
5. **Lockstep** the final program on the RTL (`verify/dsnd_lockstep.cpp`, the core's `obj_dsnd/Vdsnd_engine`):
   `lockstep: N samples, 0 mismatches`, plus long stress runs of random overlapping triggers at the game's write rate.
6. **MRA**: the core's generator emits index 5 after index 1. A new program needs no rebuild; new source wiring does.

### Rules learned

| Rule | Why |
|---|---|
| Static budget, not the sim maximum | an over-budget sample silently loses its OUT; `finish()` asserts the bound |
| Respect the Q24 range | clip before a large gain and split gains into steps; pick units that keep values small |
| Register names are global per program | node internals derive from the output name (`out + "_x"`); names starting `_` belong to the assembler and helpers |
| Over budget | move scaling into `kreg`, share identical sub-circuits, run slow parts every n-th sample (round robin / alternate), keep EXP / RCP rare |
| Apply the board's output-stage gain | output scale = the netlist's output gain × its route gain / 32768 |
| A settings change costs one silent sample | the change block ENDs |
| zsh does not word-split `$EV` | use `${=EV}` (sh: `$EV`), or the harness gets only the first event |

### Using the engine in a core

- **Files**: `rtl/dsnd_engine.sv` (copied to the core's `rtl/rodimus/dsnd_engine/`, byte-identical) + the core's
  `dpram_dc` (RodimusCoresMaster `rtl/ram_rom/`, byte enables required). Simulation: VerilatorMaster
  `common/ram_sim.sv`.
- **Instance** (pool slot in the dispatcher):

```systemverilog
dsnd_engine #(.TICK(832)) dsnd_0 (                    // clk = TICK x sample rate
    .clk(clk), .reset(reset),                         // reset must cover the MRA download
    .pause(pause),
    .prog_wr(ioctl_wr && ioctl_index == 8'd5), .prog_addr(ioctl_addr[12:0]), .prog_data(ioctl_dout),
    .src(ds_src),                                     // {byte7 .. byte0}, see Sources
    .out(ds_out), .out_r(ds_out_r), .sample(ds_sample)   // out_r / sample optional
);
```

- **Verification**: the core's `verilator/Makefile` builds `obj_dsnd/Vdsnd_engine` from `verify/` with its own
  `-DTICK -DCLK_HZ [-DWAV_CH=1]`; model-only tools include `verify/dsnd_model.h`. Never copy the kit into a core.

2026-11-03: header comments rewritten (history out, model path `verify/dsnd_model.h`); code identical to 11dbdc41
(`codediff.py`), no rebuild needed.

## License

License: BSD-3-Clause (own work, Rodimus). See `LICENSE`.

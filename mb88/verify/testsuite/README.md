# MB88 differential test suite

Exhaustive opcode-level and timer-level verification of `rtl/cpu/mb88_sv/mb88_core.sv`
against MAME's `cpu/mb88xx` core, in the style of `verilator/z8002_testsuite`.

**Bar: MAME parity.** MAME runs Kangaroo and Pole Position correctly, so anything that
matches it architecturally cannot be our bug. This does not claim silicon accuracy —
note MAME's own `#define TIMER_PRESCALE 32 /* guess */` (`mb88xx.cpp:35`).

```bash
make bootstrap && ./bootstrap        # prove the ORACLE first
make suite                           # build the Verilator co-sim
./obj_dir/Vmb88_suite_tb --ctx 8     # full opcode run (2044 tests, ~15 ms)
./obj_dir/Vmb88_suite_tb --timer     # timer / prescaler run
```

Results land in `results/summary.txt` (counts, cycle census, per-opcode failures) and
`results/failures.txt` (sampled diffs with disassembly).

Options: `--ctx N` contexts per opcode, `--seed S`, `--begin/--end` opcode window,
`--maxfail N` sample cap, `--timer` internal timer, `--tc` external TC timer,
`--irq` interrupt entry, `--inject OP` negative control,
`--dbg` per-test trace. Everything derives from `(seed, opcode, ctx)`, so runs are
reproducible and there is no corpus file to maintain.

## Result (2026-08-21, first full run)

| Run | Tests | Architecture | Cycles |
|---|---|---|---|
| `--ctx 8`, opcodes 00–FF | 2044 | **0 fail** | **0 fail** |
| `--timer --ctx 3` | 27 | **0 fail** | n/a |
| `--tc --ctx 2` | 28 | **0 fail** | n/a |
| `--irq` | 5 cases | vectors/priority/gating **match** | **DIVERGE, see below** |

4 tests excluded (a randomised `pio` serial value MAME `fatalerror`s on).

**Cycle census — the RTL is cycle-accurate.** Exactly 19 opcodes charge 2 cycles and
the RTL matches MAME on every one: `3D jpa`, `3E en`, `3F dis`, `60–67 call`,
`68–6F jpl`. Every other opcode is 1/1. This is precisely MAME's `oc++` set
(`mb88xx.cpp:847,854,861,915,930`). ⛔ An earlier session-note claim that
"`mb88_core` retires one instruction per `ce`" is **WRONG** — it uses `S_FETCH2` for
two-byte instructions and charges 2.

**Timer cascade matches** across the 31/32/33 prescaler boundary and out to 4096
machine cycles: TL, TH and the `vf` overflow flag agree with MAME throughout.

## ✅ FIXED: `IRQ-CYCLES-FIX-2026-08-21` (suite-verified, ⬜ NOT yet HW-tested)

Opcodes, the internal timer and the external TC timer all match MAME exactly. Interrupt
ENTRY does not. `--irq` reports it:

| | MAME | `mb88_core.sv` |
|---|---|---|
| When | end of `burn_cycles`, i.e. AFTER the instruction executed | in `S_FETCH`, INSTEAD of executing |
| Pushed return PC | post-instruction (`A009`) | pre-instruction (`A008`) |
| Cost | **4 cycles** (1 insn + `burn_cycles(3)`) | **1 `ce`** |

Vector (`02` ext / `04` timer / `06` serial), the ext-over-timer priority, `pending_irq`
clearing, and the disabled-`pio` gating all MATCH.

**Both are now fixed** in `mb88_core.sv`: the interrupt is taken AFTER the instruction
(so the pushed PC is post-instruction, matching MAME's `GETPC()`), and entry runs through
`S_IRQ1/2/3` for 3 `ce`, so instruction+interrupt costs 4 `ce` = MAME's 1+3. `--irq` now
reports vector / SP push / pending-clear MATCH on all 5 cases with `ce=4` vs `cyc=4`, and
the full opcode, timer and TC runs are unchanged at 0 fail. The original block is left
commented in place, tagged `IRQ-CYCLES-FIX-2026-08-21`, for a one-step revert.

Applied to **both** `Arcade-PolePosition_MiSTer` and `Arcade-Kangaroo_MiSTer` copies and
each validated through this suite (`make suite MB88=<path> MB88DEF=+define+MB88_NO_OWR`
for cores predating the `o_wr` strobe). `Arcade-ChampionBaseball_MiSTer` also has a copy
and was deliberately left alone.

⚠️ Verilator-verified only. A clean Verilator build is **not** evidence it synthesises
under Quartus 17.0.

**The push difference was probably benign**: each model executes the deferred instruction
exactly once overall (MAME before the ISR, RTL after RTI). It only bites if the ISR reads
state that instruction would have changed.

**The cycle difference is not.** MAME's `burn_cycles(3)` feeds `m_TP`, the ÷32 timer
prescaler, so in MAME every interrupt advances the timer by 3 cycles. The RTL charges
nothing. On an MCU driven by timer interrupts that is a systematic drift between code
execution and timer expiry — the shape of "a timed effect expires at the wrong moment".
⛔ UNVERIFIED as the cause of any specific game bug; it is a measured MAME divergence,
nothing more, until a hardware build says otherwise.

## How it works

MAME's `cpu/mb88xx` sources compile **completely unmodified** out of
`Useful Stuff/mame/mb88/` (via the `mame_mb88` symlink, which exists only so make does
not have to cope with the space in "Useful Stuff"). `mame_shim/emu.h` supplies the slice
of MAME framework those files touch. Nothing is transcribed — a hand-copied oracle
would carry hand-copied bugs.

**Reading private state without touching MAME.** Every MB88 member is `private` in
`mb88xx.h`, so unlike the z8002 device a subclass cannot see them. But `device_start()`
calls `save_item(NAME(m_PC))` for *all* of them, and the shim owns both `NAME()` and
`save_item()`. `NAME(x)` is redefined to capture `(name, address, size)`, giving a
complete name→address map of the oracle's architectural state — no `#define private
public`, no ODR violation. `set_icountptr(m_icount)` similarly hands over the cycle
counter, so `step()` runs exactly one instruction and reports the cycles MAME charged.

**Per test** both models start from an identical image: seeded-random program bytes
(with the opcode under test at PA=0/PC=0), 128 seeded-random data nibbles, seeded
registers/flags/stack/timer regs, and seeded K/R/SI port inputs.

**Compared:** PC, PA, A, X, Y, st, zf, cf, vf, sf, if, SI, SP[0..3], TH, TL, SB, pio,
`pending_irq`, `in_irq`, and all 128 data-RAM nibbles — plus cycles, reported as a
SEPARATE verdict so a timing difference is never mistaken for a functional one.

### Two harness hazards worth knowing (both cost real debugging time)

1. **Stale opcode.** The RTL reads its opcode combinationally as `prog[prog_addr]`.
   Verilator does not mark that dirty when the `prog` array is poked from C++, so the
   core executed a *stale* byte on the first edge — it ran `nop` instead of the opcode
   under test, which looks exactly like "the RTL ignored the instruction". Fixed by
   clocking once with `ce=0`, which re-settles combinational logic while the ce-gated
   block does not run, so all poked state survives.
2. **`iflag` is pin-driven.** The core assigns `iflag <= ~irq_n` every clock, so a poked
   value is overwritten on the first edge. The harness drives `irq_n` to match instead.

Both produced *plausible-looking* mass failures. A suite in that state would have
"found" 27 bugs that do not exist.

### Trust the oracle, and trust the suite, before trusting a green run

`./bootstrap` checks the things that would silently corrupt everything downstream: the
`save_item(NAME(...))` map resolving at all, `GETPC() = (PA<<6)+PC` addressing, the
cycle counts `step()` reports (1 for `nop`, 2 for `en`/`call`), and the ÷32 prescaler
(TL still 0 at 31 machine cycles, TL=1 at 32). All pass. If they ever stop, no number
from `Vmb88_suite_tb` means anything.

`--inject OP` is the suite's own negative control: it corrupts one opcode's RTL result
on purpose. `--inject 0x04` must report exactly `--ctx` failures. A suite that cannot
fail proves nothing.

## NOT covered — do not read this as "the MCU is correct"

- **Interrupt EXIT / nesting.** `--irq` covers entry; `rti` and `in_irq` nesting are not
  differentially tested, and `pending_irq` is forced to 0 in the per-opcode run.
- **The serial engine.** MAME drives it from a scheduler timer the shim does not model;
  serial-dependent behaviour is out of scope (and `pio` serial bits are constrained).
- **`mb88.sv`'s own ÷32 prescaler.** Timer mode reproduces its *contract* (one
  `ena_timer` pulse per 32 `ena`) in the harness rather than instantiating `mb88.sv`,
  so an off-by-one inside that counter would not be caught here.
- **Multi-instruction interaction**, and anything above the core: `mb88.sv`,
  `namco_51xx/52xx/53xx/54xx.sv`, and how `ena`/`ena_timer`/`tc_in` are driven at the
  top level.

⇒ A clean run here says the **core** matches MAME. It moves suspicion to the
**wrapper and its clocking**, which is where [[feedback_suspect_my_wrapper_not_shared_core]]
says to look anyway.

## Related

- `verilator/z8002_testsuite/` — the suite this is modelled on
- [[Soft-CPU opcode coverage auditing]]

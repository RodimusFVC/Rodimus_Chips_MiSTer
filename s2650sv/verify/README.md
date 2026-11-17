# s2650sv verification

Everything runs on Linux with Verilator 5.020, GHDL 4.1 (gcc backend, for the yosys plugin), Yosys 0.33 +
yosys-plugin-ghdl, Python 3, g++.

```
apt-get install verilator ghdl ghdl-gcc yosys yosys-plugin-ghdl
```

The reference sources are not copied here (they are the oracle and stay where they are). By default the
scripts look for the fleet copy at `../ref/galaxian/rtl/cpu/s2650` next to this tree (a clone of
`RodimusFVC/Arcade-Galaxian_MiSTer`); set `SGS2650_DIR` otherwise. The MAME comparison needs a MAME checkout
(`MAME_DIR`, default `../ref/mame`; only `src/devices/cpu/s2650/` is used, unmodified).

| Path | What |
|---|---|
| `run_all.sh [quick]` | everything below, logs and `summary.txt` in `results/` |
| `refmodel/convert.sh` | GHDL → Verilog: `ref_a.v` (s2650_cpu, VER_B false), `ref_b_core.v` (sgs2650, VER_B true) |
| `tb/tb_top.sv`, `tb/lockstep.cpp` | lockstep harness: reference and s2650sv on the same inputs, every output every clock, R0-R3 / R1'-R3' / PSL / PSU / IAR / RAS / state every clock |
| `tb/build.sh` | builds `lockstep_{a,b}_m{1,0}`: 2650A / 2650B × return stack in MLAB / registers |
| `tb/lockstep_* random <seed> <cycles>` | random memory (all 256 opcodes), random ack (always, Bernoulli, bursts of waits, periodic), garbage `dr` on wait cycles, irq levels / pulses with random or fixed vectors (incl. indirect), sense toggles, resets at random times incl. mid-instruction |
| `tb/lockstep_* sweep <seeds>` | per opcode × addressing mode (incl. register field) × seeds: prologue that sets both banks, PSL, PSU, then the instruction; one run with irq asserted on each cycle in turn (pulse and level, direct and indirect vector), reset on each cycle, ack stalled 1/2/3 cycles on each access, and with garbage `dr` |
| `tb/lockstep_* prog <bin> <cycles> [ackper]` | runs a program (the exerciser) in lockstep; `DUTBUS=1` lets s2650sv alone drive memory / I/O (judges s2650sv without the reference), `TRACE=1` prints every instruction |
| `tb/mutants.py`, `tb/mutate.sh` | 10 deliberate s2650sv bugs; each must be caught |
| `exerciser/gen_exerciser.py` | generates `exerciser.asm` (self-checking, 480 tests) and `exerciser_quirks.txt` |
| `exerciser/asm2650.py` | small 2650 assembler (Signetics syntax) used for the exerciser |
| `ghdl/run_xcheck.sh` | replays dumped stimulus through the original VHDL in the GHDL simulator, compares every output bit with the converted netlist |
| `formal/bmc.sh [N]` | Yosys SAT miter, gold = GHDL-elaborated s2650_cpu, gate = s2650sv_s2650_cpu, all inputs free each cycle, N clocks from the all-zero power-up state (`RTL=` to try a mutant) |
| `mame/build.sh`, `mame/mamecmp` | MAME `s2650.cpp` (unmodified, compiled against `mame/stub/emu.h`) against the reference, per instruction: IAR, registers, PSL, PSU, RAS, memory and I/O, cycles |
| `synth/synth.sh` | `yosys synth_intel_alm -family cyclonev`: reference vs s2650sv, LUT / FF / MLAB and LUT-level depth (`depth.py`) |
| `lint.sh`, `lint.vlt` | `verilator --lint-only -Wall` on every top / parameter set, four waivers |
| `make_all.sh` | regenerates `rtl/s2650sv_all.sv` |

Exerciser test-bench protocol (extended I/O ports): FE console, FF result (`P` / `F`, also stored at $7FF0),
FD interrupt request with that vector after (last FA) × 4 clocks, held until INTACK, FC sense (bit 0) or
sense = flag output (bit 1). I/O reads return the last value written to the port XOR $5A.

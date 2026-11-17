# t48sv — test report

t48sv is a synthesizable SystemVerilog MCS-48-family core (8035/8039/8040/8048/8049/8050 + 87xx,
UPI-41/41A/42, 8021/8022, and the 8243 expander), derived from Arnim Laeuger's T48 and
cycle-for-cycle identical to the two T48 lineages the MiSTer fleet runs.

## 1. Results at a glance

| check | result |
|---|---|
| Lockstep vs GHDL reference, 25 configurations, every output + 37–48 internal registers every clock, RAM at every instruction boundary | **490 M cycles, 2,450 runs, 16.7 M instructions, all 256 opcodes in every configuration, 0 mismatches** |
| Directed timing sweeps (INT / T1 / T0 / host access moved through every clock of every instruction class) | **379,200 runs, 569 M cycles, 0 mismatches** |
| T48 verification suite, unmodified upstream benches, t48sv co-simulated in GHDL | **815 / 815 runs identical to the T48 reference netlist in the same bench (PASS/FAIL and time of result to the ns)**; vs native 4-state VHDL: identical except 9 runs whose reference PASS depends on X propagation (§7.4) |
| 8243 expander vs unmodified VHDL (GHDL) | **8 M random events, 0 mismatches** (sync and async variants) |
| MAME `mcs48.cpp` (unmodified) instruction-level comparison | 1.2 M instructions per variant (with / without timer); every disagreement classified (§7.6); MCS-48 without timer: only `DA A` differs |
| Mutation test of the harness (8 single-point RTL bugs) | 8 / 8 detected |
| `verilator --lint-only -Wall` | clean on all 25 tops + pool wrapper, with documented waivers (§7.8) |
| Quartus 17 language-rule scan / declare-before-use scan | 0 findings |
| yosys `synth_intel_alm` Cyclone V | **20–32 % fewer ALMs than the reference in every configuration**, worst path equal or one LUT level shorter (§8) |

Decision points for you (§4.2): T48 lineage A and B **disagree on MCS-48 behaviour in two places**.
t48sv implements both (`REV2023`), every top defaults to the lineage it replaces, and nothing in
the fleet changes behaviour; which lineage a *new* MCS-48 instance should default to is your call.

## 2. Deliverables

```
rtl/t48sv_core.sv               attribution header + t48sv_core (all variants, parameterised)
rtl/t48sv_blocks.sv             clock control, ALU, branch, BUS, UPI DBB, data/program memory ctrl, PSW, timer, ports, ADC
rtl/t48sv_decoder.sv            decoder, machine-cycle control, interrupt controller
rtl/t48sv_cores.sv              t48sv_t48_core, t48sv_upi41_core, t48sv_t21_core, t48sv_t22_core, RAM, ROM
rtl/t48sv_t8039_notri_extrom.sv the fleet top (drop-in for t8039_notri_extrom)
rtl/t48sv_system.sv             t48sv_t8039/8048/8049/8050_notri, t8041/8041a/8042ah_notri, t8021/8022_notri, t8050_wb
rtl/t48sv_tri.sv                pin-level tri-state tops t48sv_t8039/8048/8041/8041a/8042ah/8021/8022
rtl/t48sv_t8243.sv              t48sv_t8243_core / _sync_notri / _async_notri / t8243
rtl/t48sv_mcs48_pool.sv         wrapper on chip_pool_pkg::mcs48_i_t / mcs48_o_t (not in t48sv_all.sv)
rtl/t48sv_all.sv                everything above except the pool wrapper, one file for Quartus
rtl/t48sv_lint.vlt, files.f     lint waivers, file list
verify/                         all harnesses and scripts, see verify/README.md
verify/results/                 raw results of every run quoted here
```

Drop-in names (same ports and generics as the VHDL, `t48sv_` prefix): `t48sv_t8039_notri_extrom`,
`t48sv_t48_core`, `t48sv_upi41_core`, `t48sv_t21_core`, `t48sv_t22_core`, all `system/` tops
(`t48sv_t8021[_notri]`, `t8022`, `t8039`, `t8041`, `t8041a`, `t8042ah`, `t8048`, `t8050_wb`), and
the `t8243` set. Extra parameters (all defaulted): `REV2023`, `RAMSTYLE`, `ROM_INIT_FILE`,
`UPI_IBF_ACK`. Additional convenience tops `t48sv_t8049_notri` / `t48sv_t8050_notri` (2K/128 B,
4K/256 B) have no T48 counterpart; the 8040 is `t48sv_t8039_notri_extrom` with `ram_addr_width_g = 8`.

Fleet swap: rename `t8039_notri_extrom` → `t48sv_t8039_notri_extrom`, `t48_core` → `t48sv_t48_core`,
`upi41_core` → `t48sv_upi41_core`, add `t48sv_all.sv`, drop the VHDL. No port or generic changes.

## 3. Reference sources

All clones read-only; no commits, pushes or PRs.

| item | md5 | status |
|---|---|---|
| A `t48_core.vhd` (Galaxian `rtl/cpu/i8039`, `$Id ... 295 2009-04-01`) | 0e07bc408e697ed4661d34d75ced7eb0 | ✓ |
| A `t8039_notri.vhd` | 42cd692b64e2d8c8980c9df985e5c66a | ✓ |
| A `t8039_notri_extrom.vhd` | 380e66829a73c00f7cd787641fd380da | ✓ |
| A, concatenation of all `*.vhd` | 872667bcef91bef26c95596fdba51b33 | ✓ **only in en_US glob order** (`alu_pack-p.vhd` before `alu.vhd`); C-locale order gives 72561f0e… |
| A identical in Nintendo, Konami82 (`rtl/cpu/i8039`), SegaG80 (`rtl/sound/i8039`) | same concat | ✓ |
| B `t48_core.vhd` (DECOCassette `rtl/cpu/T48`) | 804788adff8492ec50d6cb8292219be4 | ✓ |
| B `upi41_core.vhd` | 2a431df82cd16cf4572e7ab937e4add7 | ✓ |
| B `upi41_db_bus.vhd` (DECO-modified, see §4) | 38a9936f59cb4d06ceb02a2483133780 | recorded |

The DECO repository is **`RodimusFVC/Arcade-DECOCassette_MiSTer`** (underscore); the hyphenated
name in the brief does not exist.

Fleet instantiations read: Nintendo / Galaxian / Konami82 `t8039_notri_extrom #(0, 7)`, SegaG80
`#(0, 6)` plus `rtl/sound/usb/i8035.v` (`t48_core` defaults, external 64 B `spram`, `xtal3_o` →
`en_clk_i`, `pmem_data_i = 0`, EA from the bus), DECO `rtl/mcu/i8041_top.v` (`upi41_core`,
`clk_sys` + `ce_hclk`, 128 B external RAM, uses the DECO `sts_o` port). Note: `i8041_top.v`
passes **no generics**, so DECO runs `is_upi_type_a_g = 1` (UPI-41A: EN DMA / EN FLAGS /
MOV STS) although its comment says 0. t48sv reproduces what actually runs.

## 4. Lineage A / B / upstream

Upstream is `github.com/devsaurus/t48` (OpenCores T48 continued by Laeuger), release 1.4,
HEAD 837bd24 (2025-10-05).

* **A = upstream 013d615** (2009-04-01, SVN r295) exactly, modulo `$Id$` expansion
  (every core file diffs to zero against that commit).
* **B = upstream HEAD** for every file except two DECO edits:
  `upi41_core.vhd` (adds `sts_o`, the status register exported) and `upi41_db_bus.vhd`
  (adds `sts_o`, and `IN A,DBB` also releases the IBF interrupt request — "IBF-INT-ACK-FIX").
  t48sv implements the DECO behaviour; `UPI_IBF_ACK = 0` gives stock upstream.
* Upstream after B: only CI and test-cell commits (e.g. 2854c71 "clear carry" in a test).

### 4.1 What changed A → B (upstream d202458 "merge wip_t2x", 2023-01)

| change | kind |
|---|---|
| UPI-41/41A/42 (`upi41_core`, `upi41_db_bus`, decoder `MN_IN_DBB` … `MN_MOV_STS`, `JNIBF`/`JOBF`, F1 set/clear by host) | new function |
| 8021 / 8022 (`t21_core`, `t22_core`, `adc.vhd`, P0, `RAD`, `SEL ANx`, `RETI`, MCS-2x CALL/RET PC handling) | new function |
| decoder split into per-variant decode functions; `RET`/`RETR` become separate mnemonics | refactor (equivalent) |
| **interrupt latch: INT sampled on ALE rising edge instead of falling edge** (`int.vhd`) | **MCS-48 behaviour change** |
| **RET/RETR: program-memory address reload moved from M2 to M3 of the second cycle** | **MCS-48 behaviour change** |
| `bus_mux` default port values, `cond_branch` IBF/OBF, `t48_core` To_X01Z via signals, component packages → entity instantiation, VHDL-93 migration | cosmetic |
| `system/t8050_wb.vhd` still references packages and `syn_rom`/`syn_ram` declarations upstream deleted in 2006 (d8b9bc9) and 2023 (aa812fe) — **does not elaborate in A, B or upstream** | upstream bug |

### 4.2 Measured A vs B difference (reference vs reference, same lockstep harness)

`build.sh A_core --left B_core`, 20 random runs: every run diverges. Pins only, INT disabled:
only `pmem_addr_o` differs; with INT: the INT latch and then everything downstream.

1. **RET / RETR**: A presents the return address on `pmem_addr_o` in M2 of the second cycle,
   B one machine state (3 XTAL clocks) later in M3. The next opcode fetch is identical, so code
   executes identically, but the external program-ROM address pin differs for one state. The
   fleet's external-ROM cores (Nintendo, Galaxian, Konami82, SegaG80) feed `pmem_addr_o` to a
   BRAM, so this is visible on that bus.
2. **INT sampling**: A latches INT at ALE's falling edge (M4, XTAL phase 2) of the last cycle,
   B at ALE's rising edge (M3, XTAL phase 3), i.e. 2 XTAL clocks earlier. An INT edge inside that
   window is taken one instruction later on A than on B. Consequence for the test suite: the
   2023-retimed upstream cells `white_box/int_on_call` and `int_on_jmp` **fail on A** (natively
   in GHDL, and identically on t48sv `REV2023=0`), pass on B.

Per the brief I did not pick a winner: `REV2023` selects; `t48sv_t8039_notri_extrom`,
`t48sv_t48_core` and the pool wrapper default to A (fleet), the B system tops default to B,
UPI-41 / 8021 / 8022 exist only in B. **Your call:** which default the B-derived MCS-48 tops
(`t48sv_t8039_notri`, `t48sv_t8048_notri`, `t48sv_t8050_wb`, …) should carry for new cores.

## 5. Architecture and design decisions

* **Faithful structure, not a re-imagined core.** T48 has pin-visible micro-quirks a clean
  redesign would lose: the mnemonic register lags the opcode by one state (M2 still decodes
  the previous instruction, e.g. MOVX keeps `bidir_bus` asserted), the internal data bus is an
  AND of every unit's output so simultaneous readers merge (PSW+PCH stack byte), `db_dir`
  stays set after `OUTL BUS` until MOVX/EA, P2 low-impedance flags are delayed through an XTAL
  register, etc. t48sv keeps T48's register set and phase timing; the combinational logic is
  rewritten (flat 256-entry decode table, simplified datapath).
* **One core, four variants**: `t48sv_core #(VARIANT, UPI_TYPE_A, REV2023, …)`; all variant
  differences are `generate`/constant conditions, verified to vanish (no UPI/8021/8022 net
  survives synthesis of the fleet configurations).
* **Clocks / reset**: exactly as T48 — `clk_i` and `xtal_i` domains with clock enables (fleet:
  same net), asynchronous active-low reset on the same registers T48 resets, registers T48
  leaves un-reset (RAM, 8022 sample & hold) left un-reset.
* **Don't-care resolution**: where T48 drives `'-'` (decoder `data_s` in MOVD M4, unselected
  8243 P2 / port data), t48sv drives 0, which is what GHDL synthesis picks; on the 8243 these
  bits are masked in the comparison and only ever reach a pin while that pin is not enabled.
* **Area optimisations (all lockstep-verified)**: flat opcode table (Verilator also choked on
  chained decode functions, 94 MB of C++); adder operand / carry-in selection decoded from the
  mnemonic only (observed only in states where the result is consumed — removes one LUT level
  in front of the carry chain); data RAM without HDL init so it maps to MLAB. Tried and rejected
  (measured, no reliable depth gain, more area): one-hot machine state, one-hot mnemonic.
* **Data RAM**: `t48sv_ram` with `ramstyle = "MLAB, no_rw_check"`. `no_rw_check` is safe:
  `en_clk` pulses are ≥ 3 XTAL clocks apart and the RAM address register reloads on every
  clock, so the core never observes same-edge read-during-write. Cost: 128 B = 32 MLAB 32×1
  slices = 4 LABs (40 ALM positions); 64 B = 2 LABs; 256 B = 8 LABs. Registers instead would cost
  ~1,000 FFs + read mux (measured: 1,192 FFs, +~400 ALMs for 128 B). `RAMSTYLE = "M10K"` or
  `"logic"` selects the alternatives. The fleet's VHDL `generic_ram_ena` has a zero
  initialiser, so today's Quartus builds most likely put it in an M10K — t48sv frees that block.
* **ROM** (internal-ROM tops): `t48sv_rom #(INIT_FILE)` loaded with `$readmemh`; registered
  address like the T48 LPM ROM.
* **Package-free, Quartus-17-safe SV**: no packages / imports (yosys 0.33 cannot parse in-module
  imports; Quartus 17 header-import support is uncertain), untyped string parameters, genvars at
  module scope, no casts, no keyed assignment patterns, struct outputs of the pool wrapper driven
  field by field through plain wires.
* **Not implemented: `extra/upi41_db_bus_async.vhd`** — an experimental variant clocked by
  RD/WR, instantiated by no top, and incompatible with the one-clock rule.

## 6. Fleet behaviour notes (T48 ≠ silicon; t48sv matches T48 on purpose)

Found by the MAME comparison and the suite analysis; all reproduced bit-exactly by t48sv:

1. **`DA A` ignores the incoming carry** (and the carry out of the low-nibble adjust): it adds
   0x60 only when the high nibble > 9 and otherwise clears CY. Intel/MAME also adjust when CY=1.
   BCD arithmetic after an ADD that carried gives a different result on T48.
2. **BUS stays driven after `OUTL BUS` / `ANL/ORL BUS`** until MOVX or EA; a following `INS A,BUS`
   fights an external driver (a real 8048 floats BUS during RD).
3. **Timer**: `MOV A,T` reads 0x00 after 31 NOPs following `STRT T` with T=0xFF (0xFF after 30);
   MAME's source quotes a real-8048 measurement of 0xFF after 31 / 0x00 after 32. The IRQ variant
   of that measurement gives A=0x20 on T48 and MAME, 0x22 on real hardware.
4. **8021/8022 `CALL` pushes the address of the CALL's second byte** and RET increments it;
   the stack image in RAM is one lower than Intel's.
5. **8021 `IN A,P2`** returns 0 in the upper nibble (4-pin P2).
6. **8022**: external interrupt is T0 low (zero-cross input); `RETI` does not restore PSW.

## 7. Verification

### 7.1 Reference models

`verify/ref/build_refs.py` analyses each lineage with GHDL 4.1 and synthesises every top in every
used generic setting to Verilog (`ghdl synth --out=verilog`), prefixing module names so that
several models link into one Verilator build: 36 configurations (A fleet tops incl. 8040 and the
`t48_core` generic corners `xtal_div_3_g=0`, `register_mnemonic_g=0`, `sample_t1_state_g=3`,
all `include_*_g=0`; B `t48_core`, `upi41_core` (A and non-A), `t21/t22_core`, every
`system/*_notri` in both `gate_port_input_g` values, `t8050_wb`; upstream r295 system tops).
Harness-only VHDL: black-box architectures for the integrator-supplied `t48_rom`/`t49_rom`/`syn_rom`,
`syn_ram` = T48's own `generic_ram_ena` (LPM semantics identical), and the upstream package files
`t8050_wb` needs (restored from upstream history, provenance in `ref/vhdl/recovered/`).
GHDL synthesis cannot elaborate the 8243 core (`clock-level is not a constant`), so the 8243
oracle is GHDL *simulation* of the unmodified VHDL (§7.5).

### 7.2 Lockstep (`verify/tb`)

Per configuration a generated top instantiates the reference netlist and the t48sv drop-in with
shared inputs; the C++ driver compares **every output after both clock edges** and 37–48 internal
registers (A, shadow, temp, PC, program-address latch, PSW, SP, F1, MB, opcode, branch / IRQ /
timer / prescaler / counter / T1-sample / BUS / port / UPI DBB / ADC state, machine state,
XTAL divider) every clock, and the whole data RAM at every instruction boundary.
Stimulus per run (random mode per run): XTAL_EN always / random p / periodic 1-in-N / bursts;
asynchronous resets at random points mid-instruction; INT random toggles / long low / off; T0, T1
random edges (slow and fast, counter mode); random port inputs; program ROM random bytes or
structured random code (vectors, CALL/RET, mode-setting instructions) with registered (BRAM) or
combinational fetch; EA low / high / switching with an external program + MOVX memory model
driven from ALE/PSEN/RD/WR; BUS noise; UPI host reads/writes with random A0, lengths and chaos
mode; 8022 analog inputs; Wishbone ACK delays.
Mutation check: 8 single-point bugs (prescaler compare, DA threshold, P2 low-impedance logic,
INT edge, RET state, mnemonic lag, BUS direction register, T1 sample state) — all detected.

| configuration | cycles | runs | instructions | opcodes | INTs taken | async resets | timer ovf | counter incs | MOVX writes | XTAL_EN gaps | host rd/wr | mismatches |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| A_core | 50M | 250 | 1629051 | 256/256 | 67844 | 4776 | 935 | 69785 | 11517 | 14.5M | 0/0 | 0 |
| A_core_m0 | 10M | 50 | 350518 | 256/256 | 6944 | 679 | 406 | 15131 | 2063 | 2.4M | 0/0 | 0 |
| A_core_min | 10M | 50 | 371793 | 256/256 | 11116 | 679 | 0 | 0 | 1469 | 2.4M | 0/0 | 0 |
| A_core_t3 | 10M | 50 | 350304 | 256/256 | 6948 | 679 | 407 | 14752 | 2051 | 2.4M | 0/0 | 0 |
| A_core_x0 | 10M | 50 | 1049372 | 256/256 | 26976 | 679 | 151 | 25628 | 7282 | 2.4M | 0/0 | 0 |
| A_extrom_g0_r6 | 50M | 250 | 1629858 | 256/256 | 67128 | 4776 | 868 | 68007 | 12624 | 14.5M | 0/0 | 0 |
| A_extrom_g0_r7 | 50M | 250 | 1627369 | 256/256 | 67627 | 4776 | 953 | 68512 | 12127 | 14.5M | 0/0 | 0 |
| A_extrom_g0_r8 | 50M | 250 | 1629051 | 256/256 | 67844 | 4776 | 935 | 69785 | 11517 | 14.5M | 0/0 | 0 |
| A_extrom_g1_r6 | 10M | 50 | 350489 | 256/256 | 6237 | 679 | 353 | 14998 | 2667 | 2.4M | 0/0 | 0 |
| A_extrom_g1_r7 | 50M | 250 | 1629467 | 256/256 | 67510 | 4776 | 906 | 65686 | 12360 | 14.5M | 0/0 | 0 |
| A_t8039_notri | 10M | 50 | 368054 | 256/256 | 13191 | 1067 | 156 | 15247 | 1987 | 2.4M | 0/0 | 0 |
| B_core | 10M | 50 | 348465 | 256/256 | 9136 | 679 | 350 | 14833 | 1759 | 2.4M | 0/0 | 0 |
| B_t21_core | 10M | 50 | 203999 | 256/256 | 0 | 940 | 239 | 11125 | 0 | 2.1M | 0/0 | 0 |
| B_t22_core | 10M | 50 | 195908 | 256/256 | 8970 | 763 | 146 | 12029 | 0 | 2.1M | 0/0 | 0 |
| B_t8021_notri | 10M | 50 | 202245 | 256/256 | 0 | 940 | 258 | 14468 | 0 | 2.1M | 0/0 | 0 |
| B_t8022_notri | 10M | 50 | 150824 | 256/256 | 7356 | 832 | 237 | 9544 | 0 | 3.8M | 0/0 | 0 |
| B_t8039_notri | 10M | 50 | 367575 | 256/256 | 14845 | 1067 | 156 | 15263 | 2018 | 2.4M | 0/0 | 0 |
| B_t8041_notri | 10M | 50 | 335327 | 256/256 | 15761 | 1164 | 183 | 20277 | 0 | 2.8M | 178616/179039 | 0 |
| B_t8041a_notri | 10M | 50 | 333914 | 256/256 | 16097 | 1164 | 172 | 19091 | 0 | 2.8M | 178616/179039 | 0 |
| B_t8042ah_notri | 10M | 50 | 333212 | 256/256 | 15564 | 1164 | 162 | 14891 | 0 | 2.8M | 178616/179039 | 0 |
| B_t8048_notri | 10M | 50 | 346089 | 256/256 | 8460 | 679 | 498 | 16385 | 2496 | 2.4M | 0/0 | 0 |
| B_t8048_notri_g0 | 10M | 50 | 345914 | 256/256 | 8479 | 679 | 509 | 16132 | 1771 | 2.4M | 0/0 | 0 |
| B_t8050_wb | 10M | 50 | 492956 | 256/256 | 11845 | 1058 | 174 | 28113 | 0 | 3.4M | 0/0 | 0 |
| B_upi41_core | 50M | 250 | 1753671 | 256/256 | 109660 | 5397 | 1354 | 107916 | 0 | 12.2M | 838085/839961 | 0 |
| B_upi41_core_a0 | 10M | 50 | 333119 | 256/256 | 16481 | 1164 | 175 | 17696 | 0 | 2.8M | 178616/179039 | 0 |
| **total** | **490M** | 2450 | 16728544 | | 652019 | 46032 | 10683 | 745294 | 85708 | | | **0** |

### 7.3 Directed timing sweeps

Programs (`verify/sweeps/*.asm`) loop one instruction class each: 1-cycle ALU/register ops,
2-cycle immediates and port/BUS ops, MOVX, MOVP/MOVP3, JMPP, all conditional jumps (taken and
not) + DJNZ, CALL/RET/RETR incl. bank 1, timer/counter start/stop/MOV T/JTF/EN-DIS TCNTI,
8243/PSW/ENT0/SEL MB; UPI: JNIBF/JOBF/IN-OUT DBB/MOV STS/EN FLAGS, EN DMA + DRQ; 8022: SEL AN/RAD/P0/
JT0 + T0 interrupt; 8021. For each clock offset k = 0…599 after reset (covers set-up plus at least
one full loop, i.e. every state of every instruction) a run asserts INT for 40–79 clocks, drops T1
(counter preloaded 0xFF → overflow → timer IRQ), raises T1 again (classes 2–3), toggles T0; UPI
runs place a host write at k and a read at k+60; class 3 also runs XTAL_EN every 2nd clock.

| configuration | sweep runs | cycles | INTs taken | timer ovf | mismatches |
|---|---:|---:|---:|---:|---:|
| A_core | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_core_m0 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_core_min | 21600 | 32.4M | 17967 | 0 | 0 |
| A_core_t3 | 21600 | 32.4M | 27283 | 46446 | 0 |
| A_core_x0 | 21600 | 32.4M | 65026 | 23108 | 0 |
| A_extrom_g0_r6 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_extrom_g0_r7 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_extrom_g0_r8 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_extrom_g1_r6 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_extrom_g1_r7 | 21600 | 32.4M | 26614 | 48372 | 0 |
| A_t8039_notri | 21600 | 32.4M | 26614 | 48372 | 0 |
| B_core | 21600 | 32.4M | 28585 | 48372 | 0 |
| B_t21_core | 2400 | 3.6M | 0 | 8844 | 0 |
| B_t22_core | 2400 | 3.6M | 4053 | 8844 | 0 |
| B_t8021_notri | 2400 | 3.6M | 0 | 8844 | 0 |
| B_t8022_notri | 2400 | 3.6M | 4053 | 8844 | 0 |
| B_t8039_notri | 21600 | 32.4M | 28585 | 48372 | 0 |
| B_t8041_notri | 4800 | 7.2M | 4242 | 6939 | 0 |
| B_t8041a_notri | 4800 | 7.2M | 4242 | 6939 | 0 |
| B_t8042ah_notri | 4800 | 7.2M | 4242 | 6939 | 0 |
| B_t8048_notri | 21600 | 32.4M | 28585 | 48372 | 0 |
| B_t8048_notri_g0 | 21600 | 32.4M | 28585 | 48372 | 0 |
| B_t8050_wb | 21600 | 32.4M | 35792 | 48624 | 0 |
| B_upi41_core | 4800 | 7.2M | 4242 | 6939 | 0 |
| B_upi41_core_a0 | 4800 | 7.2M | 4242 | 6939 | 0 |
| **total** | **379200** | **569M** | 502636 | 768713 | **0** |

### 7.4 T48 verification suite (`sw/verif`, 101 cells)

* **Assembler**: the cells need Alfred Arnold's AS. Building it was blocked in this session
  (sandbox policy on compiling downloaded code), so `verify/asm/t48asm.py` implements the AS
  subset the cells use (macros with per-expansion local labels, EQU/ORG/ALIGN/DB, `$`, `#` modulo,
  CPU-specific mnemonics) including AS's **implicit `SEL MB0/MB1` before a cross-bank JMP/CALL**
  (read from AS's `code48.c`; four white-box cells depend on it). Validation: the unmodified
  reference passes every cell natively (below), which wrong encodings would not survive.
* **Native reference** (GHDL-LLVM simulation of the unmodified upstream benches and RTL; mcode
  traps a `time` overflow in `if_timing.vhd`, upstream CI uses LLVM too):
  B (DECO RTL + upstream HEAD bench/cells, 8 benches incl. 8243 and UPI host stimulus):
  **556/556 PASS**; A (upstream r295 snapshot with its own 2009 bench/cells, gen/t8048/t8039):
  **259/259 PASS**; A with today's cells: 252/258 (the 2 retimed INT cells, §4.2).
* **t48sv**: GHDL+Verilator co-simulation (`verify/cosim`). The upstream benches and tri-state
  wrappers run unmodified; only `t48_core` and the `*_notri` / 8243 notri entities are replaced
  by VHDL shims (reference entity declarations copied verbatim) that evaluate the Verilated
  t48sv model through VHPIDIRECT on every input event and drive the bench's
  `tb_accu_s`/`tb_istrobe_s`. The same shims host the GHDL reference *netlist* (`--ref`), giving a
  2-state reference in the same bench.

| run set | t48sv == reference netlist in same bench | t48sv == native VHDL |
|---|---|---|
| B, 556 runs | **556 / 556** (result and time) | 550 / 556 |
| A r295, 259 runs | **259 / 259** | 250 / 259 |
| A r295 with today's cells, 258 runs | 258 / 258 | 252 / 258 |

The native-only differences are `anl/bus`, `orl/bus`, `ins` (gen/t48/t39 benches) and `movd`
(8243 bench): §6 item 2 — the core still drives BUS after `OUTL BUS` when `INS` strobes RD, the
bench's external RAM drives too, GHDL resolves `'X'`, and the cell reaches PASS only through X
propagation (`movd`: the 8243 and P2 both drive). A 2-state model cannot represent that; the
2-state T48 netlist fails those runs at exactly the same time as t48sv.

### 7.5 8243

`verify/cosim/tb_8243_cmp.vhd` drives the unmodified `t8243_sync_notri` / `t8243_async_notri`
and t48sv with the same random PROG / CS / P2 / port / reset stimulus (clock edges and data
changes in separate deltas, as in a real system), comparing every output after every event:
5 seeds × 800,001 events × 2 variants, **0 mismatches**; only bits T48 itself drives as `'-'`
are masked. The co-simulated suite additionally ran the `io_exp` cells (`anld`, `movd`, `orld`) through t48sv's 8243
in `tb_t8243` / `tb_t8048_t8243`.

### 7.6 MAME `mcs48.cpp`

MAME master `src/devices/cpu/mcs48/mcs48.cpp` (md5 ab130ef80ff87aaf1b757da686a06ed1) is compiled
**unmodified** against a minimal `emu.h` stand-in (`verify/mame/shim`), run side by side with
Verilated t48sv on the same program and static inputs; after every instruction A, PC, PSW, SP,
F1, MB, timer, timer/IRQ flags, port latches, RAM and machine-cycle count are compared; on a
difference MAME is resynchronised from t48sv and the (opcode, field) is tallied.
Quasi-bidirectional reads use `pin & latch` on both sides (MAME's model = T48
`gate_port_input_g = 1`). External INT is held inactive (MAME's instruction-level IRQ model with
its JNI hack is not comparable at clock level; the timer IRQ is compared).
600,000 instructions per variant and mode, 254–256 opcodes each:

| variant (MAME device) | disagreements (no timer) | cause |
|---|---|---|
| MCS-48 (i8039), REV2023 0 and 1 | `57 DA A`: A, CY | §6 item 1 |
| UPI-41 (i8041ah) | `DA A`; P26 pin after `EN DMA` | MAME does not model DRQ on P26 |
| | `OUTL/ANL/ORL P2` latch after `EN DMA` | MAME's `p2_mask()` protects P26/P27 latch bits, T48 writes them |
| | `IN A,P2` bit 6 after `EN DMA` | T48 reads back DRQ on P26 |
| 8021 (i8021) | `CALL` stack bytes, `RET` PC | §6 item 4 |
| | `IN A,P2` upper nibble | §6 item 5 |
| | `76`: MAME executes `JNC` (2 cycles), T48 `NOP` | MAME's 8021/8022 opcode tables map 0x76 to `jnc`; the 8021/22 have no JF1 — likely a MAME table error |
| | `DA A` | §6 item 1 |
| 8022 (i8022) | as 8021, plus `80 RAD` (illegal in MAME), `93 RETI` (MAME = RETR, restores PSW), `SEL AN0/1` (illegal in MAME), T0 interrupt (not modelled by MAME) | MAME TODO lists the 8022 opcodes as missing |

With the timer running, the remaining differences are the timer register at instruction
boundaries (T48 increments inside the instruction at M4, MAME after it) and, as a consequence,
timer interrupts taken one instruction apart; `MOV A,T` reads agree in the directed test
(§6 item 3). Fleet configurations follow T48.

### 7.7 Public exercisers

None found: the SingleStepTests organisation (22 CPU suites) has no MCS-48 / UPI / 8021 set, nor
does any other public source I could locate. Upstream T48 also ships `sw/i8039emu`, a 1997
MAME-ancestor 8039 core — not independent of §7.6, so not used.

### 7.8 Lint

`verilator --lint-only -Wall rtl/t48sv_lint.vlt …` → 0 warnings on every top (split files and
`t48sv_all.sv`) and on the pool wrapper against the fleet's real `chip_pool_pkg`. Waivers
(`t48sv_lint.vlt`): DECLFILENAME (several modules per file), PINCONNECTEMPTY (outputs a variant
does not use), UNUSEDSIGNAL in variant-shared modules (ports / control lines unused by a variant,
harness taps; PSW ignores data bit 3 as in T48; RAM/ROM use low address bits), UNUSEDPARAM
`RAMSTYLE` (consumed by the synthesis attribute only), SYNCASYNCNET in the 8243 (CS is an
asynchronous preset in T48). `verify/lint/q17_check.py` (Quartus 17 rule scan) and
`declare_before_use.py`: 0 findings.

## 8. Synthesis (yosys 0.33 `synth_intel_alm -family cyclonev -noiopad -nobram`)

Same flow for reference netlist and t48sv. yosys-abc 0.33 asserts in `&mfs`, so ABC9 runs
`-fast` for both. "ALM est" = 6-LUTs + ⌈(smaller LUTs + arith/2)/2⌉ (pairs into fracturable ALMs);
levels = LUT levels on the worst register-to-register path from the netlist; ns = rough
Cyclone V −7 estimate (0.55 ns/level + 0.05 ns/carry bit + 0.5 ns). Quartus numbers will differ;
the comparison is like for like.

| configuration | fleet use | ref LUTs | ref FFs | ref MLAB | ref ALM est | ref levels | t48sv LUTs | t48sv FFs | t48sv MLAB | t48sv ALM est | t48sv levels | ALM saving |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fleet_8039_extrom | Nintendo / Galaxian / Konami82 | 1122 | 171 | 32 | 642 | 14 (8.2 ns) | 896 | 168 | 32 | 513 | 14 (8.2 ns) | 20 % |
| fleet_8035_extrom | SegaG80 speech | 1109 | 169 | 16 | 635 | 14 (8.2 ns) | 896 | 166 | 16 | 504 | 14 (8.2 ns) | 21 % |
| fleet_t48_core | SegaG80 USB (i8035.v) | 1100 | 166 | 0 | 637 | 14 (8.2 ns) | 885 | 163 | 0 | 499 | 14 (8.2 ns) | 22 % |
| fleet_upi41_core | DECOCassette (i8041_top.v) | 1231 | 185 | 0 | 729 | 15 (8.8 ns) | 870 | 182 | 0 | 494 | 14 (8.2 ns) | 32 % |
| extrom_8040 | - | 1161 | 173 | 64 | 666 | 14 (8.2 ns) | 930 | 170 | 64 | 528 | 14 (8.2 ns) | 21 % |
| B_t48_core | - | 1220 | 166 | 0 | 739 | 15 (8.8 ns) | 885 | 163 | 0 | 499 | 14 (8.2 ns) | 32 % |
| B_t8039_notri | - | 1245 | 171 | 32 | 735 | 14 (8.2 ns) | 898 | 168 | 32 | 514 | 14 (8.2 ns) | 30 % |
| B_upi41_core_a0 | - | 1187 | 174 | 0 | 711 | 15 (8.8 ns) | 858 | 171 | 0 | 489 | 14 (8.2 ns) | 31 % |
| B_t21_core | - | 842 | 132 | 0 | 487 | 15 (8.8 ns) | 687 | 129 | 0 | 378 | 14 (8.2 ns) | 22 % |
| B_t22_core | - | 1028 | 176 | 0 | 602 | 14 (8.2 ns) | 797 | 168 | 0 | 441 | 14 (8.2 ns) | 27 % |
| A_core_min | - | 949 | 104 | 0 | 557 | 14 (8.2 ns) | 736 | 102 | 0 | 426 | 12 (7.2 ns) | 24 % |

* Register count is identical before mapping (fleet `t48_core`: 163 flip-flops in both,
  register for register); the 2–8 FF difference in the mapped netlists comes from yosys's
  flop legalisation / ABC mapping of the two netlists, not from the designs.
* The ALU-adder change (§5) took the fleet 8039 top from 15 to 14 levels at equal area; the
  worst path is register → decoder → 9-bit adder → op mux → internal AND bus → data-memory
  address mux → RAM address register, the same chain as in T48.
* No M10K, no DSP in any configuration. Fleet configurations contain no UPI / 8021 / 8022
  logic (checked by net name in the synthesised netlist).

## 9. Not done / limits

* **Quartus 17.0 compile and timing, hardware tests** — not available here (next session).
  The yosys numbers are relative estimates.
* **AS assembler** not built (sandbox refused compiling the downloaded source); replaced by
  `t48asm.py` (§7.4), validated by 815 native reference PASSes.
* **Tri-state tops** (`rtl/t48sv_tri.sv`) are verified by lint and review only; the suite ran
  the *upstream* VHDL tri-state wrappers around t48sv's notri cores. They are one assignment per
  pin, mirroring `port_bidir_f`.
* **9 suite runs** pass on the reference only through 4-state X propagation (§7.4); not a
  t48sv difference (the 2-state reference behaves identically).
* **External INT vs MAME** not compared at instruction level (different interrupt models); INT
  timing is covered by the clock-level lockstep and sweeps against T48.
* **`upi41_db_bus_async`** not implemented (§5). **`t8050_wb`** reference needed upstream files
  restored from history (§4.1).
* t48sv inherits every T48 deviation from silicon (§6) — by design.

## 10. Rerunning

See `verify/README.md`.

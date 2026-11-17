# crtc6845sv verification

Tools used: Verilator 5.020, GHDL 4.1.0 (mcode, `--synth --out=verilog`), Yosys 0.33, g++ 13 (Ubuntu 24.04 packages:
`apt-get install verilator ghdl yosys`).

## Reference models (`ref/`)
`mc6845_fixed.vhd` (md5 bab5f31f9ef3f5ff702cb586a5e8c714 before the entity rename) and `mc6845_stock.vhd`
(md5 e1c74cb714f3ae0431314e6047e9b426) with the entity renamed to `mc6845_fixed` / `mc6845_stock`, and their GHDL
conversions `*_ghdl.v`. To regenerate from the originals:

```bash
cp <Arcade-Universal_MiSTer>/rtl/video/mc6845.vhd ref/mc6845_fixed.vhd && sed -i 's/\bmc6845\b/mc6845_fixed/g' ref/mc6845_fixed.vhd
cp <BBCMicro_MiSTer>/rtl/mc6845.vhd ref/mc6845_stock.vhd && sed -i 's/\bmc6845\b/mc6845_stock/g' ref/mc6845_stock.vhd
cd ref && for v in fixed stock; do mkdir -p w_$v; ghdl -a --std=08 --workdir=w_$v mc6845_$v.vhd && ghdl --synth --std=08 --workdir=w_$v --out=verilog mc6845_$v > mc6845_${v}_ghdl.v; done
```

## 1. Lockstep (default variant, cycle-exact)
`tb/tb_lockstep.sv` runs the drop-in `crtc6845sv_mc6845`, the fixed and the stock reference on the same pins;
`tb/lockstep_main.cpp` compares all outputs (DO, MA, RA, VSYNC, HSYNC, VBLANK, HBLANK, DE, CURSOR) after both clock
phases of every CLOCK and classifies every stock-vs-fixed difference. Stimulus: `tb/stim.h` (directed edge tables
first, then random episodes: 5 register profiles, mid-frame rewrites of R0-R15 and R16-R31, reads of all 32 indices
and the status port, light-pen toggles, 6 CLKEN patterns, ENABLE held 1-4 clocks, bus noise, mid-frame resets).

```bash
./build_lockstep.sh
./build/lockstep/lockstep <seed> <cycles>        # exit 1 on any dut/fixed mismatch or out-of-class stock difference
./run_lockstep.sh 16 60000000                    # the report's run: 16 seeds x 60M CLOCKs
```

## 2. Formal equivalence (variant logic folds away)
`equiv/equiv.ys`: Yosys `equiv_make` / `equiv_simple -seq 5` / `equiv_induct` of `crtc6845sv` at VARIANT = 0 against
`equiv/crtc6845sv_v1.sv` (the pre-variant core that passed the lockstep). `cd equiv && yosys equiv.ys`.

## 3. Fleet scenarios
`tb/fleet_main.cpp` replays the fleet games' CRTC tables (write order, character clock divider, ENABLE hold, Yo-Yo
per-frame R12/R13 rewrites incl. cocktail flip, TMS-board read-backs, board-switch resets) through the lockstep model.

```bash
./build_fleet.sh && ./build/fleet/fleet
```

## 4. MAME frame-level oracle (all variants)
`mame/mame6845.h` is a character-clock transliteration of MAME `mc6845.cpp` (md5 aaaff6e62887123c9a8c5de1a30b6682)
with "knobs": each replaces one MAME behaviour by the crtc6845sv choice. `tb/variant_main.cpp` runs all eight
variants (`tb/tb_variants.sv`) against their MAME types with (a) the full knob set (must be 0 mismatches on MA, RA,
DE, HSYNC, VSYNC, CURSOR, the update strobe and every register / status read) and (b) each knob reverted alone (the
size and signature of that documented difference).

```bash
./build_variants.sh
./build/variants/variants <seed> <n_random_tables>          # directed tables + n random stable tables
./build/variants/variants 99 0 tb/fleet_tables.txt          # fleet games' tables
./run_variants.sh 4 400 && python3 summarize_variants.py results/variants_seed*.log
```

## 5. C128 VDC (MOS 8563 / 8568) vs MAME mos8563
`mame/mame8563.h` transliterates MAME `mos8563.cpp` (md5 ed1577f0ebf9ac2759c9e116b05ea417) on the mc6845 base model,
with documentation knobs (C128 PRG / VICE agree against MAME). `tb/tb_vdc.sv` runs the 8563 and the 8568 with their
own video RAM; `tb/vdc_main.cpp` compares, per character, HSYNC / VSYNC / display flip-flop, per displayed line the
pixel window against MAME's draw_row, every register / status read, the 64K video RAM after R31 / block operations,
8568 vs 8563 and the 8568 /INTR. Run 0 has all knobs on (must be 0); one run per knob reverted measures it.

```bash
./build_vdc.sh
./build/vdc/vdc <seed> <scenarios>         # every 4th scenario is a memory scenario
./run_vdc.sh 4 400                          # the report's campaign
python3 mutate_vdc.py                       # 16 injected bugs, each must be caught
```

## 6. Synthesis estimate
`synth/synth_one.sh <top> <files>`: Yosys `synth_intel_alm -family cyclonev`, cell statistics and
register-to-register LUT depth (`synth/depth.py`, FFs and IO cut paths).

## 7. Lint
`../lint.sh` (verilator --lint-only -Wall on every top; waivers listed in the script).

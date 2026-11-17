# t48sv verification — how to rerun

All flows run on Ubuntu 24.04 with `verilator` 5.020, `ghdl` 4.1 (mcode + llvm), `yosys` 0.33,
`yosys-plugin-ghdl`, `g++`, `python3`.

```
sudo apt-get install verilator ghdl ghdl-llvm yosys yosys-plugin-ghdl libllvm18
```

Ubuntu's `ghdl-llvm` looks for `libLLVM-18.so.18.1` while the package ships `libLLVM.so.18.1`:

```
mkdir -p ~/llvmshim && ln -sf /usr/lib/x86_64-linux-gnu/libLLVM.so.18.1 ~/llvmshim/libLLVM-18.so.18.1
export LD_LIBRARY_PATH=~/llvmshim
```

Reference sources (read-only clones, md5-checked in REPORT.md):

| name | where |
|---|---|
| A (fleet T48 r295) | `Arcade-Galaxian_MiSTer/rtl/cpu/i8039` |
| B (T48 2023+, fleet DECO copy) | `Arcade-DECOCassette_MiSTer/rtl/cpu/T48` |
| R (upstream r295 snapshot incl. system tops / bench / cells) | `git -C devsaurus/t48 worktree add <dir> 013d615` |
| upstream HEAD (bench, verification cells) | `github.com/devsaurus/t48` (837bd24) |
| MAME | `src/devices/cpu/mcs48/mcs48.{cpp,h}` from mamedev/mame master |

## 1. GHDL reference models

```
python3 ref/build_refs.py <A dir> <B dir> <R dir>/rtl/vhdl ref/gen          # all configurations
```

`ref/vhdl/` holds harness-only VHDL: black-box architectures for the ROM entities T48 leaves to
the integrator, and (`recovered/`) the upstream files `t8050_wb` still needs (deleted upstream,
see `recovered/PROVENANCE.txt`).

## 2. Lockstep (reference model vs t48sv, every pin + ~45 internal registers every clock)

```
cd tb
./build.sh <cfg>                       # one configuration, cfg from all_cfgs.txt
./build.sh A_core --left B_core        # reference A vs reference B (lineage comparison)
./run_lockstep.sh                      # random campaign, all configurations  -> results/lock_*.txt
./run_sweeps.sh                        # directed timing sweeps (sweeps/*.asm) -> results/sweep_*.txt
build/<cfg>/Vlockstep --runs N --cycles N --seed S --prog random|struct|mixed|file:<hex> [--trace]
```

## 3. T48 verification suite

Assembler (ASL subset, incl. AS's implicit `SEL MBx` before cross-bank JMP/CALL):

```
python3 asm/t48asm.py cell/test.asm -I <verif>/include --hex image.hex --ihex rom_t48.hex:0-1023
```

Native GHDL run of the unmodified upstream benches on the reference:

```
python3 suite/regress_ghdl.py B <run dir> <upstream>/sw/verif <upstream>/bench/vhdl <B> <B>/system <B>/t8243
python3 suite/regress_ghdl.py A <run dir> <R>/sw/verif <R>/bench/vhdl <R>/rtl/vhdl <R>/rtl/vhdl/system <R>/rtl/vhdl/t8243 --tbs gen,t48,t39
```

Same benches with t48sv (or the 2-state reference netlist) co-simulated through VHPIDIRECT:

```
cosim/build_cosim.sh B <B> <out> [--ref]            # --ref: GHDL netlist instead of t48sv
python3 suite/regress_ghdl.py B_t48sv <run dir> <upstream>/sw/verif <upstream>/bench/vhdl @<out>/files.txt --link "$(cat <out>/link.txt)"
python3 suite/compare_results.py native.json refnet.json t48sv.json
```

(`files.txt` = the lineage's packages, `system/` tri-state tops, `lpm_*`, `t8243.vhd`, plus
`<out>/shim_*.vhd`; see REPORT.md.) 8243 lockstep against the VHDL:

```
ghdl-llvm -i --std=08 -frelaxed <B>/t8243/{t8243_core,t8243_sync_notri,t8243_async_notri}.vhd cosim/tb_8243_cmp.vhd
ghdl-llvm -m --std=08 -frelaxed $(for l in $(cat <out>/link.txt); do echo -Wl,$l; done) tb_8243_cmp
./tb_8243_cmp -gasync_g=0|1 -gseed_g=S -gsteps_g=400000
```

## 4. MAME instruction-level comparison

```
MAME=<dir with mcs48.cpp/.h> mame/build.sh <variant 0=48 1=41 2=21 3=22> <REV2023>
mame/build/v0_r0/mame_cmp --variant 48 --progs 200 --instrs 3000 [--no-timer] [--file x.hex --trace --noresync]
```

## 5. Synthesis (yosys synth_intel_alm, Cyclone V)

```
python3 synth/run_synth.py <out dir> [config ...]
```

## 6. Lint

```
cd ../rtl
verilator --lint-only -Wall t48sv_lint.vlt $(cat files.f) --top-module <top>
python3 ../verify/lint/q17_check.py t48sv_all.sv t48sv_mcs48_pool.sv
python3 ../verify/lint/declare_before_use.py t48sv_all.sv
../verify/lint/make_all.sh                         # regenerate t48sv_all.sv
```

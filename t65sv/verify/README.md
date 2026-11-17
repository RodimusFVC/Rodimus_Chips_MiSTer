# t65sv verification

Everything here is verification-only. Nothing in `verify/` is needed to build t65sv.

## Tools (Ubuntu 24.04)

```bash
apt-get install -y verilator ghdl yosys subversion cc65
```

as65 1.42 (the assembler the Dormann tests are written for) is a 32-bit Linux binary inside the Dormann repo's
`as65_142.zip`. It needs the i386 runtime:

```bash
dpkg --add-architecture i386 && apt-get update && apt-get install -y libc6:i386 libstdc++6:i386
```

Versions used for the report: Verilator 5.020, GHDL 4.1.0, Yosys 0.33, as65 1.42.
Test data: SingleStepTests/65x02 2f6980a, SingleStepTests/65816 307c63f, Klaus2m5 tests 7954e2d,
VICE testprogs svn r46309, C64_MiSTer 93f558b (VIC-II, CIA, ROMs for the mini-C64).

## Test data (download steps)

Everything is fetched read-only into a scratch directory, here `$DL`.

```bash
DL=$HOME/dl; mkdir -p $DL; cd $DL
git clone --depth 1 https://github.com/RodimusFVC/Arcade-Galaxian_MiSTer galaxian              # T65 oracle source
git clone --depth 1 https://github.com/Klaus2m5/6502_65C02_functional_tests dormann
mkdir as65 && (cd as65 && unzip -q ../dormann/as65_142.zip && chmod +x as65)
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/SingleStepTests/65x02 sst
(cd sst && git checkout HEAD -- 6502 nes6502 wdc65c02 rockwell65c02 synertek65c02)               # ~5 GB of JSON
git clone --depth 1 --filter=blob:none https://github.com/SingleStepTests/65816 sst816             # ~8 GB of JSON
svn export -r 46309 https://svn.code.sf.net/p/vice-emu/code/testprogs/general/Lorenz-2.15 vicetp/Lorenz-2.15
svn export -r 46309 https://svn.code.sf.net/p/vice-emu/code/testprogs/CPU vicetp/CPU
mkdir -p vicetb && svn export -r 46309 https://svn.code.sf.net/p/vice-emu/code/testprogs/testbench/x64sc-testlist.txt vicetb/x64sc-testlist.txt
git clone --depth 1 --filter=blob:none --sparse https://github.com/MiSTer-devel/C64_MiSTer c64m && (cd c64m && git sparse-checkout set rtl)
```

## One-time preparation

```bash
cp $DL/galaxian/rtl/cpu/T65/*.vhd ref/ && ref/gen_ref.sh          # checks the 4 md5s, builds ref/ref_T65.v (GHDL synth)
cp $DL/dormann/6502_functional_test.a65 $DL/dormann/6502_decimal_test.a65 $DL/dormann/65C02_extended_opcodes_test.a65c tests/dormann/
tests/dormann/build.sh $DL/as65/as65                               # assembles all Dormann variants (Intel HEX)
sst/convert_all.sh $DL/sst $DL/sstbin                              # JSON -> compact binary (~1.2 GB)
sst816/convert816.sh $DL/sst816 $DL/sst816bin                      # 65816 JSON -> compact binary
c64/prepare_c64.sh $DL/c64m                                        # VIC-II (GHDL), CIA, ROM images for the mini-C64
```

The C64 ROM images and the VIC-II/CIA RTL come from C64_MiSTer and are only used by the C64 test harness.

## Harnesses

| Binary | Built by | What |
|---|---|---|
| `build/lockstep` | `./build_lockstep.sh` | oracle + t65sv in one model, every output compared before and after every clock edge. `random <seed> <cycles>` / `sweep` |
| `build/progrun_ls` | `./build_tb.sh progrun_ls progrun.cpp lockstep` | runs a program (Dormann) in lockstep |
| `build/progrun_{wdc,rkwl,syn,2a03}` | `./build_tb.sh progrun_wdc progrun.cpp solo -GC02=1` (2, 3; `-GC02=0 -GNO_DECIMAL=1`) | variant builds (t65sv only) |
| `build/sst_ls`, `build/sst_{wdc,rkwl,syn,2a03}` | `./build_tb.sh sst_ls sst.cpp lockstep` etc. | SingleStepTests runner, final state + every bus cycle |
| `build/c64flat_ls` | `./build_tb.sh c64flat_ls c64flat.cpp lockstep` | flat C64 shim (real ROMs, no VIC/CIA) in lockstep |
| `build/c64_lockstep`, `build/c64_solo` | `c64/build_c64.sh lockstep` / `solo` | cycle-accurate mini-C64 (fpga64 timing, C64_MiSTer VIC-II + CIAs); solo = `t65sv_6510` wrapper |
| `build/c02dir` | `./build_tb.sh c02dir c02dir.cpp solo -GC02=1` | WAI/STP and 65C02 interrupt-entry directed tests |
| `build/port6510` | see `run_all.sh` | 6510 I/O port directed test |
| `build/ls6507` | see `run_all.sh` | 6507 wrapper lockstep |
| `build/sst816` | `./build816.sh` | SingleStepTests 65816 on `t65sv816` (state loaded through `--public-flat-rw` signals) |
| `build/sst816_t65` | `./build816t.sh` | the same through `t65sv_T65 #(.C816(1))` (the generate path) |
| `build/c816dir` | `OUT=c816dir CPP=c816dir.cpp ./build816.sh` | 65C816 reset / IRQ / NMI / ABORT / WAI / STP directed tests |
| `build/progrun816` | `OUT=progrun816 CPP=progrun816.cpp ./build816.sh` | 6502 test programs on the 65C816 from reset (emulation mode) |
| `build/cov_*` | `./cov.sh $DL` | Verilator line coverage builds; `results/coverage.txt` (merged per file by `cov_summary.py`) |

## Running everything

`./run_all.sh $DL` rebuilds and reruns every suite and writes `results/`; `./final.sh $DL` does the same minus the
C64 programs. Rough single-core times: lockstep random 20M cycles 10 s, sweep 3 min, Dormann (all) 6 min, SST
5 sets x 2.56M cases 25 min each, SST 65816 2 x 2.54M cases 5 min each, Lorenz flat 1 h (4 jobs), mini-C64 runs
about 30k-100k CPU cycles/s per job (Lorenz 2-3 h and VICE 1-2 h with 4 jobs), mutation 10 min, yosys area 15 min,
coverage 30 min. `make_tables.py $DL` turns the Lorenz / VICE results into `results/lorenz_table.md` and
`results/vice_table.md`; `vice_c64_list.py` picks the VICE programs for the mini-C64 from VICE's testbench list.

Individual commands, e.g.:

```bash
./build/lockstep random 1 5000000
./build/lockstep sweep
./build/progrun_ls --hex tests/dormann/6502_functional_test.hex --start 0400 --pass 3469
./build/progrun_ls --hex tests/dormann/dec_nmos_all.hex --start 0200 --stop 024b --check 000b=00
./build/progrun_wdc --mode 1 --hex tests/dormann/c02_wdc.hex --start 0400 --pass 24f1
./build/sst_ls --quiet $DL/sstbin/6502
./build/sst_wdc --mode 1 --quiet $DL/sstbin/wdc65c02
./build/sst816 $DL/sst816bin n e 69             # 65816: opcode 69, native and emulation sets
./build/c64flat_ls $DL/vicetp/Lorenz-2.15/src/adcb.prg
./run_c64.sh lockstep list.txt results/out.txt 40000000   # list lines: <prg> [max cycles]
./mutate.sh mutants1.txt
synth/area.sh
```

## Notes

- The oracle is the GHDL synthesis netlist of the four T65 Ver 315 files (md5 checked). `break` is renamed
  (SV keyword) and GHDL's duplicate `alu_q` declaration is merged; nothing else is touched.
- Before the first clock edge the oracle sees an asynchronous reset event at time 0 that t65sv does not
  (simulator initialisation of the `Res_n_i` net); comparisons start at the first edge. On hardware both power
  up with all registers 0.
- Mutation testing (`mutate.sh`) injects single bugs into a copy of `rtl/t65sv.sv` and checks that the lockstep
  harness reports a mismatch.

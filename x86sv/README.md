# x86sv

Our own SystemVerilog 8088 / 8086 / NEC V20 / V30 CPU, written for Quartus 17 / Cyclone V and any core clock (one clock
+ a CPU-clock enable). Intended to replace MCL86 in the fleet.

**Status: in development, checkpoint 9.**
- **8088** (`x86sv`): cycle-exact; all 323 SingleStepTests 8088 v2 files (3,007,000 tests) pass on registers incl.
  flags, RAM, cycle count and the per-clock bus / queue trace; 42 directed tests (reset, wait states, INTR / INTA,
  NMI, single-step, HLT, WAIT, LOCK). Quartus 17 (user run): 2,000 ALMs, fmax 102.8 MHz.
- **8086** (`x86sv16`): cycle-exact; all 323 SingleStepTests 8086 v1 files (646,000 tests) pass on every comparison
  (the inactive half of AD15-0 after a byte write is masked, per the suite's BHE rule).
- **V20** (`x86sv #(.NEC(1))`): cycle-exact; all 360 SingleStepTests V20 v1 native files (3,125,000 tests) pass on
  registers incl. every flag, RAM, cycle count and the per-clock bus / queue trace, including ADD4S / SUB4S / CMP4S
  and INS / EXT. **V30** (`x86sv16 #(.NEC(1))`): V20 suite registers / RAM 100 %; its timing (V20 EU + 8086 BIU16)
  is inferred, no V30 suite exists.
- **8080 emulation mode** (`NEC8080`, with `NEC`): BRKEM / RETEM / CALLN, MD flag rules, the full 8080 instruction set,
  INT / NMI / HALT in the mode (NEC user's manual section 8); V20 and V30 pass 100 % of our own model-generated suite
  `verify/suites/v20_8080` (657,673 tests; model checked against the 8080 exercisers), the 8080 exercisers in 8080
  mode and 44 directed tests. 8080-mode clock counts are inferred (no NEC document gives them). V20 / V30 HALT:
  INT releases it even with IE = 0 in native and 8080 mode (UM 9-1).

Files:
- `rtl/x86sv_all.sv`: the one file a Quartus project needs (generated from `rtl/x86sv_alu.sv`, `x86sv_biu.sv`,
  `x86sv_biu16.sv`, `x86sv_eu.sv`, `x86sv.sv`, `x86sv16.sv` by `verify/tools/mkall.sh`; `verify/build.sh` regenerates it).
  Tops: `x86sv` (8-bit bus, 8088 / V20) and `x86sv16` (16-bit bus with BHE, 8086 / V30), parameter `NEC`.
- `rtl/x86sv_fleet.sv`: wrappers on the fleet's `chip_pool_pkg` bus types: `x86sv_mcl86`, `x86sv_i8088`,
  `x86sv_i8086`, `x86sv_v20`, `x86sv_v30` (types `i8088_*`, `i8086_*`, `v20_*`, `v30_*`, all in the master package;
  `fleet_types.svh` holds proposals, none pending).
- `syn/quartus/`: Quartus 17 test project, one revision per configuration (8088, 8086, V20, V30, V20 / V30 + 8080; 5CSEBA6U23I7,
  80 MHz .sdc, sources in `files.qip`).
- `verify/`: Verilator runner for the SingleStepTests MOO files (own MOO reader `tb/moo.h`; configs 8088 / 8086 /
  v20 / v30 / v20e / v30e), the 8080-mode suite runner `tb/s80.cpp` and exerciser / directed runner `tb/x80.cpp`, the
  8080-mode suite and its generator (`suites/v20_8080/`), directed tests (`tb/dsim.cpp`, 8088), fleet wrapper test (`tb/fleet.cpp`), `run_all.sh` (one command:
  every config), trace tools `mooview` / `mooscan` / `moocsv`, `tools/yosys.sh` (Cyclone V estimate per config),
  `tools/equiv.sh` (formal equivalence against a reference RTL). `REPORT.md`: method, results, sources.
- `DESIGN.md`: architecture, timing model, options, fleet bus types, risks.

Fleet users: none yet (planned: the two MCL86 cores).

License: TBD by the maintainer; test-data notice in `LICENSE`.

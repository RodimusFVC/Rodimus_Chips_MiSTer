# crtc6845sv: test report

One synthesizable SystemVerilog 6845-family CRTC. At default parameters it is cycle-for-cycle identical to the fleet's
fixed `mc6845.vhd` (CRTCADJ-2026-10-24). Seven more 6845 / 6545 family members are selected by `VARIANT`.
Target: Quartus 17.0, Cyclone V 5CSEBA6U23I7 (MiSTer). Verified RTL: `rtl/crtc6845sv.sv` md5 f78a10415ac5ace5e8bc5d1621ae84c2. Everything here was produced in a cloud container. Nothing was
pushed, committed or opened on GitHub.

## 1. Results at a glance

| Check | Result |
|---|---|
| Lockstep vs **fixed** reference, every output, both clock phases of every CLOCK | **0 mismatches** in 960 M CLOCKs (463 M CLKENs, 6 980 episodes) on the pre-variant core. Final RTL: **0** in 960 000 000 CLOCKs (463 420 025 CLKENs, 6 980 episodes) |
| Formal: final core at VARIANT = 0 ≡ the pre-variant core | **Proven** (Yosys equiv_induct, 533 / 533 equivalence cells) |
| Lockstep vs **stock** reference | 68 964 804 differing clock-phases, **all** in one class: vertical-adjust lines whose row counter is below R6. Split (final RTL, by the row counter when the condition held): row wrapped to 0 (R4 = 127) 5 865 558, row = R4 + 1 < R6 63 099 246. Outside the class: **0** |
| Fleet scenarios (12 game tables, real write order / clock / bus) vs fixed | **0 mismatches** (all 12). Stock differs only on Cosmic Guerilla (R4 = 127, R5 = 7), as the fix intends |
| Variants vs MAME `mc6845.cpp` (per-character MA, RA, DE, HSYNC, VSYNC, CURSOR, update strobe, every register and status read) | **0 mismatches** on all 10 variant / MAME-type pairs once each pair's documented deviations ("knobs") are applied. Random + directed run: 276 613 280 characters and 1 749 523 reads per model, 2 767 386 098 characters over all pairs; mismatches 0 |
| C128 VDC 8563 / 8568 vs MAME mos8563 + C128 docs (section 11) | **0** sync / line / read mismatches over 1.48 M displayed lines and 19.6 M reads; video RAM identical after R31 / block ops (one harness artifact explained and fixed) |
| `verilator --lint-only -Wall` | Clean on every top, VDC included. Waivers: DECLFILENAME (the concatenated file only), PINCONNECTEMPTY (pool wrapper `.CURSOR()`) |
| Yosys `synth_intel_alm` (Cyclone V), default | 229 FF, ~149 ALM (reference: 229 FF, ~150 ALM), 5 LUT levels. No M10K, no DSP |

## 2. Sources (md5 verified before use)

| File | md5 | Status |
|---|---|---|
| Stock `mc6845.vhd`, MiSTer-devel/BBCMicro_MiSTer `rtl/mc6845.vhd` | e1c74cb714f3ae0431314e6047e9b426 | Match. Fleet copies in Qix `rtl/cpu/` and SNK6502 `rtl/video/` are byte-identical |
| Fixed `mc6845.vhd`, RodimusFVC/Arcade-Universal_MiSTer `rtl/video/mc6845.vhd` | bab5f31f9ef3f5ff702cb586a5e8c714 | Reachable, match. `diff -w` vs stock: only `in_adj_s` and the gated `v_display_early` (plus comments) |
| DECOCassette `rtl/mc6845.vhd` | 797f5438467856eabd9727ef4093f844 | Match, stock minus one comment and a blank line |
| MAME `src/devices/video/mc6845.cpp` / `.h` (master, fetched 2026-10-29) | aaaff6e62887123c9a8c5de1a30b6682 / 5b27d0f6b09edbec5750318b6209fb93 | Oracle for the variants |

The brief also lists a fleet copy in a "master repo `rtl/video/`". None of the repositories visible to this session is
named or shaped like a master repo, so that copy was not checked. Qix, SNK6502 and Universal were checked.

**Upstream (report only, full detail in `docs/UPSTREAM_SURVEY.md`):**
- The BBCMicro file's content last changed on **2019-09-27** (f6f1afb, sorgelig, "Tweaks for direct video"). That
  commit disabled the odd-field toggle and moved the VSYNC start from character 0 to character R2.
- 2020-05-10 (ad2300a) is a pure rename, `src/` to `rtl/`, with the same blob.
- Upstream HEAD d37f7d2 still has md5 e1c74cb7….
- Other maintained 6845-family HDL found in MiSTer-devel (from the wiki Cores list, 361 repos):

| Core | File | Lineage | What it models differently from the BBC file |
|---|---|---|---|
| AcornElectron | rtl/mode7/mc6845.vhd | Stirling/Banks, before the 2019 tweak | Real interlace (field toggle, odd-field VSYNC at R0/2), true 2-char cursor skew, no H/VBLANK ports |
| CBM-II | rtl/mc6845.vhd | hoglet BeebFpga rewrite | New timing core (end-of-frame latched at C0 = 0/1/2), true DE / cursor skew incl. "off", light-pen synchroniser, single field |
| Amstrad | rtl/UM6845R.v | Sorgelig, CPC type 0/1 | CRTC_TYPE input: type-1 status reg, R31 = FF, fixed 16-line VSYNC; real interlace; mid-frame R1/R6/R7 effects; no light pen / blink |
| PCXT, Tandy1000, PCjr, PCXT-EGA | rtl/video/UM6845R.v | forks of the Amstrad file | CGA/Hercules sync tuning (PCXT), EGA register set (PCXT-EGA: no longer a 6845) |
| Lynx48, EG2000 | rtl/UM6845R.v | early UM6845R snapshot | Simple counters, real interlace, status / R31, R6 = 0 suppresses DE |

None of them treats HSYNC width 0 as 16. The CBM-II / BeebFpga VHDL is the most accurate maintained descendant of the
same lineage.

## 3. The design

### Files (`rtl/`)
| File | What |
|---|---|
| `crtc6845sv.sv` | The core, `#(parameter int VARIANT = 0)`, ports = mc6845 + `PHI2` (6545 interleave only) |
| `crtc6845sv_mc6845.sv` | **Drop-in** for the fleet's `mc6845`: same ports, no parameters, VARIANT 0 |
| `crtc6845sv_mc6845_motorola.sv` … `crtc6845sv_mos6545.sv` | Per-variant drop-in tops (same ports; `crtc6845sv_r6545` adds `input tri0 PHI2`, which may be left open) |
| `crtc6845sv_pool.sv` | `chip_pool_pkg` wrapper (`mc6845_i_t` in, `mc6845_o_t` out; struct fields assigned one by one from plain wires) |
| `crtc6845sv_vdc.sv` | C128 VDC, `#(VARIANT = 8 / 9)` for MOS 8563 / 8568 (section 11) |
| `crtc6845sv_all.sv` | Core + all drop-in / variant tops + the VDC in one file (everything a Quartus project needs except the pool wrapper). Regenerate with `make_all.sh` |

To retire Universal's edited copy, replace `mc6845 mc6845_0 (…)` with `crtc6845sv_mc6845 mc6845_0 (…)` (identical
port list), or instantiate `crtc6845sv_pool`. Then add `crtc6845sv_all.sv` to `files.qip` and drop `mc6845.vhd`.

### Variants
| VARIANT | Top | Part | CPC type |
|---|---|---|---|
| 0 | crtc6845sv_mc6845 | fleet mc6845 (fixed reference) | n/a (Hitachi-flavoured hybrid) |
| 1 | crtc6845sv_mc6845_motorola | Motorola MC6845 | 2 |
| 2 | crtc6845sv_hd6845s | Hitachi HD6845S / HD46505SP, UMC UM6845 | 0 |
| 3 | crtc6845sv_um6845r | UMC UM6845R | 1 |
| 4 | crtc6845sv_ams40489 | Amstrad AMS40489 ASIC | 3 |
| 5 | crtc6845sv_ams40226 | Amstrad 40226 pre-ASIC | 4 |
| 6 | crtc6845sv_r6545 | Rockwell R6545-1 / Synertek SY6545-1 | n/a |
| 7 | crtc6845sv_mos6545 | MOS / Commodore 6545-1 (C6545-1) | n/a |

The brief files the Motorola part under "default class". It is not: the fleet file is Hitachi-flavoured
(programmable VSYNC width, R8 skew bits, R12/R13 read-back). The real Motorola behaviour is VARIANT 1. The default is
its own class, the fixed reference, bit for bit.

**What each variant changes** (sources: [ACCC] Longshot's Amstrad CPC CRTC Compendium v1.11; [MC] MC6845 datasheet;
[SY] SY6545-1 datasheet; [MOS] 6545-1 datasheet; [TS] tom-seddon/6845-tests on real HD6845; [MAME]. Per-claim quotes
are in `docs/VARIANT_SOURCES.md`):

| Feature | 0 fleet | 1 MC6845 | 2 HD6845S | 3 UM6845R | 4 / 5 AMS | 6 R6545-1 | 7 MOS 6545-1 | Source / note |
|---|---|---|---|---|---|---|---|---|
| VSYNC width | R3[7:4], 0 = 16 | fixed 16 | R3[7:4] | fixed 16 | R3[7:4] | R3[7:4] | R3[7:4] | [ACCC 14.1-2], [MC], [SY]. MAME ams40489 says fixed: disagrees with [ACCC] |
| HSYNC width 0 | none | 16 | none | none | 16 | 16 | 16 | [ACCC 14.6] measured. [MC] says "no HS": disagrees. 6545: datasheet silent, MAME 16 |
| Read back | R12-R17 | R14-R17 | R12-R17 | R14-R17, R31 = FF | idx[2:0] mirror: R16, R17, Status1, Status2, R12 (8 bits), R13, R14, R15 | R14-R17 | R14-R17 | [ACCC 21], [SY Fig 3] |
| RS = 0 read | register (as fleet) | 00 | 00 | status: b6 light pen, b5 vertical border | same as RS = 1 | status: b7 update ready, b6 LPEN full, b5 vblank | b6, b5 | Real type 0/2 float (CPC reads FF/7F); 00 matches MAME |
| R8 skew | fleet: DE 00/01 = 0, 10 = 2, 11 = off; cursor 01/10 = 1, 11 = off | none | DE and cursor 0 / 1 / 2 / off | none | DE 0 / 1 / 2 / off, no cursor skew | b4 DE +1, b5 cursor +1 | b4 / b5 | [ACCC 19], [SY], [MOS]. Type 3/4 cursor skew disputed in [ACCC]: not implemented |
| Interlace (R8 = 3: lines in twos) | yes, no field toggle | same | same | same | same | ignored (non-interlace part) | ignored | Field toggle / half-line VSYNC not modelled (see 9) |
| Vertical display | `row < R6` and not in adjust (CRTCADJ) | flip-flop: set at frame start, cleared at row = R6 (any character) | same | same + R6 = 0 forces border at any time | same | same | same | [ACCC 10-12], [MAME] |
| VSYNC timing | starts / counts at character R2 | starts / counts at character 0 | 0 | 0 | 0 | 0 | 0 | [ACCC], [MAME]. Fleet R2 = the 2019 "direct video" tweak |
| Vertical adjust | line counter vs R5-1, row = R4 + 1 | separate adjust counter, rows keep counting | as fleet (type 0: C4 held at R4 + 1) | as type 2 | as fleet but row held at R4 | as fleet | as fleet | [ACCC 11-12, 16.4] |
| Start address | at frame start | frame start | frame start | reloaded on every line of row 0 | frame start | frame start; R8 b2 row/column (row += 0x100) | same, row/column | [ACCC 20.3.2], [SY], [MOS] |
| Cursor rows | latch at the cursor character, cleared on line 0 | line latch: set at R10, cleared after R11, every line (start > end wraps) | same | same | same | same | same | [TS] (real HD6845), [MC]/PCjs (solid cursor when start > end). MAME's HD "no wrap" disagrees with [TS] |
| Cursor blink | field / 16, / 32 (8 on / 8 off, 16 / 16) | same | same | same | same | same | same | [MC] Table 4, [SY]. MAME blinks at half this rate |
| First frame after reset | display on, MA from 0 | display off until first frame start ([MC]), MA from 0 | same | same | same | same | same | [MC], [HD-R] |
| Transparent addressing | n/a | n/a | n/a | n/a | n/a | R18/R19 update address, R31 dummy, update strobe on RA4 (R8 b6), retrace mode (MA steal after 4 blank characters) and phi2-interleaved mode (MA = update address while PHI2, R31 access increments) | n/a | [SY], [MAME] |

**Constant folding.** Every feature is a `localparam bit` derived from `VARIANT` and used only in constant
conditions, so unused logic disappears. At VARIANT = 0 the core is formally equivalent to the pre-variant core (section
4.2), and Yosys gives the same cell counts as the reference.

### Design decisions
1. **Default = fixed reference, bit for bit, including its quirks.** These include the R2-phased VSYNC, the DE skew
   01 → no delay, cursor skew 10 → 1 character, no interlace field toggle, and RS ignored on reads. They also include
   the un-reset skew pipeline (it shifts during reset, as in the VHDL), sync counters that keep counting through a
   retrigger, and the asynchronous active-low reset that clears all registers and DO.
2. **Redundancy removed without changing behaviour.** `in_adj` / `in_adj_s` and `h_sync_start` / `v_sync_start`
   are each one signal. `odd_field` is constant 0 and gone. RA in interlace sync+video mode is `line` (the VHDL's
   `line(0) or odd_field` with odd_field = 0).
3. **Chip variants share the fleet engine** and switch only the documented differences. Their outputs keep the
   same one-character latency, so a core can change variant without retiming its pixel pipeline.
4. **Where sources disagree**, measured hardware wins over datasheet prose, and datasheets win over MAME
   simplifications. Examples: HSYNC 0 = 16 on type 2 ([ACCC] measured, despite [MC]); the cursor wraps on HD6845
   ([TS] hardware, despite MAME); blink at the datasheet rate (despite MAME).
5. **6545 transparent timing follows MAME's 4-character update timer**, the only documented latency. An R31 access
   in the middle of a character is quantised to "update on the 4th following character". In retrace mode MA carries
   the update address for one character, with the RA4 strobe when R8 b6. A single-clock FPGA has no phi2 phase, so
   interleaved mode uses a `PHI2` input: MA shows the update address while PHI2 is high.
6. **R31 read** returns FF on the UM6845R ([ACCC]: "127 or 255 seen"). On the SY6545 it leaves DO unchanged
   ("does not drive the data bus"). A status read of a chip without a status register returns 00 (MAME's choice;
   real parts float).
7. **Registers are cleared by reset on every variant**, as in the fleet. The datasheets say control registers
   survive /RESET. The fleet holds the chip in reset and reprograms it, so clearing is the safer FPGA behaviour.

## 4. Default variant: proof

### 4.1 Lockstep vs the fixed and stock references
GHDL 4.1 converts both VHDL files to Verilog (`verify/ref/`). Verilator runs them next to the drop-in on the same
pins (`verify/tb/tb_lockstep.sv`). After both clock phases of every CLOCK, `lockstep_main.cpp` compares DO, MA, RA,
VSYNC, HSYNC, VBLANK, HBLANK, DE and CURSOR.

Stimulus (`verify/tb/stim.h`):
- **Directed tables first:** R0 / R1 / R4 / R6 / R9 = 0; R1 > R0; R4 = 127 with R5 = 0, 7 and 31; R9 = 31; R6 / R7
  beyond R4; R2 beyond R0; sync widths 0 and 15; R8 = 0 / 1 / 3 with odd R9; every DE and cursor skew; cursor modes
  incl. both blinks, off, split, end > R9; a Vanguard-like table.
- **Then random episodes** from 5 register profiles, with mid-frame rewrites of R0-R15 (and R16-R31) at random
  character / line positions.
- **Bus activity:** reads of all 32 indices and the RS = 0 port; ENABLE held 1-4 CLOCKs; random R_nW / RS / DI noise
  while ENABLE is low.
- **Other pins:** light-pen toggles; 6 CLKEN patterns (always, 1/N for N = 2-8, 1/32, random 50 % / 90 % / 15 %);
  mid-frame resets.

| Run | CLOCKs | CLKENs | Episodes | Writes / reads / mid-frame rewrites | Mid-frame resets | dut vs fixed |
|---|---|---|---|---|---|---|
| 16 seeds x 60 M (pre-variant core) | 960 000 000 | 463 420 025 | 6 980 | 1 152 423 / 673 663 / 151 298 | 2 902 | **0** |
| 16 seeds x 60 M (final RTL) | 960 000 000 | 463 420 025 | 6 980 | 1 152 423 / 673 663 / 151 298 | 2 902 | **0** |

Coverage in the 960 M run (CLKENs with the condition true):

| Condition | CLKENs |
|---|---|
| In vertical adjust | 29 476 211 |
| Adjust with R4 = 127 | 1 574 265 |
| Adjust with row < R6 | 16 760 369 |
| Adjust exits | 1 060 627 |
| R8 = 3 interlace | 82 125 340 |
| R0 = 0 | 17 510 283 |
| R9 = 31 | 8 028 238 |
| Light-pen toggles | 659 441 |

Every DE skew (00 / 01 / 10 / 11) and cursor skew value is hit, each with at least 3.1 M CLKENs. Every cursor mode
is hit, each with at least 5.8 M.

**Stock vs fixed.** The harness keeps a 5-CLKEN history of the fixed model's `in_adj & (row < R6)`, sampled before
each edge, the state that edge acts on. Every stock difference must fall inside that window and touch only VBLANK, DE
or CURSOR. Result: 68 964 804 differing clock-phases, 0 outside the class.

| Signals | Count |
|---|---|
| VBLANK | 30 308 170 |
| DE + VBLANK | 38 045 587 |
| DE (skew-delayed tail) | 609 855 |
| CURSOR + DE + VBLANK | 1 192 |

Final-RTL run: 68 964 804 differing clock-phases, 0 outside the class. They spread over 5462 distinct (row counter, R6, R4, R5) settings, listed in `verify/results/stock_diff_by_registers.txt`. R4 / R5 there are the values when the condition held; a mid-adjust rewrite can leave R4 or R5 different from the frame's original values, because the row counter keeps the value it had on entering the adjust.
Two sub-cases:
- **Row counter wrapped to 0** (R4 = 127 on entering the adjust): 5.9 M. This is the Cosmic Guerilla case the fix targets.
- **Row counter = R4 + 1, still below R6** (R6 > R4 + 1): 63.1 M.

**Finding: the CRTCADJ gate is wider than its comment says.** It blanks every adjust line whenever row < R6. That
includes R6 > R4 + 1, where nothing wraps. There, stock and MAME (display flip-flop never cleared, display stays on
through the adjust) agree with each other, and the fixed copy differs. No fleet game programs R6 > R4 + 1: all 12
fleet tables show the default's `de_fleet` behaviour identical to MAME's flip-flop (section 6). So the fix is correct
for the fleet. If a future core needs R6 > R4 + 1, a narrower gate (only when the row counter wrapped) would match
MAME in both cases. The default keeps the fixed behaviour, as required.

### 4.2 Variant logic folds away (formal)
`verify/equiv/equiv.ys`: `equiv_make` / `equiv_simple -seq 5` / `equiv_induct -seq 5` of `crtc6845sv` at
VARIANT = 0 against `crtc6845sv_v1.sv`, the pre-variant core that passed the 960 M-cycle lockstep. Result:
"Equivalence successfully proven", 533 / 533 cells.

## 5. Variants vs MAME (frame-level oracle)

`verify/mame/mame6845.h` transliterates MAME's mc6845.cpp to the character clock. Every emu_timer becomes a character
position or a down-counter; at equal times the earlier-armed timer fires first, as in MAME's timer list.
handle_line_timer, match_line, is_row_end, both check_cursor_visible versions, update_cursor_state, register_r /
register_w / status_r and the transparent-update logic follow MAME line by line.

Each crtc6845sv choice that differs from MAME is a named **knob** in the model. For each of the 10 (variant, MAME
type) pairs the harness runs:
- one model with the pair's full knob set, which must give **0 mismatches**;
- one model per knob with only that knob reverted to MAME, which measures that difference on its own and proves it
  is exercised.

What is compared: MA, RA, DE (after skew), HSYNC, VSYNC and CURSOR on every character; the update address and RA4
strobe (6545); MA while PHI2 (6545 interleave); DO on every register and status read.

Scope of the stimulus:
- Registers R0-R15 stay stable within a scenario, because MAME's model is line-timer based and a mid-line rewrite has
  no defined meaning in it.
- Reads, R18 / R19 / R31 accesses, light-pen strobes and PHI2 run between characters.
- Scenarios: the 26 directed tables, 4 x 400 random tables (30 % with R8 b3 transparent mode), and the fleet tables.

| Pair | Characters | Frames | Reads | Mismatches (all knobs) | Knobs (characters / reads that differ when reverted alone) |
|---|---|---|---|---|---|
| V0 fleet  vs MAME hd6845s | 276 613 280 | 370 406 | 1 749 523 | **0 / 0** | `hsw0_none` 5 497 005; `blink_ds` 3 462; `cursor_fleet` 4 829; `engine_t0` 28 872 051 / 3 921r; `de_fleet` 2 409 996; `vs_r2` 4 827 601; `il_fleet` 30 520 408 / 4 202r; `hs_cont` 6 537 895; `vs_hdl` 428 288; `lp_now` 0 / 25 530r; `skew` 7 025 819; `rd_rs0_reg` 0 / 37 704r; `first_ma0` 9 370 705 / 1 791r |
| V0 fleet  vs MAME mc6845 | 276 613 280 | 370 406 | 1 749 523 | **0 / 0** | `hsw0_none` 5 497 005; `blink_ds` 3 462; `cursor_fleet` 6 016; `engine_t0` 28 872 051 / 3 921r; `de_fleet` 2 409 996; `vs_r2` 4 827 601; `il_fleet` 30 520 408 / 4 202r; `hs_cont` 6 537 895; `vs_hdl` 428 288; `lp_now` 0 / 25 530r; `skew` 7 025 819; `rd_rs0_reg` 0 / 37 704r; `first_ma0` 9 370 705 / 1 791r; `vsw_prog` 7 578 969; `rd_r12` 0 / 50 501r |
| V1 MC6845 vs MAME mc6845 | 276 613 280 | 362 895 | 1 749 523 | **0 / 0** | `blink_ds` 3 681; `cursor_line` 4 903; `first_off` 2 727 060; `frame_match` 4 019 313; `il_fleet` 29 905 952 / 3 142r; `hs_cont` 7 624 645; `vs_hdl` 1 824 330; `lp_now` 0 / 19 193r; `first_ma0` 9 398 523 / 1 391r |
| V2 HD6845S vs MAME hd6845s | 276 613 280 | 370 406 | 1 749 523 | **0 / 0** | `blink_ds` 3 635; `cursor_line` 7 495; `first_off` 2 578 026; `engine_t0` 29 044 115 / 2 920r; `hsw0_none` 5 497 005; `il_fleet` 30 577 263 / 3 156r; `hs_cont` 6 537 895; `vs_hdl` 602 265; `lp_now` 0 / 19 193r; `skew` 7 995 356; `first_ma0` 9 370 705 / 1 381r |
| V3 UM6845R vs MAME mc6845 | 276 613 280 | 362 895 | 1 749 523 | **0 / 0** | `blink_ds` 3 681; `cursor_line` 4 903; `first_off` 2 727 060 / 6 678r; `hsw0_none` 5 497 005; `r6z` 4 019 313 / 13 727r; `vma_row0` 10 035 746 / 1 436r; `il_fleet` 29 904 770 / 13 205r; `hs_cont` 6 537 895; `vs_hdl` 4 138 114; `lp_now` 0 / 19 199r; `rd_status_um` 0 / 401 677r; `rd_r31ff` 0 / 401 218r; `first_ma0` 300 485 / 57r |
| V4 AMS40489 vs MAME ams40489 | 276 613 280 | 370 406 | 1 749 523 | **0 / 0** | `vsw_prog` 13 256 440; `blink_ds` 3 685; `cursor_line` 5 052; `first_off` 2 581 045; `engine_t0` 30 342 230 / 15 685r; `adj_hold` 2 244 444; `il_fleet` 30 573 615 / 16 767r; `hs_cont` 7 624 645; `vs_hdl` 848 029; `lp_now` 0 / 102 921r; `skew` 8 048 509; `rd_mirror` 0 / 1 631 412r; `first_ma0` 9 370 705 / 7 208r |
| V5 40226  vs MAME ams40489 | 276 613 280 | 370 406 | 1 749 523 | **0 / 0** | `vsw_prog` 13 256 440; `blink_ds` 3 685; `cursor_line` 5 052; `first_off` 2 581 045; `engine_t0` 30 342 230 / 15 685r; `adj_hold` 2 244 444; `il_fleet` 30 573 615 / 16 767r; `hs_cont` 7 624 645; `vs_hdl` 848 029; `lp_now` 0 / 102 921r; `skew` 8 048 509; `rd_mirror` 0 / 1 631 412r; `first_ma0` 9 370 705 / 7 208r |
| V6 R6545-1 vs MAME r6545_1 | 277 239 929 | 346 242 | 1 749 523 | **0 / 0** | `blink_ds` 3 836; `cursor_line` 4 555; `first_off` 2 884 521 / 7 181r; `engine_t0` 7 767 787 / 1 318r; `rowcol` 45 605 947 / 5 826r; `upd_needs_mode` 1 838 207; `upd_access3` 176 558 / 184r; `r1z_no_de` 1 941 / 555r; `hs_cont` 7 624 645; `vs_hdl` 511 502; `lp_now` 0 / 19 250r; `skew` 987 704; `rd_r31hold` 0 / 184 960r; `first_ma0` 9 802 859 / 1 451r |
| V6 SY6545-1 vs MAME sy6545_1 | 277 239 929 | 346 242 | 1 749 523 | **0 / 0** | `blink_ds` 3 836; `cursor_line` 4 555; `first_off` 2 884 521 / 7 181r; `engine_t0` 7 767 787 / 1 318r; `rowcol` 45 605 947 / 5 826r; `upd_needs_mode` 1 838 207; `upd_access3` 176 558 / 184r; `r1z_no_de` 1 941 / 555r; `hs_cont` 7 624 645; `vs_hdl` 511 502; `lp_now` 0 / 19 250r; `skew` 987 704; `rd_r31hold` 0 / 184 960r; `first_ma0` 9 802 859 / 1 451r |
| V7 C6545-1 vs MAME c6545_1 | 276 613 280 | 346 242 | 1 749 523 | **0 / 0** | `blink_ds` 3 836; `cursor_line` 4 555; `first_off` 2 881 652 / 7 093r; `engine_t0` 7 768 392 / 1 153r; `rowcol` 45 629 360 / 5 826r; `hs_cont` 7 624 645; `vs_hdl` 511 502; `lp_now` 0 / 19 250r; `skew` 987 704; `first_ma0` 9 808 781 / 1 451r |

Fleet tables through the same oracle: V0 fleet  vs MAME hd6845s: 0 / 0; V0 fleet  vs MAME mc6845: 0 / 0; V1 MC6845 vs MAME mc6845: 0 / 0; V2 HD6845S vs MAME hd6845s: 0 / 0; V3 UM6845R vs MAME mc6845: 0 / 0; V4 AMS40489 vs MAME ams40489: 0 / 0; V5 40226  vs MAME ams40489: 0 / 0; V6 R6545-1 vs MAME r6545_1: 0 / 0; V6 SY6545-1 vs MAME sy6545_1: 0 / 0; V7 C6545-1 vs MAME c6545_1: 0 / 0 (character / read mismatches, all knobs).

### Every difference between the default (stock VHDL lineage) and MAME, with the datasheet view
Character counts are from the random runs, with the knob reverted alone on V0 (fleet) vs MAME hd6845s; vs MAME mc6845
the counts are the same plus `vsw_prog` and `rd_r12`.

| Knob | Difference | MAME | Datasheet / hardware | Count |
|---|---|---|---|---|
| vs_r2 | VSYNC starts and ends at character R2 (fleet's 2019 tweak) | character 0 | [ACCC]: C0 = 0 | 4 827 601 |
| hsw0_none | HSYNC width 0 = no HSYNC | 16 | type 0/1 none, type 2/3/4 16 ([ACCC]); [MC] says none | 5 497 005 |
| vsw_prog | VSYNC width programmable | mc6845: fixed 16 | [MC] fixed 16; Hitachi programmable | 7 578 969 (vs mc6845) |
| engine_t0 | Adjust lines count the line counter to R5-1, no row increments, row = R4 + 1 | rows keep counting, raster wraps at R9 | type 0 = fleet; type 1 / 2 = MAME ([ACCC] 11-12) | 28 872 051 |
| de_fleet | Vertical display = row < R6 and not in adjust | flip-flop | flip-flop (all types) | 2 409 996 |
| il_fleet | R8 = 3: lines in twos, LSB forced 0, no field | rudimentary (+interlace_adjust) | real interlace alternates fields | 30 520 408 |
| cursor_fleet | Cursor latch at the cursor character, cleared on line 0 (start > end shows R10..max only) | MC: wrap; HD: none | [TS]: wraps | 4 829 |
| blink_ds | Blink 8 on / 8 off and 16 / 16 fields | half that rate | [MC] Table 4: 1/16, 1/32 field rate. Fleet = datasheet | 3 462 |
| skew | Fleet R8 skew mapping | none | Hitachi: 0 / 1 / 2 / off | 7 025 819 |
| hs_cont | HSYNC width counter keeps counting through a retrigger (width ≥ line length, R0 = 0); also no HSYNC when R2 > R0 | off timer restarts; fires at line end when R2 = R0 + 1 | not documented | 6 537 895 |
| vs_hdl | R7 / line 0 tested every line; a match during VSYNC does not restart its width | tested at row changes, restarts | [ACCC]: re-trigger protection varies by type | 428 288 |
| first_ma0 | First frame after reset runs from MA 0 | from R12/R13 | counters cleared by reset | 9 370 705 |
| lp_now | Light pen latches the character being output when the strobe is seen | one character later | [MC] "M+2", [SY] "n+2" | reads: 25 530 |
| rd_rs0_reg / rd_r12 | RS = 0 reads the selected register; R12/R13 readable | 00; mc6845: R12/R13 = 00 | type 0/2 float; Hitachi reads R12/R13 | reads |

MAME quirks found along the way (not differences of the default, but they explain knobs on the chip variants):
- MAME's MC6845 / AMS40489 models skip match_line at frame restart, because they lack `supports_vert_sync_width`.
  So **R7 = 0 never starts VSYNC** and **R6 = 0 leaves the display on for the whole frame** there (knob
  `frame_match`).
- MAME fires HSYNC at the line end when R2 = R0 + 1.
- MAME runs transparent-update cycles even with R8 b3 clear (`upd_needs_mode`).
- With R1 = 0, MAME raises DE for zero time at each line start, which re-arms its update timer (`r1z_no_de`).

## 6. Fleet scenarios

`verify/tb/fleet_main.cpp` replays each game's table through the lockstep model. Each game uses its write order
(Qix R13 → R0, Slither R0 → R13), its character clock (Qix 20 MHz / 32, SNK6502 / 16, Universal 19.656 MHz / 32) and
an ENABLE held for 4-16 CLOCKs. On top of that:
- Yo-Yo rewrites R12/R13 in every vblank, including the cocktail-flip $3FE0 case.
- Cosmic Guerilla reads R12-R17 back (TMS board).
- Universal boards are held in reset mid-run (board switch) and reprogrammed.

Tables and their confidence are in `docs/FLEET_REGISTERS.md`:
- **Measured** from the video-CPU ROM tables: Qix, Slither, Electric Yo-Yo, Zookeeper.
- **Partly measured, partly derived:** SNK6502.
- **Derived from MAME `set_raw`:** Mr. Do's Castle, Cosmic Guerilla (R4 = 127 / R5 = 7 are documented).

| Game | Source | CLOCKs | Frames | dut vs fixed | stock vs fixed |
|---|---|---|---|---|---|
| qix | MEASURED qix video ROM table | 10 349 984 | 30 | **0** | 0 |
| qix2 | assumed = qix table | 3 183 904 | 10 | **0** | 0 |
| slither | MEASURED (R0 first) | 10 366 048 | 30 | **0** | 0 |
| elecyoyo | MEASURED + per-frame R12/R13 | 9 633 120 | 30 | **0** | 0 |
| elecyoyo_flip | MEASURED, cocktail flip $3FE0 | 9 631 808 | 30 | **0** | 0 |
| zookeeper | MEASURED (trace) | 9 620 672 | 30 | **0** | 0 |
| vanguard | R0 R1 R6 R9 R12/13 MEASURED, rest DERIVED/guess | 5 449 632 | 30 | **0** | 0 |
| fantasy | DERIVED (= vanguard table) | 1 676 832 | 10 | **0** | 0 |
| sasuke | MEASURED start $0000, rest = vanguard | 3 563 248 | 20 | **0** | 0 |
| docastle | DERIVED from MAME set_raw (HD6845S) | 9 144 768 | 30 | **0** | 0 |
| docastle_r4_31 | DERIVED alt R4=31 R5=8 | 2 559 072 | 10 | **0** | 0 |
| cosmicg | R4/R5 DOCUMENTED, rest DERIVED (MC6845) | 8 729 600 | 30 | **0** | 419 328 |

The same tables through the MAME oracle give 0 mismatches for all 10 pairs with knobs applied. On these real games
the default differs from MAME only in:
- VSYNC phase (`vs_r2`);
- MA / RA during the non-displayed adjust lines of Qix / Yo-Yo / Zookeeper / Cosmic Guerilla, where R5 > R9 + 1
  (`engine_t0`);
- the first frame after reset (`first_ma0`);
- read-path details.

`de_fleet` reverted gives **0** differences on every fleet game, Cosmic Guerilla included. The CRTCADJ fix makes the
fleet's DE agree with MAME's flip-flop exactly where the games need it.

One more note: Qix, Slither and Yo-Yo program **R7 = R4 + 1**, so their VSYNC starts in the first adjust line. On a
type 3/4 CRTC (row held at R4 in the adjust) VSYNC would never fire; the `adj_hold` knob shows exactly that
(52 253 characters on the fleet tables).

## 7. Synthesis (Yosys 0.33 `synth_intel_alm -family cyclonev`)

Estimated ALMs = ALUT6 + ceil(ALUT2..5 / 2) + ceil(ARITH / 2) (two LUTs and two FFs per ALM); FF / 2 is the
register floor. "LUT levels" is the worst register-to-register path in LUTs (`verify/synth/depth.py`); every path also
has at most one 14-bit carry chain. Real ALM and timing numbers need Quartus (next session).

| Top | FF | ALUT6 | ALUT2-5 | ARITH | est. ALM | LUT levels |
|---|---|---|---|---|---|---|
| mc6845_fixed (GHDL reference) | 229 | 29 | 152 | 89 | 150 | 5 |
| **crtc6845sv_mc6845 (default)** | 229 | 31 | 148 | 88 | **149** | 5 |
| crtc6845sv_mc6845_motorola | 222 | 32 | 138 | 85 | 144 | 5 |
| crtc6845sv_hd6845s | 231 | 32 | 158 | 80 | 151 | 5 |
| crtc6845sv_um6845r | 223 | 37 | 139 | 85 | 150 | 6 |
| crtc6845sv_ams40489 / ams40226 | 229 | 28 | 199 | 126 | 191 | 7 |
| crtc6845sv_r6545 | 249 | 48 | 199 | 93 | 195 | 5 |
| crtc6845sv_mos6545 | 226 | 16 | 171 | 76 | 140 | 5 |

- No M10K, MLAB or DSP anywhere.
- Default area is at parity with the reference. The FF count is the floor: 117 register bits, 42 address bits
  (`ma_i`, `ma_row`, MA), counters, and the skew pipeline. Further savings would change cycle behaviour under
  mid-line register rewrites, which the brief forbids.
- At roughly 1 ns per LUT level plus routing, and about 0.6 ns for a 14-bit carry, the default's worst path is about
  6 ns. The AMS variants (7 levels, from the Status1/Status2 comparators into DO) come to about 8 ns. All are under
  10 ns. The fleet runs CLOCK at 11-20 MHz.

## 8. Quartus 17.0 rules applied
- No `for (genvar …)`, no generate loops at all.
- No assignment patterns, no size casts, no bit-selects on expressions, no unary minus on casts.
- Every identifier is declared before use.
- The pool wrapper drives its struct output field by field from plain wires.
- `crtc6845sv_r6545`'s optional `PHI2` is `input tri0`.
- One clock, CLKEN-gated counters, the reference's asynchronous active-low reset; the register interface is not
  gated by CLKEN, as in the reference.
- A grep of `rtl/` finds none of the forbidden constructs.
- Not yet compiled in Quartus. That, and real ALM / timing numbers, happen in the local session.

## 9. Not done, limits, open points
- **C128 VDC (MOS 8563 / 8568):** implemented and verified; see section 11.
- **Interlace:** no variant toggles fields or delays the odd-field VSYNC by half a line. The fleet reference
  removed it in 2019, and MAME doesn't model it, so there is no oracle.
- **CPC cycle-level quirks not modelled.** Each needs a CPC-test-suite oracle, which this session did not have:
  - type 0: last-line compare only at C0 < 2, R5 counting rules, R6 = 0 alternating DE;
  - type 1: C4 overflow when R4 is reduced on the last line, the R5 = 0 adjust loop;
  - type 2: HSYNC over C0 = 0 (ghost VSYNC, rolling frame), the last-line state machine;
  - type 3/4: R4 change "at end of line", C9 > R9 handling;
  - per-type register-write I/O latency, per-type light-pen offset.
- **Unverified features:**
  - Type 3/4 Status1 / Status2 bits follow the [ACCC] 21.3.4 table but have no oracle (MAME has none). Status1 b5 is
    the least certain.
  - Mid-frame register rewrites on variants 1-7 are exercised only through the shared engine, which the default
    lockstep covers. The variant-specific paths under rewrites are not oracle-checked.
- **R6545 transparent timing** follows MAME (the datasheet gives no latency). The quantisation of a mid-character
  R31 access is a documented choice.
- **Fleet tables** for SNK6502, Mr. Do's Castle and Cosmic Guerilla are partly derived or guessed. No ROMs or game
  code for them were available. Qix-family tables are measured from the ROM disassemblies.
- **"master repo `rtl/video/`"** copy: not identified (section 2).

## 10. Rerun
`verify/README.md` has every command. Short version:

```bash
./lint.sh
cd verify && ./build_lockstep.sh && ./run_lockstep.sh 16 60000000
./build_fleet.sh && ./build/fleet/fleet
./build_variants.sh && ./run_variants.sh 4 400 && python3 summarize_variants.py results/variants_seed*.log
cd equiv && yosys equiv.ys
```

## 11. C128 VDC (MOS 8563 / 8568): the last phase

Status: **implemented and verified against MAME mos8563.cpp + the C128 documentation**, within the limits listed at
the end of this section. Started only after sections 1-10 were complete and published.

### Design
- `rtl/crtc6845sv_vdc.sv`, `module crtc6845sv_vdc #(parameter int VARIANT = 8)`: 8 = MOS 8563, 9 = MOS 8568.
- **Its own module, not a VARIANT of `crtc6845sv`.** Its port list cannot share the mc6845 drop-in ports: it has a
  16-bit video-RAM bus, RGBI pixels, a dot-clock enable, /INTR and CSYNC. Keeping it separate leaves
  `crtc6845sv.sv` byte-identical (md5 f78a10415ac5ace5e8bc5d1621ae84c2), so:
  - the VDC costs nothing (no logic, no paths) in any design that does not instantiate it;
  - every default / variant proof above stays valid.
  - `crtc6845sv_all.sv` carries it as one more module; Quartus drops an uninstantiated module.
- **6845-derived timing**, the mc6845 engine with the VDC flags MAME uses:
  - 8-bit row counter and R4 / R6 / R7, separate adjust counter, row end latched one line early;
  - interlace fields (R8 = 3), VSYNC width from R3[7:4] (0 = 16), HSYNC width R3[3:0] (0 = 16).
  - On top of that: the 8563 start-address latch (R12/R13 and R20/R21 latched at the first line of vertical
    blank) and MAME's draw counters (R27 row increment, R24 vertical smooth scroll, separate bitmap line address).
- **Video-RAM controller** on a synchronous 64K x 8 port (VDI valid the CLOCK after VA). Priority order:
  1. per-column display fetch FSM (code, attribute, font);
  2. CPU R31 write;
  3. R30 block fill / copy, one byte per character clock as MAME;
  4. R31 read prefetch, re-issued whenever R18/R19 change.
- **R28 bit 4** selects the 4416 (16K) address wiring `(A & $80FF) | ((A & $3F00) << 1) | (A & $0100)`, as
  MAME / VICE / PRG p.333.
- **Pixel pipeline** implements MAME `draw_row` column by column: text and bitmap modes, attributes, alternate
  character set, 16- or 32-byte cells, R23 displayed lines, R22 displayed width and inter-character gap,
  semigraphics, pixel double, R25 horizontal smooth scroll (incl. the extra right-edge column), underline,
  character blink, attribute reverse, cursor, R24 reverse screen, R26 colours, R34/R35 blank-all.
- **Outputs:** RGBI, DE (pixel window), PIXCE (first dot of each pixel), HSYNC, VSYNC, VBLANK. The 8568 adds
  /INTR and CSYNC.
- **Requirement:** CLOCK at least 10 x the character clock (one display fetch needs up to 6 CLOCKs).
  - Every timing next-state value is precomputed and registered one or two CLOCKs ahead and taken on the character
    clock. Static display constants are registered.
  - So a register write takes effect at most 2-5 CLOCKs later; MAME applies writes at character granularity.

### Where the docs win over MAME (each a knob in the oracle, as for the 6845 variants)
Sources: C128 Programmer's Reference Guide (PRG), C128 service manual, VICE; quotes and page numbers in
`docs/VDC_SOURCES.md`, section 8.

| Knob | crtc6845sv_vdc (docs) | MAME | Source |
|---|---|---|---|
| r5e0 | R5 reads back with bits 7:5 = 1 | bit 5 reads 0 (`\| 0xC0`) | PRG p.294; VICE regmask |
| version_8568 | status version 1 on the 8563, 2 on the 8568 | 1 on both | PRG p.331; VICE vdc.h; ACME |
| status_busy | status bit 7 = 0 while an R31 read prefetch, R31 write or block op is pending | 0 only during block ops | PRG p.295-296, p.327; service manual p.37 |
| cursor_vice | cursor on lines R10 .. R11 - 1 (start = end: that line; start > end wraps) | R11 inclusive, mc6845 wrap rules | PRG p.326 ("last line plus 1"); VICE vdc-draw.c |
| blink_fast | cursor / character blink toggle every 8 / 16 frames (1/16, 1/32 frame rate) | every 16 / 32 | PRG p.326, p.329; VICE |
| no_r37_8563 | the 8563 has no R37 (reads FF, writes ignored); the 8568 applies R37 polarity to HSYNC / VSYNC | R37 on both, never applied | PRG p.324; service manual p.40 |

The 8568 /INTR (low on Update Ready 0 → 1, released by a status read or when ready falls) and CSYNC
(HSYNC XNOR VSYNC) follow the service manual p.40. MAME has neither.

Kept as MAME and recorded (no hardware data to choose otherwise):
- the R16/R17 light-pen format (MAME: refresh address; PRG: row / column with offsets);
- R30 counting down during a block op;
- block ops at one byte per character clock;
- R34/R35 only as MAME's "blank everything" case (the docs describe a horizontal blanking window with an unclear
  offset);
- interlace R3 / R5 counted in full lines;
- no R7A revision quirks;
- a copy leaving the R31 fill byte unchanged (VICE sets it to the last copied byte).

All 26 disagreements found are listed in `docs/VDC_SOURCES.md` section 8.

### Verification (`verify/tb/tb_vdc.sv`, `verify/tb/vdc_main.cpp`, `verify/mame/mame8563.h`)
- **Oracle model:** `mame8563.h` transliterates MAME mos8563.cpp (md5 ed1577f0ebf9ac2759c9e116b05ea417) on top of
  the mc6845 base model: register file and masks, status, R31, block copy / fill, update_cursor_state with the
  character blink, frame_start / set_vsync latch, reload / advance / start_draw_line, displayed_width,
  semigraphics_gap and draw_row.
- **Bench:** the 8563 and the 8568 run side by side, each with its own C++ video RAM.
- **Display scenarios:** random static registers and RAM. Checked:
  - every character: HSYNC, VSYNC and the display flip-flop;
  - every displayed line: the R1 x cth pixel window, colour by colour, against MAME's `draw_row` for that line;
  - random reads of every register and of status.
- **Memory scenarios:** R18/R19, R31 reads and writes, R30 fills and copies (R24 bit 7, R32/R33), and status polls,
  including while busy. At the end all 64K of video RAM is compared, for both chips.
- The 8568 is also checked against the 8563 on every dot: same pixels, polarity-adjusted syncs, CSYNC, and the
  /INTR protocol.

**Results** (4 seeds x 400 scenarios, every 4th a memory scenario):
- 11.1 G CLOCKs, 118 591 631 character clocks, 32 295 frames.
- 1 483 129 displayed lines (204 289 379 pixels) compared.
- 19 634 954 register / status reads (5 552 status reads while busy), 12 644 R31 operations, 4 229 block fills / copies.

| Run | Sync | Lines | Reads | Video RAM |
|---|---|---|---|---|
| all knobs | **0** | **0** | **0** | 1 byte (harness artifact, see below) |
| `-r5e0` | 0 | 0 | 366 317 | |
| `-version_8568` | 0 | 0 | 4 919 857 | |
| `-no_r37_8563` | 0 | 0 | 281 653 | |
| `-status_busy` | 0 | 0 | 3 448 | |
| `-cursor_vice` | 0 | 5 980 | 0 | |
| `-blink_fast` | 0 | 180 151 | 0 | |

- **The 1-byte video-RAM difference was the harness, not the RTL.** The end-of-scenario drain gave a fixed 20 000
  CLOCKs. A 135-byte fill on 32-dot characters needs more than that, and the model writes on the character clock
  while the RTL writes a few CLOCKs later, so the cut landed between them. The drain now waits until chip and models
  are idle; that scenario (seed 1, #63) re-runs clean. The confirmation rerun of all 1 600 scenarios with the fixed
  harness gives **0** sync / line / read / video-RAM mismatches (`verify/results/vdc_seed*.log`).
- 8568 vs 8563 on every dot (pixels, polarity-adjusted syncs, CSYNC): 0 differences. /INTR protocol: 0 differences.
- Coverage, in displayed lines compared:

| Feature | Lines |
|---|---|
| text | 1 048 057 |
| bitmap | 435 072 |
| attributes | 753 614 |
| semigraphics | 212 675 |
| pixel double | 239 883 |
| horizontal scroll ≠ 0 | 494 603 |
| vertical scroll ≠ 0 | 437 931 |
| reverse screen | 490 149 |
| R27 ≠ 0 | 514 203 |
| 32-byte cells | 248 590 |
| 4416 map | 748 402 |
| R22 ≠ $78 | 562 607 |
| R23 < R9 | 253 025 |
| cursor blink | 787 283 |
| interlace R8 = 3 | 46 960 |

**Mutation check** (`verify/mutate_vdc.py`, 16 scenarios per mutant; log `verify/results/vdc_mutants.txt`): 16
deliberate bugs, one at a time.

**13 / 16 caught:** attribute colour, cursor, underline, vertical scroll, R27, HSYNC width, VSYNC width, block count,
4416 map, read mask, horizontal scroll, status busy, 8568 /INTR. The three misses:
- **Cursor blink rate and 8563 R37:** too rare in a 16-scenario run. The full campaign does detect both
  (`-blink_fast` 180 151 line differences, `-no_r37_8563` 281 653 read differences).
- **The start-address latch: a real coverage gap.** The display scenarios never rewrite R12/R13 or R20/R21 during
  vertical blank, so MAME's "latched at the first blank line" behaviour is implemented but not exercised. A
  mid-frame start-address scenario is the next test to add.

### Synthesis (Yosys `synth_intel_alm`, Cyclone V)
| Top | FF | ALUT6 | ALUT2-5 | ARITH | est. ALM | LUT levels |
|---|---|---|---|---|---|---|
| crtc6845sv_vdc VARIANT 8 (8563) | 1150 | 81 | 1026 | 733 | 961 | 8 |
| crtc6845sv_vdc VARIANT 9 (8568) | 1154 | 90 | 1022 | 733 | 968 | 8 |

- No M10K, no DSP: the two products (vertical scroll x row step, R1 x character width) are registered shift-add
  trees.
- The FF count is large because of the one-ahead next-state pipeline that keeps the worst path at 8 LUT levels
  (about 8 ns). Without it the design is about 720 FF at 14 levels.

### VDC limits
- The pixel output runs one character (+1 dot) behind the timing counters. The horizontal position of the pixel
  window relative to HSYNC is this design's own; MAME positions its bitmap through a monitor model, so it is not
  compared. Per-line content and per-character sync timing are compared.
- The extra right-edge column (needed for horizontal smooth scroll) must fall inside the line: R1 < R0 (all real
  modes satisfy it).
- Interlace sync+video (R8 = 3) follows MAME's field logic and is in the random mix (46 960 lines compared). It
  inherits MAME's own "fitted, not from hardware" extra-row rule.
- **Not verified:** light pen (LPSTB), R7A quirks, and the 8568 composite-video output (not provided: the RGBI
  outputs are there to build it).
- **Not compiled in Quartus.** As for the 6845, that is the local next step.

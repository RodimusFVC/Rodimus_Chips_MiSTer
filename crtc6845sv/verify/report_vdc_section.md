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

{{VDC_RESULTS}}

**Mutation check** (`verify/mutate_vdc.py`): 16 deliberate bugs, one at a time, each must be reported. {{VDC_MUTANTS}}

### Synthesis (Yosys `synth_intel_alm`, Cyclone V)
| Top | FF | ALUT6 | ALUT2-5 | ARITH | est. ALM | LUT levels |
|---|---|---|---|---|---|---|
{{VDC_SYNTH}}

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
- Interlace sync+video (R8 = 3) follows MAME's field logic and is in the random mix ({{VDC_IL}} lines compared). It
  inherits MAME's own "fitted, not from hardware" extra-row rule.
- **Not verified:** light pen (LPSTB), R7A quirks, and the 8568 composite-video output (not provided: the RGBI
  outputs are there to build it).
- **Not compiled in Quartus.** As for the 6845, that is the local next step.

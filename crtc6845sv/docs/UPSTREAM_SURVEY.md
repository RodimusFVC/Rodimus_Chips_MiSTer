# 6845-family CRTC HDL in the MiSTer-devel org: survey

Date of survey: 2026-10-29. Read-only: no pushes, forks, PRs or issues.

Method:
- Repo list: the 361 `github.com/MiSTer-devel/*` links on the wiki Cores page
  (`raw.githubusercontent.com/wiki/MiSTer-devel/Wiki_MiSTer/Cores.md`, the same source
  `Distribution_MiSTer/.github/download_distribution.py` uses). This session could not
  use the org listing or code-search APIs: the proxy only allows repo-scoped paths,
  and repo-scoped calls for MiSTer-devel also returned "not enabled".
- Each repo was cloned with `--depth 1 --filter=blob:none --no-checkout` into
  `<clone>/survey/repos/`. All tree paths were grepped for
  `6845|6545|46505|crtc`. Every `*.v/*.sv/*.vhd/*.vhdl/*.vh/*.svh` outside `sys/` was then
  checked out and its content grepped for `6845|6545|46505|crtc`.
- Repos holding a 6845 file were unshallowed (blobless) to get the file history
  (`git log --follow`).
- Reference copies are in `<clone>/survey/raw/`: `bbc_mc6845.vhd` (upstream BBC)
  and `beebfpga_mc6845.vhd` (hoglet67/BeebFpga master, md5 226caa61a9a6d5b5fbd64b1e57ad0b8a,
  for lineage only; it is not a MiSTer-devel repo).

## 1. BBCMicro_MiSTer rtl/mc6845.vhd

- Upstream master HEAD is `d37f7d2` (2026-08-30), the same commit as the local clone
  (checked with `git ls-remote`). The local clone is **not** shallow and holds the full
  42-commit history back to 2018-05-17.
- md5 of `rtl/mc6845.vhd` at HEAD and of the raw.githubusercontent copy:
  **e1c74cb714f3ae0431314e6047e9b426** (confirmed).
- `git log --follow -- rtl/mc6845.vhd`:
  - `ad2300a` 2020-05-10 sorgelig "Update sys, re-organize the sources, some tweaks."
    This is a **pure rename** `{src => rtl}/mc6845.vhd (100%)`. The blob is the same
    before and after (`031958788c9e325a5ddaf0ff8be5079abb5e9384`), so the content did not change.
  - `f6f1afb` **2019-09-27** sorgelig "Tweaks for direct video." This is the **last content
    change**, 2 lines:
    - It commented out `odd_field <= not odd_field;`, so interlace never toggles fields.
      `odd_field` stays 0.
    - It changed the VSYNC start from `h_counter = 0` to `h_counter = r02_h_sync_pos`, so
      VSYNC now starts with HSYNC instead of at the line start or half line.
  - `c8efff5` 2018-05-17 initial import (md5 bd80a67f662055a36e539002793e81e4). It already
    had the MiSTer HBLANK/VBLANK ports.
- So the user's belief is right: the content has not changed since 2019-09-27. Only the
  path changed in 2020.

Baseline behaviour of the BBC file, used for the comparisons below:
- **Registers:** R12–R17 readable. Other registers read 0. No status register, no R31.
  R3 high nibble is the VSYNC width (0 = 16 lines). R3 low nibble is the HSYNC width
  (0 = no HSYNC).
- **Interlace:** no real interlace, because the field toggle is disabled. In the R8=11
  mode, RA LSB is the field bit (always 0 here) and lines count in 2s.
- **VSYNC:** starts at character R2 on line 0 of row R7.
- **Skew:** DE skew 01 is treated as 0, and cursor skew 10 is treated as 1.
- **Cursor:** blink comes from field_counter bit 3 or bit 4.
- **Light pen:** rising edge on LPSTB captures MA.
- **R6:** `row < R6` comparison, so R6=0 means no display.
- **No CRTC-type selection.** It is HD6845S-flavoured: programmable VSYNC width and R8 skew.

## 2. Other 6845-family CRTCs in MiSTer-devel

| # | Repo | File | Lang | Lineage / author | md5 | Relation to BBC file |
|---|------|------|------|------------------|-----|----------------------|
| 1 | Arcade-Qix_MiSTer | rtl/cpu/mc6845.vhd | VHDL | BBC copy (RodimusFVC, 2026-02-27) | e1c74cb714f3ae0431314e6047e9b426 | **identical** |
| 2 | Arcade-SNK6502_MiSTer | rtl/video/mc6845.vhd | VHDL | BBC copy (RodimusFVC, 2026-04-01 / 2026-10-28) | e1c74cb714f3ae0431314e6047e9b426 | **identical** |
| 3 | Arcade-DECOCassette_MiSTer | rtl/mc6845.vhd | VHDL | BBC copy (RodimusFVC, 2026-05-18) | 797f5438467856eabd9727ef4093f844 | whitespace/comment only (`diff -w` = 1 comment, 1 blank line); functionally identical |
| 4 | AcornElectron_MiSTer | rtl/mode7/mc6845.vhd | VHDL | Stirling/Banks **pre-MiSTer** original (A. Steremberg import, 2022-01-14) | cca6ffcb9dcdf74420d8af0db2f145b9 | older/purer than BBC (see below) |
| 5 | CBM-II_MiSTer | rtl/mc6845.vhd | VHDL | hoglet67 **BeebFpga** rewrite (2020s), adapted by Erik Scheffers (2024-01-29; resynced 2026-09-05) | 9e36a634e22a108b8a5f4f17a0fdb3ad | different architecture |
| 6 | Amstrad_MiSTer | rtl/UM6845R.v | Verilog | Sorgelig 2018 original; 2023 type-0/1 work by littlelazyexperiment; SNA 2026 | 3985a1ddc5fad1b2d5b0279ad3563a1c | independent, CPC type 0/1 |
| 7 | PCXT_MiSTer | rtl/video/UM6845R.v | Verilog | fork of Amstrad UM6845R (Aitor Gómez, 2023-03 → 2026-10) | 7072fa8c5e16b2a09c9d584b9bc8c084 | CGA/HGC-oriented fork |
| 8 | Tandy1000_MiSTer | rtl/video/UM6845R.v | Verilog | same fork, older stage (Aitor Gómez, 2026-01/02) | bffee62037ae21fef542772e32997878 | ≈ PCjr copy |
| 9 | PCjr_MiSTer | rtl/video/UM6845R.v | Verilog | same fork (Aitor Gómez, 2026-01/03) | b993f470e7ac71322258a140705d8ca9 | Tandy with `hres_mode` renamed `crtc_2x` |
| 10 | PCXT-EGA_MiSTer | rtl/video/UM6845R.v | Verilog | PCXT fork extended to EGA CRTC (Aitor Gómez, 2026-03 → 08) | e796c270650d84c33180639b75538416 | 6845 + EGA register set |
| 11 | Lynx48_MiSTer | rtl/UM6845R.v | Verilog | **early (2018-ish) Sorgelig UM6845R** snapshot (A. Steremberg, 2022-02-25) | cac85bf9bef2b47c4d9a4092f3f70c1a | simple |
| 12 | EG2000_MiSTer | rtl/UM6845R.v | Verilog | same early snapshot + blink/blank (JasonCoombes-hr, 2022-09-23) | e46da763c36636770fe05ef2c2d5e4f2 | simple |

Related support file: CBM-II_MiSTer `rtl/video_sync_crtc.sv` (Erik Scheffers 2025) only
delays HBLANK by 7 clocks. It is not a CRTC.

### Per-implementation differences vs the BBC mc6845.vhd (from reading the code)

**AcornElectron rtl/mode7/mc6845.vhd** (the Banks 2015 original before sorgelig's 2019 tweak)
- **Real interlace:** `odd_field <= not odd_field` is active. The odd field adds an extra
  scanline in the adjust period.
- **VSYNC start:** at `h_counter = 0` in the even field and at `h_counter = R0/2` in the odd
  field (half-line offset). The BBC file starts it at R2.
- **Cursor skew:** `cursor2` is a real 2-char delay. Cursor skew 10 gives 2 chars, not 1.
- No HBLANK/VBLANK ports. Otherwise the same register and readback set.

**CBM-II rtl/mc6845.vhd** (BeebFpga rewrite, 738 lines)
- **New timing core:** concurrent counters with end-of-main, adjust and end-of-frame latched
  at C0=0/1/2 (per RichTW and the CPC CRTC Compendium). HSYNC and DE are R/S flip-flops that
  react to counter compares within one fast clock, and R6 is checked at any character
  (jsbeeb behaviour). Field and cursor-blink counters advance on R6 hit. Has a `VGA` input
  (Mode-7 624-line), a `CLKEN_CPU` write qualifier, and a `test` port.
- **Interlace:** upstream BeebFpga has a real field toggle and an odd-field half-line VSYNC.
  CBM-II forces `odd_field <= '0'` and re-times VSYNC to change only at `h_counter = R2`
  (aligned with HSYNC).
- **Skew and cursor:** DE skew 01/10 gives a real 1/2-char delay, and 11 disables DE. Cursor
  skew 00/01/10 gives 0/1/2 chars. Cursor test is a range (`start ≤ line ≤ end`), not
  start/stop latching.
- **Light pen:** strobe goes through a 4-stage synchroniser. VSYNC width 0 = 16 lines and
  HSYNC 0 = none, as in the BBC file. Same R12–R17 readback. No status register, no R31.

**Amstrad rtl/UM6845R.v** (Sorgelig, CPC)
- **`CRTC_TYPE` input (0 = HD6845S/UM6845, 1 = UM6845R):**
  - Type 1: VSYNC is fixed at 16 lines (`vsc <= 0-1`), DE skew is ignored, R12/R13 read
    back 0, and R31 reads FF. RS=0 reads a **status register** (bit 5 = vertical blanking).
    It also reloads MA from R12/R13 on every line of row 0.
  - Type 0: R0=0 and R4=0 quirks. Last-line, last-row and adjust decisions are latched at
    HCC=0 and confirmed at HCC=2.
- **Real interlace:** the field toggles each frame. The odd-field VSYNC starts at
  `hcc = R0/2`. RA LSB = field in interlace-video mode, and there is a FIELD output.
- **Mid-frame register writes are modelled:**
  - R1 write with C0==new R1 kills HDE.
  - R7 write with row==R7 fires VSYNC immediately, and `vsync_allow` blocks re-trigger in
    the same row.
  - R6 writes are handled per type. R6=0 on type 0 toggles VDE on both clock edges (border
    glitch).
- **Missing features:** HSYNC width 0 gives no HSYNC on both types. No light pen. Cursor has
  no blink (R10 bits 6:5 are ignored) and no skew. R10–R15 are readable, but R16/R17 read 0.
  Snapshot (SNA) register preload.

**PCXT rtl/video/UM6845R.v** (fork of Amstrad, used with `CRTC_TYPE=1` for CGA and Hercules)
- Same type-0/1 core, status register, R31, field/interlace and R6/R7 write handling as Amstrad.
  The difference is that R12/R13 are reloaded **only at frame start** on both types. This
  matches the IBM CGA MC6845 (Area 5150 ISOTEXT).
- **Sync handling:**
  - HSYNC starts 3–4 chars early and goes through a delay line. There is an OSD CRT H/V
    offset, an OSD HSYNC width override, and an OSD VSYNC width override (otherwise 16 on
    type 1).
  - VSYNC starts 1–2 rows early and goes through a delay line, with a `vs_direct` bypass when
    R7 is in the first rows.
  - `HSYNC_REF`/`VSYNC_REF` give un-shifted reference syncs.
- Power-on defaults come from parameters, and R8 resets to 2.
- **Extras:**
  - `composite_phase` toggle on an R0 71h→72h write (8088 MPH).
  - Optional "frame stacking rebuilt" synthetic 114×262 raster for one-frame-per-scanline
    demos.
  - hblank/vblank/line_reset outputs.

**Tandy1000 / PCjr rtl/video/UM6845R.v** (earlier stage of the PCXT fork; identical apart from the `hres_mode`/`crtc_2x` name)
- Same as PCXT minus frame stacking, composite_phase, the REF syncs, the R2-lead wrap guard
  and the vs_direct bypass.
- Keeps the Amstrad type-1 per-line R12/R13 reload.
- HSYNC lead `R2-(3|4)` and VSYNC lead `R7-(1|2)` have no underflow guard, so a small R2 or
  R7 gives no sync.
- Has the OSD HSYNC/VSYNC width overrides and the CRT offset delay line.

**PCXT-EGA rtl/video/UM6845R.v** (PCXT fork turned into an EGA CRTC when `CRTC_TYPE=1 && EGA_RESET_R19≠0`)
- **EGA register meanings:**
  - R4/R5 become H-retrace start/end, and R8 becomes preset row scan.
  - New registers: R16 VSYNC start, R17 VSYNC end (with a write-protect bit), R18 V display
    end, R19 offset, R20 underline, R21/R22 V-blank, R23 mode control, R24 line compare.
  - Overflow bits in R7/R9 give 10-bit vertical counters.
- **Readback:** all registers R0–R24 are readable in EGA mode. The status outputs drive Input
  Status #1 (vretrace window, display enable). There is a 16-bit MA.
- No frame stacking or composite_phase. Not a 6845 model in EGA mode.

**Lynx48 / EG2000 rtl/UM6845R.v** (early Sorgelig UM6845R; both instantiated with `TYPE=0`)
- **Simple counters:** `MA = row_addr + hcc`. `row_addr` advances by R1 at the end of each
  row. No HCC=0/2 latching. R5 adjust is `R5-1` without a zero guard.
- **Status and interlace:** status register on RS=0 with TYPE=1, R31, and type-1 R12/R13
  readback of 0. Field toggle with half-line odd VSYNC. VSYNC width is 16 on type 1, R3 high
  nibble on type 0.
- **Sync outputs:**
  - HSYNC uses a down-counter loaded at `hcc_next==R2` (0 = none).
  - VSYNC is split when HSYNC falls ("separate 2 concatenated VSYNCs").
  - DE is gated by `|R6`, so R6=0 means no display.
- **Differences between the two:** EG2000 adds cursor blink (R10 bits 6:5, frame counter
  bits 4 and 5) and an optional registered `USE_BLANK` HBLANK/VBLANK (HDE extended by one
  char). Lynx48 has combinational hBlank/vBlank and no blink. Neither has a light pen.

## 3. Checked and found to have no 6845 model

- **Sequential timing ROM or fixed timing, not a 6845:** Apple-II_MiSTer (IIe 80-col through
  aux memory, no Videx), PET2001_MiSTer (`pet2001video.v` fixed timing), FM-7_MiSTer (fixed
  timing ported from 77AVEMU), and the Arcade-LaserdiscGames SuperDon board (HD46505
  documented as "fixed timing"; the registers are not modelled).
- **Own video chips, not a 6845:**
  - AcornAtom (6847), C16 (TED), MSX (TMS99xx/V99x8), Oric (ULA), SAM-Coupe (ASIC)
  - Jupiter, Specialist, Vector-06C, OndraSPO186, Odyssey2/Videopac (8244), CoCo2/3 (6847/GIME)
  - TRS-80, Amstrad-PCW (ASIC)
  - ao486 (VGA CRTC in its own VGA core, not 6845-derived)
  - PC88 (`CRTCP.vhd`/`CRTCREGS.vhd`, µPD3301), X68000 (`CRTCX68TXT.vhd`,
    `x68k_native_crtc.sv`), Marty (`towns_crtc.sv`, FM Towns)
  - Seibu arcades (`*_seibu_crtc.sv`: BloodBros, Dcon, DenjinMakai, Godzilla, GundamSD,
    HeatedBarrel, Legionnaire, Raiden, Raiden2, SDGundamRainbow, SeibuCupSoccer,
    SkySmasher), IremM72 (kna70h015), MiSTerLaggy (`crtc.sv` test-pattern timing)
- **Interface only:** Arcade-Arabian/BluePrint/ChampionBaseball/Kangaroo/Vastar carry
  `rtl/chip_pool_pkg.sv` with `mc6845_i_t`/`mc6845_o_t` structs that reference
  `rtl/video/mc6845.vhd`. None of these repos contains a 6845 implementation file.
- All other 6545/46505/6845 hits were numeric constants in sample ROMs or netlists.
- Coverage caveats:
  - When the final content grep ran, the HDL checkout had not finished for Tandy1000,
    X68000 and ao486. Tandy's CRTC was already fetched and is covered. The CRTCs in X68000
    and ao486 are not 6845s.
  - Repos that are not linked from the wiki Cores page were not scanned, for example
    unlisted or archived MiSTer-devel repos.

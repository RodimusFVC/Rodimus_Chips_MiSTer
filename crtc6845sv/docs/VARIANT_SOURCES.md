# 6845-family CRTC variant research: raw notes

Date: 2026-10-29. All downloaded files in this directory are untrusted data. None of them were executed.

## Source key (local file, then URL)

- **[ACCC]**: Longshot (Logon System), *Amstrad CPC CRTC Compendium* v1.11, 08.2026, English.
  - Files: `ACCC1.11-EN.pdf`, `ACCC1.11-EN.txt` (pdftotext -layout).
  - URL: https://shaker.logonsystem.eu/ACCC1.11-EN.pdf
  - Sections used: 4.2, 4.3, 10.x (R9), 11.x (R5), 12.x (R4), 14.x (R3), 15.x (R2/HSYNC), 16.x (R7), 18.x (R6), 19.1-19.3 (R8), 20.3 (R12/R13), 21 (read registers/status), 22.
  - Text line numbers in ACCC1.11-EN.txt: 4.2 ~681, 4.3 ~868, R9 3479, R5 3767, R4 4358, R3 6093, R2 6874, R7 7517, R6 8751, R8 8925, read-back 11455.
- **[MC]**: Motorola MC6845 datasheet.
  - Files: `mc6845_hackaday.pdf/.txt`
  - URL: https://cdn.hackaday.io/files/1670897148735776/6845.pdf
- **[HD-R]**: Hitachi HD46505R (= HD6845R) User's Manual HLN014. This is the R part, not the S part; the OCR is poor.
  - Files: `hd46505r_users_manual.pdf/.txt`
  - URL: https://ftp.mirrorservice.org/sites/www.bitsavers.org/components/hitachi/_dataSheets/HLN014_HD46505R_CRT_Controller_Users_Manual.pdf
- **[SY]**: Synertek SY6545-1 datasheet.
  - Files: `synertek_sy6545.pdf/.txt`
  - URL: https://vgamuseum.info/images/doc/misc/synertek_sy6545.pdf
- **[MOS]**: Commodore/MOS 6545-1 datasheet.
  - Files: `crtc6545_cbm.pdf/.txt`
  - URL: https://cbmmanuals1.classic-computing.de/public/Hardware/Datasheet/crtc6545.pdf
- **[RM65]**: Rockwell RM65-5102 CRTC module manual, which includes an R6545-1 appendix. That appendix is mostly images, and its text extraction did not yield the register tables.
  - Files: `rm65-5102.pdf/.txt`
  - URL: https://theoddys.com/acorn/rockwell/rm_65/rm65-5102_crt_controller_crtc_module/RM65-5102%20CRT%20Controller%20Module%20User's%20Manual.pdf
- **[MAME]**: MAME `src/devices/video/mc6845.cpp/.h`.
  - Files: `mame_mc6845.cpp/.h`
  - URL: https://github.com/mamedev/mame/blob/master/src/devices/video/mc6845.cpp
- **[MiSTer]**: MiSTer Amstrad core `rtl/UM6845R.v`, which implements types 0 and 1 only.
  - File: `mister_UM6845R.v`
  - URL: https://github.com/MiSTer-devel/Amstrad_MiSTer/blob/master/rtl/UM6845R.v
- **[CLK]**: Clock Signal (Thomas Harte) `Components/6845/CRTC6845.hpp`.
  - File: `clk_CRTC6845.hpp`
  - URL: https://github.com/TomHarte/CLK/blob/master/Components/6845/CRTC6845.hpp
- **[C32]**: Caprice32 `src/crtc.cpp`, `src/cap32.cpp`. It emulates type 0 only, so it is of little per-type value.
  - Files: `caprice32_*`
  - URL: https://github.com/colinpitrat/caprice32/tree/master/src
- **[TS]**: Tom Seddon, 6845-tests README. These are hardware tests on a BBC Micro comparing the HD6845 with the VL6845.
  - File: `tomseddon_6845tests_README.md`
  - URL: https://github.com/tom-seddon/6845-tests
- **[PCJS]**: PCjs blog 2018-03-20 on 6845 cursor behaviour, read via WebFetch and not saved.
  - URL: https://www.pcjs.org/blog/2018/03/20/
- **[MSX]**: msx.org wiki, Hitachi HD6845, read via WebFetch.
  - URL: https://msx.org/wiki/Hitachi_HD6845

### Sources that could not be fetched

- **cpcwiki.eu**: every path returned 403 or the Cloudflare challenge. This included `/index.php/CRTC`, `?action=raw` and `/imgs/...UM6845-UMC.pdf`.
- **grimware.org**: 403.
- **web.archive.org**: the connection was reset through the proxy (curl), and WebFetch reported that the domain is blocked.
- **6502.org André Fachat "crtc/diffs.html"** (the source MAME cites for the variant list): 503.
- **cpctech (Kevin Thacker) crtc docs**: 404 or TLS name mismatch.
- **CPCEC, Arnold, ACE-DL sources**: not located. The GitHub search API returned nothing, and I did not pursue it further.
- **Rockwell-branded R6545-1 datasheet text**: not obtained. The R6545-1 data below comes from the SY6545-1 datasheet together with MAME, which treats R6545-1 and SY6545-1 identically: same flags, lines 1151-1204.

## Type identification ([ACCC] 4.2)

| Type | Part |
|---|---|
| 0 | Hitachi HD6845S(P), or UMC UM6845. [ACCC] says these behave identically. |
| 1 | UMC UM6845R (sub-variants 1-A and 1-B) |
| 2 | Motorola MC6845(P) |
| 3 | Amstrad ASIC 40489 (CPC+ and GX4000) |
| 4 | Amstrad "pre-ASIC" 40226. It cannot be distinguished from type 3 unless the ASIC extras are enabled. |

[ACCC] 4.2 note: Get Dexter detected the CRTC by reading R12 at &BF00. R12 is readable on HD6845S but not on MC6845 or UM6845R.

## 1. Register read-back

[ACCC] 4.3 overview table for R0-R17:
- **CRTC 0**: R12-R15 r/w, R16-R17 r, everything else w.
- **CRTC 1 and 2**: R12-R13 w only, R14-R15 r/w, R16-R17 r.
- **CRTC 3 and 4**: R10-R11 r (status), R12-R15 r/w, R16-R17 r.

**Type 0** ([ACCC] 21.2.1):
- Only 5 LSBs of the register number are decoded.
- R12, R13, R14, R15, R16 and R17 are readable. R12, R14 and R16 read bits 7-6 as 0.
- "An attempt to read another register (0 to 255) returns the value 0."
- [MAME] hd6845s agrees: `supports_disp_start_addr_r = true`, and other registers return 0.
- [C32] returns R12-R17 and 0 otherwise.
- [MiSTer] type 0 returns R10, R11, R12, R13, R14 and R15. **This disagrees with [ACCC]**: MiSTer returns R10/R11 on reads and does not return R16/R17. It is MiSTer-specific and probably wrong.

**Type 1** ([ACCC] 21.2.2):
- R14-R17 are readable. R12 and R13 read 0 (MiSTer agrees: CRTC_TYPE ? 0).
- "For CRTC 1, an attempt to read another register returns 0, except for register 31 (and all values whose bits 0-4 are 1) which returns a non-zero value (I got 127 or 255)."
- [MiSTer] returns 0xFF for R31 on type 1. [CLK] returns `dummy_register_` for R31 on UM6845R.
- [ACCC] 21.4: R31 does not really exist on the UM6845R. It is defined on the UM6845E for transparent mode, but a read on the UM6845R still returns non-zero.

**Type 2** ([ACCC] 21.2.2): R14-R17 readable, everything else reads 0.
- [MC] register table: R14 and R15 are R/W; R16 and R17 are R only; R12 and R13 are write-only ("This 14-bit write-only register pair" on the start address).
- [MAME] mc6845: R12 and R13 read 0 ("double checked on datasheet").

**Type 3/4** ([ACCC] 21.2.3):
- Only the 3 LSBs of the register number select the read.
- Mapping (low 3 bits): 0 = R16, 1 = R17, 2 = R10 (Status 1), 3 = R11 (Status 2), 4 = R12, 5 = R13, 6 = R14, 7 = R15.
- "Reading register 4 therefore also means reading register 12 (8+4) or 20 (16+4)".
- Reads work at &BE00 and &BF00 alike. In other words the RS line is ignored on reads, so the "status" port mirrors the register-read port.
- [ACCC] 4.3 shows R12 on type 3/4 without forced-0 high bits. [ACCC] 20.5 notes that R12 bit 3 on CRTC 3 doubles as the 8th printer data bit.
- [MAME] ams40489: R12/R13 readable, no status, and none of the R10/R11 status modelling (simplified).

**Type 3/4 Status 1 (R10)** ([ACCC] 21.3.4.1). Bit, value, condition:

| Bit | Value | Condition |
|---|---|---|
| b0 | 1 | C0=R0 |
| b1 | 0 | C0=R0/2 |
| b2 | 0 | C0=R1-1 (if R0>=R1) |
| b3 | 0 | C0=R2 |
| b4 | 0 | C0=R2+R3 |
| b5 | 0 | if R3h>0: C0=0..R0 on line R3h from Vsync |
| b5 | 1 | if R3h=0: over 15 lines from Vsync |
| b6 | 1 | always 1 |
| b7 | 0 | for C0=0..R0-1, when VMA.lsb=0xFF |
| b7 | 0 | at C0=R0, when VMA'.lsb=0x00 |

**Type 3/4 Status 2 (R11)** ([ACCC] 21.3.4.2):

| Bit | Value | Condition |
|---|---|---|
| b0 | 0 | C4=R4 & C9=R9 & C0=R0 |
| b1 | 0 | C4=R6-1 & C9=R9 & C0=R0 |
| b2 | 0 | C4=R7-1 & C9=R9 & C0=R0 |
| b3 | toggles | every 16 frames |
| b4 | 1 | always |
| b5 | 0 | C9=R9, C0=0..R0 |
| b6 | 0 | always |
| b7 | 1 | (C9=R9 & C0=R0) or (C9=0 & C0=0..R0-1) |

Note: bit 3 of the register number is forced, so R2 and R3 read as R10 and R11.

**Status port (RS=0 read)** ([ACCC] 21.3):
- **CRTC 0**: high impedance. "My CPC CRTC 0 randomly returns 255 or 127."
- **CRTC 2**: high impedance. "always returns 255".
- **CRTC 1**: bit 6 = L, bit 5 = V, other bits 0. "The UMC documentation specifies that bits 0 to 4 and bit 7 are unused... Repeated readings return 0".
  - V = 1 when the "BORDER R6" condition is true. It is updated when C0=R0 and is set by the C4=R6 condition (C9=C0=0). R6=0 used as a "border now" level is NOT reflected.
  - The L legend in the [ACCC] table reads "1 Light pen reading / 0 R16/R17 registers can be read". Its polarity is ambiguous in the table.
- **CRTC 3/4**: mirror of &BF00.
- **UM6845E and R6545E**: U L V xxxxx, where U = 1 is an update event and U = 0 means R31 was read or written.
- [MiSTer] type 1 status = `vde ? 0x00 : 0x20` (bit 5 only, L not modelled).
- [CLK] UM6845R status = status_ | (vsync ? 0x20 : 0). **This disagrees with [ACCC]**: CLK treats bit 5 as VSYNC rather than vertical border.
- [MAME] for all of mc6845, hd6845s and ams40489, status_r returns 0x00. That models the chip driving 0, whereas the real CPC bus floats.

**SY6545-1 / R6545-1** ([SY] Fig. 3):
- Read: R14, R15, R16, R17 (R12/R13 are write-only). R18/R19 (update address) are write-only.
- R31 is a "Dummy Location". Unused bits read as 0, "except for R31, which does not drive the data bus at all, and for CS=1 which operates likewise".
- Status register: bit 7 = UPDATE READY, bit 6 = LPEN REGISTER FULL, bit 5 = VERTICAL BLANKING, bits 4-0 unused and read 0.
- [MAME] r6545_1 and sy6545_1: status d5, d6 and d7 supported, transparent mode supported, R12/R13 not readable.
- [MAME] c6545_1: d5 and d6 only, no transparent mode.
- [MOS] 6545-1 (Commodore): status has only V and LPEN full. Bit 7 is listed as not used, and the part is non-interlace.

## 2. R3

**[ACCC] 14.1 table:**
- CRTC 0, 3 and 4: bits 7-4 = Vsync, bits 3-0 = Hsync.
- CRTC 1 and 2: bits 7-4 = x, bits 3-0 = Hsync.
- Also listed: "MC6845*1" and UM6845E have the Vsync bits. The *1 footnote is not present in the text. It is consistent with [MAME]'s MC6845-1 having `supports_vert_sync_width = true`.
- Vsync: 0 means 16 lines on the chips that have the field.
- Hsync column 1 (CRTC 0, 1): 0 means "No Hsync". Hsync column 2: 0 means 16.

**[ACCC] 14.6:** "When R3=0, CRTC's 0 and 1 do not produce HSYNC (and therefore no interruption). On CRTC's 2, 3 and 4 ... A value of 0 in R3 will generate a HSYNC of 16 µsec".

**[ACCC] 14.2:** CRTC 1 and 2 have fixed 16-line VSYNC. CRTC 0, 3 and 4 use R3h, with 0 = 16. R3h can be changed during VSYNC: writing a value below the current count makes the 4-bit counter wrap (16 + new value).

**[MC] datasheet:** "The vertical sync pulse width is fixed at 16 scan-line times. The HS pulse width may be programmed from 1-to-15 ... If zero is written into this register then no HS is provided."
- **This disagrees with [ACCC]**, which measured 16 µs on a CPC type 2.
- [CLK] comment: "MC6845... no zero-length HSYNC", which agrees with [ACCC].
- [MAME]: 0 means 16 for all variants.

**[SY]:** R3 = V3..V0 H3..H0. "IF BITS 4-7 ARE ALL 0, THEN VSYNC WILL BE 16 SCAN LINES WIDE." The datasheet does not say what H=0 does.

[MiSTer]: no HSYNC when R3l=0 on both type 0 and type 1. Type 1 VSYNC is fixed at 16, type 0 uses R3h with 0 = 16.

[CLK] comments:
- HD6845S: "Zero-width HSYNC available... programmable VSYNC length".
- AMS40226: "fixed-length VSYNC, no zero-length HSYNC". **This disagrees with [ACCC]** on VSYNC.

[MAME] ams40489: `supports_vert_sync_width = false`. **This disagrees with [ACCC]**.

## 3. R8

[ACCC] 19.1, bits 7..0:

| Chip | Bits 7-0 |
|---|---|
| CRTC 0 | Sc Sc Sd Sd x x i i |
| CRTC 1, 2 | x x x x x x i i |
| CRTC 3, 4 | x x Sd Sd x x i i |
| MC6845*1 | Sc Sc Sd Sd x x i i |
| UM6845E | UpdM US Sc Sd Vdrac Vdrad i i |

- **This disagrees with [ACCC] 4.3**, which shows "c c d d i i" for CRTC 3 and 4. The compendium is internally inconsistent on cursor skew for 3 and 4.
- Interlace: 00 = none, 01 = interlace sync, 10 = none, 11 = interlace sync and video.
- Skew (both DISPTMG and CUDISP): 00 = none, 01 = 1 char, 10 = 2 chars, 11 = "Non-output".
- [ACCC] 19.2: R8 = 001100xx gives "BORDER ON" (DE forced off immediately; the pointer keeps counting). With delay +1, border goes off at C0=1 and on at C0=R1+1.

[MC]: "The MC6845 only allows control of the interlace modes as programmed by the low order two bits." Table 3: x0 = normal, 01 = interlace sync, 11 = interlace sync and video.

[MSX] (HD6845): bits 0-1 interlace, 4-5 display delay, 6-7 cursor delay.

[MiSTer]: DE is taken from `de[R8_skew & ~{2{CRTC_TYPE}}]` with de[3] = 0, so skew 3 = DE off. Skew applies on type 0 only.

[SY] R8:

| Bits | Function |
|---|---|
| 1-0 | interlace: x0 = non-interlace, x1 = "Invalid (Do Not Use)" |
| 2 | 0 = straight binary, 1 = row/column addressing |
| 3 | 0 = shared memory, 1 = transparent addressing |
| 4 | DE skew, 1 = delay one character |
| 5 | cursor skew, 1 = delay one character |
| 6 | update strobe: 1 = pin 34 is the update strobe (transparent mode only) |
| 7 | update/read mode: 0 = during h/v blanking, 1 = interleaved in phi2 (transparent mode only) |

[MAME] mode macros: `0x08` transparent, `0x88` transparent phi2, `0x40` update strobe, `0x20` cursor skew, `0x10` DE skew, `0x04` row/column.

## 4. R6

[ACCC] 18.1: "Except on CRTC 3 and 4, R6 is considered immediately on the current C0." DE goes off when C4=R6 and stays off until C4=C9=C0=0.

**Type 0 and 2** ([ACCC] 18.2.2 and 18.3.2):
- Setting C4=R6 mid-line gives immediate, definitive border for the rest of the frame.
- The exception is the first line (C4=C9=0) with R6=0: a conflict in which DE turns on at each character start and off 0.5 µs later, so the line alternates between border and characters. Setting R6>0 during that line cancels it.
- [TS]: HD6845 with R6=0 shows 1 scanline; VL6845 shows empty. "r6: Setting R6 to the current row number will stop the display immediately, even mid-scanline."

**Type 1** ([ACCC] 18.2.3 and 18.3.3):
- R6=0 forces border while the register is 0, at any C0. It is level-sensitive and reversible by writing R6 ≠ C4.
- If C4=R6=0 also holds, the border becomes definitive until a new frame.
- Exception: if C4=R6=0 was already evaluated on the last character of the previous frame, the border can be cancelled.
- [MiSTer] implements type-1 R6 write side effects.

**Type 3/4** ([ACCC] 18.2.4): R6 is tested only at line start (C0=0). Mid-line writes are ignored. R6=0 has no special meaning. C4 does not increment in the adjust area, so with R6=R4 the border also covers the R5 lines.

## 5. R4, R9, R5 and R7 timing

**R9** ([ACCC] 10.x):
- Writing R9 < C9 makes C9 overflow, counting to 31 and wrapping. This applies to types 0, 1 and 2.
- Types 3/4: if C9 > R9 the next C9 is 0. Overflow is impossible.
- Type 0: C9==R9 and C4==R4 are compared only while C0<2 ("last line" state).
  - If the last-line state is true at C0=0 and R4/R9 is rewritten at C0==1 to a value different from C4/C9, a vertical adjust is started even when R5=0.
  - R0<2 forces adjust.
- Type 1: no exceptions. R9=current C9 means C9 goes to 0 on the next line.
- Type 2: has a "Last Line" state machine:
  - evaluated at C0=0 with the new R4 and the old R9;
  - re-evaluated on R4/R9 writes when "Last Line Management" is active (not on the first line);
  - sampled at the last HSYNC char (C0=R2+R3-1) for "Previous Last Line";
  - writes during HSYNC are ignored; an HSYNC starting at C0=0 cancels last-line;
  - two consecutive last lines are not allowed unless the condition was false at the end of HSYNC.

**R4** ([ACCC] 12):
- C4 overflows to 127 if R4 < C4 (all types).
- Type 0: R4=0 at C0<2 works as described above.
- Type 1: R4=0 on the last line of the frame overflows; set R4=0 only when C4=0. Line-to-line ruptures: R4=R9=0 when C4=C9=0.
- Types 3/4: the change takes effect "immediately at the end of the line". CRTC 3 has an exception when the I/O coincides with ROM select.

**R5** ([ACCC] 11):
- **Type 0**: no C5 counter. C9 is reused and compared with R5; C4 = R4+1 is held constant during the adjust.
  - R5>0 must be set before C0=3 of the last line to count.
  - An interlace extra line is added on even frames.
- **Types 1 and 2**: separate C5 counter. C4 increments each time C9=R9 inside the adjust, starting from C4=R4+1.
  - Type 1 bug: writing R5=0 during an adjust leaves the adjust state stuck and C5 loops ([ACCC] 11.3.2). R5 0→>0 at C0==R0 triggers the "RFD" bug (11.6).
- **Types 3/4**: C4 stays equal to R4 and C9 is compared with R5. Writing R5 < C9+1 ends the adjust. C9 cannot overflow.
- Types 1, 2, 3 and 4 consider R5 at every C0 position.

**VSYNC in the adjust area** ([ACCC] 11.5):
- Types 0, 1 and 2: R7 can match a C4 reached during the adjust.
- Type 0: VSYNC is blocked if R7 := C4 is written at C0<2.
- Type 2: R7 := C4 written during HSYNC gives a ghost VSYNC.
- Types 3/4: VSYNC starts only when C4=R7 at C0=C9=0.

**R7** ([ACCC] 16.3, 16.4 and 15.4):
- Types 0, 1 and 2 evaluate C4==R7 at any C0 and C9, so writing R7=C4 mid-row starts VSYNC at once.
  - Type 0: not if written at C0vs<2, which gives a "blocked VSYNC". The mid-line start lengthens VSYNC by R0-C0.
  - Types 1 and 2: VSYNC is counted as if it started at C0=0, so it is shortened.
- Types 3/4: only at C4=R7 with C9=0 and C0=0. No re-entrancy protection, so a new VSYNC fires if the condition persists after VSYNC ends.
- Types 0, 1 and 2 have two protections: no retrigger while VSYNC is active, and no retrigger until the C4==R7 equality changes.
- [MiSTer] has a `vsync_allow` latch and an R7-write immediate trigger.
- [MC] and [MAME] generic: VSYNC starts at the row where C4==R7, at the row boundary.

## 6. Type 2 HSYNC/VSYNC interactions ([ACCC] 15.4.4, 15.5.2, 15.6, 16.4.3, 15.3)

- The VSYNC condition is evaluated at every C0 while C4=R7. If HSYNC is active (C0 in [R2, R2+R3]), a "GHOST VSYNC" occurs: lines are counted and retrigger is blocked, but the VSYNC pin is never asserted.
- If HSYNC covers C0=0 (R2+R3 wraps past R0):
  - the border is not disabled at C0=0, so it stays on;
  - the last-line condition at C0=0 is cancelled, so C4 increments instead of resetting and the frame rolls;
  - R4/R9 writes during HSYNC are ignored for setting last-line.
- R2=0: the VSYNC condition is detected early enough to work normally.
- Examples with R0=63:
  - R2=50, R3=14: display on, no VSYNC.
  - R2=50, R3=15: display off, no VSYNC, C4 overflows.
  - R2=0, R3=6: border, VSYNC present, C4 overflows.
- Types 1, 2, 3 and 4 have a bug when C0=R2 coincides with C0=R2+R3: infinite HSYNC (e.g. R0=0, R2=0, R3=1). Type 0 prevents back-to-back HSYNC.
- Type 2 border: the C0=0 border-off test is skipped during HSYNC.
- R2 write latency: R2 is updated in the 3rd µs of OUT (C),r on types 0, 1 and 2, and in the 4th µs on types 3 and 4 ([ACCC] 14.7).

## 7. Cursor

**[MC]** Table 4, R10 bits 6:5:

| Bits 6:5 | Mode |
|---|---|
| 00 | non-blink |
| 01 | cursor non-display |
| 10 | blink at 1/16 field rate |
| 11 | blink at 1/32 field rate |

The text says "1/16 times or 1/32 times the field period". [SY] gives the same table, and the CAST C6845 sheet agrees per the search snippet. [HD-R] says "Blink, 16 Field Period / 32 Field Period".

[MAME]: the blink counter increments once per frame.
- 0x40 toggles when bit 4 changes, i.e. every 16 frames, which is a period of 32 fields.
- 0x60 toggles every 32 frames, a period of 64 fields.
- **This is likely 2x slower than the datasheet** if "1/16 field rate" means a 16-field period.

Split or inverted cursor (start > end):
- [MAME] mc6845: start>end gives the split form (ra<=end || ra>=start). end > max_ras gives a full block.
- [MAME] hd6845s override: "The HD6845 cursor does not wrap as it does for the MC6845". start>end gives no cursor.
- [PCJS]: on real MC6845-based MDA/CGA boards, start=5, end=4 gives a solid cursor (wrap). Behaviour is card-specific.
- [TS], tested on the BBC with HD6845 and VL6845: "there's no per-row cursor enable latch. Looks like the cursor switches on when cursor is off and raster matches R10, and switches off when cursor is on and raster matches R11", and R11 is inclusive.
  - **This disagrees with MAME's HD6845S "no cursor"**: set/reset behaviour naturally wraps.
  - [MiSTer] uses the same set/reset model for all types.
- [TS]: the HD6845 updates the blink timer when R6 is reached; the VL6845 does so when R4 is reached.
- On the CPC there is no cursor hardware use. CUDISP goes to the expansion port, pin 46 ([ACCC] 22).

## 8. Light pen

- **[MC]**: LPSTB rising edge latches the "current Refresh Address" through an internal synchronizer. The timing figure says "When CRTC detects the rising edge of LPSTB in this period, the CRTC sets the Refresh Memory Address 'M+2' into the LIGHT PEN REGISTER." The value must be software-corrected.
- **[SY]**: "When the LPEN input changes from low to high, then, on the next negative-going edge of CCLK, the contents of the internal scan counter is stored in R16 and R17." The timing note says "address n+2". Status bit 6 goes to 1 on an LPEN strobe and goes to 0 when either R16 or R17 is read by the MPU.
- **[MAME]**: latches MA one character clock after the strobe ("NEXT character"). The latched flag is cleared on an R16/R17 read; a FIXME says it should not clear while LPEN is held high.
- **[HD-R]**: LPSTB is active-high. The 14-bit address is stored and must be software-corrected for delays (Fig. 8-2).
- **Per-CPC-type latch offset**: NOT SOURCED. [ACCC] 22 explicitly does not cover it. LPEN is wired to expansion pin 47.
- [C32] uses a fudge of +4 chars for the Magnum Phaser, which is emulator-empirical.
- Only type 1 (UM6845R) has an L status bit among the CPC types.

## 9. Reset

- **[MC]**: RESET low clears all counters and stops the display, and drives all outputs low (HSYNC is undefined until R2 is programmed). "The control registers of the CRTC are not affected and remain unchanged." RESET=0 with LPSTB=1 is test mode. Display resumes immediately after release; DE and CURSOR stay inactive until the first frame has been displayed.
- **[HD-R]**: same as MC (counters cleared, outputs low, control registers unchanged). RES works only when LPSTB is low.
- **[SY]/[MOS]**: "When RES is low, all internal counters are stopped and cleared, all scan and video outputs are low, and control registers are unaffected... All scan timing is initiated when RES goes high."
- [MAME] reset also clears the light pen latch flag, cursor_addr, address latch, update addr and light pen addr. It marks these as an unproven TODO.
- [MiSTer] reset clears hcc, line, row, in_adj, field, hsc, hde and syncs only.
- **Types 3/4 (ASIC) reset behaviour**: NOT SOURCED.
- [C32] crtc_init sets R0=0x3f, R2=0x2e, R3=0x8e; these are emulator defaults, not reset values.

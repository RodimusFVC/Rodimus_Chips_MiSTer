# MOS 8563 / 8568 VDC: documentation view vs MAME and VICE

Research notes for the SystemVerilog VDC. They record what the Commodore documents
say, what VICE does, and where MAME's `mos8563.cpp` differs from either.

- MAME under test: `mos8563.cpp` / `.h` from mamedev/mame master fetched 2026-10-29 (unmodified, md5
  ed1577f0ebf9ac2759c9e116b05ea417 / fe02d988e2c955045f56f7467a452630), with the base class `mc6845.cpp`
  (md5 aaaff6e62887123c9a8c5de1a30b6682). "MAME:N" means
  `mos8563.cpp` line N; "mc6845:N" means `mc6845.cpp` line N.
- VICE: `vice/src/vdc/*.c` from the GitHub svn mirror, saved in `vice/`. "VICE file:N"
  means a line in that file.
- Page numbers are the printed book page numbers.

---------------------------------------------------------------------------

## 0. Source inventory (all under (research copies, not shipped) )

| File | What it is | Provenance |
|---|---|---|
| `raw/C128_Programmers_Reference_Guide.pdf` | Commodore 128 Programmer's Reference Guide (Bantam 1986), scanned with an OCR layer | zimmers.net `/pub/cbm/manuals/c128/` |
| `raw/C128_PRG.txt` | `pdftotext -layout` of the whole guide | generated |
| `raw/C128_PRG_ch10_8563.txt` | Chapter 10 "Programming the 80-column (8563) chip", pp.291-334, incl. the register-by-register description pp.324-334 | excerpt of above |
| `raw/C128_PRG_ch16_8563_hw.txt` | Chapter 16 hardware spec, "The 8563 video controller", pp.595-599 (pins, status, INIT/RES) | excerpt of above |
| `raw/C128_Service_Manual_314001-08.pdf` + `.ocr.txt` | C128/128D service manual 314001-08 (Nov 1987). 8563: pp.36-38; **8568 "80 column CRT controller" PN 315092: pp.39-40**; video interface pp.31-32 | zimmers.net `/pub/cbm/schematics/computers/c128/servicemanuals/`. The OCR is mine (tesseract), so tables are garbled and the prose is fine |
| `raw/C128_Developers_Package_1987.pdf` + `.txt` | C128 developers package (Oct 1987): kernal change notes (PAL R0/R4 values) | zimmers.net, same dir |
| `raw/chacking1.txt` | C= Hacking #1: Craig Bruce, "Introduction to the VDC" and bitmap/fill notes (sections 2-4) | ffd2.com/fridge/chacking |
| `raw/chacking2.txt` | C= Hacking #2: Craig Taylor, "An In-Depth Look at the 8563" (has known errors, see section 9) | ffd2.com |
| `raw/chacking3.txt`, `chacking4.txt` | Mention 64K VDC RAM use and 40-column mode; little VDC detail | ffd2.com |
| `raw/acme_c128_vdc.a` | ACME assembler library `cbm/c128/vdc.a` (Marco Baye): revision list, kernal defaults, light-pen offsets, R34/R35 meaning, 8568 R37 bits | sourceforge acme-crossass trunk |
| `raw/cc65_c128-vdc.s` | cc65 VDC EMD driver (reading R31 twice per ready check, 64K probe) | github cc65 |
| `raw/csg.chips.info.txt` | CSG chip summary: 8568 adds Update Ready interrupt, composite video, composite sync | zimmers chipdata |
| `raw/wikipedia_MOS_Technology_8568.wiki` | Wikipedia raw wikitext (8568 /INTR, R37 table) | en.wikipedia |
| `vice/*.c,*.h` | VICE `src/vdc`: vdc.c, vdc-draw.c, vdc-mem.c, vdc-snapshot.c, vdctypes.h, vdc.h, vdc-resources.c, vdc-color.c | raw.githubusercontent.com/VICE-Team/svn-mirror/main. The commit id could not be fetched because the GitHub API is blocked here; see `vice/SOURCE.txt` and `vice/SHA256SUMS` |

**Not found:** a standalone 8563 datasheet. Bitsavers returns 403 from this sandbox,
zimmers has none, and archive.org search had no hit. PRG chapter 16 (pp.595-599) and
service manual pp.36-40 are the datasheet-derived text Commodore published.

All downloaded files are inert data. Nothing was executed.

---------------------------------------------------------------------------

## 1. CPU interface ($D600 / $D601)

`/RS` is tied to A0, so the chip mirrors across $D600-$D6FF: even = address/status,
odd = data (PRG p.597; VICE vdc-mem.c:543,570).

### 1.1 Address register (write $D600)
- **6 bits** select R0-R63. PRG p.296 says six bits are needed for 37 registers. PRG
  ch16 p.596 and service manual p.37 say "five least significant bits", which cannot
  address R32-R36, so that is a documentation error.
- MAME `address_w` masks with `& 0x3f` (MAME:294). VICE also masks with `& 0x3f`
  ("VDC ignores values of top 2 bits", vdc-mem.c:150-152). Bits 7:6 are ignored.
- **R38-R63:** reads return `$FF` in both emulators (MAME default `ret = 0xff`,
  MAME:320; VICE `return 0xff` for `update_reg >= 38`, vdc-mem.c:565-569). Writes:
  MAME ignores them. VICE stores them into `regs[64]` (vdctypes.h:96) but never uses
  or reads them back. No document covers R38+.
- On the 8563, **R37** is not documented. Both emulators implement it as RW on every
  revision (see R37 and disagreement D18).

### 1.2 Status register (read $D600)

| Bit | Name | Meaning (docs) | MAME | VICE |
|---|---|---|---|---|
| 7 | STATUS / Update Ready | 0 while a CPU access to VDC RAM, a register access or a block op is pending; 1 when ready (PRG p.295-296, p.327; ch16 p.596; svc p.37) | 0 only during a block fill/copy (MAME:417, :448) | 0 for ~43 CPU cycles after R18/R19/R31 accesses during display, ~4 in border, and for a length-proportional time after R30 (vdc-mem.c:337-343, 495-503, 551-557, 105, 115) |
| 6 | LP | 1 = light pen registers hold a valid latch. Cleared by a CPU read of R16 or R17 (PRG p.327) | `m_light_pen_latched`, cleared on R16/R17 read (MAME:307, 340-341) | same (vdc-mem.c:561-563, 583-585) |
| 5 | VBLANK | Docs: "high while in vertical blanking" (ch16 p.596, svc p.37). Emulators: 1 whenever the beam is outside the R6 displayed rows (top/bottom border, vsync, adjust) | `!m_line_enable_ff` (MAME:303) | `!vdc.display_enable`. The comment says "nothing to do with vertical retrace" (vdc-mem.c:587-591) |
| 4:3 | — | unused (C=Hacking #2) | 0 | 0 |
| 2:0 | VER | version number (PRG p.331; C=Hacking #2) | `m_revision = 1`, fixed, for 8563 **and** 8568 (MAME:155, 300) | 0, 1 or 2 per `VDCRevision` resource; default 2 (vdc-resources.c:112) |

Revision values:

| Part | VER (bits 2:0) | Kernal R25 value | Source |
|---|---|---|---|
| 8563 R7A | 0 | $40 | PRG p.331 table; ACME vdc.a; VICE vdc.h:34 |
| 8563 R8 | 1 | $47 | PRG p.331 |
| 8563 R9 | 1 | $47 | PRG p.331 (C=Hacking #2 also lists only %000 and %001) |
| 8568 (C128DCR) | 2 | $47 | VICE vdc.h:36 (`VDC_REVISION_2 /* 8568 */`); ACME vdc.a "v2: VDC 8568" |

ACME treats bits 4:0 as the version (`vdcstate_VERSIONMASK = %...#####`). The PRG says
bits 2:0. Real chips read 0 in bits 4:3 per both emulators.

**8568 only:** the `/INTR` open-drain output goes low when Update Ready makes a 0->1
transition. It is released (high-Z) when Update Ready is 0 or the CPU reads the status
register (service manual p.40; Wikipedia 8568). The C128DCR leaves it unconnected.

### 1.3 Data register ($D601)
Reads and writes the register selected by the address register. Software waits for
status bit 7 = 1 before **every** $D601 access (PRG pp.296-311), including register
accesses that are not RAM accesses. Only RAM accesses really need the wait.

---------------------------------------------------------------------------

## 2. Register reference R0-R37

Legend: **RB OR-mask** = bits forced to 1 on read-back (unused bits). Sources: VICE
`regmask[]` (vdc-mem.c:54-60); C=Hacking #2 notes ^3/^4/^5/^6 ("unused ... always
returning a binary 1"); MAME `register_r` (MAME:324-361). **Kernal** = value programmed
by the C128 kernal IOINIT (table at $E179, from ACME vdc.a, PRG text, C=Hacking #2 and
the Developers Package). It is **not** a hardware reset value. See section 2.1 on reset.

| R | Hex | Bits | Meaning | RB OR-mask (docs/VICE) | MAME write mask / RB mask | Kernal |
|---|---|---|---|---|---|---|
| 0 | $00 | HT7-0 | Horizontal total: characters per line **minus 1** (PRG p.324) | $00 | $FF / $00 | 126 ($7E). PAL: $7F in later kernals (Dev. Package item 25) |
| 1 | $01 | HD7-0 | Horizontal displayed characters (PRG p.324). Also the per-row address increment base | $00 | $FF / $00 | 80 |
| 2 | $02 | HP7-0 | Horizontal sync position, in characters from the start of display (PRG p.324) | $00 | $FF / $00 | 102 ($66) |
| 3 | $03 | VW3-0 HW3-0 | 7:4 = vertical sync width in scan lines. In interlace sync+video, program **twice** the lines wanted (PRG p.324-325). 3:0 = horizontal sync width "in characters, plus 1" (PRG p.324; wording ambiguous) | $00 | $FF / $00 (MAME: HSW 0 = 16 chars, VSW 0 = 16 lines, mc6845) | $49 |
| 4 | $04 | VT7-0 | Vertical total: character rows **minus 1** (PRG p.325) | $00 | $FF / $00 | 32 NTSC ($20), 39 PAL ($27; $26 in later kernals) |
| 5 | $05 | VA4-0 | Vertical total adjust: extra scan lines. In interlace sync+video, program twice; the duration is half the value (PRG p.325) | **$E0** | $1F / **$C0** (bit 5 reads 0: D1) | 0 |
| 6 | $06 | VD7-0 | Vertical displayed character rows (PRG p.325) | $00 | $FF / $00 | 25 |
| 7 | $07 | VP7-0 | Vertical sync position, in character rows (PRG p.325 "plus 1", ambiguous) | $00 | $FF / $00 | 29 NTSC, 32 PAL (ACME) |
| 8 | $08 | IM1-0 | Interlace: 00/10 non-interlaced, 01 interlaced sync, 11 interlaced sync+video (PRG p.325) | $FC | $03 / $FC | 0 |
| 9 | $09 | CTV4-0 | Character total vertical: scan lines per row **minus 1**. ≥16 selects 32-byte character cells (PRG p.303-304, p.325) | $E0 | $1F / $E0 | 7 |
| 10 | $0A | CM1-0 (6:5), CS4-0 | Cursor mode: 00 solid, 01 none, 10 blink 1/16 frame rate, 11 blink 1/32. Start scan line (PRG p.313, p.326) | $80 | $7F / $80 | $20 (ACME; cursor off at init, then the editor sets $60/$40 shadow $0A2B) |
| 11 | $0B | CE4-0 | Cursor end scan line **plus 1** (exclusive) (PRG p.326; ACME "should be 8 instead of 7") | $E0 | $1F / $E0 | 7 |
| 12 | $0C | DS15-8 | Display start address hi | $00 | $FF / $00 | $00 |
| 13 | $0D | DS7-0 | Display start address lo | $00 | $FF / $00 | $00 |
| 14 | $0E | CP15-8 | Cursor position hi (a RAM address) | $00 | $FF / $00 | — |
| 15 | $0F | CP7-0 | Cursor position lo | $00 | $FF / $00 | — |
| 16 | $10 | LPV7-0 | Light pen **vertical character-row count**: the first row latches 1, then 2, 3... (PRG p.327). Read-only. Reading clears status bit 6 | $00 | read-only / returns **MA hi** (D4) | — |
| 17 | $11 | LPH7-0 | Light pen **horizontal character count**: the leftmost column latches 8, then 9, 10... (PRG p.327; ACME "characters, plus 8"; C=Hacking #2 measured 27-29..120). Read-only. Reading clears status bit 6 | $00 | read-only / returns **MA lo** (D4) | — |
| 18 | $12 | UA15-8 | Update (CPU RAM) address hi. A write starts a RAM read into the R31 latch (PRG p.327) | $00 | $FF / $00 | — |
| 19 | $13 | UA7-0 | Update address lo. Same behaviour | $00 | $FF / $00 | — |
| 20 | $14 | AA15-8 | Attribute start address hi | $00 | $FF / $00 | $08 |
| 21 | $15 | AA7-0 | Attribute start address lo | $00 | $FF / $00 | $00 |
| 22 | $16 | CTH3-0 (7:4), CDH3-0 (3:0) | Character total horizontal: pixels minus 1 (in DBL mode, pixels, with no minus 1). Character displayed horizontal (PRG p.328, see 5.2) | $00 | $FF / $00 | $78 |
| 23 | $17 | CDV4-0 | Character displayed vertical: scan lines **minus 1** of the visible part. ≤ R9 (PRG p.328) | $E0 | $1F / $E0 | 8 (ACME; 7 would suffice) |
| 24 | $18 | COPY, RVS, CBRATE, VSS4-0 | 7: 1 = block copy, 0 = block fill (selects the R30 operation). 6: reverse whole screen. 5: character blink rate (0 = 1/16, 1 = 1/32 frame rate). 4:0: vertical smooth scroll (PRG p.328-329) | $00 | $FF / $00 | $20 |
| 25 | $19 | TEXT/BMM, ATR, SEMI, DBL, HSS3-0 | 7: 1 = bitmap. 6: attribute enable. 5: semigraphics. 4: pixel double. 3:0: horizontal smooth scroll (PRG p.329-332) | $00 | $FF / $00 | $47 (R8/R9/8568), $40 (R7A) |
| 26 | $1A | FG3-0, BG3-0 | 7:4 foreground (used when attributes are off), 3:0 background and border (PRG p.332) | $00 | $FF / $00 | $F0 |
| 27 | $1B | AI7-0 | Address increment per row: bytes skipped after R1 bytes, applied per scan line (bitmap) and per character row (text and attributes) (PRG p.332) | $00 | $FF / $00 | 0 |
| 28 | $1C | CB15-13 (7:5), RAM (4) | Character set base A15-A13. With 32-byte cells only 7:6 are used. Bit 4: 0 = 4416 (16K) addressing, 1 = 4164 (64K) addressing (PRG p.332-333) | $0F | $F0 / $0F | $20 (16K) or $30 |
| 29 | $1D | UL4-0 | Underline scan line (PRG p.333) | $E0 | $1F / $E0 | 7 |
| 30 | $1E | WC7-0 | Word count. **A write starts** a block fill or copy. 0 = 256 (ACME; VICE). ch16 p.596: "Word Count (count-1)" | $00 | $FF / $00 (MAME counts it down to 0) | — |
| 31 | $1F | DA7-0 | CPU read/write data for VDC RAM at R18/R19, auto-incrementing. Also the fill byte (PRG p.327, p.329) | n/a (RAM data) | write = RAM write. Read = RAM read at that moment | — |
| 32 | $20 | BA15-8 | Block copy source address hi. Auto-increments (PRG p.333) | $00 | $FF / $00 | — |
| 33 | $21 | BA7-0 | Block copy source address lo | $00 | $FF / $00 | — |
| 34 | $22 | DEB7-0 | Display enable begin (horizontal blanking end) (PRG p.333, see 5.8) | $00 | $FF / $00 | 125 ($7D) |
| 35 | $23 | DEE7-0 | Display enable end (horizontal blanking start) (PRG p.333) | $00 | $FF / $00 | 100 ($64) |
| 36 | $24 | DRR3-0 | DRAM refresh cycles per scan line (PRG p.334) | $F0 | $0F / $F0 | 5 |
| 37 | $25 | HSYNC (7), VSYNC (6) | **8568 only**: sync polarity. Not in the PRG (it lists 37 registers R0-R36, p.324). Bits from ACME vdc.a and Wikipedia (go64 article). Service manual p.40: "HSYNC/VSYNC polarity ... fully programmable" | $3F | $C0 / $3F, on 8563 as well. Reset 0xC0 (MAME:246) | not written by the kernal (ACME) |

### 2.1 Reset / power-on values
- Documented hardware: **`INIT`** (active low, tied to system /RES on the C128) "clears
  internal control latches, allowing the chip to begin operation" and must be held low
  ≥16 DCLK (svc p.40; PRG p.597). **`RES`** "initializes all internal scan counters,
  but not control registers". It is unused on the C128 (PRG p.597; svc p.38, p.40)
  and on the 8568 "can be used to synchronize the display frame to an external signal".
- **No document gives register reset values.** The kernal programs every register
  (IOINIT). Treat registers as undefined after power-on. Only the internal latches
  (busy state, light-pen flag, presumably the address latch) are cleared by INIT.
- VICE powerup zeroes all registers and then loads R0=126, R1=102, R4=39, R5=0, R6=25,
  R8=0, R9=7, R22=$78, R27=0 (vdc.c:330-341). VICE fills RAM with an $FF/$00 pattern
  (vdc.c:373-376).
- MAME device_start sets R22=$78 and everything else 0 (MAME:111-134). The mc6845 base
  starts with R0=$FF, R9=$1F, R4=$7F (mc6845 device_start). device_reset clears R14/R15,
  R18/R19, the address latch and the light pen (mc6845:1102-1110) and sets R37=$C0
  (MAME:246). MAME fills RAM with the same $FF/$00 pattern (MAME:158-164).

---------------------------------------------------------------------------

## 3. VDC RAM access: R18/R19/R31 and block operations

### 3.1 What the docs say (PRG p.327 "R18, R19 update location / R31 CPU data")
1. **Writing R18/R19 makes the chip read** the RAM location at the new address **into
   R31**. Status bit 7 is 0 while that read is pending and 1 when R31 holds valid data.
2. **CPU read of R31** returns the latched (prefetched) byte. The chip then increments
   R18/R19 and **reads the next location into R31**.
3. **CPU write of R31:** the chip writes the data to RAM at R18/R19, increments R18/R19,
   **reads the incremented location into R31**, then sets Update Ready to 1.
4. "Additional access of R18, R19 or R31 should be avoided until the Update Ready bit
   is a 1."

Consequences and folklore. The VICE test repo forum and a Lemon64 thread report this
second-hand; I could not fetch either directly (403/429):
- R31 is a **prefetch latch**. A read returns the byte fetched when the address was set
  or when the previous access completed, not a byte read at the moment of the CPU
  access. If RAM at the update address changes between the prefetch and the CPU read
  (for example a block op, or software that changed R18 alone), the read returns stale
  data. To get a fresh byte, rewrite R18/R19 (preferably both) and wait for ready, then
  read R31.
- Writing R18 alone also triggers a prefetch, using the old R19. Forum reports say
  writing **R19 before R18** corrupts data, so always write hi then lo. This is not in
  Commodore docs, so treat it as unverified.
- I found **no primary source** for the claim "R31 read returns the byte at the
  PREVIOUS update address". In the PRG model the observable value is the byte at the
  current R18/R19 at the time of the last prefetch, which equals the "current address"
  value if nothing changed. Mark that claim **unverified**.
- Can the prefetch overwrite the fill byte? Not settled by the docs. PRG p.329 says a
  block write repeats "the data in R31". Kernal and Craig Bruce practice is: write the
  fill byte to R31, which performs one write, wait for ready, then write R30. C=Hacking
  #1 §3 says fill uses "the value that you last poked into the VDC RAM data register".
  Fills work on hardware, so the write-data latch is evidently **not** clobbered by the
  post-write prefetch. Either the read and write latches are separate, or the prefetch
  goes elsewhere. A safe RTL model keeps a write-data latch (CPU R31 writes) separate
  from a read-prefetch latch.

### 3.2 Block fill / copy (PRG p.312-313, p.329, p.333; C=Hacking #1 §3)
- **Select the operation** with R24 bit 7 (0 = fill, 1 = copy). **Start it** by writing
  R30. Writing R31 does not start a block op; C=Hacking #2 ^9 says otherwise and is
  wrong.
- **Fill:** set R18/R19, write the data to R31, which writes one byte and leaves
  R18/R19 = start+1. Wait for ready, clear R24 bit 7, then write R30 = N. The chip
  writes the R31 data N more times. "One write cycle will follow the initial write of
  data to R31, so the quantity written to R30 should be one less than the total number
  of memory locations desired" (PRG p.329). Afterwards R18/R19 = address after the last
  location written.
- **Copy:** set R18/R19 = destination, wait for ready, set R24 bit 7, set R32/R33 =
  source, write R30 = N. The chip reads the source and writes the destination, and
  **both** addresses increment for N bytes (PRG p.333). Afterwards R18/R19 = dest+N and
  R32/R33 = src+N (VICE vdc-mem.c:100-103, 118-120; MAME increments both per byte,
  MAME:438-440).
- **R30 = 0 means 256** (ACME vdc.a "0 means 256"; C=Hacking #1 "If you poke a 0 into
  the repeat register it means to fill 256 bytes"; VICE vdc-mem.c:88). MAME reaches the
  same result through the 8-bit `--m_word_count` wrap (MAME:442).
- **Status bit 7** is 0 for the whole operation (PRG p.329 "again waiting for the
  Update Ready Status bit").
- **Timing:** no Commodore figure. Craig Bruce (C=Hacking #1 §3): fill runs at "about 1
  Megabyte per second". VICE approximates the busy time as fill = 0.66 CPU cycles per
  byte and copy = 1.2 CPU cycles per byte, so copy is slower (vdc-mem.c:105, 115).
  MAME: one byte per character clock (8 dots at 16 MHz, i.e. 0.5 µs or 2 MB/s in 80-col
  mode, doubled in DBL mode), with the same speed for fill and copy and a 1-cclk start
  delay (MAME:418, 444). In DBL mode, "8563 RAM bus cycles occur at half the normal
  rate" (PRG p.331).
- **R30 after the op:** docs are silent. MAME counts down to 0 (MAME:442), so R30 reads
  0 afterwards and the remaining count during the op. VICE leaves the written value
  (vdc-mem.c:88).
- **R31 after a copy:** VICE sets R31 to the last byte copied (vdc-mem.c:101), so a
  following fill uses it. MAME leaves `m_data` unchanged (MAME:438). Docs are silent.
- **Kernal note** (PRG p.293 "8563 NOTES"): never use indirect-indexed instructions on
  $D600/$D601, because false bus cycles are acted on. Never access the VDC from IRQ
  handlers.

---------------------------------------------------------------------------

## 4. Video RAM addressing and R28 bit 4

PRG p.332-333 gives the multiplexed address pins (DA7..DA0 carry row/column):

```
4416 mode (R28.4=0): DA7..DA0  row = A7..A0
                                col = A15,A13,A12,A11,A10,A9,A8,A8   (A14 not output)
4164 mode (R28.4=1): DA7..DA0  row = A7..A0
                                col = A15,A14,A13,A12,A11,A10,A9,A8
```

- A 4416 (16K×4, 256 rows × 64 cols) uses column pins DA6..DA1 only. In 4416 mode it
  therefore sees column = A13..A8, so physical address = A & $3FFF (A14 and A15 ignored).
- **4416 addressing with 64K (4164/4464) RAM fitted** (a 64K-upgraded C128 left in 16K
  mode) gives physical = `(A & $80FF) | ((A & $3F00) << 1) | (A & $0100)`. This
  formula follows exactly from the table above (phys bit 9 = phys bit 8 = A8, A14
  dropped). MAME `vram_address` (MAME:273-279) and VICE `vdc_16k_to_64k_map`
  (vdc-mem.c:620-630) both use it. **They agree with the docs.**
- **4164 addressing with 16K (4416) RAM fitted:** the 4416 sees column = A14..A9, so
  physical = `(A & $FF) | ((A & $7E00) >> 1)`. VICE `vdc_64k_to_16k_map`
  (vdc-mem.c:633-641) implements this. MAME has no such mapping: R28.4=1 passes the
  16-bit address straight to the address space (MAME:275-276), so the result depends on
  the driver's RAM map (the device default is 64K RAM, MAME:54). See D24.
- The R28.4 bit does **not** report how much RAM is installed (VICE comment
  vdc-mem.c:484; C=Hacking #2 ^I is misleading). Software detects 64K by testing for
  mirroring (cc65 c128-vdc.s INSTALL).
- C128/early 128D: 2× 4416 = 16K. 128DCR (8568): 64K (4464) (svc p.38; Wikipedia 8568;
  csg.chips.info).
- Refresh (R36): N refresh cycles per scan line. The refresh address is 16 bits; its low
  byte is the DRAM row (PRG p.334).

---------------------------------------------------------------------------

## 5. Display behaviour

### 5.1 Text mode, character fetch
- Screen pointer address = R12/R13 + column, incremented by R1+R27 per character row
  (PRG p.300, p.322-323, p.332).
- Attribute address = R20/R21 + column, incremented by R1+R27 per character row.
- **Character cell size:** R9 < 16 gives 16 bytes/char and 4K per set. R9 ≥ 16 gives
  32 bytes/char and 8K per set (PRG p.303-304). Font address:
  - 16-byte: `{R28[7:5], ALT, code[7:0], ra[3:0]}`, i.e. `(R28&$E0)<<8 | ALT<<12 | code<<4 | ra`
  - 32-byte: `{R28[7:6], ALT, code, ra[4:0]}`, i.e. `(R28&$C0)<<8 | ALT<<13 | code<<5 | ra`.
    PRG p.333: "If R9 is greater than 15, then only bits 7-6 of R28 will be used". MAME
    implements exactly this (MAME:840-847). VICE adds `(R28&$E0)<<8 + ALT*$2000`
    (vdc-mem.c:485; vdc-draw.c:705), which differs from the doc when R28.5=1 (D13).
  - PRG p.304 also says "Bits 4 through 0 of register 9 make up the five least
    significant bits for the address". That sentence is garbled: the scan-line counter,
    not R9, supplies the low bits.
- Scan lines with ra > R23 show no character data (PRG p.328). Both emulators do this
  (MAME:849, VICE vdc-draw.c:700).
- **Fetch timing (8568, service manual p.39):** "The device contains an internal
  80-column double line buffer. This buffer is loaded with Character Pointers and
  Attributes during the Horizontal-Blanking interval (and any blank scan lines). These
  Pointers and Attributes are loaded during one displayed character row for use in the
  next character row." Pointers and attributes are therefore fetched one row ahead.
  Font bytes are fetched per scan line. See D21.
- **Start-address latching:** ACME vdc.a "hardscroll notes": R12/13/20/21 are taken at
  the **end of the display window**, so changes made in the lower border apply only to
  the frame after next. VICE latches at row R6+1 line 1 (vdc.c:681-697). MAME latches
  on the first line after `m_line_enable_ff` drops (MAME:562-567).

### 5.2 R22 horizontal character geometry (PRG p.328, p.330)
- CTH = R22[7:4]: pixels per character minus 1. In DBL mode it is the pixel count with
  no minus 1, and each pixel is 2 DCLKs.
- CDH = R22[3:0]: displayed pixels. Without a gap, CDH = CTH+1. With a gap, CDH =
  displayed pixels minus 1. In DBL mode, write 1 more than these values.
- The emulator table (VICE `displayedwidth[256]`, vdc-draw.c:80-98; MAME
  `displayed_width`, MAME:732-745) is empirical. For CTH < 8: CDH < CTH gives CDH+1
  pixels, CDH = CTH gives **0 pixels**, CDH > CTH gives CTH+1 pixels. CTH ≥ 8 follows a
  further table. The visible part is limited to 8 pixels (DD bus width, PRG p.304).
- PRG p.330: when a gap exists, **CDH must be changed together with HSS**: CDH = (shown
  pixels + HSS) mod (CTH+1), as in the table on p.330. The emulators do not need this
  (D17).

### 5.3 R24 vertical smooth scroll
VSS = R24[4:0] is the first scan line of the first row. Raising it moves the screen up.
At most R9; then reset it to 0 and add R1+R27 to R12/R13 and R20/R21 (PRG p.321-322,
p.328-329). Part of an extra row (N+1 rows) appears at the bottom.

### 5.4 R25 horizontal smooth scroll (PRG p.323, p.330-331; VICE vdc-mem.c:386-407)
- **R8/R9/8568:** HSS = CTH means unscrolled. Each decrement moves the display one pixel
  left, down to 0, which is the maximum scroll. The kernal writes $47 (HSS=7=CTH). R27
  must be ≥1 so a character exists to scroll in. In emulator terms the draw offset is
  `HSS - CTH` pixels (×2 in DBL; VICE vdc-draw.c:585-587; MAME:871).
- **R7A (version 0):** the kernal writes $40 (HSS=0). VICE comment: "in v0 VDC, the left
  border moves to the right as well(!)", and if HSS == CTH, "pixel data of leftmost
  char is missing ... attributes are out of sync ... cursor ... one char to the right".
  Also R27: "v0, where 0 means 0 and all other values mean one more"
  (vdc-mem.c:474-477). PRG p.330: R7A software misbehaves on the left edge of R8/R9, and
  R8/R9 software on the right edge of R7A.
- HSS > CTH, or (DBL and HSS == CTH): VICE blanks the line (vdc.c:806-809, "technically
  ... black in the foreground area, border normal"). MAME draws nothing on that line, so
  the whole line shows border colour (MAME:764-765).

### 5.5 Colours and attributes
Attribute byte (PRG p.301-302; ACME `2rufRGBI`):

| bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|---|---|---|---|---|---|---|---|---|
| text | ALT charset | reverse | underline | blink | R | G | B | I |
| bitmap | bg R | bg G | bg B | bg I | fg R | fg G | fg B | fg I |

| Mode | Pixel=1 colour | Pixel=0 colour | Attr flags used |
|---|---|---|---|
| Text, ATR=1 | attr[3:0] | R26[3:0] | ALT, RVS, UL, BLINK |
| Text, ATR=0 | R26[7:4] | R26[3:0] | none (one charset only) |
| Bitmap, ATR=1 | attr[3:0] | attr[7:4] (one attribute per character cell, R9+1 lines tall) | none |
| Bitmap, ATR=0 | R26[7:4] | R26[3:0] | none |

- PRG p.315 says bitmap data comes from R12/R13 and advances R1+R27 per **scan line**.
  Attributes advance per character row (PRG p.326, p.332).
- Border, inter-character gaps and blanked lines use R26[3:0] (PRG p.332).
- Pixel modifier order in both emulators (VICE vdc-draw.c:711-755; MAME:849-865):
  font AND CDH mask, then underline (ra == R29 gives all 8 pixels plus the gap), then
  blink (char off), then semigraphics extend, then attribute reverse, then cursor
  invert, then R24.6 screen reverse. Screen reverse also applies in bitmap mode. Cursor,
  underline and blink apply in text mode only. PRG p.329: R24.6 "will re-reverse any
  character normally reversed by the cursor and/or the individual character reverse
  attribute".
- RGBI order in a nibble: bit3=R, bit2=G, bit1=B, bit0=I (PRG p.302; C=Hacking #2 ^F).
  Colour 6 (dark cyan) is often called grey. The VDC has no "brown" fix-up (the monitor
  does that).

### 5.6 Semigraphics (R25 bit 5)
The last displayed pixel is repeated through the inter-character gap (PRG p.331). The
emulators use empirical tables (VICE `semigfxtype`, vdc-draw.c:100-117; MAME
`semigraphics_gap`, MAME:748-754). In DBL mode with CTH == CDH, semigraphics is forced
on (VICE vdc-draw.c:207-208, "extra weirdness"; MAME:774).

### 5.7 Cursor and blink
- Cursor: the character at RAM address R14/R15, when it is inside the displayed frame,
  is inverted on lines R10[4:0] .. R11[4:0]-1. **R11 is exclusive** (PRG p.326: "last
  (bottom) scan line ... plus 1"). VICE (vdc-draw.c:316-318): `start ≤ ra < end`;
  start == end shows that one line; start > end wraps (ra ≥ start or ra < end).
- Modes R10[6:5]: 00 solid, 01 off, 10 blink at 1/16 frame rate, 11 blink at 1/32 frame
  rate (PRG p.326; ACME calls 10 "FAST" and 11 "SLOW"). The PRG chapter text p.313 table
  labels 10 "slow" and 11 "fast", which contradicts p.326. Trust p.326.
- Interpretation: "1/16 the frame rate" means one full on+off cycle every 16 frames,
  toggling every 8. VICE does this (`crsrblink[] = {1,0,8,16}`, vdc-draw.c:58; char
  blink `frame_counter & 8/16`, vdc.c:639-643). MAME toggles every 16/32 frames (D11,
  D12).
- Character blink: R24 bit 5: 0 = 1/16, 1 = 1/32 frame rate (PRG p.329). C=Hacking #2
  swaps bits 5 and 6 (an error).

### 5.8 R34/R35 display enable window (horizontal blanking)
- PRG p.333: RGBI is blanked during sync. "R34 is programmed with the number of
  characters from the first displayed character of a row to the first blanked character
  in that row. R35 is programmed with the number of characters from the first displayed
  character of a row to the last blanked character." Blanking applies on all lines.
- With the kernal values (R34=125, R35=100, R0=126, R1=80) the literal PRG wording
  cannot be right. Register names, ACME and C=Hacking agree on this reading:
  **R35 = character position where display enable ends (blanking starts), R34 = position
  where display enable begins again (blanking ends)**, counted modulo R0+1. ACME: R34
  "column to enable display in (6 is left of text)", R35 "column to disable display in
  (86 is right of text)". C=Hacking #2 ^J: "R34 determines the rightmost blanked column,
  R35 the leftmost blanked column ... a value of 6 usually corresponds to the leftmost
  column of the screen, while 85 corresponds to the rightmost".
  - The counter is therefore **offset by about 6 characters** from the display column
    (column 0 = 6, column 79 = 85, using the kernal R2=102 timing). The kernal window
    blanks counts 100..124 and covers the hsync at 102..110.
- Neither emulator implements the window (VICE logs "REG 34/35 unsupported",
  vdc-mem.c:509-519). Both blank the whole line only when (R34 > R0 and R35 ≤ R0) or
  (R34 == R35 and R35 ≤ R0) (VICE vdc.c:810-811; MAME:703).

### 5.9 Interlace (R8)
- 00/10: non-interlaced. 01: interlaced sync. Both fields show the same data, offset by
  half a line. 11: interlaced sync and video. Odd fields show odd scan lines, even fields
  even lines, which doubles the vertical density. R3 VSW and R5 should be even, and
  their durations are half the programmed value (PRG p.325). C=Hacking #2 ^4: change
  R0, R4, R6, R7, R8 for mode 11.
- In mode 11 the row-line counter steps by 2 per field and starts at the field parity.
  At row end the next row starts at `~(ra XOR R9) & 1` (VICE vdc.c:491, 740, 766; MAME
  `advance_draw_line`, MAME:617-636; mc6845:650).
- Neither emulator models the half-line field offset in vsync timing. VICE renders mode
  01 as interlaced (vdc-mem.c:276-279). MAME treats 01 as non-interlaced
  (`interlace_video()` == mode 3 only, mos8563.h:121).

### 5.10 Light pen
A positive edge on LPEN latches the **vertical and horizontal character positions**
(svc p.40; PRG p.597). The first row latches 1, the leftmost column latches 8 (PRG
p.327). Status bit 6 is set and is cleared by a read of R16 or R17.

---------------------------------------------------------------------------

## 6. 8563 vs 8568

| Item | 8563 (R7A/R8/R9) | 8568 (C128DCR, PN 315092) | Source |
|---|---|---|---|
| Status version | 0 (R7A), 1 (R8/R9) | 2 | PRG p.331; VICE vdc.h:34-36; ACME |
| R37 sync polarity | absent (37 registers R0-R36) | bit7 HSYNC, bit6 VSYNC polarity. The kernal ignores it | ACME; Wikipedia (go64 "38th register"); svc p.40 "HSYNC/VSYNC polarity ... programmable" |
| /INTR | none | open-drain. Low on Update Ready 0->1; high-Z when ready=0 or on a status read | svc p.40; Wikipedia |
| CSYNC pin | none (external logic) | **XNOR of internal active-high HSYNC and VSYNC** | svc p.40 |
| CV pin (composite/mono) | none: the C128 derives mono from RGBI externally (3-level, svc p.32) | **OR of R, G, B** | svc p.40; ACME "8568 does a part of this internally" |
| DCLK | — | -01 TTL DCLK, -02 CMOS DCLK | svc p.39 |
| Pinout | 48-pin | 48-pin, **different** pin assignment, not interchangeable | ACME; Wikipedia; svc p.39 |
| RAM | 16K 4416 on the C128 (64K possible) | 64K on the DCR | svc; csg.chips.info |
| Quirk fixes | R7A: HSS/border bug, R27+1 | as R8/R9 ("R9a/R9b" marks of the 8568 are said to work better: csg.chips.info) | VICE vdc-mem.c:386-407, 474-477 |

---------------------------------------------------------------------------

## 7. Known documentation errata (do not implement these)
1. PRG ch16 p.596 / svc p.37: address register "five least significant bits". The real
   width is 6 (PRG p.296; both emulators).
2. PRG p.313 cursor table labels 10 slow and 11 fast. p.326 says 10 = 1/16 and 11 = 1/32.
3. PRG p.304: R9 forms the low character-address bits. The scan-line counter does.
4. PRG p.331 heading "R25(5) PIXEL DOUBLE WIDTH" should read R25(4).
5. PRG p.333 R34/R35 wording does not fit the kernal values (see 5.8).
6. C=Hacking #2: R24 bits 5 and 6 swapped. It says R31 writes start block ops (R30
   writes do). It says ATR=1 limits you to one charset (it is the opposite, PRG p.303).
   It says R28 bit 4 reports the RAM size.
7. PRG p.293 says "16K of RAM" and "thirty-seven registers". The chip addresses 64K, and
   the 8568 has 38 registers.

---------------------------------------------------------------------------

## 8. MAME `mos8563.cpp` vs docs / VICE: disagreement list

"Agree" items are omitted. Each entry gives the MAME location, the conflicting source
and a recommendation for the RTL.

1. **D1: R5 read-back mask.** MAME:329 `m_vert_total_adj | 0xc0`. The write mask is
   `& 0x1f` (MAME:384), so bit 5 reads **0**. Docs: R5 bits 7:5 are unused (PRG p.294
   Fig 10-1; C=Hacking #2 ^3 "bits 5-7 are unused, always returning a binary 1"). VICE
   `regmask[5] = 0xE0` (vdc-mem.c:55). RTL: OR with $E0.
2. **D2: Version bits.** MAME:155 `m_revision = 1` for both devices. MAME:232-249: the
   8568 is identical to the 8563. Docs/VICE: R7A = 0, R8/R9 = 1 (PRG p.331), 8568 = 2
   (VICE vdc.h:36; ACME vdc.a). The RTL needs a revision parameter (0/1/2).
3. **D3: No R7A behaviour.** MAME:871 (`x = hss - cth + 1 + ...`) and the R27 handling
   (MAME:605, :615, :620) implement only R8/R9 semantics. VICE models the v0 border
   shift, the HSS==CTH bug and R27 "+1 when nonzero" (vdc-mem.c:386-407, 474-477). PRG
   p.330-331 documents that the revisions differ.
4. **D4: Light pen registers hold an address, not row/column counts.** MAME:340-341 read
   `m_light_pen_addr`, which mc6845:745-748 loads from `get_ma()`, a **14-bit** MA
   (`& 0x3fff`, mc6845:778). Docs: R16 = character row count (first row = 1), R17 =
   character column count (leftmost = 8) (PRG p.327; ACME "lines, plus 1" / "characters,
   plus 8"; svc p.40 "vertical and horizontal character positions"). C=Hacking #2 ^8
   measured values of 1..25 and 27-29..120. VICE: row and column+22 (vdc.c:415-419).
5. **D5: Update Ready (status bit 7) never drops for single accesses.** MAME clears
   `m_update_ready_bit` only for R30 block ops (MAME:417, :448). Writes to R18/R19 and
   reads or writes of R31 complete instantly (MAME:355, :397-398, :420-422). Docs: bit 7
   is 0 while any RAM read/write is pending, including the prefetch after an R18/R19
   write (PRG p.296, p.327; ch16 p.596). VICE makes it busy for 43 CPU cycles in the
   display area and 4 in the border after R18/R19/R31 accesses (vdc-mem.c:337-343,
   495-503, 551-557).
6. **D6: No R31 prefetch latch.** MAME:355 `read_videoram(m_update_addr++)` reads RAM at
   the instant of the CPU read. PRG p.327: the R18/R19 write triggers a read into R31,
   a CPU read returns the latched byte and then prefetches the next one, and a CPU write
   prefetches the incremented address. VICE also reads at access time
   (vdc-mem.c:546-550), so VICE does not model the doc either. The behaviour is visible
   when RAM changes between prefetch and read, or when only R18 is rewritten.
7. **D7: Fill source after a block copy.** MAME fills with `m_data`, which only CPU R31
   writes set (MAME:421, :438), and a copy does not touch it. VICE sets R31 to the last
   copied byte (vdc-mem.c:101), so a fill that follows a copy without a new R31 write
   uses that byte. Docs: silent. The data path through R31 for copies is implied by
   "data written ... obtained from other memory locations" (PRG p.333). Unverified on
   hardware.
8. **D8: R30 read-back after or during an op.** MAME decrements the register itself
   (MAME:442), so it reads the remaining count and 0 when done. VICE keeps the written
   value (vdc-mem.c:88). Docs: silent.
9. **D9: Block op speed and timing.** MAME runs fill and copy at the same speed, one
   byte per character clock, with a 1-cclk start delay (MAME:418, :444), ignoring
   display/refresh contention. VICE: copy is ~1.8× slower than fill (vdc-mem.c:105 vs
   :115). Craig Bruce measured about 1 MB/s for fill (C=Hacking #1 §3). MAME's 0.5
   µs/byte is about 2 MB/s.
10. **D10: Cursor end line is inclusive in MAME.** mc6845:563
    `(ra >= start) && (ra <= m_cursor_end_ras)`. MAME also applies 6845 rules: end > R9
    gives a full cursor and start > R9 gives no cursor (mc6845:547-561). PRG p.326: R11
    is the last line **plus 1**. ACME: "should be 8 instead of 7". VICE: `ra < R11`, and
    start == end shows a single line (vdc-draw.c:316-318, 740-742). With the kernal
    R10/R11 values, MAME draws one extra cursor line.
11. **D11: Cursor blink twice as slow.** mc6845:835-845 toggles on bit 4 (mode 10) or
    bit 5 (mode 11) of a per-frame counter, giving full periods of 32 and 64 frames. PRG
    p.326: blink "at one sixteenth / one thirty-second the frame rate". VICE toggles
    every 8 or 16 frames (vdc-draw.c:58). Under interlace, MAME's counter advances per
    field (mc6845:672 via frame_start), as VICE's does.
12. **D12: Character blink twice as slow.** MAME:477-486 toggles on counter bit 5 or 4,
    every 32 or 16 frames. PRG p.329: 1/16 (R24.5=0) and 1/32 (R24.5=1) frame rate.
    VICE `frame_counter & 8 / & 16` (vdc.c:639-643; vdc-mem.c:369-373).
13. **D13 (VICE vs doc, MAME agrees): 32-byte charset base.** MAME:846 uses `R28 & $C0`
    plus ALT<<13, matching PRG p.333 "only bits 7-6 ... used". VICE adds `R28 & $E0`
    plus $2000×ALT (vdc-mem.c:485; vdc-draw.c:705), which differs when R28 bit 5 = 1.
    Recorded so the testbench does not "fix" MAME to match VICE.
14. **D14: Interlace sync+video: R3 vsync width and R5 adjust counted in full lines.**
    mc6845:616-626 (vsync width counter per line) and mc6845:656-663 (adjust counter per
    line) run at full rate in mode 11. PRG p.324-325: program twice the value, and the
    duration is half. VICE halves the R5 adjust (`row_counter_y + interlaced == R5`,
    vdc.c:609). VICE uses a fixed vsync height, so it does not model R3 VSW either.
15. **D15: Interlaced-sync mode (R8=01) and the half-line field offset.** MAME treats 01
    as non-interlaced (`interlace_video()` mode 3 only, mos8563.h:121). No MAME mode
    produces the half-scan-line vsync displacement. PRG p.325 describes it for 01 and
    11. VICE renders 01 interlaced (vdc-mem.c:276-279).
16. **D16: R34/R35 horizontal blanking window not implemented.** MAME:703 only blanks the
    whole line in two degenerate cases, copied from VICE vdc.c:810-811. The visible area
    uses fixed `RETRACE_DOTS=40` and `FRONT_PORCH_DOTS=80` (mos8563.h:41-43;
    MAME:503-504) instead of the DE window. Docs: PRG p.333; ACME; C=Hacking #2 ^J
    (section 5.8). VICE does not implement it either (vdc-mem.c:509-519).
17. **D17: R22 CDH and HSS interaction.** MAME applies the CDH mask and gap to the
    shifted character (MAME:792-794, 850, 867, 871), so the gap moves with HSS
    automatically. PRG p.330 says CDH must be reprogrammed together with HSS, with a
    worked table. That implies the displayed/gap window is tied to the **unscrolled**
    character clock. VICE does the same as MAME. Hardware behaviour is unverified, so
    this needs a hardware test.
18. **D18: R37 and 8568 pins.** MAME implements R37 on the 8563 as well: it reads
    `| 0x3f` and resets to $C0 (MAME:246, :361, :429). The polarity is stored but never
    applied to `m_out_hsync_cb`/`m_out_vsync_cb`. The 8568's /INTR (on Update Ready 0->1,
    cleared by a status read), CSYNC = XNOR(HSYNC,VSYNC) and CV = R|G|B outputs (svc
    p.40) are missing. The 8563 has no R37 (PRG p.324), and its read value on real
    silicon is unknown ($FF would be a guess consistent with R38+).
19. **D19: Reset clears registers that hardware does not reset.** mc6845:1102-1110
    clears R14/R15, R18/R19, the address latch and the light pen address. MAME:246 sets
    R37 = $C0. Docs: RES resets scan counters only, "not control registers". INIT clears
    internal "control latches" (PRG p.597; svc p.38, p.40). No register reset values are
    documented. The MAME comment itself says "none of these should reset unless
    otherwise proven" (mc6845:1101).
20. **D20: 14-bit address arithmetic in the base class.** mc6845:643 and :778 mask the
    line address and MA with `& 0x3fff`. The VDC uses 16-bit addresses (PRG p.326
    "complete 16-bit address"). In this MAME copy, drawing uses its own 16-bit counters
    (MAME:597-621), so the mask only affects the light-pen value (D4) and any driver
    using `get_ma()`.
21. **D21: No row-ahead pointer/attribute buffer.** MAME reads screen and attribute bytes
    from RAM at draw time for every scan line (MAME:799, :808). `m_char_buffer` and
    `m_attr_buffer` are declared (mos8563.h:63-64) but unused. Service manual p.39 (8568):
    pointers and attributes are loaded into an 80-column double line buffer during the
    previous row's blanking intervals. So CPU or block writes to screen/attribute RAM
    during a row take effect on the next row. VICE uses `scrnbuf`/`attrbuf`
    (vdc-draw.c:687-689).
22. **D22: Busy/ready during display vs border.** MAME's block op rate is the same in the
    border and in the active display. VICE (vdc-mem.c:339-342) and the general
    DRAM-contention model say CPU access is slower during active display. The docs only
    say "wait for ready". This affects test timing, not results.
23. **D23: Address register width.** MAME (6 bits, MAME:294) agrees with PRG p.296 and
    VICE. It conflicts only with PRG ch16 p.596 and svc p.37 ("five bits"), which are
    erroneous.
24. **D24: 4164 addressing on a 16K machine.** MAME does no 64K-to-16K remap
    (MAME:275-276). The result depends on the driver's map. VICE maps
    `(A&$FF)|((A&$7E00)>>1)` (vdc-mem.c:633-641, 650-652), and this follows from the
    PRG p.333 pin table (section 4). The 4416-mode formula (MAME:278) **agrees** with the
    docs and VICE.
25. **D25: HSS > CTH line content.** MAME:764-765 returns, so the whole line is border
    colour. VICE comment: "technically this should be black in the foreground area
    (border remains normal)" (vdc.c:807). Minor.
26. **D26: VBLANK status bit naming.** MAME:303 and VICE vdc-mem.c:587-591 agree with
    each other: bit 5 = outside the displayed rows. The PRG ch16 p.596 / svc p.37 call it
    "vertical blanking". Recorded so the RTL follows the emulators, which have been
    validated by software such as VDC demos, and not the literal doc wording.

### Where MAME agrees with docs and VICE (no action)
- R30 = 0 means 256. Both addresses increment during a copy, and R18/R19 and R32/R33
  end at start+N.
- Attribute bit layout. Colour rules in text and bitmap mode, with and without
  attributes. Bitmap attributes: fg = low nibble, bg = high nibble.
- Read-back masks of R8, R9, R10, R11, R23, R28, R29, R36 and R37
  ($FC, $E0, $80, $E0, $E0, $0F, $E0, $F0, $3F).
- R38+ reads return $FF. The address latch is 6 bits.
- The 4416-mode remap formula.
- The 16/32-byte cell select at R9 ≥ 16, and the R23 cut-off.
- HSS semantics for R8/R9. DBL-mode CTH semantics.
- The underline/blink/semigraphics/reverse/cursor/screen-reverse ordering.
- Light-pen status bit cleared by a read of R16 or R17.

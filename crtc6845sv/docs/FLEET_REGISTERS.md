# Arcade fleet: MC6845 / HD6845S register tables

Confidence tags:
- **MEASURED**: read out of the game's own code (the CRTC table bytes in a ROM disassembly), from an execution trace, or from a debugger reading noted in a repo.
- **DOCUMENTED**: stated in a source comment (file:line given).
- **DERIVED**: calculated from MAME `set_raw()`, the visible area, the tilemap offset or the board clocks. The calculation is shown.
- **GUESS**: no evidence was found. The value is only a plausible filler for a simulation.

Paths: `QIX` = `<clone>/Arcade-Qix_MiSTer/Useful Information`, `SNK` = `<clone>/Arcade-SNK6502_MiSTer`, `UNI` = `<clone>/Arcade-Universal_MiSTer`, `MAME/` = upstream master (fetched 2026-10-29).

---------------------------------------------------------------------------------------------------
## 1. Qix family (Taito/Taito America; video CPU 6809E; CRTC MC6845 "vid_u18")

CRTC clock: 20 MHz/2/16 = 625 kHz for the Qix, Zookeeper and Yo-Yo boards (MAME/taito/qix_v.cpp:369-374), with 8 px per character (5 MHz dot clock).
Slither has a 21.3 MHz oscillator (qix.h:167). MAME only re-clocks Slither's CPUs, so its CRTC stays at 625 kHz there. On real hardware it might be 665.6 kHz; this is unverified.
Ports: `$9C00` (address) and `$9C01` (data), mirrored over 0x03FE. Zookeeper and Yo-Yo use the mirror `$9FFC`/`$9FFD`.

### Write sequence (MEASURED)
Each game writes its CRTC table in one loop during init, and no other CRTC writes appear in the listing:
```
LDA #$0D ; LDX #table
loop: STA $9C00 (or $9FFC) ; LDB ,X+ ; STB $9C01 (or $9FFD) ; DECA ; BPL loop
```
So the order is **R13, R12, R11 … R0**, and table byte 0 goes to R13. Slither is the exception: it writes R0 first and counts up to R13 (`CLRA … INCA ; CMPX #$EB71`). R14 and R15 are never written, so they keep their power-on values; the cursor is unused.

| Game | Init code | Table |
|---|---|---|
| Qix | qix_videocpu.dasm:7119-7126 (F9A4-F9B2) | $F456 (line 6520) |
| Slither | slither_videocpu.dasm:2985-2994 (E6A6-E6B6) | $EB63 (line 3558) |
| Zookeeper (warm init) | zookeep_video.asm:8332-8338 (E4EC-E4FA) | $B373 (line 2328) |
| Zookeeper (reset) | zookeep_video.asm:10532-10538 (F604-F612) | $FAE2 (line 11054), identical bytes |
| Electric Yo-Yo | elecyoyo_videocpu.dasm:11325-11331 (F317-F325) | $F7A3 (line 11812) |

The Zookeeper execution trace `QIX/traces/zk_video.trace:27-149` confirms the order: the $F609 loop runs first (reset), then the $E4F1 loop (game start). There are no other CRTC accesses in the 64,931-line trace.

### Register values (all MEASURED from the ROM table bytes)
| Reg | Qix / Slither | Electric Yo-Yo | Zookeeper |
|---|---|---|---|
| R0 H total-1 | 40 (0x28) | 38 (0x26) | 38 (0x26) |
| R1 H displayed | 32 (0x20) | 32 (0x20) | 32 (0x20) |
| R2 HSYNC pos | 35 (0x23) | 34 (0x22) | 34 (0x22) |
| R3 sync widths | 3 (0x03): HS=3 ch, VS=16 lines | 3 (0x03) | 3 (0x03) |
| R4 V total-1 | 31 (0x1F) | 31 (0x1F) | 31 (0x1F) |
| R5 V adjust | 17 (0x11) | 11 (0x0B) | 11 (0x0B) |
| R6 V displayed | 32 (0x20) | 32 (0x20) | 30 (0x1E) |
| R7 VSYNC pos | 32 (0x20) | 32 (0x20) | 31 (0x1F) |
| R8 interlace | 0 | 0 | 0 |
| R9 max raster | 7 | 7 | 7 |
| R10 cursor start | 0 | 0 | 0 |
| R11 cursor end | 0 | 0 | 0 |
| R12 start hi | 0x00 | 0x00 (see scroll writes below) | 0x00 |
| R13 start lo | 0x00 | 0x00 | **0x20** |
| R14/R15 | not written | not written | not written |

Raw table bytes in ROM order (R13 first; Slither's is R0 first):
- Qix: `00 00 00 00 07 00 20 20 11 1F 03 23 20 28`
- Yo-Yo: `00 00 00 00 07 00 20 20 0B 1F 03 22 20 26`
- Zookeeper: `20 00 00 00 07 00 1F 1E 0B 1F 03 22 20 26`
- Slither: `28 20 23 03 1F 11 20 20 00 07 00 00 00 00`

Timing that follows from these values:
- **Qix and Slither:** 41 × 8 = 328 px and 32 × 8 + 17 = 273 lines. This matches MAME `set_raw(…, 0x148, 0, 0x100, 0x111, 0, 0x100)` (qix_v.cpp:384). At 625 kHz that is 15.244 kHz and 55.84 Hz.
- **Yo-Yo and Zookeeper:** 312 px and 267 lines, which is 16.026 kHz and 60.02 Hz. Zookeeper shows 240 lines. Its start address 0x0020 skips the first 8 VRAM lines, because the VRAM row offset is `(MA<<6)&0xF800 | RA<<8`.
- **R7 = R4+1** in Qix, Slither and Yo-Yo. VSYNC therefore fires on the first R5 (vertical adjust) line. This only works if the row counter increments past R4 during the adjust lines, as on MC6845/HD6845/UM6845 (CPC CRTC types 0-2; see `docs/research/ACCC1.11-EN.txt:4096-4099`). On a type-3/4 CRTC model VSYNC would never fire.
- **VSYNC wrap on Yo-Yo:** R5 is 11 and VSYNC lasts 16 lines, so VSYNC runs on into lines 0-4 of the next frame.

### Electric Yo-Yo: per-frame start-address rewrites (MEASURED, elecyoyo_videocpu.dasm:1718-1751, AF26-AF70)
- `<$1D` is shared RAM `$801D`. The data CPU sets it to $FF (cocktail flip) or $00 together with the PIA flip control at `$9003` (elecyoyo_maincpu.dasm:13-17, 1380-1387).
- **Not flipped:** the code spins until the scanline latch `$9800` reads `$FF` (the DE rising edge of display line 255). It waits about 15 DECA loops, roughly 60 µs or about 2 lines, so the writes land in vertical blank. It writes the palette bank `$8800`, then **R12=$00, R13=$00**.
- **Flipped:** the code spins until `$9800 == $F7` (line 247), waits the same delay (about line 249, still inside the display), writes the palette bank, then **R12=$FF, R13=$E0**.
  - Only 6 bits of R12 exist, so the start address becomes $3FE0. The first displayed row reads VRAM lines 248-255, and MA wraps 0x3FE0 → 0x0000.
  - The start address takes effect at the next frame start. The palette bank change applies mid-frame (from about line 249).
- `$9800` latches `((MA>>2)&0xF8)|RA` on the DE rising edge (qix_v.cpp:34-46). A simulation must provide this latch for the spin loops to exit.

### Not available locally
There are no video-CPU listings for Qix II, Space Dungeon, Kram or Complex X. The `complexx.asm` file is the 6802 sound CPU.
- **Qix II:** the video ROMs (u3-u10.rmb) differ from Qix. The Qix table is a strong guess.
- **Space Dungeon, Kram, Complex X:** these are later 4K-ROM boards like Yo-Yo. Use the Yo-Yo table (0x26/0x22/0x1F/0x0B/0x20/0x20) as a GUESS.
- MAME gives every set the same `set_raw`, and the CRTC overrides it at runtime, so MAME cannot settle this.

---------------------------------------------------------------------------------------------------
## 2. SNK 6502 (Vanguard, Fantasy, Nibbler, Pioneer Balloon, Sasuke vs Commander, Satan of Saturn)

CRTC clock: 11.289 MHz/16 = 705.6 kHz, with a 5.645 MHz dot clock (MAME/snk/snk6502.cpp:815, 822, 859, 866).
Ports: `$3000`/`$3001` on Vanguard, Fantasy, Nibbler and Pioneer Balloon, `$2000`/`$2001` on one set, and `$B000`/`$B001` on Sasuke and Satan of Saturn (snk6502.cpp:334-446). These ports are write-only, and no game reads the CRTC.

There are no ROMs or disassemblies here, and the repo's verilator/ folder (now only in git history) contains sound simulations only. The evidence is a measurement in a comment:
- `SNK/Useful Information/Ian Suggestions/speech_fixes_2026-08-23/rtl/snk6502.v:442-469` (also in the `cea2239` history of rtl/snk6502.v) records a "MEASURED (MAME debugger, user, 2026-08-04)" result: Sasuke and Satan of Saturn program "an IDENTICAL 6845 register table to Vanguard except … R12/R13. Vanguard = $03FF, satansat family = $0000 … R0 h-total 45, R1 32 displayed, R6 28 rows, R9 8 lines/row".
- The same file at lines 731-732 reads: "real Vanguard CRTC register values R0=0x2C R1=0x20 ... R9=0x07".

| Reg | Value | Source |
|---|---|---|
| R0 | 44 (0x2C) | MEASURED (note above). 45 × 8 = 360 matches set_raw htotal 360 |
| R1 | 32 (0x20) | MEASURED |
| R2 | 36 (0x24) | GUESS: hblank is chars 32-44 and the sync is placed mid-blank |
| R3 | 0x04 | GUESS (HSYNC 4 chars; VSYNC 16 lines on MC6845) |
| R4 | 31 (0x1F) | DERIVED: set_raw vtotal 262 = 32 × 8 + 6 |
| R5 | 6 (0x06) | DERIVED (same calculation) |
| R6 | 28 (0x1C) | MEASURED. 224 lines matches set_raw visible 0-223 |
| R7 | 29 (0x1D) | GUESS (VSYNC at line 232; vblank runs from line 224 to 261) |
| R8 | 0 | GUESS (non-interlaced) |
| R9 | 7 | MEASURED |
| R10/R11 | 0/0 | GUESS (cursor unused) |
| R12/R13 | Vanguard **0x03/0xFF**; Sasuke and Satan of Saturn **0x00/0x00** | MEASURED |
| R12/R13 | Fantasy and Nibbler 0x03/0xFF | DERIVED: same MAME video start as Vanguard (no scrolldy), and the core's MA offset is applied only to the satansat family (rtl/boards/snk6502_board.sv:300) |
| R12/R13 | Pioneer Balloon **0x00/0x3F**? | DERIVED, low confidence: only pballoon has `set_scrolldy(-16)` (MAME snk6502_v.cpp:167-173), i.e. 2 rows (0x40) down from Vanguard's 0x03FF. Its R6/R7 might differ instead |
| R14/R15 | 0 | GUESS |

Timing: 705.6 kHz/45 = 15.68 kHz, and 15.68 kHz/262 = 59.84 Hz. No mid-frame CRTC writes are known. Scrolling uses separate scroll latches, not R12/R13.

---------------------------------------------------------------------------------------------------
## 3. Universal: Mr. Do's Castle family (HD6845S; Do! Run Run, Spiero, Jumping Jack, Kick Rider, Indoor Soccer)

CRTC clock: 9.828 MHz/16 = 614.25 kHz, with a 4.914 MHz dot clock (MAME/universal/docastle.cpp:1096).
Ports: Z80 I/O `0x00` (address) and `0x02` (data), write-only (docastle.cpp:739-740). The idsoccert bootleg uses an SY6845BA with a 10 MHz crystal (docastle.cpp:1568).
Main CPU IRQ = VSYNC. The sub CPU IRQ fires when MA6 rises at HSYNC (docastle.cpp:571-583). MAME's TODO says the schematics drive the IRQ from the CURSOR pin, with "the cursor configured at scanline 0" (docastle.cpp:149-151).

No ROM code was available. Everything below is DERIVED from `screen.set_raw(9.828MHz/2, 0x138, 8, 0x100-8, 0x108, 0, 0xc0) // from CRTC` (docastle.cpp:1111) and the comment at docastle.cpp:1103.

| Reg | Value | Source |
|---|---|---|
| R0 | 38 (0x26) | DERIVED: htotal 0x138 = 312 = 39 × 8 |
| R1 | 32 (0x20) | DOCUMENTED, docastle.cpp:1103 ("program the CRTC for a width of 32 characters") |
| R2 | 34 (0x22) | GUESS (hblank is chars 32-38) |
| R3 | 0x03 | GUESS. On the HD6845S the VSYNC width is R3[7:4], and 0 means 16 lines |
| R4 | 32 (0x20) | DERIVED: vtotal 0x108 = 264 = 33 × 8. The alternative R4=31, R5=8 also gives 264 |
| R5 | 0 | DERIVED (same calculation) |
| R6 | 24 (0x18) | DERIVED: visible 0xC0 = 192 = 24 × 8 |
| R7 | 28 (0x1C) | GUESS (VSYNC at line 224) |
| R8 | 0 | GUESS |
| R9 | 7 | DERIVED: 8×8 tiles; MA6 period gives an IRQ every 4 rows |
| R10/R11 | 0x00/0x00? | DERIVED, weak: the cursor is "at scanline 0". R10 bits 6-5 = 00 means a steady cursor |
| R12/R13 | 0x00/0x80 | DERIVED: tilemap `set_scrolldy(-32)` (docastle.cpp:356) means the display starts at tile row 4 = 4 × 32, assuming VRAM = MA[9:0] |
| R14/R15 | 0x00/0x80 | DERIVED, weak: a cursor on the first displayed character gives a once-per-frame pulse at line 0 |

Timing: 614.25 kHz/39 = 15.75 kHz, and 15.75 kHz/264 = 59.66 Hz. The visible window is trimmed to 240 px by DE gating (docastle.cpp:1103-1108).

---------------------------------------------------------------------------------------------------
## 4. Universal: Cosmic Guerilla (MC6845, TMS9980A)

CRTC clock: 9.828 MHz/16 = 614.25 kHz (cosmicg.cpp:364).
Ports: memory `$3FF1` (address), `$3FF5` (write), `$3FF7` (read) (cosmicg.cpp:236-238). The CPU polls MA8-MA11 through CRU bits 0-3 as a beam-position counter (cosmicg.cpp:169-176). That makes R4=127 meaningful: MA sweeps 0x000 to 0xFE0.

| Reg | Value | Source |
|---|---|---|
| R0 | 38 (0x26) | DERIVED: set_raw htotal 312 = 39 × 8 (cosmicg.cpp:359); hblank is 56 px |
| R1 | 32 (0x20) | DERIVED: 256 px visible; update_row uses `ma & 0x1f` |
| R2 | 32 (0x20) | DERIVED, weak: "CRTC HSYNC = blank + 1 px" (UNI/rtl/boards/tms/tms_board.sv:558) |
| R3 | ? (try 0x03) | GUESS |
| R4 | **127 (0x7F)** | DOCUMENTED: UNI/rtl/video/mc6845.vhd:432-433 ("Cosmic Guerilla: R4 127, R5 7") |
| R5 | **7** | DOCUMENTED (same lines) |
| R6 | 96 (0x60) | DERIVED: visible 192 lines / 2 lines per row. Leaves the 64-line blank of rows 96-127, plus 7 adjust lines |
| R7 | ~108 (0x6C) | GUESS: VSYNC about 24 lines into the 64-line blank (tms_board.sv:559 describes the core's regenerated sync) |
| R8 | 0 | GUESS |
| R9 | **1** | DERIVED: update_row uses `ra & 1` (cosmicg.cpp:206,218), and 128 × 2 + 7 = 263 matches set_raw vtotal 263 |
| R10/R11 | 0 | GUESS (cursor unused) |
| R12/R13 | 0x00/0x00 | DERIVED: offset = MA[4:0] \| RA0<<5 \| MA[11:5]<<6 starts at VRAM 0 on screen line 0 |
| R14/R15 | 0 | GUESS |

Timing: 15.75 kHz and 59.89 Hz. Note on R4 = 127: the row counter must not let DE come back on during the R5 adjust lines (the CRTCADJ fix, mc6845.vhd:432).

---------------------------------------------------------------------------------------------------
## Sources not found
- No ROMs or program disassemblies for SNK6502, docastle or cosmicg exist on disk.
- No CRTC-writing verilator testbench exists in any of the three repos or their full git histories. The SNK history was deepened to 56 commits and its verilator/ is sound-only; the Universal repo has 19 commits.
- Upstream MAME has no register-value comments beyond those cited above.

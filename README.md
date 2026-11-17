# Rodimus_Chips_MiSTer

Chip implementations written for the Rodimus MiSTer arcade cores: CPUs, MCUs, sound and speech chips, peripherals and
custom chips, in SystemVerilog / Verilog. **This repo is the authoritative source for every chip in it.** The fleet's
master template (`RodimusCoresMaster_MiSTer`) and the cores copy from here.

One folder per chip: `rtl/` (the files a Quartus project compiles), `README.md` (origin, files, fleet users, status),
and `verify/` + `REPORT.md` where a verification suite exists.

## Chips

| Chip | Imported from | Status |
|---|---|---|
| [`t80sv`](t80sv/) | cloud rewrite 2026-10-29 | ✅ HW-verified in 14 cores |
| [`t65sv`](t65sv/) | cloud rewrite 2026-10-29 | ✅ HW-verified in all 6 eligible cores (SNK6502, Nintendo, Exidy, PunchOut, Gottlieb, Centipede) |
| [`t48sv`](t48sv/) | cloud rewrite 2026-10-29 | ✅ HW-verified in 2 cores (Nintendo, SegaG80) |
| [`s2650sv`](s2650sv/) | cloud rewrite 2026-10-29 | ✅ HW-verified in Centipede · ⚠️ upstream licence unconfirmed |
| [`crtc6845sv`](crtc6845sv/) | cloud rewrite 2026-10-29 | ✅ HW-verified in 2 cores (Universal, SNK6502) · ⚠️ non-commercial licence (mc6845.vhd) |
| [`x86sv`](x86sv/) | own design 2026-11-03 | ✅ complete (checkpoint 9, 2026-11-04); in **Gottlieb** (8088, HW 2026-11-04) and **LaserdiscGames** (8088, HW 2026-11-04; Mach 3 open there), both byte-identical to checkpoint 9 (`x86sv_all.sv` md5 e06b9929): 8088 SingleStepTests 3,007,000/3,007,000 + 42 directed; 8086 (BUS16) 646,000/646,000; V20 3,125,000/3,125,000 (timing fitted); V30 registers / RAM 100 % (timing inferred); V20 / V30 `NEC8080` 8080 mode: own suite `verify/suites/v20_8080` 657,673/657,673, 8080EXM 25/25, 44 directed. Quartus 17 at 80 MHz: 8088 1,988 ALMs +3.02 ns … V30+8080 3,136 ALMs +1.92 ns. Pool types `i8088` / `i8086` / `v20` / `v30` (master `chip_pool_pkg`), wrappers `rtl/x86sv_fleet.sv` |
| [`m68ksv`](m68ksv/) | own design 2026-11-14 | 🟡 complete in simulation + Quartus (checkpoints 1–6, 2026-11-17; `m68ksv_all.sv` md5 62430834), **not yet run on hardware**. One core for 68000 / 68008 / 68008FN / 68EC000 / 68010 / 68020 / 68EC020 (`CPU` parameter), `RES` = BRAM-heavy (default) / logic-heavy. Verification:<br>• 68000: SingleStepTests 794,139 / 794,139 on every column; fx68k pin-exact lockstep; MAME 68008 lockstep; Amiberry cycle-exact 68000 settled the suite disputes<br>• 68010: Musashi lockstep, 0 mismatches<br>• 68020: Musashi lockstep, plus WinUAE's behaviour from an Amiberry run<br>Quartus 17, 68000: 1,785 ALMs / 16 M10K / 113.8 MHz (logic-heavy 1,990 / 7 / 117.8; fx68k 2,047 / 6 / 100.0). Details: `m68ksv/REPORT.md` (Handover section), [[m68ksv_2026-11-17]] |
| [`adc0804`](adc0804/) | PolePosition | ✅ one version |
| [`digitalker`](digitalker/) | Galaxian | ✅ one version |
| [`dlogic`](dlogic/) | RodimusCoresMaster | ✅ one version |
| [`dsnd_engine`](dsnd_engine/) | RodimusCoresMaster | ✅ one version (SpaceInvaders moved 2026-11-02, WAVs byte-identical, HW) · one `verify/` kit (2026-11-03) |
| [`eeprom_93c46`](eeprom_93c46/) | Centipede | ✅ HW in Centipede (Multipede) · SpaceInvaders (compile byte-identical) |
| [`hc55516`](hc55516/) | Williams | ✅ one version |
| [`hd38880`](hd38880/) | SNK6502 | ✅ one version |
| [`hmcs40`](hmcs40/) | ChampionBaseball | ✅ one version |
| [`i8255`](i8255/) | SegaSystem1-2 | ✅ one version |
| [`i8257`](i8257/) | Nintendo | ✅ one version |
| [`m6803`](m6803/) | Irem1 | ✅ one version |
| [`jt680x_6802`](jt680x_6802/) | jtcores (jotego, unmodified) + our 6802 microcode | ✅ HW in Qix 2026-11-05 · Williams / SpaceInvaders to move from their old edited copy |
| [`k084`](k084/) | Vic20-Ian (Tutankham) | ✅ HW in Tutankham; Konami82 |
| [`mb88`](mb88/) | Galaga | ✅ one version |
| [`mc3417`](mc3417/) | Exidy | ✅ one version (2026-11-15; Exidy 440 = future MC3417 + MC3418 user) |
| [`mc68705p3`](mc68705p3/) | Qix | ✅ one version |
| [`namco_05xx`](namco_05xx/) | Galaga | ✅ one version |
| [`namco_06xx`](namco_06xx/) | Galaga | ✅ one version (PolePosition too, 2026-11-11) |
| [`namco_15xx`](namco_15xx/) | Namco6809 | ✅ one version |
| [`namco_50xx`](namco_50xx/) | Galaga | ✅ one version |
| [`namco_51xx`](namco_51xx/) | Galaga | ✅ one version (PolePosition too, 2026-11-11) |
| [`namco_52xx`](namco_52xx/) | Galaga | ✅ one version (PolePosition too, 2026-11-11) |
| [`namco_52xx_snd`](namco_52xx_snd/) | Galaga | ✅ one version |
| [`namco_53xx`](namco_53xx/) | Galaga | ✅ one version (PolePosition too, 2026-11-11) |
| [`namco_54xx`](namco_54xx/) | Galaga | ✅ one version (PolePosition too, 2026-11-11) |
| [`namco_54xx_snd`](namco_54xx_snd/) | Galaga | ✅ one version |
| [`namco_62xx`](namco_62xx/) | Namco6809 | ✅ one version |
| [`namco_io`](namco_io/) | Namco6809 | ✅ one version |
| [`namco_wsg3`](namco_wsg3/) | Galaga | ✅ one version |
| [`namco_wsg8`](namco_wsg8/) | PolePosition | ✅ one version |
| [`pokey_cx`](pokey_cx/) | ThePokeyProject (retired) | ✅ HW in Centipede; lockstep 0 divergences vs MAME |
| [`pia6821`](pia6821/) | Williams | ✅ HW in Qix (6 PIAs, 2026-11-04) · Exidy / Williams moved, rebuild pending |
| [`pit8253`](pit8253/) | own (MAME port) 2026-10-30 | ✅ lockstep 0 divergences (MAME + 2 Intel datasheet rules, 2026-11-15); Exidy moved 2026-11-15 (HW pending) · SegaVICDual on the pre-rule copy |
| [`ptm6840`](ptm6840/) | Exidy | ✅ one version |
| [`riot6532`](riot6532/) | RodimusCoresMaster | ✅ one version |
| [`rp2a03`](rp2a03/) | Nintendo | ✅ one version |
| [`sc01`](sc01/) | Gottlieb | ✅ one version |
| [`sega_315_5018`](sega_315_5018/) | CrazyClimber | ✅ one version |
| [`sega_decrypt`](sega_decrypt/) | SegaSystem1-2 | ✅ ids 1-27 (2026-11-15: +315-5013 / 5014 / 5061 for Sega82); SegaSystem1-2 still has the ids 1-24 copy |
| [`sp0250`](sp0250/) | SegaG80 | ✅ one version (SegaG80, Galaxian) |
| [`sn76477`](sn76477/) | Nintendo | ✅ one version |
| [`sn76489sv`](sn76489sv/) | own design 2026-11-05 | ✅ 7 variants tick-exact vs MAME `sn76496.cpp`; HW in Qix (Slither) 2026-11-05 · replaces jt89 (Sega-flavoured) for TI chips |
| [`tc8830f`](tc8830f/) | Konami82 | ✅ one version |
| [`tms5220`](tms5220/) | PolePosition, Qix, Exidy (all through `tms5220_rsws`, type `tms5220rsws`) | ✅ bit-exact vs MAME (verify/ rig, 0 mismatches); one version everywhere (2026-11-11) |
| [`tms36xx`](tms36xx/) | RodimusCoresMaster | ✅ one version |
| [`tms5110`](tms5110/) | CrazyClimber | ⚠️ differs in SpaceInvaders |
| [`vlm5030`](vlm5030/) | PunchOut | ✅ one version |
| [`williams_sc`](williams_sc/) | Williams | ✅ one version |
| [`z80ctc`](z80ctc/) | BallyMidwayMCR | ⚠️ MAME port, datasheet audit pending · differs in LaserdiscGames (no `zc_to`) |
| [`z80dma`](z80dma/) | Nintendo | ✅ one version |
| [`z80pio`](z80pio/) | SegaSystem1-2 | ✅ one version |
| [`z8002`](z8002/) | PolePosition (own design 2026) | ✅ one version (PolePosition, both game CPUs); pool types `z8002_i_t` / `z8002_o_t` |

## Pending unification (several fleet versions, one to become the reference)

| Chip | Versions |
|---|---|
| MSM5205 | Irem1 vs Universal |
| TMS5110 | here = CrazyClimber's; SpaceInvaders differs |
| SN76477 | here = Nintendo's full chip; SNK6502 noise-only section to fold in |
| SC-01 | here = Gottlieb's MAME port; LaserdiscGames uses a sample player |

## Licenses

Every chip folder has a `LICENSE` (our line, each upstream's attribution, the upstream terms). Most chips are ports
of MAME devices (BSD-3-Clause); the CPU rewrites carry their VHDL originals' BSD-style terms (T80, T65, T48).
Best-effort cases, carried as the upstream states them:
- `mb88`: Dar's `mb88.vhd` terms (educational use only; not open source).
- `crtc6845sv`: Mike Stirling's `mc6845.vhd` terms (non-commercial use only); its VDC part is MAME BSD-3.
- `s2650sv`: `sgs2650` (TEMlib) states no licence; offered under its upstream (Arcadia_MiSTer) terms.

**These attributions are our best reading of the sources. If anything is wrong, incomplete or not what an author
intended, please open an issue on this repository and it will be corrected.**

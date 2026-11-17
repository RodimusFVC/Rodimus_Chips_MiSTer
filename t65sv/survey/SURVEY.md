# T65 (6502 VHDL core) copies in MiSTer-devel repos vs. "Ver 315 SzGy April 2020"

Survey date: 2026-10-29. Reference: `/home/user/ext/galaxian/rtl/cpu/T65/` (T65.vhd `4f4b9f2b…`, T65_ALU.vhd `e53ea5b5…`, T65_MCode.vhd `2085d347…`, T65_Pack.vhd `5451562e…`).

**Provenance of the reference:** it is byte-identical to `MiSTer-devel/C64_MiSTer` / `C128_MiSTer` `rtl/t65/` at commit `351ced1` (2020-04-30, sorgelig, "T65: unstable undocumented opcode fixes"), i.e. the first Ver 315 drop into MiSTer, *before* the 2020-05-22 "T65: minor update for unification" commit that added `BCD_en`.

## Method / limitations

* The GitHub REST/code-search API is blocked in this session (403 "sessions are bound to their configured repositories"), so `gh search code` was impossible. Instead the repo list was taken from the MiSTer wiki `Cores.md` (the list `Distribution_MiSTer` builds from: 361 MiSTer-devel repos) plus ~70 guessed names (365 unique existing repos). Each was cloned treeless (`--depth 1 --filter=blob:none --no-checkout`) and its tree scanned for `t65|6502|65c02|cpu65|65xx|2a03|6510` file names. Repos with T65 were then unshallowed (blob:none) for `git log` dates. Repos that are not linked from the wiki (archived, private, renamed) may be missed.
* md5 columns are of the files as committed (raw bytes). Many copies differ only by CRLF vs LF and/or a trailing newline, so copies were grouped by a *normalized* hash (CR and trailing blanks stripped). "Last change" = committer date of the last commit touching the four T65 files in that repo.
* Raw unified diffs (`diff -u --strip-trailing-cr`, reference -> variant), one per normalized variant: `/home/user/survey/diffs/<representative-repo>.diff` (header lists all member repos). `BBCMicro_MiSTer.diff` is empty (identical to the reference).
* Fetched sources: `/home/user/survey/files/<repo>/<path>/`; treeless clones: `/home/user/survey/trees/<repo>`.

## Variant groups (semantic summary vs. Ver 315 reference)

| Grp | Lineage / origin | Members | Diff vs. Ver 315 (semantic) |
|---|---|---|---|
| **A** | C64_MiSTer@351ced1 (2020-04-30) | BBCMicro, Arcade-Centipede, Arcade-DECOCassette, Arcade-SNK6502 | **Identical** (byte-identical md5s). |
| **B** | **C64_MiSTer HEAD 66acee6 (2026-06-08)** = C128 a7ed50c (2026-06-06) = CBM-II 021ff7d (2026-09-05, "Incorporate upstream change to rtl/t65 from C64_MiSTer") | C64, C128, CBM-II | Ver 315 **+ `BCD_en` input** (ALU decimal gating) **+ default values on Rdy/Abort_n/IRQ_n/NMI_n/SO_n** (2020-05-22) **+ interrupt-handling rework by gyurco** (IRQReq/NMIReq, 2022-11) **+ S decremented during reset for Mode="00"** (2022-11) **+ NMI_ack now a 1-cycle pulse at MCycle="001"** with BRK/NMI-hijack comments (2026-06, ported from C64MEGA65). MCode unchanged. |
| **C** | C64_MiSTer@50032d9 "T65: rework interrupt handling (gyurco)" (2022-11-14) = VIC20 c0c9a99 (2022-11-30) | VIC20, TK2000, Arcade-BlackWidow, -Asteroids, -DonkeyKong3, -MajorHavoc, -MarbleMadness2, -Tempest | As B but without the 2026 NMI_ack change: BCD_en + port defaults + IRQReq/NMIReq interrupt rework; also `Dec_S` decrements S during reset when Mode="00". |
| **D** | C + local edit | Arcade-Exidy2, Arcade-Victory | C + new output port `PH3 <= MCycle(0)`. |
| **E** | C + local edit (2026-09) | Apple-III | C + reworked taken-branch timing (PC low byte updated first, page-cross fix in following cycle so bus shows old-page/new-low address as on NMOS; `Set_Addr_To_PBR` uses PC instead of PCAdder; interrupt delay keyed on PCAdd; MCode Cycle_3 sets Jump "11"). |
| **F** | C64/C128/VIC20/PET/C16 @ "T65: minor update for unification" (2020-05-22) | C16, PET2001 | Ver 315 + `BCD_en` (T65 + ALU) + default '1' on Rdy/Abort_n/IRQ_n/NMI_n/SO_n; nothing else. |
| **G** | Atari2600 (2020-08/10) | Atari2600 | F + `Dec_S` during reset for Mode="00" (6502 pushes 3 dummy bytes on reset). |
| **H** | NES_MiSTer@b61cea7 (2020-07-22) | AcornAtom, Atari7800, CreatiVision, Gamate | Ver 315 + `BCD_en` (no port defaults) + Dec_S-during-reset fix. |
| **I** | NES_MiSTer HEAD 1d2880e (2025-10-13) | NES | H + many NES-specific changes: `BCD_en` also into MCode (OAL/LXA uses DI instead of DAO when BCD disabled), new ports `Pwr_n` (cold reset), `Instrnew`, `SaveStateBus_*` (savestates via eReg_SavestateV, requires `pBus_savestates` package), reset restores from savestate regs, D flag not cleared on reset for Mode="00", KIL opcode halts CPU (Cycle_sync), MCycle saturates at "111", reset-sync process gated by Enable. Divergent fork. |
| **J** | Ver 315 + local edit (2026-05) | Oric | Reference + snapshot-restore ports `Regs_set(63:0)`, `Regs_set_we` (load PC/S/P/A/X/Y, restart fetch). No BCD_en. |
| **K** | NES_MiSTer@df9dd34 (2018-11-25) | Arcade-ATetris | **Ver 313** (no Ver 315 RDY/undoc fixes: no rdy_mod, no BAQuirk, no Regs port, IRQ sampled only when rdy) + `BCD_en` + port defaults + reordered ports (A/DI/DO moved up, Enable default) + Dec_S reset fix; Pack reorders `T_Set_Addr_To` enum (PBR third). |
| **K2** | K + signal init values | Arcade-Gauntlet, -Atari-system1, -AtariSystem2, -Badlands, -Batman, -Blasteroids, -Escape, -OffTheWall, -SkullXBones, -Toobin, -Vindicators, -Xybots | K + power-up initializers on PC/S/IR/MCycle/Mode_r/Set_Addr_To_r/PCAdder. |
| **L** | C64_MiSTer@e2d5556 (2019-02-05) | Arcade-SuperBreakout | Ver 313, no BCD_en, no Regs port; lacks Ver 315 RDY/undoc fixes. |
| **L2** | BBCMicro@c8efff5 (2018-05-17) | AcornElectron (`rtl/T6502`) | Ver 313, no NMI_ack/BCD_en; lacks Ver 315 fixes; SO handled inside rdy. |
| **M** | MikeJ/opencores "Ver 301 more merging" (2005-2014 era) | MultiComp, UK101 (CRLF), Arcade-BurgerTime, jtframe copies in Arcade-ActFancer/-ChinaGate/-TrioThePunch | Pre-WoS core: totally different code (tabs, std_logic_vector cycle codes), no Lorenz/undoc fixes, no NMI_ack/DEBUG/Regs. |
| **M2** | M + small edit | Arcade-BurningRubber | M minus dummy `D` register, B_o line commented. |
| **M3** | "Ver 301/302" variant (alt MCode with "Ver 302 minor timing fixes") | Arcade-AsteroidsDeluxe (CRLF, files directly in `rtl/`), -CanyonBomber, -Dominos, -LunarLander, -Sprint1, -Sprint2, -Subs, -Ultratank | Old core with B-flag rework; 3-bit Set_Addr_To; very old. |

### Verilog / other forms
* `TK2000_MiSTer/rtl/t65/{t65,t65_alu,t65_mcode,t65_pack}.v` (2025-11-25) and `Arcade-Chameleon_MiSTer/rtl/t65/{t65,T65_ALU,T65_MCode,t65_pack}.v` (2022-08-13): hand Verilog translation of **Ver 315** (header kept, has rdy_mod/BAQuirk), **no BCD_en**. ALU/MCode/Pack .v files identical between the two; t65.v differs only by module-name case and verilator pragmas. TK2000 actually builds the VHDL (`files.qip` -> `rtl/t65/t65.qip`; `t65v.qip` unused).
* `jtframe/hdl/cpu/t65/t65.v` in Arcade-ActFancer/-ChinaGate/-TrioThePunch: GHDL-synthesized netlist ("Converted from T65 VHDL code using GHDL 3.0.0-dev") of the Ver 301 VHDL beside it; no BCD_en.
* `Apple-III_MiSTer/rtl/t65_wrapper.vhd`, `T65_wrap.vhd` in the Atari-system arcade repos: wrappers only.
* 6502-family cores that are **not** T65: Atari800/5200 (`cpu_65xx.vhd`, Wendrich), Apple-II (`cpu_65c02.sv`), Apple-I (arlet/aholme), Atari7800 also has `rtl/6502/mos6502.sv`, Orao (`cpu65xx_fast`), SuperVision (`r65c02_tc`), BBCMicro/AcornElectron `R65Cx2.vhd` (copro / alt), CrystalCastles `cpu_65c02.v`, MissileCommand/LaserdiscGames `bc6502`, QBert/VBall/ExpressRaider `cpu6502.v`/chip_6502, TankBattalion arlet, Qix/TrioThePunch/ActFancer `jt65c02`. No T65 in AtariLynx, Vectrex (6809), Apple-IIgs.

## Full table (one row per repo)

Grp = variant group above. md5 = raw file bytes.

| Grp | Repo (MiSTer-devel/) | Path | First "Ver" line of T65.vhd | T65.vhd | T65_ALU.vhd | T65_MCode.vhd | T65_Pack.vhd | Last change | EOL |
|---|---|---|---|---|---|---|---|---|---|
| A | Arcade-Centipede_MiSTer | `rtl/T65` | Ver 315 SzGy April 2020 | `4f4b9f2bed732aa991fad4cd6ac486ae` | `e53ea5b5e62a6d7a601636255593502b` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2022-04-24 | CRLF |
| A | Arcade-DECOCassette_MiSTer | `rtl/cpu/T65` | Ver 315 SzGy April 2020 | `4f4b9f2bed732aa991fad4cd6ac486ae` | `e53ea5b5e62a6d7a601636255593502b` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2026-05-18 | CRLF |
| A | Arcade-SNK6502_MiSTer | `rtl/T65` | Ver 315 SzGy April 2020 | `4f4b9f2bed732aa991fad4cd6ac486ae` | `e53ea5b5e62a6d7a601636255593502b` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2026-04-01 | CRLF |
| A | BBCMicro_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `4f4b9f2bed732aa991fad4cd6ac486ae` | `e53ea5b5e62a6d7a601636255593502b` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2020-05-10 | CRLF |
| B | C128_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `e6fde7e3a231021228d7543dfd223789` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2026-06-06 | CRLF |
| B | C64_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `e6fde7e3a231021228d7543dfd223789` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2026-06-08 | CRLF |
| B | CBM-II_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `bd635b687e7a71338fe3a7626deaee86` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-09-05 | LF |
| C | Arcade-Asteroids_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `1837ae0f75823ebf8d9c5911b65929a2` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-07-25 | LF |
| C | Arcade-BlackWidow_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `e7c758b5faea1dcb0f97d080fd62a24a` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2026-07-16 | CRLF |
| C | Arcade-DonkeyKong3_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `1837ae0f75823ebf8d9c5911b65929a2` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-05-26 | LF |
| C | Arcade-MajorHavoc_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `1837ae0f75823ebf8d9c5911b65929a2` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-07-31 | LF |
| C | Arcade-MarbleMadness2_MiSTer | `rtl/vendor/T65` | Ver 315 SzGy April 2020 | `1837ae0f75823ebf8d9c5911b65929a2` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-07-29 | LF |
| C | Arcade-Tempest_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `1837ae0f75823ebf8d9c5911b65929a2` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-07-20 | LF |
| C | TK2000_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `e7c758b5faea1dcb0f97d080fd62a24a` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2025-11-25 | CRLF |
| C | VIC20_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `e7c758b5faea1dcb0f97d080fd62a24a` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2022-11-30 | CRLF |
| D | Arcade-Exidy2_MiSTer | `modules/cpu-t65` | Ver 315 SzGy April 2020 | `1481415fa82fd67b8770df313fef3578` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2024-02-17 | LF |
| D | Arcade-Victory_MiSTer | `rtl/sound/imports/t65` | Ver 315 SzGy April 2020 | `1481415fa82fd67b8770df313fef3578` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `9d52d1ad8ec134732c54fee3b898dd97` | 2026-10-06 | LF |
| E | Apple-III_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `08e9987231bf8756dde62e2aa49192f7` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `e3acddcb5087522822a5124686aad849` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2026-09-26 | CRLF |
| F | C16_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `2be9c318b089ae5c327094dc340be68b` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2020-05-22 | CRLF |
| F | PET2001_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `2be9c318b089ae5c327094dc340be68b` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2020-05-22 | CRLF |
| G | Atari2600_MiSTer | `rtl/T65` | Ver 315 SzGy April 2020 | `3675bd3a9411c58be2346fd11555db3e` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `2085d347eee208b3b4faf6a46acabd93` | `aa213dcc769323fe7b67e8e9619bf3e7` | 2020-10-03 | CRLF |
| H | AcornAtom_MiSTer | `rtl/T65` | Ver 315 SzGy April 2020 | `a71edec01582ca558a5f0de159000cd8` | `3cd42b109605ae6fa2062712815e7632` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2022-01-11 | CRLF |
| H | Atari7800_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `444334c2448693e07ac74faebf8283a9` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `6b05b32dcb4cf27ec7162f189f2614bc` | 2021-04-08 | LF |
| H | CreatiVision_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `444334c2448693e07ac74faebf8283a9` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `6b05b32dcb4cf27ec7162f189f2614bc` | 2022-08-06 | LF |
| H | Gamate_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `444334c2448693e07ac74faebf8283a9` | `16078b47cf5ca1399dd83599d7947981` | `954bbc896f9a0e01f9109aa681d19c1f` | `6b05b32dcb4cf27ec7162f189f2614bc` | 2022-06-13 | LF |
| I | NES_MiSTer | `rtl/t65` | Ver 315 SzGy April 2020 | `2e1547cd61cb1d5641d947ff75c925fd` | `2b5c4dc1df702fb630d5e7dfcd1a956e` | `0fa7838e6ef38ab71a71c83d37a876f9` | `5451562ee2ae37d76db7991034af8ee3` | 2025-10-13 | CRLF |
| J | Oric_MiSTer | `rtl/T65` | Ver 315 SzGy April 2020 | `f93efb465f4506046e5e3134c840b9e5` | `e53ea5b5e62a6d7a601636255593502b` | `2085d347eee208b3b4faf6a46acabd93` | `5451562ee2ae37d76db7991034af8ee3` | 2026-05-11 | CRLF |
| K | Arcade-ATetris_MiSTer | `rtl/t65` | Ver 313 WoS January 2015 | `5b84177a3bb9684b477ec07cd6c57041` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2021-01-14 | LF |
| K2 | Arcade-Atari-system1_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2023-12-03 | LF |
| K2 | Arcade-AtariSystem2_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-08-20 | LF |
| K2 | Arcade-Badlands_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-09-19 | LF |
| K2 | Arcade-Batman_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-10-03 | LF |
| K2 | Arcade-Blasteroids_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-09-17 | LF |
| K2 | Arcade-Escape_MiSTer | `rtl/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-08-30 | LF |
| K2 | Arcade-Gauntlet_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2020-11-22 | LF |
| K2 | Arcade-OffTheWall_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-10-08 | LF |
| K2 | Arcade-SkullXBones_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-10-03 | LF |
| K2 | Arcade-Toobin_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-08-13 | LF |
| K2 | Arcade-Vindicators_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-09-17 | LF |
| K2 | Arcade-Xybots_MiSTer | `rtl/lib/T65` | Ver 313 WoS January 2015 | `206cc0d674b59ff273e0ca0c1cfcb0c3` | `d46c995bf85baa63f7507807ef3ce6dd` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `7a529a096d3a5553853b6dfe0fd7fde6` | 2026-09-16 | LF |
| L | Arcade-SuperBreakout_MiSTer | `rtl/T65` | Ver 313 WoS January 2015 | `9574e5e4119f1ae9dba8e7ac6b59ac95` | `866bc09717da5c95a27834995be87397` | `5f1350f794dc7cc30828cb0100ca88a7` | `f6494c282bc26023398af0c1fa51a2d8` | 2020-12-10 | LF |
| L2 | AcornElectron_MiSTer | `rtl/T6502` | Ver 313 WoS January 2015 | `d6dd726814689ce71414dc93e0fb2f76` | `107c1f79518ad2c9cb80f51d44f59faf` | `c2fcf61e4e50bd8acf81661eacd5e6e6` | `9d52d1ad8ec134732c54fee3b898dd97` | 2022-01-14 | LF |
| M | Arcade-ActFancer_MISTer | `jtframe/hdl/cpu/t65` | Ver 301 more merging | `89ce1707b3ea7debb498aedc509abd04` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2026-06-15 | LF |
| M | Arcade-BurgerTime_MiSTer | `rtl/cpu` | Ver 301 more merging | `89ce1707b3ea7debb498aedc509abd04` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2021-01-14 | LF |
| M | Arcade-ChinaGate_MiSTer | `jtframe/hdl/cpu/t65` | Ver 301 more merging | `89ce1707b3ea7debb498aedc509abd04` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2026-05-06 | LF |
| M | Arcade-TrioThePunch_MiSTer | `jtframe/hdl/cpu/t65` | Ver 301 more merging | `89ce1707b3ea7debb498aedc509abd04` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2026-07-08 | LF |
| M | MultiComp_MiSTer | `Components/M6502` | Ver 301 more merging | `89ce1707b3ea7debb498aedc509abd04` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2018-06-24 | LF |
| M | UK101_MiSTer | `UK101/Components/M6502` | Ver 301 more merging | `1dd44d00d0e3a8ba9d80fc2fba9731b5` | `d9aa2863e7b084474455f1ff6dd49ea0` | `5da5481ae0d5a8a350714e43cd4c1e04` | `8b3606bbce3c88ca005674c5f4185a04` | 2021-08-17 | CRLF |
| M2 | Arcade-BurningRubber_MiSTer | `rtl/cpu` | Ver 301 more merging | `96a1678309032c1e86eea985b2eecdcf` | `3f1bc531a2614a823afea44179ae4e5f` | `49be60844e480fcf0fa3ac270d28eeb2` | `0a654fd50204c117ee89001747b9ecf0` | 2021-01-14 | LF |
| M3 | Arcade-AsteroidsDeluxe_MiSTer | `rtl` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-05-19 | CRLF |
| M3 | Arcade-CanyonBomber_MiSTer | `rtl/T65` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-12-14 | CRLF |
| M3 | Arcade-Dominos_MiSTer | `rtl/T65` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-12-14 | CRLF |
| M3 | Arcade-LunarLander_MiSTer | `rtl/T65` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-12-16 | CRLF |
| M3 | Arcade-Sprint1_MiSTer | `rtl/T65` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-12-10 | CRLF |
| M3 | Arcade-Sprint2_MiSTer | `rtl/T65` | Ver 301 more merging | `577a774900065e86119f2bcb2871ac04` | `d9aa2863e7b084474455f1ff6dd49ea0` | `c779a74af7d8c59fc960a5c0e693cf67` | `8b3606bbce3c88ca005674c5f4185a04` | 2020-12-11 | CRLF |
| M3 | Arcade-Subs_MiSTer | `rtl/T65` | Ver 301 more merging | `c0fb0a472a589f887c3d5841e2c71cb9` | `3f1bc531a2614a823afea44179ae4e5f` | `d30710ccfc875c37b95e990eb1035d96` | `0a654fd50204c117ee89001747b9ecf0` | 2022-01-05 | LF |
| M3 | Arcade-Ultratank_MiSTer | `rtl/T65` | Ver 301 more merging | `c0fb0a472a589f887c3d5841e2c71cb9` | `3f1bc531a2614a823afea44179ae4e5f` | `d30710ccfc875c37b95e990eb1035d96` | `0a654fd50204c117ee89001747b9ecf0` | 2021-01-16 | LF |

## Conclusions

### Newest maintained upstream
**`MiSTer-devel/C64_MiSTer` `rtl/t65/` (HEAD 66acee6, 2026-06-08)** — Sorgelig's canonical MiSTer T65 that the computer cores track (C128 identical as of 2026-06-06, CBM-II re-synced 2026-09-05 from C64). The header still reads "Ver 315 SzGy April 2020"; no new Ver entry was added. Its lineage in C64_MiSTer:

| Date | Commit | Change |
|---|---|---|
| 2020-04-30 | 351ced1 | Ver 315 imported (= the galaxian reference, byte-identical) |
| 2020-05-22 | 2f30f68 | "T65: minor update for unification": `BCD_en` port + port defaults (originated in NES_MiSTer 0ba9a3a, 2018-11-09 "Ignore D flag in CPU") |
| 2022-11-14 | 50032d9 | "T65: rework interrupt handling (gyurco)" |
| 2026-05-22 / 06-05 | fbc9c62 / 9674cf4 | "Fix NMI handling." then reverted |
| 2026-06-08 | 66acee6 | "Second fix NMI handling (#214)" (Erik Scheffers, ported from C64MEGA65) |

What it changes vs Ver 315 (full diff: `diffs/C64_MiSTer.diff`, ~100 changed lines; ALU/MCode/Pack: ALU = BCD_en only, MCode identical, Pack = trailing newline only):

1. **`BCD_en` decimal-enable input** (T65 + T65_ALU), latched at MCycle 0 like `Mode`:
```diff
     Mode    : in  std_logic_vector(1 downto 0);      -- "00" => 6502, "01" => 65C02, "10" => 65C816
+    BCD_en  : in  std_logic := '1';             -- '0' => 2A03/2A07, '1' => others
...
-    Rdy     : in  std_logic;
+    Rdy     : in  std_logic := '1';     (likewise Abort_n, IRQ_n, NMI_n, SO_n)
...
           if MCycle  = "000" then
             Mode_r <= Mode;
+            BCD_en_r <= BCD_en;
```
   T65_ALU: `BCD_en : in std_logic;` and every decimal correction gated, e.g.
```diff
-    if AL(5 downto 1) > 9 and P_In(Flag_D) = '1' then
+    if AL(5 downto 1) > 9 and P_In(Flag_D) = '1' and BCD_en = '1' then
```
   (same for AH, the SBC `if P_In(Flag_D)='1'` and the ARR decimal fixup.)
2. **Interrupt rework (gyurco, 2022)**: new `IRQReq`/`NMIReq` registered in the MCycle process; IRQ/NMI cycle selection moved to the opcode-fetch cycle; IRQ_n/NMI_n sampled every enabled cycle; taken-branch delay now keyed on `Jump="11"`:
```diff
-            if IRQCycle = '0' and NMICycle = '0' then
+            if IRQReq = '0' and NMIReq = '0' then
               PC <= PC + 1;
...
+            IRQCycle <= '0';
+            NMICycle <= '0';
+            if NMIReq = '1' then
+              NMICycle <= '1';
+            elsif IRQReq = '1' then
+              IRQCycle <= '1';
+            end if;
...
-        -- detect irq even if not rdy
-        if IR(4 downto 0)/="10000" or Jump/="01" or really_rdy = '0' then ...
-          IRQ_n_o <= IRQ_n;
...
+          if (IR(4 downto 0)/="10000" or Jump/="11") then -- taken branches delay the interrupts
+            if NMIAct = '1' and IR/=x"00" then NMIReq <= '1'; else NMIReq <= '0'; end if;
+            if IRQ_n_o = '0' and P(Flag_I) = '0' then IRQReq <= '1'; else IRQReq <= '0'; end if;
+          end if;
...
+        IRQ_n_o <= IRQ_n;
+        NMI_n_o <= NMI_n;
-        if NMI_n_o = '1' and (NMI_n = '0' and (IR(4 downto 0)/="10000" or Jump/="01")) then
+        if NMI_n_o = '1' and NMI_n = '0' then
           NMIAct <= '1';
```
3. **Stack decrement during reset on NMOS** (same commit):
```diff
-          if Dec_S = '1' and RstCycle = '0' then
+          if Dec_S = '1' and (RstCycle = '0' or Mode = "00") then -- Decrement during reset - 6502 only?
```
4. **NMI_ack pulse (2026-06)**:
```diff
-  NMI_ack <= NMIAct;
+  NMI_ack <= '1' when (NMIAct = '1' and MCycle = "001") else '0';
```
   (plus comment block documenting the NMOS BRK/NMI-hijack quirk; BAL logic unchanged.)

The Ver 315 RDY/undocumented-opcode fixes (rdy_mod, BAQuirk) are retained in all Ver 315-based variants (A–J).

The only other actively-changed copy is **NES_MiSTer** (last 2025-10-13) — a divergent fork (savestates, `Pwr_n`, `Instrnew`, KIL halt, BCD_en also in MCode) built on the 2020-05 base *without* the 2022 interrupt rework. Not a good general-purpose upstream.

### Does any upstream add `BCD_en`?
**Yes.** `BCD_en : in std_logic := '1'; -- '0' => 2A03/2A07, '1' => others`:
* Introduced in **NES_MiSTer** commit 0ba9a3a (2018-11-09, sorgelig, "Ignore D flag in CPU", then on the Ver 313 core) for the Ricoh 2A03.
* Carried into the **Ver 315** core on 2020-05-11 (NES "Update T65") and propagated to C64/C128/C16/VIC20/PET2001 on 2020-05-22 ("T65: minor update for unification").
* Present today in groups B–I and K/K2: C64, C128, CBM-II, VIC20, C16, PET2001, Atari2600, Atari7800, AcornAtom, CreatiVision, Gamate, NES, Apple-III, TK2000 (VHDL), Arcade-Asteroids/-BlackWidow/-DonkeyKong3 (uses it for the 2A03)/-MajorHavoc/-MarbleMadness2/-Tempest/-Exidy2/-Victory, and the Ver 313-based Atari-system arcade family (ATetris, Gauntlet, Atari-system1/2, Badlands, Batman, Blasteroids, Escape, OffTheWall, SkullXBones, Toobin, Vindicators, Xybots).
* NES_MiSTer additionally routes `BCD_en` into T65_MCode (LXA/OAL `$AB` uses DI instead of DAO when BCD disabled).
* Absent in: the reference Ver 315 copies (BBCMicro, Centipede, DECOCassette, SNK6502), Oric (has `Regs_set` instead), the Ver 313 SuperBreakout/AcornElectron copies, all Ver 301-era copies, and the Verilog translations (TK2000 .v, Chameleon .v, jtframe GHDL .v).
* No other new decimal-related port name (e.g. `Dec_en`, `BCD_dis`) was found in any copy.

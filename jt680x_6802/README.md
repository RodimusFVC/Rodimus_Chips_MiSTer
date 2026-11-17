# jt680x_6802

Motorola MC6800 / MC6802 CPU: jotego's `jt680x` exactly as jtcores ships it, running MC6802 microcode that jotego's
own tool generates from our cycle table. jtcores ships the core with 6801 / 6301 microcode only; the 6801 runs ~8 %
fast on a 6802 board (Qix's DAC sounds and Zoo Keeper's music tempo depend on the 6800 cycle counts).

How it stays jotego's: his `.v` files `include "6801_param.vh"` / `"6801.vh"`, and the 6802 control store is generated
under exactly those names (`ucode/jt6802.yaml`: `src: 6802.yaml`, `output: "6801"`). No jotego file is edited; a new
jtcores version is taken by copying his four `.v` files and running `ucode/gen.sh`.

## Files

| File | md5 | From |
|---|---|---|
| `rtl/jt680x.v` | cb8c2a24 | jtcores `modules/jt680x/hdl`, byte-identical (2026-11-05 checkout) |
| `rtl/jt680x_ctrl.v` | ac28adaf | same |
| `rtl/jt680x_alu.v` | fb9c97d6 | same |
| `rtl/jt680x_regs.v` | f4be55e4 | same |
| `rtl/6801.vh` | 4e85a419 | generated (`$readmemb("6801.uc")`, relative) |
| `rtl/6801_param.vh` | 67e81895 | generated |
| `rtl/6801.uc` | 8a782a9a | generated: 4096 x 40-bit control store |
| `ucode/6802.yaml` | 6099efeb | ours: MC6800 per-opcode cycles (MAME `cycles_6800[]`) on jotego's 680x op set |
| `ucode/jt6802.yaml` | aaa81e8d | ours: jtframe cfg |
| `ucode/gen.sh` | 25d8efef | ours: regenerate `rtl/6801.*` |

A core lists the four `.v` in `files.qip`; the `.vh` / `.uc` sit beside them (Quartus finds the `include` and the
`$readmemb` there; a Verilator harness adds `-I` and links `6801.uc` into its run folder). `cen` = the crystal rate
(4 x E: `cycle_factor: 4`); the 6801 on-chip interrupt inputs and `ext_halt` tie low.

Pool type (master `chip_pool_pkg`): `m6800_i_t` / `m6800_o_t`.

## Regenerate

`ucode/gen.sh [jtcores dir]`: copies jtcores' `modules/jt680x` to a temp folder with our two yaml files added, builds
jtframe there (Go >= 1.22; online the first time), runs `jtframe ucode jt680x 6802`, makes the `$readmemb` path
relative. jtcores is never written. Deterministic: 2026-11-05 runs here and in Qix give identical files.

The same `6802.yaml` does NOT give the old `.uc` byte-for-byte under a newer jtframe / `680x.yaml`: the layout and the
shared sequences move together with jotego's `.v`. Take both from the same jtcores and prove a change by simulation.

## Known gaps

`jtframe ucode --report jt680x 6802`: 22 opcodes are 1-2 cycles shorter than the datasheet (indexed read-modify-write,
JSR / BSR, indexed / extended stores). Unchanged since the first 6802 build; not yet investigated.

## Fleet copies

- Qix (`rtl/rodimus/jt680x_6802/`): identical, HW 2026-11-05 (all games, Zoo Keeper tempo). Moving to it from the old
  copy: frames identical, sound CPU timing moved by single DAC samples (mainline's faster interrupt entry), no drift.
- Williams, SpaceInvaders: the old setup (older jotego copy edited to include `6802*` files, `.uc` md5 cead73f7, the
  same one Qix shipped before): move each to this package in its own task, with a regression.

## License

GPL-3.0-or-later (jotego's jt680x). See `LICENSE`.

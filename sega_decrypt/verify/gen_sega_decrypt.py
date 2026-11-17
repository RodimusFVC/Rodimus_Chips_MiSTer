#!/usr/bin/env python3
"""Generate ../rtl/sega_decrypt.sv from MAME's devices/machine/segacrpt_device.cpp and segacrp2_device.cpp.
    gen_sega_decrypt.py [--check] [--mame <MAME src/ root>]
Chip ids = CRYPT_CHIPS order + 1. Ids are append-only: an existing id never moves (cores store it in their MRAs).
One clocked ROM (inferred M10K), 4096 x 9 bits:
  address {chip[4:0], op, sel[5:0]}
    segacrpt (315-50xx / 5093-5155): sel = {A12, A8, A4, A0, col[1:0]}, col = {D5, D3} (mirrored when D7 = 1);
                                     data = {6'b0, table bits D7 D5 D3}
    segacrp2 (5162, 5176-5179, 317-0006 / 0007): sel = {A14, A12, A9, A6, A3, A0}; data = {swap index[4:0], xor D6 D4 D2 D0}
--check also runs a straight Python port of MAME's decode() for every chip, address row and data byte against the
generated table (no ROM data involved).
Moved here 2026-11-15 from SegaSystem1-2 tools/ (it read that core's mra_cfg.CRYPT_CHIPS); ids 25-27 added for Sega82."""
import re, sys
from pathlib import Path



HERE = Path(__file__).resolve().parent
_mi = sys.argv.index('--mame') if '--mame' in sys.argv else -1
MAME = Path(sys.argv[_mi + 1] if _mi > 0 else '/Work/Projects/ZZZ_Obsidian_FPGA/FPGA-Brain/Projects/Mame_Source/src') / 'devices/machine'
CRPT = (MAME / 'segacrpt_device.cpp').read_text()
CRP2 = (MAME / 'segacrp2_device.cpp').read_text()
OUT = HERE.parent / 'rtl/sega_decrypt.sv'

# ids 1-24: SegaSystem1-2 (MRA index-1 byte 149); 25-27: Sega82 (zaxxon / turbo boards). Append only.
CRYPT_CHIPS = ['315_5033', '315_5041', '315_5048', '315_5051', '315_5064', '315_5065', '315_5093', '315_5096',
               '315_5098', '315_5099', '315_5102', '315_5110', '315_5111', '315_5132', '315_5133', '315_5135',
               '315_5155', '315_5162', '315_5176', '315_5177', '315_5178', '315_5179', '317_0006', '317_0007',
               '315_5013', '315_5014', '315_5061']

SWAPTABLE = [[6,4,2,0],[4,6,2,0],[2,4,6,0],[0,4,2,6],[6,2,4,0],[6,0,2,4],[6,4,0,2],[2,6,4,0],
             [4,2,6,0],[4,6,0,2],[6,0,4,2],[0,6,4,2],[4,0,6,2],[0,4,6,2],[6,2,0,4],[2,6,0,4],
             [0,6,2,4],[2,0,6,4],[0,2,6,4],[4,2,0,6],[2,4,0,6],[4,0,2,6],[2,0,4,6],[0,2,4,6]]


def body(src, chip):
    m = re.search(r'void\s+(?:sega|nec)_%s_device::decrypt\(\)\s*\{(.*?)\n\}' % chip, src, re.S)
    return m.group(1) if m else None


def nums(block):
    return [int(x, 0) for x in re.findall(r'0x[0-9a-fA-F]+|\b\d+\b', block)]


def array(b, name):
    m = re.search(r'%s\[[^\]]*\]\s*=\s*\{(.*?)\};' % name, b, re.S)
    return nums(m.group(1)) if m else None


def crpt_parent(chip):
    """MAME devices that only inherit another chip's table: sega_315_5096_device(...) : sega_315_5006_device(...)"""
    m = re.search(r'sega_%s_device::sega_%s_device\([^)]*\)\s*:\s*sega_(\d{3}_\d{4})_device\(' % (chip, chip), CRPT)
    return m.group(1) if m else None


def crpt_table(chip):
    b = body(CRPT, chip)
    if b is None:
        p = crpt_parent(chip)
        return crpt_table(p) if p else None
    m = re.search(r'convtable\[32\]\[4\]\s*=\s*\{(.*?)\};', re.sub(r'/\*.*?\*/', '', b, flags=re.S), re.S)
    assert m, chip
    v = nums(m.group(1))
    assert len(v) == 128, (chip, len(v))
    return [v[i * 4:(i + 1) * 4] for i in range(32)]


def crp2_tables(chip):
    b = body(CRP2, chip)
    if b is None:
        return None
    b = re.sub(r'//[^\n]*', '', b)
    m = re.search(r'sega_decode_317\([^,]*,[^,]*,\s*(\d+)\)', b)
    if m:
        g = re.search(r'static void sega_decode_317\(.*?\)\s*\{(.*?)\n\}', CRP2, re.S).group(1)
        sh = int(m.group(1))
        return array(g, 'xor_table')[sh:sh + 128], array(g, 'swap_table')[sh:sh + 128]
    x, s = array(b, 'xor_table'), array(b, 'swap_table')
    assert len(x) == 128 and len(s) == 128, (chip, len(x), len(s))
    return x, s


def bit(v, n):
    return (v >> n) & 1


def mame_crpt(tab, a, src, op):
    row = bit(a, 0) | bit(a, 4) << 1 | bit(a, 8) << 2 | bit(a, 12) << 3
    col = bit(src, 3) | bit(src, 5) << 1
    xv = 0
    if src & 0x80:
        col, xv = 3 - col, 0xA8
    return (src & ~0xA8 & 0xFF) | (tab[2 * row + (0 if op else 1)][col] ^ xv)


def mame_crp2(x, s, a, src, op):
    row = bit(a, 0) | bit(a, 3) << 1 | bit(a, 6) << 2 | bit(a, 9) << 3 | bit(a, 12) << 4 | bit(a, 14) << 5
    i = 2 * row + (0 if op else 1)
    t = SWAPTABLE[s[i]]
    v = bit(src, 7) << 7 | bit(src, t[0]) << 6 | bit(src, 5) << 5 | bit(src, t[1]) << 4 | bit(src, 3) << 3 | \
        bit(src, t[2]) << 2 | bit(src, 1) << 1 | bit(src, t[3])
    return v ^ x[i]


def rtl_model(rom, chip, a, src, op):
    """what the generated ROM + its datapath compute (mirrors sega_decrypt.sv)"""
    kind = KIND[chip]
    if kind == 1:
        col = bit(src, 3) | bit(src, 5) << 1
        if src & 0x80:
            col = 3 - col
        sel = col | bit(a, 0) << 2 | bit(a, 4) << 3 | bit(a, 8) << 4 | bit(a, 12) << 5
        e = rom[chip << 7 | op << 6 | sel] & 7
        t = (e & 1) << 3 | (e >> 1 & 1) << 5 | (e >> 2 & 1) << 7
        if src & 0x80:
            t ^= 0xA8
        return (src & 0x57) | t
    sel = bit(a, 0) | bit(a, 3) << 1 | bit(a, 6) << 2 | bit(a, 9) << 3 | bit(a, 12) << 4 | bit(a, 14) << 5
    e = rom[chip << 7 | op << 6 | sel]
    sw, xv = e >> 4, e & 0xF
    t = SWAPTABLE[sw]
    v = bit(src, 7) << 7 | bit(src, t[0]) << 6 | bit(src, 5) << 5 | bit(src, t[1]) << 4 | bit(src, 3) << 3 | \
        bit(src, t[2]) << 2 | bit(src, 1) << 1 | bit(src, t[3])
    xb = (xv & 1) | (xv >> 1 & 1) << 2 | (xv >> 2 & 1) << 4 | (xv >> 3 & 1) << 6
    return v ^ xb


KIND = {}


def build():
    rom = [0] * 4096
    for i, name in enumerate(CRYPT_CHIPS):
        chip = i + 1
        t = crpt_table(name)
        if t:
            KIND[chip] = 1
            for op in (0, 1):
                for row in range(16):
                    for col in range(4):
                        e = t[2 * row + (0 if op else 1)][col]
                        assert e & ~0xA8 == 0, (name, hex(e))
                        rom[chip << 7 | op << 6 | row << 2 | col] = bit(e, 3) | bit(e, 5) << 1 | bit(e, 7) << 2
            continue
        x, s = crp2_tables(name)
        KIND[chip] = 2
        for op in (0, 1):
            for row in range(64):
                i2 = 2 * row + (0 if op else 1)
                assert x[i2] & ~0x55 == 0 and s[i2] < 24, (name, row)
                xv = bit(x[i2], 0) | bit(x[i2], 2) << 1 | bit(x[i2], 4) << 2 | bit(x[i2], 6) << 3
                rom[chip << 7 | op << 6 | row] = s[i2] << 4 | xv
    return rom


def check(rom):
    bad = 0
    for i, name in enumerate(CRYPT_CHIPS):
        chip = i + 1
        t = crpt_table(name)
        x2 = None if t else crp2_tables(name)
        for op in (0, 1):
            for a in range(0, 0x8000, 0x101):          # covers every A0/A3/A4/A6/A8/A9/A12/A14 combination
                for src in range(256):
                    want = mame_crpt(t, a, src, op) if t else mame_crp2(x2[0], x2[1], a, src, op)
                    got = rtl_model(rom, chip, a, src, op)
                    if want != got:
                        bad += 1
                        if bad < 5:
                            print('MISMATCH', name, 'op' if op else 'data', hex(a), hex(src), hex(want), hex(got))
    print('check: %d chips, %d mismatches' % (len(CRYPT_CHIPS), bad))
    return bad == 0


def emit(rom):
    kinds = ''.join("            5'd%d: kind = 2'd%d;\n" % (c, k) for c, k in sorted(KIND.items()))
    rows = ''.join("            12'h%03X: q <= 9'h%03X;\n" % (i, v) for i, v in enumerate(rom) if v)
    names = '\n'.join('//    %2d  %s-%s' % (i + 1, n[:3], n[4:]) for i, n in enumerate(CRYPT_CHIPS))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(f"""//============================================================================
//
//  sega_decrypt.sv — Sega Z80 security CPU decryption (315-xxxx / 317-xxxx), decrypt on read
//  Copyright (C) 2026 Rodimus
//
//  GENERATED by verify/gen_sega_decrypt.py from MAME devices/machine/segacrpt_device.cpp and segacrp2_device.cpp
//  (the tables are MAME's; checked there against a port of MAME's decode() on every chip / row / data byte).
//  Do not edit by hand: change the generator and rerun it.
//  SPDX-License-Identifier: BSD-3-Clause
//  Tables from MAME src/devices/machine/segacrpt_device.cpp and segacrp2_device.cpp
//  (license:BSD-3-Clause, copyright-holders: Nicola Salmoria, David Haywood)
//
//  Only A15 = 0 is encrypted; opcode fetches (M1) and data reads use different tables.
//    segacrpt: D7 D5 D3 permuted / inverted by {{M1, A12, A8, A4, A0}} and the data's own D7 D5 D3
//    segacrp2: D6 D4 D2 D0 permuted (24 swaps) and XORed by {{M1, A14, A12, A9, A6, A3, A0}}
//  One clocked ROM (M10K): dout is valid one clock after din / a / op.
//
//  chip ids (verify/gen_sega_decrypt.py CRYPT_CHIPS; append-only):
{names}
//
//============================================================================

module sega_decrypt
(
    input             clk,
    input       [4:0] chip,           // 0 = not encrypted
    input             op,             // opcode fetch (M1)
    input      [15:0] a,
    input       [7:0] din,
    output reg  [7:0] dout
);

    reg [1:0] kind;
    always_comb begin
        case (chip)
{kinds}            default: kind = 2'd0;
        endcase
    end

    // segacrpt column: {{D5, D3}}, mirrored when D7 is set
    wire [1:0] col_raw = {{din[5], din[3]}};
    wire [1:0] col     = din[7] ? ~col_raw : col_raw;
    wire [5:0] sel1    = {{a[12], a[8], a[4], a[0], col}};
    wire [5:0] sel2    = {{a[14], a[12], a[9], a[6], a[3], a[0]}};
    wire [11:0] ra     = {{chip, op, (kind == 2'd1) ? sel1 : sel2}};

    (* romstyle = "M10K" *) reg [8:0] q;
    always @(posedge clk) begin
        case (ra)
{rows}            default: q <= 9'h000;
        endcase
    end

    // pipeline the inputs to line up with the ROM
    reg  [7:0] s;
    reg  [1:0] k;
    reg        enc;
    always @(posedge clk) begin
        s   <= din;
        k   <= kind;
        enc <= (chip != 5'd0) && !a[15];
    end

    // segacrpt: table bits -> D3 D5 D7, inverted together when the source D7 was set
    wire [7:0] t1   = {{q[2], 1'b0, q[1], 1'b0, q[0], 3'b000}} ^ (s[7] ? 8'hA8 : 8'h00);
    wire [7:0] out1 = (s & 8'h57) | t1;

    // segacrp2: swap D6 D4 D2 D0 by table index, then XOR
    reg  [7:0] sw;
    always_comb begin
        sw = s;
        case (q[8:4])
{''.join("            5'd%d: begin sw[6] = s[%d]; sw[4] = s[%d]; sw[2] = s[%d]; sw[0] = s[%d]; end\n" % ((i,) + tuple(t)) for i, t in enumerate(SWAPTABLE))}            default: ;
        endcase
    end
    wire [7:0] out2 = sw ^ {{1'b0, q[3], 1'b0, q[2], 1'b0, q[1], 1'b0, q[0]}};

    always_comb begin
        if (!enc)           dout = s;
        else if (k == 2'd1) dout = out1;
        else                dout = out2;
    end

endmodule
""")
    print('wrote', OUT, '(%d non-zero ROM words)' % sum(1 for v in rom if v))


if __name__ == '__main__':
    rom = build()
    if '--check' in sys.argv and not check(rom):
        sys.exit(1)
    emit(rom)

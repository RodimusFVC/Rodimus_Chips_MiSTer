#!/usr/bin/env python3
"""Mutation check of the VDC oracle: inject one known bug at a time into crtc6845sv_vdc.sv, rebuild, run a short
campaign and confirm the harness reports it (any non-zero mismatch in the all-knob run). Run from verify/."""
import os, re, subprocess, sys
MUTANTS = [
    ("attribute colour", "if (attr_en) c_fg = f_attr[3:0];", "if (attr_en) c_fg = f_attr[7:4];"),
    ("cursor", "if (cur_on_q && {2'b00, cur_col_q} == col) begin c_d3 = ~c_d3; c_g3 = ~c_g3; end", ""),
    ("underline line", "if (f_attr[5] && ln_ra == r29)", "if (f_attr[5] && ln_ra == r23)"),
    ("vertical scroll", "wire  [4:0] c_ra   = p_restart ? (r24[4:0] + {4'd0, f_n}) : draw_ra;", "wire  [4:0] c_ra   = p_restart ? ({4'd0, f_n}) : draw_ra;"),
    ("R27 row increment", "wire  [8:0] row_step   = {1'b0, r01} + {1'b0, r27};", "wire  [8:0] row_step   = {1'b0, r01};"),
    ("HSYNC width", "hs_left <= r03[3:0] - 4'd1;", "hs_left <= r03[3:0];"),
    ("VSYNC width", "if (vs_cnt_a == r03[7:4])", "if (vs_cnt_a == r03[3:0])"),
    ("block count", "r30 <= r30 - 8'd1;", "r30 <= r30 - 8'd2;"),
    ("4416 address map", "assign VA  = r28[0] ?", "assign VA  = 1'b1 ?"),
    ("read-back mask", "6'h09: rd_data = {3'b111, r09};", "6'h09: rd_data = {3'b000, r09};"),
    ("horizontal scroll", "s_x <= (col == 9'd0) ? $signed({10'd0, r25[3:0]})", "s_x <= (col == 9'd0) ? $signed({10'd0, 4'd0})"),
    ("status busy", "wire        ready  = ~(blk_active | cpu_wr_req | ~pf_valid);", "wire        ready  = ~blk_active;"),
    ("cursor blink rate", "2'd2: if (blink_cnt[3] != blink_n[3])", "2'd2: if (blink_cnt[4] != blink_n[4])"),
    ("8563 R37", "6'h25: rd_data = V8568 ? {r37, 6'h3f} : 8'hff;", "6'h25: rd_data = {r37, 6'h3f};"),
    ("8568 /INTR", "else if (~ready_q) intr <= 1'b1;", ""),
    ("start-address latch", "if (p_latch) begin", "if (1'b0) begin"),
]
src = open('../rtl/crtc6845sv_vdc.sv').read()
os.makedirs('build/mut', exist_ok=True)
caught = 0
for i, (name, a, b) in enumerate(MUTANTS):
    assert src.count(a) == 1, name
    open('build/mut/crtc6845sv_vdc.sv', 'w').write(src.replace(a, b))
    d = f'build/mut/m{i}'
    subprocess.run(['verilator', '--cc', '--exe', '--build', '-O3', '-j', '4', '--x-assign', '0', '--x-initial', '0', '-Wno-fatal',
                    '-Wno-lint', '-Wno-style', '--top-module', 'tb_vdc', '-Mdir', d, '-o', 'vdc', 'build/mut/crtc6845sv_vdc.sv',
                    'tb/tb_vdc.sv', os.path.abspath('tb/vdc_main.cpp'), '-CFLAGS', '-O2 -I' + os.path.abspath('tb')],
                   check=True, capture_output=True)
    out = subprocess.run([d + '/vdc', '1', '16'], capture_output=True, text=True).stdout
    res = re.search(r'RESULT .*', out).group(0)
    run0 = re.search(r'RUN \[all knobs\]\s+(.*)', out).group(1)
    nums = [int(x) for x in re.findall(r'mismatches (\d+)', res + ' ' + run0)]
    hit = any(nums)
    caught += hit
    print(f"{'CAUGHT' if hit else 'MISSED'}  {name:22s} {run0}  | 8568/intr: {' '.join(re.findall(r'(?:8568_vs_8563|intr)_mismatches \d+', res))}")
print(f"{caught} / {len(MUTANTS)} mutants caught")

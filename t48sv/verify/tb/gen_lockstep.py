#!/usr/bin/env python3
"""Generate a Verilator lockstep top for one configuration.

gen_lockstep.py <cfg> <out_dir> [--left <cfg2>]

Left side: the GHDL reference model <cfg> (verify/ref/gen/<cfg>.v).
Right side: the t48sv drop-in (default) or, with --left, a second reference
model (used for the lineage A vs B comparison).
Emits <out_dir>/lockstep.sv and <out_dir>/cfg.h.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, '..', 'ref', 'gen')

# cfg: (t48sv module, params, ref core path, dut core path, core kind, flags)
#   kind: 'core48' t48_core-like, 'upi' upi41_core, 't21', 't22'
#   flags: div3, bus, timer, p1, p2, ram (ref path, dut path, size) or 'hram' (harness RAM)
X = 't48_core_b.'
CFG = {
    'A_extrom_g0_r7': ('t48sv_t8039_notri_extrom', dict(gate_port_input_g=0, ram_addr_width_g=7), X, 't48_core_b.core.', 'core48', dict(ram=('ram_b.mem_q', 'ram_b.mem', 128))),
    'A_extrom_g0_r6': ('t48sv_t8039_notri_extrom', dict(gate_port_input_g=0, ram_addr_width_g=6), X, 't48_core_b.core.', 'core48', dict(ram=('ram_b.mem_q', 'ram_b.mem', 64))),
    'A_extrom_g1_r7': ('t48sv_t8039_notri_extrom', dict(gate_port_input_g=1, ram_addr_width_g=7), X, 't48_core_b.core.', 'core48', dict(ram=('ram_b.mem_q', 'ram_b.mem', 128))),
    'A_extrom_g1_r6': ('t48sv_t8039_notri_extrom', dict(gate_port_input_g=1, ram_addr_width_g=6), X, 't48_core_b.core.', 'core48', dict(ram=('ram_b.mem_q', 'ram_b.mem', 64))),
    'A_extrom_g0_r8': ('t48sv_t8039_notri_extrom', dict(gate_port_input_g=0, ram_addr_width_g=8), X, 't48_core_b.core.', 'core48', dict(ram=('ram_b.mem_q', 'ram_b.mem', 256))),
    'A_core':     ('t48sv_t48_core', dict(REV2023=0), '', 'core.', 'core48', dict(hram=1)),
    'A_core_x0':  ('t48sv_t48_core', dict(REV2023=0, xtal_div_3_g=0), '', 'core.', 'core48', dict(hram=1, nodiv=1)),
    'A_core_m0':  ('t48sv_t48_core', dict(REV2023=0, register_mnemonic_g=0), '', 'core.', 'core48', dict(hram=1)),
    'A_core_t3':  ('t48sv_t48_core', dict(REV2023=0, sample_t1_state_g=3), '', 'core.', 'core48', dict(hram=1)),
    'A_core_min': ('t48sv_t48_core', dict(REV2023=0, include_port1_g=0, include_port2_g=0, include_bus_g=0, include_timer_g=0), '', 'core.', 'core48', dict(hram=1, nobus=1, notimer=1, nop1=1, nop2=1)),
    'A_t8039_notri': ('t48sv_t8039_notri', dict(REV2023=0), X, 'sys.t48_core_b.core.', 'core48', dict(ram=('ram_128_b.mem_q', 'sys.ram_b.mem', 128))),
    'B_core':     ('t48sv_t48_core', dict(REV2023=1), '', 'core.', 'core48', dict(hram=1)),
    'B_t8039_notri': ('t48sv_t8039_notri', dict(), X, 'sys.t48_core_b.core.', 'core48', dict(ram=('ram_128_b.mem_q', 'sys.ram_b.mem', 128))),
    'B_t8048_notri': ('t48sv_t8048_notri', dict(ROM_INIT_FILE='rom10.hex'), X, 'sys.t48_core_b.core.', 'core48', dict(ram=('ram_64_b.mem_q', 'sys.ram_b.mem', 64), rom=10)),
    'B_t8048_notri_g0': ('t48sv_t8048_notri', dict(gate_port_input_g=0, ROM_INIT_FILE='rom10.hex'), X, 'sys.t48_core_b.core.', 'core48', dict(ram=('ram_64_b.mem_q', 'sys.ram_b.mem', 64), rom=10)),
    'B_upi41_core':    ('t48sv_upi41_core', dict(), '', 'core.', 'upi', dict(hram=1)),
    'B_upi41_core_a0': ('t48sv_upi41_core', dict(is_upi_type_a_g=0), '', 'core.', 'upi', dict(hram=1)),
    'B_t8041_notri':   ('t48sv_t8041_notri', dict(ROM_INIT_FILE='rom10.hex'), 'upi41_core_b.', 'sys.upi41_core_b.core.', 'upi', dict(ram=('ram_64_b.mem_q', 'sys.ram_b.mem', 64), rom=10)),
    'B_t8041a_notri':  ('t48sv_t8041a_notri', dict(ROM_INIT_FILE='rom10.hex'), 'upi41a_core_b.', 'sys.upi41_core_b.core.', 'upi', dict(ram=('ram_64_b.mem_q', 'sys.ram_b.mem', 64), rom=10)),
    'B_t8042ah_notri': ('t48sv_t8042ah_notri', dict(ROM_INIT_FILE='rom11.hex'), 'upi41a_core_b.', 'sys.upi41_core_b.core.', 'upi', dict(ram=('ram_256_b.mem_q', 'sys.ram_b.mem', 256), rom=11)),
    'B_t21_core':      ('t48sv_t21_core', dict(), '', 'core.', 't21', dict(hram=1)),
    'B_t22_core':      ('t48sv_t22_core', dict(), '', 'core.', 't22', dict(hram=1)),
    'B_t8021_notri':   ('t48sv_t8021_notri', dict(ROM_INIT_FILE='rom10.hex'), 't21_core_b.', 't21_core_b.core.', 't21', dict(ram=('ram_64_b.mem_q', 'ram_b.mem', 64), rom=10)),
    'B_t8022_notri':   ('t48sv_t8022_notri', dict(ROM_INIT_FILE='rom11.hex'), 't22_core_b.', 't22_core_b.core.', 't22', dict(ram=('ram_64_b.mem_q', 'ram_b.mem', 64), rom=11)),
    'B_t8050_wb':      ('t48sv_t8050_wb', dict(ROM_INIT_FILE='rom12.hex'), X, 't48_core_b.core.', 'core48', dict(ram=('ram_256_b.ram_b.mem_q', 'ram_b.mem', 256), rom=12)),
}


def ports_of(vfile, top_suffix):
    v = open(vfile).read()
    m = re.search(r'^module (\w+__%s)\s*\((.*?)\);' % top_suffix, v, re.S | re.M)
    name, body = m.group(1), m.group(2)
    ports = []
    for d, w, n in re.findall(r'(input|output)\s+(\[\d+:0\])?\s*(\w+)', body):
        width = int(w[1:].split(':')[0]) + 1 if w else 1
        ports.append((d, width, n))
    return name, ports


def top_of(cfg):
    v = open(os.path.join(GEN, cfg + '.v')).read()
    return re.findall(r'^module (\w+)', v, re.M)[-1].split('__', 1)[1]


def probes(kind, flags, rp, dp, right_is_ref):
    """(name, width, left path, right path) for internal state."""
    timer_r = 'timer_b.' if kind != 'core48' else 'use_timer_timer_b.'
    p1_r = 'p1_b.' if kind != 'core48' else 'use_p1_p1_b.'
    p2_r = 'p2_b.' if kind != 'core48' else 'use_p2_p2_b.'
    bus_r = 'db_bus_b.' if kind == 'upi' else 'use_db_bus_db_bus_b.'
    P = []

    def add(n, w, r, d):
        P.append((n, w, rp + r, (rp if right_is_ref else dp) + (r if right_is_ref else d)))
    add('acc', 8, 'alu_b.accumulator_q', 'alu_b.accu_q')
    add('shadow', 8, 'alu_b.accu_shadow_q', 'alu_b.shadow_q')
    add('temp', 8, 'alu_b.temp_req_q', 'alu_b.temp_q')
    add('mstate', 3, 'clock_ctrl_b.mstate_q', 'clock_ctrl_b.mstate_q')
    add('mcyc', 1, 'clock_ctrl_b.multi_cycle_q', 'clock_ctrl_b.multi_cycle_q')
    add('scyc', 1, 'clock_ctrl_b.second_cycle_q', 'clock_ctrl_b.second_cycle_q')
    if not flags.get('nodiv'):
        add('xtalq', 2, 'clock_ctrl_b.xtal_q', 'clock_ctrl_b.g_div3.xtal_q')
    add('take', 1, 'cond_branch_b.take_branch_q', 'cond_branch_b.take_q')
    add('opc', 8, 'decoder_b.opc_opcode_q', 'decoder_b.opc_opcode_q')
    add('btq', 1, 'decoder_b.branch_taken_q', 'decoder_b.branch_taken_q')
    add('f1', 1, 'decoder_b.f1_q', 'decoder_b.f1_q')
    add('mb', 1, 'decoder_b.mb_q', 'decoder_b.mb_q')
    add('t0dir', 1, 'decoder_b.t0_dir_q', 'decoder_b.t0_dir_q')
    for n, s in [('tflag', 'timer_flag_q'), ('tovf', 'timer_overflow_q'), ('tie', 'timer_int_enable_q'),
                 ('ie', 'int_enable_q'), ('itype', 'int_type_q'), ('iprog', 'int_in_progress_q'),
                 ('intq', 'int_q'), ('ialeq', 'ale_q')]:
        add(n, 1, 'decoder_b.int_b.' + s, 'decoder_b.' + s)
    add('istate', 2, 'decoder_b.int_b.int_state_q', 'decoder_b.int_state_q')
    add('dmaddr', 8, 'dmem_ctrl_b.dmem_addr_q', 'dmem_ctrl_b.addr_q')
    add('pc', 12, 'pmem_ctrl_b.program_counter_q', 'pmem_ctrl_b.pc_q')
    add('paddr', 12, 'pmem_ctrl_b.pmem_addr_q', 'pmem_ctrl_b.addr_q')
    add('psw', 4, 'psw_b.psw_q', 'psw_b.psw_q')
    add('sp', 3, 'psw_b.sp_q', 'psw_b.sp_q')
    if not flags.get('notimer'):
        add('tcnt', 8, timer_r + 'counter_q', 'g_timer.timer_b.counter_q')
        add('tpre', 5, timer_r + 'prescaler_q', 'g_timer.timer_b.prescaler_q')
        add('tsel', 2, timer_r + 'inc_sel_q', 'g_timer.timer_b.inc_sel_q')
        add('tovq', 1, timer_r + 'overflow_q', 'g_timer.timer_b.overflow_q')
        add('t1q', 1, timer_r + 't1_q', 'g_timer.timer_b.t1_q')
    if kind == 'core48' and not flags.get('nobus'):
        add('busq', 8, bus_r + 'bus_q', 'g_no_upi_bus.g_bus.db_bus_b.bus_q')
        add('dirq', 1, bus_r + 'db_dir_q', 'g_no_upi_bus.g_bus.db_bus_b.dir_q')
        add('dirqq', 1, bus_r + 'db_dir_qq', 'g_no_upi_bus.g_bus.db_bus_b.dir_qq')
    if kind == 'upi':
        for n, w, s, d in [('dbbin', 8, 'dbbin_q', 'dbbin_q'), ('dbbout', 8, 'dbbout_q', 'dbbout_q'),
                           ('sts', 4, 'sts_q', 'sts_q'), ('ibf', 1, 'ibf_q', 'ibf_q'),
                           ('obf', 1, 'obf_q', 'obf_q'), ('dbint', 1, 'int_n_o', 'int_n_q'),
                           ('dma', 1, 'dma_q', 'dma_q'), ('drq', 1, 'drq_o', 'drq_q'),
                           ('flags', 1, 'flags_q', 'flags_q'), ('a0q', 1, 'a0_q', 'a0_q'),
                           ('status', 8, 'status_q', 'status_q')]:
            add(n, w, bus_r + s, 'g_upi_bus.db_bus_b.' + d)
    if not flags.get('nop1'):
        add('p1q', 8, p1_r + 'p1_q', 'g_p1.p1_b.port_q')
    if not flags.get('nop2'):
        add('p2q', 8, p2_r + 'p2_q', 'g_p2.p2_b.p2_q')
    if kind in ('t21', 't22'):
        add('p0q', 8, 'p0_b.p1_q', 'g_p0.p0_b.port_q')
    if kind == 't22':
        add('sar', 8, 'adc_b.sar_q', 'g_adc.adc_b.sar_q')
        add('crr', 8, 'adc_b.crr_q', 'g_adc.adc_b.crr_q')
    return P


def ram_paths(cfg, flags, right_ref):
    if flags.get('hram'):
        return 'r_hram.mem', 'd_hram.mem'
    r, d, size = flags['ram']
    if right_ref:
        return 'lft.' + r, 'dut.' + CFG[right_ref][5]['ram'][0]
    return 'lft.' + r, 'dut.' + d


def main():
    cfg, out = sys.argv[1], sys.argv[2]
    right_ref = None
    if '--left' in sys.argv:
        right_ref = sys.argv[sys.argv.index('--left') + 1]
    os.makedirs(out, exist_ok=True)
    dmod, dpar, rp, dp, kind, flags = CFG[cfg]
    top = top_of(cfg)
    rname, ports = ports_of(os.path.join(GEN, cfg + '.v'), top)
    clocks = {'xtal_i', 'clk_i'}
    core = kind if top.endswith('_core') else None
    hram = flags.get('hram')
    mem_ports = {'dmem_addr_o', 'dmem_we_o', 'dmem_data_i', 'dmem_data_o', 'en_clk_i', 'xtal3_o'} if hram else set()
    ins = [(w, n) for d, w, n in ports if d == 'input' and n not in clocks and n not in mem_ports]
    outs = [(w, n) for d, w, n in ports if d == 'output']
    if hram:
        outs = [(w, n) for w, n in outs]
    L = ['// generated by gen_lockstep.py %s' % cfg, '/* verilator lint_off WIDTH */',
         'module lockstep (', '  input logic clk,']
    for w, n in ins:
        L.append('  input logic %s%s,' % ('[%d:0] ' % (w - 1) if w > 1 else '', n))
    for w, n in outs:
        for s in 'rd':
            L.append('  output logic %s%s_%s,' % ('[%d:0] ' % (w - 1) if w > 1 else '', s, n))
    P = probes(kind, flags, 'lft.' + rp, 'dut.' + dp, right_ref is not None)
    if right_ref:
        P = [(n, w, a, 'dut.' + b[len('lft.'):]) for n, w, a, b in P]
    for n, w, a, b in P:
        for s in 'rd':
            L.append('  output logic %sp%s_%s,' % ('[%d:0] ' % (w - 1) if w > 1 else '', s, n))
    L.append('  output logic dinj_o,')
    L.append('  output logic dummy_o);')
    L.append('assign dinj_o = %s;' % (('dut.' + dp + 'decoder_b.injected_int_q') if not right_ref else "1'b0"))
    L.append('assign dummy_o = 1\'b0;')

    def conn(side):
        c = []
        for d, w, n in ports:
            if n in clocks:
                c.append('.%s(clk)' % n)
            elif n in mem_ports:
                c.append('.%s(%s_%s)' % (n, side, n))
            elif d == 'input':
                c.append('.%s(%s)' % (n, n))
            else:
                c.append('.%s(%s_%s)' % (n, side, n))
        return ', '.join(c)
    if hram:
        for s in 'rd':
            L.append('logic [7:0] %s_dmem_data_i;' % s)
            L.append('logic %s_en_clk_i;' % s)
            L.append('assign %s_en_clk_i = %s_xtal3_o;' % (s, s))
            L.append('harness_ram %s_hram (.clk_i(clk), .a_i(%s_dmem_addr_o), .we_i(%s_dmem_we_o), '
                     '.d_i(%s_dmem_data_o), .d_o(%s_dmem_data_i));' % (s, s, s, s, s))
    L.append('%s lft (%s);' % (rname, conn('r')))
    if right_ref:
        rname2, _ = ports_of(os.path.join(GEN, right_ref + '.v'), top_of(right_ref))
        L.append('%s dut (%s);' % (rname2, conn('d')))
    else:
        par = ', '.join('.%s(%s)' % (k, '"%s"' % v if isinstance(v, str) else v) for k, v in dpar.items())
        L.append('%s %s dut (%s);' % (dmod, '#(%s)' % par if par else '', conn('d')))
    for n, w, a, b in P:
        L.append('assign pr_%s = %s;' % (n, a))
        L.append('assign pd_%s = %s;' % (n, b))
    rr, dr = ram_paths(cfg, flags, right_ref)
    L.append('export "DPI-C" function ram_peek;')
    L.append('function automatic int ram_peek(input int side, input int i);')
    L.append('  return side != 0 ? int\'(%s[i]) : int\'(%s[i]);' % (dr, rr))
    L.append('endfunction')
    L.append('endmodule')
    open(os.path.join(out, 'lockstep.sv'), 'w').write('\n'.join(L) + '\n')

    H = ['// generated by gen_lockstep.py %s' % cfg, '#define CFG_NAME "%s"' % cfg,
         '#define KIND_%s 1' % kind.upper()]
    for w, n in ins:
        H.append('#define HAS_IN_%s 1' % n)
    for w, n in outs:
        H.append('#define HAS_OUT_%s 1' % n)
    H.append('#define FOREACH_OUTPUT(X) ' + ' '.join('X(%s,%d)' % (n, w) for w, n in outs))
    for n, w, a, b in P:
        H.append('#define HAS_PRB_%s 1' % n)
    H.append('#define FOREACH_PROBE(X) ' + ' '.join('X(%s,%d)' % (n, w) for n, w, a, b in P))
    if top in ('t8021_notri', 't8022_notri'):
        H.append('#define RESET_ACTIVE_HIGH 1')
    if 'rom' in flags:
        H.append('#define ROM_AW %d' % flags['rom'])
    H.append('#define RAM_SIZE %d' % (256 if hram else flags['ram'][2]))
    if hram:
        H.append('#define HRAM 1')
    open(os.path.join(out, 'cfg.h'), 'w').write('\n'.join(H) + '\n')


if __name__ == '__main__':
    main()

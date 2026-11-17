#!/usr/bin/env python3
"""Generate the lockstep testbench for one configuration: the GHDL reference model and the t80sv drop-in module of
the same top, wired to the same stimulus with identical port maps. Every output, every T80 register and every
front-end register of both sides is packed into ref_* / dut_* vectors for the C++ driver (sim.cpp).
usage: tbgen.py <config> <out dir> <ref model .v>"""
import os, re, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from configs import CONFIGS, FLEET_WRAPPERS, mode_of

# tb input signals
TBIN = [('clk', 1), ('reset_n', 1), ('cen', 1), ('cen_p', 1), ('cen_n', 1), ('wait_n', 1), ('int_n', 1), ('nmi_n', 1),
        ('busrq_n', 1), ('di', 8), ('di2', 8), ('out0', 1), ('r800', 1), ('dirset', 1), ('dir', 212), ('i8080', 1),
        ('i8085', 1), ('rim_d', 8)]

Z80_OUT = [('M1_n', 1), ('MREQ_n', 1), ('IORQ_n', 1), ('RD_n', 1), ('WR_n', 1), ('RFSH_n', 1), ('HALT_n', 1),
           ('BUSAK_n', 1), ('A', 16), ('DO', 8)]
# top -> (inputs [(port, tb expr)], outputs [(port, width)], bus kind)
PORTS = {
    'T80s': ([('RESET_n', 'reset_n'), ('CLK', 'clk'), ('CEN', 'cen'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'),
              ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n'), ('OUT0', 'out0'), ('DI', 'di')], Z80_OUT, 'z80'),
    'T80se': ([('RESET_n', 'reset_n'), ('CLK_n', 'clk'), ('CLKEN', 'cen'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'),
               ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n'), ('DI', 'di')], Z80_OUT, 'z80'),
    'T80pa': ([('RESET_n', 'reset_n'), ('CLK', 'clk'), ('CEN_p', 'cen_p'), ('CEN_n', 'cen_n'), ('WAIT_n', 'wait_n'),
               ('INT_n', 'int_n'), ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n'), ('OUT0', 'out0'), ('DI', 'di'),
               ('R800_mode', 'r800'), ('DIRSet', 'dirset'), ('DIR', 'dir')], Z80_OUT + [('REG', 212)], 'z80'),
    'T8080se': ([('RESET_n', 'reset_n'), ('CLK', 'clk'), ('CLKEN', 'cen'), ('READY', 'wait_n'), ('HOLD', 'busrq_n'),
                 ('INT', '~int_n'), ('DI', 'di')],
                [('INTE', 1), ('DBIN', 1), ('SYNC', 1), ('VAIT', 1), ('HLDA', 1), ('WR_n', 1), ('A', 16), ('DO', 8)],
                '8080'),
    'GBse': ([('RESET_n', 'reset_n'), ('CLK_n', 'clk'), ('CLKEN', 'cen'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'),
              ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n'), ('DI', 'di')], Z80_OUT + [('STOP', 1)], 'z80'),
    'T80a': ([('RESET_n', 'reset_n'), ('R800_mode', 'r800'), ('CLK_n', 'clk'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'),
              ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n')],
             [('M1_n', 1), ('MREQ_n', 1), ('IORQ_n', 1), ('RD_n', 1), ('WR_n', 1), ('RFSH_n', 1), ('HALT_n', 1),
              ('BUSAK_n', 1), ('A', 16)], 'a'),
    'T80as': ([('RESET_n', 'reset_n'), ('CLK_n', 'clk'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'), ('NMI_n', 'nmi_n'),
               ('BUSRQ_n', 'busrq_n'), ('DI', 'di')], Z80_OUT + [('DOE', 1)], 'z80'),
    'T80': ([('RESET_n', 'reset_n'), ('CLK_n', 'clk'), ('CEN', 'cen'), ('WAIT_n', 'wait_n'), ('INT_n', 'int_n'),
             ('NMI_n', 'nmi_n'), ('BUSRQ_n', 'busrq_n'), ('DInst', 'di'), ('DI', 'di2'), ('R800_mode', 'r800'),
             ('out0', 'out0'), ('DIRSet', 'dirset'), ('DIR', 'dir')],
            [('M1_n', 1), ('IORQ', 1), ('NoRead', 1), ('Write', 1), ('RFSH_n', 1), ('HALT_n', 1), ('BUSAK_n', 1),
             ('A', 16), ('DO', 8), ('MC', 3), ('TS', 3), ('IntCycle_n', 1), ('IntE', 1), ('Stop', 1), ('REG', 212)],
            't80'),
}
PORTS['T80sed'] = PORTS['T80se']
PHX_IN = [('I8080', 'i8080'), ('I8085', 'i8085'), ('RIM_D', 'rim_d')]

# T80 registers: (ref signal, dut signal, width)
CORE = [
    ('acc', 'ACC', 8), ('f', 'F', 8), ('ap', 'Ap', 8), ('fp', 'Fp', 8), ('i', 'I', 8), ('r', 'R', 8),
    ('sp', 'SP', 16), ('pc', 'PC', 16), ('wz', 'WZ', 16), ('ir', 'IR', 8), ('iset', 'ISet', 2),
    ('xy_state', 'XY_State', 2), ('istatus', 'IStatus', 2), ('mcycles', 'MCycles', 3), ('alternate', 'Alternate', 1),
    ('read_to_reg_r', 'Read_To_Reg_r', 5), ('arith16_r', 'Arith16_r', 1), ('btr_r', 'BTR_r', 1), ('z16_r', 'Z16_r', 1),
    ('alu_op_r', 'ALU_Op_r', 4), ('save_alu_r', 'Save_ALU_r', 1), ('preservec_r', 'PreserveC_r', 1),
    ('xy_ind', 'XY_Ind', 1), ('i_rxdd', 'I_RXDD', 1), ('regaddra_r', 'RegAddrA_r', 3), ('regaddrb_r', 'RegAddrB_r', 3),
    ('regaddrc', 'RegAddrC', 3), ('incdecz', 'IncDecZ', 1), ('regbusa_r', 'RegBusA_r', 16), ('busa', 'BusA', 8),
    ('busb', 'BusB', 8), ('mcycle', 'MCycle', 3), ('tstate', 'TState', 3), ('pre_xy_f_m', 'Pre_XY_F_M', 3),
    ('halt_ff', 'Halt_FF', 1), ('nmicycle', 'NMICycle', 1), ('intcycle', 'IntCycle', 1), ('inte_ff1', 'IntE_FF1', 1),
    ('inte_ff2', 'IntE_FF2', 1), ('no_btr', 'No_BTR', 1), ('auto_wait_t1', 'Auto_Wait_t1', 1),
    ('auto_wait_t2', 'Auto_Wait_t2', 1), ('nmi_s', 'NMI_s', 1), ('busreq_s', 'BusReq_s', 1), ('busack', 'BusAck', 1),
    ('m1_n', 'M1_n', 1), ('rfsh_n', 'RFSH_n', 1), ('a', 'A', 16), ('do', 'DO', 8), ('OLDNMI', 'OldNMI_n', 1),
    ('mulu_prod32', 'MULU_Prod32', 32), ('mulu_fakt1', 'MULU_Fakt1', 16),
    ('dor', 'DOR', 128),
]
# front-end registers: top -> [(ref signal, dut signal under dut.u, width)]
FRONT = {
    'T80s': [('di_reg', 'DI_Reg', 8)],
    'T80se': [('di_reg', 'DI_Reg', 8)],
    'T80sed': [('di_reg', 'DI_Reg', 8)],
    'GBse': [('di_reg', 'DI_Reg', 8)],
    'T8080se': [('di_reg', 'DI_Reg', 8)],
    'T80pa': [('di_reg', 'DI_Reg', 8), ('cen_pol', 'g_pa.CEN_pol', 1), ('intcycled_n', 'g_pa.IntCycleD_n', 2)],
    'T80a': [('di_reg', 'DI_Reg', 8), ('reset_s', 'g_a.Reset_s', 1), ('wait_s', 'g_a.Wait_s', 1),
             ('wr_t2', 'g_a.WR_t2', 1), ('req_inhibit', 'g_a.Req_Inhibit', 1), ('mreq_inhibit', 'g_a.MReq_Inhibit', 1),
             ('rd', 'g_a.RD', 1), ('mreq', 'g_a.MREQ', 1), ('iorq_int', 'g_a.IORQ_int', 1),
             ('iorq_int_inhibit', 'g_a.IORQ_int_inhibit', 3), ('iorq_t1', 'g_a.IORQ_t1', 1),
             ('iorq_t2', 'g_a.IORQ_t2', 1),
             # pre-tri-state pins and drivers
             ('mreq_n_i', 'mreq_n', 1), ('iorq_n_i', 'iorq_n', 1), ('rd_n_i', 'rd_n', 1), ('wr_n_i', 'wr_n', 1),
             ('rfsh_n_i', 'rfsh_n', 1), ('a_i', 'a', 16), ('busak_n_i', 'bus_oe', 1), ('DOENA', 'doe', 1),
             ('DOVAL', 'dout', 8)],
    'T80as': [('di_reg', 'DI_Reg', 8), ('reset_s', 'g_as.Reset_s', 1), ('wait_s', 'g_as.Wait_s', 1),
              ('wr_n_i', 'g_as.WR_n_i', 1), ('iorq_n_i', 'g_as.IORQ_n_i', 1), ('req_inhibit', 'g_as.Req_Inhibit', 1),
              ('mreq_inhibit', 'g_as.MReq_Inhibit', 1), ('rd', 'g_as.RD', 1), ('mreq', 'g_as.MREQ', 1)],
    'T80': [],
}
DUTMOD = {'T80s': 't80sv_T80s', 'T80se': 't80sv_T80se', 'T80sed': 't80sv_T80sed', 'T80pa': 't80sv_T80pa',
          'T8080se': 't80sv_T8080se', 'GBse': 't80sv_GBse', 'T80a': 't80sv_T80a', 'T80as': 't80sv_T80as',
          'T80': 't80sv_T80'}


def module_text(v, suffix):
    m = re.search(r'^module \w+__%s\n(.*?)^endmodule' % suffix, v, re.M | re.S)
    return m.group(1) if m else ''


# struct field -> tb signal
FIELD_SRC = {'reset_n': 'reset_n', 'ce': 'cen', 'cen_p': 'cen_p', 'cen_n': 'cen_n', 'wait_n': 'wait_n', 'int_n': 'int_n',
             'nmi_n': 'nmi_n', 'busrq_n': 'busrq_n', 'i8080': 'i8080', 'i8085': 'i8085', 'rim_d': 'rim_d', 'di': 'di'}
STRUCT_FIELDS = {
    'z80_i_t': ['ce', 'int_n', 'nmi_n', 'di'],
    'z80r_i_t': ['reset_n', 'ce', 'int_n', 'nmi_n', 'di'],
    'z80w_i_t': ['ce', 'wait_n', 'int_n', 'nmi_n', 'di'],
    'z80sed_i_t': ['reset_n', 'ce', 'wait_n', 'int_n', 'nmi_n', 'di'],
    'z80pa_i_t': ['reset_n', 'cen_p', 'cen_n', 'wait_n', 'int_n', 'nmi_n', 'busrq_n', 'di'],
    'z80pa85_i_t': ['cen_p', 'cen_n', 'wait_n', 'int_n', 'nmi_n', 'i8080', 'i8085', 'rim_d', 'di'],
}
OUT_FIELDS = [('a', 'A'), ('dout', 'DO'), ('m1_n', 'M1_n'), ('mreq_n', 'MREQ_n'), ('iorq_n', 'IORQ_n'), ('rd_n', 'RD_n'),
              ('wr_n', 'WR_n'), ('rfsh_n', 'RFSH_n')]


def main(cfg, outdir, refv_path, solo=None):
    fleet = FLEET_WRAPPERS.get(cfg)
    if fleet:
        refcfg, wmod, itype, ties, extra_out, _ = fleet
        top, src, gens = CONFIGS[refcfg]
        cfg_ref = refcfg
    else:
        top, src, gens = CONFIGS[cfg]
        cfg_ref = cfg
    v = open(refv_path).read()
    ins, outs, kind = PORTS[top]
    ins = list(ins)
    outs = list(outs)
    phx = src == 'phx'
    if phx and top in ('T80pa', 'T80'):
        ins += PHX_IN
        outs = outs + [('SOD', 1)]
    dutmod = DUTMOD[top] + ('_phx' if phx and top in ('T80pa', 'T80') else '')
    refmod = f'{cfg_ref}__{top}'
    if fleet:
        ins = [(p, ties.get(p, e)) for p, e in ins]
        omap = dict(OUT_FIELDS + [('busak_n', 'BUSAK_n'), ('sod', 'SOD')])
        outs = [(n, w) for n, w in outs if n in [omap[f] for f, _ in OUT_FIELDS] or n in [omap[x] for x in extra_out if x in omap]]
        if 'inte' in extra_out:
            outs.append(('INTE_X', 1))
    core_ref = 'rm.' if top == 'T80' else 'rm.u0.'
    core_dut = 'dut.u0.' if top == 'T80' else 'dut.u.u0.'
    coretext = v[v.index('module %s__t80' % cfg_ref):]
    oldnmi = re.search(r'reg (n\d+_oldnmi_n);', coretext).group(1)

    def sv_name(n):
        return '\\%s ' % n if n in ('do', 'reg') else n

    L = [f'// generated by tbgen.py: {cfg} ({top}, {src}, {gens})', 'module tb (']
    L += [f'    input  logic {"[%d:0] " % (w - 1) if w > 1 else ""}{n},' for n, w in TBIN]
    PW = sum(w for _, w in outs)
    TOPPORT = {'m1_n': 'M1_n', 'rfsh_n': 'RFSH_n', 'a': 'A', 'do': 'DO'} if top == 'T80' else {}  # top ports keep case
    st = [((core_ref + (oldnmi if r == 'OLDNMI' else TOPPORT.get(r) or sv_name(r))), core_dut + d, w) for r, d, w in CORE]
    if phx:
        st.append((core_ref + 'sod_r', core_dut + 'SOD_r', 1))
    for r, d, w in FRONT[top]:
        if r == 'DOENA':
            st.append(('(rm.write & rm.busak_n_i)', 'dut.u.' + d, w))
        elif r == 'DOVAL':
            st.append(('rm.\\do ', 'dut.u.' + d, w))
        else:
            st.append(('rm.' + r, 'dut.u.' + d, w))
    SW = sum(w for _, _, w in st)
    L.append(f'    output logic [{PW + 95}:0] ref_pins, dut_pins,')
    L.append(f'    output logic [{SW + 95}:0] ref_st, dut_st')
    L.append(');')
    for side in ('r', 'd'):
        for n, w in outs:
            L.append(f'wire {"[%d:0] " % (w - 1) if w > 1 else ""}{side}_{n};')
    params = ', '.join(f'.{k}({v})' for k, v in gens.items())
    sides = (('r', refmod, 'rm'), ('d', dutmod, 'dut'))
    if fleet:
        sides = (('r', refmod, 'rm'),)
        L.append(f'chip_pool_pkg::{itype} fi;')
        L.append(f'chip_pool_pkg::{itype.replace("_i_t", "_o_t")} fo;')
        for f in STRUCT_FIELDS[itype]:
            L.append(f'assign fi.{f} = {FIELD_SRC[f]};')
        wp = ''
        if 'T2Write' in gens and wmod != 't80sv_z80sed':
            wp = f' #(.T2WRITE({gens["T2Write"]}))'
        rst = '' if fleet[5] else '.reset_n(reset_n), '
        L.append(f'{wmod}{wp} dut (.clk(clk), {rst}.i(fi), .o(fo));')
        omap = dict(OUT_FIELDS + [('busak_n', 'BUSAK_n'), ('sod', 'SOD')])
        for f, n in omap.items():
            if any(n == o for o, _ in outs):
                L.append(f'assign d_{n} = fo.{f};')
        if 'inte' in extra_out:
            L.append('assign r_INTE_X = r_REG[210];')
            L.append('assign d_INTE_X = fo.inte;')
            L.insert(L.index('wire r_INTE_X;'), 'wire [211:0] r_REG;')
    if solo:
        sides = tuple(x for x in sides if x[0] == solo[0])
    for side, mod, inst in sides:
        conns = [f'.{p}({e})' for p, e in ins] + [f'.{n}({side}_{n})' for n, _ in outs if n != 'INTE_X']
        if fleet and 'inte' in extra_out:
            conns.append('.REG(r_REG)')
        if fleet:
            conns += [f'.{n}()' for n, _ in PORTS[top][1] + ([('SOD', 1)] if phx and top == 'T80pa' else [])
                      if n not in [o for o, _ in outs] and not (n == 'REG' and 'inte' in extra_out)]
        if kind == 'a':
            L.append(f'tri [7:0] {side}_D;')
            conns.append(f'.D({side}_D)')
        hdr = f'{mod} #({params}) {inst} (' if (side == 'd' and params) else f'{mod} {inst} ('
        L.append(hdr)
        L.append('    ' + ',\n    '.join(conns))
        L.append(');')
    if kind == 'a':
        L.append("assign r_D = (rm.write & rm.busak_n_i) ? 8'bz : di;")
        L.append("assign d_D = dut.doe ? 8'bz : di;")
    sp = 'r' if solo != 'dut' else 'd'
    rpins = ', '.join(f'{sp}_{n}' for n, _ in outs)
    rst = ', '.join((d if solo == 'dut' else r) for r, d, _ in st)
    L.append('assign ref_pins = {96\'d0, ' + rpins + '};')
    L.append('assign dut_pins = {96\'d0, ' + (rpins if solo else ', '.join(f'd_{n}' for n, _ in outs)) + '};')
    L.append('assign ref_st = {96\'d0, ' + rst + '};')
    L.append('assign dut_st = {96\'d0, ' + (rst if solo else ', '.join(d for _, d, _ in st)) + '};')
    L.append('endmodule')
    os.makedirs(outdir, exist_ok=True)
    open(os.path.join(outdir, 'tb.sv'), 'w').write('\n'.join(L) + '\n')

    with open(os.path.join(outdir, 'tb_fields.h'), 'w') as h:
        h.write(f'// generated by tbgen.py: {cfg}\n')
        h.write('static const struct { const char *name; int w; } ST_FIELDS[] = {\n')
        for r, d, w in st:
            nm = d.split('.')[-1]
            h.write(f'    {{"{nm}", {w}}},\n')
        h.write('};\n')
        h.write('static const struct { const char *name; int w; } PIN_FIELDS[] = {\n')
        for n, w in outs:
            h.write(f'    {{"{n}", {w}}},\n')
        h.write('};\n')
        kinds = {'z80': 0, '8080': 1, 't80': 2, 'a': 3}
        h.write(f'#define ST_W {SW}\n#define PIN_W {PW}\n#define CFG_NAME "{cfg}"\n#define CFG_MODE {mode_of(cfg_ref)}\n')
        h.write(f'#define CFG_KIND {kinds[kind]}\n#define CFG_PA {1 if top == "T80pa" else 0}\n')
        h.write(f'#define CFG_PHX {1 if phx else 0}\n#define CFG_GB {1 if top == "GBse" or "Flag_C" in gens else 0}\n')
        has = {p for p, _ in ins}
        h.write(f'#define HAS_R800 {1 if "R800_mode" in has else 0}\n#define HAS_DIR {1 if "DIRSet" in has else 0}\n')
        h.write(f'#define HAS_OUT0 {1 if ("OUT0" in has or "out0" in has) else 0}\n')
        h.write(f'#define HAS_CEN {1 if ("CEN" in has or "CLKEN" in has) else 0}\n')
        h.write(f'#define TWO_EDGE {1 if top in ("T80a", "T80as") else 0}\n')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None)

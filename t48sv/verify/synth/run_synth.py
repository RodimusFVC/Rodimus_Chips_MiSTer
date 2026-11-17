#!/usr/bin/env python3
"""yosys synth_intel_alm (Cyclone V) of the GHDL reference models and t48sv.

run_synth.py <out_dir> [config ...]   -> <out_dir>/synth_results.json + table on stdout
ALMs are estimated as in Quartus' packing ballpark: one ALM holds one 6-LUT or two
LUTs with <= 8 distinct inputs together; we report LUT counts by size and
est_alm = luts6 + ceil((luts<=5 + arith/2) / 2) (fracturable pairs), plus FFs.
"""
import json, os, re, subprocess, sys, math

HERE = os.path.dirname(os.path.abspath(__file__))
RTL = os.environ.get('RTL', os.path.join(HERE, '..', '..', 'rtl'))
GEN = os.path.join(HERE, '..', 'ref', 'gen')
SV = ['t48sv_blocks.sv', 't48sv_decoder.sv', 't48sv_core.sv', 't48sv_cores.sv',
      't48sv_t8039_notri_extrom.sv', 't48sv_system.sv']

# name: (fleet use, ref cfg, ref entity, t48sv module, params)
CONFIGS = {
    'fleet_8039_extrom': ('Nintendo / Galaxian / Konami82', 'A_extrom_g0_r7', 't8039_notri_extrom',
                          't48sv_t8039_notri_extrom', 'gate_port_input_g=0, ram_addr_width_g=7'),
    'fleet_8035_extrom': ('SegaG80 speech', 'A_extrom_g0_r6', 't8039_notri_extrom',
                          't48sv_t8039_notri_extrom', 'gate_port_input_g=0, ram_addr_width_g=6'),
    'fleet_t48_core':    ('SegaG80 USB (i8035.v)', 'A_core', 't48_core', 't48sv_t48_core', 'REV2023=0'),
    'fleet_upi41_core':  ('DECOCassette (i8041_top.v)', 'B_upi41_core', 'upi41_core', 't48sv_upi41_core', ''),
    'extrom_8040':       ('-', 'A_extrom_g0_r8', 't8039_notri_extrom', 't48sv_t8039_notri_extrom',
                          'gate_port_input_g=0, ram_addr_width_g=8'),
    'B_t48_core':        ('-', 'B_core', 't48_core', 't48sv_t48_core', 'REV2023=1'),
    'B_t8039_notri':     ('-', 'B_t8039_notri', 't8039_notri', 't48sv_t8039_notri', ''),
    'B_upi41_core_a0':   ('-', 'B_upi41_core_a0', 'upi41_core', 't48sv_upi41_core', 'is_upi_type_a_g=0'),
    'B_t21_core':        ('-', 'B_t21_core', 't21_core', 't48sv_t21_core', ''),
    'B_t22_core':        ('-', 'B_t22_core', 't22_core', 't48sv_t22_core', ''),
    'A_core_min':        ('-', 'A_core_min', 't48_core', 't48sv_t48_core',
                          'REV2023=0, include_port1_g=0, include_port2_g=0, include_bus_g=0, include_timer_g=0'),
}


def run_yosys(out, name, read, top):
    tmpl = open(os.path.join(HERE, 'alm.ys.tmpl')).read()
    ys = tmpl.replace('@READ@', read).replace('@TOP@', top).replace('@OPTS@', '-noiopad -nobram') \
             .replace('@OUT@', os.path.join(out, name))
    ys = ys.replace('ltp -noff', 'write_json %s.json' % os.path.join(out, name))
    path = os.path.join(out, name + '.ys')
    open(path, 'w').write(ys)
    r = subprocess.run(['yosys', '-q', '-s', path], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stderr[-2000:])
    stat = open(os.path.join(out, name + '.stat')).read()
    cells = dict((k, int(v)) for k, v in re.findall(r'^\s+(MISTRAL_\w+)\s+(\d+)', stat, re.M))
    dep = subprocess.run(['python3', os.path.join(HERE, 'depth.py'), os.path.join(out, name + '.json')],
                         capture_output=True, text=True).stdout.strip()
    lv, cy, ns = re.findall(r'levels=(\d+) carry=(\d+) est_ns=([\d.]+)', dep)[0]
    l6 = cells.get('MISTRAL_ALUT6', 0)
    lsmall = sum(cells.get('MISTRAL_ALUT%d' % k, 0) for k in (2, 3, 4, 5)) + cells.get('MISTRAL_NOT', 0)
    arith = cells.get('MISTRAL_ALUT_ARITH', 0)
    return dict(cells=cells, luts=l6 + lsmall + arith, ff=cells.get('MISTRAL_FF', 0),
                mlab=cells.get('MISTRAL_MLAB', 0), m10k=cells.get('MISTRAL_M10K', 0),
                est_alm=l6 + math.ceil((lsmall + arith / 2) / 2), levels=int(lv), carry=int(cy),
                est_ns=float(ns))


def main():
    out = os.path.abspath(sys.argv[1])
    os.makedirs(out, exist_ok=True)
    want = sys.argv[2:] or list(CONFIGS)
    res = {}
    for name in want:
        use, ref, ent, mod, par = CONFIGS[name]
        ref_top = '%s__%s' % (ref, ent)
        wrap = os.path.join(out, name + '_t48sv_top.sv')
        # wrapper so that parameters are applied like an instance in a fleet core
        src = open(os.path.join(GEN, ref + '.v')).read()
        ports = re.search(r'^module %s\s*\((.*?)\);' % re.escape(ref_top), src, re.S | re.M).group(1)
        names = re.findall(r'(?:input|output)\s+(?:\[\d+:0\]\s*)?(\w+)', ports)
        decl = re.sub(r'\n\s*', ' ', ports)
        open(wrap, 'w').write('module syn_top (%s);\n  %s %s u (%s);\nendmodule\n' % (
            decl, mod, '#(%s)' % ', '.join('.%s(%s)' % tuple(p.strip().split('=')) for p in par.split(',') if p.strip()) if par else '',
            ', '.join('.%s(%s)' % (n, n) for n in names)))
        r_ref = run_yosys(out, name + '_ref', 'read_verilog %s' % os.path.join(GEN, ref + '.v'), ref_top)
        r_sv = run_yosys(out, name + '_t48sv', 'read_verilog -sv %s %s' % (
            ' '.join(os.path.join(RTL, f) for f in SV), wrap), 'syn_top')
        res[name] = dict(use=use, ref=r_ref, t48sv=r_sv)
        print('%-20s ref: luts %4d ff %3d mlab %d alm~%4d lv %2d (%.1f ns) | t48sv: luts %4d ff %3d mlab %d alm~%4d lv %2d (%.1f ns)'
              % (name, r_ref['luts'], r_ref['ff'], r_ref['mlab'], r_ref['est_alm'], r_ref['levels'], r_ref['est_ns'],
                 r_sv['luts'], r_sv['ff'], r_sv['mlab'], r_sv['est_alm'], r_sv['levels'], r_sv['est_ns']), flush=True)
    json.dump(res, open(os.path.join(out, 'synth_results.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()

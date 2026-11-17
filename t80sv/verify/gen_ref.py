#!/usr/bin/env python3
"""Convert the reference T80 VHDL tops to Verilog with GHDL synth, one model per configuration (configs.py).
usage: gen_ref.py <stock T80 dir> <phoenix T80 dir> <out dir> [config ...]"""
import hashlib, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from configs import CONFIGS

stock, phx, out = (os.path.abspath(p) for p in sys.argv[1:4])
only = sys.argv[4:]
SRC = {'stock': stock, 'phx': phx}
for k, want in (('stock', 'cd16504e'), ('phx', 'd4956f04')):
    h = hashlib.md5(open(os.path.join(SRC[k], 'T80.vhd'), 'rb').read()).hexdigest()
    if not h.startswith(want):
        sys.exit(f'{k} T80.vhd md5 {h}, expected {want}')
os.makedirs(out, exist_ok=True)

def fix(text, pre):
    mods = re.findall(r'^module (\S+)', text, re.M)
    for m in mods:
        text = re.sub(r'^module %s\b' % re.escape(m), 'module %s__%s' % (pre, m), text, flags=re.M)
        text = re.sub(r'^(\s+)%s(\s+\S+\s*\()' % re.escape(m), r'\g<1>%s__%s\2' % (pre, m), text, flags=re.M)
    # GHDL names an instance port wire <inst>_<port>; it can collide with a signal of the same name (ALU_Q):
    # rename the second declaration and its two instance-side uses
    lines = text.split('\n')
    seen, dups = set(), {}
    for i, l in enumerate(lines):
        if l.startswith('module '):
            seen = set()
        m = re.match(r'\s+wire (\[\d+:\d+\] )?(\w+);$', l)
        if m:
            if m.group(2) in seen:
                dups[m.group(2)] = i
                lines[i] = l.replace(m.group(2) + ';', m.group(2) + '_port;')
            seen.add(m.group(2))
    for n, i in dups.items():
        for j in range(i, len(lines)):
            if re.match(r'\s+assign \w+_n\d+ = %s;' % n, lines[j]) or re.match(r'\s+\.\w+\(%s\)' % n, lines[j]):
                lines[j] = re.sub(r'\b%s\b(?=[;)])' % n, n + '_port', lines[j])
            if lines[j].startswith('endmodule'):
                break
    text = '\n'.join(lines)
    text = re.sub(r'(\w+)_\\reg ', r'\1_reg_o ', text)   # GHDL emits an escaped name inside a plain one
    return '`begin_keywords "1364-2005"\n' + text + '\n`end_keywords\n'  # GHDL uses SV keywords (do) as names

def gen(name):
    top, src, gens = CONFIGS[name]
    s = SRC[src]
    w = os.path.join(out, 'work_' + name)
    os.makedirs(w, exist_ok=True)
    files = ['T80_Pack.vhd', 'T80_ALU.vhd', 'T80_Reg.vhd', 'T80_MCode.vhd', 'T80.vhd']
    if top != 'T80':
        files.append(top + '.vhd')
    subprocess.run(['ghdl', '-a', '--std=08', '-fsynopsys'] + [os.path.join(s, f) for f in files], cwd=w,
                   check=True, capture_output=True)
    r = subprocess.run(['ghdl', '--synth', '--std=08', '-fsynopsys'] + [f'-g{k}={v}' for k, v in gens.items()] +
                       ['--out=verilog', top], cwd=w, check=True, capture_output=True, text=True)
    open(os.path.join(out, f'ref_{name}.v'), 'w').write(fix(r.stdout, name))
    return name

with ThreadPoolExecutor(4) as ex:
    for n in ex.map(gen, only or list(CONFIGS)):
        print('ref', n)

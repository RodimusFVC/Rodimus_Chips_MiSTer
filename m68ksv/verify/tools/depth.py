#!/usr/bin/env python3
# Copyright (C) 2026 Rodimus
# m68ksv: register-to-register path depth of a yosys synth_intel_alm netlist (write_json), in LUT levels.
#   depth.py <netlist.json> [N]      -> the N (default 30) deepest endpoints, each with its traced worst path
# A yosys estimate of path depth, NOT a timing analysis: one LUT level per ALUT entered on a data input, 0.05 per
# carry-chain step (CI -> CO), 1.5 for an MLAB read (address -> data), 2 for the DSP multiplier; an M10K output
# starts at 3 levels (its clock-to-output time). Sources: FF outputs, M10K outputs (registered address), module
# inputs; sinks: FF / M10K / MLAB inputs and module outputs.
import json, sys, functools, re

d = json.load(open(sys.argv[1]))
N = int(sys.argv[2]) if len(sys.argv) > 2 else 30
top = [m for m in d['modules'].values() if m.get('attributes', {}).get('top')]
m = top[0] if top else list(d['modules'].values())[0]
cells = m['cells']
drv = {}
for cn, c in cells.items():
    for p, bits in c['connections'].items():
        if c['port_directions'].get(p) == 'output':
            for b in bits:
                drv[b] = (cn, p)
inbits = set()
for pn, p in m['ports'].items():
    if p['direction'] == 'input':
        inbits.update(b for b in p['bits'] if isinstance(b, int))
names = {}
for nn, n in m['netnames'].items():
    if n.get('hide_name', 0) or 'MISTRAL' in nn or '$' in nn:
        continue
    for i, b in enumerate(n['bits']):
        if not isinstance(b, int):
            continue
        nm_ = nn if len(n['bits']) == 1 else '%s[%d]' % (nn, i)
        if b not in names or len(nm_) < len(names[b][0]):
            names[b] = (nm_, 0)

def nm(b):
    return names.get(b, ('?%s' % b, 1))[0]

def source(t):
    return t.startswith('MISTRAL_FF') or t.startswith('MISTRAL_M10K')

def weight(t, port):
    if t.startswith('MISTRAL_ALUT_ARITH'):
        return 0.05 if port == 'CI' else 1.0
    if t.startswith('MISTRAL_ALUT'):
        return 1.0
    if t.startswith('MISTRAL_MLAB'):
        return 1.5 if port.startswith('B1ADDR') else None   # write side is a sink
    if t.startswith('MISTRAL_MUL'):
        return 2.0
    return 0.0

sys.setrecursionlimit(1000000)

@functools.lru_cache(None)
def arr(b):
    """(levels, predecessor bit or None) of the deepest path from a source to bit b"""
    if not isinstance(b, int) or b in inbits or b not in drv:
        return (0.0, None)
    cn, p = drv[b]
    c = cells[cn]
    t = c['type']
    if source(t):
        return (3.0 if t.startswith('MISTRAL_M10K') else 0.0, None)
    best = (0.0, None)
    for ip, bits in c['connections'].items():
        if c['port_directions'].get(ip) != 'input':
            continue
        w = weight(t, ip)
        if w is None:
            continue
        for x in bits:
            r = arr(x)
            if r[0] + w > best[0] or best[1] is None:
                best = (r[0] + w, x)
    return best

# source line of a cell
def srcof(c):
    s_ = c.get('attributes', {}).get('src', '')
    return re.sub(r'^.*?:(\d+)\..*$', r'line \1', s_.split('|')[0]) if s_ else ''
ends = []
for cn, c in cells.items():
    t = c['type']
    if source(t) or t.startswith('MISTRAL_MLAB'):
        for ip, bits in c['connections'].items():
            if c['port_directions'].get(ip) != 'input' or ip in ('CLK', 'clk', 'CLK1'):
                continue
            if t.startswith('MISTRAL_MLAB') and ip.startswith('B1ADDR'):
                continue
            for b in bits:
                if isinstance(b, int):
                    lab = cn if t.startswith('MISTRAL_M') else None
                    if t.startswith('MISTRAL_FF'):
                        q = c['connections'].get('Q', [None])[0]
                        n_ = nm(q) if q is not None else '?'
                        lab = (n_ if not n_.startswith('?') else 'FF@' + srcof(c)) + ('' if ip == 'DATAIN' or ip == 'D' else '.' + ip)
                    ends.append((arr(b)[0], b, t, ip, lab))
for pn, p in m['ports'].items():
    if p['direction'] == 'output':
        for b in p['bits']:
            if isinstance(b, int):
                ends.append((arr(b)[0], b, 'port', pn, None))

def group(s):
    return re.sub(r'\[\d+\]', '', s)

seen = {}
for e in sorted(ends, key=lambda e: -e[0]):
    lv, b, t, ip, lab = e
    if t.startswith('MISTRAL_FF'):
        en = lab
    elif t == 'port':
        en = 'port ' + ip
    else:
        en = '%s:%s' % (re.sub(r'\$.*', '', lab or '') or t, re.sub(r'\d+$', '', ip))
    g = group(en)
    if g in seen:
        continue
    seen[g] = (lv, b, en)
    if len(seen) >= N:
        break

print('rank levels endpoint  <-  worst path (source first; FF@line / line = source line in the synthesised file,\n'
      '                         lines below 100 are yosys cell-library lines)')
for i, (g, (lv, b, en)) in enumerate(seen.items()):
    bits = []
    x = b
    while x is not None:
        bits.append(x)
        x = arr(x)[1]
    bits.reverse()
    short = []
    for x in bits:
        n_ = nm(x)
        if n_.startswith('?') and x in drv:
            c = cells[drv[x][0]]
            n_ = ('FF@' if c['type'].startswith('MISTRAL_FF') else '') + srcof(c) if srcof(c) else n_
        if not n_.startswith('?') and (not short or short[-1] != n_):
            short.append(n_)
    print('%3d %5.2f %s' % (i + 1, lv, en))
    print('          ' + ' -> '.join(short[:1] + short[1:-1][-12:] + short[-1:]))

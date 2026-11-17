#!/usr/bin/env python3
"""Longest combinational path of a synth_intel_alm netlist (yosys write_json), in LUT levels.
A LUT or an arithmetic cell entered on a data input costs 1 level; ripple through a carry chain
(CI -> CO) costs 1/20 of a level. Sources: FF / MLAB outputs and module inputs; sinks: FF / MLAB
inputs and module outputs. Prints the worst path for reg->reg, in->reg, reg->out, in->out."""
import json, sys, functools
d = json.load(open(sys.argv[1]))
top = [m for m in d['modules'].values() if m.get('attributes', {}).get('top')]
m = top[0] if top else list(d['modules'].values())[0]
drv = {}           # bit -> (cell, port)
for cn, c in m['cells'].items():
    for p, bits in c['connections'].items():
        if c['port_directions'].get(p) == 'output':
            for b in bits: drv[b] = (cn, p)
inbits = set()
for pn, p in m['ports'].items():
    if p['direction'] == 'input': inbits.update(b for b in p['bits'] if isinstance(b, int))
seq = lambda t: t.startswith('MISTRAL_FF') or t.startswith('MISTRAL_MLAB') or t in ('MISTRAL_CLKBUF',)
sys.setrecursionlimit(100000)
@functools.lru_cache(None)
def arr(b, cls):
    """(levels, source kind) arriving at bit b from sources of class cls; None if none"""
    if not isinstance(b, int): return None
    if b in inbits or b not in drv: return (0.0, 'in') if cls == 'in' else None
    cn, p = drv[b]; c = m['cells'][cn]; t = c['type']
    if t == 'MISTRAL_IB': return (0.0, 'in') if cls == 'in' else None
    if seq(t): return (0.0, 'reg') if cls == 'reg' else None
    best = None
    for ip, bits in c['connections'].items():
        if c['port_directions'].get(ip) != 'input': continue
        w = 0.0 if t in ('MISTRAL_NOT', 'MISTRAL_OB') else 1.0
        if t == 'MISTRAL_ALUT_ARITH' and ip == 'CI': w = 0.05
        for x in bits:
            r = arr(x, cls)
            if r is None: continue
            if best is None or r[0] + w > best[0]: best = (r[0] + w, r[1])
    return best
res = {}
def sink(bits, kind):
    for b in bits:
      for cls in ('in', 'reg'):
        r = arr(b, cls)
        if r is None: continue
        l, k = r
        key = f"{k}->{kind}"
        if l > res.get(key, 0): res[key] = l
for cn, c in m['cells'].items():
    if seq(c['type']):
        for ip, bits in c['connections'].items():
            if c['port_directions'].get(ip) == 'input' and ip not in ('CLK', 'clk'): sink(bits, 'reg')
    if c['type'] == 'MISTRAL_OB':
        sink(c['connections']['I'], 'out')
for pn, p in m['ports'].items():
    if p['direction'] == 'output': sink(p['bits'], 'out')
for k in sorted(res): print(f"  {k:10s} {res[k]:5.2f} LUT levels")
# worst reg->reg path, traced back
if len(sys.argv) > 2:
    best = None
    for cn, c in m['cells'].items():
        if seq(c['type']):
            for ip, bits in c['connections'].items():
                if c['port_directions'].get(ip) == 'input' and ip not in ('CLK', 'clk'):
                    for b in bits:
                        r = arr(b, 'reg')
                        if r and (best is None or r[0] > best[0]): best = (r[0], b, cn)
    for pn, p in m['ports'].items():
        if p['direction'] == 'output':
            for b in p['bits']:
                for cls in ('reg', 'in'):
                    r = arr(b, cls)
                    if r and r[0] > best[0]: best = (r[0], b, 'port ' + pn)
    names = {}
    for nn, n in m['netnames'].items():
        for b in n['bits']:
            if isinstance(b, int) and (b not in names or nn.startswith('\\') is False): names.setdefault(b, nn)
    print("worst path ends at", best[2], "level", best[0])
    b = best[1]
    while True:
        cls = 'reg' if arr(b, 'reg') else 'in'
        print("   ", names.get(b, b), arr(b, cls))
        if b not in drv: break
        cn, p = drv[b]; c = m['cells'][cn]; t = c['type']
        if seq(t) or t == 'MISTRAL_IB': print("    from", t, cn); break
        nxt = None
        for ip, bits in c['connections'].items():
            if c['port_directions'].get(ip) != 'input': continue
            for x in bits:
                r = arr(x, cls)
                if r and (nxt is None or r[0] > nxt[0]): nxt = (r[0], x)
        if not nxt: break
        b = nxt[1]

#!/usr/bin/env python3
"""Register-to-register logic depth of a yosys synth_intel_alm JSON netlist.
FFs / IO buffers cut paths. Reports max LUT levels and, for that path, carry-chain hops."""
import json, sys
from functools import lru_cache
sys.setrecursionlimit(100000)
nl = json.load(open(sys.argv[1]))
top = [m for m in nl['modules'].values() if m['attributes'].get('top')][0]
cells = top['cells']
drv = {}                                   # net bit -> cell name
for cn, c in cells.items():
    for p, d in c['port_directions'].items():
        if d == 'output':
            for b in c['connections'][p]:
                drv[b] = cn
CUT = ('MISTRAL_FF', 'MISTRAL_IB', 'MISTRAL_OB', 'MISTRAL_CLKBUF')
def ins(cn):
    c = cells[cn]
    return [b for p, d in c['port_directions'].items() if d == 'input' for b in c['connections'][p] if isinstance(b, int)]
@lru_cache(None)
def depth(cn):
    """(lut_levels, carry_hops) of the worst path ending at this cell's output."""
    t = cells[cn]['type']
    if t.startswith(CUT):
        return (0, 0)
    best = (0, 0)
    for b in ins(cn):
        if b in drv:
            d = depth(drv[b])
            if (d[0], d[1]) > best: best = d
    if t == 'MISTRAL_ALUT_ARITH':
        # a carry hop when fed through CI from another arith cell, else a LUT level
        ci = cells[cn]['connections'].get('CI', [])
        if ci and isinstance(ci[0], int) and ci[0] in drv and cells[drv[ci[0]]]['type'] == 'MISTRAL_ALUT_ARITH':
            dci = depth(drv[ci[0]])
            other = (0, 0)
            for p in ('A', 'B', 'C', 'D0', 'D1'):
                for b in cells[cn]['connections'].get(p, []):
                    if isinstance(b, int) and b in drv:
                        d = depth(drv[b]); other = max(other, (d[0] + 1, d[1]))
            return max((dci[0], dci[1] + 1), other)
        return (best[0] + 1, best[1])
    if t.startswith('MISTRAL_ALUT') or t == 'MISTRAL_NOT':
        return (best[0] + 1, best[1])
    return best
worst = (0, 0)
for cn, c in cells.items():
    if c['type'].startswith(('MISTRAL_FF', 'MISTRAL_OB')):
        for b in ins(cn):
            if b in drv:
                worst = max(worst, depth(drv[b]))
print(f"max LUT levels {worst[0]}, carry hops on that path {worst[1]}")
if len(sys.argv) > 2:
    # walk back the worst path: at each cell follow the input driver with the deepest path
    end = None
    for cn, c in cells.items():
        if c['type'].startswith(('MISTRAL_FF', 'MISTRAL_OB')):
            for b in ins(cn):
                if b in drv and depth(drv[b]) == worst: end = drv[b]; endff = cn
    path = []
    cn = end
    while cn and not cells[cn]['type'].startswith(CUT):
        path.append(cn)
        best = None; bd = (-1, -1)
        for b in ins(cn):
            if b in drv:
                d = depth(drv[b])
                if d > bd: bd = d; best = drv[b]
        cn = best
    if cn: path.append(cn)
    for p in reversed(path): print("   ", cells[p]['type'], p[:110])
    print("    ->", endff[:110])

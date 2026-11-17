#!/usr/bin/env python3
"""Logic depth of a yosys synth_intel_alm netlist (write_json).

Cut points: MISTRAL_FF, MLAB / M10K, ports. Each MISTRAL_ALUT* adds one LUT level;
MISTRAL_ALUT_ARITH adds one level when entered on a LUT input and a carry hop
when entered on CI. Reports max LUT levels, carry hops on that path, and a rough
Cyclone V -7 delay estimate (0.55 ns per LUT level incl. local routing,
0.05 ns per carry hop, 0.5 ns clock-to-out + setup).
"""
import json, sys, collections

SEQ = ('MISTRAL_FF', 'MISTRAL_MLAB', 'MISTRAL_M10K', 'MISTRAL_CLKBUF')


def analyse(path):
    d = json.load(open(path))
    mods = d['modules']
    top = [m for m in mods if mods[m].get('attributes', {}).get('top')] or list(mods)
    m = mods[top[0]]
    drivers = {}          # bit -> (cell, port)
    loads = collections.defaultdict(list)
    for cn, c in m['cells'].items():
        for p, bits in c['connections'].items():
            d_ = c['port_directions'].get(p, 'input')
            for b in bits:
                if isinstance(b, str):
                    continue
                if d_ == 'output':
                    drivers[b] = (cn, p)
                else:
                    loads[b].append((cn, p))
    cells = m['cells']
    memo = {}
    pred = {}

    def arrival(cn, inport):
        """(lut levels, carry hops) at the output of cell cn"""
        if cn in memo:
            return memo[cn]
        memo[cn] = (0, 0)
        c = cells[cn]
        t = c['type']
        best = (0, 0)
        for p, bits in c['connections'].items():
            if c['port_directions'].get(p) != 'input':
                continue
            for b in bits:
                if isinstance(b, str) or b not in drivers:
                    continue
                dc, dp = drivers[b]
                if cells[dc]['type'] in SEQ:
                    a = (0, 0)
                else:
                    a = arrival(dc, dp)
                if t == 'MISTRAL_ALUT_ARITH' and p == 'CI':
                    a = (a[0], a[1] + 1)
                elif t.startswith('MISTRAL_ALUT') or t == 'MISTRAL_NOT':
                    a = (a[0] + (0 if t == 'MISTRAL_NOT' else 1), a[1])
                if a > best:
                    best = a
                    pred[cn] = dc if cells[dc]['type'] not in SEQ else ('SRC', dc)
        memo[cn] = best
        return best

    sys.setrecursionlimit(100000)
    worst = (0, 0)
    end = [None]
    for cn, c in cells.items():
        if c['type'] in SEQ:
            for p, bits in c['connections'].items():
                if c['port_directions'].get(p) != 'input':
                    continue
                for b in bits:
                    if isinstance(b, str) or b not in drivers:
                        continue
                    dc, dp = drivers[b]
                    if cells[dc]['type'] in SEQ:
                        continue
                    a = arrival(dc, dp)
                    if a > worst:
                        worst, end[0] = a, (dc, cn)
    # paths ending at output ports
    for pn, pd in m['ports'].items():
        if pd['direction'] != 'output':
            continue
        for b in pd['bits']:
            if not isinstance(b, str) and b in drivers and cells[drivers[b][0]]['type'] not in SEQ:
                worst = max(worst, arrival(*drivers[b]))
    path = []
    if end[0]:
        cn = end[0][0]
        path.append(end[0][1])
        while cn is not None and not isinstance(cn, tuple):
            path.append(cn)
            cn = pred.get(cn)
        if isinstance(cn, tuple):
            path.append(cn[1])
    analyse.path = [(p, cells[p]['type']) for p in reversed(path)]
    return worst


if __name__ == '__main__':
    lv, cy = analyse(sys.argv[1])
    print('levels=%d carry=%d est_ns=%.2f' % (lv, cy, 0.5 + 0.55 * lv + 0.05 * cy))
    if '-v' in sys.argv:
        for n, t in analyse.path:
            print('   %-22s %s' % (t, n[:150]))

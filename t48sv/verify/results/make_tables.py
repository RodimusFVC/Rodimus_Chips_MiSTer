#!/usr/bin/env python3
"""Aggregate result files into markdown tables (results/tables.md)."""
import glob, collections, json, os
H = os.path.dirname(os.path.abspath(__file__))
out = []
def agg(pat):
    a = collections.defaultdict(collections.Counter); op = {}
    for f in glob.glob(os.path.join(H, pat)):
        for l in open(f):
            if l.startswith('RESULT'):
                d = dict(kv.split('=') for kv in l.split()[1:]); c = d.pop('cfg')
                for k, v in d.items():
                    if k == 'opcodes': op[c] = max(op.get(c, 0), int(v))
                    else: a[c][k] += int(v)
    return a, op
a, op = agg('lock_*.txt')
out.append('| configuration | cycles | runs | instructions | opcodes | INTs taken | async resets | timer ovf | counter incs | MOVX writes | XTAL_EN gaps | host rd/wr | mismatches |')
out.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
T = collections.Counter()
for c in sorted(a):
    x = a[c]; T.update(x)
    out.append('| %s | %.0fM | %d | %d | %d/256 | %d | %d | %d | %d | %d | %.1fM | %d/%d | %d |' % (
        c, x['cycles'] / 1e6, x['runs'], x['instrs'], op[c], x['ints'], x['resets'], x['tovf'], x['cnt_inc'],
        x['movx'], x['xen_gaps'] / 1e6, x['host_rd'], x['host_wr'], x['mismatching_runs']))
out.append('| **total** | **%.0fM** | %d | %d | | %d | %d | %d | %d | %d | | | **%d** |' % (
    T['cycles'] / 1e6, T['runs'], T['instrs'], T['ints'], T['resets'], T['tovf'], T['cnt_inc'], T['movx'], T['mismatching_runs']))
out.append('')
a, op = agg('sweep_[A-Z]*.txt')
out.append('| configuration | sweep runs | cycles | INTs taken | timer ovf | mismatches |')
out.append('|---|---:|---:|---:|---:|---:|')
T = collections.Counter()
for c in sorted(a):
    x = a[c]; T.update(x)
    out.append('| %s | %d | %.1fM | %d | %d | %d |' % (c, x['sweeps'], x['cycles'] / 1e6, x['ints'], x['tovf'], x['mismatching_runs']))
out.append('| **total** | **%d** | **%.0fM** | %d | %d | **%d** |' % (T['sweeps'], T['cycles'] / 1e6, T['ints'], T['tovf'], T['mismatching_runs']))
open(os.path.join(H, 'tables.md'), 'w').write('\n'.join(out) + '\n')
print('\n'.join(out))

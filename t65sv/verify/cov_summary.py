#!/usr/bin/env python3
# cov_summary.py <coverage.dat>: line/block coverage per RTL file, merged over every build and instance (a point
# counts as covered if any configuration executed it), plus the list of points never executed.
import sys, re, os, collections
pts = collections.defaultdict(int)
for l in open(sys.argv[1], encoding='latin-1'):
    if not l.startswith('C '): continue
    m = re.match(r"C '(.*)' (\d+)", l.rstrip('\n'))
    kv = dict(x.split('\x02', 1) for x in m.group(1).split('\x01') if '\x02' in x)
    f = os.path.normpath(kv['f'])
    if '/rtl/' not in f: continue
    pts[(f, int(kv['l']), kv.get('n', ''), kv.get('o', ''))] += int(m.group(2))
files = sorted({k[0] for k in pts})
tot_c = tot = 0
print('Verilator line/block coverage, merged over all coverage runs (cov.sh)')
for f in files:
    ks = [k for k in pts if k[0] == f]
    c = sum(1 for k in ks if pts[k] > 0)
    tot_c += c; tot += len(ks)
    print(f'{os.path.basename(f):24s} {c:5d} / {len(ks):5d} points  {100.0 * c / len(ks):5.1f} %')
print(f'{"all RTL":24s} {tot_c:5d} / {tot:5d} points  {100.0 * tot_c / tot:5.1f} %')
print('\nNever executed:')
src = {}
for (f, line, n, o), cnt in sorted(pts.items()):
    if cnt: continue
    if f not in src: src[f] = open(f).read().splitlines()
    print(f'{os.path.basename(f)}:{line}: [{o}] {src[f][line - 1].strip()[:110]}')

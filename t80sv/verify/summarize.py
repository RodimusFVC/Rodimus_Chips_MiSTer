#!/usr/bin/env python3
"""Summarize a results directory into markdown tables: summarize.py <results dir> > results.md"""
import glob, os, re, sys
from collections import defaultdict
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from configs import CONFIGS, FLEET, FLEET_WRAPPERS

R = sys.argv[1]
PAGES = ['base', 'CB', 'ED', 'DD', 'FD', 'DDCB', 'FDCB']
st = defaultdict(lambda: dict(rcyc=0, rjobs=0, rfail=0, scyc=0, sjobs=0, sfail=0, cases=[0] * 5, zl=0, zlfail=0,
                              zlcyc=0, i80=[], cov=defaultdict(set)))
fails = []
covbits = defaultdict(lambda: [set() for _ in PAGES])
for log in sorted(glob.glob(os.path.join(R, '*.log'))):
    name = os.path.basename(log)[:-4]
    t = open(log, errors='replace').read()
    m = re.search(r'EXIT (\d+)\s*$', t)
    rc = int(m.group(1)) if m else -1
    if rc:
        fails.append(name)
    cyc = sum(int(x) for x in re.findall(r': (\d+) cycles, \d+ compares', t))
    kind, rest = name.split('_', 1)
    if kind == 'random':
        cfg = rest.rsplit('_s', 1)[0]
        d = st[cfg]; d['rcyc'] += cyc; d['rjobs'] += 1; d['rfail'] += rc != 0
    elif kind == 'sweep':
        cfg = rest.rsplit('_p', 1)[0]
        d = st[cfg]; d['scyc'] += cyc; d['sjobs'] += 1; d['sfail'] += rc != 0
        m = re.search(r'INT (\d+) NMI (\d+) WAIT (\d+) BUSRQ (\d+) INT\+NMI (\d+)', t)
        if m:
            d['cases'] = [a + int(b) for a, b in zip(d['cases'], m.groups())]
    elif kind == 'zexlock':
        cfg = re.match(r'(.*)_zex(doc|all)_\d+$', rest).group(1)
        d = st[cfg]; d['zl'] += 1; d['zlfail'] += rc != 0; d['zlcyc'] += cyc
    elif kind == 'i8080':
        cfg, prog = rest.rsplit('_', 1)
        st[cfg]['i80'].append((prog, rc, cyc, 'stopped via BDOS 0' in t))
    else:
        continue
    for m in re.finditer(r'COVERAGE \S+ \S+:(.*)', t):
        pass
    covf = log[:-4] + '.cov'
    if os.path.exists(covf):
        b = open(covf, 'rb').read()
        for p in range(7):
            for i in range(256):
                if any(b[(p * 256 + i) * 8:(p * 256 + i) * 8 + 8]):
                    covbits[cfg][p].add(i)

def covstr(cfg):
    c = covbits.get(cfg)
    if not c:
        return '-'
    return ' '.join(f'{len(c[p])}' for p in range(7))

print('| configuration | top | generics | random cycles (jobs) | sweep cases INT/NMI/WAIT/BUSRQ/INT+NMI | sweep cycles | '
      'ZEX lockstep tests (cycles) | opcodes hit base/CB/ED/DD/FD/DDCB/FDCB | result |')
print('|---|---|---|---|---|---|---|---|---|')
order = FLEET + [c for c in CONFIGS if c not in FLEET] + list(FLEET_WRAPPERS)
for c in order:
    d = st.get(c)
    if d is None:
        continue
    top, src, g = CONFIGS[FLEET_WRAPPERS[c][0]] if c in FLEET_WRAPPERS else CONFIGS[c]
    gen = ', '.join(f'{k}={v}' for k, v in g.items() if not k.startswith('Flag')) + (' GB flags' if 'Flag_C' in g else '')
    bad = d['rfail'] + d['sfail'] + d['zlfail'] + sum(1 for x in d['i80'] if x[1])
    print(f"| {c}{' (fleet)' if c in FLEET else ''} | {top}{' (Phoenix)' if src == 'phx' else ''} | {gen} | "
          f"{d['rcyc']:,} ({d['rjobs']}) | {'/'.join(str(x) for x in d['cases']) if d['sjobs'] else '-'} | "
          f"{d['scyc']:,} | {d['zl']} ({d['zlcyc']:,}) | {covstr(c)} | {'PASS' if not bad else 'FAIL'} |")
print()
tot = sum(d['rcyc'] + d['scyc'] + d['zlcyc'] + sum(x[2] for x in d['i80']) for d in st.values())
print(f'Total lockstep cycles: {tot:,}; failing jobs: {len(fails)} {fails[:20]}')
print()
print('8080 exercisers (lockstep):')
for c, d in st.items():
    for prog, rc, cyc, done in d['i80']:
        print(f'- {c} {prog}: {cyc:,} cycles, {"ran to completion" if done else "bounded prefix"}, {"PASS" if rc == 0 else "FAIL"}')

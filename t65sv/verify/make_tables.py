#!/usr/bin/env python3
# make_tables.py [download dir]: per-program Lorenz and VICE tables (markdown) from the result files in results/.
#   results/lorenz_table.md, results/vice_table.md, and a one-line summary of each on stdout.
import re, os, glob, sys
DL = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser('~/dl')
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results')

def load(path):
    out = {}
    if not os.path.exists(path): return out
    for l in open(path):
        m = re.match(r'(PASS|FAIL|TIMEOUT|D7FF\?)\s+(\S+)\s+(.*)', l)
        if not m: continue
        k = m.group(2)
        cyc = re.search(r'(?:cpu_)?cycles=(\d+)', l); mis = re.search(r'mismatches=(\d+)', l)
        o = re.search(r'out="(.*)"', l)
        out[k] = dict(r=m.group(1), cyc=int(cyc.group(1)) if cyc else 0, mis=int(mis.group(1)) if mis else -1,
                      out=(o.group(1) if o else ''))
    return out

def short(k): return k.split('/CPU/')[-1] if '/CPU/' in k else os.path.basename(k)

# ---------------------------------------------------------------- Lorenz
L = DL + '/vicetp/Lorenz-2.15/src'
progs = sorted(p for p in glob.glob(L + '/*.prg')
               if not re.search(r'-dtv|-plus4|nextdisk|template|cpuport128', p))
flat = load(R + '/lorenz_flat_lockstep.txt')
c64 = {}
for f in ['lorenz_c64_lockstep.txt', 'lorenz_c64_lockstep_first5.txt', 'lorenz_c64_lockstep_rest.txt', 'lorenz_c64_lockstep_2.txt']:
    c64.update(load(R + '/' + f))
solo = load(R + '/lorenz_c64_solo6510.txt')

def detail(d):
    o = d['out'].strip('|').split('|')
    o = [x for x in o if x and not x.endswith('- ok')]
    return ' / '.join(' '.join(x.split()) for x in o[1:6]) if len(o) > 1 else ''

rows = []; tot = dict(pass_=0, fail=0, other=0); mis_bad = 0; c64cyc = 0; c64n = 0
for p in progs:
    n = os.path.basename(p)
    f = flat.get(p); c = c64.get(p)
    fs = f['r'] if f else 'not finished (1 h limit)'
    cs = c['r'] if c else ''
    if c: c64cyc += c['cyc']; c64n += 1
    for d in (f, c):
        if d and d['mis'] not in (0, -1): mis_bad += 1
    final = 'PASS' if (f and f['r'] == 'PASS') or (c and c['r'] == 'PASS') else (c['r'] if c else fs)
    note = ''
    if final != 'PASS' and c: note = detail(c) or ('no result within %dM cycles' % (c['cyc'] // 1000000) if c['r'] == 'TIMEOUT' else '')
    if final == 'PASS': tot['pass_'] += 1
    elif final == 'FAIL': tot['fail'] += 1
    else: tot['other'] += 1
    if c or (f and f['r'] != 'PASS') or not f:
        rows.append(f"| {n} | {fs} | {cs or '—'} | **{final}** | {note} |")
with open(R + '/lorenz_table.md', 'w') as o:
    o.write('| Program | Flat C64 | Mini-C64 | Result | Detail (from the test\'s own output) |\n|---|---|---|---|---|\n')
    o.write('\n'.join(rows) + '\n')
    passed_flat = sorted(os.path.basename(p) for p in progs if flat.get(p, {}).get('r') == 'PASS' and p not in c64)
    o.write(f"\nPassed in the flat C64 (not rerun): {len(passed_flat)} programs: " + ', '.join(x[:-4] for x in passed_flat) + '.\n')
print(f"lorenz: programs={len(progs)} pass={tot['pass_']} fail={tot['fail']} other={tot['other']} "
      f"flat_runs={len(flat)} c64_runs={c64n} c64_cycles={c64cyc} nonzero_mismatch_runs={mis_bad}")
if solo:
    print('solo6510: ' + ', '.join(f"{os.path.basename(k)} {v['r']}" for k, v in sorted(solo.items())))

# ---------------------------------------------------------------- VICE
tl = {}
tlf = DL + '/vicetb/x64sc-testlist.txt'
if os.path.exists(tlf):
    for l in open(tlf):
        f = l.strip().split(',')
        if f[0].startswith('../CPU/'): tl[f[0].replace('../CPU/', '') + f[1]] = f[2:]
vflat = load(R + '/vice_flat_lockstep.txt')
vc64 = load(R + '/vice_c64_lockstep.txt')
rows = []; cnt = {}; vcyc = sum(v['cyc'] for v in vflat.values()) + sum(v['cyc'] for v in vc64.values())
for k in sorted(vflat):
    s = short(k); t = tl.get(s, ['not in testlist'])
    mode = t[0]; extra = ','.join(t[2:]) if len(t) > 2 else ''
    f = vflat[k]; c = vc64.get(k)
    if f['r'] == 'PASS' or (c and c['r'] == 'PASS'): final = 'PASS'
    elif 'expect:timeout' in extra: final = 'T65: no jam'
    elif mode != 'exitcode': final = 'n/a (' + mode + ')'
    elif c: final = c['r']
    elif 'ntsc' in extra: final = 'not run (NTSC)'
    else: final = 'not run (budget %sM)' % (int(t[1]) // 1000000)
    cnt[final.split(' (')[0]] = cnt.get(final.split(' (')[0], 0) + 1
    rows.append(f"| {s} | {mode}{(' ' + extra) if extra else ''} | {f['r']} | {c['r'] if c else '—'} | **{final}** |")
with open(R + '/vice_table.md', 'w') as o:
    o.write('| Program | Testbench mode | Flat C64 | Mini-C64 | Result |\n|---|---|---|---|---|\n' + '\n'.join(rows) + '\n')
bad = sum(1 for v in list(vflat.values()) + list(vc64.values()) if v['mis'] not in (0, -1))
print(f"vice: programs={len(vflat)} " + ' '.join(f'{k}={v}' for k, v in sorted(cnt.items())) +
      f" cycles={vcyc} nonzero_mismatch_runs={bad}")

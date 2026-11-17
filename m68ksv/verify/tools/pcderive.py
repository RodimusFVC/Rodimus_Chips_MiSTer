#!/usr/bin/env python3
# Copyright (C) 2026 Rodimus
# Locate the 68000's PC-register loads in m68ksv's microcode (field pu): reads lockstep PCTRACE "P" lines (fx68k's PC
# register changed: at its T1 = m68ksv's e0, AU -> PC; at its T3 = m68ksv's e2, bus -> PC) and names, per m68ksv
# micro-word and phase, which m68ksv value the new PC equals (pre-edge values):
#   T1: fpc / pcx / aur      T3: fpc / fpc - 2 / fpc + 2 / pcx / at / vector address / fault address
#   PCTRACE=1 lockstep ... | grep '^P ' > p.txt;  python3 -I verify/tools/pcderive.py <ualabels.h> p.txt
# Output: one line per (phase, word) with the counts of each matching source; a word whose loads match no single source
# is marked MIXED (needs a look, not a code). A load of only one half (fx68k moves PCL and PCH separately on its
# T3; seen when fpc crosses a 64K boundary) matches nothing and shows as 'none'.
import sys, collections, bisect
lab = []
for l in open(sys.argv[1]):
    if l.startswith('#define UA_'):
        a = l.split(); lab.append((int(a[2]), a[1][3:]))
lab.sort(); la = [x[0] for x in lab]
def name(u):
    i = bisect.bisect_right(la, u) - 1
    return '%s+%d' % (lab[i][1], u - lab[i][0]) if i >= 0 else str(u)
c = collections.defaultdict(collections.Counter)
for fn in sys.argv[2:]:
    for l in open(fn):
        if not l.startswith('P '): continue
        a = l.split(); k = int(a[2]); pc = int(a[3], 16); fpc = int(a[4], 16); u = int(a[7])
        v = {a[i]: int(a[i + 1], 16) for i in range(8, len(a) - 1, 2)}
        src = []
        if k == 1:
            if pc == fpc: src.append('fpc')
            if pc == v['pcx']: src.append('pcx')
            if pc == v['aur']: src.append('aur')
        elif k == 3:
            if pc == fpc: src.append('fpc')
            if pc == (fpc - 2) & 0xffffffff: src.append('fpc-2')
            if pc == (fpc + 2) & 0xffffffff: src.append('fpc+2')
            if pc == v['pcx']: src.append('pcx')
            if pc == v['vec'] * 4: src.append('vec')
            if pc == v['fa']: src.append('fa')
            if pc == v['at']: src.append('at')
        c[(k, u)][' '.join(src) if src else 'none'] += 1
for (k, u) in sorted(c):
    m = c[(k, u)]
    common = set.intersection(*[set(s.split()) for s in m]) if all(s != 'none' for s in m) else set()
    print('T%d %4d %-18s %-12s %s' % (k, u, name(u), ' '.join(sorted(common)) if common else 'MIXED',
                                    ' '.join('[%s]:%d' % x for x in m.most_common(4))))

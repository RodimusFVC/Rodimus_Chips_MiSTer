#!/usr/bin/env python3
"""Summarise variant-oracle logs: per pair, the all-knob totals and each reverted knob's mismatch signature."""
import re, sys, collections
pat = re.compile(r'^\s+(\S+(?: knobs\])?)\s+chars\s+(\d+) frames\s+(\d+) mismatches\s+(\d+)\s+reads\s+(\d+) read-mismatches\s+(\d+)(.*)$')
tot = collections.OrderedDict()
for fn in sys.argv[1:]:
    pair = None
    for line in open(fn):
        if line.startswith('== '):
            pair = line[3:].strip(); tot.setdefault(pair, collections.OrderedDict()); continue
        m = pat.match(line)
        if not m or pair is None: continue
        knob, chars, frames, mism, reads, rmism, rest = m.groups()
        d = tot[pair].setdefault(knob, {'chars':0,'frames':0,'mism':0,'reads':0,'rmism':0,'sig':collections.Counter()})
        d['chars'] += int(chars); d['frames'] += int(frames); d['mism'] += int(mism); d['reads'] += int(reads); d['rmism'] += int(rmism)
        for s in re.findall(r'\s{2}(.+?):(\d+)(?=\s{2}|$)', rest):
            d['sig'][s[0].strip()] += int(s[1])
for pair, ks in tot.items():
    a = ks.get('[all knobs]')
    print(f"== {pair}: all knobs -> {a['mism']} char mismatches / {a['chars']} chars, {a['rmism']} read mismatches / {a['reads']} reads, {a['frames']} frames")
    for k, d in ks.items():
        if k == '[all knobs]': continue
        sig = ', '.join(f"{s} {n}" for s, n in d['sig'].most_common(4))
        print(f"   {k:<16} char mism {d['mism']:>9}  read mism {d['rmism']:>6}   [{sig}]")

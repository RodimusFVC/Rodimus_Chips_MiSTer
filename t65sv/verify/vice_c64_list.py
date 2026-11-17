#!/usr/bin/env python3
# vice_c64_list.py <x64sc-testlist.txt> <vice_flat_lockstep.txt>: the VICE CPU programs to rerun on the mini-C64,
# one "<prg> <max cycles>" per line: exit-code tests that did not pass in the flat C64, minus those the testbench
# expects to time out (JAM tests), NTSC-only tests, and budgets over 100M cycles.
import sys, re
tl = {}
for l in open(sys.argv[1]):
    f = l.strip().split(',')
    if f[0].startswith('../CPU/'): tl[f[0].replace('../CPU/', '') + f[1]] = f[2:]
for l in open(sys.argv[2]):
    m = re.match(r'(\S+) (\S+)', l)
    if not m or m.group(1) == 'PASS': continue
    k = m.group(2).split('/CPU/')[-1]; t = tl.get(k)
    if not t or t[0] != 'exitcode': continue
    extra = ','.join(t[2:])
    if 'expect:timeout' in extra or 'ntsc' in extra or int(t[1]) > 100000000: continue
    print(m.group(2), t[1])

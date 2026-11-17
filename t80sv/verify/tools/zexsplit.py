#!/usr/bin/env python3
"""Split ZEXDOC / ZEXALL into one .COM per test (the test table is cut down to a single entry), so the
exerciser can run in parallel. usage: zexsplit.py <zex.com> <out dir>  -> prints the number of tests"""
import os, sys
src, out = sys.argv[1], sys.argv[2]
b = bytearray(open(src, 'rb').read())
pat = bytes([0x7E, 0x23, 0xB6, 0xCA])           # loop: ld a,(hl); inc hl; or (hl); jp z,done
i = b.index(pat)
assert b[i - 3] == 0x21                         # ld hl,tests
tests = b[i - 2] | b[i - 1] << 8
t = tests - 0x100
ptrs = []
while b[t] | b[t + 1]:
    ptrs.append((b[t], b[t + 1]))
    t += 2
os.makedirs(out, exist_ok=True)
base = os.path.splitext(os.path.basename(src))[0]
for k, (lo, hi) in enumerate(ptrs):
    c = bytearray(b)
    c[tests - 0x100] = lo
    c[tests - 0x100 + 1] = hi
    c[tests - 0x100 + 2] = 0
    c[tests - 0x100 + 3] = 0
    open(os.path.join(out, f'{base}_{k:02d}.com'), 'wb').write(c)
print(len(ptrs))

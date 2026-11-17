#!/usr/bin/env python3
# mif2hex.py in.mif out.hex : Altera MIF (hex radix) -> one byte per line for $readmemh
import re, sys
src, dst = sys.argv[1], sys.argv[2]
depth = None; mem = {}
for line in open(src, encoding='latin-1'):
    line = line.split('--')[0].strip()
    m = re.match(r'DEPTH\s*=\s*(\d+)', line)
    if m: depth = int(m.group(1)); continue
    m = re.match(r'\[([0-9A-Fa-f]+)\.\.([0-9A-Fa-f]+)\]\s*:\s*([0-9A-Fa-f]+)\s*;', line)
    if m:
        for a in range(int(m.group(1), 16), int(m.group(2), 16) + 1): mem[a] = int(m.group(3), 16)
        continue
    m = re.match(r'([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;', line)
    if m: mem[int(m.group(1), 16)] = int(m.group(2), 16)
with open(dst, 'w') as f:
    for a in range(depth): f.write('%02x\n' % mem.get(a, 0))

#!/usr/bin/env python3
# SingleStepTests 65816 JSON -> compact binary for sst816.cpp
# state: pc(u16) s(u16) p a(u16) x(u16) y(u16) dbr d(u16) pbr e nram(u32) {addr(u32) val(u8)}*
# cycle: addr(u32) val(u8) valid(u8) flags(u8: bit7..0 = d p v r e m x l)
import json, struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
out = bytearray(struct.pack('<I', len(d)))
def st(s):
    b = struct.pack('<HHBHHHBHBBI', s['pc'], s['s'], s['p'], s['a'], s['x'], s['y'], s['dbr'], s['d'], s['pbr'], s['e'], len(s['ram']))
    for a, v in s['ram']: b += struct.pack('<IB', a, v)
    return b
for t in d:
    out += st(t['initial']) + st(t['final'])
    out += struct.pack('<H', len(t['cycles']))
    for a, v, f in t['cycles']:
        fl = 0
        for i, ch in enumerate(f):
            if ch not in '-w': fl |= 0x80 >> i
        out += struct.pack('<IBBB', a if a is not None else 0, v if v is not None else 0, 0 if v is None else 1, fl)
open(dst, 'wb').write(out)

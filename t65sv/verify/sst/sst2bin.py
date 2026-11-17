#!/usr/bin/env python3
# Converts one SingleStepTests 65x02 JSON file to the compact binary read by sst.cpp.
# test: pc(u16) s a x y p (u8) nram(u16) {addr(u16) val(u8)}*  [final: same]  ncyc(u16) {addr(u16) val(u8) rw(u8:1=read)}*
import json, struct, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src))
out = bytearray(struct.pack('<I', len(d)))
def st(s):
    b = struct.pack('<HBBBBBH', s['pc'], s['s'], s['a'], s['x'], s['y'], s['p'], len(s['ram']))
    for a, v in s['ram']: b += struct.pack('<HB', a, v)
    return b
for t in d:
    out += st(t['initial']) + st(t['final'])
    out += struct.pack('<H', len(t['cycles']))
    for a, v, k in t['cycles']:
        out += struct.pack('<HBB', a, v, 1 if k == 'read' else 0)
open(dst, 'wb').write(out)

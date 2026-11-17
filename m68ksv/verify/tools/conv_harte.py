#!/usr/bin/env python3
# Convert Tom Harte / SingleStepTests 680x0 JSON(.gz) files to the compact binary the harness reads.
#   python3 -I conv_harte.py <suite dir with *.json.gz> <out dir>
# Record: name, initial + final state (d0-d7 a0-a6 usp ssp sr pc, prefetch[2], ram[]), length, transactions.
import gzip, json, os, struct, sys, glob

REGS = ['d0','d1','d2','d3','d4','d5','d6','d7','a0','a1','a2','a3','a4','a5','a6','usp','ssp','sr','pc']

def state(s):
    b = struct.pack('<19I', *[s[r] & 0xffffffff for r in REGS])
    b += struct.pack('<2H', s['prefetch'][0] & 0xffff, s['prefetch'][1] & 0xffff)
    ram = s['ram']
    b += struct.pack('<I', len(ram))
    for a, v in ram:
        b += struct.pack('<IB', a & 0xffffff, v & 0xff)
    return b

def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for f in sorted(glob.glob(os.path.join(src, '*.json.gz'))):
        tests = json.load(gzip.open(f))
        name = os.path.basename(f)[:-len('.json.gz')]
        with open(os.path.join(out, name + '.bin'), 'wb') as o:
            o.write(b'M68T' + struct.pack('<I', len(tests)))
            for t in tests:
                n = t['name'].encode()[:255]
                o.write(struct.pack('<H', len(n)) + n)
                o.write(state(t['initial']))
                o.write(state(t['final']))
                tr = t['transactions']
                o.write(struct.pack('<II', t['length'], len(tr)))
                for x in tr:
                    if x[0] == 'n':
                        o.write(struct.pack('<BIBIBI', ord('n'), x[1], 0, 0, 0, 0))
                    else:
                        o.write(struct.pack('<BIBIBI', ord(x[0]), x[1], x[2], x[3] & 0xffffff,
                                            1 if x[4] == '.w' else 0, x[5] & 0xffff))
        print(name, len(tests))

main()

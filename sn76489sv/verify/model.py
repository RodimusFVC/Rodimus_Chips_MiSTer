#!/usr/bin/env python3
"""model.py - MAME sn76496.cpp behaviour per variant (Python port, reference only) and the sn76489sv check.

  model.py stim <file> <edges> [seed]      random write stream (edge % 4 == 2)
  model.py check <stim> <prefix>           compare <prefix>.ticks / .ready against the model, every variant

Reset state as sn76489sv (attenuation 15 on every chip; MAME's device_start full volume is not modelled).
"""
import random, struct, sys

# MAME constructor arguments: feedback mask, tap1, tap2, clock divider, ncr, sega
VARIANTS = [('SN76489', 0x4000, 0x01, 0x02, 8, False, False), ('SN76489A', 0x10000, 0x04, 0x08, 8, False, False),
            ('SN76496', 0x10000, 0x04, 0x08, 8, False, False), ('SN76494', 0x10000, 0x04, 0x08, 1, False, False),
            ('SN94624', 0x4000, 0x01, 0x02, 1, False, False), ('SEGAPSG', 0x8000, 0x01, 0x08, 8, False, True),
            ('NCR8496', 0x8000, 0x02, 0x20, 8, True, False)]
VOL = [255, 203, 161, 128, 102, 81, 64, 51, 40, 32, 26, 20, 16, 13, 10, 0]

class Psg:
    def __init__(s, fb, t1, t2, div, ncr, sega):
        s.fb, s.t1, s.t2, s.div, s.ncr, s.sega = fb, t1, t2, div, ncr, sega
        s.reg = [0] * 8
        for c in range(4): s.reg[2 * c + 1] = 15
        s.per = [0 if sega else 0x400] * 3 + [0]; s.cnt = [0] * 4; s.out = [0] * 4
        s.rng = fb; s.out[3] = s.rng & 1; s.last = 3 if sega else 0
    def write(s, d):
        if d & 0x80:
            r = (d >> 4) & 7; s.last = r
            if s.ncr and r == 6 and (d & 4) != (s.reg[6] & 4): s.rng = s.fb
            s.reg[r] = (s.reg[r] & 0x3f0) | (d & 15)
        else: r = s.last
        c = r >> 1
        if r in (0, 2, 4):
            if not d & 0x80: s.reg[r] = (s.reg[r] & 15) | ((d & 0x3f) << 4)
            s.per[c] = s.reg[r] if (s.reg[r] or s.sega) else 0x400
            if r == 4 and s.reg[6] & 3 == 3: s.per[3] = s.per[2] << 1
        elif r & 1:
            if not d & 0x80: s.reg[r] = (s.reg[r] & 0x3f0) | (d & 15)
        else:
            if not d & 0x80: s.reg[r] = (s.reg[r] & 0x3f0) | (d & 15)
            n = s.reg[6]; s.per[3] = s.per[2] << 1 if n & 3 == 3 else 1 << (5 + (n & 3))
            if not s.ncr: s.rng = s.fb
    def tick(s):
        for i in range(3):
            s.cnt[i] -= 1
            if s.cnt[i] <= 0: s.out[i] ^= 1; s.cnt[i] = s.per[i]
        s.cnt[3] -= 1
        if s.cnt[3] <= 0:
            a = (s.rng & s.t1) != 0
            b = ((s.rng & s.t2) != (s.t2 if s.ncr else 0)) and bool(s.reg[6] & 4)
            s.rng = (s.rng >> 1) | s.fb if a != b else s.rng >> 1
            s.out[3] = s.rng & 1; s.cnt[3] = s.per[3]
    def sound(s):
        return sum(VOL[s.reg[2 * c + 1] & 15] if s.out[c] else 0 for c in range(4))

def stim(path, edges, seed=1):
    rnd = random.Random(seed); k = 40; L = []
    while k < edges - 100:
        mode = rnd.random()
        if mode < 0.5: b = rnd.randrange(256)                                  # anything at all
        elif mode < 0.75: c = rnd.randrange(3); p = rnd.choice([0, 1, 2, 3, rnd.randrange(16), rnd.randrange(1024)]); \
                b = None; L.append((k, 0x80 | c << 5 | (p & 15))); k += 4 * rnd.randrange(1, 8); b = (p >> 4) & 0x3f
        elif mode < 0.9: b = 0x90 | rnd.randrange(4) << 5 | rnd.choice([0, 0, 3, 7, 15, rnd.randrange(16)])
        else: b = 0xe0 | rnd.randrange(8)
        L.append((k, b)); k += 4 * rnd.choice([1, 2, 5, 20, 100, 400])
    with open(path, 'w') as f:
        for e, b in L: f.write(f'{e + 2 - e % 4} {b:02x}\n')

def check(stim_path, pre):
    W = [(int(l.split()[0]), int(l.split()[1], 16)) for l in open(stim_path)]
    raw = open(pre + '.ticks', 'rb').read(); rec = 4 + 1 + 4 + 14
    T = [struct.unpack('<IBI7h', raw[i:i + rec]) for i in range(0, len(raw) - rec + 1, rec)]
    R = {}
    for l in open(pre + '.ready'):
        v, e, lv = map(int, l.split()); R.setdefault(v, []).append((e, lv))
    ok = True
    for v, (name, *par) in enumerate(VARIANTS):
        p = Psg(*par); wi = 0; ticks = [t for t in T if t[1] >> v & 1]; bad = badS = 0; first = None
        gaps = {ticks[i + 1][0] - ticks[i][0] for i in range(len(ticks) - 1)}
        for e, m, outs, *snd in ticks:
            while wi < len(W) and W[wi][0] < e: p.write(W[wi][1]); wi += 1
            p.tick()
            got = (outs >> 4 * v) & 15; exp = sum(p.out[i] << i for i in range(4))
            if got != exp:
                bad += 1; first = first or (e, got, exp)
            if snd[v] != p.sound(): badS += 1
        # READY: low on the edge after each write, high again RDY ce later (ce every 4 edges)
        rdy = 32 if par[3] == 8 else 4; expR = []
        for e, _ in W:
            if expR and expR[-1][0] > e: expR.pop()             # a write while READY is low restarts the count
            else: expR.append((e, 0))
            ce_after = [x for x in range(e + 1, e + 4 * rdy + 8) if x % 4 == 0][:rdy]
            expR.append((ce_after[-1], 1))
        exp_r = [x for x in expR if x[0] < (T[-1][0] if T else 0)]
        got_r = [x for x in R.get(v, []) if x[0] < (T[-1][0] if T else 0)]
        rok = got_r == exp_r
        ok &= bad == 0 and badS == 0 and rok and gaps == {64 if par[3] == 8 else 8}
        print(f'{name:9s} ticks {len(ticks):7d} (every {sorted(gaps)} edges)  output bits differ {bad}'
              f'{" first " + str(first) if first else ""}  sound differs {badS}  READY {"ok" if rok else "DIFFERS"} '
              f'({len(got_r)} edges)')
    print('PASS' if ok else 'FAIL'); return ok

if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['stim']: stim(a[1], int(a[2]), int(a[3]) if len(a) > 3 else 1)
    elif a[:1] == ['check']: sys.exit(0 if check(a[1], a[2]) else 1)
    else: print(__doc__)

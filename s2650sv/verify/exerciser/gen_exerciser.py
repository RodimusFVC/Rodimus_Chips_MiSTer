#!/usr/bin/env python3
"""Generate exerciser.asm: a self-checking Signetics 2650 instruction exerciser.

Each test sets PSL and registers, runs the instruction(s) under test and compares R0-R3, PSL and any
extra result it left in RES (memory, PSU) with its expected-value table (COMR / COMA, BCFA to fail). Expected values come from the model below, which follows sgs2650, the core the fleet runs. Where
sgs2650 departs from the Signetics manual the model knows both, and those tests are listed in
exerciser_quirks.txt: on silicon or MAME they would fail by design.

Coverage: every opcode in every addressing mode (register, immediate, relative and absolute, direct and
indirect, indexed with and without auto increment / decrement, indirect indexed), all branches and
branch-to-subroutine forms incl. ZBRR / ZBSR / BXA / BSXA (direct / indirect, taken / not taken), RETC /
RETE, PSU / PSL instructions, WC / COM / IDC / OVF / C, DAR, RRR / RRL, register banks, 8-level return
stack and SP wrap, interrupts (two vectors, II), HALT left by an interrupt, sense / flag, all six I/O
instructions, code and data in all four 8K pages.

Result: 'P' (pass) or 'F' (fail) written to extended port FF and to $7FF0; on a fail the test bench prints
the address of the failing check (exerciser.lst maps it to the test). Console text on extended port FE. Test bench protocol (verify/tb/lockstep.cpp, prog
mode): WRTE FD = interrupt request with that vector after (last WRTE FA) * 4 clocks, held until INTACK;
WRTE FC = sense input (bit 0), or sense = flag output when bit 1 is set. I/O reads return the last value
written to the port XOR $5A.
"""
import random, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from asm2650 import Asm

random.seed(2650)

# ------------------------------------------------------------------------------------------------ model
def sign(v):
    return 0 if v == 0 else (1 if v < 0x80 else 2)

def alu(op3, a, b, psl, sheet=False):
    """op_alu of sgs2650_pack (sheet=True: Signetics manual). Returns (result, psl)."""
    c, com, wc = psl & 1, (psl >> 1) & 1, (psl >> 3) & 1
    a7, b7 = a >> 7, b >> 7
    p = psl
    if op3 == 0: vt = vo = b
    elif op3 == 1: vt = vo = a ^ b
    elif op3 == 2: vt = vo = a & b
    elif op3 == 3: vt = vo = a | b
    elif op3 == 4:
        cin = c & wc
        vt = vo = (a + b + cin) & 0xFF
        t7 = vt >> 7
        cf = (a7 & b7) | ((1 - t7) & (a7 | b7))
        ov = (a7 & b7 & (1 - t7)) | ((1 - a7) & (1 - b7) & t7)
        idc = ((a & 15) + (b & 15) + cin) >> 4 if sheet else int((vt & 15) < (a & 15))
        p = (p & ~0x25) | cf | (ov << 2) | (idc << 5)
    elif op3 == 5:
        bin_ = (1 - c) & wc
        vt = vo = (a - b - bin_) & 0xFF
        t7 = vt >> 7
        cf = 1 - (((1 - a7) & b7) | (t7 & ((1 - a7) | b7)))
        ov = (a7 & (1 - b7) & (1 - t7)) | ((1 - a7) & b7 & t7)
        idc = int((a & 15) - (b & 15) - bin_ >= 0) if sheet else int((vt & 15) <= (a & 15))
        p = (p & ~0x25) | cf | (ov << 2) | (idc << 5)
    else:
        vt = (a - b) & 0xFF
        t7 = vt >> 7
        if vt == 0: cc = 0
        elif com: cc = 2 if a < b else 1
        elif sheet: cc = 2 if (a - 256 * a7) < (b - 256 * b7) else 1
        else:
            lt = (a7 & (1 - b7)) | ((1 - a7) & (1 - b7) & t7) | (a7 & b7 & (1 - t7))
            cc = 2 if lt else 1
        return a, (p & 0x3F) | (cc << 6)
    return vo, (p & 0x3F) | (sign(vt) << 6)

def alu_q(op3, a, b, psl):
    r, p = alu(op3, a, b, psl)
    rs, ps = alu(op3, a, b, psl, sheet=True)
    q = None
    if (r, p) != (rs, ps):
        what = []
        if (p ^ ps) & 0xC0: what.append('CC %d (manual %d)' % (p >> 6, ps >> 6))
        if (p ^ ps) & 0x20: what.append('IDC %d (manual %d)' % ((p >> 5) & 1, (ps >> 5) & 1))
        q = ', '.join(what)
    return r, p, q

def rot(left, v, psl, sheet=False):
    c, wc = psl & 1, (psl >> 3) & 1
    p = psl
    if left:
        r = ((v << 1) | (c if wc else v >> 7)) & 0xFF
        if wc: p = (p & ~0x21) | (v >> 7) | (((v >> 4) & 1) << 5)
    else:
        r = (v >> 1) | ((c if wc else v & 1) << 7)
        if wc: p = (p & ~0x21) | (v & 1) | (((v >> 6) & 1) << 5)
    if sheet and wc and ((r ^ v) & 0x80): p |= 0x04     # manual: OVF set when bit 7 changes (WC=1)
    return r, (p & 0x3F) | (sign(r) << 6)

def dar(v, psl):
    t = v if psl & 1 else (v + 0xA0) & 0xFF
    if not psl & 0x20: t = (t & 0xF0) | ((t + 0x0A) & 0x0F)
    return t, (psl & 0x3F) | (sign(t) << 6)            # manual: CC meaningless

def R(): return random.randrange(256)

def rpsl(rs=None):
    p = R()
    if rs is not None: p = (p & ~0x10) | (rs << 4)
    return p

# ------------------------------------------------------------------------------------------------ tests
class Test:
    def __init__(self, title, setup, body, exp, data=(), extra=(), quirk=None, group=None):
        self.title, self.setup, self.body, self.exp = title, setup, list(body), list(exp)
        self.data, self.extra, self.quirk, self.group = list(data), list(extra), quirk, group

    def render(self, n, P):
        L = 'T%d_' % n
        f = lambda t: t.replace('{L}', L).replace('{P}', P)
        o = []
        if self.group:
            o.append(';==================== ' + self.group)
            for ch in self.group + ' ':
                o += ['        lodi,r0 %d' % ord(ch), '        wrte,r0 $FE']
        o.append('; T%d %s' % (n, self.title))
        o += ['        lodi,r0 $%02X' % self.setup.get('psl', 0), '        lpsl']
        for r in (1, 2, 3):
            if 'r%d' % r in self.setup: o.append('        lodi,r%d $%02X' % (r, self.setup['r%d' % r]))
        if 'r0' in self.setup: o.append('        lodi,r0 $%02X' % self.setup['r0'])
        o += [f(s) for s in self.body]
        # R0-R3 and PSL against the table, then any extra results the test left in RES+5..
        cm = 'comr' if len(self.exp) <= 7 else 'coma'        # COMR while the table is in reach
        o += ['        stra,r0 %s_res' % P, '        spsl', '        %s,r0 %se+4' % (cm, L), '        bcfa,eq %s_fail' % P,
              '        loda,r0 %s_res' % P]                 # PSL first: the compares set CC
        for r in range(4):
            o += ['        %s,r%d %se+%d' % (cm, r, L, r), '        bcfa,eq %s_fail' % P]
        o += [f(s) for s in self.extra]
        for i in range(5, len(self.exp)):
            o += ['        loda,r0 %s_res+%d' % (P, i), '        coma,r0 %se+%d' % (L, i), '        bcfa,eq %s_fail' % P]
        o += ['        bctr,un %snext' % L]
        o.append('%se:    db %s' % (L, ','.join('$%02X' % (e & 0xFF) for e in self.exp)))
        o += [f(s) for s in self.data]
        o.append('%snext:' % L)
        return o

T = []
def add(*a, **k):
    T.append(Test(*a, **k))

def regs_of(st):
    return [st.get('r%d' % i, 0) for i in range(4)]

def cc_after_setup(st):
    """CC once the test prologue has run: the last register loaded sets it"""
    if 'r0' in st: return sign(st['r0'])
    if 'r3' in st: return sign(st['r3'])
    return st.get('psl', 0) >> 6

def psl_in(st):
    return (st.get('psl', 0) & 0x3F) | (cc_after_setup(st) << 6)

def base_regs(st):
    """R0 = PSL value when the test does not load R0 (the prologue loads PSL through R0)"""
    r = regs_of(st)
    if 'r0' not in st: r[0] = st.get('psl', 0)
    return r

OPN = ['lod', 'eor', 'and', 'ior', 'add', 'sub', 'str', 'com']
PAIRS = [(0x00, 0x00), (0x7F, 0x01), (0x80, 0xFF), (0xFF, 0x01), (0x0F, 0x01), (0x99, 0x01), (0x50, 0x50),
         (0x80, 0x80), (0xF0, 0x10), (0x37, 0xC9), (0x01, 0x02), (0xFE, 0xFF), (0x85, 0xFE), (0xFE, 0x85)]

def alu_tests():
    first = True
    for op3 in (0, 1, 2, 3, 4, 5, 7):
        name = OPN[op3]
        heavy = op3 in (4, 5, 7)
        grp = lambda: ('ALU' if first else None)
        # Z: R0 = R0 op Rn (COM: compare R0 with Rn)
        for n in range(1 if op3 == 2 else 0, 4):          # ANDZ R0 is HALT
            for a, b in (random.sample(PAIRS, 3) if heavy else random.sample(PAIRS[:4], 2)) if n else [(0x5A, 0x5A), (0x80, 0x80)]:
                st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': a}
                if n: st['r%d' % n] = b
                regs = base_regs(st)
                res, p, q = alu_q(op3, regs[0], regs[n], psl_in(st))
                regs[0] = res
                add('%sz r%d a=%02X b=%02X' % (name, n, regs_of(st)[0], regs_of(st)[n]), st,
                    ['        %sz r%d' % (name, n)], regs + [p], quirk=q, group=grp())
                first = False
        # I: Rn = Rn op imm, with WC / C / COM from the random PSL
        for n in range(4):
            for a, b in (PAIRS[:7] if heavy and n == 1 else [random.choice(PAIRS)]):
                st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
                st['r%d' % n] = a
                regs = base_regs(st)
                res, p, q = alu_q(op3, regs[n], b, psl_in(st))
                regs[n] = res
                add('%si,r%d a=%02X b=%02X psl=%02X' % (name, n, a, b, st['psl']), st,
                    ['        %si,r%d $%02X' % (name, n, b)], regs + [p], quirk=q)
                # same operands again with the carry and compare-mode bits flipped
                if heavy and n == 1:
                    st2 = dict(st, psl=st['psl'] ^ 0x0B)
                    regs = base_regs(st2)
                    res, p, q = alu_q(op3, regs[n], b, psl_in(st2))
                    regs[n] = res
                    add('%si,r%d a=%02X b=%02X psl=%02X' % (name, n, a, b, st2['psl']), st2,
                        ['        %si,r%d $%02X' % (name, n, b)], regs + [p], quirk=q)
        # relative / absolute, direct / indirect: Rn = Rn op mem, all four registers in one test
        for mode in ('r', 'r*', 'a', 'a*'):
            st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
            regs = base_regs(st)
            p = psl_in(st)
            body, data, qs = [], [], []
            ind = '*' if '*' in mode else ''
            for n in (1, 2, 3, 0):
                b_ = random.choice(PAIRS)[1]
                regs[n], p, q = alu_q(op3, regs[n], b_, p)
                if q: qs.append(q)
                body.append('        %s%s,r%d %s%s' % (name, mode[0], n, ind, '{L}p%d' % n if ind else '{L}d%d' % n))
                data += ['{L}d%d:  db $%02X' % (n, b_), '{L}p%d:  dw {L}d%d' % (n, n)]
            add('%s%s,r1/r2/r3/r0 %s' % (name, mode[0], 'indirect' if ind else 'direct'), st, body, regs + [p],
                data=data, quirk='; '.join(qs) or None)
        # absolute indexed: R0 = R0 op mem[base + Rn (+/-1 first)], index R0 then R1, R2, R3 in one test,
        # direct and indirect (the index is added after the indirection)
        for ind in ('', '*'):
            for auto, delta in (('', 0), (',+', 1), (',-', -1)):
                k = random.randrange(2, 6)
                st = {'psl': rpsl(), 'r1': random.randrange(2, 6), 'r2': random.randrange(2, 6),
                      'r3': random.randrange(2, 6), 'r0': k}
                regs = base_regs(st)
                p = psl_in(st)
                body, data, qs = [], [], []
                for n in (0, 1, 2, 3):
                    regs[n] = (regs[n] + delta) & 0xFF
                    idx = regs[n]
                    b_ = random.choice(PAIRS)[1]
                    tbl = [R() for _ in range(4)]
                    tbl[3] = b_
                    regs[0], p, q = alu_q(op3, regs[0], b_, p)
                    if q: qs.append(q)
                    base = '{L}t%d%+d' % (n, 3 - idx)
                    body.append('        %sa,r0 %s,r%d%s' % (name, '*{L}p%d' % n if ind else base, n, auto))
                    data += ['{L}t%d:  db ' % n + ','.join('$%02X' % t for t in tbl), '{L}p%d:  dw ' % n + base]
                add('%sa,r0 %stb,r0/r1/r2/r3%s' % (name, ind, auto), st, body, regs + [p], data=data,
                    quirk='; '.join(qs) or None)
    # multi-byte add / subtract with carry (WC=1)
    for opn, op3 in (('add', 4), ('sub', 5)):
        x, y = random.randrange(1 << 16), random.randrange(1 << 16)
        st = {'psl': 0x08 | (1 if opn == 'sub' else 0), 'r1': x & 0xFF, 'r2': x >> 8, 'r3': R()}
        regs = base_regs(st)
        pin = psl_in(st)
        regs[1], p1 = alu(op3, regs[1], y & 0xFF, pin)
        regs[2], p2 = alu(op3, regs[2], y >> 8, p1)
        add('%s 16-bit with carry %04X %04X' % (opn, x, y), st,
            ['        %si,r1 $%02X' % (opn, y & 0xFF), '        %si,r2 $%02X' % (opn, y >> 8)], regs + [p2])

def str_tests():
    g = 'STR'
    for n in (0, 1, 2, 3):
        for v in random.sample((0x00, 0x45, 0xC3), 2):
            st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': v}
            regs = base_regs(st)
            p = psl_in(st)
            if n:
                regs[n] = v
                p = (p & 0x3F) | (sign(v) << 6)
            add('%s v=%02X' % ('nop' if n == 0 else 'strz r%d' % n, v), st,
                ['        %s' % ('nop' if n == 0 else 'strz r%d' % n)], regs + [p], group=g)
            g = None
    for mode in ('r', 'r*', 'a', 'a*'):
        for n in range(4):
            st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
            regs = base_regs(st)
            ind = '*' if '*' in mode else ''
            add('str%s,r%d %sm' % (mode[0], n, ind), st,
                ['        str%s,r%d %s' % (mode[0], n, '*{L}ptr' if ind else '{L}m')], regs + [psl_in(st), regs[n]],
                data=['{L}m:   db $EE', '{L}ptr: dw {L}m'], extra=['        loda,r0 {L}m', '        stra,r0 {P}_res+5'])
    # STRA indexed: index R1, R2, R3 then R0 in one test, each into its own table
    for ind in ('', '*'):
        for auto, delta in (('', 0), (',+', 1), (',-', -1)):
            st = {'psl': rpsl(), 'r1': random.randrange(2, 6), 'r2': random.randrange(2, 6),
                  'r3': random.randrange(2, 6), 'r0': random.randrange(2, 6)}
            regs = base_regs(st)
            body, data, extra, stored, qs = [], [], [], [], []
            for j, n in enumerate((1, 2, 3, 0)):
                old0 = regs[0]
                regs[n] = (regs[n] + delta) & 0xFF
                idx = regs[n]
                v = regs[0]
                if n == 0 and delta and ind:
                    v = old0
                    qs.append('STRA,R0 *a,R0,%s: sgs2650 stores R0 before the update (%02X), manual / MAME after '
                              '(%02X)' % (auto[1], old0, regs[0]))
                stored.append(v)
                base = '{L}t%d%+d' % (n, 3 - idx)
                body.append('        stra,r0 %s,r%d%s' % ('*{L}p%d' % n if ind else base, n, auto))
                data += ['{L}t%d:  db $EE,$EE,$EE,$EE' % n, '{L}p%d:  dw ' % n + base]
                extra += ['        loda,r0 {L}t%d+3' % n, '        stra,r0 {P}_res+%d' % (5 + j)]
            add('stra,r0 %stb,r1/r2/r3/r0%s' % (ind, auto), st, body, regs + [psl_in(st)] + stored,
                data=data, extra=extra, quirk='; '.join(qs) or None)

def rot_dar_tmi_tests():
    g = 'ROT DAR TMI'
    for left in (0, 1):
        for wc in (0, 1):
            for c in (0, 1):
                for i, v in enumerate((0x81, 0x40) if c else (0x10, 0x7F)):
                    n = (2 * c + i + wc) & 3
                    st = {'psl': (rpsl() & ~0x09) | (wc << 3) | c, 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
                    st['r%d' % n] = v
                    regs = base_regs(st)
                    r, p = rot(left, v, psl_in(st))
                    _, ps = rot(left, v, psl_in(st), sheet=True)
                    regs[n] = r
                    add('%s,r%d v=%02X wc=%d c=%d' % ('rrl' if left else 'rrr', n, v, wc, c), st,
                        ['        %s,r%d' % ('rrl' if left else 'rrr', n)], regs + [p], group=g,
                        quirk=None if p == ps else 'OVF unchanged (manual: set, bit 7 changed)')
                    g = None
    for i, v in enumerate((0x00, 0x09, 0x9A, 0x5F, 0xF5, 0xFF)):
        for c, idc in random.sample([(0, 0), (0, 1), (1, 0), (1, 1)], 1 if v not in (0x9A, 0xFF) else 4):
                n = i & 3
                st = {'psl': (rpsl() & ~0x21) | c | (idc << 5), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
                st['r%d' % n] = v
                regs = base_regs(st)
                regs[n], p = dar(v, psl_in(st))
                add('dar,r%d v=%02X c=%d idc=%d' % (n, v, c, idc), st, ['        dar,r%d' % n], regs + [p])
    for v, m in ((0xF0, 0xF0), (0xF0, 0x18), (0x81, 0x01)):
        for n in range(4):
            st = {'psl': rpsl(), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
            st['r%d' % n] = v
            regs = base_regs(st)
            pi = psl_in(st)
            add('tmi,r%d v=%02X m=%02X' % (n, v, m), st, ['        tmi,r%d $%02X' % (n, m)],
                regs + [(pi & 0x3F) | ((0 if (v & m) == m else 2) << 6)])

def psw_tests():
    g = 'PSW'
    for _ in range(3):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R()}
        regs, pi = base_regs(st), psl_in(st)
        m = R() & ~0x10
        add('cpsl $%02X' % m, st, ['        cpsl $%02X' % m], regs + [pi & ~m], group=g); g = None
        add('ppsl $%02X' % m, st, ['        ppsl $%02X' % m], regs + [pi | m])
        add('tpsl $%02X' % m, st, ['        tpsl $%02X' % m], regs + [(pi & 0x3F) | ((0 if (pi & m) == m else 2) << 6)])
        v = R() & ~0x10
        add('lpsl r0=%02X' % v, dict(st, r0=v), ['        lpsl'], regs_of(dict(st, r0=v)) + [v])
        add('spsl', st, ['        spsl'], [pi] + regs[1:] + [(pi & 0x3F) | (sign(pi) << 6)])
    # PSU: SP, II, flag (bits 4:3 left alone: 0 on the -A, user flags on the -B)
    for v in (0x05, 0x47, 0x62):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': v}
        regs = base_regs(st)
        add('lpsu / spsu v=%02X' % v, st, ['        lpsu', '        lodi,r0 $00', '        spsu', '        stra,r0 {P}_res+5',
                                          '        lodi,r0 $00', '        lpsu', '        lodi,r0 $00'],
            [0] + regs[1:] + [st['psl'] & 0x3F, v & 0x67])
    for m in (0x20, 0x40, 0x07, 0x67):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': 0x00}
        regs = base_regs(st)
        add('ppsu / tpsu / cpsu $%02X' % m, st,
            ['        lpsu', '        ppsu $%02X' % m, '        tpsu $%02X' % m, '        spsl', '        stra,r0 {P}_res+6',
             '        cpsu $%02X' % m, '        tpsu $%02X' % m, '        spsl', '        stra,r0 {P}_res+7', '        spsu',
             '        stra,r0 {P}_res+5', '        lodi,r0 $00'],
            [0] + regs[1:] + [st['psl'] & 0x3F, 0x00, st['psl'] & 0x3F, (st['psl'] & 0x3F) | 0x80])
    for s in (1, 0):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R()}
        regs = base_regs(st)
        add('sense=%d: spsu, tpsu $80' % s, st,
            ['        lodi,r0 $%02X' % s, '        wrte,r0 $FC', '        nop', '        nop', '        spsu',
             '        stra,r0 {P}_res+5', '        tpsu $80', '        spsl', '        stra,r0 {P}_res+6', '        lodi,r0 $00'],
            [0] + regs[1:] + [st['psl'] & 0x3F, s << 7, (st['psl'] & 0x3F) | ((0 if s else 2) << 6)])
    st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R()}
    regs = base_regs(st)
    add('flag output looped back to sense', st,
        ['        lodi,r0 $02', '        wrte,r0 $FC', '        ppsu $40', '        nop', '        nop', '        tpsu $80',
         '        spsl', '        stra,r0 {P}_res+5', '        cpsu $40', '        nop', '        nop', '        tpsu $80',
         '        spsl', '        stra,r0 {P}_res+6', '        lodi,r0 $00', '        wrte,r0 $FC', '        lodi,r0 $00'],
        [0] + regs[1:] + [st['psl'] & 0x3F, st['psl'] & 0x3F, (st['psl'] & 0x3F) | 0x80])
    # undefined opcodes: sgs2650 decodes 90 / 91 as LPSU / LPSL and B6 / B7 as TPSU / TPSL (MAME: 1-byte NOP)
    v = 0x45
    st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': v}
    regs = base_regs(st)
    add('undefined $90 (as LPSU)', st, ['        db $90', '        lodi,r0 $00', '        spsu', '        stra,r0 {P}_res+5',
                                        '        lodi,r0 $00', '        lpsu', '        lodi,r0 $00'],
        [0] + regs[1:] + [st['psl'] & 0x3F, v & 0x67], quirk='undefined opcode $90 acts as LPSU (MAME: NOP)')
    v = R() & ~0x10
    st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R(), 'r0': v}
    add('undefined $91 (as LPSL)', st, ['        db $91'], regs_of(st) + [v],
        quirk='undefined opcode $91 acts as LPSL (MAME: NOP)')
    for op, m in ((0xB6, 0x07), (0xB7, 0x0C)):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R()}
        regs, pi = base_regs(st), psl_in(st)
        tst = 0 if op == 0xB6 else pi
        add('undefined $%02X $%02X (as %s)' % (op, m, 'TPSU' if op == 0xB6 else 'TPSL'), st,
            ['        db $%02X, $%02X' % (op, m)], regs + [(pi & 0x3F) | ((0 if (tst & m) == m else 2) << 6)],
            quirk='undefined opcode $%02X acts as %s, 2 bytes (MAME: 1-byte NOP)' % (op, 'TPSU' if op == 0xB6 else 'TPSL'))
    add('register banks', {'psl': 0x00},
        ['        lodi,r1 $11', '        lodi,r2 $22', '        lodi,r3 $33', '        ppsl $10',
         '        lodi,r1 $44', '        lodi,r2 $55', '        lodi,r3 $66', '        lodi,r0 $77',
         '        cpsl $10', '        stra,r1 {P}_res+5', '        stra,r2 {P}_res+6', '        stra,r3 {P}_res+7',
         '        ppsl $10', '        stra,r1 {P}_res+8', '        stra,r2 {P}_res+9', '        stra,r3 {P}_res+10',
         '        cpsl $10'],
        [0x77, 0x11, 0x22, 0x33, 0x40, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66])

def branch_tests():
    g = 'BRANCH'
    ccn = ['eq', 'gt', 'lt', 'un']
    # every conditional branch twice in one test: condition met, then not met (order random); the path taken
    # is recorded in ACC (R1, or R2 when R1 is the register tested)
    grp = [g]
    def shots(fam, kind, form, fld, sub):
        acc = 2 if fld == 1 else 1
        st = {'psl': rpsl(rs=random.randrange(2)), 'r1': R(), 'r2': R(), 'r3': R()}
        regs = base_regs(st)
        body = ['        lodi,r%d $00' % acc]
        regs[acc] = 0
        ind = '*' if '*' in form else ''
        order = [True, False] if random.randrange(2) else [False, True]
        data = []
        psl = st['psl']
        for k, want in enumerate(order):
            if kind in ('cc', 'ccf'):
                cc = (fld if want else (fld + 1) % 3) if kind == 'cc' else ((fld + 1) % 3 if want else fld)
                if kind == 'cc' and fld == 3: cc = random.randrange(3)
                p0 = (rpsl(rs=(psl >> 4) & 1) & 0x3F) | (cc << 6)
                body += ['        lodi,r0 $%02X' % p0, '        lpsl']
                regs[0], psl = p0, p0
                tk = (fld == 3 or fld == cc) if kind == 'cc' else fld != cc
            else:
                if kind == 'reg': v = random.choice([1, 0x80, R() | 1]) if want else 0
                elif kind == 'inc': v = random.choice([0, 0x7F, 0x10]) if want else 0xFF
                else: v = random.choice([2, 0, 0x80]) if want else 1
                body.append('        lodi,r%d $%02X' % (fld, v))
                psl = (psl & 0x3F) | (sign(v) << 6)
                if kind == 'inc': v = (v + 1) & 0xFF
                if kind == 'dec': v = (v - 1) & 0xFF
                regs[fld] = v
                tk = v != 0
            tgt = '{L}s%d' % k if sub else '{L}t%d' % k
            body.append('        %s%s,%d %s' % (fam, form[0], fld, ('*{L}p%d' % k) if ind else tgt))
            data.append('{L}p%d:  dw %s' % (k, tgt))
            if sub:
                body += ['        bctr,un {L}t%d' % k, '{L}s%d:   iori,r%d $%02X' % (k, acc, 4 << k), '        retc,un']
                if tk:
                    regs[acc] |= 4 << k
                    psl = (psl & 0x3F) | (sign(regs[acc]) << 6)
            else:
                body.append('        iori,r%d $%02X' % (acc, 1 << k))
                if not tk:
                    regs[acc] |= 1 << k
                    psl = (psl & 0x3F) | (sign(regs[acc]) << 6)
            body.append('{L}t%d:' % k)
        name = ccn[fld] if kind in ('cc', 'ccf') else 'r%d' % fld
        add('%s%s,%s %s(taken + not taken)' % (fam, form[0], name, 'ind ' if ind else ''), st, body, regs + [psl],
            data=data, group=grp.pop() if grp else None)

    for fam, kind in (('bct', 'cc'), ('bcf', 'ccf'), ('brn', 'reg'), ('bir', 'inc'), ('bdr', 'dec')):
        for form in ('r', 'a', 'r*', 'a*'):
            for fld in range(4):
                if kind == 'ccf' and fld == 3: continue          # BCFR,3 / BCFA,3 are ZBRR / BXA
                shots(fam, kind, form, fld, False)
    for fam, kind in (('bst', 'cc'), ('bsf', 'ccf'), ('bsn', 'reg')):
        for form in ('r', 'a', 'r*', 'a*'):
            for fld in range(4):
                if kind == 'ccf' and fld == 3: continue
                shots(fam, kind, form, fld, True)
    for rete in (0, 1):
        for fld in range(4):
            for want in (True, False):
                psl = rpsl(rs=random.randrange(2))
                psl = (psl & 0x3F) | ((fld if want or fld == 3 else (fld + 1) % 3) << 6)
                st = {'psl': psl, 'r1': R(), 'r2': R(), 'r3': R()}
                regs = base_regs(st)
                tk = fld == 3 or fld == psl >> 6
                regs[0] = psl if tk else 0x77
                add('%s,%s%s' % ('rete' if rete else 'retc', ccn[fld], ' taken' if tk else ' not taken'), st,
                    ['        ppsu $20', '        lodi,r0 $%02X' % psl, '        lpsl', '        bstr,un {L}sub',
                     '        bctr,un {L}j', '{L}sub:  %s,%d' % ('rete' if rete else 'retc', fld), '        lodi,r0 $77',
                     '        retc,un', '{L}j:    stra,r0 {P}_mark', '        spsu', '        andi,r0 $20',
                     '        stra,r0 {P}_res+5', '        cpsu $20', '        loda,r0 {P}_mark'],
                    regs + [(psl & 0x3F) | (sign(regs[0]) << 6), 0 if (tk and rete) else 0x20])
    for fam in ('bxa', 'bsxa'):
        for ind in ('', '*'):
            for k in (0, 1, 2):
                psl = rpsl(rs=random.randrange(2))
                st = {'psl': psl, 'r1': R(), 'r2': R(), 'r3': 4 * k}
                regs = base_regs(st)
                regs[0] = 0x10 + k
                slots = []
                for i in range(3):
                    slots += ['        lodi,r0 $%02X' % (0x10 + i)]
                    slots += ['        bctr,un {L}j'] if fam == 'bxa' else ['        retc,un', '        nop']
                add('%s %stab,r3 r3=%d' % (fam, ind, 4 * k), st,
                    ['        %s %s,r3' % (fam, '*{L}ptr' if ind else '{L}tab'),
                     '        bctr,un {L}j' if fam == 'bsxa' else '        halt', '{L}tab:'] + slots + ['{L}j:'],
                    regs + [(psl & 0x3F) | (1 << 6)], data=['{L}ptr: dw {L}tab'])
    # ZBRR / ZBSR: stubs in page 0 at $0020 / $0028 and $1FF0 / $1FE8, pointers at $0012-$0019
    g = 'ZBRR ZBSR'
    for fam, tgt, v in (('zbrr', '$0020', 0xA1), ('zbsr', '$0028', 0xA2), ('zbrr', '$1FF0', 0xA3),
                        ('zbsr', '$1FE8', 0xA4), ('zbrr', '*$0012', 0xA1), ('zbsr', '*$0014', 0xA2),
                        ('zbrr', '*$0016', 0xA3), ('zbsr', '*$0018', 0xA4)):
        st = {'psl': rpsl(rs=0), 'r1': R(), 'r2': R(), 'r3': R()}
        regs = base_regs(st)
        regs[0] = v
        add('%s %s' % (fam, tgt), st,
            ['        lodi,r0 hi({L}j)', '        stra,r0 *{L}zr', '        lodi,r0 lo({L}j)', '        stra,r0 *{L}zr1',
             '        %s %s' % (fam, tgt), '{L}j:'],
            regs + [(st['psl'] & 0x3F) | (sign(v) << 6)], data=['{L}zr:  dw ZRET', '{L}zr1: dw ZRET+1'], group=g)
        g = None

def stack_tests():
    body = ['        lodi,r0 $00', '        lpsu', '        lodi,r1 $00', '        bsta,un {L}s1', '        bcta,un {L}j']
    for i in range(1, 8):
        body += ['{L}s%d:  addi,r1 $%02X' % (i, 1 << (i - 1)), '        bsta,un {L}s%d' % (i + 1),
                 '        stra,r1 {P}_res+%d' % (4 + i), '        retc,un']
    body += ['{L}s8:  addi,r1 $80', '        spsu', '        stra,r0 {P}_res+12', '        retc,un',
             '{L}j:    spsu', '        stra,r0 {P}_res+13', '        lodi,r0 $00', '        lodi,r2 $00', '        lodi,r3 $00']
    p = 0x00
    r1 = 0
    for i in range(8):
        r1, p = alu(4, r1, 1 << i, p)
    p = (p & 0x3F)                          # CC from lodi,r3 $00
    add('8-level call nesting', {'psl': 0x00}, body, [0x00, 0xFF, 0x00, 0x00, p] + [0xFF] * 7 + [0x00, 0x00],
        group='STACK')
    add('SP wrap 7 -> 0 -> 7', {'psl': 0x00},
        ['        lodi,r0 $07', '        lpsu', '        bstr,un {L}s', '        spsu', '        stra,r0 {P}_res+6',
         '        bctr,un {L}j', '{L}s:    spsu', '        stra,r0 {P}_res+5', '        retc,un',
         '{L}j:    lodi,r0 $00', '        lpsu', '        lodi,r1 $00', '        lodi,r2 $00', '        lodi,r3 $00'],
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07])

def io_tests():
    g = 'IO'
    for n in range(4):
        v = R()
        st = {'psl': 0x00, 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
        st['r%d' % n] = v
        regs = base_regs(st)
        m = (n + 1) & 3
        regs[m] = v ^ 0x5A
        add('wrte,r%d / rede,r%d port $%02X' % (n, m, 0x40 + n), st,
            ['        wrte,r%d $%02X' % (n, 0x40 + n), '        rede,r%d $%02X' % (m, 0x40 + n)],
            regs + [sign(regs[m]) << 6], group=g)
        g = None
    for wr, rd in (('wrtc', 'redc'), ('wrtd', 'redd')):
        for n in range(4):
            v = R()
            st = {'psl': 0x00, 'r1': R(), 'r2': R(), 'r3': R(), 'r0': R()}
            st['r%d' % n] = v
            regs = base_regs(st)
            m = (n + 2) & 3
            regs[m] = v ^ 0x5A
            add('%s,r%d / %s,r%d' % (wr, n, rd, m), st, ['        %s,r%d' % (wr, n), '        %s,r%d' % (rd, m)],
                regs + [sign(regs[m]) << 6])

def int_tests():
    tail = ['        lodi,r1 $00', '        lodi,r2 $00', '        lodi,r3 $00', '        lodi,r0 $00', '        lpsl']
    cnt = ['{L}cp:  dw ISRCNT', '{L}pp:  dw ISRPSU']
    g = 'INT HALT'
    for vec in ('$03', '$7E'):
        add('interrupt, vector %s' % vec, {'psl': 0x00},
            ['        lodi,r0 $00', '        stra,r0 *{L}cp', '        lpsu', '        lodi,r0 $02', '        wrte,r0 $FA',
             '        lodi,r0 %s' % vec, '        wrte,r0 $FD', '        lodi,r1 $00',
             '{L}w:    loda,r0 *{L}cp', '        birr,r1 {L}x', '        bcta,un {P}_fail', '{L}x:    bctr,eq {L}w',
             '        loda,r0 *{L}pp', '        andi,r0 $27', '        stra,r0 {P}_res+5', '        spsu',
             '        andi,r0 $27', '        stra,r0 {P}_res+6'] + tail,
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0x00], data=cnt, group=g)
        g = None
    add('interrupt held off by II until CPSU', {'psl': 0x00},
        ['        lodi,r0 $00', '        stra,r0 *{L}cp', '        lodi,r0 $20', '        lpsu', '        lodi,r0 $01',
         '        wrte,r0 $FA', '        lodi,r0 $03', '        wrte,r0 $FD', '        lodi,r1 $40',
         '{L}w:    bdrr,r1 {L}w', '        loda,r0 *{L}cp', '        stra,r0 {P}_res+5', '        cpsu $20', '        nop',
         '        nop', '        loda,r0 *{L}cp', '        stra,r0 {P}_res+6', '        lodi,r0 $00', '        lpsu'] + tail,
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01], data=cnt)
    add('HALT left by an interrupt', {'psl': 0x00},
        ['        lodi,r0 $00', '        stra,r0 *{L}cp', '        lpsu', '        lodi,r0 $10', '        wrte,r0 $FA',
         '        lodi,r1 $01', '        lodi,r0 $03', '        wrte,r0 $FD', '        lodi,r0 $00', '        halt',
         '        iorz r1', '        stra,r0 {P}_res+5', '        loda,r0 *{L}cp', '        stra,r0 {P}_res+6'] + tail,
        [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01], data=cnt,
        quirk='HALT left by an interrupt returns to HALT+2: the IORZ after HALT is skipped (manual / MAME: HALT+1)')

def page_tests():
    add('call into page 0, indirect data in page 0', {'psl': 0x00, 'r1': 0x00, 'r2': 0x00, 'r3': 0x00},
        ['        bsta,un FARSUB', '        lodr,r1 *{L}fp', '        lodi,r2 $01', '        loda,r0 *{L}fp,r2',
         '        lodi,r3 $00'],
        [0x01, 0x3A, 0x01, 0x00, 0x00], data=['{L}fp:  dw FARDATA'], group='PAGES')
    add('subroutine in page 0 stores through a pointer', {'psl': 0x00, 'r1': 0x00, 'r2': 0x00, 'r3': 0x00},
        ['        lodi,r0 $E7', '        bsta,un FARSTR', '        loda,r0 *{L}bp', '        lodi,r1 $00'],
        [0xE7, 0x00, 0x00, 0x00, 0x00], data=['{L}bp:  dw FARBOX'])

def idc_tests():
    # IDC with the carry folded in: sgs2650 compares nibbles of result and operand, the manual takes the
    # carry / borrow out of bit 3
    for opn, op3, psl, a, b in (('add', 4, 0x09, 0x05, 0x0F), ('sub', 5, 0x08, 0x05, 0x0F)):
        st = {'psl': psl, 'r1': a, 'r2': R(), 'r3': R()}
        regs = base_regs(st)
        regs[1], p, q = alu_q(op3, a, b, psl_in(st))
        add('%si,r1 with carry a=%02X b=%02X psl=%02X' % (opn, a, b, psl), st, ['        %si,r1 $%02X' % (opn, b)],
            regs + [p], quirk=q, group='IDC' if op3 == 4 else None)

# ------------------------------------------------------------------------------------------------ layout
HEAD = '''; Signetics 2650 exerciser - generated by gen_exerciser.py, do not edit
RESULT  equ $7FF0               ; P / F
ZRET    equ $0010               ; way back from the ZBRR stubs
ISRCNT  equ $001A
ISRPSU  equ $001B
        org $0000
        bcta,un main
        bcta,un isr             ; vector $03
        org $0010
        dw 0                    ; ZRET
        dw $0020                ; $0012: ZBRR * pointer
        dw $0028                ; $0014: ZBSR * pointer
        dw $1FF0                ; $0016
        dw $1FE8                ; $0018
        db 0, 0                 ; ISRCNT, ISRPSU
        org $0020
        lodi,r0 $A1
        bcta,un *ZRET
        org $0028
        lodi,r0 $A2
        retc,un
        org $0030
isr:    stra,r0 isrr0
        spsu
        stra,r0 ISRPSU
        loda,r0 ISRCNT
        addi,r0 1
        stra,r0 ISRCNT
        loda,r0 isrr0
        rete,un
isrr0:  db 0
FARSUB: lodi,r0 $5C
        retc,un
FARSTR: stra,r0 *farbp
        retc,un
farbp:  dw FARBOX
FARBOX: db 0
FARDATA: db $3A, $01
main:   lodi,r0 $00
        lpsu
'''
P0TAIL = '''        org $1FD0
isr2:   bcta,un isr             ; vector $7E: $1FFE
        org $1FE8
        lodi,r0 $A4
        retc,un
        org $1FF0
        lodi,r0 $A3
        bcta,un *ZRET
        org $1FFE
        bctr,un isr2
'''

def routines(p):
    x = 'P%d' % p
    return ['; ---- page %d support' % p,
            "%s_fail: lodi,r0 'F'" % x, '        stra,r0 *%s_resp' % x, '        wrte,r0 $FF', '        halt',
            '%s_res:  ds 16' % x, '%s_resp: dw RESULT' % x, '%s_mark: db 0' % x]

def say(s):
    o = []
    for ch in s: o += ['        lodi,r0 %d' % ord(ch), '        wrte,r0 $FE']
    return o

def layout():
    a = Asm()
    lim = {0: 0x1FC0, 1: 0x3FE0, 2: 0x5FE0, 3: 0x7FC0}
    out = HEAD.split('\n') + say('2650 exerciser\r\n')
    pc = 0x1000 + a.size('\n'.join(out))       # HEAD sets its own origins
    rsz = a.size('\n'.join(routines(0))) + 8
    page, n = 0, 0
    for t in T:
        n += 1
        lines = t.render(n, 'P%d' % page)
        sz = a.size('\n'.join(lines))
        if pc + sz + rsz > lim[page]:
            out += ['        bcta,un page%d' % (page + 1)] + routines(page)
            if page == 0: out += P0TAIL.split('\n')
            page += 1
            if page > 3: raise SystemExit('exerciser does not fit')
            out += ['        org $%04X' % (page * 0x2000), 'page%d:' % page]
            pc = page * 0x2000
            lines = t.render(n, 'P%d' % page)
        out += lines
        pc += sz
        t.page = page
    out += say('\r\nPASS\r\n') + ["        lodi,r0 'P'", '        stra,r0 *P%d_resp' % page, '        wrte,r0 $FF',
                                  '        halt'] + routines(page)
    if page == 0: out += P0TAIL.split('\n')
    return out, page

if __name__ == '__main__':
    alu_tests(); str_tests(); rot_dar_tmi_tests(); psw_tests(); io_tests(); branch_tests(); stack_tests()
    page_tests(); int_tests(); idc_tests()
    out, last = layout()
    fn = sys.argv[1] if len(sys.argv) > 1 else 'exerciser.asm'
    open(fn, 'w').write('\n'.join(out) + '\n')
    q = [('T%d %s: %s' % (i + 1, t.title, t.quirk)) for i, t in enumerate(T) if t.quirk]
    open(os.path.join(os.path.dirname(os.path.abspath(fn)), 'exerciser_quirks.txt'), 'w').write(
        'Exerciser tests whose expected (sgs2650) result differs from the Signetics manual (%d):\n' % len(q) +
        '\n'.join(q) + '\n')
    pages = {}
    for t in T: pages[t.page] = pages.get(t.page, 0) + 1
    print('%s: %d tests (pages %s), %d on sgs2650-specific behaviour' % (fn, len(T), pages, len(q)))

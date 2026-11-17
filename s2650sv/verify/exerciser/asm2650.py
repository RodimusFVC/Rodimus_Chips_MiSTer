#!/usr/bin/env python3
"""asm2650: minimal two-pass Signetics 2650 assembler (verification only).

Syntax (Signetics style):
  label:  MNEM[,r|,cc]  operand   ; comment
  name    EQU   expr
          ORG   expr
          DB    expr|"text", ...       (also DATA)
          DW    expr, ...              (15-bit address, big endian; also ACON)
          DS    count
  registers r0-r3, conditions eq/z gt/p lt/n un (or 0-3)
  immediate:       LODI,r1 $12      (a leading # is accepted)
  relative:        LODR,r1 label    BCTR,eq *label (indirect)
  absolute:        LODA,r1 label    LODA,r0 *label,r2  LODA,r0 label,r3,+  (indexed: operand R0,
                   index in the register field; auto + / -)
  branch absolute: BCTA,un label    BXA *table,r3
  zero page:       ZBRR $0010       ZBSR *$1FC0
Numbers: $hex 0xhex %bin decimal 'c'; operators + - * // & | ^ << >> ~ ( ), lo(x) hi(x),
$ alone = current address.
Usage: asm2650.py in.asm out.bin [out.lst]
"""
import re, sys

REG = {'r0': 0, 'r1': 1, 'r2': 2, 'r3': 3}
CC = {'eq': 0, 'z': 0, 'gt': 1, 'p': 1, 'lt': 2, 'n': 2, 'un': 3}

# mnemonic -> (base opcode, kind)
#   z: register zero (1 byte)       e: implicit (1 byte)       i: immediate      ei: immediate, no register
#   r: relative                     a: absolute (non branch)   br: branch relative (cc/reg)  ba: branch absolute
#   zr: zero page relative (ZBRR/ZBSR, no field)              bx: BXA / BSXA (index r3)     n1: 1 byte no field
OPS = {}
def _alu(name, base):
    OPS[name + 'z'] = (base + 0x0, 'z'); OPS[name + 'i'] = (base + 0x4, 'i')
    OPS[name + 'r'] = (base + 0x8, 'r'); OPS[name + 'a'] = (base + 0xC, 'a')
for n, b in (('lod', 0x00), ('eor', 0x20), ('and', 0x40), ('ior', 0x60), ('add', 0x80), ('sub', 0xA0),
             ('com', 0xE0)):
    _alu(n, b)
OPS.update({
    'strz': (0xC0, 'z'), 'strr': (0xC8, 'r'), 'stra': (0xCC, 'a'),
    'spsu': (0x12, 'n1'), 'spsl': (0x13, 'n1'), 'lpsu': (0x92, 'n1'), 'lpsl': (0x93, 'n1'),
    'retc': (0x14, 'z'), 'rete': (0x34, 'z'),
    'bctr': (0x18, 'br'), 'bcta': (0x1C, 'ba'), 'bcfr': (0x98, 'br'), 'bcfa': (0x9C, 'ba'),
    'bstr': (0x38, 'br'), 'bsta': (0x3C, 'ba'), 'bsfr': (0xB8, 'br'), 'bsfa': (0xBC, 'ba'),
    'brnr': (0x58, 'br'), 'brna': (0x5C, 'ba'), 'bsnr': (0x78, 'br'), 'bsna': (0x7C, 'ba'),
    'birr': (0xD8, 'br'), 'bira': (0xDC, 'ba'), 'bdrr': (0xF8, 'br'), 'bdra': (0xFC, 'ba'),
    'zbrr': (0x9B, 'zr'), 'zbsr': (0xBB, 'zr'), 'bxa': (0x9F, 'bx'), 'bsxa': (0xBF, 'bx'),
    'halt': (0x40, 'n1'), 'nop': (0xC0, 'n1'),
    'rrr': (0x50, 'z'), 'rrl': (0xD0, 'z'), 'dar': (0x94, 'z'),
    'redc': (0x30, 'z'), 'redd': (0x70, 'z'), 'wrtc': (0xB0, 'z'), 'wrtd': (0xF0, 'z'),
    'rede': (0x54, 'i'), 'wrte': (0xD4, 'i'), 'tmi': (0xF4, 'i'),
    'cpsu': (0x74, 'ei'), 'cpsl': (0x75, 'ei'), 'ppsu': (0x76, 'ei'), 'ppsl': (0x77, 'ei'),
    'tpsu': (0xB4, 'ei'), 'tpsl': (0xB5, 'ei'),
})


class AsmError(Exception):
    pass


def split_args(s):
    out, depth, cur, q = [], 0, '', None
    for ch in s:
        if q:
            cur += ch
            if ch == q: q = None
            continue
        if ch in '"\'':
            q = ch; cur += ch; continue
        if ch == '(': depth += 1
        if ch == ')': depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip(): out.append(cur.strip())
    return out


class Asm:
    def __init__(self):
        self.sym = {}
        self.mem = {}
        self.lst = []

    def ev(self, e, pc, final):
        e = e.strip()
        if e.startswith('#'): e = e[1:]
        def num(m):
            t = m.group(0)
            if t.startswith('$') and len(t) > 1: return str(int(t[1:], 16))
            if t.lower().startswith('0x'): return str(int(t, 16))
            if t.startswith('%'): return str(int(t[1:], 2))
            return t
        def chr_(m): return str(ord(m.group(1)))
        x = re.sub(r"'(.)'", chr_, e)
        x = re.sub(r"\$[0-9A-Fa-f]+|0[xX][0-9A-Fa-f]+|%[01]+", num, x)
        x = re.sub(r"(?<![\w)])\$(?![\w])", str(pc), x)
        def ident(m):
            n = m.group(0)
            if n.lower() in ('lo', 'hi'): return n.lower()
            if n.isdigit(): return n
            k = n.lower()
            if k in self.sym: return str(self.sym[k])
            if final: raise AsmError("undefined symbol %s" % n)
            return '0'
        x = re.sub(r"[A-Za-z_][A-Za-z_0-9]*|\d+", ident, x)
        try:
            return int(eval(x, {'__builtins__': {}}, {'lo': lambda v: v & 0xFF, 'hi': lambda v: (v >> 8) & 0xFF}))
        except Exception as ex:
            raise AsmError("bad expression '%s' (%s)" % (e, ex))

    def assemble(self, text):
        lines = text.split('\n')
        for final in (False, True):
            pc = 0
            self.mem = {}
            self.lst = []
            for ln, raw in enumerate(lines, 1):
                try:
                    pc = self.line(raw, pc, final)
                except AsmError as ex:
                    raise AsmError("line %d: %s\n  %s" % (ln, ex, raw))
        return self.mem

    def size(self, text):
        """bytes produced by a fragment (undefined symbols read as 0)"""
        pc0 = pc = 0x1000
        for raw in text.split('\n'):
            pc = self.line(raw, pc, False)
        return pc - pc0

    def emit(self, pc, bs, raw, final):
        for i, b in enumerate(bs):
            a = (pc + i) & 0x7FFF
            if final and a in self.mem: raise AsmError("overlapping code at %04X" % a)
            self.mem[a] = b & 0xFF
        if final: self.lst.append("%04X  %-12s %s" % (pc, ' '.join('%02X' % (b & 0xFF) for b in bs[:4]), raw))
        return pc + len(bs)

    def line(self, raw, pc, final):
        s = raw.split(';', 1)[0].rstrip()
        if not s.strip():
            return pc
        m = re.match(r"^\s*([A-Za-z_][\w]*)\s*:\s*(.*)$", s)
        if m:
            self.define(m.group(1), pc, final)
            s = m.group(2)
            if not s.strip():
                if final: self.lst.append("%04X               %s" % (pc, raw))
                return pc
        m = re.match(r"^\s*([A-Za-z_][\w]*)\s+(equ|EQU|Equ)\s+(.*)$", s)
        if m:
            self.define(m.group(1), self.ev(m.group(3), pc, final), final)
            return pc
        m = re.match(r"^\s*([A-Za-z]+)(?:,(\w+))?\s*(.*)$", s)
        if not m: raise AsmError("syntax")
        mn, fld, opnd = m.group(1).lower(), m.group(2), m.group(3).strip()
        if mn == 'org':
            return self.ev(opnd, pc, final)
        if mn in ('db', 'data'):
            bs = []
            for a in split_args(opnd):
                if a.startswith('"'): bs += [ord(c) for c in a[1:-1]]
                else: bs.append(self.ev(a, pc, final))
            return self.emit(pc, bs, raw, final)
        if mn in ('dw', 'acon'):
            bs = []
            for a in split_args(opnd):
                v = self.ev(a, pc, final); bs += [(v >> 8) & 0xFF, v & 0xFF]
            return self.emit(pc, bs, raw, final)
        if mn == 'ds':
            return pc + self.ev(opnd, pc, final)
        if mn == 'end':
            return pc
        if mn not in OPS: raise AsmError("unknown mnemonic %s" % mn)
        base, kind = OPS[mn]
        f = 0
        if kind == 'z' and fld is None and opnd.lower() in REG:   # LODZ R1 style
            fld, opnd = opnd, ''
        if kind in ('z', 'i', 'r', 'a', 'br', 'ba'):
            if fld is None: raise AsmError("%s needs a register / condition field" % mn)
            k = fld.lower()
            if k in REG: f = REG[k]
            elif k in CC: f = CC[k]
            elif k.isdigit() and int(k) < 4: f = int(k)
            else: raise AsmError("bad field %s" % fld)
        elif fld is not None:
            raise AsmError("%s takes no field" % mn)
        op = base + f
        if kind in ('z', 'n1'):
            return self.emit(pc, [op], raw, final)
        if kind in ('i', 'ei'):
            v = self.ev(opnd, pc, final)
            if final and not -128 <= v <= 255: raise AsmError("immediate out of range")
            return self.emit(pc, [op, v & 0xFF], raw, final)
        ind = opnd.startswith('*')
        if ind: opnd = opnd[1:].strip()
        args = split_args(opnd)
        if kind in ('r', 'br'):
            t = self.ev(args[0], pc, final)
            d = t - ((pc + 2) & 0x7FFF)
            if final and not -64 <= d <= 63: raise AsmError("relative target out of range (%d)" % d)
            return self.emit(pc, [op, (0x80 if ind else 0) | (d & 0x7F)], raw, final)
        if kind == 'zr':
            t = self.ev(args[0], pc, final) & 0x7FFF
            if final and not (t <= 0x3F or 0x1FC0 <= t <= 0x1FFF): raise AsmError("zero page target out of range")
            return self.emit(pc, [op, (0x80 if ind else 0) | (t & 0x7F)], raw, final)
        if kind in ('ba', 'bx'):
            t = self.ev(args[0], pc, final)
            if kind == 'bx' and (len(args) != 2 or args[1].lower() != 'r3'): raise AsmError("BXA / BSXA index is r3")
            return self.emit(pc, [op, (0x80 if ind else 0) | ((t >> 8) & 0x7F), t & 0xFF], raw, final)
        if kind == 'a':
            t = self.ev(args[0], pc, final)
            if final and (t & 0x6000) != (pc & 0x6000) and not ind:
                raise AsmError("absolute operand %04X outside the current page" % t)
            mode = 0
            if len(args) >= 2:
                x = args[1].lower()
                if x not in REG: raise AsmError("bad index register")
                if f not in (0, REG[x]): raise AsmError("indexed: the operand register is R0")
                f = REG[x]; op = base + f
                mode = 3
                if len(args) == 3:
                    mode = {'+': 1, '-': 2}.get(args[2])
                    if mode is None: raise AsmError("auto index must be + or -")
            return self.emit(pc, [op, (0x80 if ind else 0) | (mode << 5) | ((t >> 8) & 0x1F), t & 0xFF], raw, final)
        raise AsmError("unhandled")

    def define(self, name, v, final):
        self.sym[name.lower()] = v


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    a = Asm()
    try:
        mem = a.assemble(open(sys.argv[1]).read())
    except AsmError as ex:
        print("error:", ex); sys.exit(1)
    top = max(mem) + 1 if mem else 0
    img = bytearray(top)
    for k, v in mem.items(): img[k] = v
    open(sys.argv[2], 'wb').write(img)
    if len(sys.argv) > 3:
        open(sys.argv[3], 'w').write('\n'.join(a.lst) + '\n')
    print("%s: %d bytes used, image %d bytes" % (sys.argv[2], len(mem), top))


if __name__ == '__main__':
    main()

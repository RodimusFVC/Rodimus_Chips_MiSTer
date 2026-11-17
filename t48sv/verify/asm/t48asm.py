#!/usr/bin/env python3
"""Minimal MCS-48 / UPI-41 / MCS-21/22 assembler for the subset of ASL
(Alfred Arnold's Macroassembler AS) syntax used by the T48 verification cells.

  t48asm.py <src.asm> -I <incdir> -o <image.bin> [--ihex <out.hex> --range lo-hi [-a]]

Supported: labels (with or without ':'), EQU, ORG, ALIGN, DB, CPU, INCLUDE,
MACRO/ENDM (labels local to each expansion, as in AS), $ (location counter),
numbers 0FFH / 101B / decimal, operators ~ unary-minus * / # (mod) + - << >> & | !.
"""
import argparse, os, re, sys

CPU_FAMILY = {'8048': '48', '8049': '48', '8050': '48', '8035': '48', '8039': '48', '8040': '48',
              '8041': '41', '8042': '41', '8741': '41', '8742': '41',
              '8021': '21', '8022': '22'}


class AsmError(Exception):
    pass


# ----------------------------------------------------------------------------
# expressions
# ----------------------------------------------------------------------------
TOK = re.compile(r'\s*(?:(\$)|([0-9][0-9A-Fa-f]*[HhBbOoQq]?)|([A-Za-z_.][A-Za-z0-9_.]*)|(<<|>>|[-+*/#&|!~()]))')


def parse_num(s):
    u = s.upper()
    if u.endswith('H'):
        return int(u[:-1], 16)
    if u.endswith('B') and re.fullmatch(r'[01]+B', u):
        return int(u[:-1], 2)
    if u[-1] in 'OQ':
        return int(u[:-1], 8)
    return int(u, 10)


def evaluate(expr, syms, pc, strict):
    toks = []
    pos = 0
    expr = expr.strip()
    while pos < len(expr):
        m = TOK.match(expr, pos)
        if not m or m.end() == pos:
            raise AsmError('bad expression: %r' % expr)
        pos = m.end()
        if m.group(1):
            toks.append(('n', pc))
        elif m.group(2):
            toks.append(('n', parse_num(m.group(2))))
        elif m.group(3):
            name = m.group(3).lower()
            if name in syms:
                toks.append(('n', syms[name]))
            elif strict:
                raise AsmError('undefined symbol %s' % name)
            else:
                toks.append(('n', 0))
        else:
            toks.append(('o', m.group(4)))
    toks.append(('e', None))
    i = [0]

    def peek():
        return toks[i[0]]

    def take():
        t = toks[i[0]]
        i[0] += 1
        return t

    def unary():
        t = take()
        if t == ('o', '~'):
            return ~unary()
        if t == ('o', '-'):
            return -unary()
        if t == ('o', '+'):
            return unary()
        if t == ('o', '('):
            v = binop(0)
            if take() != ('o', ')'):
                raise AsmError('missing ) in %r' % expr)
            return v
        if t[0] == 'n':
            return t[1]
        raise AsmError('bad expression: %r' % expr)

    # C-like precedence (agrees with AS for every expression in the T48 cells)
    prec = {'|': 1, '!': 2, '&': 3, '<<': 4, '>>': 4, '+': 5, '-': 5, '*': 6, '/': 6, '#': 6}

    def binop(minp):
        v = unary()
        while True:
            t = peek()
            if t[0] != 'o' or t[1] not in prec or prec[t[1]] < minp:
                return v
            op = take()[1]
            r = binop(prec[op] + 1)
            v = {'|': lambda a, b: a | b, '!': lambda a, b: a ^ b, '&': lambda a, b: a & b,
                 '<<': lambda a, b: a << b, '>>': lambda a, b: a >> b, '+': lambda a, b: a + b,
                 '-': lambda a, b: a - b, '*': lambda a, b: a * b,
                 '/': lambda a, b: int(a / b) if b else 0, '#': lambda a, b: a % b if b else 0}[op](v, r)

    v = binop(0)
    if peek()[0] != 'e':
        raise AsmError('trailing garbage in %r' % expr)
    return v


# ----------------------------------------------------------------------------
# instruction encoding
# ----------------------------------------------------------------------------
def reg(op):
    m = re.fullmatch(r'R([0-7])', op, re.I)
    return int(m.group(1)) if m else None


def ind(op):
    m = re.fullmatch(r'@R([01])', op, re.I)
    return int(m.group(1)) if m else None


def imm(op):
    return op[1:] if op.startswith('#') else None


def port(op, ports):
    m = re.fullmatch(r'P([0-7])', op, re.I)
    if m and int(m.group(1)) in ports:
        return int(m.group(1))
    return None


def encode(mn, ops, fam, ev, pc):
    """returns list of bytes (callables evaluated in pass 2 via ev)"""
    U = [o.upper().replace(' ', '') for o in ops]
    n = len(U)
    is48, is41, is2x = fam == '48', fam == '41', fam in ('21', '22')

    def alu(base_r, base_i, op_imm):
        if n == 2 and U[0] == 'A':
            if reg(U[1]) is not None:
                return [base_r + reg(U[1])]
            if ind(U[1]) is not None and base_i is not None:
                return [base_i + ind(U[1])]
            if imm(ops[1]) is not None and op_imm is not None:
                return [op_imm, ev(imm(ops[1].strip())) & 0xFF]
        return None

    def jump8(opc, target):
        t = ev(target)
        return [opc, t & 0xFF]

    if mn == 'ADD':
        r = alu(0x68, 0x60, 0x03)
    elif mn == 'ADDC':
        r = alu(0x78, 0x70, 0x13)
    elif mn in ('ANL', 'ORL'):
        r = alu(0x58, 0x50, 0x53) if mn == 'ANL' else alu(0x48, 0x40, 0x43)
        if r is None and n == 2 and imm(ops[1].strip()) is not None:
            base = 0x98 if mn == 'ANL' else 0x88
            if U[0] == 'BUS' and is48:
                r = [base, ev(imm(ops[1].strip())) & 0xFF]
            elif port(U[0], (1, 2)) is not None and not is2x:
                r = [base + port(U[0], (1, 2)), ev(imm(ops[1].strip())) & 0xFF]
    elif mn == 'XRL':
        r = alu(0xD8, 0xD0, 0xD3)
    elif mn in ('ANLD', 'ORLD'):
        r = [(0x9C if mn == 'ANLD' else 0x8C) + port(U[0], (4, 5, 6, 7)) - 4] if n == 2 and U[1] == 'A' and port(U[0], (4, 5, 6, 7)) is not None else None
    elif mn in ('CALL', 'JMP'):
        full = ev(ops[0])
        t = full & 0x7FF
        r = [(0x14 if mn == 'CALL' else 0x04) | ((t >> 3) & 0xE0), t & 0xFF]
        # AS (code48.c) prefixes SEL MB0/MB1 when the target is in the other 2K bank
        if is48 and ((full >> 11) & 1) != ((pc >> 11) & 1):
            r = [0xF5 if (full >> 11) & 1 else 0xE5] + r
    elif mn in ('CLR', 'CPL'):
        tab = {'CLR': {'A': 0x27, 'C': 0x97, 'F0': 0x85, 'F1': 0xA5},
               'CPL': {'A': 0x37, 'C': 0xA7, 'F0': 0x95, 'F1': 0xB5}}[mn]
        r = [tab[U[0]]] if n == 1 and U[0] in tab else None
    elif mn == 'DA':
        r = [0x57] if U == ['A'] else None
    elif mn == 'DEC':
        r = [0x07] if U == ['A'] else ([0xC8 + reg(U[0])] if n == 1 and reg(U[0]) is not None else None)
    elif mn in ('DIS', 'EN'):
        tab = {'I': 0x05, 'TCNTI': 0x25}
        if is41:
            tab.update({'DMA': 0xE5, 'FLAGS': 0xF5})
        r = [tab[U[0]] + (0x10 if mn == 'DIS' and U[0] in ('I', 'TCNTI') else 0)] if n == 1 and U[0] in tab else None
        if mn == 'DIS' and U[0] in ('DMA', 'FLAGS'):
            r = None
    elif mn == 'DJNZ':
        r = jump8(0xE8 + reg(U[0]), ops[1]) if n == 2 and reg(U[0]) is not None else None
    elif mn == 'ENT0':
        r = [0x75] if U == ['CLK'] else None
    elif mn == 'IN':
        if n == 2 and U[0] == 'A':
            if U[1] == 'DBB' and is41:
                r = [0x22]
            elif U[1] == 'P0' and is2x:
                r = [0x08]
            elif port(U[1], (1, 2)) is not None:
                r = [0x08 + port(U[1], (1, 2))]
            else:
                r = None
        else:
            r = None
    elif mn == 'INS':
        r = [0x08] if U == ['A', 'BUS'] else None
    elif mn == 'INC':
        if U == ['A']:
            r = [0x17]
        elif n == 1 and reg(U[0]) is not None:
            r = [0x18 + reg(U[0])]
        elif n == 1 and ind(U[0]) is not None:
            r = [0x10 + ind(U[0])]
        else:
            r = None
    elif re.fullmatch(r'JB[0-7]', mn):
        r = jump8(0x12 | (int(mn[2]) << 5), ops[0])
    elif mn in ('JC', 'JNC', 'JZ', 'JNZ', 'JT0', 'JNT0', 'JT1', 'JNT1', 'JF0', 'JF1', 'JTF', 'JNI',
                'JNIBF', 'JOBF'):
        r = jump8({'JC': 0xF6, 'JNC': 0xE6, 'JZ': 0xC6, 'JNZ': 0x96, 'JT0': 0x36, 'JNT0': 0x26,
                   'JT1': 0x56, 'JNT1': 0x46, 'JF0': 0xB6, 'JF1': 0x76, 'JTF': 0x16, 'JNI': 0x86,
                   'JNIBF': 0xD6, 'JOBF': 0x86}[mn], ops[0])
    elif mn == 'JMPP':
        r = [0xB3] if U == ['@A'] else None
    elif mn == 'MOV':
        r = None
        if n == 2:
            d, s = U
            if d == 'A':
                if imm(ops[1].strip()) is not None:
                    r = [0x23, ev(imm(ops[1].strip())) & 0xFF]
                elif reg(s) is not None:
                    r = [0xF8 + reg(s)]
                elif ind(s) is not None:
                    r = [0xF0 + ind(s)]
                elif s == 'PSW':
                    r = [0xC7]
                elif s == 'T':
                    r = [0x42]
            elif reg(d) is not None:
                if s == 'A':
                    r = [0xA8 + reg(d)]
                elif imm(ops[1].strip()) is not None:
                    r = [0xB8 + reg(d), ev(imm(ops[1].strip())) & 0xFF]
            elif ind(d) is not None:
                if s == 'A':
                    r = [0xA0 + ind(d)]
                elif imm(ops[1].strip()) is not None:
                    r = [0xB0 + ind(d), ev(imm(ops[1].strip())) & 0xFF]
            elif d == 'PSW' and s == 'A':
                r = [0xD7]
            elif d == 'T' and s == 'A':
                r = [0x62]
            elif d == 'STS' and s == 'A' and is41:
                r = [0x90]
    elif mn == 'MOVD':
        if n == 2 and U[0] == 'A' and port(U[1], (4, 5, 6, 7)) is not None:
            r = [0x0C + port(U[1], (4, 5, 6, 7)) - 4]
        elif n == 2 and U[1] == 'A' and port(U[0], (4, 5, 6, 7)) is not None:
            r = [0x3C + port(U[0], (4, 5, 6, 7)) - 4]
        else:
            r = None
    elif mn in ('MOVP', 'MOVP3'):
        r = [0xA3 if mn == 'MOVP' else 0xE3] if U == ['A', '@A'] else None
    elif mn == 'MOVX':
        if n == 2 and U[0] == 'A' and ind(U[1]) is not None:
            r = [0x80 + ind(U[1])]
        elif n == 2 and U[1] == 'A' and ind(U[0]) is not None:
            r = [0x90 + ind(U[0])]
        else:
            r = None
    elif mn == 'NOP':
        r = [0x00]
    elif mn == 'OUTL':
        if n == 2 and U[1] == 'A':
            if U[0] == 'BUS' and is48:
                r = [0x02]
            elif U[0] == 'P0' and is2x:
                r = [0x90]
            elif port(U[0], (1, 2)) is not None:
                r = [0x38 + port(U[0], (1, 2))]
            else:
                r = None
        else:
            r = None
    elif mn == 'OUT':
        r = [0x02] if U == ['DBB', 'A'] and is41 else None
    elif mn == 'RAD':
        r = [0x80] if fam == '22' else None
    elif mn == 'RET':
        r = [0x83]
    elif mn in ('RETR', 'RETI'):
        r = [0x93]
    elif mn in ('RL', 'RLC', 'RR', 'RRC'):
        r = [{'RL': 0xE7, 'RLC': 0xF7, 'RR': 0x77, 'RRC': 0x67}[mn]] if U == ['A'] else None
    elif mn == 'SEL':
        tab = {'RB0': 0xC5, 'RB1': 0xD5}
        if is48:
            tab.update({'MB0': 0xE5, 'MB1': 0xF5})
        if fam == '22':
            tab.update({'AN0': 0x95, 'AN1': 0x85})
        r = [tab[U[0]]] if n == 1 and U[0] in tab else None
    elif mn == 'STOP':
        r = [0x65] if U == ['TCNT'] else None
    elif mn == 'STRT':
        r = [{'CNT': 0x45, 'T': 0x55}[U[0]]] if n == 1 and U[0] in ('CNT', 'T') else None
    elif mn == 'SWAP':
        r = [0x47] if U == ['A'] else None
    elif mn == 'XCH':
        if n == 2 and U[0] == 'A' and reg(U[1]) is not None:
            r = [0x28 + reg(U[1])]
        elif n == 2 and U[0] == 'A' and ind(U[1]) is not None:
            r = [0x20 + ind(U[1])]
        else:
            r = None
    elif mn == 'XCHD':
        r = [0x30 + ind(U[1])] if n == 2 and U[0] == 'A' and ind(U[1]) is not None else None
    else:
        return None
    if r is None:
        raise AsmError('illegal operands for %s on %s: %s' % (mn, fam, ', '.join(ops)))
    return r


# ----------------------------------------------------------------------------
# assembler
# ----------------------------------------------------------------------------
def split_ops(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
            continue
        depth += ch == '('
        depth -= ch == ')'
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def strip_comment(l):
    out, q = '', False
    for ch in l:
        if ch == '"':
            q = not q
        if ch == ';' and not q:
            break
        out += ch
    return out.rstrip()


DIRECTIVES = {'CPU', 'INCLUDE', 'ORG', 'EQU', 'DB', 'ALIGN', 'MACRO', 'ENDM', 'END'}


class Assembler:
    def __init__(self, incdirs):
        self.incdirs = incdirs

    def read(self, path):
        for d in [os.path.dirname(path)] + self.incdirs + ['']:
            p = os.path.join(d, path) if not os.path.isabs(path) else path
            if os.path.exists(p):
                return open(p).read().splitlines()
        raise AsmError('cannot find %s' % path)

    def expand(self, lines, macros, depth=0):
        """yield (label, mnemonic, operand string, macro-scope id)"""
        it = iter(lines)
        for raw in it:
            l = strip_comment(raw)
            if not l.strip():
                continue
            label = None
            m = re.match(r'^([A-Za-z_.][A-Za-z0-9_.]*):?(?=\s|$)', l)
            m2 = re.match(r'^\s*([A-Za-z_.][A-Za-z0-9_.]*):', l)
            if m and not l[0].isspace():
                label = m.group(1)
                rest = l[m.end():]
            elif m2:
                label = m2.group(1)
                rest = l[m2.end():]
            else:
                rest = l
            rest = rest.strip()
            parts = rest.split(None, 1)
            mn = parts[0].upper() if parts else ''
            args = parts[1] if len(parts) > 1 else ''
            if mn == 'MACRO':
                params = [p.strip().lower() for p in split_ops(args)]
                body = []
                for b in it:
                    if strip_comment(b).strip().upper() == 'ENDM':
                        break
                    body.append(b)
                macros[label.lower()] = (params, body)
                continue
            if mn == 'INCLUDE':
                yield from self.expand(self.read(args.strip().strip('"')), macros, depth)
                continue
            if mn.lower() in macros:
                params, body = macros[mn.lower()]
                vals = split_ops(args)
                self.scope += 1
                sc = self.scope
                sub = []
                for b in body:
                    for p, v in zip(params, vals):
                        b = re.sub(r'\b%s\b' % re.escape(p), v, b, flags=re.I)
                    sub.append(b)
                if label:
                    yield (label, '', '', None)
                for item in self.expand(sub, macros, depth + 1):
                    yield (item[0], item[1], item[2], item[3] if item[3] is not None else sc)
                continue
            yield (label, mn, args, None)

    def assemble(self, path):
        self.scope = 0
        items = list(self.expand(self.read(path), {}))
        syms = {}
        image = {}
        fam = '48'

        def sym_key(label, sc):
            return ('%s@%d' % (label.lower(), sc)) if sc is not None else label.lower()

        prev = None
        passes = [1] * 10 + [2]
        for pas in passes:
            if pas == 1 and prev == syms:
                continue
            prev = dict(syms)
            pc = 0
            fam = '48'
            for label, mn, args, sc in items:
                look = dict(syms)
                if sc is not None:   # labels local to a macro expansion shadow globals
                    for k, v in syms.items():
                        if k.endswith('@%d' % sc):
                            look[k.split('@')[0]] = v
                ev = lambda e: evaluate(e, look, pc, pas == 2)
                if mn == 'EQU':
                    syms[label.lower()] = evaluate(args, look, pc, pas == 2)
                    continue
                if label:
                    syms[sym_key(label, sc)] = pc
                    look[label.lower()] = pc
                if not mn or mn == 'END':
                    continue
                if mn == 'CPU':
                    fam = CPU_FAMILY[args.strip()]
                elif mn == 'ORG':
                    pc = ev(args)
                elif mn == 'ALIGN':
                    a = ev(args)
                    pc = (pc + a - 1) // a * a
                elif mn == 'DB':
                    for o in split_ops(args):
                        if pas == 2:
                            image[pc] = ev(o) & 0xFF
                        pc += 1
                else:
                    b = encode(mn, split_ops(args), fam, ev, pc)
                    if b is None:
                        raise AsmError('unknown mnemonic %s' % mn)
                    if pas == 2:
                        for i, x in enumerate(b):
                            if pc + i in image:
                                raise AsmError('overlapping code at %03x' % (pc + i))
                            image[pc + i] = x
                    pc += len(b)
        return image, fam


def ihex(image, lo, hi, relative):
    lines = []
    addrs = sorted(a for a in image if lo <= a <= hi)
    i = 0
    while i < len(addrs):
        start = addrs[i]
        chunk = [image[start]]
        while i + 1 < len(addrs) and addrs[i + 1] == addrs[i] + 1 and len(chunk) < 16:
            i += 1
            chunk.append(image[addrs[i]])
        i += 1
        a = start - lo if relative else start
        rec = [len(chunk), (a >> 8) & 0xFF, a & 0xFF, 0] + chunk
        lines.append(':' + ''.join('%02X' % x for x in rec) + '%02X' % ((-sum(rec)) & 0xFF))
    lines.append(':00000001FF')
    return '\n'.join(lines) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('-I', action='append', default=[])
    ap.add_argument('-o', help='4096-byte binary image (unused bytes 0)')
    ap.add_argument('--hex', help='plain hex image, one byte per line (for $readmemh)')
    ap.add_argument('--ihex', action='append', default=[], help='file:lo-hi[:a]')
    a = ap.parse_args()
    try:
        image, fam = Assembler(a.I).assemble(a.src)
    except AsmError as e:
        sys.exit('%s: %s' % (a.src, e))
    if a.o:
        open(a.o, 'wb').write(bytes(image.get(i, 0) for i in range(4096)))
    if a.hex:
        open(a.hex, 'w').write(''.join('%02x\n' % image.get(i, 0) for i in range(4096)))
    for spec in a.ihex:
        f, rng, *rel = spec.split(':')
        lo, hi = (int(x) for x in rng.split('-'))
        open(f, 'w').write(ihex(image, lo, hi, bool(rel)))


if __name__ == '__main__':
    main()

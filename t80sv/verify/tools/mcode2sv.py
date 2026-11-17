#!/usr/bin/env python3
"""Convert the T80_MCode.vhd decode process body to an SV always_comb body.
Statically prunes Mode = 3 (Game Boy) and R800_mode = '1' branches (both never true in the fleet)."""
import re, sys

src = open(sys.argv[1]).read().splitlines()
# locate process body: after 'SetWZ <= "00";' default block start = line with 'MCycles <= "001";'
start = next(i for i, l in enumerate(src) if re.match(r'\s*MCycles <= "001";', l))
end = max(i for i, l in enumerate(src) if re.match(r'\s*end process;', l))
lines = src[start:end]

# strip comments, join into statement tokens
stmts = []
buf = ''
for l in lines:
    l = l.split('--')[0].strip()
    if not l:
        continue
    buf = (buf + ' ' + l).strip() if buf else l
    if buf.startswith('when') and '=>' not in buf:
        continue
    if buf.startswith('when'):
        head, rest = buf.split('=>', 1)
        stmts.append(head.strip() + ' =>')
        buf = rest.strip()
        if not buf:
            continue
    if buf.startswith(('if ', 'elsif ')) and not buf.endswith('then'):
        continue
    if buf.startswith('case ') and not buf.endswith(' is'):
        continue
    if buf in ('else',) or buf.endswith('then') or buf.endswith(' is') or buf.endswith(';'):
        stmts.append(buf)
        buf = ''
assert not buf, buf

# parse
pos = 0
def peek():
    return stmts[pos] if pos < len(stmts) else None

def parse_block(stops):
    global pos
    out = []
    while True:
        s = peek()
        if s is None or any(s.startswith(t) for t in stops):
            return out
        if s.startswith('if '):
            out.append(parse_if())
        elif s.startswith('case '):
            out.append(parse_case())
        else:
            pos += 1
            if s != 'null;':
                out.append(('asg', s))

def parse_if():
    global pos
    s = stmts[pos]; pos += 1
    arms = [(s[3:-5].strip(), parse_block(['elsif', 'else', 'end if']))]
    els = None
    while True:
        s = stmts[pos]; pos += 1
        if s.startswith('elsif'):
            arms.append((s[6:-5].strip(), parse_block(['elsif', 'else', 'end if'])))
        elif s == 'else':
            els = parse_block(['end if'])
        else:
            assert s == 'end if;', s
            return ('if', arms, els)

def parse_case():
    global pos
    s = stmts[pos]; pos += 1
    sel = s[5:-3].strip()
    arms = []
    while True:
        s = stmts[pos]; pos += 1
        if s == 'end case;':
            return ('case', sel, arms)
        assert s.startswith('when'), s
        arms.append((s[5:-3].strip(), parse_block(['when', 'end case'])))

tree = parse_block([])
assert pos == len(stmts), stmts[pos]

# static evaluation
STATIC = {}  # full translation: no static pruning
def static(c):
    c = c.strip()
    while c.startswith('(') and c.endswith(')') and c.count('(') == 1:
        c = c[1:-1].strip()
    if c in STATIC:
        return STATIC[c]
    for op, absorb in ((' and ', False), (' or ', True)):
        if op in c and '(' not in c.replace('IR(5)', ''):
            parts = [static(p) for p in c.split(op)]
            if absorb in parts:
                return absorb
    return None

def prune(block):
    out = []
    for st in block:
        if st[0] == 'asg':
            out.append(st)
        elif st[0] == 'case':
            out.append(('case', st[1], [(ch, prune(b)) for ch, b in st[2]]))
        else:
            arms = []
            els = prune(st[2]) if st[2] is not None else None
            done = False
            for c, b in st[1]:
                v = static(c)
                if v is False:
                    continue
                if v is True:
                    if not arms:
                        out.extend(prune(b)); done = True
                    else:
                        els = prune(b)
                    break
                arms.append((c, prune(b)))
            if done:
                continue
            if not arms:
                if els:
                    out.extend(els)
                continue
            out.append(('if', arms, els))
    return out

tree = prune(tree)

def bits(m):
    return "%d'b%s" % (len(m.group(1)), m.group(1))

CANON = {n.lower(): n for n in '''MCycles TStates Prefix Inc_PC Inc_WZ IncDec_16 Read_To_Reg Read_To_Acc Set_BusA_To
 Set_BusB_To ALU_Op Save_ALU PreserveC Arith16 Set_Addr_To IORQ Jump JumpE JumpXY Call RstP LDZ LDW LDSPHL
 Special_LD ExchangeDH ExchangeRp ExchangeAF ExchangeRS ExchangeWH I_DJNZ I_CPL I_CCF I_SCF I_RETN I_BT I_BC I_BTR
 I_RLD I_RRD I_INRC SetWZ SetDI SetEI IMode Halt NoRead Write No_PC XYbit_undoc IR ISet MCycle F NMICycle IntCycle
 XY_State DDD SSS DPair R800_mode LDHLSP ADDSPdd I_MULU I_MULUB Rot_Akku'''.split()}
def expr(e):
    e = e.strip()
    e = re.sub(r'\b[A-Za-z_][A-Za-z_0-9]*\b', lambda m: CANON.get(m.group(0).lower(), m.group(0)), e)
    e = re.sub(r'to_bitvector\((.*)\)$', r'\1', e)
    e = e.replace('to_bitvector(IR(5 downto 3))', 'IR(5 downto 3)')
    e = re.sub(r'to_integer\(unsigned\((.*?\)?)\)\)', r'\1', e)
    e = re.sub(r'\bIRB\b', 'IR', e)
    e = re.sub(r'\bDPAIR\b', 'DPair', e, flags=re.I)
    e = re.sub(r'\bMode\b', 'mode', e)
    e = re.sub(r"R800_mode == 1'b1", 'R800_mode', e)
    e = re.sub(r'\((\d) downto (\d)\)', r'[\1:\2]', e)
    e = re.sub(r'\b(IR|F|Set_BusA_To|Set_BusB_To|IncDec_16|XY_State)\((\w+)\)', r'\1[\2]', e)
    e = re.sub(r'"0" & (IR\[5:3\])', r"{1'b0, \1}", e)
    e = re.sub(r'"([01]{8})"', lambda m: "8'h%02X" % int(m.group(1), 2), e)
    e = re.sub(r'"([01]+)"', bits, e)
    e = re.sub(r"'([01])'", r"1'b\1", e)
    e = re.sub(r'"0" & ', '', e)
    e = e.replace('/=', '!=')
    e = re.sub(r'(?<![<>=!])=(?!=)', '==', e)
    e = re.sub(r'\bnot\s*\(', '!(', e)
    e = re.sub(r'\band\b', '&&', e)
    e = re.sub(r'\bor\b', '||', e)
    e = re.sub(r'is_cc_true\(F, (.*)\)', r'is_cc_true(\1)', e)
    return e

CASEW = {'MCycle': 3, 'IR(5 downto 4)': 2, 'IR': 8, 'IR(4 downto 3)': 2, 'ISet': 2}
DROP = set()
out = []
def emit(block, ind):
    p = '\t' * ind
    for st in block:
        if st[0] == 'asg' and st[1].split('<=')[0].strip() in DROP:
            continue
        if st[0] == 'asg':
            lhs, rhs = st[1][:-1].split('<=')
            lhs = expr(lhs); rhs = expr(rhs)
            if lhs == 'ALU_Op':
                rhs = '{1\'b0, IR[5:3]}' if 'IR[5:3]' in rhs and "'b" not in rhs else rhs
            out.append(f'{p}{lhs} = {rhs};')
        elif st[0] == 'if':
            if len(st[1]) == 1 and not st[1][0][1] and st[2]:
                out.append(f'{p}if (!({expr(st[1][0][0])})) begin')
                emit(st[2], ind + 1)
                out.append(f'{p}end')
                continue
            for k, (c, b) in enumerate(st[1]):
                kw = 'if' if k == 0 else 'end else if'
                out.append(f'{p}{kw} ({expr(c)}) begin')
                emit(b, ind + 1)
            if st[2]:
                out.append(f'{p}end else begin')
                emit(st[2], ind + 1)
            out.append(f'{p}end')
        else:
            sel = re.sub(r'to_integer\(unsigned\((.*)\)\)', r'\1', st[1])
            sel = re.sub(r'\bIRB\b', 'IR', sel)
            w = CASEW[sel]
            out.append(f'{p}case ({expr(sel)})')
            for ch, b in st[2]:
                if ch == 'others':
                    lab = 'default'
                else:
                    labs = []
                    for c in ch.split('|'):
                        c = c.strip()
                        if c.startswith('"') and w == 8:
                            labs.append("8'h%02X" % int(c.strip('"'), 2))
                        elif c.startswith('"'):
                            labs.append(expr(c))
                        else:
                            labs.append(f"{w}'d{c}")
                    lab = ',\n'.join(p + ', '.join(labs[i:i+8]) for i in range(0, len(labs), 8)).lstrip('\t')
                if not b:
                    out.append(f'{p}{lab}: ;')
                else:
                    out.append(f'{p}{lab}: begin')
                    emit(b, ind + 1)
                    out.append(f'{p}end')
            out.append(f'{p}endcase')

emit(tree, 1)
print('\n'.join(out))

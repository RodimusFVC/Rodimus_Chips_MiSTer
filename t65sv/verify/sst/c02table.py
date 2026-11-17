#!/usr/bin/env python3
# Per-opcode bus-pattern signature table for a SST set (pattern = symbolic address sequence; length = PC delta)
import struct, sys
exec(open(__file__.replace('c02table.py','dump.py')).read().split("d,op=sys.argv")[0])
def sym(i, a, r):
    pc=i['pc']; s=i['s']; o1=i['ram'].get((pc+1)&0xffff,0); o2=i['ram'].get((pc+2)&0xffff,0); x=i['x']; y=i['y']
    dd=(a-pc)&0xffff
    if dd<4: return f'P{dd}'
    if 0x100<=a<0x200 and -3<=(a-0x100)-s<=3: return f'S{(a-0x100)-s:+d}'
    c=[('zp',o1),('zp1',(o1+1)&0xff),('zpX',(o1+x)&0xff),('zpX1',(o1+x+1)&0xff),('zpY',(o1+y)&0xff),
       ('ab',o2*256+o1),('ab1',(o2*256+o1+1)&0xffff),('abXl',o2*256+((o1+x)&0xff)),('abX',(o2*256+o1+x)&0xffff),('abX1',(o2*256+o1+x+1)&0xffff),
       ('abYl',o2*256+((o1+y)&0xff)),('abY',(o2*256+o1+y)&0xffff)]
    zl=i['ram'].get(o1,None); zh=i['ram'].get((o1+1)&0xff,None)
    if zl is not None and zh is not None:
        c+= [('iz',zh*256+zl),('izYl',zh*256+((zl+y)&0xff)),('izY',(zh*256+zl+y)&0xffff)]
    xl=i['ram'].get((o1+x)&0xff,None); xh=i['ram'].get((o1+x+1)&0xff,None)
    if xl is not None and xh is not None: c+=[('ixz',xh*256+xl)]
    for n,v in c:
        if a==v: return n
    if a>=0xfff0: return f'{a:04x}'
    return f'?{a:04x}'
d=sys.argv[1]
for op in range(256):
    path=f"{d}/{op:02x}.bin"
    try: open(path).close()
    except: continue
    pats={}
    lens=set()
    for i,fi,cyc in tests(path):
        key=' '.join(('r' if r else 'W')+sym(i,a,r) for a,v,r in cyc)
        dec=(i['p']>>3)&1
        pats.setdefault(key,[0,set()]); pats[key][0]+=1; pats[key][1].add(dec)
        lens.add((fi['pc']-i['pc'])&0xffff)
    L=','.join(str(l) for l in sorted(lens)) if len(lens)<4 else 'var'
    top=sorted(pats.items(), key=lambda kv:-kv[1][0])[:5]
    print(f"{op:02X} len={L}: " + ' || '.join(f"{k} (x{v[0]}{' D' if v[1]=={1} else ''})" for k,(v) in top))

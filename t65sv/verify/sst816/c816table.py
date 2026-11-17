#!/usr/bin/env python3
# c816table.py <bindir> <e|n> [ops...]: symbolic bus patterns per opcode, split by M/X/E and D-low!=0
import sys
exec(open(__file__.replace('c816table.py','dump816.py')).read().split("if __name__")[0])
def syms(i):
    pc,pbr,s,d,dbr,x,y=i['pc'],i['pbr'],i['s'],i['d'],i['dbr'],i['x'],i['y']
    r=i['ram']
    o=[r.get((pbr<<16)|((pc+k)&0xffff),0) for k in range(4)]
    o1=o[1]; o16=o[1]|o[2]<<8; o24=o16|o[3]<<16
    c={}
    def add(n,a):
        c.setdefault(a&0xffffff,n)
    for k in range(4): add(f'P{k}',(pbr<<16)|((pc+k)&0xffff))
    for k in range(-3,4): add(f'S{k:+d}',(s+k)&0xffff)
    for k in range(-3,4): add(f'S{k:+d}e',0x100|((s+k)&0xff))
    for n,base in [('d',d+o1),('dX',d+o1+x),('dY',d+o1+y)]:
        for k in range(3): add(n+('' if k==0 else f'+{k}'),(base+k)&0xffff)
    add('dXw',(d&0xff00)|((d+o1+x)&0xff)); add('dXw+1',(d&0xff00)|((d+o1+x+1)&0xff))
    add('dYw',(d&0xff00)|((d+o1+y)&0xff))
    add('dw+1',(d&0xff00)|((o1+1)&0xff))
    for n,base in [('a',(dbr<<16)+o16),('aX',(dbr<<16)+o16+x),('aY',(dbr<<16)+o16+y)]:
        for k in range(3): add(n+('' if k==0 else f'+{k}'),base+k)
    add('aXl',(dbr<<16)|(o16&0xff00)|((o16+x)&0xff)); add('aYl',(dbr<<16)|(o16&0xff00)|((o16+y)&0xff))
    for k in range(3): add('L'+('' if k==0 else f'+{k}'),o24+k); add('LX'+('' if k==0 else f'+{k}'),o24+x+k)
    for k in range(2): add('sr'+('' if k==0 else f'+{k}'),(s+o1+k)&0xffff)
    # indirect pointers through direct page / stack
    for n,pa in [('id',(d+o1)&0xffff),('idX',(d+o1+x)&0xffff),('isr',(s+o1)&0xffff)]:
        lo=r.get(pa,None); hi=r.get((pa+1)&0xffff,None); bk=r.get((pa+2)&0xffff,None)
        if lo is not None and hi is not None:
            p=lo|hi<<8
            for k in range(3): add(n+'>'+('' if k==0 else f'+{k}'),(dbr<<16)+p+k)
            for k in range(3): add(n+'>Y'+('' if k==0 else f'+{k}'),(dbr<<16)+p+y+k)
            if bk is not None:
                for k in range(3): add(n+'>>'+('' if k==0 else f'+{k}'),((bk<<16)|p)+k); add(n+'>>Y'+('' if k==0 else f'+{k}'),((bk<<16)|p)+y+k)
    return c
def pat(i,cyc):
    c=syms(i); out=[]
    for a,v,ok,f in cyc:
        n=c.get(a, 'V%04x'%a if a>=0xffe0 else '?%06x'%a)
        flags=''.join(ch for k,ch in enumerate('dpv') if f&(0x80>>k)) or 'i'
        rw='r' if f&0x10 else 'W'
        out.append(f'{rw}{n}.{flags}')
    return ' '.join(out)
d,mode=sys.argv[1],sys.argv[2]
ops=sys.argv[3:] or ['%02x'%k for k in range(256)]
for op in ops:
    groups={}
    for i,fi,cyc in tests(f"{d}/{op}.{mode}.bin"):
        p=i['p']; key=('M' if p&0x20 else 'm')+('X' if p&0x10 else 'x')+('D0' if i['d']&0xff==0 else 'Dn')+('d' if p&8 else '')
        if i['e']: key='E'+('D0' if i['d']&0xff==0 else 'Dn')+('d' if p&8 else '')
        pt=pat(i,cyc)
        groups.setdefault(key,{}).setdefault(pt,0); groups[key][pt]+=1
    print(f"== {op}.{mode}")
    for k in sorted(groups):
        top=sorted(groups[k].items(), key=lambda kv:-kv[1])[:3]
        tot=sum(groups[k].values())
        for pt,n in top: print(f"  {k:7s} {n:5d}/{tot:<5d} {pt}")

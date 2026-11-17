#!/usr/bin/env python3
# dump2.py <bin-dir> op... : one compact example per distinct cycle count (and per D flag for ADC/SBC)
import struct, sys
def rd_st(f):
    pc,s,a,x,y,p,n = struct.unpack('<HBBBBBH', f.read(9))
    ram=[struct.unpack('<HB', f.read(3)) for _ in range(n)]
    return dict(pc=pc,s=s,a=a,x=x,y=y,p=p,ram=dict(ram))
def tests(path):
    f=open(path,'rb'); n,=struct.unpack('<I',f.read(4))
    for _ in range(n):
        i=rd_st(f); fi=rd_st(f); nc,=struct.unpack('<H',f.read(2))
        cyc=[struct.unpack('<HBB',f.read(4)) for _ in range(nc)]
        yield i,fi,cyc
d=sys.argv[1]
for op in sys.argv[2:]:
    seen={}
    for i,fi,cyc in tests(f"{d}/{op}.bin"):
        key=(len(cyc), (i['p']>>3)&1 if op[1] in '19dDb5' and op[0] in '67eEfF' else 0)
        seen.setdefault(key,[0,None]); seen[key][0]+=1
        if seen[key][1] is None:
            pc=i['pc']; s=i['s']; o1=i['ram'].get((pc+1)&0xffff,0); o2=i['ram'].get((pc+2)&0xffff,0)
            toks=[]
            for a,v,r in cyc:
                dd=(a-pc)&0xffff
                if dd<4: t=f'PC+{dd}'
                elif 0x100<=a<0x200 and abs((a-0x100)-s)<4: t=f'S{(a-0x100)-s:+d}'
                elif a==o1: t='zp'
                elif a==((o1+1)&0xff): t='zp+1'
                elif a==((o1+i['x'])&0xff): t='zp+X'
                elif a==((o1+i['x']+1)&0xff): t='zp+X+1'
                elif a==((o1+i['y'])&0xff): t='zp+Y'
                elif a==o2*256+o1: t='abs'
                elif a==(o2*256+((o1+i['x'])&0xff)): t='abs+Xlo'
                elif a==((o2*256+o1+i['x'])&0xffff): t='abs+X'
                elif a==(o2*256+((o1+i['y'])&0xff)): t='abs+Ylo'
                elif a==((o2*256+o1+i['y'])&0xffff): t='abs+Y'
                elif a==((pc+2+((o1^0x80)-0x80))&0xffff): t='btgt'
                elif a>=0xfffa: t=f'{a:04x}'
                else: t=f'{a:04x}'
                toks.append(('R' if r else 'W')+':'+t)
            seen[key][1]=f"pc={pc:04x} o={o1:02x} {o2:02x} x={i['x']:02x} y={i['y']:02x} p={i['p']:02x} | "+' '.join(toks)
    for k,(n,ex) in sorted(seen.items()):
        print(f"{op} n={k[0]}{' D' if k[1] else ''} x{n}: {ex}")

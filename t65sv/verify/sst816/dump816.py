#!/usr/bin/env python3
# dump816.py <bindir> <op> <e|n> [n]: print a few 65816 SST cases
import struct, sys
def rd_st(f):
    pc,s,p,a,x,y,dbr,d,pbr,e,n = struct.unpack('<HHBHHHBHBBI', f.read(20))
    ram=dict(struct.unpack('<IB', f.read(5)) for _ in range(n))
    return dict(pc=pc,s=s,p=p,a=a,x=x,y=y,dbr=dbr,d=d,pbr=pbr,e=e,ram=ram)
def tests(path):
    f=open(path,'rb'); n,=struct.unpack('<I',f.read(4))
    for _ in range(n):
        i=rd_st(f); fi=rd_st(f); nc,=struct.unpack('<H',f.read(2))
        cyc=[struct.unpack('<IBBB',f.read(7)) for _ in range(nc)]
        yield i,fi,cyc
def fl(b): return ''.join(c if b&(0x80>>k) else ('w' if c=='r' else '-') for k,c in enumerate('dpvrexml'.replace('exml','emxl')))
if __name__=='__main__':
    d,op,m=sys.argv[1],sys.argv[2],sys.argv[3]; n=int(sys.argv[4]) if len(sys.argv)>4 else 3
    for k,(i,fi,cyc) in enumerate(tests(f"{d}/{op}.{m}.bin")):
        if k>=n: break
        print(f"pc={i['pbr']:02x}:{i['pc']:04x} s={i['s']:04x} p={i['p']:02x} e={i['e']} a={i['a']:04x} x={i['x']:04x} y={i['y']:04x} d={i['d']:04x} dbr={i['dbr']:02x}  -> pc={fi['pbr']:02x}:{fi['pc']:04x} p={fi['p']:02x} s={fi['s']:04x}")
        for a,v,ok,f in cyc: print(f"   {a:06x} {v:02x} {fl(f)}" if ok else f"   {a:06x} -- {fl(f)}")

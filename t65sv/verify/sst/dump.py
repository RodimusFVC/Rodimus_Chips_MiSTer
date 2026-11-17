#!/usr/bin/env python3
# dump.py <bin-dir> <op-hex> [n] [filter]: print bus traces of a few SST cases (relative annotations)
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
d,op=sys.argv[1],sys.argv[2]; want=int(sys.argv[3]) if len(sys.argv)>3 else 3
flt=sys.argv[4] if len(sys.argv)>4 else None
cnt={}
shown=0
for i,fi,cyc in tests(f"{d}/{op}.bin"):
    cnt[len(cyc)]=cnt.get(len(cyc),0)+1
    if flt and str(len(cyc))!=flt: continue
    if shown<want:
        shown+=1
        pc=i['pc']; ops=[i['ram'].get((pc+k)&0xffff) for k in range(3)]
        print(f"pc={pc:04x} ops={' '.join('%02x'%o if o is not None else '--' for o in ops)} s={i['s']:02x} a={i['a']:02x} x={i['x']:02x} y={i['y']:02x} p={i['p']:02x} -> pc={fi['pc']:04x} a={fi['a']:02x} p={fi['p']:02x} s={fi['s']:02x}")
        for k,(a,v,r) in enumerate(cyc):
            rel=''
            dd=(a-pc)&0xffff
            if dd<4: rel=f'PC+{dd}'
            elif 0x100<=a<0x200: rel=f'SP{(a-0x100)-i["s"]:+d}'
            print(f"   {k}: {'R' if r else 'W'} {a:04x} {v:02x} {rel}")
print('cycle-count histogram:', dict(sorted(cnt.items())))

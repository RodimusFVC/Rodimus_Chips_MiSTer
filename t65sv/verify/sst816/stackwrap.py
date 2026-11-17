#!/usr/bin/env python3
# stackwrap.py <bindir>: per stack opcode in emulation, do stack accesses near a page edge leave page 1?
import sys
exec(open(__file__.replace('stackwrap.py','dump816.py')).read().split("if __name__")[0])
d=sys.argv[1]
for op in '08 28 48 68 8b ab 0b 2b 4b da fa 5a 7a 62 d4 f4 22 6b 20 fc 60 40 00 02'.split():
    res={}
    for i,fi,cyc in tests(f"{d}/{op}.e.bin"):
        sl=i['s']&0xff
        if 3<=sl<=0xfc: continue
        pages=set()
        for a,v,ok,f in cyc:
            if a>>16==0 and (f&0x80) and (a>>8) in (0,1,2) and abs((a&0xff)-sl)<6 or (a>>16==0 and (f&0x80) and ((a&0xff)<6 or (a&0xff)>0xf9) and (a>>8) in (0,2)):
                pages.add(a>>8)
        k=tuple(sorted(pages)); res[k]=res.get(k,0)+1
    print(op,res)

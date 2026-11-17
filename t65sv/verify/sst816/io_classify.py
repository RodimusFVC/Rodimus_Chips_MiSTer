#!/usr/bin/env python3
# io_classify.py <bindir> <e|n>: for every internal (VDA=VPA=0) cycle, how its address relates to the previous cycle
import sys
exec(open(__file__.replace('io_classify.py','c816table.py')).read().split("def pat")[0].split("import sys")[1].replace("exec(open(__file__.replace('c816table.py','dump816.py')).read().split(\"if __name__\")[0])",""))
exec(open(__file__.replace('io_classify.py','dump816.py')).read().split("if __name__")[0])
d,mode=sys.argv[1],sys.argv[2]
for op in range(256):
    res={}
    for i,fi,cyc in tests(f"{d}/{op:02x}.{mode}.bin"):
        c=syms(i)
        for k,(a,v,ok,f) in enumerate(cyc):
            if k==0 or f&0xe0: continue
            pa=cyc[k-1][0]
            if a==pa: cl='prev'
            elif a==((pa&0xff0000)|((pa+1)&0xffff)): cl='prev+1'
            else: cl=c.get(a,'?')
            key=(k,cl); res[key]=res.get(key,0)+1
    if res: print(f"{op:02x}.{mode}: "+' '.join(f"c{k}:{cl}x{n}" for (k,cl),n in sorted(res.items())))

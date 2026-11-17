#!/usr/bin/env python3
# find816.py <bindir> <op> <e|n> <python-cond on i/fi> [n]: dump cases matching a condition
import sys
exec(open(__file__.replace('find816.py','dump816.py')).read().split("if __name__")[0])
d,op,m,cond=sys.argv[1:5]; n=int(sys.argv[5]) if len(sys.argv)>5 else 2
k=0
for i,fi,cyc in tests(f"{d}/{op}.{m}.bin"):
    if not eval(cond): continue
    print(f"pc={i['pbr']:02x}:{i['pc']:04x} s={i['s']:04x} p={i['p']:02x} e={i['e']} a={i['a']:04x} x={i['x']:04x} y={i['y']:04x} d={i['d']:04x} dbr={i['dbr']:02x}  -> pc={fi['pbr']:02x}:{fi['pc']:04x} p={fi['p']:02x} s={fi['s']:04x} a={fi['a']:04x} x={fi['x']:04x} y={fi['y']:04x} d={fi['d']:04x} dbr={fi['dbr']:02x} e={fi['e']}")
    for a,v,ok,f in cyc: print(f"   {a:06x} {v:02x} {fl(f)}" if ok else f"   {a:06x} -- {fl(f)}")
    k+=1
    if k>=n: break

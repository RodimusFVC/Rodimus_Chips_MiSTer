#!/usr/bin/env python3
# stat816.py <bindir> <e|n> <python-cond> [ops]: count matching cases per opcode
import sys
exec(open(__file__.replace('stat816.py','dump816.py')).read().split("if __name__")[0])
d,m,cond=sys.argv[1:4]; ops=sys.argv[4:] or ['%02x'%k for k in range(256)]
for op in ops:
    n=sum(1 for i,fi,cyc in tests(f"{d}/{op}.{m}.bin") if eval(cond))
    print(op,n)

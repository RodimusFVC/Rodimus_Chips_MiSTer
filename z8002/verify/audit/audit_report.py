#!/usr/bin/env python3
"""Cross-tabulate rtl/cpu/z8002/z8002.sv coverage against MAME's z8002 dispatch table.

Oracle: Useful Stuff/mame/z8000/z8000tbl.hxx. Entries are
    { first_word_lo, first_word_hi, ..., &z8002_device::HANDLER },
applied IN ORDER, so a later entry overrides an earlier one. The first entry
fills 0x0000-0xFFFF with `zinvalid`. Any word whose final handler is not
`zinvalid` is a real Z8002 instruction our core must decode.
"""
import re, sys, collections

TBL = "../../Useful Stuff/mame/z8000/z8000tbl.hxx"
ENT = re.compile(r'\{\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,[^&]*&\s*z8002_device::(\w+)')

handler = ["zinvalid"] * 65536
n_ent = 0
for line in open(TBL):
    m = ENT.search(line)
    if not m:
        continue
    lo, hi, h = int(m.group(1), 16), int(m.group(2), 16), m.group(3)
    if hi < lo or hi > 0xFFFF:
        continue
    for w in range(lo, hi + 1):
        handler[w] = h
    n_ent += 1

mame_valid = {w for w in range(65536) if handler[w] != "zinvalid"}
ours_ill   = {int(l.strip(), 16) for l in open("ours_illegal.txt") if l.strip()}

missing = sorted(mame_valid & ours_ill)          # MAME says real, we say illegal
extra   = sorted((set(range(65536)) - mame_valid) - ours_ill)  # MAME invalid, we accept

print(f"table entries parsed : {n_ent}")
print(f"MAME-valid words     : {len(mame_valid)}")
print(f"our illegal words    : {len(ours_ill)}")
print(f"\n*** GAPS: MAME-valid but our core flags ILLEGAL: {len(missing)} words ***")

by_h = collections.defaultdict(list)
for w in missing:
    by_h[handler[w]].append(w)
print(f"    spanning {len(by_h)} distinct MAME handlers\n")
for h, ws in sorted(by_h.items(), key=lambda kv: -len(kv[1])):
    rngs, s = [], ws[0]
    for a, b in zip(ws, ws[1:] + [None]):
        if b != (a + 1) if b is not None else True:
            rngs.append(f"{s:04X}" if s == a else f"{s:04X}-{a:04X}")
            if b is not None:
                s = b
    print(f"  {h:<34} {len(ws):>6} words   {', '.join(rngs[:6])}{' ...' if len(rngs)>6 else ''}")

print(f"\n(for reference) MAME-invalid words our core ACCEPTS: {len(extra)}")

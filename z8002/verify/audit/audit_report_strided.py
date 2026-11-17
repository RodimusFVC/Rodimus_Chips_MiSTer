#!/usr/bin/env python3
"""CORRECTED cross-tabulation of rtl/cpu/z8002/z8002.sv coverage against MAME's
z8002 dispatch table, respecting the table's `step` field.

WHY THIS FILE EXISTS: audit_report.py (the rig's official report script) parses
each z8000tbl.hxx entry as `{ lo, hi, ..., handler }` and fills handler[lo..hi]
DENSELY. But the real struct is `Z8000_init { int beg, end, step; ... }`
(z8000.h:689) and MAME's own init loop is:
    for (u32 val = opc->beg; val <= opc->end; val += opc->step)
        z8000_exec[val] = opc - table;
221 entries have step=16 and 1 has step=8 (verified: every non-1 step in the
table). For those entries (all "NIB2=reg-field-nonzero, NIB3=fixed-sub-op"
register-indirect/direct-address families -- e.g. Z1C_ssN0_0001_..., step 16
walks NIB2=1..F holding NIB3 fixed), audit_report.py's dense fill wrongly marks
every intermediate word (other NIB3 values, which are REAL, DIFFERENT
instructions or genuinely invalid encodings) as "belonging" to that handler.
Since later table entries in the same byte range can still correctly overwrite
some of those words, the practical effect is INFLATED/bogus "MAME-valid" gaps
at intermediate words that are not real instructions at all.

This script is diagnostic ONLY (guides which reported gaps are REAL vs
phantom-due-to-stride-bug); the task's official deliverable numbers still come
from audit_report.py + ours_illegal.txt, per the task brief. Do not implement
opcode decode logic to "fix" a gap this script shows as phantom -- that would
mean inventing behavior for a word that is not a real Z8002 instruction.
"""
import re, sys, collections

TBL = "../../Useful Stuff/mame/z8000/z8000tbl.hxx"
ENT = re.compile(
    r'\{\s*0x([0-9a-fA-F]+)\s*,\s*0x([0-9a-fA-F]+)\s*,\s*(\d+)\s*,[^&]*&\s*z8002_device::(\w+)'
)

handler = ["zinvalid"] * 65536
n_ent = 0
for line in open(TBL):
    m = ENT.search(line)
    if not m:
        continue
    lo, hi, step, h = int(m.group(1), 16), int(m.group(2), 16), int(m.group(3)), m.group(4)
    if hi < lo or hi > 0xFFFF or step <= 0:
        continue
    for w in range(lo, hi + 1, step):
        handler[w] = h
    n_ent += 1

mame_valid = {w for w in range(65536) if handler[w] != "zinvalid"}
ours_ill   = {int(l.strip(), 16) for l in open("ours_illegal.txt") if l.strip()}

missing = sorted(mame_valid & ours_ill)          # MAME says real, we say illegal
extra   = sorted((set(range(65536)) - mame_valid) - ours_ill)  # MAME invalid, we accept

print(f"table entries parsed  : {n_ent}")
print(f"MAME-valid words (true, step-respecting): {len(mame_valid)}")
print(f"our illegal words     : {len(ours_ill)}")
print(f"\n*** TRUE GAPS: MAME-valid but our core flags ILLEGAL: {len(missing)} words ***")

by_h = collections.defaultdict(list)
for w in missing:
    by_h[handler[w]].append(w)
print(f"    spanning {len(by_h)} distinct MAME handlers\n")
for h, ws in sorted(by_h.items(), key=lambda kv: -len(kv[1])):
    rngs, s = [], ws[0]
    for a, b in zip(ws, ws[1:] + [None]):
        if (b != a + 1) if b is not None else True:
            rngs.append(f"{s:04X}" if s == a else f"{s:04X}-{a:04X}")
            if b is not None:
                s = b
    print(f"  {h:<34} {len(ws):>6} words   {', '.join(rngs[:10])}{' ...' if len(rngs)>10 else ''}")

print(f"\n(for reference) MAME-invalid words our core ACCEPTS: {len(extra)}")
if extra:
    by_h2 = collections.defaultdict(int)
    # words our core accepts that the TRUE table says are invalid -- these would be
    # real over-acceptance bugs (not stride artifacts) if nonzero.
    for w in extra[:50]:
        print(f"    over-accepted: {w:04X}")

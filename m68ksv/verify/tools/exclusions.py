#!/usr/bin/env python3
# Build verify/suite_exclusions.txt: suite tests whose expected result disagrees with the 68000 tie-breaker (MAME
# m68000, the microcode-derived core) - see REPORT.md "Suite exclusions". Rule based, re-run against any copy:
#   python3 -I exclusions.py <suite dir with *.json.gz> > ../suite_exclusions.txt
# Line: <file> <test index> <corrected SR or -> <reason>
import gzip, json, os, sys

D = sys.argv[1]
out = []
for f, bits in (('ASR.b', 8), ('ASR.w', 16), ('ASR.l', 32)):
    for i, t in enumerate(json.load(gzip.open(os.path.join(D, f + '.json.gz')))):
        op = t['initial']['prefetch'][0]
        if (op >> 6) & 3 == 3 or not (op >> 5) & 1:
            continue
        cnt = t['initial']['d%d' % ((op >> 9) & 7)] & 63
        v = t['initial']['d%d' % (op & 7)] & ((1 << bits) - 1)
        if cnt > bits and v >> (bits - 1):
            # every shift step moves the sign bit out: X = C = 1 (MAME alu_asr*, Musashi); the suite has X = C = 0
            out.append('%s %d %04x asr_count_gt_size_negative' % (f, i, t['final']['sr'] | 0x11))
for f, bits in (('ASL.b', 8), ('ASR.b', 8), ('LSL.b', 8), ('LSR.b', 8), ('ROL.b', 8), ('ROR.b', 8), ('ROXL.b', 8), ('ROXR.b', 8)):
    for i, t in enumerate(json.load(gzip.open(os.path.join(D, f + '.json.gz')))):
        op = t['initial']['prefetch'][0]
        if (op >> 6) & 3 == 3:
            continue
        r = 'd%d' % (op & 7)
        if (t['initial'][r] ^ t['final'][r]) & 0xffffff00:
            out.append('%s %d - byte_shift_changes_upper_bits' % (f, i))
for i, t in enumerate(json.load(gzip.open(os.path.join(D, 'DIVU.json.gz')))):
    if any(x[0] == 'r' and x[3] == 0x14 and x[2] == 5 for x in t['transactions']):
        out.append('DIVU %d - zero_divide_frame' % i)
for i, t in enumerate(json.load(gzip.open(os.path.join(D, 'DIVS.json.gz')))):
    if any(x[0] == 'r' and x[3] == 0x14 and x[2] == 5 for x in t['transactions']):
        out.append('DIVS %d - zero_divide_frame' % i)
print('\n'.join(out))

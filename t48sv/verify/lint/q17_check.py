#!/usr/bin/env python3
"""Scan RTL for constructs Quartus 17.0 rejects (fleet experience, see REPORT.md)."""
import re, sys
bad = 0
for f in sys.argv[1:]:
    src = open(f).read()
    code = re.sub(r'//[^\n]*', '', src)
    checks = [
        (r'for\s*\(\s*genvar', 'for (genvar ...) loop (error 10170)'),
        (r"'\{\s*\w+\s*:", 'assignment pattern with key (10734 / 10163)'),
        (r"\b\d+\s*'\s*\(", 'size cast N\'(x)'),
        (r"-\s*\w+\s*'\s*\(", 'unary minus on a cast'),
        (r"\)\s*\[[^\]]*\]", 'bit-select on an expression'),
        (r'\bparameter\s+string\b', 'typed string parameter'),
        (r'\bimport\s+\w+::', 'package import'),
        (r'\binterface\b', 'interface'),
    ]
    for pat, what in checks:
        for m in re.finditer(pat, code):
            line = code[:m.start()].count('\n') + 1
            ctx = code.split('\n')[line - 1].strip()
            # ")[" inside port connections like .a_i(x)[..] would be real; casts in harness excluded
            print('%s:%d: %s: %s' % (f, line, what, ctx))
            bad += 1
print('q17_check: %d finding(s)' % bad)
sys.exit(1 if bad else 0)

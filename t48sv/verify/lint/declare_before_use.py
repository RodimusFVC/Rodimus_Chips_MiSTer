#!/usr/bin/env python3
"""Heuristic: report identifiers used inside a module before their declaration."""
import re, sys
bad = 0
for f in sys.argv[1:]:
    src = re.sub(r'//[^\n]*', '', open(f).read())
    src = re.sub(r'`define(.*?\\\n)*.*\n', lambda m: '\n' * m.group(0).count('\n'), src)
    for mm in re.finditer(r'\bmodule\s+(\w+)(.*?)\bendmodule\b', src, re.S):
        body, base = mm.group(2), mm.start(2)
        decl = {}
        for d in re.finditer(r'\b(?:input|output|inout|logic|wire|reg|genvar|localparam|parameter|bit|int)\b'
                             r'(?:\s+(?:logic|wire|bit|int|\[[^\]]*\]))*\s+((?:\w+\s*(?:\[[^\]]*\])?\s*(?:=[^,;)]*)?,\s*)*\w+)', body):
            for n in re.findall(r'(?:^|,)\s*(\w+)', d.group(1)):
                decl.setdefault(n, d.start())
        for n, pos in decl.items():
            u = re.search(r'(?<![.\w`])%s\b' % re.escape(n), body)
            if u and u.start() < pos:
                line = src[:base + u.start()].count('\n') + 1
                print('%s:%d: %s used before declaration in %s' % (f, line, n, mm.group(1)))
                bad += 1
print('declare_before_use: %d finding(s)' % bad)

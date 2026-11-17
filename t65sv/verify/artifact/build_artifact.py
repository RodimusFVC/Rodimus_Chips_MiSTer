#!/usr/bin/env python3
# build_artifact.py <t65sv root> <out html>: renders REPORT.md into the artifact page and writes files.json
# (the list of deliverable files the page serves one by one). Needs python-markdown.
import sys, os, json, re, html
import markdown

root, out = sys.argv[1], sys.argv[2]

# ---------------------------------------------------------------- deliverable files
INCLUDE_DIRS = ['rtl', 'verify', 'survey']
SKIP_DIRS = {'verify/build', 'verify/c64/gen', 'verify/sst816/__pycache__', 'verify/sst/__pycache__', 'verify/results816'}
SKIP_EXT = {'.vhd', '.hex', '.lst', '.a65', '.a65c', '.snap', '.o', '.d', '.log', '.ltp', '.ffs', '.dat', '.pyc', '.tmp', '.cf'}
SKIP_FILES = {'verify/ref/ref_T65.v', 'verify/ref/T65_ghdl_raw.v', 'verify/synth/t65sv_T65_yosys.sv', 'verify/tests/dormann/license.txt',
              'verify/sst816/table_n.txt', 'verify/sst816/table_e.txt', 'verify/sst816/compact_n.txt',
              'verify/sst816/compact_e.txt', 'verify/sst816/spec_n.txt', 'verify/sst816/spec_e.txt',
              'verify/sst816/io_n.txt', 'verify/sst816/io_e.txt'}
files = ['REPORT.md']
for d in INCLUDE_DIRS:
    for dp, dns, fns in os.walk(os.path.join(root, d)):
        rel = os.path.relpath(dp, root)
        dns[:] = sorted(x for x in dns if os.path.join(rel, x) not in SKIP_DIRS and not x.startswith('obj_'))
        for fn in sorted(fns):
            p = os.path.join(rel, fn)
            if os.path.splitext(fn)[1] in SKIP_EXT or p in SKIP_FILES: continue
            if os.path.getsize(os.path.join(root, p)) > 15 * 1024 * 1024: continue
            files.append(p)
sizes = {p: os.path.getsize(os.path.join(root, p)) for p in files}
json.dump(files, open(os.path.join(os.path.dirname(out), 'files.json'), 'w'), indent=0)

# ---------------------------------------------------------------- report -> html
md = open(os.path.join(root, 'REPORT.md')).read()
body = markdown.markdown(md, extensions=['tables', 'fenced_code', 'toc'], extension_configs={'toc': {'permalink': False}})
# wide tables scroll inside their own box
body = body.replace('<table>', '<div class="tw"><table>').replace('</table>', '</table></div>')
# inline code naming a deliverable file becomes a link to the viewer
fileset = set(files)
def linkify(m):
    t = html.unescape(m.group(1))
    if t in fileset:
        return f'<a class="fl" href="#files" data-file="{html.escape(t)}"><code>{m.group(1)}</code></a>'
    return m.group(0)
body = re.sub(r'<code>([^<]+)</code>', linkify, body)
# first h1 is rendered by the page header instead
body = re.sub(r'<h1[^>]*>.*?</h1>\s*<p>.*?</p>', '', body, count=1, flags=re.S)   # title + lede are in the header
# section ids for the nav
heads = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', body)

def human(n):
    return f'{n} B' if n < 1024 else f'{n/1024:.1f} KB' if n < 1024 * 1024 else f'{n/1048576:.1f} MB'

groups = {}
for p in files:
    g = os.path.dirname(p) or '.'
    groups.setdefault(g, []).append(p)
flist = []
for g in sorted(groups, key=lambda x: (x != '.', x)):
    items = ''.join(f'<li><a class="fl" href="#files" data-file="{html.escape(p)}">{html.escape(os.path.basename(p))}</a>'
                    f'<span class="sz">{human(sizes[p])}</span></li>' for p in groups[g])
    flist.append(f'<div class="fg"><h3>{html.escape(g if g != "." else "top level")}</h3><ul>{items}</ul></div>')

nav = ''.join(f'<a href="#{i}">{t}</a>' for i, t in heads) + '<a href="#files">Files</a>'
tpl = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'page.html')).read()
chips = ''
cf = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'chips.txt')
for l in open(cf).read().splitlines():
    if '|' in l:
        a, b = l.split('|', 1)
        chips += f'<span class="chip"><b>{html.escape(a.strip())}</b><i>{html.escape(b.strip())}</i></span>'
page = (tpl.replace('@@CHIPS@@', chips).replace('@@NAV@@', nav).replace('@@BODY@@', body).replace('@@FILES@@', ''.join(flist))
           .replace('@@NFILES@@', str(len(files))))
open(out, 'w').write(page)
print(f'{out}: {len(page)} bytes, {len(files)} files')

#!/usr/bin/env python3
"""Build the artifact page (index.html) from REPORT.md plus a list of every deliverable file served beside it."""
import markdown, os, html, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'index.html')
files = [l.strip() for l in open(os.path.join(ROOT, 'files.txt')) if l.strip()]
body = markdown.markdown(open(os.path.join(ROOT, 'REPORT.md')).read(), extensions=['tables', 'fenced_code'])
body = body.replace('<table>', '<div class="tw"><table>').replace('</table>', '</table></div>')

groups = {}
for f in files:
    g = f.split('/')[0] if '/' in f else 'top level'
    if f.startswith('verify/') and f.count('/') >= 2:
        g = 'verify/' + f.split('/')[1]
    groups.setdefault(g, []).append(f)
order = ['top level', 'rtl', 'docs'] + sorted(k for k in groups if k.startswith('verify'))
idx = []
for g in order:
    if g not in groups: continue
    items = ''.join(f'<li><a href="{html.escape(f)}">{html.escape(f)}</a> <span class="sz">{os.path.getsize(os.path.join(ROOT, f)) // 1024 + 1} KB</span></li>'
                    for f in groups[g])
    idx.append(f'<section class="grp"><h3>{html.escape(g)}</h3><ul>{items}</ul></section>')

page = f"""<title>crtc6845sv Test Report</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;600&family=IBM+Plex+Mono:wght@400;600&family=IBM+Plex+Sans+Condensed:wght@600&display=swap">
<style>
/* Layout: a single reading column with a sticky file index on wide screens; datasheet-like, signal-trace accent. */
:root {{
  --bg: #f6f7f5; --panel: #ffffff; --fg: #1b1f1d; --muted: #5d6762; --rule: #d6dbd7; --accent: #0b7a55; --code: #eef1ee;
  --ok: #0b7a55; --display: "IBM Plex Sans Condensed", "Arial Narrow", sans-serif; --body: "IBM Plex Sans", system-ui, sans-serif;
  --mono: "IBM Plex Mono", ui-monospace, Menlo, monospace;
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg: #121614; --panel: #181d1a; --fg: #e3e8e4; --muted: #9aa59f; --rule: #2c3530; --accent: #4cc99a; --code: #1e2521; --ok: #4cc99a; color-scheme: dark }} }}
:root[data-theme="dark"] {{ --bg: #121614; --panel: #181d1a; --fg: #e3e8e4; --muted: #9aa59f; --rule: #2c3530; --accent: #4cc99a; --code: #1e2521; --ok: #4cc99a; color-scheme: dark }}
body {{ background: var(--bg); color: var(--fg); font: 15px/1.55 var(--body); }}
.wrap {{ display: grid; grid-template-columns: minmax(0, 1fr) 300px; gap: 40px; max-width: 1280px; margin: 0 auto;
  padding-block: 28px 64px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }}
main {{ min-width: 0; }}
aside {{ min-width: 0; position: sticky; top: calc(env(safe-area-inset-top, 0px) + 16px); align-self: start; max-height: calc(100vh - 32px); overflow: auto;
  border-left: 1px solid var(--rule); padding-left: 20px; font-size: 13px; }}
@media (max-width: 980px) {{ .wrap {{ grid-template-columns: minmax(0, 1fr); }} aside {{ position: static; max-height: none; border-left: 0; padding-left: 0; border-top: 1px solid var(--rule); padding-top: 16px; }} }}
h1, h2, h3 {{ font-family: var(--display); font-weight: 600; text-wrap: balance; line-height: 1.2; }}
h1 {{ font-size: 2.1rem; margin: 0 0 .4rem; letter-spacing: -.01em; }}
h1::before {{ content: "MA[13:0] RA[4:0] DE HS VS"; display: block; font: 600 11px var(--mono); letter-spacing: .14em; color: var(--accent); margin-bottom: 8px; }}
h2 {{ font-size: 1.35rem; margin: 2.4rem 0 .6rem; padding-top: .8rem; border-top: 1px solid var(--rule); }}
h3 {{ font-size: 1.05rem; margin: 1.6rem 0 .4rem; }}
p, li {{ max-width: 78ch; }}
a {{ color: var(--accent); }}
a:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 2px; }}
code {{ font-family: var(--mono); font-size: .86em; background: var(--code); padding: .08em .3em; border-radius: 3px; }}
pre {{ background: var(--code); padding: 12px 14px; overflow-x: auto; border-radius: 4px; }}
pre code {{ background: none; padding: 0; }}
.tw {{ overflow-x: auto; margin: .8rem 0 1.2rem; }}
table {{ border-collapse: collapse; font-size: 13px; min-width: 100%; font-variant-numeric: tabular-nums; }}
th, td {{ border-bottom: 1px solid var(--rule); padding: 6px 10px; text-align: left; vertical-align: top; }}
th {{ font-family: var(--display); font-size: 12px; letter-spacing: .04em; text-transform: uppercase; color: var(--muted); border-bottom: 2px solid var(--rule); }}
td strong {{ color: var(--ok); }}
aside h2 {{ border: 0; margin: 0 0 .6rem; padding: 0; font-size: 1rem; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); }}
aside p {{ color: var(--muted); margin: 0 0 1rem; }}
.grp h3 {{ font: 600 12px var(--mono); margin: 1rem 0 .3rem; color: var(--fg); }}
.grp ul {{ list-style: none; margin: 0; padding: 0; }}
.grp li {{ font-family: var(--mono); font-size: 12px; padding: 2px 0; word-break: break-all; }}
.sz {{ color: var(--muted); }}
</style>
<div class="wrap">
<main>{body}</main>
<aside><h2>Files</h2><p>Every deliverable is served beside this page; open a file to view or save it.</p>{''.join(idx)}</aside>
</div>
"""
open(out, 'w').write(page)
print(out, len(files), 'files')

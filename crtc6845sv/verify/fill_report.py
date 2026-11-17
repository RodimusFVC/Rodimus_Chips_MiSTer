#!/usr/bin/env python3
"""Fill the {{...}} result slots in REPORT.md from verify/results (run from verify/)."""
import re, glob, collections, sys

def lockstep(pattern):
    tot = collections.Counter()
    regs = collections.Counter()
    n = 0
    for f in glob.glob(pattern):
        t = open(f).read()
        m = re.search(r'seed \d+ cycles (\d+) clkens (\d+) episodes (\d+) writes (\d+) reads (\d+) rewrites (\d+) mid_resets (\d+)', t)
        if not m: continue
        n += 1
        for k, v in zip(['cycles', 'clkens', 'episodes', 'writes', 'reads', 'rewrites', 'resets'], m.groups()): tot[k] += int(v)
        tot['dut'] += int(re.search(r'dut_vs_fixed_mismatches (\d+)', t).group(1))
        m = re.search(r'stock_vs_fixed_mismatches (\d+) \(in adjust class: R4=127 wrap (\d+), R6>R4\+1 (\d+); OUTSIDE class (\d+)', t)
        for k, v in zip(['stk', 'wrap', 'r6', 'out'], m.groups()): tot[k] += int(v)
        for k, v in re.findall(r'stock diff regs (.+?) (\d+)\n', t): regs[k] += int(v)
    return n, tot, regs

def f(x): return f"{x:,}".replace(",", " ")

rep = open('../REPORT.md').read()
n, t, regs = lockstep('results/lockstep_final_seed*.log')
if n:
    rep = rep.replace('{{FINAL_LOCKSTEP}}', f"**0** in {f(t['cycles'])} CLOCKs ({f(t['clkens'])} CLKENs, {f(t['episodes'])} episodes)"
                      if t['dut'] == 0 else f"**{t['dut']} MISMATCHES**")
    rep = rep.replace('| 16 seeds x 60 M (final RTL) | {{FINAL_ROW}} |',
                      f"| 16 seeds x 60 M (final RTL) | {f(t['cycles'])} | {f(t['clkens'])} | {f(t['episodes'])} | "
                      f"{f(t['writes'])} / {f(t['reads'])} / {f(t['rewrites'])} | {f(t['resets'])} | **{t['dut']}** |")
    open('results/stock_diff_by_registers.txt', 'w').write(
        f"stock-vs-fixed differing clock-phases on the final-RTL run, by the row counter and R6 when the adjust condition held (R4 / R5 as they were then); total {t['stk']}, "
        f"outside the adjust class {t['out']}\n" + "".join(f"{k}  {v}\n" for k, v in sorted(regs.items())))
    rep = rep.replace('The per-(R4, R5, R6) list of every difference is in `verify/results/lockstep_final_seed*.log` ("stock diff regs").',
                      f"Final-RTL run: {f(t['stk'])} differing clock-phases, {t['out']} outside the class, over {len(regs)} distinct "
                      f"(R4, R5, R6) settings, listed in `verify/results/stock_diff_by_registers.txt`.")

# oracle
pairs = collections.OrderedDict()
cur = None
for line in open('results/variants_random_summary.txt'):
    m = re.match(r'== (.+?): all knobs -> (\d+) char mismatches / (\d+) chars, (\d+) read mismatches / (\d+) reads, (\d+) frames', line)
    if m:
        cur = m.group(1).strip(); pairs[cur] = {'all': m.groups()[1:], 'k': collections.OrderedDict()}; continue
    m = re.match(r'\s+-(\S+)\s+char mism\s+(\d+)\s+read mism\s+(\d+)\s+\[(.*)\]', line)
    if m and cur: pairs[cur]['k'][m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4))
fleetp = collections.OrderedDict()
for line in open('results/variants_fleet_summary.txt'):
    m = re.match(r'== (.+?): all knobs -> (\d+) char mismatches / (\d+) chars, (\d+) read mismatches / (\d+) reads', line)
    if m: fleetp[m.group(1).strip()] = m.groups()[1:]
allzero = all(p['all'][0] == '0' and p['all'][2] == '0' for p in pairs.values())
chars = sum(int(p['all'][1]) for p in pairs.values()); reads = sum(int(p['all'][3]) for p in pairs.values())
first = next(iter(pairs.values()))['all']
rep = rep.replace('{{ORACLE_TOTALS}}', (f"Random + directed run: {f(int(first[1]))} characters and {f(int(first[3]))} reads per model, "
                  f"{f(chars)} characters over all pairs; mismatches {'0' if allzero else 'NONZERO'}"))
rows = ["| Pair | Characters | Frames | Reads | Mismatches (all knobs) | Knobs (characters / reads that differ when reverted alone) |",
        "|---|---|---|---|---|---|"]
for name, p in pairs.items():
    ks = "; ".join(f"`{k}` {f(c)}" + (f" / {f(r)}r" if r else "") for k, (c, r, _) in p['k'].items())
    rows.append(f"| {name} | {f(int(p['all'][1]))} | {f(int(p['all'][4]))} | {f(int(p['all'][3]))} | "
                f"**{p['all'][0]} / {p['all'][2]}** | {ks} |")
rows.append("")
rows.append("Fleet tables through the same oracle: " + "; ".join(f"{k}: {v[0]} / {v[2]}" for k, v in fleetp.items()) + " (character / read mismatches, all knobs).")
rep = rep.replace('{{ORACLE_TABLE}}', "\n".join(rows))
v0 = pairs.get('V0 fleet  vs MAME hd6845s') or next(iter(pairs.values()))
v0m = pairs.get('V0 fleet  vs MAME mc6845', v0)
for k in ['vs_r2', 'hsw0_none', 'engine_t0', 'de_fleet', 'il_fleet', 'cursor_fleet', 'blink_ds', 'skew', 'hs_cont', 'vs_hdl', 'first_ma0']:
    c = v0['k'].get(k, (0, 0, ''))[0]
    rep = rep.replace('{{K_%s}}' % k, f(c))
rep = rep.replace('{{K_vsw_prog}}', f(v0m['k'].get('vsw_prog', (0, 0, ''))[0]) + " (vs mc6845)")
rep = rep.replace('{{K_lp_now}}', f(v0['k'].get('lp_now', (0, 0, ''))[1]))

# fleet
frows = []
for line in open('results/fleet.txt'):
    m = re.match(r'(\S+)\s+(.+?)\s+clocks\s+(\d+) frames\s+(\d+) reads\s+(\d+) resets (\d+)\s+dut-vs-fixed mismatches (\d+)\s+stock-vs-fixed diffs (\d+)', line)
    if m:
        g, src, clk, fr, rd, rs, mm, st = m.groups()
        frows.append(f"| {g} | {src} | {f(int(clk))} | {fr} | **{mm}** | {f(int(st))} |")
rep = rep.replace('{{FLEET_ROWS}}', "\n".join(frows))
vdc = sys.argv[1] if len(sys.argv) > 1 else None
if vdc: rep = rep.replace('{{VDC_STATUS}}', vdc)
open('../REPORT.md', 'w').write(rep)
left = re.findall(r'\{\{[A-Z_a-z0-9]+\}\}', rep)
print("unfilled:", left)

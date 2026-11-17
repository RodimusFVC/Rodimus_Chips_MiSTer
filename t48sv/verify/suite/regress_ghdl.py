#!/usr/bin/env python3
"""Run the T48 verification suite on the UNMODIFIED VHDL reference with GHDL
(native VHDL simulation of the upstream testbenches), mirroring
sw/run_regression.pl. Records PASS / FAIL and the simulation time of the
result for every (cell, testbench).

regress_ghdl.py <name> <run_dir> <verif_dir> <bench_dir> <vhdl dirs...> [--tbs t39,t48,gen]
"""
import os, re, subprocess, sys, glob, json

HERE = os.path.dirname(os.path.abspath(__file__))
ASM = os.path.join(HERE, '..', 'asm', 't48asm.py')
TBS = {'gen': 'tb', 't48': 'tb_t8048', 't39': 'tb_t8039', 't41': 'tb_t8041', 't41a': 'tb_t8041a',
       't42ah': 'tb_t8042ah', 't21': 'tb_t8021', 't22': 'tb_t8022'}
IOX = {'gen': 'tb_t8243', 't48': 'tb_t8048_t8243'}
GHDL = 'ghdl-llvm'   # mcode traps time overflow in bench/if_timing.vhd; upstream CI uses LLVM too


def sh(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)


def main():
    args = sys.argv[1:]
    tbs = None
    link = []
    if '--link' in args:
        i = args.index('--link')
        link = args[i + 1].split()
        del args[i:i + 2]
    if '--tbs' in args:
        i = args.index('--tbs')
        tbs = args[i + 1].split(',')
        del args[i:i + 2]
    name, run, verif, bench, *vdirs = args
    run = os.path.abspath(run)
    os.makedirs(os.path.join(run, 'work'), exist_ok=True)
    files = []
    for d in vdirs + [bench]:
        if d.startswith('@'):
            files += [l.strip() for l in open(d[1:]) if l.strip()]
        else:
            files += sorted(glob.glob(os.path.join(d, '*.vhd')))
    files = [f for f in files if not f.endswith('-c.vhd')]
    r = sh([GHDL, '-i', '--std=93c', '-frelaxed', '--workdir=work'] + files, run)
    if r.returncode:
        sys.exit(r.stderr)
    tags = tbs or list(TBS)
    built = set()
    for t in set(tags):
        for ent in {TBS.get(t), IOX.get(t)} - {None}:
            r = sh([GHDL, '-m', '--std=93c', '-frelaxed', '--workdir=work'] + ['-Wl,' + l for l in link] + [ent], run)
            if r.returncode == 0:
                built.add(ent)
            else:
                print('cannot build %s: %s' % (ent, r.stderr.strip().splitlines()[-1:]))
    cells = sorted({os.path.dirname(p) for p in glob.glob(os.path.join(verif, '*_box', '**', '*.asm'),
                                                         recursive=True)})
    results = []
    for cell in cells:
        rel = os.path.relpath(cell, verif)
        asm = glob.glob(os.path.join(cell, '*.asm'))[0]
        for f in glob.glob(os.path.join(run, '*.hex')):
            os.remove(f)
        r = sh(['python3', ASM, asm, '-I', os.path.join(verif, 'include'),
                '--hex', 'image.hex',
                '--ihex', 'rom_t3x_ext.hex:0-4095',
                '--ihex', 'rom_t48.hex:0-1023', '--ihex', 'rom_t48_ext.hex:1024-4095',
                '--ihex', 'rom_t49.hex:0-2047', '--ihex', 'rom_t49_ext.hex:2048-4095:a'], run)
        if r.returncode == 0:
            img = open(os.path.join(run, 'image.hex')).read().split()
            for aw in (10, 11, 12):
                open(os.path.join(run, 'rom%d.hex' % aw), 'w').write('\n'.join(img[:1 << aw]) + '\n')
        if r.returncode:
            results.append(dict(cell=rel, tb='asm', result='ASM-ERROR', msg=r.stderr.strip()))
            continue
        io_exp = os.path.exists(os.path.join(cell, 'io_exp'))
        for tag in tags:
            ent = (IOX if io_exp else TBS).get(tag)
            if not ent or os.path.exists(os.path.join(cell, 'no_' + tag)):
                continue
            if ent not in built:
                continue
            r = sh(['./' + ent, '--assert-level=error', '--stop-time=20ms'], run)
            out = r.stdout + r.stderr
            m = re.search(r'@(\d+)(ps|ns|fs).*Simulation Result: (PASS|FAIL)', out)
            if m:
                t = int(m.group(1)) * {'fs': 1e-6, 'ps': 1e-3, 'ns': 1}[m.group(2)]
                results.append(dict(cell=rel, tb=tag, result=m.group(3), time_ns=t))
            else:
                results.append(dict(cell=rel, tb=tag, result='NO-RESULT', msg=out[-300:]))
            print('%-40s %-6s %s' % (rel, tag, results[-1]['result']), flush=True)
    json.dump(results, open(os.path.join(run, 'results_%s.json' % name), 'w'), indent=1)
    n = len(results)
    p = sum(1 for x in results if x['result'] == 'PASS')
    print('SUITE %s: %d/%d PASS' % (name, p, n))


if __name__ == '__main__':
    main()

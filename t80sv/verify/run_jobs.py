#!/usr/bin/env python3
"""Run the verification job list on N workers; resumable (a job whose log ends in a pass line is skipped).

usage: run_jobs.py <build dir> <results dir> <job set> [workers]
job sets: random, sweep, zexlock, zexsolo_dut, zexsolo_ref, i8080, fleet, all

Every job is one simulator invocation; its log is <results>/<job>.log and its exit status decides pass / fail.
"""
import glob, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from configs import CONFIGS, FLEET, FLEET_WRAPPERS, mode_of

BUILD, RES, SET = sys.argv[1], sys.argv[2], sys.argv[3]
WORKERS = int(sys.argv[4]) if len(sys.argv) > 4 else 4
HERE = os.path.dirname(os.path.abspath(__file__))
ZEXDIR = os.environ.get('ZEX_SPLIT', os.path.join(RES, '..', 'zex', 'split'))
I8080DIR = os.environ.get('I8080_TESTS', '')
os.makedirs(RES, exist_ok=True)


def sim(cfg):
    return os.path.join(BUILD, cfg, 'obj', 'sim')


def jobs_random():
    j = []
    for c in list(CONFIGS) + list(FLEET_WRAPPERS):
        fleet = c in FLEET
        seeds = range(1, 5) if fleet else (range(1, 3) if c not in FLEET_WRAPPERS else range(1, 2))
        n = 25_000_000 if fleet else 5_000_000
        for s in seeds:
            j.append((f'random_{c}_s{s}', [sim(c), 'random', str(s), str(n)], c))
    return j


def jobs_sweep():
    j = []
    for c in CONFIGS:
        m = mode_of(c)
        parts = 16 if m < 2 else (4 if m == 3 else 2)
        for p in range(parts):
            j.append((f'sweep_{c}_p{p}', [sim(c), 'sweep', str(p), str(parts), '64'], c))
    return j


def zex_files():
    return sorted(glob.glob(os.path.join(ZEXDIR, '*.com')))


def jobs_zexlock():
    # every ZEX test, lockstep, first 4M cycles, on the Z80-mode fleet configurations
    j = []
    for c in ['t80s_m0_t1_w1', 't80pa_m0', 'phx_t80pa_m0', 't80sed', 't80se_m0_t0_w1']:
        for f in zex_files():
            t = os.path.splitext(os.path.basename(f))[0]
            j.append((f'zexlock_{c}_{t}', [sim(c), 'com', f, '0', '4000000'], c))
    return j


def jobs_zexsolo(side):
    c = 't80s_m0_t1_w1'
    return [(f'zexsolo_{side}_{os.path.splitext(os.path.basename(f))[0]}',
             [os.path.join(BUILD, f'{c}_{side}', 'obj', 'sim'), 'comfast', f, '0'], c) for f in zex_files()]


def jobs_i8080():
    j = []
    if not I8080DIR:
        return j
    progs = ['TST8080.COM', 'CPUTEST.COM', '8080PRE.COM', '8080EXM.COM']
    for c in [x for x in CONFIGS if mode_of(x) == 2] + ['phx_t80pa_m0_i8080', 'phx_t80_m0_w1_i8080']:
        for p in progs:
            lim = '400000000' if p == '8080EXM.COM' else '2000000000'
            cc = c.replace('_i8080', '')
            args = [sim(cc), 'com', os.path.join(I8080DIR, p), '0', lim]
            if c.endswith('_i8080'):
                args = ['env', 'FORCE_I8080=1'] + args
            j.append((f'i8080_{c}_{p.split(".")[0]}', args, cc))
    return j


SETS = {
    'random': jobs_random, 'sweep': jobs_sweep, 'zexlock': jobs_zexlock, 'i8080': jobs_i8080,
    'zexsolo_dut': lambda: jobs_zexsolo('dut'), 'zexsolo_ref': lambda: jobs_zexsolo('ref'),
}


def passed(log):
    try:
        t = open(log).read()
    except OSError:
        return False
    return 'EXIT 0\n' in t[-200:]


def run(job):
    name, args, cfg = job
    log = os.path.join(RES, name + '.log')
    if passed(log):
        return name, 0, 0.0, True
    if not os.path.exists(args[0] if args[0] != 'env' else args[2]):
        open(log, 'w').write(f'missing simulator {args}\nEXIT 98\n')
        return name, 98, 0.0, False
    t0 = time.time()
    with open(log, 'w') as f:
        f.write(' '.join(args) + '\n')
        f.flush()
        env = dict(os.environ, COV_OUT=log[:-4] + '.cov')
        r = subprocess.run(['nice', '-n', '5'] + args, stdout=f, stderr=subprocess.STDOUT, env=env)
        rc = r.returncode
        if rc == 4 and name.startswith(('zexlock_', 'i8080_')):
            rc = 0     # bounded lockstep prefix: cycle limit reached with no mismatch
        f.write(f'\nEXIT {rc}\n')
    return name, rc, time.time() - t0, False


def main():
    sets = list(SETS) if SET == 'all' else SET.split(',')
    jobs = [j for s in sets for j in SETS[s]()]
    print(f'{len(jobs)} jobs', flush=True)
    fails = 0
    with ThreadPoolExecutor(WORKERS) as ex:
        for name, rc, dt, skipped in ex.map(run, jobs):
            if rc:
                fails += 1
            print(f'{"PASS" if rc == 0 else "FAIL"} {name} {"(done earlier)" if skipped else f"{dt:.0f}s"}', flush=True)
    print(f'{len(jobs) - fails} passed, {fails} failed', flush=True)
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())

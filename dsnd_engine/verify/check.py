# Runs the dsnd_engine checks on the binaries the Makefile built in <out>; exit 0 only if every check passes.
#   check.py <out> [--fleet <core> ...]
#   random programs (all ops 0-33, all 8 sources) and the directed programs (dsnd_optest.py) at every TICK: 0 mismatches
#   noise_guard and noise_plain must differ (the guard state is reached), control mutants must report mismatches,
#   dsnd_run (model only) must write the lockstep's WAV and summary for every directed program,
#   --fleet: every unique MRA index-5 program in /Work/Projects/Arcade-<core>_MiSTer/releases at that core's TICK
import glob, hashlib, os, random, re, subprocess, sys
from pathlib import Path

out = Path(sys.argv[1])
fleet = sys.argv[sys.argv.index("--fleet") + 1:] if "--fleet" in sys.argv else []
here = Path(__file__).resolve().parent
proj = here.parents[2]
ticks = sorted(int(p.parent.name[1:]) for p in out.glob("t*/Vdsnd_engine"))
fails = []


def run(exe, *args):
    r = subprocess.run([str(exe), *args], capture_output=True, text=True)
    m = re.search(r"lockstep: (\d+) samples, (\d+) mismatches", r.stdout)
    return (int(m.group(1)), int(m.group(2))) if m else (0, -1)


def expect(label, exe, *args, fail=False):
    n, bad = run(exe, *args)
    ok = (bad > 0) if fail else (bad == 0 and n > 0)
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {n} samples, {bad} mismatches{' (must be > 0)' if fail else ''}")
    if not ok:
        fails.append(label)


progs = out / "progs"
progs.mkdir(exist_ok=True)
subprocess.run([sys.executable, "-I", str(here / "dsnd_optest.py"), str(progs)], check=True, capture_output=True)
directed = sorted(progs.glob("*.bin"))

for t in ticks:
    exe = out / f"t{t}" / "Vdsnd_engine"
    expect(f"TICK {t} random programs", exe, "--fuzz=300")
    for p in directed:
        expect(f"TICK {t} {p.stem}", exe, f"--prog={p}", "--len=2")
    same = 0
    for p in directed:
        args = [f"--prog={p}", "--len=2", "--ev=0.5:3:5a", "--ev=1.2:7:c3"]
        a = subprocess.run([str(exe), *args, f"--wav={out}/ls.wav"], capture_output=True, text=True).stdout.splitlines()[0]
        b = subprocess.run([str(out / f"t{t}" / "dsnd_run"), *args, f"--wav={out}/run.wav"], capture_output=True, text=True).stdout.splitlines()[0]
        same += a == b and (out / "ls.wav").read_bytes() == (out / "run.wav").read_bytes()
    ok = same == len(directed)
    print(f"{'ok  ' if ok else 'FAIL'} TICK {t} dsnd_run = lockstep WAV + summary: {same} / {len(directed)}")
    if not ok:
        fails.append(f"TICK {t} dsnd_run")

exe = out / f"t{ticks[0]}" / "Vdsnd_engine"
w = {}
for k in ("guard", "plain"):
    run(exe, f"--prog={progs}/noise_{k}.bin", "--len=2", f"--wav={out}/noise_{k}.wav")
    w[k] = (out / f"noise_{k}.wav").read_bytes()
ok = w["guard"] != w["plain"]
print(f"{'ok  ' if ok else 'FAIL'} NOISE guard reached: noise_guard {'differs from' if ok else 'equals'} noise_plain")
if not ok:
    fails.append("NOISE guard reached")

expect("control noguard on noise_guard", out / "mut_noguard" / "Vdsnd_engine", f"--prog={progs}/noise_guard.bin", "--len=2", fail=True)
expect("control nooutr on random programs", out / "mut_nooutr" / "Vdsnd_engine", "--fuzz=300", fail=True)

for core in fleet:
    root = proj / f"Arcade-{core}_MiSTer"
    tick = 832
    for f in glob.glob(f"{root}/rtl/*.sv"):
        m = re.search(r"dsnd_engine\s*#\(\s*\.TICK\((\d+)\)", open(f).read())
        if m:
            tick = int(m.group(1))
    exe = out / f"t{tick}" / "Vdsnd_engine"
    seen = {}
    for d, _, fs in os.walk(root / "releases"):
        for f in fs:
            if not f.endswith(".mra"):
                continue
            m = re.search(r'<rom index="5">(.*?)</rom>', open(os.path.join(d, f), encoding="utf-8", errors="replace").read(), re.S)
            if m:
                data = bytes.fromhex("".join("".join(re.findall(r"<part>(.*?)</part>", m.group(1), re.S)).split()))
                seen.setdefault(hashlib.md5(data).hexdigest()[:8], data)
    fp = out / "fleet" / core
    fp.mkdir(parents=True, exist_ok=True)
    rng = random.Random(7)
    evf = fp / "events.txt"
    evf.write_text("".join(f"{t / 5:.2f} {s} {rng.randrange(256):x}\n" for t in range(1, 40) for s in range(8)))
    print(f"     {core}: {len(seen)} unique programs, TICK {tick}")
    for h, data in sorted(seen.items()):
        (fp / f"{h}.bin").write_bytes(data)
        expect(f"{core} {h}", exe, f"--prog={fp}/{h}.bin", "--len=8", f"--evfile={evf}")

print(f"\n{'PASS' if not fails else 'FAIL'}: {len(fails)} failed" + (f" ({', '.join(fails)})" if fails else ""))
sys.exit(1 if fails else 0)

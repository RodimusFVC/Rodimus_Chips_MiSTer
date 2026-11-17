# Control mutants: copy dsnd_lockstep.cpp + dsnd_model.h to <dir> with one model behaviour removed, so check.py can
# prove the test that covers it fails without it.  usage: mutate.py <mutant> <dir>
#   noguard  NOISE b[2] lock-up guard gone     (caught by noise_guard.bin)
#   nooutr   op 33 OUTR adds nothing to out_r   (caught by random programs)
import sys
from pathlib import Path

name, out = sys.argv[1], Path(sys.argv[2])
here = Path(__file__).resolve().parent
model = (here / "dsnd_model.h").read_text()
cut = {"noguard": "if ((b & 4) && (l & 0x1000001Fu) == 0) nb = 1;",
       "nooutr": "mix_r = (int32_t)((uint32_t)mix_r + (uint32_t)acc); "}[name]
assert model.count(cut) == 1, f"{name}: mutation site not found once in dsnd_model.h"
out.mkdir(parents=True, exist_ok=True)
(out / "dsnd_model.h").write_text(model.replace(cut, ""))
(out / "dsnd_lockstep.cpp").write_text((here / "dsnd_lockstep.cpp").read_text())

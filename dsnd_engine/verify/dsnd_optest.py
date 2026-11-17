# Directed RTL-vs-model programs for the ops random programs cannot reach reliably.
#   EXP / RCP: every sample feeds a fresh pseudo-random input (LCG in state memory) and outputs a 7-bit window of the
#   result, so each result bit reaches the 16-bit output in one of the window programs (exp_w<k>, rcp_w<k>).
#   NOISE b[2] (lock-up guard): noise_guard / noise_plain output the LFSR 0 bit stream as +-0.5 with and without the
#   guard; the guard state (bits 28 and 4:0 all 0) comes round within the first few seconds, so the two streams must
#   differ and each must lockstep with 0 mismatches.
# usage: dsnd_optest.py <out dir>   (opcodes from RodimusCoresMaster_MiSTer/tools/dsnd.py, the fleet assembler)
import os, sys, struct
from pathlib import Path
sys.path.insert(0, os.environ.get("DSND_TOOLS", str(Path(__file__).resolve().parents[2].parent / "RodimusCoresMaster_MiSTer" / "tools")))
from dsnd import OPS

out = sys.argv[1]


def assemble(code):
    return b"".join(struct.pack("<Q", o << 56 | a << 48 | b << 40 | (imm & 0xFFFFFFFF)) for o, a, b, imm in code)


def prog(kind, window):
    code = []
    op = lambda n, a=0, b=0, imm=0: code.append((OPS[n] if n in OPS else n, a, b, imm))
    # x = x * 1103515245 + 12345 (wrapping: MULI keeps (acc * imm) >> 24, so multiply by 2^24 pieces)
    op("LD", 0); op("MULI", imm=1103515245 & 0x7FFFFFFF); op("ADDI", imm=12345 + 0x1357); op("ST", 0)
    if kind == "exp":
        op("MULI", imm=33 << 18)                 # x -> about -16.5 .. 16.5 (Q24), covers both clamps
        op("EXP")
    else:
        op("MULI", imm=40 << 18); op("ADDI", imm=-(12 << 24)); op("EXP")   # log-uniform magnitude 2^-32 .. 2^8
        op("ST", 1); op("LD", 0); op("CMPI", imm=0); op("LD", 1)
        op("SKF", imm=1); op("MULI", imm=-(1 << 24))                        # random sign
        op("RCP")
    for _ in range(window // 6):                 # shift the window up: x 64 per MULI (wraps)
        op("MULI", imm=1 << 30)
    if window % 6:
        op("MULI", imm=1 << (24 + window % 6))
    op("MULI", imm=1 << 8)                       # top 16 bits -> mix; OUT >> 9 leaves 7 bits + sign
    op("OUT"); op("END")
    return assemble(code)


def noise(guard):
    return assemble([(OPS["NOISE"], 0, 4 if guard else 0, 0), (OPS["LDI"], 0, 0, -(1 << 23)),
                     (OPS["LDIF"], 0, 0, 1 << 23), (OPS["OUT"], 0, 0, 0), (OPS["END"], 0, 0, 0)])


for kind in ("exp", "rcp"):
    for w in range(0, 32, 6):
        open(f"{out}/{kind}_w{w}.bin", "wb").write(prog(kind, w))
open(f"{out}/noise_guard.bin", "wb").write(noise(True))
open(f"{out}/noise_plain.bin", "wb").write(noise(False))
print("written")

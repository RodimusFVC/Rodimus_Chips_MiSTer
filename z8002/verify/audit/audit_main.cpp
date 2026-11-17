// z8002 EXHAUSTIVE opcode-coverage audit (2026-08-09).
//
// Feeds every one of the 65536 possible first instruction words to the REAL
// production rtl/cpu/z8002/z8002.sv and records whether it asserts dbg_illegal.
// The oracle is MAME's own z8002 dispatch table (Useful Stuff/mame/z8000/
// z8000tbl.hxx): any word whose handler is not `zinvalid` is a real Z8002
// instruction our core must decode.
//
// This is deliberately EXHAUSTIVE rather than trace-derived: a trace-derived set
// only proves the paths that happened to execute, which is exactly how the
// CP-DIRECT-FIX-2026-08-09 hang (4D01) survived earlier passes.
//
// Output: ours_illegal.txt, one 4-hex-digit word per line.
#include <cstdio>
#include <cstdint>
#include <verilated.h>
#include "Vz8002_optest_tb.h"
#include "Vz8002_optest_tb_z8002_optest_tb.h"

static Vz8002_optest_tb *top;
static inline int W(int byte_addr) { return byte_addr >> 1; }
static void tick() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vz8002_optest_tb;

    FILE* f = fopen("ours_illegal.txt", "w");
    long n_ill = 0;

    for (uint32_t op = 0; op <= 0xFFFF; op++) {
        // Fresh memory each candidate: vectors + the opcode + benign operand words.
        // Operands are 0x0000 so any imm/addr fetch lands on harmless low memory.
        for (int i = 0; i < 32768; i++) top->z8002_optest_tb->mem[i] = 0;
        top->z8002_optest_tb->mem[W(2)] = 0x0000;   // FCW: flags clear, non-segmented
        top->z8002_optest_tb->mem[W(4)] = 0x0010;   // reset PC
        top->z8002_optest_tb->mem[W(0x10)] = (uint16_t)op;

        top->reset_n = 0;
        for (int i = 0; i < 4; i++) tick();
        top->reset_n = 1;

        // Run until the first instruction retires or the core flags illegal.
        // dbg_illegal is latched in z8002.sv, so sampling any tick after it sets is fine.
        bool ill = false;
        for (int i = 0; i < 64; i++) {
            tick();
            if (top->dbg_illegal) { ill = true; break; }
            if (top->dbg_retire)  break;
        }
        if (ill) { fprintf(f, "%04X\n", op); n_ill++; }

        if ((op & 0x0FFF) == 0x0FFF) { printf("  ...%04X (%ld illegal so far)\n", op, n_ill); fflush(stdout); }
    }
    fclose(f);
    printf("\nDONE: %ld / 65536 words assert dbg_illegal -> ours_illegal.txt\n", n_ill);
    return 0;
}

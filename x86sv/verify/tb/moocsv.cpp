// Copyright (C) 2026 Rodimus
// MOO test table for analysis: moocsv <file.MOO.gz>
// One line per test: idx qlen bytes cycles init-regs(14) final-regs(14, unchanged filled in) | events
#include "moo.h"
#include <cstdio>

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    moo::File f = moo::load(argv[1]);
    if (!f.error.empty()) { fprintf(stderr, "%s\n", f.error.c_str()); return 1; }
    static const char bc[] = "iIOrwhC.";
    for (auto &t : f.tests) {
        printf("%u %zu ", t.index, t.init.queue.size());
        for (auto b : t.bytes) printf("%02X", b);
        printf(" %zu", t.cycles.size());
        for (int r = 0; r < moo::R_NUM; r++) printf(" %04X", t.init.regs[r]);
        for (int r = 0; r < moo::R_NUM; r++) printf(" %04X", (t.fina.mask & (1 << r)) ? t.fina.regs[r] : t.init.regs[r]);
        printf(" |");
        uint32_t prev = t.cycles.empty() ? 0 : t.cycles[0].addr;
        for (size_t c = 0; c < t.cycles.size(); c++) {
            const moo::Cycle &y = t.cycles[c];
            int n = (int)c - 1;
            if (y.qop == 1) printf(" F%d", n);
            if (y.qop == 3) printf(" S%d", n);
            if (y.qop == 2) printf(" E%d", n);
            if (y.ts == 1) printf(" %c%zu", bc[y.bus & 7], c);
            if (y.ts == 0 && c > 0 && y.addr != prev) printf(" a%zu", c);
            prev = y.addr;
        }
        printf("\n");
    }
    return 0;
}

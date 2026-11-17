// Copyright (C) 2026 Rodimus
// MOO test viewer: mooview <file.MOO.gz> [first] [count] [w]   (w: BHE and 16-bit data)
#include "moo.h"
#include <cstdio>
#include <cstdlib>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: mooview file.MOO.gz [first] [count]\n"); return 2; }
    moo::File f = moo::load(argv[1]);
    if (!f.error.empty()) { fprintf(stderr, "%s\n", f.error.c_str()); return 1; }
    size_t first = argc > 2 ? strtoul(argv[2], 0, 0) : 0, cnt = argc > 3 ? strtoul(argv[3], 0, 0) : 1;
    bool wide = argc > 4 && argv[4][0] == 'w';
    for (size_t i = first; i < f.tests.size() && i < first + cnt; i++) {
        const moo::Test &t = f.tests[i];
        printf("#%u %s  bytes:", t.index, t.name.c_str());
        for (auto b : t.bytes) printf(" %02X", b);
        printf("\n init:");
        for (int r = 0; r < moo::R_NUM; r++)
            if (t.init.mask & (1 << r)) printf(" %s=%04X", moo::reg_name[r], t.init.regs[r]);
        printf("\n  q:");
        for (auto b : t.init.queue) printf(" %02X", b);
        printf("  ram:");
        for (auto &m : t.init.ram) printf(" %05X=%02X", m.first, m.second);
        printf("\n final:");
        for (int r = 0; r < moo::R_NUM; r++)
            if (t.fina.mask & (1 << r)) printf(" %s=%04X", moo::reg_name[r], t.fina.regs[r]);
        printf("\n  q:");
        for (auto b : t.fina.queue) printf(" %02X", b);
        printf("  ram:");
        for (auto &m : t.fina.ram) printf(" %05X=%02X", m.first, m.second);
        printf("\n");
        for (size_t c = 0; c < t.cycles.size(); c++)
            printf("  %3zu %s\n", c, (wide ? moo::fmtw(t.cycles[c]) : moo::fmt(t.cycles[c])).c_str());
    }
    return 0;
}

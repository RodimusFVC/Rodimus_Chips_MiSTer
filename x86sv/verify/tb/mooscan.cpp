// Copyright (C) 2026 Rodimus
// MOO trace event summary: mooscan <file.MOO.gz> [max]
// One line per test: queue reads (F/S@cycle), bus cycles (type@T1), aborted-fetch Ti cycles (a@), length.
#include "moo.h"
#include <cstdio>
#include <cstdlib>

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    moo::File f = moo::load(argv[1]);
    if (!f.error.empty()) { fprintf(stderr, "%s\n", f.error.c_str()); return 1; }
    size_t mx = argc > 2 ? strtoul(argv[2], 0, 0) : f.tests.size();
    static const char bc[] = "iIOrwhC.";
    for (size_t i = 0; i < f.tests.size() && i < mx; i++) {
        const moo::Test &t = f.tests[i];
        printf("%5u %c %-34s|", t.index, t.init.queue.empty() ? 'n' : 'p', t.name.c_str());
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
        printf(" |%zu\n", t.cycles.size());
    }
    return 0;
}

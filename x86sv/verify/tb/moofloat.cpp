// Copyright (C) 2026 Rodimus
// Floating-bus survey: moofloat <file.MOO.gz>...
// Lists Ti clocks whose AD value changes although no bus cycle, abort or IP-correction clock is near:
// file test clock idle-clocks-since-T4 old new
#include "moo.h"
#include <cstdio>

int main(int argc, char **argv) {
    for (int a = 1; a < argc; a++) {
        moo::File f = moo::load(argv[a]);
        if (!f.error.empty()) { fprintf(stderr, "%s\n", f.error.c_str()); continue; }
        for (auto &t : f.tests) {
            int last_t4 = -1000;
            for (size_t c = 1; c < t.cycles.size(); c++) {
                const moo::Cycle &y = t.cycles[c], &p = t.cycles[c - 1];
                if (p.ts == 4) last_t4 = (int)c - 1;
                if (y.ts != 0 || p.ts != 0) continue;
                if (y.addr == p.addr) continue;
                int idle = (int)c - last_t4;
                // aborted fetch / correction clocks change the upper bits; report only low-byte-only changes
                if (((y.addr ^ p.addr) & 0xFFF00) == 0)
                    printf("%s %u %zu %d %05X %05X\n", argv[a], t.index, c, idle, p.addr, y.addr);
            }
        }
    }
    return 0;
}

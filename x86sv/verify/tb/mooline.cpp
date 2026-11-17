// Copyright (C) 2026 Rodimus
// MOO compact trace: mooline <file.MOO.gz>
// One line per test: idx p/n bytes | bus per clock (. Ti, a Ti with a new address, T1 = C R W I O A H by type, 2 3 4 T2-T4)
// | queue op per clock of the pop (- F S E; the QS lines report it one clock later) | name; both start at clock -1
#include "moo.h"
#include <cstdio>

int main(int argc, char **argv) {
    if (argc < 2) return 2;
    moo::File f = moo::load(argv[1]);
    if (!f.error.empty()) { fprintf(stderr, "%s\n", f.error.c_str()); return 1; }
    static const char t1c[] = "AIORWHC.";
    static const char qc[] = "-FES";
    for (auto &t : f.tests) {
        printf("%u %c ", t.index, t.init.queue.empty() ? 'n' : 'p');
        for (auto b : t.bytes) printf("%02X", b);
        std::string bs = "_", qs(1, t.cycles.empty() ? '-' : qc[t.cycles[0].qop & 3]);
        uint32_t prev = t.cycles.empty() ? 0 : t.cycles[0].addr;
        for (size_t c = 0; c < t.cycles.size(); c++) {
            const moo::Cycle &y = t.cycles[c];
            char ch = '.';
            if (y.ts == 1) ch = t1c[y.bus & 7];
            else if (y.ts >= 2 && y.ts <= 4) ch = '0' + y.ts;
            else if (c > 0 && y.addr != prev) ch = 'a';
            prev = y.addr;
            bs += ch;
            qs += (c + 1 < t.cycles.size()) ? qc[t.cycles[c + 1].qop & 3] : 'F';
        }
        printf(" %s %s %s\n", bs.c_str(), qs.c_str(), t.name.c_str());
    }
    return 0;
}

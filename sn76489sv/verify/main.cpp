// main.cpp - drive tb with a write stream, record every tick (verify/run.sh, compared by model.py).
//   ./obj/Vtb <stim> <out prefix> <edges>
// stim: "<edge> <byte hex>" per write (wr_n low for that one edge; edge % 4 == 2). ce on edges % 4 == 0, rst on 0-9.
// <prefix>.ticks: per edge where any variant ticks: u32 edge, u8 tick mask, u32 outs (4 bits x 7), then the 7
//                 sound values (i16) after the following edge.
// <prefix>.ready: "<variant> <edge> <level>" per READY change (level after that edge).
#include "Vtb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <vector>
#include <utility>

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: Vtb <stim> <out prefix> <edges>\n"); return 1; }
    std::vector<std::pair<long, int>> w;
    FILE *f = fopen(argv[1], "r"); long e; int b;
    while (f && fscanf(f, "%ld %x", &e, &b) == 2) w.push_back({e, b});
    if (f) fclose(f);
    long n = atol(argv[3]);
    std::string pre = argv[2];
    FILE *ft = fopen((pre + ".ticks").c_str(), "wb"), *fr = fopen((pre + ".ready").c_str(), "w");
    Verilated::commandArgs(argc, argv);
    Vtb *t = new Vtb;
    t->clk = 0; t->rst = 1; t->ce = 0; t->wr_n = 1; t->din = 0; t->eval();
    size_t wi = 0; int rdy_d = 0x7f; bool pend = false; uint32_t rec_e = 0; uint8_t rec_m = 0; uint32_t rec_o = 0;
    for (long k = 0; k < n; k++) {
        t->rst = k < 10; t->ce = (k % 4) == 0;
        t->wr_n = 1;
        if (wi < w.size() && w[wi].first == k) { t->wr_n = 0; t->din = w[wi].second; wi++; }
        t->clk = 0; t->eval();
        uint8_t tm = t->tick;
        t->clk = 1; t->eval();
        if (pend) {                                       // sound after the edge that follows a tick
            fwrite(&rec_e, 4, 1, ft); fwrite(&rec_m, 1, 1, ft); fwrite(&rec_o, 4, 1, ft);
            for (int v = 0; v < 7; v++) {
                int s = (int)((t->sound[(11 * v) / 32] >> ((11 * v) % 32)) & 0x7ff);
                if ((11 * v) % 32 > 21) s = (int)(((uint64_t)t->sound[(11 * v) / 32 + 1] << 32 | t->sound[(11 * v) / 32]) >> ((11 * v) % 32)) & 0x7ff;
                int16_t sv = (int16_t)(s << 5) >> 5; fwrite(&sv, 2, 1, ft);
            }
            pend = false;
        }
        if (tm) { pend = true; rec_e = (uint32_t)k; rec_m = tm; rec_o = t->outs; }
        int rd = t->ready;
        for (int v = 0; v < 7; v++) if (((rd ^ rdy_d) >> v) & 1) fprintf(fr, "%d %ld %d\n", v, k, (rd >> v) & 1);
        rdy_d = rd;
    }
    fclose(ft); fclose(fr); delete t;
    printf("%zu writes, %ld edges\n", w.size(), n);
    return 0;
}

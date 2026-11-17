// Fleet scenarios: each game's CRTC table, write order, character clock and bus behaviour replayed through the
// lockstep model (crtc6845sv drop-in vs fixed vs stock), every output compared on every CLOCK.
#include "Vtb_lockstep.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <random>
#include <string>
#include <vector>

struct Game {
    std::string name, src;
    int r[16];
    bool ascending;      // write order R0..R13 (else R13..R0)
    int nregs;           // registers written (14 = R0..R13)
    int clk_div;         // CLOCKs per CLKEN
    int hold;            // CLOCKs ENABLE is held per access
    int frames;
    int yoyo;            // 1: rewrite R12/R13 every frame in vblank, 2: same, alternating flip ($3FE0)
    bool reads;          // host reads registers back (TMS board)
    int resets;          // board-switch resets during the run (Universal: chip held in reset while inactive)
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    std::vector<Game> G = {
        {"qix",        "MEASURED qix video ROM table",           {40,32,35,0x03,31,17,32,32,0,7,0,0,0x00,0x00,0,0}, false, 14, 32, 16, 30, 0, false, 0},
        {"qix2",       "assumed = qix table",                    {40,32,35,0x03,31,17,32,32,0,7,0,0,0x00,0x00,0,0}, false, 14, 32, 16, 10, 0, false, 0},
        {"slither",    "MEASURED (R0 first)",                    {40,32,35,0x03,31,17,32,32,0,7,0,0,0x00,0x00,0,0}, true,  14, 32, 16, 30, 0, false, 0},
        {"elecyoyo",   "MEASURED + per-frame R12/R13",           {38,32,34,0x03,31,11,32,32,0,7,0,0,0x00,0x00,0,0}, false, 14, 32, 16, 30, 1, false, 0},
        {"elecyoyo_flip","MEASURED, cocktail flip $3FE0",        {38,32,34,0x03,31,11,32,32,0,7,0,0,0x00,0x00,0,0}, false, 14, 32, 16, 30, 2, false, 0},
        {"zookeeper",  "MEASURED (trace)",                       {38,32,34,0x03,31,11,30,31,0,7,0,0,0x00,0x20,0,0}, false, 14, 32, 16, 30, 0, false, 0},
        {"vanguard",   "R0 R1 R6 R9 R12/13 MEASURED, rest DERIVED/guess", {44,32,36,0x04,31,6,28,29,0,7,0,0,0x03,0xFF,0,0}, true, 16, 16, 8, 30, 0, false, 0},
        {"fantasy",    "DERIVED (= vanguard table)",             {44,32,36,0x04,31,6,28,29,0,7,0,0,0x03,0xFF,0,0}, true, 16, 16, 8, 10, 0, false, 0},
        {"sasuke",     "MEASURED start $0000, rest = vanguard",  {44,32,36,0x04,31,6,28,29,0,7,0,0,0x00,0x00,0,0}, true, 16, 16, 8, 20, 0, false, 0},
        {"docastle",   "DERIVED from MAME set_raw (HD6845S)",    {38,32,34,0x03,32,0,24,28,0,7,0,0,0x00,0x80,0x00,0x80}, true, 16, 32, 4, 30, 0, false, 1},
        {"docastle_r4_31","DERIVED alt R4=31 R5=8",              {38,32,34,0x03,31,8,24,28,0,7,0,0,0x00,0x80,0x00,0x80}, true, 16, 32, 4, 10, 0, false, 1},
        {"cosmicg",    "R4/R5 DOCUMENTED, rest DERIVED (MC6845)",{38,32,32,0x03,127,7,96,108,0,1,0,0,0x00,0x00,0,0}, true, 16, 32, 6, 30, 0, true, 2},
    };
    int only = argc > 1 ? atoi(argv[1]) : -1;
    int fail = 0;
    for (size_t gi = 0; gi < G.size(); gi++) {
        if (only >= 0 && (int)gi != only) continue;
        Game &g = G[gi];
        Vtb_lockstep *t = new Vtb_lockstep;
        std::mt19937 rng(1234 + gi);
        uint64_t cyc = 0, mism = 0, stk = 0, frames = 0, reads = 0;
        int div = 0;
        std::deque<std::pair<int,int>> q;                 // (rs, data) writes; rs = 2: read of a register
        auto program = [&]() {
            if (g.ascending) for (int i = 0; i < g.nregs; i++) { q.push_back({0, i}); q.push_back({1, g.r[i]}); }
            else for (int i = g.nregs - 1; i >= 0; i--) { q.push_back({0, i}); q.push_back({1, g.r[i]}); }
        };
        int reset_left = 64, hold_left = 0, gap = 0, cur_rs = 0, cur_d = 0, cur_rnw = 0;
        int prev_vs = 0, yoyo_wait = -1, flip = 0, resets_done = 0;
        bool programmed = false;
        uint64_t frame_target = (uint64_t)g.frames;
        t->CLOCK = 0; t->eval();
        while (frames < frame_target && cyc < 200000000ull) {
            cyc++;
            int clken = (++div % g.clk_div) == 0;
            int nres = reset_left > 0 ? 0 : 1;
            if (reset_left > 0) reset_left--;
            if (nres && !programmed) { program(); programmed = true; }
            // board switch: hold the chip in reset for a while mid-frame, then reprogram
            if (g.resets && resets_done < g.resets && frames == (uint64_t)(resets_done + 1) * frame_target / (g.resets + 1)
                && reset_left == 0 && q.empty() && hold_left == 0) {
                resets_done++; reset_left = 5000 + rng() % 20000; programmed = false; q.clear(); nres = 0;
            }
            int en = 0, rnw = 1, rs = 0, di = rng() & 0xff;
            if (nres) {
                if (hold_left > 0) { hold_left--; en = 1; rnw = cur_rnw; rs = cur_rs; di = cur_d; if (!hold_left) gap = 4 + rng() % 40; }
                else if (gap > 0) gap--;
                else if (!q.empty()) {
                    auto op = q.front(); q.pop_front();
                    cur_rnw = op.first == 2; cur_rs = op.first == 2 ? 1 : op.first; cur_d = op.second;
                    hold_left = g.hold - 1; en = 1; rnw = cur_rnw; rs = cur_rs; di = cur_d;
                    if (cur_rnw) reads++;
                    if (!hold_left) gap = 4 + rng() % 40;
                }
            }
            t->CLOCK = 0; t->CLKEN = clken; t->nRESET = nres; t->ENABLE = en; t->R_nW = rnw; t->RS = rs; t->DI = di;
            t->LPSTB = 0;
            t->eval();
            for (int ph = 0; ph < 2; ph++) {
                if (ph) { t->CLOCK = 1; t->eval(); }
                if (t->o_dut != t->o_fix) {
                    if (mism < 5) printf("  MISMATCH %s cyc %llu dut %010llx fix %010llx\n", g.name.c_str(),
                                         (unsigned long long)cyc, (unsigned long long)t->o_dut, (unsigned long long)t->o_fix);
                    mism++;
                }
                if (t->o_stk != t->o_fix) stk++;
            }
            int vs = (t->o_fix >> 5) & 1;
            if (vs && !prev_vs && nres) {
                frames++;
                if (g.yoyo) yoyo_wait = 2 * (g.r[0] + 1) * g.clk_div;     // ~2 lines into vblank
                if (g.reads) {                                           // TMS board: read the address registers back
                    for (int i = 12; i < 18; i++) { q.push_back({0, i}); q.push_back({2, 0}); }
                    q.push_back({0, (int)(rng() % 32)}); q.push_back({2, 0});
                }
            }
            prev_vs = vs;
            if (yoyo_wait > 0 && --yoyo_wait == 0) {
                int a = (g.yoyo == 2 && (flip ^= 1)) ? 0x3FE0 : 0x0000;
                q.push_back({0, 12}); q.push_back({1, g.yoyo == 2 && a ? 0xFF : 0x00});
                q.push_back({0, 13}); q.push_back({1, a & 0xff});
            }
        }
        printf("%-15s %-48s clocks %10llu frames %3llu reads %5llu resets %d  dut-vs-fixed mismatches %llu  stock-vs-fixed diffs %llu\n",
               g.name.c_str(), g.src.c_str(), (unsigned long long)cyc, (unsigned long long)frames,
               (unsigned long long)reads, resets_done, (unsigned long long)mism, (unsigned long long)stk);
        if (mism) fail = 1;
        delete t;
    }
    return fail;
}

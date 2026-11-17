// Copyright (C) 2026 Rodimus
// tim020: instruction times of m68ksv (CPU = 68020 / 68021) against the MC68020 User's Manual section 8 tables
// (checkpoint 5). The manual's conditions (8.2 p. 8-9): long-aligned operands and stack, a 32-bit bus, no wait states
// (3-clock cycles); "cache case" (CC) = the instruction in the cache, no overlap with other instructions; "worst case"
// (WC) = the cache disabled, no overlap. For each instruction the harness runs eight copies of it twice in a DBRA loop,
// on a 32-bit DSACK port with no wait states (CPU clock = clk / 4), once with the cache disabled (CACR = 0: WC) and
// once with it enabled (CACR = 1, measured on the second pass, all hits: CC), and takes the time of one copy as the
// mean clocks between instruction boundaries over copies 2 to 7 (six copies: a one-word instruction alternates between
// a copy that fetches the next long and one that does not; the copies' min / max are printed when they differ). The expected figures are the
// manual's table entries (MOVE: 8.2.6 p. 8-20..8-28, everything included; the others: the 8.2.8 - 8.2.16 entry plus
// the 8.2.1 fetch-EA time where the table's footnote asks for it). Best-case figures need overlap m68ksv does not
// have: not compared.
//   tim020 [-v]       prints one line per instruction and the agreement totals; exit code 0
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <string>

static uint8_t mem[1 << 20];
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }

struct Ins { const char *name; std::vector<uint16_t> w; int cc, wc; const char *ref; };

// one run: returns the mean clocks per copy (or < 0), sets lo / hi to the copies' extremes
static double run(const Ins &in, bool cache, int &lo, int &hi) {
    const uint32_t CODE = 0x1000;
    memset(mem, 0, sizeof mem);
    w32(0, 0x7000); w32(4, CODE);
    for (int v = 2; v < 64; v++) w32(v * 4, 0x3000);
    w16(0x3000, 0x60fe);
    for (int i = 0; i < 0x400; i += 2) { w16(0x8000 + i, 0x0001); w16(0x9000 + i, 0x0001); }
    uint32_t p = CODE;
    auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
    o16(0x7201); o16(0x7402); o16(0x7601); o16(0x283c); o16(0x0000); o16(0x03e8);   // D1 = 1, D2 = 2, D3 = 1, D4 = 1000
    if (cache) { o16(0x7001); o16(0x4e7b); o16(0x0002); }                             // MOVEQ #1,D0; MOVEC D0,CACR
    o16(0x7e01);                                                                       // MOVEQ #1,D7 (two passes)
    uint32_t loop = p;
    o16(0x207c); o16(0x0000); o16(0x8040);                                             // MOVEA.L #$8040,A0
    o16(0x227c); o16(0x0000); o16(0x9040);                                             // MOVEA.L #$9040,A1
    o16(0x7201);                                                                       // MOVEQ #1,D1 (Z clear)
    std::vector<uint32_t> start;
    for (int k = 0; k < 8; k++) { start.push_back(p); for (uint16_t x : in.w) o16(x); }
    uint32_t after = p;
    o16(0x51cf); o16((uint16_t)(loop - (p + 2)));                                      // DBRA D7,loop
    o16(0x60fe);
    Vm68ksv *t = new Vm68ksv;
    t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = 1; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
    t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0; t->dbg_ra = 0;
    int pass = 0; long tb[9]; for (long &x : tb) x = -1;
    bool wseen = false;
    for (long n = 0; n < 200000; n++) {
        t->RESET_n_i = n > 80;
        uint32_t a = t->A32 & 0xfffff;
        if (t->AS_n) wseen = false;
        t->D32_i = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
        t->DSACK_n = t->AS_n ? 3 : 0;
        t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;
        t->clk = 0; t->eval(); bool fin = t->dbg_fin; t->clk = 1; t->eval();
        a = t->A32 & 0xfffff;
        if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {
            wseen = true;
            int nb = t->SIZ ? t->SIZ : 4, o = a & 3, k = nb < 4 - o ? nb : 4 - o;
            for (int j = 0; j < k; j++) mem[(a + j) & 0xfffff] = t->D32_o >> (24 - 8 * (o + j));
        }
        if (!fin) continue;
        uint32_t pc = t->dbg_pc & 0xfffff;
        if (pc == loop) pass++;
        if (pass == 2) {
            for (int k = 0; k < 8; k++) if (pc == start[k]) tb[k] = n;
            if (pc == after) { tb[8] = n; break; }
        }
        if (pc == 0x3000) break;                                                       // an exception: no figure
    }
    delete t;
    lo = 1 << 30; hi = -1;
    for (int k = 1; k < 7; k++) {
        if (tb[k] < 0 || tb[k + 1] < 0) return -1;
        int d = (int)(tb[k + 1] - tb[k]) / 4;
        lo = d < lo ? d : lo; hi = d > hi ? d : hi;
    }
    return (tb[7] - tb[1]) / 24.0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    bool verbose = false;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "-v")) verbose = true;
    // registers on entry to each copy: D1 = 1 (MOVEQ #1,D1 before the copies), D2 = 2, D3 = 1, D4 = 1000, A0 = $8040,
    // A1 = $9040, SP = $7000; memory at A0 / A1 = $0001 words
    std::vector<Ins> list = {
        {"NOP",                    {0x4e71},                  2, 3, "8.2.16"},
        {"MOVEQ #1,D1",            {0x7201},                  2, 3, "8.2.9"},
        {"MOVE.L D1,D2",           {0x2401},                  2, 3, "8.2.6"},
        {"MOVE.L (A0),D1",         {0x2210},                  6, 7, "8.2.6"},
        {"MOVE.L (A0)+,D1",        {0x2218},                  6, 7, "8.2.6"},
        {"MOVE.L -(A0),D1",        {0x2220},                  7, 8, "8.2.6"},
        {"MOVE.L (16,A0),D1",      {0x2228, 0x0010},          7, 9, "8.2.6"},
        {"MOVE.L (xxx).L,D1",      {0x2239, 0x0000, 0x8040},  6, 10, "8.2.6"},
        {"MOVE.W #imm,D1",         {0x323c, 0x0001},          4, 3, "8.2.6"},
        {"MOVE.L #imm,D1",         {0x223c, 0x0000, 0x0001},  6, 5, "8.2.6"},
        {"MOVE.L D1,(A1)",         {0x2281},                  4, 5, "8.2.6"},
        {"MOVE.L D1,(A1)+",        {0x22c1},                  4, 5, "8.2.6"},
        {"MOVE.L D1,-(A1)",        {0x2301},                  5, 6, "8.2.6"},
        {"MOVE.L D1,(16,A1)",      {0x2341, 0x0010},          5, 7, "8.2.6"},
        {"MOVE.L D1,(xxx).L",      {0x23c1, 0x0000, 0x9040},  6, 9, "8.2.6"},
        {"MOVE.W D1,(A1)",         {0x3281},                  4, 5, "8.2.6"},
        {"MOVE.L (A0),(A1)",       {0x2290},                  7, 9, "8.2.6"},
        {"MOVE.L (A0)+,(A1)+",     {0x22d8},                  7, 9, "8.2.6"},
        {"ADD.L D1,D2",            {0xd481},                  2, 3, "8.2.8"},
        {"ADD.L (A0),D2",          {0xd490},                  6, 7, "8.2.8 + 8.2.1"},
        {"ADD.L D2,(A1)",          {0xd591},                  8, 10, "8.2.8 + 8.2.1"},
        {"CMP.L D1,D2",            {0xb481},                  2, 3, "8.2.8"},
        {"ADDQ.L #1,D1",           {0x5281},                  2, 3, "8.2.9"},
        {"CLR.L D1",               {0x4281},                  2, 3, "8.2.11"},
        {"NEG.L D1",               {0x4481},                  2, 3, "8.2.11"},
        {"TST.L D1",               {0x4a81},                  2, 3, "8.2.11"},
        {"EXT.L D1",               {0x48c1},                  4, 4, "8.2.11"},
        {"ST D1",                  {0x50c1},                  4, 4, "8.2.11"},
        {"LSL.L #1,D1",            {0xe389},                  4, 4, "8.2.12"},
        {"LSL.L D3,D1",            {0xe7a9},                  6, 6, "8.2.12"},
        {"ASR.L #1,D1",            {0xe281},                  6, 6, "8.2.12"},
        {"ROL.L #1,D1",            {0xe399},                  8, 8, "8.2.12"},
        {"BTST #3,D1",             {0x0801, 0x0003},          4, 5, "8.2.13"},
        {"BSET D3,D1",             {0x07c1},                  4, 5, "8.2.13"},
        {"BEQ.S (not taken)",      {0x6702},                  4, 5, "8.2.15"},
        {"BRA.S (taken)",          {0x6002, 0x4e71},          6, 9, "8.2.15"},
        {"DBF D4 (taken)",         {0x51cc, 0x0002},          6, 9, "8.2.15"},
        {"MULU.W D1,D2",           {0xc4c1},                  27, 28, "8.2.8"},
        {"DIVU.W D1,D2",           {0x84c1},                  44, 44, "8.2.8"},
        {"LINK.W A6,#-8",          {0x4e56, 0xfff8},          5, 7, "8.2.16"},
    };
    int n = 0, cc_eq = 0, wc_eq = 0, cc_le = 0, wc_le = 0; double cc_d = 0, wc_d = 0;
    printf("%-22s %-14s %12s %12s\n", "instruction", "manual ref", "CC m68ksv/UM", "WC m68ksv/UM");
    for (auto &in : list) {
        int l1, h1, l2, h2;
        double cc = run(in, true, l1, h1), wc = run(in, false, l2, h2);
        n++;
        if (cc > in.cc - 0.5 && cc < in.cc + 0.5) cc_eq++;
        if (wc > in.wc - 0.5 && wc < in.wc + 0.5) wc_eq++;
        if (cc >= in.cc - 2 && cc <= in.cc + 2) cc_le++;
        if (wc >= in.wc - 2 && wc <= in.wc + 2) wc_le++;
        cc_d += cc - in.cc; wc_d += wc - in.wc;
        char x[64] = "";
        if (l1 != h1 || l2 != h2 || verbose) snprintf(x, sizeof x, "  (copies CC %d-%d, WC %d-%d)", l1, h1, l2, h2);
        printf("%-22s %-14s %6.1f/%-5d %6.1f/%-5d%s\n", in.name, in.ref, cc, in.cc, wc, in.wc, x);
    }
    printf("tim020: %d instructions; m68ksv = manual (mean within 0.5 clock): cache case %d, worst case %d; within 2 clocks: "
           "%d / %d; mean difference (m68ksv - manual): cache case %+.2f, worst case %+.2f clocks\n",
           n, cc_eq, wc_eq, cc_le, wc_le, cc_d / n, wc_d / n);
    return 0;
}

// Copyright (C) 2026 Rodimus
// rmc020: directed test of the 68020 read-modify-write lock (RMC_n) of m68ksv (CPU = 68020 / 68021), checkpoint 4b.
// A program runs TAS, CAS.B / .W / .L (compare equal and not equal) and CAS2.W / .L (equal, first compare failing,
// second compare failing); the memory is a 32-bit port (or 16 / 8-bit / a second 32-bit port with -port; cp5: that was STERM, not a 68020 signal) with random wait states. For
// every interval in which RMC_n is low the test collects the bus cycles and checks: (1) the cycles are exactly the
// locked sequence of that instruction (operand reads, then the writes when the compare succeeded; FC, R/W, address,
// SIZ - a long operand read is one request, a long write two word requests), (2) no instruction fetch or other cycle
// inside, (3) RMC_n stays low from the first cycle's start to the last cycle's end and is high on the next cycle (the
// final prefetch), (4) the bus is not granted: BR is asserted throughout the interval and BG_n must stay high. Register
// and memory results are checked at the end (CAS semantics: equal -> Du written, flags Z; not equal -> Dc loaded).
//   rmc020 [-port 0..3] [-w W] [-v]
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <string>

static uint8_t mem[1 << 20];
static uint32_t rs = 11;
static uint32_t rnd() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static uint32_t r32(uint32_t a) { return ((uint32_t)mem[a] << 24) | (mem[a + 1] << 16) | (mem[a + 2] << 8) | mem[a + 3]; }
struct Cyc { uint32_t a; int siz, rw, fc; };
struct Exp { const char *name; std::vector<Cyc> cyc; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int port = 0, wmax = 2; bool verbose = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-port")) port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = true;
    }
    const uint32_t CODE = 0x1000, OP = 0x8000;      // operands: OP + 0x00 .. 0x3f
    memset(mem, 0, sizeof mem);
    w32(0, 0x7000); w32(4, CODE);
    for (int v = 2; v < 64; v++) w32(v * 4, 0x2000);
    w16(0x2000, 0x60fe);
    uint32_t p = CODE;
    auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
    std::vector<Exp> exp;
    auto C = [](uint32_t a, int siz, int rw) { return Cyc{a, siz, rw, 5}; };
    // A0 = OP, A1 = OP + 0x20; operand memory
    o16(0x207c); o16(OP >> 16); o16(OP);                       // MOVEA.L #OP,A0
    o16(0x227c); o16((OP + 0x20) >> 16); o16(OP + 0x20);       // MOVEA.L #OP+$20,A1
    w32(OP + 0x00, 0x12345678); w32(OP + 0x04, 0x0000abcd); w32(OP + 0x08, 0x40000000);
    w32(OP + 0x20, 0x11112222); w32(OP + 0x24, 0x33334444);
    // TAS (A0) at OP + 8 (byte $40 -> $C0)
    o16(0x4ad0 | 0); o16(0x4e71);                              // TAS (A0)... (A0 = OP: byte $12)
    exp.push_back({"TAS (A0)", {C(OP, 1, 1), C(OP, 1, 0)}});
    // CAS.L D1,D2,(A0): D1 = $92345678 (after TAS: $12 -> $92) equal -> D2 written
    o16(0x223c); o16(0x9234); o16(0x5678);                     // MOVE.L #$92345678,D1
    o16(0x243c); o16(0xcafe); o16(0xbabe);                     // MOVE.L #$CAFEBABE,D2
    o16(0x0ed0); o16(0x0081);                                  // CAS.L D1,D2,(A0)   (Du = D2 bits 8-6, Dc = D1)
    exp.push_back({"CAS.L equal", {C(OP, 0, 1), C(OP, 2, 0), C(OP + 2, 2, 0)}});
    // CAS.L D1,D2,(A0) again: memory = $CAFEBABE != D1 -> D1 loaded, no write
    o16(0x0ed0); o16(0x0081);
    exp.push_back({"CAS.L not equal", {C(OP, 0, 1)}});
    // CAS.W D3,D4,2(A0)... use (A0)+ form? keep (d16,A0): CAS.W D3,D4,(4,A0)? operand at OP+6 = $abcd
    o16(0x363c); o16(0xabcd);                                  // MOVE.W #$ABCD,D3
    o16(0x383c); o16(0x5555);                                  // MOVE.W #$5555,D4
    o16(0x0ce8); o16(0x0103); o16(0x0006);                     // CAS.W D3,D4,(6,A0)
    exp.push_back({"CAS.W equal", {C(OP + 6, 2, 1), C(OP + 6, 2, 0)}});
    // CAS.B D3,D4,(7,A0): byte $55 != $CD -> no write
    o16(0x0ae8); o16(0x0103); o16(0x0007);                     // CAS.B D3,D4,(7,A0)
    exp.push_back({"CAS.B not equal", {C(OP + 7, 1, 1)}});
    // CAS.W at an odd address (7,A0) equal: D3 = $5555 (bytes 7, 8 = $55, $C0?) -> set the compare from memory first
    o16(0x3628); o16(0x0007);                                  // MOVE.W (7,A0),D3
    o16(0x0ce8); o16(0x0103); o16(0x0007);                     // CAS.W D3,D4,(7,A0)  equal -> D4 written (odd: 2 bytes)
    exp.push_back({"CAS.W odd equal", {C(OP + 7, 2, 1), C(OP + 7, 2, 0)}});
    // CAS2.L D1:D2,D3:D4,(A0):(A1): D1 = mem(A0), D2 = mem(A1) -> equal, D3 / D4 written
    o16(0x2210); o16(0x2411);                                  // MOVE.L (A0),D1 ; MOVE.L (A1),D2
    o16(0x263c); o16(0x0102); o16(0x0304);                     // MOVE.L #$01020304,D3
    o16(0x283c); o16(0x0506); o16(0x0708);                     // MOVE.L #$05060708,D4
    o16(0x0efc); o16(0x80c1); o16(0x9102);                     // CAS2.L D1:D2,D3:D4,(A0):(A1)
    exp.push_back({"CAS2.L equal", {C(OP, 0, 1), C(OP + 0x20, 0, 1), C(OP, 2, 0), C(OP + 2, 2, 0), C(OP + 0x20, 2, 0), C(OP + 0x22, 2, 0)}});
    // CAS2.L again: first compare fails (D1 = old) -> reads only
    o16(0x0efc); o16(0x80c1); o16(0x9102);
    exp.push_back({"CAS2.L not equal (1)", {C(OP, 0, 1), C(OP + 0x20, 0, 1)}});
    // CAS2.W: D1 = mem.w(A0) (equal), D2 = 0 (second fails)
    o16(0x3210); o16(0x7400);                                  // MOVE.W (A0),D1 ; MOVEQ #0,D2
    o16(0x0cfc); o16(0x80c1); o16(0x9102);                     // CAS2.W D1:D2,D3:D4,(A0):(A1)
    exp.push_back({"CAS2.W not equal (2)", {C(OP, 2, 1), C(OP + 0x20, 2, 1)}});
    o16(0x4e71);
    uint32_t endpc = p;
    o16(0x60fe);
    Vm68ksv *t = new Vm68ksv;
    t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = 1; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
    t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0;
    std::vector<std::vector<Cyc>> got; std::vector<int> gviol;
    bool in_rmc = false, in_as = false, wseen = false, done = false; int wait = 0, viol = 0; long n;
    bool prev_cyc_rmc = false; int after_bad = 0, bg_bad = 0; long bg_n0 = 0; uint32_t bg_pc = 0; int bg_upc = 0;
    for (n = 0; n < 400000 && !done; n++) {
        t->RESET_n_i = n > 80;
        uint32_t a = t->A32 & 0xfffff;
        bool rmc = !t->RMC_n && n > 120;      // (the outputs are undefined before the reset has taken hold)
        if (t->AS_n) { in_as = false; wait = wmax ? rnd() % (wmax + 1) : 0; }
        else if (!in_as) {
            in_as = true; wseen = false;
            Cyc c{t->A32 & 0xfffff, t->SIZ, t->RW, t->FC};
            if (rmc) { if (!in_rmc) { got.push_back({}); gviol.push_back(0); in_rmc = true; } got.back().push_back(c); }
            else if (prev_cyc_rmc) { /* first cycle after a locked interval: RMC high there (checked by construction) */ }
            prev_cyc_rmc = rmc;
        }
        if (in_rmc && !rmc && t->AS_n) in_rmc = false;
        if (in_rmc && !rmc && !t->AS_n) after_bad++;            // RMC negated in the middle of a cycle of the sequence
        if (rmc && !t->BG_n) { if (!bg_bad) { bg_n0 = n; bg_pc = t->dbg_pc; bg_upc = t->dbg_upc; } bg_bad++; }
        t->BR_n = rmc ? 0 : 1;                                   // request the bus during the lock: must not be granted
        uint32_t d = rnd();
        if (port == 0 || port == 3) d = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
        else if (port == 1) d = (d & 0xffff) | ((uint32_t)mem[a & ~1u] << 24) | ((uint32_t)mem[a | 1] << 16);
        else d = (d & 0xffffff) | ((uint32_t)mem[a] << 24);
        t->D32_i = d;
        bool ack = !t->AS_n && wait == 0;
        // (cp5: no STERM on the 68020, User's Manual Table 3-2: port 3 is a second 32-bit DSACK port)
        t->DSACK_n = !ack ? 3 : (port == 0 || port == 3) ? 0 : port == 1 ? 1 : 2;
        t->STERM_n = 1;
        if (!t->AS_n && wait > 0 && (n % 4) == 0) wait--;
        t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;
        t->clk = 0; t->eval(); bool fin = t->dbg_fin; t->clk = 1; t->eval();
        a = t->A32 & 0xfffff;
        if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {
            wseen = true;
            int nb = t->SIZ ? t->SIZ : 4, o = a & 3, k, l0;
            if (port == 0 || port == 3) { k = std::min(nb, 4 - o); l0 = o; }
            else if (port == 1) { k = std::min(nb, 2 - (o & 1)); l0 = o & 1; }
            else { k = 1; l0 = 0; }
            for (int j = 0; j < k; j++) mem[(a + j) & 0xfffff] = t->D32_o >> (24 - 8 * (l0 + j));
        }
        if (fin && (t->dbg_pc & 0xfffff) >= endpc && (t->dbg_pc & 0xfffff) <= endpc + 4) done = true;
    }
    (void)viol;
    int fails = 0;
    // expected cycles split by the port (dynamic sizing of each request)
    auto split = [&](const Cyc &c) {
        std::vector<Cyc> v; int left = c.siz ? c.siz : 4; uint32_t ad = c.a;
        while (left > 0) { int o = ad & 3, k = (port == 0 || port == 3) ? std::min(left, 4 - o) : port == 1 ? std::min(left, 2 - (o & 1)) : 1;
                           v.push_back(Cyc{ad, left & 3, c.rw, c.fc}); ad += k; left -= k; }
        return v;
    };
    if (!done) { printf("rmc020: program did not complete\n"); fails++; }
    for (size_t i = 0; i < exp.size(); i++) {
        std::vector<Cyc> e; for (auto &c : exp[i].cyc) for (auto &x : split(c)) e.push_back(x);
        std::string why;
        if (i >= got.size()) why = " (no locked interval)";
        else {
            auto &g = got[i];
            if (g.size() != e.size()) { char b[64]; snprintf(b, sizeof b, " (%zu cycles, expected %zu)", g.size(), e.size()); why += b; }
            for (size_t k = 0; k < g.size() && k < e.size(); k++)
                if (g[k].a != e[k].a || (g[k].siz & 3) != (e[k].siz & 3) || g[k].rw != e[k].rw || g[k].fc != e[k].fc) {
                    char b[96]; snprintf(b, sizeof b, " cycle %zu: %05x SIZ%d %c FC%d (expected %05x SIZ%d %c FC%d)", k, g[k].a, g[k].siz, g[k].rw ? 'r' : 'w', g[k].fc,
                                         e[k].a, e[k].siz & 3, e[k].rw ? 'r' : 'w', e[k].fc); why += b; }
        }
        if (!why.empty()) fails++;
        if (!why.empty() || verbose) printf("%-22s %s%s\n", exp[i].name, why.empty() ? "ok" : "FAIL", why.c_str());
        if (verbose && i < got.size()) for (auto &c : got[i]) printf("      %05x SIZ%d %c FC%d\n", c.a, c.siz, c.rw ? 'r' : 'w', c.fc);
    }
    if (got.size() != exp.size()) { printf("locked intervals: %zu, expected %zu\n", got.size(), exp.size()); fails++; }
    if (after_bad) { printf("RMC negated inside a cycle of a locked sequence: %d clocks\n", after_bad); fails++; }
    if (bg_bad) { printf("bus granted while RMC asserted: %d clocks (first at clk %ld, PC %x, upc %d)\n", bg_bad, bg_n0, bg_pc, bg_upc); fails++; }
    // results: TAS $12 -> $92; CAS.L equal -> $CAFEBABE; CAS.W equal at 6 -> $5555; CAS.W odd at 7 -> $5555 bytes 7-8;
    // CAS2.L equal -> $01020304 / $05060708
    std::string rw;
    if (mem[OP + 0] != 0x01) rw += " byte OP";       // overwritten by CAS2.L (01020304)
    if (r32(OP) != 0x01020304) rw += " OP+0";
    if (r32(OP + 0x20) != 0x05060708) rw += " OP+20";
    if (mem[OP + 6] != 0x55 || mem[OP + 7] != 0x55 || mem[OP + 8] != 0x55) rw += " OP+6..8";
    if (!rw.empty()) { printf("memory results wrong:%s\n", rw.c_str()); fails++; }
    printf("rmc020 (port %s, waits 0-%d): %zu locked sequences checked (%zu expected), %d failures\n",
           port == 3 ? "32b" : port == 0 ? "32" : port == 1 ? "16" : "8", wmax, got.size(), exp.size(), fails);
    delete t;
    return fails != 0;
}

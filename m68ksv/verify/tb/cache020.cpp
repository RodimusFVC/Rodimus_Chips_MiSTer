// Copyright (C) 2026 Rodimus
// cache020: directed instruction-cache test of m68ksv (CPU = 68020 / 68021). Small programs call a subroutine in a probe
// area (0x3080, port width under test: 32 / 16 / 8 bits by DSACK, and a second 32-bit DSACK port - cp5: it was STERM, which the 68020 does not have) and the harness counts the instruction
// fetch cycles that reach the bus in that area and reads the registers at the end:
//   hit        cache on: two calls fetch from the bus exactly as often as one call (the second runs from the cache)
//   stale      a write to cached code does not update the cache (old instruction runs), CACR C clears it (new one runs)
//   entry      CACR CE with CAAR = the line clears that line only (the new instruction runs)
//   freeze     CACR F: misses do not fill (two calls = twice the fetches of one)
//   off        CACR E = 0: no cache (two calls = twice the fetches)
//   cdis       CDIS low: no cache (two calls = twice the fetches)
//   fc2        a line filled in supervisor mode misses in user mode (FC2 is part of the tag), the user fill then hits
// Random wait states. One line per case and port, a total; exit code = failures.
//   cache020 [-w W] [-v]
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

static const uint32_t CODE = 0x1000, SUB = 0x3080, PROBE_END = 0x4000;   // SUB: cache index 0x20 up, away from CODE (0-12)
struct Res { bool done; uint32_t d[8]; long fetch_s, fetch_u; };

// run the program in mem with the probe area on port pw; cdis = CDIS_n level
static Res run(int pw, int wmax, bool cdis_n, uint32_t end_pc) {
    Res r{}; Vm68ksv *t = new Vm68ksv;
    t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = cdis_n; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
    t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0;
    bool in_as = false, wseen = false; int wait = 0;
    for (long n = 0; n < 200000 && !r.done; n++) {
        t->RESET_n_i = n > 80;
        uint32_t a = t->A32 & 0xfffff;
        int p = (a >= SUB && a < PROBE_END) ? pw : 0;
        if (t->AS_n) { in_as = false; wait = wmax ? rnd() % (wmax + 1) : 0; }
        else if (!in_as) {
            in_as = true; wseen = false;
            if (a >= SUB && a < PROBE_END && (t->FC == 6 || t->FC == 2)) (t->FC == 6 ? r.fetch_s : r.fetch_u)++;
        }
        uint32_t d = rnd();
        if (p == 0 || p == 3) d = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
        else if (p == 1) d = (d & 0xffff) | ((uint32_t)mem[a & ~1u] << 24) | ((uint32_t)mem[a | 1] << 16);
        else d = (d & 0xffffff) | ((uint32_t)mem[a] << 24);
        t->D32_i = d;
        bool ack = !t->AS_n && wait == 0;
        // (cp5: no STERM on the 68020, User's Manual Table 3-2: port 3 is a second 32-bit DSACK port)
        t->DSACK_n = !ack ? 3 : (p == 0 || p == 3) ? 0 : p == 1 ? 1 : 2;
        t->STERM_n = 1;
        if (!t->AS_n && wait > 0 && (n % 4) == 0) wait--;
        t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;   // CPU clock = clk / 4 (cp4b)
        t->clk = 0; t->eval(); bool fin = t->dbg_fin; t->clk = 1; t->eval();
        a = t->A32 & 0xfffff;
        if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {           // writes (32-bit port outside the probe area)
            wseen = true;
            int pp = (a >= SUB && a < PROBE_END) ? pw : 0;
            int nb = t->SIZ ? t->SIZ : 4, o = a & 3, k, l0;
            if (pp == 0 || pp == 3) { k = std::min(nb, 4 - o); l0 = o; }
            else if (pp == 1) { k = std::min(nb, 2 - (o & 1)); l0 = o & 1; }
            else { k = 1; l0 = 0; }
            for (int j = 0; j < k; j++) mem[(a + j) & 0xfffff] = t->D32_o >> (24 - 8 * (l0 + j));
        }
        if (fin && (t->dbg_pc & 0xfffff) == end_pc) {
            for (int k = 0; k < 8; k++) {
                t->dbg_ra = k; t->cen_p = 0; t->cen_n = 0; t->clk = 0; t->eval(); t->clk = 1; t->eval();
                r.d[k] = t->dbg_rd;
            }
            r.done = true;
        }
    }
    delete t;
    return r;
}

// program builder
static uint32_t pc;
static void o16(uint16_t v) { w16(pc, v); pc += 2; }
static void cacr(uint32_t v) { o16(0x203c); o16(v >> 16); o16(v); o16(0x4e7b); o16(0x0002); }     // MOVE.L #v,D0; MOVEC D0,CACR
static void caar(uint32_t v) { o16(0x203c); o16(v >> 16); o16(v); o16(0x4e7b); o16(0x0802); }     // MOVEC D0,CAAR
static void bsr(uint32_t to) { o16(0x6100); o16((uint16_t)(to - pc)); }                             // BSR.W to
static uint32_t finish() { uint32_t e = pc; o16(0x60fe); return e; }                                // BRA *
static void base() {
    memset(mem, 0, sizeof mem);
    w32(0, 0x7000); w32(4, CODE);
    for (int v = 2; v < 64; v++) w32(v * 4, 0x2000);
    w16(0x2000, 0x60fe);
    pc = SUB;                                   // subroutine: MOVEQ #1,D1; NOP x 5; RTS (three lines)
    o16(0x7201); for (int i = 0; i < 5; i++) o16(0x4e71); o16(0x4e75);
    pc = CODE;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int wmax = 2; bool verbose = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = true;
    }
    int fails = 0, cases = 0;
    static const char *pn[4] = {"32", "16", "8", "32b"};
    for (int pw = 0; pw < 4; pw++) {
        auto report = [&](const char *name, bool ok, const std::string &why) {
            cases++; if (!ok) fails++;
            if (!ok || verbose) printf("port %-8s %-7s %s%s\n", pn[pw], name, ok ? "ok" : "FAIL", why.c_str());
        };
        char b[256];
        // hit / off / freeze / cdis: fetch cycles of one call vs two calls
        struct { const char *name; uint32_t cr; bool cdis_n; bool hits; } mode[4] = {
            {"hit", 1, true, true}, {"off", 0, true, false}, {"freeze", 3, true, false}, {"cdis", 1, false, false}};
        for (auto &m : mode) {
            long f[2] = {0, 0}; bool done = true;
            for (int calls = 1; calls <= 2; calls++) {
                base(); cacr(m.cr); for (int c = 0; c < calls; c++) bsr(SUB);
                uint32_t e = finish();
                Res r = run(pw, wmax, m.cdis_n, e);
                done = done && r.done && r.d[1] == 1; f[calls - 1] = r.fetch_s;
            }
            bool ok = done && f[0] > 0 && (m.hits ? f[1] == f[0] : f[1] == 2 * f[0]);
            snprintf(b, sizeof b, " (fetch cycles in the probe area: one call %ld, two calls %ld; expected %s)", f[0], f[1],
                     m.hits ? "equal" : "twice");
            report(m.name, ok, b);
        }
        // stale: D3 = first call, D4 = after the code write (cached: old), D5 = after CACR C (new)
        for (int ce = 0; ce < 2; ce++) {
            base(); cacr(1);
            bsr(SUB); o16(0x2601);                              // MOVE.L D1,D3
            o16(0x33fc); o16(0x7202); o16(0x0000); o16(SUB);    // MOVE.W #$7202,SUB (MOVEQ #2,D1)
            bsr(SUB); o16(0x2801);                              // MOVE.L D1,D4
            if (ce) { caar(SUB); cacr(5); } else cacr(9);       // CE (entry of CAAR) / C (all), E kept
            bsr(SUB); o16(0x2a01);                              // MOVE.L D1,D5
            uint32_t e = finish();
            Res r = run(pw, wmax, true, e);
            bool ok = r.done && r.d[3] == 1 && r.d[4] == 1 && r.d[5] == 2;
            snprintf(b, sizeof b, " (D3 %x D4 %x D5 %x, expected 1 1 2)", r.d[3], r.d[4], r.d[5]);
            report(ce ? "entry" : "stale", ok, b);
        }
        // fc2: supervisor call fills; user-mode calls: first misses (user fetches > 0), second hits (no more)
        {
            long fu[2] = {0, 0}; bool done = true;
            for (int calls = 1; calls <= 2; calls++) {
                base(); cacr(1); bsr(SUB);
                o16(0x207c); o16(0x0000); o16(0x6000); o16(0x4e60);      // MOVEA.L #$6000,A0; MOVE A0,USP
                o16(0x46fc); o16(0x0000);                                // MOVE #0,SR (user mode)
                for (int c = 0; c < calls; c++) bsr(SUB);
                uint32_t e = finish();
                Res r = run(pw, wmax, true, e);
                done = done && r.done; fu[calls - 1] = r.fetch_u;
            }
            bool ok = done && fu[0] > 0 && fu[1] == fu[0];
            snprintf(b, sizeof b, " (user fetch cycles: one user call %ld, two %ld; expected > 0 and equal)", fu[0], fu[1]);
            report("fc2", ok, b);
        }
    }
    printf("cache020: %d cases (hit / off / freeze / cdis / stale / entry / fc2 x port 32 / 16 / 8 / 32b), %d failures\n", cases, fails);
    return fails != 0;
}

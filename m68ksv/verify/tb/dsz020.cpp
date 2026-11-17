// Copyright (C) 2026 Rodimus
// dsz020: directed dynamic bus sizing test of m68ksv (CPU = 68020 / 68021). For every port width (32 / 16 / 8 bits by
// DSACK, a second 32-bit DSACK port (cp5: it was STERM, which the 68020 does not have)) x operand size (byte / word / long) x address offset (A1 A0 = 0-3), a program reads an
// operand from a pattern area into D1 (MOVE.x (A0),D1), writes D2 to a cleared area (MOVE.x D2,(A1)), compares the
// register with the expected value and the written bytes with the expected bytes; it also checks every physical bus
// cycle against the 68020 rules: SIZ = the operand bytes still to transfer, the address advancing by the bytes the
// port took (32-bit port: up to the long boundary, 16-bit: up to the word boundary, 8-bit: one byte), and the number
// of cycles. Random wait states. Prints one line per combination and a total; exit code = failures.
// (m68ksv issues a long operand as two word requests: the cycle check follows that.)
//   dsz020 [-w W] [-v]
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <string>

#ifndef M68KSV_HCPU
#define M68KSV_HCPU 68020
#endif
static const bool EC020 = M68KSV_HCPU == 68021;    // the MC68EC020 has no DBEN (User's Manual Table 3-2)
static uint8_t mem[1 << 20];
static uint32_t rs = 7;
static uint32_t rnd() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
struct Cyc { uint32_t a; int siz, rw; long t0, t1, tds, tdb; };  // t0 / t1: clk of AS asserted / negated; tds / tdb: DS / DBEN low

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int wmax = 2; bool verbose = false; int be = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = true;
        // cp5: -be 3 / -be 4 - a bus error on the operand read's first physical cycle by the User's Manual Table 5-8 case 3
        // (BERR with DSACK1 / DSACK0) / case 4 (BERR one clock after DSACK1 / DSACK0, at the latching edge): the bus error
        // exception must be taken (handler at 0x2000), the store must not run (no wait states)
        else if (!strcmp(argv[i], "-be")) { be = atoi(argv[++i]); wmax = 0; }
    }
    const uint32_t CODE = 0x1000, SRC = 0x8000, DST = 0x9000;
    int fails = 0, combos = 0; long cycles_checked = 0, timed = 0;
    for (int port = 0; port < 4; port++)
    for (int sz = 0; sz < 3; sz++)
    for (int off = 0; off < 4; off++) {
        combos++;
        memset(mem, 0, sizeof mem);
        for (int i = 0; i < 16; i++) mem[SRC + i] = 0x11 * (i + 1);
        w32(0, 0x7000); w32(4, CODE);
        for (int v = 2; v < 64; v++) w32(v * 4, 0x2000);               // any exception: loop at 0x2000
        w16(0x2000, 0x60fe);
        uint32_t p = CODE;
        auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
        static const uint16_t msz[3] = {0x1000, 0x3000, 0x2000};       // MOVE.B / .W / .L
        o16(0x207c); o16((SRC + off) >> 16); o16(SRC + off);           // MOVEA.L #src,A0
        o16(0x227c); o16((DST + off) >> 16); o16(DST + off);           // MOVEA.L #dst,A1
        o16(0x243c); o16(0xa1b2); o16(0xc3d4);                         // MOVE.L #$A1B2C3D4,D2
        o16(0x7200);                                                   // MOVEQ #0,D1
        uint32_t mark = p;
        o16(msz[sz] | 0x0210);                                         // MOVE.x (A0),D1
        o16(msz[sz] | 0x0282);                                         // MOVE.x D2,(A1)
        o16(0x60fe);                                                   // BRA *
        Vm68ksv *t = new Vm68ksv;
        t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = 1; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
        t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0;
        std::vector<Cyc> cyc; bool in_as = false, wseen = false; int wait = 0; bool done = false; uint32_t d1 = 0;
        bool data_phase = false; long be_t0 = -1; bool in_handler = false;
        for (long n = 0; n < 80000 && !done; n++) {
            t->RESET_n_i = n > 80;
            uint32_t a = t->A32 & 0xfffff;
            int pw = (a >= SRC && a < SRC + 0x2000) ? port : 0;       // the test areas have the port under test
            if (t->AS_n) {
                if (in_as && data_phase && !cyc.empty() && cyc.back().t1 < 0) cyc.back().t1 = n;
                in_as = false; wait = wmax ? rnd() % (wmax + 1) : 0;
            }
            else if (!in_as) {
                in_as = true; wseen = false;
                if (data_phase && (a >= SRC && a < SRC + 0x2000)) { cyc.push_back(Cyc{t->A32, t->SIZ, t->RW, n, -1, -1, -1}); }
            }
            if (!t->AS_n && in_as && data_phase && !cyc.empty() && cyc.back().t1 < 0) {
                if (!t->DS_n && cyc.back().tds < 0) cyc.back().tds = n;
                if (!t->DBEN_n && cyc.back().tdb < 0) cyc.back().tdb = n;
            }
            uint32_t d = rnd();
            if (pw == 0 || pw == 3) d = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
            else if (pw == 1) d = (d & 0xffff) | ((uint32_t)mem[a & ~1u] << 24) | ((uint32_t)mem[a | 1] << 16);
            else d = (d & 0xffffff) | ((uint32_t)mem[a] << 24);
            t->D32_i = d;
            bool ack = !t->AS_n && wait == 0;
            // (-be: AS of the first operand-read cycle observed low at be_t0; DSACK is recognised at the falling edge be_t0 + 3,
            // the data latched at be_t0 + 7)
            if (be && data_phase && be_t0 < 0 && !t->AS_n && t->RW && pw == port && a >= SRC && a < SRC + 0x2000) be_t0 = n;
            t->BERR_n = !(be && be_t0 >= 0 && ((be == 3 && n >= be_t0 && n <= be_t0 + 8) || (be == 4 && n >= be_t0 + 5 && n <= be_t0 + 8)));
            // (cp5: no STERM on the 68020, User's Manual Table 3-2: port 3 is a second 32-bit DSACK port)
            t->DSACK_n = !ack ? 3 : (pw == 0 || pw == 3) ? 0 : pw == 1 ? 1 : 2;
            t->STERM_n = 1;
            if (!t->AS_n && wait > 0 && (n % 4) == 0) wait--;
            t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;   // CPU clock = clk / 4 (cp4b)
            t->clk = 0; t->eval(); bool fin = t->dbg_fin; t->clk = 1; t->eval();
            a = t->A32 & 0xfffff;
            if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {
                wseen = true;
                int nb = t->SIZ ? t->SIZ : 4, o = a & 3, k, l0;
                if (pw == 0 || pw == 3) { k = std::min(nb, 4 - o); l0 = o; }
                else if (pw == 1) { k = std::min(nb, 2 - (o & 1)); l0 = o & 1; }
                else { k = 1; l0 = 0; }
                for (int j = 0; j < k; j++) mem[(a + j) & 0xfffff] = t->D32_o >> (24 - 8 * (l0 + j));
            }
            if (fin && (t->dbg_pc & 0xfffff) == mark) data_phase = true;
            if (be && fin && (t->dbg_pc & 0xfffff) == 0x2000) { in_handler = true; done = true; }
            if (fin && (t->dbg_pc & 0xfffff) == mark + 4) {           // at BRA *: both moves done
                t->dbg_ra = 1; t->cen_p = 0; t->cen_n = 0; t->clk = 0; t->eval(); t->clk = 1; t->eval();
                d1 = t->dbg_rd; done = true;
            }
        }
        // expected
        int nb = sz == 0 ? 1 : sz == 1 ? 2 : 4;
        uint32_t ex = 0;
        for (int i = 0; i < nb; i++) ex = (ex << 8) | (0x11 * (off + i + 1));
        bool ok = done && d1 == ex;
        if (be) ok = in_handler && be_t0 >= 0;                       // the bus error taken (memory checked below: no store)
        std::string why;
        if (!done) why += " (no completion)";
        if (done && d1 != ex && !be) { char b[64]; snprintf(b, sizeof b, " D1 %08x expected %08x", d1, ex); why += b; }
        if (be && !in_handler) why += " (no bus error exception)";
        static const uint8_t wv[4] = {0xa1, 0xb2, 0xc3, 0xd4};
        for (int i = 0; i < 6; i++) {
            uint8_t e = (i >= off && i < off + nb && !be) ? wv[4 - nb + (i - off)] : 0;
            if (mem[DST + i] != e) { ok = false; char b[48]; snprintf(b, sizeof b, " M%x %02x/%02x", DST + i, mem[DST + i], e); why += b; }
        }
        // bus cycles: the read cycles then the write cycles of the operand, by the 68020 rules
        int ci = 0;
        for (int rw = 1; rw >= 0 && !be; rw--) {
            uint32_t base = (rw ? SRC : DST) + off;
            // a long operand read is one request (checkpoint 4b); a long write is two word requests, high word first
            // (REPORT.md "Checkpoint 4b"): each request is sized and split by the port as on the 68020
            int nrq = (nb == 4 && !rw) ? 2 : 1;
            for (int rq = 0; rq < nrq; rq++) {
            int left = nrq == 2 ? 2 : nb; uint32_t ad = base + 2 * rq;
            while (left > 0) {
                int o = ad & 3, k = (port == 0 || port == 3) ? std::min(left, 4 - o) : port == 1 ? std::min(left, 2 - (o & 1)) : 1;
                if (ci >= (int)cyc.size()) { ok = false; why += " (missing cycle)"; break; }
                Cyc &c = cyc[ci++];
                cycles_checked++;
                if ((c.a & 0xfffff) != ad || (c.siz ? c.siz : 4) != left || c.rw != rw) {
                    ok = false; char b[96]; snprintf(b, sizeof b, " cycle %d: %05x SIZ%d %c (expected %05x SIZ%d %c)", ci - 1, c.a & 0xfffff, c.siz,
                                                      c.rw ? 'r' : 'w', ad, left & 3, rw ? 'r' : 'w'); why += b;
                }
                // cycle timing with no wait states (MC68020 User's Manual 5.3.1 / 5.3.2; CPU clock = 4 clk here): a 3-clock
                // cycle, AS low for 2 clocks (S1-S4; cp5: every port - the 68020 has no STERM); the next cycle of a sized
                // request starts 3 clocks later; read: DS with AS (S1), DBEN half a clock later (S2); write: DBEN with AS,
                // DS one clock after AS (S3)
                if (wmax == 0) {
                    long as_w = c.t1 - c.t0, want = 8;
                    if (as_w != want) { ok = false; char b[80]; snprintf(b, sizeof b, " cycle %d: AS %ld clk (expected %ld)", ci - 1, as_w, want); why += b; }
                    if (left != (nrq == 2 ? 2 : nb) && ci >= 2) {
                        long d = c.t0 - cyc[ci - 2].t0, wd = 12;
                        if (d != wd) { ok = false; char b[80]; snprintf(b, sizeof b, " cycle %d: %ld clk after the last (expected %ld)", ci - 1, d, wd); why += b; }
                    }
                    long ds_d = c.tds - c.t0, db_d = c.tdb - c.t0, ds_w = rw ? 0 : 4, db_w = rw ? 2 : 0;
                    if (c.tds < 0 || ds_d != ds_w) { ok = false; char b[80]; snprintf(b, sizeof b, " cycle %d: DS %ld clk after AS (expected %ld)", ci - 1, ds_d, ds_w); why += b; }
                    if (EC020 ? c.tdb >= 0 : (c.tdb < 0 || db_d != db_w)) { ok = false; char b[80]; snprintf(b, sizeof b, " cycle %d: DBEN %ld clk after AS (expected %ld)", ci - 1, db_d, db_w); why += b; }
                    timed++;
                }
                ad += k; left -= k;
            }
            }
        }
        if (ci != (int)cyc.size() && !be) { ok = false; why += " (extra cycles)"; }
        if (!ok) fails++;
        if (verbose && !ok) for (auto &c : cyc) printf("    %05x SIZ%d %c\n", c.a & 0xfffff, c.siz, c.rw ? 'r' : 'w');
        if (!ok || verbose) printf("port %s size %c offset %d: %s%s (%zu cycles)\n", port == 3 ? "32b" : port == 0 ? "32" : port == 1 ? "16" : "8",
                                   "BWL"[sz], off, ok ? "ok" : "FAIL", why.c_str(), cyc.size());
        delete t;
    }
    printf("dsz020%s: %d combinations (port 32 / 16 / 8 / 32b x byte / word / long x offset 0-3, read and write), %ld bus cycles checked (%ld timed), %d failures\n", be == 3 ? " -be 3 (BERR with DSACK)" : be == 4 ? " -be 4 (late BERR)" : "",
           combos, cycles_checked, timed, fails);
    return fails != 0;
}

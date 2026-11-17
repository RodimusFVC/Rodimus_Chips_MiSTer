// Copyright (C) 2026 Rodimus
// m68ksv directed test of the bus retry (re-run), MC68000 User's Manual 5.4.2: BERR asserted together with HALT
// during a bus cycle ends the cycle; the processor waits with no bus cycle while HALT is asserted and then runs the
// same cycle again (same address, function code, R/W, data strobes and, for a write, data); BERR is negated at least
// one clock before HALT. A read-modify-write (TAS) cycle is never retried: BERR + HALT there is a bus error.
// fx68k has no retry, so there is no lockstep oracle: this test checks the manual's sequence. Pass / fail per item.
//   retry [-bus8]      (-bus8: the model is an 8-bit configuration, memory on D7-D0 with A0 / DS_n)
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <vector>

static uint8_t mem[1 << 24];
static Vm68ksv *top;
static uint64_t n;
static bool bus8 = false;
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v & 0xff; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v & 0xffff); }

struct Cyc { uint32_t a; int fc, rw, strobes; uint16_t d; uint64_t start, end; bool berr; };
static std::vector<Cyc> cyc;
static uint32_t fault_addr = 0xffffffff; static int fault_rw = -1;   // next cycle to this address / direction faults
static int halt_hold = 0;                // clocks HALT stays asserted after BERR is negated
static uint64_t halt_neg_at = 0;
static int state = 0;                    // 0 idle, 1 faulting cycle (BERR + HALT), 2 BERR off / HALT held
static int cnt = 0;
static bool in_cyc = false;

static uint32_t addr() { return bus8 ? ((((uint32_t)top->A << 1) | top->A0) & 0xffffff) : (((uint32_t)top->A << 1) & 0xfffffe); }
static int strobes() { return bus8 ? (top->DS_n ? 0 : 1) : ((top->UDS_n ? 0 : 2) | (top->LDS_n ? 0 : 1)); }

static void tick() {
    uint32_t a = addr();
    top->D_i = bus8 ? mem[a] : ((mem[a] << 8) | mem[a + 1]);
    bool as = !top->AS_n;
    if (as && !in_cyc) {
        in_cyc = true;
        cyc.push_back({a, top->FC, top->RW, 0, 0, n, 0, false});
        if (state == 0 && a == fault_addr && (fault_rw < 0 || fault_rw == top->RW)) { state = 1; cyc.back().berr = true; fault_addr = 0xffffffff; }
    }
    if (in_cyc) { cyc.back().strobes |= strobes(); if (!top->RW && strobes()) cyc.back().d = top->D_o; }
    top->DTACK_n = !(as && state != 1);
    top->BERR_n = state != 1;
    top->HALT_n_i = !(state == 1 || state == 2);
    if (!as && in_cyc) { in_cyc = false; cyc.back().end = n; if (state == 1) { state = 2; cnt = 2 + halt_hold; } }
    // BERR negated when the faulted cycle ends; HALT two clocks + halt_hold clocks later
    if (state == 2 && (n & 1) == 0 && cnt-- <= 0) { state = 0; halt_neg_at = n; }
    if (state == 2) top->BERR_n = 1;
    top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1;
    top->clk = 0; top->eval(); top->clk = 1; top->eval();
    n++;
    a = addr();
    if (!top->AS_n && !top->RW) {
        if (bus8) { if (!top->DS_n) mem[a] = top->D_o & 0xff; }
        else { if (!top->UDS_n) mem[a] = top->D_o >> 8; if (!top->LDS_n) mem[a + 1] = top->D_o & 0xff; }
    }
}
static uint32_t rreg(int k) {
    top->dbg_ra = k; top->cen_p = 0; top->cen_n = 0;
    top->clk = 0; top->eval(); top->clk = 1; top->eval();
    return top->dbg_rd;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "-bus8")) bus8 = true;
    top = new Vm68ksv;
    top->IPL_n = 7; top->BR_n = 1; top->BGACK_n = 1; top->VPA_n = 1; top->tl_en = 0; top->MODE = !bus8;
    int fails = 0, items = 0;
    auto check = [&](const char *what, bool ok, const char *detail) {
        items++; fails += !ok; printf("retry: %-58s %s  %s\n", what, ok ? "ok  " : "FAIL", detail);
    };
    w32(0, 0x1000); w32(4, 0x400); w32(8, 0x600);              // SSP, PC, bus error vector
    w16(0x600, 0x7a77); w16(0x602, 0x60fe);                     // MOVEQ #$77,D5 ; BRA *
    uint32_t p = 0x400;
    auto o = [&](uint16_t v) { w16(p, v); p += 2; };
    o(0x3039); o(0x0000); o(0x2000);                            // MOVE.W $2000,D0      (read retried)
    o(0x33fc); o(0x1234); o(0x0000); o(0x2100);                 // MOVE.W #$1234,$2100  (write retried)
    o(0x2239); o(0x0000); o(0x2200);                            // MOVE.L $2200,D1      (second word retried twice)
    o(0x4e71);                                                  // NOP
    o(0x4af9); o(0x0000); o(0x2300);                            // TAS $2300            (no retry: bus error)
    o(0x60fe);                                                  // BRA *
    w16(0x2000, 0xbeef); w32(0x2200, 0xcafef00d); mem[0x2300] = 0x05;
    top->RESET_n_i = 0; top->HALT_n_i = 0; top->BERR_n = 1; top->DTACK_n = 1;
    for (int i = 0; i < 40; i++) { top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1; top->clk = 0; top->eval(); top->clk = 1; top->eval(); n++; }
    top->RESET_n_i = 1; top->HALT_n_i = 1;
    char b[200];
    // planned faults, armed one after the other: read, write, the long's second word twice, TAS
    struct F { uint32_t a; int rw, hold; } plan[] = {{0x2000, 1, 10}, {0x2100, 0, 3}, {0x2202, 1, 6}, {0x2202, 1, 1}, {0x2300, -1, 4}};
    std::vector<uint64_t> negs;
    int next = 0;
    for (int i = 0; i < 8000; i++) {
        if (state == 0 && fault_addr == 0xffffffff && next < 5) {
            if (next) negs.push_back(halt_neg_at);
            fault_addr = plan[next].a; fault_rw = plan[next].rw; halt_hold = plan[next].hold; next++;
        }
        tick();
    }
    negs.push_back(halt_neg_at);
    std::vector<size_t> fk;
    for (size_t k = 0; k < cyc.size(); k++) if (cyc[k].berr) fk.push_back(k);
    auto pair_ok = [&](size_t i) { const Cyc &f = cyc[fk[i]], &r = cyc[fk[i] + 1];
        return r.a == f.a && r.fc == f.fc && r.rw == f.rw && r.strobes == f.strobes && (f.rw || r.d == f.d) && r.start > negs[i]; };
    snprintf(b, sizeof b, "%zu faulted cycles (5 planned)", fk.size());
    check("all planned faults happened", fk.size() == 5, b);
    if (fk.size() == 5) {
        const char *nm[4] = {"read", "write", "long, second word (1st retry)", "long, second word (2nd retry)"};
        for (int i = 0; i < 4; i++) {
            const Cyc &f = cyc[fk[i]], &r = cyc[fk[i] + 1];
            snprintf(b, sizeof b, "A %06x FC %d RW %d strobes %x D %04x | re-run A %06x FC %d RW %d strobes %x D %04x | end %llu HALT off %llu AS %llu",
                     f.a, f.fc, f.rw, f.strobes, f.d, r.a, r.fc, r.rw, r.strobes, r.d, (unsigned long long)f.end,
                     (unsigned long long)negs[i], (unsigned long long)r.start);
            char w[80]; snprintf(w, sizeof w, "%s: same cycle re-run after HALT", nm[i]);
            check(w, pair_ok(i), b);
        }
        // no bus activity between the end of a faulted cycle and the re-run
        bool quiet = true;
        for (int i = 0; i < 4; i++) quiet = quiet && (cyc[fk[i] + 1].start > cyc[fk[i]].end);
        check("no bus cycle between the faulted cycle and its re-run", quiet, "");
    }
    uint32_t d0 = rreg(0), d1 = rreg(1), d5 = rreg(5);
    snprintf(b, sizeof b, "D0 %08x D1 %08x mem[2100] %02x%02x", d0, d1, mem[0x2100], mem[0x2101]);
    check("results: D0, D1 and the written word correct", (d0 & 0xffff) == 0xbeef && d1 == 0xcafef00d &&
          mem[0x2100] == 0x12 && mem[0x2101] == 0x34, b);
    int n2300 = 0; for (auto &c : cyc) n2300 += c.a == 0x2300;
    snprintf(b, sizeof b, "D5 %08x (77 = bus error handler ran), cycles at 2300: %d", d5, n2300);
    check("TAS: BERR + HALT takes the bus error exception, no re-run", d5 == 0x77 && n2300 == 1, b);
    printf("retry: %d / %d pass%s\n", items - fails, items, bus8 ? " (8-bit bus)" : "");
    delete top;
    return fails != 0;
}

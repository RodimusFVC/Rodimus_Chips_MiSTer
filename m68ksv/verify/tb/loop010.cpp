// Copyright (C) 2026 Rodimus
// m68ksv CPU=68010: directed loop-mode test (MC68010 data sheet 7.1.3 / User's Manual appendix A).
// Per loopable instruction class: a DBcc loop with displacement -4 runs; measured are the clocks of one loop pass
// (looped instruction start to the next one), the pass that ends the loop (count expired / condition true), and the
// opcode fetches of the three loop words while loop mode runs (must be 0). Expected times: data sheet tables 7-6 /
// 7-8 / 7-10 / 7-14 / 7-16 / 7-20. Plus: an interrupt during the loop (taken after a DBcc, never after the looped
// instruction; the loop is fetched again after RTE), a bus error on an operand read in the loop + RTE (format 8: the
// faulted cycle re-run, the loop words not fetched again), T set (no loop mode), a looped instruction that writes the
// DBcc counter. Own code.
#include "Vm68ksv.h"
#include "verilated.h"
#include "m68ksv_ualabels.h"
#include <cstdio>
#include <cstring>
#include <vector>

static uint8_t mem[1 << 24];
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static uint16_t r16(uint32_t a) { return (mem[a] << 8) | mem[a + 1]; }
static const uint32_t L = 0x1020;      // address of the looped instruction

struct Res {
    std::vector<long> starts;          // clock of each start of the looped instruction while the loop runs
    long t_after = -1;                 // clock of the dispatch after the loop
    int loop_fetch = 0;                // opcode fetches of the loop words after the first loop-mode DBcc
    int dbl = 0;                       // DBcc executions in loop mode
    int iack = 0; uint32_t int_pc = 0; // interrupt acknowledged; PC it stacked
    int berr = 0, fetch_after_rte = 0;
    uint32_t d0 = 0, d1 = 0, a0 = 0, a1 = 0;
    bool done = false;
};

// run: program at 0x1000 (setup), loop at L, STOP after it. irq_at: start of the loop pass on which IPL 1 is raised
// (0: none); berr_addr: operand read address that ends with BERR once (0: none)
static bool dbg = false;
static Res run(Vm68ksv *top, uint16_t op, uint16_t dbcc, int count, uint16_t sr, int irq_at, uint32_t berr_addr,
               const std::vector<uint16_t> &data) {
    memset(mem, 0, sizeof mem);
    w32(0, 0x8000); w32(4, 0x1000);
    for (int v = 2; v < 64; v++) w32(v * 4, 0x700);
    w32(2 * 4, 0x600);                                      // bus error: RTE (68010: re-runs the faulted cycle)
    w16(0x600, 0x4e73); w16(0x700, 0x4e73);                 // interrupt / trace / others: RTE
    uint32_t p = 0x1000;
    auto o = [&](uint16_t v) { w16(p, v); p += 2; };
    o(0x207c); o(0x0000); o(0x4000);                        // MOVEA.L #$4000,A0
    o(0x227c); o(0x0000); o(0x5000);                        // MOVEA.L #$5000,A1
    o(0x7000 | (count & 0xff));                             // MOVEQ #count,D0
    o(0x7203);                                              // MOVEQ #3,D1
    o(0x46fc); o(sr);                                       // MOVE #sr,SR
    while (p < L) o(0x4e71);                                // NOP
    o(op); o(dbcc); o(0xfffc);                              // loop
    o(0x4e72); o(0x2700);                                   // STOP #$2700
    for (size_t i = 0; i < data.size(); i++) { w16(0x4000 + 2 * i, data[i]); w16(0x5000 + 2 * i, data[i] ^ 0x1111); }
    // -(An) forms: the data below the pointers as well
    for (size_t i = 0; i < data.size(); i++) { w16(0x4000 - 2 - 2 * i, data[i]); w16(0x5000 - 2 - 2 * i, data[i] ^ 0x2222); }

    Res r;
    top->RESET_n_i = 0; top->HALT_n_i = 0; top->DTACK_n = 1; top->BERR_n = 1; top->VPA_n = 1; top->IPL_n = 7;
    top->BR_n = 1; top->BGACK_n = 1; top->MODE = 1;
    long n = 0;
    bool in_cyc = false, berr_done = false, rte_seen = false, inloop = false, fin = false, irq_on = false;
    int pend_fin = 0;
    for (; n < 4000000; n++) {
        if (n == 40) { top->RESET_n_i = 1; top->HALT_n_i = 1; }
        top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1;
        top->clk = 0; top->eval();
        fin = top->dbg_fin;
        top->clk = 1; top->eval();
        long clk = n / 2;
        if (fin) {
            int upc = top->dbg_upc; uint32_t pc = top->dbg_pc & 0xffffff;
            if (dbg && clk < 3000) printf("  %6ld disp upc %4d PC %06x IR %04x\n", clk, upc, pc, top->dbg_ir);
            if (upc >= UA10_DBL4 && upc <= UA10_DBL1) { r.dbl++; inloop = true; }
            if (pc == L && upc != UA_EXC_TRACE) {
                r.starts.push_back(clk);
                if (irq_at && (int)r.starts.size() == irq_at && !irq_on) { top->IPL_n = 6; irq_on = true; }
            }
            if (pc == L + 6 && r.t_after < 0) r.t_after = clk;
        }
        // bus: AS low = a cycle; serve it, zero wait states
        if (!top->AS_n) {
            uint32_t a = (top->A << 1) & 0xffffff;
            if (!in_cyc) {
                in_cyc = true;
                if (dbg && clk < 3000) printf("  %6ld bus %06x FC%d %c %04x\n", clk, a, top->FC, top->RW ? 'r' : 'w', top->RW ? r16(a & ~1u) : 0);
                bool opf = (top->FC == 6 || top->FC == 2);
                if (opf && a >= L && a < L + 6 && inloop) { r.loop_fetch++; if (rte_seen) r.fetch_after_rte++; }
                if (top->FC == 7) { r.iack++; top->IPL_n = 7; irq_on = false; }
                if (a == 0x600) rte_seen = true;
            }
            if (top->FC == 7) { top->VPA_n = 0; }
            else if (berr_addr && a == berr_addr && top->RW && !berr_done && (top->FC == 5 || top->FC == 1)) {
                if (top->BERR_n) r.berr++;
                top->BERR_n = 0;
            } else {
                if (top->RW) top->D_i = r16(a & ~1u);
                else if (!top->UDS_n || !top->LDS_n) {
                    if (!top->UDS_n) mem[a & ~1u] = top->D_o >> 8;
                    if (!top->LDS_n) mem[(a & ~1u) + 1] = top->D_o;
                    if (dbg && clk < 3000 && !top->DTACK_n == 0) printf("  %6ld   wdata %04x\n", clk, top->D_o);
                }
                top->DTACK_n = 0;
            }
        } else {
            if (in_cyc && !top->BERR_n) berr_done = true;
            in_cyc = false; top->DTACK_n = 1; top->BERR_n = 1; top->VPA_n = 1;
        }
        if (r.t_after >= 0 && clk > r.t_after + 200) break;
    }
    // stacked PC of the interrupt: the handler's RTE frame was at SSP - 8 .. (format 0); read it from memory
    r.int_pc = (r16(0x8000 - 6) << 16) | r16(0x8000 - 4);
    auto rdreg = [&](int k) { top->dbg_ra = k; top->cen_p = 0; top->cen_n = 0;
                              top->clk = 0; top->eval(); top->clk = 1; top->eval(); return (uint32_t)top->dbg_rd; };
    r.d0 = rdreg(0); r.d1 = rdreg(1); r.a0 = rdreg(8); r.a1 = rdreg(9);
    r.done = r.t_after >= 0;
    return r;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vm68ksv *top = new Vm68ksv;
    if (argc > 1 && !strcmp(argv[1], "-d")) dbg = true;
    struct C { const char *name; uint16_t op; int cont, term_cc, term_exp; };
    // expected: loop continued (valid count, cc false) / terminated with cc true / terminated with count expired
    static const C cs[] = {
        {"MOVE.W (A0)+,(A1)+", 0x32d8, 14, 20, 18}, {"MOVE.W (A0),(A1)", 0x3290, 14, 20, 18},
        {"MOVE.W (A0)+,-(A1)", 0x3318, 16, 22, 20}, {"MOVE.W -(A0),-(A1)", 0x3320, 18, 24, 22},
        {"MOVE.W D1,(A1)+", 0x32c1, 10, 18, 16}, {"MOVE.B (A0)+,(A1)+", 0x12d8, 14, 20, 18},
        {"MOVE.L (A0)+,(A1)+", 0x22d8, 22, 28, 24}, {"MOVE.L -(A0),-(A1)", 0x2320, 26, 32, 28},
        {"MOVE.L D1,(A1)", 0x2281, 14, 20, 18},
        {"ADD.W (A0)+,D1", 0xd258, 16, 22, 20}, {"ADD.L (A0)+,D1", 0xd298, 22, 28, 26},
        {"SUB.L (A0)+,D1", 0x9298, 20, 26, 24}, {"AND.W -(A0),D1", 0xc260, 18, 24, 22},
        {"CMP.W (A0)+,D1", 0xb258, 12, 18, 16}, {"CMP.L (A0)+,D1", 0xb298, 18, 24, 20},
        {"ADDA.W (A0)+,A1", 0xd2d8, 18, 24, 22}, {"ADDA.L (A0)+,A1", 0xd3d8, 22, 28, 26},
        {"CMPA.W (A0)+,A1", 0xb2d8, 12, 18, 16}, {"CMPA.L (A0)+,A1", 0xb3d8, 18, 24, 20},
        {"ADD.W D1,(A0)+", 0xd358, 16, 22, 20}, {"EOR.L D1,(A0)+", 0xb398, 24, 30, 28},
        {"CLR.W (A0)+", 0x4258, 10, 18, 16}, {"CLR.L (A0)+", 0x4298, 14, 22, 20},
        {"NEG.W (A0)+", 0x4458, 16, 22, 20}, {"NOT.L (A0)+", 0x4698, 24, 30, 28},
        {"TST.W (A0)+", 0x4a58, 12, 18, 16}, {"TST.L (A0)+", 0x4a98, 18, 24, 20},
        {"NBCD (A0)+", 0x4818, 18, 24, 22}, {"ASR.W (A0)+", 0xe0d8, 18, 24, 22}, {"ROXL.W -(A0)", 0xe5e0, 20, 26, 24},
        {"CMPM.W (A0)+,(A1)+", 0xb348, 14, 20, 18}, {"CMPM.L (A0)+,(A1)+", 0xb388, 24, 30, 26},
        {"ADDX.W -(A0),-(A1)", 0xd348, 22, 28, 26}, {"SUBX.L -(A0),-(A1)", 0x9388, 32, 38, 36},
        {"ABCD -(A0),-(A1)", 0xc308, 24, 30, 28},
    };
    int fails = 0;
    std::vector<uint16_t> nz(64, 0x1234);
    printf("%-22s %16s %16s %16s %s\n", "looped instruction", "continued m/ds", "cc true m/ds", "expired m/ds", "loop-word fetches in loop mode");
    for (auto &c : cs) {
        if (dbg) break;
        Res a = run(top, c.op, 0x51c8, 6, 0x2700, 0, 0, nz);            // DBF: runs to the count
        // cc true: DBNE on a looped instruction that sets Z from data (zero data, then a non-zero word at index 4)
        std::vector<uint16_t> z(64, 0); z[4] = 0x0080; z[60] = 0x0080;
        Res b = run(top, c.op, 0x56c8, 20, 0x2700, 0, 0, z);
        long cont = -1, term = -1, termc = -1;
        if (a.starts.size() >= 4) cont = a.starts[3] - a.starts[2];
        if (!a.starts.empty() && a.t_after >= 0) term = a.t_after - a.starts.back();
        bool ccx = b.t_after >= 0 && b.starts.size() >= 3 && b.starts.size() < 20;
        if (ccx) termc = b.t_after - b.starts.back();
        bool ok = (cont == c.cont) && a.loop_fetch == 0 && a.dbl >= 4 && a.d0 == 0xffffu;
        printf("%-22s %8ld / %-5d %8ld / %-5d %8ld / %-5d %d%s%s\n", c.name, cont, c.cont, ccx ? termc : -1L, c.term_cc,
               term, c.term_exp, a.loop_fetch, ok ? "" : "   FAIL (continued time / fetches / count)", ccx ? "" : "  (no cc-true exit for this class)");
        if (!ok) fails++;
    }
    // interrupt in the loop
    {
        Res r = run(top, 0x32d8, 0x51c8, 40, 0x2000, 6, 0, nz);
        bool ok = r.iack == 1 && r.int_pc == L && r.d0 == 0xffffu && r.a0 == 0x4000 + 2 * 41 && r.loop_fetch == 5 && r.dbl >= 30;
        printf("interrupt in loop mode: IACK %d, stacked PC %06x (looped instruction %06x), loop-word fetches after entry %d (5 = the loop entered again after RTE: L, L+2, L+4, L, L+2), D0 %04x A0 %06x: %s\n",
               r.iack, r.int_pc, L, r.loop_fetch, r.d0 & 0xffff, r.a0, ok ? "ok" : "FAIL");
        if (!ok) fails++;
    }
    // bus error on an operand read inside the loop, RTE re-runs it (format 8), the loop words are not fetched again
    {
        Res r = run(top, 0x32d8, 0x51c8, 20, 0x2700, 0, 0x4000 + 2 * 8, nz);
        bool ok = r.berr == 1 && r.fetch_after_rte == 0 && r.loop_fetch == 0 && r.d0 == 0xffffu && r.a0 == 0x4000 + 2 * 21 &&
                  r16(0x5000 + 2 * 8) == 0x1234;
        printf("bus error in loop mode + RTE: BERR %d, loop words fetched after RTE %d (loop mode total %d), D0 %04x A0 %06x, word moved %04x: %s\n",
               r.berr, r.fetch_after_rte, r.loop_fetch, r.d0 & 0xffff, r.a0, r16(0x5000 + 2 * 8), ok ? "ok" : "FAIL");
        if (!ok) fails++;
    }
    // trace: no loop mode
    {
        Res r = run(top, 0x32d8, 0x51c8, 6, 0xa700, 0, 0, nz);
        bool ok = r.dbl == 0 && r.d0 == 0xffffu;
        printf("T set: DBcc executions in loop mode %d, D0 %04x: %s\n", r.dbl, r.d0 & 0xffff, ok ? "ok" : "FAIL");
        if (!ok) fails++;
    }
    // looped instruction writing the DBcc counter (ADD.W (A0)+,D0): loop mode runs, the slow DBcc path keeps the count
    {
        std::vector<uint16_t> zz(64, 0);
        Res r = run(top, 0xd058, 0x51c8, 6, 0x2700, 0, 0, zz);
        bool ok = r.d0 == 0xffffu && r.a0 == 0x4000 + 2 * 7 && r.loop_fetch == 0;
        printf("looped ADD.W (A0)+,D0 (counter written by the looped instruction): D0 %04x A0 %06x loop-word fetches %d: %s\n",
               r.d0 & 0xffff, r.a0, r.loop_fetch, ok ? "ok" : "FAIL");
        if (!ok) fails++;
    }
    printf("loop010: %d failures\n", fails);
    delete top;
    return fails ? 1 : 0;
}

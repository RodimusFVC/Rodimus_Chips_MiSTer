// Copyright (C) 2026 Rodimus
// Fleet wrapper test: x86sv_mcl86 against x86sv_i8088 running the same program.
// x86sv_mcl86 is driven by a req / ack bus model that acknowledges D core clocks after req; the reference
// x86sv_i8088 gets READY low for exactly k = max(0, ceil((D + 3 - 3P) / P)) Tw per bus cycle (P = core clocks per
// cpu_clk period: req rises 2 clocks after the T1 ce, the acknowledge is seen 1 clock later, READY is sampled at the
// 3rd ce after T1). Every bus cycle (ce of T1, type, address, write data) and the final memory must be identical.
// x86sv_i8086 runs the same program with 0-3 Tw per bus cycle: its data cycles (type, address, BHE, data) must not
// depend on the wait states, it must take the INTA pair, and its final memory must equal the 8088's. x86sv_v20 and
// x86sv_v30 likewise; their final memory must equal each other's (NEC MUL / DIV flags differ from the 8088's).
//   fleet [-v]
#include "Vtb_fleet.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static Vtb_fleet *top;
static uint8_t ref88[1 << 20];          // final memory of the 8088 reference run

struct Cyc { long ce; int type; uint32_t addr; int data; };

static void prog(uint8_t *m) {
    memset(m, 0x90, 1 << 20);
    const uint8_t rv[] = {0xEA, 0x00, 0x00, 0x00, 0x01};                  // FFFF0: JMP 0100:0000
    memcpy(m + 0xFFFF0, rv, sizeof rv);
    const uint8_t p[] = {0xFB, 0xB8, 0x34, 0x12, 0xA3, 0x00, 0x02, 0x03, 0x06, 0x00, 0x02, 0xE4, 0x40, 0xE6, 0x41,
                         0xB9, 0x05, 0x00, 0xBE, 0x00, 0x02, 0xBF, 0x00, 0x03, 0xF3, 0xA4, 0xB1, 0x07, 0xF6, 0xE1,
                         0x50, 0x5B, 0xF6, 0xF1, 0xCD, 0x21, 0xF4, 0xF4, 0xF4};
    memcpy(m + 0x01000, p, sizeof p);
    const uint8_t v21[] = {0x80, 0x00, 0x00, 0x01}, v40[] = {0x90, 0x00, 0x00, 0x01};
    memcpy(m + 0x84, v21, 4);
    memcpy(m + 0x100, v40, 4);
    m[0x01080] = 0xCF;                                                    // IRET
    m[0x01090] = 0xCF;
}

static uint8_t rdval(const uint8_t *m, int type, uint32_t a, int &inta) {
    if (type == 0) return (inta++ & 1) ? 0x40 : 0xFF;                     // INTA: type in the second cycle
    if (type == 1) return (uint8_t)(a * 7 + 0x11);
    return m[a & 0xFFFFF];
}

static bool run(int P, int D, bool verbose) {
    static uint8_t mm[1 << 20], mr[1 << 20];
    prog(mm); prog(mr);
    int k = (D + 3 - 3 * P) > 0 ? (D + 3 - 3 * P + P - 1) / P : 0;
    std::vector<Cyc> cm, cr;
    long ces = 0;
    int ack_at = -1, inta_m = 0, inta_r = 0;
    bool req_q = false, ale_q = false, cpu_q = false, cyc_on = false;
    int n_since = 0, rtype = 7;
    uint32_t raddr = 0;
    const long clocks = (4000L + 700L * k) * P, ix = 900L + 700L * k;   // intr raised while halted
    for (long t = 0; t < clocks; t++) {
        bool cpu = (t % P) < (P + 1) / 2;
        bool ce = cpu && !cpu_q;
        top->reset = t < 8L * P;
        top->cpu_clk = cpu;
        top->intr = ces >= ix && ces < ix + 100;
        top->r_ce = ce;
        // mcl86 side: acknowledge D clocks after req rises
        top->m_ack = 0;
        top->eval();
        if (top->m_req && !req_q) {
            cm.push_back({ces, top->m_type, top->m_addr, (top->m_type == 2 || top->m_type == 6) ? top->m_wdata : -1});
            ack_at = (int)(t + D);
        }
        if (top->m_req && t == ack_at) {
            int ty = top->m_type;
            top->m_ack = 1;
            top->m_rdata = rdval(mm, ty, top->m_addr, inta_m);
            if (ty == 6) mm[top->m_addr] = top->m_wdata;
        }
        req_q = top->m_req;
        // reference side: READY low for the first k decision ce's of each cycle
        if (top->r_ale && !ale_q) {
            cyc_on = true; n_since = 0; rtype = top->r_cyc; raddr = top->r_addr;
            cr.push_back({ces, rtype, raddr, -1});
        }
        bool ready = !(cyc_on && n_since >= 2 && n_since - 2 < k);
        top->r_ready = ready;
        int ir = inta_r;
        top->r_din = rdval(mr, rtype, raddr, ir);
        top->eval();
        if (ce && ready && cyc_on && n_since >= 2) {
            if (rtype == 0) inta_r++;
            if (!top->r_wr_n) { mr[raddr] = top->r_dout; cr.back().data = top->r_dout; }
            if (!top->r_iow_n) cr.back().data = top->r_dout;
            cyc_on = false;
        }
        if (ce && cyc_on) n_since++;
        ale_q = top->r_ale;
        top->clk = 1; top->eval(); top->clk = 0; top->eval();
        if (ce) ces++;
        cpu_q = cpu;
    }
    int ints0 = 0;
    for (auto &c : cr) if (c.type == 0) ints0++;
    bool ok = cm.size() == cr.size() && cm.size() > 100 && ints0 == 2;
    size_t bad = 0;
    for (size_t i = 0; ok && i < cm.size(); i++) {
        const Cyc &a = cm[i], &b = cr[i];
        if (a.ce != b.ce || a.type != b.type || a.addr != b.addr || a.data != b.data) { ok = false; bad = i; }
    }
    bool mem = memcmp(mm, mr, sizeof mm) == 0;
    if (P == 3 && D == 0) memcpy(ref88, mr, sizeof mr);
    int ints = 0;
    for (auto &c : cr) if (c.type == 0) ints++;
    printf("P=%-2d D=%-2d Tw/cycle=%d  cycles %zu / %zu  INTA %d  %s%s\n", P, D, k, cm.size(), cr.size(), ints,
           ok && mem ? "pass" : "FAIL", mem ? "" : " (memory differs)");
    if ((!ok || verbose) && !cm.empty()) {
        size_t a = bad > 3 ? bad - 3 : 0;
        for (size_t i = a; i < a + 8 && i < cm.size() && i < cr.size(); i++)
            printf("   %zu  mcl86 ce%ld t%d %05X %d   i8088 ce%ld t%d %05X %d\n", i, cm[i].ce, cm[i].type, cm[i].addr,
                   cm[i].data, cr[i].ce, cr[i].type, cr[i].addr, cr[i].data);
    }
    return ok && mem;
}

// one wrapper's ports (i8086 / v20 / v30)
struct Port {
    CData *ce, *ready, *cyc, *bhe, *ale, *wr, *iow; SData *din, *dout; IData *addr; bool bus8;
};
static uint8_t refnec[1 << 20];         // final memory of the first V20 run

// a wrapper with k Tw per bus cycle (ce every P clocks); returns its non-code bus cycles; ok = memory equals ref
static std::vector<Cyc> run16(const Port &pt, const uint8_t *ref, int P, int k, bool &ok, int &ints) {
    static uint8_t m[1 << 20];
    prog(m);
    std::vector<Cyc> cy;
    long ces = 0;
    bool ale_q = false, cyc_on = false;
    int n_since = 0, type = 7, bhe = 1, inta = 0;
    uint32_t addr = 0;
    ints = 0;
    const long clocks = (4000L + 700L * k) * P, ix = 900L + 700L * k;
    for (long t = 0; t < clocks; t++) {
        bool ce = (t % P) == 0;
        top->reset = t < 8L * P;
        top->intr = ces >= ix && ints == 0;      // held until acknowledged
        *pt.ce = ce;
        top->eval();
        if (*pt.ale && !ale_q) {
            cyc_on = true; n_since = 0; type = *pt.cyc; addr = *pt.addr; bhe = *pt.bhe;
            if (type == 0) ints++;
        }
        bool ready = !(cyc_on && n_since >= 2 && n_since - 2 < k);
        *pt.ready = ready;
        uint16_t d;
        if (type == 0) d = (inta & 1) ? 0x40 : 0xFF;
        else if (type == 1) d = (uint16_t)(((addr & ~1u) * 7 + 0x11) & 0xFF) | ((((addr | 1u) * 7 + 0x11) & 0xFF) << 8);
        else if (pt.bus8) d = m[addr & 0xFFFFF];
        else d = m[addr & 0xFFFFE] | (m[(addr | 1) & 0xFFFFF] << 8);
        if (pt.bus8 && type == 1) d = (uint16_t)((addr * 7 + 0x11) & 0xFF);
        *pt.din = d;
        top->eval();
        if (ce && ready && cyc_on && n_since >= 2) {
            if (type == 0) inta++;
            int data = -1;
            if (!*pt.wr || !*pt.iow) {
                data = *pt.dout;
                if (!*pt.wr) {
                    if (pt.bus8) m[addr & 0xFFFFF] = *pt.dout & 0xFF;
                    else {
                        if (!(addr & 1)) m[addr] = *pt.dout & 0xFF;
                        if (!bhe) m[(addr | 1) & 0xFFFFF] = *pt.dout >> 8;
                    }
                }
            } else if (type != 4) data = d;
            if (type != 4) cy.push_back({0, type * 2 + bhe, addr, data});
            cyc_on = false;
        }
        if (ce && cyc_on) n_since++;
        ale_q = *pt.ale;
        top->clk = 1; top->eval(); top->clk = 0; top->eval();
        if (ce) ces++;
    }
    if (ref == refnec && !refnec[0x1000]) memcpy(refnec, m, sizeof m);   // the first NEC run is the reference
    ok = memcmp(m, ref, sizeof m) == 0;
    return cy;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    bool v = argc > 1 && !strcmp(argv[1], "-v");
    top = new Vtb_fleet;
    int fails = 0;
    for (int P : {3, 4, 12})
        for (int D : {0, 1, 3, 6, 8, 13, 30}) {
            top->clk = 0; top->eval();
            if (!run(P, D, v)) fails++;
        }
    const Port p86 = {&top->w_ce, &top->w_ready, &top->w_cyc, &top->w_bhe_n, &top->w_ale, &top->w_wr_n, &top->w_iow_n,
                      &top->w_din, &top->w_dout, &top->w_addr, false};
    const Port pv20 = {&top->v_ce, &top->v_ready, &top->v_cyc, &top->v_bhe_n, &top->v_ale, &top->v_wr_n, &top->v_iow_n,
                       &top->v_din, &top->v_dout, &top->v_addr, true};
    const Port pv30 = {&top->x_ce, &top->x_ready, &top->x_cyc, &top->x_bhe_n, &top->x_ale, &top->x_wr_n, &top->x_iow_n,
                       &top->x_din, &top->x_dout, &top->x_addr, false};
    struct { const char *name; const Port *p; const uint8_t *ref; const char *refname; } cfgs[] = {
        {"i8086", &p86, ref88, "= 8088"}, {"v20", &pv20, refnec, "= V20"}, {"v30", &pv30, refnec, "= V20"}};
    memset(refnec, 0, sizeof refnec);
    for (auto &cf : cfgs) {
        std::vector<Cyc> base;
        for (int P : {1, 3})
            for (int k : {0, 1, 3}) {
                top->clk = 0; top->eval();
                bool memok; int ints;
                std::vector<Cyc> c = run16(*cf.p, cf.ref, P, k, memok, ints);
                if (base.empty()) base = c;
                bool same = c.size() == base.size() && c.size() > 20;
                for (size_t i = 0; same && i < c.size(); i++)
                    if (c[i].type != base[i].type || c[i].addr != base[i].addr || c[i].data != base[i].data) same = false;
                bool ok = same && memok && ints == 2;
                printf("%-5s P=%d Tw/cycle=%d  data cycles %zu  INTA %d  memory %s  %s\n", cf.name, P, k, c.size(), ints,
                       memok ? cf.refname : "differs", ok ? "pass" : "FAIL");
                if (!ok) fails++;
            }
    }
    printf("fleet wrappers: %s\n", fails ? "FAIL" : "pass");
    delete top;
    return fails ? 1 : 0;
}

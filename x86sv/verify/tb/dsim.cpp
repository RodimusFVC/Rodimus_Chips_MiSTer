// Copyright (C) 2026 Rodimus
// Directed tests for x86sv: reset, wait states (READY), INTR / INTA, NMI, single-step, HLT, WAIT, LOCK.
// Expectations come from the Intel documentation, cited per test (see REPORT.md):
//   [DS]  8088 datasheet, order 231456 (pin descriptions, Figure 9, "Processor Reset and Initialization")
//   [PR]  iAPX 86/88, 186/188 User's Manual Programmer's Reference, order 210911-001 (section 4.3, Table 4-1/4-2,
//         instruction reference)
//   dsim [-v]   (-v prints the bus-cycle list of every test)
#include "Vtb_x86.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

static Vtb_x86 *top;
static uint8_t mem[1 << 20];
static bool verbose = false;

enum { S_INTA = 0, S_IOR = 1, S_IOW = 2, S_HALT = 3, S_CODE = 4, S_MEMR = 5, S_MEMW = 6, S_PASV = 7 };
static const char *sname[] = {"INTA", "IOR", "IOW", "HALT", "CODE", "MEMR", "MEMW", "PASV"};

struct Clk {                            // one CPU clock as seen on the pins
    int ts, ale, s, rd, wra, wr, io, inta, lock, qs, ready;
    uint32_t ad;
    uint8_t dout, din;
};
struct Cyc {                            // one bus cycle
    int type, t1;                       // S2-S0 at T1, clock index of T1
    uint32_t addr;
    std::string states;                 // e.g. "123w4"
    uint8_t data;                       // byte read (at the READY clock) or written
    bool ok_shape = true;               // strobes / status / ALE per [DS] in every state
};

struct Sim {
    int waits[8] = {};                  // wait states per bus type
    uint8_t vector = 0x40;              // type supplied in the second INTA cycle
    std::function<void(int, Sim &)> stim; // drives intr / nmi / test_n per clock
    std::vector<Clk> clk;
    int wcnt = 0, cur_type = 7, inta_n = 0;
    uint32_t latch = 0;
    bool reset_hi = false;

    void tick() { top->eval(); top->clk = 1; top->eval(); top->clk = 0; top->eval(); }

    void step() {
        int n = (int)clk.size();
        top->reset = reset_hi;
        if (stim) stim(n, *this);
        top->ready = 1;
        top->eval();
        if (top->ale) {
            latch = top->ad & 0xFFFFF;
            cur_type = top->s20 & 7;
            wcnt = waits[cur_type];
            if (cur_type == S_INTA) inta_n++;
        }
        int ts = top->tstate;
        if ((ts == 3 || ts == 5) && wcnt > 0) top->ready = 0;
        uint8_t d;
        if (cur_type == S_INTA) d = (inta_n % 2 == 0) ? vector : 0xFF;
        else if (cur_type == S_IOR) d = (uint8_t)(latch * 7 + 0x11);
        else d = mem[latch];
        top->din = d;
        top->eval();
        Clk c{};
        c.ts = top->tstate; c.ale = top->ale; c.s = top->s20 & 7; c.rd = top->rd; c.wra = top->wra; c.wr = top->wr;
        c.io = top->io; c.inta = top->inta; c.lock = top->lock; c.qs = top->qs; c.ready = top->ready;
        c.ad = top->ad & 0xFFFFF; c.dout = top->dout; c.din = d;
        if (top->wr && top->ready && (ts == 3 || ts == 5) && !top->io) mem[latch] = top->dout;
        if ((ts == 3 || ts == 5) && !top->ready) wcnt--;
        clk.push_back(c);
        tick();
    }
    void run(int n) { for (int i = 0; i < n; i++) step(); }

    std::vector<Cyc> cycles() const {
        std::vector<Cyc> v;
        for (size_t i = 0; i < clk.size(); i++) {
            const Clk &c = clk[i];
            if (c.ts == 1 && c.ale) {
                Cyc y; y.type = c.s; y.t1 = (int)i; y.addr = c.ad; y.data = 0;
                size_t j = i;
                for (; j < clk.size(); j++) {
                    const Clk &k = clk[j];
                    int t = k.ts;
                    y.states += t == 5 ? 'w' : (char)('0' + t);
                    bool rdcmd = y.type == S_CODE || y.type == S_MEMR || y.type == S_IOR;
                    bool wrcmd = y.type == S_MEMW || y.type == S_IOW;
                    bool intacmd = y.type == S_INTA;
                    bool act = t == 2 || t == 3 || t == 5;
                    // [DS] RD / INTA active T2, T3, Tw; WR (8288 AMWC) T2, T3, Tw; ALE only in T1;
                    // S2-S0 active T1, T2 and T3 / Tw while READY is low, passive once READY is high
                    if ((k.rd != (rdcmd && act)) || (k.inta != (intacmd && act)) || (k.wra != (wrcmd && act)) ||
                        (k.ale != (t == 1)) || (k.io != (y.type == S_IOR || y.type == S_IOW)))
                        y.ok_shape = false;
                    int exp_s = (t == 1 || t == 2 || ((t == 3 || t == 5) && !k.ready)) ? y.type : S_PASV;
                    if (y.type == S_HALT) exp_s = (t == 1 || t == 2) ? S_HALT : S_PASV;
                    if (k.s != exp_s) y.ok_shape = false;
                    if ((t == 3 || t == 5) && k.ready) y.data = wrcmd ? k.dout : k.din;
                    if (t == 4) break;
                }
                v.push_back(y);
            }
        }
        return v;
    }
    int first_byte(int k) const {       // clock of the k-th "first byte" QS status (0-based)
        int n = 0;
        for (size_t i = 0; i < clk.size(); i++) if (clk[i].qs == 1 && n++ == k) return (int)i;
        return -1;
    }
};

static uint16_t reg(int i) {            // moo order: ax bx cx dx cs ss ds es sp bp si di ip flags
    uint16_t v = 0;
    for (int b = 0; b < 16; b++) v |= ((top->dbg_regs[(i * 16 + b) / 32] >> ((i * 16 + b) % 32)) & 1u) << b;
    return v;
}
enum { AX, BX, CX, DX, CS, SS, DS, ES, SP, BP, SI, DI, IP, FL };

static void set_reg(int i, uint16_t v) {
    for (int b = 0; b < 16; b++) {
        int k = i * 16 + b;
        if ((v >> b) & 1) top->tl_regs[k / 32] |= 1u << (k % 32); else top->tl_regs[k / 32] &= ~(1u << (k % 32));
    }
}

// fresh CPU: reset, then load registers through the test-load path with an empty queue (code fetched from memory)
static void start(Sim &s, uint16_t cs, uint16_t ip, uint16_t flags, uint16_t ss = 0x1000, uint16_t sp = 0x0100) {
    top->reset = 1; top->tl_en = 0; top->ready = 1; top->intr = 0; top->nmi = 0; top->test_n = 0; top->tl_md = 1; top->tl_mdwe = 0;
    s.tick(); s.tick();
    top->reset = 0;
    for (int i = 0; i < 7; i++) top->tl_regs[i] = 0;
    set_reg(CS, cs); set_reg(IP, ip); set_reg(FL, flags); set_reg(SS, ss); set_reg(SP, sp);
    set_reg(DS, 0x2000); set_reg(ES, 0x3000); set_reg(AX, 0x1234); set_reg(CX, 4); set_reg(SI, 0x10); set_reg(DI, 0x20);
    set_reg(DX, 0x0080);
    top->tl_qlen = 0; top->tl_queue = 0; top->tl_ad = 0; top->tl_en = 1;
    s.tick();
    top->tl_en = 0;
}
static void put(uint32_t a, std::vector<uint8_t> b) { for (size_t i = 0; i < b.size(); i++) mem[(a + i) & 0xFFFFF] = b[i]; }
static void vec(int t, uint16_t seg, uint16_t off) { put(t * 4, {(uint8_t)off, (uint8_t)(off >> 8), (uint8_t)seg, (uint8_t)(seg >> 8)}); }

static std::string list(const std::vector<Cyc> &v) {
    std::string r;
    char b[64];
    for (auto &c : v) {
        snprintf(b, sizeof b, " %s@%d:%05X:%s%s", sname[c.type], c.t1, c.addr, c.states.c_str(), c.ok_shape ? "" : "!");
        r += b;
    }
    return r;
}

static int npass = 0, nfail = 0;
static void check(const char *name, bool ok, const std::string &why, const Sim &s) {
    printf("%-58s %s", name, ok ? "pass" : "FAIL");
    if (!ok) printf("  %s", why.c_str());
    printf("\n");
    if (!ok || verbose) printf("     %s\n", list(s.cycles()).c_str());
    (ok ? npass : nfail)++;
}

static const Cyc *find(const std::vector<Cyc> &v, int type, int k = 0) {
    for (auto &c : v) if (c.type == type && k-- == 0) return &c;
    return nullptr;
}
static bool shapes_ok(const std::vector<Cyc> &v) { for (auto &c : v) if (!c.ok_shape) return false; return true; }
static std::string wstates(int n) { return "123" + std::string(n, 'w') + "4"; }

// ---------------------------------------------------------------------------------------------------------------
static void t_reset() {
    // [DS] RESET: terminates activity immediately, HIGH >= 4 clocks; internal reset sequence ~7 clocks after the
    // falling edge, then execution starts at FFFF0H. [PR] Table 4-2: flags clear, IP 0, CS FFFF, DS SS ES 0, queue empty.
    Sim s;
    memset(mem, 0x90, sizeof mem);
    put(0xFFFF0, {0xEA, 0x00, 0x01, 0x00, 0x50});         // JMP 5000:0100
    put(0x50100, {0x90, 0x90});
    start(s, 0x1234, 0x5678, 0x0FD5, 0x4444, 0x4444);
    s.run(30);                                             // running from a random state
    s.reset_hi = true;
    int r0 = (int)s.clk.size();
    s.run(5);
    bool quiet = true;
    for (int i = r0 + 1; i < (int)s.clk.size(); i++) if (s.clk[i].ale || s.clk[i].rd || s.clk[i].wra) quiet = false;
    s.reset_hi = false;
    int rl = (int)s.clk.size();
    s.step();
    bool regs = reg(CS) == 0xFFFF && reg(IP) == 0 && reg(DS) == 0 && reg(SS) == 0 && reg(ES) == 0 && reg(FL) == 0xF002;
    s.run(60);
    auto v = s.cycles();
    const Cyc *f = nullptr;
    for (auto &c : v) if (c.t1 > rl) { f = &c; break; }
    char why[160];
    int dt = f ? f->t1 - rl : -1;
    snprintf(why, sizeof why, "quiet=%d regs=%d first=%s@+%d", quiet, regs, f ? sname[f->type] : "-", dt);
    check("reset: no bus activity while RESET high", quiet, why, s);
    check("reset: CS=FFFF IP=0 DS=SS=ES=0 flags clear", regs, why, s);
    bool first = f && f->type == S_CODE && f->addr == 0xFFFF0 && dt >= 7 && dt <= 10;
    snprintf(why, sizeof why, "first cycle %s %05X at clock %d after RESET low (expect CODE FFFF0, ~7 clocks + start)",
             f ? sname[f->type] : "-", f ? f->addr : 0, dt);
    check("reset: first fetch at FFFF0 after the ~7-clock reset sequence", first, why, s);
    bool jmp = reg(CS) == 0x5000 && find(v, S_CODE) != nullptr;
    bool fetched = false;
    for (auto &c : v) if (c.type == S_CODE && c.addr == 0x50100) fetched = true;
    check("reset: execution continues (JMP FAR at FFFF0 reaches 5000:0100)", jmp && fetched, "", s);
    int fq = -1;
    for (int i = rl; i < (int)s.clk.size(); i++) if (s.clk[i].qs == 1) { fq = i - rl; break; }
    printf("     (first T1 at clock %d after RESET falls; first QS first-byte at clock %d)\n", dt, fq);
}

// wait states on one bus type: compare against the zero-wait run of the same program
static void t_wait(const char *what, int type, std::vector<uint8_t> prog, int n_per) {
    for (int nw : {1, 2, 5}) {
        Sim a, b;
        memset(mem, 0x90, sizeof mem);
        put(0x20000 + 0x1234, {0x5A, 0xA5});
        put(0x10000, prog);
        start(a, 0x1000, 0, 0xF002);
        a.run(80);
        auto va = a.cycles();
        memset(mem, 0x90, sizeof mem);
        put(0x20000 + 0x1234, {0x5A, 0xA5});
        put(0x10000, prog);
        b.waits[type] = nw;
        start(b, 0x1000, 0, 0xF002);
        b.run(80 + 8 * nw);
        auto vb = b.cycles();
        // [DS] "wait states (Tw) are inserted between T3 and T4"; each Tw is one clock
        bool shape = shapes_ok(vb);
        int k = 0;
        bool states = true, shift = true;
        int delay = 0;                  // accumulated Tw before this cycle
        std::string why;
        size_t m = va.size() < vb.size() ? va.size() : vb.size();
        if (m > 12) m = 12;
        for (size_t i = 0; i < m; i++) {
            const Cyc &x = va[i], &y = vb[i];
            if (x.type != y.type || x.addr != y.addr) { shift = false; why = "cycle order differs"; break; }
            std::string es = (y.type == type) ? wstates(nw) : "1234";
            if (y.states != es) { states = false; why = "states " + y.states + " expected " + es; break; }
            // every bus cycle starts exactly the accumulated wait clocks later than without waits
            if (y.t1 - x.t1 != delay) {
                shift = false;
                char t[96]; snprintf(t, sizeof t, "cycle %zu T1 at %d, zero-wait %d + %d Tw", i, y.t1, x.t1, delay);
                why = t; break;
            }
            if (y.data != x.data) { shift = false; why = "data differs"; break; }
            if (y.type == type) { delay += nw; k++; }
        }
        char name[96];
        snprintf(name, sizeof name, "wait: %d Tw on %s", nw, what);
        check(name, shape && states && shift && k >= n_per, why.empty() ? (shape ? "" : "strobe/status shape") : why, b);
    }
}

static void t_inta_waits() {
    for (int nw : {0, 1, 3}) {
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(0x40, 0x4000, 0x0010);
        s.waits[S_INTA] = nw;
        s.stim = [](int n, Sim &) { top->intr = n >= 20 && n < 60; };
        start(s, 0x1000, 0, 0xF202);
        s.run(160);
        auto v = s.cycles();
        const Cyc *a1 = find(v, S_INTA, 0), *a2 = find(v, S_INTA, 1);
        bool ok = a1 && a2 && a1->states == wstates(nw) && a2->states == wstates(nw);
        // [DS] Figure 9: the two INTA cycles back to back; LOCK from T2 of the first to T2 of the second
        ok = ok && a2->t1 == a1->t1 + (int)a1->states.size();
        bool lk = ok;
        if (ok) for (int i = a1->t1; i <= a2->t1 + 1; i++) {
            bool exp = i >= a1->t1 + 1 && i <= a2->t1;
            if (s.clk[i].lock != exp) lk = false;
        }
        char name[96];
        snprintf(name, sizeof name, "INTA pair, %d Tw each: back to back, LOCK T2..T2", nw);
        check(name, ok && lk && shapes_ok(v), ok ? (lk ? "" : "LOCK window") : "INTA cycles", s);
    }
}

// INTR: acceptance, sequence, vector, return address
static void t_intr() {
    {
        // [DS] INTR sampled at the end of each instruction; [PR] 4.3: two INTA cycles, the type byte in the second,
        // vector at type*4 (IP word, then CS word), flags, CS and IP pushed, IF and TF cleared
        Sim t;
        memset(mem, 0x90, sizeof mem);
        vec(0x40, 0x4000, 0x0010);
        t.stim = [](int n, Sim &) { top->intr = n >= 20 && n < 40; };
        start(t, 0x1000, 0, 0xF202);
        t.run(150);
        auto v = t.cycles();
        const Cyc *a1 = find(v, S_INTA, 0), *a2 = find(v, S_INTA, 1);
        std::vector<int> seq;
        for (auto &c : v) if (a1 && c.t1 >= a1->t1) seq.push_back(c.type);
        // after the INTA pair: 4 vector reads (2 words), 2 flag writes, 2 CS writes, then code at 40010, IP writes
        bool vreads = false, order = false;
        if (a1 && a2) {
            std::vector<uint32_t> rd;
            for (auto &c : v) if (c.t1 > a2->t1 && c.type == S_MEMR) rd.push_back(c.addr);
            vreads = rd.size() >= 4 && rd[0] == 0x100 && rd[1] == 0x101 && rd[2] == 0x102 && rd[3] == 0x103;
            std::vector<uint32_t> wa; std::vector<uint8_t> wd;
            for (auto &c : v) if (c.type == S_MEMW) { wa.push_back(c.addr); wd.push_back(c.data); }
            uint16_t ret = (uint16_t)(wd.size() >= 6 ? wd[4] | (wd[5] << 8) : 0xFFFF);
            uint16_t fl = (uint16_t)(wd.size() >= 2 ? wd[0] | (wd[1] << 8) : 0);
            order = wa.size() >= 6 && wa[0] == 0x100FE && wa[2] == 0x100FC && wa[4] == 0x100FA && fl == 0xF202 &&
                    wd[2] == 0x00 && wd[3] == 0x10;
            // return address: the instruction boundary at which INTR was recognised (NOPs from 1000:0000)
            int fb = 0;
            for (int i = 0; i < a1->t1; i++) if (t.clk[i].qs == 1) fb++;
            order = order && ret == fb;
        }
        bool regs = reg(CS) == 0x4000 && reg(SP) == 0x00FA && (reg(FL) & 0x0300) == 0;
        check("INTR: INTA, INTA, vector 4n (CS or none), push FLAGS CS IP", a1 && a2 && vreads && order, "", t);
        check("INTR: CS:IP from the vector, SP-6, IF and TF cleared", regs, "", t);
    }
    {
        // [PR] 4.3: INTR ignored while IF = 0
        Sim s;
        memset(mem, 0x90, sizeof mem);
        s.stim = [](int n, Sim &) { top->intr = n >= 10; };
        start(s, 0x1000, 0, 0xF002);
        s.run(100);
        check("INTR: masked by IF = 0", find(s.cycles(), S_INTA) == nullptr, "", s);
    }
    // [PR] 4.3: no interrupt after MOV / POP to a segment register until after the following instruction;
    // STI enables INTR only after the following instruction
    struct Case { const char *name; std::vector<uint8_t> prog; uint16_t fl; uint16_t ret; };
    for (auto c : std::vector<Case>{
             {"INTR: not after MOV SS,AX (taken after the next instruction)", {0x8E, 0xD0, 0x40, 0x90}, 0xF202, 3},
             {"INTR: not after POP DS (taken after the next instruction)", {0x1F, 0x40, 0x90}, 0xF202, 2},
             {"INTR: STI enables only after the next instruction", {0xFB, 0x40, 0x90}, 0xF002, 2},
             {"INTR: never between a prefix and its instruction", {0x26, 0x26, 0x8B, 0x07, 0x90}, 0xF202, 4}}) {
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(0x40, 0x4000, 0x0010);
        put(0x10000, c.prog);
        // INTR high from the clock the first byte is read to the end
        s.stim = [&](int n, Sim &x) { top->intr = x.first_byte(0) >= 0; };
        start(s, 0x1000, 0, c.fl);
        s.run(200);
        auto v = s.cycles();
        std::vector<uint8_t> wd;
        for (auto &y : v) if (y.type == S_MEMW) wd.push_back(y.data);
        uint16_t ret = wd.size() >= 6 ? (uint16_t)(wd[4] | (wd[5] << 8)) : 0xFFFF;
        char why[64]; snprintf(why, sizeof why, "pushed IP %04X expected %04X", ret, c.ret);
        check(c.name, ret == c.ret, why, s);
    }
}

static void t_nmi_tf() {
    {
        // [DS] NMI: rising edge, type 2, no INTA; [PR] Table 4-1: NMI before INTR
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(2, 0x5000, 0x0000); vec(0x40, 0x4000, 0x0010);
        s.stim = [](int n, Sim &) { top->nmi = n >= 20; top->intr = n >= 20; };
        start(s, 0x1000, 0, 0xF202);
        s.run(150);
        auto v = s.cycles();
        const Cyc *r = find(v, S_MEMR);
        bool ok = r && r->addr == 0x8 && find(v, S_INTA) == nullptr;
        // the handler (IF now 0) runs; INTR stays masked, NMI held high is one edge: one NMI only
        int nmis = 0;
        for (auto &y : v) if (y.type == S_MEMR && y.addr == 0x8) nmis++;
        check("NMI: type 2 without INTA, before a pending INTR", ok, "", s);
        check("NMI: edge triggered (held high = one interrupt)", nmis == 1 && reg(CS) == 0x5000, "", s);
    }
    {
        // [PR] 4.3 single step: type 1 after the instruction following the one that set TF (POPF here)
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(1, 0x6000, 0x0000);
        put(0x10000, {0x9D, 0x40, 0x41});                 // POPF (TF=1) ; INC AX ; INC CX
        put(0x10000 + 0x100, {0x02, 0xF1});               // stack word F102 at 1000:0100
        start(s, 0x1000, 0, 0xF002);
        s.run(150);
        auto v = s.cycles();
        std::vector<uint8_t> wd;
        for (auto &y : v) if (y.type == S_MEMW) wd.push_back(y.data);
        uint16_t ret = wd.size() >= 6 ? (uint16_t)(wd[4] | (wd[5] << 8)) : 0xFFFF;
        uint16_t pf = wd.size() >= 2 ? (uint16_t)(wd[0] | (wd[1] << 8)) : 0;
        const Cyc *r = find(v, S_MEMR, 2);
        bool ok = r && r->addr == 0x4 && ret == 2 && (pf & 0x100) && reg(CS) == 0x6000 && (reg(FL) & 0x100) == 0;
        check("TF: trap (type 1) after the instruction following POPF", ok, "", s);
    }
    {
        // [PR] Figure 4-10: an interrupt taken in single-step mode is followed by the single-step trap before the
        // first instruction of its procedure
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(1, 0x6000, 0x0000); vec(0x21, 0x7000, 0x0000);
        put(0x10000, {0xCD, 0x21});
        start(s, 0x1000, 0, 0xF102);
        s.run(250);
        auto v = s.cycles();
        std::vector<uint32_t> va;
        for (auto &y : v) if (y.type == S_MEMR) va.push_back(y.addr);
        bool ok = va.size() >= 8 && va[0] == 0x84 && va[4] == 0x4 && reg(CS) == 0x6000;
        check("TF: INT n in single-step mode traps before the handler runs", ok, "", s);
    }
}

static void t_rep_int() {
    // [PR] REP: interruptible between elements; on return the operation resumes; only the prefix immediately
    // before the string instruction is remembered (return address = that prefix)
    Sim s;
    memset(mem, 0x90, sizeof mem);
    vec(0x40, 0x4000, 0x0010);
    put(0x10000, {0x2E, 0xF3, 0xA4});                     // CS: REP MOVSB, CX = 4
    s.stim = [](int n, Sim &x) {
        int w = 0;
        for (auto &c : x.clk) if (c.ts == 1 && c.ale && c.s == S_MEMW) w++;
        top->intr = w >= 2;                               // after the second element is written
    };
    start(s, 0x1000, 0, 0xF202);
    s.run(300);
    auto v = s.cycles();
    std::vector<uint8_t> wd; int strw = 0;
    for (auto &y : v) if (y.type == S_MEMW) { if (y.addr >= 0x30000 && y.addr < 0x30100) strw++; else wd.push_back(y.data); }
    uint16_t ret = wd.size() >= 6 ? (uint16_t)(wd[4] | (wd[5] << 8)) : 0xFFFF;
    bool ok = find(v, S_INTA) && ret == 1 && reg(CX) == 4 - strw && strw >= 2 && strw < 4 && reg(DI) == 0x20 + strw;
    char why[96]; snprintf(why, sizeof why, "ret %04X elements %d cx %d di %04X", ret, strw, reg(CX), reg(DI));
    check("REP MOVSB: INTR between elements, returns to the REP prefix", ok, why, s);
}

static void t_hlt_wait_lock() {
    {
        // [DS] HALT: HALT status on S2-S0, the 8288 issues one ALE; left by INTR (IF=1), NMI or RESET;
        // [PR] HLT: return address after the HLT
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(0x40, 0x4000, 0x0010);
        put(0x10000, {0xF4});
        s.stim = [](int n, Sim &) { top->intr = n >= 80 && n < 120; };
        start(s, 0x1000, 0, 0xF202);
        s.run(200);
        auto v = s.cycles();
        const Cyc *h = find(v, S_HALT);
        int between = 0;
        const Cyc *a = find(v, S_INTA);
        for (auto &y : v) if (h && a && y.t1 > h->t1 && y.t1 < a->t1) between++;
        std::vector<uint8_t> wd;
        for (auto &y : v) if (y.type == S_MEMW) wd.push_back(y.data);
        uint16_t ret = wd.size() >= 6 ? (uint16_t)(wd[4] | (wd[5] << 8)) : 0xFFFF;
        check("HLT: one HALT status cycle, idle until INTR, return after HLT", h && a && between == 0 && ret == 1, "", s);
    }
    {
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(2, 0x5000, 0x0000);
        put(0x10000, {0xF4});
        s.stim = [](int n, Sim &) { top->nmi = n >= 80; };
        start(s, 0x1000, 0, 0xF002);
        s.run(200);
        check("HLT: left by NMI with IF = 0", reg(CS) == 0x5000, "", s);
    }
    {
        // [DS] TEST / WAIT: waits while TEST is high; [PR] WAIT 4 + 5n clocks
        int len[2];
        for (int k = 0; k < 2; k++) {
            Sim s;
            memset(mem, 0x90, sizeof mem);
            put(0x10000, {0x9B, 0x90, 0x90, 0x90});
            int hold = k ? 200 : 0;
            s.stim = [hold](int n, Sim &x) { top->test_n = x.first_byte(0) >= 0 && (int)x.clk.size() < x.first_byte(0) + hold; };
            start(s, 0x1000, 0, 0xF002);
            s.run(300);
            len[k] = s.first_byte(1) - s.first_byte(0);
        }
        bool ok = len[0] == 4 && (len[1] - 4) % 5 == 0 && len[1] > 200;
        char why[64]; snprintf(why, sizeof why, "WAIT lengths %d and %d", len[0], len[1]);
        Sim dummy;
        check("WAIT: 4 clocks with TEST low, +5 per TEST sample while high", ok, why, dummy);
    }
    {
        // [DS] "The WAIT instruction is then refetched, and reexecuted" after an interrupt during WAIT
        Sim s;
        memset(mem, 0x90, sizeof mem);
        vec(0x40, 0x4000, 0x0010);
        put(0x10000, {0x90, 0x9B});
        s.stim = [](int n, Sim &) { top->test_n = 1; top->intr = n >= 60 && n < 100; };
        start(s, 0x1000, 0, 0xF202);
        s.run(200);
        std::vector<uint8_t> wd;
        for (auto &y : s.cycles()) if (y.type == S_MEMW) wd.push_back(y.data);
        uint16_t ret = wd.size() >= 6 ? (uint16_t)(wd[4] | (wd[5] << 8)) : 0xFFFF;
        check("WAIT: interrupt while waiting returns to the WAIT", ret == 1, "", s);
    }
    {
        // [DS] LOCK: active the clock after the LOCK prefix is decoded until the end of the locked instruction
        Sim s;
        memset(mem, 0x90, sizeof mem);
        put(0x10000, {0xF0, 0x86, 0x07, 0x90});           // LOCK XCHG [BX],AL
        start(s, 0x1000, 0, 0xF002);
        s.run(80);
        auto v = s.cycles();
        const Cyc *r = find(v, S_MEMR), *w = find(v, S_MEMW);
        bool ok = r && w;
        if (ok) for (int i = r->t1; i < w->t1 + 4; i++) if (!s.clk[i].lock) ok = false;
        int f2 = s.first_byte(2);
        bool off = f2 > 0 && !s.clk[w->t1 + 5].lock;
        if (verbose) { for (int i = 0; i < 50; i++) printf("%d", s.clk[i].lock); printf("  lock per clock, f2=%d\n", f2); }
        check("LOCK: held across the read and write of LOCK XCHG, released after", ok && off, "", s);
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "-v")) verbose = true;
    top = new Vtb_x86;
    top->clk = 0; top->eval();
    t_reset();
    t_wait("code fetch", S_CODE, {0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90}, 4);
    t_wait("memory read (MOV AL,[1234])", S_MEMR, {0xA0, 0x34, 0x12, 0x90, 0x90}, 1);
    t_wait("memory read, word (MOV AX,[1234])", S_MEMR, {0xA1, 0x34, 0x12, 0x90, 0x90}, 2);
    t_wait("memory write (MOV [1234],AX)", S_MEMW, {0xA3, 0x34, 0x12, 0x90, 0x90}, 2);
    t_wait("I/O read (IN AL,DX)", S_IOR, {0xEC, 0x90, 0x90}, 1);
    t_wait("I/O write (OUT DX,AX)", S_IOW, {0xEF, 0x90, 0x90}, 2);
    t_inta_waits();
    t_intr();
    t_nmi_tf();
    t_rep_int();
    t_hlt_wait_lock();
    printf("directed: %d pass, %d fail\n", npass, nfail);
    delete top;
    return nfail ? 1 : 0;
}

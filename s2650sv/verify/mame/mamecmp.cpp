// Instruction-level comparison: GHDL-converted sgs2650 (the oracle s2650sv matches) vs MAME s2650.cpp.
// The RTL runs as master; at every instruction boundary MAME is loaded with the RTL state from the previous
// boundary (memory rolled back to it), executes that one instruction, and both results are compared:
// IAR, R0-R3, R1'-R3', PSL, PSU, RAS (logical stack), memory writes, I/O writes / reads, cycles.
// Differences are counted per (opcode, field) with one example each.
//
//   mamecmp random <seed> <instructions>
//   mamecmp directed <seeds-per-variant>   (opcode x mode x seeds programs)
#include "Vtb_top.h"
#include "verilated.h"
#include "mame_s2650.cpp"
#include <map>
#include <set>
#include <string>
#include <vector>
#include <algorithm>

static uint64_t rng_s = 1;
static inline uint64_t rnd() { rng_s ^= rng_s << 13; rng_s ^= rng_s >> 7; rng_s ^= rng_s << 17; return rng_s; }
static inline uint32_t rndn(uint32_t n) { return (uint32_t)(rnd() % n); }
static inline bool chance(uint32_t a, uint32_t b) { return rndn(b) < a; }

static uint8_t mem[32768], io_ext[256], io_cd[2];

// MAME bus: program reads from mem (RTL writes of the instruction rolled back), writes logged only
struct Acc { int sp; uint16_t a; uint8_t d; bool wr; };
static std::vector<Acc> m_acc;
uint8_t mame_bus_read(int sp, offs_t a) {
    uint8_t v = sp == AS_PROGRAM ? mem[a & 0x7FFF] : sp == AS_DATA ? (uint8_t)(io_cd[a & 1] ^ 0x5A) : (uint8_t)(io_ext[a & 0xFF] ^ 0x5A);
    if (sp != AS_PROGRAM) m_acc.push_back({sp, (uint16_t)a, v, false});
    return v;
}
void mame_bus_write(int sp, offs_t a, uint8_t d) { m_acc.push_back({sp, (uint16_t)a, d, true}); }

struct Arch {
    uint16_t pc; uint8_t r[7]; uint8_t psl, psu; uint16_t ras[8];   // r: R0 R1 R2 R3 R1' R2' R3'; ras: RTL indexing
};
static std::string arch_str(const Arch &s) {
    char b[200];
    snprintf(b, sizeof b, "pc=%04X r0=%02X r1-3=%02X,%02X,%02X r1'-3'=%02X,%02X,%02X psl=%02X psu=%02X", s.pc, s.r[0],
             s.r[1], s.r[2], s.r[3], s.r[4], s.r[5], s.r[6], s.psl, s.psu);
    return b;
}

struct Diff { uint64_t n = 0; std::string ex; };
static std::map<std::pair<int, std::string>, Diff> diffs;     // (opcode or 0x100 = interrupt entry, field)
static std::map<std::pair<int, std::string>, Diff> wdiffs;    // same, instructions that cross an 8K page
static std::map<int, uint64_t> ops_done, ops_wrap;
static bool g_wrap = false;
static void note(int op, const std::string &field, const std::string &ex) {
    auto &d = (g_wrap ? wdiffs : diffs)[{op, field}];
    if (!d.n) d.ex = ex;
    d.n++;
}

struct Rtl {
    std::unique_ptr<VerilatedContext> ctx;
    std::unique_ptr<Vtb_top> t;
    uint8_t dr_reg = 0;
    bool prev_req = false;
    uint64_t cyc = 0, lock_mism = 0;
    Rtl() : ctx(new VerilatedContext), t(new Vtb_top(ctx.get())) { t->clk = 0; t->eval(); }
    Arch arch() const {
        Arch s;
        const uint32_t *w = t->r_regs.data();
        uint64_t lo = w[0] | ((uint64_t)w[1] << 32); uint8_t hi = w[2] & 0xFF;
        s.psu = lo & 0xFF; s.psl = (lo >> 8) & 0xFF;
        s.r[6] = (lo >> 16) & 0xFF; s.r[5] = (lo >> 24) & 0xFF; s.r[4] = (lo >> 32) & 0xFF;
        s.r[3] = (lo >> 40) & 0xFF; s.r[2] = (lo >> 48) & 0xFF; s.r[1] = (lo >> 56) & 0xFF; s.r[0] = hi;
        s.pc = t->r_iar;
        for (int i = 0; i < 8; i++) {
            int bit = i * 15;
            uint64_t v = 0;
            for (int k = 0; k < 15; k++) v |= (uint64_t)((t->r_ras[(bit + k) / 32] >> ((bit + k) % 32)) & 1) << k;
            s.ras[i] = (uint16_t)v;
        }
        return s;
    }
};

// MAME state load / read-back (bank select swaps physical registers; RAS pushed at ++sp)
static void mame_load(s2650_device &c, const Arch &s, bool sense) {
    c.m_page = s.pc & 0x6000; c.m_iar = s.pc & 0x1FFF;
    c.m_psl = s.psl; c.m_psu = (s.psu & 0x7F) | (sense ? 0x80 : 0);
    bool rs = s.psl & 0x10;
    c.m_reg[0] = s.r[0];
    for (int i = 1; i <= 3; i++) { c.m_reg[i] = rs ? s.r[3 + i] : s.r[i]; c.m_reg[3 + i] = rs ? s.r[i] : s.r[3 + i]; }
    for (int i = 0; i < 8; i++) c.m_ras[i] = s.ras[(i - 1) & 7];
    c.m_halt = 0; c.m_irq_state = 0;
}
static Arch mame_read(s2650_device &c) {
    Arch s;
    s.pc = c.m_page + c.m_iar; s.psl = c.m_psl; s.psu = c.m_psu;
    bool rs = c.m_psl & 0x10;
    s.r[0] = c.m_reg[0];
    for (int i = 1; i <= 3; i++) { s.r[i] = rs ? c.m_reg[3 + i] : c.m_reg[i]; s.r[3 + i] = rs ? c.m_reg[i] : c.m_reg[3 + i]; }
    for (int i = 0; i < 8; i++) s.ras[(i - 1) & 7] = c.m_ras[i];
    return s;
}

// Pending instruction (RTL side)
struct Pend {
    bool valid = false, irq = false, halted = false;
    Arch s0; uint8_t bytes[3] = {0, 0, 0}; int nbytes = 0; uint8_t ivec = 0;
    std::vector<Acc> acc;                      // RTL memory writes (with old value in d2) and I/O accesses
    std::vector<uint8_t> old;
    int cycles = 0;
};

static int len_of(int op) {
    int lo = op & 15, row = op >> 4, g = lo >> 2;
    if (op == 0x40) return 1;
    if (!(row & 1)) return g == 0 ? 1 : g == 3 ? 3 : 2;
    if (op == 0x10 || op == 0x11) return 3;
    if (g == 0) return 1;
    if (g == 1) return (row == 1 || row == 3 || row == 9) ? 1 : 2;
    return g == 2 ? 2 : 3;
}
// Does this instruction touch an 8K page boundary? (sgs2650 carries into A14:A13, MAME wraps inside the page)
static bool page_wrap(const Pend &p) {
    if (p.irq) return false;
    int op = p.bytes[0], pc = p.s0.pc, L = len_of(op), row = op >> 4, g = (op & 15) >> 2;
    uint8_t b2 = p.bytes[1], b3 = p.bytes[2];
    if ((pc & 0x1FFF) + L >= 0x2000) return true;
    auto sx = [](int v) { return (v & 0x40) ? (v & 0x7F) - 0x80 : v & 0x7F; };
    bool rel = L == 2 && g == 2;                         // R / ER formats (columns 8-B)
    bool absa = L == 3 && !(row & 1) && g == 3;          // ALU / STR absolute
    bool absb = L == 3 && (row & 1) && g == 3;           // branches absolute
    int ptr = -1;
    if (rel) {
        int e = (op == 0x9B || op == 0xBB) ? sx(b2) & 0x1FFF : pc + 2 + sx(b2);
        int ref = e & 0x7FFF, mm = (op == 0x9B || op == 0xBB) ? ref : (pc & 0x6000) + (e & 0x1FFF);
        if (ref != mm) return true;
        if (b2 & 0x80) ptr = ref;
    }
    if (absa && (b2 & 0x80)) ptr = (pc & 0x6000) | ((b2 & 0x1F) << 8) | b3;
    if (absb && (b2 & 0x80)) ptr = ((b2 & 0x7F) << 8) | b3;
    if (ptr >= 0 && (ptr & 0x1FFF) == 0x1FFF) return true;
    if (absa && (b2 & 0x60)) {
        int base = (b2 & 0x80) ? (((mem[ptr] & 0x7F) << 8) | mem[(ptr + 1) & 0x7FFF]) : ((pc & 0x6000) | ((b2 & 0x1F) << 8) | b3);
        int rn = op & 3, rs = p.s0.psl & 0x10;
        int x = rn == 0 ? p.s0.r[0] : p.s0.r[rs ? rn + 3 : rn];
        int m = (b2 >> 5) & 3;
        if (m == 1) x = (x + 1) & 0xFF;
        if (m == 2) x = (x - 1) & 0xFF;
        if (((base + x) & 0x7FFF) != ((base & 0x6000) + ((base + x) & 0x1FFF))) return true;
    }
    return false;
}

static void compare(Pend &p, const Arch &s1, bool sense, s2650_device &c) {
    int op = p.irq ? 0x100 + (p.ivec >> 7) : p.bytes[0];    // 0x100 / 0x101: interrupt, direct / indirect vector
    // roll back the RTL memory writes
    for (int i = (int)p.acc.size() - 1; i >= 0; i--)
        if (p.acc[i].sp == AS_PROGRAM && p.acc[i].wr) mem[p.acc[i].a] = p.old[i];
    g_wrap = page_wrap(p);
    if (g_wrap) ops_wrap[op]++;
    mame_load(c, p.s0, sense);
    m_acc.clear();
    c.m_intack_handler.fn = [&]() { return p.ivec; };
    c.m_sense_handler.fn = [sense]() { return sense ? 1 : 0; };
    int cyc;
    if (p.irq) { c.m_irq_state = 1; cyc = c.check_irq_line(); }
    else {
        c.m_icount = 1; c.execute_run(); cyc = 1 - c.m_icount;
        if (p.halted) {   // HALT left by an interrupt: MAME takes it on the next run
            c.m_irq_state = 1; cyc += c.check_irq_line();
        }
    }
    Arch m = mame_read(c);
    for (size_t i = 0; i < p.acc.size(); i++)
        if (p.acc[i].sp == AS_PROGRAM && p.acc[i].wr) mem[p.acc[i].a] = p.acc[i].d;

    char ex[600];
    char ins[32];
    snprintf(ins, sizeof ins, p.irq ? "INT ivec=%02X" : "%02X %02X %02X", p.irq ? p.ivec : p.bytes[0], p.bytes[1], p.bytes[2]);
    if (p.irq) snprintf(ins, sizeof ins, "INT ivec=%02X", p.ivec);
    else if (p.nbytes == 1) snprintf(ins, sizeof ins, "%02X", p.bytes[0]);
    else if (p.nbytes == 2) snprintf(ins, sizeof ins, "%02X %02X", p.bytes[0], p.bytes[1]);
    auto exs = [&](const char *f, unsigned rv, unsigned mv) {
        snprintf(ex, sizeof ex, "%s @%04X: %s rtl=%X mame=%X | before %s", ins, p.s0.pc, f, rv, mv, arch_str(p.s0).c_str());
        return std::string(ex);
    };
    if (s1.pc != m.pc) note(op, "IAR", exs("IAR", s1.pc, m.pc));
    static const char *rn[7] = {"R0", "R1", "R2", "R3", "R1'", "R2'", "R3'"};
    for (int i = 0; i < 7; i++) if (s1.r[i] != m.r[i]) note(op, rn[i][1] == '0' ? "R0" : "Rn", exs(rn[i], s1.r[i], m.r[i]));
    uint8_t dpsl = s1.psl ^ m.psl;
    if (dpsl & 0xC0) note(op, "PSL.CC", exs("PSL", s1.psl, m.psl));
    if (dpsl & 0x20) note(op, "PSL.IDC", exs("PSL", s1.psl, m.psl));
    if (dpsl & 0x04) note(op, "PSL.OVF", exs("PSL", s1.psl, m.psl));
    if (dpsl & 0x01) note(op, "PSL.C", exs("PSL", s1.psl, m.psl));
    if (dpsl & 0x1A) note(op, "PSL.RS/WC/COM", exs("PSL", s1.psl, m.psl));
    uint8_t dpsu = (s1.psu ^ m.psu) & 0x7F;
    if (dpsu & 0x07) note(op, "PSU.SP", exs("PSU", s1.psu, m.psu));
    if (dpsu & 0x20) note(op, "PSU.II", exs("PSU", s1.psu, m.psu));
    if (dpsu & 0x40) note(op, "PSU.F", exs("PSU", s1.psu, m.psu));
    if (dpsu & 0x18) note(op, "PSU.UF", exs("PSU", s1.psu, m.psu));
    // logical return stack: entries below the stack pointer, top first
    for (int k = 0; k < 8; k++) {
        int sr = ((s1.psu & 7) - 1 - k) & 7, sm = ((m.psu & 7) - 1 - k) & 7;
        if (s1.ras[sr] != m.ras[sm]) { note(op, k == 0 ? "RAS top" : "RAS", exs("RAS", s1.ras[sr], m.ras[sm])); break; }
    }
    // writes / IO
    std::vector<Acc> rw, mw;
    for (auto &a : p.acc) if (a.wr || a.sp != AS_PROGRAM) rw.push_back(a);
    for (auto &a : m_acc) mw.push_back(a);
    auto key = [](const Acc &a) { char b[48]; snprintf(b, sizeof b, "%s%s[%X]=%02X", a.sp == 0 ? "M" : a.sp == 1 ? "D" : "E", a.wr ? "w" : "r", a.a, a.d); return std::string(b); };
    std::string rs, ms;
    for (auto &a : rw) rs += key(a) + " ";
    for (auto &a : mw) ms += key(a) + " ";
    if (rs != ms) {
        snprintf(ex, sizeof ex, "%s @%04X: bus rtl={%s} mame={%s} | before %s", ins, p.s0.pc, rs.c_str(), ms.c_str(), arch_str(p.s0).c_str());
        bool any_wr = false; for (auto &a : rw) any_wr |= a.wr; for (auto &a : mw) any_wr |= a.wr;
        note(op, any_wr ? "writes" : "I/O reads", ex);
    }
    if (!p.halted && p.cycles * 3 != cyc) {
        snprintf(ex, sizeof ex, "%s @%04X: cycles rtl=%d mame=%d | before %s", ins, p.s0.pc, p.cycles, cyc / 3, arch_str(p.s0).c_str());
        note(op, "cycles", ex);
    }
    ops_done[op]++;
#ifdef DEBUG_OP
    if (op == DEBUG_OP && (s1.psl ^ m.psl) & 0xC0) {
        printf("DBG %s\n  s0 %s\n  s1 %s\n  m  %s\n  rtl bus: %s\n", ins, arch_str(p.s0).c_str(), arch_str(s1).c_str(), arch_str(m).c_str(), rs.c_str());
    }
#endif
}

// Drive the RTL with a fleet-like bus (ack every 2nd clock, valid dr while waiting), compare each instruction
struct Runner {
    Rtl r;
    machine_config mc;
    s2650_device c{mc, "c", nullptr, 1};
    Pend p;
    bool sense = false;
    uint64_t instrs = 0;
    Runner() { c.device_start(); c.device_reset(); }

    // one clock; irq / ivec inputs; returns false if the RTL halted with no way out
    void clock(bool reset, bool ack, bool irq, uint8_t ivec) {
        Vtb_top *t = r.t.get();
        t->reset = reset; t->ack = ack; t->irq = irq; t->ivec = ivec; t->sense = sense; t->dr = r.dr_reg; t->clk = 0;
        t->eval();
        bool go = ack || !r.prev_req;
        int st = t->r_state;
        bool ii = t->r_regs[0] & 0x20;
        if (reset) p.valid = false;
        else if (go) {
            if (st == 0) {
                Arch s = r.arch();
                if (p.valid) { compare(p, s, sense, c); instrs++; }
                p = Pend();
                p.valid = true; p.s0 = s;
                if (irq && !ii) { p.irq = true; p.ivec = ivec; }
                else { p.bytes[0] = t->dr; p.nbytes = 1; }
            } else if (p.valid && !p.irq && (st == 1 || st == 2) && p.nbytes < 3) p.bytes[p.nbytes++] = t->dr;
            if (p.valid) p.cycles++;
            if (st == 10 && p.valid) { p.halted = true; if (irq && !ii) p.ivec = ivec; }
        }
        if (t->r_req ^ t->d_req || t->r_ad != t->d_ad) r.lock_mism++;
#ifdef DEBUG_OP
        if (p.valid && !p.irq && p.bytes[0] == DEBUG_OP)
            printf("   clk st=%d ack=%d dr=%02X -> req=%d ad=%04X wr=%d mio=%d iar=%04X mem[ad]=%02X\n", st, ack, t->dr, t->r_req, t->r_ad, t->r_wr, t->r_mio, t->r_iar, mem[t->r_ad]);
#endif
        if (reset) r.dr_reg = mem[0];
        else if (t->r_req && ack) {
            uint16_t a = t->r_ad;
            if (t->r_mio) {
                if (t->r_wr) { if (p.valid) { p.acc.push_back({0, a, t->r_dw, true}); p.old.push_back(mem[a]); } mem[a] = t->r_dw; }
                else r.dr_reg = mem[a];
            } else {
                int sp = t->r_ene ? AS_IO : AS_DATA;
                uint16_t port = t->r_ene ? (a & 0xFF) : t->r_dc;
                uint8_t *q = t->r_ene ? &io_ext[a & 0xFF] : &io_cd[t->r_dc];
                if (t->r_wr) { if (p.valid) { p.acc.push_back({sp, port, t->r_dw, true}); p.old.push_back(0); } *q = t->r_dw; }
                else { r.dr_reg = *q ^ 0x5A; if (p.valid) { p.acc.push_back({sp, port, r.dr_reg, false}); p.old.push_back(0); } }
            }
        }
        r.prev_req = t->r_req;
        t->clk = 1; t->eval(); t->clk = 0; r.cyc++;
    }
};

static void fill(int mode) {
    for (int i = 0; i < 32768; i++) {
        uint8_t v = (uint8_t)rnd();
        if (mode) while ((v >= 0xC4 && v <= 0xC7) || v == 0x10 || v == 0x11) v = (uint8_t)rnd();
        mem[i] = v;
    }
    for (auto &x : io_ext) x = (uint8_t)rnd();
    io_cd[0] = (uint8_t)rnd(); io_cd[1] = (uint8_t)rnd();
}

static void report1(const char *title, std::map<std::pair<int, std::string>, Diff> &dm, std::map<int, uint64_t> &den, bool examples) {
    printf("== %s: %zu (opcode, field) disagreement classes\n", title, dm.size());
    std::map<std::string, std::vector<std::pair<int, uint64_t>>> byf;
    for (auto &d : dm) byf[d.first.second].push_back({d.first.first, d.second.n});
    for (auto &f : byf) {
        printf("-- %s: %zu opcodes:", f.first.c_str(), f.second.size());
        for (auto &o : f.second) {
            if (o.first >= 0x100) printf(" INT-%s(%llu/%llu)", o.first == 0x100 ? "direct" : "indirect", (unsigned long long)o.second, (unsigned long long)den[o.first]);
            else printf(" %02X(%llu/%llu)", o.first, (unsigned long long)o.second, (unsigned long long)den[o.first]);
        }
        printf("\n");
    }
    if (!examples) return;
    printf("== %s examples\n", title);
    for (auto &d : dm) {
        char o[8];
        if (d.first.first >= 0x100) snprintf(o, sizeof o, d.first.first == 0x100 ? "INT-d" : "INT-i"); else snprintf(o, sizeof o, "%02X", d.first.first);
        printf("[%s %s] %s\n", o, d.first.second.c_str(), d.second.ex.c_str());
    }
}

static void report(const char *title, uint64_t instrs) {
    uint64_t w = 0;
    for (auto &x : ops_wrap) w += x.second;
    printf("==== %s: %llu instructions compared (%llu cross an 8K page boundary)\n", title, (unsigned long long)instrs, (unsigned long long)w);
    std::map<int, uint64_t> core;
    for (auto &x : ops_done) core[x.first] = x.second - ops_wrap[x.first];
    report1("same-page instructions", diffs, core, true);
    report1("page-crossing instructions", wdiffs, ops_wrap, true);
    int never = 0;
    for (int op = 0; op < 256; op++) if (!ops_done[op]) never++;
    printf("== opcodes never compared: %d, interrupt entries compared: %llu direct, %llu indirect vector\n", never,
           (unsigned long long)ops_done[0x100], (unsigned long long)ops_done[0x101]);
}

int main(int argc, char **argv) {
    std::string m = argc > 1 ? argv[1] : "random";
    uint64_t seed = argc > 2 ? strtoull(argv[2], 0, 0) : 1;
    uint64_t n = argc > 3 ? strtoull(argv[3], 0, 0) : 1000000;
    rng_s = seed * 0x9E3779B97F4A7C15ull + 7;
    uint64_t total = 0, lock = 0;
    if (m == "random") {
        while (total < n) {
            Runner R; fill(chance(1, 2));
            R.sense = chance(1, 2);
            int irq_mode = rndn(3);
            uint8_t ivec = (uint8_t)rnd();
            uint64_t seg = 20000 + rndn(100000);
            bool irq = false;
            for (uint64_t c = 0; R.instrs < seg; c++) {
                bool reset = c < 4;
                if (irq_mode == 1 && chance(1, 400)) { irq = !irq; ivec = (uint8_t)rnd(); }
                if (irq_mode == 2) irq = chance(1, 50);
                R.clock(reset, c & 1, irq, ivec);
                if (c > 4000000) break;
            }
            total += R.instrs; lock += R.r.lock_mism;
        }
        report("random", total);
    } else {
        // directed: prologue (both banks, PSL, PSU) + one instruction of each opcode x mode, then a few more
        int seeds = (int)seed;
        for (int op = 0; op < 256; op++)
            for (int var = 0; var < 8; var++)
                for (int s = 0; s < seeds; s++) {
                    Runner R; fill(0);
                    R.sense = chance(1, 2);
                    std::vector<uint8_t> pg;
                    auto rv = [&]() { static const int v[] = {0, 1, 0xFF}; return chance(1, 2) ? v[rndn(3)] : (int)(rnd() & 0xFF); };
                    uint8_t psl = (uint8_t)rnd();
                    if (chance(1, 3)) psl &= 0xEF;
                    for (int x : {0x04, psl & ~0x10, 0x93, 0x05, rv(), 0x06, rv(), 0x07, rv(), 0x77, 0x10, 0x05, rv(), 0x06,
                                  rv(), 0x07, rv(), 0x04, (int)(rnd() & 0xDF), 0x92, 0x04, (int)psl, 0x93})
                        pg.push_back((uint8_t)x);
                    pg.push_back((uint8_t)op);
                    uint8_t b2 = (uint8_t)rnd();
                    b2 = (b2 & 0x1F) | ((var & 3) << 5) | ((var >> 2) << 7);
                    pg.push_back(b2); pg.push_back((uint8_t)rnd());
                    for (size_t i = 0; i < pg.size(); i++) mem[i] = pg[i];
                    for (uint64_t c = 0; c < 400; c++) R.clock(c < 4, c & 1, false, 0);
                    total += R.instrs; lock += R.r.lock_mism;
                }
        report("directed", total);
    }
    printf("(RTL lockstep req/ad mismatches during these runs: %llu)\n", (unsigned long long)lock);
    return 0;
}

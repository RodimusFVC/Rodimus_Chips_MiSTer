// Lockstep harness: GHDL-converted sgs2650 (reference) vs s2650sv, every output every clock,
// architectural state (R0-R3, R1'-R3', PSL, PSU, IAR, RAS, state) every clock.
//
//   lockstep random  <seed> <cycles>      random instruction streams, random bus / irq / sense / reset
//   lockstep sweep   [seeds-per-variant]  directed irq / reset / ack-stall sweeps, every opcode x mode
//   lockstep prog    <file.bin> <cycles>  run a binary from 0000 (exerciser), realistic bus
#include "Vtb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <memory>

#ifndef VARIANT_NAME
#define VARIANT_NAME "?"
#endif

static uint64_t rng_s;
static inline uint64_t rnd() { rng_s ^= rng_s << 13; rng_s ^= rng_s >> 7; rng_s ^= rng_s << 17; return rng_s; }
static inline uint32_t rndn(uint32_t n) { return (uint32_t)(rnd() % n); }
static inline bool chance(uint32_t num, uint32_t den) { return rndn(den) < num; }

//------------------------------------------------------------------------------
// Opcode table (format, length) from sgs2650_pack, for coverage
enum Fmt { Z, I, R, A, B, C, E, EI, ER, EB };
static Fmt fmt_of(int op) {
    int lo = op & 15, row = op >> 4;
    if (op == 0x40) return E;
    if ((row & 1) == 0) { int g = lo >> 2; return g == 0 ? Z : g == 1 ? I : g == 2 ? R : A; }
    if (op == 0x10 || op == 0x11) return C;
    if (op == 0x12 || op == 0x13 || (op >= 0x90 && op <= 0x93)) return E;
    if (op == 0x74 || op == 0x75 || op == 0x76 || op == 0x77 || (op >= 0xB4 && op <= 0xB7)) return EI;
    if (op == 0x9B || op == 0xBB) return ER;
    if (op == 0x9F || op == 0xBF) return EB;
    int g = lo >> 2;
    if (g == 0) return Z;
    if (g == 1) return (row == 1 || row == 3 || row == 9) ? Z : I;
    return g == 2 ? R : B;
}
static int len_of(int op) { Fmt f = fmt_of(op); return (f == Z || f == E) ? 1 : (f == I || f == R || f == EI || f == ER) ? 2 : 3; }
// flow kind: 0 none, 1 conditional (taken / not taken), 2 always taken
static int flow_kind(int op) {
    int row = op >> 4, g = (op & 15) >> 2;
    if ((row == 1 || row == 3) && g == 1) return (op & 3) == 3 ? 2 : 1;              // RETC RETE
    if ((row & 1) && g >= 2) {
        if (row == 1 || row == 3 || row == 9 || row == 11) return (op & 3) == 3 ? 2 : 1;
        return 1;                                                                    // BRN BSN BIR BDR
    }
    return 0;
}
static bool is_ret(int op) { int row = op >> 4; return (row == 1 || row == 3) && ((op & 15) >> 2) == 1; }
// variants: R/ER/B/EB: indirect bit; A: index mode x indirect (only for ALU / STR absolute)
static int nvariants(int op) { Fmt f = fmt_of(op); return f == A ? 8 : (f == R || f == ER || f == B || f == EB) ? 2 : 1; }
static int variant_of(int op, int b2) {
    Fmt f = fmt_of(op);
    if (f == A) return ((b2 >> 5) & 3) | ((b2 >> 7) << 2);
    if (f == R || f == ER || f == B || f == EB) return b2 >> 7;
    return 0;
}
static bool hangs(int op) { return (op >= 0xC4 && op <= 0xC7) || op == 0x10 || op == 0x11; }

//------------------------------------------------------------------------------
struct In { bool reset = false, ack = true, irq = false, sense = false, garbage = false; uint8_t ivec = 3; };

struct Cov {
    // key: op*64 + variant*2 + taken
    std::map<int, uint64_t> hit;
    uint64_t instrs = 0, ints = 0, ints_ind = 0, rete = 0, push_wrap = 0, pop_wrap = 0, halts = 0, halt_wake = 0,
             resets = 0, resets_mid = 0, io_rd = 0, io_wr = 0, stalls = 0;
    void merge(const Cov &o) {
        for (auto &k : o.hit) hit[k.first] += k.second;
        instrs += o.instrs; ints += o.ints; ints_ind += o.ints_ind; rete += o.rete; push_wrap += o.push_wrap;
        pop_wrap += o.pop_wrap; halts += o.halts; halt_wake += o.halt_wake; resets += o.resets;
        resets_mid += o.resets_mid; io_rd += o.io_rd; io_wr += o.io_wr; stalls += o.stalls;
    }
};

struct Bench {
    std::unique_ptr<VerilatedContext> ctx;
    std::unique_ptr<Vtb_top> t;
    uint8_t mem[32768];
    uint8_t io_ext[256], io_cd[2];
    uint8_t dr_reg = 0;
    uint64_t cyc = 0, mism = 0;
    Cov cov;
    bool quiet = false;
    // instruction tracking
    bool in_ins = false; int cur_op = 0, cur_b2 = 0, cur_pc = 0, cur_imm = 0; uint8_t cur_sp = 0;
    struct RingEnt { uint64_t cyc; In in; uint8_t dr, st; uint16_t iar; uint32_t r; };
    RingEnt ring[40]; unsigned ring_n = 0;
    std::vector<std::pair<uint16_t, uint8_t>> io_writes;   // (ext<<9 | dc<<8 | port, data)

    Bench() {
        ctx.reset(new VerilatedContext);
        t.reset(new Vtb_top(ctx.get()));
        memset(mem, 0, sizeof mem); memset(io_ext, 0, sizeof io_ext); io_cd[0] = io_cd[1] = 0;
        t->clk = 0; t->eval();
    }

    static uint32_t pack_r(Vtb_top *t) {
        return t->r_req | (t->r_ad << 1) | (t->r_wr << 16) | ((uint32_t)t->r_dw << 17) | ((uint32_t)t->r_mio << 25) |
               ((uint32_t)t->r_ene << 26) | ((uint32_t)t->r_dc << 27) | ((uint32_t)t->r_ph << 28) |
               ((uint32_t)t->r_intack << 30) | ((uint32_t)t->r_flag << 31);
    }
    static uint32_t pack_d(Vtb_top *t) {
        return t->d_req | (t->d_ad << 1) | (t->d_wr << 16) | ((uint32_t)t->d_dw << 17) | ((uint32_t)t->d_mio << 25) |
               ((uint32_t)t->d_ene << 26) | ((uint32_t)t->d_dc << 27) | ((uint32_t)t->d_ph << 28) |
               ((uint32_t)t->d_intack << 30) | ((uint32_t)t->d_flag << 31);
    }
    static std::string fmt_bus(uint32_t v) {
        char b[160];
        snprintf(b, sizeof b, "req=%u ad=%04X wr=%u dw=%02X mio=%u ene=%u dc=%u ph=%u intack=%u flag=%u", v & 1,
                 (v >> 1) & 0x7FFF, (v >> 16) & 1, (v >> 17) & 0xFF, (v >> 25) & 1, (v >> 26) & 1, (v >> 27) & 1,
                 (v >> 28) & 3, (v >> 30) & 1, (v >> 31) & 1);
        return b;
    }
    void fail(const char *what, const std::string &detail) {
        mism++;
        if (mism > 3) return;
        printf("MISMATCH [%s] cycle %llu: %s\n%s\n--- last cycles (ref) ---\n", VARIANT_NAME, (unsigned long long)cyc,
               what, detail.c_str());
        for (unsigned i = ring_n > 40 ? ring_n - 40 : 0; i < ring_n; i++) {
            const RingEnt &e = ring[i % 40];
            printf("%8llu rst=%d ack=%d irq=%d ivec=%02X sns=%d dr=%02X st=%d iar=%04X | %s\n",
                   (unsigned long long)e.cyc, e.in.reset, e.in.ack, e.in.irq, e.in.ivec, e.in.sense, e.dr, e.st,
                   e.iar, fmt_bus(e.r).c_str());
        }
        fflush(stdout);
    }
    void dump_ring(const In &in, uint32_t r) {
        ring[ring_n++ % 40] = RingEnt{cyc, in, t->dr, (uint8_t)t->r_state, (uint16_t)t->r_iar, r};
    }

    // one clock; returns false on mismatch
    FILE *dumpf = nullptr;     // per-cycle inputs and reference outputs, for the GHDL cross-check
    bool step(const In &in) {
        t->reset = in.reset; t->ack = in.ack; t->irq = in.irq; t->ivec = in.ivec; t->sense = in.sense;
        t->dr = (in.garbage && !in.ack) ? (uint8_t)rnd() : dr_reg;
        t->clk = 0;
        t->eval();
        uint32_t r = pack_r(t.get()), d = pack_d(t.get());
        if (dumpf) fprintf(dumpf, "%d %d %d %d %02X %02X %08X\n", in.reset, in.ack, in.irq, in.sense, t->dr, in.ivec, r);
        if (!quiet) dump_ring(in, r);
        bool ok = true;
        if (r != d) { fail("outputs", "ref " + fmt_bus(r) + "\ndut " + fmt_bus(d)); ok = false; }

        // instruction-level bookkeeping (ref state; state equality is checked below)
        int st = t->r_state;
        bool go = in.ack || !prev_req;
        fetched_now = false;
        uint8_t sp = t->r_regs[0] & 7;
        if (go && !in.reset) {
            if (st == 0) {
                if (in_ins) end_ins(t->r_iar);
                bool irqt = in.irq && !((t->r_regs[0] >> 5) & 1);
                if (irqt) { cov.ints++; if (in.ivec & 0x80) cov.ints_ind++; in_ins = false; }
                else {
                    in_ins = true; cur_op = t->dr; cur_pc = t->r_iar; cur_b2 = 0; cur_sp = sp;
                    fetched_now = true; fetch_pc = t->r_iar;
                    if (hangs(cur_op)) cov.hit[cur_op * 64]++;
                }
            } else if (st == 1 && in_ins) { cur_b2 = t->dr; }
            else if (st == 10 && in.irq && !((t->r_regs[0] >> 5) & 1)) cov.halt_wake++;
            if (st == 7 && in_ins) { if (cur_op & 0x80) cov.io_wr++; else cov.io_rd++; }
        }
        if (!in.ack && t->r_req) cov.stalls++;
        if (in.reset) { cov.resets++; if (st != 0 || prev_req == 0) cov.resets_mid++; in_ins = false; }

        // bus: the access shown during an ack completes; read data is presented for the next ack
        // (reset: the board restarts the bus on a read of 0000, as the fleet boards do)
        // dutbus: the bus follows s2650sv instead of the reference (to run a program on s2650sv alone)
        bool b_req = dutbus ? t->d_req : t->r_req, b_wr = dutbus ? t->d_wr : t->r_wr;
        bool b_mio = dutbus ? t->d_mio : t->r_mio, b_ene = dutbus ? t->d_ene : t->r_ene, b_dc = dutbus ? t->d_dc : t->r_dc;
        uint16_t b_ad = dutbus ? t->d_ad : t->r_ad;
        uint8_t b_dw = dutbus ? t->d_dw : t->r_dw;
        if (in.reset) dr_reg = mem[0];
        else if (b_req && in.ack) {
            uint16_t a = b_ad;
            if (b_mio) {
                if (b_wr) mem[a] = b_dw; else dr_reg = mem[a];
            } else {
                uint8_t *p = b_ene ? &io_ext[a & 0xFF] : &io_cd[b_dc];
                if (b_wr) { *p = b_dw; io_writes.push_back({(uint16_t)((b_ene << 9) | (b_dc << 8) | (a & 0xFF)), b_dw}); }
                else dr_reg = *p ^ 0x5A;
            }
        }
        prev_req = t->r_req;

        t->clk = 1;
        t->eval();
        cyc++;
        // architectural / state probes
        uint64_t rr[2] = {t->r_regs[0] | ((uint64_t)t->r_regs[1] << 32), (uint64_t)t->r_regs[2]};
        uint64_t dd[2] = {t->d_regs[0] | ((uint64_t)t->d_regs[1] << 32), (uint64_t)t->d_regs[2]};
        bool sok = rr[0] == dd[0] && rr[1] == dd[1] && t->r_iar == t->d_iar && t->d_state == (1u << t->r_state);
        for (int i = 0; i < 4 && sok; i++) sok = t->r_ras[i] == t->d_ras[i];
        if (!sok) {
            char b[400];
            snprintf(b, sizeof b, "ref regs %02llX%016llX iar %04X st %d ras %08X%08X%08X%08X\n"
                                  "dut regs %02llX%016llX iar %04X st %03X ras %08X%08X%08X%08X",
                     (unsigned long long)rr[1], (unsigned long long)rr[0], t->r_iar, t->r_state,
                     t->r_ras[3], t->r_ras[2], t->r_ras[1], t->r_ras[0],
                     (unsigned long long)dd[1], (unsigned long long)dd[0], t->d_iar, t->d_state,
                     t->d_ras[3], t->d_ras[2], t->d_ras[1], t->d_ras[0]);
            fail("state", b); ok = false;
        }
        uint8_t nsp = t->r_regs[0] & 7;
        if (sp == 7 && nsp == 0 && !in.reset) cov.push_wrap++;
        if (sp == 0 && nsp == 7 && !in.reset) cov.pop_wrap++;
        if (st != 10 && t->r_state == 10) cov.halts++;
        t->clk = 0;
        return ok;
    }
    bool prev_req = false, fetched_now = false, dutbus = false;
    int fetch_pc = 0;

    void end_ins(int next_pc) {
        int op = cur_op, L = len_of(op);
        int var = variant_of(op, cur_b2);
        int taken = 0;
        if (flow_kind(op)) taken = next_pc != ((cur_pc + L) & 0x7FFF);
        if ((op & 0xFC) == 0x34 && taken) cov.rete++;
        if (!hangs(op)) cov.hit[op * 64 + var * 2 + taken]++;
        cov.instrs++;
        in_ins = false;
    }
};

// expected coverage keys
static std::set<int> expected_keys() {
    std::set<int> s;
    for (int op = 0; op < 256; op++) {
        if (hangs(op)) { s.insert(op * 64); continue; }
        int nv = nvariants(op), k = flow_kind(op);
        for (int v = 0; v < nv; v++) {
            if (k == 1) { s.insert(op * 64 + v * 2); s.insert(op * 64 + v * 2 + 1); }
            else s.insert(op * 64 + v * 2 + (k == 2 ? 1 : 0));
        }
    }
    return s;
}

static void cov_report(const Cov &c, const char *title) {
    auto exp = expected_keys();
    int miss = 0;
    std::string ml;
    for (int k : exp) if (!c.hit.count(k)) { miss++; if (miss <= 40) { char b[32]; snprintf(b, sizeof b, " %02X/v%d/t%d", k / 64, (k % 64) / 2, k & 1); ml += b; } }
    // the same ignoring taken / not taken: opcode x addressing mode only
    std::set<int> expm, hitm;
    for (int k : exp) expm.insert(k & ~1);
    for (auto &k : c.hit) hitm.insert(k.first & ~1);
    int missm = 0;
    std::string mml;
    for (int k : expm) if (!hitm.count(k)) { missm++; if (missm <= 40) { char b[32]; snprintf(b, sizeof b, " %02X/v%d", k / 64, (k % 64) / 2); mml += b; } }
    printf("[%s] %s coverage: %zu / %zu opcode x addressing-mode classes hit, %d missing%s%s\n", VARIANT_NAME, title,
           expm.size() - missm, expm.size(), missm, missm ? ":" : "", mml.c_str());
    int extra = 0;
    for (auto &k : c.hit) if (!exp.count(k.first)) extra++;
    printf("[%s] %s coverage: %zu / %zu opcode x mode x taken classes hit, %d missing%s%s\n", VARIANT_NAME, title,
           exp.size() - miss, exp.size(), miss, miss ? ":" : "", ml.c_str());
    printf("[%s] %s: instrs %llu, interrupts %llu (indirect vec %llu), RETE taken %llu, RAS push wrap %llu, pop wrap %llu,"
           " HALT %llu (irq wake %llu), resets %llu (mid-instr %llu), IO rd %llu wr %llu, stalled cycles %llu\n",
           VARIANT_NAME, title, (unsigned long long)c.instrs, (unsigned long long)c.ints,
           (unsigned long long)c.ints_ind, (unsigned long long)c.rete, (unsigned long long)c.push_wrap,
           (unsigned long long)c.pop_wrap, (unsigned long long)c.halts, (unsigned long long)c.halt_wake,
           (unsigned long long)c.resets, (unsigned long long)c.resets_mid, (unsigned long long)c.io_rd,
           (unsigned long long)c.io_wr, (unsigned long long)c.stalls);
}

//------------------------------------------------------------------------------
// Random mode
struct Profile {
    int ack_mode; uint32_t ack_p; uint32_t ack_maxd; uint32_t ack_per;
    bool garbage; int irq_mode; int ivec_mode; uint8_t ivec_fix; uint32_t reset_rate; int mem_mode;
};

static Profile rand_profile() {
    Profile p;
    p.ack_mode = rndn(4); p.ack_p = 20 + rndn(80); p.ack_maxd = 1 + rndn(6); p.ack_per = 1 + rndn(6);
    p.garbage = chance(1, 2); p.irq_mode = rndn(4); p.ivec_mode = rndn(4);
    static const uint8_t fixv[] = {0x03, 0x00, 0x83, 0x7F, 0x40};
    p.ivec_fix = chance(1, 2) ? fixv[rndn(5)] : (uint8_t)rnd();
    p.reset_rate = 2000 + rndn(20000); p.mem_mode = rndn(3);
    return p;
}

static void fill_mem(Bench &b, int mode) {
    for (int i = 0; i < 32768; i++) {
        uint8_t v = (uint8_t)rnd();
        // mode 1: fewer hanging / halting opcodes; mode 2: small relative offsets and mostly page-local pointers
        if (mode >= 1) while (hangs(v) || v == 0x40) v = (uint8_t)rnd();
        if (mode == 2 && chance(1, 3)) v = (uint8_t)(rnd() & 0x8F);
        b.mem[i] = v;
    }
    for (int i = 0; i < 256; i++) b.io_ext[i] = (uint8_t)rnd();
    b.io_cd[0] = (uint8_t)rnd(); b.io_cd[1] = (uint8_t)rnd();
}

static FILE *g_dump = nullptr;
static bool g_xinit = false;     // GHDL cross-check: start with a program that defines every register
static int run_random(uint64_t seed, uint64_t cycles) {
    rng_s = seed * 0x9E3779B97F4A7C15ull + 1;
    Cov total;
    uint64_t done = 0, mism = 0;
    int segs = 0;
    while (done < cycles && !mism) {
        Bench b; b.quiet = false; b.dumpf = g_dump;
        Profile p = rand_profile();
        fill_mem(b, p.mem_mode);
        if (g_xinit) {
            // R0-R3, R1'-R3', PSL, PSU, then 8 nested calls (all RAS entries), then BCTA $0100 into random code
            static const uint8_t init[] = {0x04, 0x00, 0x93, 0x05, 0x11, 0x06, 0x22, 0x07, 0x33, 0x77, 0x10, 0x05, 0x44,
                                           0x06, 0x55, 0x07, 0x66, 0x75, 0x10, 0x04, 0x00, 0x92, 0x3F, 0x00, 0x20,
                                           0x1F, 0x01, 0x00};
            memcpy(b.mem, init, sizeof init);
            for (int k = 0; k < 7; k++) {
                int a = 0x20 + 4 * k, n = a + 4;
                b.mem[a] = 0x3F; b.mem[a + 1] = n >> 8; b.mem[a + 2] = n & 0xFF; b.mem[a + 3] = 0x17;
            }
            b.mem[0x3C] = 0x17;
            p.irq_mode = 0;
        }
        uint64_t seg = g_xinit ? cycles : 200000 + rndn(800000);
        In in; in.reset = true; in.garbage = p.garbage;
        uint32_t ackd = 0, ackc = 0, rst_left = 1 + rndn(3), irq_hold = 0;
        bool irq = false;
        for (uint64_t c = 0; c < seg && done < cycles; c++, done++) {
            // reset
            if (g_xinit && c < 4) rst_left = 1;
            if (g_xinit && c == 3000) p.irq_mode = 1 + rndn(3);
            if (rst_left) { in.reset = true; rst_left--; }
            else { in.reset = false; if (chance(1, p.reset_rate)) rst_left = 1 + rndn(4); }
            // ack
            switch (p.ack_mode) {
            case 0: in.ack = true; break;
            case 1: in.ack = chance(p.ack_p, 100); break;
            case 2: if (ackd) { in.ack = false; ackd--; } else { in.ack = true; ackd = rndn(p.ack_maxd + 1); } break;
            default: in.ack = (ackc++ % p.ack_per) == 0; break;
            }
            // irq
            switch (p.irq_mode) {
            case 0: irq = false; break;
            case 1: if (irq_hold) irq_hold--; else { irq = chance(1, 3); irq_hold = rndn(200); } break;
            case 2: irq = chance(1, 500); break;
            default: if (irq_hold) irq_hold--; else { irq = !irq; irq_hold = rndn(irq ? 40 : 3000); } break;
            }
            in.irq = irq;
            switch (p.ivec_mode) {
            case 0: in.ivec = 0x03; break;
            case 1: in.ivec = p.ivec_fix; break;
            case 2: in.ivec = (uint8_t)rnd(); break;
            default: if (chance(1, 50)) in.ivec = (uint8_t)rnd(); break;
            }
            if (chance(1, 300)) in.sense = !in.sense;
            if (chance(1, 400000)) fill_mem(b, p.mem_mode);
            if (!b.step(in)) { mism += b.mism; break; }
        }
        mism += b.mism;
        total.merge(b.cov);
        segs++;
    }
    printf("[%s] random seed %llu: %llu cycles in %d segments, %llu mismatches\n", VARIANT_NAME,
           (unsigned long long)seed, (unsigned long long)done, segs, (unsigned long long)mism);
    cov_report(total, "random");
    return mism ? 1 : 0;
}

//------------------------------------------------------------------------------
// Directed sweeps: prologue sets both banks, PSL, PSU (II=0, random SP / flag); then the target instruction
struct Prog { std::vector<uint8_t> bytes; int target_at; };

static int regval() { static const int v[] = {0x00, 0x01, 0xFF}; return chance(1, 2) ? v[rndn(3)] : (int)(rnd() & 0xFF); }

static Prog make_prog(int op, int var) {
    Prog p;
    auto e = [&](std::initializer_list<int> l) { for (int x : l) p.bytes.push_back((uint8_t)x); };
    uint8_t psl = (uint8_t)rnd();
    e({0x04, psl & ~0x10, 0x93});                                       // LODI,R0  LPSL (RS=0)
    e({0x05, regval(), 0x06, regval(), 0x07, regval()});
    e({0x77, 0x10});                                                    // PPSL RS
    e({0x05, regval(), 0x06, regval(), 0x07, regval()});
    uint8_t psu = (uint8_t)(rnd() & ~0x20);
    e({0x04, psu, 0x92});                                               // LPSU (II=0)
    if (chance(1, 3)) psl &= 0xEF;                                      // R0 = PSL: with RS=0, also 00 / 01 / FF
    if (chance(1, 4)) psl = (uint8_t)(chance(1, 2) ? 0x01 : 0xFF);
    e({0x04, psl, 0x93});                                               // LPSL
    p.target_at = (int)p.bytes.size();
    p.bytes.push_back((uint8_t)op);
    int L = len_of(op);
    Fmt f = fmt_of(op);
    uint8_t b2 = (uint8_t)rnd(), b3 = (uint8_t)rnd();
    if (f == A) b2 = (b2 & 0x1F) | ((var & 3) << 5) | ((var >> 2) << 7);
    else if (f == R || f == ER || f == B || f == EB) b2 = (b2 & 0x7F) | (var << 7);
    if (L >= 2) p.bytes.push_back(b2);
    if (L >= 3) p.bytes.push_back(b3);
    return p;
}

static int run_sweep(int seeds) {
    rng_s = 0x5EED5EED;
    Cov total;
    uint64_t runs = 0, cycles = 0, mism = 0;
    for (int op = 0; op < 256 && !mism; op++) {
        int nv = nvariants(op);
        for (int var = 0; var < nv && !mism; var++)
            for (int s = 0; s < seeds && !mism; s++) {
                Prog pg = make_prog(op, var);
                std::vector<uint8_t> image(32768);
                for (auto &x : image) x = (uint8_t)rnd();
                for (size_t i = 0; i < pg.bytes.size(); i++) image[i] = pg.bytes[i];
                uint8_t ivec_a = (uint8_t)(rnd() & 0x7F), ivec_i = (uint8_t)(0x80 | (rnd() & 0x7F));
                uint8_t ioinit[258];
                for (auto &x : ioinit) x = (uint8_t)rnd();

                // kind: 0 baseline, 1 irq pulse at k, 2 irq held from k, 3 irq held from k (indirect vector),
                //       4 reset at k, 5 ack stall 1 at k, 6 stall 2, 7 stall 3, 8 stall 2 + garbage dr
                int c0 = -1, c1 = -1;
                for (int kind = 0; kind <= 8 && !mism; kind++) {
                    int kmin = kind == 0 ? 0 : c0 - 1, kmax = kind == 0 ? 0 : c1 + 1;
                    for (int k = kmin; k <= kmax && !mism; k++) {
                        Bench b; b.quiet = false;
                        memcpy(b.mem, image.data(), 32768);
                        memcpy(b.io_ext, ioinit, 256); b.io_cd[0] = ioinit[256]; b.io_cd[1] = ioinit[257];
                        int horizon = kind == 0 ? 400 : c1 + 24;
                        int stall = kind >= 5 ? (kind == 5 ? 1 : kind == 6 ? 2 : kind == 7 ? 3 : 2) : 0;
                        for (int c = 0; c < horizon; c++) {
                            In in;
                            in.reset = c < 2 || (kind == 4 && c == k);
                            in.ack = !(stall && c >= k && c < k + stall);
                            in.garbage = kind == 8;
                            in.irq = (kind == 1 && c == k) || ((kind == 2 || kind == 3) && c >= k);
                            in.ivec = kind == 3 ? ivec_i : ivec_a;
                            in.sense = (c >> 3) & 1;
                            if (!b.step(in)) break;
                            // baseline: the fetch of the target and of the next instruction
                            if (kind == 0 && b.fetched_now) {
                                if (b.fetch_pc == pg.target_at && c0 < 0) c0 = c;
                                else if (c0 >= 0 && c1 < 0) c1 = c;
                            }
                            if (kind == 0 && c1 >= 0 && c > c1 + 4) break;
                        }
                        if (kind == 0) {
                            if (c0 < 0) { printf("sweep: target %02X not reached\n", op); mism++; }
                            if (c1 < 0) c1 = c0 + 12;            // halts and hangs: sweep a window
                        }
                        mism += b.mism;
                        runs++; cycles += b.cyc;
                        total.merge(b.cov);
                    }
                }
            }
    }
    printf("[%s] sweep: %llu runs, %llu cycles, %llu mismatches\n", VARIANT_NAME, (unsigned long long)runs,
           (unsigned long long)cycles, (unsigned long long)mism);
    cov_report(total, "sweep");
    return mism ? 1 : 0;
}

//------------------------------------------------------------------------------
// Program mode: exerciser. Bus: ack every <ackper> clocks (fleet-like), dr = data of the pending access.
// Protocol (extended ports): FE console, FF result ('P' pass, else fail), FB failing test number (hi, lo),
// FD interrupt request with that vector after (FA)*4 clocks, held until INTACK, FC sense: bit 0, or the
// flag output when bit 1 is set.
static int run_prog(const char *file, uint64_t cycles, uint32_t ackper) {
    FILE *f = fopen(file, "rb");
    if (!f) { printf("cannot open %s\n", file); return 2; }
    Bench b;
    size_t n = fread(b.mem, 1, sizeof b.mem, f);
    fclose(f);
    printf("[%s] loaded %zu bytes from %s, ack every %u clocks\n", VARIANT_NAME, n, file, ackper);
    rng_s = 12345;
    In in;
    uint64_t c;
    size_t seen = 0;
    int result = -1, delay = -1;
    std::string con, tnum;
    bool irq_pend = false;
    // DUTBUS: memory / I/O follow s2650sv, lockstep mismatches do not stop the run (judge s2650sv alone)
    bool trace = getenv("TRACE") != nullptr, nolock = getenv("DUTBUS") != nullptr;
    b.dutbus = nolock;
    int pcs[8] = {0}; unsigned npc = 0;
    for (c = 0; c < cycles; c++) {
        in.reset = c < 3;
        in.ack = (c % ackper) == 0;
        if (delay > 0) delay--;
        else if (delay == 0) { irq_pend = true; delay = -1; }
        in.irq = irq_pend;
        in.sense = (b.io_ext[0xFC] & 2) ? (nolock ? b.t->d_flag : b.t->r_flag) : (b.io_ext[0xFC] & 1);
        if (!b.step(in) && !nolock) break;
        if (b.fetched_now) pcs[npc++ % 8] = b.fetch_pc;
        if (trace && b.fetched_now) {
            const uint8_t *r = b.t->r_regs.data() ? (const uint8_t *)b.t->r_regs.data() : nullptr;
            printf("TR %04X %02X %02X %02X  r0=%02X r1-3=%02X %02X %02X psl=%02X psu=%02X\n", b.fetch_pc, b.mem[b.fetch_pc],
                   b.mem[(b.fetch_pc + 1) & 0x7FFF], b.mem[(b.fetch_pc + 2) & 0x7FFF], r[8], r[7], r[6], r[5], r[1], r[0]);
        }
        if (nolock ? b.t->d_intack : b.t->r_intack) irq_pend = false;
        for (; seen < b.io_writes.size(); seen++) {
            auto w = b.io_writes[seen];
            if ((w.first & 0x200) == 0) continue;
            int port = w.first & 0xFF;
            if (port == 0xFE) con += (char)w.second;
            if (port == 0xFD) { in.ivec = w.second; delay = b.io_ext[0xFA] * 4; }
            if (port == 0xFB) { char t[4]; snprintf(t, sizeof t, "%02X", w.second); tnum += t; }
            if (port == 0xFF) result = w.second;
        }
        if (result >= 0 && (nolock ? (b.t->d_state >> 10) & 1 : b.t->r_state == 10)) break;
    }
    printf("%s", con.c_str());
    printf("\n[%s] exerciser: %llu cycles, result %s", VARIANT_NAME, (unsigned long long)c,
           result == 'P' ? "PASS" : result < 0 ? "NONE (no result written)" : "FAIL");
    if (result >= 0 && result != 'P') {
        printf(" (last instructions:");
        for (unsigned i = npc > 8 ? npc - 8 : 0; i < npc; i++) printf(" %04X", pcs[i % 8]);
        printf(")");
    }
    printf(", RESULT byte at $7FF0 = %02X, %llu lockstep mismatches\n", b.mem[0x7FF0], (unsigned long long)b.mism);
    cov_report(b.cov, "exerciser");
    return (result == 'P' && !b.mism) ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: lockstep random <seed> <cycles> | sweep [seeds] | prog <bin> <cycles> [ackper]\n"); return 2; }
    std::string m = argv[1];
    if (m == "random") return run_random(strtoull(argv[2], 0, 0), strtoull(argv[3], 0, 0));
    if (m == "dump") { g_xinit = true; g_dump = fopen(argv[4], "w"); int r = run_random(strtoull(argv[2], 0, 0), strtoull(argv[3], 0, 0)); fclose(g_dump); return r; }
    if (m == "sweep") return run_sweep(argc > 2 ? atoi(argv[2]) : 2);
    if (m == "prog") return run_prog(argv[2], strtoull(argv[3], 0, 0), argc > 4 ? atoi(argv[4]) : 3);
    return 2;
}

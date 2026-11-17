// Copyright (C) 2026 Rodimus
// SingleStepTests runner for x86sv (Verilator): 8088 v2 / V20 v1 (8-bit bus); with -DBUS16 8086 v1 (16-bit bus).
//   sim [-n N] [-i index] [-s] [-e K] [-q] file.MOO.gz ...
//   -n N   first N tests of each file      -i k   only test k
//   -s     stop at the first failure and dump it (expected vs actual per cycle)
//   -e K   print event summaries of the first K failures per file
//   -q     table only
//   -l     one line per test: index, queue (p/n), R M C B fail flags, expected / got cycles, name
//   -L     as -l, plus the expected and actual compact traces of failing tests (see line())
#include "Vtb_x86.h"
#include "moo.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

static Vtb_x86 *top;
static uint8_t mem[1 << 20];

static const int bus_map[8] = {0, 1, 2, 5, 6, 3, 4, 7}; // S2-S0 -> moo bus_status
#ifdef NEC
static const uint8_t PFX[] = {0x26, 0x2E, 0x36, 0x3E, 0xF0, 0xF2, 0xF3, 0x64, 0x65};   // + REPNC / REPC
#else
static const uint8_t PFX[] = {0x26, 0x2E, 0x36, 0x3E, 0xF0, 0xF2, 0xF3};
#endif
static bool is_pfx(uint8_t b) {
    for (uint8_t p : PFX) if (p == b) return true;
    return false;
}

static void tick() {
    top->eval();
    top->clk = 1; top->eval();
    top->clk = 0; top->eval();
}

struct Result {
    bool reg_ok = true, mem_ok = true, cyc_ok = true, bus_ok = true;
    int drift = 0;                      // idle clocks where the floating AD7-AD0 drifted (accepted)
    int lane = 0;                       // BUS16: clocks where only the masked inactive half of AD15-0 differed
    std::vector<moo::Cycle> got;
    uint16_t regs[moo::R_NUM] = {};
    std::vector<std::string> notes;
    bool pass() const { return reg_ok && mem_ok && cyc_ok && bus_ok; }
};

static void set_w(uint32_t *w, int bit, int n, uint32_t v) {
    for (int i = 0; i < n; i++) {
        int b = bit + i;
        if ((v >> i) & 1) w[b / 32] |= 1u << (b % 32); else w[b / 32] &= ~(1u << (b % 32));
    }
}
static uint32_t get_w(const uint32_t *w, int bit, int n) {
    uint32_t v = 0;
    for (int i = 0; i < n; i++) { int b = bit + i; v |= ((w[b / 32] >> (b % 32)) & 1u) << i; }
    return v;
}

static Result run(const moo::Test &t) {
    Result res;
    memset(mem, 0x90, sizeof mem);
    std::map<uint32_t, uint8_t> init_ram, fina_ram;
    for (auto &m : t.init.ram) { mem[m.first & 0xFFFFF] = m.second; init_ram[m.first & 0xFFFFF] = m.second; }
    for (auto &m : t.fina.ram) fina_ram[m.first & 0xFFFFF] = m.second;

    top->reset = 1; top->tl_en = 0; top->din = 0x90; top->tl_md = 1; top->tl_mdwe = 0;
    top->ready = 1; top->intr = 0; top->nmi = 0; top->test_n = 0;
    tick(); tick();
    top->reset = 0;
    for (int i = 0; i < 7; i++) top->tl_regs[i] = 0;
    for (int r = 0; r < moo::R_NUM; r++) set_w(top->tl_regs, r * 16, 16, t.init.regs[r]);
#ifdef BUS16
    const size_t QMAX = 6;
#else
    const size_t QMAX = 4;
#endif
    size_t ql = t.init.queue.size() > QMAX ? QMAX : t.init.queue.size();
    uint64_t qv = 0;
    for (size_t i = 0; i < ql; i++) qv |= (uint64_t)t.init.queue[i] << (8 * i);
    top->tl_qlen = ql; top->tl_queue = qv;
    top->tl_ad = t.cycles.empty() ? 0 : t.cycles[0].addr & 0xFFFFF;
    top->tl_bhe = t.cycles.empty() ? 1 : (t.cycles[0].bhe & 1);
    top->tl_en = 1;
    tick();
    top->tl_en = 0;

    // the capture rig serves the instruction bytes to the first code fetches and NOPs to every later one
    uint32_t latch = 0;
    bool code = false, iocyc = false;
    size_t nfetch = 0;
    int lanes = 1;                      // active data lanes of the current cycle: b0 AD7-0, b1 AD15-8
    bool started = false;
    int opc = 0;
    std::vector<uint32_t> writes;
    size_t limit = t.cycles.size() * 4 + 256;   // runs past the expected end so registers are compared at the real end
    for (int guard = 0; guard < 65536; guard++) {
#ifdef BUS16
        // word bus: memory supplies both bytes of the aligned word; code fetches take the next instruction bytes in
        // fetch order (one byte on AD15-8 at an odd address)
        auto cbyte = [&](size_t k) { return k < t.bytes.size() ? t.bytes[k] : (uint8_t)0x90; };
        auto feed = [&]() {
            if (iocyc) return (uint16_t)0xFFFF;
            if (!code) return (uint16_t)(mem[latch & ~1u] | (mem[(latch | 1u) & 0xFFFFF] << 8));
            size_t k = ql + nfetch;
            if (latch & 1) return (uint16_t)(0x90 | (cbyte(k) << 8));
            return (uint16_t)(cbyte(k) | (cbyte(k + 1) << 8));
        };
#else
        auto feed = [&]() {
            if (iocyc) return (uint8_t)0xFF;  // the rig answers every I/O read with FF
            if (!code) return mem[latch];
            size_t k = ql + nfetch - 1;
            return k < t.bytes.size() ? t.bytes[k] : (uint8_t)0x90;
        };
#endif
        top->din = feed();
        top->eval();
        if (top->ale) {
#ifdef BUS16
            if (code) nfetch += (latch & 1) ? 1 : 2;
#endif
            latch = top->ad & 0xFFFFF;
            code = (top->s20 & 7) == 4;
            iocyc = (top->s20 & 7) == 1 || (top->s20 & 7) == 2;
#ifdef BUS16
            lanes = ((latch & 1) ? 0 : 1) | (top->bhe_n ? 0 : 2);
#else
            if (code) nfetch++;
#endif
        }
        top->din = feed();
        top->eval();
        moo::Cycle c{};
        c.pins = top->ale ? 1 : 0;
        c.addr = top->ad & 0xFFFFF;
        c.seg = top->seg_v ? top->seg_s : 4;
        uint8_t strobes = (top->rd << 2) | (top->wra << 1) | top->wr;
        c.mem = top->io ? 0 : strobes;
        c.io = top->io ? strobes : 0;
#ifdef BUS16
        c.bhe = top->bhe_n;
        c.data = (top->tstate == 3 && (top->rd || top->wra)) ?
                 (top->ad & ((lanes & 1) ? 0x00FF : 0) & 0xFFFF) | (top->ad & ((lanes & 2) ? 0xFF00 : 0)) : 0;
#else
        c.bhe = 0;
        c.data = (top->tstate == 3 && (top->rd || top->wra)) ? (top->ad & 0xFF) : 0;
#endif
        c.bus = bus_map[top->s20 & 7];
        c.ts = top->tstate;
        c.qop = top->qs;
        c.qbyte = top->qs_byte;
#ifdef BUS16
        if (top->wr && top->tstate == 3 && !top->io) {
            if (lanes & 1) { mem[latch] = top->dout & 0xFF; writes.push_back(latch); }
            if (lanes & 2) { uint32_t a = (latch | 1u) & 0xFFFFF; mem[a] = top->dout >> 8; writes.push_back(a); }
        }
#else
        if (top->wr && top->tstate == 3 && !top->io) { mem[latch] = top->dout; writes.push_back(latch); }
#endif
        if (!started && c.qop == 1) started = true;
        if (started) {
            if (c.qop == 1 && !is_pfx(c.qbyte)) {
                if (++opc == 2) break;
            }
            res.got.push_back(c);
            if (res.got.size() > limit) break;
        }
        tick();
    }

    // registers (sampled at the cycle that shows the next opcode fetch)
    uint32_t *dr = top->dbg_regs;
    for (int r = 0; r < moo::R_NUM; r++) {
        res.regs[r] = get_w(dr, r * 16, 16);
        uint16_t exp = (t.fina.mask & (1 << r)) ? t.fina.regs[r] : t.init.regs[r];
        if (res.regs[r] != exp) {
            res.reg_ok = false;
            char b[96];
            snprintf(b, sizeof b, "reg %s exp %04X got %04X", moo::reg_name[r], exp, res.regs[r]);
            res.notes.push_back(b);
        }
    }
    // memory: every final entry, and no other byte changed
    for (auto &m : fina_ram) {
        if (mem[m.first] != m.second) {
            res.mem_ok = false;
            char b[96];
            snprintf(b, sizeof b, "mem %05X exp %02X got %02X", m.first, m.second, mem[m.first]);
            res.notes.push_back(b);
        }
    }
    for (uint32_t a : writes) {
        if (fina_ram.count(a)) continue;
        auto it = init_ram.find(a);
        if (it == init_ram.end() || it->second != mem[a]) {
            res.mem_ok = false;
            char b[96];
            snprintf(b, sizeof b, "mem %05X unexpected write %02X", a, mem[a]);
            res.notes.push_back(b);
        }
    }
    if (res.got.size() != t.cycles.size()) {
        res.cyc_ok = false;
        char b[96];
        snprintf(b, sizeof b, "cycles exp %zu got %zu", t.cycles.size(), res.got.size());
        res.notes.push_back(b);
    }
    size_t n = res.got.size() < t.cycles.size() ? res.got.size() : t.cycles.size();
    int last_t4 = -1000;
    uint32_t admask = 0xFFFFF;          // BUS16: inactive half of a single-lane write, from its T2 to the next T1
    for (size_t i = 0; i < n; i++) {
        const moo::Cycle &e = t.cycles[i], &g = res.got[i];
        if (e.ts == 4) last_t4 = (int)i;
#ifdef BUS16
        if (e.pins & 1) {
            static uint32_t wl;
            wl = e.addr;
            admask = 0xFFFFF;
            if (e.bus == 4 || e.bus == 2) {     // MEMW / IOW: lanes from A0 and BHE
                int ln = ((wl & 1) ? 0 : 1) | (e.bhe ? 0 : 2);
                if (ln == 1) admask = 0xF00FF;
                if (ln == 2) admask = 0xFFF00;
            }
        }
        uint32_t am = (e.ts == 1 && (e.pins & 1)) ? 0xFFFFF : admask;
#else
        const uint32_t am = 0xFFFFF;
#endif
        // AD7-AD0 float while idle; after >= 128 idle clocks the rig sees floating lines drift 0 -> 1
        if (((e.addr ^ g.addr) & ~am & 0xFFFFF) != 0) res.lane++;
        uint32_t ea = e.addr & am, x = ea ^ (g.addr & am);
        if (x && e.ts == 0 && g.ts == 0 && (int)i - last_t4 >= 128 && (x & 0xFFF00) == 0 && (x & ea) == x) {
            res.drift++;
            ea = g.addr & am;
        }
        if (e.pins != g.pins || ea != (g.addr & am) || e.seg != g.seg || e.mem != g.mem || e.io != g.io ||
            e.bhe != g.bhe || e.data != g.data || e.bus != g.bus || e.ts != g.ts || e.qop != g.qop || e.qbyte != g.qbyte) {
            res.bus_ok = false;
            char b[96];
            snprintf(b, sizeof b, "bus first mismatch at cycle %zu", i);
            res.notes.push_back(b);
            break;
        }
    }
    if (!res.cyc_ok && n < t.cycles.size()) res.bus_ok = false;
    if (!res.cyc_ok && n < res.got.size()) res.bus_ok = false;
    return res;
}

static std::string events(const std::vector<moo::Cycle> &cy) {
    static const char bc[] = "iIOrwhC.";
    std::string s;
    char b[16];
    uint32_t prev = cy.empty() ? 0 : cy[0].addr;
    for (size_t c = 0; c < cy.size(); c++) {
        const moo::Cycle &y = cy[c];
        int n = (int)c - 1;
        if (y.qop == 1) { snprintf(b, sizeof b, " F%d", n); s += b; }
        if (y.qop == 3) { snprintf(b, sizeof b, " S%d", n); s += b; }
        if (y.qop == 2) { snprintf(b, sizeof b, " E%d", n); s += b; }
        if (y.ts == 1) { snprintf(b, sizeof b, " %c%zu", bc[y.bus & 7], c); s += b; }
        if (y.ts == 0 && c > 0 && y.addr != prev) { snprintf(b, sizeof b, " a%zu", c); s += b; }
        prev = y.addr;
    }
    snprintf(b, sizeof b, " |%zu", cy.size());
    return s + b;
}

// compact trace from clock -1: bus (. Ti, a new address in Ti, T1 by type C R W I O A H, 2 3 4) and queue pops (- F S E)
static std::string line(const std::vector<moo::Cycle> &cy) {
    static const char t1c[] = "AIORWHC.", qc[] = "-FES";
    std::string bs = "_", qs(1, cy.empty() ? '-' : qc[cy[0].qop & 3]);
    uint32_t prev = cy.empty() ? 0 : cy[0].addr;
    for (size_t c = 0; c < cy.size(); c++) {
        const moo::Cycle &y = cy[c];
        char ch = '.';
        if (y.ts == 1) ch = t1c[y.bus & 7];
        else if (y.ts >= 2 && y.ts <= 4) ch = '0' + y.ts;
        else if (c > 0 && y.addr != prev) ch = 'a';
        prev = y.addr;
        bs += ch;
        qs += (c + 1 < cy.size()) ? qc[cy[c + 1].qop & 3] : 'F';
    }
    return bs + " " + qs;
}

static void dump(const moo::Test &t, const Result &r) {
    printf("#%u %s  bytes:", t.index, t.name.c_str());
    for (auto b : t.bytes) printf(" %02X", b);
    printf("  queue:%zu\n", t.init.queue.size());
    for (auto &s : r.notes) printf("  %s\n", s.c_str());
    size_t n = r.got.size() > t.cycles.size() ? r.got.size() : t.cycles.size();
    printf("       %-44s %s\n", "expected", "x86sv");
    for (size_t i = 0; i < n; i++) {
#ifdef BUS16
        std::string e = i < t.cycles.size() ? moo::fmtw(t.cycles[i]) : "";
        std::string g = i < r.got.size() ? moo::fmtw(r.got[i]) : "";
#else
        std::string e = i < t.cycles.size() ? moo::fmt(t.cycles[i]) : "";
        std::string g = i < r.got.size() ? moo::fmt(r.got[i]) : "";
#endif
        printf("  %3zu%c %-44s %s\n", i, e == g ? ' ' : '*', e.c_str(), g.c_str());
    }
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    size_t nmax = (size_t)-1;
    long only = -1;
    bool stop = false, quiet = false, list = false, lines = false;
    int evk = 0;
    std::vector<std::string> files;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "-n" && i + 1 < argc) nmax = strtoul(argv[++i], 0, 0);
        else if (a == "-i" && i + 1 < argc) only = strtol(argv[++i], 0, 0);
        else if (a == "-s") stop = true;
        else if (a == "-q") quiet = true;
        else if (a == "-l") list = true;
        else if (a == "-L") list = lines = true;
        else if (a == "-e" && i + 1 < argc) evk = atoi(argv[++i]);
        else if (a[0] != '+') files.push_back(a);
    }
    top = new Vtb_x86;
    top->clk = 0; top->eval();
    printf("%-14s %6s %6s %6s %6s %6s %6s %6s %6s\n", "file", "tests", "pass", "reg", "mem", "cycles", "bus", "drift",
           "lane");
    long tot[8] = {};
    for (auto &fn : files) {
        moo::File f = moo::load(fn);
        std::string base = fn.substr(fn.find_last_of('/') + 1);
        if (base.size() > 7 && base.substr(base.size() - 7) == ".MOO.gz") base = base.substr(0, base.size() - 7);
        if (!f.error.empty()) { printf("%-14s ERROR %s\n", base.c_str(), f.error.c_str()); continue; }
        long cnt[8] = {};
        int shown = 0;
        bool stopped = false;
        for (size_t i = 0; i < f.tests.size() && i < nmax; i++) {
            if (only >= 0 && (long)i != only) continue;
            const moo::Test &t = f.tests[i];
            Result r = run(t);
            cnt[0]++;
            if (r.pass()) cnt[1]++;
            if (!r.reg_ok) cnt[2]++;
            if (!r.mem_ok) cnt[3]++;
            if (!r.cyc_ok) cnt[4]++;
            if (!r.bus_ok) cnt[5]++;
            if (r.drift) cnt[6]++;
            if (r.lane) cnt[7]++;
            if (list)
                printf("L %u %c %c%c%c%c %zu %zu %s\n", t.index, t.init.queue.empty() ? 'n' : 'p', r.reg_ok ? '.' : 'R',
                       r.mem_ok ? '.' : 'M', r.cyc_ok ? '.' : 'C', r.bus_ok ? '.' : 'B', t.cycles.size(), r.got.size(),
                       t.name.c_str());
            if (lines && !r.pass()) printf("E %s\nG %s\n", line(t.cycles).c_str(), line(r.got).c_str());
            if (!r.pass()) {
                if (shown < evk) {
                    shown++;
                    printf("#%-5u %c %-34s exp%s\n", t.index, t.init.queue.empty() ? 'n' : 'p', t.name.c_str(),
                           events(t.cycles).c_str());
                    printf("       %-36s got%s", "", events(r.got).c_str());
                    for (auto &s : r.notes) if (s.compare(0, 3, "bus") && s.compare(0, 6, "cycles")) printf("  [%s]", s.c_str());
                    printf("\n");
                }
                if (stop || only >= 0) { dump(t, r); stopped = stop; }
            }
            if (stopped) break;
        }
        printf("%-14s %6ld %6ld %6ld %6ld %6ld %6ld %6ld %6ld\n", base.c_str(), cnt[0], cnt[1], cnt[2], cnt[3], cnt[4],
               cnt[5], cnt[6], cnt[7]);
        fflush(stdout);
        for (int k = 0; k < 8; k++) tot[k] += cnt[k];
        if (stopped) break;
    }
    if (files.size() > 1)
        printf("%-14s %6ld %6ld %6ld %6ld %6ld %6ld %6ld %6ld\n", "TOTAL", tot[0], tot[1], tot[2], tot[3], tot[4], tot[5],
               tot[6], tot[7]);
    (void)quiet;
    delete top;
    return 0;
}

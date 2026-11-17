// Copyright (C) 2026 Rodimus
// m68ksv harness: runs Tom Harte / SingleStepTests 680x0 (68000) tests converted by tools/conv_harte.py.
//   harte [-v N] [-t idx] [-gap N] [-bus8] <file.bin> ...    (-gap: random 0..N idle clocks between phase enables;
//   -bus8: the model is an 8-bit configuration (68008, 68EC000 with MODE = 0): memory on D7-D0 with A0 / DS_n; the
//   bus order is compared with each word access of the suite split into two byte cycles, the cycle count against the
//   suite's + 4 per word access)
// Per test: reset, load registers / prefetch queue / RAM through the test-load port, run to the next instruction
// boundary, compare registers + SR + PC + prefetch queue and every final RAM byte (checkpoint 1 pass criterion).
// Cycle count and bus-transaction order are measured and reported, not part of the pass criterion (checkpoint 2).
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>

struct State { uint32_t r[19]; uint16_t pf[2]; std::vector<std::pair<uint32_t, uint8_t>> ram; };
struct Tr { char t; uint32_t len, fc, addr, sz, val; };
struct Test { std::string name; State in, out; uint32_t length; std::vector<Tr> tr; };

static bool rd(FILE *f, void *p, size_t n) { return fread(p, 1, n, f) == n; }
static bool rdstate(FILE *f, State &s) {
    if (!rd(f, s.r, 76) || !rd(f, s.pf, 4)) return false;
    uint32_t n; if (!rd(f, &n, 4) || n > 100000) return false;
    s.ram.resize(n);
    for (auto &e : s.ram) { uint8_t b[5]; if (!rd(f, b, 5)) return false; memcpy(&e.first, b, 4); e.second = b[4]; }
    return true;
}
static bool load(const char *fn, std::vector<Test> &v) {
    FILE *f = fopen(fn, "rb"); if (!f) return false;
    char m[4]; uint32_t n;
    if (!rd(f, m, 4) || memcmp(m, "M68T", 4) || !rd(f, &n, 4) || n > 1000000) { fclose(f); return false; }
    v.resize(n);
    for (auto &t : v) {
        uint16_t nl; if (!rd(f, &nl, 2)) return false;
        t.name.resize(nl); if (!rd(f, &t.name[0], nl)) return false;
        if (!rdstate(f, t.in) || !rdstate(f, t.out)) return false;
        uint32_t nt; if (!rd(f, &t.length, 4) || !rd(f, &nt, 4) || nt > 10000) return false;
        t.tr.resize(nt);
        for (auto &x : t.tr) {
            uint8_t b[15]; if (!rd(f, b, 15)) return false;
            x.t = b[0]; memcpy(&x.len, b + 1, 4); x.fc = b[5]; memcpy(&x.addr, b + 6, 4); x.sz = b[10]; memcpy(&x.val, b + 11, 4);
        }
    }
    fclose(f); return true;
}

static uint8_t *mem;
static uint8_t *wmark;
static std::vector<uint32_t> touched;
static Vm68ksv *top;
static uint64_t phase_ctr;

static bool fin_pre;
static bool bus8 = false;
static bool bus32 = false;
static unsigned long cls20[6];  // 68020 build: failing tests by class (see the comparison)
static int cls_shown = 0;      // 68020 / 68EC020 build: the memory is one 32-bit port (DSACK1 / DSACK0 low, no waits)
static uint32_t amask = 0xffffff;     // -abits N: address pins of the configuration (68008 20, 68008FN 22): memory aliases
static uint64_t aliased = 0;          // tests skipped because two of their addresses alias under amask
static uint32_t baddr() { if (bus32) return top->A32 & 0xffffff; return bus8 ? ((((uint32_t)top->A << 1) | top->A0) & 0xffffff) : (((uint32_t)top->A << 1) & 0xfffffe); }
static int upc_tl;             // UA_TLFIN, learned from the first test start
static int gap = 0;            // -gap N: 0..N idle clocks (no enable) before each phase enable, pseudo-random
static uint32_t lfsr = 1;
static void tick() {
    // one system clock with a phase enable; cen_p / cen_n alternate (system clock = 2 x CPU clock without -gap)
    if (gap) {
        lfsr = lfsr * 1103515245u + 12345u;
        for (int g = (lfsr >> 16) % (gap + 1); g > 0; g--) {
            top->cen_p = 0; top->cen_n = 0;
            top->clk = 0; top->eval(); top->clk = 1; top->eval();
        }
    }
    top->cen_p = (phase_ctr & 1) == 0;
    top->cen_n = (phase_ctr & 1) == 1;
    top->clk = 0; top->eval();
    fin_pre = top->dbg_fin;
    top->clk = 1; top->eval();
    phase_ctr++;
    if (bus32) {        // 68020 build: two clk or more between CPU edges (cp4b one-clock micro-cycle)
        top->cen_p = 0; top->cen_n = 0;
        top->clk = 0; top->eval(); top->clk = 1; top->eval();
    }
}

// read a register-file entry through the debug read port without advancing the CPU (no clock enables)
static uint32_t rreg(int k) {
    top->dbg_ra = k;
    top->cen_p = 0; top->cen_n = 0;
    top->clk = 0; top->eval(); top->clk = 1; top->eval();
    return top->dbg_rd;
}

// corrections (suite_corrections, made by fxprobe -mame -emit): tests whose suite expectation is shown wrong by fx68k
// with MAME as tie-breaker; such a test is compared with the corrected expectation and counted in its own columns
struct Corr { std::string why; uint32_t r[19]; uint16_t pf[2]; std::vector<std::pair<uint32_t, uint8_t>> ram; std::string timed; };
static std::map<std::string, std::map<int, Corr>> corr;
static void load_corr(const char *fn, const std::vector<const char *> &files) {
    std::map<std::string, int> want;
    for (const char *f : files) { std::string b = f; b = b.substr(b.rfind('/') + 1); b = b.substr(0, b.rfind('.')); want[b] = 1; }
    FILE *f = fopen(fn, "r");
    if (!f) { printf("cannot open %s\n", fn); exit(1); }
    static char line[1 << 16];
    while (fgets(line, sizeof line, f)) {
        char name[64], why[96]; int idx, n = 0;
        if (sscanf(line, "%63s %d %95s%n", name, &idx, why, &n) != 3 || !want.count(name)) continue;
        Corr c; c.why = why;
        char *p = line + n;
        for (int k = 0; k < 19; k++) c.r[k] = strtoul(p, &p, 16);
        c.pf[0] = strtoul(p, &p, 16); c.pf[1] = strtoul(p, &p, 16);
        int nr = strtoul(p, &p, 10);
        for (int k = 0; k < nr; k++) { uint32_t a = strtoul(p, &p, 16); p++; uint8_t v = strtoul(p, &p, 16); c.ram.push_back({a, v}); }
        char *bar = strchr(p, '|');
        if (bar) { c.timed = bar + 2; while (!c.timed.empty() && (c.timed.back() == '\n')) c.timed.pop_back(); }
        corr[name][idx] = c;
    }
    fclose(f);
}

static const char *RN[19] = {"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","usp","ssp","sr","pc"};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int verbose = 0, only = -1, trace = 0, tmdump = 0;
    const char *corr_file = nullptr;
    std::map<std::string, std::map<int, int>> excl;     // file -> index -> corrected SR (-1: none)
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-v") && i + 1 < argc) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) only = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-tr") && i + 1 < argc) trace = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-gap") && i + 1 < argc) gap = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-tm") && i + 1 < argc) tmdump = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-c") && i + 1 < argc) corr_file = argv[++i];
        else if (!strcmp(argv[i], "-bus8")) bus8 = true;
        else if (!strcmp(argv[i], "-bus32")) bus32 = true;
        else if (!strcmp(argv[i], "-abits") && i + 1 < argc) amask = (1u << atoi(argv[++i])) - 1;
        else if (!strcmp(argv[i], "-x") && i + 1 < argc) {
            FILE *xf = fopen(argv[++i], "r");
            char fn[64], sr[16], why[96]; int ix;
            while (xf && fscanf(xf, "%63s %d %15s %95s", fn, &ix, sr, why) == 4)
                excl[fn][ix] = strcmp(sr, "-") ? (int)strtol(sr, nullptr, 16) : -1;
            if (xf) fclose(xf);
        }
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    if (corr_file) load_corr(corr_file, files);
    mem = (uint8_t *)calloc(1 << 24, 1);
    wmark = (uint8_t *)calloc(1 << 24, 1);
    top = new Vm68ksv;
    top->DTACK_n = 0; top->BERR_n = 1; top->VPA_n = 1; top->IPL_n = 7; top->BR_n = 1; top->BGACK_n = 1;
    top->HALT_n_i = 1; top->RESET_n_i = 1; top->MODE = !bus8;
    top->DSACK_n = 0; top->STERM_n = 1; top->AVEC_n = 1; top->CDIS_n = 1;
    printf("# file tests pass regfail ramfail pffail timeout cyc_ok bus_ok excluded excl_corrected_ok timed_ok corrected corr_pass corr_timed\n");
    uint64_t T[14] = {0};
    for (const char *fn : files) {
        std::vector<Test> tests;
        if (!load(fn, tests)) { printf("cannot load %s\n", fn); continue; }
        uint64_t c[14] = {0};
        int shown = 0, tmshown = 0;
        std::string base = fn; base = base.substr(base.rfind('/') + 1); base = base.substr(0, base.rfind('.'));
        std::map<int, int> &xs = excl[base];
        std::map<int, Corr> &cs = corr[base];
        for (size_t ti = 0; ti < tests.size(); ti++) {
            if (only >= 0 && (int)ti != only) continue;
            Test t = tests[ti];
            const Corr *cr = cs.count((int)ti) ? &cs[(int)ti] : nullptr;
            if (cr) { for (int k = 0; k < 19; k++) t.out.r[k] = cr->r[k]; t.out.pf[0] = cr->pf[0]; t.out.pf[1] = cr->pf[1]; t.out.ram = cr->ram; }
            for (uint32_t a : touched) { mem[a] = 0; wmark[a] = 0; }
            touched.clear();
            if (amask != 0xffffff) {
                std::map<uint32_t, uint32_t> seen; bool al = false;
                for (auto *v : {&t.in.ram, &t.out.ram}) for (auto &e : *v) {
                    auto it = seen.find(e.first & amask);
                    if (it != seen.end() && it->second != e.first) al = true; else seen[e.first & amask] = e.first;
                }
                if (al) { aliased++; continue; }
            }
            for (auto &e : t.in.ram) { mem[e.first & amask] = e.second; touched.push_back(e.first & amask); }
            // reset + test load
            top->RESET_n_i = 0; top->HALT_n_i = 0; top->tl_en = 1;
            for (int i = 0; i < 15; i++) top->tl_r[i] = t.in.r[i];
            top->tl_usp = t.in.r[15]; top->tl_ssp = t.in.r[16]; top->tl_sr = t.in.r[17]; top->tl_pc = t.in.r[18];
            top->tl_ir = t.in.pf[0]; top->tl_irc = t.in.pf[1];
            for (int i = 0; i < 6; i++) tick();
            top->RESET_n_i = 1; top->HALT_n_i = 1;
            for (int i = 0; i < 14; i++) tick();     // test load writes one register-file entry per clock
            if (phase_ctr & 1) tick();
            top->tl_en = 0;
            upc_tl = top->dbg_upc;
            // run
            std::vector<Tr> got;
            bool in_cyc = false, wseen = false, rseen = false; uint32_t cyc_addr = 0, cyc_fc = 0, strobes = 0, rdata = 0, wdata = 0; int cyc_start = 0;
            int clocks = 0, fin = 0, timeout = 1;
            // timed transactions: tick index of the instruction's first e0 (t0), of each AS fall (S2) and rise (S7)
            int64_t t0 = -1, as_fall = 0, tend = 0;
            struct TC { char t; int64_t s, e; uint32_t fc, addr, sz; };
            std::vector<TC> tgot;
            int prev_upc = upc_tl;
            for (int k = 0; k < 20000; k++) {
                // memory: drive read data combinationally from the current address
                uint32_t a = baddr();
                top->D_i = bus8 ? mem[a] : ((mem[a] << 8) | mem[a + 1]);
                if (bus32) { uint32_t al = a & ~3u; top->D32_i = ((uint32_t)mem[al] << 24) | (mem[al + 1] << 16) | (mem[al + 2] << 8) | mem[al + 3]; }
                tick();
                if (!(phase_ctr & 1)) clocks++;
                if (t0 < 0 && prev_upc == upc_tl && top->dbg_upc != upc_tl) t0 = phase_ctr - 1;
                prev_upc = top->dbg_upc;
                a = baddr();
                if (!top->AS_n) {
                    if (!in_cyc) { in_cyc = true; cyc_addr = a; cyc_fc = top->FC; strobes = 0; wseen = false; rseen = false; cyc_start = clocks; as_fall = phase_ctr - 1; }
                    uint32_t s = bus32 ? (top->DS_n ? 0 : 3) : bus8 ? (top->DS_n ? 0 : ((a & 1) ? 1 : 2)) : ((top->UDS_n ? 0 : 2) | (top->LDS_n ? 0 : 1));
                    if (bus32 && s && !top->RW) {     // 68020 write: the SIZ bytes from A1 / A0 up to the long boundary
                        int nb = top->SIZ ? top->SIZ : 4, o = a & 3, k = nb < 4 - o ? nb : 4 - o;
                        for (int j = 0; j < k; j++) { uint32_t b = (a + j) & 0xffffff; mem[b] = top->D32_o >> (24 - 8 * (o + j));
                                                      if (!wmark[b]) { wmark[b] = 1; touched.push_back(b); } }
                        wseen = true; s = 0;
                    }
                    if (bus32 && s) s = 0, rseen = true;
                    if (bus8) cyc_addr = a & ~1u;
                    strobes |= s;
                    if (s && top->RW) { rdata = bus8 ? ((mem[a] << 8) | mem[a]) : ((mem[a] << 8) | mem[a + 1]); rseen = true; }
                    if (bus8 && s && !top->RW) {
                        wseen = true; wdata = (top->D_o & 0xff) * 0x101;
                        mem[a] = top->D_o & 0xff; if (!wmark[a]) { wmark[a] = 1; touched.push_back(a); }
                    } else if (s && !top->RW) {
                        wseen = true; wdata = top->D_o;
                        if (s & 2) { mem[a] = top->D_o >> 8; if (!wmark[a]) { wmark[a] = 1; touched.push_back(a); } }
                        if (s & 1) { mem[a + 1] = top->D_o & 0xff; if (!wmark[a + 1]) { wmark[a + 1] = 1; touched.push_back(a + 1); } }
                    }
                } else if (in_cyc) {
                    in_cyc = false;
                    Tr x; x.t = (wseen && rseen) ? 't' : wseen ? 'w' : 'r'; x.fc = cyc_fc; x.sz = strobes == 3; x.len = clocks - cyc_start;
                    x.addr = cyc_addr | ((strobes == 1) ? 1 : 0);
                    uint32_t d = wseen ? wdata : rdata;
                    x.val = (strobes == 3) ? d : (strobes == 2 ? d >> 8 : d & 0xff);
                    if (strobes) got.push_back(x);       // AS without data strobes = cycle aborted by an address error
                    if (strobes) tgot.push_back(TC{x.t, as_fall - 2, phase_ctr - 1 + 1, x.fc, x.addr, x.sz});
                }
                if (trace && (phase_ctr & 1) == 0) printf("   clk %4d upc %3d AS %d A %06x RW %d FC %d UDS %d LDS %d D_o %04x\n", clocks, top->dbg_upc,
                    top->AS_n, a, top->RW, top->FC, top->UDS_n, top->LDS_n, top->D_o);
                if (fin_pre) { fin++; timeout = 0; tend = phase_ctr - 1; break; }
                if (trace && clocks > trace) break;
            }
            // compare
            uint32_t g[19];
            for (int i = 0; i < 17; i++) g[i] = rreg(i);
            g[17] = top->dbg_sr; g[18] = top->dbg_pc;
            bool regbad = false, rambad = false, pfbad = false;
            for (int i = 0; i < 19; i++) if (g[i] != t.out.r[i]) regbad = true;
            if (top->dbg_ir != t.out.pf[0] || top->dbg_irc != t.out.pf[1]) pfbad = true;
            for (auto &e : t.out.ram) if (mem[e.first & amask] != e.second) rambad = true;
            // bus order (ignoring idle) and cycle count (checkpoint 2 data)
            std::vector<Tr> exp;
            int words = 0;
            for (auto &x : t.tr) if (x.t != 'n') { exp.push_back(x); words += x.sz; }
            if (bus8) {
                // 8-bit bus: each expected word access becomes two byte cycles at a / a + 1
                std::vector<Tr> e8;
                for (auto &x : exp) {
                    Tr y = x; y.sz = 0;
                    if (x.sz) { y.addr = x.addr & ~1u; e8.push_back(y); y.addr |= 1; e8.push_back(y); } else e8.push_back(y);
                }
                exp = e8;
                for (auto &x : got) x.sz = 0;
            }
            bool busok = exp.size() == got.size();
            for (size_t i = 0; busok && i < exp.size(); i++) {
                char et = exp[i].t;
                if (et != got[i].t || (exp[i].addr & amask) != got[i].addr || exp[i].fc != got[i].fc || exp[i].sz != got[i].sz) busok = false;
            }
            clocks -= 1;   // the test-start micro-cycle (TLFIN dispatch) is not part of the instruction (half of it runs
                           // inside the load window: the phase counter restarts at e2 after reset)
            bool cycok = (uint32_t)clocks == t.length + (bus8 ? 4 * words : 0);
            if (getenv("CYCDBG")) printf("CYC %s #%zu clocks %d exp %u\n", base.c_str(), ti, clocks, t.length);
            // timed transaction list (suite form: idle runs merged into one 'n', bus cycles with their lengths)
            std::string texp, tgs;
            {
                char buf[64]; uint32_t idle = 0;
                for (auto &x : t.tr) {
                    if (x.t == 'n') { idle += x.len; continue; }
                    if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); texp += buf; idle = 0; }
                    snprintf(buf, sizeof buf, "%c%u:%u@%x%s ", x.t, x.len, x.fc, x.addr, x.sz ? "w" : "b"); texp += buf;
                }
                if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); texp += buf; }
                int64_t at = t0;
                for (auto &x : tgot) {
                    if (x.s > at) { snprintf(buf, sizeof buf, "n%ld ", (long)((x.s - at) / 2)); tgs += buf; }
                    snprintf(buf, sizeof buf, "%c%ld:%u@%x%s ", x.t, (long)((x.e - x.s) / 2), x.fc, x.addr, x.sz ? "w" : "b"); tgs += buf;
                    at = x.e;
                }
                if (tend > at) { snprintf(buf, sizeof buf, "n%ld ", (long)((tend - at) / 2)); tgs += buf; }
            }
            if (cr) texp = cr->timed;
            bool timok = !timeout && t0 >= 0 && texp == tgs;
            if (!timok && tmshown < tmdump) {
                tmshown++;
                printf("TM %s #%zu [%s]%s | %s| %s\n", base.c_str(), ti, t.name.c_str(), cr ? " C" : "", texp.c_str(), tgs.c_str());
            }
            bool pass = !regbad && !rambad && !pfbad && !timeout;
            if (xs.count((int)ti)) {
                // excluded (suite disagrees with the tie-breaker): compare against the corrected SR when one is given
                bool ok = false;
                if (xs[(int)ti] >= 0 && !rambad && !pfbad && !timeout) {
                    ok = (g[17] == (uint32_t)xs[(int)ti]);
                    for (int i = 0; i < 19; i++) if (i != 17 && g[i] != t.out.r[i]) ok = false;
                }
                c[8]++; c[9] += ok; c[6] += cycok; c[7] += busok; c[10] += timok;
                continue;
            }
            if (cr && getenv("AEX") && cr->why.compare(0, 13, "address_error") == 0) {
                // address-error analysis: frame words vs the corrected expectation, by faulting micro-address
                uint32_t sp = t.out.r[16] & 0xffffff;
                auto m8 = [&](uint32_t a) { return (uint32_t)mem[a & 0xffffff]; };
                auto e8 = [&](uint32_t a) { for (auto &e : t.out.ram) if ((e.first & 0xffffff) == (a & 0xffffff)) return (uint32_t)e.second; return 0xffffffffu; };
                auto w16 = [&](auto f, uint32_t a) { return (f(a) << 8) | f(a + 1); };
                uint32_t gpc = (w16(m8, sp + 10) << 16) | w16(m8, sp + 12), epc = (w16(e8, sp + 10) << 16) | w16(e8, sp + 12);
                uint32_t gaw = w16(m8, sp), eaw = w16(e8, sp);
                uint32_t gfa = (w16(m8, sp + 2) << 16) | w16(m8, sp + 4), efa = (w16(e8, sp + 2) << 16) | w16(e8, sp + 4);
                std::string rd;
                for (int i = 0; i < 16; i++) if (g[i] != t.out.r[i]) { char b[48]; snprintf(b, sizeof b, " %s%+d", RN[i], (int)(g[i] - t.out.r[i])); rd += b; }
                printf("AEX %s %zu %s upc %d pc %+d %+d aw %04x fa %+d sr %d%s | %s\n", base.c_str(), ti, cr->why.c_str(), top->tl_aeupc,
                       (int)(epc - top->tl_aefpc), (int)(gpc - top->tl_aefpc), gaw ^ eaw, (int)(gfa - efa), g[17] != t.out.r[17], rd.c_str(), t.name.c_str());
            }
            if (bus32 && !pass) {
                // 68020 build: why a 68000 test fails (first matching class): 0 the 68000 took an address error (the
                // 68020 has none for data / odd stack accesses), 1 another exception (020 frame formats, T0, stacked
                // PC), 2 an SR write (M / T0 bits exist on the 68020), 3 an indexed mode whose extension word has bits
                // 10-8 set (scale / full format on the 68020), 5 (2026-11-16) DIVU / DIVS / CHK where only the CCR differs
                // (the 68020's undefined flags as WinUAE's 68020 core: REPORT.md "68020 behaviour from WinUAE"), 4 other
                auto ib = [&](uint32_t a) { for (auto &e : t.in.ram) if ((e.first & 0xffffff) == (a & 0xffffff)) return (uint32_t)e.second; return 0u; };
                uint16_t op = t.in.pf[0];
                int k = 4;
                bool ae = false, exv = false;
                for (auto &x : t.tr) if (x.t == 'r' && x.fc == 5 && x.addr < 0x400) { if ((x.addr & ~3u) == 0x0c) ae = true; else exv = true; }
                bool srw = op == 0x007c || op == 0x027c || op == 0x0a7c || (op & 0xffc0) == 0x46c0 || op == 0x4e72 || op == 0x4e73;
                bool idx = ((op >> 3) & 7) == 6 || (op & 0x3f) == 0x3b;
                if ((op & 0xc000) == 0 && (op & 0x3000) && ((op >> 6) & 7) == 6) idx = true;   // MOVE destination
                bool xb = false;
                if (idx) {
                    uint32_t pc = t.in.r[18];
                    uint16_t w[4] = {t.in.pf[1], (uint16_t)((ib(pc) << 8) | ib(pc + 1)), (uint16_t)((ib(pc + 2) << 8) | ib(pc + 3)),
                                     (uint16_t)((ib(pc + 4) << 8) | ib(pc + 5))};
                    for (int j = 0; j < 4; j++) if (w[j] & 0x0700) xb = true;
                }
                bool ccr_only = !rambad && !pfbad && ((g[17] ^ t.out.r[17]) & 0xffe0) == 0;
                for (int i = 0; i < 19; i++) if (i != 17 && g[i] != t.out.r[i]) ccr_only = false;
                bool wflag = ccr_only && ((op & 0xf0c0) == 0x80c0 || (op & 0xf1c0) == 0x4180);   // DIVU / DIVS, CHK.W
                if (ae) k = 0; else if (exv) k = 1; else if (srw) k = 2; else if (xb) k = 3; else if (wflag) k = 5;
                cls20[k]++;
                if (k == 4 && cls_shown < verbose) {
                    cls_shown++;
                    printf("OTHER %s #%zu %s%s%s\n", t.name.c_str(), ti, regbad ? "reg " : "", rambad ? "ram " : "", pfbad ? "pf" : "");
                    for (int i = 0; i < 19; i++) if (g[i] != t.out.r[i]) printf("   %-3s got %08x exp %08x init %08x\n", RN[i], g[i], t.out.r[i], t.in.r[i]);
                    printf("   pf  got %04x %04x exp %04x %04x\n", top->dbg_ir, top->dbg_irc, t.out.pf[0], t.out.pf[1]);
                    for (auto &e : t.out.ram) if (mem[e.first] != e.second) printf("   ram %06x got %02x exp %02x\n", e.first, mem[e.first], e.second);
                }
            }
            if (cr) {
                c[11]++; c[12] += pass; c[13] += timok;
                if (!pass && shown < verbose) {
                    shown++;
                    printf("FAIL(corrected %s) %s #%zu\n", cr->why.c_str(), t.name.c_str(), ti);
                    for (int i = 0; i < 19; i++) if (g[i] != t.out.r[i] || i >= 17) printf("   %-3s got %08x exp %08x init %08x\n", RN[i], g[i], t.out.r[i], t.in.r[i]);
                    printf("   pf  got %04x %04x exp %04x %04x\n", top->dbg_ir, top->dbg_irc, t.out.pf[0], t.out.pf[1]);
                    for (auto &e : t.out.ram) if (mem[e.first] != e.second) printf("   ram %06x got %02x exp %02x\n", e.first, mem[e.first], e.second);
                }
                continue;
            }
            c[0]++; c[1] += pass; c[2] += regbad; c[3] += rambad; c[4] += pfbad; c[5] += timeout; c[6] += cycok; c[7] += busok; c[10] += timok;
            if (!pass && shown < verbose) {
                shown++;
                printf("FAIL %s #%zu %s%s%s%s clocks %d (exp %u)\n", t.name.c_str(), ti, regbad ? "reg " : "", rambad ? "ram " : "",
                       pfbad ? "pf " : "", timeout ? "timeout" : "", clocks, t.length);
                for (int i = 0; i < 19; i++)
                    if (g[i] != t.out.r[i] || i >= 17) printf("   %-3s got %08x exp %08x init %08x\n", RN[i], g[i], t.out.r[i], t.in.r[i]);
                printf("   pf  got %04x %04x exp %04x %04x\n", top->dbg_ir, top->dbg_irc, t.out.pf[0], t.out.pf[1]);
                for (auto &e : t.out.ram) if (mem[e.first] != e.second) printf("   ram %06x got %02x exp %02x\n", e.first, mem[e.first], e.second);
                printf("   bus exp:"); for (auto &x : exp) printf(" %c%u@%06x%s=%x", x.t, x.fc, x.addr, x.sz ? "w" : "b", x.val); printf("\n");
                printf("   bus got:"); for (auto &x : got) printf(" %c%u@%06x%s=%x", x.t, x.fc, x.addr, x.sz ? "w" : "b", x.val); printf("\n");
            }
        }
        const char *b = strrchr(fn, '/'); b = b ? b + 1 : fn;
        if (bus32) { printf("CLS %s %lu %lu %lu %lu %lu %lu\n", b, cls20[0], cls20[1], cls20[2], cls20[3], cls20[4], cls20[5]); for (auto &x : cls20) x = 0; }
        printf("%-16s %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu\n", b, c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12], c[13]);
        fflush(stdout);
        for (int i = 0; i < 14; i++) T[i] += c[i];
    }
    if (amask != 0xffffff) printf("# aliased tests skipped (two addresses alias on the configuration's address pins): %lu\n", (unsigned long)aliased);
    if (files.size() > 1)
        printf("%-16s %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu\n", "TOTAL", T[0], T[1], T[2], T[3], T[4], T[5], T[6], T[7], T[8], T[9], T[10], T[11], T[12], T[13]);
    delete top;
    return 0;
}

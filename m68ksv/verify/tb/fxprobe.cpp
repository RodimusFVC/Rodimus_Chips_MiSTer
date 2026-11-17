// Copyright (C) 2026 Rodimus
// fxprobe: runs Tom Harte / SingleStepTests 68000 tests (converted by tools/conv_harte.py) on fx68k (Jorge Cwik's
// microcode-derived 68000, the reference for checkpoint 2) and compares its result with the suite.
//   fxprobe [-n N] [-t idx]... [-x exclusions] [-v K] <file.bin> ...
//     -n N   every (size / N)-th test of each file (N tests per file; default all)
//     -t idx only these test indices (repeatable)
//     -x f   suite_exclusions.txt: excluded tests are run and reported separately (fx68k vs suite vs corrected SR)
//     -v K   print details of the first K mismatches per file
// fx68k has no test-load port, so each test is set up by a program: reset vectors (SSP 800, PC F000), at F000 MOVEA
// #usp / MOVE USP, MOVE.L #d0-d7, MOVEA.L #a0-a6 / #ssp, MOVE #sr,SR, JMP (test PC); the test's initial RAM and prefetch
// words are in memory. Two NOPs are placed at the test's final PC; the state is read from fx68k's own registers
// (Verilator --public-flat-rw) when the first NOP prefetches final PC + 4, i.e. after the test instruction (and any
// exception it raises) has completed. Compared: D0-D7, A0-A6, USP, SSP, SR, the final PC (reached or not), every
// final RAM byte, and the bus-cycle order (type, FC, address, size) between the JMP's target fetch and that prefetch.
// Not compared: the prefetch queue (the NOPs replace the next opcode words) and cycle counts. Address-error tests (the
// suite reads vector 3) are counted in their own columns; a cycle with AS but no data strobe (fx68k on an address
// error) is counted there and left out of the bus order.
// Tests whose RAM touches the setup areas (vectors 0-7, F000-F07F) or whose data accesses touch the two NOP words
// are skipped and counted.
// Environment: FXBUS=1 also prints passing tests whose bus order differs (with -v), FXAE=1 lists the frame words
// that differ on address-error tests, FXTRACE=1 prints every clock of the test (use with -t).
// Build: verify/fx68k_build.sh (Verilator 5.052 with --no-assert; Verilator 4.204 builds fx68k but the model never
// starts a bus cycle). fx68k reads microrom.mem / nanorom.mem from the current directory.
#include "Vfx68k.h"
#include "Vfx68k___024root.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <set>
#ifdef FX_MAME
#include "mame_model.h"
#endif

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

#ifdef FX_MAME
// -mame: the expected result of each test is taken from the MAME m68000 model (verify/mame) instead of the suite:
// final registers / SR / PC / prefetch, the bytes the suite lists plus every byte MAME wrote, and MAME's timed bus
// transactions. fx68k is then compared with MAME (the checkpoint 2 tie-breaker) on every suite test.
static mame_model *mm;
static uint8_t *mmem;
static void mame_expect(Test &t) {
    for (auto &e : t.in.ram) mmem[e.first & 0xffffff] = e.second;
    mame_state s;
    for (int i = 0; i < 17; i++) s.r[i] = t.in.r[i];
    s.sr = t.in.r[17]; s.pc = t.in.r[18]; s.ir = t.in.pf[0]; s.irc = t.in.pf[1];
    mm->log.clear();
    mm->set_state(s);
    int total = mm->step();
    mame_state o; mm->get_state(o);
    for (int i = 0; i < 17; i++) t.out.r[i] = o.r[i];
    t.out.r[17] = o.sr; t.out.r[18] = o.pc; t.out.pf[0] = o.ir; t.out.pf[1] = o.irc;
    std::set<uint32_t> addrs;
    for (auto &e : t.out.ram) addrs.insert(e.first & 0xffffff);
    for (auto &x : mm->log) if (x.wr) { addrs.insert(x.addr & 0xffffff); if (x.size == 2) addrs.insert((x.addr | 1) & 0xffffff); }
    t.out.ram.clear();
    for (uint32_t a : addrs) t.out.ram.push_back({a, mmem[a]});
    t.tr.clear();
    bool tas = (t.in.pf[0] & 0xffc0) == 0x4ac0 && ((t.in.pf[0] >> 3) & 7) >= 2;
    int at = 0;
    for (size_t i = 0; i < mm->log.size(); i++) {
        const mame_access &x = mm->log[i];
        if (x.size == 2 && (x.addr & 1)) continue;                 // aborted access (address error)
        Tr r; r.t = x.wr ? 'w' : 'r'; r.len = 4; r.fc = x.fc; r.addr = x.addr; r.sz = x.size == 2; r.val = x.val;
        if (tas && !x.wr && i + 1 < mm->log.size() && mm->log[i + 1].wr && mm->log[i + 1].addr == x.addr) {
            r.t = 't'; r.len = mm->log[i + 1].time + 4 - x.time; i++;
        }
        if (x.time > at) t.tr.push_back(Tr{'n', (uint32_t)(x.time - at), 0, 0, 0, 0});
        t.tr.push_back(r);
        at = x.time + r.len;
    }
    if (total > at) t.tr.push_back(Tr{'n', (uint32_t)(total - at), 0, 0, 0, 0});
    for (auto &e : t.in.ram) mmem[e.first & 0xffffff] = 0;
    for (uint32_t a : addrs) mmem[a] = 0;
    for (auto &x : mm->log) { mmem[x.addr & 0xffffff] = 0; mmem[(x.addr ^ 1) & 0xffffff] = 0; }
}
#endif

static uint8_t *mem;
static uint8_t *used;                       // byte set by this test (cleared before the next one)
static std::vector<uint32_t> touched;
static void mark(uint32_t a) { if (!used[a]) { used[a] = 1; touched.push_back(a); } }
static void w8(uint32_t a, uint8_t v) { a &= 0xffffff; mark(a); mem[a] = v; }
static void w16(uint32_t a, uint16_t v) { w8(a, v >> 8); w8(a + 1, v & 0xff); }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v & 0xffff); }

static Vfx68k *cpu;
static uint64_t ph;
static void tick() {
    cpu->enPhi1 = (ph & 1) == 0;
    cpu->enPhi2 = (ph & 1) == 1;
    uint32_t a = ((uint32_t)cpu->eab << 1) & 0xffffff;
    cpu->iEdb = (mem[a] << 8) | mem[(a + 1) & 0xffffff];
    cpu->DTACKn = cpu->ASn;
    cpu->clk = 0; cpu->eval(); cpu->clk = 1; cpu->eval();
    ph++;
}

struct Result {
    bool reached = false, regok = false, srok = false, ramok = false, busok = false;
    std::vector<std::pair<uint32_t, std::pair<uint8_t, uint8_t>>> rambad;   // address, (fx68k, suite)
    int aborted = 0;
    uint32_t g[19] = {0};
    std::vector<Tr> bus;
    std::vector<std::pair<uint32_t, uint16_t>> writes;
    std::string tgot;                       // timed transactions (suite form), see run()
    std::set<uint32_t> cpuw;                // bytes written by fx68k during the test
    bool tvalid = false;
};
static std::string timed_suite(const Test &t, bool shape) {
    std::string s; char buf[64]; uint32_t idle = 0;
    for (auto &x : t.tr) {
        if (x.t == 'n') { idle += x.len; continue; }
        if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); s += buf; idle = 0; }
        if (shape) snprintf(buf, sizeof buf, "%c%u ", x.t, x.len);
        else snprintf(buf, sizeof buf, "%c%u:%u@%x%s ", x.t, x.len, x.fc, x.addr, x.sz ? "w" : "b");
        s += buf;
    }
    if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); s += buf; }
    return s;
}
static std::string strip_fc(const std::string &full) {    // drop the ":fc" of each token, keep the address
    std::string o;
    for (size_t i = 0; i < full.size(); i++) {
        if (full[i] == ':' && i + 2 < full.size() && full[i + 2] == '@') { i += 1; continue; }
        o += full[i];
    }
    return o;
}
static std::string shape_of(const std::string &full) {      // drop ":fc@addr size" from each token
    std::string o; size_t i = 0;
    while (i < full.size()) {
        size_t j = full.find(' ', i); if (j == std::string::npos) j = full.size();
        std::string tok = full.substr(i, j - i);
        size_t c = tok.find(':'); if (c != std::string::npos) tok = tok.substr(0, c);
        o += tok + " "; i = j + 1;
    }
    return o;
}

static const char *RN[19] = {"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","usp","ssp","sr","pc"};

// returns false if the test cannot be set up (RAM overlaps the probe's own areas)
static bool run(const Test &t, Result &R) {
    uint32_t pc = t.in.r[18] & 0xffffff, fpc = t.out.r[18] & 0xffffff;
    auto clash = [&](uint32_t a) { a &= 0xffffff; return a < 8 || (a >= 0xf000 && a < 0xf080); };
    for (auto &e : t.in.ram) if (clash(e.first)) return false;
    for (auto &e : t.out.ram) if (clash(e.first)) return false;
    // the NOP words replace the next opcode words: skip a test whose data accesses touch them
    for (auto &x : t.tr)
        if (x.t != 'n' && x.fc != 2 && x.fc != 6 && (x.addr & 0xffffff) + 1 >= fpc && (x.addr & 0xffffff) < fpc + 4) return false;
    if ((fpc & 1) || (pc & 1) || (fpc < pc + 2 && fpc + 4 > pc)) return false;      // NOPs would cover the opcode
    for (uint32_t a : touched) { mem[a] = 0; used[a] = 0; }
    touched.clear();
    for (auto &e : t.in.ram) w8(e.first, e.second);
    w16(pc, t.in.pf[0]); w16(pc + 2, t.in.pf[1]);
    w32(0, 0x800); w32(4, 0xf000);
    uint32_t p = 0xf000;
    w16(p, 0x207c); w32(p + 2, t.in.r[15]); p += 6;           // MOVEA.L #usp,A0
    w16(p, 0x4e60); p += 2;                                   // MOVE A0,USP
    for (int i = 0; i < 8; i++) { w16(p, 0x203c | (i << 9)); w32(p + 2, t.in.r[i]); p += 6; }
    for (int i = 0; i < 7; i++) { w16(p, 0x207c | (i << 9)); w32(p + 2, t.in.r[8 + i]); p += 6; }
    w16(p, 0x2e7c); w32(p + 2, t.in.r[16]); p += 6;           // MOVEA.L #ssp,A7
    w16(p, 0x46fc); w16(p + 2, t.in.r[17]); p += 4;           // MOVE #sr,SR
    uint32_t jmp = p;
    w16(p, 0x4ef9); w32(p + 2, pc); p += 6;                   // JMP pc
    w16(fpc, 0x4e71); w16(fpc + 2, 0x4e71);                   // NOP NOP at the final PC
    std::set<uint32_t> cpuw;                                  // bytes written by the CPU during the test

    cpu->HALTn = 1; cpu->VPAn = 1; cpu->BERRn = 1; cpu->BRn = 1; cpu->BGACKn = 1;
    cpu->IPL0n = cpu->IPL1n = cpu->IPL2n = 1;
    ph = 0;
    for (int k = 0; k < 40; k++) { cpu->pwrUp = 1; cpu->extReset = 1; tick(); }
    cpu->pwrUp = 0;
    for (int k = 0; k < 400; k++) tick();
    cpu->extReset = 0;
    // phases: 0 setup until the JMP target's second word is fetched, 1 test (record bus), 2 done
    int phase = 0, seen_target = 0;
    bool in_cyc = false, wseen = false, rseen = false; uint32_t ca = 0, cfc = 0, strobes = 0, rdat = 0, wdat = 0;
    bool jmp_fetched = false;
    // timing (tick numbers of AS falls): the test starts when the JMP target's second fetch ends (fall + 8 ticks) and
    // ends at the S0 of the stop fetch (fall - 2 ticks; S0 -> AS fall measured as 2 ticks below, any constant cancels)
    long tfall = 0, tstart = -1;
    struct TC { char t; long f, r; uint32_t fc, addr, sz; };
    std::vector<TC> tcs;
    long k_end = 0;
    for (long k = 0; k < 200000; k++) {
        tick();
        uint32_t a = ((uint32_t)cpu->eab << 1) & 0xffffff;
        uint32_t fc = (cpu->FC2 << 2) | (cpu->FC1 << 1) | cpu->FC0;
        if (getenv("FXTRACE") && phase == 1) printf("   tick %lu phi%d AS %d UDS %d LDS %d RW %d A %06x FC %u D %04x E %d VMA %d\n", (unsigned long)ph, (int)((ph - 1) & 1) + 1, cpu->ASn, cpu->UDSn, cpu->LDSn, cpu->eRWn, a, fc, cpu->oEdb, cpu->E, cpu->VMAn);
        if (!cpu->ASn) {
            if (!in_cyc) {
                in_cyc = true; ca = a; cfc = fc; strobes = 0; wseen = rseen = false; tfall = k;
                if (phase == 1 && a == ((fpc + 4) & 0xffffff) && (fc == 2 || fc == 6)) { phase = 2; R.reached = true; k_end = k; break; }
            }
            uint32_t s = (cpu->UDSn ? 0 : 2) | (cpu->LDSn ? 0 : 1);
            strobes |= s;
            if (s && cpu->eRWn) { rdat = (mem[a] << 8) | mem[(a + 1) & 0xffffff]; rseen = true; }
            if (s && !cpu->eRWn) {
                wseen = true; wdat = cpu->oEdb;
                uint32_t a1 = (a + 1) & 0xffffff;
                if (s & 2) { mem[a] = cpu->oEdb >> 8; mark(a); if (phase == 1) cpuw.insert(a); }
                if (s & 1) { mem[a1] = cpu->oEdb & 0xff; mark(a1); if (phase == 1) cpuw.insert(a1); }
            }
        } else if (in_cyc) {
            in_cyc = false;
            if (phase == 1 && strobes == 0) R.aborted++;   // AS without data strobes (fx68k on an address error)
            else if (phase == 1) {
                Tr x; x.t = (wseen && rseen) ? 't' : wseen ? 'w' : 'r'; x.fc = cfc; x.sz = strobes == 3; x.len = 0;
                x.addr = ca | ((strobes == 1) ? 1 : 0);
                uint32_t d = wseen ? wdat : rdat;
                x.val = (strobes == 3) ? d : (strobes == 2 ? d >> 8 : d & 0xff);
                R.bus.push_back(x);
                if (wseen) R.writes.push_back({x.addr, (uint16_t)x.val});
                tcs.push_back(TC{x.t, tfall, k, x.fc, x.addr, x.sz});
            }
            if (phase == 0) {
                if (ca == ((jmp + 4) & 0xffffff)) jmp_fetched = true;           // last JMP extension word
                if (jmp_fetched && (ca == pc || ca == ((pc + 2) & 0xffffff))) seen_target++;
                if (seen_target == 2) { phase = 1; tstart = tfall + 8; }        // queue holds the test's two words
            }
        }
    }
    if (R.reached && tstart >= 0) {
        // a cycle without wait states lasts 8 ticks from its AS fall to the next S0 + 2; TAS: 20
        char buf[64]; long at = tstart;
        for (auto &x : tcs) {
            long s0 = x.f, len = (x.t == 't') ? 20 : 8;
            if (s0 > at) { snprintf(buf, sizeof buf, "n%ld ", (s0 - at) / 2); R.tgot += buf; }
            snprintf(buf, sizeof buf, "%c%ld:%u@%x%s ", x.t, len / 2, x.fc, x.addr, x.sz ? "w" : "b"); R.tgot += buf;
            at = s0 + len;
        }
        if (k_end > at) { snprintf(buf, sizeof buf, "n%ld ", (k_end - at) / 2); R.tgot += buf; }
        R.tvalid = true;
    }
    R.cpuw = cpuw;
    auto *r = cpu->rootp;
    for (int i = 0; i < 17; i++)
        R.g[i] = ((uint32_t)r->fx68k__DOT__excUnit__DOT__regs68H[i] << 16) | r->fx68k__DOT__excUnit__DOT__regs68L[i];
    R.g[17] = (r->fx68k__DOT__pswT << 15) | (r->fx68k__DOT__pswS << 13) | (r->fx68k__DOT__pswI << 8) | (r->fx68k__DOT__ccr & 0x1f);
    R.g[18] = R.reached ? fpc : 0xffffffff;
    R.regok = true;
    for (int i = 0; i < 17; i++) if (R.g[i] != t.out.r[i]) R.regok = false;
    R.srok = R.g[17] == t.out.r[17];
    R.ramok = true;
    for (auto &e : t.out.ram) {
        uint32_t a = e.first & 0xffffff;
        if (a >= fpc && a < fpc + 4 && !cpuw.count(a)) continue;     // the NOP patch (not written by the test)
        if (mem[a] != e.second) { R.ramok = false; R.rambad.push_back({a, {mem[a], e.second}}); }
    }
    std::vector<Tr> exp;
    for (auto &x : t.tr) if (x.t != 'n') exp.push_back(x);
    R.busok = exp.size() == R.bus.size();
    for (size_t i = 0; R.busok && i < exp.size(); i++)
        if (exp[i].t != R.bus[i].t || exp[i].addr != R.bus[i].addr || exp[i].fc != R.bus[i].fc || exp[i].sz != R.bus[i].sz) R.busok = false;
    return true;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int per = 0, verbose = 0, tmdump = 0; bool use_mame = false;
    FILE *emitf = nullptr;
    std::set<int> only;
    std::map<std::string, std::map<int, int>> excl;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) per = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) only.insert(atoi(argv[++i]));
        else if (!strcmp(argv[i], "-v") && i + 1 < argc) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-tm") && i + 1 < argc) tmdump = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-mame")) use_mame = true;
        else if (!strcmp(argv[i], "-emit") && i + 1 < argc) emitf = fopen(argv[++i], "w");
        else if (!strcmp(argv[i], "-x") && i + 1 < argc) {
            FILE *xf = fopen(argv[++i], "r");
            char fn[64], sr[16], why[96]; int ix;
            while (xf && fscanf(xf, "%63s %d %15s %95s", fn, &ix, sr, why) == 4)
                excl[fn][ix] = strcmp(sr, "-") ? (int)strtol(sr, nullptr, 16) : -1;
            if (xf) fclose(xf);
        }
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    mem = (uint8_t *)calloc(1 << 24, 1);
    used = (uint8_t *)calloc(1 << 24, 1);
    cpu = new Vfx68k;
#ifdef FX_MAME
    mm = mame_model_new(68000);
    mmem = (uint8_t *)calloc(1 << 24, 1);
    mm->mem = mmem;
#else
    if (use_mame) { printf("built without FX_MAME (fx68k_build.sh with MAMELIB set)\n"); return 1; }
#endif
    printf("# file run skipped pass(regs+sr+ram+pc) regfail srfail ramfail notreached bus_ok | excluded: run fx=suite fx=corrected"
           " | address-error tests: run pass bus_ok AS-without-strobes | timed_ok timed_shape_ok (non-excluded, incl. address-error)\n");
    uint64_t T[17] = {0};
    for (const char *fn : files) {
        std::vector<Test> tests;
        if (!load(fn, tests)) { printf("cannot load %s\n", fn); continue; }
        std::string base = fn; base = base.substr(base.rfind('/') + 1); base = base.substr(0, base.rfind('.'));
        std::map<int, int> &xs = excl[base];
        uint64_t c[17] = {0};
        int shown = 0, tmshown = 0;
        size_t step = (per > 0 && (size_t)per < tests.size()) ? tests.size() / per : 1;
        std::vector<int> idx;
        if (!only.empty()) { for (int i : only) if (i >= 0 && (size_t)i < tests.size()) idx.push_back(i); }
        else for (size_t i = 0; i < tests.size(); i += step) idx.push_back((int)i);
        // excluded tests are always run (all of them) when -x is given, reported in their own columns
        std::set<int> idxs(idx.begin(), idx.end());
        if (!excl.empty() && only.empty()) for (auto &e : xs) idxs.insert(e.first);
        for (int i : idxs) {
            Test t = tests[i];
#ifdef FX_MAME
            if (use_mame) mame_expect(t);
#endif
            Result R;
            bool isx = xs.count(i);
            if (!run(t, R)) {
                c[1]++;
#ifdef FX_MAME
                // fx68k cannot run this test (setup-area clash): the corrected expectation is MAME's, if it differs
                if (use_mame && emitf && !xs.count(i)) {
                    const Test &su = tests[i];
                    bool st = true;
                    for (int k = 0; k < 19; k++) if (t.out.r[k] != su.out.r[k]) st = false;
                    std::map<uint32_t, uint8_t> me(t.out.ram.begin(), t.out.ram.end());
                    for (auto &e : su.out.ram) if (me[e.first & 0xffffff] != e.second) st = false;
                    std::string tm = timed_suite(t, false);
                    if (!st || tm != timed_suite(su, false)) {
                        fprintf(emitf, "%s %d mame_only_setup_clash", base.c_str(), i);
                        for (int k = 0; k < 19; k++) fprintf(emitf, " %x", t.out.r[k]);
                        fprintf(emitf, " %x %x %zu", t.out.pf[0], t.out.pf[1], t.out.ram.size());
                        for (auto &e : t.out.ram) fprintf(emitf, " %x=%x", e.first, e.second);
                        fprintf(emitf, " | %s\n", tm.c_str());
                    }
                }
#endif
                continue;
            }
#ifdef FX_MAME
            if (use_mame && getenv("FXV3")) {
                // three-way verdict line: fx68k vs MAME (state, timing), fx68k vs suite, MAME vs suite
                const Test &su = tests[i];
                uint32_t fpc = su.out.r[18] & 0xffffff;
                bool fs_st = R.reached, ms_st = true;
                for (int k = 0; k < 18; k++) { if (R.g[k] != su.out.r[k]) fs_st = false; if (t.out.r[k] != su.out.r[k]) ms_st = false; }
                if (t.out.r[18] != su.out.r[18]) { fs_st = false; ms_st = false; }
                std::map<uint32_t, uint8_t> mexp(t.out.ram.begin(), t.out.ram.end());
                for (auto &e : su.out.ram) {
                    uint32_t a = e.first & 0xffffff;
                    if (a >= fpc && a < fpc + 4) continue;
                    if (mem[a] != e.second) fs_st = false;
                    if (mexp.count(a) && mexp[a] != e.second) ms_st = false;
                }
                bool fm_st = R.reached && R.regok && R.srok && R.ramok;
                std::string tsu = timed_suite(su, false), tmm = timed_suite(t, false);
                bool aeflag = false;
                for (auto &x : su.tr) if (x.t == 'r' && (x.addr & 0xffffff) == 0x00000c && x.fc == 5) aeflag = true;
                printf("V3 %s #%d %s fm=%d%d fs=%d%d ms=%d%d\n", base.c_str(), i, aeflag ? "AE" : "--", fm_st, R.tgot == tmm,
                       fs_st, R.tgot == tsu, ms_st, tmm == tsu);
            }
            if (use_mame && emitf && !xs.count(i)) {
                // corrected expectation (tools: suite_corrections.txt): fx68k's result where it differs from the suite;
                // the reason names the class (MAME, the tie-breaker, agrees with fx68k on every non-address-error test)
                const Test &su = tests[i];
                uint32_t fpc = su.out.r[18] & 0xffffff;
                bool st = R.reached;
                for (int k = 0; k < 18; k++) if (R.g[k] != su.out.r[k]) st = false;
                if ((R.g[18] & 0xffffff) != (su.out.r[18] & 0xffffff)) st = false;     // fx68k's PC has 24 bits
                std::set<uint32_t> addrs;
                for (auto &e : su.out.ram) addrs.insert(e.first & 0xffffff);
                for (uint32_t a : R.cpuw) addrs.insert(a);
                for (auto &e : su.out.ram) { uint32_t a = e.first & 0xffffff; if (!(a >= fpc && a < fpc + 4) && mem[a] != e.second) st = false; }
                std::string tsu = timed_suite(su, false);
                bool tim = R.tgot == tsu;
                if (getenv("FXDBG")) { printf("DBG st %d tim %d reached %d\n", st, tim, R.reached); for (int k = 0; k < 19; k++) if (R.g[k] != su.out.r[k]) printf(" k%d %x %x", k, R.g[k], su.out.r[k]); for (auto &e : su.out.ram) if (mem[e.first & 0xffffff] != e.second) printf(" m%x %x %x", e.first, mem[e.first & 0xffffff], e.second); printf("\n"); }
                if (!st || !tim) {
                    bool aeflag = false, fmok = R.reached && R.regok && R.srok && R.ramok;
                    for (auto &x : su.tr) if (x.t == 'r' && (x.addr & 0xffffff) == 0x00000c && x.fc == 5) aeflag = true;
                    std::string why;
                    if (aeflag) why = fmok ? "address_error_frame_timing" : "address_error_fx68k_not_mame";
                    else if (st && strip_fc(R.tgot) == strip_fc(tsu)) why = "pcrel_read_program_space";
                    else if (base == "CHK") why = "chk_flags_no_extra_prefetch";
                    else if (base == "RTE" || base == "RTR") why = "rte_rtr_sr_read_first";
                    else if (base == "DIVS" || base == "DIVU") why = st ? "divs_late_overflow_timing" : "div_undocumented_flags";
                    else if (base == "LINK") why = "link_a7_pushes_old_a7";
                    else if (base == "ADD.l" || base == "SUB.l") why = "addq_subq_long_an_8_clocks";
                    else why = "other";
                    if (!fmok && !aeflag) why += "_FX68K_NE_MAME";
                    fprintf(emitf, "%s %d %s", base.c_str(), i, why.c_str());
                    uint32_t pc32 = ((t.out.r[18] & 0xffffff) == (R.g[18] & 0xffffff)) ? t.out.r[18] :
                                    ((su.out.r[18] & 0xffffff) == (R.g[18] & 0xffffff)) ? su.out.r[18] : R.g[18];
                    for (int k = 0; k < 18; k++) fprintf(emitf, " %x", R.g[k]);
                    fprintf(emitf, " %x %x %x %zu", pc32, t.out.pf[0], t.out.pf[1], addrs.size());
                    for (uint32_t a : addrs) fprintf(emitf, " %x=%x", a, (a >= fpc && a < fpc + 4 && !R.cpuw.count(a)) ? (unsigned)[&]{ for (auto &e : su.out.ram) if ((e.first & 0xffffff) == a) return e.second; return (uint8_t)0; }() : mem[a]);
                    fprintf(emitf, " | %s\n", R.tgot.c_str());
                }
            }
#endif
            bool pass = R.reached && R.regok && R.srok && R.ramok;
            if (!isx) {
                std::string te = timed_suite(t, false);
                bool tf = R.tvalid && R.tgot == te, ts = R.tvalid && shape_of(R.tgot) == timed_suite(t, true);
                c[15] += tf; c[16] += ts;
                if (!ts && tmshown < tmdump) {
                    tmshown++;
                    printf("TM %s #%d [%s] | %s| %s\n", base.c_str(), i, t.name.c_str(), te.c_str(), R.tgot.c_str());
                }
            }
            bool aerr = false;
            for (auto &x : t.tr) if (x.t == 'r' && (x.addr & 0xffffff) == 0x00000c) aerr = true;
            if (isx) {
                c[8]++;
                c[9] += pass;
                int cor = xs[i];
                bool cok = R.reached && R.regok && R.ramok && cor >= 0 && R.g[17] == (uint32_t)cor;
                c[10] += cok;
                if (verbose || !only.empty()) {
                    printf("EXCL %s #%d: fx68k %s the suite%s\n", t.name.c_str(), i, pass ? "matches" : "differs from",
                           cor >= 0 ? (cok ? "; matches the corrected SR" : "; differs from the corrected SR") : "");
                    for (int k = 0; k < 18; k++)
                        if (R.g[k] != t.out.r[k] || k == 17) printf("   %-3s fx68k %08x suite %08x init %08x\n", RN[k], R.g[k], t.out.r[k], t.in.r[k]);
                    printf("   writes:"); for (auto &w : R.writes) printf(" %06x=%x", w.first, w.second); printf("\n");
                }
                continue;
            }
            if (aerr) {
                c[11]++; c[12] += pass; c[13] += R.busok; c[14] += R.aborted > 0;
                if (getenv("FXAE") && !pass) {   // frame words that differ, as offsets from the final SSP
                    uint32_t sp = t.out.r[16] & 0xffffff;
                    printf("AE %s #%d:", t.name.c_str(), i);
                    for (auto &m : R.rambad) printf(" +%d(%06x fx %02x exp %02x)", (int)(m.first - sp), m.first, m.second.first, m.second.second);
                    for (int k = 0; k < 17; k++) if (R.g[k] != t.out.r[k]) printf(" %s", RN[k]);
                    if (!R.srok) printf(" sr");
                    printf("\n");
                }
                continue;
            }
            c[0]++;
            c[2] += pass; c[3] += !R.regok; c[4] += !R.srok; c[5] += !R.ramok; c[6] += !R.reached; c[7] += R.busok;
            if (((!pass || (getenv("FXBUS") && !R.busok)) && shown < verbose) || !only.empty()) {
                shown++;
                printf("%s %s #%d%s\n", pass ? "PASS" : "FAIL", t.name.c_str(), i, R.reached ? "" : " (final PC not reached)");
                for (int k = 0; k < 18; k++)
                    if (R.g[k] != t.out.r[k] || k == 17) printf("   %-3s fx68k %08x suite %08x init %08x\n", RN[k], R.g[k], t.out.r[k], t.in.r[k]);
                printf("   writes:"); for (auto &w : R.writes) printf(" %06x=%x", w.first, w.second); printf("\n");
                for (auto &m : R.rambad) printf("   ram %06x fx68k %02x suite %02x\n", m.first, m.second.first, m.second.second);
                if (!R.busok) {
                    printf("   bus fx68k:"); for (auto &x : R.bus) printf(" %c%u@%06x%s", x.t, x.fc, x.addr, x.sz ? "w" : "b"); printf("\n");
                    printf("   bus suite:"); for (auto &x : t.tr) if (x.t != 'n') printf(" %c%u@%06x%s", x.t, x.fc, x.addr, x.sz ? "w" : "b"); printf("\n");
                }
            }
        }
        const char *b = strrchr(fn, '/'); b = b ? b + 1 : fn;
        printf("%-16s %5lu %4lu %5lu %4lu %4lu %4lu %4lu %5lu | %4lu %4lu %4lu | %4lu %4lu %4lu %4lu | %5lu %5lu\n", b, c[0], c[1], c[2], c[3], c[4],
               c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12], c[13], c[14], c[15], c[16]);
        fflush(stdout);
        for (int i = 0; i < 17; i++) T[i] += c[i];
    }
    if (files.size() > 1)
        printf("%-16s %5lu %4lu %5lu %4lu %4lu %4lu %4lu %5lu | %4lu %4lu %4lu | %4lu %4lu %4lu %4lu | %5lu %5lu\n", "TOTAL", T[0], T[1], T[2], T[3],
               T[4], T[5], T[6], T[7], T[8], T[9], T[10], T[11], T[12], T[13], T[14], T[15], T[16]);
    delete cpu;
    return 0;
}

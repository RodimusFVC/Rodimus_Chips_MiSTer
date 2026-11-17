// Copyright (C) 2026 Rodimus
// mamesuite: runs Tom Harte / SingleStepTests 68000 tests (tools/conv_harte.py binaries) on the standalone MAME m68000
// model (mame_model.cpp) - the checkpoint 2 tie-breaker - and compares with the suite.
//   mamesuite [-tm N] [-t idx] [-x exclusions] [-dump] <file.bin> ...
// Per test: load registers, prefetch queue and RAM, run one instruction (plus the exception processing it raises),
// compare D0-D7 A0-A6 USP SSP SR PC, the prefetch queue, every final RAM byte, and the timed transaction list (suite
// form: idle runs merged, each bus cycle with its length). A word access at an odd address that MAME logs before it
// raises the address error is an aborted cycle and counts as idle time. TAS read + write = one 't' cycle.
// -tm N: print the first N timing mismatches per file ("TM file #idx [name] | suite | mame"); -dump: print MAME's timed
// list for every test ("MT file #idx | list") for comparison with other models.
#include "mame_model.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <set>

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

std::string suite_timed(const Test &t) {
    std::string s; char buf[64]; uint32_t idle = 0;
    for (auto &x : t.tr) {
        if (x.t == 'n') { idle += x.len; continue; }
        if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); s += buf; idle = 0; }
        snprintf(buf, sizeof buf, "%c%u:%u@%x%s ", x.t, x.len, x.fc, x.addr, x.sz ? "w" : "b"); s += buf;
    }
    if (idle) { snprintf(buf, sizeof buf, "n%u ", idle); s += buf; }
    return s;
}
// MAME log -> suite-form timed list
std::string mame_timed(const std::vector<mame_access> &log, int total, uint16_t op) {
    std::string s; char buf[64]; int at = 0;
    bool tas = (op & 0xffc0) == 0x4ac0 && ((op >> 3) & 7) >= 2;
    for (size_t i = 0; i < log.size(); i++) {
        const mame_access &x = log[i];
        if (x.size == 2 && (x.addr & 1)) continue;                 // aborted (address error)
        char t = x.wr ? 'w' : 'r';
        int len = 4;
        if (tas && !x.wr && i + 1 < log.size() && log[i + 1].wr && log[i + 1].addr == x.addr) { t = 't'; len = log[i + 1].time + 4 - x.time; i++; }
        if (x.time > at) { snprintf(buf, sizeof buf, "n%d ", x.time - at); s += buf; }
        snprintf(buf, sizeof buf, "%c%d:%d@%x%s ", t, len, x.fc, x.addr, x.size == 2 ? "w" : "b"); s += buf;
        at = x.time + len;
    }
    if (total > at) { snprintf(buf, sizeof buf, "n%d ", total - at); s += buf; }
    return s;
}

static const char *RN[19] = {"d0","d1","d2","d3","d4","d5","d6","d7","a0","a1","a2","a3","a4","a5","a6","usp","ssp","sr","pc"};

int main(int argc, char **argv) {
    int tmdump = 0, only = -1, verbose = 0; bool dump = false, cat = false;
    std::map<std::string, std::set<int>> excl;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-tm") && i + 1 < argc) tmdump = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) only = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v") && i + 1 < argc) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-dump")) dump = true;
        else if (!strcmp(argv[i], "-cat")) cat = true;
        else if (!strcmp(argv[i], "-x") && i + 1 < argc) {
            FILE *xf = fopen(argv[++i], "r");
            char fn[64], sr[16], why[96]; int ix;
            while (xf && fscanf(xf, "%63s %d %15s %95s", fn, &ix, sr, why) == 4) excl[fn].insert(ix);
            if (xf) fclose(xf);
        } else files.push_back(argv[i]);
    }
    uint8_t *mem = (uint8_t *)calloc(1 << 24, 1);
    mame_model *m = mame_model_new(68000);
    m->mem = mem;
    printf("# file run pass regfail srfail pcfail pffail ramfail timed_ok excluded excl_regs_ok\n");
    uint64_t T[10] = {0};
    for (const char *fn : files) {
        std::vector<Test> tests;
        if (!load(fn, tests)) { printf("cannot load %s\n", fn); continue; }
        std::string base = fn; base = base.substr(base.rfind('/') + 1); base = base.substr(0, base.rfind('.'));
        uint64_t c[10] = {0};
        int tms = 0, shown = 0;
        for (size_t ti = 0; ti < tests.size(); ti++) {
            if (only >= 0 && (int)ti != only) continue;
            const Test &t = tests[ti];
            for (auto &e : t.in.ram) mem[e.first & 0xffffff] = e.second;
            mame_state s;
            for (int i = 0; i < 17; i++) s.r[i] = t.in.r[i];
            s.sr = t.in.r[17]; s.pc = t.in.r[18]; s.ir = t.in.pf[0]; s.irc = t.in.pf[1];
            m->log.clear();
            m->set_state(s);
            int clocks = m->step();
            mame_state o; m->get_state(o);
            uint32_t g[19];
            for (int i = 0; i < 17; i++) g[i] = o.r[i];
            g[17] = o.sr; g[18] = o.pc;
            bool regbad = false, srbad = g[17] != t.out.r[17], pcbad = g[18] != t.out.r[18], rambad = false;
            bool pfbad = o.ir != t.out.pf[0] || o.irc != t.out.pf[1];
            for (int i = 0; i < 17; i++) if (g[i] != t.out.r[i]) regbad = true;
            for (auto &e : t.out.ram) if (mem[e.first & 0xffffff] != e.second) rambad = true;
            std::string te = suite_timed(t), tg = mame_timed(m->log, clocks, t.in.pf[0]);
            bool timok = te == tg;
            bool pass = !regbad && !srbad && !pcbad && !rambad && !pfbad;
            if (dump) printf("MT %s #%zu | %s\n", base.c_str(), ti, tg.c_str());
            if (excl[base].count((int)ti)) { c[8]++; c[9] += !regbad && !pcbad && !rambad && !pfbad; }
            else {
                c[0]++; c[1] += pass; c[2] += regbad; c[3] += srbad; c[4] += pcbad; c[5] += pfbad; c[6] += rambad; c[7] += timok;
                if (cat && (!pass || !timok)) {
                    bool ae = false;
                    for (auto &x : t.tr) if (x.t == 'r' && x.addr == 0xc && x.fc == 5) ae = true;
                    printf("CAT %s %s%s%s%s%s%s%s\n", base.c_str(), ae ? "AE" : "--", regbad ? " reg" : "", srbad ? " sr" : "",
                           pcbad ? " pc" : "", pfbad ? " pf" : "", rambad ? " ram" : "", timok ? "" : " tim");
                }
                if (!timok && tms < tmdump) { tms++; printf("TM %s #%zu [%s] | %s| %s\n", base.c_str(), ti, t.name.c_str(), te.c_str(), tg.c_str()); }
                if (!pass && shown < verbose) {
                    shown++;
                    printf("FAIL %s #%zu\n", t.name.c_str(), ti);
                    for (int i = 0; i < 19; i++) if (g[i] != t.out.r[i] || i >= 17) printf("   %-3s mame %08x suite %08x init %08x\n", RN[i], g[i], t.out.r[i], t.in.r[i]);
                    printf("   pf mame %04x %04x suite %04x %04x\n", o.ir, o.irc, t.out.pf[0], t.out.pf[1]);
                    for (auto &e : t.out.ram) if (mem[e.first & 0xffffff] != e.second) printf("   ram %06x mame %02x suite %02x\n", e.first, mem[e.first & 0xffffff], e.second);
                }
            }
            for (auto &e : t.in.ram) mem[e.first & 0xffffff] = 0;
            for (auto &e : t.out.ram) mem[e.first & 0xffffff] = 0;
            for (auto &x : m->log) { mem[x.addr & 0xffffff] = 0; mem[(x.addr ^ 1) & 0xffffff] = 0; }
        }
        const char *b = strrchr(fn, '/'); b = b ? b + 1 : fn;
        printf("%-16s %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu\n", b, c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9]);
        fflush(stdout);
        for (int i = 0; i < 10; i++) T[i] += c[i];
    }
    if (files.size() > 1)
        printf("%-16s %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu %6lu\n", "TOTAL", T[0], T[1], T[2], T[3], T[4], T[5], T[6], T[7], T[8], T[9]);
    return 0;
}

// Copyright (C) 2026 Rodimus
// Runner for the V20 8080-emulation-mode suite (verify/suites/v20_8080, gzipped JSON) on x86sv with NEC8080:
//   s80 [-n N] [-i k] [-s] [-q] file.json.gz ...
// Per test: reset, load registers, PSW (MD = bit 15) and the MD write enable, empty queue; run from the first
// first-byte QS to the next one (or the HALT cycle); compare every register, the PSW, the write enable, every final
// RAM byte (and no other byte written), the I/O writes. RTL clocks per test are reported (the suite has no cycle
// column: no NEC document gives 8080-mode clock counts). With -DBUS16 the 16-bit bus (V30).
#include "Vtb_x86.h"
#include "verilated.h"
#include <zlib.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>
#include <vector>

// ---- minimal JSON reader (the suite's own format: objects, arrays, integers, strings) ----
struct J {
    enum T { NUL, NUM, STR, ARR, OBJ } t = NUL;
    long long n = 0;
    std::string s;
    std::vector<J> a;
    std::vector<std::pair<std::string, J>> o;
    const J *get(const char *k) const { for (auto &p : o) if (p.first == k) return &p.second; return nullptr; }
    long long num(const char *k, long long d = 0) const { const J *j = get(k); return j ? j->n : d; }
};
struct P {
    const char *p, *e;
    void ws() { while (p < e && (*p == ' ' || *p == '\n' || *p == '\r' || *p == '\t')) p++; }
    bool parse(J &j) {
        ws();
        if (p >= e) return false;
        if (*p == '{') {
            j.t = J::OBJ; p++; ws();
            if (*p == '}') { p++; return true; }
            for (;;) {
                J k; if (!parse(k) || k.t != J::STR) return false;
                ws(); if (*p != ':') return false; p++;
                J v; if (!parse(v)) return false;
                j.o.emplace_back(k.s, std::move(v));
                ws(); if (*p == ',') { p++; continue; }
                if (*p == '}') { p++; return true; }
                return false;
            }
        }
        if (*p == '[') {
            j.t = J::ARR; p++; ws();
            if (*p == ']') { p++; return true; }
            for (;;) {
                J v; if (!parse(v)) return false;
                j.a.push_back(std::move(v));
                ws(); if (*p == ',') { p++; continue; }
                if (*p == ']') { p++; return true; }
                return false;
            }
        }
        if (*p == '"') {
            j.t = J::STR; p++;
            while (p < e && *p != '"') { if (*p == '\\') p++; j.s += *p++; }
            p++; return true;
        }
        j.t = J::NUM;
        char *q; j.n = strtoll(p, &q, 10);
        if (q == p) return false;
        p = q; return true;
    }
};

static Vtb_x86 *top;
static uint8_t mem[1 << 20];
static const char *RN[14] = {"ax", "bx", "cx", "dx", "cs", "ss", "ds", "es", "sp", "bp", "si", "di", "ip", "flags"};

static void tick() { top->eval(); top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
static void set_w(uint32_t *w, int bit, int n, uint32_t v) {
    for (int i = 0; i < n; i++) { int b = bit + i; if ((v >> i) & 1) w[b / 32] |= 1u << (b % 32); else w[b / 32] &= ~(1u << (b % 32)); }
}
static uint32_t get_w(const uint32_t *w, int bit, int n) {
    uint32_t v = 0; for (int i = 0; i < n; i++) { int b = bit + i; v |= ((w[b / 32] >> (b % 32)) & 1u) << i; } return v;
}

struct Res { bool reg = true, ram = true, io = true, wem = true; int clocks = 0; std::vector<std::string> notes; };

static Res run(const J &t) {
    Res r;
    const J &in = *t.get("initial"), &fi = *t.get("final");
    memset(mem, 0x00, sizeof mem);
    std::map<uint32_t, uint8_t> iram, fram;
    for (auto &e : in.get("ram")->a) { mem[e.a[0].n & 0xFFFFF] = (uint8_t)e.a[1].n; iram[e.a[0].n & 0xFFFFF] = (uint8_t)e.a[1].n; }
    for (auto &e : fi.get("ram")->a) fram[e.a[0].n & 0xFFFFF] = (uint8_t)e.a[1].n;
    uint16_t ir[14], fr[14];
    for (int i = 0; i < 14; i++) { ir[i] = (uint16_t)in.get("regs")->num(RN[i]); fr[i] = (uint16_t)fi.get("regs")->num(RN[i], ir[i]); }
    const J *pins = t.get("pins");
    bool intr = pins && pins->num("intr"), nmi = pins && pins->num("nmi");
    uint8_t ivec = pins ? (uint8_t)pins->num("inta_vector") : 0;
    uint8_t pin = (uint8_t)t.num("port_in", 0xFF);
    bool halt_exp = t.num("halted", 0) != 0;

    top->reset = 1; top->tl_en = 0; top->din = 0; top->ready = 1; top->intr = 0; top->nmi = 0; top->test_n = 0;
    top->tl_md = 1; top->tl_mdwe = 0;
    tick(); tick();
    top->reset = 0;
    for (int i = 0; i < 7; i++) top->tl_regs[i] = 0;
    for (int i = 0; i < 14; i++) set_w(top->tl_regs, i * 16, 16, ir[i]);
    top->tl_md = (ir[13] >> 15) & 1;
    top->tl_mdwe = in.num("md_we") ? 1 : 0;
    top->tl_qlen = 0; top->tl_queue = 0; top->tl_ad = 0; top->tl_bhe = 1;
    top->tl_en = 1; tick(); top->tl_en = 0;
    top->intr = intr;

    uint32_t latch = 0; int type = 7; bool hi = false;
    std::vector<std::pair<uint8_t, uint8_t>> outs;
    std::vector<uint32_t> writes;
    bool started = false, halted = false; int opc = 0, after_halt = 0;
    for (int g = 0; g < 4000; g++) {
        if (nmi && g == 2) top->nmi = 1;
        auto feed = [&]() -> uint16_t {
            if (type == 0) return (uint16_t)(ivec | (ivec << 8));                  // INTA
            if (type == 1) return (uint16_t)(pin | (pin << 8));                    // I/O read
#ifdef BUS16
            return (uint16_t)(mem[latch & 0xFFFFE] | (mem[(latch & 0xFFFFE) | 1] << 8));
#else
            return mem[latch];
#endif
        };
        top->din = feed(); top->eval();
        if (top->ale) {
            latch = top->ad & 0xFFFFF; type = top->s20 & 7;
#ifdef BUS16
            hi = !top->bhe_n;
#endif
            if (type == 3) halted = true;
        }
        top->din = feed(); top->eval();
        if (top->wr && top->tstate == 3) {
            if (top->io) outs.push_back({(uint8_t)(latch & 0xFF), (uint8_t)((latch & 1) && hi ? (top->dout >> 8) : top->dout)});
            else {
#ifdef BUS16
                if (!(latch & 1)) { mem[latch] = top->dout & 0xFF; writes.push_back(latch); }
                if (hi) { uint32_t a = (latch | 1) & 0xFFFFF; mem[a] = top->dout >> 8; writes.push_back(a); }
#else
                mem[latch] = top->dout & 0xFF; writes.push_back(latch);
#endif
            }
        }
        if (!started && top->qs == 1) started = true;
        if (started) {
            if (top->qs == 1 && ++opc == 2) break;
            r.clocks++;
        }
        if (halted && ++after_halt > 8) break;
        tick();
    }
    // registers (sampled at the next opcode's first byte, or after the HALT cycle)
    uint32_t *dr = top->dbg_regs;
    for (int i = 0; i < 14; i++) {
        uint16_t got = (uint16_t)get_w(dr, i * 16, 16);
        if (i == 12 && halt_exp && halted) got++;        // halted: the debug IP is the HLT's own offset (1 byte)
        if (got != fr[i]) { r.reg = false; char b[80]; snprintf(b, sizeof b, "reg %s exp %04X got %04X", RN[i], fr[i], got); r.notes.push_back(b); }
    }
    if ((int)top->dbg_mdwe != (int)fi.num("md_we")) { r.wem = false; r.notes.push_back("md_we differs"); }
    if (halt_exp != halted) { r.reg = false; r.notes.push_back(halt_exp ? "HALT expected" : "unexpected HALT"); }
    for (auto &m : fram) if (mem[m.first] != m.second) {
        r.ram = false; char b[80]; snprintf(b, sizeof b, "mem %05X exp %02X got %02X", m.first, m.second, mem[m.first]); r.notes.push_back(b);
    }
    for (uint32_t a : writes) if (!fram.count(a)) {
        r.ram = false; char b[80]; snprintf(b, sizeof b, "mem %05X written (not in final ram)", a); r.notes.push_back(b);
    }
    const J *pe = t.get("ports");
    size_t np = pe ? pe->a.size() : 0;
    if (np != outs.size()) { r.io = false; r.notes.push_back("I/O write count differs"); }
    else for (size_t i = 0; i < np; i++)
        if (pe->a[i].a[0].n != outs[i].first || pe->a[i].a[1].n != outs[i].second) { r.io = false; r.notes.push_back("I/O write differs"); }
    return r;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vtb_x86;
    long nmax = -1, only = -1; bool stop = false, quiet = false;
    std::vector<std::string> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-n") && i + 1 < argc) nmax = atol(argv[++i]);
        else if (!strcmp(argv[i], "-i") && i + 1 < argc) only = atol(argv[++i]);
        else if (!strcmp(argv[i], "-s")) stop = true;
        else if (!strcmp(argv[i], "-q")) quiet = true;
        else files.push_back(argv[i]);
    }
    if (!quiet) printf("%-12s %6s %6s %6s %6s %6s %6s %8s\n", "file", "tests", "pass", "reg", "ram", "io", "inf", "clk avg");
    for (auto &fn : files) {
        gzFile z = gzopen(fn.c_str(), "rb");
        if (!z) { fprintf(stderr, "%s: cannot open\n", fn.c_str()); return 1; }
        std::string data; char buf[1 << 16]; int k;
        while ((k = gzread(z, buf, sizeof buf)) > 0) data.append(buf, k);
        gzclose(z);
        J root; P p{data.data(), data.data() + data.size()};
        if (!p.parse(root) || root.t != J::ARR) { fprintf(stderr, "%s: bad JSON\n", fn.c_str()); return 1; }
        long tests = 0, pass = 0, freg = 0, fram = 0, fio = 0, inf = 0; long long clk = 0;
        for (auto &t : root.a) {
            long idx = t.num("idx");
            if (only >= 0 && idx != only) continue;
            if (nmax >= 0 && tests >= nmax) break;
            Res r = run(t);
            tests++; clk += r.clocks;
            if (t.num("inferred")) inf++;
            if (!r.reg || !r.wem) freg++;
            if (!r.ram) fram++;
            if (!r.io) fio++;
            bool ok = r.reg && r.wem && r.ram && r.io;
            if (ok) pass++;
            else if (stop || only >= 0) {
                printf("# %s test %ld \"%s\":", fn.c_str(), idx, t.get("name")->s.c_str());
                for (auto &n : r.notes) printf(" | %s", n.c_str());
                printf("\n");
                if (stop) { stop = false; }
            }
        }
        std::string b = fn.substr(fn.find_last_of('/') + 1);
        b = b.substr(0, b.find(".json"));
        printf("%-12s %6ld %6ld %6ld %6ld %6ld %6ld %8.1f\n", b.c_str(), tests, pass, freg, fram, fio, inf, tests ? (double)clk / tests : 0.0);
    }
    delete top;
    return 0;
}

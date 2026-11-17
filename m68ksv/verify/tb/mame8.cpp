// Copyright (C) 2026 Rodimus
// mame8: bus-cycle lockstep of m68ksv on the 8-bit bus (68008 DIP48 / 68008FN / 68EC000 with MODE = 0) against MAME's
// cycle-exact m68008 (verify/mame, unmodified MAME source compiled as a C++ model). Same program for both: the random
// instruction stream of lockstep.cpp (suite opcodes + extension words, vector table to a recovery handler), immediate
// DTACK, no interrupts. Every byte cycle is compared in order: start time (S0, CPU clocks, aligned on the first cycle),
// address (on the configuration's address pins), function code, read / write, data.
//   mame8 [-cpu 68008|68009|68001] [-seed N] [-runs N] [-clocks N] [-v N] <suite .bin ...>
// Known divergence, not a pass: MAME's m68008 runs an odd word access as two complete byte accesses (a write is
// performed) and then takes the address error; m68ksv keeps the 68000 rule (one cycle with AS only, no data strobe,
// no write; DESIGN.md / REPORT.md). A run that first differs at such an address error ends there and is counted
// separately (both CPUs are then reset with the same memory and continue the stream); every other difference is a
// mismatch, which ends the run.
#include "Vm68ksv.h"
#include "verilated.h"
#include "mame_model.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>

static uint32_t rng = 1;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static std::vector<std::vector<uint8_t>> pool;
static bool rd(FILE *f, void *p, size_t n) { return fread(p, 1, n, f) == n; }
struct St { uint32_t r[19]; uint16_t pf[2]; std::vector<std::pair<uint32_t, uint8_t>> ram; };
static bool rdst(FILE *f, St &s) {
    if (!rd(f, s.r, 76) || !rd(f, s.pf, 4)) return false;
    uint32_t n; if (!rd(f, &n, 4) || n > 100000) return false;
    s.ram.resize(n);
    for (auto &e : s.ram) { uint8_t b[5]; if (!rd(f, b, 5)) return false; memcpy(&e.first, b, 4); e.second = b[4]; }
    return true;
}
static void load_pool(const char *fn, int every) {
    FILE *f = fopen(fn, "rb"); if (!f) return;
    char m[4]; uint32_t n;
    if (!rd(f, m, 4) || memcmp(m, "M68T", 4) || !rd(f, &n, 4)) { fclose(f); return; }
    for (uint32_t i = 0; i < n; i++) {
        uint16_t nl; if (!rd(f, &nl, 2)) break;
        std::string name(nl, 0); if (!rd(f, &name[0], nl)) break;
        St a, b; if (!rdst(f, a) || !rdst(f, b)) break;
        uint32_t len, nt; if (!rd(f, &len, 4) || !rd(f, &nt, 4)) break;
        fseek(f, (long)nt * 15, SEEK_CUR);
        if (i % every) continue;
        uint32_t pc = a.r[18] & 0xffffff;
        std::vector<uint8_t> ins = {(uint8_t)(a.pf[0] >> 8), (uint8_t)a.pf[0], (uint8_t)(a.pf[1] >> 8), (uint8_t)a.pf[1]};
        for (uint32_t k = 4; k < 10; k++) {
            int v = -1;
            for (auto &e : a.ram) if ((e.first & 0xffffff) == pc + k) v = e.second;
            if (v < 0) break;
            ins.push_back((uint8_t)v);
        }
        pool.push_back(ins);
    }
    fclose(f);
}

static uint8_t *mem, *mmem;
static const uint32_t STREAM = 0x1000, STREAM_END = 0x40000, HANDLER = 0x400, RESTART = 0x500;
static void w16(uint32_t a, uint16_t v) { mem[a & 0xffffff] = v >> 8; mem[(a + 1) & 0xffffff] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static void build_memory() {
    for (uint32_t a = 0; a < (1u << 24); a += 4) { uint32_t v = rnd(); memcpy(mem + a, &v, 4); }
    w32(0, 0x8000); w32(4, STREAM);
    for (int v = 2; v < 256; v++) w32(v * 4, HANDLER);
    uint32_t p = HANDLER;
    auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
    o16(0x46fc); o16(0x2700);                       // MOVE #$2700,SR
    o16(0x2e7c); o16(0x0000); o16(0x8000);          // MOVEA.L #$8000,A7
    o16(0x2039); o16(0x0000); o16(RESTART);         // MOVE.L RESTART,D0
    o16(0x0680); o16(0x0000); o16(0x0046);          // ADDI.L #$46,D0
    o16(0x0280); o16(0x0003); o16(0xfffe);          // ANDI.L #$3FFFE,D0
    o16(0x0080); o16(0x0000); o16(STREAM);          // ORI.L #STREAM,D0
    o16(0x23c0); o16(0x0000); o16(RESTART);         // MOVE.L D0,RESTART
    o16(0x2040);                                    // MOVEA.L D0,A0
    o16(0x4ed0);                                    // JMP (A0)
    w32(RESTART, STREAM);
    for (uint32_t a = STREAM; a < STREAM_END - 16;) {
        auto &ins = pool[rnd() % pool.size()];
        for (uint8_t b : ins) mem[a++] = b;
        if (a & 1) a++;
    }
}

struct Cyc { int64_t t; uint32_t a; int fc, wr; uint8_t d; bool ae; };
static std::string fmt(const Cyc &c) {
    char b[96]; snprintf(b, sizeof b, "t %lld %c FC%d A %06x D %02x%s", (long long)c.t, c.wr ? 'w' : 'r', c.fc, c.a, c.d, c.ae ? " (AS only: address error)" : "");
    return b;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int cpu = 68008, runs = 1, verbose = 0, every = 16; uint32_t seed = 1; long clocks = 100000;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-cpu")) cpu = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-seed")) seed = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-runs")) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-clocks")) clocks = atol(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = atoi(argv[++i]);
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    for (const char *f : files) load_pool(f, every);
    if (pool.empty()) { printf("no instruction pool (give suite .bin files)\n"); return 1; }
    // address pins compared: 20 (68008), 22 (68008FN); the 68EC000 also on 22 - MAME's m68008 core drives 22 bits only,
    // so the 68EC000 check is a system that decodes A21-A0
    uint32_t amask = cpu == 68008 ? 0xfffff : 0x3fffff;
    mem = (uint8_t *)malloc(1 << 24); mmem = (uint8_t *)malloc(1 << 24);
    long total_cyc = 0, total_clk = 0, ae_resets = 0, halt_resets = 0, trapv_resets = 0; int fails = 0;
    for (int run = 0; run < runs; run++) {
        rng = seed * 2654435761u + run * 40503u + 1;
        build_memory();
        memcpy(mmem, mem, 1 << 24);
        Vm68ksv *top = new Vm68ksv;
        top->IPL_n = 7; top->BERR_n = 1; top->VPA_n = 1; top->BR_n = 1; top->BGACK_n = 1; top->MODE = 0; top->tl_en = 0;
        top->DTACK_n = 1;
        mame_model *m = mame_model_new(68008);
        m->mem = mmem; m->mem_mask = amask;
        // online: m68ksv phase by phase, MAME instruction by instruction, cycles compared in order as both produce them;
        // at an address error of m68ksv (or a double-fault halt) both are reset with the same memory (m68ksv's), the
        // reset vector then pointing at the handler, which continues the instruction stream further on
        std::deque<Cyc> qv, qm;
        int64_t mtime = 0, off = 0; bool aligned = false;
        uint64_t n = 0; long hold = 80; bool in_cyc = false, ds_seen = false; int64_t as_fall = 0; Cyc cur{};
        long run_cyc = 0; int64_t t_first = -1, t_last = 0; bool bad = false;
        std::deque<std::string> hist;
        uint16_t op_prev = 0, op_cur = 0;
        auto do_reset = [&]() {
            w32(4, HANDLER); memcpy(mmem, mem, 1 << 24);
            hold = 80; in_cyc = false; qv.clear(); qm.clear(); aligned = false;
            // registers too: m68ksv's (read through the debug port, CPU not clocked) into the MAME model
            mame_state st{};
            for (int k = 0; k < 17; k++) {
                top->dbg_ra = k; top->cen_p = 0; top->cen_n = 0;
                top->clk = 0; top->eval(); top->clk = 1; top->eval();
                st.r[k] = top->dbg_rd;
            }
            st.sr = 0x2700 | (top->dbg_sr & 0x1f); st.pc = HANDLER;
            m->set_state(st);
            m->log.clear(); m->halted = false; m->reset(); mtime = 0;
        };
        m->reset();
        for (long ph = 0; ph < 2 * clocks && !bad; ph++) {
            if (hold > 0) { top->RESET_n_i = 0; top->HALT_n_i = 0; hold--; } else { top->RESET_n_i = 1; top->HALT_n_i = 1; }
            uint32_t a = ((((uint32_t)top->A << 1) | top->A0)) & amask;
            top->D_i = mem[a];
            top->DTACK_n = top->AS_n;
            top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1;
            top->clk = 0; top->eval();
            bool fin = top->dbg_fin;
            top->clk = 1; top->eval();
            n++;
            if (fin) { op_prev = op_cur; op_cur = top->dbg_ir; }
            if (hold > 0 || top->RESET_n_i == 0) continue;
            a = ((((uint32_t)top->A << 1) | top->A0)) & amask;
            if (!top->AS_n) {
                if (!in_cyc) { in_cyc = true; as_fall = (int64_t)n - 1; ds_seen = false; cur = Cyc{0, a, top->FC, !top->RW, 0, false}; }
                if (!top->DS_n && !ds_seen) {
                    ds_seen = true;
                    if (top->RW) cur.d = mem[a]; else { cur.d = top->D_o & 0xff; mem[a] = cur.d; }
                }
                // TAS: R/W falls inside the same AS period: the read part ends, the write part starts (S0 one clock
                // before R/W goes low, as for any write)
                if (ds_seen && !top->RW && !cur.wr) {
                    cur.t = (as_fall - 2) / 2; cur.ae = false; qv.push_back(cur);
                    as_fall = (int64_t)n - 1; ds_seen = false; cur = Cyc{0, a, top->FC, 1, 0, false};
                }
            } else if (in_cyc) {
                in_cyc = false; cur.t = (as_fall - 2) / 2; cur.ae = !ds_seen; qv.push_back(cur);
            }
            if (!top->HALT_n_o) { halt_resets++; do_reset(); continue; }
            while (!qv.empty()) {
                while (qm.empty() && !m->halted) {
                    m->log.clear();
                    int k = m->step();
                    for (auto &x : m->log) qm.push_back(Cyc{mtime + x.time, x.addr & amask, x.fc, x.wr, (uint8_t)x.val, false});
                    mtime += k;
                }
                if (qm.empty()) break;
                Cyc x = qv.front(), y = qm.front();
                if (!aligned) { off = x.t - y.t; aligned = true; }
                char line[160]; snprintf(line, sizeof line, "%-44s | MAME %s", fmt(x).c_str(), fmt(Cyc{y.t + off, y.a, y.fc, y.wr, y.d, false}).c_str());
                hist.push_back(line); if (hist.size() > (size_t)(verbose > 1 ? 60 : 8)) hist.pop_front();
                if (x.t - off != y.t || x.a != y.a || x.fc != y.fc || x.wr != y.wr || x.d != y.d) {
                    if (x.ae) { ae_resets++; do_reset(); break; }
                    // MAME's TRAPV tests its internal ALU status (m_isr), so it traps after e.g. an ADDA that overflowed
                    // with CCR V = 0; fx68k and the manual test CCR V (directed test: lockstep TRAPVTEST=1): resync
                    if (op_prev == 0x4e76 && !(top->dbg_sr & 2) && y.wr) { trapv_resets++; do_reset(); break; }
                    { mame_state ms; m->get_state(ms); printf("m68ksv IR %04x upc %d SR %04x | MAME (after its step) SR %04x PC %06x\n",
                      top->dbg_ir, top->dbg_upc, top->dbg_sr, ms.sr, ms.pc); }
                    bad = true; break;
                }
                qv.pop_front(); qm.pop_front();
                run_cyc++; if (t_first < 0) t_first = x.t; t_last = x.t;
            }
        }
        total_cyc += run_cyc; total_clk += (long)(n / 2);
        if (bad) {
            fails++;
            printf("run %d seed %u: MISMATCH after %ld byte cycles\n", run, seed, run_cyc);
            for (auto &l : hist) printf("   %s\n", l.c_str());
        } else if (verbose) printf("run %d: %ld byte cycles equal in %llu clocks\n", run, run_cyc, (unsigned long long)(n / 2));
        delete top; delete m;
    }
    printf("mame8 (CPU %d): %d runs, %ld CPU clocks, %ld byte cycles compared, %d mismatching runs; resets after an m68ksv "
           "address error (documented divergence): %ld, after MAME's TRAPV on the internal V (documented): %ld, after a "
           "double-fault halt: %ld\n", cpu, runs, total_clk, total_cyc, fails, ae_resets, trapv_resets, halt_resets);
    return fails != 0;
}

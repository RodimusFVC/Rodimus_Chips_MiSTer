// Copyright (C) 2026 Rodimus
// rerun010: bus error + RTE continuation self-check of the 68010 (CPU = 68010). Two m68ksv instances run the same random
// program (mus010's stream: suite opcodes + 68010 snippets) from the same memory. Instance B gets BERR instead of DTACK
// on random bus cycles; its bus error handler (vector 2) is a single RTE, so the format-8 frame is reloaded at once, the
// faulted cycle re-run and the instruction continued (data sheet 5.3.9, 5.4). At every instruction dispatch outside
// that handler the two instances must agree: D0-D7, A0-A6, USP, SSP, SR, PC, VBR, SFC, DFC and the bytes written since
// the last comparison (the 29-word frame area below the stack is excluded and restored from A after the RTE).
// Also: a quarter of the injected faults get SSW.RR set by the harness with the cycle completed in software
// (write: memory updated from DOB; read: DIB / IIB filled), the other way a handler may return (data sheet 5.3.9).
//   rerun010 [-seed N] [-runs N] [-instr N] [-p P] [-sw] [-v N] <suite .bin ...>      P: 1 / P of the bus cycles fault
#include "Vm68ksv.h"
#include "verilated.h"
#include "m68ksv_ualabels.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <deque>

static uint32_t rng = 1;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static uint32_t rng2 = 7;                   // injection decisions (independent of the program generator)
static uint32_t rnd2() { rng2 ^= rng2 << 13; rng2 ^= rng2 >> 17; rng2 ^= rng2 << 5; return rng2; }
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

static uint8_t *memA, *memB, *mem;
static const uint32_t STREAM = 0x1000, STREAM_END = 0x40000, HANDLER = 0x400, RESTART = 0x500, BEHANDLER = 0x600;
static const uint32_t VBR_ALT[3] = {0x0, 0x800, 0xc00};
static void w16(uint32_t a, uint16_t v) { mem[a & 0xffffff] = v >> 8; mem[(a + 1) & 0xffffff] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static int mix = 25;
static uint32_t put_snippet(uint32_t a) {
    std::vector<uint16_t> w;
    int k = rnd() % 11;
    switch (k) {
    case 0: w.push_back(0x42c0 | (rnd() % 8)); break;
    case 1: w.push_back(0x40c0 | (0x10 | (rnd() % 7))); break;                         // MOVE SR,(An)
    case 2: w.push_back(0x4e7a); w.push_back((rnd() & 0xf000) | ((rnd() & 1) ? 0x800 : 0x001)); break;
    case 3: { int r = rnd() % 8; uint32_t v = VBR_ALT[rnd() % 3];
              w.push_back(0x203c | (r << 9)); w.push_back(v >> 16); w.push_back(v); w.push_back(0x4e7b); w.push_back((r << 12) | 0x801); break; }
    case 4: { int sz = rnd() % 3, m = rnd() % 3, r = rnd() % 7;
              w.push_back(0x0e00 | (sz << 6) | ((2 + m) << 3) | r); w.push_back((rnd() & 0xf000) | ((rnd() & 1) << 11)); break; }
    case 5: w.push_back(0x487a); w.push_back(0x0006); w.push_back(0x4e74); w.push_back((rnd() % 64) * 2 - 32); break;
    case 6: w.push_back(0x4848 | (rnd() % 8)); break;
    case 7: w.push_back(0x027c); w.push_back(0xdfff); break;
    case 8: w.push_back(0x3f3c); w.push_back(((rnd() % 256) << 2)); w.push_back(0x487a); w.push_back(0x0008);
            w.push_back(0x3f3c); w.push_back((rnd() & 0x071f) | 0x2000); w.push_back(0x4e73); break;
    case 9: { static const uint16_t lp[] = {0x3218, 0x32d8, 0x30d9, 0xd058, 0xb058, 0x4218, 0x4458, 0xe0d8, 0xd109, 0x2018};
              w.push_back(0x7000 | (rnd() % 20)); w.push_back(lp[rnd() % 10]); w.push_back(0x51c8 | ((rnd() % 16) << 8)); w.push_back(0xfffc); break; }
    default: w.push_back(0x48d0 | (rnd() % 7)); w.push_back(rnd() & 0x7fff); break;    // MOVEM.L list,(An)
    }
    for (auto x : w) { w16(a, x); a += 2; }
    return a;
}
static void build_memory() {
    mem = memA;
    for (uint32_t a = 0; a < (1u << 24); a += 4) { uint32_t v = rnd(); memcpy(mem + a, &v, 4); }
    w32(0, 0x8000); w32(4, STREAM);
    for (int t = 0; t < 3; t++) { for (int v = 2; v < 256; v++) w32(VBR_ALT[t] + v * 4, HANDLER); w32(VBR_ALT[t] + 8, BEHANDLER); }
    w32(0x800, 0x8000); w32(0x804, STREAM); w32(0xc00, 0x8000); w32(0xc04, STREAM);
    uint32_t p = HANDLER;
    auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
    o16(0x46fc); o16(0x2700); o16(0x2e7c); o16(0x0000); o16(0x8000);
    o16(0x2039); o16(0x0000); o16(RESTART); o16(0x0680); o16(0x0000); o16(0x0046);
    o16(0x0280); o16(0x0003); o16(0xfffe); o16(0x0080); o16(0x0000); o16(STREAM);
    o16(0x23c0); o16(0x0000); o16(RESTART); o16(0x2040); o16(0x4ed0);
    w32(RESTART, STREAM);
    w16(BEHANDLER, 0x4e73);                         // bus error handler: RTE
    for (uint32_t a = STREAM; a < STREAM_END - 32;) {
        if ((int)(rnd() % 100) < mix) a = put_snippet(a);
        else { auto &ins = pool[rnd() % pool.size()]; for (uint8_t b : ins) mem[a++] = b; if (a & 1) a++; }
    }
}

struct Snap { uint32_t r[17], pc, vbr; uint16_t sr; int sfc, dfc, ir, upc; std::map<uint32_t, uint8_t> w; };
static std::deque<std::string> blog;
static long n_lmre = 0;
static std::string hex(uint32_t v) { char b[16]; snprintf(b, sizeof b, "%x", v); return b; }

struct Inst {
    Vm68ksv *t; uint8_t *m; bool in_cyc = false, wseen = false, berr = false; uint64_t n = 0; long hold = 80;
    std::map<uint32_t, uint8_t> w; std::deque<Snap> q;
    // B only: fault bookkeeping
    bool in_handler = false; int inj_ok = 0; long faults = 0, rr_sw = 0;
    uint32_t ssp = 0x8000;            // SSP as of the last dispatch
    uint32_t frame_lo = 0, frame_hi = 0, ca = 0; int cfc = 0, crw = 1; uint16_t cdo = 0;
};

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int runs = 1, verbose = 0, every = 16, P = 40; uint32_t seed = 1; long instr = 20000; bool sw = false;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-seed")) seed = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-runs")) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-instr")) instr = atol(argv[++i]);
        else if (!strcmp(argv[i], "-p")) P = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-sw")) sw = true;
        else if (!strcmp(argv[i], "-v")) verbose = atoi(argv[++i]);
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    for (const char *f : files) load_pool(f, every);
    if (pool.empty()) { printf("no instruction pool\n"); return 1; }
    memA = (uint8_t *)malloc(1 << 24); memB = (uint8_t *)malloc(1 << 24);
    long tot_cmp = 0, tot_faults = 0, tot_sw = 0, halts = 0, halts_b = 0, by_kind[4] = {0, 0, 0, 0}; int fails = 0;
    for (int run = 0; run < runs; run++) {
        rng = seed * 2654435761u + run * 40503u + 1; rng2 = seed * 7919u + run * 104729u + 3;
        build_memory();
        memcpy(memB, memA, 1 << 24);
        Inst A, B; A.t = new Vm68ksv; A.m = memA; B.t = new Vm68ksv; B.m = memB;
        for (Inst *x : {&A, &B}) { auto *t = x->t; t->IPL_n = 7; t->BERR_n = 1; t->VPA_n = 1; t->BR_n = 1; t->BGACK_n = 1; t->MODE = 1; t->tl_en = 0; t->DTACK_n = 1; }
        long cmp = 0; bool bad = false; std::string why; std::deque<std::string> hist;
        auto snap = [&](Inst &x, Snap &s) {
            for (int k = 0; k < 17; k++) {
                x.t->dbg_ra = k; x.t->cen_p = 0; x.t->cen_n = 0;
                x.t->clk = 0; x.t->eval(); x.t->clk = 1; x.t->eval();
                s.r[k] = x.t->dbg_rd;
            }
            s.pc = x.t->dbg_pc & 0xffffff; s.sr = x.t->dbg_sr; s.vbr = x.t->dbg_vbr; s.sfc = x.t->dbg_sfc; s.dfc = x.t->dbg_dfc;
            s.ir = x.t->dbg_ir; s.upc = x.t->dbg_upc;
        };
        // one phase of an instance; returns true at a dispatch it reports
        auto phase = [&](Inst &x, bool isB) -> bool {
            auto *t = x.t;
            if (x.hold > 0) { t->RESET_n_i = 0; t->HALT_n_i = 0; x.hold--; } else { t->RESET_n_i = 1; t->HALT_n_i = 1; }
            uint32_t a = ((uint32_t)t->A << 1) & 0xffffff;
            t->D_i = (x.m[a] << 8) | x.m[a + 1];
            if (t->FC == 7 && a == 0) t->D_i = 0xffff;
            bool b = isB && x.berr && !t->AS_n;
            t->DTACK_n = t->AS_n || b;
            t->BERR_n = !b;
            t->cen_p = (x.n & 1) == 0; t->cen_n = (x.n & 1) == 1;
            t->clk = 0; t->eval();
            bool fin = t->dbg_fin;
            t->clk = 1; t->eval();
            x.n++;
            if (x.hold > 0 || t->RESET_n_i == 0) return false;
            a = ((uint32_t)t->A << 1) & 0xffffff;
            if (!t->AS_n) {
                if (!x.in_cyc) {
                    x.in_cyc = true; x.wseen = false; x.ca = a; x.cfc = t->FC; x.crw = t->RW;
                    // B: fault this cycle? (not IACK / BKPT, not while a fault is being handled)
                    // (not in group-0 processing or a vector fetch / refill: a fault there is a double fault)
                    int u = t->dbg_upc;
                    bool g0 = (u >= UA10_EXC0_010 && u < UA10_EXC0_010 + 80) || (u >= UA_VECTAIL && u <= UA_VECJMP_G0 + 2) ||
                              u == UA_EXC0 || u == UA_EXC0A || (u >= UA10_RTE10_F8 && u < UA10_RTE10_END);
                    // (and only where the handler is reachable: VBR one of the tables, the supervisor stack in RAM)
                    bool reach = (t->dbg_vbr == 0 || t->dbg_vbr == 0x800 || t->dbg_vbr == 0xc00) && x.ssp >= 0x2000 && x.ssp <= 0xfff000;
                    // (not an access within the frame's own area: an instruction that has already moved SP past stack
                    // data it still reads, e.g. RTR / RTE popping, would see the frame overwrite that data)
                    if (((x.ssp - a) & 0xffffff) < 80 || ((a - x.ssp) & 0xffffff) < 16) reach = false;
                    if (isB && x.inj_ok && reach && !g0 && t->FC != 7 && (int)(rnd2() % P) == 0) {
                        x.berr = true; x.inj_ok = 0; x.faults++;
                        by_kind[!t->RW ? 1 : (t->FC & 3) == 2 ? 2 : 0]++;
                    }
                }
                if (!t->RW && (!t->UDS_n || !t->LDS_n) && !x.wseen && !(isB && x.berr)) {
                    x.wseen = true;
                    // the bus error vector entries (and the handler) are read-only for the program (both instances)
                    bool ro = a < 0x400 || (a >= 0x800 && a < 0x1000) || (a >= BEHANDLER && a < BEHANDLER + 2);
                    if (!ro) {
                        if (!t->UDS_n) { x.m[a] = t->D_o >> 8; x.w[a] = t->D_o >> 8; }
                        if (!t->LDS_n) { x.m[a + 1] = t->D_o; x.w[a + 1] = t->D_o; }
                    }
                }
                if (t->RW) x.wseen = false; else { x.crw = 0; x.cdo = t->D_o; }
            } else {
                if (isB && x.in_cyc && verbose > 1) {
                    char bb[120]; snprintf(bb, sizeof bb, "      B bus %06x FC%d %c %04x%s upc %d", x.ca, x.cfc, x.crw ? 'r' : 'w',
                                           x.crw ? ((x.m[x.ca] << 8) | x.m[x.ca + 1]) : x.cdo, x.berr ? " BERR" : "", t->dbg_upc);
                    blog.push_back(bb); if (blog.size() > 90) blog.pop_front();
                }
                x.in_cyc = false; x.berr = false;
            }
            return fin;
        };
        bool resetA = true;
        while (cmp < instr && !bad) {
            // advance each instance to its next reportable dispatch
            for (int which = 0; which < 2 && !bad; which++) {
                Inst &x = which ? B : A;
                while (x.q.empty() && !bad) {
                    if (phase(x, which == 1)) {
                        Snap s; snap(x, s);
                        x.ssp = s.r[16] & 0xffffff;
                        if (s.upc == UA_EXC0 || s.upc == UA_EXC0A || s.upc == UA_HALT || s.upc == UA_HALTA) continue;   // not a dispatch
                        if (which == 1) {
                            // the handler's RTE: optionally complete the faulted cycle in software (SSW.RR = 1)
                            if (s.pc == BEHANDLER) {
                                x.in_handler = true;
                                uint32_t sp = s.r[16], f = sp & 0xffffff;
                                x.frame_lo = f; x.frame_hi = f + 58;
                                if (f > 0xffff00) { x.in_handler = true; continue; }   // frame at the top of memory: no software completion
                                x.frame_lo = f; x.frame_hi = f + 58;
                                uint16_t ssw = (x.m[f + 8] << 8) | x.m[f + 9];
                                uint32_t fa = (x.m[f + 10] << 24) | (x.m[f + 11] << 16) | (x.m[f + 12] << 8) | x.m[f + 13];
                                fa &= 0xfffffe | (ssw & 0x0200 ? 1 : 0);
                                bool rmw = ssw & 0x0800;
                                bool infr = ((fa - f) & 0xffffff) < 60;      // the faulted access targets the frame itself
                                if (fa < 0x400 || (fa >= 0x800 && fa < 0x1000) || (fa >= BEHANDLER && fa < BEHANDLER + 2)) infr = true;   // read-only area
                                if (sw && !rmw && !infr && (rnd2() & 3) == 0) {
                                    x.rr_sw++;
                                    if (!(ssw & 0x0100)) {          // write: perform it from DOB
                                        uint16_t dob = (x.m[f + 16] << 8) | x.m[f + 17];
                                        if (ssw & 0x0200) { x.m[fa] = (fa & 1) ? dob : dob >> 8; x.w[fa] = x.m[fa]; }
                                        else { x.m[fa & ~1u] = dob >> 8; x.m[(fa & ~1u) + 1] = dob; x.w[fa & ~1u] = dob >> 8; x.w[(fa & ~1u) + 1] = dob; }
                                    } else {                         // read: data into DIB (data) or IIB (prefetch)
                                        uint16_t v = (ssw & 0x0200) ? ((fa & 1) ? x.m[fa] : x.m[fa]) : ((x.m[fa & ~1u] << 8) | x.m[(fa & ~1u) + 1]);
                                        int off = (ssw & 0x2000) ? 24 : 20;
                                        x.m[f + off] = v >> 8; x.m[f + off + 1] = v;
                                    }
                                    x.m[f + 8] |= 0x80;               // RR
                                }
                                continue;                             // the handler's RTE is not compared
                            }
                            if (x.in_handler) {
                                // continuation done: restore the frame area from A, allow the next fault
                                x.in_handler = false;
                                for (uint32_t ad = x.frame_lo; ad < x.frame_hi; ad++) { x.m[ad & 0xffffff] = memA[ad & 0xffffff]; x.w.erase(ad & 0xffffff); }
                            }
                            if (!x.in_handler && s.upc != UA_EXC0 && s.upc != UA_EXC0A) x.inj_ok = 1;
                        }
                        s.w.swap(x.w); x.w.clear();
                        x.q.push_back(s);
                    }
                    if (!x.t->HALT_n_o) { bad = true; why = which ? " B halted" : " A halted"; if (verbose > 1) printf("  halt: upc %d PC %06x\n", x.t->dbg_upc, x.t->dbg_pc & 0xffffff); }
                    if (x.n > 400000000ull) { bad = true; why = " no progress"; }
                }
            }
            if (bad) break;
            Snap a = A.q.front(), b = B.q.front(); A.q.pop_front(); B.q.pop_front();
            std::string d;
            for (int k = 0; k < 17; k++) if (a.r[k] != b.r[k]) d += " R" + std::to_string(k) + " " + hex(a.r[k]) + "/" + hex(b.r[k]);
            if (a.pc != b.pc) d += " PC " + hex(a.pc) + "/" + hex(b.pc);
            if ((a.sr & 0xa71f) != (b.sr & 0xa71f)) d += " SR " + hex(a.sr) + "/" + hex(b.sr);
            if (a.vbr != b.vbr || a.sfc != b.sfc || a.dfc != b.dfc) d += " CTL";
            // loop mode continued by RTE: the loop words are not fetched again, but the first DBcc after it runs the
            // normal DBcc micro-routine (internal fetches) to re-establish the counter test: same state, other entry
            bool lmre = (a.upc >= UA10_DBL4 && a.upc <= UA10_DBL1) && b.upc == UA_DBCC;
            if (lmre) n_lmre++;
            if (a.upc != b.upc && !lmre) d += " UPC " + std::to_string(a.upc) + "/" + std::to_string(b.upc);
            for (auto &x : a.w) if (memB[x.first] != memA[x.first] && ((x.first - B.frame_lo) & 0xffffff) >= 58) d += " M" + hex(x.first) + " " + hex(memA[x.first]) + "/" + hex(memB[x.first]);
            for (auto &x : b.w) if (memB[x.first] != memA[x.first] && ((x.first - B.frame_lo) & 0xffffff) >= 58) d += " M" + hex(x.first) + " " + hex(memA[x.first]) + "/" + hex(memB[x.first]);
            char line[160]; snprintf(line, sizeof line, "cmp %ld upc %d IR %04x PC %06x SR %04x | B faults %ld", cmp, a.upc, a.ir, a.pc, a.sr, B.faults);
            hist.push_back(line); if (hist.size() > 12) hist.pop_front();
            if (!d.empty()) { bad = true; why = d; break; }
            cmp++;
            (void)resetA;
        }
        tot_cmp += cmp; tot_faults += B.faults; tot_sw += B.rr_sw;
        if (bad) {
            if (why == " B halted" || why == " A halted") { halts++; if (why == " B halted") halts_b++; if (verbose) printf("run %d: %s after %ld comparisons\n", run, why.c_str(), cmp); }
            else {
                fails++;
                printf("run %d seed %u: MISMATCH at comparison %ld:%s\n", run, seed, cmp, why.c_str());
                for (auto &l : hist) printf("   %s\n", l.c_str());
                for (auto &l : blog) printf("%s\n", l.c_str());
            }
        } else if (verbose) printf("run %d: %ld comparisons equal, %ld faults\n", run, cmp, B.faults);
        delete A.t; delete B.t;
    }
    printf("rerun010: %d runs, %ld dispatches compared, %ld bus errors injected (read %ld, write %ld, prefetch %ld), "
           "%ld completed in software (RR), %d mismatching runs, %ld runs ended by a double-fault halt (%ld of them in B first)\n",
           runs, tot_cmp, tot_faults, by_kind[0], by_kind[1], by_kind[2], tot_sw, fails, halts, halts_b);
    printf("loop mode continued by RTE (first DBcc through the normal micro-routine, no fetch): %ld\n", n_lmre);
    return fails != 0;
}

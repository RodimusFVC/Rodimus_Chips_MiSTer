// Copyright (C) 2026 Rodimus
// mus010: instruction-boundary lockstep of m68ksv (CPU = 68010) against MAME's Musashi 68010 (verify/musashi, MAME's
// Musashi compiled unmodified as a C++ model). Same random program for both (suite opcodes + extension words from the
// SingleStepTests pool, mixed with 68010-specific snippets: MOVEC, MOVES, RTD, MOVE from CCR / SR, BKPT, privilege
// drops, RTE frames of every format, trace, DBcc loops for loop mode), each CPU with its own 16 MB memory.
// At every m68ksv instruction dispatch (except the one that starts trace exception processing - Musashi takes the
// trace inside the instruction's step) the two states are compared: D0-D7, A0-A7, USP, SSP, SR, PC, VBR, SFC, DFC,
// and the memory writes made since the last comparison (address, data, function code; last value per byte).
//   mus010 [-seed N] [-runs N] [-instr N] [-irq] [-w W] [-mix P] [-berr P] [-v N] <suite .bin ...>
// Interrupts: m68ksv sees random IPL levels on its pins; when it dispatches to interrupt processing, Musashi is
// stepped with that level asserted (Musashi samples at instruction boundaries only; interrupt timing is fx68k's,
// verified at checkpoint 2). Group-0 exceptions (address / bus error) are compared where Musashi models them and
// then resynchronised, counted per class (REPORT.md "Checkpoint 3"): Musashi aborts an instruction at its C++ access
// point, not at the 68000 / 68010 micro-word, and its format-8 frame contents are simplified.
#include "Vm68ksv.h"
#include "verilated.h"
#include "musashi_model.h"
#include "m68ksv_ualabels.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
#include <deque>

static uint32_t rng = 1;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static std::vector<std::vector<uint8_t>> pool;
static std::vector<std::string> pool_name;
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
    std::string base = fn; base = base.substr(base.find_last_of('/') + 1);
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
        pool.push_back(ins); pool_name.push_back(base);
    }
    fclose(f);
}

static uint8_t *mem;                       // m68ksv's memory
static uint8_t *mmem;                      // Musashi's memory
static const uint32_t STREAM = 0x1000, STREAM_END = 0x40000, HANDLER = 0x400, RESTART = 0x500;
static const uint32_t VBR_ALT[3] = {0x0, 0x800, 0xc00};       // vector tables (all entries -> HANDLER)
static void w16(uint32_t a, uint16_t v) { mem[a & 0xffffff] = v >> 8; mem[(a + 1) & 0xffffff] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static int mix = 25;                        // per-mille... percent of 68010 snippets in the stream
static long n_snip[16];
static const char *snip_name[16] = {"MOVE from CCR", "MOVE from SR", "MOVEC", "MOVEC VBR", "MOVES", "RTD", "BKPT",
                                    "user mode", "RTE frame", "trace on", "DBcc loop", "MOVEC illegal", "", "", "", ""};
static int ea_mem(uint16_t &op_ea, std::vector<uint16_t> &ext) {    // a memory-alterable EA with its extension words
    int m = rnd() % 6, r = rnd() % 8;
    switch (m) {
    case 0: op_ea = 0x10 | r; break;                    // (An)
    case 1: op_ea = 0x18 | r; break;                    // (An)+
    case 2: op_ea = 0x20 | r; break;                    // -(An)
    case 3: op_ea = 0x28 | r; ext.push_back(rnd() & 0xfffe); break;              // (d16,An)
    case 4: op_ea = 0x38; ext.push_back(0x2000 + (rnd() & 0x7ffe)); break;      // abs.W (RAM area)
    default: op_ea = 0x39; ext.push_back(0x0000); ext.push_back(0x4000 + (rnd() & 0x7ffe)); break;   // abs.L
    }
    return m;
}
static uint32_t put_snippet(uint32_t a) {
    std::vector<uint16_t> w;
    int k = rnd() % 12;
    n_snip[k]++;
    uint16_t ea; std::vector<uint16_t> ext;
    switch (k) {
    case 0:   // MOVE from CCR
        if (rnd() & 1) w.push_back(0x42c0 | (rnd() % 8));
        else { ea_mem(ea, ext); w.push_back(0x42c0 | ea); for (auto e : ext) w.push_back(e); }
        break;
    case 1:   // MOVE from SR (privileged on the 68010)
        if (rnd() & 1) w.push_back(0x40c0 | (rnd() % 8));
        else { ea_mem(ea, ext); w.push_back(0x40c0 | ea); for (auto e : ext) w.push_back(e); }
        break;
    case 2: { // MOVEC to / from SFC, DFC, USP (random register; VBR read only)
        static const uint16_t cr[5] = {0x000, 0x001, 0x800, 0x801, 0x800};
        int dir = rnd() & 1, c = rnd() % 5;
        if (dir && cr[c] == 0x801) c = 0;
        w.push_back(dir ? 0x4e7b : 0x4e7a); w.push_back((rnd() & 0xf000) | cr[c]);
        break; }
    case 3: { // MOVEC Dn,VBR with a vector-table base
        int r = rnd() % 8;
        uint32_t v = VBR_ALT[rnd() % 3];
        w.push_back(0x203c | (r << 9)); w.push_back(v >> 16); w.push_back(v);      // MOVE.L #v,Dr
        w.push_back(0x4e7b); w.push_back((r << 12) | 0x801);
        break; }
    case 4: { // MOVES
        int sz = rnd() % 3;
        ea_mem(ea, ext);
        w.push_back(0x0e00 | (sz << 6) | ea); w.push_back((rnd() & 0xf000) | ((rnd() & 1) << 11));
        for (auto e : ext) w.push_back(e);
        break; }
    case 5: { // PEA (6,PC); RTD #d (returns to the next snippet)
        w.push_back(0x487a); w.push_back(0x0006);
        w.push_back(0x4e74); w.push_back((rnd() % 64) * 2 - 32);
        break; }
    case 6:   // BKPT #n (breakpoint cycle, then illegal instruction)
        w.push_back(0x4848 | (rnd() % 8));
        break;
    case 7:   // drop to user mode
        if (rnd() & 1) { w.push_back(0x027c); w.push_back(0xdfff); }                // ANDI #$DFFF,SR
        else { w.push_back(0x46fc); w.push_back(0x0000 | (rnd() & 0x071f)); }       // MOVE #x,SR (S = 0)
        break;
    case 8: { // MOVE.W #fv,-(A7); PEA (8,PC); MOVE.W #sr,-(A7); RTE
        static const uint16_t fmt[8] = {0, 0, 0, 0, 0x1000, 0x2000, 0x9000, 0xf000};
        uint16_t fv = fmt[rnd() % 8] | ((rnd() % 256) << 2);
        uint16_t sr = (rnd() & 0x071f) | ((rnd() % 4) ? 0x2000 : 0) | ((rnd() % 8) ? 0 : 0x8000);
        w.push_back(0x3f3c); w.push_back(fv);
        w.push_back(0x487a); w.push_back(0x0008);
        w.push_back(0x3f3c); w.push_back(sr);
        w.push_back(0x4e73);
        break; }
    case 9:   // trace on
        w.push_back(0x007c); w.push_back(0x8000);
        break;
    case 10: { // MOVEQ #n,D0; <one-word loop-mode instruction>; DBcc D0,(-4)
        static const uint16_t lp[] = {0x3218, 0x32d8, 0x30d9, 0x3091, 0x3121, 0xd058, 0xb058, 0x9050, 0xc050, 0x8060,
                                      0xd1c8, 0xb1d0, 0xd358, 0xb348, 0x4218, 0x4458, 0x4a50, 0x4810, 0xe0d8, 0xd109,
                                      0xc30a, 0x2018, 0x20c1, 0x4298, 0xd398};
        int r = rnd() % 8;
        w.push_back(0x7000 | (rnd() % 20));
        uint16_t li = lp[rnd() % (sizeof lp / 2)];
        // the address registers of the loop body: keep them from A7 so the loop does not run over the stack
        if ((li & 0x38) && (li & 7) == 7) li &= ~1;
        w.push_back(li);
        w.push_back(0x50c8 | ((rnd() % 16) << 8)); w.push_back(0xfffc);
        (void)r;
        break; }
    default: { // MOVEC with an illegal control register
        w.push_back((rnd() & 1) ? 0x4e7b : 0x4e7a); w.push_back((rnd() & 0xf000) | 0x002 + (rnd() % 0x7fd));
        break; }
    }
    for (auto x : w) { w16(a, x); a += 2; }
    return a;
}
static void build_memory() {
    for (uint32_t a = 0; a < (1u << 24); a += 4) { uint32_t v = rnd(); memcpy(mem + a, &v, 4); }
    w32(0, 0x8000); w32(4, STREAM);
    for (int t = 0; t < 3; t++) for (int v = 2; v < 256; v++) w32(VBR_ALT[t] + v * 4, HANDLER);
    w32(0x800, 0x8000); w32(0x804, STREAM); w32(0xc00, 0x8000); w32(0xc04, STREAM);
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
    for (uint32_t a = STREAM; a < STREAM_END - 32;) {
        if ((int)(rnd() % 100) < mix) a = put_snippet(a);
        else {
            auto &ins = pool[rnd() % pool.size()];
            for (uint8_t b : ins) mem[a++] = b;
            if (a & 1) a++;
        }
    }
}

struct Wr { uint8_t v; int fc; };
struct CycE { long n = 0, ok = 0, bad = 0, last_m = 0, last_mus = 0; int ir = 0; };
static std::map<int, CycE> cyc_map;
static bool cyc_on = false;
// the vector tables are ROM for both CPUs (the random program would otherwise overwrite them and run into endless
// exception loops); writes there are ignored on both sides
static bool rom_area(uint32_t a) { a &= 0xffffff; return a < 0x400 || (a >= 0x800 && a < 0x1000); }
static std::string hex(uint32_t v) { char b[16]; snprintf(b, sizeof b, "%x", v); return b; }

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int only = -1, runs = 1, verbose = 0, every = 16, wmax = 0, berr_p = 0; uint32_t seed = 1; long instr = 20000; bool irq = false;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-seed")) seed = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-runs")) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-instr")) instr = atol(argv[++i]);
        else if (!strcmp(argv[i], "-irq")) irq = true;
        else if (!strcmp(argv[i], "-cyc")) cyc_on = true;      // cycle cross-check against Musashi (use without -w / -irq)
        else if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-mix")) mix = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-berr")) berr_p = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-only")) only = atoi(argv[++i]);
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    for (const char *f : files) load_pool(f, every);
    if (pool.empty()) { printf("no instruction pool (give suite .bin files)\n"); return 1; }
    mem = (uint8_t *)malloc(1 << 24); mmem = (uint8_t *)malloc(1 << 24);
    long tot_cmp = 0, tot_clk = 0, n_g0 = 0, n_halt = 0, n_int = 0, n_trace = 0, n_berr = 0, n_bkpt = 0;
    long n_exc = 0, n_nmi_wake = 0, n_quirk_divs = 0, n_rte_f8 = 0, n_smc = 0, n_tr2 = 0, n_uninit = 0, n_divs_dummy = 0, n_g0_regs_eq = 0, n_g0_frame_bad = 0, n_g0_romframe = 0, n_g0_ccr = 0, n_vbr_reset = 0, n_g0_deferred = 0, n_g0_pcrel = 0, n_g0_dbcc = 0, n_loopdb = 0, n_smc_loop = 0; uint32_t loop_lo = 0; bool loop_on = false; int loop_poison = 0;
    bool cyc_pend = false, lm_seen = false; int cyc_ir = 0, cyc_mus = 0, cyc_upc = 0; long cyc_t0 = 0; int fails = 0;
    for (int run = 0; run < runs; run++) {
        if (only >= 0 && run != only) continue;
        rng = seed * 2654435761u + run * 40503u + 1;
        build_memory();
        memcpy(mmem, mem, 1 << 24);
        Vm68ksv *top = new Vm68ksv;
        top->IPL_n = 7; top->BERR_n = 1; top->VPA_n = 1; top->BR_n = 1; top->BGACK_n = 1; top->MODE = 1; top->tl_en = 0;
        top->DTACK_n = 1;
        mus_model *m = mus_model_new();
        m->mem = mmem; m->ro = rom_area;
        m->reset();
        std::map<uint32_t, Wr> wv;                  // m68ksv writes since the last comparison
        long cmp = 0; uint64_t n = 0; long hold = 80; bool bad = false;
        int ipl = 0, ipl_hold = 0, wait = 0, iack_av = 0, iack_vec = 0, last_iack = -1, iack_lvl = 0; bool pend_int = false, uninit = false; bool in_cyc = false, wseen = false; uint32_t cyc_a = 0; int cyc_fc = 0;
        bool traced = false; int prev_ir = 0; bool prev_s = false; uint32_t prev_a7 = 0, prev_pc = 0; std::vector<uint32_t> last_w;
        bool first = true, g0_pending = false; std::string why; uint64_t last_fin = 0;
        std::deque<std::string> hist;
        auto regs = [&](uint32_t *r) {
            for (int k = 0; k < 17; k++) {
                top->dbg_ra = k; top->cen_p = 0; top->cen_n = 0;
                top->clk = 0; top->eval(); top->clk = 1; top->eval();
                r[k] = top->dbg_rd;
            }
        };
        auto do_reset = [&]() {
            hold = 80; in_cyc = false; wv.clear(); first = true; g0_pending = false;
            w32(4, HANDLER); memcpy(mmem, mem, 1 << 24);
            m->wlog.clear(); m->reset();
        };
        for (; cmp < instr && !bad; ) {
            if (hold > 0) { top->RESET_n_i = 0; top->HALT_n_i = 0; hold--; } else { top->RESET_n_i = 1; top->HALT_n_i = 1; }
            // bus: immediate or delayed DTACK; IACK by autovector (VPA) or vector number; BKPT acknowledged by DTACK
            uint32_t a = ((uint32_t)top->A << 1) & 0xffffff;
            // CPU space: interrupt acknowledge at A23-A4 all ones, breakpoint acknowledge at 0; any other CPU-space
            // address (MOVES with SFC / DFC = 7) is served from memory, as Musashi does
            bool cpu = top->FC == 7 && ((a & 0xfffff0) == 0xfffff0 || a == 0);
            if (top->AS_n) { wait = wmax ? (int)(rnd() % (wmax + 1)) : 0; iack_av = rnd() & 1; iack_vec = 0x40 + (rnd() % 192); }
            uint16_t din = (mem[a] << 8) | mem[a + 1];
            int vpa = 1;
            if (cpu && !top->AS_n && a != 0) { if (iack_av) vpa = 0; else din = iack_vec; last_iack = iack_av ? -1 : iack_vec; iack_lvl = (a >> 1) & 7; }
            if (cpu && !top->AS_n && a == 0) din = 0xffff;
            top->D_i = din;
            top->DTACK_n = top->AS_n || wait > 0 || !vpa;
            top->VPA_n = top->AS_n ? 1 : vpa;
            if (!top->AS_n && wait > 0 && (n & 1)) wait--;
            if (irq) {
                if (ipl_hold > 0) ipl_hold--;
                else { ipl = (rnd() % 6 == 0) ? (int)(rnd() % 8) : 0; ipl_hold = 40 + rnd() % 800; }
                top->IPL_n = 7 - ipl;
            }
            // STOP with nothing to wake it: a level-7 (edge) interrupt after 5000 idle clocks
            if (hold == 0 && n - last_fin > 10000 && n - last_fin < 10400) { top->IPL_n = 0; n_nmi_wake += (n - last_fin == 10001); }
            else if (!irq) top->IPL_n = 7;
            top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1;
            top->clk = 0; top->eval();
            bool fin = top->dbg_fin;
            top->clk = 1; top->eval();
            n++;
            if (hold > 0 || top->RESET_n_i == 0) { last_fin = n; continue; }
            if (n - last_fin > 400000) { bad = true; char b[96]; snprintf(b, sizeof b, " STALL (no dispatch for 200000 clocks, upc %d)", top->dbg_upc); why = b; break; }
            // m68ksv writes (data strobes with R/W low)
            a = ((uint32_t)top->A << 1) & 0xffffff;
            if (!top->AS_n) {
                if (!in_cyc) { in_cyc = true; wseen = false; cyc_a = a; cyc_fc = top->FC; }
                if (!top->RW && (!top->UDS_n || !top->LDS_n) && !wseen) {
                    wseen = true;
                    if (!rom_area(a)) {
                        if (!top->UDS_n) { mem[a] = top->D_o >> 8; wv[a] = Wr{(uint8_t)(top->D_o >> 8), top->FC}; }
                        if (!top->LDS_n) { mem[a + 1] = top->D_o; wv[a + 1] = Wr{(uint8_t)top->D_o, top->FC}; }
                    }
                }
                if (top->RW) wseen = false;
            } else {
                if (in_cyc && verbose > 3) { char b[80]; snprintf(b, sizeof b, "    bus %06x FC%d %c %04x %c%c", cyc_a, cyc_fc, top->RW ? 'r' : 'w', top->RW ? ((mem[cyc_a] << 8) | mem[cyc_a + 1]) : top->D_o, top->UDS_n ? '-' : 'U', top->LDS_n ? '-' : 'L');
                    hist.push_back(b); if (hist.size() > 60) hist.pop_front(); }
                in_cyc = false;
            }
            if (!top->HALT_n_o) { n_halt++; do_reset(); continue; }
            if (top->dbg_upc == UA_EXC0 || top->dbg_upc == UA_EXC0A) g0_pending = true;
            if (!fin) continue;
            last_fin = n;
            int upc = top->dbg_upc;
            if (upc == UA_EXC_TRACE) { n_trace++; traced = true; continue; }
            if (upc >= UA10_DBL4 && upc <= UA10_DBL1) {               // loop mode: looped instruction -> DBcc loop word
                n_loopdb++; loop_lo = (top->dbg_pc - 2) & 0xffffff; loop_on = true;
            } else if (loop_on && ((top->dbg_pc - loop_lo) & 0xffffff) >= 4) loop_on = false;
            // a FIN word whose cycle ended with a bus error: not a dispatch (group 0 processing follows)
            if (upc == UA_EXC0 || upc == UA_EXC0A || upc == UA_HALT || upc == UA_HALTA) { g0_pending = true; continue; }          // Musashi did the trace in the last step
            // an interrupt m68ksv took since the last comparison: Musashi takes it now, with the level and vector of
            // m68ksv's IACK cycle
            if (pend_int) {
                if (verbose > 2) printf("cmp %ld: interrupt level %d vector %d (-1 auto)\n", cmp, iack_lvl, last_iack);
                // Musashi quirk: an interrupt vector entry of 0 is replaced by vector 15 (m68kcpu.cpp
                // m68ki_exception_interrupt); the 68010 fetches the entry as it is
                { mus_state ms; m->get_state(ms); uint32_t va = (ms.vbr + 4 * (last_iack < 0 ? 24 + iack_lvl : last_iack)) & 0xffffff;
                  if (!mmem[va] && !mmem[va + 1] && !mmem[va + 2] && !mmem[va + 3]) { n_uninit++; uninit = true; } }
                m->set_irq(iack_lvl); m->iack_vector = last_iack;
                m->step();
                m->set_irq(0); m->iack_vector = -1; pend_int = false;
            }
            // compare m68ksv (now, between instructions) with Musashi (after its steps so far)
            uint32_t r[17]; regs(r);
            mus_state s; m->get_state(s);
            uint16_t msr = top->dbg_sr;
            std::string d;
            if (!first) {
                for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) d += " D" + std::to_string(k) + " " + hex(r[k]) + "/" + hex(s.d[k]);
                for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) d += " A" + std::to_string(k) + " " + hex(r[8 + k]) + "/" + hex(s.a[k]);
                if (r[15] != s.usp) d += " USP " + hex(r[15]) + "/" + hex(s.usp);
                if (r[16] != s.ssp) d += " SSP " + hex(r[16]) + "/" + hex(s.ssp);
                if ((msr & 0xa71f) != (s.sr & 0xa71f)) d += " SR " + hex(msr) + "/" + hex(s.sr);
                if ((top->dbg_pc & 0xffffff) != (s.pc & 0xffffff)) d += " PC " + hex(top->dbg_pc) + "/" + hex(s.pc);
                if (top->dbg_vbr != s.vbr) d += " VBR " + hex(top->dbg_vbr) + "/" + hex(s.vbr);
                if (top->dbg_sfc != s.sfc) d += " SFC " + hex(top->dbg_sfc) + "/" + hex(s.sfc);
                if (top->dbg_dfc != s.dfc) d += " DFC " + hex(top->dbg_dfc) + "/" + hex(s.dfc);
                std::map<uint32_t, Wr> mw;
                for (auto &x : m->wlog) {
                    if (x.mask & 0xff00) mw[x.addr] = Wr{(uint8_t)(x.data >> 8), x.fc};
                    if (x.mask & 0x00ff) mw[x.addr + 1] = Wr{(uint8_t)x.data, x.fc};
                }
                // memory: every byte either CPU wrote must now hold the same value in both memories (a write that
                // leaves a byte unchanged need not appear on both sides - e.g. Musashi's NBCD of 0 writes nothing);
                // where both wrote it, the function codes must match
                for (auto &x : wv) { auto it = mw.find(x.first);
                    if (mem[x.first] != mmem[x.first]) d += " M" + hex(x.first) + " " + hex(mem[x.first]) + "/" + hex(mmem[x.first]);
                    else if (it != mw.end() && it->second.fc != x.second.fc)
                        d += " FC" + hex(x.first) + " " + std::to_string(x.second.fc) + "/" + std::to_string(it->second.fc); }
                for (auto &x : mw) if (!wv.count(x.first) && mem[x.first] != mmem[x.first])
                    d += " M" + hex(x.first) + " " + hex(mem[x.first]) + "/" + hex(mmem[x.first]);
            }
            char line[200]; snprintf(line, sizeof line, "cmp %ld upc %d IR %04x SR %04x PC %06x | Musashi IR %04x PC %06x", cmp, upc,
                                     top->dbg_ir, msr, top->dbg_pc & 0xffffff, m->last_ir(), s.pc & 0xffffff);
            hist.push_back(line); if (hist.size() > (size_t)(verbose ? 40 : 10)) hist.pop_front();
            // Musashi quirk, not a 68010 behaviour: DIVS of $80000000 by -1 stores 0 with Z = 1, V = 0 (MAME
            // m68k_in.lst divs); the manual and m68ksv: overflow (V = 1, Dn unchanged)
            bool quirk = !d.empty() && (((m->last_ir() & 0xf1c0) == 0x81c0 && (msr & 2) && !(s.sr & 2) && (s.sr & 4)) || uninit);
            if (uninit && !d.empty()) n_divs_dummy++;
            if (quirk && !uninit) n_quirk_divs++;
            if (quirk) g0_pending = true;
            uninit = false;
            // RTE of a format-8 frame that no bus / address error produced (random stack data): the 68010 checks the
            // version number in the frame (data sheet 5.4) and continues from its internal state; Musashi pops the
            // frame and restarts at the stacked PC. Not comparable: resynchronised, counted
            // (every format-8 RTE here is of a snippet's frame - the harness handler never returns from a real fault -
            // so it is reset whether or not the state already differs: the continuation runs from that frame's words)
            bool f8 = prev_ir == 0x4e73 && prev_s && ((mmem[(prev_a7 + 6) & 0xffffff] >> 4) == 8);
            // (m68ksv may then continue from garbage internal state: both CPUs are reset, the stream continues)
            if (f8) { n_rte_f8++; prev_ir = 0; do_reset(); continue; }
            // self-modifying code inside the prefetch window: a write to the words just ahead of the executing
            // instruction; the 68010 has already prefetched them (two-word queue, data sheet 7.1.2), Musashi caches
            // one word (m_pref_data). Not comparable: resynchronised, counted
            // trace after a group-2 exception (TRAP, TRAPV, CHK, divide by zero, RTE format error): data sheet 5.3.8 -
            // the trace exception follows the forced exception (m68ksv); Musashi's m68ki_init_exception cancels it
            bool tr2 = !d.empty() && traced && (((prev_ir & 0xfff0) == 0x4e40) || prev_ir == 0x4e76 ||
                       ((prev_ir & 0xf1c0) == 0x4180) || ((prev_ir & 0xf0c0) == 0x80c0) || prev_ir == 0x4e73);
            if (tr2) { n_tr2++; g0_pending = true; }
            bool smc = false;
            if (loop_poison) loop_poison--;
            if (loop_on) {
                for (uint32_t ad : last_w) if (((ad - loop_lo) & 0xffffff) < 6) loop_poison = 64;
                for (auto &x : wv) if (((x.first - loop_lo) & 0xffffff) < 6) loop_poison = 64;
            }
            if (!d.empty() && !quirk && !f8 && !tr2) {
                for (uint32_t ad : last_w) if (((ad - prev_pc) & 0xffffff) < 12) smc = true;
                for (auto &x : wv) if (((x.first - prev_pc) & 0xffffff) < 12) smc = true;
                if (smc) { n_smc++; g0_pending = true; }
                // loop mode: the three loop words are not fetched again (data sheet 7.1.3); a loop that writes into
                // its own words keeps running the old ones on the 68010 (and m68ksv), Musashi runs the new ones
                // (the rest of such a loop is not comparable: both CPUs are reset, the stream continues)
                if (!smc && loop_poison) { n_smc_loop++; loop_poison = 0; loop_on = false; do_reset(); continue; }
            }
            if (cyc_pend) {
                bool clean = d.empty() && !g0_pending && !pend_int && !traced && !(upc >= UA10_DBL4 && upc <= UA10_DBL1) &&
                             !(cyc_upc >= UA10_DBL4 && cyc_upc <= UA10_DBL1) && cyc_upc != UA_EXC_INT &&
                             !(prev_ir == 0x4e72) && !(lm_seen);
                if (clean) { auto &e = cyc_map[cyc_ir & 0xf1f8]; e.n++; long mk = (n - cyc_t0) / 2;
                             if (mk == cyc_mus) e.ok++; else { e.bad++; e.last_m = mk; e.last_mus = cyc_mus; e.ir = cyc_ir; } }
                cyc_pend = false;
            }
            if (!d.empty()) {
                if (g0_pending) {
                    // group-0 exception: resynchronise Musashi to m68ksv (state and memory written since the comparison)
                    if (!quirk && !f8 && !smc && !tr2) {
                        n_g0++;
                        // what Musashi models of the format-8 frame: SSP after the push, the SR word, format 8
                        uint32_t fb = r[16] & 0xffffff;
                        bool regs_eq = true;
                        for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) regs_eq = false;
                        for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) regs_eq = false;
                        if (r[15] != s.usp) regs_eq = false;
                        if (regs_eq) n_g0_regs_eq++;
                        if (fb < 0x1000 || fb > 0xffffc0) n_g0_romframe++;
                        // jump / branch / return to an odd address: the 68000 / 68010 microcode faults on the target
                        // prefetch inside the jump; Musashi on the next opcode fetch (its next step)
                        // (JSR / BSR: Musashi has pushed the return address first)
                        else if (((s.ssp & 0xffffff) == ((fb + 58) & 0xffffff) || (s.ssp & 0xffffff) == ((fb + 54) & 0xffffff)) && (s.pc & 1)) n_g0_deferred++;
                        // PC-relative operand at an odd address: Musashi reads it unaligned (m68k_read_pcrelative_*),
                        // the manual (and m68ksv): address error
                        // DBcc with an odd target and an expiring count: the microcode prefetches the target before the
                        // count test (MC68010 table 9-15: cc false, count expired 16(3/0)) - address error; Musashi: none
                        else if ((s.ssp & 0xffffff) == ((fb + 58) & 0xffffff) && (prev_ir & 0xf0f8) == 0x50c8) n_g0_dbcc++;
                        else if ((s.ssp & 0xffffff) == ((fb + 58) & 0xffffff) && ((prev_ir & 0x3e) == 0x3a || (prev_ir & 0x0fc0) == 0x0e80 || (prev_ir & 0x0fc0) == 0x0ec0)) n_g0_pcrel++;
                        else if ((s.ssp & 0xffffff) != fb || mem[fb] != mmem[fb] || (mmem[fb + 6] >> 4) != 8 || (mem[fb + 6] >> 4) != 8) {
                            n_g0_frame_bad++;
                            if (verbose) printf("run %d cmp %ld: group-0 frame differs (IR %04x PC %06x): SSP %06x/%06x SR %02x%02x/%02x%02x fmt %02x/%02x\n", run, cmp, prev_ir, prev_pc, fb, s.ssp & 0xffffff,
                                                mem[fb], mem[fb + 1], mmem[fb], mmem[fb + 1], mem[fb + 6], mmem[fb + 6]);
                        }
                        else if (mem[fb + 1] != mmem[fb + 1]) n_g0_ccr++;
                    }
                    if (verbose > 1) printf("run %d cmp %ld: group-0 resync:%s\n", run, cmp, d.c_str());
                    for (auto &x : wv) mmem[x.first] = x.second.v;
                    for (auto &x : m->wlog) for (int b = 0; b < 2; b++) { uint32_t ad = x.addr + b; if (!wv.count(ad)) mmem[ad] = mem[ad]; }
                } else {
                    bad = true; why = d;
                    if (verbose > 2) { int k = 0; for (uint32_t ad = 0; ad < 0x80000 && k < 16; ad++) if (mem[ad] != mmem[ad]) { printf("  memdiff %06x %02x/%02x\n", ad, mem[ad], mmem[ad]); k++; } }
                    break;
                }
            }
            if (d.empty() || g0_pending || first) {
                for (int k = 0; k < 8; k++) { s.d[k] = r[k]; s.a[k] = r[8 + k]; }
                s.usp = r[15]; s.ssp = r[16]; s.a[7] = (msr & 0x2000) ? r[16] : r[15];
                s.sr = msr; s.pc = top->dbg_pc; s.vbr = top->dbg_vbr; s.sfc = top->dbg_sfc; s.dfc = top->dbg_dfc;
                if (first || g0_pending) m->set_state(s);
            }
            first = false; g0_pending = false; traced = false;
            if (!(top->dbg_vbr == 0 || top->dbg_vbr == 0x800 || top->dbg_vbr == 0xc00) || (r[16] & 0xffffff) < 0x1100 || (r[16] & 0xffffff) > 0xfff000) {
                n_vbr_reset++; do_reset(); continue;
            }
            last_w.clear(); for (auto &x : wv) last_w.push_back(x.first);
            prev_pc = top->dbg_pc & 0xffffff;
            prev_ir = top->dbg_ir; prev_s = (msr & 0x2000) != 0; prev_a7 = prev_s ? r[16] : r[15];
            wv.clear(); m->wlog.clear();
            // advance Musashi over what m68ksv dispatches now
            if (upc == UA_EXC_INT) { n_int++; pend_int = true; }
            else {
                int mc = m->step();
                // cycle cross-check (no wait states only): this instruction's clocks, dispatch to dispatch, against
                // Musashi's cycle count for it (m68ki_cycles of the 68010 + its EA / exception additions)
                if (cyc_on) { cyc_pend = true; cyc_ir = top->dbg_ir; cyc_mus = mc; cyc_t0 = n; cyc_upc = upc; }
            }
            if (m->halted()) { n_halt++; do_reset(); }
            cmp++;
        }
        // group-0 entries are not dispatches: mark them when m68ksv enters EXC0 (checked at the next comparison)
        tot_cmp += cmp; tot_clk += (long)(n / 2);
        n_bkpt += m->bkpt_cycles;
        if (bad) {
            fails++;
            printf("run %d seed %u: MISMATCH at comparison %ld:%s\n", run, seed, cmp, why.c_str());
            for (auto &l : hist) printf("   %s\n", l.c_str());
        } else if (verbose) printf("run %d: %ld comparisons equal in %llu clocks\n", run, cmp, (unsigned long long)(n / 2));
        delete top; delete m;
    }
    (void)n_berr; (void)n_exc; (void)berr_p;
    printf("mus010: %d runs, %ld instruction boundaries compared, %ld CPU clocks, %d mismatching runs; group-0 resyncs %ld, "
           "double-fault resets %ld, interrupts %ld, trace exceptions %ld, Musashi BKPT cycles %ld, STOP wake-ups %ld\n",
           runs, tot_cmp, tot_clk, fails, n_g0, n_halt, n_int, n_trace, n_bkpt, n_nmi_wake);
    printf("Musashi DIVS $80000000 / -1 quirk resyncs: %ld; foreign format-8 RTE resyncs: %ld; self-modifying code in the prefetch window: %ld; trace after a group-2 exception: %ld; interrupt vector entry 0 (Musashi uses vector 15): %ld\n", n_quirk_divs, n_rte_f8, n_smc, n_tr2, n_divs_dummy);
    printf("group-0 exceptions: %ld (registers equal to Musashi's after it: %ld; format-8 frame SSP / SR / format code different from Musashi's: %ld; frame in the harness ROM area, not checked: %ld; stacked CCR different (abort point): %ld; odd jump target, Musashi faults one step later: %ld; odd PC-relative operand, Musashi reads it unaligned: %ld; DBcc expiring with an odd target: %ld)\n",
           n_g0, n_g0_regs_eq, n_g0_frame_bad, n_g0_romframe, n_g0_ccr, n_g0_deferred, n_g0_pcrel, n_g0_dbcc);
    if (cyc_on) {
        long tn = 0, tok = 0;
        std::vector<std::pair<long, int>> v;
        for (auto &x : cyc_map) { tn += x.second.n; tok += x.second.ok; if (x.second.bad) v.push_back({x.second.bad, x.first}); }
        std::sort(v.rbegin(), v.rend());
        printf("cycles vs Musashi: %ld instructions, %ld equal; differing opcode groups (IR & f1f8: count differing / total, example IR m68ksv/Musashi):\n", tn, tok);
        for (auto &x : v) { auto &e = cyc_map[x.second]; printf("  %04x %ld/%ld IR %04x %ld/%ld\n", x.second, e.bad, e.n, e.ir, e.last_m, e.last_mus); }
    }
    printf("loop mode: %ld DBcc executions in loop mode (looped instruction -> loop word dispatches); loop writing its own words (no refetch in loop mode): %ld\n", n_loopdb, n_smc_loop);
    printf("resets after VBR left the vector tables or SSP left RAM (random program; degenerate exception loops): %ld\n", n_vbr_reset);
    printf("snippets:"); for (int k = 0; k < 12; k++) printf(" %s %ld,", snip_name[k], n_snip[k]); printf("\n");
    return fails != 0;
}

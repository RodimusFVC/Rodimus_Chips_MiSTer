// Copyright (C) 2026 Rodimus
// mus020: instruction-boundary lockstep of m68ksv (CPU = 68020 / 68021) against MAME's Musashi 68020 / 68EC020
// (verify/musashi, MAME's Musashi compiled unmodified as a C++ model) - the 68020 counterpart of mus010. Same random
// program for both (suite opcodes + extension words from the SingleStepTests pool - their random extension words are
// full-format / scaled 68020 addressing modes here - mixed with 68020 snippets), each CPU with its own 16 MB memory.
// m68ksv's bus is served by a dynamic-sizing memory model: every 64-byte block of the address space is a 32-, 16- or
// 8-bit port (DSACK1 / DSACK0) or a second 32-bit DSACK port (cp5: was STERM, not a 68020 signal), chosen at random per run; read data on the lanes
// the port drives (random data on the others), written bytes taken from the lanes the port reads, by SIZ and A1 / A0
// as a real port decodes them; random wait states. At every m68ksv instruction dispatch (except the one that starts
// trace processing - Musashi takes the trace inside the instruction's step) the states are compared: D0-D7, A0-A6, USP,
// ISP, MSP, SR, PC, VBR, SFC, DFC, CACR, CAAR, and every byte written since the last comparison (value, function code).
//   mus020 [-ec] [-seed N] [-runs N] [-instr N] [-irq] [-w W] [-mix P] [-port 0..4] [-v N] [-cyc] <suite .bin ...>
// Group-0 exceptions (address / bus error) are resynchronised and counted (REPORT.md "Checkpoint 4"): Musashi's
// format-A / B frames are mostly zeros and it aborts at its C++ access point.
#include "Vm68ksv.h"
#include "verilated.h"
#include "musashi_model020.h"
#include "m68ksv_ualabels.h"
#include "winuae020.h"
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
        for (uint32_t k = 4; k < 14; k++) {
            int v = -1;
            for (auto &e : a.ram) if ((e.first & 0xffffff) == pc + k) v = e.second;
            if (v < 0) break;
            ins.push_back((uint8_t)v);
        }
        pool.push_back(ins);
    }
    fclose(f);
}

static uint8_t *mem;                       // m68ksv's memory (16 MB, mirrored over the 32-bit space)
static uint8_t *mmem;                      // Musashi's memory
static const uint32_t AM = 0xffffff;
static const uint32_t STREAM = 0x1000, STREAM_END = 0x40000, HANDLER = 0x400, RESTART = 0x500;
static const uint32_t VBR_ALT[3] = {0x0, 0x800, 0xc00};
static void w16(uint32_t a, uint16_t v) { mem[a & AM] = v >> 8; mem[(a + 1) & AM] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static int mix = 25;
static const int NSNIP = 16;
static long n_snip[NSNIP];
static int snip_max = 12;                  // snippet kinds in use (grows with the implemented 68020 features)
static const char *snip_name[NSNIP] = {"MOVE from CCR", "MOVE from SR", "MOVEC", "MOVEC VBR", "MOVES", "RTD", "BKPT",
                                       "user mode", "RTE frame", "trace on", "MOVEC 020", "Bcc.L / BSR.L", "EXTB / LINK.L",
                                       "CHK.L / TST / CMPI", "M bit", "bit field"};
static int ea_mem(uint16_t &op_ea, std::vector<uint16_t> &ext) {    // a memory-alterable EA with its extension words
    int m = rnd() % 6, r = rnd() % 8;
    switch (m) {
    case 0: op_ea = 0x10 | r; break;
    case 1: op_ea = 0x18 | r; break;
    case 2: op_ea = 0x20 | r; break;
    case 3: op_ea = 0x28 | r; ext.push_back(rnd() & 0xffff); break;              // (d16,An) (any alignment: 68020)
    case 4: op_ea = 0x38; ext.push_back(0x2000 + (rnd() & 0x7fff)); break;
    default: op_ea = 0x39; ext.push_back(0x0000); ext.push_back(0x4000 + (rnd() & 0x7fff)); break;
    }
    return m;
}
static uint32_t put_snippet(uint32_t a) {
    std::vector<uint16_t> w;
    int k = rnd() % snip_max;
    n_snip[k]++;
    uint16_t ea; std::vector<uint16_t> ext;
    switch (k) {
    case 0:
        if (rnd() & 1) w.push_back(0x42c0 | (rnd() % 8));
        else { ea_mem(ea, ext); w.push_back(0x42c0 | ea); for (auto e : ext) w.push_back(e); }
        break;
    case 1:
        if (rnd() & 1) w.push_back(0x40c0 | (rnd() % 8));
        else { ea_mem(ea, ext); w.push_back(0x40c0 | ea); for (auto e : ext) w.push_back(e); }
        break;
    case 2: { // MOVEC to / from SFC, DFC, USP (VBR read only)
        static const uint16_t cr[5] = {0x000, 0x001, 0x800, 0x801, 0x800};
        int dir = rnd() & 1, c = rnd() % 5;
        if (dir && cr[c] == 0x801) c = 0;
        w.push_back(dir ? 0x4e7b : 0x4e7a); w.push_back((rnd() & 0xf000) | cr[c]);
        break; }
    case 3: { // MOVEC Dn,VBR with a vector-table base
        int r = rnd() % 8;
        uint32_t v = VBR_ALT[rnd() % 3];
        w.push_back(0x203c | (r << 9)); w.push_back(v >> 16); w.push_back(v);
        w.push_back(0x4e7b); w.push_back((r << 12) | 0x801);
        break; }
    case 4: { // MOVES
        int sz = rnd() % 3;
        ea_mem(ea, ext);
        w.push_back(0x0e00 | (sz << 6) | ea); w.push_back((rnd() & 0xf000) | ((rnd() & 1) << 11));
        for (auto e : ext) w.push_back(e);
        break; }
    case 5: // PEA (6,PC); RTD #d
        w.push_back(0x487a); w.push_back(0x0006);
        w.push_back(0x4e74); w.push_back((rnd() % 64) * 2 - 32);
        break;
    case 6:   // BKPT #n
        w.push_back(0x4848 | (rnd() % 8));
        break;
    case 7:   // drop to user mode
        if (rnd() & 1) { w.push_back(0x027c); w.push_back(0xdfff); }
        else { w.push_back(0x46fc); w.push_back(0x0000 | (rnd() & 0x071f)); }
        break;
    case 8: { // RTE of a format-0 / format-2 frame built here: [MOVE.L #a,-(A7)]; MOVE.W #fv,-(A7); PEA (n,PC); MOVE.W #sr,-(A7); RTE
        int f2 = rnd() & 1;
        uint16_t fv = (f2 ? 0x2000 : 0) | ((rnd() % 256) << 2);
        uint16_t sr = (rnd() & 0x071f) | ((rnd() % 4) ? 0x2000 : 0) | ((rnd() % 8) ? 0 : 0x8000);
        if (f2) { w.push_back(0x2f3c); w.push_back(rnd()); w.push_back(rnd()); }
        w.push_back(0x3f3c); w.push_back(fv);
        w.push_back(0x487a); w.push_back(0x0008);
        w.push_back(0x3f3c); w.push_back(sr);
        w.push_back(0x4e73);
        break; }
    case 9:   // trace on
        w.push_back(0x007c); w.push_back(0x8000);
        break;
    case 10: { // MOVEC 68020 registers: CACR (E / F, no clear bits: the cache is not modelled byte-exactly), CAAR, MSP, ISP
        static const uint16_t cr[4] = {0x002, 0x802, 0x803, 0x804};
        int dir = rnd() & 1, c = rnd() % 4, r = rnd() % 8;
        if (dir && cr[c] == 0x002) { w.push_back(0x7000 | (r << 9) | (rnd() & 3)); w.push_back(0x4e7b); w.push_back((r << 12) | 0x002); }
        else if (dir && (cr[c] == 0x803 || cr[c] == 0x804)) {     // a stack pointer value in RAM
            w.push_back(0x203c | (r << 9)); w.push_back(0x0000); w.push_back(0x7000 + (rnd() & 0x0ffe));
            w.push_back(0x4e7b); w.push_back((r << 12) | cr[c]);
        } else { w.push_back(dir ? 0x4e7b : 0x4e7a); w.push_back((rnd() & 0xf000) | cr[c]); }
        break; }
    case 11: { // Bcc.L / BSR.L over a few words (BSR.L: the callee returns at once)
        int cc = rnd() % 16;
        if (cc == 1) {   // BSR.L +6: RTS there, continue after it
            w.push_back(0x61ff); w.push_back(0x0000); w.push_back(0x0006);
            w.push_back(0x6002); w.push_back(0x4e75);
        } else {
            w.push_back(0x60ff | (cc << 8)); w.push_back(0x0000); w.push_back(0x0006);
            w.push_back(0x4e71);
        }
        break; }
    case 12:  // EXTB.L / LINK.L / UNLK
        if (rnd() & 1) w.push_back(0x49c0 | (rnd() % 8));
        else { int r = rnd() % 7; w.push_back(0x4808 | r); w.push_back(0xffff); w.push_back(0xfff0 & rnd()); w.push_back(0x4e58 | r); }
        break;
    case 13: { // CHK.L <ea>,Dn (register / immediate bound), TST.x An / #imm / (d16,PC), CMPI.x #,(d16,PC)
        int t = rnd() % 4, sz = rnd() % 3;
        if (t == 0) { w.push_back(0x4100 | ((rnd() % 8) << 9) | (rnd() % 8)); }
        else if (t == 1) { w.push_back(0x413c | ((rnd() % 8) << 9)); w.push_back(rnd() & 0x7fff); w.push_back(rnd()); }
        else if (t == 2) { int m = rnd() % 3;
            if (m == 0 && sz) w.push_back(0x4a08 | (sz << 6) | (rnd() % 8));
            else if (m == 1) { w.push_back(0x4a3c | (sz << 6)); w.push_back(rnd()); if (sz == 2) w.push_back(rnd()); }
            else { w.push_back(0x4a3a | (sz << 6)); w.push_back(rnd() & 0x00fe); } }
        else { w.push_back(0x0c3a | (sz << 6)); w.push_back(rnd()); if (sz == 2) w.push_back(rnd()); w.push_back(rnd() & 0x00fe); }
        break; }
    case 14: { // M bit on / off (MOVE #sr,SR with S = 1)
        w.push_back(0x46fc); w.push_back(0x2000 | (rnd() & 0x171f));
        break; }
    default: { // bit field (cp4b): BFTST / BFEXTU / BFCHG / BFEXTS / BFCLR / BFFFO / BFSET / BFINS on Dn, (An) or abs.W,
               // offset / width immediate or in Dn
        int t = rnd() % 8, m = rnd() % 3, r = rnd() % 8;
        uint16_t ea = m == 0 ? r : m == 1 ? (0x10 | r) : 0x38;
        uint16_t ext = ((rnd() % 8) << 12) | (rnd() & 0x0fff);
        w.push_back(0xe8c0 | (t << 8) | ea); w.push_back(ext);
        if (m == 2) w.push_back(0x2000 + (rnd() & 0x3ffe));
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
    o16(0x46fc); o16(0x2700);                       // MOVE #$2700,SR (M = 0: A7 = ISP)
    o16(0x203c); o16(0x0000); o16(0x6000);          // MOVE.L #$6000,D0
    o16(0x4e7b); o16(0x0803);                       // MOVEC D0,MSP
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
static bool rom_area(uint32_t a) { a &= AM; return a < 0x400 || (a >= 0x800 && a < 0x1000); }
static std::string hex(uint32_t v) { char b[16]; snprintf(b, sizeof b, "%x", v); return b; }
static uint8_t port_of[256];                // per 64-byte block (address bits 13-6): 0 32-bit, 1 16-bit, 2 8-bit, 3 32-bit (cp5: was STERM)

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int only = -1, runs = 1, verbose = 0, every = 16, wmax = 0, port_mode = 4; uint32_t seed = 1; long instr = 20000;
    bool irq = false, ec = false, s_br = false, s_halt = false, s_rst = false;   // cp4b: -br / -halt / -rst stimulus
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-seed")) seed = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-runs")) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-instr")) instr = atol(argv[++i]);
        else if (!strcmp(argv[i], "-irq")) irq = true;
        else if (!strcmp(argv[i], "-ec")) ec = true;
        else if (!strcmp(argv[i], "-br")) s_br = true;
        else if (!strcmp(argv[i], "-halt")) s_halt = true;
        else if (!strcmp(argv[i], "-rst")) s_rst = true;
        else if (!strcmp(argv[i], "-cyc")) cyc_on = true;
        else if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-mix")) mix = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-snip")) snip_max = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-port")) port_mode = atoi(argv[++i]);    // 0-3: one port kind everywhere, 4: mixed
        else if (!strcmp(argv[i], "-v")) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-only")) only = atoi(argv[++i]);
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    if (snip_max > NSNIP) snip_max = NSNIP;
    for (const char *f : files) load_pool(f, every);
    if (pool.empty()) { printf("no instruction pool (give suite .bin files)\n"); return 1; }
    mem = (uint8_t *)malloc(1 << 24); mmem = (uint8_t *)malloc(1 << 24);
    long tot_cmp = 0, tot_clk = 0, n_g0 = 0, n_halt = 0, n_int = 0, n_trace = 0, n_bkpt = 0, n_nmi_wake = 0;
    std::vector<uint8_t> wmap((1 << 24) / 8, 0);     // bytes written since the last reset
    long n_code = 0;
    long n_quirk_divs = 0, n_smc = 0, n_tr2 = 0, n_uninit = 0, n_divs_dummy = 0, n_vbr_reset = 0, n_g0_regs_eq = 0;
    long n_br = 0, n_hlt = 0, n_rstp = 0, n_bg = 0;
    long n_cyc[4] = {0, 0, 0, 0}, n_split = 0, n_rte_bad = 0, n_callm = 0, n_pcodd = 0, n_pcx = 0, n_f79 = 0, n_pk7 = 0, n_rte_fb = 0, n_rte_f1u = 0, n_cpp = 0, n_cpc = 0, n_dvc = 0, n_c2w = 0;
    // 68020 behaviour from WinUAE (2026-11-16): differences from Musashi where m68ksv equals WinUAE's rule (winuae020.h)
    long n_w_divw = 0, n_w_chk = 0, n_w_chk2 = 0, n_w_chk2t = 0, n_w_divl = 0, n_w_pk = 0, n_w_link = 0;
    bool cyc_pend = false; int cyc_ir = 0, cyc_mus = 0, cyc_upc = 0; long cyc_t0 = 0; int fails = 0;
    for (int run = 0; run < runs; run++) {
        std::fill(wmap.begin(), wmap.end(), 0);
        if (only >= 0 && run != only) continue;
        rng = seed * 2654435761u + run * 40503u + 1;
        for (int i = 0; i < 256; i++) port_of[i] = port_mode < 4 ? port_mode : rnd() % 4;
        build_memory();
        memcpy(mmem, mem, 1 << 24);
        Vm68ksv *top = new Vm68ksv;
        top->IPL_n = 7; top->BERR_n = 1; top->BR_n = 1; top->BGACK_n = 1; top->tl_en = 0;
        top->DSACK_n = 3; top->STERM_n = 1; top->AVEC_n = 1; top->CDIS_n = 1;
        mus20_model *m = mus20_model_new(ec);
        m->mem = mmem; m->ro = rom_area;
        m->reset();
        std::map<uint32_t, Wr> wv;
        long cmp = 0; uint64_t n = 0; long hold = 80; bool bad = false;
        int ipl = 0, ipl_hold = 0, wait = 0, iack_av = 0, iack_vec = 0, last_iack = -1, iack_lvl = 0; bool pend_int = false, uninit = false;
        bool wseen = false, in_as = false; uint32_t cyc_a = 0; int cyc_fc = 0, cyc_port = 0; uint32_t junk = 0;
        bool traced = false, prev_s = false; int prev_ir = 0; uint32_t prev_pc = 0, prev_a7 = 0, prev_usp = 0, prev_msp = 0;
        uint32_t prev_r[18] = {0}; uint16_t prev_sr = 0;   // state at the previous comparison (WinUAE-rule classes)
        int prev_rte_fmt = -1; int br_t = 0, halt_t = 0;
        std::vector<uint32_t> last_w;
        bool first = true, g0_pending = false; std::string why; uint64_t last_fin = 0;
        std::deque<std::string> hist;
        auto regs = [&](uint32_t *r) {
            for (int k = 0; k < 18; k++) {
                top->dbg_ra = k; top->cen_p = 0; top->cen_n = 0;
                top->clk = 0; top->eval(); top->clk = 1; top->eval();
                r[k] = top->dbg_rd;
            }
        };
        auto do_reset = [&]() {
            hold = 80; wv.clear(); first = true; g0_pending = false; std::fill(wmap.begin(), wmap.end(), 0);
            w32(4, HANDLER); memcpy(mmem, mem, 1 << 24);
            m->wlog.clear(); m->reset();
        };
        for (; cmp < instr && !bad; ) {
            // -br: bus requests (BR held for a random time; the CPU grants at a cycle boundary and waits while BR is held,
            // no BGACK); -halt: HALT pulses (the CPU stops at the next cycle boundary); -rst: reset pulses (both CPUs reset)
            if (s_br) { if (br_t > 0) br_t--; else if (rnd() % 20000 == 0) { br_t = 20 + rnd() % 400; n_br++; } }
            if (s_halt) { if (halt_t > 0) halt_t--; else if (rnd() % 30000 == 0) { halt_t = 20 + rnd() % 400; n_hlt++; } }
            if (s_rst && hold == 0 && n > 2000 && rnd() % 3000000 == 0) { n_rstp++; do_reset(); }
            top->BR_n = br_t > 0 ? 0 : 1;
            if (!top->BG_n && br_t > 0) n_bg++;
            if (hold > 0) { top->RESET_n_i = 0; top->HALT_n_i = 0; hold--; } else { top->RESET_n_i = 1; top->HALT_n_i = halt_t > 0 ? 0 : 1; }
            uint32_t a = top->A32 & AM;
            uint32_t a32 = top->A32;
            int fc = top->FC;
            bool iack = fc == 7 && (a32 & (ec ? 0x00fffff0u : 0xfffffff0u)) == (ec ? 0x00fffff0u : 0xfffffff0u);   // (68EC020: A23-A0)
            bool bkpt = fc == 7 && (a32 & ~0x1cu) == 0;                 // breakpoint acknowledge (number on A4-A2)
            bool cop = fc == 7 && ((a32 >> 16) & 0xf) == 2;             // coprocessor interface: no coprocessor (BERR)
            if (top->AS_n) {
                in_as = false;
                wait = wmax ? (int)(rnd() % (wmax + 1)) : 0; iack_av = rnd() & 1; iack_vec = 0x40 + (rnd() % 192);
                cyc_port = port_of[(a >> 6) & 255];
                junk = rnd();
            } else if (!in_as) {
                in_as = true; wseen = false; cyc_a = a; cyc_fc = fc; n_cyc[cyc_port]++; if (cop) n_cpc++;
                if (verbose > 3) { char b[96]; snprintf(b, sizeof b, "    bus %08x FC%d %c SIZ%d port%d", a32, fc, top->RW ? 'r' : 'w', top->SIZ, cyc_port);
                    hist.push_back(b); if (hist.size() > 80) hist.pop_front(); }
            }
            int port = (iack || bkpt) ? 0 : cyc_port;
            // read data on the port's lanes
            uint32_t d = junk;
            if (port == 0 || port == 3) d = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
            else if (port == 1) d = (junk & 0xffff) | ((uint32_t)mem[a & ~1u] << 24) | ((uint32_t)mem[a | 1] << 16);
            else d = (junk & 0xffffff) | ((uint32_t)mem[a] << 24);
            bool avec = false;
            if (iack && !top->AS_n) { if (iack_av) avec = true; else d = iack_vec * 0x01010101u; last_iack = iack_av ? -1 : iack_vec; iack_lvl = (a32 >> 1) & 7; }
            top->D32_i = d;
            bool ack = !top->AS_n && wait == 0;
            top->BERR_n = !(ack && cop);
            top->AVEC_n = !(ack && avec);
            // (cp5: the 68020 has no STERM - User's Manual Table 3-2: port 3, formerly STERM, is a second 32-bit DSACK port)
            top->DSACK_n = (!ack || cop || avec) ? 3 : (port == 0 || port == 3) ? 0 : port == 1 ? 1 : 2;
            top->STERM_n = 1;
            if (!top->AS_n && wait > 0 && (n % 4) == 0) wait--;
            if (irq) {
                if (ipl_hold > 0) ipl_hold--;
                else { ipl = (rnd() % 6 == 0) ? (int)(rnd() % 8) : 0; ipl_hold = 40 + rnd() % 800; }
                top->IPL_n = 7 - ipl;
            }
            if (hold == 0 && n - last_fin > 20000 && n - last_fin < 20800) { top->IPL_n = 0; n_nmi_wake += (n - last_fin == 20001); }
            else if (!irq) top->IPL_n = 7;
            // CPU clock = clk / 4 (cp4b: the 68020 build needs two clk or more between CPU edges)
            top->cen_p = (n % 4) == 0; top->cen_n = (n % 4) == 2;
            top->clk = 0; top->eval();
            bool fin = top->dbg_fin;
            top->clk = 1; top->eval();
            n++;
            if (hold > 0 || top->RESET_n_i == 0) { last_fin = n; continue; }
            if (n - last_fin > 800000) { bad = true; char b[96]; snprintf(b, sizeof b, " STALL (no dispatch for 200000 clocks, upc %d)", top->dbg_upc); why = b; break; }
            // m68ksv writes: the bytes the port takes (SIZ, A1 / A0, port width) from its lanes
            a = top->A32 & AM;
            if (!top->AS_n && !top->RW && !top->DS_n && !wseen && !cop && !iack && !bkpt) {
                wseen = true;
                int nb = top->SIZ ? top->SIZ : 4, o = a & 3, kk, l0;
                if (cyc_port == 0 || cyc_port == 3) { kk = std::min(nb, 4 - o); l0 = o; }
                else if (cyc_port == 1) { kk = std::min(nb, 2 - (o & 1)); l0 = o & 1; }
                else { kk = 1; l0 = 0; }
                if (kk < nb) n_split++;
                for (int j = 0; j < kk; j++) {
                    uint32_t ad = (a + j) & AM;
                    uint8_t v = top->D32_o >> (24 - 8 * (l0 + j));
                    if (!rom_area(ad)) { mem[ad] = v; wv[ad] = Wr{v, fc}; }
                }
            }
            if (!top->HALT_n_o) { n_halt++; do_reset(); continue; }
            if (top->dbg_upc == UA_EXC0 || top->dbg_upc == UA_EXC0A) g0_pending = true;
            if (!fin) continue;
            last_fin = n;
            int upc = top->dbg_upc;
            if (upc == UA_EXC_TRACE) { n_trace++; traced = true; continue; }
            if (upc == UA_EXC0 || upc == UA_EXC0A || upc == UA_HALT || upc == UA_HALTA) { g0_pending = true; continue; }
            if (pend_int) {
                if (verbose > 2) printf("cmp %ld: interrupt level %d vector %d (-1 auto)\n", cmp, iack_lvl, last_iack);
                { mus20_state ms; m->get_state(ms); uint32_t va = (ms.vbr + 4 * (last_iack < 0 ? 24 + iack_lvl : last_iack)) & AM;
                  if (!mmem[va] && !mmem[va + 1] && !mmem[va + 2] && !mmem[va + 3]) { n_uninit++; uninit = true; } }
                m->set_irq(iack_lvl); m->iack_vector = last_iack;
                m->step();
                m->set_irq(0); m->iack_vector = -1; pend_int = false;
            }
            uint32_t r[18]; regs(r);
            mus20_state s; m->get_state(s);
            uint16_t msr = top->dbg_sr;
            std::string dd;
            if (!first) {
                for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) dd += " D" + std::to_string(k) + " " + hex(r[k]) + "/" + hex(s.d[k]);
                for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) dd += " A" + std::to_string(k) + " " + hex(r[8 + k]) + "/" + hex(s.a[k]);
                if (r[15] != s.usp) dd += " USP " + hex(r[15]) + "/" + hex(s.usp);
                if (r[16] != s.isp) dd += " ISP " + hex(r[16]) + "/" + hex(s.isp);
                if (r[17] != s.msp) dd += " MSP " + hex(r[17]) + "/" + hex(s.msp);
                if ((msr & 0xf71f) != (s.sr & 0xf71f)) dd += " SR " + hex(msr) + "/" + hex(s.sr);
                if (top->dbg_pc != s.pc) dd += " PC " + hex(top->dbg_pc) + "/" + hex(s.pc);
                if (top->dbg_vbr != s.vbr) dd += " VBR " + hex(top->dbg_vbr) + "/" + hex(s.vbr);
                if (top->dbg_sfc != s.sfc) dd += " SFC " + hex(top->dbg_sfc) + "/" + hex(s.sfc);
                if (top->dbg_dfc != s.dfc) dd += " DFC " + hex(top->dbg_dfc) + "/" + hex(s.dfc);
                if (top->dbg_cacr != (s.cacr & 3)) dd += " CACR " + hex(top->dbg_cacr) + "/" + hex(s.cacr);
                if (top->dbg_caar != s.caar) dd += " CAAR " + hex(top->dbg_caar) + "/" + hex(s.caar);
                std::map<uint32_t, Wr> mw;
                for (auto &x : m->wlog) mw[x.addr] = Wr{x.data, x.fc};
                for (auto &x : wv) { auto it = mw.find(x.first);
                    if (mem[x.first] != mmem[x.first]) dd += " M" + hex(x.first) + " " + hex(mem[x.first]) + "/" + hex(mmem[x.first]);
                    else if (it != mw.end() && it->second.fc != x.second.fc)
                        dd += " FC" + hex(x.first) + " " + std::to_string(x.second.fc) + "/" + std::to_string(it->second.fc); }
                for (auto &x : mw) if (!wv.count(x.first) && mem[x.first] != mmem[x.first])
                    dd += " M" + hex(x.first) + " " + hex(mem[x.first]) + "/" + hex(mmem[x.first]);
            }
            char line[200]; snprintf(line, sizeof line, "cmp %ld upc %d IR %04x SR %04x PC %08x | Musashi IR %04x PC %08x", cmp, upc,
                                     top->dbg_ir, msr, top->dbg_pc, m->last_ir(), s.pc);
            hist.push_back(line); if (hist.size() > (size_t)(verbose ? 40 : 12)) hist.pop_front();
            // Musashi quirks (as mus010): DIVS $80000000 / -1; interrupt vector entry 0 -> vector 15
            bool quirk = !dd.empty() && (((m->last_ir() & 0xf1c0) == 0x81c0 && (msr & 2) && !(s.sr & 2) && (s.sr & 4)) || uninit);
            if (uninit && !dd.empty()) n_divs_dummy++;
            if (quirk && !uninit) n_quirk_divs++;
            if (quirk) g0_pending = true;
            uninit = false;
            // trace after a group-2 exception (TRAP, TRAPV, CHK, divide by zero, RTE format error): the trace follows the
            // exception (m68ksv, as the 68010 data sheet 5.3.8); Musashi's m68ki_init_exception cancels it
            bool tr2 = !dd.empty() && traced && (((prev_ir & 0xfff0) == 0x4e40) || prev_ir == 0x4e76 ||
                       ((prev_ir & 0xf1c0) == 0x4180) || ((prev_ir & 0xf1c0) == 0x4100) || ((prev_ir & 0xf0c0) == 0x80c0) || prev_ir == 0x4e73 ||
                       ((prev_ir & 0xf9c0) == 0x00c0) || ((prev_ir & 0xf0f8) == 0x50f8) || ((prev_ir & 0xffc0) == 0x4c40));
            if (tr2) { n_tr2++; g0_pending = true; }
            // CALLM / RTM (06C0-06FF): Musashi does not model them (m68k_in.lst callm / rtm: log only; CALLM even reads
            // its EA before the argument-count word); m68ksv: see REPORT.md. Not comparable: resynchronised, counted
            bool callm = !dd.empty() && !tr2 && (prev_ir & 0xffc0) == 0x06c0;
            if (callm) { n_callm++; g0_pending = true; }
            // word operand at an odd PC-relative address (legal on the 68020): Musashi's m68k_read_pcrelative_16 returns
            // (word(a - 1) << 8) | (word(a + 1) >> 8) without masking bits 23-16, which then leak into the operation
            // (DIVU / ADD flags, ...). (d16,PC): the address is checked; (d8,PC,Xn): counted on the mode alone
            bool pcodd = false;
            if (!dd.empty() && !tr2 && !callm && (prev_ir & 0x3f) == 0x3a) {
                uint32_t ea = prev_pc + 2 + (int16_t)((mmem[(prev_pc + 2) & AM] << 8) | mmem[(prev_pc + 3) & AM]);
                pcodd = ea & 1;
            }
            bool pcx = !dd.empty() && !tr2 && !callm && (prev_ir & 0x3f) == 0x3b;
            // RTE of a format-7 frame (68040 access error: Musashi pops it, the 68020 takes a format error) or a format-9
            // frame (68020 coprocessor mid-instruction: m68ksv returns from it, Musashi takes a format error)
            bool f79 = false;
            int rte_fmt = prev_ir == 0x4e73 ? prev_rte_fmt : -1;   // (from the memory before the RTE)
            if (!dd.empty() && !tr2 && !callm) f79 = rte_fmt == 7 || rte_fmt == 9;
            if (f79) { n_f79++; g0_pending = true; callm = true; }
            // PACK -(Ay),-(A7) with Ay != A7 (8F48-8F4E): Musashi's handler for this form assembles and packs the two
            // bytes differently from its other PACK forms and from the PRM (m68k_in.lst 8f48 pack)
            bool pk7 = !dd.empty() && !tr2 && !callm && (prev_ir & 0xfff8) == 0x8f48 && (prev_ir & 7) != 7;
            if (pk7) { n_pk7++; g0_pending = true; callm = true; }
            // cpSAVE / cpRESTORE (F-line types 4 / 5) in user mode: privileged on the 68020 (privilege violation, m68ksv);
            // Musashi without an FPU takes the F-line exception first (vector offset in the frame differs)
            bool cpp = !dd.empty() && !tr2 && !callm && (prev_ir & 0xf000) == 0xf000 && (((prev_ir >> 6) & 7) == 4 ||
                       ((prev_ir >> 6) & 7) == 5) && !prev_s;
            if (cpp) { n_cpp++; g0_pending = true; callm = true; }
            // ---- 68020 behaviour from WinUAE (2026-11-16, REPORT.md "68020 behaviour from WinUAE"): m68ksv follows WinUAE's
            // 68020 rules (winuae020.h) where Musashi differs. Classified only when m68ksv's result equals the rule computed
            // from the operands (the previous comparison's registers; a memory operand from Musashi's read log of this
            // instruction, which must agree with m68ksv's registers) and nothing else differs
            auto rd32m = [&](uint32_t a) { return ((uint32_t)mem[a & AM] << 24) | ((uint32_t)mem[(a + 1) & AM] << 16) | (mem[(a + 2) & AM] << 8) | mem[(a + 3) & AM]; };
            auto rd16p = [&](uint32_t a) { return (uint32_t)((mmem[a & AM] << 8) | mmem[(a + 1) & AM]); };
            auto pregv = [&](int k) { return k == 15 ? prev_a7 : prev_r[k]; };       // D0-D7, A0-A6, active A7 (0-15)
            // Musashi's data reads of this instruction without an exception's vector fetch (the last read(s): the new PC)
            std::vector<mus20_read> dreads;
            bool pcrel = ((prev_ir >> 3) & 7) == 7 && ((prev_ir & 7) == 2 || (prev_ir & 7) == 3);   // operand in program space
            for (auto &x : m->rlog)
                if ((x.fc & 3) == 1 || (pcrel && (x.fc & 3) == 2 && ((x.addr - prev_pc) & AM) >= 22)) dreads.push_back(x);
            if (!dreads.empty() && dreads.back().size == 4 && dreads.back().data == s.pc && ((dreads.back().addr - s.vbr) & AM) < 0x400)
                dreads.pop_back();
            else if (dreads.size() >= 2 && dreads.back().size == 2 && dreads[dreads.size() - 2].size == 2 &&
                     ((dreads[dreads.size() - 2].data << 16) | dreads.back().data) == s.pc && ((dreads.back().addr - s.vbr) & AM) < 0x400)
                { dreads.pop_back(); dreads.pop_back(); }
            // the instruction's source operand (size 1 / 2 / 4): Dn, #imm after `ext` extension words, else the last data read(s)
            auto srcop = [&](int size, int ext, uint32_t &v) -> bool {
                int md = (prev_ir >> 3) & 7, rg = prev_ir & 7;
                uint32_t mk = size == 4 ? 0xffffffffu : size == 2 ? 0xffffu : 0xffu;
                if (md == 0) { v = prev_r[rg] & mk; return true; }
                if (md == 1) return false;
                if (md == 7 && rg == 4) {
                    uint32_t a = prev_pc + 2 + 2 * ext;
                    v = size == 4 ? (rd16p(a) << 16) | rd16p(a + 2) : rd16p(a) & mk; return true;
                }
                if (md == 7 && rg == 2) {                                  // (d16,PC): the operand address directly
                    uint32_t dp = prev_pc + 2 + 2 * ext, a = dp + (int16_t)rd16p(dp);
                    v = 0; for (int b = 0; b < size; b++) v = (v << 8) | mmem[(a + b) & AM]; return true;
                }
                std::map<uint32_t, uint8_t> bm; uint32_t end = 0; bool any = false;
                for (auto &x : dreads) {
                    for (int b = 0; b < x.size; b++) bm[(x.addr + b) & AM] = x.data >> (8 * (x.size - 1 - b));
                    end = x.addr + x.size; any = true;
                }
                if (!any) return false;
                v = 0;
                for (int b = 0; b < size; b++) { auto it = bm.find((end - size + b) & AM); if (it == bm.end()) return false; v = (v << 8) | it->second; }
                return true;
            };
            // nothing but the CCR (and the byte at `okm`, e.g. the stacked SR's low byte of a trap frame) differs
            auto only_ccr = [&](long okm) -> bool {
                for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) return false;
                for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) return false;
                if (r[15] != s.usp || r[16] != s.isp || r[17] != s.msp || top->dbg_pc != s.pc || ((msr ^ s.sr) & 0xf700)) return false;
                for (auto &x : wv) if (mem[x.first] != mmem[x.first] && (long)x.first != okm) return false;
                for (auto &x : m->wlog) if (mem[x.addr] != mmem[x.addr] && (long)x.addr != okm) return false;
                return true;
            };
            uint32_t sp_now = (msr & 0x2000) ? ((msr & 0x1000) ? r[17] : r[16]) : r[15];
            bool w_cls = false;
            if (!dd.empty() && !tr2 && !callm && !quirk) {
                int pccr = prev_sr & 0x1f, ec;
                if ((prev_ir & 0xf0c0) == 0x80c0 && ((prev_ir >> 3) & 7) != 1) {                 // DIVU.W / DIVS.W overflow
                    uint32_t dv, d0; bool sg = prev_ir & 0x100;
                    if (srcop(2, 0, dv) && w_divw(sg, prev_r[(prev_ir >> 9) & 7], dv, pccr, ec, d0) && (ec & 2) &&
                        (msr & 0x1f) == ec && only_ccr(-1)) { n_w_divw++; w_cls = true; }
                }
                if ((prev_ir & 0xf140) == 0x4100 && ((prev_ir >> 3) & 7) != 1) {                 // CHK.W (4180) / CHK.L (4100)
                    bool lg = !(prev_ir & 0x80); uint32_t bd;
                    if (srcop(lg ? 4 : 2, 0, bd)) {
                        bool tr = w_chk(lg, prev_r[(prev_ir >> 9) & 7], bd, pccr, ec);
                        if ((msr & 0x1f) == ec && only_ccr(tr ? (long)((sp_now + 1) & AM) : -1)) { n_w_chk++; w_cls = true; }
                    }
                }
                if ((prev_ir & 0xf9c0) == 0x00c0 && ((prev_ir >> 9) & 3) != 3) {                 // CHK2 / CMP2
                    int sz = (prev_ir >> 9) & 3, nb = 1 << sz; uint32_t ext = rd16p(prev_pc + 2);
                    std::map<uint32_t, uint8_t> bm; uint32_t end = 0; bool any = false;
                    for (auto &x : dreads) {
                        for (int b = 0; b < x.size; b++) bm[(x.addr + b) & AM] = x.data >> (8 * (x.size - 1 - b));
                        end = x.addr + x.size; any = true;
                    }
                    uint32_t lo = 0, up = 0; bool okb = any;
                    if ((prev_ir & 0x3f) == 0x3a) {                             // (d16,PC): the bounds' address directly
                        uint32_t dp = prev_pc + 4, a = dp + (int16_t)rd16p(dp); okb = true;
                        for (int b = 0; b < nb; b++) { lo = (lo << 8) | mmem[(a + b) & AM]; up = (up << 8) | mmem[(a + nb + b) & AM]; }
                    } else
                    for (int b = 0; b < nb && okb; b++) {
                        auto a = bm.find((end - 2 * nb + b) & AM), u = bm.find((end - nb + b) & AM);
                        if (a == bm.end() || u == bm.end()) okb = false; else { lo = (lo << 8) | a->second; up = (up << 8) | u->second; }
                    }
                    if (okb) {
                        auto sx = [&](uint32_t v) -> int32_t { return sz == 2 ? (int32_t)v : sz == 1 ? (int16_t)v : (int8_t)v; };
                        int rn = (ext >> 12) & 15; uint32_t rv = pregv(rn);
                        int32_t val = rn >= 8 ? (int32_t)rv : sx(rv);
                        int c = w_chk2(sx(lo), sx(up), val, pccr, ec);
                        bool etrap = c && (ext & 0x800);
                        uint32_t h6 = rd32m(top->dbg_vbr + 0x18);
                        bool mtrap = top->dbg_pc == h6 && (msr & 0x2000), strap = s.pc == h6;
                        if ((msr & 0x1f) == ec && etrap == mtrap) {
                            if (mtrap == strap) { if (only_ccr(mtrap ? (long)((sp_now + 1) & AM) : -1)) { n_w_chk2++; w_cls = true; } }
                            else { n_w_chk2t++; w_cls = true; }          // the trap decision differs (lower > upper): resync
                        }
                    }
                }
                if ((prev_ir & 0xffc0) == 0x4c40 && ((prev_ir >> 3) & 7) != 1) {                 // DIV.L overflow
                    uint32_t ext = rd16p(prev_pc + 2), dv;
                    if (srcop(4, 1, dv) && w_divl(ext, prev_r[(ext >> 12) & 7], prev_r[ext & 7], dv, pccr, ec) &&
                        (msr & 0x1f) == ec && only_ccr(-1)) { n_w_divl++; w_cls = true; }
                }
                // PACK -(A7),-(Ax) / UNPK -(Ay),-(A7): the two-byte side moves A7 by 2 (Musashi: 4)
                if ((prev_ir & 0xf1ff) == 0x814f || (prev_ir & 0xfff8) == 0x8f88) {
                    int ry = prev_ir & 7, rx = (prev_ir >> 9) & 7; uint32_t adj = rd16p(prev_pc + 2);
                    uint32_t ay = pregv(8 + ry), ax = pregv(8 + rx), wa; uint8_t wb[2]; int nw;
                    bool pack = (prev_ir & 0x1c0) == 0x140;
                    if (pack) {
                        ay -= 2; uint32_t v = ((mem[ay & AM] << 8) | mem[(ay + 1) & AM]) + adj;
                        if (rx == ry) ax = ay;
                        ax -= (rx == 7) ? 2 : 1; wa = ax; wb[0] = ((v >> 4) & 0xf0) | (v & 0xf); nw = 1;
                    } else {
                        ay -= (ry == 7) ? 2 : 1; uint32_t b = mem[ay & AM], v = (((b << 4) & 0xf00) | (b & 0xf)) + adj;
                        if (rx == ry) ax = ay;
                        ax -= 2; wa = ax; wb[0] = v >> 8; wb[1] = v; nw = 2;
                    }
                    uint32_t gy = ry == 7 ? sp_now : r[8 + ry], gx = rx == 7 ? sp_now : r[8 + rx];
                    bool ok = gy == (rx == ry ? ax : ay) && gx == ax;
                    for (int b = 0; b < nw; b++) if (!rom_area((wa + b) & AM) && mem[(wa + b) & AM] != wb[b]) ok = false;   // (ROM: not written)
                    for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) ok = false;
                    if (top->dbg_pc != s.pc || ((msr ^ s.sr) & 0xf71f)) ok = false;
                    if (ok) { n_w_pk++; w_cls = true; }
                }
                // LINK A7 / LINK.L A7: the old A7 is pushed (Musashi: the decremented one)
                if (prev_ir == 0x4e57 || prev_ir == 0x480f) {
                    bool ok = rd32m(prev_a7 - 4) == prev_a7;
                    for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) ok = false;
                    for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) ok = false;
                    if (top->dbg_pc != s.pc || ((msr ^ s.sr) & 0xf71f) || sp_now != s.a[7]) ok = false;
                    if (ok) { n_w_link++; w_cls = true; }
                }
            }
            if (w_cls) { g0_pending = true; callm = true; }
            // DIV.L overflow: the PRM clears C ("always cleared"); Musashi leaves it (m68k_in.lst divl: only V set)
            bool dvc = !dd.empty() && !tr2 && !callm && (prev_ir & 0xffc0) == 0x4c40 && (msr & 2) && ((msr ^ s.sr) & 0xffff) == 1;
            if (dvc) { n_dvc++; g0_pending = true; callm = true; }
            // CAS2.W with a failing compare: Musashi sign-extends the loaded word into Dc when its Rn is an address
            // register (m68k_in.lst cas2 w: BIT_1F / BIT_F); m68ksv (PRM: word operation) replaces Dc's low word only
            bool c2w = !dd.empty() && !tr2 && !callm && prev_ir == 0x0cfc;
            if (c2w) {
                for (int k = 0; k < 8; k++) if (r[k] != s.d[k] && (r[k] & 0xffff) != (s.d[k] & 0xffff)) c2w = false;
                for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) c2w = false;
                if ((msr & 0xf71f) != (s.sr & 0xf71f) || top->dbg_pc != s.pc) c2w = false;
            }
            if (c2w) { n_c2w++; g0_pending = true; callm = true; }
            // RTE of a format-B frame no bus / address error produced (the harness handler never returns from a real
            // fault): m68ksv checks the frame's version word and takes a format error on a foreign frame (as the
            // 68010 / format 8); Musashi pops it and returns to the stacked PC. Not comparable: both CPUs are reset
            bool fb = !tr2 && !callm && rte_fmt == 0xb;
            if (fb) { n_rte_fb++; prev_ir = 0; do_reset(); continue; }
            // RTE through a throwaway frame whose SR has S clear (the next frame on the user stack): no defined 68020
            // behaviour (the PRM describes throwaway frames only with S set); Musashi and m68ksv differ. Reset both
            bool f1u = !tr2 && !callm && rte_fmt == 0x10;
            if (f1u) { n_rte_f1u++; prev_ir = 0; do_reset(); continue; }
            if (pcodd) { n_pcodd++; g0_pending = true; }
            if (pcx) { n_pcx++; g0_pending = true; }
            callm = callm || pcodd || pcx;
            // self-modified code under the instruction cache / prefetch: the instruction's bytes (up to 24 from its PC)
            // were written since the last reset, so each CPU may run a different (stale or fresh) copy: the 68020
            // cache is not updated by writes, and m68ksv's line reads / prefetch fall at other times than Musashi's
            // (fill at its one-word prefetch). Not comparable: both CPUs reset (which clears both caches)
            for (auto &x : wv) wmap[(x.first & AM) >> 3] |= 1 << (x.first & 7);
            if (!dd.empty() && !quirk && !tr2 && !callm) {
                bool cw = false;
                for (uint32_t k = 0; k < 24; k++) { uint32_t ad = (prev_pc + k) & AM; if (wmap[ad >> 3] & (1 << (ad & 7))) cw = true; }
                if (cw) { n_code++; prev_ir = 0; do_reset(); continue; }
            }
            bool smc = false;
            if (!dd.empty() && !quirk && !tr2 && !callm) {
                for (uint32_t ad : last_w) if (((ad - prev_pc) & AM) < 12) smc = true;
                for (auto &x : wv) if (((x.first - prev_pc) & AM) < 12) smc = true;
                if (smc) { n_smc++; g0_pending = true; }
            }
            if (cyc_pend) {
                bool clean = dd.empty() && !g0_pending && !pend_int && !traced && cyc_upc != UA_EXC_INT && !(prev_ir == 0x4e72);
                if (clean) { auto &e = cyc_map[cyc_ir & 0xf1f8]; e.n++; long mk = (n - cyc_t0) / 4;
                             if (mk == cyc_mus) e.ok++; else { e.bad++; e.last_m = mk; e.last_mus = cyc_mus; e.ir = cyc_ir; } }
                cyc_pend = false;
            }
            if (!dd.empty()) {
                if (g0_pending) {
                    if (!quirk && !smc && !tr2 && !callm) {
                        n_g0++;
                        bool regs_eq = true;
                        for (int k = 0; k < 8; k++) if (r[k] != s.d[k]) regs_eq = false;
                        for (int k = 0; k < 7; k++) if (r[8 + k] != s.a[k]) regs_eq = false;
                        if (regs_eq) n_g0_regs_eq++;
                    }
                    if (verbose > 1) printf("run %d cmp %ld: group-0 resync:%s\n", run, cmp, dd.c_str());
                    for (auto &x : wv) mmem[x.first] = x.second.v;
                    for (auto &x : m->wlog) if (!wv.count(x.addr)) mmem[x.addr] = mem[x.addr];
                } else {
                    bad = true; why = dd;
                    break;
                }
            }
            if (dd.empty() || g0_pending || first) {
                for (int k = 0; k < 8; k++) { s.d[k] = r[k]; s.a[k] = r[8 + k]; }
                s.usp = r[15]; s.isp = r[16]; s.msp = r[17];
                s.a[7] = (msr & 0x2000) ? ((msr & 0x1000) ? r[17] : r[16]) : r[15];
                s.sr = msr; s.pc = top->dbg_pc; s.vbr = top->dbg_vbr; s.sfc = top->dbg_sfc; s.dfc = top->dbg_dfc;
                s.cacr = top->dbg_cacr; s.caar = top->dbg_caar;
                if (first || g0_pending) m->set_state(s);
            }
            first = false; g0_pending = false; traced = false;
            uint32_t sp_act = (msr & 0x2000) ? ((msr & 0x1000) ? r[17] : r[16]) : r[15];
            bool msp_bad = (msr & 0x1000) && ((r[17] & AM) < 0x1100 || (r[17] & AM) > 0xfff000);   // M set: MSP in RAM
            if (!(top->dbg_vbr == 0 || top->dbg_vbr == 0x800 || top->dbg_vbr == 0xc00) || msp_bad ||
                (r[16] & AM) < 0x1100 || (r[16] & AM) > 0xfff000) {
                n_vbr_reset++; do_reset(); continue;
            }
            last_w.clear(); for (auto &x : wv) last_w.push_back(x.first);
            prev_pc = top->dbg_pc & AM;
            prev_ir = top->dbg_ir;
            prev_s = (msr & 0x2000) != 0; prev_a7 = sp_act; prev_usp = r[15]; prev_msp = r[17];
            for (int k = 0; k < 18; k++) prev_r[k] = r[k]; prev_sr = msr;
            prev_rte_fmt = -1;
            if (prev_ir == 0x4e73 && prev_s) {      // RTE: format of the frame it returns through (after throwaway
                uint32_t fa = prev_a7;              // frames; 0x10 = a throwaway frame with S clear in its SR)
                for (int lp = 0; lp < 4 && (mmem[(fa + 6) & AM] >> 4) == 1 && prev_rte_fmt < 0; lp++) {
                    uint16_t tsr = (mmem[fa & AM] << 8) | mmem[(fa + 1) & AM];
                    if (!(tsr & 0x2000)) prev_rte_fmt = 0x10;
                    fa = (tsr & 0x1000) ? prev_msp : fa + 8;
                }
                if (prev_rte_fmt < 0) prev_rte_fmt = mmem[(fa + 6) & AM] >> 4;
            }
            wv.clear(); m->wlog.clear();
            if (upc == UA_EXC_INT) { n_int++; pend_int = true; }
            else {
                int mc = m->step();
                if (cyc_on) { cyc_pend = true; cyc_ir = top->dbg_ir; cyc_mus = mc; cyc_t0 = n; cyc_upc = upc; }
            }
            if (m->halted()) { n_halt++; do_reset(); }
            cmp++;
        }
        tot_cmp += cmp; tot_clk += (long)(n / 4);
        n_bkpt += m->bkpt_cycles;
        if (bad) {
            fails++;
            printf("run %d seed %u: MISMATCH at comparison %ld:%s\n", run, seed, cmp, why.c_str());
            for (auto &l : hist) printf("   %s\n", l.c_str());
        } else if (verbose) printf("run %d: %ld comparisons equal in %llu clocks\n", run, cmp, (unsigned long long)(n / 4));
        delete top; delete m;
    }
    (void)n_rte_bad;
    printf("mus020%s: %d runs, %ld instruction boundaries compared, %ld CPU clocks, %d mismatching runs; group-0 resyncs %ld "
           "(registers equal after it %ld), double-fault resets %ld, interrupts %ld, trace exceptions %ld, Musashi BKPT cycles %ld, "
           "STOP wake-ups %ld\n", ec ? " (68EC020)" : "", runs, tot_cmp, tot_clk, fails, n_g0, n_g0_regs_eq, n_halt, n_int, n_trace, n_bkpt, n_nmi_wake);
    printf("bus cycles by port: 32-bit %ld, 16-bit %ld, 8-bit %ld, 32b %ld; write cycles split by the port %ld\n",
           n_cyc[0], n_cyc[1], n_cyc[2], n_cyc[3], n_split);
    printf("Musashi DIVS $80000000 / -1 quirk resyncs: %ld; self-modifying code in the prefetch window: %ld; trace after a group-2 exception: %ld; interrupt vector entry 0: %ld; CALLM / RTM (not in Musashi): %ld\n",
           n_quirk_divs, n_smc, n_tr2, n_divs_dummy, n_callm);
    printf("Musashi odd PC-relative word read (unmasked): (d16,PC) at an odd address %ld, (d8,PC,Xn) differences %ld; RTE of a format-7 / 9 frame: %ld; PACK -(Ay),-(A7): %ld; foreign format-B RTE (reset): %ld; throwaway frame with S clear (reset): %ld\n", n_pcodd, n_pcx, n_f79, n_pk7, n_rte_fb, n_rte_f1u);
    printf("self-modified code under the cache / prefetch (reset): %ld\n", n_code);
    printf("coprocessor interface cycles (answered by BERR): %ld; cpSAVE / cpRESTORE in user mode (privilege violation vs Musashi's F-line): %ld\n", n_cpc, n_cpp);
    printf("DIV.L overflow C (PRM cleared, Musashi kept): %ld; CAS2.W failing, Dc upper word (Musashi sign-extends for An): %ld\n", n_dvc, n_c2w);
    printf("WinUAE 68020 rules (m68ksv = WinUAE, Musashi differs): DIVU.W / DIVS.W overflow flags %ld; CHK flags %ld; CHK2 / CMP2 flags %ld, "
           "trap decision (lower > upper) %ld; DIV.L overflow flags %ld; PACK / UNPK -(A7) word side %ld; LINK A7 %ld\n",
           n_w_divw, n_w_chk, n_w_chk2, n_w_chk2t, n_w_divl, n_w_pk, n_w_link);
    if (cyc_on) {
        long tn = 0, tok = 0;
        std::vector<std::pair<long, int>> v;
        for (auto &x : cyc_map) { tn += x.second.n; tok += x.second.ok; if (x.second.bad) v.push_back({x.second.bad, x.first}); }
        std::sort(v.rbegin(), v.rend());
        printf("cycles vs Musashi: %ld instructions, %ld equal; differing opcode groups (IR & f1f8: count differing / total, example IR m68ksv/Musashi):\n", tn, tok);
        int shown = 0;
        for (auto &x : v) { auto &e = cyc_map[x.second]; printf("  %04x %ld/%ld IR %04x %ld/%ld\n", x.second, e.bad, e.n, e.ir, e.last_m, e.last_mus); if (++shown > 60) break; }
    }
    printf("resets after VBR left the vector tables or SSP left RAM: %ld\n", n_vbr_reset);
    if (s_br || s_halt || s_rst) printf("stimulus: bus requests %ld (clocks granted %ld), HALT pulses %ld, reset pulses %ld\n", n_br, n_bg, n_hlt, n_rstp);
    printf("snippets:"); for (int k = 0; k < snip_max; k++) printf(" %s %ld,", snip_name[k], n_snip[k]); printf("\n");
    return fails != 0;
}

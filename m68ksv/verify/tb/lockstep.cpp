// Copyright (C) 2026 Rodimus
// lockstep: m68ksv (CPU = 68000) against fx68k, both Verilated (5.052) into one binary, fed the same inputs every
// phase; every output pin compared after every phase enable.
//   lockstep [-seed N] [-runs N] [-ticks N] [-w W] [-irq] [-berr P] [-br] [-halt] [-rst] [-vpa] [-v] <suite .bin ...>
// Per run: random memory = a 256-entry vector table (all to a recovery handler), the handler, and a random stream of
// instructions copied from the SingleStepTests suite files given (every opcode / mode the suite covers, with its
// extension words); both CPUs are reset together and run for -ticks phases. Stimulus (computed from fx68k's outputs,
// applied to both):
//   -w W     0..W wait states per cycle (DTACK delayed by up to W clocks)     -vpa  6800 cycles (VPA) at F00000-F0FFFF
//   -irq     random IPL changes; IACK answered by autovector (VPA), vector number (DTACK) or spurious (BERR)
//   -berr P  BERR instead of DTACK on 1 / P of the cycles                    -br   random BR / BGACK (bus arbitration)
//   -halt    random HALT pulses                                             -rst  random reset (RESET + HALT) pulses
// Compared pins: AS UDS LDS RW FC E VMA BG RESET_o HALT_o every phase; A while fx68k drives an address (its addrOe,
// S1 to the end of the cycle); D_o while fx68k drives the data bus (its dataOe). A run stops at its first mismatch.
// State probes (environment variables, the CPUs being in step; DESIGN.md 5):
//   PCTRACE=1   fx68k PC-register loads against m68ksv's micro-words ("P" lines, for verify/tools/pcderive.py)
//   PC68CHK=1   m68ksv's pc68 against fx68k's PC register at every point a bus error can be taken (PC68V=N: show N)
//   ABORTCHK=1  registers and CCR against fx68k at every such point ("AB" lines: what a bus error there would expose)
//   WRTRACE=1   register / CCR write timeline of both CPUs ("X" lines);  AECHK=1  address-error PC against pc68
//   CCRTRACE=1  CCR changes of both CPUs
#include "Vfx68k.h"
#include "Vfx68k___024root.h"
#include "Vm68ksv.h"
#include "Vm68ksv___024root.h"
#include "verilated.h"
#include "m68ksv_ualabels.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <deque>

static uint8_t *mem;
static Vfx68k *fx;
static Vm68ksv *mv;
static uint32_t rng = 1;
static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }

// instruction pool from the suite: opcode + extension words (the test's initial prefetch + RAM after it)
static std::vector<std::vector<uint8_t>> pool;
static std::vector<int> pool_cls;                 // suite file (instruction class) of each pool entry
static std::vector<std::string> cls_name;
static std::vector<int16_t> cls_at;               // stream address -> class of the instruction placed there (-1: none)
static std::vector<int16_t> cls_op(65536, -1);    // opcode -> class (every test of every suite file given)
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
        cls_op[a.pf[0]] = (int16_t)cls_name.size();
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
        pool_cls.push_back((int)cls_name.size());
    }
    fclose(f);
    std::string b = fn; b = b.substr(b.rfind('/') + 1); b = b.substr(0, b.rfind('.'));
    cls_name.push_back(b);
}

static const uint32_t STREAM = 0x1000, STREAM_END = 0x40000, HANDLER = 0x400, RESTART = 0x500;
static void w16(uint32_t a, uint16_t v) { mem[a & 0xffffff] = v >> 8; mem[(a + 1) & 0xffffff] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static void build_memory() {
    for (uint32_t a = 0; a < (1u << 24); a += 4) { uint32_t v = rnd(); memcpy(mem + a, &v, 4); }
    w32(0, 0x8000); w32(4, STREAM);
    for (int v = 2; v < 256; v++) w32(v * 4, HANDLER);
    // handler: SR = 2700, SSP = 8000, restart pointer += 0x46 (kept in the stream area), jump there
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
    if (getenv("TRAPVTEST")) {
        // directed: ADDA.L overflowing internally, CCR V = 0, then TRAPV (MAME m68008 traps on the ALU status)
        p = STREAM;
        o16(0x2a3c); o16(0x7fff); o16(0xffff);      // MOVE.L #$7FFFFFFF,D5
        o16(0x2c7c); o16(0x0000); o16(0x0001);      // MOVEA.L #1,A6
        o16(0x44fc); o16(0x0000);                   // MOVE #0,CCR
        o16(0xddc5);                                // ADDA.L D5,A6
        o16(0x4e76);                                // TRAPV
        o16(0x7e55);                                // MOVEQ #$55,D7 (reached when TRAPV does not trap)
        o16(0x60fe);                                // BRA *
        return;
    }
    for (uint32_t a = STREAM; a < STREAM_END - 16;) {
        size_t pi = rnd() % pool.size();
        auto &ins = pool[pi];
        if (cls_at.size() < STREAM_END) cls_at.assign(STREAM_END, -1);
        cls_at[a] = (int16_t)pool_cls[pi];
        for (uint8_t b : ins) mem[a++] = b;
        if (a & 1) a++;
    }
}

// ------------------------------------------------------------------------------------------------ stimulus state
struct Opt { int w = 0, berr = 0; bool irq = false, br = false, halt = false, rst = false, vpa = false; } opt;
static int wait_left = -1;        // wait-state countdown for the current cycle
static int berr_tail = 0;         // BERR kept asserted this many more phases after AS rises
static bool cyc_berr = false, cyc_vpa = false;
static int ipl = 0, ipl_hold = 0;
static int br_state = 0, br_timer = 0;   // 0 idle, 1 BR asserted, 2 BGACK asserted (BR released)
static int halt_timer = 0, rst_timer = 0;
static bool prev_as = true;
// -collect: a mismatch that is only the data of a group-0 frame write is logged (FRAME line) and the run goes on (the
// handler does not read the frame, both CPUs stay in step); used to derive the stacked values per micro-instruction
static bool collect = false, collect_reset = false;

struct Pins { int as, uds, lds, rw, fc, e, vma, bg, rsto, halto; uint32_t a; uint16_t d; int aoe, doe; };
static Pins fx_pins() {
    Pins p;
    p.as = fx->ASn; p.uds = fx->UDSn; p.lds = fx->LDSn; p.rw = fx->eRWn; p.fc = (fx->FC2 << 2) | (fx->FC1 << 1) | fx->FC0;
    p.e = fx->E; p.vma = fx->VMAn; p.bg = fx->BGn; p.rsto = fx->oRESETn; p.halto = fx->oHALTEDn;
    p.a = fx->eab; p.d = fx->oEdb;
    p.aoe = fx->rootp->fx68k__DOT__addrOe;
    p.doe = fx->rootp->fx68k__DOT__busControl__DOT__dataOe;
    return p;
}
static Pins mv_pins() {
    Pins p;
    p.as = mv->AS_n; p.uds = mv->UDS_n; p.lds = mv->LDS_n; p.rw = mv->RW; p.fc = mv->FC;
    p.e = mv->E; p.vma = mv->VMA_n; p.bg = mv->BG_n; p.rsto = mv->RESET_n_o; p.halto = mv->HALT_n_o;
    p.a = mv->A; p.d = mv->D_o; p.aoe = 0; p.doe = mv->D_oe;
    return p;
}

// inputs for the next phase, from fx68k's current outputs (the reference); identical for both CPUs
struct In { int dtack = 1, berr = 1, vpa = 1, ipl = 7, br = 1, bgack = 1, halt = 1, reset = 1; uint16_t d = 0; };
// directed sweeps (-sweep ipl|berr|halt|br): at each instruction boundary (m68ksv's, the CPUs being in step) the
// next stimulus event is placed at an offset that cycles through 0..SW-1 phases (berr: bus cycle 0..5 after the boundary
// x 0..3 wait clocks) separately per instruction class (the suite file the instruction came from)
static int sweep = 0;                     // 1 ipl, 2 berr, 3 halt, 4 br
static const int SW = 48;
static long ev_at = -1; static int ev_cls = -2, ev_off = 0;
static long cyc_count = 0, berr_cyc_at = -1; static int berr_wait = 0;
static std::vector<std::vector<long>> cover;      // [class + 1][offset] events
static std::vector<long> ctr;
static In stim(uint64_t t, bool phi1_next) {
    In in;
    Pins p = fx_pins();
    uint32_t a = (p.a << 1) & 0xffffff;
    if (!p.as) {
        if (prev_as) {         // new cycle
            wait_left = opt.w ? (int)(rnd() % (opt.w + 1)) * 2 : 0;
            cyc_berr = opt.berr && (rnd() % opt.berr) == 0;
            cyc_count++;
            if (sweep == 2 && cyc_count == berr_cyc_at) { cyc_berr = true; wait_left = berr_wait * 2; berr_cyc_at = -1; }
            cyc_vpa = opt.vpa && a >= 0xf00000 && a < 0xf10000;
            if (p.fc == 7) {   // IACK: autovector / vector / spurious
                int k = rnd() % 8;
                cyc_vpa = k < 4; cyc_berr = k == 7;
            }
        }
        if (wait_left > 0) wait_left--;
        else if (cyc_berr) { in.berr = 0; berr_tail = (int)(rnd() % 4) * 2; }
        else if (cyc_vpa) in.vpa = 0;
        else in.dtack = 0;
    }
    else if (berr_tail > 0) { berr_tail--; in.berr = 0; }
    prev_as = p.as;
    if (p.fc == 7 && !p.as) in.d = 0x4000 | (rnd() & 0x3f) * 0x101;     // vector number (64-127)
    else in.d = (mem[a] << 8) | mem[(a + 1) & 0xffffff];
    // interrupts
    if (sweep == 1 && (long)t == ev_at) { ipl = (rnd() & 1) ? 7 : 1 + (int)(rnd() % 7); ipl_hold = 20 + rnd() % 200; ev_at = -1; }
    if (sweep == 1 && !opt.irq) {
        if (ipl_hold > 0) { if (--ipl_hold == 0) ipl = 0; }
        in.ipl = 7 - ipl;
    }
    if (sweep == 3 && (long)t == ev_at) { halt_timer = 2 + rnd() % 40; ev_at = -1; }
    if (sweep == 3 && !opt.halt) { if (halt_timer > 0) halt_timer--; in.halt = halt_timer == 0; }
    if (sweep == 4 && (long)t == ev_at) { if (br_state == 0) br_state = 1; ev_at = -1; }
    if (sweep == 4 && !opt.br) {
        if (br_state == 1 && !p.bg && p.as) { br_state = 2; br_timer = 4 + rnd() % 60; }
        else if (br_state == 2 && --br_timer <= 0) br_state = 0;
        in.br = br_state != 1;
        in.bgack = br_state != 2;
    }
    if (opt.irq) {
        if (ipl_hold > 0) ipl_hold--;
        else { ipl = (rnd() % 4 == 0) ? (int)(rnd() % 8) : 0; ipl_hold = 20 + rnd() % 400; }
        in.ipl = 7 - ipl;
    }
    // bus arbitration: BR, wait for BG, then BGACK for a while (BR released)
    if (opt.br) {
        if (br_state == 0 && rnd() % 600 == 0) { br_state = 1; }
        else if (br_state == 1 && !p.bg && p.as) { br_state = 2; br_timer = 4 + rnd() % 60; }
        else if (br_state == 2 && --br_timer <= 0) br_state = 0;
        in.br = br_state != 1;
        in.bgack = br_state != 2;
    }
    if (opt.halt) {
        if (halt_timer > 0) halt_timer--;
        else if (rnd() % 3000 == 0) halt_timer = 2 + rnd() % 80;
        in.halt = halt_timer == 0;
    }
    (void)t; (void)phi1_next;
    return in;
}

static void apply(const In &in) {
    fx->DTACKn = in.dtack; fx->BERRn = in.berr; fx->VPAn = in.vpa; fx->BRn = in.br; fx->BGACKn = in.bgack;
    fx->IPL0n = in.ipl & 1; fx->IPL1n = (in.ipl >> 1) & 1; fx->IPL2n = (in.ipl >> 2) & 1; fx->HALTn = in.halt;
    fx->iEdb = in.d;
    mv->DTACK_n = in.dtack; mv->BERR_n = in.berr; mv->VPA_n = in.vpa; mv->BR_n = in.br; mv->BGACK_n = in.bgack;
    mv->IPL_n = in.ipl; mv->HALT_n_i = in.halt && in.reset; mv->RESET_n_i = in.reset;
    mv->D_i = in.d;
    mv->MODE = 1;                                     // 68EC000 build: 16-bit bus (the fx68k lockstep is the 16-bit check)
}

static bool mv_fin = false;
static int pre_e0, pre_e2, pre_t1, pre_t3;
static uint32_t pre_fpc, pre_pcx, pre_at, pre_fa, pre_aur, pre_vec; static int pre_upc, pre_mc2;
static bool abortchk = getenv("ABORTCHK") != nullptr;
static bool wrtrace = getenv("WRTRACE") != nullptr;   // register / CCR write timeline
static int pre_e13, pre_ir;   // registers / CCR against fx68k at every bus-error point
static int ab_mc1 = -1; static uint32_t ab_rf[17]; static uint16_t ab_sr;
static bool pctrace = getenv("PCTRACE") != nullptr;
static bool pc68chk = getenv("PC68CHK") != nullptr;   // compare pc68 with fx68k's PC register
static long pc68_tot = 0, quiet_pc = 0, ab_n = 0; static int pc68_shown = 0; static long pc68_bad[2048];
   // phase enables active at this edge (PCTRACE)
static void clock(uint64_t t, bool fx_reset, bool mv_hold) {
    bool phi1 = (t & 1) == 0;
    fx->enPhi1 = phi1; fx->enPhi2 = !phi1;
    mv->cen_p = phi1; mv->cen_n = !phi1;
    fx->extReset = fx_reset;
    if (mv_hold) { mv->RESET_n_i = 0; mv->HALT_n_i = 0; }
    fx->clk = 0; mv->clk = 0; fx->eval(); mv->eval();
    mv_fin = mv->dbg_fin;                             // instruction boundary (with this edge's e0)
    pre_e0 = mv->rootp->m68ksv__DOT__e0; pre_e2 = mv->rootp->m68ksv__DOT__e2;
    pre_t1 = fx->rootp->fx68k__DOT__enT1; pre_t3 = fx->rootp->fx68k__DOT__enT3;
    pre_e13 = mv->rootp->m68ksv__DOT__e1 ? 1 : mv->rootp->m68ksv__DOT__e3 ? 3 : 9;
    pre_ir = mv->rootp->m68ksv__DOT__eu__DOT__ir;
    pre_fpc = mv->rootp->m68ksv__DOT__eu__DOT__fpc; pre_upc = mv->dbg_upc; pre_mc2 = mv->rootp->m68ksv__DOT__eu__DOT__mc2;
    pre_pcx = mv->rootp->m68ksv__DOT__eu__DOT__pcx; pre_at = mv->rootp->m68ksv__DOT__eu__DOT__at;
    pre_fa = mv->rootp->m68ksv__DOT__eu__DOT__fa; pre_aur = mv->rootp->m68ksv__DOT__eu__DOT__aur; pre_vec = mv->rootp->m68ksv__DOT__eu__DOT__vec;
    fx->clk = 1; mv->clk = 1; fx->eval(); mv->eval();
}

static void memwrite() {
    Pins p = fx_pins();
    if (!p.as && !p.rw) {
        uint32_t a = (p.a << 1) & 0xffffff;
        if (!p.uds) mem[a] = p.d >> 8;
        if (!p.lds) mem[(a + 1) & 0xffffff] = p.d;
    }
}

static std::string fmt(const Pins &p) {
    char b[160];
    snprintf(b, sizeof b, "AS%d U%d L%d RW%d FC%d E%d VMA%d BG%d RST%d HLT%d A%06x%s D%04x%s", p.as, p.uds, p.lds, p.rw, p.fc,
             p.e, p.vma, p.bg, p.rsto, p.halto, p.a << 1, p.aoe ? "*" : " ", p.d, p.doe ? "*" : " ");
    return b;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    uint32_t seed = 1; int runs = 1, first = 0; long ticks = 200000; int verbose = 0, every = 16;
    std::vector<const char *> files;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-seed")) seed = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-runs")) runs = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-first")) first = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-ticks")) ticks = atol(argv[++i]);
        else if (!strcmp(argv[i], "-w")) opt.w = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-berr")) opt.berr = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-irq")) opt.irq = true;
        else if (!strcmp(argv[i], "-br")) opt.br = true;
        else if (!strcmp(argv[i], "-halt")) opt.halt = true;
        else if (!strcmp(argv[i], "-rst")) opt.rst = true;
        else if (!strcmp(argv[i], "-vpa")) opt.vpa = true;
        else if (!strcmp(argv[i], "-v")) verbose = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-every")) every = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-collect")) collect = true;
        else if (!strcmp(argv[i], "-sweep")) { const char *w = argv[++i]; sweep = !strcmp(w, "ipl") ? 1 : !strcmp(w, "berr") ? 2 : !strcmp(w, "halt") ? 3 : 4; }
        else if (argv[i][0] != '+') files.push_back(argv[i]);
    }
    for (const char *f : files) load_pool(f, every);
    if (pool.empty()) { printf("no instruction pool (give suite .bin files)\n"); return 1; }
    mem = (uint8_t *)malloc(1 << 24);
    cover.assign(cls_name.size() + 1, std::vector<long>(SW, 0));
    ctr.assign(cls_name.size() + 1, 0);
    uint64_t total_ticks = 0; int fails = 0;
    int last_fault_upc = -1;
    for (int run = first; run < first + runs; run++) {
        rng = seed * 2654435761u + run * 40503u + 1;
        build_memory();
        fx = new Vfx68k; mv = new Vm68ksv;
        wait_left = -1; berr_tail = 0; prev_as = true; ipl = 0; collect_reset = true; ipl_hold = 0; br_state = 0; halt_timer = 0; rst_timer = 0;
        // power-up: fx68k pwrUp 40 phases + extReset; m68ksv RESET + HALT; released with the calibrated offset
        const int FX_REL = 440, MV_REL = FX_REL + atoi(getenv("MVOFF") ? getenv("MVOFF") : "0");
        In in; apply(in);
        std::deque<std::string> hist;
        bool bad = false; long t;
        int rst_left = 0, rst_rel_fx = -1, rst_rel_mv = -1, resets = 0;
        long n_berr = 0, n_exc0 = 0, n_iack = 0; int prev_upc = -1; bool prev_be = true, prev_as = true;
        int cyc_late = 0, e_late = 0, cyc_upc = -1, berr_upc = -1, berr_op_upc = -1; uint32_t cyc_fpc = 0, cyc_addr = 0, berr_fpc = 0, berr_addr = 0;
        uint16_t fr_fx[8], fr_mv[8], e_ir = 0, e_irn = 0; uint32_t e_fpc = 0; int fr_n = -1; bool regcmp = false, fr_bad = false, prev_ws = true; long n_frames = 0, n_frbad = 0;
        for (t = 0; t < ticks; t++) {
            fx->pwrUp = t < 40;
            bool fxr = t < FX_REL, mvh = t < MV_REL;
            {
                static int halted_for; Pins h = fx_pins();
                halted_for = h.halto ? 0 : halted_for + 1;
                bool want = (opt.rst && t > 2000 && rnd() % 200000 == 0) || halted_for > 200;   // also leaves a double-fault halt
                if (rst_left == 0 && want) {
                    // fx68k's restart latency depends on its micro-cycle phase: release on the same phase (mod 4
                    // phases) as at power-up, so the calibrated m68ksv offset holds
                    rst_left = 300 + rnd() % 200;
                    halted_for = 0; resets++;
                }
                // fx68k's micro-cycle (tState) keeps running in reset and can slip by a T0 wait state; release on the
                // same tState and phase as at power-up so the calibrated m68ksv offset holds
                static int ref_ts = -1;
                if (t == FX_REL) ref_ts = fx->rootp->fx68k__DOT__tState;
                if (rst_left == 1 && (fx->rootp->fx68k__DOT__tState != (uint32_t)ref_ts || (t & 1) != (FX_REL & 1))) rst_left++;
                if (rst_left > 0) { if (--rst_left == 0) { rst_rel_fx = t; rst_rel_mv = t + (MV_REL - FX_REL); } }
                if (rst_left > 0) { fxr = true; mvh = true; }
                if (rst_rel_mv > t) mvh = true;
            }
            if (getenv("RSTDBG")) {
                static long rel = -1; static bool seen = true; Pins q = fx_pins();
                if (t == rst_rel_fx) { rel = t; seen = false; }
                static bool mseen = true;
                if (t == rst_rel_fx) mseen = false;
                if (!seen && !q.as) { printf("reset released at %ld (mod 4 = %ld, mod 20 = %ld): fx68k first AS at +%ld\n", rel, rel & 3, rel % 20, t - rel); seen = true; }
                if (!mseen && !mv->AS_n) { printf("reset released at %ld: m68ksv first AS at +%ld\n", rel, t - rel); mseen = true; }
            }
            in = stim(t, (t & 1) == 0);
            apply(in);
            clock(t, fxr, mvh);
            if (sweep && mv_fin && !fxr && !mvh) {
                // instruction boundary: schedule the next event if none is pending / active
                int c = cls_op[mv->dbg_ir];               // the instruction starting now (IR after this e0)
                bool idle = ev_at < 0 && berr_cyc_at < 0 && halt_timer == 0 && br_state == 0 && ipl_hold == 0;
                if (idle) {
                    long o = ctr[c + 1]++ % SW;
                    ev_cls = c; ev_off = (int)o;
                    cover[c + 1][o]++;
                    if (sweep == 2) { berr_cyc_at = cyc_count + 1 + o / 8; berr_wait = (int)(o % 4); }
                    else ev_at = t + 1 + o;
                }
            }
            memwrite();
            Pins a = fx_pins(), b = mv_pins();
            if (getenv("CAL")) {
                static long fa = -1, ma = -1;
                if (fa < 0 && !a.as) { fa = t; printf("fx68k first AS at phase %ld\n", t); }
                if (ma < 0 && !b.as) { ma = t; printf("m68ksv first AS at phase %ld (released at %d)\n", t, MV_REL); }
                if (fa >= 0 && ma >= 0) return 0;
                continue;
            }
            char line[400];
            snprintf(line, sizeof line, "%8ld phi%d fx  %s IPL%d DT%d BR%d BGK%d HT%d\n%14s mv  %s upc %d sr %04x pc %06x", t, (int)(t & 1) + 1,
                     fmt(a).c_str(), 7 - in.ipl, !in.dtack, !in.br, !in.bgack, !in.halt, "", fmt(b).c_str(), mv->dbg_upc, mv->dbg_sr, mv->dbg_pc & 0xffffff);
            if (getenv("FXDBG")) {
                auto *r = fx->rootp;
                char x[120];
                auto *m = mv->rootp;
                snprintf(x, sizeof x, " | fx pswI %d intPend %d iIpl %d inl %d ua %03x | mv pend %d npf %d q %d lvl %d", r->fx68k__DOT__pswI, r->fx68k__DOT__intPend,
                         r->fx68k__DOT__iIpl, r->fx68k__DOT__inl, r->fx68k__DOT__microAddr, m->m68ksv__DOT__int_pend,
                         m->m68ksv__DOT__eu__DOT__irq_npf, m->m68ksv__DOT__eu__DOT__irq_q, m->m68ksv__DOT__int_lvl);
                strncat(line, x, sizeof line - strlen(line) - 1);
            }
            if (getenv("GRP0DBG")) {
                static int pg = -1, pm = -1; auto *f = fx->rootp;
                int g = f->fx68k__DOT__sequencer__DOT__rExcRst | f->fx68k__DOT__sequencer__DOT__rExcBusErr << 1 | f->fx68k__DOT__sequencer__DOT__rExcAdrErr << 2;
                int gm = mv->rootp->m68ksv__DOT__eu__DOT__g0;
                if (g != pg || gm != pm) printf("G0 %ld fx %d (uaddr %03x) mv %d upc %d\n", t, g, f->fx68k__DOT__microAddr, gm, mv->dbg_upc);
                pg = g; pm = gm;
            }
            if (getenv("REGTRACE")) {
                static uint32_t pf = 0xdeadbeef, pm = 0xdeadbeef; int n = atoi(getenv("REGTRACE"));
                auto *r = mv->rootp; auto *f = fx->rootp;
                uint32_t vf = (f->fx68k__DOT__excUnit__DOT__regs68H[n] << 16) | f->fx68k__DOT__excUnit__DOT__regs68L[n];
                uint32_t vm = r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[n];
                if (vf != pf) printf("RT %ld fx R%d %08x\n", t, n, vf);
                if (vm != pm) printf("RT %ld mv R%d %08x upc %d\n", t, n, vm, mv->dbg_upc);
                pf = vf; pm = vm;
            }
            if (pctrace) {
                // fx68k's PC register against m68ksv's state: E = m68ksv micro-word start (upc, fpc after the edge),
                // P = fx68k PC change (at its T1: AU -> PC, at T3: bus -> PC), T = fx68k T1 (micro-address)
                static uint32_t ppc = 0xffffffff; auto *f = fx->rootp; auto *r = mv->rootp;
                uint32_t pc = (f->fx68k__DOT__excUnit__DOT__PcH << 16) | f->fx68k__DOT__excUnit__DOT__PcL;
                if (pre_e0) printf("E %ld %d %08x %08x\n", t, mv->dbg_upc, r->m68ksv__DOT__eu__DOT__fpc, pc);
                if (pre_t1) printf("T %ld %03x\n", t, f->fx68k__DOT__microAddr);
                if (pc != ppc) printf("P %ld %d %08x %08x %08x %d %d aur %08x at %08x dt %08x pcx %08x fa %08x vec %02x\n", t, pre_t1 ? 1 : pre_t3 ? 3 : 0, pc, pre_fpc, r->m68ksv__DOT__eu__DOT__fpc, pre_upc, mv->dbg_upc, pre_aur, pre_at, r->m68ksv__DOT__eu__DOT__dt, pre_pcx, pre_fa, pre_vec);
                ppc = pc;
            }
            if (pc68chk && !fxr && !mvh && t > quiet_pc && (getenv("PC68ALL") || (pre_e2 && mv->rootp->m68ksv__DOT__eu__DOT__mc2))) {
                // m68ksv's pc68 against fx68k's PC register at every point a bus error can be taken (the e2 of the second
                // micro-word of a bus cycle; PC68ALL: every phase), counted per m68ksv micro-word
                auto *f = fx->rootp;
                uint32_t pc = (f->fx68k__DOT__excUnit__DOT__PcH << 16) | f->fx68k__DOT__excUnit__DOT__PcL;
                uint32_t p6 = mv->rootp->m68ksv__DOT__eu__DOT__pc68;
                pc68_tot++;
                if (pc != p6) { pc68_bad[mv->dbg_upc]++; if (getenv("PC68V") && (mv->dbg_upc < UA_EXC0 + 10 || mv->dbg_upc > UA_EXC0 + 17) && pc68_shown++ < atoi(getenv("PC68V"))) printf("PC68 %ld upc %d fx %08x mv %08x fpc %08x\n", t, mv->dbg_upc, pc, p6, mv->rootp->m68ksv__DOT__eu__DOT__fpc); }
            }
            if (fxr || mvh) quiet_pc = t + 2000;
            if (wrtrace && !fxr && !mvh) {
                // register / CCR write timeline of both CPUs: X <t> <fx|mv> <R0..R16|CCR> <lo|hi|both> <m68ksv upc> <phase>
                // (phase = which m68ksv enable was active at this edge: 0 e0, 1 e1, 2 e2, 3 e3, - none)
                static uint32_t pf[17], pm[17]; static int pcf, pcm; auto *f = fx->rootp; auto *r = mv->rootp;
                int ph = pre_e0 ? 0 : pre_e2 ? 2 : r->m68ksv__DOT__e1 ? 1 : r->m68ksv__DOT__e3 ? 3 : -1;
                (void)ph;
                int phx = pre_e0 ? 0 : pre_e2 ? 2 : pre_e13;
                for (int k = 0; k < 17; k++) {
                    uint32_t vf = (f->fx68k__DOT__excUnit__DOT__regs68H[k] << 16) | f->fx68k__DOT__excUnit__DOT__regs68L[k];
                    uint32_t vm = r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[k];
                    auto hl = [](uint32_t a, uint32_t b) { return ((a ^ b) >> 16) ? (((a ^ b) & 0xffff) ? "both" : "hi") : "lo"; };
                    if (vf != pf[k]) printf("X %ld fx R%d %s %d %d %08x %04x\n", t, k, hl(vf, pf[k]), pre_upc, phx, vf, pre_ir);
                    if (vm != pm[k]) printf("X %ld mv R%d %s %d %d %08x %04x\n", t, k, hl(vm, pm[k]), pre_upc, phx, vm, pre_ir);
                    pf[k] = vf; pm[k] = vm;
                }
                int cf = f->fx68k__DOT__ccr & 0x1f, cm = r->m68ksv__DOT__eu__DOT__sr & 0x1f;
                if (cf != pcf) printf("X %ld fx CCR - %d %d %02x %04x\n", t, pre_upc, phx, cf, pre_ir);
                if (cm != pcm) printf("X %ld mv CCR - %d %d %02x %04x\n", t, pre_upc, phx, cm, pre_ir);
                pcf = cf; pcm = cm;
            }
            if (getenv("CCRTRACE")) {
                // fx68k CCR changes and m68ksv's, with m68ksv's micro-word (bus-error frame studies)
                static int pcf = -1, pcm = -1; auto *f = fx->rootp; auto *r = mv->rootp;
                int cf = f->fx68k__DOT__ccr & 0x1f, cm = r->m68ksv__DOT__eu__DOT__sr & 0x1f;
                if (cf != pcf || cm != pcm) printf("C %ld fx %02x mv %02x upc %d ua %03x BE%d\n", t, cf, cm, mv->dbg_upc, f->fx68k__DOT__microAddr, !in.berr);
                pcf = cf; pcm = cm;
            }
            if (abortchk && !fxr && !mvh && t > quiet_pc) {
                // at the e0 that ends the second micro-word of a bus cycle, m68ksv's registers / CCR are what a bus error
                // there would leave (EXC0 follows); fx68k's after its word's T3 likewise (its register / CCR writes are on
                // T3, the next word's T3 never comes on a bus error). AB lines: differences, with the values at the start
                // of the cycle (mc1) for reference
                auto *f = fx->rootp; auto *r = mv->rootp;
                if (pre_e0 && pre_mc2 && ab_mc1 >= 0) {
                    for (int k = 0; k < 17; k++) {
                        uint32_t vf = (f->fx68k__DOT__excUnit__DOT__regs68H[k] << 16) | f->fx68k__DOT__excUnit__DOT__regs68L[k];
                        uint32_t vm = r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[k];
                        if (vf != vm) printf("AB %ld %d %d %04x R%d fx %08x mv %08x was %08x\n", t, ab_mc1, pre_upc, r->m68ksv__DOT__eu__DOT__ir, k, vf, vm, ab_rf[k]);
                    }
                    int cf = f->fx68k__DOT__ccr & 0x1f, cm = r->m68ksv__DOT__eu__DOT__sr & 0x1f;
                    if (cf != cm) printf("AB %ld %d %d %04x CCR fx %02x mv %02x was %02x\n", t, ab_mc1, pre_upc, r->m68ksv__DOT__eu__DOT__ir, cf, cm, ab_sr & 0x1f);
                    ab_n++;
                }
                if (pre_e0 && r->m68ksv__DOT__eu__DOT__bact) {
                    ab_mc1 = mv->dbg_upc;
                    for (int k = 0; k < 17; k++) ab_rf[k] = r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[k];
                    ab_sr = r->m68ksv__DOT__eu__DOT__sr;
                }
            }
            if (getenv("REGDBG")) {
                auto *r = mv->rootp; auto *f = fx->rootp;
                char x[200]; int n = atoi(getenv("REGDBG"));
                // fx68k: regs68L/H[0..15] = D0-D7 A0-A7(user / current), [16] = SSP (fx68k register map)
                snprintf(x, sizeof x, " | R%d fx %04x%04x mv %08x  SSP fx %04x%04x mv %08x", n, f->fx68k__DOT__excUnit__DOT__regs68H[n],
                         f->fx68k__DOT__excUnit__DOT__regs68L[n], r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[n],
                         f->fx68k__DOT__excUnit__DOT__regs68H[16], f->fx68k__DOT__excUnit__DOT__regs68L[16], r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[16]);
                strncat(line, x, sizeof line - strlen(line) - 1);
            }
            if (getenv("BIUDBG")) {
                auto *r = mv->rootp;
                char x[160];
                snprintf(x, sizeof x, " | st %d berr %d ae %d ecnt %d vpa_s %d vma %d VPA%d BE%d", r->m68ksv__DOT__g_biu16__DOT__biu__DOT__st,
                         r->m68ksv__DOT__g_biu16__DOT__biu__DOT__berr_cyc, r->m68ksv__DOT__eu__DOT__ae, r->m68ksv__DOT__g_biu16__DOT__biu__DOT__ecnt,
                         r->m68ksv__DOT__g_biu16__DOT__biu__DOT__vpa_s, r->m68ksv__DOT__g_biu16__DOT__biu__DOT__vma_n, in.vpa, in.berr);
                strncat(line, x, sizeof line - strlen(line) - 1);
            }
            if (getenv("MVDBG")) {
                auto *r = mv->rootp;
                char x[200];
                snprintf(x, sizeof x, " ir %04x irn %04x irc %04x dt %08x", r->m68ksv__DOT__eu__DOT__ir,
                         r->m68ksv__DOT__eu__DOT__irn, r->m68ksv__DOT__eu__DOT__irc, r->m68ksv__DOT__eu__DOT__dt);
                strncat(line, x, sizeof line - strlen(line) - 1);
            }
            if (getenv("AECHK") && mv->dbg_upc == UA_EXC0A && prev_upc != UA_EXC0A) {
                // address error: the pk-rule stacked PC against pc68 (the 68000's PC register model)
                auto *r = mv->rootp;
                printf("AE upc %d aepc_f %d pc68 %08x late %d\n", last_fault_upc, r->m68ksv__DOT__eu__DOT__aepc_f, r->m68ksv__DOT__eu__DOT__pc68, r->m68ksv__DOT__eu__DOT__late);
            }
            if (mv->dbg_upc < UA_EXC0A || mv->dbg_upc > UA_EXC0 + 24) last_fault_upc = mv->dbg_upc;
            if (collect) {
                if (collect_reset || mvh) { berr_upc = -1; fr_n = -1; regcmp = false; collect_reset = false; }
                if (!b.as && prev_as) { cyc_late = mv->rootp->m68ksv__DOT__eu__DOT__late; cyc_upc = mv->dbg_upc; cyc_fpc = mv->rootp->m68ksv__DOT__eu__DOT__fpc; cyc_addr = (b.a << 1); }
                if (!in.berr && !a.as) { berr_upc = cyc_upc; berr_fpc = cyc_fpc; berr_addr = cyc_addr; }
                if (mv->dbg_upc == UA_EXC0 && prev_upc != UA_EXC0) {
                    fr_n = 0; fr_bad = false; berr_op_upc = last_fault_upc;
                    auto *r = mv->rootp;
                    e_late = cyc_late; e_ir = r->m68ksv__DOT__eu__DOT__ir; e_irn = r->m68ksv__DOT__eu__DOT__irn; e_fpc = r->m68ksv__DOT__eu__DOT__fpc;
                }
                bool ws = a.uds && a.lds;
                if (fr_n >= 0 && fr_n < 8 && !a.as && !a.rw && !ws && prev_ws) {
                    fr_fx[fr_n] = a.d; fr_mv[fr_n] = b.d; if (a.d != b.d) fr_bad = true; fr_n++;
                    if (fr_n == 7) {
                        n_frames++;
                        if (fr_bad) n_frbad++;
                        if (fr_bad || getenv("ALLFRAMES"))
                            printf("FRAME run %d t %ld vec %d upc %d last %d fpc %06x addr %06x efpc %06x ir %04x irn %04x late %d | fx %04x %04x %04x %04x %04x %04x %04x | mv %04x %04x %04x %04x %04x %04x %04x\n",
                                   run, t, mv->rootp->m68ksv__DOT__eu__DOT__vec, berr_upc, berr_op_upc, berr_fpc & 0xffffff, berr_addr & 0xffffff, e_fpc & 0xffffff, e_ir, e_irn, e_late,
                                   fr_fx[0], fr_fx[1], fr_fx[2], fr_fx[3], fr_fx[4], fr_fx[5], fr_fx[6],
                                   fr_mv[0], fr_mv[1], fr_mv[2], fr_mv[3], fr_mv[4], fr_mv[5], fr_mv[6]);
                        fr_n = -1;
                        regcmp = true;
                    }
                }
                prev_ws = ws;
                // registers after the frame (at the refill): log differences and copy fx68k's into m68ksv (collect
                // mode only, so that one wrong register update does not end the run)
                if (regcmp && mv->dbg_upc == UA_VECJMP_G0) {
                        regcmp = false;
                        auto *f = fx->rootp; auto *r = mv->rootp;
                        uint16_t fsr = (f->fx68k__DOT__pswT << 15) | (f->fx68k__DOT__pswS << 13) | (f->fx68k__DOT__pswI << 8) | (f->fx68k__DOT__ccr & 0x1f);
                        if (fsr != r->m68ksv__DOT__eu__DOT__sr) {
                            printf("SRDIFF run %d t %ld upc %d fx %04x mv %04x\n", run, t, berr_upc, fsr, r->m68ksv__DOT__eu__DOT__sr);
                            r->m68ksv__DOT__eu__DOT__sr = fsr;
                        }
                        for (int k = 0; k < 17; k++) {
                            uint32_t vf = (f->fx68k__DOT__excUnit__DOT__regs68H[k] << 16) | f->fx68k__DOT__excUnit__DOT__regs68L[k];
                            uint32_t vm = r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[k];
                            if (vf != vm) {
                                printf("REGS run %d t %ld upc %d last %d R%d fx %08x mv %08x d %d\n", run, t, berr_upc, berr_op_upc, k, vf, vm, (int)(vf - vm));
                                r->m68ksv__DOT__eu__DOT__rf_a__DOT__mem[k] = vf; r->m68ksv__DOT__eu__DOT__rf_xn__DOT__mem[k] = vf;
                                r->m68ksv__DOT__eu__DOT__rf_bw__DOT__mem[k] = vf; r->m68ksv__DOT__eu__DOT__rf_dbg__DOT__mem[k] = vf;
                            }
                        }
                        berr_upc = -1;
                }
            }
            if (!in.berr && prev_be && !a.as) n_berr++;
            prev_be = in.berr;
            if (mv->dbg_upc == UA_EXC0 && prev_upc != UA_EXC0) n_exc0++;
            if (!a.as && prev_as && a.fc == 7) n_iack++;
            prev_upc = mv->dbg_upc; prev_as = a.as;
            if (getenv("TR") && t >= atol(getenv("TR")) - 200 && t <= atol(getenv("TR"))) printf("%s\n", line);
            hist.push_back(line); if (hist.size() > (verbose > 2 ? 400u : 24u)) hist.pop_front();
            static long quiet_until;
            if (t == 0) quiet_until = 0;
            if (fxr || mvh) quiet_until = t + 4;                  // pins are not compared while either CPU is in reset
            if (t < MV_REL + 4 || t < quiet_until) continue;
            bool m = a.as != b.as || a.uds != b.uds || a.lds != b.lds || a.rw != b.rw || a.fc != b.fc || a.e != b.e ||
                     a.vma != b.vma || a.bg != b.bg || a.rsto != b.rsto || a.halto != b.halto ||
                     (a.aoe && a.a != b.a) || (a.doe && (!b.doe || a.d != b.d));
            if (m && collect && fr_n >= 0 && a.as == b.as && a.uds == b.uds && a.lds == b.lds && a.rw == b.rw && a.fc == b.fc &&
                a.e == b.e && a.vma == b.vma && a.bg == b.bg && a.rsto == b.rsto && a.halto == b.halto && (!a.aoe || a.a == b.a) && b.doe)
                m = false;
            if (m && !bad) { bad = true; if (verbose) { for (auto &l : hist) printf("%s\n", l.c_str()); printf("   ^^^ mismatch\n"); } hist.clear(); }
            if (bad && hist.size() >= (size_t)(verbose > 3 ? 400 : verbose > 2 ? 60 : verbose > 1 ? 8 : 0)) break;
        }
        total_ticks += t;
        if (collect) printf("COLLECT run %d: %ld frames, %ld differ\n", run, n_frames, n_frbad);
        if (bad) {
            fails++;
            if (sweep) printf("run %d: sweep mismatch after the event at class %s offset %d\n", run, ev_cls < 0 ? "(other)" : cls_name[ev_cls].c_str(), ev_off);
            printf("run %d seed %u: MISMATCH at phase %ld\n", run, seed, t);
            if (verbose > 1) for (auto &l : hist) printf("%s\n", l.c_str());
        } else if (verbose > 1) printf("run %d: %ld phases ok (%d resets, %ld BERR cycles, %ld group-0 entries, %ld IACKs)\n",
                                       run, t, resets, n_berr, n_exc0, n_iack);
        delete fx; delete mv;
        ev_at = -1; berr_cyc_at = -1; cyc_count = 0;
    }
    if (sweep) {
        long ev = 0, pairs = 0; int ncls = 0;
        for (size_t c = 1; c < cover.size(); c++) { int k = 0; for (long x : cover[c]) { ev += x; k += x > 0; } pairs += k; ncls += k > 0; }
        long other = 0; for (long x : cover[0]) other += x;
        printf("sweep %s: %ld events at suite-class instructions (+%ld elsewhere), %d of %zu classes, %ld of %zu class x offset pairs\n",
               sweep == 1 ? "ipl" : sweep == 2 ? "berr" : sweep == 3 ? "halt" : "br", ev, other, ncls, cls_name.size(), pairs, cls_name.size() * SW);
    }
    if (abortchk) printf("ABORTCHK: %ld bus-error points compared\n", ab_n);
    if (pc68chk) {
        long b = 0; for (int u = 0; u < 2048; u++) b += pc68_bad[u];
        printf("PC68CHK: %ld phases compared, %ld differ\n", pc68_tot, b);
        for (int u = 0; u < 2048; u++) if (pc68_bad[u]) printf("PC68BAD upc %d %ld\n", u, pc68_bad[u]);
    }
    printf("lockstep: %d runs, %llu phases (%llu CPU clocks), %d mismatching runs\n",
           runs, (unsigned long long)total_ticks, (unsigned long long)total_ticks / 2, fails);
    return fails != 0;
}

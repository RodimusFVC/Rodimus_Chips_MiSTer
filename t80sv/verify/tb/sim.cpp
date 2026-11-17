// Lockstep driver: GHDL reference model vs t80sv drop-in, same clock / enables / stimulus; every output, every T80
// register and every front-end register compared after every clock edge (both edges) and every async reset change.
//
//   sim random <seed> <cycles>            random stimulus over random memory (all opcode pages)
//   sim com <file.com> [cen-pattern]      CP/M .COM at 0100h with a BDOS shim (fn 2 / 9 print, 0 stop)
//   sim sweep <first> <count>             directed timing sweeps (see sweep_case)
//
// Exit status 0 = no mismatch.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include "Vtb.h"
#include "verilated.h"
#include "tb_fields.h"

static Vtb *tb;
static uint64_t cyc = 0, compares = 0;
static uint8_t mem[65536];

struct Rng {
    uint64_t s;
    explicit Rng(uint64_t seed) : s(seed * 0x9E3779B97F4A7C15ull + 1) { next(); }
    uint64_t next() { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
    uint32_t u(uint32_t n) { return (uint32_t)(next() % n); }
    bool p(double x) { return (next() >> 11) * (1.0 / 9007199254740992.0) < x; }
};

// ---------------------------------------------------------------- state access
static const int NF = sizeof(ST_FIELDS) / sizeof(ST_FIELDS[0]);
static int f_off[NF];  // LSB offset of each field

static uint64_t wbits(const uint32_t *w, int lsb, int width) {
    if (width > 64) width = 64;
    int wi = lsb >> 5, sh = lsb & 31;
    unsigned __int128 v = (unsigned __int128)w[wi] | (unsigned __int128)w[wi + 1] << 32 |
                          (unsigned __int128)w[wi + 2] << 64;
    v >>= sh;
    return width == 64 ? (uint64_t)v : (uint64_t)v & ((1ull << width) - 1);
}
static int fidx(const char *n) {
    for (int i = 0; i < NF; i++) if (!strcmp(ST_FIELDS[i].name, n)) return i;
    fprintf(stderr, "no field %s\n", n); exit(3);
}
static uint64_t rf(int i) { return wbits(tb->ref_st.data(), f_off[i], ST_FIELDS[i].w); }
static uint64_t df(int i) { return wbits(tb->dut_st.data(), f_off[i], ST_FIELDS[i].w); }

static int F_MCYCLE, F_TSTATE, F_IR, F_ISET, F_XY, F_HALT, F_INTC, F_NMIC, F_ISTAT, F_PC, F_DOR, F_IFF1, F_DOUT;

// output pins by name (-1 = the top has no such pin)
static const int NPF = sizeof(PIN_FIELDS) / sizeof(PIN_FIELDS[0]);
static int p_off[NPF];
static int P_A, P_DO, P_M1, P_MREQ, P_IORQ, P_RD, P_WR, P_DBIN, P_SYNC, P_IORQH, P_WRITE, P_INTCN, P_MC;
static int pidx(const char *n) {
    for (int i = 0; i < NPF; i++) if (!strcmp(PIN_FIELDS[i].name, n)) return i;
    return -1;
}
// reference pin value; absent pins read as dflt
static uint64_t rp(int i, uint64_t dflt = 1) { return i < 0 ? dflt : wbits(tb->ref_pins.data(), p_off[i], PIN_FIELDS[i].w); }

// ---------------------------------------------------------------- trace ring for mismatch reports
struct TraceEnt { uint64_t cyc; uint32_t in; uint16_t a; uint8_t d, strobes; uint8_t di; uint8_t mc, ts; uint16_t pc; };
static TraceEnt ring[48];
static int ring_n = 0;

static uint32_t pack_in() {
    return tb->reset_n | tb->cen << 1 | tb->cen_p << 2 | tb->cen_n << 3 | tb->wait_n << 4 | tb->int_n << 5 |
           tb->nmi_n << 6 | tb->busrq_n << 7 | tb->i8080 << 8 | tb->i8085 << 9 | tb->dirset << 10 | tb->r800 << 11;
}

static void dump_trace() {
    int n = ring_n < 48 ? ring_n : 48;
    fprintf(stderr, "  last %d cycles (rst cen cp cn wt int nmi brq 80 85 dirset r800 | di | ref A DO m1/mreq/iorq/rd/wr | M T PC):\n", n);
    for (int k = n; k > 0; k--) {
        TraceEnt &e = ring[(ring_n - k) % 48];
        fprintf(stderr, "  %10llu  %d %d %d %d %d %d %d %d %d %d %d %d | %02x | %04x %02x %d%d%d%d%d | %d %d %04x\n",
                (unsigned long long)e.cyc, e.in & 1, e.in >> 1 & 1, e.in >> 2 & 1, e.in >> 3 & 1, e.in >> 4 & 1,
                e.in >> 5 & 1, e.in >> 6 & 1, e.in >> 7 & 1, e.in >> 8 & 1, e.in >> 9 & 1, e.in >> 10 & 1, e.in >> 11 & 1,
                e.di, e.a, e.d, e.strobes >> 4 & 1, e.strobes >> 3 & 1, e.strobes >> 2 & 1, e.strobes >> 1 & 1,
                e.strobes & 1, e.mc, e.ts, e.pc);
    }
}

static bool fail_quiet = false;
static const int ST_WORDS = (ST_W + 31) / 32, PIN_WORDS = (PIN_W + 31) / 32;
static void check(const char *where) {
    compares++;
    if (!memcmp(tb->ref_pins.data(), tb->dut_pins.data(), PIN_WORDS * 4) &&
        !memcmp(tb->ref_st.data(), tb->dut_st.data(), ST_WORDS * 4))
        return;
    for (int i = 0; i < NPF; i++)
        for (int o = 0; o < PIN_FIELDS[i].w; o += 64) {
            int w = PIN_FIELDS[i].w - o < 64 ? PIN_FIELDS[i].w - o : 64;
            uint64_t x = wbits(tb->ref_pins.data(), p_off[i] + o, w), y = wbits(tb->dut_pins.data(), p_off[i] + o, w);
            if (x != y) fprintf(stderr, "PIN MISMATCH cycle %llu (%s) %s[%d+]: ref %llx dut %llx\n", (unsigned long long)cyc,
                                where, PIN_FIELDS[i].name, o, (unsigned long long)x, (unsigned long long)y);
        }
    for (int i = 0; i < NF; i++)
        for (int o = 0; o < ST_FIELDS[i].w; o += 64) {
            int w = ST_FIELDS[i].w - o < 64 ? ST_FIELDS[i].w - o : 64;
            uint64_t x = wbits(tb->ref_st.data(), f_off[i] + o, w), y = wbits(tb->dut_st.data(), f_off[i] + o, w);
            if (x != y) fprintf(stderr, "STATE MISMATCH cycle %llu (%s) %s[%d+]: ref %llx dut %llx\n", (unsigned long long)cyc,
                                where, ST_FIELDS[i].name, o, (unsigned long long)x, (unsigned long long)y);
        }
    if (!fail_quiet) dump_trace();
    fprintf(stderr, "FAIL %s after %llu cycles\n", CFG_NAME, (unsigned long long)cyc);
    exit(1);
}

// ---------------------------------------------------------------- coverage
// pages: 0 base, 1 CB, 2 ED, 3 DD, 4 FD, 5 DDCB, 6 FDCB
static uint64_t cov[7][256];
static int prev_mt = -1;
static void coverage() {
    int mc = (int)rf(F_MCYCLE), ts = (int)rf(F_TSTATE);
    int mt = mc * 8 + ts;
    if (mt != prev_mt && ts == 3 && (mc == 1 || mc == 7)) {
        int iset = (int)rf(F_ISET), xy = (int)rf(F_XY), ir = (int)rf(F_IR);
        bool skip = rf(F_HALT) || rf(F_NMIC) || (rf(F_INTC) && rf(F_ISTAT) != 0);
        if (!skip) {
            int page = -1;
            if (mc == 1) {
                if (iset == 0) page = xy == 0 ? 0 : (xy == 1 ? 3 : 4);
                else if (iset == 1 && xy == 0) page = 1;
                else if (iset == 2) page = 2;
            } else if (iset == 1 && xy != 0) page = xy == 1 ? 5 : 6;
            if (page >= 0) cov[page][ir]++;
            static int dbg = getenv("COV_TRACE") ? atoi(getenv("COV_TRACE")) : 0;
            if (dbg > 0) { dbg--; printf("cyc %llu mc %d iset %d xy %d ir %02x pc %04x\n", (unsigned long long)cyc, mc, iset, xy, ir, (unsigned)rf(F_PC)); }
        }
    }
    prev_mt = mt;
}
static void cov_report(const char *tag) {
    static const char *pn[7] = {"base", "CB", "ED", "DD", "FD", "DDCB", "FDCB"};
    printf("COVERAGE %s %s:", CFG_NAME, tag);
    for (int p = 0; p < 7; p++) {
        int n = 0; uint64_t tot = 0;
        for (int i = 0; i < 256; i++) { n += cov[p][i] != 0; tot += cov[p][i]; }
        printf(" %s %d/256 (%llu)", pn[p], n, (unsigned long long)tot);
    }
    printf("\n");
    if (getenv("COV_DEBUG")) printf("base CB %llu ED %llu DD %llu FD %llu 76 %llu\n", (unsigned long long)cov[0][0xCB],
        (unsigned long long)cov[0][0xED], (unsigned long long)cov[0][0xDD], (unsigned long long)cov[0][0xFD], (unsigned long long)cov[0][0x76]);
}
static void cov_dump(const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) return;
    fwrite(cov, sizeof(cov), 1, f);
    fclose(f);
}

// ---------------------------------------------------------------- bus model
struct Bus {
    bool float_rand = true;     // DI when nothing is reading: random (lockstep) or memory (programs)
    Rng *rng = nullptr;
    uint8_t io_val = 0xFF, vec = 0xFF, status = 0;
    uint8_t de_lo = 0, de_hi = 0;
    bool stop = false;
    std::string out;
    bool prev_io_w = false;
    bool cpm = false;
    bool rand_io = true;

    uint8_t flt(uint16_t a) { return float_rand ? (uint8_t)rng->u(256) : mem[a]; }
    uint8_t di() {
        uint16_t a = (uint16_t)rp(P_A, 0);
        if (CFG_KIND == 1) {                                        // 8080: DBIN + status word
            if (rp(P_DBIN, 0)) {
                if (status & 0x01) return vec;                      // INTA
                if (status & 0x40) return io_in();                  // INP
                return mem[a];
            }
            return flt(a);
        }
        if (CFG_KIND == 2) {                                        // bare T80: decode from IntCycle_n / IORQ / Write
            if (!rp(P_INTCN)) return vec;
            if (rp(P_IORQH, 0)) return rp(P_WRITE, 0) ? flt(a) : io_in();
            return rp(P_WRITE, 0) ? flt(a) : mem[a];
        }
        bool m1 = !rp(P_M1), mreq = !rp(P_MREQ), iorq = !rp(P_IORQ), rd = !rp(P_RD), wr = !rp(P_WR);
        if (iorq && (m1 || (!rd && !wr))) return vec;               // INTA (GB: IORQ alone in M3)
        if (mreq && (rd || m1)) return mem[a];
        if (iorq && rd) return io_in();
        if (mreq) return mem[a];
        return flt(a);
    }
    uint8_t io_in() { return rand_io && rng ? (uint8_t)rng->u(256) : io_val; }
    void io_out(uint8_t port, uint8_t v) {
        if (!cpm) return;
        if (port == 2) de_lo = v;
        else if (port == 3) de_hi = v;
        else if (port == 1) {
            if (v == 2) { out += (char)de_lo; fputc(de_lo, stdout); fflush(stdout); }
            else if (v == 9) {
                for (uint16_t q = de_hi << 8 | de_lo; mem[q] != '$'; q++) { out += (char)mem[q]; fputc(mem[q], stdout); }
                fflush(stdout);
            } else if (v == 0) stop = true;
        }
    }
    // called after every clock edge with the reference outputs
    void update() {
        uint16_t a = (uint16_t)rp(P_A, 0);
        uint8_t d = CFG_KIND == 3 ? (uint8_t)rf(F_DOUT) : (uint8_t)rp(P_DO, 0);
        bool memw = false, iow = false;
        if (CFG_KIND == 1) {
            if (rp(P_SYNC, 0)) status = d;                          // status word on DO in T1
            if (!rp(P_WR)) { if (status & 0x10) iow = true; else memw = true; }
        } else if (CFG_KIND == 2) {
            if (rp(P_WRITE, 0) && rp(P_MC, 1) != 1) { if (rp(P_IORQH, 0)) iow = true; else memw = true; }
        } else {
            bool mreq = !rp(P_MREQ), iorq = !rp(P_IORQ), wr = !rp(P_WR), m1 = !rp(P_M1);
            memw = mreq && wr;
            iow = iorq && wr && !m1;
        }
        if (memw) mem[a] = d;
        if (iow && !prev_io_w) io_out(a & 0xff, d);
        prev_io_w = iow;
    }
};
static Bus bus;

// ---------------------------------------------------------------- clocking
static void eval_check_async(const char *where) { tb->eval(); check(where); }

static bool fast = false;   // solo builds running long programs: no compares, trace or coverage
static void tick() {
    if (fast) {
        tb->di = bus.di();
        tb->di2 = tb->di;
        tb->clk = 1;
        tb->eval();
        cyc++;
        bus.update();
        if (TWO_EDGE) { tb->di = bus.di(); tb->di2 = tb->di; }
        tb->clk = 0;
        tb->eval();
        if (TWO_EDGE) bus.update();
        return;
    }
    // inputs were set while clk = 0; DI follows the reference outputs
    tb->di = bus.di();
    tb->di2 = tb->di;
    tb->eval();
    check("pre-edge");
    TraceEnt &e = ring[ring_n++ % 48];
    e.cyc = cyc; e.in = pack_in(); e.di = tb->di;
    e.a = (uint16_t)rp(P_A, 0); e.d = (uint8_t)rp(P_DO, 0);
    e.strobes = (uint8_t)(rp(P_M1) << 4 | rp(P_MREQ) << 3 | rp(P_IORQ) << 2 | rp(P_RD) << 1 | rp(P_WR));
    e.mc = (uint8_t)rf(F_MCYCLE); e.ts = (uint8_t)rf(F_TSTATE); e.pc = (uint16_t)rf(F_PC);
    tb->clk = 1;
    tb->eval();
    cyc++;
    check("posedge");
    coverage();
    bus.update();
    tb->di = bus.di();
    tb->di2 = tb->di;
    tb->eval();
    tb->clk = 0;
    tb->eval();
    check("negedge");
    if (TWO_EDGE) bus.update();
}

static void set_reset(int v) {
    if (tb->reset_n != v) { tb->reset_n = v; eval_check_async("reset change"); }
}

// ---------------------------------------------------------------- stimulus
struct Stim {
    Rng &r;
    int cen_mode = 0, cen_k = 2, phase = 0;
    double cen_p_prob = 1.0, wait_prob = 0, int_rate = 0, nmi_rate = 0, brq_rate = 0;
    int wait_left = 0, int_left = 0, nmi_left = 0, brq_left = 0;
    explicit Stim(Rng &rr) : r(rr) {}

    void new_segment() {
        cen_mode = r.u(6);
        cen_k = 2 + r.u(4);
        cen_p_prob = 0.2 + 0.8 * (r.u(1000) / 1000.0);
        static const double wp[] = {0, 0, 0.01, 0.05, 0.2, 0.5};
        wait_prob = wp[r.u(6)];
        static const double ip[] = {0, 0.0005, 0.002, 0.01, 0.05};
        int_rate = ip[r.u(5)];
        static const double np[] = {0, 0, 0.0002, 0.001, 0.01};
        nmi_rate = np[r.u(5)];
        static const double bp[] = {0, 0, 0, 0.001, 0.01, 0.05};
        brq_rate = bp[r.u(6)];
        if (CFG_PHX) {
            if (r.p(0.3)) tb->i8080 = r.u(2);
            if (r.p(0.3)) tb->i8085 = r.u(2);
            tb->rim_d = r.u(256);
        }
        if (HAS_R800) tb->r800 = r.u(2);
        if (HAS_OUT0) tb->out0 = r.p(0.3);
        static const double dp[] = {0, 0, 0.0001, 0.001};
        dir_rate = HAS_DIR ? dp[r.u(4)] : 0;
    }
    double dir_rate = 0;
    void random_dir() {
        uint32_t *w = tb->dir.data();
        for (int k = 0; k < 7; k++) w[k] = (uint32_t)r.next();
        w[6] &= 0xFFFFF;
    }
    void step() {
        // enables
        if (CFG_PA) {
            int cp = 0, cn = 0;
            switch (cen_mode) {
            case 0: cp = phase == 0; cn = phase == 1; phase ^= 1; break;                 // p n p n
            case 1: cp = phase == 0; cn = phase == cen_k - 1; phase = (phase + 1) % (cen_k + 1); break;
            case 2: cp = r.p(cen_p_prob); cn = r.p(cen_p_prob); break;                   // independent
            case 3: cp = 1; cn = 1; break;                                               // both every clock
            case 4: if (r.p(cen_p_prob)) { cp = phase == 0; cn = phase == 1; phase ^= 1; } break;
            default: cp = phase == 0 && r.p(cen_p_prob); cn = phase == 1; phase ^= 1; break;
            }
            tb->cen_p = cp; tb->cen_n = cn; tb->cen = 0;
        } else {
            int c = 1;
            switch (cen_mode) {
            case 0: c = 1; break;
            case 1: case 4: c = r.p(cen_p_prob); break;
            case 2: c = phase == 0; phase = (phase + 1) % cen_k; break;
            case 3: c = r.p(0.5); break;
            default: c = (phase == 0) || r.p(0.1); phase = (phase + 1) % cen_k; break;
            }
            tb->cen = c; tb->cen_p = r.u(2); tb->cen_n = r.u(2);
        }
        // WAIT_n stretches
        if (wait_left > 0) { wait_left--; tb->wait_n = 0; }
        else { tb->wait_n = 1; if (r.p(wait_prob)) { wait_left = r.u(r.p(0.8) ? 4 : 40); tb->wait_n = 0; } }
        // INT_n level: held for a random time
        if (int_left > 0) { if (--int_left == 0) tb->int_n = 1; }
        else if (r.p(int_rate)) { tb->int_n = 0; int_left = 1 + r.u(r.p(0.5) ? 20 : 400); }
        // NMI_n pulses
        if (nmi_left > 0) { if (--nmi_left == 0) tb->nmi_n = 1; }
        else if (r.p(nmi_rate)) { tb->nmi_n = 0; nmi_left = 1 + r.u(r.p(0.5) ? 3 : 100); }
        // BUSRQ_n stretches
        if (brq_left > 0) { if (--brq_left == 0) tb->busrq_n = 1; }
        else if (r.p(brq_rate)) { tb->busrq_n = 0; brq_left = 1 + r.u(r.p(0.7) ? 10 : 200); }
        bus.vec = r.p(0.5) ? (uint8_t)(0xC7 | (r.u(8) << 3)) : (uint8_t)r.u(256);
        // DIRSet: load all registers from DIR, held 1..3 clocks
        if (tb->dirset && r.p(0.5)) tb->dirset = 0;
        else if (r.p(dir_rate)) { tb->dirset = 1; random_dir(); }
    }
};

// random program: instruction streams with every opcode page equally likely, mixed with raw random bytes
static void fill_random(Rng &r) {
    int a = 0;
    while (a < 65536) {
        int page = r.u(9);
        uint8_t buf[8];
        int n = 0;
        static const uint8_t pre[] = {0, 0xCB, 0xED, 0xDD, 0xFD};
        if (CFG_MODE == 2 || page >= 7 || (CFG_MODE == 3 && page != 1 && page != 0)) {
            buf[n++] = (uint8_t)r.u(256);
        } else if (page <= 4) {
            if (page) buf[n++] = pre[page];
            buf[n++] = (uint8_t)r.u(256);
        } else {
            buf[n++] = page == 5 ? 0xDD : 0xFD; buf[n++] = 0xCB; buf[n++] = (uint8_t)r.u(256);
            buf[n++] = (uint8_t)r.u(256);
        }
        int extra = r.u(3);
        for (int k = 0; k < extra; k++) buf[n++] = (uint8_t)r.u(256);
        for (int k = 0; k < n && a < 65536; k++) mem[a++] = buf[k];
    }
    // sprinkle IM n / EI so interrupts of every mode get taken
    for (int k = 0; k < (CFG_MODE >= 2 ? 0 : 300); k++) {
        int x = r.u(65530);
        static const uint8_t ims[] = {0x46, 0x56, 0x5E, 0x4E, 0x66, 0x6E, 0x76, 0x7E};
        mem[x] = 0xED; mem[x + 1] = ims[r.u(8)]; mem[x + 2] = 0xFB;
    }
}

static void idle_inputs() {
    tb->cen = 1; tb->cen_p = 0; tb->cen_n = 0; tb->wait_n = 1; tb->int_n = 1; tb->nmi_n = 1;
    tb->busrq_n = 1; tb->i8080 = 0; tb->i8085 = 0; tb->rim_d = 0; tb->out0 = 0; tb->r800 = 0; tb->dirset = 0;
}

static void power_on() {
    idle_inputs();
    tb->clk = 0; tb->reset_n = 0;                    // reset asserted from time 0 (no edge)
    tb->eval();
    check("power-on");
    for (int i = 0; i < 4; i++) tick();
}

// pa needs cen_p / cen_n to run; the other fronts use cen
static void enables_free_run(int &ph) {
    if (CFG_PA) { tb->cen_p = ph == 0; tb->cen_n = ph == 1; ph ^= 1; }
    else tb->cen = 1;
}

static int run_random(uint64_t seed, uint64_t cycles) {
    Rng r(seed);
    bus.rng = &r;
    bus.float_rand = true;
    fill_random(r);
    power_on();
    Stim s(r);
    s.new_segment();
    set_reset(1);
    uint64_t seg_left = 1000 + r.u(30000);
    uint64_t next_reset = 20000 + r.u(400000);
    uint64_t next_fill = 2000 + r.u(20000);
    for (uint64_t i = 0; i < cycles; i++) {
        if (--next_fill == 0) { fill_random(r); next_fill = 2000 + r.u(20000); }  // new code under the running CPU
        if (--seg_left == 0) { s.new_segment(); seg_left = 1000 + r.u(50000); }
        s.step();
        if (--next_reset == 0) {
            // asynchronous reset mid-instruction, applied between clock edges
            set_reset(0);
            int n = 1 + r.u(6);
            for (int k = 0; k < n; k++) { s.step(); tick(); }
            if (r.p(0.3)) fill_random(r);
            set_reset(1);
            next_reset = 5000 + r.u(400000);
            continue;
        }
        tick();
    }
    return 0;
}

// ---------------------------------------------------------------- CP/M .COM runner
static int run_com(const char *path, int pattern, uint64_t max_cycles) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return 2; }
    memset(mem, 0, sizeof(mem));
    size_t n = fread(mem + 0x100, 1, 0x10000 - 0x100, f);
    fclose(f);
    (void)n;
    static const uint8_t stop[] = {0x3E, 0x00, 0xD3, 0x01, 0x76};                 // 0000: LD A,0; OUT (1),A; HALT
    static const uint8_t bdos[] = {0x7B, 0xD3, 0x02, 0x7A, 0xD3, 0x03, 0x79, 0xD3, 0x01, 0xC9}; // E, D, C -> ports 2, 3, 1; RET
    mem[0] = 0xC3; mem[1] = 0x00; mem[2] = 0x01;                                 // 0000: JP 0100h (until started)
    mem[5] = 0xC3; mem[6] = 0x00; mem[7] = 0xFE;                                 // 0005: JP FE00h; (0006h) = top of TPA
    memcpy(mem + 0xFE00, bdos, sizeof(bdos));
    static Rng r(1);
    bus.rng = &r;
    bus.float_rand = false;
    bus.rand_io = false;
    bus.cpm = true;
    power_on();
    if (getenv("FORCE_I8080")) tb->i8080 = 1;           // Phoenix: 8080 mode for the 8080 exercisers
    if (getenv("FORCE_I8085")) tb->i8085 = 1;
    set_reset(1);
    int ph = 0;
    bool booted = false;
    uint64_t i = 0;
    Rng pr(7);
    for (; i < max_cycles && !bus.stop; i++) {
        if (pattern == 0) enables_free_run(ph);
        else {  // ce gaps
            if (CFG_PA) { tb->cen_p = ph == 0 && pr.p(0.8); tb->cen_n = ph == 1; ph ^= 1; }
            else tb->cen = pr.p(0.6);
        }
        tick();
        if (!booted && rf(F_PC) > 3) {
            booted = true;
            memcpy(mem, stop, sizeof(stop));                                       // warm boot (JP 0) now stops
        }
    }
    printf("\n%s: %llu cycles, %s\n", CFG_NAME, (unsigned long long)i, bus.stop ? "stopped via BDOS 0" : "CYCLE LIMIT");
    return bus.stop ? 0 : 4;
}

// ---------------------------------------------------------------- directed timing sweeps
// Each case: a short program around one instruction under test (every opcode of every page), entered with the
// interrupt mode / IFF state of the case, and one event (INT, NMI, WAIT, BUSRQ) asserted starting at a chosen
// clock offset from the instruction's first M1 (clock offsets cover every T-state and enable phase of the
// instruction). Cycle-exact comparison throughout.
static const int SWEEP_EVENTS = 5;
static int SWEEP_OFFSETS = 64;    // clocks after the instruction's first M1: every T-state / enable phase  // 0 INT, 1 NMI, 2 WAIT, 3 BUSRQ, 4 INT + NMI together
static uint64_t sweep_runs[SWEEP_EVENTS];

static void sweep_case(int page, int op, int im, int event, int offset, int dur, int cenpat, Rng &r) {
    for (int i = 0; i < 65536; i++) mem[i] = 0x00;
    // registers: random but sane; BC small so block instructions finish
    uint16_t a = 0x0000;
    auto put = [&](uint8_t b) { mem[a++] = b; };
    put(0x31); put(0x00); put(0xF0);                                      // LD SP,F000
    bool z80 = CFG_MODE < 2;
    if (z80) {
        if (im == 0) { put(0xED); put(0x46); } else if (im == 1) { put(0xED); put(0x56); } else { put(0xED); put(0x5E); }
        put(0x3E); put(0x40); put(0xED); put(0x47);                       // LD A,40 ; LD I,A
    }
    put(0x01); put(1 + r.u(3)); put(0x00);                                // LD BC,n
    put(0x11); put(r.u(256)); put(0x50);                                  // LD DE,50xx
    put(0x21); put(r.u(256)); put(0x60);                                  // LD HL,60xx
    if (z80) {
        put(0xDD); put(0x21); put(r.u(256)); put(0x70);                   // LD IX,70xx
        put(0xFD); put(0x21); put(r.u(256)); put(0x78);                   // LD IY,78xx
    }
    put(0x3E); put(r.u(256));                                             // LD A,n
    if (r.p(0.7)) put(0xFB); else put(0xF3);                              // EI / DI
    put(0x00);
    uint16_t at = a;
    switch (page) {
    case 0: put(op); break;
    case 1: put(0xCB); put(op); break;
    case 2: put(0xED); put(op); break;
    case 3: put(0xDD); put(op); break;
    case 4: put(0xFD); put(op); break;
    case 5: put(0xDD); put(0xCB); put(r.u(256)); put(op); break;
    case 6: put(0xFD); put(0xCB); put(r.u(256)); put(op); break;
    }
    for (int k = 0; k < 4; k++) put(r.u(256));                            // operands
    for (int k = 0; k < 16; k++) put(0x00);
    // interrupt / NMI handlers and jump targets land on NOP sleds: memory is 00 elsewhere
    bus.float_rand = true;
    bus.rand_io = true;
    bus.cpm = false;
    bus.prev_io_w = false;
    power_on();
    if (HAS_R800) tb->r800 = r.u(2);
    set_reset(1);
    int ph = 0;
    int started = -1;
    int t = 0;
    Rng pr(op * 131 + offset);
    for (int i = 0; i < 600 && (started < 0 || i < started + offset + dur + 120); i++) {
        // enables
        if (cenpat == 0) enables_free_run(ph);
        else if (CFG_PA) { tb->cen_p = ph == 0 && (cenpat == 1 ? (t % 3 != 2) : pr.p(0.7)); tb->cen_n = ph == 1; ph ^= 1; }
        else tb->cen = cenpat == 1 ? (t % 3 != 2) : pr.p(0.6);
        t++;
        // event relative to the first M1 of the instruction under test
        if (started < 0 && rf(F_PC) == at && rf(F_MCYCLE) == 1 && rf(F_TSTATE) <= 1) started = i;
        int rel = started < 0 ? -1 : i - started;
        bool on = rel >= offset && rel < offset + dur;
        tb->int_n = !(on && (event == 0 || event == 4));
        tb->nmi_n = !(on && (event == 1 || event == 4));
        tb->wait_n = !(on && event == 2);
        tb->busrq_n = !(on && event == 3);
        bus.vec = im == 0 ? (uint8_t)(0xC7 | (r.u(8) << 3)) : (uint8_t)r.u(256);
        tick();
    }
    sweep_runs[event]++;
}

static int run_sweep(int first, int count) {
    Rng r(first * 7919 + 1);
    bus.rng = &r;
    int pages = CFG_MODE == 2 ? 1 : (CFG_MODE == 3 ? 2 : 7);
    int ncase = 0;
    for (int page = 0; page < pages; page++)
        for (int op = 0; op < 256; op++) {
            if (ncase++ % count != first) continue;
            for (int event = 0; event < SWEEP_EVENTS; event++) {
                if (event == 3 && CFG_KIND == 1) continue;   // T8080se has no bus request
                for (int im = 0; im < 3; im++) {
                    if (event != 0 && event != 4 && im != 1) continue;
                    if (CFG_MODE >= 2 && im != 1) continue;           // no IM n outside Z80 modes
                    for (int offset = 0; offset < SWEEP_OFFSETS; offset++) {
                        int dur = event == 1 ? 1 + (offset % 3) : (event == 2 ? 1 + (offset % 4) : 1 + r.u(40));
                        int cenpat = (offset + op) % 3;
                        sweep_case(page, op, im, event, offset, dur, cenpat, r);
                    }
                }
            }
        }
    printf("SWEEP %s part %d/%d: INT %llu NMI %llu WAIT %llu BUSRQ %llu INT+NMI %llu cases\n", CFG_NAME, first, count,
           (unsigned long long)sweep_runs[0], (unsigned long long)sweep_runs[1], (unsigned long long)sweep_runs[2],
           (unsigned long long)sweep_runs[3], (unsigned long long)sweep_runs[4]);
    return 0;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(1, argv);
    tb = new Vtb;
    int off = 0;
    for (int i = NF - 1; i >= 0; i--) { f_off[i] = off; off += ST_FIELDS[i].w; }
    F_MCYCLE = fidx("MCycle"); F_TSTATE = fidx("TState"); F_IR = fidx("IR"); F_ISET = fidx("ISet");
    F_XY = fidx("XY_State"); F_HALT = fidx("Halt_FF"); F_INTC = fidx("IntCycle"); F_NMIC = fidx("NMICycle");
    F_ISTAT = fidx("IStatus"); F_PC = fidx("PC"); F_DOR = fidx("DOR"); F_IFF1 = fidx("IntE_FF1");
    { int off2 = 0; for (int i = NPF - 1; i >= 0; i--) { p_off[i] = off2; off2 += PIN_FIELDS[i].w; } }
    P_A = pidx("A"); P_DO = pidx("DO"); P_M1 = pidx("M1_n"); P_MREQ = pidx("MREQ_n"); P_IORQ = pidx("IORQ_n");
    P_RD = pidx("RD_n"); P_WR = pidx("WR_n"); P_DBIN = pidx("DBIN"); P_SYNC = pidx("SYNC"); P_IORQH = pidx("IORQ");
    P_WRITE = pidx("Write"); P_INTCN = pidx("IntCycle_n"); P_MC = pidx("MC");
    F_DOUT = CFG_KIND == 3 ? fidx("dout") : -1;
    if (argc < 2) { fprintf(stderr, "usage: sim random|com|sweep ...\n"); return 2; }
    std::string m = argv[1];
    int rc = 0;
    const char *covf = getenv("COV_OUT");
    if (m == "random") {
        uint64_t seed = argc > 2 ? strtoull(argv[2], 0, 0) : 1;
        uint64_t n = argc > 3 ? strtoull(argv[3], 0, 0) : 1000000;
        rc = run_random(seed, n);
        printf("RANDOM %s seed %llu: %llu cycles, %llu compares, 0 mismatches\n", CFG_NAME, (unsigned long long)seed,
               (unsigned long long)cyc, (unsigned long long)compares);
        cov_report("random");
    } else if (m == "com" || m == "comfast") {
        fast = m == "comfast";
        int pat = argc > 3 ? atoi(argv[3]) : 0;
        uint64_t lim = argc > 4 ? strtoull(argv[4], 0, 0) : 200000000000ull;
        rc = run_com(argv[2], pat, lim);
        printf("COM %s %s: %llu cycles, %llu compares, 0 mismatches\n", CFG_NAME, argv[2], (unsigned long long)cyc,
               (unsigned long long)compares);
        cov_report("com");
    } else if (m == "sweep") {
        int first = argc > 2 ? atoi(argv[2]) : 0, count = argc > 3 ? atoi(argv[3]) : 1;
        if (argc > 4) SWEEP_OFFSETS = atoi(argv[4]);
        fail_quiet = false;
        rc = run_sweep(first, count);
        printf("SWEEPDONE %s: %llu cycles, %llu compares, 0 mismatches\n", CFG_NAME, (unsigned long long)cyc,
               (unsigned long long)compares);
        cov_report("sweep");
    }
    if (covf) cov_dump(covf);
    delete tb;
    return rc;
}

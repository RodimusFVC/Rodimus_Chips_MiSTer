// rtl/dsnd_engine.sv against the instruction-set model (dsnd_model.h), sample by sample, on out and out_r.
//   Vdsnd_engine --fuzz=<programs> [--ops=<op>,<op>...]          random programs, random sources
//   Vdsnd_engine --prog=<bin> --len=<s> [--ev=<t>:<src>:<hex> ...] [--evfile=<file>] [--wav=<file>]
//       ev: at time t (s) source <src> (0-7) takes the value; evfile: "<t> <src> <hex>" or "<t>:<src>:<hex>" per line
//   Build: -GTICK=<n> -CFLAGS "-DTICK=<n> -DCLK_HZ=<core clock> [-DWAV_CH=1]" (sample rate FS = CLK_HZ / TICK)
//   --wav: WAV_CH 2 (default) = stereo (L = out, R = out_r), WAV_CH 1 = mono (out)
#include <verilated.h>
#include "Vdsnd_engine.h"
#include "dsnd_model.h"
#ifndef TICK
#define TICK 832
#endif
#ifndef CLK_HZ
#error "CLK_HZ (the core's engine clock in Hz) must be defined"
#endif
#ifndef WAV_CH
#define WAV_CH 2
#endif
static const double FS = (double)CLK_HZ / TICK;
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <string>
#include <vector>

static Vdsnd_engine *top;
static inline void tick() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }

// load with the engine held in reset, then align: the next clock after this is the sample tick
static void load(const std::vector<uint64_t> &p)
{
    top->reset = 1; top->pause = 0;
    for (size_t i = 0; i < p.size() * 8; i++) {
        top->prog_wr = 1; top->prog_addr = i; top->prog_data = (uint8_t)(p[i / 8] >> (8 * (i % 8))); tick();
    }
    top->prog_wr = 0; tick();
    top->reset = 0;
    for (int i = 0; i < TICK - 1; i++) tick();
}

static void wav(const std::string &fn, const std::vector<int16_t> &s)
{
    FILE *f = fopen(fn.c_str(), "wb");
    if (!f) { perror(fn.c_str()); return; }
    uint32_t n = s.size() * 2, sr = (uint32_t)(FS + 0.5), br = sr * 2 * WAV_CH, c16 = 16, sz = 36 + n;
    uint16_t one = 1, ch = WAV_CH, blk = 2 * WAV_CH, bits = 16;
    fwrite("RIFF", 1, 4, f); fwrite(&sz, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&c16, 4, 1, f);
    fwrite(&one, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&sr, 4, 1, f); fwrite(&br, 4, 1, f);
    fwrite(&blk, 2, 1, f); fwrite(&bits, 2, 1, f); fwrite("data", 1, 4, f); fwrite(&n, 4, 1, f);
    fwrite(s.data(), 2, s.size(), f); fclose(f);
}

// run n samples in lockstep; ev(k) updates the sources before sample k
static int steady_max = 0;                          // most instructions in a sample after the first four
template <class F>
static long run(Dsnd &m, long n, uint8_t src[8], F ev, std::vector<int16_t> *rec)
{
    long bad = 0;
    for (long k = 0; k < n; k++) {
        ev(k);
        uint64_t sv = 0; for (int i = 0; i < 8; i++) sv |= (uint64_t)src[i] << (8 * i);
        top->src = sv;
        for (int i = 0; i < TICK; i++) tick();          // one sample period: the program ran on its tick
        m.step(src);
        if (k >= 4 && m.last > steady_max) steady_max = m.last;
        if (rec) { rec->push_back(top->out); if (WAV_CH == 2) rec->push_back(top->out_r); }
        if (((int16_t)top->out != m.out || (int16_t)top->out_r != m.out_r) && bad++ < 5)
            printf("mismatch at sample %ld: rtl %d/%d model %d/%d\n", k, (int16_t)top->out, (int16_t)top->out_r, m.out, m.out_r);
    }
    return bad;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    int fuzz = 0; double len = 1.0; std::vector<int> opset; std::string prog, wavf;
    struct Ev { double t; int s; int v; };
    std::vector<Ev> evs;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("--fuzz=", 0) == 0) fuzz = atoi(a.c_str() + 7);
        else if (a.rfind("--ops=", 0) == 0) { for (char *t = strtok(&a[6], ","); t; t = strtok(nullptr, ",")) opset.push_back(atoi(t)); }
        else if (a.rfind("--prog=", 0) == 0) prog = a.substr(7);
        else if (a.rfind("--len=", 0) == 0) len = atof(a.c_str() + 6);
        else if (a.rfind("--wav=", 0) == 0) wavf = a.substr(6);
        else if (a.rfind("--ev=", 0) == 0) { Ev e; sscanf(a.c_str() + 5, "%lf:%d:%x", &e.t, &e.s, &e.v); evs.push_back(e); }
        else if (a.rfind("--evfile=", 0) == 0) {
            FILE *ef = fopen(a.c_str() + 9, "r"); if (!ef) { perror(a.c_str() + 9); return 1; }
            char ln[256];
            while (fgets(ln, sizeof ln, ef)) {
                for (char *c = ln; *c; c++) if (*c == ':') *c = ' ';
                Ev e; if (sscanf(ln, "%lf %d %x", &e.t, &e.s, &e.v) == 3) evs.push_back(e);
            }
            fclose(ef);
        }
    }
    long bad = 0, total = 0;
    if (fuzz) {
        std::mt19937 rng(1234);
        for (int p = 0; p < fuzz; p++) {
            top = new Vdsnd_engine;
            Dsnd m;
            int len_p = 20 + rng() % 360;
            for (int i = 0; i < len_p; i++) {
                uint64_t op = opset.empty() ? rng() % 34 : opset[rng() % opset.size()], a = rng() % 16, b = rng() % 64;
                int32_t imm = (int32_t)rng() >> (rng() % 24);
                if (op == 0) op = 1;
                if (op == 22 || op == 23) imm = rng() % 4;
                m.prog[i] = (op << 56) | (a << 48) | (b << 40) | (uint32_t)imm;
            }
            for (int r = 0; r < 4; r++) {                           // tail: show the state
                m.prog[len_p + 3 * r] = (1ull << 56) | ((uint64_t)r << 48);
                m.prog[len_p + 3 * r + 1] = (6ull << 56) | (uint32_t)(1 << 12);
                m.prog[len_p + 3 * r + 2] = (20ull << 56);
            }
            m.prog[len_p + 12] = 0;
            load(m.prog);
            uint8_t src[8] = {};
            bad += run(m, 200, src, [&](long k) { if (k % 7 == 0) for (int i = 0; i < 8; i++) src[i] = rng(); }, nullptr);
            total += 200;
            delete top;
        }
    } else {
        FILE *f = fopen(prog.c_str(), "rb");
        if (!f) { fprintf(stderr, "no program %s\n", prog.c_str()); return 1; }
        Dsnd m; std::vector<uint64_t> p(1024, 0);
        size_t n = fread(p.data(), 8, 1024, f); fclose(f); (void)n;
        m.prog = p;
        top = new Vdsnd_engine;
        load(p);
        uint8_t src[8] = {};
        size_t e = 0; std::vector<int16_t> rec;
        long ns = (long)(len * FS);
        bad = run(m, ns, src, [&](long k) {
            while (e < evs.size() && evs[e].t * FS <= k) { src[evs[e].s] = evs[e].v; e++; }
        }, &rec);
        total = ns;
        int pk = 0; for (auto v : rec) pk = std::max(pk, std::abs((int)v));
        printf("peak %d, most instructions in a sample %d (after sample 4: %d)\n", pk, m.maxn, steady_max);
        if (!wavf.empty()) wav(wavf, rec);
        delete top;
    }
    printf("lockstep: %ld samples, %ld mismatches\n", total, bad);
    return bad != 0;
}

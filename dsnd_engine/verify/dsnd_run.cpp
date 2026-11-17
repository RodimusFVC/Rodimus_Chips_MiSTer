// Model-only renderer (dsnd_model.h, no RTL): the lockstep's program / event / WAV arguments, plus register dumps,
// for fast iteration on a board program. check.py proves its WAV equals the lockstep's.
//   dsnd_run --prog=<bin> --len=<s> [--ev=<t>:<src>:<hex> ...] [--evfile=<file>] [--wav=<file>]
//            [--dump=<file> --regs=<r>,<r>,...]
//       evfile: "<t> <src> <hex>" or "<t>:<src>:<hex>" per line
//       dump: M[r] of every sample as float32 volts (Q24 / 2^24), one row of len(regs) values per sample
//   Build: g++ -O2 -std=gnu++17 -DTICK=<n> -DCLK_HZ=<core clock> [-DWAV_CH=1] -I<verify> dsnd_run.cpp
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
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

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

int main(int argc, char **argv)
{
    double len = 1.0; std::string prog, wavf, dumpf; std::vector<int> regs;
    struct Ev { double t; int s; int v; };
    std::vector<Ev> evs;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a.rfind("--prog=", 0) == 0) prog = a.substr(7);
        else if (a.rfind("--len=", 0) == 0) len = atof(a.c_str() + 6);
        else if (a.rfind("--wav=", 0) == 0) wavf = a.substr(6);
        else if (a.rfind("--dump=", 0) == 0) dumpf = a.substr(7);
        else if (a.rfind("--regs=", 0) == 0) { for (char *t = strtok(&a[7], ","); t; t = strtok(nullptr, ",")) regs.push_back(atoi(t)); }
        else if (a.rfind("--ev=", 0) == 0) { Ev e; if (sscanf(a.c_str() + 5, "%lf:%d:%x", &e.t, &e.s, &e.v) == 3) evs.push_back(e); }
        else if (a.rfind("--evfile=", 0) == 0) {
            FILE *ef = fopen(a.c_str() + 9, "r"); if (!ef) { perror(a.c_str() + 9); return 1; }
            char ln[256];
            while (fgets(ln, sizeof ln, ef)) {
                for (char *c = ln; *c; c++) if (*c == ':') *c = ' ';
                Ev e; if (sscanf(ln, "%lf %d %x", &e.t, &e.s, &e.v) == 3) evs.push_back(e);
            }
            fclose(ef);
        }
        else { fprintf(stderr, "unknown argument %s\n", argv[i]); return 1; }
    }
    FILE *f = fopen(prog.c_str(), "rb");
    if (!f) { fprintf(stderr, "no program %s\n", prog.c_str()); return 1; }
    Dsnd m; std::vector<uint64_t> p(1024, 0);
    size_t n = fread(p.data(), 8, 1024, f); fclose(f); (void)n;
    m.prog = p;
    FILE *df = nullptr;
    if (!dumpf.empty()) { df = fopen(dumpf.c_str(), "wb"); if (!df) { perror(dumpf.c_str()); return 1; } }
    uint8_t src[8] = {};
    size_t e = 0; std::vector<int16_t> rec; int steady_max = 0;
    long ns = (long)(len * FS);
    for (long k = 0; k < ns; k++) {
        while (e < evs.size() && evs[e].t * FS <= k) { src[evs[e].s] = evs[e].v; e++; }
        m.step(src);
        if (k >= 4 && m.last > steady_max) steady_max = m.last;
        rec.push_back(m.out); if (WAV_CH == 2) rec.push_back(m.out_r);
        if (df) for (int r : regs) { float v = m.M[r] / 16777216.0f; fwrite(&v, 4, 1, df); }
    }
    if (df) fclose(df);
    int pk = 0; for (auto v : rec) pk = std::max(pk, std::abs((int)v));
    printf("peak %d, most instructions in a sample %d (after sample 4: %d)\n", pk, m.maxn, steady_max);
    printf("model: %ld samples\n", ns);
    if (!wavf.empty()) wav(wavf, rec);
    return 0;
}

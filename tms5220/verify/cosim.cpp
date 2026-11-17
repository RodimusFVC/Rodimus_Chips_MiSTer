// cosim.cpp: MAME's TMS5220 (oracle5220.cpp, extracted verbatim) vs ../rtl/tms5220.sv, lockstep per sample.
// Stimulus: MAME-captured sound-Z80 traffic (W = data_w, R = status_r) with emulated time; event at time t is applied
// before sample ceil(t * rate). Compares every sample's output, the status byte and /INT.
//   ./obj/Vtms5220 [traffic.txt] [rate=7500] [--dump out.raw]
#include "Vtms5220.h"
#include "verilated.h"
#include "oracle5220.cpp"
#include <cmath>
#include <cstring>
#include <vector>
#include <string>

static Vtms5220 *r;
static void tick() { r->clk = 0; r->eval(); r->clk = 1; r->eval(); }
static void idle(int n) { for (int i = 0; i < n; i++) tick(); }

int main(int argc, char **argv)
{
    const char *trf = argc > 1 && argv[1][0] != '-' ? argv[1] : "polepos2bi_tms_traffic.txt";
    double rate = 7500.0;
    FILE *dump = nullptr;
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "--dump") && i + 1 < argc) dump = fopen(argv[++i], "wb");
    struct Ev { long n; char k; int d; };
    std::vector<Ev> ev;
    FILE *f = fopen(trf, "r"); if (!f) { fprintf(stderr, "no %s\n", trf); return 1; }
    char k; double t; unsigned d;
    while (fscanf(f, " %c %lf %x", &k, &t, &d) == 3) if (k == 'W' || k == 'R') ev.push_back({(long)ceil(t * rate), k, (int)d});
    fclose(f);
    long nsamp = ev.empty() ? 0 : ev.back().n + (long)(rate * 1.0);
    printf("%zu events, %ld samples (%.1f s)\n", ev.size(), nsamp, nsamp / rate);

    tms5220_oracle o;
    r = new Vtms5220;
    r->reset = 1; r->wr = 0; r->rd = 0; r->ce_sample = 0; idle(4); r->reset = 0; idle(4);

    long mism = 0, smism = 0, imism = 0, speech = 0, maxabs = 0;
    size_t e = 0;
    for (long n = 0; n < nsamp; n++) {
        while (e < ev.size() && ev[e].n <= n) {
            if (ev[e].k == 'W') { o.write(ev[e].d); r->din = ev[e].d; r->wr = 1; tick(); r->wr = 0; }
            else                { o.status();         r->rd = 1; tick(); r->rd = 0; }
            idle(3);
            e++;
        }
        int16_t want = o.sample();
        r->ce_sample = 1; tick(); r->ce_sample = 0;
        int guard = 0;
        while (!r->audio_valid && guard++ < 200) tick();
        idle(2);
        int16_t got = (int16_t)r->audio;
        if (dump) fwrite(&want, 2, 1, dump);
        if (want != -1) speech++;
        if (abs(want) > maxabs) maxabs = abs(want);
        uint8_t ostat = (o.talk_status() << 7) | (o.m_buffer_low << 6) | (o.m_buffer_empty << 5);
        if (o.m_RDB_flag) ostat = o.m_read_byte_register;
        if (got != want || guard >= 200) {
            if (mism < 12) printf("SAMPLE %ld: oracle %d rtl %d%s\n", n, want, got, guard >= 200 ? " (rtl timeout)" : "");
            mism++;
        }
        if (r->dout != ostat) { if (smism < 6) printf("STATUS %ld: oracle %02X rtl %02X\n", n, ostat, r->dout); smism++; }
        if ((!r->int_n) != o.irq()) { if (imism < 6) printf("INT %ld: oracle %d rtl %d\n", n, o.irq(), !r->int_n); imism++; }
    }
    printf("samples %ld (non-idle %ld, max |x| %ld): sample mismatches %ld, status mismatches %ld, int mismatches %ld\n",
           nsamp, speech, maxabs, mism, smism, imism);
    if (dump) fclose(dump);
    return (mism || smism || imism) ? 1 : 0;
}

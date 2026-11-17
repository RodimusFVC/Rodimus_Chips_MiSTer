// Frame-level oracle: every crtc6845sv variant against the MAME mc6845.cpp transliteration of its type.
// For each pair (variant, MAME type) one model runs with the pair's full knob set (must give 0 mismatches) and one
// model per knob runs with that knob reverted to MAME (measures that documented difference on its own).
// Registers R0-R15 are stable per scenario (MAME's model is line-timer based); host reads, R18/R19/R31 accesses,
// light pen strobes and PHI2 run mid-frame.
#include "Vtb_variants.h"
#include "verilated.h"
#include "stim.h"
#include "../mame/mame6845.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <vector>

struct Pair { const char *name; int variant; MameType mt; std::vector<std::string> knobs; };

// read-path deviations are knobs too (handled in expected_read)
static bool set_knob(Knobs &k, const std::string &n, bool v) {
#define K(x) if (n == #x) { k.x = v; return true; }
    K(hsw0_none) K(vsw_prog) K(frame_match) K(blink_ds) K(cursor_line) K(cursor_fleet) K(first_off) K(engine_t0)
    K(adj_hold) K(de_fleet) K(vs_r2) K(il_fleet) K(hs_cont) K(hs_strict) K(r6z) K(vma_row0) K(rowcol)
    K(upd_needs_mode) K(lp_now) K(vs_hdl) K(first_ma0) K(r1z_no_de) K(upd_access3)
#undef K
    return false;
}

static const std::vector<std::string> FLEET = {"hsw0_none", "blink_ds", "cursor_fleet", "engine_t0", "de_fleet", "vs_r2",
    "il_fleet", "hs_cont", "vs_hdl", "lp_now", "skew", "rd_rs0_reg", "first_ma0"};

static std::vector<Pair> pairs() {
    std::vector<Pair> p;
    std::vector<std::string> f = FLEET;
    std::vector<std::string> fm = FLEET; fm.push_back("vsw_prog"); fm.push_back("rd_r12");
    p.push_back({"V0 fleet  vs MAME hd6845s", 0, M_HD6845S, f});
    p.push_back({"V0 fleet  vs MAME mc6845 ", 0, M_MC6845, fm});
    p.push_back({"V1 MC6845 vs MAME mc6845 ", 1, M_MC6845, {"blink_ds", "cursor_line", "first_off", "frame_match",
        "il_fleet", "hs_cont", "vs_hdl", "lp_now", "first_ma0"}});
    p.push_back({"V2 HD6845S vs MAME hd6845s", 2, M_HD6845S, {"blink_ds", "cursor_line", "first_off", "engine_t0",
        "hsw0_none", "il_fleet", "hs_cont", "vs_hdl", "lp_now", "skew", "first_ma0"}});
    p.push_back({"V3 UM6845R vs MAME mc6845 ", 3, M_MC6845, {"blink_ds", "cursor_line", "first_off",
        "hsw0_none", "r6z", "vma_row0", "il_fleet", "hs_cont", "vs_hdl", "lp_now", "rd_status_um",
        "rd_r31ff", "first_ma0"}});
    p.push_back({"V4 AMS40489 vs MAME ams40489", 4, M_AMS40489, {"vsw_prog", "blink_ds", "cursor_line", "first_off",
        "engine_t0", "adj_hold", "il_fleet", "hs_cont", "vs_hdl", "lp_now", "skew", "rd_mirror", "first_ma0"}});
    p.push_back({"V5 40226  vs MAME ams40489", 5, M_AMS40489, {"vsw_prog", "blink_ds", "cursor_line", "first_off",
        "engine_t0", "adj_hold", "il_fleet", "hs_cont", "vs_hdl", "lp_now", "skew", "rd_mirror", "first_ma0"}});
    std::vector<std::string> r65 = {"blink_ds", "cursor_line", "first_off", "engine_t0", "rowcol", "upd_needs_mode",
        "upd_access3", "r1z_no_de", "hs_cont", "vs_hdl", "lp_now", "skew", "rd_r31hold", "first_ma0"};
    p.push_back({"V6 R6545-1 vs MAME r6545_1", 6, M_R6545_1, r65});
    p.push_back({"V6 SY6545-1 vs MAME sy6545_1", 6, M_SY6545_1, r65});
    p.push_back({"V7 C6545-1 vs MAME c6545_1", 7, M_C6545_1, {"blink_ds", "cursor_line", "first_off", "engine_t0",
        "rowcol", "hs_cont", "vs_hdl", "lp_now", "skew", "first_ma0"}});
    return p;
}

struct Run {
    const Pair *pr;
    std::string reverted;                 // "" = full knob set
    std::map<std::string, bool> on;       // effective knob state
    std::unique_ptr<Mame6845> m;
    uint8_t dh[3] = {0}, ch[3] = {0};     // DE / CURSOR history (skew)
    uint64_t chars = 0, mism = 0, reads = 0, rmism = 0, frames = 0;
    std::map<std::string, uint64_t> sig;
    int shown = 0;
    bool k(const char *n) const { auto it = on.find(n); return it != on.end() && it->second; }
};

static uint8_t r12_raw = 0;   // the byte last written to R12 (type 3/4 read back bits 7:6)

static int expected_read(Run &r, int rs, int idx, int &valid) {
    Mame6845 &m = *r.m;
    valid = 1;
    int v = r.pr->variant;
    if (!rs && !r.k("rd_rs0_reg") && !(r.k("rd_mirror"))) {
        if (r.k("rd_status_um")) return (m.light_pen_latched ? 0x40 : 0) | (!m.line_enable_ff ? 0x20 : 0);
        return m.status_r();
    }
    if (r.k("rd_mirror")) {
        switch (idx & 7) {
        case 0: { uint8_t x = m.register_r_at(0x10); return x; }
        case 1: { uint8_t x = m.register_r_at(0x11); return x; }
        case 2: case 3: valid = 0; return 0;
        case 4: return (r12_raw & 0xc0) | ((m.disp_start_addr >> 8) & 0x3f);
        case 5: return m.disp_start_addr & 0xff;
        case 6: return (m.cursor_addr >> 8) & 0x3f;
        default: return m.cursor_addr & 0xff;
        }
    }
    if (idx == 31 && r.k("rd_r31hold")) { m.register_r(); valid = 0; return 0; }
    if (idx == 31 && r.k("rd_r31ff")) { m.register_r(); return 0xff; }
    if ((idx == 12 || idx == 13) && r.k("rd_r12"))
        return idx == 12 ? (m.disp_start_addr >> 8) & 0x3f : m.disp_start_addr & 0xff;
    (void)v;
    return m.register_r();
}

int main(int argc, char **argv) {
    uint64_t seed = argc > 1 ? strtoull(argv[1], 0, 0) : 1;
    int nrand = argc > 2 ? atoi(argv[2]) : 200;
    const char *only = argc > 3 ? argv[3] : nullptr;     // optional: scenario table file (fleet scenarios)
    Verilated::commandArgs(argc, argv);
    Vtb_variants *t = new Vtb_variants;
    Stim gen(seed);
    gen.allow_reads = true;
    std::vector<Pair> P = pairs();

    // scenario list: name + 16 registers (+ R18/R19)
    struct Scn { std::string name; int r[16]; int r18, r19; };
    std::vector<Scn> S;
    if (only) {
        FILE *f = fopen(only, "r");
        char nm[128];
        Scn s;
        while (f && fscanf(f, "%127s", nm) == 1) {
            s.name = nm;
            for (int i = 0; i < 16; i++) if (fscanf(f, "%i", &s.r[i]) != 1) return 2;
            s.r18 = 0; s.r19 = 0;
            S.push_back(s);
        }
        if (f) fclose(f);
    } else {
        int di = 0;
        for (auto &d : Stim::directed_tables()) {
            Scn s; s.name = "directed" + std::to_string(di++);
            for (int i = 0; i < 16; i++) s.r[i] = d[i];
            s.r18 = 0; s.r19 = 0x40;
            S.push_back(s);
        }
        for (int i = 0; i < nrand; i++) {
            Scn s; s.name = "random" + std::to_string(i);
            gen.profile = (int)gen.rng.u(P_FLEET);
            if (gen.profile == P_BIG) gen.profile = P_REAL;
            for (int j = 0; j < 16; j++) { s.r[j] = gen.reg_val(j) & 0xff; gen.shadow[j] = s.r[j]; }
            if (gen.rng.p(0.3)) s.r[8] = (s.r[8] & 0xf7) | 0x08 | (gen.rng.p(0.5) ? 0x40 : 0);
            s.r18 = gen.rng.u(64); s.r19 = gen.rng.u(256);
            S.push_back(s);
        }
    }

    // runs
    std::vector<std::unique_ptr<Run>> R;
    for (auto &p : P) {
        for (int rv = -1; rv < (int)p.knobs.size(); rv++) {
            auto r = std::make_unique<Run>();
            r->pr = &p;
            for (auto &kn : p.knobs) r->on[kn] = true;
            if (rv >= 0) { r->reverted = p.knobs[rv]; r->on[p.knobs[rv]] = false; }
            R.push_back(std::move(r));
        }
    }

    auto clk = [&](int clken, int nres, int en, int rnw, int rs, int di, int lp, int phi2) {
        t->CLOCK = 0; t->CLKEN = clken; t->nRESET = nres; t->ENABLE = en; t->R_nW = rnw; t->RS = rs; t->DI = di;
        t->LPSTB = lp; t->PHI2 = phi2; t->eval();
        t->CLOCK = 1; t->eval();
    };
    auto out = [&](int v) -> uint64_t {
        switch (v) { case 0: return t->o0; case 1: return t->o1; case 2: return t->o2; case 3: return t->o3;
                     case 4: return t->o4; case 5: return t->o5; case 6: return t->o6; default: return t->o7; }
    };
    uint64_t total_chars = 0, nscn = 0;
    for (auto &s : S) {
        nscn++;
        // reset (with CLKEN, so the skew pipeline is flushed), then program with CLKEN low
        for (int i = 0; i < 6; i++) clk(1, 0, 0, 1, 0, 0, 0, 0);
        clk(0, 1, 0, 1, 0, 0, 0, 0);
        std::vector<std::pair<int,int>> prog;
        for (int i = 0; i < 16; i++) prog.push_back({i, s.r[i]});
        prog.push_back({18, s.r18}); prog.push_back({19, s.r19});
        for (auto &pv : prog) {
            clk(0, 1, 1, 0, 0, pv.first, 0, 0); clk(0, 1, 0, 1, 0, 0, 0, 0);
            clk(0, 1, 1, 0, 1, pv.second, 0, 0); clk(0, 1, 0, 1, 0, 0, 0, 0);
        }
        r12_raw = s.r[12];
        for (auto &r : R) {
            r->m = std::make_unique<Mame6845>(r->pr->mt);
            for (auto &kv : r->on) set_knob(r->m->k, kv.first, kv.second);
            for (auto &pv : prog) { r->m->address_w(pv.first); r->m->register_w(pv.second); }
            r->m->init_at_frame_start();
            memset(r->dh, 0, 3); memset(r->ch, 0, 3);
        }
        uint64_t flen = (uint64_t)(s.r[0] + 1) * ((uint64_t)((s.r[4] & 127) + 1) * ((s.r[9] & 31) + 1) + (s.r[5] & 31));
        uint64_t nchars = flen * 40;
        if (nchars < 20000) nchars = 20000;
        if (nchars > 600000) nchars = 600000;
        total_chars += nchars;
        uint8_t r8 = s.r[8];
        int lp = 0, pending_rd = -1, rd_rs = 0, latch = 19;
        for (uint64_t c = 0; c < nchars; c++) {
            // even clock: one character
            std::vector<Mame6845::Out> ex(R.size());
            for (size_t i = 0; i < R.size(); i++) ex[i] = R[i]->m->step();
            clk(1, 1, 0, 1, 0, 0, lp, 0);
            for (size_t i = 0; i < R.size(); i++) {
                Run &r = *R[i];
                int v = r.pr->variant;
                Mame6845::Out e = ex[i];
                uint64_t o = out(v);
                // skew
                int d0 = e.de, c0 = e.cur;
                int de_x = d0, cu_x = c0;
                if (r.k("skew")) {
                    int ds = 0, cs = 0, doff = 0, coff = 0;
                    if (v == 0) { int a = (r8 >> 4) & 3; ds = a == 2 ? 2 : 0; doff = a == 3;
                                  int b = (r8 >> 6) & 3; cs = (b == 1 || b == 2) ? 1 : 0; coff = b == 3; }
                    else if (v == 2) { int a = (r8 >> 4) & 3; ds = a < 3 ? a : 0; doff = a == 3;
                                       int b = (r8 >> 6) & 3; cs = b < 3 ? b : 0; coff = b == 3; }
                    else if (v == 4 || v == 5) { int a = (r8 >> 4) & 3; ds = a < 3 ? a : 0; doff = a == 3; }
                    else if (v == 6 || v == 7) { ds = (r8 >> 4) & 1; cs = (r8 >> 5) & 1; }
                    de_x = doff ? 0 : (ds == 0 ? d0 : r.dh[ds - 1]);
                    cu_x = coff ? 0 : (cs == 0 ? c0 : r.ch[cs - 1]);
                }
                r.dh[2] = r.dh[1]; r.dh[1] = r.dh[0]; r.dh[0] = d0;
                r.ch[2] = r.ch[1]; r.ch[1] = r.ch[0]; r.ch[0] = c0;
                uint16_t ema = e.ustb ? r.m->upd_strobe_addr : e.ma;
                int era = e.ra;
                if (v == 6 && (r8 & 0x48) == 0x48) era = (era & 15) | ((r8 & 0x80) ? 0 : (e.ustb ? 16 : 0));
                int hma = (o >> 11) & 0x3fff, hra = (o >> 6) & 31, hvs = (o >> 5) & 1, hhs = (o >> 4) & 1,
                    hde = (o >> 1) & 1, hcu = o & 1;
                std::string bad;
                if (hma != ema) bad += "MA ";
                if (hra != era) bad += "RA ";
                if (hde != de_x) bad += "DE ";
                if (hhs != e.hs) bad += "HSYNC ";
                if (hvs != e.vs) bad += "VSYNC ";
                if (hcu != cu_x) bad += "CURSOR ";
                r.chars++;
                if (!bad.empty()) {
                    r.mism++;
                    r.sig[bad]++;
                    if (r.reverted.empty() && r.shown < 8) {
                        r.shown++;
                        printf("MISMATCH [%s] %s char %llu line %d raster %d row %d: %s(hdl MA %04x RA %d DE %d HS %d VS %d CU %d | "
                               "exp MA %04x RA %d DE %d HS %d VS %d CU %d)\n", r.pr->name, s.name.c_str(),
                               (unsigned long long)c, r.m->char_counter - 1, r.m->raster_counter, r.m->line_counter,
                               bad.c_str(), hma, hra, hde, hhs, hvs, hcu, ema, era, de_x, e.hs, e.vs, cu_x);
                        printf("   regs:"); for (int j = 0; j < 16; j++) printf(" %d", s.r[j]); printf("\n");
                    }
                }
            }
            // odd clock: host / light pen / PHI2 activity between characters
            int en = 0, rnw = 1, rs = 0, di = 0, phi2 = 0;
            if (pending_rd >= 0) { en = 1; rnw = 1; rs = rd_rs; pending_rd = -1; }
            else {
                uint32_t a = gen.rng.u(1000);
                if (a < 6) { latch = gen.rng.u(32); en = 1; rnw = 0; rs = 0; di = latch; }       // address write
                else if (a < 12) { pending_rd = 1; rd_rs = gen.rng.u(4) != 0; }                  // read (status 1/4)
                else if (a < 14) { latch = 31; en = 1; rnw = 0; rs = 0; di = 31; }
                else if (a < 17 && latch == 31) { en = 1; rnw = gen.rng.u(2); rs = 1; }          // R31 access
                else if (a < 18) { latch = 18 + gen.rng.u(2); en = 1; rnw = 0; rs = 0; di = latch; }
                else if (a < 19 && (latch == 18 || latch == 19)) { en = 1; rnw = 0; rs = 1; di = gen.rng.u(256); }
                else if (a < 22) { lp = !lp; if (lp) for (auto &r : R) r->m->assert_light_pen_input(); }
                else if (a < 40) phi2 = 1;
            }
            if (en && rnw) {
                for (auto &r : R) { r->m->address_w(latch); }
            }
            clk(0, 1, en, rnw, rs, di, lp, phi2);
            if (en && !rnw) {
                for (auto &r : R) { if (!rs) r->m->address_w(di); else r->m->register_w(di); }
            } else if (en && rnw) {
                for (size_t i = 0; i < R.size(); i++) {
                    Run &r = *R[i];
                    int valid;
                    int exp = expected_read(r, rs, latch, valid);
                    int hdo = (out(r.pr->variant) >> 25) & 0xff;
                    r.reads++;
                    if (valid && hdo != exp) {
                        r.rmism++;
                        r.sig[std::string("DO") + (rs ? "" : "(status)")]++;
                        if (r.reverted.empty() && r.shown < 8) {
                            r.shown++;
                            printf("READ MISMATCH [%s] %s char %llu rs %d idx %d hdl %02x exp %02x\n", r.pr->name,
                                   s.name.c_str(), (unsigned long long)c, rs, latch, hdo, exp);
                        }
                    }
                }
            }
            if (phi2 && (r8 & 0x88) == 0x88) {
                for (auto &r : R) {
                    if (r->pr->variant != 6) continue;
                    int hma = (out(6) >> 11) & 0x3fff;
                    r->chars++;
                    if (hma != r->m->update_addr) { r->mism++; r->sig["MA(phi2)"]++; }
                }
            }
        }
        for (auto &r : R) r->frames += r->m->frames;
    }
    printf("\nscenarios %llu, characters per model %llu\n", (unsigned long long)nscn, (unsigned long long)total_chars);
    const Pair *last = nullptr;
    for (auto &r : R) {
        if (r->pr != last) { last = r->pr; printf("\n== %s\n", r->pr->name); }
        printf("  %-22s chars %10llu frames %7llu mismatches %9llu  reads %6llu read-mismatches %5llu",
               r->reverted.empty() ? "[all knobs]" : ("-" + r->reverted).c_str(), (unsigned long long)r->chars,
               (unsigned long long)r->frames, (unsigned long long)r->mism, (unsigned long long)r->reads,
               (unsigned long long)r->rmism);
        for (auto &kv : r->sig) printf("  %s:%llu", kv.first.c_str(), (unsigned long long)kv.second);
        printf("\n");
    }
    delete t;
    return 0;
}

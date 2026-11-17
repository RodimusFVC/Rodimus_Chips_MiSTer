// Lockstep driver: every CLOCK, compare crtc6845sv (drop-in) against the fixed reference on all outputs,
// and classify every stock-vs-fixed difference.
#include "Vtb_lockstep.h"
#include "verilated.h"
#include "stim.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <string>

static const char *bitname(int b) {
    // o_* layout: {DO[7:0], MA[13:0], RA[4:0], VSYNC, HSYNC, VBLANK, HBLANK, DE, CURSOR}
    if (b == 0) return "CURSOR";
    if (b == 1) return "DE";
    if (b == 2) return "HBLANK";
    if (b == 3) return "VBLANK";
    if (b == 4) return "HSYNC";
    if (b == 5) return "VSYNC";
    if (b < 11) return "RA";
    if (b < 25) return "MA";
    return "DO";
}

int main(int argc, char **argv) {
    uint64_t seed = argc > 1 ? strtoull(argv[1], 0, 0) : 1;
    uint64_t ncyc = argc > 2 ? strtoull(argv[2], 0, 0) : 10000000;
    Verilated::commandArgs(argc, argv);
    Vtb_lockstep *t = new Vtb_lockstep;
    Stim st(seed);

    uint64_t mism_dut = 0, mism_stk = 0, stk_bad_class = 0, clkens = 0;
    std::map<std::string, uint64_t> stk_sig;              // which outputs differ (stock vs fixed)
    std::map<std::string, uint64_t> stk_regs;             // (R4, R5, R6) of every stock-vs-fixed difference
    uint64_t stk_wrap = 0, stk_nowrap = 0;                 // R4 = 127 wrap vs R6 > R4 + 1
    uint64_t cov_adj = 0, cov_adj127 = 0, cov_adj_r6 = 0, cov_frames = 0, cov_il3 = 0, cov_skew_de[4] = {0},
             cov_skew_cu[4] = {0}, cov_cmode[4] = {0}, cov_r0_0 = 0, cov_r9_31 = 0;
    // history of the fixed model's (in_adj & row < R6) at the last 4 CLKENs, and R4 at that time
    uint8_t hist = 0, hist127 = 0;
    int first_dut_report = 0;
    uint8_t prev_in_adj = 0;
    int cr4 = 0, cr5 = 0, cr6 = 0, crow = 0;               // row counter / R4 / R5 / R6 when the class condition last held

    t->CLOCK = 0; t->eval();
    for (uint64_t c = 0; c < ncyc; c++) {
        Pins p = st.next();
        // low phase: apply inputs (async reset acts here)
        t->CLOCK = 0;
        t->CLKEN = p.clken; t->nRESET = p.nreset; t->ENABLE = p.enable; t->R_nW = p.r_nw; t->RS = p.rs;
        t->DI = p.di; t->LPSTB = p.lpstb;
        t->eval();
        // sample the fixed model's pre-edge state (what this edge acts on) for the stock-difference window
        if (p.clken && p.nreset) {
            clkens++;
            uint8_t ia = t->fix_in_adj, cond = ia && (t->fix_row < t->fix_r06);
            hist = (uint8_t)(((hist << 1) | cond) & 0x1f);
            if (cond) { cr4 = t->fix_r04; cr5 = t->fix_r05; cr6 = t->fix_r06; crow = t->fix_row; }
            hist127 = (uint8_t)(((hist127 << 1) | (cond && t->fix_row == 0)) & 0x1f);
            if (ia) { cov_adj++; if (t->fix_r04 == 127) cov_adj127++; if (cond) cov_adj_r6++; }
            if (prev_in_adj && !ia) cov_frames++;
            prev_in_adj = ia;
            uint8_t r8 = st.shadow[8];
            if ((r8 & 3) == 3) cov_il3++;
            cov_skew_de[(r8 >> 4) & 3]++; cov_skew_cu[(r8 >> 6) & 3]++; cov_cmode[(st.shadow[10] >> 5) & 3]++;
            if (st.shadow[0] == 0) cov_r0_0++;
            if ((st.shadow[9] & 31) == 31) cov_r9_31++;
        } else if (!p.nreset) { hist = 0; hist127 = 0; }
        for (int ph = 0; ph < 2; ph++) {
            if (ph == 1) { t->CLOCK = 1; t->eval(); }
            uint64_t d = t->o_dut, f = t->o_fix, s = t->o_stk;
            if (d != f) {
                mism_dut++;
                if (first_dut_report < 20) {
                    first_dut_report++;
                    printf("DUT MISMATCH cyc %llu ph %d: dut %010llx fix %010llx diff", (unsigned long long)c, ph,
                           (unsigned long long)d, (unsigned long long)f);
                    for (int b = 0; b < 33; b++) if (((d ^ f) >> b) & 1) printf(" %s", bitname(b));
                    printf("\n");
                }
            }
            if (s != f) {
                mism_stk++;
                std::string k;
                for (int b = 0; b < 33; b++) if (((s ^ f) >> b) & 1) { if (!k.empty()) k += "+"; k += bitname(b); }
                stk_sig[k]++;
                if (((s ^ f) & ~0xBull) != 0 || hist == 0) {     // only VBLANK/DE/CURSOR, inside the adjust window
                    stk_bad_class++;
                    if (stk_bad_class < 10)
                        printf("STOCK MISMATCH OUTSIDE CLASS cyc %llu: %s hist %x\n", (unsigned long long)c, k.c_str(), hist);
                } else {
                    if (hist127) stk_wrap++; else stk_nowrap++;
                    char key[160];
                    snprintf(key, sizeof key, "adjust row=%3d R6=%3d (now R4=%3d R5=%2d) %s", crow, cr6, cr4, cr5,
                             crow == 0 ? "[row wrapped: R4 was 127]" : "[row = R4+1 < R6]");
                    stk_regs[key]++;
                }
            }
        }
    }
    printf("seed %llu cycles %llu clkens %llu episodes %llu writes %llu reads %llu rewrites %llu mid_resets %llu lp_toggles %llu\n",
           (unsigned long long)seed, (unsigned long long)ncyc, (unsigned long long)clkens, (unsigned long long)st.episodes,
           (unsigned long long)st.writes, (unsigned long long)st.reads, (unsigned long long)st.rewrites,
           (unsigned long long)st.mid_resets, (unsigned long long)st.lp_toggles);
    printf("coverage: adj_clkens %llu adj_R4=127 %llu adj&row<R6 %llu adj_exits %llu il3 %llu R0=0 %llu R9=31 %llu\n",
           (unsigned long long)cov_adj, (unsigned long long)cov_adj127, (unsigned long long)cov_adj_r6,
           (unsigned long long)cov_frames, (unsigned long long)cov_il3, (unsigned long long)cov_r0_0, (unsigned long long)cov_r9_31);
    printf("coverage: skewDE %llu/%llu/%llu/%llu skewCUR %llu/%llu/%llu/%llu cursor_mode %llu/%llu/%llu/%llu\n",
           (unsigned long long)cov_skew_de[0], (unsigned long long)cov_skew_de[1], (unsigned long long)cov_skew_de[2],
           (unsigned long long)cov_skew_de[3], (unsigned long long)cov_skew_cu[0], (unsigned long long)cov_skew_cu[1],
           (unsigned long long)cov_skew_cu[2], (unsigned long long)cov_skew_cu[3], (unsigned long long)cov_cmode[0],
           (unsigned long long)cov_cmode[1], (unsigned long long)cov_cmode[2], (unsigned long long)cov_cmode[3]);
    printf("RESULT dut_vs_fixed_mismatches %llu\n", (unsigned long long)mism_dut);
    printf("RESULT stock_vs_fixed_mismatches %llu (in adjust class: R4=127 wrap %llu, R6>R4+1 %llu; OUTSIDE class %llu)\n",
           (unsigned long long)mism_stk, (unsigned long long)stk_wrap, (unsigned long long)stk_nowrap,
           (unsigned long long)stk_bad_class);
    for (auto &kv : stk_sig) printf("  stock diff signals %-24s %llu\n", kv.first.c_str(), (unsigned long long)kv.second);
    for (auto &kv : stk_regs) printf("  stock diff regs %s %llu\n", kv.first.c_str(), (unsigned long long)kv.second);
    delete t;
    return (mism_dut || stk_bad_class) ? 1 : 0;
}

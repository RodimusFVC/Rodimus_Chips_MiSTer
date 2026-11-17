// VDC oracle: crtc6845sv_vdc (8563 and 8568) against the MAME mos8563.cpp transliteration (mame8563.h).
// Display scenarios: static registers and video RAM; every character the HSYNC / VSYNC / display flip-flop is compared,
// every displayed line's window of pixels (colour index per pixel) is compared with what MAME's draw_row paints for
// that line, and random register / status reads are compared. Memory scenarios: R18/R19, R31 reads and writes,
// R30 block fill / copy with R32/R33, status polling; R31 data and the whole 64K video RAM are compared.
// As for the 6845 variants, run 0 has every documentation knob on (must match exactly); each further run reverts one
// knob to MAME and counts what that difference alone changes.
#include "Vtb_vdc.h"
#include "verilated.h"
#include "../mame/mame8563.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <vector>

struct Rng { std::mt19937_64 g; explicit Rng(uint64_t s) : g(s) {}
    uint32_t u(uint32_t n) { return n ? (uint32_t)(g() % n) : 0; }
    int r(int lo, int hi) { return lo + (int)u(hi - lo + 1); }
    bool p(double x) { return (double)(g() >> 11) / (double)(1ull << 53) < x; } };

static const char *KNOBS[] = {"r5e0", "cursor_vice", "blink_fast", "status_busy", "version_8568", "no_r37_8563"};
static const int NK = 6;

struct Run {
    int reverted;                          // -1 = all knobs on
    bool on[NK];
    std::unique_ptr<MameVdc> m;
    std::deque<std::vector<uint8_t>> exp;
    uint64_t ls_seen = 0;
    uint64_t sync_mism = 0, line_mism = 0, read_mism = 0, mem_mism = 0;
};

static Vtb_vdc *t;
static uint8_t memA[65536], memB[65536];
static uint8_t rdA = 0, rdB = 0;
static uint64_t clocks = 0;
static int dclk_div = 10, dclk_ph = 0;
static int shown_err = 0;
static std::map<std::string, uint64_t> cov_lines;

static bool tick(int en, int rnw, int rs, int di, bool dclk_on, bool &was_cclk) {
    int dclken = 0;
    if (dclk_on) { dclk_ph = (dclk_ph + 1) % dclk_div; dclken = dclk_ph == 0; }
    t->CLOCK = 0; t->DCLKEN = dclken; t->ENABLE = en; t->R_nW = rnw; t->RS = rs; t->DI = di;
    t->VDI_A = rdA; t->VDI_B = rdB;
    t->eval();
    was_cclk = dclken && t->dbg_cclk;
    uint16_t va = t->VA_A, vb = t->VA_B;
    uint8_t na = memA[va], nb = memB[vb];
    if (t->VWE_A) memA[va] = t->VDO_A;
    if (t->VWE_B) memB[vb] = t->VDO_B;
    t->CLOCK = 1; t->eval();
    rdA = na; rdB = nb;
    clocks++;
    return dclken;
}

int main(int argc, char **argv) {
    uint64_t seed = argc > 1 ? strtoull(argv[1], 0, 0) : 1;
    int nscen = argc > 2 ? atoi(argv[2]) : 40;
    Verilated::commandArgs(argc, argv);
    t = new Vtb_vdc;
    Rng rng(seed);
    std::vector<Run> runs(NK + 1);
    for (int i = 0; i <= NK; i++) {
        runs[i].reverted = i - 1;
        for (int k = 0; k < NK; k++) runs[i].on[k] = k != i - 1;
    }
    uint64_t scen = 0, chars = 0, frames = 0, lines = 0, pixels = 0, reads = 0, r31 = 0, blocks = 0, b_mism = 0,
             intr_checks = 0, intr_bad = 0, intr_low = 0, busy_reads = 0;
    for (int sc = 0; sc < nscen; sc++) {
        bool memtest = (sc % 4) == 3;
        scen++;
        // ---------------------------------------------------------------- models + video RAM
        for (auto &r : runs) {
            r.m = std::make_unique<MameVdc>();
            r.m->kv.r5e0 = r.on[0]; r.m->kv.cursor_vice = r.on[1]; r.m->kv.blink_fast = r.on[2];
            r.m->device_reset();
            r.exp.clear();
        }
        MameVdc &m0 = *runs[0].m;
        for (int i = 0; i < 65536; i++) {
            uint8_t v = memtest ? m0.vram[i] : (uint8_t)rng.u(256);
            if (!memtest && rng.p(0.3)) v = (i & 1) ? 0x00 : 0xff;
            memA[i] = memB[i] = v;
            for (auto &r : runs) r.m->vram[i] = v;
        }
        bool cc;
        t->nRESET = 0;
        for (int i = 0; i < 4; i++) tick(0, 1, 0, 0, false, cc);
        t->nRESET = 1;
        tick(0, 1, 0, 0, false, cc);
        // ---------------------------------------------------------------- registers
        int reg[38] = {0};
        int r0 = rng.r(12, memtest ? 30 : 70);
        reg[0] = r0;
        reg[1] = rng.r(1, std::max(1, r0 - 2));
        if (rng.p(0.5)) reg[1] = std::min(reg[1], 40);
        reg[2] = rng.r(0, r0);
        reg[3] = rng.u(256);
        reg[4] = rng.r(1, memtest ? 6 : 30);
        reg[5] = rng.r(0, 8);
        reg[6] = memtest ? 0 : rng.r(0, reg[4] + 1);
        reg[7] = rng.r(0, reg[4] + 2);
        reg[8] = rng.p(0.85) ? 0 : rng.u(4);
        reg[9] = rng.p(0.6) ? 7 : rng.p(0.7) ? rng.r(0, 15) : rng.r(16, 31);
        if ((reg[0] + 1) * ((reg[4] + 1) * (reg[9] + 1) + reg[5]) > 60000) reg[4] = rng.r(1, 6);
        reg[10] = rng.u(128); reg[11] = rng.u(32);
        int start = rng.u(65536);
        reg[12] = start >> 8; reg[13] = start & 0xff;
        int cur = (start + rng.r(0, 300)) & 0xffff;
        reg[14] = cur >> 8; reg[15] = cur & 0xff;
        reg[18] = rng.u(256); reg[19] = rng.u(256);
        int attr = rng.u(65536);
        reg[20] = attr >> 8; reg[21] = attr & 0xff;
        reg[22] = rng.p(0.6) ? 0x78 : rng.p(0.5) ? (rng.r(3, 15) << 4) | rng.r(0, 15) : rng.u(256);
        reg[23] = rng.p(0.5) ? reg[9] : rng.u(32);
        reg[24] = (rng.p(0.3) ? 0x40 : 0) | (rng.p(0.5) ? 0x20 : 0) | (rng.p(0.7) ? 0 : rng.u(32));
        int ctot = reg[22] >> 4;
        reg[25] = (rng.p(0.3) ? 0x80 : 0) | (rng.p(0.5) ? 0x40 : 0) | (rng.p(0.15) ? 0x20 : 0) | (rng.p(0.15) ? 0x10 : 0) |
                  (rng.p(0.6) ? 0 : rng.u(ctot + 1));
        reg[26] = rng.u(256);
        reg[27] = rng.p(0.6) ? 0 : rng.r(0, 8);
        reg[28] = rng.u(256);
        reg[29] = rng.u(32);
        reg[34] = rng.p(0.85) ? 0 : rng.u(256);
        reg[35] = rng.p(0.85) ? reg[1] : rng.u(256);
        reg[36] = rng.u(256);
        reg[37] = rng.u(256);
        reg[32] = rng.u(256); reg[33] = rng.u(256);
        if (reg[1] >= reg[0]) reg[1] = reg[0] - 1;         // the extra right-edge column must fall inside the line
        auto mw_addr = [&](int a) { for (auto &r : runs) r.m->address_w8563(a); };
        auto mw_data = [&](int d) { for (auto &r : runs) r.m->register_w8563(d); };
        auto wr = [&](int a, int d) {
            tick(1, 0, 0, a, false, cc); tick(0, 1, 0, 0, false, cc);
            tick(1, 0, 1, d, false, cc); tick(0, 1, 0, 0, false, cc);
            mw_addr(a); mw_data(d);
        };
        for (int a = 0; a < 38; a++) {
            if (a == 16 || a == 17 || a == 30 || a == 31) continue;
            wr(a, reg[a]);
        }
        for (int i = 0; i < 8; i++) tick(0, 1, 0, 0, false, cc);
        for (auto &r : runs) {
            r.m->init_at_frame_start();
            r.m->on_set_vsync(r.m->vsync);
            if (!r.m->line_pix.empty()) r.exp.push_back(r.m->line_pix);
            r.ls_seen = r.m->lines_started;
        }
        // ---------------------------------------------------------------- run
        uint64_t flen = (uint64_t)(reg[0] + 1) * (((reg[4] + 1) * (reg[9] + 1)) + reg[5] + 2);
        int nframes = memtest ? 2 : (flen < 6000 ? 40 : flen < 40000 ? 6 : 3);
        uint64_t nchar = flen * nframes + 50, charcount = 0, frame_before = m0.frames;
        std::vector<uint8_t> win;
        bool in_win = false, intr_expect = false, ready_prev = false;
        int pend_rd = -1, pend_rs = 0, wait = 0, latch = 0, mem_ops = memtest ? 200 : 0, mem_state = 0;
        ready_prev = !(!t->dbg_pf_valid || t->dbg_blk || t->dbg_wr_pend);
        intr_expect = !t->nINTR_B;
        while (charcount < nchar) {
            int en = 0, rnw = 1, rs = 0, di = 0;
            bool dclk_next = ((dclk_ph + 1) % dclk_div) == 0;
            bool do_read = false;
            bool busy = !t->dbg_pf_valid || t->dbg_blk || t->dbg_wr_pend;   // a video-RAM transfer is pending
            if (!dclk_next && wait == 0 && charcount > 0) {
                if (pend_rd >= 0) {
                    if (!(pend_rs && latch == 31 && busy)) {        // R31 data only once the prefetch is there
                        en = 1; rnw = 1; rs = pend_rs; do_read = true;
                        pend_rd = -1; wait = 3;
                    }
                } else if (!memtest && rng.p(0.002)) {
                    latch = rng.u(40); if (latch == 30 || latch == 31) latch = 0;
                    en = 1; rnw = 0; rs = 0; di = latch; mw_addr(latch);
                    pend_rd = 1; pend_rs = rng.u(4) != 0; wait = 3;
                } else if (memtest && mem_ops > 0 && !t->dbg_blk && m0.update_ready_bit) {
                    int op = rng.u(10);
                    mem_ops--;
                    if (getenv("VDC_DEBUG") && sc == atoi(getenv("VDC_DEBUG")))
                        printf("  op %d state %d latch %d upd %04x blk %04x r30 %d data %02x clk %llu\n", op, mem_state, latch,
                               m0.update_addr, m0.block_addr, m0.word_count, m0.data, (unsigned long long)clocks);
                    if (mem_state == 1) { en = 1; rnw = 0; rs = 1; di = rng.u(256); mw_data(di); mem_state = 0; wait = 12;
                                          if (rng.p(0.5)) { pend_rd = 1; pend_rs = 0; wait = 2; } }
                    else if (op < 2) { latch = 18 + rng.u(2); en = 1; rnw = 0; rs = 0; di = latch; mw_addr(latch); mem_state = 1; wait = 3; }
                    else if (op < 5) { latch = 31; en = 1; rnw = 0; rs = 0; di = 31; mw_addr(31); mem_state = rng.p(0.5) ? 1 : 0;
                                       if (!mem_state) { pend_rd = 1; pend_rs = 1; } wait = 3; r31++; }
                    else if (op < 6) { latch = 32 + rng.u(2); en = 1; rnw = 0; rs = 0; di = latch; mw_addr(latch); mem_state = 1; wait = 3; }
                    else if (op < 7) { latch = 24; en = 1; rnw = 0; rs = 0; di = 24; mw_addr(24); mem_state = 1; wait = 3; }
                    else if (op < 8) { latch = 30; en = 1; rnw = 0; rs = 0; di = 30; mw_addr(30); mem_state = 1; wait = 3; blocks++; }
                    else if (op < 9) { pend_rd = 1; pend_rs = 0; wait = 0; }   // status poll
                    else { latch = rng.u(38); if (latch == 30 || latch == 31) latch = 12; en = 1; rnw = 0; rs = 0; di = latch;
                           mw_addr(latch); pend_rd = 1; pend_rs = rng.u(4) != 0; wait = 3; }
                }
            }
            if (wait > 0 && !en) wait--;
            // expected read values, per run, from the model state before this CLOCK
            std::vector<int> expA(runs.size(), -1), expB(runs.size(), -1);
            if (do_read) {
                reads++;
                if (!rs) busy_reads += busy;
                for (size_t i = 0; i < runs.size(); i++) {
                    Run &r = runs[i];
                    int e = rs ? r.m->register_r8563() : r.m->status_r8563();
                    int a = e, b = e;
                    if (!rs) {
                        if (r.on[3] && busy) { a &= 0x7f; b &= 0x7f; }
                        if (r.on[4]) b = (b & ~7) | 2;
                    } else if (latch == 37 && r.on[5]) a = 0xff;
                    expA[i] = a; expB[i] = b;
                }
            }
            bool ready_pre = !busy;
            bool cclk;
            bool dclken = tick(en, rnw, rs, di, true, cclk);
            if (do_read) {
                for (size_t i = 0; i < runs.size(); i++) {
                    if (t->DO_A != expA[i] || t->DO_B != expB[i]) {
                        runs[i].read_mism++;
                        if (i == 0 && shown_err++ < 20)
                            printf("READ MISMATCH scen %d rs %d reg %d: hdl %02x/%02x exp %02x/%02x\n", sc, rs, latch,
                                   t->DO_A, t->DO_B, expA[i], expB[i]);
                    }
                }
            }
            // 8568 /INTR: low after Update Ready rises, until a status read or Update Ready falls
            {
                if (ready_pre && !ready_prev) intr_expect = true;
                if (!ready_pre || (do_read && !rs)) intr_expect = false;
                ready_prev = ready_pre;
                intr_checks++;
                intr_low += !t->nINTR_B;
                if (t->nINTR_B != !intr_expect || t->nINTR_A != 1) {
                    if (intr_bad < 6) printf("INTR scen %d clk %llu: nINTR_B %d nINTR_A %d exp_low %d ready_pre %d do_read %d rs %d pf %d blk %d wr %d\n",
                        sc, (unsigned long long)clocks, t->nINTR_B, t->nINTR_A, intr_expect, ready_pre, do_read, rs,
                        t->dbg_pf_valid, t->dbg_blk, t->dbg_wr_pend);
                    intr_bad++;
                }
            }
            if (cclk) {
                charcount++; chars++;
                for (size_t i = 0; i < runs.size(); i++) {
                    Run &r = runs[i];
                    Mame6845::Out o = r.m->step_vdc();
                    if (t->dbg_hs != o.hs || t->dbg_vs != o.vs || t->dbg_line_en != r.m->line_enable_ff) {
                        r.sync_mism++;
                        if (i == 0 && shown_err++ < 20)
                            printf("SYNC MISMATCH scen %d char %llu: hdl hs %d vs %d en %d exp hs %d vs %d en %d\n", sc,
                                   (unsigned long long)charcount, t->dbg_hs, t->dbg_vs, t->dbg_line_en, o.hs, o.vs,
                                   r.m->line_enable_ff);
                    }
                    if (r.m->lines_started != r.ls_seen) {
                        r.ls_seen = r.m->lines_started;
                        if (!r.m->line_pix.empty()) r.exp.push_back(r.m->line_pix);
                    }
                }
                if (m0.frames != frame_before) { frames += m0.frames - frame_before; frame_before = m0.frames; }
            }
            if (dclken) {
                if (t->RGBI_A != t->RGBI_B || t->DE_A != t->DE_B ||
                    t->HSYNC_B != (((reg[37] >> 7) & 1) ? t->HSYNC_A : !t->HSYNC_A) ||
                    t->VSYNC_B != (((reg[37] >> 6) & 1) ? t->VSYNC_A : !t->VSYNC_A) ||
                    t->CSYNC_B != (t->HSYNC_B == t->VSYNC_B)) b_mism++;
                if (t->DE_A) {
                    if (t->PIXCE_A) win.push_back(t->RGBI_A);
                    in_win = true;
                } else if (in_win) {
                    in_win = false;
                    lines++; pixels += win.size();
                    auto c = [&](const char *k, bool on) { if (on) cov_lines[k]++; };
                    c("bitmap", reg[25] & 0x80); c("text", !(reg[25] & 0x80)); c("attributes", reg[25] & 0x40);
                    c("semigraphics", reg[25] & 0x20); c("pixel_double", reg[25] & 0x10); c("hscroll!=0", reg[25] & 0x0f);
                    c("vscroll!=0", reg[24] & 0x1f); c("reverse_screen", reg[24] & 0x40); c("R27!=0", reg[27] != 0);
                    c("32-byte_cells", reg[9] >= 16); c("ram_4416_map", !(reg[28] & 0x10)); c("interlace_R8=3", (reg[8] & 3) == 3);
                    c("R22!=0x78", reg[22] != 0x78); c("cursor_blink", (reg[10] & 0x60) >= 0x40); c("R23<R9", reg[23] < reg[9]);
                    for (size_t i = 0; i < runs.size(); i++) {
                        Run &r = runs[i];
                        if (r.exp.empty()) { r.line_mism++; continue; }
                        if (r.exp.front() != win) {
                            r.line_mism++;
                            if (i == 0 && shown_err++ < 20) {
                                printf("LINE MISMATCH scen %d: hdl %zu px, exp %zu px\n  hdl:", sc, win.size(), r.exp.front().size());
                                for (size_t j = 0; j < win.size() && j < 48; j++) printf("%x", win[j]);
                                printf("\n  exp:");
                                for (size_t j = 0; j < r.exp.front().size() && j < 48; j++) printf("%x", r.exp.front()[j]);
                                printf("\n  regs:"); for (int a = 0; a < 38; a++) printf(" %d", reg[a]); printf("\n");
                            }
                        }
                        r.exp.pop_front();
                    }
                    win.clear();
                }
            }
        }
        if (memtest) {
            // drain: run until the chip and every model have finished their block operations and writes
            for (int i = 0; i < 4000000; i++) {
                bool c2;
                tick(0, 1, 0, 0, true, c2);
                if (c2) for (auto &r : runs) r.m->step_vdc();
                bool models_idle = true;
                for (auto &r : runs) models_idle &= r.m->update_ready_bit && r.m->block_left < 0;
                if (models_idle && !t->dbg_blk && !t->dbg_wr_pend && i > 64) break;
            }
            for (auto &r : runs) {
                int diff = 0;
                for (int i = 0; i < 65536; i++) if (memA[i] != r.m->vram[i] || memB[i] != memA[i]) {
                    diff++;
                    if (r.reverted < 0 && getenv("VDC_DEBUG"))
                        printf("  vram[%04x] hdlA %02x hdlB %02x model %02x  (R24 %02x R28 %02x upd %04x blk %04x)\n", i, memA[i], memB[i],
                               r.m->vram[i], r.m->vert_scroll, r.m->char_base_addr, r.m->update_addr, r.m->block_addr);
                }
                r.mem_mism += diff;
                if (diff && r.reverted < 0 && shown_err++ < 20) printf("VRAM MISMATCH scen %d: %d bytes\n", sc, diff);
            }
        } else {
            for (auto &r : runs) if (r.exp.size() > 2) r.line_mism += r.exp.size() - 2;
        }
    }
    printf("RESULT scenarios %llu clocks %llu chars %llu frames %llu lines %llu pixels %llu reads %llu (status reads while busy %llu) "
           "r31_ops %llu blocks %llu 8568_vs_8563_mismatches %llu intr_checks %llu intr_low %llu intr_mismatches %llu\n",
           (unsigned long long)scen, (unsigned long long)clocks, (unsigned long long)chars, (unsigned long long)frames,
           (unsigned long long)lines, (unsigned long long)pixels, (unsigned long long)reads, (unsigned long long)busy_reads,
           (unsigned long long)r31, (unsigned long long)blocks, (unsigned long long)b_mism, (unsigned long long)intr_checks,
           (unsigned long long)intr_low, (unsigned long long)intr_bad);
    for (auto &r : runs)
        printf("RUN %-16s sync_mismatches %llu line_mismatches %llu read_mismatches %llu vram_mismatches %llu\n",
               r.reverted < 0 ? "[all knobs]" : (std::string("-") + KNOBS[r.reverted]).c_str(),
               (unsigned long long)r.sync_mism, (unsigned long long)r.line_mism, (unsigned long long)r.read_mism,
               (unsigned long long)r.mem_mism);
    for (auto &kv : cov_lines) printf("COVERAGE lines with %-16s %llu\n", kv.first.c_str(), (unsigned long long)kv.second);
    delete t;
    return 0;
}

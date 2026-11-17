// Register-programming scenario generator shared by the lockstep and variant harnesses.
// Produces one set of input pins per CLOCK: CLKEN pattern, bus cycles, LPSTB, nRESET.
#pragma once
#include <cstdint>
#include <deque>
#include <random>
#include <vector>
#include <string>

struct Pins {
    uint8_t clken = 0, nreset = 1, enable = 0, r_nw = 1, rs = 0, di = 0, lpstb = 0;
};

struct BusOp {          // one host access
    uint8_t r_nw, rs, di;
};

struct Rng {
    std::mt19937_64 g;
    explicit Rng(uint64_t s) : g(s) {}
    uint32_t u(uint32_t n) { return n ? (uint32_t)(g() % n) : 0; }          // [0,n)
    int r(int lo, int hi) { return lo + (int)u((uint32_t)(hi - lo + 1)); }  // [lo,hi]
    bool p(double x) { return (double)(g() >> 11) / (double)(1ull << 53) < x; }
};

// register profile: how values are drawn
enum Profile { P_SMALL, P_EDGE, P_REAL, P_WRAP127, P_BIG, P_FLEET, P_COUNT };

struct Stim {
    Rng rng;
    std::deque<BusOp> q;
    uint8_t shadow[32] = {0};   // values written (what the chip should hold)
    uint8_t alatch = 0;
    int profile = P_SMALL;
    int clken_mode = 0, clken_n = 1, clken_ph = 0;
    int bus_hold = 0, bus_gap = 0, hold_len = 1;
    BusOp cur{1, 0, 0};
    uint64_t ep_left = 0, cyc = 0;
    int reset_left = 0;
    double p_rewrite = 0, p_read = 0, p_lpstb = 0, p_reset = 0;
    bool lp = false;
    bool allow_reads = true;
    // stats
    uint64_t episodes = 0, mid_resets = 0, rewrites = 0, reads = 0, writes = 0, lp_toggles = 0;
    std::vector<std::pair<int,int>> fixed_table;   // optional fixed (reg,val) program (fleet scenarios)
    int directed_idx = 0;                           // directed edge tables run first, then random
    bool use_directed = true;

    explicit Stim(uint64_t seed) : rng(seed) {}

    int reg_val(int reg) {
        auto &R = rng;
        int p = profile;
        if (p == P_EDGE) {
            static const int e8[] = {0, 1, 2, 3, 127, 128, 254, 255};
            static const int e7[] = {0, 1, 2, 126, 127};
            static const int e5[] = {0, 1, 2, 15, 16, 30, 31};
            switch (reg) {
            case 0: case 1: case 2: return R.p(0.5) ? e8[R.u(8)] : R.r(0, 12);
            case 3: return (R.p(0.5) ? (R.p(0.5) ? 0x00 : 0xF0) : (R.u(16) << 4)) | (R.p(0.5) ? (R.p(0.5) ? 0 : 15) : R.u(16));
            case 4: case 6: case 7: return R.p(0.5) ? e7[R.u(5)] : R.r(0, 6);
            case 5: case 9: return R.p(0.5) ? e5[R.u(7)] : R.r(0, 4);
            case 8: return R.u(256);
            case 10: return R.u(128);
            case 11: return R.u(32);
            default: return R.u(256);
            }
        }
        if (p == P_WRAP127) {
            switch (reg) {
            case 0: return R.r(0, 10);
            case 1: return R.r(0, 12);
            case 2: return R.r(0, 12);
            case 3: return R.u(256);
            case 4: return R.p(0.8) ? 127 : R.r(120, 127);
            case 5: return R.r(0, 31);
            case 6: return R.p(0.3) ? R.r(0, 127) : R.r(0, 40);
            case 7: return R.p(0.3) ? R.r(0, 127) : R.r(0, 10);
            case 8: return R.p(0.5) ? 0 : R.u(256);
            case 9: return R.r(0, 3);
            case 10: return R.u(128);
            case 11: return R.u(32);
            default: return R.u(256);
            }
        }
        if (p == P_BIG) {
            switch (reg) {
            case 0: return R.r(30, 255);
            case 1: return R.r(0, 255);
            case 2: return R.r(0, 255);
            case 4: return R.r(0, 127);
            case 5: return R.r(0, 31);
            case 6: case 7: return R.r(0, 127);
            case 9: return R.r(0, 31);
            case 10: return R.u(128);
            case 11: return R.u(32);
            default: return R.u(256);
            }
        }
        if (p == P_REAL) {
            switch (reg) {
            case 0: return R.r(30, 70);
            case 1: return R.r(20, 50);
            case 2: return R.r(20, 60);
            case 3: return (R.r(0, 15) << 4) | R.r(0, 15);
            case 4: return R.r(10, 40);
            case 5: return R.r(0, 10);
            case 6: return R.r(8, 40);
            case 7: return R.r(8, 40);
            case 8: return R.p(0.6) ? 0 : (R.p(0.5) ? R.u(4) : R.u(256));
            case 9: return R.r(1, 9);
            case 10: return R.u(128);
            case 11: return R.u(32);
            default: return R.u(256);
            }
        }
        // P_SMALL / default
        switch (reg) {
        case 0: return R.r(0, 16);
        case 1: return R.r(0, 18);
        case 2: return R.r(0, 18);
        case 3: return R.u(256);
        case 4: return R.r(0, 8);
        case 5: return R.r(0, 6);
        case 6: return R.r(0, 10);
        case 7: return R.r(0, 10);
        case 8: return R.p(0.4) ? R.u(4) : R.u(256);
        case 9: return R.r(0, 6);
        case 10: return R.u(128);
        case 11: return R.r(0, 8);
        case 14: return shadow[12] & 0x3f;
        case 15: return (shadow[13] + R.r(0, 40)) & 0xff;
        default: return R.u(256);
        }
    }

    void wr(int reg, int val) {
        q.push_back({0, 0, (uint8_t)reg});
        q.push_back({0, 1, (uint8_t)val});
    }
    void rd(int reg) {
        q.push_back({0, 0, (uint8_t)reg});
        q.push_back({1, 1, 0});
        if (rng.p(0.2)) q.push_back({1, 0, 0});   // status-port read
    }

    void program_all() {
        if (!fixed_table.empty()) {
            for (auto &kv : fixed_table) wr(kv.first, kv.second);
            return;
        }
        int order[16];
        for (int i = 0; i < 16; i++) order[i] = i;
        if (rng.p(0.3)) for (int i = 15; i > 0; i--) std::swap(order[i], order[rng.u(i + 1)]);
        for (int i = 0; i < 16; i++) wr(order[i], reg_val(order[i]));
    }

    void new_episode(bool first) {
        episodes++;
        q.clear();
        profile = rng.u(P_FLEET);
        clken_mode = rng.u(6);
        clken_n = rng.r(2, 8);
        if (clken_mode == 5) clken_n = 32;
        hold_len = rng.r(1, 4);
        p_rewrite = rng.p(0.7) ? 1.0 / rng.r(200, 20000) : 0.0;
        p_read = allow_reads && rng.p(0.6) ? 1.0 / rng.r(100, 5000) : 0.0;
        p_lpstb = rng.p(0.3) ? 1.0 / rng.r(20, 2000) : 0.0;
        p_reset = rng.p(0.15) ? 1.0 / rng.r(5000, 200000) : 0.0;
        int scale = (profile == P_BIG || profile == P_REAL) ? 8 : 1;
        ep_left = (uint64_t)rng.r(5000, 60000) * scale;
        reset_left = first ? 40 : (rng.p(0.5) ? rng.r(1, 30) : 0);
        if (use_directed && directed_idx < (int)directed_tables().size()) {
            const auto &d = directed_tables()[directed_idx++];
            for (int i = 0; i < 16; i++) wr(i, d[i]);
            ep_left = 400000;
            clken_mode = directed_idx % 6;
        } else
            program_all();
        if (allow_reads && rng.p(0.5)) for (int i = 0; i < 32; i++) rd(i);
    }

    // R0..R15 directed edge tables (task list: zeros, R1 > R0, R4 = 127, R5 > 0 with R4 = 127, R9 = 31, R7 beyond R4,
    // R2 beyond R0, sync widths 0 / 15, interlace 0 / 1 / 3, skews, cursor modes incl. blink)
    static const std::vector<std::vector<int>> &directed_tables() {
        static const std::vector<std::vector<int>> t = {
            //  R0  R1  R2   R3   R4  R5  R6  R7  R8  R9  R10   R11 R12 R13 R14 R15
            {   0,  0,  0, 0x00,   0,  0,  0,  0,  0,  0, 0x00,  0,  0,  0,  0,  0},
            {   7,  4,  5, 0x22,   0,  0,  0,  0,  0,  0, 0x00,  0,  0,  0,  0,  2},
            {   9, 12,  3, 0x31,   4,  0,  3,  2,  0,  2, 0x01,  2,  0,  0,  0,  5},   // R1 > R0
            {  15, 10, 12, 0x24, 127,  0, 20,  3,  0,  0, 0x00,  0,  0,  0,  0,  3},   // R4 = 127, R5 = 0
            {  15, 10, 12, 0x24, 127,  7, 20,  3,  0,  0, 0x00,  0,  0,  0,  0,  3},   // R4 = 127, R5 = 7 (Cosmic Guerilla class)
            {  11,  8,  9, 0x33, 127, 31,127,126,  0,  1, 0x40,  1,  0, 16,  0, 20},   // R4 = 127, R5 = 31, R6 = 127
            {  12,  8, 10, 0x55,   3,  2,  2,  2,  0, 31, 0x00, 31,  0,  0,  0,  4},   // R9 = 31
            {  12,  8, 10, 0x55,   3,  2,  6,  9,  0,  3, 0x00,  3,  0,  0,  0,  4},   // R6, R7 beyond R4
            {  12,  8, 20, 0x55,   5,  1,  3,  4,  0,  3, 0x00,  3,  0,  0,  0,  4},   // R2 beyond R0
            {  20, 12, 14, 0x00,   5,  1,  3,  4,  0,  3, 0x00,  3,  0,  0,  0,  4},   // sync widths 0
            {  20, 12,  8, 0xFF,   5,  1,  3,  4,  0,  3, 0x00,  3,  0,  0,  0,  4},   // sync widths 15
            {  20, 12, 14, 0x24,   6,  3,  4,  5,  1,  6, 0x02,  5,  0,  0,  0,  4},   // interlace sync
            {  20, 12, 14, 0x24,   6,  3,  4,  5,  3,  6, 0x02,  5,  0,  0,  0,  4},   // interlace sync + video
            {  20, 12, 14, 0x24,   6,  3,  4,  5,  3,  7, 0x03,  4,  0,  0,  0,  4},   // interlace sync + video, odd R9
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0x10,  3, 0x00,  3,  0,  0,  0,  4},   // DE skew 1
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0x20,  3, 0x00,  3,  0,  0,  0,  4},   // DE skew 2
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0x30,  3, 0x00,  3,  0,  0,  0,  4},   // DE skew 3
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0x40,  3, 0x00,  3,  0,  0,  0,  4},   // cursor skew 1
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0x80,  3, 0x00,  3,  0,  0,  0,  4},   // cursor skew 2
            {  20, 12, 14, 0x24,   6,  0,  4,  5,0xF0,  3, 0x00,  3,  0,  0,  0,  4},   // both skews 3
            {   9,  6,  7, 0x21,   2,  0,  2,  1,  0,  3, 0x40,  2,  0,  0,  0,  3},   // cursor blink 1/16
            {   9,  6,  7, 0x21,   2,  0,  2,  1,  0,  3, 0x61,  2,  0,  0,  0,  3},   // cursor blink 1/32
            {   9,  6,  7, 0x21,   2,  0,  2,  1,  0,  3, 0x20,  2,  0,  0,  0,  3},   // cursor off
            {   9,  6,  7, 0x21,   2,  0,  2,  1,  0,  3, 0x03,  1,  0,  0,  0,  3},   // split cursor (start > end)
            {   9,  6,  7, 0x21,   2,  0,  2,  1,  0,  3, 0x00,  9,  0,  0,  0,  3},   // end > R9
            {  44, 32, 35, 0x26,  32,  6, 28, 30,  0,  7, 0x00,  0,  3,255,  0,  0},   // Vanguard-like
        };
        return t;
    }

    bool clken_now() {
        switch (clken_mode) {
        case 0: return true;
        case 1: case 5: return (++clken_ph % clken_n) == 0;
        case 2: return rng.p(0.5);
        case 3: return rng.p(0.9);
        case 4: return rng.p(0.15);
        }
        return true;
    }

    Pins next() {
        Pins p;
        cyc++;
        if (ep_left == 0) new_episode(cyc == 1);
        ep_left--;
        p.clken = clken_now() ? 1 : 0;
        // reset
        if (reset_left > 0) { reset_left--; p.nreset = 0; }
        else if (p_reset > 0 && rng.p(p_reset)) { reset_left = rng.r(1, 20); mid_resets++; p.nreset = 0; }
        if (!p.nreset) {
            for (auto &s : shadow) s = 0;
            alatch = 0;
            if (reset_left == 0 && rng.p(0.7)) { q.clear(); program_all(); }
        }
        // random activity
        if (p_rewrite > 0 && rng.p(p_rewrite)) {
            int reg = rng.u(16);
            if (rng.p(0.05)) reg = rng.r(16, 31);
            wr(reg, reg_val(reg & 15));
            rewrites++;
        }
        if (p_read > 0 && rng.p(p_read)) { rd(rng.u(32)); }
        if (p_lpstb > 0 && rng.p(p_lpstb)) { lp = !lp; lp_toggles++; }
        p.lpstb = lp;
        // bus
        if (bus_hold > 0) {
            bus_hold--;
            p.enable = 1; p.r_nw = cur.r_nw; p.rs = cur.rs; p.di = cur.di;
            if (bus_hold == 0) bus_gap = rng.r(0, 6);
        } else if (bus_gap > 0) {
            bus_gap--;
            p.r_nw = rng.u(2); p.rs = rng.u(2); p.di = rng.u(256);   // bus noise while not enabled
        } else if (!q.empty() && p.nreset) {
            cur = q.front(); q.pop_front();
            bus_hold = hold_len - 1;
            p.enable = 1; p.r_nw = cur.r_nw; p.rs = cur.rs; p.di = cur.di;
            if (cur.r_nw) reads++; else writes++;
            if (bus_hold == 0) bus_gap = rng.r(0, 6);
        } else {
            p.r_nw = rng.u(2); p.rs = rng.u(2); p.di = rng.u(256);
        }
        if (p.enable && !p.r_nw) {
            if (!p.rs) alatch = p.di & 31;
            else if (alatch < 16) shadow[alatch] = p.di;
        }
        return p;
    }
};

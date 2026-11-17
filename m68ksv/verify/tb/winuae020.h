// Copyright (C) 2026 Rodimus
// WinUAE's 68020 rules for the undefined / disputed flags (Amiberry fork, src/newcpu_common.cpp setdivuflags /
// setdivsflags / setchkundefinedflags / setchk2undefinedflags / divul_overflow / divsl_overflow, src/gencpu.cpp i_DIVU /
// i_DIVS / i_CHK / i_CHK2), transcribed from the code (the code, not its comments, produced the Amiberry log). Harness
// only (amiga020.cpp, mus020.cpp). Own code.
#pragma once
#include <cstdint>

// gencpu.cpp i_DIVU / i_DIVS + newcpu_common.cpp setdivuflags / setdivsflags (68020 branch); X kept
static inline bool w_divw(bool sgn, uint32_t dst, uint16_t src, int ccr_in, int &ccr, uint32_t &d0) {
    int x = ccr_in & 0x10, n = (ccr_in >> 3) & 1, z = (ccr_in >> 2) & 1, v = (ccr_in >> 1) & 1, c = ccr_in & 1;
    d0 = dst;
    if (src == 0) return false;
    if (!sgn) {
        uint32_t q = dst / src, r = dst % src;
        if (q > 0xffff) { v = 1; if ((int32_t)dst < 0) n = 1; }
        else { c = 0; v = 0; z = (uint16_t)q == 0; n = (int16_t)q < 0; d0 = (q & 0xffff) | (r << 16); }
    } else {
        int32_t sd = (int32_t)dst; int16_t ss = (int16_t)src;
        auto ovf = [&]() {
            c = 0; n = 0; z = 0; v = 1;
            uint32_t ad = (uint32_t)(sd < 0 ? -(int64_t)sd : sd), as = (uint16_t)(ss < 0 ? -ss : ss);
            if ((ad >> 16) >= as) return;
            uint32_t aq = ad / as;
            if ((int8_t)aq == 0) z = 1;
            if ((int8_t)aq < 0) n = 1;
        };
        if (dst == 0x80000000u && ss == -1) ovf();
        else {
            int32_t q = sd / ss; int32_t r = sd % ss;
            if ((q & 0xffff8000) != 0 && (q & 0xffff8000) != (int32_t)0xffff8000) ovf();
            else { c = 0; v = 0; z = (int16_t)q == 0; n = (int16_t)q < 0; d0 = (q & 0xffff) | ((uint32_t)(r & 0xffff) << 16); }
        }
    }
    ccr = x | (n << 3) | (z << 2) | (v << 1) | c;
    return true;
}
// gencpu.cpp i_CHK + setchkundefinedflags (68020 / 030 branch); returns true when it traps
static inline bool w_chk(bool lng, uint32_t dn, uint32_t bound, int ccr_in, int &ccr) {
    int32_t dst = lng ? (int32_t)dn : (int16_t)dn, src = lng ? (int32_t)bound : (int16_t)bound;
    int n, z, v = 0, c = 0;
    z = dst == 0; n = dst < 0;
    if (dst < 0 || dst > src) {
        if (!lng) { int fs = (int16_t)dst < 0, fo = (int16_t)src < 0; int16_t val = (int16_t)((int16_t)src - (int16_t)dst); int fn = val < 0; v = (fs ^ fo) & (fn ^ fo); }
        else { int fs = dst < 0, fo = src < 0; int32_t val = (int32_t)((uint32_t)src - (uint32_t)dst); int fn = val < 0; v = (fs ^ fo) & (fn ^ fo); }
        c = dst < 0 ? (dst > src || src >= 0) : (src >= 0);
    }
    ccr = (ccr_in & 0x10) | (n << 3) | (z << 2) | (v << 1) | c;
    return dst > src || dst < 0;
}
// gencpu.cpp i_CHK2 + setchk2undefinedflags (68020 / 030 branch); returns C
static inline uint32_t w_wrap(int32_t a, int32_t b) { return (uint32_t)a - (uint32_t)b; }
static inline int w_chk2(int32_t lower, int32_t upper, int32_t val, int ccr_in, int &ccr) {
    int n = 0, v = 0, z = 0, c = 0;
    if (!(val == lower || val == upper)) {
        if (lower < 0 && upper >= 0) {
            if (val < lower) n = 1;
            if (val >= 0 && val < upper) n = 1;
            if (val >= 0 && (w_wrap(lower, val) & 0x80000000u) == 0) { v = 1; n = 0; if (val > upper) n = 1; }
        } else if (lower >= 0 && upper < 0) {
            if (val >= 0) n = 1;
            if (val > upper) n = 1;
            if (val > lower && (w_wrap(upper, val) & 0x80000000u) == 0) { v = 1; n = 0; }
        } else if (lower >= 0 && upper >= 0 && lower > upper) {
            if (val > upper && val < lower) n = 1;
            if (val < 0 && (w_wrap(lower, val) & 0x80000000u) != 0) v = 1;
            if (val < 0 && (w_wrap(lower, val) & 0x80000000u) == 0) n = 1;
        } else if (lower >= 0 && upper >= 0 && lower <= upper) {
            if (val >= 0 && val < lower) n = 1;
            if (val > upper) n = 1;
            if (val < 0 && (w_wrap(upper, val) & 0x80000000u) != 0) { v = 1; n = 1; }
        } else if (lower < 0 && upper < 0 && lower > upper) {
            if (val >= 0) n = 1;
            if (val > upper && val < lower) n = 1;
            if (val >= 0 && (w_wrap(val, lower) & 0x80000000u) != 0) { n = 0; v = 1; }
        } else if (lower < 0 && upper < 0 && lower <= upper) {
            if (val < lower) n = 1;
            if (val < 0 && val > upper) n = 1;
            if (val >= 0 && (w_wrap(val, lower) & 0x80000000u) != 0) { n = 1; v = 1; }
        }
    }
    if (upper == val || lower == val) z = 1;
    else {
        if (lower <= upper && (val < lower || val > upper)) c = 1;
        if (lower > upper && val > upper && val < lower) c = 1;
    }
    ccr = (ccr_in & 0x10) | (n << 3) | (z << 2) | (v << 1) | c;
    return c;
}
// newcpu_common.cpp m68k_divl overflow branches: divul_overflow / divsl_overflow (68020 / 030); false if no overflow
static inline bool w_divl(uint16_t extra, uint32_t dq, uint32_t dr, uint32_t src, int ccr_in, int &ccr) {
    int x = ccr_in & 0x10, n = (ccr_in >> 3) & 1, z = (ccr_in >> 2) & 1, v, c;
    if (src == 0) return false;
    bool ov = false;
    if (extra & 0x800) {
        int64_t a = (int64_t)(int32_t)dq;
        if (extra & 0x400) { a &= 0xffffffffLL; a |= (int64_t)((uint64_t)dr << 32); }
        if ((uint64_t)a == 0x8000000000000000ULL && src == ~0u) ov = true;
        else {
            __int128 q = (__int128)a / (int32_t)src;
            if (q > 0x7fffffff || q < -(__int128)0x80000000LL) ov = true;
        }
        if (ov) {
            int32_t a32 = (int32_t)a; bool neg64 = a < 0, neg32 = a32 < 0;
            if (extra & 0x400) {
                int32_t ahigh = (int32_t)(a >> 32);
                if (ahigh == 0) { z = 1; n = 0; }
                else if (ahigh < 0 && (int32_t)src < 0 && ahigh > (int32_t)src) { z = 0; n = 0; }
                else if (a32 == 0) { z = 1; n = 0; }
                else { z = 0; n = neg32 ^ neg64; }
            } else {
                if (a32 == 0) { z = 1; n = 0; } else { n = neg32; z = 0; }
            }
        }
    } else {
        uint64_t a = dq;
        if (extra & 0x400) a |= (uint64_t)dr << 32;
        if (a / src > 0xffffffffULL) { ov = true; n = (int32_t)dq < 0; z = dq == 0; }
    }
    if (!ov) return false;
    v = 1; c = 0;
    ccr = x | (n << 3) | (z << 2) | (v << 1) | c;
    return true;
}


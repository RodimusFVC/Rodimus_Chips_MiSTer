// Copyright (C) 2026 Rodimus
// amiga020: the 68020 behaviour cases of the Amiga test program verify/amiga020 (m68k020_a.a / m68k020.c) on m68ksv
// (CPU = 68020 / 68021), checked against the values the Amiberry run logged (verify/amiga020/m68k020.log: WinUAE's 68020
// core, the reference the user chose for the 68020's undefined / disputed behaviour - REPORT.md "68020 behaviour from
// WinUAE"), plus rows whose expected values come from WinUAE's source code (Amiberry fork, src/newcpu_common.cpp,
// gencpu.cpp; marked "code" below) where the run had no case:
//   T1   DIVU.W / DIVS.W overflow, CHK.W / CHK.L flag tables (log); random DIVU.W / DIVS.W / CHK.W / CHK.L rows (code)
//   T2   DIVU.L / DIVS.L 64-bit overflow flags (log); DIV.L overflow rows incl. the "Dr < 0, divisor < 0, Dr > divisor"
//        branch of divsl_overflow (code)
//   T4   PACK / UNPK with -(A7) as either operand: A7 / A0 steps and the bytes (log)
//   T7   JMP (A1) to an odd address right after the JMP: address-error frame (log: SR, PC, format, SSW, stage C, fault
//        address, data output buffer area, data input buffer); JMP (An) / (d16,An) / (xxx).L far away (code: stacked PC =
//        the JMP's address + 2, gencpu.cpp i_JMP). The SSW word is checked against m68ksv's choice, NOT the log: RB / RC set
//        as the MC68020 User's Manual 6.2.1 p. 6-22 says ($3066; WinUAE / the log: $0066). #unverified - printed on every
//        run as the known difference (2026-11-16, REPORT.md "SSW back to the manual, CHK2 margin")
//   T10  LINK A7,#-8 (log); LINK.L A7,#-8 (code)
//   T11  CHK2 / CMP2 .B / .W / .L, Dn and An, every branch of setchk2undefinedflags (code)
// Each case is a short program run from reset on a 32-bit port with no wait states (the CPU clock = clk / 4).
//   amiga020 [-v]
#include "Vm68ksv.h"
#include "verilated.h"
#include "winuae020.h"
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>

static uint8_t mem[1 << 20];
static const uint32_t AM = 0xfffff;
static void w16(uint32_t a, uint16_t v) { mem[a & AM] = v >> 8; mem[(a + 1) & AM] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static uint16_t r16(uint32_t a) { return (mem[a & AM] << 8) | mem[(a + 1) & AM]; }
static uint32_t r32(uint32_t a) { return ((uint32_t)r16(a) << 16) | r16(a + 2); }
static uint32_t rs = 11;
static uint32_t rnd() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static bool verbose = false;
static int fails = 0, cases = 0;
static long n_log = 0, n_code = 0;
// T7 address-error SSW (2026-11-16, the user's decision): m68ksv sets RB | RC (MC68020 User's Manual 6.2.1 p. 6-22: "the
// rerun bits alone show the cause of the exception") over WinUAE's low half (RW, SIZE word, FC 6). The Amiberry log has
// WinUAE's $0066 (no RB / RC; its code calls that frame "partially implemented only"). #unverified: no real 68020 run.
static const uint16_t SSW_AE = 0x3066, SSW_AE_WINUAE = 0x0066;
static int n_known = 0;

// program: CODE at $1000; vector v's handler at $3000 + 16 v: MOVE.W #v,$A046; MOVE.L A7,$A048; BRA *. The tail stores
// SR at $A040, D0-D7 / A0-A6 at $A000, A7 at $A04C, then BRA *.
static uint32_t P;
static void o(uint16_t v) { w16(P, v); P += 2; }
static void setup() {
    memset(mem, 0, sizeof mem);
    w32(0, 0x7000); w32(4, 0x1000);
    for (int v = 2; v < 64; v++) {
        uint32_t h = 0x3000 + v * 16; w32(v * 4, h);
        w16(h, 0x33fc); w16(h + 2, v); w32(h + 4, 0xa046); w16(h + 8, 0x23cf); w32(h + 10, 0xa048); w16(h + 14, 0x60fe);
    }
    P = 0x1000;
}
static void tail() { o(0x40f9); o(0); o(0xa040); o(0x48f9); o(0x7fff); o(0); o(0xa000); o(0x23cf); o(0); o(0xa04c); o(0x60fe); }
static void ld(int r, uint32_t v) { o((uint16_t)((r < 8 ? 0x203c : 0x207c) | ((r & 7) << 9))); o(v >> 16); o(v); }
static void ccr(int c) { o(0x44fc); o(c); }
static uint32_t R(int i) { return r32(0xa000 + 4 * i); }

static int cpu_type = 68020;
static void run(long clocks = 16000) {
    Vm68ksv *t = new Vm68ksv;
    t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = 1; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
    t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0; t->dbg_ra = 0;
    bool wseen = false;
    for (long n = 0; n < clocks; n++) {
        t->RESET_n_i = n > 80;
        uint32_t a = t->A32 & AM;
        if (t->AS_n) wseen = false;
        t->D32_i = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
        t->DSACK_n = t->AS_n ? 3 : 0;
        t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;
        t->clk = 0; t->eval(); t->clk = 1; t->eval();
        a = t->A32 & AM;
        if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {
            wseen = true;
            int nb = t->SIZ ? t->SIZ : 4, of = a & 3, k = nb < 4 - of ? nb : 4 - of;
            for (int j = 0; j < k; j++) mem[(a + j) & AM] = t->D32_o >> (24 - 8 * (of + j));
        }
    }
    delete t;
}
static void check(bool ok, bool fromlog, const char *fmt, ...) {
    char b[400]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    cases++; if (fromlog) n_log++; else n_code++;
    if (!ok) fails++;
    if (!ok || verbose) printf("%s %s %s\n", ok ? "ok  " : "FAIL", fromlog ? "[log] " : "[code]", b);
}
static std::string fl(int c) { char b[24]; snprintf(b, sizeof b, "X%d N%d Z%d V%d C%d", (c >> 4) & 1, (c >> 3) & 1, (c >> 2) & 1, (c >> 1) & 1, c & 1); return b; }

// ---------------------------------------------------------------- T1: one DIV.W / CHK row
static void row(const char *name, uint16_t op, uint32_t d0, uint32_t d1, int cin, uint32_t e_d0, int e_vec, int e_ccr, bool fromlog) {
    setup(); ld(0, d0); ld(1, d1); ccr(cin); o(op); tail(); run();
    int vec = r16(0xa046); uint16_t sr = vec ? r16(r32(0xa048)) : r16(0xa040);
    uint32_t rd0 = vec ? d0 : R(0);
    bool ok = vec == e_vec && (sr & 0x1f) == e_ccr && rd0 == e_d0;
    check(ok, fromlog, "%s %08x / %08x / %02x -> %08x vec %d %s (expected %08x vec %d %s)", name, d0, d1, cin, rd0, vec,
          fl(sr & 0x1f).c_str(), e_d0, e_vec, fl(e_ccr).c_str());
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    for (int i = 1; i < argc; i++) if (!strcmp(argv[i], "-v")) verbose = true;
#ifdef M68KSV_HCPU
    cpu_type = M68KSV_HCPU;
#endif
    // ---- T1 (log): {D0, D1, CCR in, D0 after, vector, CCR after}
    static const uint32_t divu[][6] = {
        {0x00010000, 1, 0x00, 0x00010000, 0, 0x02}, {0x00010000, 1, 0x1f, 0x00010000, 0, 0x1f},
        {0xffffffff, 1, 0x00, 0xffffffff, 0, 0x0a}, {0xffffffff, 1, 0x1f, 0xffffffff, 0, 0x1f},
        {0x80000000, 1, 0x00, 0x80000000, 0, 0x0a}, {0x7fff0000, 2, 0x00, 0x7fff0000, 0, 0x02},
        {0xffff0000, 0xffff, 0x00, 0xffff0000, 0, 0x0a}, {0x12345678, 0x100, 0x00, 0x12345678, 0, 0x02}};
    static const uint32_t divs[][6] = {
        {0x00010000, 1, 0x00, 0x00010000, 0, 0x02}, {0x00010000, 1, 0x1f, 0x00010000, 0, 0x12},
        {0xffff0000, 1, 0x00, 0xffff0000, 0, 0x02}, {0x80000000, 0xffff, 0x00, 0x80000000, 0, 0x02},
        {0x80000000, 1, 0x1f, 0x80000000, 0, 0x12}, {0x00008000, 1, 0x00, 0x00008000, 0, 0x06},
        {0xffff7fff, 1, 0x00, 0xffff7fff, 0, 0x02}, {0x12345678, 0x100, 0x00, 0x12345678, 0, 0x02}};
    static const uint32_t chkw[][6] = {
        {5, 10, 0x00, 5, 0, 0x00}, {5, 10, 0x1f, 5, 0, 0x10}, {0, 10, 0x1f, 0, 0, 0x14}, {10, 10, 0x00, 10, 0, 0x00},
        {0xffff, 10, 0x00, 0xffff, 6, 0x09}, {11, 10, 0x00, 11, 6, 0x01}, {0x8000, 10, 0x1f, 0x8000, 6, 0x1b},
        {5, 0xffff, 0x00, 5, 6, 0x00}, {0xfffe, 0xffff, 0x00, 0xfffe, 6, 0x08}, {0, 0, 0x1f, 0, 0, 0x14}};
    static const uint32_t chkl[][6] = {
        {5, 10, 0x00, 5, 0, 0x00}, {0xffffffff, 10, 0x00, 0xffffffff, 6, 0x09}, {11, 10, 0x1f, 11, 6, 0x11},
        {0x80000000, 10, 0x00, 0x80000000, 6, 0x0b}, {0, 0, 0x1f, 0, 0, 0x14}, {0x7fffffff, 0x7fffffff, 0x00, 0x7fffffff, 0, 0x00}};
    for (auto &r : divu) row("T1 DIVU.W D1,D0", 0x80c1, r[0], r[1], r[2], r[3], r[4], r[5], true);
    for (auto &r : divs) row("T1 DIVS.W D1,D0", 0x81c1, r[0], r[1], r[2], r[3], r[4], r[5], true);
    for (auto &r : chkw) row("T1 CHK.W D1,D0", 0x4181, r[0], r[1], r[2], r[3], r[4], r[5], true);
    for (auto &r : chkl) row("T1 CHK.L D1,D0", 0x4101, r[0], r[1], r[2], r[3], r[4], r[5], true);
    // ---- T1 (code): random rows, overflow-biased dividends
    for (int k = 0; k < 48; k++) {
        bool sgn = k & 1;
        uint32_t d0 = rnd(); uint16_t d1 = rnd() >> 7;
        if (k % 4 < 2) d1 &= 0xff; if (d1 == 0) d1 = 3;
        if (k % 6 == 0) d0 = (rnd() & 0x7fff) | (sgn && (k & 8) ? 0xffff0000u : 0);     // small: no overflow / late
        if (k % 6 == 3) d0 = ((uint32_t)(d1 & 0x7fff) << 15) + (rnd() & 0x7fff);          // near the signed limit
        int cin = (k & 2) ? 0x1f : 0x00, eccr; uint32_t ed0;
        w_divw(sgn, d0, d1, cin, eccr, ed0);
        row(sgn ? "T1 DIVS.W D1,D0" : "T1 DIVU.W D1,D0", sgn ? 0x81c1 : 0x80c1, d0, d1, cin, ed0, 0, eccr, false);
    }
    for (int k = 0; k < 48; k++) {
        bool lng = k & 1;
        uint32_t d0 = rnd(), d1 = rnd();
        if (k % 3 == 0) { d0 &= 0x8000ffff; d1 &= 0x8000ffff; }
        if (k % 4 == 1 && !lng) { d0 = (int16_t)d0 < 0 ? d0 : d0 & 0xff; }
        int cin = (k & 2) ? 0x1f : 0x00, eccr;
        bool tr = w_chk(lng, d0, d1, cin, eccr);
        row(lng ? "T1 CHK.L D1,D0" : "T1 CHK.W D1,D0", lng ? 0x4101 : 0x4181, d0, d1, cin, d0, tr ? 6 : 0, eccr, false);
    }
    // ---- T2 DIV.L overflow
    struct DL { uint16_t ext; uint32_t dq, dr, src; int cin, eccr; bool log; };
    std::vector<DL> dl = {
        {0x0402, 0, 2, 1, 0x00, 0x06, true}, {0x0402, 0, 2, 1, 0x1f, 0x16, true}, {0x0c02, 0, 2, 1, 0x1f, 0x16, true}};
    // code rows: 32-bit DIVS.L $80000000 / -1; 64-bit rows for each divsl_overflow branch; DIVU.L 64-bit
    struct DLc { uint16_t ext; uint32_t dq, dr, src; };
    std::vector<DLc> dlc = {
        {0x0800, 0x80000000, 0, 0xffffffff}, {0x0c02, 0x80000000, 0, 1}, {0x0c02, 0x12345678, 0xfffffffe, 0xfffffffd},
        {0x0c02, 0, 0xfffffff0, 0xfffffffe}, {0x0c02, 0, 0xffffffff, 0xfffffffe}, {0x0c02, 0x80000000, 0x00000005, 3}, {0x0c02, 0x00001234, 0xfffffff0, 7},
        {0x0c02, 0, 0x80000000, 0xffffffff}, {0x0c02, 0x7fffffff, 0x40000000, 0x10}, {0x0402, 0x80000000, 0x00000007, 2},
        {0x0402, 0x00000005, 0xffffffff, 0xffffffff}, {0x0c02, 0x00000001, 0xffffffff, 0xffffffff}};
    for (auto &c : dlc) for (int cin : {0x00, 0x1f}) {
        int e; if (!w_divl(c.ext, c.dq, c.dr, c.src, cin, e)) { printf("internal: DIV.L row without overflow\n"); fails++; continue; }
        dl.push_back(DL{c.ext, c.dq, c.dr, c.src, cin, e, false});
    }
    for (auto &c : dl) {
        setup(); ld(2, c.dr); ld(0, c.dq); ld(1, c.src); ccr(c.cin); o(0x4c41); o(c.ext); tail(); run();
        uint16_t sr = r16(0xa040); int vec = r16(0xa046);
        bool ok = vec == 0 && (sr & 0x1f) == c.eccr && R(0) == c.dq && R(2) == c.dr;
        check(ok, c.log, "T2 DIV%c.L D1,D2:D0 ext %04x D2:D0 %08x:%08x / %08x CCR %02x -> %s vec %d D2:D0 %08x:%08x (expected %s, unchanged)",
              (c.ext & 0x800) ? 'S' : 'U', c.ext, c.dr, c.dq, c.src, c.cin, fl(sr & 0x1f).c_str(), vec, R(2), R(0), fl(c.eccr).c_str());
    }
    // ---- T4 PACK / UNPK with -(A7) (log): pbuf at $5000, A0 = pbuf + 16, A7 = pbuf + 32
    struct PK { const char *name; uint16_t op, adj; int da0, da7; uint8_t b08[16], b24[16]; };
    static const PK pk[4] = {
        {"T4a PACK -(A0),-(A7),#0", 0x8f48, 0, -2, -2,
         {0xee,0xee,0xee,0xee,0xee,0xee,0x12,0x34,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee},
         {0xee,0xee,0xee,0xee,0xee,0x56,0x24,0x9a,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee}},
        {"T4b PACK -(A7),-(A0),#0", 0x814f, 0, -1, -2,
         {0xee,0xee,0xee,0xee,0xee,0xee,0x12,0x8a,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee},
         {0xee,0xee,0xee,0xee,0xee,0x56,0x78,0x9a,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee}},
        {"T4c UNPK -(A0),-(A7),#$3030", 0x8f88, 0x3030, -1, -2,
         {0xee,0xee,0xee,0xee,0xee,0xee,0x12,0x34,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee},
         {0xee,0xee,0xee,0xee,0xee,0x56,0x33,0x34,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee}},
        {"T4d UNPK -(A7),-(A0),#$3030", 0x818f, 0x3030, -2, -2,
         {0xee,0xee,0xee,0xee,0xee,0xee,0x37,0x38,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee},
         {0xee,0xee,0xee,0xee,0xee,0x56,0x78,0x9a,0xee,0xee,0xee,0xee,0xee,0xee,0xee,0xee}}};
    for (auto &c : pk) {
        setup();
        for (int i = 0; i < 48; i++) mem[0x5000 + i] = 0xee;
        mem[0x500e] = 0x12; mem[0x500f] = 0x34; mem[0x501d] = 0x56; mem[0x501e] = 0x78; mem[0x501f] = 0x9a;
        ld(8, 0x5010); ld(15, 0x5020); o(c.op); o(c.adj); tail(); run();
        int da0 = (int)(R(8) - 0x5010), da7 = (int)(r32(0xa04c) - 0x5020);
        bool ok = r16(0xa046) == 0 && da0 == c.da0 && da7 == c.da7 && !memcmp(&mem[0x5008], c.b08, 16) && !memcmp(&mem[0x5018], c.b24, 16);
        std::string got;
        for (int i = 8; i < 40; i++) { char b[4]; snprintf(b, sizeof b, " %02x", mem[0x5000 + i]); got += b; }
        check(ok, true, "%s: A0 delta %d A7 delta %d (expected %d / %d) bytes +08..+39:%s", c.name, da0, da7, c.da0, c.da7, got.c_str());
    }
    // ---- T7 JMP to an odd address: address-error frame (format B). Log layout: JMP (A1) at $1012, target $1014 + 1
    // (NOPs there). Checked words: 0 SR, 1-2 PC, 3 format / vector, 5 SSW, 6 stage C, 8-9 fault address, 12-19 (data
    // output buffer and the internal words up to +27: 0 in the log), 22-23 data input buffer. Not checked (WinUAE internal
    // state, not hardware): 4 (+08), 7 (+0E stage B), 10-11 (+14), 20-21 (+28)
    {
        setup(); uint32_t lea = P; ld(9, 0); uint32_t jpc = P; o(0x4ed1);
        uint32_t tgt = P; o(0x4e71); o(0x4e71); o(0x4e71); tail();
        w32(lea + 2, tgt + 1);
        run();
        uint32_t sp = r32(0xa048);
        uint16_t e[24] = {0x2700, (uint16_t)(tgt >> 16), (uint16_t)tgt, 0xb00c, 0, SSW_AE, 0x4e71, 0, (uint16_t)((tgt + 1) >> 16),
                          (uint16_t)(tgt + 1), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, (uint16_t)((tgt + 1) >> 16), (uint16_t)(tgt + 1)};
        static const bool chk[24] = {1,1,1,1,0,1,1,0,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1};
        bool ok = r16(0xa046) == 3; std::string got, bad;
        for (int i = 0; i < 24; i++) {
            uint16_t w = r16(sp + 2 * i); char b[8]; snprintf(b, sizeof b, " %04x", w); got += b;
            if (chk[i] && w != e[i]) { ok = false; char c[40]; snprintf(c, sizeof c, " w%d %04x/%04x", i, w, e[i]); bad += c; }
        }
        check(ok, true, "T7 JMP (A1) at %x to %x + 1: vec %d frame%s%s", jpc, tgt, r16(0xa046), got.c_str(), bad.c_str());
        // the one logged word checked against another value: shown on every run, not dropped
        n_known++;
        printf("known difference [log] T7 SSW (word 5): m68ksv %04x, expected %04x (MC68020 UM 6.2.1: RB | RC), Amiberry log "
               "%04x (WinUAE, no RB / RC) - #unverified, no real 68020 to settle it\n", r16(sp + 10), SSW_AE, SSW_AE_WINUAE);
    }
    // (code) JMP far away: (A1), (d16,A1), (xxx).L - stacked PC = the JMP's address + 2; SSW, fault address, DIB as above
    for (int m = 0; m < 3; m++) {
        setup(); uint32_t tgt = 0x2201;
        if (m == 0) ld(9, tgt); else if (m == 1) ld(9, tgt - 0x100);
        uint32_t jpc = P;
        if (m == 0) o(0x4ed1); else if (m == 1) { o(0x4ee9); o(0x0100); } else { o(0x4ef9); o(tgt >> 16); o(tgt); }
        tail(); run();
        uint32_t sp = r32(0xa048);
        bool ok = r16(0xa046) == 3 && r16(sp) == 0x2700 && r32(sp + 2) == jpc + 2 && r16(sp + 6) == 0xb00c && r16(sp + 10) == SSW_AE &&
                  r32(sp + 16) == tgt && r32(sp + 44) == tgt;
        check(ok, false, "T7 JMP %s to %x at %x: vec %d SR %04x PC %08x fmt %04x SSW %04x FA %08x DIB %08x (expected PC %08x, SSW 3066, FA = DIB = %x)",
              m == 0 ? "(A1)" : m == 1 ? "(d16,A1)" : "(xxx).L", tgt, jpc, r16(0xa046), r16(sp), r32(sp + 2), r16(sp + 6), r16(sp + 10),
              r32(sp + 16), r32(sp + 44), jpc + 2, tgt);
    }
    // ---- T10 LINK A7,#-8 (log) / LINK.L A7,#-8 (code): A7 = lbuf + 32 ($5020); the old A7 is pushed at lbuf + 28
    for (int l = 0; l < 2; l++) {
        setup(); for (int i = 0; i < 32; i++) mem[0x5000 + i] = 0xee;
        ld(15, 0x5020); if (l) { o(0x480f); o(0xffff); o(0xfff8); } else { o(0x4e57); o(0xfff8); } tail(); run();
        bool ok = r32(0x501c) == 0x5020 && r32(0xa04c) == 0x5014;
        check(ok, l == 0, "T10 %s A7,#-8: pushed at $501C %08x, A7 after %08x (expected 00005020 / 00005014)", l ? "LINK.L" : "LINK",
              r32(0x501c), r32(0xa04c));
    }
    // ---- T11 CHK2 / CMP2 (code): bounds at (A0) = $6000; value in D2 / A2; sizes B / W / L; CCR in 00 / 1F
    {
        static const int32_t vals[] = {0, 1, 5, 0x10, 0x40, 0x7f, -1, -0x10, -0x40, -0x80, 0x7fff, -0x8000, 0x12345678, -0x12345678,
                                       0x7fffffff, (int32_t)0x80000000};
        int ncase = 0;
        for (int sz = 0; sz < 3; sz++) for (int t = 0; t < 40; t++) {
            int bits = sz == 0 ? 8 : sz == 1 ? 16 : 32;
            auto sx = [&](uint32_t v) -> int32_t { return bits == 32 ? (int32_t)v : bits == 16 ? (int16_t)v : (int8_t)v; };
            uint32_t lo, hi, val; int an = t & 1, isch = (t & 2) >> 1, cin = (t & 4) ? 0x1f : 0;
            int pick = t % 8;
            lo = vals[rnd() % 16]; hi = vals[rnd() % 16]; val = vals[rnd() % 16];
            if (pick == 3) val = lo; if (pick == 5) { lo = rnd(); hi = rnd(); val = rnd(); }
            if (pick == 6) { val = rnd(); }
            int32_t L = sx(lo), U = sx(hi);
            int32_t V = an ? (int32_t)val : sx(val);
            int eccr; int c = w_chk2(L, U, V, cin, eccr);
            setup();
            if (sz == 0) { mem[0x6000] = lo; mem[0x6001] = hi; }
            else if (sz == 1) { w16(0x6000, lo); w16(0x6002, hi); }
            else { w32(0x6000, lo); w32(0x6004, hi); }
            ld(8, 0x6000); ld(an ? 10 : 2, val); ccr(cin);
            o((uint16_t)(0x00d0 | (sz << 9))); o((uint16_t)((an ? 0xa000 : 0x2000) | (isch ? 0x0800 : 0)));
            tail(); run();
            int vec = r16(0xa046); uint16_t sr = vec ? r16(r32(0xa048)) : r16(0xa040);
            int evec = (isch && c) ? 6 : 0;
            bool ok = vec == evec && (sr & 0x1f) == eccr;
            check(ok, false, "T11 %s.%c %c2 bounds %08x..%08x value %08x CCR %02x -> vec %d %s (expected vec %d %s)", isch ? "CHK2" : "CMP2",
                  "BWL"[sz], an ? 'A' : 'D', (uint32_t)L, (uint32_t)U, (uint32_t)V, cin, vec, fl(sr & 0x1f).c_str(), evec, fl(eccr).c_str());
            ncase++;
        }
    }
    printf("amiga020 (%s): %d checks (%ld from the Amiberry log, %ld from WinUAE's code), %d failures; %d known difference "
           "from the log (T7 SSW: the manual's RB / RC, #unverified)\n",
           cpu_type == 68021 ? "68EC020" : "68020", cases, n_log, n_code, fails, n_known);
    return fails != 0;
}

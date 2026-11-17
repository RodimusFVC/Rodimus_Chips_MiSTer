// tb_pit8253.cpp — lockstep Verilator bench: pit8253.sv vs the C++ transcription of MAME's pit8253_device (pit_ref.h).
//
// Per clk the RTL and the reference get the same inputs; compared every clk:
//   dout   vs the reference peek (read() without side effects) of address a — i.e. on every read and on every other clk
//   out[3] vs m_output_pin != 0
//   the full counter state (control, value, count, phase, latch counts, flags, output) vs the reference state
// Event order per clk (documented in rtl/pit8253.sv): gate change, bus write, bus read, clk_ce.
// DATASHEET rule 1 (rtl/pit8253.sv header): per counter, a bus write on a clk where that counter has clk_ce (or while
// a held write is pending for it) is held and applied to that counter on the next clk (pit_ref::write_to).
// DATASHEET rule 2 lives in pit_ref.h (m_cnt_wr, compared as state flag bit 7).
// Inputs are settled with clk low before the rising edge (Common-Pitfalls: bench input changed on the clock edge).
//
// usage: tb [suite|directed|sweep|random] [--seed S] [--cycles N] [--seeds K]     (no argument = everything)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include "Vpit8253.h"
#include "verilated.h"
#include "pit_ref.h"

#ifndef PIT8254
#define PIT8254 0
#endif

#define RS(c, n) (top->pit8253__DOT__ctr__BRA__##c##__KET____DOT__##n)

struct CeCfg { int kind = 0; int div = 1; int ph = 0; int p = 128; };   // 0 none, 1 every div, 2 random p/256

struct Cov
{
    uint64_t ce[3][8] = {}, tog[3][8] = {}, ph[8][4] = {}, gate[8][2] = {};
    uint64_t rd_norm[4] = {}, rd_lat = 0, rd_stat = 0, rd_wmsb = 0, rd_ctl = 0, rd_mid = 0;
    uint64_t w_set[8] = {}, w_cnt[4] = {}, w_latch = 0, w_rb[8] = {}, w_rb_st = 0, w_rb_ct = 0, w_rb_both = 0;
    uint64_t bcd_wrap = 0, bin_wrap = 0, resets = 0, nocs = 0, null_rd = 0, held = 0;
};

struct Rig
{
    Vpit8253 *top;
    pit_ref ref;
    Cov cov;
    uint64_t cyc = 0, errs = 0, rs = 0x9E3779B97F4A7C15ull;
    std::string tag;
    uint8_t gate_v = 7;
    bool hp[3] = {}; unsigned ha[3] = {}, hd[3] = {};                    // DATASHEET rule 1: held write per counter
    CeCfg ce_cfg[3];

    Rig() : top(new Vpit8253), ref(PIT8254 ? pit_type::I8254 : pit_type::I8253) { ref.reset(); }

    uint64_t rnd() { rs ^= rs << 13; rs ^= rs >> 7; rs ^= rs << 17; return rs; }

    void fail(const char *what, int c, unsigned got, unsigned exp)
    {
        printf("DIVERGENCE cyc=%llu [%s] %s counter=%d rtl=0x%x mame=0x%x\n", (unsigned long long)cyc, tag.c_str(), what, c, got, exp);
        if (++errs >= 12) { printf("too many divergences, stopping\n"); exit(1); }
    }

    void compare_state()
    {
        for (int c = 0; c < 3; c++)
        {
            const pit_counter_ref &m = ref.m_counter[c];
            unsigned ctrl, val, cnt, ph, latc, flags;
            switch (c)
            {
            case 0: ctrl = RS(0, ctrl); val = RS(0, val); cnt = RS(0, cnt); ph = RS(0, ph); latc = RS(0, lat_cnt);
                    flags = RS(0, outp) | RS(0, gate_in) << 1 | RS(0, rose) << 2 | RS(0, lat_stat) << 3 | RS(0, null_c) << 4 | RS(0, rmsb) << 5 | RS(0, wmsb) << 6 | RS(0, cnt_wr) << 7; break;
            case 1: ctrl = RS(1, ctrl); val = RS(1, val); cnt = RS(1, cnt); ph = RS(1, ph); latc = RS(1, lat_cnt);
                    flags = RS(1, outp) | RS(1, gate_in) << 1 | RS(1, rose) << 2 | RS(1, lat_stat) << 3 | RS(1, null_c) << 4 | RS(1, rmsb) << 5 | RS(1, wmsb) << 6 | RS(1, cnt_wr) << 7; break;
            default: ctrl = RS(2, ctrl); val = RS(2, val); cnt = RS(2, cnt); ph = RS(2, ph); latc = RS(2, lat_cnt);
                    flags = RS(2, outp) | RS(2, gate_in) << 1 | RS(2, rose) << 2 | RS(2, lat_stat) << 3 | RS(2, null_c) << 4 | RS(2, rmsb) << 5 | RS(2, wmsb) << 6 | RS(2, cnt_wr) << 7; break;
            }
            unsigned eflags = (m.m_output != 0) | m.m_gate_input << 1 | m.m_gate_rose << 2 | m.m_latched_status << 3 |
                              m.m_null_count << 4 | (m.m_rmsb ? 1 : 0) << 5 | (m.m_wmsb ? 1 : 0) << 6 | m.m_cnt_wr << 7;
            if (ctrl != m.m_control)       fail("state.control", c, ctrl, m.m_control);
            if (val != m.m_value)          fail("state.value", c, val, m.m_value);
            if (cnt != m.m_count)          fail("state.count", c, cnt, m.m_count);
            if (ph != (unsigned)m.m_phase) fail("state.phase", c, ph, m.m_phase);
            if (latc != (unsigned)m.m_latched_count) fail("state.latched_count", c, latc, m.m_latched_count);
            if (flags != eflags)           fail("state.flags(out|gate|rose|lstat|null|rmsb|wmsb|cnt_wr)", c, flags, eflags);
        }
    }

    // one clk
    void step(bool rst, bool cs, bool wr, bool rd, unsigned a, unsigned din, unsigned ce, unsigned gate)
    {
        top->rst = rst; top->cs = cs; top->wr = wr; top->rd = rd; top->a = a; top->din = din;
        top->clk_ce = ce; top->gate = gate; top->clk = 0; top->eval();

        unsigned exp = (a == 3) ? 0 : ref.read(a, false);
        if (top->dout != exp) fail("dout", a, top->dout, exp);

        if (rst) { ref.reset(); cov.resets++; for (int c = 0; c < 3; c++) hp[c] = false; }
        else
        {
            uint16_t pv[3]; int pm[3], pp[3];
            for (int c = 0; c < 3; c++) { pv[c] = ref.m_counter[c].m_value; pm[c] = CTRL_MODE(ref.m_counter[c].m_control); pp[c] = ref.m_counter[c].m_output_pin != 0; }
            for (int c = 0; c < 3; c++)
            {
                int s = (gate >> c) & 1;
                if (s != ref.m_counter[c].m_gate_input) cov.gate[CTRL_MODE(ref.m_counter[c].m_control)][s]++;
                ref.write_gate(c, s);
            }
            if (cs && wr) coverage_write(a, din);
            for (int c = 0; c < 3; c++)                                      // DATASHEET rule 1
            {
                bool bw = cs && wr, hold = bw && (((ce >> c) & 1) || hp[c]);
                if (hp[c]) ref.write_to(c, ha[c], hd[c]);
                else if (bw && !hold) ref.write_to(c, a, din);
                if (hold) { ha[c] = a; hd[c] = din; cov.held++; }
                hp[c] = hold;
            }
            if (cs && rd) { coverage_read(a); ref.read(a, true); }
            if (!cs && (wr || rd)) cov.nocs++;
            for (int c = 0; c < 3; c++)
                if ((ce >> c) & 1)
                {
                    pit_counter_ref &m = ref.m_counter[c];
                    int md = CTRL_MODE(m.m_control);
                    uint16_t before = m.m_value;
                    ref.write_clk(c, 1); ref.write_clk(c, 0);
                    cov.ce[c][md]++;
                    cov.ph[md][m.m_phase]++;
                    if (before == 0 && m.m_value == 0x9999 && CTRL_BCD(m.m_control)) cov.bcd_wrap++;
                    if (before == 0 && m.m_value == 0xFFFF && !CTRL_BCD(m.m_control)) cov.bin_wrap++;
                }
            for (int c = 0; c < 3; c++)
                if ((ref.m_counter[c].m_output_pin != 0) != pp[c]) cov.tog[c][CTRL_MODE(ref.m_counter[c].m_control)]++;
            (void)pv; (void)pm;
        }

        top->clk = 1; top->eval(); top->clk = 0; top->eval();
        cyc++;
        for (int c = 0; c < 3; c++)
        {
            unsigned g = (top->out >> c) & 1, e = ref.m_counter[c].m_output_pin != 0;
            if (g != e) fail("out", c, g, e);
        }
        compare_state();
    }

    void coverage_write(unsigned a, unsigned d)
    {
        if (a < 3) { cov.w_cnt[CTRL_ACCESS(ref.m_counter[a].m_control)]++; return; }
        int t = d >> 6;
        if (t == 3)
        {
            int n = ((d >> 1) & 1) + ((d >> 2) & 1) + ((d >> 3) & 1);
            cov.w_rb[n]++;
            bool st = !((d >> 4) & 1), ct = !((d >> 5) & 1);
            if (st && ct) cov.w_rb_both++; else if (st) cov.w_rb_st++; else if (ct) cov.w_rb_ct++;
        }
        else if (CTRL_ACCESS(d) == 0) cov.w_latch++;
        else cov.w_set[CTRL_MODE(d & 0x3f)]++;
    }
    void coverage_read(unsigned a)
    {
        if (a == 3) { cov.rd_ctl++; return; }
        pit_counter_ref &m = ref.m_counter[a];
        if (m.m_latched_status) cov.rd_stat++;
        else if (m.m_latched_count) cov.rd_lat++;
        else
        {
            cov.rd_norm[CTRL_ACCESS(m.m_control)]++;
            if (CTRL_ACCESS(m.m_control) == 3 && m.m_wmsb) cov.rd_wmsb++;
            if (CTRL_ACCESS(m.m_control) == 3 && m.m_rmsb) cov.rd_mid++;
        }
        if (m.m_null_count) cov.null_rd++;
    }

    // ---- stimulus primitives ----
    unsigned ce_now()
    {
        unsigned ce = 0;
        for (int c = 0; c < 3; c++)
        {
            CeCfg &k = ce_cfg[c];
            if (k.kind == 1) { if (++k.ph >= k.div) { k.ph = 0; ce |= 1u << c; } }
            else if (k.kind == 2) { if ((rnd() & 255) < (unsigned)k.p) ce |= 1u << c; }
        }
        return ce;
    }
    void idle(int n = 1) { while (n--) step(0, 0, 0, 0, 0, 0, ce_now(), gate_v); }
    void wrt(unsigned a, unsigned d) { step(0, 1, 1, 0, a, d, ce_now(), gate_v); }
    unsigned rdr(unsigned a) { step(0, 1, 0, 1, a, 0, ce_now(), gate_v); return 0; }
    void do_reset(int n = 2) { for (int i = 0; i < n; i++) step(1, 0, 0, 0, 0, 0, 0, gate_v); }
    void set_ce(int c, int kind, int div = 1, int p = 128) { ce_cfg[c].kind = kind; ce_cfg[c].div = div; ce_cfg[c].ph = 0; ce_cfg[c].p = p; }
    void no_ce() { for (int c = 0; c < 3; c++) set_ce(c, 0); }

    void ctl(int c, int rw, int mode, int bcd) { wrt(3, c << 6 | rw << 4 | mode << 1 | bcd); }
    // count write for access mode rw: the value as the counter would see it (rw 2: v is the MSB)
    void wcount(int c, int rw, unsigned v)
    {
        if (rw == 1) wrt(c, v & 0xff);
        else if (rw == 2) wrt(c, v & 0xff);
        else { wrt(c, v & 0xff); wrt(c, (v >> 8) & 0xff); }
    }
};

static uint32_t eff_count(int rw, int bcd, unsigned v)
{
    uint32_t n = (rw == 2) ? (v & 0xff) << 8 : v;
    if (rw == 1) n = v & 0xff;
    if (!bcd) return n ? n : 65536;
    if (!n) return 10000;
    return ((n >> 12) & 15) * 1000 + ((n >> 8) & 15) * 100 + ((n >> 4) & 15) * 10 + (n & 15);
}

// ---------------------------------------------------------------------------------------------
// sweep: every mode (0..7) x bcd x rw x count x counter x gate behaviour x clk_ce rate
static void scenario(Rig &r, int c, int mode, int bcd, int rw, unsigned count, int gvar, int ceopt, uint64_t seed)
{
    char buf[128];
    snprintf(buf, sizeof buf, "sweep c%d m%d bcd%d rw%d cnt%04x g%d ce%d", c, mode, bcd, rw, count, gvar, ceopt);
    r.tag = buf;
    r.rs = seed * 0x2545F4914F6CDD1Dull + 1;
    r.gate_v = 7;
    r.do_reset(2);
    r.no_ce();
    int f = 1;
    if (ceopt == 0) r.set_ce(c, 1, 1);
    else if (ceopt == 1) { r.set_ce(c, 1, 3); f = 3; }
    else { r.set_ce(c, 2, 1, 100); f = 2; }
    if (gvar == 1) r.gate_v &= ~(1 << c);
    r.idle(2);
    r.ctl(c, rw, mode, bcd);
    r.wcount(c, rw, count);

    uint32_t eff = eff_count(rw, bcd, count);
    if (eff > 1200) eff = 1200;
    int N = 150 + (int)(eff * f * 5 / 2);
    for (int k = 0; k < N; k++)
    {
        // gate behaviour
        if (gvar == 1 && k == N / 4) r.gate_v |= 1 << c;
        if (gvar == 2 && (k == N / 5 || k == N / 2)) r.gate_v &= ~(1 << c);
        if (gvar == 2 && (k == N / 5 + 1 + (int)(r.rnd() % 6) || k == N / 2 + 1 + (int)(r.rnd() % 6))) r.gate_v |= 1 << c;
        if (gvar == 3 && r.rnd() % 12 == 0) r.gate_v ^= 1 << c;
        if (gvar == 4 && (k % 17) == 3) r.gate_v ^= 1 << c;            // regular toggling, short pulses
        if (r.rnd() % 7 == 0) r.gate_v ^= (r.rnd() & 7) & ~(1 << c);     // the other two gates wiggle

        unsigned o = r.rnd() % 48;
        if (o < 6)       r.rdr(c);
        else if (o == 6) r.wrt(3, c << 6 | (r.rnd() & 0x0f));                // counter latch command
        else if (o == 7 && r.rnd() % 3 == 0) r.wcount(c, rw, r.rnd() % 3 ? count : (unsigned)(r.rnd() & 0xff));   // reload while counting
        else if (o == 8) r.rdr(3);
        else if (o == 9 && PIT8254) r.wrt(3, 0xC0 | (r.rnd() & 0x3e));        // read-back
        else r.idle();
    }
    r.rdr(c); r.rdr(c); r.rdr(c);
}

static void sweep(Rig &r)
{
    static const unsigned c1[] = {0, 1, 2, 3, 4, 5, 6, 9, 0x10, 0x99, 0xFF, 0x0A};
    static const unsigned c2[] = {0, 1, 2, 0x10, 0x99, 0xFF};
    static const unsigned c3[] = {0, 1, 2, 3, 4, 5, 6, 7, 9, 0x10, 0xFF, 0x100, 0x101, 0x105, 0x1001, 0x0A0A, 0x1234, 0x9999, 0xFFFF};
    uint64_t seed = 1;
    for (int c = 0; c < 3; c++)
        for (int mode = 0; mode < 8; mode++)
            for (int bcd = 0; bcd < 2; bcd++)
                for (int rw = 1; rw <= 3; rw++)
                {
                    const unsigned *cl = rw == 1 ? c1 : rw == 2 ? c2 : c3;
                    int ncl = rw == 1 ? 12 : rw == 2 ? 6 : 19;
                    for (int i = 0; i < ncl; i++)
                        for (int gvar = 0; gvar < 5; gvar++)
                            for (int ceopt = 0; ceopt < 3; ceopt++)
                            {
                                // the long counts only with a plain gate and clock, they exist for the digit borrows
                                if (cl[i] >= 0x1000 && cl[i] != 0x1001 && cl[i] != 0x1234 && (gvar || ceopt)) continue;
                                if (cl[i] >= 0x1000 && ceopt == 1) continue;
                                scenario(r, c, mode, bcd, rw, cl[i], gvar, ceopt, seed++);
                            }
                }
}

// ---------------------------------------------------------------------------------------------
// directed tests
static void d_latch(Rig &r)
{
    r.tag = "directed latch";
    for (int mode = 0; mode < 6; mode++)
        for (int bcd = 0; bcd < 2; bcd++)
            for (int rw = 1; rw <= 3; rw++)
                for (int div = 1; div <= 3; div += 2)
                {
                    r.do_reset(2); r.gate_v = 7; r.no_ce();
                    for (int c = 0; c < 3; c++) r.set_ce(c, 1, div + c);
                    for (int c = 0; c < 3; c++) { r.ctl(c, rw, mode, bcd); r.wcount(c, rw, rw == 2 ? 0x02 : (c == 0 ? 0x0123 : c == 1 ? 0x0046 : 0x0705)); }
                    r.idle(37);
                    for (int c = 0; c < 3; c++) r.wrt(3, c << 6);            // latch all three, same moment
                    r.idle(20);
                    for (int c = 0; c < 3; c++) r.wrt(3, c << 6);            // second latch: ignored while latched
                    for (int k = 0; k < 4; k++) for (int c = 0; c < 3; c++) { r.rdr(c); r.idle(3); }
                    r.wrt(3, 0 << 6);                                        // new latch after the drain
                    r.idle(5);
                    r.rdr(0);                                                // 16-bit: LSB read ...
                    r.wrt(3, 0 << 6);                                        // ... latch with RMSB set: no effect
                    r.idle(4); r.rdr(0); r.rdr(0); r.rdr(0);
                    r.wrt(3, 1 << 6 | 0x0f); r.idle(2); r.rdr(1); r.rdr(1); r.rdr(1);   // latch word with junk low bits
                    r.rdr(2); r.idle(7); r.rdr(2); r.idle(1);                // unlatched reads, count moving
                }
}

static void d_reload(Rig &r)
{
    r.tag = "directed reload";
    for (int mode = 0; mode < 6; mode++)
        for (int bcd = 0; bcd < 2; bcd++)
            for (int rw = 1; rw <= 3; rw++)
                for (int c = 0; c < 3; c++)
                {
                    r.do_reset(2); r.gate_v = 7; r.no_ce(); r.set_ce(c, 1, 1);
                    r.ctl(c, rw, mode, bcd);
                    r.wcount(c, rw, rw == 2 ? 0x01 : 0x0012);
                    r.idle(7);
                    r.wcount(c, rw, rw == 2 ? 0x02 : 0x0007);                   // reload while counting
                    for (int k = 0; k < 30; k++) { r.idle(1); if (k % 5 == 0) r.rdr(c); }
                    if (rw == 3)
                    {
                        r.wrt(c, 0x03);                                         // LSB only: counter is mid-16-bit-write
                        r.idle(5); r.rdr(c); r.rdr(c); r.idle(2);               // read returns ~LSB
                        r.wrt(c, 0x00);                                         // MSB completes it
                        r.idle(20); r.rdr(c); r.rdr(c);
                        r.wrt(c, 0x01); r.idle(4); r.wrt(3, c << 6 | 3 << 4 | mode << 1 | bcd);   // control word between LSB and MSB
                        r.idle(10); r.wrt(c, 0x04); r.wrt(c, 0x00); r.idle(20);
                    }
                    r.wcount(c, rw, 1);                                         // count 1 (illegal in modes 2 / 3)
                    r.idle(12); r.rdr(c); r.rdr(c);
                    r.wcount(c, rw, 0); r.idle(20); r.rdr(c);
                    r.ctl(c, rw, mode, bcd); r.idle(4); r.rdr(c); r.rdr(c);     // mode rewrite: null count, output rule
                }
}

static void d_gate(Rig &r)
{
    r.tag = "directed gate";
    for (int mode = 0; mode < 6; mode++)
        for (int bcd = 0; bcd < 2; bcd++)
            for (int c = 0; c < 3; c++)
                for (int div = 1; div <= 3; div++)
                    for (int start = 0; start < 16; start++)
                        for (int len = 1; len <= 9; len++)
                        {
                            r.do_reset(1); r.gate_v = 7; r.no_ce(); r.set_ce(c, 1, div);
                            r.ctl(c, 1, mode, bcd); r.wcount(c, 1, 5);
                            for (int k = 0; k < 40; k++)
                            {
                                if (k == start) r.gate_v &= ~(1 << c);
                                if (k == start + len) r.gate_v |= 1 << c;
                                r.idle();
                                if (k % 9 == 0) r.rdr(c);
                            }
                        }
    // gate low while the mode word / count is written, and gate high only later
    for (int mode = 0; mode < 6; mode++)
        for (int c = 0; c < 3; c++)
        {
            r.do_reset(1); r.gate_v = 7 & ~(1 << c); r.no_ce(); r.set_ce(c, 1, 2);
            r.ctl(c, 3, mode, 0); r.wcount(c, 3, 9); r.idle(30);
            r.gate_v |= 1 << c; r.idle(40);
            r.gate_v &= ~(1 << c); r.idle(10); r.rdr(c);
            r.gate_v |= 1 << c; r.idle(40);
            r.ctl(c, 3, mode, 1); r.gate_v &= ~(1 << c); r.wcount(c, 3, 0x12); r.idle(9); r.gate_v |= 1 << c; r.idle(60);
        }
}

static void d_rates(Rig &r)
{
    r.tag = "directed rates";
    static const int divs[6][3] = {{1, 2, 5}, {5, 1, 2}, {2, 5, 1}, {1, 1, 1}, {3, 7, 11}, {1, 13, 2}};
    for (int s = 0; s < 6; s++)
        for (int m = 0; m < 6; m++)
            for (int bcd = 0; bcd < 2; bcd++)
            {
                r.do_reset(2); r.gate_v = 7; r.no_ce();
                for (int c = 0; c < 3; c++)
                {
                    r.set_ce(c, c == 2 && s == 5 ? 2 : 1, divs[s][c], 90);
                    r.ctl(c, 3, (m + c * 2) % 6, bcd ^ (c == 1));              // mixed modes / BCD across the three counters
                    r.wcount(c, 3, 8 + 5 * c);
                }
                for (int k = 0; k < 400; k++) { r.idle(); if (k % 11 == 0) r.rdr(k % 3); if (k % 53 == 0) r.wrt(3, (k % 3) << 6); }
                // same mode everywhere, free-running rates, different counts
                for (int c = 0; c < 3; c++) { r.ctl(c, 3, m, bcd); r.wcount(c, 3, 3 + c * 4); }
                for (int k = 0; k < 400; k++) { r.idle(); if (k % 17 == 0) r.rdr(k % 3); }
            }
}

static void d_readback(Rig &r)
{
    r.tag = "directed readback";
    for (int mode = 0; mode < 6; mode++)
        for (int bcd = 0; bcd < 2; bcd++)
            for (int rw = 1; rw <= 3; rw++)
            {
                for (int cmd = 0; cmd < 4 * 8 * 2; cmd++)          // all [5:4] x [3:1] x bit0
                {
                    unsigned data = 0xC0 | (cmd >> 4 & 3) << 4 | (cmd >> 1 & 7) << 1 | (cmd & 1);
                    r.do_reset(1); r.gate_v = 7; r.no_ce();
                    for (int c = 0; c < 3; c++) { r.set_ce(c, 1, c + 1); r.ctl(c, rw, (mode + c) % 6, bcd); }
                    r.rdr(0);                                      // null count visible in the status byte
                    r.wrt(3, data);                                // status of untouched counters
                    for (int c = 0; c < 3; c++) r.rdr(c);
                    for (int c = 0; c < 3; c++) r.wcount(c, rw, rw == 2 ? 0x01 : 0x0030 + c * 17);
                    r.idle(13);
                    r.wrt(3, data);
                    r.idle(9);
                    r.wrt(3, data);                                // repeat while already latched: ignored
                    for (int k = 0; k < 4; k++) for (int c = 0; c < 3; c++) { r.rdr(c); r.idle(1); }
                    r.wrt(3, data); r.rdr(1); r.wrt(3, data);      // read-back with RMSB set / status pending
                    for (int k = 0; k < 4; k++) for (int c = 0; c < 3; c++) r.rdr(c);
                }
                // status flags: output, null count, mode, access, bcd across a run, read after each phase
                r.do_reset(1); r.gate_v = 7; r.no_ce();
                for (int c = 0; c < 3; c++) { r.set_ce(c, 1, 1); r.ctl(c, rw, mode, bcd); r.wcount(c, rw, rw == 2 ? 0x01 : 4); }
                for (int k = 0; k < 330; k++) { r.wrt(3, 0xC0 | 0x20 | 0x0e); r.rdr(k % 3); r.idle(1); }
            }
}

// count left in CR by an earlier mode (1 is legal in modes 0 / 1 / 4 / 5 but is rewritten by load_count in 2 / 3),
// then the mode word changes and a gate edge triggers the load without a new count write
static void d_stale(Rig &r)
{
    r.tag = "directed stale count";
    for (int from = 0; from < 6; from++)
        for (int to = 0; to < 6; to++)
            for (int bcd = 0; bcd < 2; bcd++)
                for (unsigned cnt = 0; cnt < 6; cnt++)
                    for (int div = 1; div <= 2; div++)
                        for (int c = 0; c < 3; c++)
                        {
                            r.do_reset(1); r.gate_v = 7 & ~(1 << c); r.no_ce(); r.set_ce(c, 1, div);
                            r.ctl(c, 1, from, bcd); r.wcount(c, 1, cnt);
                            r.idle(6);
                            r.ctl(c, 1, to, bcd);                                  // CR keeps cnt, no count write
                            r.idle(3);
                            r.gate_v |= 1 << c;                                    // rising edge: modes 1, 2, 3, 5 load CR
                            for (int k = 0; k < 24; k++) { r.idle(); if (k % 7 == 3) r.rdr(c); }
                            r.gate_v &= ~(1 << c); r.idle(3); r.gate_v |= 1 << c;  // and a second trigger
                            for (int k = 0; k < 16; k++) r.idle();
                            r.rdr(c);
                        }
}

// a new count written at every offset of a running count (legal 1 / 2 included): exercises the clock where the
// counter is at its last value of a phase while CR changes
static void d_midwrite(Rig &r)
{
    r.tag = "directed mid-count write";
    for (int mode = 0; mode < 6; mode++)
        for (int bcd = 0; bcd < 2; bcd++)
            for (unsigned c0 = 2; c0 <= 9; c0++)
                for (int off = 0; off < 14; off++)
                    for (unsigned nc = 0; nc <= 4; nc++)
                        for (int div = 1; div <= 2; div++)
                        {
                            int c = (mode + off) % 3;
                            r.do_reset(1); r.gate_v = 7; r.no_ce(); r.set_ce(c, 1, div);
                            r.ctl(c, 1, mode, bcd); r.wcount(c, 1, c0);
                            r.idle(off);
                            r.wcount(c, 1, nc);
                            for (int k = 0; k < 26; k++) { r.idle(); if (k % 9 == 4) r.rdr(c); }
                        }
}

static void directed(Rig &r) { d_latch(r); d_reload(r); d_gate(r); d_rates(r); d_readback(r); d_stale(r); d_midwrite(r); }

// ---------------------------------------------------------------------------------------------
// long seeded random sequence
static void random_run(Rig &r, uint64_t seed, uint64_t cycles)
{
    char buf[64]; snprintf(buf, sizeof buf, "random seed %llu", (unsigned long long)seed); r.tag = buf;
    r.rs = seed * 0x9E3779B97F4A7C15ull + 0x1234567;
    for (int i = 0; i < 8; i++) r.rnd();
    r.gate_v = 7; r.no_ce(); r.do_reset(2);
    unsigned gate_period = 64, bus_rate = 6, small_pct = 70;
    uint64_t end = r.cyc + cycles;
    auto reconfig = [&]() {
        static const unsigned gp[] = {0, 8, 64, 500, 3};
        static const unsigned br[] = {2, 4, 6, 40, 300};
        gate_period = gp[r.rnd() % 5]; bus_rate = br[r.rnd() % 5]; small_pct = 40 + r.rnd() % 60;
        for (int c = 0; c < 3; c++)
        {
            unsigned k = r.rnd() % 6;
            if (k == 0) r.set_ce(c, 0);
            else if (k == 1) r.set_ce(c, 1, 1);
            else if (k == 2) r.set_ce(c, 1, 2 + r.rnd() % 7);
            else if (k == 3) r.set_ce(c, 2, 1, 128);
            else if (k == 4) r.set_ce(c, 2, 1, 8 + r.rnd() % 30);
            else r.set_ce(c, 2, 1, 230);
        }
    };
    reconfig();
    auto cval = [&]() -> unsigned { return (r.rnd() % 100 < small_pct) ? (unsigned)(r.rnd() % 13) : (unsigned)(r.rnd() & 0xff); };
    while (r.cyc < end)
    {
        if (r.rnd() % 4000 == 0) reconfig();
        if (gate_period && r.rnd() % gate_period == 0) r.gate_v ^= 1 << (r.rnd() % 3);
        if (r.rnd() % (1u << 20) == 0) { r.do_reset(1 + r.rnd() % 3); continue; }
        if (r.rnd() % bus_rate)
        {
            r.idle();
            continue;
        }
        unsigned o = r.rnd() % 100;
        if (o < 22)                                                  // count write
            r.wrt(r.rnd() % 3, cval());
        else if (o < 33)                                             // control word / latch / read-back
        {
            unsigned t = r.rnd() % 100;
            unsigned cn = (t < 14) ? 3 : r.rnd() % 3;
            unsigned rw = (t % 7 == 0) ? 0 : 1 + r.rnd() % 3;
            r.wrt(3, cn << 6 | rw << 4 | (r.rnd() & 0x0f));
        }
        else if (o < 95)                                             // read
            r.rdr(r.rnd() % 4);
        else if (o < 98)                                             // strobes without chip select: no effect
            r.step(0, 0, r.rnd() & 1, r.rnd() & 1, r.rnd() & 3, r.rnd() & 0xff, r.ce_now(), r.gate_v);
        else                                                         // 8254 read-back biased towards useful forms
            r.wrt(3, 0xC0 | (r.rnd() & 0x3e));
    }
}

// ---------------------------------------------------------------------------------------------
static void report_cov(const Rig &r)
{
    const Cov &c = r.cov;
    printf("coverage (%s):\n", PIT8254 ? "8254" : "8253");
    printf("  clk_ce pulses per mode (counter 0/1/2):");
    for (int m = 0; m < 6; m++) printf("  m%d=%llu/%llu/%llu", m, (unsigned long long)c.ce[0][m], (unsigned long long)c.ce[1][m], (unsigned long long)c.ce[2][m]);
    printf("\n  out toggles per mode (c0/c1/c2):");
    for (int m = 0; m < 6; m++) printf("  m%d=%llu/%llu/%llu", m, (unsigned long long)c.tog[0][m], (unsigned long long)c.tog[1][m], (unsigned long long)c.tog[2][m]);
    printf("\n  phase visits (ce events) per mode, ph0..3:");
    for (int m = 0; m < 6; m++) printf("  m%d=%llu/%llu/%llu/%llu", m, (unsigned long long)c.ph[m][0], (unsigned long long)c.ph[m][1], (unsigned long long)c.ph[m][2], (unsigned long long)c.ph[m][3]);
    printf("\n  gate falling/rising edges per mode:");
    for (int m = 0; m < 6; m++) printf("  m%d=%llu/%llu", m, (unsigned long long)c.gate[m][0], (unsigned long long)c.gate[m][1]);
    printf("\n  mode-word writes per mode (0..7):");
    for (int m = 0; m < 8; m++) printf(" %llu", (unsigned long long)c.w_set[m]);
    printf("\n  count writes by access (1/2/3): %llu/%llu/%llu   counter-latch cmds: %llu\n", (unsigned long long)c.w_cnt[1], (unsigned long long)c.w_cnt[2], (unsigned long long)c.w_cnt[3], (unsigned long long)c.w_latch);
    printf("  read-back cmds by #counters (0..3): %llu/%llu/%llu/%llu   status-only %llu, count-only %llu, both %llu\n",
           (unsigned long long)c.w_rb[0], (unsigned long long)c.w_rb[1], (unsigned long long)c.w_rb[2], (unsigned long long)c.w_rb[3],
           (unsigned long long)c.w_rb_st, (unsigned long long)c.w_rb_ct, (unsigned long long)c.w_rb_both);
    printf("  reads: unlatched rw1/2/3 %llu/%llu/%llu, latched-count %llu, status %llu, ~LSB mid-write %llu, MSB-next %llu, control(a=3) %llu, with null-count set %llu\n",
           (unsigned long long)c.rd_norm[1], (unsigned long long)c.rd_norm[2], (unsigned long long)c.rd_norm[3], (unsigned long long)c.rd_lat,
           (unsigned long long)c.rd_stat, (unsigned long long)c.rd_wmsb, (unsigned long long)c.rd_mid, (unsigned long long)c.rd_ctl, (unsigned long long)c.null_rd);
    printf("  BCD wraps 0->9999: %llu, binary wraps 0->FFFF: %llu, resets %llu, wr/rd strobes without cs %llu, held writes (rule 1) %llu\n",
           (unsigned long long)c.bcd_wrap, (unsigned long long)c.bin_wrap, (unsigned long long)c.resets, (unsigned long long)c.nocs, (unsigned long long)c.held);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    std::string what = "all";
    uint64_t seed = 1, cycles = 25000000, seeds = 8;
    for (int i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--seed") && i + 1 < argc) seed = strtoull(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "--cycles") && i + 1 < argc) cycles = strtoull(argv[++i], 0, 0);
        else if (!strcmp(argv[i], "--seeds") && i + 1 < argc) seeds = strtoull(argv[++i], 0, 0);
        else if (argv[i][0] != '-') what = argv[i];
    }
    Rig r;
    r.do_reset(3);
    uint64_t c0;
    if (what == "all" || what == "directed")
    {
        c0 = r.cyc; directed(r);
        printf("directed: %llu clocks, divergences so far %llu\n", (unsigned long long)(r.cyc - c0), (unsigned long long)r.errs);
    }
    if (what == "all" || what == "sweep")
    {
        c0 = r.cyc; sweep(r);
        printf("sweep: %llu clocks, divergences so far %llu\n", (unsigned long long)(r.cyc - c0), (unsigned long long)r.errs);
    }
    if (what == "all" || what == "random")
    {
        c0 = r.cyc;
        for (uint64_t s = 0; s < seeds; s++) random_run(r, seed + s, cycles);
        printf("random: %llu seeds x %llu clocks = %llu clocks, divergences so far %llu\n", (unsigned long long)seeds, (unsigned long long)cycles,
               (unsigned long long)(r.cyc - c0), (unsigned long long)r.errs);
    }
    report_cov(r);
    printf("%s: %llu clocks total, %llu divergences\n", r.errs ? "FAIL" : "PASS", (unsigned long long)r.cyc, (unsigned long long)r.errs);
    return r.errs ? 1 : 0;
}

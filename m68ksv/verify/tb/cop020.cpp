// Copyright (C) 2026 Rodimus
// cop020: directed test of the 68020 coprocessor interface of m68ksv (CPU = 68020 / 68021), checkpoint 4b, with a
// scripted coprocessor model on Cp-ID 1 (a 16-bit port in CPU space type 2; Cp-ID 2 is absent: bus error). Steps:
//   1 cpGEN cp1: command word to the command register ($0A), response ($00) busy, busy, null + come again, null: done
//   2 cpGEN cp2 (absent): BERR on the command write -> F-line exception (vector 11, format 0, PC = the instruction)
//   3 cpGEN cp1, response $1C30 (take preinstruction exception: a primitive m68ksv does not implement) -> protocol
//     violation (vector 13); busy = $A400 (cp5: the manual's encoding, was $0400)
//   4 cpBcc.W cp1 (answered: not implemented beyond the condition write) -> protocol violation
//   5 cpBcc.W cp2 (absent): BERR on the condition write ($0E) -> F-line
//   6 cpSAVE (A0) cp2 (absent): BERR on the save-register read ($04) -> F-line
//   7 cpGEN cp1, response null at once: done
// Checked: every CPU-space cycle (address, R/W, SIZ, written data), the exception taken by each step (vector, stacked PC,
// format / vector word, recorded by the handlers), and that the steps that complete run on.
//   cop020 [-w W] [-v]
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <vector>
#include <deque>
#include <string>

static uint8_t mem[1 << 20];
static uint32_t rs = 5;
static uint32_t rnd() { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v); }
static uint32_t r32(uint32_t a) { return ((uint32_t)mem[a] << 24) | (mem[a + 1] << 16) | (mem[a + 2] << 8) | mem[a + 3]; }
static uint16_t r16(uint32_t a) { return (mem[a] << 8) | mem[a + 1]; }
struct Sp { uint32_t a; int rw, siz; uint16_t d; };

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int wmax = 2; bool verbose = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-w")) wmax = atoi(argv[++i]);
        else if (!strcmp(argv[i], "-v")) verbose = true;
    }
    const uint32_t CODE = 0x1000, RES = 0x9000;
    memset(mem, 0, sizeof mem);
    w32(0, 0x7000); w32(4, CODE);
    for (int v = 2; v < 64; v++) w32(v * 4, 0x2000);
    w16(0x2000, 0x60fe);
    w32(11 * 4, 0x3000); w32(13 * 4, 0x3100);
    for (int h = 0; h < 2; h++) {           // handlers: D5 = vector, D4 = stacked PC, D3 = format / vector word; PC += 4; RTE
        uint32_t q = h ? 0x3100 : 0x3000;
        uint16_t c[] = {(uint16_t)(0x7a00 | (h ? 13 : 11)), 0x282f, 0x0002, 0x362f, 0x0006, 0x58af, 0x0002, 0x4e73};
        for (uint16_t x : c) { w16(q, x); q += 2; }
    }
    uint32_t p = CODE;
    auto o16 = [&](uint16_t v) { w16(p, v); p += 2; };
    o16(0x2c7c); o16(RES >> 16); o16(RES);                     // MOVEA.L #RES,A6
    o16(0x207c); o16(0x0000); o16(0x8000);                     // MOVEA.L #$8000,A0
    std::vector<uint32_t> step_pc;
    auto store = [&]() { o16(0x2cc5); o16(0x2cc4); o16(0x3cc3); o16(0x7a00); o16(0x7800); o16(0x7600); };   // results, clear
    o16(0x7a00); o16(0x7800); o16(0x7600);
    step_pc.push_back(p); o16(0xf200); o16(0x1234); store();   // 1
    step_pc.push_back(p); o16(0xf400); o16(0x5678); store();   // 2
    step_pc.push_back(p); o16(0xf200); o16(0x9abc); store();   // 3
    step_pc.push_back(p); o16(0xf281); o16(0x0000); store();   // 4 cpBcc.W cp1, condition 1
    step_pc.push_back(p); o16(0xf481); o16(0x0000); store();   // 5 cpBcc.W cp2
    step_pc.push_back(p); o16(0xf510); o16(0x4e71); store();   // 6 cpSAVE (A0) cp2 (+ NOP the handler's PC += 4 skips)
    step_pc.push_back(p); o16(0xf200); o16(0x0042); store();   // 7
    uint32_t endpc = p; o16(0x4e71); o16(0x60fe);
    // coprocessor 1 responses, in order of the response-register reads
    // (cp5, User's Manual 7.4.3 / 7.4.4: busy = $A400 (CA, DR set), null = $08xx / $88xx with IA = bit 8 - so $8900 is a
    // null + come again + interrupts allowed; step 3 uses take-preinstruction-exception $1C30, which m68ksv does not implement)
    std::deque<uint16_t> resp = {0xa400, 0xa400, 0x8800, 0x0800, 0x1c30, 0x0800};
    Vm68ksv *t = new Vm68ksv;
    t->DSACK_n = 3; t->STERM_n = 1; t->AVEC_n = 1; t->CDIS_n = 1; t->BERR_n = 1; t->BR_n = 1; t->BGACK_n = 1;
    t->IPL_n = 7; t->HALT_n_i = 1; t->tl_en = 0;
    std::vector<Sp> sp; bool in_as = false, wseen = false, done = false; int wait = 0; long n; uint16_t cur_resp = 0;
    for (n = 0; n < 400000 && !done; n++) {
        t->RESET_n_i = n > 80;
        uint32_t a32 = t->A32, a = a32 & 0xfffff;
        bool cpu = t->FC == 7 && n > 120, cop = cpu && ((a32 >> 16) & 0xf) == 2, cp1 = cop && ((a32 >> 13) & 7) == 1;
        if (t->AS_n) { in_as = false; wait = wmax ? rnd() % (wmax + 1) : 0; }
        else if (!in_as) {
            in_as = true; wseen = false;
            if (cop) {
                if (t->RW && cp1 && (a32 & 0x1f) == 0) { cur_resp = resp.empty() ? 0x0800 : resp.front(); if (!resp.empty()) resp.pop_front(); }
                sp.push_back(Sp{a32, t->RW, t->SIZ, (uint16_t)(t->RW ? cur_resp : 0)});
            }
        }
        uint32_t d = rnd();
        if (cop) d = ((uint32_t)cur_resp << 16) | (d & 0xffff);
        else d = ((uint32_t)mem[a & ~3u] << 24) | ((uint32_t)mem[(a & ~3u) + 1] << 16) | (mem[(a & ~3u) + 2] << 8) | mem[(a & ~3u) + 3];
        t->D32_i = d;
        bool ack = !t->AS_n && wait == 0;
        t->DSACK_n = !ack ? 3 : cop ? (cp1 ? 1 : 3) : 0;          // memory: 32-bit port; coprocessor 1: 16-bit port
        t->BERR_n = !(ack && cop && !cp1);
        if (!t->AS_n && wait > 0 && (n % 4) == 0) wait--;
        t->cen_p = (n % 4) == 0; t->cen_n = (n % 4) == 2;
        t->clk = 0; t->eval(); bool fin = t->dbg_fin; t->clk = 1; t->eval();
        a32 = t->A32; a = a32 & 0xfffff;
        cop = t->FC == 7 && ((a32 >> 16) & 0xf) == 2;
        if (!t->AS_n && !t->RW && !t->DS_n && !wseen) {
            wseen = true;
            if (cop) { if (!sp.empty()) sp.back().d = t->D32_o >> 16; }
            else {
                int nb = t->SIZ ? t->SIZ : 4, o = a & 3, k = std::min(nb, 4 - o);
                for (int j = 0; j < k; j++) mem[(a + j) & 0xfffff] = t->D32_o >> (24 - 8 * (o + j));
            }
        }
        if (fin && (t->dbg_pc & 0xfffff) >= endpc && (t->dbg_pc & 0xfffff) <= endpc + 4) done = true;
    }
    int fails = 0;
    if (!done) { printf("cop020: program did not complete\n"); fails++; }
    // expected CPU-space cycles
    std::vector<Sp> e = {
        {0x2200a, 0, 2, 0x1234}, {0x22000, 1, 2, 0xa400}, {0x22000, 1, 2, 0xa400}, {0x22000, 1, 2, 0x8800}, {0x22000, 1, 2, 0x0800},
        {0x2400a, 0, 2, 0x5678},
        {0x2200a, 0, 2, 0x9abc}, {0x22000, 1, 2, 0x1c30},
        {0x2200e, 0, 2, 0x0001},
        {0x2400e, 0, 2, 0x0001},
        {0x24004, 1, 2, 0x0000},
        {0x2200a, 0, 2, 0x0042}, {0x22000, 1, 2, 0x0800}};
    std::string why;
    if (sp.size() != e.size()) { char b[64]; snprintf(b, sizeof b, " (%zu CPU-space cycles, expected %zu)", sp.size(), e.size()); why += b; }
    for (size_t i = 0; i < sp.size() && i < e.size(); i++)
        if (sp[i].a != e[i].a || sp[i].rw != e[i].rw || (sp[i].siz & 3) != e[i].siz || (sp[i].d != e[i].d && !(e[i].a == 0x24004))) {
            char b[120]; snprintf(b, sizeof b, " cycle %zu: %08x %c SIZ%d %04x (expected %08x %c SIZ%d %04x)", i, sp[i].a, sp[i].rw ? 'r' : 'w',
                                  sp[i].siz, sp[i].d, e[i].a, e[i].rw ? 'r' : 'w', e[i].siz, e[i].d); why += b; }
    if (!why.empty()) { printf("CPU-space cycles:%s\n", why.c_str()); fails++; }
    if (verbose) for (auto &c : sp) printf("   %08x %c SIZ%d %04x\n", c.a, c.rw ? 'r' : 'w', c.siz, c.d);
    // per step: D5 (vector or 0), D4 (stacked PC), D3 (format / vector word)
    static const int vec[7] = {0, 11, 13, 13, 11, 11, 0};
    for (int s = 0; s < 7; s++) {
        uint32_t r = RES + 10 * s;
        uint32_t d5 = r32(r), d4 = r32(r + 4); uint16_t d3 = r16(r + 8);
        bool ok = d5 == (uint32_t)vec[s] && (vec[s] == 0 ? (d4 == 0 && d3 == 0) : (d4 == step_pc[s] && d3 == (uint16_t)(vec[s] * 4)));
        if (!ok) fails++;
        if (!ok || verbose) printf("step %d: %s (vector %u, stacked PC %x, format/vector %04x; expected %d, %x, %04x)\n", s + 1, ok ? "ok" : "FAIL",
                                   d5, d4, d3, vec[s], vec[s] ? step_pc[s] : 0, vec[s] * 4);
    }
    printf("cop020 (waits 0-%d): %zu CPU-space cycles, 7 steps, %d failures\n", wmax, sp.size(), fails);
    delete t;
    return fails != 0;
}

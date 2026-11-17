// Copyright (C) 2026 Rodimus
// m68ksv directed smoke test for paths the single-step suite does not cover: reset (SSP / PC from the vector table),
// an autovectored level-1 interrupt taken and returned from (RTE), trace after an instruction with T set, STOP woken
// by an interrupt. Pass / fail per item; not a timing check.
#include "Vm68ksv.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>

static uint8_t mem[1 << 24];
static Vm68ksv *top;
static uint64_t n;
static void w16(uint32_t a, uint16_t v) { mem[a] = v >> 8; mem[a + 1] = v & 0xff; }
static void w32(uint32_t a, uint32_t v) { w16(a, v >> 16); w16(a + 2, v & 0xffff); }

static void tick() {
    uint32_t a = ((uint32_t)top->A << 1) & 0xfffffe;
    top->D_i = (mem[a] << 8) | mem[a + 1];
    // autovector: VPA during an interrupt acknowledge (FC = 7)
    top->VPA_n = !(top->FC == 7 && !top->AS_n);
    top->DTACK_n = top->FC == 7 && !top->AS_n;
    top->cen_p = (n & 1) == 0; top->cen_n = (n & 1) == 1;
    top->clk = 0; top->eval(); top->clk = 1; top->eval();
    n++;
    a = ((uint32_t)top->A << 1) & 0xfffffe;
    if (!top->AS_n && !top->RW) {
        if (!top->UDS_n) mem[a] = top->D_o >> 8;
        if (!top->LDS_n) mem[a + 1] = top->D_o & 0xff;
    }
}

// register-file entry through the debug read port, CPU held (no clock enables)
static uint32_t rreg(int k) {
    top->dbg_ra = k;
    top->cen_p = 0; top->cen_n = 0;
    top->clk = 0; top->eval(); top->clk = 1; top->eval();
    return top->dbg_rd;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vm68ksv;
    top->BERR_n = 1; top->IPL_n = 7; top->BR_n = 1; top->BGACK_n = 1; top->tl_en = 0;
    w32(0, 0x1000); w32(4, 0x400);
    w32(0x64, 0x500);                      // level-1 autovector
    w32(0x24, 0x700);                      // trace
    uint32_t p = 0x400;
    w16(p, 0x46fc); w16(p + 2, 0x2000); p += 4;   // MOVE #$2000,SR (mask 0)
    w16(p, 0x7001); p += 2;                        // MOVEQ #1,D0
    w16(p, 0x5280); p += 2;                        // loop: ADDQ.L #1,D0
    w16(p, 0x60fc); p += 2;                        // BRA loop
    w16(0x500, 0x7e55); w16(0x502, 0x4e73);        // MOVEQ #$55,D7 ; RTE
    w16(0x700, 0x7c66); w16(0x702, 0x4e73);        // MOVEQ #$66,D6 ; RTE
    top->RESET_n_i = 0; top->HALT_n_i = 0;
    for (int i = 0; i < 20; i++) tick();
    top->RESET_n_i = 1; top->HALT_n_i = 1;
    int fails = 0;
    for (int i = 0; i < 2000; i++) tick();
    uint32_t ssp = rreg(16), d0 = rreg(0);
    bool reset_ok = ssp == 0x1000 && d0 > 3 && (top->dbg_pc >= 0x406 && top->dbg_pc <= 0x40a);
    printf("reset: SSP %08x PC %08x D0 %08x -> %s\n", ssp, top->dbg_pc, d0, reset_ok ? "ok" : "FAIL");
    fails += !reset_ok;
    uint32_t d0a = d0;
    top->IPL_n = 6;                                // level 1
    for (int i = 0; i < 400 && rreg(7) != 0x55; i++) tick();
    top->IPL_n = 7;
    for (int i = 0; i < 400; i++) tick();
    uint32_t d7 = rreg(7); d0 = rreg(0); ssp = rreg(16);
    bool int_ok = d7 == 0x55 && d0 > d0a && ssp == 0x1000 && (top->dbg_sr & 0x2700) == 0x2000;
    printf("interrupt: D7 %08x D0 %08x SSP %08x SR %04x -> %s\n", d7, d0, ssp, top->dbg_sr, int_ok ? "ok" : "FAIL");
    fails += !int_ok;
    // trace: set T via a second program entered by a fresh reset
    p = 0x400;
    w16(p, 0x46fc); w16(p + 2, 0xa700); p += 4;   // MOVE #$A700,SR (T=1)
    w16(p, 0x4e71); p += 2;                        // NOP (traced)
    w16(p, 0x60fe); p += 2;                        // BRA *
    top->RESET_n_i = 0; top->HALT_n_i = 0;
    for (int i = 0; i < 20; i++) tick();
    top->RESET_n_i = 1; top->HALT_n_i = 1;
    for (int i = 0; i < 3000; i++) tick();
    uint32_t d6 = rreg(6);
    bool tr_ok = d6 == 0x66;
    printf("trace: D6 %08x SR %04x PC %08x -> %s\n", d6, top->dbg_sr, top->dbg_pc, tr_ok ? "ok" : "FAIL");
    fails += !tr_ok;
    printf("smoke: %d / 3 pass\n", 3 - fails);
    delete top;
    return fails != 0;
}

// Copyright (C) 2026 Rodimus
// x86sv with NEC8080 in 8080 emulation mode, from reset:
//   x80 com <file.COM> [max clocks]   CP/M 8080 test program (loaded only as a memory image)
//   x80 dir [-v]                      directed tests of the mode (BRKEM / RETEM / CALLN, MD, interrupts, HALT)
// com: native boot at FFFF0 -> 0000:0700 (segments, SS:SP 0080:0100, BP F000, BRKEM 80h) -> 1000:0100 in 8080
// mode. 1000:0000 HLT (warm boot ends the run), 1000:0005 JMP F000, 1000:F000 CALLN 81h; RET. Vector 81h -> 0000:0600:
// OUT E0h, AL; RETI. The testbench answers the OUT as the CP/M BDOS: C = 2 prints E, C = 9 the $-string at DS0:DE.
#include "Vtb_x86.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <string>
#include <vector>

static Vtb_x86 *top;
static uint8_t mem[1 << 20];

static void tick() { top->eval(); top->clk = 1; top->eval(); top->clk = 0; top->eval(); }
static uint32_t get_w(const uint32_t *w, int bit, int n) {
    uint32_t v = 0; for (int i = 0; i < n; i++) { int b = bit + i; v |= ((w[b / 32] >> (b % 32)) & 1u) << i; } return v;
}
// moo register order: ax bx cx dx cs ss ds es sp bp si di ip flags
enum { AX, BX, CX, DX, CS, SS, DS, ES, SP, BP, SI, DI, IP, FL };
static uint16_t reg(int i) { return (uint16_t)get_w(top->dbg_regs, i * 16, 16); }

struct Cyc { long clk; int type; uint32_t addr; uint16_t data; bool emu; };   // emu: A19 / PS3 in T2

// the bus: memory, I/O (callbacks), INTA vector; one call = one clock
struct Sys {
    uint32_t latch = 0; int type = 7; bool hi = false; long clk = 0; bool halted = false; int nhalt = 0, ninta = 0;
    uint8_t ivec = 0;
    std::vector<Cyc> cyc;
    std::function<void(uint8_t port, uint8_t v)> on_out;
    bool log = false;
    bool rec = true;                    // keep the bus-cycle list (directed tests)
    void reset() {
        top->reset = 1; top->tl_en = 0; top->ready = 1; top->intr = 0; top->nmi = 0; top->test_n = 0; top->tl_md = 1; top->tl_mdwe = 0;
        for (int i = 0; i < 4; i++) tick();
        top->reset = 0; clk = 0; halted = false; nhalt = 0; ninta = 0; cyc.clear();
    }
    uint16_t feed() {
        if (type == 0) return (uint16_t)(ivec | (ivec << 8));
        if (type == 1) return 0xFFFF;
#ifdef BUS16
        return (uint16_t)(mem[latch & 0xFFFFE] | (mem[(latch & 0xFFFFE) | 1] << 8));
#else
        return mem[latch];
#endif
    }
    void step() {
        top->din = feed(); top->eval();
        if (top->ale) {
            latch = top->ad & 0xFFFFF; type = top->s20 & 7;
#ifdef BUS16
            hi = !top->bhe_n;
#endif
            if (type == 3) { halted = true; nhalt++; }
            if (type == 0) ninta++;
            if (rec) cyc.push_back({clk, type, latch, 0, false});
        }
        if (top->tstate == 2 && !cyc.empty()) cyc.back().emu = (top->ad >> 19) & 1;
        top->din = feed(); top->eval();
        if (top->wr && top->tstate == 3) {
            uint8_t v = (uint8_t)(((latch & 1) && hi) ? (top->dout >> 8) : top->dout);
            if (!cyc.empty()) cyc.back().data = v;
            if (top->io) { if (on_out) on_out((uint8_t)latch, v); }
            else {
#ifdef BUS16
                if (!(latch & 1)) mem[latch] = top->dout & 0xFF;
                if (hi) mem[(latch | 1) & 0xFFFFF] = top->dout >> 8;
#else
                mem[latch] = top->dout & 0xFF;
#endif
            }
        }
        tick(); clk++;
    }
};

static void put(uint32_t a, std::initializer_list<uint8_t> b) { for (uint8_t v : b) mem[(a++) & 0xFFFFF] = v; }
static void vec(int n, uint16_t seg, uint16_t off) { put(n * 4, {(uint8_t)off, (uint8_t)(off >> 8), (uint8_t)seg, (uint8_t)(seg >> 8)}); }

// native boot: CLI CLD; DS = ES = 1000; SS:SP = 0080:0100; BP = F000; BRKEM 80h; (after RETEM) HLT
static void boot_image() {
    memset(mem, 0, sizeof mem);
    put(0xFFFF0, {0xEA, 0x00, 0x07, 0x00, 0x00});
    put(0x700, {0xFA, 0xFC, 0xB8, 0x00, 0x10, 0x8E, 0xD8, 0x8E, 0xC0, 0xB8, 0x80, 0x00, 0x8E, 0xD0, 0xBC, 0x00, 0x01,
                0xBD, 0x00, 0xF0, 0x0F, 0xFF, 0x80, 0xF4});
    vec(0x80, 0x1000, 0x0100);
}

static int run_com(const char *fn, long long maxclk) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); return 1; }
    boot_image();
    size_t n = fread(&mem[0x10100], 1, 0xF000 - 0x100, f);
    fclose(f);
    (void)n;
    put(0x10000, {0x76});
    put(0x10005, {0xC3, 0x00, 0xF0});
    put(0x1F000, {0xED, 0xED, 0x81, 0xC9});
    vec(0x81, 0x0000, 0x0600);
    put(0x600, {0xE6, 0xE0, 0xCF});
    Sys s; s.rec = false; s.reset();
    long calln = 0;
    s.on_out = [&](uint8_t port, uint8_t) {
        if (port != 0xE0) return;
        calln++;
        uint8_t fnc = reg(CX) & 0xFF;
        if (fnc == 2) putchar(reg(DX) & 0xFF);
        else if (fnc == 9) {
            uint32_t base = (uint32_t)reg(DS) << 4; uint16_t p = reg(DX);
            for (int i = 0; i < 65536; i++) { uint8_t c = mem[(base + p++) & 0xFFFFF]; if (c == '$') break; putchar(c); }
        }
        fflush(stdout);
    };
    while (!s.halted && s.clk < maxclk) s.step();
    for (int i = 0; i < 16; i++) s.step();
    printf("\n[x80] %s: %ld clocks, %ld BDOS calls (CALLN), %s at %04X:%04X, MD %d\n", fn, s.clk, calln,
           s.halted ? "halted" : "stopped", reg(CS), reg(IP), (reg(FL) >> 15) & 1);
    return s.halted ? 0 : 1;
}

int dir_tests(bool verbose);

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vtb_x86;
    int rc = 2;
    if (argc >= 3 && !strcmp(argv[1], "com")) rc = run_com(argv[2], argc > 3 ? atoll(argv[3]) : 400000000000LL);
    else if (argc >= 2 && !strcmp(argv[1], "dir")) rc = dir_tests(argc > 2 && !strcmp(argv[2], "-v"));
    else fprintf(stderr, "usage: x80 com <file.COM> [max clocks] | x80 dir [-v]\n");
    delete top;
    return rc;
}


// ---- directed tests (sources: [UM] NEC uPD70108/70116 User's Manual Oct 1986, [DS] uPD70108 data sheet,
// [ALP] Intel 8080/8085 Assembly Language Programming Manual 9800301D) ----
static int npass = 0, nfail = 0;
static void check(bool ok, const char *what, const char *src) {
    printf("  %s  %-62s [%s]\n", ok ? "pass" : "FAIL", what, src);
    if (ok) npass++; else nfail++;
}
static uint16_t m16(uint32_t a) { return (uint16_t)(mem[a & 0xFFFFF] | (mem[(a + 1) & 0xFFFFF] << 8)); }
static bool emu_write(Sys &s, uint32_t a) {               // a memory write to a with PS3 high
    for (auto &c : s.cyc) if (c.type == 6 && c.addr == a) return c.emu;
    return false;
}
static bool written(Sys &s, uint32_t a) { for (auto &c : s.cyc) if (c.type == 6 && c.addr == a) return true; return false; }
// run until the n-th HALT status cycle (then a few clocks), with a per-clock hook
static void run(Sys &s, int nhalt, long maxclk, std::function<void(Sys &)> hook = nullptr) {
    while (s.nhalt < nhalt && s.clk < maxclk) { if (hook) hook(s); s.step(); }
    for (int i = 0; i < 12; i++) s.step();
}
static const uint32_t NSTK = 0x800;                       // native SS = 0080: physical base
static void handler_psw(uint32_t at, uint16_t store) {    // PUSHF; POP AW; MOV [store], AW; MOV AW, SP; MOV [store+2], AW; RETI
    put(at, {0x9C, 0x58, 0xA3, (uint8_t)store, (uint8_t)(store >> 8), 0x89, 0xE0, 0xA3, (uint8_t)(store + 2),
             (uint8_t)((store + 2) >> 8), 0xCF});
}

int dir_tests(bool verbose) {
    (void)verbose;
    Sys s;
    // A: BRKEM entry, register mapping, RETEM
    printf("A  BRKEM / register mapping / RETEM\n");
    boot_image();
    put(0x10100, {0x3E, 0x11, 0x06, 0x22, 0x0E, 0x33, 0x16, 0x44, 0x1E, 0x55, 0x26, 0x66, 0x2E, 0x77, 0x31, 0x88, 0x88,
                  0x32, 0x00, 0x02, 0xED, 0xFD});
    s.reset(); run(s, 1, 100000);
    check(m16(NSTK + 0xFA) == 0x0717 && m16(NSTK + 0xFC) == 0x0000, "BRKEM pushes PC (next instruction) and PS on SS:SP", "UM 12-169");
    check(m16(NSTK + 0xFE) & 0x8000, "BRKEM pushes PSW with MD = 1 (native)", "UM 12-169");
    check((reg(AX) & 0xFF) == 0x11 && reg(CX) == 0x2233 && reg(DX) == 0x4455 && reg(BX) == 0x6677,
          "A B C D E H L = AL CH CL DH DL BH BL", "UM 8-1 fig 8-1; DS p19");
    check(reg(BP) == 0x8888 && reg(SP) == 0x0100, "8080 SP = BP; native SP restored by RETEM", "UM 8-1; 12-177");
    check(mem[0x10200] == 0x11 && emu_write(s, 0x10200), "8080 STA writes DS0:addr with PS3 = 1", "UM 8-1; DS p5");
    check(!s.cyc.empty() && s.cyc[0].addr == 0xFFFF0 && !s.cyc[0].emu, "native bus cycles: PS3 = 0", "DS p5");
    check((reg(FL) & 0x8000) && !top->dbg_mdwe && (reg(CS) == 0) && s.halted, "RETEM: native mode (MD 1), MD write disabled", "UM 12-177; 8-5");

    // B: segments
    printf("B  segment use (code PS, data and stack DS0)\n");
    boot_image();
    put(0x702, {0xB8, 0x00, 0x20});                       // DS0 = DS1 = 2000, PS = 1000 (vector)
    put(0x10100, {0x21, 0x50, 0x00, 0x36, 0xA5, 0x3E, 0x5C, 0x32, 0x60, 0x00, 0x31, 0x00, 0x02, 0x01, 0xEF, 0xBE, 0xC5,
                  0xED, 0xFD});
    s.reset(); run(s, 1, 100000);
    check(mem[0x20050] == 0xA5 && mem[0x10050] == 0, "MVI M: DS0:HL", "UM 8-1");
    check(mem[0x20060] == 0x5C && mem[0x10060] == 0, "STA: DS0:addr", "UM 8-1");
    check(mem[0x201FE] == 0xEF && mem[0x201FF] == 0xBE && mem[NSTK + 0x1FE] == 0 && reg(BP) == 0x01FE,
          "PUSH: DS0:BP - 2 (not SS), BP decremented", "UM 8-1");

    // C: CALLN round trip
    printf("C  CALLN / RETI back to emulation\n");
    boot_image();
    put(0x700, {0xFB});                                   // STI before BRKEM (IE = 1)
    put(0x10100, {0x3E, 0x3C, 0xED, 0xED, 0x81, 0x32, 0x70, 0x00, 0xED, 0xFD});
    vec(0x81, 0x0000, 0x0600); handler_psw(0x600, 0x0080);
    s.reset(); run(s, 1, 100000);
    check(m16(0x10080) & 0x8000, "native routine called by CALLN runs with MD = 1", "UM 12-176");
    check(m16(0x10080) & 0x0200, "BRKEM and CALLN leave IE unchanged", "UM 12-169, 12-176 flag tables");
    check(m16(0x10082) == 0x00F4, "CALLN pushes 6 bytes on the native SS:SP", "UM 12-176");
    check(!(m16(NSTK + 0xF8) & 0x8000) && m16(NSTK + 0xF4) == 0x0105 && m16(NSTK + 0xF6) == 0x1000,
          "CALLN pushes PSW with MD = 0, PS, PC after CALLN", "UM 12-176");
    check(mem[0x10070] == 0xF4 && emu_write(s, 0x10070), "RETI returns to 8080 mode after CALLN", "UM 8-4; 12-168");
    check((reg(FL) & 0x8000) && !top->dbg_mdwe, "RETEM ends in native mode", "UM 12-177");

    // D1: MD write protect outside emulation
    printf("D  MD write enable\n");
    boot_image();
    put(0x10100, {0xED, 0xFD});
    put(0x717, {0xB8, 0x02, 0x70, 0x50, 0x9D, 0x9C, 0x58, 0xA3, 0x90, 0x00, 0xF4});
    s.reset(); run(s, 1, 100000);
    check(written(s, 0x10090) && (m16(0x10090) & 0x8000), "after RETEM: POP PSW with bit 15 = 0 keeps MD = 1", "UM 12-151");
    // D2: POP PSW inside a CALLN routine changes MD
    boot_image();
    put(0x10100, {0xED, 0xED, 0x81});
    vec(0x81, 0x0000, 0x0600);
    put(0x600, {0x68, 0x02, 0x00, 0x9D, 0x3E, 0x77, 0x32, 0x94, 0x00, 0x76});
    s.reset(); run(s, 1, 100000);
    check(mem[0x10094] == 0x77 && emu_write(s, 0x10094) && !(reg(FL) & 0x8000),
          "in a CALLN routine POP PSW with MD = 0 enters 8080 mode", "UM 12-151");

    // E: INT in emulation mode
    printf("E  INT in 8080 mode (IE = 1)\n");
    boot_image();
    put(0x10100, {0x3E, 0x00, 0xFB, 0x00, 0x00, 0x00, 0x32, 0xA4, 0x00, 0xED, 0xFD});
    vec(0x40, 0x0000, 0x0620); handler_psw(0x620, 0x00A0);
    s.reset(); s.ivec = 0x40; top->intr = 1;
    run(s, 1, 100000, [](Sys &x) { if (x.ninta >= 1) top->intr = 0; });
    top->intr = 0;
    uint16_t hsp = m16(0x100A2);
    check(s.ninta == 2, "one INTA pair", "UM 8-4; DS INT");
    check((m16(0x100A0) & 0x8000) && !(m16(0x100A0) & 0x0200), "handler: MD = 1, IE = 0", "UM 8-4 NMI or INT Operation");
    check(!(m16(NSTK + hsp + 4) & 0x8000) && (m16(NSTK + hsp + 4) & 0x0200), "stacked PSW: MD = 0, IE = 1", "UM 8-4");
    check(m16(NSTK + hsp) == 0x0104, "taken after the instruction following EI", "ALP 3-23 EI");
    check(emu_write(s, 0x100A4), "RETI returns to 8080 mode", "UM 8-4");

    // F: NMI in emulation mode, IE = 0
    printf("F  NMI in 8080 mode (IE = 0)\n");
    boot_image();
    {
        std::vector<uint8_t> c = {0xF3};
        for (int i = 0; i < 40; i++) c.push_back(0x00);
        c.insert(c.end(), {0x32, 0xB4, 0x00, 0xED, 0xFD});
        for (size_t i = 0; i < c.size(); i++) mem[0x10101 - 1 + i] = c[i];
    }
    vec(2, 0x0000, 0x0640); handler_psw(0x640, 0x00B0);
    s.reset();
    { long t0 = -1;
      run(s, 1, 100000, [&](Sys &x) { if (t0 < 0 && !x.cyc.empty() && x.cyc.back().emu) t0 = x.clk; if (t0 >= 0 && x.clk == t0 + 30) top->nmi = 1; }); }
    top->nmi = 0;
    check(written(s, 0x100B0) && (m16(0x100B0) & 0x8000) && s.ninta == 0, "NMI taken with IE = 0, handler native, no INTA", "UM 8-4");
    check(!(m16(NSTK + m16(0x100B2) + 4) & 0x8000), "stacked PSW: MD = 0", "UM 8-4");
    check(emu_write(s, 0x100B4), "RETI returns to 8080 mode", "UM 8-4");

    // G H I: HALT in emulation mode
    printf("G  HALT in 8080 mode, IE = 0, INT\n");
    boot_image();
    put(0x10100, {0xF3, 0x76, 0x3E, 0x5A, 0x32, 0xC0, 0x00, 0xED, 0xFD});
    s.reset();
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->intr = 1; }); }
    top->intr = 0;
    if (verbose) { printf("    nhalt %d ninta %d clk %ld\n", s.nhalt, s.ninta, s.clk); for (auto &c : s.cyc) if (c.clk > 0) printf("    %ld t%d %05X %02X e%d\n", c.clk, c.type, c.addr, c.data, c.emu); }
    check(s.nhalt == 2 && s.ninta == 0, "INT releases HALT with IE = 0, no interrupt taken", "UM 8-2");
    check(mem[0x100C0] == 0x5A && emu_write(s, 0x100C0), "execution continues after HLT in 8080 mode", "UM 8-2");
    printf("H  HALT in 8080 mode, IE = 1, INT\n");
    boot_image();
    put(0x10100, {0xFB, 0x76, 0x3E, 0x5A, 0x32, 0xC0, 0x00, 0xED, 0xFD});
    vec(0x40, 0x0000, 0x0620); handler_psw(0x620, 0x00A0);
    s.reset(); s.ivec = 0x40;
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->intr = 1;
                                      if (x.ninta >= 1) top->intr = 0; }); }
    top->intr = 0;
    check(s.ninta == 2 && (m16(0x100A0) & 0x8000), "INT taken from HALT (native routine)", "UM 8-2");
    check(m16(NSTK + m16(0x100A2)) == 0x0102 && emu_write(s, 0x100C0), "RETI resumes after HLT in 8080 mode", "UM 8-2");
    printf("I  HALT in 8080 mode, NMI\n");
    boot_image();
    put(0x10100, {0xF3, 0x76, 0x3E, 0x5A, 0x32, 0xC0, 0x00, 0xED, 0xFD});
    vec(2, 0x0000, 0x0640); handler_psw(0x640, 0x00B0);
    s.reset();
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->nmi = 1; }); }
    top->nmi = 0;
    check(written(s, 0x100B0) && (m16(0x100B0) & 0x8000) && s.ninta == 0, "NMI leaves HALT into the native routine", "UM 8-2");
    check(emu_write(s, 0x100C0), "RETI resumes after HLT in 8080 mode", "UM 8-2");

    // J: nesting CALLN -> INT n -> RETI -> RETI -> RETEM
    printf("J  nesting CALLN -> BRK n -> RETI -> RETI -> RETEM\n");
    boot_image();
    put(0x10100, {0xED, 0xED, 0x81, 0x3E, 0x99, 0x32, 0xD4, 0x00, 0xED, 0xFD});
    vec(0x81, 0x0000, 0x0600); put(0x600, {0xCD, 0x41, 0x9C, 0x58, 0xA3, 0xD2, 0x00, 0xCF});
    vec(0x41, 0x0000, 0x0660); put(0x660, {0x9C, 0x58, 0xA3, 0xD0, 0x00, 0xCF});
    s.reset(); run(s, 1, 100000);
    check(written(s, 0x100D0) && (m16(0x100D0) & 0x8000), "BRK n inside a CALLN routine: native", "UM 8-4");
    check(written(s, 0x100D2) && (m16(0x100D2) & 0x8000), "its RETI restores MD = 1 (stacked in native mode)", "UM 12-168");
    check(mem[0x100D4] == 0x99 && emu_write(s, 0x100D4), "CALLN routine's RETI returns to 8080 mode", "UM 8-4, 8-5");
    check((reg(FL) & 0x8000) && !top->dbg_mdwe && s.halted, "RETEM ends in native mode", "UM 12-177");

    // K: RESET during emulation mode
    printf("K  RESET in 8080 mode\n");
    boot_image();
    put(0x10100, {0xC3, 0x00, 0x01});
    s.reset();
    { long t0 = -1; while (s.clk < 20000) { if (t0 < 0 && !s.cyc.empty() && s.cyc.back().emu) t0 = s.clk; if (t0 >= 0 && s.clk > t0 + 100) break; s.step(); } }
    bool was = !(reg(FL) & 0x8000) && top->dbg_mdwe;
    top->reset = 1; for (int i = 0; i < 4; i++) tick(); top->reset = 0;
    s.cyc.clear();
    for (int i = 0; i < 40; i++) s.step();
    check(was, "(precondition: 8080 mode, MD write enabled)", "UM 12-169");
    check((reg(FL) & 0x8000) && !top->dbg_mdwe && !s.cyc.empty() && s.cyc[0].addr == 0xFFFF0 && !s.cyc[0].emu,
          "RESET: native mode at FFFF0, PS3 = 0, MD write disabled", "UM 8-4 RESET Operation");

    // L M N: HALT in native mode (UM 9-1 "Releasing Standby Mode with INT"): boot, then [CLI | STI] HLT;
    // MOV BYTE [00C0], 5A; HLT. Prints the clock of the first bus cycle after the tested HALT status cycle.
    auto native_halt = [&](uint8_t ie_op) {
        memset(mem, 0, sizeof mem);
        put(0xFFFF0, {0xEA, 0x00, 0x07, 0x00, 0x00});
        put(0x700, {0xFA, 0xFC, 0xB8, 0x00, 0x10, 0x8E, 0xD8, 0x8E, 0xC0, 0xB8, 0x80, 0x00, 0x8E, 0xD0, 0xBC, 0x00, 0x01,
                    ie_op, 0xF4, 0xC6, 0x06, 0xC0, 0x00, 0x5A, 0xF4});
    };
    auto after_halt = [&](Sys &x) { long th = -1; for (auto &c : x.cyc) { if (th >= 0) return c.clk - th; if (c.type == 3) th = c.clk; } return -1L; };
    printf("L  HALT in native mode, IE = 0, INT\n");
    native_halt(0xFA);
    s.reset();
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->intr = 1; }); }
    top->intr = 0;
    printf("    first bus cycle %ld clocks after the HALT status cycle\n", after_halt(s));
    check(s.nhalt == 2 && s.ninta == 0, "INT releases HALT with IE = 0, no interrupt taken", "UM 9-1");
    check(mem[0x100C0] == 0x5A && written(s, 0x100C0) && !emu_write(s, 0x100C0), "execution continues after HALT in native mode", "UM 9-1");
    printf("M  HALT in native mode, IE = 1, INT\n");
    native_halt(0xFB);
    vec(0x40, 0x0000, 0x0620); handler_psw(0x620, 0x00A0);
    s.reset(); s.ivec = 0x40;
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->intr = 1;
                                      if (x.ninta >= 1) top->intr = 0; }); }
    top->intr = 0;
    printf("    first bus cycle %ld clocks after the HALT status cycle\n", after_halt(s));
    check(s.ninta == 2 && written(s, 0x100A0) && (m16(0x100A0) & 0x8000), "INT taken from HALT", "UM 9-1");
    check(mem[0x100C0] == 0x5A, "RETI resumes after HALT", "UM 9-1");
    printf("N  HALT in native mode, NMI\n");
    native_halt(0xFA);
    vec(2, 0x0000, 0x0640); handler_psw(0x640, 0x00B0);
    s.reset();
    { long th = -1;
      run(s, 2, 100000, [&](Sys &x) { if (th < 0 && x.nhalt == 1) th = x.clk; if (th >= 0 && x.clk == th + 20) top->nmi = 1; }); }
    top->nmi = 0;
    printf("    first bus cycle %ld clocks after the HALT status cycle\n", after_halt(s));
    check(written(s, 0x100B0) && s.ninta == 0, "NMI leaves HALT into its routine", "UM 9-1");
    check(mem[0x100C0] == 0x5A, "RETI resumes after HALT", "UM 9-1");

    printf("directed 8080-mode tests: %d / %d pass\n", npass, npass + nfail);
    return nfail ? 1 : 0;
}

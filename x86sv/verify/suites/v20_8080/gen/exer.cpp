// Copyright (C) 2026 Rodimus
// Runs a CP/M 8080 test program (.COM, loaded only as a memory image) on the reference model in 8080 emulation mode:
//   exer <file.COM> [max instructions]
// Memory image (the same layout the RTL exerciser test uses): 8080 segment 1000h (PS = DS0); 0000 HLT (warm boot ends
// the run); 0005 JMP F000; F000 CALLN 81h, RET. Vector 81h -> 0000:0600 = OUT E0h, AL; RETI (native). The OUT is the
// BDOS: C = 2 prints E, C = 9 prints the $-terminated string at DE. 8080 SP (BP) = F000.
#include "v20e.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

struct Mem : v20e::Bus {
    std::vector<uint8_t> m = std::vector<uint8_t>(1 << 20, 0);
    v20e::Cpu *cpu = nullptr;
    uint8_t rd(uint32_t a) override { return m[a & 0xFFFFF]; }
    void wr(uint32_t a, uint8_t v) override { m[a & 0xFFFFF] = v; }
    uint8_t inp(uint16_t) override { return 0xFF; }
    void outp(uint16_t port, uint8_t) override {
        if (port != 0xE0) return;
        uint8_t fn = cpu->r[v20e::CW] & 0xFF;
        if (fn == 2) { putchar(cpu->r[v20e::DW] & 0xFF); fflush(stdout); }
        else if (fn == 9) {
            uint16_t p = cpu->r[v20e::DW];
            for (int i = 0; i < 65536; i++) {
                uint8_t c = rd(v20e::Cpu::phys(cpu->s[v20e::DS0], p++));
                if (c == '$') break;
                putchar(c);
            }
            fflush(stdout);
        }
    }
};

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: exer file.COM [max]\n"); return 2; }
    long long maxi = argc > 2 ? atoll(argv[2]) : 100000000000LL;
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror(argv[1]); return 1; }
    static uint8_t com[0xF000 - 0x100];
    size_t n = fread(com, 1, sizeof com, f);
    fclose(f);

    Mem mem; v20e::Cpu cpu; cpu.bus = &mem; mem.cpu = &cpu;
    const uint32_t B = 0x10000;
    memcpy(&mem.m[B + 0x100], com, n);
    mem.m[B + 0] = 0x76;
    mem.m[B + 5] = 0xC3; mem.m[B + 6] = 0x00; mem.m[B + 7] = 0xF0;
    const uint8_t bdos[] = {0xED, 0xED, 0x81, 0xC9};
    memcpy(&mem.m[B + 0xF000], bdos, sizeof bdos);
    mem.m[0x81 * 4 + 0] = 0x00; mem.m[0x81 * 4 + 1] = 0x06; mem.m[0x81 * 4 + 2] = 0; mem.m[0x81 * 4 + 3] = 0;
    const uint8_t handler[] = {0xE6, 0xE0, 0xCF};
    memcpy(&mem.m[0x600], handler, sizeof handler);

    // state after BRKEM 80h from a native boot: emulation mode, MD write enabled
    cpu.s[v20e::PS] = cpu.s[v20e::DS0] = cpu.s[v20e::DS1] = 0x1000;
    cpu.s[v20e::SS] = 0x0080; cpu.r[v20e::SP] = 0x0100;
    cpu.r[v20e::BP] = 0xF000;
    cpu.pc = 0x0100;
    cpu.psw = v20e::psw_norm(0x0000);
    cpu.we = true;
    long long i = 0;
    for (; i < maxi && !cpu.halted; i++) {
        if (!cpu.step()) { fprintf(stderr, "\nunsupported native opcode at %04X:%04X\n", cpu.s[v20e::PS], cpu.pc); return 1; }
    }
    printf("\n[exer] %s: %lld instructions, %s at %04X:%04X MD=%d\n", argv[1], i, cpu.halted ? "halted" : "stopped",
           cpu.s[v20e::PS], cpu.pc, cpu.md() ? 1 : 0);
    return cpu.halted ? 0 : 1;
}

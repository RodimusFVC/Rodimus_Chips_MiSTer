// Shared bus driver for the lockstep (oracle + t65sv) and solo (t65sv only) Verilator builds.
// Lockstep build: define LOCKSTEP; every output of both models is compared before and after each edge.
#pragma once
#include "verilated.h"
#include "covwrite.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#ifdef LOCKSTEP
#include "Vlockstep_top.h"
typedef Vlockstep_top Top;
#else
#include "Vsolo_top.h"
typedef Vsolo_top Top;
#endif

struct Bus {
  Top* t = nullptr;
  uint8_t mem[65536];
  uint64_t cycles = 0, mismatches = 0, comparisons = 0;
  bool armed = false;      // no compares before the first clock edge (t=0 init artifact of the oracle)
  bool fb_write = true;    // DI = DO on write cycles
  const char* ctx = "";
  // hooks for memory-mapped devices (C64 shim etc.)
  uint8_t (*rd_hook)(Bus&, uint16_t, bool&) = nullptr;   // return value, set handled=true to override RAM
  bool (*wr_hook)(Bus&, uint16_t, uint8_t) = nullptr;    // return true if consumed (RAM not written)
  void (*cyc_hook)(Bus&) = nullptr;                      // called once per clock before the edge

  Bus() { t = new Top; memset(mem, 0, sizeof mem); }
  ~Bus() { delete t; }

  uint16_t addr() const { return t->r_A & 0xFFFF; }
  bool sync() const { return t->r_Sync; }
  uint16_t pc() const { return (uint16_t)(t->r_Regs >> 48); }
  uint8_t  rA() const { return t->r_Regs & 0xFF; }
  uint8_t  rX() const { return (t->r_Regs >> 8) & 0xFF; }
  uint8_t  rY() const { return (t->r_Regs >> 16) & 0xFF; }
  uint8_t  rP() const { return (t->r_Regs >> 24) & 0xFF; }
  uint8_t  rS() const { return (t->r_Regs >> 32) & 0xFF; }

  void compare(const char* phase) {
#ifdef LOCKSTEP
    if (!armed) return;
    comparisons++;
    bool bad = false;
#define CMP(f) if (t->r_##f != t->d_##f) { if (mismatches < 20) printf("MISMATCH %s cyc=%llu %s: %-7s ref=%llx dut=%llx\n", ctx, (unsigned long long)cycles, phase, #f, (unsigned long long)t->r_##f, (unsigned long long)t->d_##f); bad = true; }
    CMP(R_W_n) CMP(Sync) CMP(EF) CMP(MF) CMP(XF) CMP(ML_n) CMP(VP_n) CMP(VDA) CMP(VPA) CMP(NMI_ack)
    CMP(A) CMP(DO) CMP(Regs) CMP(DEBUG)
#undef CMP
    if (bad) mismatches++;
#else
    (void)phase;
#endif
  }
  uint8_t read(uint16_t a) {
    bool h = false; uint8_t v = 0;
    if (rd_hook) v = rd_hook(*this, a, h);
    return h ? v : mem[a];
  }
  void settle(const char* phase) {
    t->eval();
    if (!t->r_R_W_n) t->DI = fb_write ? t->r_DO : (uint8_t)rand();
    else t->DI = read(addr());
    t->eval();
    compare(phase);
  }
  // one full clock; returns true if this cycle was an opcode fetch that the CPU accepted
  bool tick() {
    if (cyc_hook) cyc_hook(*this);
    settle("pre");
    bool wr = !t->r_R_W_n, en = t->Enable;
    uint16_t a = addr(); uint8_t d = t->r_DO;
    bool fetch = t->r_Sync && t->Rdy && en && t->Res_n;
    t->Clk = 1; t->eval();
    if (wr && en) { if (!(wr_hook && wr_hook(*this, a, d))) mem[a] = d; }
    compare("post");
    t->Clk = 0; t->eval();
    cycles++;
    return fetch;
  }
  void init_pins() {
    t->Mode = 0; t->Enable = 1; t->Rdy = 1; t->Abort_n = 1; t->IRQ_n = 1; t->NMI_n = 1; t->SO_n = 1;
    t->Clk = 0; t->Res_n = 1; t->DI = 0; t->eval();
  }
  void reset(int lowcycles = 3) {
    t->Res_n = 1; t->Clk = 0; t->eval();
    t->Res_n = 0; t->eval();
    for (int i = 0; i < lowcycles; i++) { tick(); armed = true; }
    t->Res_n = 1;
  }
  // loaders
  bool load_hex(const char* fn) {
    FILE* f = fopen(fn, "r"); if (!f) return false;
    char line[600];
    while (fgets(line, sizeof line, f)) {
      if (line[0] != ':') continue;
      unsigned n, a, ty; sscanf(line + 1, "%2x%4x%2x", &n, &a, &ty);
      if (ty != 0) continue;
      for (unsigned i = 0; i < n; i++) { unsigned b; sscanf(line + 9 + 2 * i, "%2x", &b); mem[(a + i) & 0xFFFF] = b; }
    }
    fclose(f); return true;
  }
  bool load_bin(const char* fn, uint32_t at, long skip = 0) {
    FILE* f = fopen(fn, "rb"); if (!f) return false;
    fseek(f, skip, SEEK_SET);
    int c; uint32_t a = at; while ((c = fgetc(f)) != EOF && a < 65536) mem[a++] = c;
    fclose(f); return true;
  }
};

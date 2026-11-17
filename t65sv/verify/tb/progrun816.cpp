// Runs a 6502 test program on t65sv816 (flat 16 MB RAM) from a real reset, until a stop address or a "jmp *" trap.
//   progrun816 --hex F [--start ADDR] [--stop ADDR] [--pass ADDR] [--check ADDR=VAL]... [--max CYCLES] [--stall SEED]
// --stall: random RDY-low and Enable-low cycles; the program must behave identically (same active-cycle count).
// The 65C816 comes out of reset in emulation mode, so 6502 programs run unchanged.
#include "Vt65sv816.h"
#include "verilated.h"
#include "covwrite.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static std::vector<uint8_t> mem(1 << 24, 0);

static bool load_hex(const char* fn) {
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

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  int start = -1, stop = -1, pass = -1;
  uint64_t maxc = 300000000ull;
  std::vector<std::pair<int,int>> checks;
  uint32_t stall = 0;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto nx = [&]() { return std::string(argv[++i]); };
    if (a == "--hex") { std::string f = nx(); if (!load_hex(f.c_str())) { printf("cannot load %s\n", f.c_str()); return 2; } }
    else if (a == "--start") start = strtoul(nx().c_str(), 0, 16);
    else if (a == "--stop") stop = strtoul(nx().c_str(), 0, 16);
    else if (a == "--pass") pass = strtoul(nx().c_str(), 0, 16);
    else if (a == "--max") maxc = strtoull(nx().c_str(), 0, 0);
    else if (a == "--stall") stall = strtoul(nx().c_str(), 0, 0);
    else if (a == "--check") { std::string s = nx(); size_t p = s.find('='); checks.push_back({(int)strtoul(s.substr(0, p).c_str(), 0, 16), (int)strtoul(s.substr(p + 1).c_str(), 0, 16)}); }
  }
  if (start >= 0) { mem[0xFFFC] = start & 0xFF; mem[0xFFFD] = start >> 8; }
  Vt65sv816* t = new Vt65sv816;
  t->Enable = 1; t->Rdy = 1; t->Abort_n = 1; t->IRQ_n = 1; t->NMI_n = 1; t->Clk = 0;
  t->Res_n = 0; t->eval();
  for (int i = 0; i < 2; i++) { t->Clk = 1; t->eval(); t->Clk = 0; t->eval(); }
  t->Res_n = 1; t->eval();
  uint64_t cyc = 0, instr = 0, stalls = 0; int last = -1, same = 0, end_pc = -1;
  uint32_t rng = stall;
  while (cyc < maxc) {
    if (stall) {
      rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
      t->Rdy = (rng % 7) != 0; t->Enable = ((rng >> 8) % 11) != 0;
    }
    bool active = t->Rdy && t->Enable;
    t->eval();
    uint32_t a = t->A & 0xFFFFFF;
    if (t->R_W_n) { t->DI = mem[a]; t->eval(); }
    a = t->A & 0xFFFFFF;
    if (t->Sync && active) {
      instr++;
      if (stop >= 0 && (int)a == stop) { end_pc = a; break; }
      if ((int)a == last) { if (++same >= 2) { end_pc = a; break; } } else same = 0;
      last = a;
    }
    if (!t->R_W_n) mem[a] = t->DO;
    t->Clk = 1; t->eval(); t->Clk = 0; t->eval();
    if (active) cyc++; else stalls++;
  }
  bool ok = end_pc >= 0 && (pass < 0 || end_pc == pass);
  for (auto& c : checks) if (mem[c.first] != c.second) { ok = false; printf("check $%04X = %02X (want %02X)\n", c.first, mem[c.first], c.second); }
  printf("%s end_pc=%06X cycles=%llu instructions=%llu E=%d", ok ? "PASS" : "FAIL", end_pc & 0xFFFFFF,
         (unsigned long long)cyc, (unsigned long long)instr, (int)t->E);
  if (stall) printf(" stall_cycles=%llu", (unsigned long long)stalls);
  printf("\n");
  COV_WRITE();
  return ok ? 0 : 1;
}

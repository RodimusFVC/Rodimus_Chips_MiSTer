// Runs a 6502 test program on the flat-RAM bus until a stop address or a "jmp *" trap.
//   progrun [--mode M] [--hex F]... [--bin F@ADDR]... [--start ADDR] [--stop ADDR] [--pass ADDR]
//           [--check ADDR=VAL]... [--max CYCLES]
#include "tbcommon.h"

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Bus b;
  int start = -1, stop = -1, pass = -1, mode = 0;
  uint64_t maxc = 200000000ull;
  std::vector<std::pair<int,int>> checks;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto nx = [&]() { return std::string(argv[++i]); };
    if (a == "--hex") { std::string f = nx(); if (!b.load_hex(f.c_str())) { printf("cannot load %s\n", f.c_str()); return 2; } }
    else if (a == "--bin") { std::string s = nx(); size_t p = s.find('@'); b.load_bin(s.substr(0, p).c_str(), strtoul(s.substr(p + 1).c_str(), 0, 16)); }
    else if (a == "--start") start = strtoul(nx().c_str(), 0, 16);
    else if (a == "--stop") stop = strtoul(nx().c_str(), 0, 16);
    else if (a == "--pass") pass = strtoul(nx().c_str(), 0, 16);
    else if (a == "--mode") mode = atoi(nx().c_str());
    else if (a == "--max") maxc = strtoull(nx().c_str(), 0, 0);
    else if (a == "--check") { std::string s = nx(); size_t p = s.find('='); checks.push_back({(int)strtoul(s.substr(0, p).c_str(), 0, 16), (int)strtoul(s.substr(p + 1).c_str(), 0, 16)}); }
  }
  if (start >= 0) { b.mem[0xFFFC] = start & 0xFF; b.mem[0xFFFD] = start >> 8; }
  b.init_pins();
  b.t->Mode = mode;
  b.reset();
  int last_fetch = -1, same = 0; uint64_t instr = 0;
  int end_pc = -1;
  while (b.cycles < maxc) {
    uint16_t a = b.addr();
    bool s = b.sync();
    if (b.tick()) {
      (void)s;
      instr++;
      if (stop >= 0 && a == stop) { end_pc = a; break; }
      if (a == last_fetch) { if (++same >= 2) { end_pc = a; break; } } else same = 0;
      last_fetch = a;
    }
    if (b.mismatches >= 20) break;
  }
  bool ok = end_pc >= 0 && (pass < 0 || end_pc == pass);
  for (auto& c : checks) if (b.mem[c.first] != c.second) { ok = false; printf("check $%04X = %02X (want %02X)\n", c.first, b.mem[c.first], c.second); }
  if (b.mismatches) ok = false;
  printf("%s end_pc=%04X cycles=%llu instructions=%llu", ok ? "PASS" : "FAIL", end_pc & 0xFFFF,
         (unsigned long long)b.cycles, (unsigned long long)instr);
#ifdef LOCKSTEP
  printf(" lockstep_comparisons=%llu mismatches=%llu", (unsigned long long)b.comparisons, (unsigned long long)b.mismatches);
#endif
  printf("\n");
  COV_WRITE();
  return ok ? 0 : 1;
}

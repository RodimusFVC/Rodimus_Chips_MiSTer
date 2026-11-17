// Mini-C64 runner: boots the real KERNAL, autostarts a PRG with RUN, reports the first write to $D7FF
// (VICE "debug cartridge": $00 = pass, $FF = fail) as the test result. CHROUT output is captured.
//   c64 <prg> [--max CPU-cycles] [--cia-new] [--trace]   (--trace: raster line every 1M cycles, PC histogram of the
//   last 200k cycles)
#include "Vc64_top.h"
#include "Vc64_top___024root.h"
#include "verilated.h"
#include "verilated_save.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>
#include <algorithm>

static Vc64_top* t;
static uint64_t ticks = 0, cpu_cycles = 0, mism = 0;

static void tick() {
  t->clk32 = 0; t->eval();
  t->clk32 = 1; t->eval();
  if (t->mismatch) mism++;
  ticks++;
}

static char petscii(uint8_t c) {
  if (c == 13) return '\n';
  if (c >= 0x41 && c <= 0x5a) return c + 0x20;
  if (c >= 0xc1 && c <= 0xda) return c - 0x80;
  if (c >= 0x20 && c < 0x7f) return c;
  return '.';
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  if (argc < 2) { fprintf(stderr, "usage: c64 <prg> [--max N] [--cia-new]\n"); return 2; }
  std::string prg = argv[1];
  uint64_t maxc = 400000000ull; bool cianew = false, trace = false;
  std::string save_boot, load_boot;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "--max")) maxc = strtoull(argv[++i], 0, 0);
    else if (!strcmp(argv[i], "--cia-new")) cianew = true;
    else if (!strcmp(argv[i], "--trace")) trace = true;
    else if (!strcmp(argv[i], "--save-boot")) save_boot = argv[++i];
    else if (!strcmp(argv[i], "--boot")) load_boot = argv[++i];
  }
  std::vector<uint8_t> img;
  { FILE* f = fopen(prg.c_str(), "rb"); if (!f) { printf("cannot open %s\n", prg.c_str()); return 2; }
    int c; while ((c = fgetc(f)) != EOF) img.push_back(c); fclose(f); }
  t = new Vc64_top;
  auto& ram = t->rootp->c64_top__DOT__ram;
  if (!load_boot.empty()) {
    VerilatedRestore is; is.open(load_boot.c_str()); is >> *t; is.close();
    if (t->cia_new != cianew) { printf("snapshot CIA type mismatch\n"); return 2; }
  } else {
    t->cia_new = cianew; t->reset_n = 0;
    for (int i = 0; i < 32 * 8; i++) tick();
    t->reset_n = 1;
  }

  enum { BOOT, RUNNING } st = BOOT;
  std::string out;
  std::map<uint16_t, uint32_t> pcs;
  int result = -1;
  uint64_t inject_at = 0;
  while (cpu_cycles < maxc) {
    tick();
    if (t->dbg_wr && result < 0) result = t->dbg_val;
    if (!t->cpu_edge) continue;
    cpu_cycles++;
    if (t->cpu_sync) {
      uint16_t pc = t->cpu_addr;
      if (st == BOOT && pc == 0xE5CD && !save_boot.empty()) {
        VerilatedSave os; os.open(save_boot.c_str()); os << *t; os.close();
        printf("saved boot snapshot after %llu cycles\n", (unsigned long long)cpu_cycles);
        return 0;
      }
      if (st == BOOT && pc == 0xE5CD) {
        // BASIC is waiting for input: load the PRG, set VARTAB and type RUN
        uint16_t la = img[0] | img[1] << 8;
        for (size_t i = 2; i < img.size(); i++) ram[(uint16_t)(la + i - 2)] = img[i];
        uint16_t end = la + img.size() - 2;
        ram[0x2d] = end & 0xff; ram[0x2e] = end >> 8;
        ram[0x2f] = end & 0xff; ram[0x30] = end >> 8;
        ram[0x31] = end & 0xff; ram[0x32] = end >> 8;
        ram[0xae] = end & 0xff; ram[0xaf] = end >> 8;
        const char* k = "RUN\r";
        for (int i = 0; i < 4; i++) ram[0x277 + i] = k[i];
        ram[0xc6] = 4;
        st = RUNNING; inject_at = cpu_cycles;
      } else if (st == RUNNING && pc == 0xFFD2) {
        out += petscii(t->cpu_regs & 0xff);
      }
    }
    if (trace && t->cpu_sync && cpu_cycles + 200000 > maxc) pcs[t->cpu_addr]++;
    if (trace && (cpu_cycles % 1000000) == 0) printf("cyc %llu rasterY %u\n", (unsigned long long)cpu_cycles, (unsigned)t->dbg_rasterY);
    if (result >= 0) break;
  }
  if (trace) {   // where the program spent its last 200k cycles
    std::vector<std::pair<uint32_t, uint16_t>> v;
    for (auto& kv : pcs) v.push_back({kv.second, kv.first});
    std::sort(v.rbegin(), v.rend());
    for (size_t i = 0; i < v.size() && i < 24; i++) printf("pc %04x x%u\n", v[i].second, v[i].first);
  }
  // a little more so the oracle/t65sv comparison covers the final cycles
  for (int i = 0; i < 32 * 4; i++) tick();
  for (auto& c : out) if (c == '\n') c = '|';
  const char* r = result == 0 ? "PASS" : result == 0xff ? "FAIL" : result >= 0 ? "D7FF?" : "TIMEOUT";
  printf("%s %s d7ff=%02x cpu_cycles=%llu boot=%llu mismatches=%llu out=\"%s\"\n", r, prg.c_str(),
         result & 0xff, (unsigned long long)cpu_cycles, (unsigned long long)inject_at,
         (unsigned long long)mism, out.c_str());
  delete t;
  return result == 0 ? 0 : 1;
}

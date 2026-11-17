// SingleStepTests 65x02 runner: every case, final state and every bus cycle.
//   sst [--mode M] [--maxfail N] [--quiet] <dir-with-XX.bin> [opcode-hex ...]
// CPU state is loaded by a preamble running from a separate scratch memory
// (LDX #s / TXS / LDA #p / PHA / LDA #a / LDX #x / LDY #y / PLP / JMP pc); the bus
// switches to the test RAM at the first opcode fetch of the test instruction.
// Recorded bus cycles: from that fetch up to (excluding) the next opcode fetch.
// Final registers are read after the next fetch's clock edge (T65 writes A/X/Y/P back then).
// P is compared with B (bit 4) and bit 5 masked: T65 holds both at 1, they only exist on the stack.
#include "tbcommon.h"
#include <map>
#include <set>

struct St { uint16_t pc; uint8_t s, a, x, y, p; std::vector<std::pair<uint16_t,uint8_t>> ram; };
struct Cy { uint16_t a; uint8_t v; uint8_t rd; };
struct Test { St i, f; std::vector<Cy> c; };

static bool rd_st(FILE* f, St& s) {
  uint8_t h[9]; if (fread(h, 1, 9, f) != 9) return false;
  s.pc = h[0] | h[1] << 8; s.s = h[2]; s.a = h[3]; s.x = h[4]; s.y = h[5]; s.p = h[6];
  int n = h[7] | h[8] << 8; s.ram.resize(n);
  for (int i = 0; i < n; i++) { uint8_t r[3]; if (fread(r, 1, 3, f) != 3) return false; s.ram[i] = {(uint16_t)(r[0] | r[1] << 8), r[2]}; }
  return true;
}

static uint8_t scratch[65536];
static bool in_test = false;
static uint8_t rd(Bus& b, uint16_t a, bool& h) { if (!in_test) { h = true; return scratch[a]; } return 0; }
static bool wr(Bus& b, uint16_t a, uint8_t v) { if (!in_test) { scratch[a] = v; return true; } return false; }

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  int mode = 0, maxfail_print = 3; bool quiet = false, allcyc = false;
  std::string dir; std::vector<int> ops;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--mode") mode = atoi(argv[++i]);
    else if (a == "--maxfail") maxfail_print = atoi(argv[++i]);
    else if (a == "--quiet") quiet = true;
    else if (a == "--allcycles") allcyc = true;
    else if (dir.empty()) dir = a;
    else ops.push_back(strtoul(a.c_str(), 0, 16));
  }
  if (ops.empty()) for (int i = 0; i < 256; i++) ops.push_back(i);
  Bus b; b.rd_hook = rd; b.wr_hook = wr;
  uint64_t total = 0, total_fail = 0;
  for (int op : ops) {
    char fn[512]; snprintf(fn, sizeof fn, "%s/%02x.bin", dir.c_str(), op);
    FILE* f = fopen(fn, "rb"); if (!f) { printf("op %02X: missing %s\n", op, fn); continue; }
    uint32_t n; if (fread(&n, 4, 1, f) != 1) { fclose(f); continue; }
    uint64_t fails = 0;
    std::map<std::string, uint64_t> kinds;   // failure category -> count
    std::string first_example;
    for (uint32_t ti = 0; ti < n; ti++) {
      Test t;
      if (!rd_st(f, t.i) || !rd_st(f, t.f)) break;
      uint8_t h[2]; if (fread(h, 1, 2, f) != 2) break;
      int nc = h[0] | h[1] << 8; t.c.resize(nc);
      for (int k = 0; k < nc; k++) { uint8_t r[4]; if (fread(r, 1, 4, f) != 4) break; t.c[k] = {(uint16_t)(r[0] | r[1] << 8), r[2], r[3]}; }
      // memory
      for (auto& r : t.i.ram) b.mem[r.first] = r.second;
      // preamble
      uint16_t p = 0x0200;
      auto e = [&](uint8_t v) { scratch[p++] = v; };
      e(0xA2); e(t.i.s); e(0x9A); e(0xA9); e(t.i.p); e(0x48); e(0xA9); e(t.i.a);
      e(0xA2); e(t.i.x); e(0xA0); e(t.i.y); e(0x28);
      uint16_t jmp_at = p; e(0x4C); e(t.i.pc & 0xFF); e(t.i.pc >> 8);
      scratch[0xFFFC] = 0x00; scratch[0xFFFD] = 0x02;
      in_test = false;
      b.init_pins(); b.t->Mode = mode; b.ctx = fn;
      b.reset();
      bool jmp_seen = false; int guard = 0;
      while (guard++ < 200) {
        b.t->eval();
        if (b.sync() && jmp_seen) break;
        bool fetch_jmp = b.sync() && b.addr() == jmp_at;
        b.tick();
        if (fetch_jmp) jmp_seen = true;
      }
      in_test = true;
      std::vector<Cy> got;
      int g2 = 0;
      do {
        b.settle("pre");
        got.push_back({b.addr(), (uint8_t)(b.t->r_R_W_n ? b.read(b.addr()) : b.t->r_DO), (uint8_t)b.t->r_R_W_n});
        b.tick();
        b.t->eval();
      } while (!b.sync() && ++g2 < 64);
      uint16_t fpc = b.addr();
      b.tick();   // next fetch: writeback of A/X/Y/P
      std::string why;
      char buf[200];
      if (got.size() != t.c.size()) { snprintf(buf, sizeof buf, "cycles %zu (sst %zu)", got.size(), t.c.size()); why = buf; }
      size_t m = std::min(got.size(), t.c.size());
      for (size_t k = 0; k < m && why.empty(); k++) {
        if (got[k].rd != t.c[k].rd) { snprintf(buf, sizeof buf, "cyc%zu rw %s@%04X (sst %s@%04X)", k, got[k].rd ? "R" : "W", got[k].a, t.c[k].rd ? "R" : "W", t.c[k].a); why = buf; }
        else if (got[k].a != t.c[k].a) { snprintf(buf, sizeof buf, "cyc%zu addr %04X (sst %04X)", k, got[k].a, t.c[k].a); why = buf; }
        else if (got[k].v != t.c[k].v) { snprintf(buf, sizeof buf, "cyc%zu %s data %02X (sst %02X)", k, got[k].rd ? "read" : "write", got[k].v, t.c[k].v); why = buf; }
      }
      std::string regs;
      if (fpc != t.f.pc) { snprintf(buf, sizeof buf, " PC=%04X(sst %04X)", fpc, t.f.pc); regs += buf; }
      if (b.rA() != t.f.a) { snprintf(buf, sizeof buf, " A=%02X(sst %02X)", b.rA(), t.f.a); regs += buf; }
      if (b.rX() != t.f.x) { snprintf(buf, sizeof buf, " X=%02X(sst %02X)", b.rX(), t.f.x); regs += buf; }
      if (b.rY() != t.f.y) { snprintf(buf, sizeof buf, " Y=%02X(sst %02X)", b.rY(), t.f.y); regs += buf; }
      if (b.rS() != t.f.s) { snprintf(buf, sizeof buf, " S=%02X(sst %02X)", b.rS(), t.f.s); regs += buf; }
      if ((b.rP() & 0xCF) != (t.f.p & 0xCF)) { snprintf(buf, sizeof buf, " P=%02X(sst %02X)", b.rP(), t.f.p); regs += buf; }
      for (auto& r : t.f.ram) if (b.mem[r.first] != r.second) { snprintf(buf, sizeof buf, " M[%04X]=%02X(sst %02X)", r.first, b.mem[r.first], r.second); regs += buf; break; }
      bool fail = !why.empty() || !regs.empty();
      if (fail) {
        fails++;
        // category: bus kind + which registers differ (without values)
        std::string cat = why.empty() ? "" : why.substr(0, why.find(' ') == std::string::npos ? why.size() : why.find(' '));
        if (!why.empty()) { size_t sp = why.find(' '); std::string rest = why.substr(sp + 1); cat += " " + rest.substr(0, rest.find(' ')); }
        if (!regs.empty()) {
          std::string rc; size_t q = 0;
          while ((q = regs.find('=', q)) != std::string::npos) {   // " NAME=VAL(sst VAL)" -> " NAME"
            size_t st = regs.rfind(' ', q); rc += regs.substr(st, q - st); q = regs.find(')', q);
          }
          cat += (cat.empty() ? "" : " +") + std::string("final") + rc;
        }
        kinds[cat]++;
        if (first_example.empty()) {
          first_example = std::string("\"") + std::to_string(ti) + "\" " + why + regs;
        }
        if (!quiet && fails <= (uint64_t)maxfail_print) printf("  op %02X test %u: %s%s\n", op, ti, why.c_str(), regs.c_str());
        if (allcyc && fails <= (uint64_t)maxfail_print)
          for (size_t k = 0; k < std::max(got.size(), t.c.size()); k++)
            printf("    cyc%zu  core %s%04X=%02X   sst %s%04X=%02X%s\n", k,
                   k < got.size() ? (got[k].rd ? "R " : "W ") : "  ", k < got.size() ? got[k].a : 0, k < got.size() ? got[k].v : 0,
                   k < t.c.size() ? (t.c[k].rd ? "R " : "W ") : "  ", k < t.c.size() ? t.c[k].a : 0, k < t.c.size() ? t.c[k].v : 0,
                   (k < got.size() && k < t.c.size() && (got[k].a != t.c[k].a || got[k].v != t.c[k].v || got[k].rd != t.c[k].rd)) ? "  <--" : "");
      }
      for (auto& r : t.i.ram) b.mem[r.first] = 0;
      for (auto& r : t.f.ram) b.mem[r.first] = 0;
      for (auto& c : got) b.mem[c.a] = 0;
      total++;
      if (b.mismatches) break;
    }
    fclose(f);
    total_fail += fails;
    printf("op %02X: %s %llu/%u fail", op, fails ? "FAIL" : "ok  ", (unsigned long long)fails, n);
    if (fails) { printf(" |"); for (auto& k : kinds) printf(" [%s]x%llu", k.first.c_str(), (unsigned long long)k.second); printf(" | e.g. %s", first_example.c_str()); }
    printf("\n");
    fflush(stdout);
    if (b.mismatches) { printf("LOCKSTEP MISMATCH, stopping\n"); break; }
  }
  printf("TOTAL tests=%llu fail=%llu", (unsigned long long)total, (unsigned long long)total_fail);
#ifdef LOCKSTEP
  printf(" lockstep_cycles=%llu comparisons=%llu mismatches=%llu", (unsigned long long)b.cycles, (unsigned long long)b.comparisons, (unsigned long long)b.mismatches);
#endif
  printf("\n");
  COV_WRITE();
  return 0;
}

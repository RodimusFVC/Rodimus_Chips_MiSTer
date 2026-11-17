// SingleStepTests 65816 runner: every case, final state and every bus cycle including VDA/VPA/VPB/RWB/E/M/X/MLB.
//   sst816 [--maxfail N] [--quiet] [--verbose] [--limit N] <dir-with-XX.{e,n}.bin> [e|n] [opcode-hex ...]
// The CPU state is loaded through Verilator's public signals (built with --public-flat-rw) with the sequencer
// parked at an instruction boundary; the first recorded cycle is the opcode fetch.
// Conventions (see REPORT.md):
//  * emulation-mode cases give S with an arbitrary high byte; S is loaded as 01:SL (the 65816 forces SH = 01).
//  * WAI / STP cases end with a cycle "000000, no value, all flags off": the test generator's halt marker, not a
//    bus cycle. It is not compared (t65sv816 is waiting / stopped there).
#ifdef VIA_T65
// integrated path: t65sv_T65 #(.C816(1)) -> t65sv (generate g_c816) -> t65sv816
#include "Vt65sv_T65.h"
#include "Vt65sv_T65___024root.h"
typedef Vt65sv_T65 Top;
#define R(sig) top->rootp->t65sv_T65__DOT__u_core__DOT__g_c816__DOT__u_816__DOT__##sig
#define EPIN EF
#else
#include "Vt65sv816.h"
#include "Vt65sv816___024root.h"
typedef Vt65sv816 Top;
#define R(sig) top->rootp->t65sv816__DOT__##sig
#define EPIN E
#endif
#include "verilated.h"
#include "covwrite.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <map>

struct St { uint16_t pc, s, a, x, y, d; uint8_t p, dbr, pbr, e; std::vector<std::pair<uint32_t,uint8_t>> ram; };
struct Cy { uint32_t a; uint8_t v, valid, f; };

static bool rd_st(FILE* f, St& s) {
  uint8_t h[20]; if (fread(h, 1, 20, f) != 20) return false;
  s.pc = h[0] | h[1] << 8; s.s = h[2] | h[3] << 8; s.p = h[4]; s.a = h[5] | h[6] << 8; s.x = h[7] | h[8] << 8;
  s.y = h[9] | h[10] << 8; s.dbr = h[11]; s.d = h[12] | h[13] << 8; s.pbr = h[14]; s.e = h[15];
  uint32_t n = h[16] | h[17] << 8 | h[18] << 16 | (uint32_t)h[19] << 24; s.ram.resize(n);
  for (uint32_t i = 0; i < n; i++) {
    uint8_t r[5]; if (fread(r, 1, 5, f) != 5) return false;
    s.ram[i] = {(uint32_t)(r[0] | r[1] << 8 | r[2] << 16 | (uint32_t)r[3] << 24), r[4]};
  }
  return true;
}

static std::vector<uint8_t> mem(1 << 24, 0);
static Top* top;

static void tick() {
  top->Clk = 1; top->eval();
  top->Clk = 0; top->eval();
}

static std::string fl(uint8_t f) {
  std::string s; const char* c = "dpvremxl";
  for (int k = 0; k < 8; k++) s += (f & (0x80 >> k)) ? c[k] : (k == 3 ? 'w' : '-');
  return s;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  int maxfail_print = 2; bool quiet = false, verbose = false; uint32_t limit = 0;
  std::string dir; std::vector<std::string> modes; std::vector<int> ops;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--maxfail") maxfail_print = atoi(argv[++i]);
    else if (a == "--limit") limit = strtoul(argv[++i], 0, 0);
    else if (a == "--quiet") quiet = true;
    else if (a == "--verbose") verbose = true;
    else if (dir.empty()) dir = a;
    else if (a == "e" || a == "n") modes.push_back(a);
    else ops.push_back(strtoul(a.c_str(), 0, 16));
  }
  if (modes.empty()) modes = {"e", "n"};
  if (ops.empty()) for (int i = 0; i < 256; i++) ops.push_back(i);
  top = new Top;
#ifdef VIA_T65
  top->Mode = 0; top->SO_n = 1; top->BCD_en = 1;
#endif
  top->Enable = 1; top->Rdy = 1; top->Abort_n = 1; top->IRQ_n = 1; top->NMI_n = 1; top->DI = 0;
  top->Clk = 0; top->Res_n = 0; top->eval(); top->Res_n = 1; top->eval();
  uint64_t total = 0, total_fail = 0;
  for (auto& m : modes) {
    for (int op : ops) {
      char fn[512]; snprintf(fn, sizeof fn, "%s/%02x.%s.bin", dir.c_str(), op, m.c_str());
      FILE* f = fopen(fn, "rb"); if (!f) { printf("op %02x.%s: missing %s\n", op, m.c_str(), fn); continue; }
      uint32_t n; if (fread(&n, 4, 1, f) != 1) { fclose(f); continue; }
      if (limit && n > limit) n = limit;   // --limit: first N cases of each file
      uint64_t fails = 0; int printed = 0;
      std::map<std::string, uint64_t> kinds;
      for (uint32_t ti = 0; ti < n; ti++) {
        St si, sf; std::vector<Cy> cy;
        if (!rd_st(f, si) || !rd_st(f, sf)) break;
        uint8_t h[2]; if (fread(h, 1, 2, f) != 2) break;
        int nc = h[0] | h[1] << 8; cy.resize(nc);
        for (int k = 0; k < nc; k++) {
          uint8_t r[7]; if (fread(r, 1, 7, f) != 7) break;
          cy[k] = {(uint32_t)(r[0] | r[1] << 8 | r[2] << 16 | (uint32_t)r[3] << 24), r[4], r[5], r[6]};
        }
        if (nc && cy[nc - 1].f == 0) nc--;   // WAI / STP halt marker
        for (auto& r : si.ram) mem[r.first & 0xFFFFFF] = r.second;
        // load state, park at an instruction boundary
        R(C) = si.a; R(X) = si.x; R(Y) = si.y; R(D) = si.d; R(PC) = si.pc; R(DBR) = si.dbr; R(PBR) = si.pbr;
        R(S) = si.e ? (0x0100 | (si.s & 0xFF)) : si.s;
        R(P) = si.e ? (si.p | 0x30) : si.p; R(Ef) = si.e;
        R(IR) = 0xEA; R(K) = 0; R(INTR) = 0; R(res_pend) = 0; R(abt_pend) = 0; R(nmi_pend) = 0; R(nmi_d) = 1;
        top->eval();
        std::string why; std::vector<uint32_t> written;
        for (int k = 0; k < nc; k++) {
          uint32_t a = top->A & 0xFFFFFF;
          bool rd = top->R_W_n;
          if (rd) top->DI = mem[a];
          top->eval();
          a = top->A & 0xFFFFFF; rd = top->R_W_n;
          uint8_t gf = (top->VDA << 7) | (top->VPA << 6) | ((!top->VP_n) << 5) | (rd << 4) | (top->EPIN << 3) |
                       (top->MF << 2) | (top->XF << 1) | (!top->ML_n);
          const Cy& c = cy[k];
          bool bad = (a != c.a) || (gf != c.f) || (!rd && c.valid && top->DO != c.v);
          if (bad && why.empty()) {
            char b[256];
            snprintf(b, sizeof b, "cyc%d %06x %s%s (sst %06x %s%s)", k, a, rd ? "" : "W", fl(gf).c_str(), c.a,
                     (c.f & 0x10) ? "" : "W", fl(c.f).c_str());
            why = b;
            if (!rd && top->DO != c.v) { snprintf(b, sizeof b, " DO=%02x(sst %02x)", top->DO, c.v); why += b; }
          }
          if (!rd) { mem[a] = top->DO; written.push_back(a); }
          tick();
        }
        // final state
        std::string fw;
        char b[128];
        auto chk = [&](const char* nm, unsigned got, unsigned exp) {
          if (got != exp) { snprintf(b, sizeof b, " %s=%x(sst %x)", nm, got, exp); fw += b; }
        };
        chk("pc", R(PC), sf.pc); chk("s", R(S), sf.s); chk("p", R(P), sf.p); chk("a", R(C), sf.a);
        chk("x", R(X), sf.x); chk("y", R(Y), sf.y); chk("dbr", R(DBR), sf.dbr); chk("d", R(D), sf.d);
        chk("pbr", R(PBR), sf.pbr); chk("e", R(Ef), sf.e);
        for (auto& r : sf.ram) if (mem[r.first & 0xFFFFFF] != r.second) {
          snprintf(b, sizeof b, " mem[%06x]=%02x(sst %02x)", r.first, mem[r.first & 0xFFFFFF], r.second); fw += b; break;
        }
        if (!why.empty() || !fw.empty()) {
          fails++;
          std::string key = why.empty() ? std::string("final") : why.substr(0, why.find(' '));
          if (!fw.empty()) key += "+final";
          kinds[key]++;
          if (printed < maxfail_print && !quiet) {
            printed++;
            printf("  FAIL %02x.%s #%u pc=%02x:%04x s=%04x p=%02x e=%d a=%04x x=%04x y=%04x d=%04x dbr=%02x: %s%s\n",
                   op, m.c_str(), ti, si.pbr, si.pc, si.s, si.p, si.e, si.a, si.x, si.y, si.d, si.dbr,
                   why.c_str(), fw.c_str());
            if (verbose) for (int k = 0; k < (int)cy.size(); k++)
              printf("     sst %06x %02x %s\n", cy[k].a, cy[k].v, fl(cy[k].f).c_str());
          }
        }
        for (auto& r : si.ram) mem[r.first & 0xFFFFFF] = 0;
        for (auto a : written) mem[a] = 0;
        total++;
      }
      fclose(f);
      total_fail += fails;
      printf("op %02x.%s: %s %6llu/%u pass", op, m.c_str(), fails ? "FAIL" : "ok  ", (unsigned long long)(n - fails), n);
      if (fails) { printf(" |"); for (auto& kv : kinds) printf(" [%s]x%llu", kv.first.c_str(), (unsigned long long)kv.second); }
      printf("\n");
      fflush(stdout);
    }
  }
  printf("TOTAL tests=%llu pass=%llu fail=%llu\n", (unsigned long long)total, (unsigned long long)(total - total_fail),
         (unsigned long long)total_fail);
  COV_WRITE();
  return total_fail ? 1 : 0;
}

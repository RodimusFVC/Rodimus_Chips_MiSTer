// Lockstep driver: reference model (left, "r") vs t48sv (right, "d").
// Every output and every probe is compared after every clock edge; data RAM is
// compared at every instruction boundary.
//
// usage: Vlockstep [--runs N] [--cycles N] [--seed S] [--prog random|struct|file:<hex>]
//                  [--sweep <class>] [--quiet] [--trace]
#include "Vlockstep.h"
#include "Vlockstep__Dpi.h"
#include "verilated.h"
#include "svdpi.h"
#include "cfg.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <random>
#include <string>
#include <vector>
#include <memory>

static std::mt19937_64 g_rng;
static uint32_t U(uint32_t n) { return n ? (uint32_t)(g_rng() % n) : 0; }
static bool P(double p) { return (double)(g_rng() >> 11) * (1.0 / 9007199254740992.0) < p; }

struct Mode {
  int xen;          // 0 always, 1 random p, 2 periodic, 3 bursts
  double xen_p;
  int xen_per;
  int pmem_reg;     // program data: 1 registered (BRAM), 0 combinational
  double int_p, t0_p, t1_p, port_p, noise_p, reset_p, host_p;
  int ea;           // 0 low, 1 high, 2 switching
  int int_mode;     // 0 random toggles, 1 long low, 2 off
};

struct Stats {
  uint64_t cycles = 0, runs = 0, mismatches = 0, instrs = 0, ints = 0, resets = 0;
  uint64_t tovf = 0, cnt_inc = 0, movx = 0, xen_gaps = 0, host_rd = 0, host_wr = 0, ram_checks = 0;
  uint64_t opc[256] = {0};
};
static Stats S;

static std::vector<uint8_t> rom(4096), xmem(256);
static bool g_quiet = false, g_trace = false, g_probes = true, g_noint = false;
static std::string g_prog = "random";

// ---------------------------------------------------------------- programs
static void prog_random() { for (auto &b : rom) b = (uint8_t)U(256); }

static void prog_struct() {
  // random code with vectors in place: 0 reset, 3 external INT, 7 timer INT
  prog_random();
  int span = 256 << U(5);  // keep execution in the first 256..4K bytes
  for (int a = 0; a < 4096; a++) {
    uint8_t op = rom[a];
    // long jumps / calls stay inside span
    if ((op & 0x0F) == 0x04 && a + 1 < 4096) {
      int t = (int)U(span);
      rom[a] = (uint8_t)((op & 0x10) | ((t >> 3) & 0xE0) | 0x04);
      rom[a + 1] = (uint8_t)t;
    }
  }
  rom[0] = 0x04; rom[1] = 0x09;                // JMP 009
  rom[3] = 0x27 + 0x0E * U(2); rom[4] = 0x93;  // CLR/CPL... RETR
  rom[5] = 0x00; rom[6] = 0x00;
  rom[7] = 0x17; rom[8] = 0x93;                // INC A, RETR
  int a = 9;
  static const uint8_t setup[] = {0x05, 0x25, 0x55, 0x45, 0xC5, 0xD5, 0xE5, 0xF5, 0x75};
  for (int i = 0; i < 6; i++) rom[a++] = setup[U(sizeof setup)];
  for (int i = 0; i < 8; i++) {                // sprinkle RET/RETR to keep the stack busy
    int r = 16 + (int)U(span - 16);
    rom[r] = P(0.5) ? 0x83 : 0x93;
  }
}

static bool prog_file(const std::string &f) {
  FILE *fp = fopen(f.c_str(), "r");
  if (!fp) { fprintf(stderr, "cannot open %s\n", f.c_str()); return false; }
  std::fill(rom.begin(), rom.end(), 0);
  unsigned v; int a = 0;
  while (a < 4096 && fscanf(fp, "%x", &v) == 1) rom[a++] = (uint8_t)v;
  fclose(fp);
  return true;
}

static void write_rom_files() {
  for (int aw = 10; aw <= 12; aw++) {
    char n[32];
    snprintf(n, sizeof n, "rom%d.hex", aw);
    FILE *fp = fopen(n, "w");
    for (int a = 0; a < (1 << aw); a++) fprintf(fp, "%02x\n", rom[a]);
    fclose(fp);
  }
}

// ---------------------------------------------------------------- compare
static Vlockstep *T;
static uint64_t g_cyc;
static int g_fail;

#define CMP_OUT(n, w) \
  if (T->r_##n != T->d_##n) { \
    if (g_fail++ < 8) printf("MISMATCH %s cyc %llu %s out %-14s ref %0*llx t48sv %0*llx\n", CFG_NAME, \
      (unsigned long long)g_cyc, ph, #n, (w + 3) / 4, (unsigned long long)T->r_##n, (w + 3) / 4, \
      (unsigned long long)T->d_##n); }
#define CMP_PRB(n, w) \
  if (T->pr_##n != T->pd_##n) { \
    if (g_fail++ < 8) printf("MISMATCH %s cyc %llu %s prb %-14s ref %0*llx t48sv %0*llx\n", CFG_NAME, \
      (unsigned long long)g_cyc, ph, #n, (w + 3) / 4, (unsigned long long)T->pr_##n, (w + 3) / 4, \
      (unsigned long long)T->pd_##n); }

static void compare(const char *ph) {
  FOREACH_OUTPUT(CMP_OUT)
  if (g_probes) { FOREACH_PROBE(CMP_PRB) }
}

static void compare_ram() {
  if (!g_probes) return;
  S.ram_checks++;
  for (int i = 0; i < RAM_SIZE; i++) {
    int r = ram_peek(0, i), d = ram_peek(1, i);
    if (r != d) {
      if (g_fail++ < 8)
        printf("MISMATCH %s cyc %llu RAM[%02x] ref %02x t48sv %02x\n", CFG_NAME,
               (unsigned long long)g_cyc, i, r, d);
      return;
    }
  }
}

#define TR_OUT(n, w) printf(" %s=%llx", #n, (unsigned long long)T->r_##n);
#define TR_PRB(n, w) printf(" %s=%llx", #n, (unsigned long long)T->pr_##n);

// ---------------------------------------------------------------- one run
struct Sweep { int cls; int k; };

static int run(uint64_t ncyc, const Mode &m, const Sweep *sw) {
  auto ctx = std::make_unique<VerilatedContext>();
  T = new Vlockstep(ctx.get());
  svSetScope(svGetScopeFromName("TOP.lockstep"));
  g_fail = 0;
  int reset_left = sw ? 20 : 4 + (int)U(40);
  int int_n = 1, t0 = 0, t1 = 0, xen_cnt = 0, burst = 0;
  uint8_t pmem_q = 0, addr_lo = 0, addr_hi = 0, db_hold = 0, p1 = 0xFF, p2 = 0xFF, p0 = 0xFF;
  uint8_t an0 = (uint8_t)U(256), an1 = (uint8_t)U(256);
  int ea = m.ea == 1;
  int host_state = 0, host_len = 0, host_rd = 0, host_a0 = 0;
  uint8_t host_db = 0;
  int wb_wait = 0;
  int prev_mstate = -1, prev_mcyc = 0, prev_scyc = 0, prev_istate = 0, prev_tcnt = 0;
  int prev_ale = 0, prev_rd = 1, prev_wr = 1;
  (void)prev_tcnt; (void)prev_rd; (void)host_rd; (void)wb_wait; (void)an0; (void)an1;
  (void)p0; (void)host_db; (void)host_a0; (void)host_len; (void)host_state;

  for (g_cyc = 0; g_cyc < ncyc && !g_fail; g_cyc++) {
    // ---------------- negative edge: drive inputs
    T->clk = 0;
    int rst = reset_left > 0;
    if (reset_left > 0) reset_left--;
    else if (!sw && P(m.reset_p)) { reset_left = 1 + (int)U(30); rst = 1; S.resets++; }
    int xen;
    switch (m.xen) {
      case 0: xen = 1; break;
      case 1: xen = P(m.xen_p); break;
      case 2: xen = (++xen_cnt % m.xen_per) == 0; break;
      default:
        if (burst <= 0) burst = (int)U(64) - 32;
        xen = burst > 0; burst += burst > 0 ? -1 : 1;
        break;
    }
    if (!xen) S.xen_gaps++;
#ifdef HAS_IN_xtal_en_i
    T->xtal_en_i = xen;
#endif
#ifdef HAS_IN_reset_n_i
    T->reset_n_i = !rst;
#endif
#ifdef HAS_IN_reset_i
#ifdef RESET_ACTIVE_HIGH
    T->reset_i = rst;
#else
    T->reset_i = !rst;
#endif
#endif
    if (sw) {
      // directed sweep: events placed at clock k after reset release (60 clocks)
      //   INT low for 40..79 clocks, T1 falling edge (counter preloaded 0xFF -> overflow),
      //   T1 rising again 20 clocks later (cls >= 2), T0 toggles at k+7
      uint64_t k = 60 + sw->k;
      int_n = !(g_cyc >= k && g_cyc < k + 40 + 13 * (sw->cls & 3));
      t1 = !(g_cyc >= k) || (sw->cls >= 2 && g_cyc >= k + 20);
      t0 = (g_cyc >= k + 7);
    } else {
      if (m.int_mode == 0 && P(m.int_p)) int_n ^= 1;
      if (m.int_mode == 1) int_n = !(P(m.int_p * 4) ? 1 : !int_n);
      if (m.int_mode == 2) int_n = 1;
      if (P(m.t0_p)) t0 ^= 1;
      if (P(m.t1_p)) t1 ^= 1;
    }
#ifdef HAS_IN_int_n_i
    T->int_n_i = int_n;
#endif
#ifdef HAS_IN_t0_i
    T->t0_i = t0;
#endif
#ifdef HAS_IN_t1_i
    T->t1_i = t1;
#endif
    if (P(m.port_p)) p1 = (uint8_t)U(256);
    if (P(m.port_p)) p2 = (uint8_t)U(256);
    if (P(m.port_p)) p0 = (uint8_t)U(256);
#ifdef HAS_IN_p1_i
    T->p1_i = p1;
#endif
#ifdef HAS_IN_p2_i
#ifdef KIND_T21
    T->p2_i = p2 & 0xF;
#else
    T->p2_i = p2;
#endif
#endif
#ifdef HAS_IN_p0_i
    T->p0_i = p0;
#endif
#ifdef HAS_IN_pmem_data_i
    {
      uint16_t a = T->r_pmem_addr_o & 0xFFF;
      T->pmem_data_i = m.pmem_reg ? pmem_q : rom[a];
    }
#endif
#ifdef HAS_IN_ea_i
    if (m.ea == 2 && P(0.0005)) ea ^= 1;
    T->ea_i = ea;
#endif
#if defined(KIND_CORE48) && defined(HAS_IN_db_i)
    {
      uint8_t v = db_hold;
      if (P(m.noise_p)) v = (uint8_t)U(256);
#ifdef HAS_OUT_psen_n_o
      if (!T->r_psen_n_o) v = rom[((addr_hi & 0xF) << 8) | addr_lo];
#endif
#ifdef HAS_OUT_rd_n_o
      if (!T->r_rd_n_o) v = xmem[addr_lo];
#endif
      db_hold = v;
      T->db_i = v;
    }
#endif
#ifdef KIND_UPI
    {
      // host: idle -> (cs low, rd or wr low for n clocks) -> release
      if (sw) {
        uint64_t k = 60 + sw->k;
        bool w = g_cyc >= k && g_cyc < k + 6, r = g_cyc >= k + 60 && g_cyc < k + 66;
        host_state = (w || r) ? 1 : 0; host_rd = r; host_a0 = sw->cls & 1;
        host_db = (uint8_t)(0x5A + sw->cls); host_len = 9;
      } else if (host_state == 0 && P(m.host_p)) {
        host_state = 1; host_len = 1 + (int)U(12); host_rd = P(0.5); host_a0 = P(0.5);
        host_db = (uint8_t)U(256);
        if (host_rd) S.host_rd++; else S.host_wr++;
      } else if (host_state == 1 && --host_len <= 0) {
        host_state = 2; host_len = (int)U(6);
      } else if (host_state == 2 && --host_len <= 0) {
        host_state = 0;
      }
      int chaos = P(m.noise_p);
      T->cs_n_i = chaos ? P(0.5) : !(host_state == 1 || (host_state == 2 && host_len > 2));
      T->rd_n_i = chaos ? P(0.5) : !(host_state == 1 && host_rd);
      T->wr_n_i = chaos ? P(0.5) : !(host_state == 1 && !host_rd);
      T->a0_i = chaos ? P(0.5) : host_a0;
      T->db_i = chaos ? (uint8_t)U(256) : host_db;
    }
#endif
#ifdef HAS_IN_an0_i
    if (P(0.001)) an0 = (uint8_t)U(256);
    if (P(0.001)) an1 = (uint8_t)U(256);
    T->an0_i = an0;
    T->an1_i = an1;
#endif
#ifdef HAS_IN_adc_comp_i
    T->adc_comp_i = P(0.5);
#endif
#ifdef HAS_IN_wb_ack_i
    T->wb_ack_i = T->r_wb_cyc_o && P(0.3);
    T->wb_dat_i = (uint8_t)U(256);
#endif
    T->eval();
    compare("neg");

    // ---------------- positive edge
    T->clk = 1;
    T->eval();
    compare("pos");
    S.cycles++;

    // external models sample the outputs
#ifdef HAS_OUT_pmem_addr_o
    pmem_q = rom[T->r_pmem_addr_o & 0xFFF];
#endif
#ifdef HAS_OUT_ale_o
    if (T->r_ale_o) {
#ifdef HAS_OUT_db_o
      addr_lo = T->r_db_o;
#endif
#ifdef HAS_OUT_p2_o
      addr_hi = T->r_p2_o;
#endif
    }
    prev_ale = T->r_ale_o;
#endif
#if defined(HAS_OUT_wr_n_o) && defined(HAS_OUT_db_o) && defined(KIND_CORE48)
    if (!T->r_wr_n_o) xmem[addr_lo] = T->r_db_o;
    if (!T->r_wr_n_o && prev_wr) S.movx++;
    prev_wr = T->r_wr_n_o;
#endif
    // instruction boundary: M5 -> M1 at the end of the last cycle
    int ms = T->pd_mstate;
    if (prev_mstate == 4 && ms == 0 && (!prev_mcyc || prev_scyc)) {
      S.instrs++;
      if (!T->dinj_o) S.opc[T->pd_opc]++;
      compare_ram();
    }
    if (prev_istate == 1 && T->pd_istate == 2) S.ints++;
    prev_istate = T->pd_istate;
#ifdef HAS_PRB_tovq
    if (T->pd_tovq) S.tovf++;
    if (T->pd_tsel == 2 && T->pd_tcnt != prev_tcnt) S.cnt_inc++;
    prev_tcnt = T->pd_tcnt;
#endif
    prev_mstate = ms; prev_mcyc = T->pd_mcyc; prev_scyc = T->pd_scyc;
    if (g_trace) {
      printf("T %llu", (unsigned long long)g_cyc);
      FOREACH_OUTPUT(TR_OUT)
      FOREACH_PROBE(TR_PRB)
      printf("\n");
    }
  }
  (void)prev_ale;
  T->final();
  delete T;
  S.runs++;
  if (g_fail) S.mismatches++;
  return g_fail;
}

static Mode random_mode() {
  Mode m;
  m.xen = (int)U(4);
  m.xen_p = 0.3 + 0.7 * (U(100) / 100.0);
  m.xen_per = 1 + (int)U(8);
  m.pmem_reg = P(0.8);
  m.int_p = P(0.3) ? 0.0005 : 0.02;
  m.int_mode = (int)U(3);
  m.t0_p = P(0.5) ? 0.001 : 0.05;
  m.t1_p = P(0.5) ? 0.002 : 0.1;
  m.port_p = 0.02;
  m.noise_p = P(0.5) ? 0.0 : 0.05;
  m.reset_p = P(0.5) ? 0.0 : 0.0002;
  m.ea = P(0.7) ? 0 : (int)U(3);
  m.host_p = P(0.5) ? 0.01 : 0.1;
#if !defined(HAS_IN_pmem_data_i) && !defined(ROM_AW)
  m.ea = P(0.9) ? 1 : 2;   // no program memory inside: run from the BUS
#endif
  if (g_noint) m.int_mode = 2;
  return m;
}

int main(int argc, char **argv) {
  uint64_t runs = 20, cycles = 200000, seed = 1;
  std::string sweep;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--runs") runs = strtoull(argv[++i], 0, 0);
    else if (a == "--cycles") cycles = strtoull(argv[++i], 0, 0);
    else if (a == "--seed") seed = strtoull(argv[++i], 0, 0);
    else if (a == "--prog") g_prog = argv[++i];
    else if (a == "--sweep") sweep = argv[++i];
    else if (a == "--quiet") g_quiet = true;
    else if (a == "--trace") g_trace = true;
    else if (a == "--pins-only") g_probes = false;
    else if (a == "--no-int") g_noint = true;
  }
  g_rng.seed(seed);
  uint64_t sweeps = 0;
  if (!sweep.empty()) {
    // directed timing sweep: program file, one INT / T1 / T0 event moved through every clock
    if (!prog_file(sweep)) return 2;
    write_rom_files();
    Mode m = random_mode();
    m.xen = 0; m.pmem_reg = 1; m.ea = 0; m.noise_p = 0; m.reset_p = 0; m.port_p = 0.01;
#if !defined(HAS_IN_pmem_data_i) && !defined(ROM_AW)
    m.ea = 1;   // no program memory inside: fetch the sweep program over the BUS
#endif
    for (int cls = 0; cls < 4; cls++)
      for (int k = 0; k < (int)runs; k++) {
        Sweep sw{cls, k};
        m.xen = cls == 3 ? 2 : 0;   // cls 3: XTAL enable every 2nd clock
        m.xen_per = 2;
        run(cycles, m, &sw);
        sweeps++;
      }
  } else {
    for (uint64_t r = 0; r < runs; r++) {
      if (g_prog == "random") prog_random();
      else if (g_prog == "struct") prog_struct();
      else if (g_prog.rfind("file:", 0) == 0) { if (!prog_file(g_prog.substr(5))) return 2; }
      else if (g_prog == "mixed") { if (r & 1) prog_struct(); else prog_random(); }
      for (auto &b : xmem) b = (uint8_t)U(256);
      write_rom_files();
      Mode m = random_mode();
      run(cycles, m, nullptr);
    }
  }
  int covered = 0;
  for (int i = 0; i < 256; i++) covered += S.opc[i] != 0;
  printf("RESULT cfg=%s runs=%llu sweeps=%llu cycles=%llu mismatching_runs=%llu instrs=%llu "
         "opcodes=%d ints=%llu resets=%llu tovf=%llu cnt_inc=%llu movx=%llu xen_gaps=%llu "
         "host_rd=%llu host_wr=%llu ram_checks=%llu\n",
         CFG_NAME, (unsigned long long)S.runs, (unsigned long long)sweeps,
         (unsigned long long)S.cycles, (unsigned long long)S.mismatches,
         (unsigned long long)S.instrs, covered, (unsigned long long)S.ints,
         (unsigned long long)S.resets, (unsigned long long)S.tovf, (unsigned long long)S.cnt_inc,
         (unsigned long long)S.movx, (unsigned long long)S.xen_gaps, (unsigned long long)S.host_rd,
         (unsigned long long)S.host_wr, (unsigned long long)S.ram_checks);
  if (!g_quiet) {
    printf("OPCODES_MISSING");
    for (int i = 0; i < 256; i++) if (!S.opc[i]) printf(" %02x", i);
    printf("\n");
  }
  return S.mismatches ? 1 : 0;
}

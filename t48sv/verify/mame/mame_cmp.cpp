// Instruction-level comparison: MAME src/devices/cpu/mcs48/mcs48.cpp (unmodified,
// compiled against shim/emu.h) against t48sv (Verilated mame_dut.sv).
// After every instruction: A, PC, PSW, SP, F1, MB, timer, timer/IRQ flags,
// P1 / P2 latches, internal RAM, and the number of machine cycles are compared.
// On a disagreement the MAME state is resynchronised from t48sv and the
// (opcode, field) pair is tallied.
//
// mame_cmp [--variant 48|41|21|22] [--rev 0|1] [--progs N] [--instrs N] [--seed S]
#include "emu.h"
#include "mcs48.h"
#include "Vmame_dut.h"
#include "Vmame_dut__Dpi.h"
#include "svdpi.h"
#include "verilated.h"
#include <map>
#include <random>
#include <set>
#include <string>

mcs48_harness *g_harness;
u8 g_ram[256];
static machine_config g_mc;

struct Env : mcs48_harness {
  u8 rom[4096];
  u8 p1in = 0xff, p2in = 0xff, bus = 0xff;
  int t0 = 0, t1 = 0;
  u8 prog_r(offs_t a) override { return rom[a & 0xfff]; }
  u8 io_r(offs_t) override { return bus; }
  void io_w(offs_t, u8) override {}
  u8 port_r(int p) override { return p == 1 ? p1in : p2in; }
  void port_w(int, u8) override {}
  u8 bus_r() override { return bus; }
  void bus_w(u8) override {}
  int test_r(int t) override { return t ? t1 : t0; }
  void prog_w(int) override {}
};

#define MEMBERS                                                                    \
  void start() { this->device_start(); this->device_reset(); }                    \
  int step() { this->m_icount = 1; this->execute_run(); return 1 - this->m_icount; } \
  u8 &a() { return this->m_a; }                                                    \
  u16 &pc() { return this->m_pc; }                                                 \
  u8 &psw() { return this->m_psw; }                                                \
  bool &f1() { return this->m_f1; }                                                \
  u16 &a11() { return this->m_a11; }                                               \
  u8 &timer() { return this->m_timer; }                                            \
  u8 &presc() { return this->m_prescaler; }                                        \
  u8 &p1() { return this->m_p1; }                                                  \
  u8 &p2() { return this->m_p2; }                                                  \
  u8 &tce() { return this->m_timecount_enabled; }                                  \
  bool &tflag() { return this->m_timer_flag; }                                     \
  bool &tovf() { return this->m_timer_overflow; }                                  \
  bool &tie() { return this->m_tirq_enabled; }                                     \
  bool &ie() { return this->m_xirq_enabled; }                                      \
  bool &iprog() { return this->m_irq_in_progress; }                                \
  u8 &t1h() { return this->m_t1_history; }                                         \
  int ram_size() { return this->m_ram_size; }                                      \
  void regs() { this->update_regptr(); }

struct M48 : i8039_device { M48() : i8039_device(g_mc, "cpu", nullptr, 6000000) {} MEMBERS };
struct M41 : i8041ah_device { M41() : i8041ah_device(g_mc, "cpu", nullptr, 6000000) {} MEMBERS
  u8 p2pin() { return this->p2_output(this->m_p2); } };
struct M21 : i8021_device { M21() : i8021_device(g_mc, "cpu", nullptr, 6000000) {} MEMBERS };
struct M22 : i8022_device { M22() : i8022_device(g_mc, "cpu", nullptr, 6000000) {} MEMBERS };

static std::mt19937_64 rng;
static unsigned U(unsigned n) { return (unsigned)(rng() % n); }

struct Tally { uint64_t n = 0; std::string example; };
static std::map<std::pair<int, std::string>, Tally> g_diff;
static uint64_t g_instr = 0, g_cmp = 0, g_bad = 0;
static uint64_t g_opc[256];
static int g_trace, g_noresync;

template <class CPU> static void run_prog(Env &env, int variant, int rev, int ninstr) {
  CPU cpu;
  memset(g_ram, 0, sizeof g_ram);
  cpu.start();
  VerilatedContext ctx;
  Vmame_dut *t = new Vmame_dut(&ctx);
  svSetScope(svGetScopeFromName("TOP.mame_dut"));
  (void)rev;
  u8 pq = 0;
  auto clock = [&](void) {
    t->clk = 0; t->pmem_data_i = pq; t->eval();
    t->clk = 1; t->eval();
    pq = env.rom[t->pmem_addr_o & 0xfff];
  };
  t->p1_i = env.p1in; t->p2_i = env.p2in; t->db_i = env.bus; t->t0_i = env.t0; t->t1_i = env.t1;
  t->int_n_i = 1;
  t->reset_n = 0;
  for (int i = 0; i < 12; i++) clock();
  t->reset_n = 1;
  // run to the end of the reset pseudo-instruction (T48 leaves reset in state M3)
  int pm = t->mstate_o, pmc = t->mcyc_o, psc = t->scyc_o;
  auto boundary = [&]() {
    bool b = pm == 4 && t->mstate_o == 0 && (!pmc || psc);
    pm = t->mstate_o; pmc = t->mcyc_o; psc = t->scyc_o;
    return b;
  };
  while (!boundary()) clock();
  for (int n = 0; n < ninstr; n++) {
    u8 op = env.rom[cpu.pc() & 0xfff];
    int mc = cpu.step();
    // t48sv: cycles until the next non-injected boundary
    int tc = 0;
    for (;;) {
      clock();
      if (pm == 4 && t->mstate_o == 0) tc++;
      bool inj = t->inj_o;
      if (boundary() && !inj) break;
    }
    g_instr++;
    g_opc[op]++;
    if (g_trace)
      printf("TRACE %4d op %02x  MAME A=%02x PC=%03x T=%02x cyc=%d | t48sv A=%02x PC=%03x T=%02x cyc=%d\n", n, op,
             cpu.a(), cpu.pc(), cpu.timer(), mc, t->acc_o, t->pc_o, t->timer_o, tc);
    // compare
    std::vector<std::string> d;
    char buf[160];
    auto chk = [&](const char *f, unsigned m, unsigned s) {
      if (m != s) { snprintf(buf, sizeof buf, "%s mame %x t48sv %x", f, m, s); d.push_back(buf); }
    };
    chk("cycles", mc, tc);
    chk("A", cpu.a(), t->acc_o);
    chk("PC", cpu.pc(), t->pc_o);
    chk("PSW", cpu.psw() & 0xf0, t->psw_o << 4);
    chk("SP", cpu.psw() & 7, t->sp_o);
    chk("F1", cpu.f1(), t->f1_o);
    if (variant == 0) chk("MB", cpu.a11() >> 11, t->mb_o);
    chk("T", cpu.timer(), t->timer_o);
    chk("TF", cpu.tflag(), t->tflag_o);
    chk("TCNTI", cpu.tie(), t->tie_o);
    chk("I", cpu.ie(), t->ie_o);
    chk("TMODE", cpu.tce(), t->tsel_o);
    chk("IRQINPROG", cpu.iprog(), t->iprog_o);
    chk("P1", cpu.p1(), t->p1_o);
    if (variant == 2) chk("P2", cpu.p2() & 0x0f, t->p2q_o & 0x0f);
    else chk("P2", cpu.p2(), t->p2q_o);
    if constexpr (std::is_same_v<CPU, M41>) chk("P2pin", cpu.p2pin(), t->p2_o);
    int ramsz = cpu.ram_size();
    for (int i = 0; i < ramsz; i++)
      if (g_ram[i] != ram_peek(i)) {
        snprintf(buf, sizeof buf, "RAM[%02x] mame %02x t48sv %02x", i, g_ram[i], ram_peek(i));
        d.push_back(buf);
        break;
      }
    g_cmp++;
    if (!d.empty()) {
      g_bad++;
      for (auto &s : d) {
        std::string field = s.substr(0, s.find(' '));
        auto &e = g_diff[{op, field}];
        if (!e.n) e.example = s;
        e.n++;
      }
      // resynchronise MAME from t48sv
      if (!g_noresync) {
      cpu.a() = t->acc_o; cpu.pc() = t->pc_o;
      cpu.psw() = (u8)((t->psw_o << 4) | (cpu.psw() & 0x08) | t->sp_o);
      cpu.f1() = t->f1_o; cpu.a11() = t->mb_o ? 0x800 : 0; cpu.timer() = t->timer_o;
      cpu.tflag() = t->tflag_o; cpu.tie() = t->tie_o; cpu.ie() = t->ie_o; cpu.tce() = t->tsel_o;
      cpu.tovf() = t->tovf_o; cpu.iprog() = t->iprog_o; cpu.p1() = t->p1_o; cpu.p2() = t->p2q_o;
      cpu.presc() = t->presc_o;
      for (int i = 0; i < 256; i++) g_ram[i] = (u8)ram_peek(i);
      cpu.regs();
      }
    }
  }
  t->final();
  delete t;
}

int main(int argc, char **argv) {
  int variant = 0, rev = 0, progs = 200, ninstr = 2000, notimer = 0;
  std::string progfile;
  uint64_t seed = 1;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--variant") { std::string v = argv[++i]; variant = v == "41" ? 1 : v == "21" ? 2 : v == "22" ? 3 : 0; }
    else if (a == "--rev") rev = atoi(argv[++i]);
    else if (a == "--progs") progs = atoi(argv[++i]);
    else if (a == "--instrs") ninstr = atoi(argv[++i]);
    else if (a == "--seed") seed = strtoull(argv[++i], 0, 0);
    else if (a == "--no-timer") notimer = 1;
    else if (a == "--file") progfile = argv[++i];
    else if (a == "--trace") g_trace = 1;
    else if (a == "--noresync") g_noresync = 1;
  }
  rng.seed(seed);
  Env env;
  g_harness = &env;
  for (int p = 0; p < progs; p++) {
    if (!progfile.empty()) {
      FILE *f = fopen(progfile.c_str(), "r");
      unsigned v; int a = 0;
      while (a < 4096 && fscanf(f, "%x", &v) == 1) env.rom[a++] = (u8)v;
      fclose(f);
      env.p1in = env.p2in = env.bus = 0xff; env.t0 = env.t1 = 1;
      progs = 1;
    } else
    for (auto &b : env.rom) {
      b = (u8)U(256);
      // --no-timer: STRT T / STRT CNT become NOP (operand bytes may still decode as them,
      // so a second pass catches those positions too)
      if (notimer && (b == 0x45 || b == 0x55)) b = 0x00;
    }
    // keep INT inactive: the external interrupt is compared separately (timing models differ)
    if (progfile.empty()) { env.p1in = (u8)U(256); env.p2in = (u8)U(256); env.bus = (u8)U(256); }
    if (progfile.empty()) { env.t0 = U(2); env.t1 = U(2); }
    if (variant == 3 && notimer) env.t0 = 1;   // 8022: T0 low is an interrupt request in T48
    switch (variant) {
      case 0: run_prog<M48>(env, variant, rev, ninstr); break;
      case 1: run_prog<M41>(env, variant, rev, ninstr); break;
      case 2: run_prog<M21>(env, variant, rev, ninstr); break;
      default: run_prog<M22>(env, variant, rev, ninstr); break;
    }
  }
  int cov = 0;
  for (int i = 0; i < 256; i++) cov += g_opc[i] != 0;
  printf("MAMECMP variant=%d instrs=%llu compared=%llu disagreeing_instrs=%llu opcodes=%d\n", variant,
         (unsigned long long)g_instr, (unsigned long long)g_cmp, (unsigned long long)g_bad, cov);
  for (auto &kv : g_diff)
    printf("DIFF op=%02x field=%-9s count=%-8llu e.g. %s\n", kv.first.first, kv.first.second.c_str(),
           (unsigned long long)kv.second.n, kv.second.example.c_str());
  return 0;
}

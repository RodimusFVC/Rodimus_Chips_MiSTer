// Lockstep harness: T65 oracle (GHDL-converted) vs t65sv, every output compared on every clock.
//   lockstep random <seed> <cycles>   random memory + random pins
//   lockstep sweep                    directed per-opcode timing sweeps (IRQ/NMI/RDY/SO/Enable/Reset on each cycle)
#include "Vlockstep_top.h"
#include "verilated.h"
#include "covwrite.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

static Vlockstep_top* t;
static uint8_t mem[65536];
static uint64_t cycles = 0, mismatches = 0, comparisons = 0;
static uint64_t opcode_seen[256];        // opcode fetches (Sync & Rdy & Enable) seen in lockstep
static bool fb_write = true;             // DI = DO on write cycles
static uint32_t rng = 1;
static inline uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static const char* ctx = "";

static bool armed = false;  // t=0 power-up before the first clock edge is a simulator artifact (oracle sees a reset edge at init)
static void compare(const char* phase) {
  if (!armed) return;
  comparisons++;
#define CMP(f) if (t->r_##f != t->d_##f) { if (mismatches < 20) printf("MISMATCH %s cyc=%llu %s: %-7s ref=%llx dut=%llx\n", ctx, (unsigned long long)cycles, phase, #f, (unsigned long long)t->r_##f, (unsigned long long)t->d_##f); bad = true; }
  bool bad = false;
  CMP(R_W_n) CMP(Sync) CMP(EF) CMP(MF) CMP(XF) CMP(ML_n) CMP(VP_n) CMP(VDA) CMP(VPA) CMP(NMI_ack)
  CMP(A) CMP(DO) CMP(Regs) CMP(DEBUG)
  if (bad) mismatches++;
}

// Drive DI from memory (feedback of DO on writes unless disabled), settle, compare.
static void settle(const char* phase) {
  t->eval();
  uint16_t a = t->r_A & 0xFFFF;
  if (!t->r_R_W_n) t->DI = fb_write ? t->r_DO : (uint8_t)rnd();
  else t->DI = mem[a];
  t->eval();
  compare(phase);
}

// One full clock: inputs already set (Clk low). Rising edge commits memory write.
static void tick() {
  settle("pre");
  bool wr = !t->r_R_W_n, en = t->Enable;
  bool sync = t->r_Sync, rdy = t->Rdy;
  uint16_t a = t->r_A & 0xFFFF; uint8_t d = t->r_DO;
  if (sync && rdy && en && t->Res_n) opcode_seen[t->DI]++;
  t->Clk = 1; t->eval();
  if (wr && en) mem[a] = d;
  compare("post");
  t->Clk = 0; t->eval();
  cycles++;
}

static void reset_both(int lowcycles = 3) {
  t->Res_n = 1; t->Clk = 0; t->eval();
  t->Res_n = 0; t->eval();
  for (int i = 0; i < lowcycles; i++) { tick(); armed = true; }
  t->Res_n = 1;
}

static void init_pins() {
  t->Mode = 0; t->Enable = 1; t->Rdy = 1; t->Abort_n = 1; t->IRQ_n = 1; t->NMI_n = 1; t->SO_n = 1;
  t->Clk = 0; t->Res_n = 1; t->DI = 0;
}

// ---------------------------------------------------------------- random mode
static int run_random(uint32_t seed, uint64_t ncyc) {
  rng = seed ? seed : 1;
  for (int i = 0; i < 65536; i++) mem[i] = rnd();
  init_pins();
  ctx = "random";
  reset_both();
  int rdy_len = 0, en_len = 0, nmi_len = 0, so_len = 0, irq_len = 0, rst_len = 0;
  int phase_kind = 0;  // varies stimulus density over time
  for (uint64_t c = 0; c < ncyc; c++) {
    if ((c & 0xFFFF) == 0) { phase_kind = rnd() % 8; fb_write = (rnd() % 8) != 0; }
    if ((c & 0x3FFFF) == 0x20000) for (int i = 0; i < 1024; i++) mem[rnd() & 0xFFFF] = rnd();  // stir
    uint32_t r = rnd();
    // Rdy stretches (may land on read or write cycles)
    if (rdy_len > 0) { rdy_len--; t->Rdy = 0; } else { t->Rdy = 1; if (phase_kind >= 2 && (r % (phase_kind >= 6 ? 5 : 23)) == 0) rdy_len = 1 + rnd() % 4; }
    // Enable gaps
    if (en_len > 0) { en_len--; t->Enable = 0; } else { t->Enable = 1; if (phase_kind >= 3 && (rnd() % 7) == 0) en_len = 1 + rnd() % 3; }
    // IRQ: level, random hold times
    // phases 6/7: IRQ and NMI edges every few cycles, overlapping dense RDY stalls
    if (irq_len > 0) irq_len--; else { t->IRQ_n = (phase_kind == 0) ? 1 : (rnd() & 1); irq_len = rnd() % (phase_kind >= 6 ? 6 : 60); }
    // NMI pulses
    if (nmi_len > 0) { nmi_len--; if (nmi_len == 0) t->NMI_n = 1; }
    else if (phase_kind != 0 && (rnd() % (phase_kind == 7 ? 25 : 400)) == 0) { t->NMI_n = 0; nmi_len = 1 + rnd() % 20; }
    // SO pulses
    if (so_len > 0) { so_len--; if (so_len == 0) t->SO_n = 1; }
    else if ((rnd() % 300) == 0) { t->SO_n = 0; so_len = 1 + rnd() % 5; }
    // Abort_n toggles (unused by T65, must stay unused)
    t->Abort_n = (rnd() % 50) != 0;
    // reset mid-instruction
    if (rst_len > 0) { rst_len--; t->Res_n = (rst_len == 0); }
    else if ((rnd() % 200000) == 0) { t->Res_n = 0; rst_len = 1 + rnd() % 4; }
    tick();
    if (mismatches >= 20) break;
  }
  return 0;
}

// ---------------------------------------------------------------- directed sweeps
// Program at $0200: set flags/regs, then target opcode at TGT with chosen operands, then NOPs.
// IRQ/NMI/BRK vectors -> handler at $0300 (RTI).
// combined events: an interrupt edge or SO pulse landing inside a RDY stall, short IRQ pulses, IRQ released mid-stall
enum Ev { EV_IRQ, EV_NMI, EV_RDY1, EV_RDY2, EV_RDY3, EV_SO, EV_EN, EV_RES, EV_IRQNMI, EV_RDYIRQ, EV_RDYNMI,
          EV_IRQPULSE, EV_RDYIRQREL, EV_RDYSO, EV_ENIRQ, EV_NONE, EV_COUNT };
static const char* evname[] = {"IRQ", "NMI", "RDY1", "RDY2", "RDY3", "SO", "EN", "RES", "IRQ+NMI", "RDY+IRQ", "RDY+NMI",
                               "IRQpulse", "RDY+IRQrel", "RDY+SO", "EN+IRQ", "none"};
static uint64_t sweep_runs = 0, sweep_by_ev[EV_COUNT];

static void sweep_one(int op, int var, int pflags, int ev, int k, uint16_t tgt) {
  for (int i = 0; i < 65536; i++) mem[i] = (uint8_t)(i * 7 + (i >> 8) * 13 + var);
  // vectors
  mem[0xFFFA] = 0x00; mem[0xFFFB] = 0x03;   // NMI  -> $0300
  mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x02;   // RES  -> $0200
  mem[0xFFFE] = 0x00; mem[0xFFFF] = 0x03;   // IRQ  -> $0300
  mem[0x0300] = 0x40;                       // RTI
  uint8_t xv = 0x20, yv = 0x30, av = 0x5A;
  uint8_t o1, o2;
  switch (var) {
    case 0: o1 = 0x10; o2 = 0x12; xv = 0x01; yv = 0x02; break;        // no page cross
    case 1: o1 = 0xF0; o2 = 0x12; xv = 0x20; yv = 0x30; break;        // page cross for indexed
    default: o1 = 0x80; o2 = 0x7F; xv = 0xFF; yv = 0xFF; break;       // wraps / negative branch
  }
  // zero page pointers used by (zp,X) and (zp),Y
  for (int z = 0; z < 256; z++) mem[z] = (uint8_t)(0x40 + z);
  uint16_t p = 0x0200;
  auto emit = [&](uint8_t b) { mem[p++] = b; };
  emit(0xA2); emit(xv);               // LDX #
  emit(0xA0); emit(yv);               // LDY #
  emit(0xA9); emit(pflags);           // LDA #flags
  emit(0x48); emit(0x28);             // PHA, PLP
  emit(0xA9); emit(av);               // LDA # (flags N/Z change; I/D/C/V stay)
  emit(0x4C); emit(tgt & 0xFF); emit(tgt >> 8);   // JMP tgt
  mem[tgt] = op; mem[(uint16_t)(tgt + 1)] = o1; mem[(uint16_t)(tgt + 2)] = o2;
  for (int i = 3; i < 24; i++) mem[(uint16_t)(tgt + i)] = 0xEA;
  // branch targets land in NOP sleds too
  uint16_t bt = tgt + 2 + (int8_t)o1;
  for (int i = 0; i < 16; i++) mem[(uint16_t)(bt + i)] = 0xEA;
  // JMP/JSR/RTS/RTI/BRK targets: put NOPs at the absolute target and at the (ind) target
  for (int i = 0; i < 16; i++) mem[(uint16_t)(o2 * 256 + o1 + i)] = 0xEA;
  // setup code and handler written last so no sled can overwrite them
  mem[0x0300] = 0x40;
  p = 0x0200;
  emit(0xA2); emit(xv); emit(0xA0); emit(yv); emit(0xA9); emit(pflags); emit(0x48); emit(0x28);
  emit(0xA9); emit(av); emit(0x4C); emit(tgt & 0xFF); emit(tgt >> 8);
  mem[tgt] = op; mem[(uint16_t)(tgt + 1)] = o1; mem[(uint16_t)(tgt + 2)] = o2;

  init_pins();
  reset_both();
  // run until the target opcode is fetched
  int guard = 0;
  while (!(t->r_Sync && (t->r_A & 0xFFFF) == tgt) && guard++ < 200) { if (guard > 170) printf("A=%04x rw=%d sync=%d DI=%02x\n", (unsigned)(t->r_A & 0xFFFF), t->r_R_W_n, t->r_Sync, t->DI); tick(); }
  if (guard >= 200) { printf("sweep setup failed op=%02x\n", op); mismatches++; return; }
  int n = 0, hold = 0;
  if (ev == EV_RDYIRQREL) t->IRQ_n = 0;
  for (int c = 0; c < 40; c++, n++) {
    if (n == k + 1) {
      if (ev == EV_RDYIRQ || ev == EV_ENIRQ) t->IRQ_n = 0;
      if (ev == EV_RDYNMI) t->NMI_n = 0;
      if (ev == EV_RDYIRQREL) t->IRQ_n = 1;
      if (ev == EV_RDYSO) t->SO_n = 0;
    }
    if (n == k) {
      switch (ev) {
        case EV_IRQ: t->IRQ_n = 0; hold = 1 << 20; break;
        case EV_NMI: t->NMI_n = 0; hold = 6; break;
        case EV_IRQNMI: t->IRQ_n = 0; t->NMI_n = 0; hold = 1 << 20; break;
        case EV_RDY1: t->Rdy = 0; hold = 1; break;
        case EV_RDY2: t->Rdy = 0; hold = 2; break;
        case EV_RDY3: t->Rdy = 0; hold = 3; break;
        case EV_SO: t->SO_n = 0; hold = 2; break;
        case EV_EN: t->Enable = 0; hold = 2; break;
        case EV_RES: t->Res_n = 0; hold = 2; break;
        case EV_RDYIRQ: case EV_RDYIRQREL: t->Rdy = 0; hold = 3; break;
        case EV_RDYNMI: t->Rdy = 0; hold = 6; break;
        case EV_RDYSO: t->Rdy = 0; hold = 3; break;
        case EV_IRQPULSE: t->IRQ_n = 0; hold = 2; break;
        case EV_ENIRQ: t->Enable = 0; hold = 3; break;
        default: break;
      }
    } else if (n > k && hold > 0) {
      if (--hold == 0) {
        t->Rdy = 1; t->SO_n = 1; t->Enable = 1; t->Res_n = 1;
        if (ev == EV_NMI || ev == EV_RDYNMI) t->NMI_n = 1;
        if (ev == EV_IRQPULSE) t->IRQ_n = 1;
      }
    }
    tick();
    if (ev == EV_IRQ || ev == EV_IRQNMI || ev == EV_RDYIRQ || ev == EV_ENIRQ) {
      // drop IRQ once the handler is entered so it does not retrigger forever
      if (t->r_Sync && (t->r_A & 0xFFFF) == 0x0300) { t->IRQ_n = 1; t->NMI_n = 1; }
    }
  }
  sweep_runs++; sweep_by_ev[ev]++;
}

static int run_sweep() {
  // targets: mid-page and near page end (branch/indexed page crossing), and code at page boundary
  const uint16_t tgts[] = {0x0480, 0x04FD, 0x05F0};
  const int pfl[] = {0x00, 0xCB, 0x08, 0xC3};   // all clear / NVBDZC set (I clear) / D set / NVZC set
  char buf[64];
  for (int op = 0; op < 256; op++) {
    for (int ti = 0; ti < 3; ti++)
      for (int var = 0; var < 3; var++)
        for (int pi = 0; pi < 4; pi++)
          for (int ev = 0; ev < EV_COUNT; ev++) {
            int kmax = (ev == EV_NONE) ? 1 : 12;
            for (int k = 0; k < kmax; k++) {
              snprintf(buf, sizeof buf, "op=%02X t=%04X v=%d p=%02X %s@%d", op, tgts[ti], var, pfl[pi], evname[ev], k);
              ctx = buf;
              sweep_one(op, var, pfl[pi], ev, k, tgts[ti]);
              if (mismatches >= 20) return 1;
            }
          }
  }
  printf("sweep runs: %llu (", (unsigned long long)sweep_runs);
  for (int e = 0; e < EV_COUNT; e++) printf("%s%s=%llu", e ? " " : "", evname[e], (unsigned long long)sweep_by_ev[e]);
  printf(")\n");
  return 0;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  t = new Vlockstep_top;
  std::string mode = argc > 1 ? argv[1] : "random";
  if (mode == "random") {
    uint32_t seed = argc > 2 ? strtoul(argv[2], 0, 0) : 1;
    uint64_t n = argc > 3 ? strtoull(argv[3], 0, 0) : 1000000;
    run_random(seed, n);
  } else if (mode == "sweep") {
    run_sweep();
  }
  int ops = 0;
  for (int i = 0; i < 256; i++) ops += opcode_seen[i] != 0;
  uint64_t mn = ~0ull; for (int i = 0; i < 256; i++) if (opcode_seen[i] < mn) mn = opcode_seen[i];
  printf("%s: cycles=%llu comparisons=%llu mismatches=%llu opcodes_executed=%d/256 min_per_opcode=%llu\n",
         mode.c_str(), (unsigned long long)cycles, (unsigned long long)comparisons,
         (unsigned long long)mismatches, ops, (unsigned long long)mn);
  COV_WRITE();
  delete t;
  return mismatches ? 1 : 0;
}

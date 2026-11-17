// Directed tests for the t65sv816 behaviour SingleStepTests cannot reach: reset, IRQ, NMI, ABORT, WAI, STP.
// Built like sst816 (--public-flat-rw); prints one line per check and exits non-zero on any failure.
#include "Vt65sv816.h"
#include "Vt65sv816___024root.h"
#include "verilated.h"
#include "covwrite.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

static Vt65sv816* t;
static std::vector<uint8_t> mem(1 << 24, 0);
static int fails = 0;
static uint64_t cyc = 0;
struct Cyc { uint32_t a; uint8_t d; bool rd, vda, vpa, vp; };
static std::vector<Cyc> trace;

#define R(sig) t->rootp->t65sv816__DOT__##sig

static void step() {
  t->eval();
  uint32_t a = t->A & 0xFFFFFF;
  if (t->R_W_n) t->DI = mem[a];
  t->eval();
  a = t->A & 0xFFFFFF;
  trace.push_back({a, t->R_W_n ? t->DI : t->DO, (bool)t->R_W_n, (bool)t->VDA, (bool)t->VPA, !t->VP_n});
  if (!t->R_W_n) mem[a] = t->DO;
  t->Clk = 1; t->eval(); t->Clk = 0; t->eval();
  cyc++;
}
static void run(int n) { for (int i = 0; i < n; i++) step(); }
// run until an opcode fetch at PBR:PC == a (max n cycles); returns true if reached
static bool run_to(uint32_t a, int n) {
  for (int i = 0; i < n; i++) {
    t->eval();
    if (t->Sync && (t->A & 0xFFFFFF) == a) return true;
    step();
  }
  return false;
}
static void check(bool ok, const char* what) {
  printf("%s %s\n", ok ? "PASS" : "FAIL", what);
  if (!ok) fails++;
}
static void put(uint32_t a, std::initializer_list<uint8_t> b) { for (auto v : b) mem[a++] = v; }
static void reset() {
  t->Res_n = 0; t->Clk = 0; t->eval(); run(2); t->Res_n = 1; t->eval();
}
static bool saw_write(uint32_t a, uint8_t v) {
  for (auto& c : trace) if (!c.rd && c.a == a && c.d == v) return true;
  return false;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  t = new Vt65sv816;
  t->Enable = 1; t->Rdy = 1; t->Abort_n = 1; t->IRQ_n = 1; t->NMI_n = 1;

  // vectors (emulation / native)
  put(0xFFFC, {0x00, 0x80});              // RESET  -> 8000
  put(0xFFFE, {0x00, 0x90});              // IRQ/BRK (emulation) -> 9000
  put(0xFFFA, {0x00, 0x91});              // NMI (emulation) -> 9100
  put(0xFFF8, {0x00, 0x92});              // ABORT (emulation) -> 9200
  put(0xFFEE, {0x00, 0xA0});              // IRQ (native) -> A000
  put(0xFFEA, {0x00, 0xA1});              // NMI (native) -> A100
  put(0xFFE8, {0x00, 0xA2});              // ABORT (native) -> A200
  for (uint32_t a = 0x9000; a < 0xA300; a++) mem[a] = 0xEA;   // handlers: NOPs

  // ---- reset
  put(0x8000, {0x58, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0xEA, 0x80, 0xF7});   // CLI; NOP x6; BRA 8000
  reset();
  trace.clear();
  bool r = run_to(0x008000, 20);
  bool vp = false; for (auto& c : trace) if (c.vp && (c.a == 0xFFFC || c.a == 0xFFFD)) vp = true;
  check(r && trace.size() <= 10, "reset: vector 00FFFC fetched within 10 cycles, first opcode at 008000");
  check(vp, "reset: VPB asserted on the vector reads");
  check(R(Ef) == 1 && (R(P) & 0x3C) == 0x34 && R(D) == 0 && R(DBR) == 0 && R(PBR) == 0 && (R(S) >> 8) == 1,
        "reset: E=1, M=X=1, I=1, D=0, D=0000, DBR=PBR=00, SH=01");

  // ---- IRQ, emulation
  run(4);                                   // CLI done
  uint16_t s0 = R(S);
  t->IRQ_n = 0; trace.clear();
  r = run_to(0x009000, 40);
  t->IRQ_n = 1;
  check(r, "IRQ (emulation): vectors through 00FFFE");
  check((uint16_t)(R(S)) == (uint16_t)(0x0100 | ((s0 - 3) & 0xFF)), "IRQ (emulation): 3 bytes pushed in page 1");
  check((mem[0x0100 | ((s0 - 2) & 0xFF)] & 0x10) == 0, "IRQ (emulation): pushed P has B clear");
  check((R(P) & 0x04) != 0, "IRQ: I set on entry");

  // ---- NMI, emulation (edge triggered; I is set)
  t->NMI_n = 0; trace.clear();
  r = run_to(0x009100, 40);
  check(r, "NMI (emulation): vectors through 00FFFA with I=1");
  run(20);
  bool again = false;
  trace.clear(); run(30);
  for (auto& c : trace) if (c.vp) again = true;
  check(!again, "NMI: a held-low NMI is taken once (edge triggered)");
  t->NMI_n = 1; run(2);

  // ---- native mode: CLC; XCE; REP #$30; LDA #$1234; ... then IRQ pushes PBR
  put(0x9200, {0x18, 0xFB, 0xC2, 0x30, 0x58, 0xA9, 0x34, 0x12, 0xEA, 0xEA, 0xEA, 0xEA, 0x80, 0xFA});
  R(PC) = 0x9200; R(PBR) = 0x00; R(IR) = 0xEA; R(K) = 0; R(INTR) = 0; t->eval();
  run_to(0x00920C, 60);
  check(R(Ef) == 0 && (R(P) & 0x30) == 0 && R(C) == 0x1234, "native: XCE / REP #$30 / LDA #$1234");
  // jump to bank 05 so the pushed PBR is visible
  put(0x05A000, {0xEA, 0xEA, 0xEA, 0xEA, 0x80, 0xFA});
  R(PC) = 0xA000; R(PBR) = 0x05; R(IR) = 0xEA; R(K) = 0; t->eval();
  s0 = R(S);
  t->IRQ_n = 0; trace.clear();
  r = run_to(0x00A000, 40);
  t->IRQ_n = 1;
  check(r && R(PBR) == 0, "IRQ (native): vectors through 00FFEE, PBR=00");
  check(R(S) == (uint16_t)(s0 - 4) && mem[s0] == 0x05, "IRQ (native): 4 bytes pushed, PBR first");

  // ---- ABORT (native): abort an INX, registers unchanged, return address = the INX
  R(PC) = 0xA000; R(PBR) = 0x05; R(IR) = 0xEA; R(K) = 0; t->eval();
  put(0x05A000, {0xE8, 0xE8, 0xE8, 0xEA, 0x80, 0xFB});
  R(X) = 0x0100; s0 = R(S);
  run_to(0x05A001, 10);           // first INX done (X=0101); now at the second INX fetch
  step();                          // opcode fetch of INX @A001
  t->Abort_n = 0; step(); t->Abort_n = 1;   // its execute cycle
  trace.clear();
  r = run_to(0x00A200, 40);
  check(r, "ABORT (native): vectors through 00FFE8");
  check(R(X) == 0x0101, "ABORT: the aborted INX did not modify X");
  check(mem[(uint16_t)(s0 - 1)] == 0xA0 && mem[(uint16_t)(s0 - 2)] == 0x01, "ABORT: pushed return address is the aborted opcode (05:A001)");

  // ---- WAI with I=1: IRQ resumes after WAI without vectoring
  put(0x050000, {0x78, 0xCB, 0xE8, 0xEA, 0x80, 0xFE});   // SEI; WAI; INX; NOP; BRA *
  R(PC) = 0x0000; R(PBR) = 0x05; R(IR) = 0xEA; R(K) = 0; R(X) = 0x0010; t->eval();
  run(12);
  check(R(X) == 0x0010 && !t->Wait_n, "WAI: waiting, next instruction not executed");
  t->IRQ_n = 0; trace.clear();
  r = run_to(0x050003, 10);
  t->IRQ_n = 1;
  bool vec = false; for (auto& c : trace) if (c.vp) vec = true;
  check(r && R(X) == 0x0011 && !vec, "WAI + IRQ with I=1: continues with the next instruction");

  // ---- WAI with I=0: IRQ is taken
  put(0x050010, {0x58, 0xCB, 0xE8, 0x80, 0xFE});
  R(PC) = 0x0010; R(PBR) = 0x05; R(IR) = 0xEA; R(K) = 0; t->eval();
  run(10);
  t->IRQ_n = 0; r = run_to(0x00A000, 20); t->IRQ_n = 1;
  check(r, "WAI + IRQ with I=0: interrupt taken");

  // ---- STP: only reset restarts
  put(0x050020, {0xDB, 0xE8});
  R(PC) = 0x0020; R(PBR) = 0x05; R(IR) = 0xEA; R(K) = 0; R(X) = 0x0020; t->eval();
  run(5); t->IRQ_n = 0; t->NMI_n = 0; run(20); t->IRQ_n = 1; t->NMI_n = 1;
  check(R(X) == 0x0020 && R(PC) == 0x0021, "STP: IRQ / NMI do not restart");
  reset(); r = run_to(0x008000, 20);
  check(r, "STP: reset restarts");

  printf("%s: %d failure(s)\n", fails ? "FAIL" : "PASS", fails);
  COV_WRITE();
  return fails ? 1 : 0;
}

// Directed 65C02 tests SingleStepTests cannot cover: WAI/STP (WDC) and interrupt entry clearing D.
// Solo build with C02=1, Mode 01.
#include "tbcommon.h"

static int fails = 0;
static void chk(const char* what, unsigned got, unsigned want) {
  printf("%-58s got %02X want %02X %s\n", what, got, want, got == want ? "ok" : "FAIL");
  if (got != want) fails++;
}

// program at $0400, IRQ/BRK handler at $0300, NMI handler at $0340
static void load(Bus& b, const std::vector<uint8_t>& prog) {
  memset(b.mem, 0, sizeof b.mem);
  for (size_t i = 0; i < prog.size(); i++) b.mem[0x400 + i] = prog[i];
  const uint8_t irq[] = {0x08, 0x68, 0x85, 0x20,         // PHP PLA STA $20   (P inside the handler)
                         0xE6, 0x21, 0x40};              // INC $21 RTI
  const uint8_t nmi[] = {0xE6, 0x22, 0x40};              // INC $22 RTI
  memcpy(b.mem + 0x300, irq, sizeof irq);
  memcpy(b.mem + 0x340, nmi, sizeof nmi);
  b.mem[0xFFFA] = 0x40; b.mem[0xFFFB] = 0x03;
  b.mem[0xFFFC] = 0x00; b.mem[0xFFFD] = 0x04;
  b.mem[0xFFFE] = 0x00; b.mem[0xFFFF] = 0x03;
  b.init_pins(); b.t->Mode = 1; b.reset();
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Bus b;
  // 1: WAI with I=1, IRQ asserted -> resumes after WAI, no vector
  load(b, {0x78, 0xCB, 0xA9, 0x01, 0x85, 0x10, 0x4C, 0x06, 0x04});      // SEI WAI LDA #1 STA $10 JMP *
  for (int i = 0; i < 60; i++) b.tick();
  chk("WAI (I=1): stalled before IRQ", b.mem[0x10], 0x00);
  int wrs = 0; for (int i = 0; i < 40; i++) { if (!b.t->r_R_W_n) wrs++; b.tick(); }
  chk("WAI: no bus writes while waiting", wrs, 0);
  b.t->IRQ_n = 0; for (int i = 0; i < 30; i++) b.tick(); b.t->IRQ_n = 1;
  chk("WAI (I=1) + IRQ: execution continues after WAI", b.mem[0x10], 0x01);
  chk("WAI (I=1) + IRQ: handler not entered", b.mem[0x21], 0x00);

  // 2: WAI with I=0 and D=1: IRQ vector taken, D clear inside handler, restored after RTI
  load(b, {0x58, 0xF8, 0xCB, 0x08, 0x68, 0x85, 0x11, 0x4C, 0x07, 0x04}); // CLI SED WAI PHP PLA STA $11 JMP *
  for (int i = 0; i < 60; i++) b.tick();
  b.t->IRQ_n = 0; for (int i = 0; i < 14; i++) b.tick(); b.t->IRQ_n = 1;
  for (int i = 0; i < 60; i++) b.tick();
  chk("WAI (I=0) + IRQ: handler entered once", b.mem[0x21], 0x01);
  chk("IRQ entry: D clear, I set in handler (P & $0C)", b.mem[0x20] & 0x0C, 0x04);
  chk("after RTI: D restored (P & $08)", b.mem[0x11] & 0x08, 0x08);

  // 3: WAI woken by NMI
  load(b, {0x78, 0xCB, 0xA9, 0x02, 0x85, 0x10, 0x4C, 0x06, 0x04});
  for (int i = 0; i < 50; i++) b.tick();
  b.t->NMI_n = 0; for (int i = 0; i < 4; i++) b.tick(); b.t->NMI_n = 1;
  for (int i = 0; i < 60; i++) b.tick();
  chk("WAI + NMI: NMI handler entered", b.mem[0x22], 0x01);
  chk("WAI + NMI: execution continues after WAI", b.mem[0x10], 0x02);

  // 4: STP stops until reset, IRQ/NMI do not wake it
  load(b, {0xA9, 0x03, 0x85, 0x12, 0xDB, 0xA9, 0x04, 0x85, 0x12, 0x4C, 0x09, 0x04});
  for (int i = 0; i < 40; i++) b.tick();
  b.t->NMI_n = 0; b.t->IRQ_n = 0; for (int i = 0; i < 60; i++) b.tick(); b.t->NMI_n = 1; b.t->IRQ_n = 1;
  for (int i = 0; i < 20; i++) b.tick();
  chk("STP: instruction after STP never runs", b.mem[0x12], 0x03);
  chk("STP: no interrupt taken", b.mem[0x21] + b.mem[0x22], 0x00);
  b.mem[0x400] = 0xA9; b.mem[0x401] = 0x05;               // after reset: LDA #5, STA $12, STP
  b.reset(); for (int i = 0; i < 40; i++) b.tick();
  chk("STP: reset restarts the CPU", b.mem[0x12], 0x05);

  // 5: NMI entry clears D as well; BRK clears D (SST checks BRK too)
  load(b, {0xF8, 0xEA, 0xEA, 0x4C, 0x01, 0x04});          // SED NOP NOP JMP $0401
  b.mem[0x340] = 0x08; b.mem[0x341] = 0x68; b.mem[0x342] = 0x85; b.mem[0x343] = 0x23; b.mem[0x344] = 0x40;
  for (int i = 0; i < 30; i++) b.tick();
  b.t->NMI_n = 0; for (int i = 0; i < 4; i++) b.tick(); b.t->NMI_n = 1;
  for (int i = 0; i < 40; i++) b.tick();
  chk("NMI entry: D clear in handler", b.mem[0x23] & 0x08, 0x00);

  printf("%s\n", fails ? "FAIL" : "PASS");
  COV_WRITE();
  return fails ? 1 : 0;
}

// Directed test of t65sv_6510's I/O port ($0000 DDR, $0001 data) against datasheet behaviour:
// reset state, read-back of DDR, output bits from the data latch, input bits from the pins,
// bits 6/7 (no pins on 6510/8500) holding their last driven level, and port accesses still
// appearing on the external bus.
#include "Vt65sv_6510.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
static Vt65sv_6510* t; static uint8_t mem[65536]; static int fails = 0, buswr01 = 0;
static void tick() {
  t->Clk = 0; t->eval();
  if (t->R_W_n) t->DI = mem[t->A]; else t->DI = t->DO;
  t->eval();
  bool wr = !t->R_W_n; uint16_t a = t->A; uint8_t d = t->DO;
  t->Clk = 1; t->eval();
  if (wr) { mem[a] = d; if (a < 2) { buswr01++; if (getenv("DBG")) printf("bus write $%04X=%02X\n", a, d); } }
}
static void chk(const char* what, unsigned got, unsigned want) {
  printf("%-44s got %02X want %02X %s\n", what, got, want, got == want ? "ok" : "FAIL");
  if (got != want) fails++;
}
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  t = new Vt65sv_6510;
  const uint8_t prog[] = {
    0xA9,0xFF,0x85,0x00, 0xA9,0xA5,0x85,0x01,           // DDR=$FF, data=$A5
    0xA5,0x01,0x8D,0x00,0x02, 0xA5,0x00,0x8D,0x01,0x02, // read $01,$00
    0xA9,0x0F,0x85,0x00, 0xA5,0x01,0x8D,0x02,0x02,      // DDR=$0F, read $01
    0xA9,0x00,0x85,0x00, 0xA5,0x01,0x8D,0x03,0x02,      // DDR=0, read $01
    0xA9,0xC0,0x85,0x00, 0xA9,0x40,0x85,0x01,           // drive bits 7/6 = 0/1
    0xA9,0x00,0x85,0x00, 0xA5,0x01,0x8D,0x04,0x02,      // float them again, read
    0x4C,0x3B,0x04 };
  memcpy(mem + 0x0400, prog, sizeof prog);
  mem[0xFFFC] = 0x00; mem[0xFFFD] = 0x04;
  mem[0x0000] = 0x11; mem[0x0001] = 0x22;               // RAM under the port must not be what the CPU reads
  t->Enable = 1; t->Rdy = 1; t->AEC = 1; t->IRQ_n = 1; t->NMI_n = 1; t->P_I = 0x30;
  t->Res_n = 1; t->Clk = 0; t->eval(); t->Res_n = 0; t->eval();
  for (int i = 0; i < 4; i++) tick();
  chk("after reset: DDR", t->P_DDR, 0x00);
  chk("after reset: data latch", t->P_O, 0x00);
  t->Res_n = 1; buswr01 = 0;   // registers power up 0 (R_W_n low) until the first clock: not a CPU write
  for (int i = 0; i < 400; i++) tick();
  chk("DDR=$FF data=$A5: read $01", mem[0x200], 0xA5);
  chk("read $00 returns DDR", mem[0x201], 0xFF);
  chk("DDR=$0F pins=$30: read $01 (bit7 held 1)", mem[0x202], 0xB5);
  chk("DDR=$00: read $01 = pins | held b7/b6", mem[0x203], 0xB0);
  chk("bits 7/6 re-driven 0/1 then floated", mem[0x204], 0x70);
  chk("P_DDR output", t->P_DDR, 0x00);
  chk("P_O output (data latch)", t->P_O, 0x40);
  chk("Bus_En follows AEC", t->Bus_En, 1);
  printf("port writes seen on the external bus: %d (want 7)\n", buswr01);
  if (buswr01 != 7) fails++;
  printf("%s\n", fails ? "FAIL" : "PASS");
  delete t; return fails ? 1 : 0;
}

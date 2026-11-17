// 6507 lockstep: random 8 KB memory image, random RDY/Enable gaps and resets
#include "Vls6507_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  Vls6507_top* t = new Vls6507_top; uint8_t mem[8192]; uint32_t r = 7;
  auto rnd = [&]() { r ^= r << 13; r ^= r >> 17; r ^= r << 5; return r; };
  for (int i = 0; i < 8192; i++) mem[i] = rnd();
  uint64_t cyc = 0, mism = 0;
  t->Res_n = 1; t->Enable = 1; t->Rdy = 1; t->Clk = 0; t->eval(); t->Res_n = 0; t->eval();
  for (uint64_t c = 0; c < 5000000; c++) {
    if (c == 3) t->Res_n = 1;
    t->Rdy = (rnd() % 11) != 0; t->Enable = (rnd() % 7) != 0;
    if ((rnd() % 300000) == 0) t->Res_n = 0; else if (!t->Res_n && (rnd() % 3) == 0) t->Res_n = 1;
    t->eval();
    t->DI = t->r_RW ? mem[t->r_A] : t->r_DO; t->eval();
    if (c > 3 && (t->r_A != t->d_A || t->r_DO != t->d_DO || t->r_RW != t->d_RW)) mism++;
    bool wr = !t->r_RW && t->Enable; uint16_t a = t->r_A; uint8_t d = t->r_DO;
    t->Clk = 1; t->eval(); if (wr) mem[a] = d;
    if (c > 3 && (t->r_A != t->d_A || t->r_DO != t->d_DO || t->r_RW != t->d_RW)) mism++;
    t->Clk = 0; t->eval(); cyc++;
  }
  printf("6507 lockstep: cycles=%llu mismatches=%llu\n", (unsigned long long)cyc, (unsigned long long)mism);
  return mism != 0;
}

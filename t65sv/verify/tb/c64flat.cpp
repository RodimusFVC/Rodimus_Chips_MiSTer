// Flat C64 shim for CPU-only test programs (Lorenz instruction tests, VICE CPU tests without DMA timing).
// RAM + real BASIC/KERNAL/CHAR ROMs banked by the 6510 port (emulated here), I/O area reads $FF except a
// free-running raster counter at $D011/$D012; CHROUT ($FFD2) is trapped (fetch returns RTS, A is logged).
// No boot: KERNAL vectors are copied to $0314, a small preamble sets S/port/I and jumps to the SYS address.
// Result = first write to $D7FF ($00 pass, $FF fail).
//   c64flat <prg> [--rom basic_kernal.hex] [--chr chargen.hex] [--max N]
#include "tbcommon.h"

static uint8_t rom[16384], chr[4096];
static uint8_t ddr = 0x2f, port = 0x35;
static int result = -1;
static std::string out;

static uint8_t bank() { return ((port & ddr) | (0x17 & ~ddr)) & 7; }

static uint8_t rd(Bus& b, uint16_t a, bool& h) {
  uint8_t bs = bank();
  h = true;
  if (a == 0) return ddr;
  if (a == 1) return (port & ddr) | (0x17 & ~ddr) | (port & ~ddr & 0xc8);
  if (a >= 0xe000 && (bs & 2)) {
    if (a == 0xffd2 && b.t->r_Sync) { out += (char)b.rA(); return 0x60; }    // CHROUT -> RTS
    return rom[0x2000 + (a - 0xe000)];
  }
  if (a >= 0xa000 && a < 0xc000 && (bs & 3) == 3) return rom[a - 0xa000];
  if (a >= 0xd000 && a < 0xe000 && (bs & 3)) {
    if (!(bs & 4)) return chr[a & 0xfff];
    uint64_t line = (b.cycles / 63) % 312;
    if ((a & 0xfc3f) == 0xd011) return (uint8_t)(0x1b | ((line >> 1) & 0x80));
    if ((a & 0xfc3f) == 0xd012) return (uint8_t)line;
    return 0xff;
  }
  h = false;
  return 0;
}

static bool wr(Bus& b, uint16_t a, uint8_t v) {
  uint8_t bs = bank();
  if (a == 0) ddr = v;
  if (a == 1) port = v;
  if (a >= 0xd000 && a < 0xe000 && (bs & 3) && (bs & 4)) {
    if (a == 0xd7ff && result < 0) result = v;
    return true;                                   // I/O write, RAM untouched
  }
  return false;
}

static bool load_hexbytes(const char* fn, uint8_t* d, int n) {
  FILE* f = fopen(fn, "r"); if (!f) return false;
  unsigned v; int i = 0;
  while (i < n && fscanf(f, "%x", &v) == 1) d[i++] = v;
  fclose(f); return i == n;
}

int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  std::string prg, romf = "c64/gen/basic_kernal.hex", chrf = "c64/gen/chargen.hex";
  uint64_t maxc = 2000000000ull;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    if (a == "--rom") romf = argv[++i];
    else if (a == "--chr") chrf = argv[++i];
    else if (a == "--max") maxc = strtoull(argv[++i], 0, 0);
    else prg = a;
  }
  if (!load_hexbytes(romf.c_str(), rom, 16384) || !load_hexbytes(chrf.c_str(), chr, 4096)) { printf("ROM load failed\n"); return 2; }
  Bus b; b.rd_hook = rd; b.wr_hook = wr;
  std::vector<uint8_t> img;
  { FILE* f = fopen(prg.c_str(), "rb"); if (!f) { printf("cannot open %s\n", prg.c_str()); return 2; }
    int c; while ((c = fgetc(f)) != EOF) img.push_back(c); fclose(f); }
  uint16_t la = img[0] | img[1] << 8;
  for (size_t i = 2; i < img.size(); i++) b.mem[(uint16_t)(la + i - 2)] = img[i];
  // SYS address from the BASIC stub
  int sys = la;
  for (size_t i = 2; i + 1 < img.size() && i < 40; i++)
    if (img[i] == 0x9e) { sys = 0; for (size_t j = i + 1; j < img.size() && img[j] >= '0' && img[j] <= '9'; j++) sys = sys * 10 + img[j] - '0'; break; }
  // KERNAL state a booted C64 would have: vectors $0314-$0333 (RESTOR table at $FD30), screen base
  for (int i = 0; i < 32; i++) b.mem[0x314 + i] = rom[0x2000 + 0xfd30 - 0xe000 + i];
  b.mem[0x288] = 0x04;
  uint16_t end = la + img.size() - 2;
  b.mem[0x2b] = 0x01; b.mem[0x2c] = 0x08; b.mem[0x2d] = end & 0xff; b.mem[0x2e] = end >> 8;
  // preamble in the cassette buffer (reset vector in RAM, KERNAL banked out until the port is set):
  // LDA #$2F, STA $00, LDA #$37, STA $01, LDX #$F6, TXS, CLI, JMP sys
  uint8_t pre[] = {0xa9, 0x2f, 0x85, 0x00, 0xa9, 0x37, 0x85, 0x01, 0xa2, 0xf6, 0x9a, 0x58,
                   0x4c, (uint8_t)(sys & 0xff), (uint8_t)(sys >> 8)};
  for (unsigned i = 0; i < sizeof pre; i++) b.mem[0x33c + i] = pre[i];
  b.mem[0xfffc] = 0x3c; b.mem[0xfffd] = 0x03;
  b.init_pins();
  ddr = 0x2f; port = 0x35;
  b.reset();
  while (b.cycles < maxc && result < 0 && b.mismatches < 20) b.tick();
  for (int i = 0; i < 8; i++) b.tick();
  for (auto& c : out) { if (c == 13) c = '|'; else if (c >= 0x41 && c <= 0x5a) c += 0x20; else if ((uint8_t)c >= 0xc1 && (uint8_t)c <= 0xda) c -= 0x80; else if (c < 0x20 || c > 0x7e) c = '.'; }
  const char* r = result == 0 ? "PASS" : result == 0xff ? "FAIL" : result >= 0 ? "D7FF?" : "TIMEOUT";
  printf("%s %s d7ff=%02x cycles=%llu", r, prg.c_str(), result & 0xff, (unsigned long long)b.cycles);
#ifdef LOCKSTEP
  printf(" lockstep_comparisons=%llu mismatches=%llu", (unsigned long long)b.comparisons, (unsigned long long)b.mismatches);
#endif
  printf(" out=\"%s\"\n", out.c_str());
  return result == 0 && !b.mismatches ? 0 : 1;
}

// Copyright (C) 2026 Rodimus
// Generates the V20 8080-emulation-mode test suite from the reference model (v20e.h):
//   gen <out dir> [tests per opcode file]
// One gzipped JSON array per file; the seed of each file is derived from SEED and the file name (reproducible).
#include "v20e.h"
#include <zlib.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <vector>

static const uint64_t SEED = 0x5632303830383031ULL;   // "V2080801"

struct Rng {
    uint64_t s;
    explicit Rng(uint64_t seed) : s(seed) {}
    uint64_t next() { uint64_t z = (s += 0x9E3779B97F4A7C15ULL); z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
                      z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL; return z ^ (z >> 31); }
    uint32_t u(uint32_t n) { return (uint32_t)(next() % n); }
    uint8_t b() { return (uint8_t)next(); }
    uint16_t w() { return (uint16_t)next(); }
    bool p(uint32_t n) { return u(n) == 0; }      // probability 1/n
};
static uint64_t fnv(const std::string &s) { uint64_t h = 1469598103934665603ULL; for (char c : s) { h ^= (uint8_t)c; h *= 1099511628211ULL; } return h; }

static const uint8_t E8[] = {0x00, 0x01, 0x0F, 0x10, 0x7F, 0x80, 0x81, 0xFE, 0xFF, 0x09, 0x0A, 0x99, 0x9A, 0x90, 0xF0, 0x8F, 0x55, 0xAA};
static const uint16_t E16[] = {0x0000, 0x0001, 0xFFFF, 0xFFFE, 0x7FFF, 0x8000, 0x00FF, 0x0100, 0xFFFD, 0x0002};
static uint8_t e8(Rng &g) { return E8[g.u(sizeof E8)]; }
static uint16_t e16(Rng &g) { return E16[g.u(sizeof E16 / 2)]; }

// memory: unknown bytes are random on first touch; records first-access order, initial and final values, writes
struct GMem : v20e::Bus {
    Rng *g;
    std::map<uint32_t, uint8_t> init, cur;
    std::vector<uint32_t> order;
    std::set<uint32_t> written;
    std::vector<std::pair<uint8_t, uint8_t>> outs;
    uint8_t port_in = 0xFF;
    bool used_in = false;
    void touch(uint32_t a) { if (!init.count(a)) { uint8_t v = g->b(); init[a] = v; cur[a] = v; order.push_back(a); } }
    void preset(uint32_t a, uint8_t v) { if (!init.count(a)) { init[a] = v; cur[a] = v; order.push_back(a); } }
    uint8_t rd(uint32_t a) override { touch(a); return cur[a]; }
    void wr(uint32_t a, uint8_t v) override { touch(a); cur[a] = v; written.insert(a); }
    uint8_t inp(uint16_t) override { used_in = true; return port_in; }
    void outp(uint16_t port, uint8_t v) override { outs.push_back({(uint8_t)port, v}); }
};

static const char *RN[14] = {"ax", "bx", "cx", "dx", "cs", "ss", "ds", "es", "sp", "bp", "si", "di", "ip", "flags"};
static void regs14(const v20e::Cpu &c, uint16_t *o) {
    o[0] = c.r[v20e::AW]; o[1] = c.r[v20e::BW]; o[2] = c.r[v20e::CW]; o[3] = c.r[v20e::DW];
    o[4] = c.s[v20e::PS]; o[5] = c.s[v20e::SS]; o[6] = c.s[v20e::DS0]; o[7] = c.s[v20e::DS1];
    o[8] = c.r[v20e::SP]; o[9] = c.r[v20e::BP]; o[10] = c.r[v20e::IX]; o[11] = c.r[v20e::IY];
    o[12] = c.pc; o[13] = c.psw;
}
static std::string view8080(const v20e::Cpu &c) {
    char b[200];
    snprintf(b, sizeof b, "{\"a\":%u,\"f\":%u,\"b\":%u,\"c\":%u,\"d\":%u,\"e\":%u,\"h\":%u,\"l\":%u,\"sp\":%u,\"pc\":%u}",
             c.r[0] & 0xFF, c.psw & 0xFF, c.r[1] >> 8, c.r[1] & 0xFF, c.r[2] >> 8, c.r[2] & 0xFF, c.r[3] >> 8, c.r[3] & 0xFF,
             c.r[5], c.pc);
    return b;
}

static const char *R8[8] = {"B", "C", "D", "E", "H", "L", "M", "A"};
static const char *RP[4] = {"B", "D", "H", "SP"};
static const char *CC[8] = {"NZ", "Z", "NC", "C", "PO", "PE", "P", "M"};
static std::string mnem(uint8_t op) {
    char b[40];
    int d = (op >> 3) & 7, s = op & 7;
    static const char *AL[8] = {"ADD", "ADC", "SUB", "SBB", "ANA", "XRA", "ORA", "CMP"};
    static const char *AI[8] = {"ADI", "ACI", "SUI", "SBI", "ANI", "XRI", "ORI", "CPI"};
    static const char *X7[8] = {"RLC", "RRC", "RAL", "RAR", "DAA", "CMA", "STC", "CMC"};
    if (op == 0x76) return "HLT";
    if ((op & 0xC0) == 0x40) { snprintf(b, sizeof b, "MOV %s,%s", R8[d], R8[s]); return b; }
    if ((op & 0xC0) == 0x80) { snprintf(b, sizeof b, "%s %s", AL[d], R8[s]); return b; }
    if ((op & 0xC0) == 0) {
        switch (s) {
        case 0: return op ? "NOP*" : "NOP";
        case 1: snprintf(b, sizeof b, "%s %s", (op & 8) ? "DAD" : "LXI", RP[op >> 4]); return b;
        case 2: { static const char *M2[8] = {"STAX B", "LDAX B", "STAX D", "LDAX D", "SHLD", "LHLD", "STA", "LDA"}; return M2[d]; }
        case 3: snprintf(b, sizeof b, "%s %s", (op & 8) ? "DCX" : "INX", RP[op >> 4]); return b;
        case 4: snprintf(b, sizeof b, "INR %s", R8[d]); return b;
        case 5: snprintf(b, sizeof b, "DCR %s", R8[d]); return b;
        case 6: snprintf(b, sizeof b, "MVI %s", R8[d]); return b;
        default: return X7[d];
        }
    }
    switch (s) {
    case 0: snprintf(b, sizeof b, "R%s", CC[d]); return b;
    case 1: { static const char *M1[8] = {"POP B", "RET", "POP D", "RET*", "POP H", "PCHL", "POP PSW", "SPHL"}; return M1[d]; }
    case 2: snprintf(b, sizeof b, "J%s", CC[d]); return b;
    case 3: { static const char *M3[8] = {"JMP", "JMP*", "OUT", "IN", "XTHL", "XCHG", "DI", "EI"}; return M3[d]; }
    case 4: snprintf(b, sizeof b, "C%s", CC[d]); return b;
    case 5: { static const char *M5[8] = {"PUSH B", "CALL", "PUSH D", "CALL*", "PUSH H", "ESC", "PUSH PSW", "CALL*"}; return M5[d]; }
    case 6: return AI[d];
    default: snprintf(b, sizeof b, "RST %d", d); return b;
    }
}

enum Kind { K8080, KED, KEDX, KBRKEM, KRETI, KPOPF, KINT, KNMI, KRETEM0 };

struct File {
    std::string name;
    Kind kind;
    uint8_t op;
    int count;
};

struct Writer {
    gzFile z;
    bool first = true;
    std::string buf;
    explicit Writer(const std::string &p) { z = gzopen(p.c_str(), "wb9"); gzputs(z, "["); }
    void test(const std::string &s) { if (!first) buf += ",\n"; else buf += "\n"; first = false; buf += s;
                                       if (buf.size() > (1 << 20)) { gzwrite(z, buf.data(), (unsigned)buf.size()); buf.clear(); } }
    ~Writer() { buf += "\n]\n"; gzwrite(z, buf.data(), (unsigned)buf.size()); gzclose(z); }
};

static std::string state_json(const v20e::Cpu &c, const GMem &m, bool fin, const uint16_t *ir, bool init_we) {
    std::string s = "{\"regs\":{";
    uint16_t r[14]; regs14(c, r);
    bool firstr = true;
    for (int i = 0; i < 14; i++) {
        if (fin && r[i] == ir[i]) continue;
        char b[32]; snprintf(b, sizeof b, "%s\"%s\":%u", firstr ? "" : ",", RN[i], r[i]); s += b; firstr = false;
    }
    s += "},\"md_we\":"; s += c.we ? "1" : "0";
    (void)init_we;
    s += ",\"i8080\":" + view8080(c) + ",\"ram\":[";
    bool firstm = true;
    for (uint32_t a : m.order) {
        if (fin && !m.written.count(a)) continue;
        char b[32]; snprintf(b, sizeof b, "%s[%u,%u]", firstm ? "" : ",", a, fin ? m.cur.at(a) : m.init.at(a)); s += b; firstm = false;
    }
    s += "]}";
    return s;
}

// one test: random initial state with edge values forced in, run one instruction (+ interrupt), emit JSON
static std::string make_test(const File &f, int idx, Rng &g, bool &ok) {
    GMem m; m.g = &g;
    v20e::Cpu c; c.bus = &m;
    for (int i = 0; i < 8; i++) c.r[i] = g.w();
    for (int i = 0; i < 4; i++) c.s[i] = g.w();
    c.pc = g.w();
    uint16_t p = g.w();
    if (g.p(4)) p = (uint16_t)(p & ~v20e::F8080);
    else if (g.p(3)) p = (uint16_t)(p | v20e::F8080);
    p &= ~v20e::F_BRK;                                   // single-step is not exercised
    c.psw = v20e::psw_norm((uint16_t)(p & ~v20e::F_MD)); // emulation mode
    c.we = true;
    // edge values
    if (g.p(4)) c.r[0] = (uint16_t)((c.r[0] & 0xFF00) | e8(g));
    for (int k = 1; k <= 3; k++) {
        if (g.p(5)) c.r[k] = (uint16_t)((c.r[k] & 0xFF00) | e8(g));
        if (g.p(5)) c.r[k] = (uint16_t)((c.r[k] & 0x00FF) | (e8(g) << 8));
        if (g.p(8)) c.r[k] = e16(g);
    }
    if (g.p(6)) c.r[5] = e16(g);
    if (g.p(16)) c.pc = (uint16_t)(0xFFFF - g.u(3));
    if (g.p(16)) c.s[v20e::PS] = (uint16_t)(0xFFFF - g.u(2));
    if (g.p(16)) c.s[v20e::DS0] = (uint16_t)(0xFFFF - g.u(2));

    uint8_t op = f.op;
    // code bytes
    uint32_t pa = v20e::Cpu::phys(c.s[1], c.pc);
    auto code = [&](int k, uint8_t v) { m.preset(v20e::Cpu::phys(c.s[1], (uint16_t)(c.pc + k)), v); };
    std::string name;
    bool native = false, inferred = false;
    uint8_t intvec = 0;
    bool intr = false, nmi = false;
    switch (f.kind) {
    case K8080: {
        code(0, op);
        // immediates: edge or random
        if (g.p(4)) { code(1, e8(g)); code(2, e8(g)); }
        if ((op & 0xC7) == 0x06 || (op & 0xC7) == 0xC6) {}   // MVI / immediate ALU: byte 1 as above
        // memory operand at HL: edge value sometimes
        if (g.p(4)) m.preset(v20e::Cpu::phys(c.s[3], c.r[3]), e8(g));
        name = mnem(op);
        if (op == 0x08 || op == 0x10 || op == 0x18 || op == 0x20 || op == 0x28 || op == 0x30 || op == 0x38 ||
            op == 0xCB || op == 0xD9 || op == 0xDD || op == 0xFD) inferred = true;
        if (op == 0x27) {                                // DAA: every A x AC x CY combination, twice
            int k = idx % 1024;
            c.r[0] = (uint16_t)((c.r[0] & 0xFF00) | (k & 0xFF));
            c.psw = (uint16_t)((c.psw & ~(v20e::F_AC | v20e::F_CY)) | ((k & 0x100) ? v20e::F_AC : 0) | ((k & 0x200) ? v20e::F_CY : 0));
        }
        if (op == 0xDB) m.port_in = g.p(4) ? e8(g) : g.b();
        break;
    }
    case KED: code(0, 0xED); code(1, op); name = op == 0xED ? "CALLN" : "RETEM";
        if (op == 0xFD) {                                // stacked PSW as BRKEM leaves it: MD = 1
            uint32_t a = v20e::Cpu::phys(c.s[2], (uint16_t)(c.r[4] + 5));
            m.preset(a, (uint8_t)(g.b() | 0x80));
        }
        break;
    case KRETEM0: code(0, 0xED); code(1, 0xFD); name = "RETEM (stacked MD 0)"; inferred = true;
        m.preset(v20e::Cpu::phys(c.s[2], (uint16_t)(c.r[4] + 5)), (uint8_t)(g.b() & 0x7F));
        break;
    case KEDX: { uint8_t o2; do { o2 = g.b(); } while (o2 == 0xED || o2 == 0xFD); code(0, 0xED); code(1, o2);
        name = "ED (undefined second byte)"; inferred = true; break; }
    case KBRKEM:
        native = true; c.psw = v20e::psw_norm((uint16_t)(c.psw | v20e::F_MD)); c.we = false;
        code(0, 0x0F); code(1, 0xFF); name = "BRKEM"; break;
    case KRETI: case KPOPF: {
        native = true; c.psw = v20e::psw_norm((uint16_t)(c.psw | v20e::F_MD)); c.we = g.p(4) ? false : true;
        code(0, f.kind == KRETI ? 0xCF : 0x9D);
        int slot = f.kind == KRETI ? 5 : 1;
        m.preset(v20e::Cpu::phys(c.s[2], (uint16_t)(c.r[4] + slot)), (uint8_t)(g.p(2) ? (g.b() & 0x7F) : (g.b() | 0x80)));
        name = f.kind == KRETI ? (c.we ? "RETI (MD write enabled)" : "RETI (MD write disabled)")
                               : (c.we ? "POP PSW (MD write enabled)" : "POP PSW (MD write disabled)");
        break;
    }
    case KINT: case KNMI: {
        // one register-only 8080 instruction, then INT (INTA vector) or NMI at its end
        static const uint8_t ops[] = {0x00, 0x41, 0x7A, 0x80, 0x91, 0xA2, 0xB3, 0xBF, 0x04, 0x0D, 0x03, 0x2B, 0x07, 0x1F, 0x27, 0x2F, 0x37, 0x3F, 0xEB};
        uint8_t o = ops[g.u(sizeof ops)];
        code(0, o);
        if (f.kind == KINT) { intr = true; intvec = g.b(); name = std::string("INT after ") + mnem(o); }
        else { nmi = true; intvec = 2; name = std::string("NMI after ") + mnem(o); }
        break;
    }
    }
    (void)pa;
    if (native) c.psw |= v20e::F_MD;

    v20e::Cpu c0 = c;
    uint16_t ir[14]; regs14(c, ir);
    // run
    ok = c.step();
    if (ok && (nmi || (intr && (c.psw & v20e::F_IE)))) c.interrupt(intvec);
    // initial state JSON needs the initial memory incl. bytes first touched by the run (their initial values)
    std::string s = "{\"idx\":" + std::to_string(idx) + ",\"name\":\"" + name + "\",\"bytes\":[";
    for (int i = 0; i < c.ilen; i++) { if (i) s += ","; s += std::to_string(c.ibytes[i]); }
    s += "],\"initial\":";
    {
        // initial state: registers of c0, every touched address with its initial value
        GMem mi = m; mi.written.clear();
        for (auto &kv : mi.init) mi.cur[kv.first] = kv.second;
        s += state_json(c0, mi, false, ir, c0.we);
    }
    if (intr || nmi) {
        s += ",\"pins\":{\"intr\":" + std::string(intr ? "1" : "0") + ",\"nmi\":" + (nmi ? "1" : "0") +
             ",\"inta_vector\":" + std::to_string(intr ? intvec : 0) + "}";
    }
    if (m.used_in) s += ",\"port_in\":" + std::to_string(m.port_in);
    s += ",\"final\":" + state_json(c, m, true, ir, c0.we);
    s += ",\"ports\":[";
    for (size_t i = 0; i < m.outs.size(); i++) { if (i) s += ","; s += "[" + std::to_string(m.outs[i].first) + "," + std::to_string(m.outs[i].second) + "]"; }
    s += "]";
    if (c.halted) s += ",\"halted\":1";
    if (inferred) s += ",\"inferred\":1";
    s += "}";
    return s;
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: gen <out dir> [tests per opcode file]\n"); return 2; }
    std::string out = argv[1];
    int n = argc > 2 ? atoi(argv[2]) : 1000;
    std::vector<File> files;
    for (int o = 0; o < 256; o++) {
        if (o == 0xED) continue;
        char b[8]; snprintf(b, sizeof b, "%02X", o);
        files.push_back({b, K8080, (uint8_t)o, o == 0x27 ? 2048 : n});
    }
    files.push_back({"ED_ED", KED, 0xED, n});
    files.push_back({"ED_FD", KED, 0xFD, n});
    files.push_back({"ED_xx", KEDX, 0, n});
    files.push_back({"ED_FD_md0", KRETEM0, 0, n / 4});
    files.push_back({"0F_FF", KBRKEM, 0, n});
    files.push_back({"CF_native", KRETI, 0, n});
    files.push_back({"9D_native", KPOPF, 0, n});
    files.push_back({"INT", KINT, 0, n});
    files.push_back({"NMI", KNMI, 0, n});
    long total = 0;
    for (auto &f : files) {
        Rng g(SEED ^ fnv(f.name));
        Writer w(out + "/" + f.name + ".json.gz");
        for (int i = 0; i < f.count; i++) {
            bool ok = true;
            std::string t = make_test(f, i, g, ok);
            if (!ok) { fprintf(stderr, "%s: model does not cover test %d\n", f.name.c_str(), i); return 1; }
            w.test(t);
        }
        total += f.count;
    }
    printf("%zu files, %ld tests, seed %016llX\n", files.size(), total, (unsigned long long)SEED);
    return 0;
}

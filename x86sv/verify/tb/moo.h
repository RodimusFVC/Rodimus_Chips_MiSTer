// Copyright (C) 2026 Rodimus
// MOO (SingleStepTests) reader: gzip file -> vector of tests. Bounds-checked; the file is untrusted data.
#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <zlib.h>

namespace moo {

enum { R_AX, R_BX, R_CX, R_DX, R_CS, R_SS, R_DS, R_ES, R_SP, R_BP, R_SI, R_DI, R_IP, R_FLAGS, R_NUM };
static const char *reg_name[R_NUM] = {"ax", "bx", "cx", "dx", "cs", "ss", "ds", "es",
                                      "sp", "bp", "si", "di", "ip", "flags"};

struct Cycle {
    uint8_t pins;      // b0 ALE
    uint32_t addr;     // multiplexed bus (20 bits)
    uint8_t seg;       // 0 ES 1 SS 2 CS/none 3 DS 4 invalid
    uint8_t mem;       // b2 R (MRDC) b1 A (AMWC) b0 W (MWTC)
    uint8_t io;        // b2 IORC b1 AIOWC b0 IOWC
    uint8_t bhe;
    uint16_t data;
    uint8_t bus;       // S2-S0: 0 INTA 1 IOR 2 IOW 3 MEMR 4 MEMW 5 HALT 6 CODE 7 PASV
    uint8_t ts;        // 0 Ti 1 T1 2 T2 3 T3 4 T4
    uint8_t qop;       // 0 none 1 first 2 flush 3 subsequent
    uint8_t qbyte;
};

struct State {
    uint16_t mask = 0;
    uint16_t regs[R_NUM] = {};
    std::vector<std::pair<uint32_t, uint8_t>> ram;
    std::vector<uint8_t> queue;
};

struct Test {
    uint32_t index = 0;
    std::string name;
    std::vector<uint8_t> bytes;
    State init, fina;
    std::vector<Cycle> cycles;
    uint8_t hash[20] = {};
};

struct File {
    std::string error;
    uint32_t count = 0;
    std::string cpu;
    std::vector<Test> tests;
};

class Rd {
public:
    Rd(const uint8_t *p, size_t n) : p_(p), n_(n) {}
    bool ok() const { return ok_; }
    size_t left() const { return ok_ ? n_ - i_ : 0; }
    uint8_t u8() { if (!need(1)) return 0; return p_[i_++]; }
    uint16_t u16() { if (!need(2)) return 0; uint16_t v = p_[i_] | (p_[i_ + 1] << 8); i_ += 2; return v; }
    uint32_t u32() {
        if (!need(4)) return 0;
        uint32_t v = p_[i_] | (p_[i_ + 1] << 8) | (p_[i_ + 2] << 16) | ((uint32_t)p_[i_ + 3] << 24);
        i_ += 4; return v;
    }
    std::string tag() { if (!need(4)) return ""; std::string s((const char *)p_ + i_, 4); i_ += 4; return s; }
    Rd sub(uint32_t len) { if (!need(len)) return Rd(p_, 0); Rd r(p_ + i_, len); i_ += len; return r; }
    const uint8_t *raw(uint32_t len) { if (!need(len)) return nullptr; const uint8_t *r = p_ + i_; i_ += len; return r; }
private:
    bool need(size_t k) { if (!ok_ || n_ - i_ < k) { ok_ = false; return false; } return true; }
    const uint8_t *p_; size_t n_; size_t i_ = 0; bool ok_ = true;
};

static bool read_state(Rd r, State &s) {
    while (r.ok() && r.left() >= 8) {
        std::string t = r.tag();
        uint32_t len = r.u32();
        Rd c = r.sub(len);
        if (!r.ok()) return false;
        if (t == "REGS") {
            s.mask = c.u16();
            for (int i = 0; i < R_NUM; i++)
                if (s.mask & (1 << i)) s.regs[i] = c.u16();
            if (s.mask >> R_NUM) return false;
        } else if (t == "RAM ") {
            uint32_t n = c.u32();
            if (n > len / 5) return false;
            for (uint32_t i = 0; i < n; i++) {
                uint32_t a = c.u32();
                uint8_t v = c.u8();
                s.ram.push_back({a, v});
            }
        } else if (t == "QUEU") {
            uint32_t n = c.u32();
            if (n > 16) return false;
            for (uint32_t i = 0; i < n; i++) s.queue.push_back(c.u8());
        }
        if (!c.ok()) return false;
    }
    return r.ok();
}

static bool read_test(Rd r, Test &t) {
    t.index = r.u32();
    while (r.ok() && r.left() >= 8) {
        std::string tg = r.tag();
        uint32_t len = r.u32();
        Rd c = r.sub(len);
        if (!r.ok()) return false;
        if (tg == "NAME") {
            uint32_t n = c.u32();
            const uint8_t *s = c.raw(n);
            if (s) t.name.assign((const char *)s, n);
        } else if (tg == "BYTS") {
            uint32_t n = c.u32();
            const uint8_t *s = c.raw(n);
            if (s) t.bytes.assign(s, s + n);
        } else if (tg == "INIT") {
            if (!read_state(c, t.init)) return false;
        } else if (tg == "FINA") {
            if (!read_state(c, t.fina)) return false;
        } else if (tg == "CYCL") {
            uint32_t n = c.u32();
            if (n > len / 15) return false;
            t.cycles.resize(n);
            for (uint32_t i = 0; i < n; i++) {
                Cycle &y = t.cycles[i];
                y.pins = c.u8(); y.addr = c.u32(); y.seg = c.u8(); y.mem = c.u8(); y.io = c.u8();
                y.bhe = c.u8(); y.data = c.u16(); y.bus = c.u8(); y.ts = c.u8(); y.qop = c.u8(); y.qbyte = c.u8();
            }
        } else if (tg == "HASH") {
            const uint8_t *s = c.raw(20);
            if (s) memcpy(t.hash, s, 20);
        }
        if (!c.ok()) return false;
    }
    return r.ok();
}

static File load(const std::string &path) {
    File f;
    gzFile g = gzopen(path.c_str(), "rb");
    if (!g) { f.error = "cannot open " + path; return f; }
    std::vector<uint8_t> buf;
    uint8_t tmp[1 << 16];
    int k;
    while ((k = gzread(g, tmp, sizeof tmp)) > 0) {
        buf.insert(buf.end(), tmp, tmp + k);
        if (buf.size() > (1u << 30)) { f.error = "file too large"; gzclose(g); return f; }
    }
    gzclose(g);
    if (k < 0) { f.error = "gzip error"; return f; }
    Rd r(buf.data(), buf.size());
    bool first = true;
    while (r.ok() && r.left() >= 8) {
        std::string t = r.tag();
        uint32_t len = r.u32();
        Rd c = r.sub(len);
        if (!r.ok()) break;
        if (first) {
            if (t != "MOO ") { f.error = "not a MOO file"; return f; }
            c.u8(); c.u8(); c.u8(); c.u8();
            f.count = c.u32();
            const uint8_t *s = c.raw(4);
            if (s) f.cpu.assign((const char *)s, 4);
            first = false;
        } else if (t == "TEST") {
            Test x;
            if (!read_test(c, x)) { f.error = "bad TEST chunk"; return f; }
            f.tests.push_back(std::move(x));
        }
    }
    if (!r.ok()) f.error = "truncated file";
    else if (f.tests.size() != f.count) f.error = "test count mismatch";
    return f;
}

static const char *seg_s[] = {"ES", "SS", "CS", "DS", "--"};
static const char *bus_s[] = {"INTA", "IOR ", "IOW ", "MEMR", "MEMW", "HALT", "CODE", "PASV"};
static const char *ts_s[] = {"Ti", "T1", "T2", "T3", "T4"};
static const char *q_s[] = {"-", "F", "E", "S"};

static std::string rwa(uint8_t v) {
    std::string s = "---";
    if (v & 4) s[0] = 'R';
    if (v & 2) s[1] = 'A';
    if (v & 1) s[2] = 'W';
    return s;
}

static std::string fmt(const Cycle &c) {
    char b[96];
    snprintf(b, sizeof b, "%c %05X %s %s %s %02X %s %s %s %02X", (c.pins & 1) ? 'A' : '.', c.addr & 0xFFFFF,
             seg_s[c.seg < 5 ? c.seg : 4], rwa(c.mem).c_str(), rwa(c.io).c_str(), c.data & 0xFF,
             bus_s[c.bus & 7], ts_s[c.ts < 5 ? c.ts : 0], q_s[c.qop & 3], c.qbyte);
    return b;
}

// 16-bit bus view: BHE (active low) and the whole data field
static std::string fmtw(const Cycle &c) {
    char b[112];
    snprintf(b, sizeof b, "%c %05X %s %s %s %c %04X %s %s %s %02X", (c.pins & 1) ? 'A' : '.', c.addr & 0xFFFFF,
             seg_s[c.seg < 5 ? c.seg : 4], rwa(c.mem).c_str(), rwa(c.io).c_str(), c.bhe ? '-' : 'B', c.data,
             bus_s[c.bus & 7], ts_s[c.ts < 5 ? c.ts : 0], q_s[c.qop & 3], c.qbyte);
    return b;
}

} // namespace moo

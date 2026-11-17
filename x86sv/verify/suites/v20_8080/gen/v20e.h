// Copyright (C) 2026 Rodimus
// Reference model of the NEC V20 / V30 (uPD70108 / uPD70116) 8080 emulation mode, written from the NEC and Intel
// documents only (see ../README.md for the page references). Stand-alone: shares no code with the x86sv RTL or its
// testbench. Register state is kept in the native view; the 8080 view is derived from it (NEC UM figure 8-1).
#pragma once
#include <cstdint>

namespace v20e {

// memory / I/O seen by the CPU (20-bit physical addresses)
struct Bus {
    virtual uint8_t rd(uint32_t a) = 0;
    virtual void wr(uint32_t a, uint8_t v) = 0;
    virtual uint8_t inp(uint16_t port) = 0;
    virtual void outp(uint16_t port, uint8_t v) = 0;
    virtual ~Bus() {}
};

enum { AW, CW, DW, BW, SP, BP, IX, IY };           // native general registers (AX CX DX BX SP BP SI DI)
enum { DS1, PS, SS, DS0 };                         // segment registers (ES CS SS DS)
enum : uint16_t { F_CY = 1, F_P = 4, F_AC = 0x10, F_Z = 0x40, F_S = 0x80, F_BRK = 0x100, F_IE = 0x200,
                  F_DIR = 0x400, F_V = 0x800, F_MD = 0x8000 };
static const uint16_t F8080 = F_S | F_Z | F_AC | F_P | F_CY;   // the five flags the 8080 view owns (UM figure 8-2)

// PSW as the CPU holds it: bits 12-14 and 1 read as 1, bits 3 and 5 as 0
inline uint16_t psw_norm(uint16_t p) { return (uint16_t)((p | 0x7002) & ~0x0028); }

struct Cpu {
    uint16_t r[8] = {};
    uint16_t s[4] = {};
    uint16_t pc = 0;
    uint16_t psw = 0xF002;                          // MD = 1: native
    bool we = false;                                // MD write enable (set by BRKEM, cleared by RETEM)
    bool halted = false;
    Bus *bus = nullptr;
    uint8_t ibytes[8]; int ilen = 0;                // code bytes of the last instruction

    bool md() const { return psw & F_MD; }
    static uint32_t phys(uint16_t seg, uint16_t off) { return (((uint32_t)seg << 4) + off) & 0xFFFFF; }
    uint8_t rd8(uint16_t seg, uint16_t off) { return bus->rd(phys(seg, off)); }
    void wr8(uint16_t seg, uint16_t off, uint8_t v) { bus->wr(phys(seg, off), v); }
    uint16_t rd16(uint16_t seg, uint16_t off) { return (uint16_t)(rd8(seg, off) | (rd8(seg, (uint16_t)(off + 1)) << 8)); }
    void wr16(uint16_t seg, uint16_t off, uint16_t v) { wr8(seg, off, v & 0xFF); wr8(seg, (uint16_t)(off + 1), v >> 8); }
    uint8_t fetch() { uint8_t b = rd8(s[PS], pc); pc++; if (ilen < 8) ibytes[ilen++] = b; return b; }
    uint16_t fetch16() { uint8_t lo = fetch(); return (uint16_t)(lo | (fetch() << 8)); }

    // 8080 registers (UM figure 8-1): A = AL, B = CH, C = CL, D = DH, E = DL, H = BH, L = BL, SP = BP
    uint8_t get8(int i) {
        switch (i) {
        case 0: return r[CW] >> 8;   case 1: return r[CW] & 0xFF;
        case 2: return r[DW] >> 8;   case 3: return r[DW] & 0xFF;
        case 4: return r[BW] >> 8;   case 5: return r[BW] & 0xFF;
        case 6: return rd8(s[DS0], r[BW]);
        default: return r[AW] & 0xFF;
        }
    }
    void set8(int i, uint8_t v) {
        auto hi = [&](int k) { r[k] = (uint16_t)((r[k] & 0x00FF) | (v << 8)); };
        auto lo = [&](int k) { r[k] = (uint16_t)((r[k] & 0xFF00) | v); };
        switch (i) {
        case 0: hi(CW); break;  case 1: lo(CW); break;
        case 2: hi(DW); break;  case 3: lo(DW); break;
        case 4: hi(BW); break;  case 5: lo(BW); break;
        case 6: wr8(s[DS0], r[BW], v); break;
        default: lo(AW); break;
        }
    }
    uint8_t a() const { return r[AW] & 0xFF; }
    void seta(uint8_t v) { r[AW] = (uint16_t)((r[AW] & 0xFF00) | v); }
    uint16_t &rp(int i) { static const int m[4] = {CW, DW, BW, BP}; return r[m[i & 3]]; }

    // 8080 flags: only S Z AC P CY change (UM figure 8-2); V, DIR, IE, BRK, MD are not 8080 flags
    void setf(uint16_t mask, uint16_t val) { psw = (uint16_t)((psw & ~mask) | (val & mask)); }
    static uint16_t szp(uint8_t v) {
        uint8_t p = v; p ^= p >> 4; p ^= p >> 2; p ^= p >> 1;
        return (uint16_t)((v & 0x80 ? F_S : 0) | (v == 0 ? F_Z : 0) | ((p & 1) ? 0 : F_P));
    }
    bool cy() const { return psw & F_CY; }

    // ALU (ALP chapter 3; AND sets AC to the OR of bit 3 of the operands, ALP 1-12; subtraction is an addition of
    // the complement, AC is the carry out of bit 3 of that addition, CY the borrow)
    void alu(int op, uint8_t b) {
        uint8_t x = a(), v; uint16_t f;
        switch (op) {
        case 0: case 1: {                                   // ADD ADC
            int c = (op == 1 && cy()) ? 1 : 0;
            int sum = x + b + c;
            v = (uint8_t)sum;
            f = szp(v) | ((sum >> 8) ? F_CY : 0) | (((x & 15) + (b & 15) + c) > 15 ? F_AC : 0);
            seta(v); setf(F8080, f); return;
        }
        case 2: case 3: case 7: {                           // SUB SBB CMP
            int c = (op == 3 && cy()) ? 0 : 1;
            uint8_t nb = (uint8_t)~b;
            int sum = x + nb + c;
            v = (uint8_t)sum;
            f = szp(v) | ((sum >> 8) ? 0 : F_CY) | (((x & 15) + (nb & 15) + c) > 15 ? F_AC : 0);
            if (op != 7) seta(v);
            setf(F8080, f); return;
        }
        case 4: v = x & b; f = szp(v) | (((x | b) & 8) ? F_AC : 0); break;   // ANA
        case 5: v = x ^ b; f = szp(v); break;                               // XRA
        default: v = x | b; f = szp(v); break;                              // ORA
        }
        seta(v); setf(F8080, f);
    }

    void push8080(uint16_t v) { r[BP]--; wr8(s[DS0], r[BP], v >> 8); r[BP]--; wr8(s[DS0], r[BP], v & 0xFF); }
    uint16_t pop8080() { uint8_t lo = rd8(s[DS0], r[BP]); r[BP]++; uint8_t hi = rd8(s[DS0], r[BP]); r[BP]++; return (uint16_t)(lo | (hi << 8)); }
    bool cond(int c) {
        bool f;
        switch (c >> 1) { case 0: f = psw & F_Z; break; case 1: f = psw & F_CY; break; case 2: f = psw & F_P; break; default: f = psw & F_S; break; }
        return f == (bool)(c & 1);
    }

    // native stack (SS:SP)
    void npush(uint16_t v) { r[SP] -= 2; wr16(s[SS], r[SP], v); }
    uint16_t npop() { uint16_t v = rd16(s[SS], r[SP]); r[SP] += 2; return v; }
    // BRK-type entry: PSW, PS, PC pushed on the native stack (UM 12-167 .. 12-169, 12-176). The vector is read before
    // the pushes (the V20's native interrupt bus order; it matters only when the stack overlaps the vector)
    void enter(uint8_t n) {
        uint16_t off = (uint16_t)(n * 4), npc = rd16(0, off), nps = rd16(0, (uint16_t)(off + 2));
        npush(psw); npush(s[PS]); npush(pc);
        pc = npc; s[PS] = nps;
    }

    // external interrupt (INT after INTA, or NMI = vector 2) at an instruction boundary: UM section 8 "NMI or INT
    // Operation" (the same as in native mode, the routine runs in native mode)
    void interrupt(uint8_t n) {
        enter(n);
        psw = (uint16_t)(psw & ~(F_IE | F_BRK));
        psw |= F_MD;
        halted = false;
    }

    // one instruction; returns false for a native opcode the model does not cover
    bool step() {
        ilen = 0;
        if (halted) return true;
        if (!md()) return step8080();
        return step_native();
    }

    bool step_native() {
        uint8_t op = fetch();
        switch (op) {
        case 0x0F: {
            uint8_t op2 = fetch();
            if (op2 != 0xFF) return false;
            uint8_t n = fetch();                            // BRKEM imm8 (UM 12-169)
            enter(n);
            psw = (uint16_t)(psw & ~F_MD);
            we = true;
            return true;
        }
        case 0xCF: {                                        // RETI (UM 12-168)
            pc = npop(); s[PS] = npop();
            uint16_t p = npop();
            psw = psw_norm((uint16_t)((p & 0x7FFF) | ((we ? p : 0xFFFF) & F_MD)));
            return true;
        }
        case 0x9D: {                                        // POP PSW (UM 12-151)
            uint16_t p = npop();
            psw = psw_norm((uint16_t)((p & 0x7FFF) | ((we ? p : 0xFFFF) & F_MD)));
            return true;
        }
        case 0xE6: { uint8_t p = fetch(); bus->outp(p, a()); return true; }   // OUT imm8, AL
        case 0x90: return true;
        case 0xF4: halted = true; return true;
        default: return false;
        }
    }

    bool step8080() {
        uint8_t op = fetch();
        int d = (op >> 3) & 7, sr = op & 7;
        switch (op >> 6) {
        case 1:                                             // MOV r, r' / HLT (ALP 3-46, 3-24)
            if (op == 0x76) { halted = true; return true; }
            set8(d, get8(sr));
            return true;
        case 2:                                             // ADD ADC SUB SBB ANA XRA ORA CMP r / M
            alu(d, get8(sr));
            return true;
        default: break;
        }
        if ((op & 0xC0) == 0) {
            switch (op & 7) {
            case 0: return true;                            // NOP (08 10 18 20 28 30 38: undefined, as NOP)
            case 1:
                if (op & 8) {                               // DAD rp: HL += rp, CY only (ALP 3-20)
                    uint32_t s32 = (uint32_t)r[BW] + rp(op >> 4);
                    r[BW] = (uint16_t)s32;
                    setf(F_CY, (s32 >> 16) ? F_CY : 0);
                } else rp(op >> 4) = fetch16();             // LXI rp (ALP 3-35)
                return true;
            case 2:
                switch (op >> 3) {
                case 0: wr8(s[DS0], r[CW], a()); break;     // STAX B
                case 1: seta(rd8(s[DS0], r[CW])); break;    // LDAX B
                case 2: wr8(s[DS0], r[DW], a()); break;     // STAX D
                case 3: seta(rd8(s[DS0], r[DW])); break;    // LDAX D
                case 4: { uint16_t ad = fetch16(); wr16(s[DS0], ad, r[BW]); break; }  // SHLD
                case 5: { uint16_t ad = fetch16(); r[BW] = rd16(s[DS0], ad); break; }  // LHLD
                case 6: { uint16_t ad = fetch16(); wr8(s[DS0], ad, a()); break; }      // STA
                default: { uint16_t ad = fetch16(); seta(rd8(s[DS0], ad)); break; }    // LDA
                }
                return true;
            case 3: if (op & 8) rp(op >> 4)--; else rp(op >> 4)++; return true;      // DCX / INX, no flags
            case 4: {                                       // INR (AC = carry out of bit 3)
                uint8_t v = get8(d), n = (uint8_t)(v + 1);
                set8(d, n);
                setf(F_S | F_Z | F_P | F_AC, szp(n) | (((v & 15) + 1) > 15 ? F_AC : 0));
                return true;
            }
            case 5: {                                       // DCR (adds FF: AC = carry out of bit 3)
                uint8_t v = get8(d), n = (uint8_t)(v - 1);
                set8(d, n);
                setf(F_S | F_Z | F_P | F_AC, szp(n) | (((v & 15) + 15) > 15 ? F_AC : 0));
                return true;
            }
            case 6: set8(d, fetch()); return true;          // MVI
            default:
                switch (op >> 3) {
                case 0: { uint8_t x = a(); uint8_t c = x >> 7; seta((uint8_t)((x << 1) | c)); setf(F_CY, c); return true; }    // RLC
                case 1: { uint8_t x = a(); uint8_t c = x & 1; seta((uint8_t)((x >> 1) | (c << 7))); setf(F_CY, c); return true; } // RRC
                case 2: { uint8_t x = a(); uint8_t c = x >> 7; seta((uint8_t)((x << 1) | (cy() ? 1 : 0))); setf(F_CY, c); return true; }  // RAL
                case 3: { uint8_t x = a(); uint8_t c = x & 1; seta((uint8_t)((x >> 1) | (cy() ? 0x80 : 0))); setf(F_CY, c); return true; } // RAR
                case 4: {                                   // DAA (ALP 3-18 / 3-19): one correction added to A
                    uint8_t x = a(), lsb = x & 15, msb = x >> 4, corr = 0;
                    bool c = cy();
                    if ((psw & F_AC) || lsb > 9) corr |= 0x06;
                    if (c || msb > 9 || (msb >= 9 && lsb > 9)) { corr |= 0x60; c = true; }
                    uint8_t v = (uint8_t)(x + corr);
                    seta(v);
                    setf(F8080, szp(v) | (c ? F_CY : 0) | (((lsb + (corr & 15)) > 15) ? F_AC : 0));
                    return true;
                }
                case 5: seta((uint8_t)~a()); return true;   // CMA
                case 6: setf(F_CY, F_CY); return true;      // STC
                default: setf(F_CY, cy() ? 0 : F_CY); return true;   // CMC
                }
            }
        }
        // C0-FF
        switch (op & 7) {
        case 0: if (cond(d)) pc = pop8080(); return true;   // Rcc
        case 1:
            switch (d) {
            case 1: case 3: pc = pop8080(); return true;    // RET (D9 undefined, as RET)
            case 5: pc = r[BW]; return true;                // PCHL
            case 7: r[BP] = r[BW]; return true;             // SPHL
            case 6: {                                       // POP PSW: A = high byte, flags from the low byte
                uint16_t v = pop8080();
                seta(v >> 8);
                setf(F8080, v);
                return true;
            }
            default: rp(d >> 1) = pop8080(); return true;   // POP B / D / H
            }
        case 2: { uint16_t t = fetch16(); if (cond(d)) pc = t; return true; }   // Jcc
        case 3:
            switch (d) {
            case 0: case 1: pc = fetch16(); return true;    // JMP (CB undefined, as JMP)
            case 2: { uint8_t p = fetch(); bus->outp(p, a()); return true; }   // OUT
            case 3: { uint8_t p = fetch(); seta(bus->inp(p)); return true; }   // IN
            case 4: {                                       // XTHL
                uint16_t v = rd16(s[DS0], r[BP]);
                wr16(s[DS0], r[BP], r[BW]);
                r[BW] = v;
                return true;
            }
            case 5: { uint16_t t = r[DW]; r[DW] = r[BW]; r[BW] = t; return true; }   // XCHG
            case 6: psw &= ~F_IE; return true;              // DI
            default: psw |= F_IE; return true;              // EI
            }
        case 4: { uint16_t t = fetch16(); if (cond(d)) { push8080(pc); pc = t; } return true; }   // Ccc
        case 5:
            if (op == 0xED) return step_ed();
            if (d & 1) { uint16_t t = fetch16(); push8080(pc); pc = t; return true; }   // CALL (DD FD undefined, as CALL)
            if (d == 6) { push8080((uint16_t)((a() << 8) | (psw & 0xFF))); return true; }   // PUSH PSW
            push8080(rp(d >> 1)); return true;              // PUSH B / D / H
        case 6: alu(d, fetch()); return true;               // ADI ACI SUI SBI ANI XRI ORI CPI
        default: push8080(pc); pc = (uint16_t)(d * 8); return true;   // RST n
        }
    }

    // ED escape (UM 12-176, 12-177): ED ED imm8 = CALLN, ED FD = RETEM; other second bytes: undefined (inferred: no
    // operation, both bytes consumed)
    bool step_ed() {
        uint8_t op2 = fetch();
        if (op2 == 0xED) {                                  // CALLN imm8: PSW (MD = 0), PS, PC to SS:SP, MD = 1
            uint8_t n = fetch();
            enter(n);
            psw |= F_MD;
            return true;
        }
        if (op2 == 0xFD) {                                  // RETEM: PC, PS, PSW from SS:SP, MD restored, write disable
            pc = npop(); s[PS] = npop();
            psw = psw_norm(npop());
            we = false;
            return true;
        }
        return true;
    }
};

}  // namespace v20e

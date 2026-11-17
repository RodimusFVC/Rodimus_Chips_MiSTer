// Discrete sound engine: instruction-set model of rtl/dsnd_engine.sv, one step() = one sample.
// Every op 0-33 (33 OUTR = right mix, out_r), NOISE b[2] = SN76477 lock-up guard. The reference for verify/ and
// for model-only renderers in the cores (include it from here, never copy it).
#pragma once
#include <cstdint>
#include <vector>

struct Dsnd {
    std::vector<uint64_t> prog = std::vector<uint64_t>(1024, 0);
    int32_t M[256] = {};
    int32_t acc = 0;
    int f = 0;
    uint32_t lfsr[4] = {1, 1, 1, 1};
    int16_t out = 0, out_r = 0;
    int last = 0;                                   // instructions executed in the latest sample
    int maxn = 0;                                   // most instructions executed in one sample

    static int32_t q24(__int128 p) { return (int32_t)(uint32_t)(uint64_t)(p >> 24); }

    // EXP: 2^a, Horner on the Q24 fraction with Q28 coefficients, then 2^(ip - 4)
    static int32_t exp2q(int32_t a)
    {
        static const int64_t C[6] = {268435436, 186066863, 64465738, 14985772, 2413057, 504005};
        if (a >= (7 << 24)) return 0x7FFFFFFF;
        if (a < -(24 << 24)) return 0;
        int ip = a >> 24; int64_t fr = a & 0xFFFFFF, p = C[5];
        for (int k = 4; k >= 0; k--) p = (int64_t)(int32_t)(C[k] + q24((__int128)p * fr));
        int sh = ip - 4;
        return sh >= 0 ? (int32_t)(p << sh) : (int32_t)(p >> -sh);
    }
    // RCP: 1 / d, D = |d| normalised to 0.5 .. 1 (Q24), seed 48/17 - 32/17 D, 3 Newton-Raphson steps
    static int32_t rcpq(int32_t d)
    {
        if (d == 0) return 0x7FFFFFFF;
        bool neg = d < 0; uint32_t m0 = neg ? 0u - (uint32_t)d : (uint32_t)d;
        int z = __builtin_clz(m0); uint32_t mn = m0 << z; int64_t D = mn >> 8;
        int64_t Y = (int32_t)(47370962 + q24((__int128)D * -31580641));
        for (int i = 0; i < 3; i++) {
            int32_t e = q24((__int128)D * Y);
            Y = q24((__int128)Y * (int32_t)(0x02000000 - e));
        }
        int sh = z - 8;
        if (sh < 0) { int32_t r = (int32_t)(Y >> -sh); return neg ? -r : r; }
        int64_t r = Y << sh;
        if (r > 0x7FFFFFFF) r = 0x7FFFFFFF;
        return neg ? -(int32_t)r : (int32_t)r;
    }

    void step(const uint8_t src[8])
    {
        auto bit = [&](uint8_t a, uint8_t b) { int s = (b >> 3) & 7; return ((src[s] >> (b & 7)) & 1) ^ (a & 1); };
        int32_t mix = 0, mix_r = 0; bool used_r = false;
        unsigned pc = 0;
        int n = 0;                                  // budget units used (EXP 4, RCP 5, others 1)
        while (n < 410) {
            uint64_t w = prog[pc & 1023];
            uint8_t op = w >> 56, a = w >> 48, b = w >> 40;
            int32_t imm = (int32_t)(uint32_t)w, m = M[a];
            pc = (pc + 1) & 1023;
            n += op == 31 ? 4 : op == 32 ? 5 : 1;
            switch (op) {
            case 0:  n -= 1; goto done;
            case 1:  acc = m; break;
            case 2:  acc = imm; break;
            case 3:  acc = (int32_t)((uint32_t)acc + (uint32_t)m); break;
            case 4:  acc = (int32_t)((uint32_t)acc - (uint32_t)m); break;
            case 5:  acc = (int32_t)((uint32_t)acc + (uint32_t)imm); break;
            case 6:  acc = q24((__int128)acc * imm); break;
            case 7:  acc = q24((__int128)acc * m); break;
            case 30: acc = (int32_t)((uint32_t)acc + (uint32_t)q24((__int128)m * imm)); break;
            case 8:  M[a] = acc; break;
            case 9:  if (f) M[a] = acc; break;
            case 28: if (!f) M[a] = acc; break;
            case 10: if (f) acc = imm; break;
            case 11: case 12: {
                int32_t k = op == 11 ? imm : M[b];
                acc = (int32_t)((uint32_t)m + (uint32_t)q24((__int128)((int64_t)acc - m) * k));
                M[a] = acc; break;
            }
            case 13: f = acc >= m; break;
            case 14: f = acc >= imm; break;
            case 15: if (acc < imm) acc = imm; break;
            case 16: if (acc > imm) acc = imm; break;
            case 17: f = bit(a, b); break;
            case 18: f = !f; break;
            case 19: { uint32_t &l = lfsr[b & 3]; int nb = ((l >> 28) ^ l) & 1;
                      if ((b & 4) && (l & 0x1000001Fu) == 0) nb = 1;   // b[2]: SN76477 lock-up guard
                      l = (l >> 1) | ((uint32_t)nb << 30); f = nb; break; }
            case 20: mix = (int32_t)((uint32_t)mix + (uint32_t)acc); break;
            case 33: mix_r = (int32_t)((uint32_t)mix_r + (uint32_t)acc); used_r = true; break;
            case 21: if (f) acc = m; break;
            case 22: if (f) pc = (pc + (uint32_t)imm) & 1023; break;
            case 23: if (!f) pc = (pc + (uint32_t)imm) & 1023; break;
            case 24: { int s = (b >> 3) & 7; acc = (int32_t)src[s] << 16; break; }
            case 29: { int s = (b >> 3) & 7; acc = (int32_t)((uint32_t)(src[s] & (imm & 0xFF)) << ((imm >> 8) & 31)); break; }
            case 25: if (acc < 0) acc = (int32_t)(0u - (uint32_t)acc); break;
            case 26: f = f & bit(a, b); break;
            case 27: f = f | bit(a, b); break;
            case 31: acc = exp2q(acc); break;
            case 32: acc = rcpq(acc); break;
            default: break;
            }
        }
        n -= 1;                                     // (budget exhausted: n counts the last instruction)
    done:
        last = n + 1;
        if (n + 1 > maxn) maxn = n + 1;
        auto sat = [](int32_t m) { int32_t o = m >> 9; return (int16_t)(o > 32767 ? 32767 : o < -32768 ? -32768 : o); };
        out = sat(mix);
        out_r = sat(used_r ? mix_r : mix);
    }
};

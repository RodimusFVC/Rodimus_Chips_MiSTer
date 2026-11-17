// Unit test for BATCH 8 2026-07-27 z8002.sv opcodes: 0x71 (LD rd,rs(rx)), 0x5D
// indexed (LDL addr(rx),RRs store), 0xB0 (DAB). Hand-assembled program, expected
// values derived directly from MAME's z8000ops.hxx semantics / z8000dab.h table
// (never hand-simulated -- see z8002_optest_expected.py for the independent
// mechanical cross-check of the DAB case).
//
// BATCH 16 2026-08-09 added Tests D/E/F: 0x5E JP cc,addr[(rd)] direct/indexed,
// taken/not-taken. Regression coverage for a real silent-wrong-target bug (the old
// decode ignored NIB2 entirely and S_JP never added R[idxr] for the indexed form) --
// see z8002.sv's `jpx` declaration comment for the full story. Expected values
// derived directly from z8000ops.hxx's Z5E_0000_cccc_addr / Z5E_ddN0_cccc_addr
// bodies (addr_add(addr,RW(dst)) before the cc test on the indexed form; not-taken
// leaves m_pc exactly where get_operand() advanced it, no jump).
#include <cstdio>
#include <cstdint>
#include <verilated.h>
#include "Vz8002_optest_tb.h"
#include "Vz8002_optest_tb_z8002_optest_tb.h"

static Vz8002_optest_tb *top;
static vluint64_t tickcount = 0;

static void tick() {
    top->clk = 0; top->eval();
    top->clk = 1; top->eval();
    tickcount++;
}

// mem[] is word-indexed (byte address >> 1) -- see z8002_optest_tb.sv.
static inline int W(int byte_addr) { return byte_addr >> 1; }

static uint16_t reg16(int n) {
    // dbg_regs = {R15,...,R0}, 16 bits each -- see z8002.sv:765. Verilator represents
    // a 256-bit wire as VlWide<8> (8 x 32-bit words), 2 registers per word.
    int word = n / 2;
    int lo = (n % 2) * 16;
    return (top->z8002_optest_tb->dbg_regs[word] >> lo) & 0xFFFF;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vz8002_optest_tb;

    for (int i = 0; i < 32768; i++) top->z8002_optest_tb->mem[i] = 0;

    // reset vectors
    top->z8002_optest_tb->mem[W(2)] = 0x0000;   // initial FCW: all flags clear, non-segmented
    top->z8002_optest_tb->mem[W(4)] = 0x0010;   // initial PC

    // ---- Test A: 0x71 LD rd,rs(rx) -- R1 = mem[R2+R3], R2=0x0100,R3=0x0000 ----
    uint16_t prog[] = {
        /*0x0010*/ 0x2102, 0x0100,   // LD R2,#0x0100
        /*0x0014*/ 0x2103, 0x0000,   // LD R3,#0x0000
        /*0x0018*/ 0x2101, 0x0000,   // LD R1,#0x0000
        /*0x001C*/ 0x7121, 0x0300,   // LD R1,R2(R3)  src=2,dst=1,idx=3 -> ea=R2+R3=0x100
        // ---- Test B: 0x5D indexed store -- mem[0x300]=R0(hi),mem[0x302]=R1(lo) ----
        /*0x0020*/ 0x2104, 0x0100,   // LD R4,#0x0100  (index reg)
        /*0x0024*/ 0x2100, 0x1234,   // LD R0,#0x1234  (RR0 hi)
        /*0x0028*/ 0x2101, 0x5678,   // LD R1,#0x5678  (RR0 lo)
        /*0x002C*/ 0x5D40, 0x0200,   // LDL 0x0200(R4),RR0  idxr=4,src=0 -> ea=0x200+0x100=0x300
        // ---- Test C: 0xB0 DAB -- R0 low byte 0x0A -> dab_rom[0x00A]=0x010 ----
        /*0x0030*/ 0x2100, 0x000A,   // LD R0,#0x000A  (rl0 = 0x0A, fcw still 0 from reset)
        /*0x0034*/ 0xB080,           // DAB rl0 (dst byte-reg-code 8 = rl0)
        /*0x0036*/ 0x8D08,           // CLR R0  (marker: never reached if we stop early enough;
                                      // harmless park instruction, not asserted on)

        // ==== BATCH 16 2026-08-09: JP cc,addr[(rd)] (0x5E) regression coverage --
        // MAME Z5E_0000_cccc_addr / Z5E_ddN0_cccc_addr. Added after the FIX for a real
        // silent-wrong-target bug: the old decode arm matched the WHOLE 0x5E00-0x5EFF
        // range with no NIB2 check, and S_JP's jump target never added R[idxr] for the
        // indexed form -- same failure class (silent WRONG, not a hang/trap) the whole
        // task's original motivating bug (CP-DIRECT-FIX) was. This is why it gets a real
        // test, not just a clean audit: a clean gap count cannot distinguish "correct"
        // from "wrong but accepted".
        //
        // Test D (direct, taken, cc=8 "always" per cc_true()): JP jumps straight to the
        // fetched addr word, no index. Poison instruction sits in the fallthrough path
        // (only reached if the jump silently failed to fire) so a regression there is
        // caught too, not just the indexed form.
        /*0x0038*/ 0x2105, 0x0000,   // LD R5,#0x0000
        /*0x003C*/ 0x5E08, 0x0044,   // JP #8,0x0044  (NIB2=0 direct, NIB3=8=cc always)
        /*0x0040*/ 0x2105, 0xDEAD,   // LD R5,#0xDEAD -- WRONG-path poison (fallthrough if
                                      // the jump silently didn't fire)
        /*0x0044*/ 0x2105, 0x1111,   // LD R5,#0x1111 -- correct target (TEST D checks this)

        // Test E (indexed, taken, cc=8): JP #8,0x0054(R6), R6=0x0010 -> true target =
        // 0x0054+0x0010 = 0x0064. The addr-alone (bug-reintroduced) target 0x0054 is
        // planted with its OWN poison instruction so a regression is caught by VALUE
        // (R7==0xDEAD), not just by "did something execute".
        /*0x0048*/ 0x2106, 0x0010,   // LD R6,#0x0010  (index value)
        /*0x004C*/ 0x2107, 0x0000,   // LD R7,#0x0000
        /*0x0050*/ 0x5E68, 0x0054,   // JP #8,0x0054(R6)  (NIB2=6=idx reg R6, NIB3=8=cc always)
        /*0x0054*/ 0x2107, 0xDEAD,   // LD R7,#0xDEAD -- WRONG target poison (addr alone,
                                      // ignoring +R[idxr] -- exactly the old bug)
        /*0x0058*/ 0x8D08,           // filler (CLR R0, harmless, never reached either way)
        /*0x005A*/ 0x8D08,
        /*0x005C*/ 0x8D08,
        /*0x005E*/ 0x8D08,
        /*0x0060*/ 0x8D08,
        /*0x0062*/ 0x8D08,
        /*0x0064*/ 0x2107, 0x2222,   // LD R7,#0x2222 -- correct target = 0x0054+R6
                                      // (TEST E checks this)

        // Test F (indexed, NOT taken, cc=0 "never"): confirms the false-condition path
        // still advances PC by exactly one operand word (2 bytes) with NO index applied
        // and NO jump at all -- the branch my fix touched (jpx ? R[idxr] : 0) must still
        // correctly skip the addend on this path. R6 is still 0x0010 from Test E.
        /*0x0068*/ 0x2108, 0x0000,   // LD R8,#0x0000
        /*0x006C*/ 0x5E60, 0x00AA,   // JP #0,0x00AA(R6)  (NIB2=6, NIB3=0=cc never) -- must NOT
                                      // jump anywhere (target would be 0x00AA+0x0010=0x00BA
                                      // if it wrongly fired)
        /*0x0070*/ 0x2108, 0x4444,   // LD R8,#0x4444 -- correct fallthrough (TEST F checks this)
    };
    for (size_t i = 0; i < sizeof(prog)/sizeof(prog[0]); i++)
        top->z8002_optest_tb->mem[W(0x0010) + i] = prog[i];
    // preload test A's source data
    top->z8002_optest_tb->mem[W(0x0100)] = 0xBEEF;

    top->reset_n = 0;
    for (int i = 0; i < 4; i++) tick();
    top->reset_n = 1;

    int retire_no = 0;
    bool pass_a = false, pass_b = false, pass_c = false, reached_end = false;
    bool pass_d = false, pass_e = false, pass_f = false;
    bool pass_timing = true;
    uint16_t prev_target = 0;
    unsigned long long prev_dispatch_cyc = 0;
    while (tickcount < 3000 && retire_no < 22) {
        tick();
        if (tickcount <= 250) {
            printf("cyc=%2llu addr=0x%04X din=0x%04X mreq=%d we=%d pc=0x%04X illegal=%d\n",
                   (unsigned long long)tickcount, top->addr_tap, top->din_tap, top->mreq_tap,
                   top->we_tap, top->dbg_pc, top->dbg_illegal);
        }
        if (top->cyc_count_tap == 1) {
            // cyc_count is reset to 1 on EXACTLY the cycle a new instruction dispatches
            // (z8002.sv's S_FETCH0 gate) -- true every single dispatch, unlike watching
            // target_cycles for a value CHANGE (which misses back-to-back instructions
            // that happen to share the same cycle count -- caught this the hard way).
            if (prev_dispatch_cyc != 0) {
                unsigned long long dispatch_delta = tickcount - prev_dispatch_cyc;
                bool ok = (dispatch_delta == prev_target);
                printf("  [DISPATCH] cyc=%4llu  dispatch-to-dispatch delta=%llu  prev instr's target_cycles=%u  -> %s\n",
                       (unsigned long long)tickcount, dispatch_delta, prev_target, ok ? "MATCH" : "MISMATCH");
                if (!ok) pass_timing = false;
            }
            prev_dispatch_cyc = tickcount;
            prev_target = top->target_cycles_tap;
        }
        if (top->dbg_retire) {
            retire_no++;
            uint16_t pc  = top->dbg_pc;
            uint16_t fcw = top->dbg_fcw;
            static unsigned long long prev_retire_cyc = 0;
            unsigned long long delta = prev_retire_cyc ? (tickcount - prev_retire_cyc) : 0;
            printf("[retire #%2d] cyc=%4llu (delta=%3llu) target_cycles=%3u pc=0x%04X fcw=0x%04X  R0=%04X R1=%04X R5=%04X R6=%04X R7=%04X R8=%04X\n",
                   retire_no, (unsigned long long)tickcount, delta, top->target_cycles_tap, pc, fcw,
                   reg16(0), reg16(1), reg16(5), reg16(6), reg16(7), reg16(8));
            prev_retire_cyc = tickcount;

            if (retire_no == 4) { // after "LD R1,R2(R3)"
                uint16_t r1 = reg16(1);
                pass_a = (r1 == 0xBEEF);
                printf("  TEST A (0x71 LD rd,rs(rx)): expect R1=0xBEEF, got R1=0x%04X -> %s\n",
                       r1, pass_a ? "PASS" : "FAIL");
            }
            if (retire_no == 8) { // after "LDL 0x0200(R4),RR0"
                uint16_t hi = top->z8002_optest_tb->mem[W(0x300)];
                uint16_t lo = top->z8002_optest_tb->mem[W(0x302)];
                pass_b = (hi == 0x1234 && lo == 0x5678);
                printf("  TEST B (0x5D indexed LDL store): expect mem[0x300]=0x1234,mem[0x302]=0x5678, got 0x%04X,0x%04X -> %s\n",
                       hi, lo, pass_b ? "PASS" : "FAIL");
            }
            if (retire_no == 10) { // after "DAB rl0"
                uint16_t r0 = reg16(0);
                bool c = (fcw & 0x0080) != 0;
                bool z = (fcw & 0x0040) != 0;
                bool s = (fcw & 0x0020) != 0;
                pass_c = ((r0 & 0xFF) == 0x10 && !c && !z && !s);
                printf("  TEST C (0xB0 DAB): expect R0 low byte=0x10,C=0,Z=0,S=0, got R0=0x%04X C=%d Z=%d S=%d -> %s\n",
                       r0, c, z, s, pass_c ? "PASS" : "FAIL");
            }
            // NOTE: retire counts here are +1 vs. a naive count-the-instructions tally --
            // the pre-existing "CLR R0" filler at 0x0036 (originally never reached because
            // the old test body `break`d right after Test C) now genuinely retires as
            // instruction #11 once the sim keeps running past Test C.
            if (retire_no == 14) { // after "LD R5,#0x1111" at the JP direct target (0x0044)
                uint16_t r5 = reg16(5);
                pass_d = (r5 == 0x1111);
                printf("  TEST D (0x5E JP cc,addr direct, taken): expect R5=0x1111 (0xDEAD means the jump"
                       " silently didn't fire), got R5=0x%04X -> %s\n", r5, pass_d ? "PASS" : "FAIL");
            }
            if (retire_no == 18) { // after the JP indexed target instruction
                uint16_t r7 = reg16(7);
                pass_e = (r7 == 0x2222);
                printf("  TEST E (0x5E JP cc,addr(rd) indexed, taken): expect R7=0x2222 (0xDEAD means the"
                       " FIX regressed -- jumped to addr alone, ignoring +R[idxr]), got R7=0x%04X -> %s\n",
                       r7, pass_e ? "PASS" : "FAIL");
            }
            if (retire_no == 21) { // after "LD R8,#0x4444" fallthrough (JP indexed, NOT taken)
                uint16_t r8 = reg16(8);
                pass_f = (r8 == 0x4444);
                printf("  TEST F (0x5E JP cc,addr(rd) indexed, NOT taken): expect R8=0x4444 (fallthrough,"
                       " no jump), got R8=0x%04X -> %s\n", r8, pass_f ? "PASS" : "FAIL");
                reached_end = true;
                break;
            }
        }
    }

    bool pass = reached_end && pass_a && pass_b && pass_c && pass_d && pass_e && pass_f && pass_timing;
    if (!reached_end)
        printf("\n*** SIMULATION STALLED: only reached retire #%d before cycle/retire budget"
               " ran out (never reached retire #10) ***\n", retire_no);
    printf(pass ? "\nAll tests PASSED.\n" : "\n*** ONE OR MORE TESTS FAILED ***\n");
    delete top;
    return pass ? 0 : 1;
}

// PHASE 1 BOOTSTRAP -- does the oracle deserve to be trusted?
//
// Runs the byte-identical program from verilator/z8002_optest/sim_main.cpp through
// MAME-on-the-shim and checks the SAME six expectations. Those expected values were
// derived by hand from z8000ops.hxx over two earlier sessions and are already
// HW-corroborated (tests D/E cover the 0x5E JP fix that went to silicon).
//
// If the oracle reproduces all six, then the parts of the shim that could silently
// corrupt everything downstream are known good:
//   * the m_regs union index macros (a wrong BYTE4_XOR_BE permutes every register),
//   * memory word indexing and big-endian byte order within the word,
//   * dispatch through MAME's own table.
// If it does NOT, the oracle is wrong and NOTHING built on top of it means anything.

#include "oracle.h"
#include "z8000_opinfo.h"

#include <cstdio>
#include <cstring>

static inline int W(int byte_addr) { return byte_addr >> 1; }

int main()
{
	z8002_oracle cpu;
	cpu.begin();

	shim_memory &mem = cpu.memory();
	mem.clear();

	// Same reset vectors the RTL testbench uses.
	mem.prog[W(2)] = 0x0000;    // FCW: flags clear, non-segmented
	mem.prog[W(4)] = 0x0010;    // PC

	static const uint16_t prog[] = {
		/*0x0010*/ 0x2102, 0x0100,   // LD R2,#0x0100
		/*0x0014*/ 0x2103, 0x0000,   // LD R3,#0x0000
		/*0x0018*/ 0x2101, 0x0000,   // LD R1,#0x0000
		/*0x001C*/ 0x7121, 0x0300,   // LD R1,R2(R3)
		/*0x0020*/ 0x2104, 0x0100,   // LD R4,#0x0100
		/*0x0024*/ 0x2100, 0x1234,   // LD R0,#0x1234
		/*0x0028*/ 0x2101, 0x5678,   // LD R1,#0x5678
		/*0x002C*/ 0x5D40, 0x0200,   // LDL 0x0200(R4),RR0
		/*0x0030*/ 0x2100, 0x000A,   // LD R0,#0x000A
		/*0x0034*/ 0xB080,           // DAB rl0
		/*0x0036*/ 0x8D08,           // CLR R0
		/*0x0038*/ 0x2105, 0x0000,   // LD R5,#0x0000
		/*0x003C*/ 0x5E08, 0x0044,   // JP #8,0x0044
		/*0x0040*/ 0x2105, 0xDEAD,   // poison (fallthrough)
		/*0x0044*/ 0x2105, 0x1111,   // correct target
		/*0x0048*/ 0x2106, 0x0010,   // LD R6,#0x0010
		/*0x004C*/ 0x2107, 0x0000,   // LD R7,#0x0000
		/*0x0050*/ 0x5E68, 0x0054,   // JP #8,0x0054(R6)
		/*0x0054*/ 0x2107, 0xDEAD,   // poison (addr without index)
		/*0x0058*/ 0x8D08,
		/*0x005A*/ 0x8D08,
		/*0x005C*/ 0x8D08,
		/*0x005E*/ 0x8D08,
		/*0x0060*/ 0x8D08,
		/*0x0062*/ 0x8D08,
		/*0x0064*/ 0x2107, 0x2222,   // correct target = 0x0054+R6
		/*0x0068*/ 0x2108, 0x0000,   // LD R8,#0x0000
		/*0x006C*/ 0x5E60, 0x00AA,   // JP #0,0x00AA(R6) -- never taken
		/*0x0070*/ 0x2108, 0x4444,   // correct fallthrough
	};
	for (size_t i = 0; i < sizeof(prog) / sizeof(prog[0]); i++)
		mem.prog[W(0x0010) + i] = prog[i];

	mem.prog[W(0x0100)] = 0xBEEF;   // test A source data

	// The RTL gets these from the reset vectors; the oracle is set explicitly.
	z8k_state st;
	memset(&st, 0, sizeof(st));
	st.pc  = mem.prog[W(4)];
	st.fcw = mem.prog[W(2)];
	cpu.set_state(st);

	bool pass_a = false, pass_b = false, pass_c = false;
	bool pass_d = false, pass_e = false, pass_f = false;

	for (int n = 1; n <= 21; n++) {
		uint16_t pc_before = st.pc;
		uint16_t opword    = mem.prog[(pc_before & 0xffff) >> 1];
		std::string text   = cpu.disasm(pc_before);

		int cycles = cpu.step();
		cpu.get_state(st);

		printf("[%2d] pc=0x%04X %-28s -> pc=0x%04X fcw=0x%04X cyc=%2d  "
		       "R0=%04X R1=%04X R5=%04X R6=%04X R7=%04X R8=%04X   (%s)\n",
		       n, pc_before, text.c_str(), st.pc, st.fcw, cycles,
		       st.r[0], st.r[1], st.r[5], st.r[6], st.r[7], st.r[8],
		       z8k_op(opword).name);

		if (n == 4) {
			pass_a = (st.r[1] == 0xBEEF);
			printf("  TEST A (0x71 LD rd,rs(rx)): expect R1=0xBEEF, got 0x%04X -> %s\n",
			       st.r[1], pass_a ? "PASS" : "FAIL");
		}
		if (n == 8) {
			uint16_t hi = mem.prog[W(0x300)], lo = mem.prog[W(0x302)];
			pass_b = (hi == 0x1234 && lo == 0x5678);
			printf("  TEST B (0x5D indexed LDL store): expect 0x1234,0x5678, got 0x%04X,0x%04X -> %s\n",
			       hi, lo, pass_b ? "PASS" : "FAIL");
		}
		if (n == 10) {
			bool c = (st.fcw & 0x0080) != 0, z = (st.fcw & 0x0040) != 0, s = (st.fcw & 0x0020) != 0;
			pass_c = ((st.r[0] & 0xFF) == 0x10 && !c && !z && !s);
			printf("  TEST C (0xB0 DAB): expect R0 low=0x10,C=0,Z=0,S=0, got R0=0x%04X C=%d Z=%d S=%d -> %s\n",
			       st.r[0], c, z, s, pass_c ? "PASS" : "FAIL");
		}
		if (n == 14) {
			pass_d = (st.r[5] == 0x1111);
			printf("  TEST D (0x5E JP direct, taken): expect R5=0x1111, got 0x%04X -> %s\n",
			       st.r[5], pass_d ? "PASS" : "FAIL");
		}
		if (n == 18) {
			pass_e = (st.r[7] == 0x2222);
			printf("  TEST E (0x5E JP indexed, taken): expect R7=0x2222, got 0x%04X -> %s\n",
			       st.r[7], pass_e ? "PASS" : "FAIL");
		}
		if (n == 21) {
			pass_f = (st.r[8] == 0x4444);
			printf("  TEST F (0x5E JP indexed, NOT taken): expect R8=0x4444, got 0x%04X -> %s\n",
			       st.r[8], pass_f ? "PASS" : "FAIL");
		}
	}

	bool pass = pass_a && pass_b && pass_c && pass_d && pass_e && pass_f;
	printf("\n%s\n", pass
	       ? "ORACLE BOOTSTRAP PASSED -- MAME-on-shim reproduces all six hand-derived cases."
	       : "*** ORACLE BOOTSTRAP FAILED -- do not build anything on this oracle ***");
	return pass ? 0 : 1;
}

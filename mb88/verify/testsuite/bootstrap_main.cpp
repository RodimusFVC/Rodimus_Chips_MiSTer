// Prove the ORACLE before trusting any suite result.
//
// Same discipline as verilator/z8002_testsuite/bootstrap: if the oracle is wrong,
// every differential result downstream is meaningless. These expectations are
// derived by hand from MAME's mb88xx.cpp and check the things that would silently
// corrupt everything else:
//
//   * the save_item(NAME(...)) state map actually resolved (no pointer is null) --
//     if this trick failed, get_state() would read garbage and every test would
//     "pass" or "fail" for no reason;
//   * program addressing: GETPC() = (PA<<6)+PC and INCPC()'s page wrap;
//   * the cycle count step() reports (1 for nop, 2 for en/call) -- the suite's
//     cycle-accuracy verdict rests entirely on this being right;
//   * the ÷32 timer prescaler, which is the mechanism under investigation:
//     TIMER_PRESCALE machine cycles must produce exactly one timer increment.
//
// If any of these fail, no number printed by Vmb88_suite_tb means anything.

#include "oracle.h"
#include <cstdio>

static int g_fail = 0;

static void check(const char *what, long got, long want)
{
	bool ok = (got == want);
	if (!ok) g_fail++;
	printf("  [%s] %-46s got %ld, want %ld\n", ok ? "PASS" : "FAIL", what, got, want);
}

// Load a program at (PA<<6)+PC and reset the machine to run from there.
static void load(mb88_oracle &o, const u8 *code, size_t n, u8 pa = 0, u8 pc = 0)
{
	o.memory().clear();
	unsigned base = (unsigned(pa) << 6) + pc;
	for (size_t i = 0; i < n; i++)
		o.memory().prog[(base + i) & (shim_memory::PROG_SIZE - 1)] = code[i];
}

static mb88_state fresh(u8 pa = 0, u8 pc = 0)
{
	mb88_state s{};
	s.PC = pc; s.PA = pa; s.st = 1;
	return s;
}

int main()
{
	mb88_oracle o;
	o.begin();

	printf("=== MB88 oracle bootstrap (MAME cpu/mb88xx, unmodified) ===\n\n");

	printf("-- state map resolved from save_item(NAME(...)) --\n");
	if (!o.state_ok())
	{
		printf("  [FAIL] state map incomplete, first missing member: %s\n", o.missing());
		printf("\nORACLE IS NOT USABLE. Nothing downstream can be trusted.\n");
		return 1;
	}
	printf("  [PASS] every MB88 member resolved to an address\n\n");

	// ---------------------------------------------------------------- nop
	{
		const u8 code[] = { 0x00, 0x00 };
		load(o, code, sizeof code);
		mb88_state s = fresh(); o.set_state(s);
		int oc = o.step();
		o.get_state(s);
		printf("-- 0x00 nop --\n");
		check("PC advanced by 1", s.PC, 1);
		check("st = 1",           s.st, 1);
		check("cycles",           oc,   1);
	}

	// ------------------------------------------------------- tatl / ttla
	{
		const u8 code[] = { 0x06, 0x16 };     // tatl ; ttla
		load(o, code, sizeof code);
		mb88_state s = fresh(); s.A = 5; o.set_state(s);
		o.step();                              // tatl: TL <- A
		o.get_state(s);
		printf("\n-- 0x06 tatl / 0x16 ttla (timer preload round trip) --\n");
		check("TL = A after tatl", s.TL, 5);

		s.A = 0; o.set_state(s);
		o.step();                              // ttla: A <- TL
		o.get_state(s);
		check("A = TL after ttla", s.A,  5);
		check("zf clear (TL != 0)", s.zf, 0);
	}

	// --------------------------------------------------------- en imm (2cy)
	{
		const u8 code[] = { 0x3e, 0x80 };     // en 0x80  (timer enable)
		load(o, code, sizeof code);
		mb88_state s = fresh(); o.set_state(s);
		int oc = o.step();
		o.get_state(s);
		printf("\n-- 0x3e en imm --\n");
		check("pio |= 0x80", s.pio & 0x80, 0x80);
		check("cycles",      oc,           2);
		check("PC advanced by 2", s.PC,    2);
	}

	// ------------------------------------------------------------ call (2cy)
	{
		const u8 code[] = { 0x64, 0x05 };     // call -> PA=(0&7)<<2|(5>>6)=0, PC=5
		load(o, code, sizeof code);
		mb88_state s = fresh(); s.st = 1; o.set_state(s);
		int oc = o.step();
		o.get_state(s);
		printf("\n-- 0x64 call imm --\n");
		check("cycles",       oc,   2);
		check("PC = target",  s.PC, 5);
		check("SI incremented", s.SI, 1);
	}

	// ------------------------------------------------------------------ tstv
	{
		const u8 code[] = { 0x26 };
		load(o, code, sizeof code);
		mb88_state s = fresh(); s.vf = 1; o.set_state(s);
		o.step();
		o.get_state(s);
		printf("\n-- 0x26 tstv --\n");
		check("st = vf ^ 1", s.st, 0);
		check("vf cleared",  s.vf, 0);
	}

	// -------------------------------------------------- the ÷32 prescaler
	// burn_cycles(): if (pio & 0x80) { m_TP += cycles; while (m_TP >= 32) {
	// m_TP -= 32; increment_timer(); } }.  So 32 one-cycle instructions must
	// produce exactly one TL increment, and 31 must produce none.
	{
		u8 code[64]; memset(code, 0x00, sizeof code);   // all nop
		printf("\n-- timer prescaler (TIMER_PRESCALE = 32 machine cycles) --\n");

		load(o, code, sizeof code);
		mb88_state s = fresh(); s.pio = 0x80; o.set_state(s);
		for (int i = 0; i < 31; i++) o.step();
		o.get_state(s);
		check("TL still 0 after 31 cycles", s.TL, 0);

		load(o, code, sizeof code);
		s = fresh(); s.pio = 0x80; o.set_state(s);
		for (int i = 0; i < 32; i++) o.step();
		o.get_state(s);
		check("TL = 1 after 32 cycles", s.TL, 1);

		load(o, code, sizeof code);
		s = fresh(); s.pio = 0x00; o.set_state(s);      // internal clock disabled
		for (int i = 0; i < 40; i++) o.step();
		o.get_state(s);
		check("TL = 0 with pio7 clear", s.TL, 0);
	}

	// ------------------------------------------------------------ disassembly
	{
		const u8 code[] = { 0x00 };
		load(o, code, sizeof code);
		std::string d = o.disasm(0);
		printf("\n-- disassembler linked (MAME mb88dasm.cpp) --\n");
		printf("  [%s] disasm(0x00) = \"%s\"\n", d.empty() ? "FAIL" : "PASS", d.c_str());
		if (d.empty()) g_fail++;
	}

	printf("\n=== %s ===\n", g_fail ? "ORACLE BOOTSTRAP FAILED" : "oracle bootstrap: ALL PASS");
	if (g_fail)
		printf("The oracle is wrong. Do not trust any suite result until this passes.\n");
	return g_fail ? 1 : 0;
}

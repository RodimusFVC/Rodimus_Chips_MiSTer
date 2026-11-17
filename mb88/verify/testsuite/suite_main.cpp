// MB88 differential test suite -- rtl/cpu/mb88_sv/mb88_core.sv vs MAME's
// UNMODIFIED cpu/mb88xx core.
//
// Bar: MAME parity. MAME runs Kangaroo and Pole Position correctly, so anything
// matching it architecturally cannot be our bug.
//
// Two verdicts are reported SEPARATELY and must not be conflated:
//
//   ARCHITECTURE -- A/X/Y/PC/PA/SP/SI/flags/TH/TL/SB/pio, data RAM, port writes.
//                   A mismatch here is a functional bug.
//   CYCLES       -- ce pulses the RTL consumed per instruction vs the cycles MAME
//                   charged (burn_cycles(oc), oc = 1 or 2). A mismatch here does
//                   not corrupt state, but it skews everything timed off the ÷32
//                   prescaler -- which is what a "timer runs out instantly" bug
//                   looks like. MAME's 2-cycle opcodes are 0x3d jpa, 0x3e en,
//                   0x3f dis, 0x60-0x67 call, 0x68-0x6f jpl.
//
// Everything is derived from (seed, opcode, ctx), so runs are reproducible and
// there is no corpus file to maintain.
//
// Run ./bootstrap FIRST. If the oracle is wrong nothing here means anything.

#include "Vmb88_suite_tb.h"
#include "Vmb88_suite_tb_mb88_suite_tb.h"
#include "verilated.h"
#include "oracle.h"

#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
#include <sys/stat.h>

static Vmb88_suite_tb *tb;
#define CORE (tb->mb88_suite_tb)

// ------------------------------------------------------------------- rng
static uint64_t splitmix64(uint64_t &x)
{
	uint64_t z = (x += 0x9E3779B97F4A7C15ULL);
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
	return z ^ (z >> 31);
}

struct test_ctx
{
	u8  prog[shim_memory::PROG_SIZE];
	u8  ram[shim_memory::DATA_SIZE];
	mb88_state st;
	u8  k;
	u8  r_in[4];
	int si;
	u8  p_init;
	u16 r_init;
	u8  so_init;
};

// Build a deterministic test image for (seed, opcode, ctx).
static test_ctx make_ctx(uint64_t seed, int opcode, int ctx)
{
	uint64_t s = seed ^ (uint64_t(opcode) << 32) ^ (uint64_t(ctx) << 48);
	splitmix64(s);

	test_ctx t{};
	// Filler is seeded random so 2-byte operands and any fallthrough vary.
	for (u32 i = 0; i < shim_memory::PROG_SIZE; i++) t.prog[i] = u8(splitmix64(s));
	t.prog[0] = u8(opcode);              // instruction under test at PA=0, PC=0

	for (u32 i = 0; i < shim_memory::DATA_SIZE; i++) t.ram[i] = u8(splitmix64(s)) & 0x0f;

	t.st.PC = 0; t.st.PA = 0;
	t.st.A = splitmix64(s) & 0x0f;
	t.st.X = splitmix64(s) & 0x0f;
	t.st.Y = splitmix64(s) & 0x0f;
	t.st.st = splitmix64(s) & 1;
	t.st.zf = splitmix64(s) & 1;
	t.st.cf = splitmix64(s) & 1;
	t.st.vf = splitmix64(s) & 1;
	t.st.sf = splitmix64(s) & 1;
	t.st.iflag = splitmix64(s) & 1;
	t.st.SI = splitmix64(s) & 3;
	for (int i = 0; i < 4; i++) t.st.SP[i] = u16(splitmix64(s) & 0xffff);
	t.st.TH = splitmix64(s) & 0x0f;
	t.st.TL = splitmix64(s) & 0x0f;
	t.st.SB = splitmix64(s) & 0x0f;
	t.st.SBcount = 0;
	t.st.TP = 0;
	t.st.ctr = 0;
	t.st.o_output = splitmix64(s) & 0xff;
	t.st.pending_irq = 0;      // interrupt entry is tested separately, not per-opcode
	t.st.in_irq = 0;

	// pio: bits 5:4 select the serial mode. pio_enable() fatalerrors on the
	// unsupported combination, so only the legal ones are generated (the shim
	// still catches the throw if MAME's rules change).
	u8 pio = u8(splitmix64(s));
	pio &= ~0x30;
	if (splitmix64(s) & 1) pio |= 0x20;      // 0x00 or 0x20 only
	t.st.pio = pio;

	t.k = splitmix64(s) & 0x0f;
	for (int i = 0; i < 4; i++) t.r_in[i] = splitmix64(s) & 0x0f;
	t.si = splitmix64(s) & 1;
	t.p_init  = splitmix64(s) & 0x0f;
	t.r_init  = u16(splitmix64(s) & 0xffff);
	t.so_init = splitmix64(s) & 1;
	return t;
}

// ------------------------------------------------------------------- RTL
static void rtl_clk()
{
	tb->clk = 0; tb->eval();
	tb->clk = 1; tb->eval();
}

static void rtl_load(const test_ctx &t)
{
	tb->reset_n = 0; tb->ce = 1; tb->ena_timer = 0;
	tb->k_in = t.k;
	tb->r_in = u16(t.r_in[0] | (t.r_in[1] << 4) | (t.r_in[2] << 8) | (t.r_in[3] << 12));
	tb->si_in = t.si; tb->irq_n = 1; tb->tc_in = 1;
	for (int i = 0; i < 4; i++) rtl_clk();
	tb->reset_n = 1;
	tb->eval();

	for (u32 i = 0; i < shim_memory::PROG_SIZE; i++) CORE->prog[i] = t.prog[i];
	for (u32 i = 0; i < shim_memory::DATA_SIZE; i++) CORE->mb88_i__DOT__ram[i] = t.ram[i];

	CORE->mb88_i__DOT__PC = t.st.PC;   CORE->mb88_i__DOT__PA = t.st.PA;
	CORE->mb88_i__DOT__A  = t.st.A;    CORE->mb88_i__DOT__X  = t.st.X;
	CORE->mb88_i__DOT__Y  = t.st.Y;
	CORE->mb88_i__DOT__st = t.st.st;   CORE->mb88_i__DOT__zf = t.st.zf;
	CORE->mb88_i__DOT__cf = t.st.cf;   CORE->mb88_i__DOT__vf = t.st.vf;
	CORE->mb88_i__DOT__sf = t.st.sf;   CORE->mb88_i__DOT__iflag = t.st.iflag;
	CORE->mb88_i__DOT__SI = t.st.SI;
	for (int i = 0; i < 4; i++) CORE->mb88_i__DOT__SP[i] = t.st.SP[i];
	CORE->mb88_i__DOT__TH = t.st.TH;   CORE->mb88_i__DOT__TL = t.st.TL;
	CORE->mb88_i__DOT__SB = t.st.SB;   CORE->mb88_i__DOT__pio = t.st.pio;
	CORE->mb88_i__DOT__o_out = t.st.o_output;   // == MAME m_o_output
	CORE->mb88_i__DOT__p_out = t.p_init;
	CORE->mb88_i__DOT__r_out = t.r_init;
	CORE->mb88_i__DOT__so_out = t.so_init;
	CORE->mb88_i__DOT__pending_irq = 0;
	CORE->mb88_i__DOT__in_irq = 0;
	CORE->mb88_i__DOT__state = 0;      // instruction-fetch state

	// The RTL reads its opcode combinationally as prog[prog_addr]. Verilator
	// does not mark that dirty when the prog array is poked from C++, so on the
	// first edge the core executed a STALE byte (observed: prog_data=00 => it
	// ran nop instead of the opcode under test, PC advanced, nothing else did).
	// Clocking once with ce=0 re-settles the combinational logic without
	// executing an instruction: the ce-gated block does not run, so all poked
	// state survives.
	// The core assigns iflag <= ~irq_n every clock, so a poked value is
	// overwritten. Drive the pin to match instead; MAME's m_if is set directly.
	tb->irq_n = t.st.iflag ? 0 : 1;

	tb->ce = 0; rtl_clk();          // re-settle prog_data, execute nothing
	tb->ce = 1; tb->eval();
}

// Run one instruction; return ce pulses consumed (0 => never retired).
static int rtl_step()
{
	for (int c = 1; c <= 32; c++)
	{
		rtl_clk();
		if (tb->retire_tap) return c;
	}
	return 0;
}

static void rtl_get(mb88_state &s, u8 ram[shim_memory::DATA_SIZE])
{
	s.PC = CORE->mb88_i__DOT__PC;  s.PA = CORE->mb88_i__DOT__PA;
	s.A  = CORE->mb88_i__DOT__A;   s.X  = CORE->mb88_i__DOT__X;
	s.Y  = CORE->mb88_i__DOT__Y;
	s.st = CORE->mb88_i__DOT__st;  s.zf = CORE->mb88_i__DOT__zf;
	s.cf = CORE->mb88_i__DOT__cf;  s.vf = CORE->mb88_i__DOT__vf;
	s.sf = CORE->mb88_i__DOT__sf;  s.iflag = CORE->mb88_i__DOT__iflag;
	s.SI = CORE->mb88_i__DOT__SI;
	for (int i = 0; i < 4; i++) s.SP[i] = CORE->mb88_i__DOT__SP[i];
	s.TH = CORE->mb88_i__DOT__TH;  s.TL = CORE->mb88_i__DOT__TL;
	s.SB = CORE->mb88_i__DOT__SB;  s.pio = CORE->mb88_i__DOT__pio;
	s.pending_irq = CORE->mb88_i__DOT__pending_irq;
	s.in_irq = CORE->mb88_i__DOT__in_irq;
	for (u32 i = 0; i < shim_memory::DATA_SIZE; i++) ram[i] = CORE->mb88_i__DOT__ram[i];
}

// ------------------------------------------------------------- comparison
struct diff_list { std::vector<std::string> v; };

static void cmp(diff_list &d, const char *what, long got, long want)
{
	if (got == want) return;
	char b[128];
	snprintf(b, sizeof b, "%-10s rtl=%ld mame=%ld", what, got, want);
	d.v.push_back(b);
}

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);

	uint64_t seed = 12345;
	int nctx = 8, begin = 0x00, end = 0xff, maxfail = 2;
	bool cycles_only = false;
	bool dbg = false;
	int  inject = -1;   // NEGATIVE CONTROL: corrupt this opcode's result on purpose
	bool timer_mode = false;
	bool tc_mode = false;
	bool irq_mode = false;

	for (int i = 1; i < argc; i++)
	{
		if (!strcmp(argv[i], "--ctx") && i + 1 < argc)        nctx  = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--seed") && i + 1 < argc)  seed  = strtoull(argv[++i], nullptr, 0);
		else if (!strcmp(argv[i], "--begin") && i + 1 < argc) begin = (int)strtoul(argv[++i], nullptr, 0);
		else if (!strcmp(argv[i], "--end") && i + 1 < argc)   end   = (int)strtoul(argv[++i], nullptr, 0);
		else if (!strcmp(argv[i], "--maxfail") && i + 1 < argc) maxfail = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--cycles-only"))           cycles_only = true;
		else if (!strcmp(argv[i], "--dbg")) dbg = true;
		else if (!strcmp(argv[i], "--inject") && i + 1 < argc) inject = (int)strtoul(argv[++i], nullptr, 0);
		else if (!strcmp(argv[i], "--timer")) timer_mode = true;
		else if (!strcmp(argv[i], "--tc")) tc_mode = true;
		else if (!strcmp(argv[i], "--irq")) irq_mode = true;
	}

	tb = new Vmb88_suite_tb;
	mb88_oracle oracle;
	oracle.begin();
	if (!oracle.state_ok())
	{
		printf("ORACLE STATE MAP INCOMPLETE (%s) -- run ./bootstrap\n", oracle.missing());
		return 1;
	}

	// -------------------------------------------------------------- IRQ mode
	// Interrupt ENTRY. This is where a correctly-ticking timer can still fail to
	// act, so it matters for Kangaroo's ape even though the timer itself matches.
	//
	// The two models order this DIFFERENTLY and that is the point of the test:
	//   MAME  processes pending IRQs at the END of burn_cycles, i.e. AFTER the
	//         instruction executed; pushes the post-instruction PC; burn_cycles(3).
	//   RTL   takes it in S_FETCH INSTEAD of executing; pushes the pre-instruction
	//         PC; costs 1 ce and does not retire.
	// Both execute the deferred instruction exactly once overall, so this is not
	// automatically a bug -- but the pushed PC, the cycle cost (which feeds the
	// ÷32 prescaler) and the ISR's view of state all differ. Reported, not judged.
	if (irq_mode)
	{
		printf("=== IRQ entry: MAME (after insn, 3 cycles) vs RTL (instead of insn, 1 ce) ===\n");
		printf("instruction under test is 0x04 tay (Y<=A), so 'ran' is visible in Y\n\n");
		struct { const char *name; u8 pend; u8 pio; u8 vec; } cases[] = {
			{ "external", 0x04, 0x04, 0x02 },
			{ "timer",    0x02, 0x02, 0x04 },
			{ "serial",   0x01, 0x01, 0x06 },
			{ "timer+ext (ext wins)", 0x06, 0x06, 0x02 },
			{ "pending but DISABLED", 0x02, 0x00, 0x00 },
		};
		for (auto &cs : cases)
		{
			test_ctx t = make_ctx(seed, 0x04, 0);
			for (u32 i = 0; i < shim_memory::PROG_SIZE; i++) t.prog[i] = 0x04;   // tay
			t.st.PC = 8; t.st.PA = 0; t.st.SI = 0; t.st.in_irq = 0;
			t.st.A = 0xA; t.st.Y = 0x5; t.st.pio = cs.pio; t.st.pending_irq = cs.pend;
			t.st.cf = 1; t.st.zf = 0; t.st.st = 1;
			for (int i = 0; i < 4; i++) t.st.SP[i] = 0;

			oracle.select();
			oracle.memory().clear();
			memcpy(oracle.memory().prog, t.prog, sizeof t.prog);
			oracle.set_state(t.st);
			int mcyc = oracle.step();
			mb88_state ms{}; oracle.get_state(ms);

			rtl_load(t);
			CORE->mb88_i__DOT__pending_irq = cs.pend;
			CORE->mb88_i__DOT__pio = cs.pio;
			CORE->mb88_i__DOT__in_irq = 0;
			tb->ce = 0; rtl_clk(); tb->ce = 1; tb->eval();
			// Run until the interrupt is actually taken. With IRQ-CYCLES-FIX the
			// instruction retires first and entry costs 3 more ce, so counting to
			// the first retire would under-report the cost.
			bool expect_irq = (cs.pend & cs.pio) != 0;
			int rcyc = 0; bool retired = false;
			for (int c = 1; c <= 12; c++) {
				rtl_clk(); rcyc = c;
				if (tb->retire_tap) retired = true;
				// entry is complete when the core is back in S_FETCH with in_irq set
				if (CORE->mb88_i__DOT__in_irq && CORE->mb88_i__DOT__state == 0) break;
				if (retired && !expect_irq) break;
			}
			mb88_state rs{}; u8 rram[shim_memory::DATA_SIZE];
			rtl_get(rs, rram);

			printf("  %-22s vector expect %02X\n", cs.name, cs.vec);
			printf("      MAME: PC=%02X PA=%02X SI=%d SP0=%04X in_irq=%d Y=%X pend=%X cyc=%d %s\n",
			       ms.PC, ms.PA, ms.SI, ms.SP[0], ms.in_irq, ms.Y, ms.pending_irq, mcyc,
			       ms.Y == 0xA ? "(tay RAN)" : "(tay deferred)");
			printf("      RTL : PC=%02X PA=%02X SI=%d SP0=%04X in_irq=%d Y=%X pend=%X ce =%d %s\n",
			       rs.PC, rs.PA, rs.SI, rs.SP[0], rs.in_irq, rs.Y, rs.pending_irq, rcyc,
			       rs.Y == 0xA ? "(tay RAN)" : "(tay deferred)");
			bool vec_ok = (rs.PC == ms.PC) && (rs.PA == ms.PA);
			printf("      vector %s | SP push %s | pending cleared %s\n\n",
			       vec_ok ? "MATCH" : "*** DIFFER ***",
			       rs.SP[0] == ms.SP[0] ? "MATCH" : "*** DIFFER ***",
			       rs.pending_irq == ms.pending_irq ? "MATCH" : "*** DIFFER ***");
		}
		delete tb;
		return 0;
	}

	// --------------------------------------------------------------- TC mode
	// The EXTERNAL-counter timer path: MAME increments on a FALLING TC edge gated
	// by pio bit 6 (mb88xx.cpp execute_set_input). This is the path namco_51xx.sv
	// actually uses -- it drives tc_n = ~vblank, so the 51xx's per-frame timer
	// lives or dies here. mb88_core detects the edge with a registered tc_in_d
	// OUTSIDE the ce gate, so this runs with ce=0 to isolate the timer from
	// instruction execution (MAME's set_input_line does not execute either).
	if (tc_mode)
	{
		printf("=== TC mode: external-counter timer, falling edge, gated by pio bit6 ===\n");
		long tfail = 0, tt = 0;
		for (int ctx = 0; ctx < nctx; ctx++)
		{
			for (u8 pio : { u8(0x40), u8(0x00) })          // enabled, then gated off
			{
				for (int edges : { 1, 2, 15, 16, 17, 255, 256 })
				{
					test_ctx t = make_ctx(seed, 0x00, ctx);
					for (u32 i = 0; i < shim_memory::PROG_SIZE; i++) t.prog[i] = 0x00;
					t.st.pio = pio;
					t.st.TH = 0; t.st.TL = 0; t.st.ctr = 1;   // TC starts high on both

					oracle.select();
					oracle.memory().clear();
					memcpy(oracle.memory().prog, t.prog, sizeof t.prog);
					oracle.set_state(t.st);
					for (int i = 0; i < edges; i++) { oracle.set_tc_line(1); oracle.set_tc_line(0); }
					mb88_state ms{}; oracle.get_state(ms);

					rtl_load(t);
					CORE->mb88_i__DOT__pio = pio;
					CORE->mb88_i__DOT__TH = 0; CORE->mb88_i__DOT__TL = 0;
					tb->ce = 0; tb->tc_in = 1; rtl_clk();      // normalise tc_in_d = 1
					for (int i = 0; i < edges; i++)
					{
						tb->tc_in = 1; rtl_clk();
						tb->tc_in = 0; rtl_clk();              // falling edge -> tick
					}
					tb->tc_in = 1; tb->ce = 1;
					mb88_state rs{}; u8 rram[shim_memory::DATA_SIZE];
					rtl_get(rs, rram);

					tt++;
					bool bad = (rs.TL != ms.TL) || (rs.TH != ms.TH) ||
					           (rs.vf != ms.vf) || (rs.pending_irq != ms.pending_irq);
					if (bad)
					{
						tfail++;
						printf("  pio=%02X ctx %d %4d edges: rtl TH=%X TL=%X vf=%d pend=%X | "
						       "mame TH=%X TL=%X vf=%d pend=%X   MISMATCH\n",
						       pio, ctx, edges, rs.TH, rs.TL, rs.vf, rs.pending_irq,
						       ms.TH, ms.TL, ms.vf, ms.pending_irq);
					}
					else if (ctx == 0)
						printf("  pio=%02X %4d edges: TH=%X TL=%X vf=%d pend=%X  (both)\n",
						       pio, edges, rs.TH, rs.TL, rs.vf, rs.pending_irq);
				}
			}
		}
		printf("TC tests %ld | fail %ld\n", tt, tfail);
		delete tb;
		return tfail ? 1 : 0;
	}

	// ------------------------------------------------------------ timer mode
	// Single-instruction tests never exercise the timer, which is the whole point
	// of this core for Kangaroo's ape and Pole Position's MCUs. MAME accumulates
	// m_TP += cycles and increments the timer every TIMER_PRESCALE(=32) MACHINE
	// CYCLES. mb88_core takes ena_timer ALREADY divided (mb88.sv generates one
	// pulse per 32 `ena`), so the harness reproduces that contract exactly and
	// compares the TL/TH cascade, the vf overflow flag and the timer IRQ.
	if (timer_mode)
	{
		printf("=== timer mode: internal clock, TIMER_PRESCALE=32 machine cycles ===\n");
		long tfail = 0, tt = 0;
		for (int ctx = 0; ctx < nctx; ctx++)
		{
			for (int ncyc : { 31, 32, 33, 64, 96, 512, 1024, 4095, 4096 })
			{
				test_ctx t = make_ctx(seed, 0x00, ctx);
				for (u32 i = 0; i < shim_memory::PROG_SIZE; i++) t.prog[i] = 0x00;  // all nop
				t.st.pio = 0x80;          // internal timer enable, no serial
				t.st.TP = 0;

				oracle.select();
				oracle.memory().clear();
				memcpy(oracle.memory().prog, t.prog, sizeof t.prog);
				memcpy(oracle.memory().data, t.ram, sizeof t.ram);
				oracle.set_state(t.st);
				for (int i = 0; i < ncyc; i++) oracle.step();   // nop = 1 cycle each
				mb88_state ms{}; oracle.get_state(ms);

				rtl_load(t);
				CORE->mb88_i__DOT__pio = 0x80; tb->eval();
				int tp = 0;
				for (int i = 0; i < ncyc; i++)
				{
					// mb88.sv: one ena_timer pulse per 32 ena (fires on the 32nd)
					tp++;
					tb->ena_timer = (tp == 32);
					if (tp == 32) tp = 0;
					rtl_clk();
				}
				tb->ena_timer = 0;
				mb88_state rs{}; u8 rram[shim_memory::DATA_SIZE];
				rtl_get(rs, rram);

				tt++;
				bool bad = (rs.TL != ms.TL) || (rs.TH != ms.TH) || (rs.vf != ms.vf);
				if (bad)
				{
					tfail++;
					printf("  ctx %d after %5d cycles: rtl TH=%X TL=%X vf=%d | mame TH=%X TL=%X vf=%d  MISMATCH\n",
					       ctx, ncyc, rs.TH, rs.TL, rs.vf, ms.TH, ms.TL, ms.vf);
				}
				else if (ctx == 0)
					printf("  after %5d cycles: TH=%X TL=%X vf=%d  (both)\n", ncyc, rs.TH, rs.TL, rs.vf);
			}
		}
		printf("timer tests %ld | fail %ld\n", tt, tfail);
		delete tb;
		return tfail ? 1 : 0;
	}

	mkdir("results", 0755);
	FILE *fsum = fopen("results/summary.txt", "w");
	FILE *ffail = fopen("results/failures.txt", "w");

	long tests = 0, arch_fail = 0, cyc_fail = 0, excluded = 0, noretire = 0;
	long arch_fail_op[256] = {0}, cyc_fail_op[256] = {0}, tested_op[256] = {0};
	int  rtl_cyc_seen[256][8] = {{0}}, mame_cyc_seen[256][8] = {{0}};
	int  shown[256] = {0};

	for (int op = begin; op <= end; op++)
	{
		for (int c = 0; c < nctx; c++)
		{
			test_ctx t = make_ctx(seed, op, c);

			// ---- oracle ----
			mb88_state ms{};
			int mcyc = 0;
			try
			{
				oracle.select();
				oracle.memory().clear();
				memcpy(oracle.memory().prog, t.prog, sizeof t.prog);
				memcpy(oracle.memory().data, t.ram, sizeof t.ram);
				oracle.ports().k = t.k;
				for (int i = 0; i < 4; i++) oracle.ports().r_in[i] = t.r_in[i];
				oracle.ports().si = t.si;
				oracle.set_state(t.st);
				mcyc = oracle.step();
				oracle.get_state(ms);
			}
			catch (const shim_fatal &)
			{
				excluded++;
				continue;
			}

			// ---- RTL ----
			rtl_load(t);
			if (dbg) {
				printf("[dbg] op=%02X ctx=%d  poked PC=%d PA=%d A=%X X=%X Y=%X st=%d\n",
				       op, c, t.st.PC, t.st.PA, t.st.A, t.st.X, t.st.Y, t.st.st);
				printf("      prog[0]=%02X  core.prog[0]=%02X  core PC=%d PA=%d A=%X Y=%X state=%d ce=%d rst=%d\n",
				       t.prog[0], CORE->prog[0], CORE->mb88_i__DOT__PC, CORE->mb88_i__DOT__PA,
				       CORE->mb88_i__DOT__A, CORE->mb88_i__DOT__Y,
				       CORE->mb88_i__DOT__state, tb->ce, tb->reset_n);
				printf("      core prog_data=%02X\n", CORE->mb88_i__DOT__prog_data);
			}
			int rcyc = rtl_step();
			mb88_state rs{};
			u8 rram[shim_memory::DATA_SIZE];
			rtl_get(rs, rram);
			// NEGATIVE CONTROL: a suite that cannot fail proves nothing. --inject
			// corrupts one opcode's RTL result so a green run can be distinguished
			// from a broken comparison path.
			if (inject >= 0 && op == inject) { rs.A ^= 0xf; CORE->mb88_i__DOT__o_out ^= 0xff;
			                                   CORE->mb88_i__DOT__p_out ^= 0xf; CORE->mb88_i__DOT__r_out ^= 0xffff; }
			if (dbg) printf("      after %d ce: PC=%d PA=%d A=%X Y=%X  | mame PC=%d A=%X Y=%X\n\n",
			                rcyc, rs.PC, rs.PA, rs.A, rs.Y, ms.PC, ms.A, ms.Y);

			tests++; tested_op[op]++;
			if (rcyc == 0) { noretire++; }
			if (rcyc >= 1 && rcyc <= 7) rtl_cyc_seen[op][rcyc]++;
			if (mcyc >= 1 && mcyc <= 7) mame_cyc_seen[op][mcyc]++;

			diff_list d;
			if (!cycles_only)
			{
				cmp(d, "PC",  rs.PC,  ms.PC);
				cmp(d, "PA",  rs.PA,  ms.PA);
				cmp(d, "A",   rs.A,   ms.A);
				cmp(d, "X",   rs.X,   ms.X);
				cmp(d, "Y",   rs.Y,   ms.Y);
				cmp(d, "st",  rs.st,  ms.st);
				cmp(d, "zf",  rs.zf,  ms.zf);
				cmp(d, "cf",  rs.cf,  ms.cf);
				cmp(d, "vf",  rs.vf,  ms.vf);
				cmp(d, "sf",  rs.sf,  ms.sf);
				cmp(d, "if",  rs.iflag, ms.iflag);
				cmp(d, "SI",  rs.SI,  ms.SI);
				cmp(d, "TH",  rs.TH,  ms.TH);
				cmp(d, "TL",  rs.TL,  ms.TL);
				cmp(d, "SB",  rs.SB,  ms.SB);
				cmp(d, "pio", rs.pio, ms.pio);
				cmp(d, "pend", rs.pending_irq, ms.pending_irq);
				cmp(d, "in_irq", rs.in_irq, ms.in_irq);
				for (int i = 0; i < 4; i++)
				{
					char nm[8]; snprintf(nm, sizeof nm, "SP%d", i);
					cmp(d, nm, rs.SP[i], ms.SP[i]);
				}
				// PORTS -- what the MCU hands back to the other chip. MAME has no
				// P/R latch (it just calls the devcb), so replay its write log onto
				// a shadow seeded identically to the RTL's latches.
				{
					u8  exp_o = ms.o_output;             // MAME's own m_o_output
					u8  exp_p = t.p_init;
					u16 exp_r = t.r_init;
					u8  exp_so = t.so_init;
					unsigned n_o = 0;
					const shim_ports &pp = oracle.ports();
					for (unsigned w = 0; w < pp.n_writes; w++)
					{
						const auto &wr = pp.writes[w];
						if (wr.kind == shim_ports::PORT_O) { exp_o = wr.val; n_o++; }
						else if (wr.kind == shim_ports::PORT_P) exp_p = wr.val & 0x0f;
						else if (wr.kind == shim_ports::PORT_R)
							exp_r = u16((exp_r & ~(0xf << (wr.idx * 4))) | ((wr.val & 0xf) << (wr.idx * 4)));
						else if (wr.kind == shim_ports::PORT_SO) exp_so = wr.val & 1;
					}
					cmp(d, "o_out",  CORE->mb88_i__DOT__o_out,  exp_o);
					cmp(d, "p_out",  CORE->mb88_i__DOT__p_out,  exp_p);
					cmp(d, "r_out",  CORE->mb88_i__DOT__r_out,  exp_r);
					cmp(d, "so_out", CORE->mb88_i__DOT__so_out, exp_so);
				}
				for (u32 i = 0; i < shim_memory::DATA_SIZE; i++)
					if (rram[i] != oracle.memory().data[i])
					{
						char b[96];
						snprintf(b, sizeof b, "ram[%02X]   rtl=%X mame=%X",
						         i, rram[i], oracle.memory().data[i]);
						d.v.push_back(b);
						break;
					}
			}

			bool cyc_bad = (rcyc != mcyc);
			if (!d.v.empty()) { arch_fail++; arch_fail_op[op]++; }
			if (cyc_bad)      { cyc_fail++;  cyc_fail_op[op]++; }

			if ((!d.v.empty() || cyc_bad) && shown[op] < maxfail)
			{
				shown[op]++;
				fprintf(ffail, "op %02X ctx %d   %s\n", op, c, oracle.disasm(0).c_str());
				if (cyc_bad) fprintf(ffail, "    CYCLES   rtl=%d mame=%d\n", rcyc, mcyc);
				for (auto &s : d.v) fprintf(ffail, "    %s\n", s.c_str());
				fprintf(ffail, "\n");
			}
		}
	}

	// ---------------------------------------------------------------- report
	fprintf(fsum, "MB88 differential suite -- rtl/cpu/mb88_sv/mb88_core.sv vs MAME cpu/mb88xx\n");
	fprintf(fsum, "seed=%llu ctx=%d opcodes %02X..%02X\n\n",
	        (unsigned long long)seed, nctx, begin, end);
	fprintf(fsum, "tests            : %ld\n", tests);
	fprintf(fsum, "excluded         : %ld  (pio serial value MAME fatalerrors on)\n", excluded);
	fprintf(fsum, "never retired    : %ld\n", noretire);
	fprintf(fsum, "ARCHITECTURE fail: %ld\n", arch_fail);
	fprintf(fsum, "CYCLE fail       : %ld\n\n", cyc_fail);

	fprintf(fsum, "--- cycle census: every opcode, ce pulses vs MAME burn_cycles ---\n");
	fprintf(fsum, "(MAME charges 2 for 0x3d jpa, 0x3e en, 0x3f dis, 0x60-0x67 call, 0x68-0x6f jpl; 1 otherwise)\n");
	{
		int n2 = 0;
		for (int op = 0; op < 256; op++)
		{
			if (!tested_op[op]) continue;
			char rc[32] = "", mc[32] = "";
			for (int k = 1; k < 8; k++) if (rtl_cyc_seen[op][k])  { char b[8]; snprintf(b,sizeof b,"%d",k); strcat(rc,b); }
			for (int k = 1; k < 8; k++) if (mame_cyc_seen[op][k]) { char b[8]; snprintf(b,sizeof b,"%d",k); strcat(mc,b); }
			if (strcmp(mc, "1") != 0)
			{
				fprintf(fsum, "  %02X rtl=%-4s mame=%-4s %s\n", op, rc, mc,
				        strcmp(rc, mc) ? "  <-- MISMATCH" : "");
				n2++;
			}
		}
		fprintf(fsum, "  (%d opcodes charge more than 1 cycle; all other opcodes are 1/1)\n\n", n2);
	}

	fprintf(fsum, "--- per-opcode (only opcodes with a failure) ---\n");
	fprintf(fsum, "%-5s %-7s %-7s %-7s %s\n", "op", "tested", "archF", "cycF", "rtl_cyc -> mame_cyc");
	for (int op = 0; op < 256; op++)
	{
		if (!arch_fail_op[op] && !cyc_fail_op[op]) continue;
		char rc[32] = "", mc[32] = "";
		for (int k = 1; k < 8; k++) if (rtl_cyc_seen[op][k])  { char b[8]; snprintf(b,sizeof b,"%d ",k); strcat(rc,b); }
		for (int k = 1; k < 8; k++) if (mame_cyc_seen[op][k]) { char b[8]; snprintf(b,sizeof b,"%d ",k); strcat(mc,b); }
		fprintf(fsum, "%02X    %-7ld %-7ld %-7ld %s-> %s\n",
		        op, tested_op[op], arch_fail_op[op], cyc_fail_op[op], rc, mc);
	}
	fclose(fsum); fclose(ffail);

	printf("tests %ld | ARCH fail %ld | CYCLE fail %ld | excluded %ld | never-retired %ld\n",
	       tests, arch_fail, cyc_fail, excluded, noretire);
	printf("results/summary.txt, results/failures.txt\n");

	delete tb;
	return 0;
}

// z8002 differential test suite -- RTL vs MAME, one instruction at a time.
//
// For every testable first word, N randomized contexts are run through BOTH
// rtl/cpu/z8002/z8002.sv and MAME's unmodified z8000 core from an IDENTICAL
// starting image, and the resulting architectural state is compared.
//
// WHAT IS COMPARED: R0-R15, PC, FCW, and the contents of every memory word either
// side wrote. NOT cycle counts -- cycle accuracy is a deliberately deferred pass
// for this core, and MAME's counts are not silicon-accurate anyway.
//
// HOW STATE IS SET UP (no RTL change, and no backdoor):
//   FCW comes from the reset vector at 0x0002, which both models honour, and the
//   16 registers are loaded by a 16-instruction `LD Rn,#imm16` preamble that BOTH
//   models execute. The state is then compared at the end of the preamble before
//   the instruction under test runs, so a setup divergence is reported as its own
//   outcome and never misattributed to the opcode being tested.
//
// REPEATING BLOCK INSTRUCTIONS: MAME implements these as one iteration per
// dispatch, rewinding PC by 4 to re-enter (z8000ops.hxx). Rather than assume the
// RTL does the same, both sides are run until PC LEAVES the instruction under
// test, which compares the architectural effect without assuming an implementation.

#include "oracle.h"
#include "z8000_opinfo.h"

#include <verilated.h>
#include "Vz8002_suite_tb.h"
#include "Vz8002_suite_tb_z8002_suite_tb.h"

#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <map>
#include <set>
#include <algorithm>
#include <unistd.h>

// ---------------------------------------------------------------- parameters

static constexpr uint16_t PRE_ADDR   = 0x0100;   // 16 x LD Rn,#imm16 = 64 bytes
static constexpr uint16_t TEST_ADDR  = 0x0140;   // instruction under test
static constexpr int      MEM_WORDS  = 0x8000;

static constexpr int PREAMBLE_INSNS  = 16;
static constexpr int SETUP_TICK_BUDGET = 4000;
static constexpr int TEST_TICK_BUDGET  = 20000;
static constexpr int MAX_REPEAT_ITERS  = 256;

// --------------------------------------------------------------------- prng

static inline uint64_t splitmix64(uint64_t &x)
{
	uint64_t z = (x += 0x9E3779B97F4A7C15ull);
	z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
	z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
	return z ^ (z >> 31);
}

// ------------------------------------------------------------------ verilator

static Vz8002_suite_tb *top;
static uint64_t tick_total = 0;

static inline void tick()
{
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	tick_total++;
}

static inline uint16_t rtl_reg(int n)
{
	// dbg_regs = {R15,...,R0}, 16 bits each; VlWide<8> => 2 registers per 32-bit word.
	int word = n / 2;
	int lo   = (n % 2) * 16;
	return (top->z8002_suite_tb->dbg_regs[word] >> lo) & 0xFFFF;
}

// -------------------------------------------------------------------- model

struct MemWrite { uint16_t addr; uint16_t data; };

struct Outcome
{
	enum Kind {
		PASS = 0,
		FAIL_STATE,
		FAIL_MEM,
		FAIL_TIMEOUT,
		FAIL_ILLEGAL,
		FAIL_SETUP,
		SKIP_INVALID,
		SKIP_EXCLUDED,
		SKIP_SELFLOOP,
		SKIP_MODECHANGE,
		SKIP_TRAP,
		SKIP_HALT,
		SKIP_ORACLE_DIVERGE,
		KIND_COUNT
	};
};

static const char *kind_name(int k)
{
	static const char *n[] = { "PASS", "FAIL_STATE", "FAIL_MEM", "FAIL_TIMEOUT",
	                           "FAIL_ILLEGAL", "FAIL_SETUP", "SKIP_INVALID",
	                           "SKIP_EXCLUDED", "SKIP_SELFLOOP", "SKIP_MODECHANGE",
	                           "SKIP_TRAP", "SKIP_HALT", "SKIP_ORACLE_DIVERGE" };
	return n[k];
}

// Instructions whose behaviour this harness cannot legitimately compare.
// I/O ops: the DUT wrapper has no I/O space (iorq is tapped but unmodelled), so
// the RTL would read/write program memory while the oracle uses a separate space.
// They need an I/O model in the testbench before they mean anything.
static bool excluded_mnemonic(const std::string &m)
{
	// Every Z8000 I/O instruction, including the self-repeating block forms.
	// The DUT wrapper has no I/O space (iorq is tapped but unmodelled), so the RTL
	// would transact against program memory while the oracle uses a separate space.
	// Comparing them would measure the harness, not the core. Lifting this needs an
	// I/O model in z8002_suite_tb.sv -- see the report's "not yet covered" section.
	static const std::set<std::string> excl = {
		"in",   "inb",   "ind",   "indb",   "indr",  "indrb",
		"ini",  "inib",  "inir",  "inirb",
		"out",  "outb",  "outd",  "outdb",  "otdr",  "otdrb",
		"outi", "outib", "otir",  "otirb",
		"sin",  "sinb",  "sind",  "sindb",  "sindr", "sindrb",
		"sini", "sinib", "sinir", "sinirb",
		"sout", "soutb", "soutd", "soutdb", "sotdr", "sotdrb",
		"souti","soutib","sotir", "sotirb",
	};
	return excl.count(m) != 0;
}

// Opcodes where the RTL and MAME deliberately disagree, verified against MAME's own
// sibling handlers. MAME IS THE EMULATOR THAT RUNS THIS GAME CORRECTLY, so a divergence
// is NOT automatically MAME being wrong -- it may be silicon behaviour the game depends
// on. These are skipped so the pass rate stays meaningful, documented at the decode site
// in z8002.sv, and left as a standing DECISION (replicate vs keep) -- never silently
// "fixed" in either direction. Each entry cites its evidence.
static bool oracle_defect(uint16_t op)
{
	// MULTL rqd,@rs (0x1810-0x18FF): Z18_ssN0_dddd does RL(src) -- a REGISTER read --
	// where every sibling indirect handler uses RDIR_L/RDIR_W (Z16 ADDL, Z1A DIVL,
	// Z19 MULT, Z1B DIV, Z14 LDL). MAME marks the line with its own "//@@@".
	// DECIDED 2026-08-20 (user): keep the architectural read -- see z8002.sv:2446.
	if ((op & 0xFF00) == 0x1800 && (op & 0x00F0) != 0) return true;

	// COMB @Rd (0x0C10-0x0CF0 step 16): Z0C_ddN0_0000 does GET_DST(OP0,NIB3), but
	// NIB3 is always 0 in that range, so MAME always complements @R0. Every sibling
	// (Z0C_ddN0_0010/0100/0110, Z0D_ddN0_0000) uses NIB2.
	if ((op & 0xFF0F) == 0x0C00 && (op & 0x00F0) != 0) return true;

	return false;
}

static std::string first_token(const std::string &s)
{
	size_t a = s.find_first_not_of(" \t");
	if (a == std::string::npos) return "";
	size_t b = s.find_first_of(" \t", a);
	return s.substr(a, (b == std::string::npos) ? std::string::npos : b - a);
}

// ------------------------------------------------------------ image building

struct TestImage
{
	uint16_t mem[MEM_WORDS];
	uint16_t r[16];
	uint16_t fcw;
};

static void build_image(uint16_t op, uint32_t ctx, uint64_t seed, TestImage &img)
{
	uint64_t st = seed ^ (uint64_t(op) << 32) ^ (uint64_t(ctx) * 0x100000001B3ull);
	splitmix64(st);

	for (int i = 0; i < MEM_WORDS; i++)
		img.mem[i] = uint16_t(splitmix64(st));

	for (int i = 0; i < 16; i++)
		img.r[i] = uint16_t(splitmix64(st));

	// System mode, non-segmented, interrupts disabled; only the arithmetic flags
	// (C Z S P/V DA H) vary. Keeping S/N fixed matters: MAME swaps in a shadow
	// stack pointer on a system/normal transition and the RTL is a documented
	// single-SP model, so a mode change would be a harness artefact, not a bug.
	img.fcw = 0x4000 | (uint16_t(splitmix64(st)) & 0x00FC);

	// Shift instructions (0xB2 byte / 0xB3 word) take a count that is only DEFINED
	// for magnitudes up to the operand width (8 / 16). A uniformly random count is
	// out of range ~97% of the time, and MAME's answer there is just whatever C's >>
	// does on a promoted int -- comparing it measures the host, not the core. The
	// count is therefore constrained to the architectural range so the family is
	// actually TESTED rather than skipped. Low nibble: &3==1 static imm8 in word 2,
	// &3==3 dynamic with the count register named by word 2 bits 11:8.
	if ((op & 0xFF00) == 0xB200 || (op & 0xFF00) == 0xB300) {
		const int width = ((op & 0xFF00) == 0xB200) ? 8 : 16;
		const uint16_t w2i = (TEST_ADDR + 2) >> 1;
		if ((op & 0x0003) == 0x0001) {
			// The handlers are named _imm8 but use GET_IMM16 -- the count is the WHOLE
			// second word, signed (negative = shift right). Masking only the low byte
			// leaves a huge out-of-range count that the disassembler does not show.
			int cnt = int(splitmix64(st) % (2 * width)) - width;         // -width..width-1
			if (cnt >= 0) cnt += 1;                                      // skip 0
			img.mem[w2i] = uint16_t(int16_t(cnt));
		} else if ((op & 0x0003) == 0x0003) {
			int cnt = int(splitmix64(st) % (2 * width + 1)) - width;     // -width..+width
			img.r[(img.mem[w2i] >> 8) & 0x0F] = uint16_t(int16_t(cnt));
		}
	}

	img.mem[0x0002 >> 1] = img.fcw;      // reset FCW
	img.mem[0x0004 >> 1] = PRE_ADDR;     // reset PC

	// 16 x LD Rn,#imm16
	uint16_t w = PRE_ADDR >> 1;
	for (int n = 0; n < 16; n++) {
		img.mem[w++] = 0x2100 | uint16_t(n);
		img.mem[w++] = img.r[n];
	}

	// Instruction under test; the following words stay random so that immediate /
	// address operands vary per context.
	img.mem[TEST_ADDR >> 1] = op;
}

// ------------------------------------------------------------------ runners

struct RunResult
{
	z8k_state state;
	std::vector<MemWrite> writes;
	bool timeout = false;
	bool illegal = false;
	bool trap_req = false;      // MAME queued an EPU/priv/syscall trap
	bool halted = false;
	int  iters = 0;
	int  cycles = 0;            // RTL ticks from first tick of the instruction to retire
	int  target = 0;            // the RTL's own lookup_cycles() value for this opcode
};

static bool run_oracle(z8002_oracle &cpu, const TestImage &img,
                       z8k_state &pre, RunResult &post)
{
	shim_memory &mem = cpu.memory();
	memcpy(mem.prog, img.mem, sizeof(img.mem));
	memset(mem.io, 0, sizeof(mem.io));
	mem.clear_writes();

	z8k_state st;
	memset(&st, 0, sizeof(st));
	st.pc  = PRE_ADDR;
	st.fcw = img.fcw;
	cpu.set_state(st);

	for (int i = 0; i < PREAMBLE_INSNS; i++)
		cpu.step();
	cpu.get_state(pre);
	if (pre.pc != TEST_ADDR)
		return false;                    // preamble did not land where expected

	post.writes.clear();
	for (post.iters = 0; post.iters < MAX_REPEAT_ITERS; post.iters++) {
		cpu.step();
		for (unsigned i = 0; i < mem.n_writes; i++)
			if (!mem.writes[i].is_io)
				post.writes.push_back({ uint16_t(mem.writes[i].addr), 0 });
		cpu.get_state(post.state);
		if (post.state.pc != TEST_ADDR) break;
	}
	if (post.iters >= MAX_REPEAT_ITERS) { post.timeout = true; return true; }

	// An instruction that queues a trap (EPU, privileged, syscall) or halts has no
	// comparable single-instruction result: MAME does not run the trap sequence until
	// the NEXT dispatch, so the architectural effect is not visible in this step.
	post.trap_req = (cpu.irq_req() != 0);
	post.halted   = cpu.halted();

	// Record the final contents (not the transaction) at each written address:
	// byte stores differ in width between a masked write and the RTL's RMW word.
	for (auto &wr : post.writes)
		wr.data = mem.prog[wr.addr >> 1];
	return true;
}

static bool run_rtl(const TestImage &img, z8k_state &pre, RunResult &post)
{
	for (int i = 0; i < MEM_WORDS; i++)
		top->z8002_suite_tb->mem[i] = img.mem[i];

	top->reset_n = 0;
	for (int i = 0; i < 4; i++) tick();
	top->reset_n = 1;

	// --- preamble ---------------------------------------------------------
	int retires = 0;
	int budget  = SETUP_TICK_BUDGET;
	while (retires < PREAMBLE_INSNS && budget-- > 0) {
		tick();
		if (top->dbg_illegal) { post.illegal = true; return false; }
		if (top->dbg_retire) retires++;
	}
	if (retires < PREAMBLE_INSNS) return false;

	for (int i = 0; i < 16; i++) pre.r[i] = rtl_reg(i);
	pre.pc      = top->dbg_pc;
	pre.fcw     = top->dbg_fcw;
	pre.nspoff  = 0;
	pre.psapoff = 0;
	if (pre.pc != TEST_ADDR) return false;

	// --- instruction under test ------------------------------------------
	post.writes.clear();
	budget = TEST_TICK_BUDGET;
	bool done = false;
	uint64_t t0 = tick_total;
	while (budget-- > 0) {
		tick();
		if (top->we_tap && top->mreq_tap)
			post.writes.push_back({ uint16_t(top->addr_tap & 0xFFFE), 0 });
		if (top->dbg_illegal) post.illegal = true;
		if (top->dbg_retire) {
			post.iters++;
			if (top->dbg_pc != TEST_ADDR) { done = true; break; }
			if (post.iters >= MAX_REPEAT_ITERS) break;
		}
	}
	post.cycles = int(tick_total - t0);
	post.target = top->target_cycles_tap;
	if (!done) { post.timeout = true; return true; }

	for (int i = 0; i < 16; i++) post.state.r[i] = rtl_reg(i);
	post.state.pc      = top->dbg_pc;
	post.state.fcw     = top->dbg_fcw;
	post.state.nspoff  = 0;
	post.state.psapoff = 0;

	for (auto &wr : post.writes)
		wr.data = top->z8002_suite_tb->mem[wr.addr >> 1];
	return true;
}

// ---------------------------------------------------------------- comparison

struct Failure
{
	uint16_t op;
	uint32_t ctx;
	int kind;
	std::string text;
};

static std::string describe_state_diff(const z8k_state &o, const z8k_state &r)
{
	char buf[256];
	std::string s;
	if (o.pc != r.pc) {
		snprintf(buf, sizeof(buf), "  PC  mame=%04X rtl=%04X\n", o.pc, r.pc);
		s += buf;
	}
	if (o.fcw != r.fcw) {
		snprintf(buf, sizeof(buf), "  FCW mame=%04X rtl=%04X (diff %04X)\n",
		         o.fcw, r.fcw, uint16_t(o.fcw ^ r.fcw));
		s += buf;
	}
	for (int i = 0; i < 16; i++)
		if (o.r[i] != r.r[i]) {
			snprintf(buf, sizeof(buf), "  R%-2d mame=%04X rtl=%04X\n", i, o.r[i], r.r[i]);
			s += buf;
		}
	return s;
}

// Compare the FINAL CONTENT of every address either side touched.
static bool compare_memory(const RunResult &o, const RunResult &r,
                           const TestImage &img, std::string &detail)
{
	std::map<uint16_t, uint16_t> om, rm;
	for (auto &w : o.writes) om[w.addr] = w.data;
	for (auto &w : r.writes) rm[w.addr] = w.data;

	std::vector<uint16_t> addrs;
	for (auto &kv : om) addrs.push_back(kv.first);
	for (auto &kv : rm) addrs.push_back(kv.first);
	std::sort(addrs.begin(), addrs.end());
	addrs.erase(std::unique(addrs.begin(), addrs.end()), addrs.end());

	bool ok = true;
	char buf[192];
	for (uint16_t a : addrs) {
		uint16_t before = img.mem[a >> 1];
		uint16_t ov = om.count(a) ? om[a] : before;
		uint16_t rv = rm.count(a) ? rm[a] : before;
		if (ov != rv) {
			ok = false;
			snprintf(buf, sizeof(buf),
			         "  mem[%04X] was=%04X mame=%04X rtl=%04X%s%s\n",
			         a, before, ov, rv,
			         om.count(a) ? "" : " (mame did not write)",
			         rm.count(a) ? "" : " (rtl did not write)");
			detail += buf;
		}
	}
	return ok;
}

// --------------------------------------------------------------------- main

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);

	uint32_t n_ctx     = 4;
	uint64_t seed      = 0xC0FFEE1234ull;
	uint32_t op_begin  = 0x0000;
	uint32_t op_end    = 0xFFFF;
	size_t   max_fail_records = 400;
	const char *cycles_path   = nullptr;
	const char *report_path   = "results/summary.txt";
	const char *fail_path     = "results/failures.txt";

	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { return (i + 1 < argc) ? strtoull(argv[++i], nullptr, 0) : 0ull; };
		if      (a == "--ctx")   n_ctx    = uint32_t(next());
		else if (a == "--seed")  seed     = next();
		else if (a == "--begin") op_begin = uint32_t(next());
		else if (a == "--end")   op_end   = uint32_t(next());
		else if (a == "--maxfail") max_fail_records = size_t(next());
		else if (a == "--dumpcycles") cycles_path = (i + 1 < argc) ? argv[++i] : nullptr;
	}

	// z8000ops.hxx:2550/4666 printf() straight to stdout on any LDPS that flips
	// F_SEG. MAME's sources are used unmodified, so stdout is parked on /dev/null
	// for the duration of the run and restored before the summary is printed.
	int saved_stdout = dup(fileno(stdout));
	{ FILE *null_out = freopen("/dev/null", "w", stdout); (void)null_out; }

	top = new Vz8002_suite_tb;

	z8002_oracle cpu;
	cpu.begin();

	std::vector<Failure> failures;
	std::map<std::string, int> fail_samples;
	long counts[Outcome::KIND_COUNT] = { 0 };

	struct HandlerStat { long pass = 0, fail = 0, skip = 0; };
	std::map<std::string, HandlerStat> by_handler;

	TestImage img;
	long tested = 0;
	FILE *cyc_f = cycles_path ? fopen(cycles_path, "w") : nullptr;

	for (uint32_t op = op_begin; op <= op_end; op++) {
		const z8k_opinfo &info = z8k_op(uint16_t(op));
		bool invalid = (strcmp(info.name, "zinvalid") == 0);

		for (uint32_t ctx = 0; ctx < n_ctx; ctx++) {
			int kind = Outcome::PASS;
			std::string detail;

			if (invalid) {
				kind = Outcome::SKIP_INVALID;
				counts[kind]++;
				break;               // no need to repeat per context
			}

			build_image(uint16_t(op), ctx, seed, img);

			// Mnemonic is only needed for the exclusion test and failure text.
			memcpy(cpu.memory().prog, img.mem, sizeof(img.mem));
			std::string text = cpu.disasm(TEST_ADDR);
			std::string mnem = first_token(text);

			if (oracle_defect(uint16_t(op))) {
				kind = Outcome::SKIP_ORACLE_DIVERGE;
				counts[kind]++;
				by_handler[info.name].skip++;
				continue;
			}

			if (excluded_mnemonic(mnem)) {
				kind = Outcome::SKIP_EXCLUDED;
				counts[kind]++;
				by_handler[info.name].skip++;
				break;
			}

			z8k_state opre, rpre;
			RunResult opost, rpost;

			if (!run_oracle(cpu, img, opre, opost)) {
				kind = Outcome::FAIL_SETUP;
				detail = "  oracle preamble did not reach TEST_ADDR\n";
			} else if (opost.timeout) {
				kind = Outcome::SKIP_SELFLOOP;
			} else if (opost.trap_req) {
				kind = Outcome::SKIP_TRAP;
			} else if (opost.halted) {
				kind = Outcome::SKIP_HALT;
			} else if (!run_rtl(img, rpre, rpost)) {
				kind = rpost.illegal ? Outcome::FAIL_ILLEGAL : Outcome::FAIL_SETUP;
				detail = rpost.illegal
				       ? "  RTL asserted dbg_illegal during the preamble\n"
				       : "  RTL preamble did not complete / landed off TEST_ADDR\n";
				detail += describe_state_diff(opre, rpre);
			} else if (memcmp(opre.r, rpre.r, sizeof(opre.r)) != 0
			           || opre.pc != rpre.pc || opre.fcw != rpre.fcw) {
				kind = Outcome::FAIL_SETUP;
				detail = "  state diverged BEFORE the instruction under test:\n"
				       + describe_state_diff(opre, rpre);
			} else if (rpost.timeout) {
				kind = Outcome::FAIL_TIMEOUT;
				detail = "  RTL never left the instruction under test\n";
			} else if (((opost.state.fcw ^ img.fcw) & 0xC000) != 0) {
				kind = Outcome::SKIP_MODECHANGE;
			} else {
				bool state_ok = (memcmp(opost.state.r, rpost.state.r, sizeof(opost.state.r)) == 0)
				              && opost.state.pc == rpost.state.pc
				              && opost.state.fcw == rpost.state.fcw;
				std::string mem_detail;
				bool mem_ok = compare_memory(opost, rpost, img, mem_detail);

				if (!state_ok) {
					kind = Outcome::FAIL_STATE;
					detail = describe_state_diff(opost.state, rpost.state) + mem_detail;
				} else if (!mem_ok) {
					kind = Outcome::FAIL_MEM;
					detail = mem_detail;
				}
			}

			counts[kind]++;
			tested++;
			if (cyc_f && rpost.cycles > 0)
				fprintf(cyc_f, "%04X %u %d %d %d\n", op, ctx, rpost.cycles,
				        rpost.target, int(z8k_op(uint16_t(op)).cycles));

			if (kind == Outcome::PASS) {
				by_handler[info.name].pass++;
			} else if (kind == Outcome::SKIP_SELFLOOP || kind == Outcome::SKIP_MODECHANGE
			           || kind == Outcome::SKIP_TRAP || kind == Outcome::SKIP_HALT
			           || kind == Outcome::SKIP_ORACLE_DIVERGE) {
				by_handler[info.name].skip++;
			} else {
				by_handler[info.name].fail++;
				// Sample per handler, not first-N overall: a global cap fills up
				// with whatever opcode sorts first and hides every other cluster.
				if (fail_samples[info.name]++ < 2 && failures.size() < max_fail_records) {
					char hdr[512];
					snprintf(hdr, sizeof(hdr),
					         "op=%04X ctx=%u  %-30s [%s]  %s\n"
					         "  words: %04X %04X %04X   fcw_in=%04X\n",
					         op, ctx, text.c_str(), info.name, kind_name(kind),
					         img.mem[TEST_ADDR >> 1], img.mem[(TEST_ADDR >> 1) + 1],
					         img.mem[(TEST_ADDR >> 1) + 2], img.fcw);
					std::string pre = "  regs_in:";
					for (int i = 0; i < 16; i++) {
						char rb[24];
						snprintf(rb, sizeof(rb), " %04X", img.r[i]);
						pre += rb;
					}
					pre += "\n";
					failures.push_back({ uint16_t(op), ctx, kind, std::string(hdr) + pre + detail });
				}
			}
		}

		if ((op & 0x03FF) == 0)
			fprintf(stderr, "\r  op %04X  tested=%ld pass=%ld fail=%ld ",
			        op, tested, counts[Outcome::PASS],
			        counts[Outcome::FAIL_STATE] + counts[Outcome::FAIL_MEM]
			        + counts[Outcome::FAIL_TIMEOUT] + counts[Outcome::FAIL_ILLEGAL]
			        + counts[Outcome::FAIL_SETUP]);
	}
	fprintf(stderr, "\n");

	// ------------------------------------------------------------- reporting
	fflush(stdout);
	dup2(saved_stdout, fileno(stdout));
	close(saved_stdout);
	clearerr(stdout);

	if (system("mkdir -p results") != 0) { fprintf(stderr, "mkdir results failed\n"); return 2; }

	FILE *f = fopen(report_path, "w");
	FILE *ff = fopen(fail_path, "w");
	if (!f || !ff) { fprintf(stderr, "cannot write results/\n"); return 2; }

	long total_fail = counts[Outcome::FAIL_STATE] + counts[Outcome::FAIL_MEM]
	                + counts[Outcome::FAIL_TIMEOUT] + counts[Outcome::FAIL_ILLEGAL]
	                + counts[Outcome::FAIL_SETUP];

	fprintf(f, "z8002 differential test suite -- RTL vs MAME\n");
	fprintf(f, "seed=0x%llX contexts/opcode=%u opcode range=%04X..%04X\n",
	        (unsigned long long)seed, n_ctx, op_begin, op_end);
	fprintf(f, "verilator ticks executed: %llu\n\n", (unsigned long long)tick_total);
	for (int k = 0; k < Outcome::KIND_COUNT; k++)
		fprintf(f, "  %-16s %8ld\n", kind_name(k), counts[k]);
	fprintf(f, "\n  %-16s %8ld\n", "TOTAL FAIL", total_fail);
	fprintf(f, "  %-16s %8.4f%%\n", "pass rate",
	        tested ? 100.0 * counts[Outcome::PASS] / double(tested) : 0.0);

	fprintf(f, "\n--- per-handler results (failing handlers first) ---\n");
	std::vector<std::pair<std::string, HandlerStat>> hs(by_handler.begin(), by_handler.end());
	std::sort(hs.begin(), hs.end(), [](auto &a, auto &b) {
		if (a.second.fail != b.second.fail) return a.second.fail > b.second.fail;
		return a.first < b.first;
	});
	for (auto &h : hs)
		fprintf(f, "  %-42s pass=%-7ld fail=%-7ld skip=%ld\n",
		        h.first.c_str(), h.second.pass, h.second.fail, h.second.skip);

	for (auto &fl : failures)
		fprintf(ff, "%s\n", fl.text.c_str());

	fclose(f);
	fclose(ff);
	if (cyc_f) fclose(cyc_f);

	printf("\n");
	for (int k = 0; k < Outcome::KIND_COUNT; k++)
		if (counts[k]) printf("  %-16s %8ld\n", kind_name(k), counts[k]);
	printf("\n  TOTAL FAIL %ld / %ld tested\n", total_fail, tested);
	printf("  report:   %s\n  failures: %s (%zu recorded)\n",
	       report_path, fail_path, failures.size());

	delete top;
	return total_fail ? 1 : 0;
}

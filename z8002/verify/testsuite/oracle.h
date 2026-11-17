// z8002 execution oracle -- MAME's unmodified cpu/z8000 core, driven directly.
//
// This exists because every expected value in verilator/z8002_optest was derived
// by HAND-READING z8000ops.hxx. That does not scale past a few opcodes and is the
// exact method the vault warns against. Here MAME's own code computes the expected
// result, so the bar is "matches the emulator that runs this game correctly".
//
// Bar and scope:
//   * ARCHITECTURAL state only -- R0-R15, PC, FCW, and the memory writes performed.
//     Cycle counts are NOT the contract (cycle accuracy is a deliberately deferred
//     final pass for this core), though step() returns MAME's count for reference.
//   * MAME's zinvalid handler is a silent no-op that only logs, so opcodes that
//     decode to it have NO defined behaviour to compare against. They are excluded
//     here and covered separately by the existing decode audit in z8002_audit/.

#ifndef Z8002_ORACLE_H
#define Z8002_ORACLE_H

#include "emu.h"
#include "z8000.h"

struct z8k_state
{
	uint16_t r[16];
	uint16_t pc;
	uint16_t fcw;
	uint16_t nspoff;    // shadow stack pointer, swapped by CHANGE_FCW on S/N change
	uint16_t psapoff;   // program status area pointer (trap/interrupt vector base)
};

class z8002_oracle : public z8002_device
{
public:
	z8002_oracle();

	// Must be called once before any step().
	void begin();

	shim_memory &memory() { return *shim_mem(); }

	void set_state(const z8k_state &s);
	void get_state(z8k_state &s) const;

	// Execute exactly one dispatch and return the cycles MAME charged for it.
	// NOTE: MAME implements the repeating block instructions as one iteration per
	// dispatch, rewinding PC by 4 to re-enter; so a repeating op needs one step()
	// per iteration, not one step() total.
	int step();

	bool     halted()  const { return m_halt; }
	uint8_t  irq_req() const { return m_irq_req; }

	// Disassemble one instruction out of the oracle's own program memory.
	std::string disasm(uint16_t pc);

private:
	shim_memory m_mem;
};

#endif // Z8002_ORACLE_H

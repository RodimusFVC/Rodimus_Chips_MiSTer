// MB88xx execution oracle -- MAME's UNMODIFIED cpu/mb88xx core, driven directly.
//
// Bar: MAME parity. MAME runs Kangaroo and Pole Position correctly, so anything
// that matches it architecturally cannot be our bug. This does not claim silicon
// accuracy -- note MAME's own "TIMER_PRESCALE 32 /* guess */" (mb88xx.cpp:35).
//
// Device: MB8841 (11-bit program, 7-bit data = 128 nibbles), which is the shape
// rtl/cpu/mb88_sv/mb88_core.sv implements (prog_addr[10:0], 128-nibble dbg_ram)
// and the part Kangaroo uses. The 51xx/53xx/54xx are MB8843/8842 (10-bit program,
// 6-bit data); their opcode behaviour is identical, only the address widths differ,
// and tests are generated inside the smaller space so results carry over.
//
// State access: every MB88 member is private in mb88xx.h, but device_start() calls
// save_item(NAME(...)) on all of them and the shim captures name -> address from
// that (see mame_shim/emu.h). So the oracle reads and writes the real members with
// no `#define private public` hack and no ODR violation.

#ifndef MB88_ORACLE_H
#define MB88_ORACLE_H

#include "emu.h"
#include "mb88xx.h"

struct mb88_state
{
	u8  PC, PA, SI, A, X, Y;
	u16 SP[4];
	u8  st, zf, cf, vf, sf, iflag;
	u8  pio, TH, TL, TP, ctr, SB;
	u16 SBcount;
	u8  o_output, pending_irq;
	u8  in_irq;
};

class mb88_oracle : public mb8841_cpu_device
{
public:
	mb88_oracle();

	// Must be called once before any step(). Resolves the state map.
	void begin();

	shim_memory &memory() { return *shim_mem(); }
	shim_ports  &ports()  { return m_ports; }

	// Make this oracle's port context the active one (the shim devcbs consult it).
	void select() { shim_port_ctx() = &m_ports; }

	void set_state(const mb88_state &s);
	void get_state(mb88_state &s) const;

	// Execute exactly one instruction; returns the cycles MAME charged (1 or 2).
	int step();

	// Raise/lower the external pins between tests.
	void set_irq_line(int state);
	void set_tc_line(int state);

	std::string disasm(u16 pc);

	bool state_ok() const { return m_ok; }
	const char *missing() const { return m_missing; }

private:
	template <typename T> T *find(const char *n)
	{
		void *p = shim_find(n);
		if (!p && !m_missing) { m_missing = n; m_ok = false; }
		return static_cast<T *>(p);
	}

	shim_memory m_mem;
	shim_ports  m_ports;

	// resolved pointers into the real device members
	u8  *p_PC = nullptr, *p_PA = nullptr, *p_SI = nullptr, *p_A = nullptr, *p_X = nullptr, *p_Y = nullptr;
	u16 *p_SP = nullptr;
	u8  *p_st = nullptr, *p_zf = nullptr, *p_cf = nullptr, *p_vf = nullptr, *p_sf = nullptr, *p_if = nullptr;
	u8  *p_pio = nullptr, *p_TH = nullptr, *p_TL = nullptr, *p_TP = nullptr, *p_ctr = nullptr, *p_SB = nullptr;
	u16 *p_SBcount = nullptr;
	u8  *p_o_output = nullptr, *p_pending_irq = nullptr;
	bool *p_in_irq = nullptr;

	bool        m_ok = true;
	const char *m_missing = nullptr;
};

#endif // MB88_ORACLE_H

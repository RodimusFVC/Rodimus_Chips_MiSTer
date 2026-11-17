#include "oracle.h"
#include "z8000cpu.h"    // RW()/RB()/RL() register-file macros, F_* flag bits
#include "8000dasm.h"

#include <sstream>

static machine_config s_dummy_mconfig;

z8002_oracle::z8002_oracle()
	: z8002_device(s_dummy_mconfig, "z8002_oracle", nullptr, 0)
{
	m_mem.clear();
}

void z8002_oracle::begin()
{
	shim_install_memory(&m_mem);
	device_start();
}

void z8002_oracle::set_state(const z8k_state &s)
{
	for (int i = 0; i < 16; i++)
		RW(i) = s.r[i];

	m_pc      = s.pc;
	m_fcw     = s.fcw;       // set directly: CHANGE_FCW's stack swap must NOT run here
	m_nspoff  = s.nspoff;
	m_psapoff = s.psapoff;

	// Nothing may be left pending from a previous test.
	m_irq_req    = 0;
	m_irq_vec    = 0;
	m_op_valid   = 0;
	m_op[0] = m_op[1] = m_op[2] = m_op[3] = 0;
	m_halt       = false;
	m_nmi_state  = CLEAR_LINE;
	m_irq_state[0] = m_irq_state[1] = CLEAR_LINE;
	m_refresh    = 0;
	m_ppc        = s.pc;
}

void z8002_oracle::get_state(z8k_state &s) const
{
	// RW() is an lvalue macro over m_regs; const-correct read of the same slots.
	for (int i = 0; i < 16; i++)
		s.r[i] = m_regs.W[BYTE4_XOR_BE(i)];

	s.pc      = uint16_t(m_pc);
	s.fcw     = m_fcw;
	s.nspoff  = m_nspoff;
	s.psapoff = m_psapoff;
}

int z8002_oracle::step()
{
	m_mem.clear_writes();

	m_icount = 1;
	execute_run();          // do/while(m_icount > 0) => exactly one dispatch
	return 1 - m_icount;
}

// ---------------------------------------------------------------- disassembly

namespace {

class oracle_buffer : public util::disasm_interface::data_buffer
{
public:
	explicit oracle_buffer(const shim_memory &mem) : m_mem(mem) { }

	u8  r8 (offs_t pc) const override
	{
		u16 w = m_mem.prog[(pc & 0xffff) >> 1];
		return (pc & 1) ? (w & 0xff) : (w >> 8);
	}
	u16 r16(offs_t pc) const override { return m_mem.prog[(pc & 0xffff) >> 1]; }
	u32 r32(offs_t pc) const override { return (u32(r16(pc)) << 16) | r16(pc + 2); }
	u64 r64(offs_t pc) const override { return (u64(r32(pc)) << 32) | r32(pc + 4); }

private:
	const shim_memory &m_mem;
};

} // namespace

std::string z8002_oracle::disasm(uint16_t pc)
{
	z8000_disassembler dasm(this);
	oracle_buffer buf(m_mem);
	std::ostringstream os;
	dasm.disassemble(os, pc, buf, buf);
	return os.str();
}

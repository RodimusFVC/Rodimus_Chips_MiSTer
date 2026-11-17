#include "oracle.h"
#include "mb88dasm.h"

#include <sstream>

static machine_config s_dummy_mconfig;

mb88_oracle::mb88_oracle()
	: mb8841_cpu_device(s_dummy_mconfig, "mb88_oracle", nullptr, 1536000)   // 1.536 MHz, polepos/kangaroo
{
	m_mem.clear();
}

void mb88_oracle::begin()
{
	shim_install_memory(&m_mem);
	select();
	device_start();          // registers save_item(NAME(...)) -> shim name map
	device_reset();

	p_PC = find<u8>("m_PC");   p_PA = find<u8>("m_PA");   p_SI = find<u8>("m_SI");
	p_A  = find<u8>("m_A");    p_X  = find<u8>("m_X");    p_Y  = find<u8>("m_Y");
	p_SP = find<u16>("m_SP");
	p_st = find<u8>("m_st");   p_zf = find<u8>("m_zf");   p_cf = find<u8>("m_cf");
	p_vf = find<u8>("m_vf");   p_sf = find<u8>("m_sf");   p_if = find<u8>("m_if");
	p_pio = find<u8>("m_pio"); p_TH = find<u8>("m_TH");   p_TL = find<u8>("m_TL");
	p_TP  = find<u8>("m_TP");  p_ctr = find<u8>("m_ctr"); p_SB = find<u8>("m_SB");
	p_SBcount = find<u16>("m_SBcount");
	p_o_output = find<u8>("m_o_output");
	p_pending_irq = find<u8>("m_pending_irq");
	p_in_irq = find<bool>("m_in_irq");
}

void mb88_oracle::set_state(const mb88_state &s)
{
	*p_PC = s.PC & 0x3f;  *p_PA = s.PA & 0x1f;  *p_SI = s.SI & 3;
	*p_A  = s.A & 0x0f;   *p_X  = s.X & 0x0f;   *p_Y  = s.Y & 0x0f;
	for (int i = 0; i < 4; i++) p_SP[i] = s.SP[i];
	*p_st = s.st & 1;  *p_zf = s.zf & 1;  *p_cf = s.cf & 1;
	*p_vf = s.vf & 1;  *p_sf = s.sf & 1;  *p_if = s.iflag & 1;
	*p_pio = s.pio;    *p_TH = s.TH & 0x0f;  *p_TL = s.TL & 0x0f;
	*p_TP  = s.TP;     *p_ctr = s.ctr & 1;   *p_SB = s.SB & 0x0f;
	*p_SBcount = s.SBcount;
	*p_o_output = s.o_output;
	*p_pending_irq = s.pending_irq;
	*p_in_irq = s.in_irq != 0;
}

void mb88_oracle::get_state(mb88_state &s) const
{
	s.PC = *p_PC;  s.PA = *p_PA;  s.SI = *p_SI;
	s.A  = *p_A;   s.X  = *p_X;   s.Y  = *p_Y;
	for (int i = 0; i < 4; i++) s.SP[i] = p_SP[i];
	s.st = *p_st;  s.zf = *p_zf;  s.cf = *p_cf;
	s.vf = *p_vf;  s.sf = *p_sf;  s.iflag = *p_if;
	s.pio = *p_pio;  s.TH = *p_TH;  s.TL = *p_TL;
	s.TP = *p_TP;    s.ctr = *p_ctr;  s.SB = *p_SB;
	s.SBcount = *p_SBcount;
	s.o_output = *p_o_output;
	s.pending_irq = *p_pending_irq;
	s.in_irq = *p_in_irq ? 1 : 0;
}

int mb88_oracle::step()
{
	select();
	m_mem.clear_writes();
	m_ports.clear_writes();

	int *ic = shim_icount();
	*ic = 1;
	execute_run();          // while (m_icount > 0) => exactly one dispatch
	return 1 - *ic;         // burn_cycles subtracted oc (1 or 2)
}

void mb88_oracle::set_irq_line(int state) { select(); execute_set_input(MB88XX_IRQ_LINE, state); }
void mb88_oracle::set_tc_line(int state)  { select(); execute_set_input(MB88XX_TC_LINE,  state); }

// ---------------------------------------------------------------- disassembly

namespace {

class oracle_buffer : public util::disasm_interface::data_buffer
{
public:
	explicit oracle_buffer(const shim_memory &mem) : m_mem(mem) { }
	u8  r8 (offs_t pc) const override { return m_mem.prog[pc & (shim_memory::PROG_SIZE - 1)]; }
	u16 r16(offs_t pc) const override { return u16(r8(pc)) | (u16(r8(pc + 1)) << 8); }
	u32 r32(offs_t pc) const override { return u32(r16(pc)) | (u32(r16(pc + 2)) << 16); }
	u64 r64(offs_t pc) const override { return u64(r32(pc)) | (u64(r32(pc + 4)) << 32); }
private:
	const shim_memory &m_mem;
};

} // namespace

std::string mb88_oracle::disasm(u16 pc)
{
	mb88_disassembler dasm;
	oracle_buffer buf(m_mem);
	std::ostringstream os;
	dasm.disassemble(os, pc, buf, buf);
	return os.str();
}

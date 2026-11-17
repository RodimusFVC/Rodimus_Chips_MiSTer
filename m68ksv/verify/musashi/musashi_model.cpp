// Copyright (C) 2026 Rodimus
// Standalone C++ model of MAME's Musashi 68010 (Karl Stenerud's Musashi as in MAME src/devices/cpu/m68000:
// m68kcpu.cpp, m68kops.cpp, m68010.cpp, m68kcpu.h, m68kops.h, m68kmusashi.h; read-only oracle, compiled unmodified)
// for the m68ksv verification harness only. This file supplies the device plumbing MAME's framework normally
// provides (address spaces on one harness bus, the disassembler and FPU members as unreachable stubs - the 68010 has
// no FPU and never disassembles here) and a small API: load a state, run one instruction, every write logged with its
// function code. Own code.
#include "emu.h"
#include "m68010.h"
#include "m68kdasm.h"
#include "musashi_model.h"

// ---------------------------------------------------------------------------------------------- unreachable stubs
m68k_disassembler::m68k_disassembler(u32) {}
u32 m68k_disassembler::opcode_alignment() const { return 2; }
offs_t m68k_disassembler::disassemble(std::ostream &, offs_t, const data_buffer &, const data_buffer &) { return 2; }
uint_fast8_t softfloat_roundingMode;
uint_fast8_t extF80_roundingPrecision;
#define FPU_STUB { fprintf(stderr, "musashi model: FPU member called\n"); abort(); }
void m68000_musashi_device::apply_fpcr_rounding() FPU_STUB
void m68000_musashi_device::do_frestore_null() FPU_STUB
void m68000_musashi_device::fpgen_rm_reg(u16) FPU_STUB
void m68000_musashi_device::fmove_reg_mem(u16) FPU_STUB
void m68000_musashi_device::fmove_fpcr(u16) FPU_STUB
void m68000_musashi_device::fmovem(u16) FPU_STUB
void m68000_musashi_device::fdbcc() FPU_STUB
void m68000_musashi_device::fbcc16() FPU_STUB
void m68000_musashi_device::fbcc32() FPU_STUB
int m68000_musashi_device::perform_fsave(u32, int) FPU_STUB
void m68000_musashi_device::m68040_do_fsave(u32, int, int) FPU_STUB
void m68000_musashi_device::m68040_do_frestore(u32, int) FPU_STUB
void m68000_musashi_device::m68881_ftrap() FPU_STUB
u32 m68000_musashi_device::m6888x_read_cir(offs_t) FPU_STUB
void m68000_musashi_device::m6888x_write_cir(offs_t, u32) FPU_STUB
bool m68000_musashi_device::fpu_check_pending_exception() FPU_STUB
int m68000_musashi_device::test_condition(int) FPU_STUB
u16 m68000_musashi_device::READ_EA_16(int) FPU_STUB
u32 m68000_musashi_device::READ_EA_32(int) FPU_STUB
u64 m68000_musashi_device::READ_EA_64(int) FPU_STUB
void m68000_musashi_device::WRITE_EA_16(int, u16) FPU_STUB
void m68000_musashi_device::WRITE_EA_32(int, u32) FPU_STUB
void m68000_musashi_device::WRITE_EA_64(int, u64) FPU_STUB

// ---------------------------------------------------------------------------------------------- the model
class mus_dev : public m68010_device, public musashi_bus_if {
public:
    mus_model *api = nullptr;
    mus_dev() : m68010_device(machine_config(), nullptr, nullptr, 0) {
        for (int i = 0; i < 8; i++) { m_spaces[i].bus = this; m_spaces[i].space = 0; }
        m_spaces[m_cpu_space_id].space = 2;
        device_start();
        set_emmu_enable(true);          // bus errors through the instruction-restart path (MAME's external-MMU hook)
    }
    // bus
    bool berr_check(offs_t a, int rw) {
        if (!api->berr_armed || api->berr_fired) return false;
        if (m_run_mode != RUN_MODE_NORMAL) return false;
        if (a != api->berr_addr || rw != api->berr_rw) return false;
        api->berr_fired = 1;
        set_buserror_details(a, rw, m_mmu_tmp_fc, true);
        return true;
    }
    u16 rd16(int space, offs_t a) override {
        if (space == 2) { if ((a & 0xffffff) == 0) api->bkpt_cycles++;
                          return api->iack_vector < 0 ? 0x18 + ((a >> 1) & 7) : api->iack_vector; }
        if (space == 0) berr_check(a & 0xffffff, 1);
        a &= 0xfffffe;
        return (api->mem[a] << 8) | api->mem[a + 1];
    }
    u8 rd8(int space, offs_t a) override {
        if (space == 2) return api->iack_vector < 0 ? 0x18 + ((a >> 1) & 7) : api->iack_vector;
        if (space == 0) berr_check(a & 0xffffff, 1);
        return api->mem[a & 0xffffff];
    }
    void wr16(offs_t a, u16 d, u16 mask) override {
        a &= 0xffffff;
        bool hit = berr_check((mask == 0x00ff) ? (a | 1) : a, 0);
        // after a bus error the rest of the faulted instruction's accesses do not happen on the real bus (MAME lets
        // the handler run on and then restores the registers); the frame pushes come later (run mode not normal)
        if (hit || (api->berr_fired && m_run_mode == RUN_MODE_NORMAL)) return;
        a &= 0xfffffe;
        if (api->ro && api->ro(a)) return;
        if (mask & 0xff00) api->mem[a] = d >> 8;
        if (mask & 0x00ff) api->mem[a + 1] = d;
        api->wlog.push_back(mus_write{a, d, mask, (int)(m_mmu_tmp_fc & 7)});
    }
    // state
    void set_state(const mus_state &s) {
        m68ki_set_sr_noint_nosp(s.sr);
        for (int i = 0; i < 8; i++) { m_dar[i] = s.d[i]; m_dar[8 + i] = s.a[i]; }
        m_sp[0] = s.usp; m_sp[4] = s.ssp;
        REG_SP() = (s.sr & 0x2000) ? s.ssp : s.usp;
        m_vbr = s.vbr; m_sfc = s.sfc; m_dfc = s.dfc;
        m_stopped = 0;
        m68ki_jump(s.pc);
        m_pref_addr = ~0u;
    }
    void get_state(mus_state &s) {
        s.sr = m68ki_get_sr();
        for (int i = 0; i < 8; i++) { s.d[i] = m_dar[i]; s.a[i] = m_dar[8 + i]; }
        if (m_s_flag) { s.ssp = m_dar[15]; s.usp = m_sp[0]; } else { s.usp = m_dar[15]; s.ssp = m_sp[4]; }
        s.pc = m_pc; s.vbr = m_vbr; s.sfc = m_sfc; s.dfc = m_dfc;
    }
    void do_reset() { device_reset(); }
    void set_irq(int level) {
        for (int l = 1; l <= 7; l++) execute_set_input(l, l == level ? ASSERT_LINE : CLEAR_LINE);
    }
    int run1() {
        m_icount = 1;
        // an address error outside execute_run's own handler (interrupt entry with an odd stack or vector, reset
        // vectors) escapes Musashi as a C++ exception: the harness treats it as a halt
        try { execute_run(); } catch (int) { m_stopped = STOP_LEVEL_HALT; }
        return 1 - m_icount;
    }
    bool is_stopped() { return (m_stopped & STOP_LEVEL_STOP) != 0; }
    bool is_halted() { return (m_stopped & STOP_LEVEL_HALT) != 0; }
    int ir() { return m_ir; }
};

struct mus_impl : mus_model {
    mus_dev *d;
    mus_impl() { d = new mus_dev; d->api = this; }
    ~mus_impl() { delete d; }
    void set_state(const mus_state &s) override { d->set_state(s); }
    void get_state(mus_state &s) override { d->get_state(s); }
    void reset() override { d->do_reset(); d->run1(); }
    void set_irq(int level) override { d->set_irq(level); }
    int step() override { berr_fired = 0; return d->run1(); }
    bool stopped() override { return d->is_stopped(); }
    bool halted() override { return d->is_halted(); }
    int last_ir() override { return d->ir(); }
};
mus_model *mus_model_new() { return new mus_impl; }

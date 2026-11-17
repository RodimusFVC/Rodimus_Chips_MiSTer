// Copyright (C) 2026 Rodimus
// Standalone C++ model of MAME's Musashi 68020 / 68EC020 (src/devices/cpu/m68000: m68kcpu.cpp, m68kops.cpp,
// m68020.cpp and their headers; read-only oracle, compiled unmodified) for the m68ksv verification harness only, as
// musashi_model.cpp is for the 68010: device plumbing (one harness bus for program / opcode / CPU space, MAME's 32-bit
// bus forms through the shim), the disassembler and FPU members as stubs (no FPU: every F-line opcode is a line-F
// exception in this model), every written byte logged with its function code. Own code.
#include "emu.h"
#include "m68020.h"
#include "m68kdasm.h"
#include "musashi_model020.h"

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
// MOVES with SFC / DFC = 7 to $22000-$2200F / $23000-$2300F reaches MAME's coprocessor interface registers: no FPU in
// this model, the access reads all ones / is dropped
u32 m68000_musashi_device::m6888x_read_cir(offs_t) { return 0xffffffff; }
void m68000_musashi_device::m6888x_write_cir(offs_t, u32) {}
bool m68000_musashi_device::fpu_check_pending_exception() FPU_STUB
int m68000_musashi_device::test_condition(int) FPU_STUB
u16 m68000_musashi_device::READ_EA_16(int) FPU_STUB
u32 m68000_musashi_device::READ_EA_32(int) FPU_STUB
u64 m68000_musashi_device::READ_EA_64(int) FPU_STUB
void m68000_musashi_device::WRITE_EA_16(int, u16) FPU_STUB
void m68000_musashi_device::WRITE_EA_32(int, u32) FPU_STUB
void m68000_musashi_device::WRITE_EA_64(int, u64) FPU_STUB

// ---------------------------------------------------------------------------------------------- the model
template <class DEV> class mus20_dev : public DEV, public musashi_bus_if {
public:
    mus20_model *api = nullptr;
    mus20_dev() : DEV(machine_config(), nullptr, nullptr, 0) {
        for (int i = 0; i < 8; i++) { this->m_spaces[i].bus = this; this->m_spaces[i].space = 0; }
        this->m_spaces[this->m_cpu_space_id].space = 2;
        this->device_start();
        this->set_emmu_enable(true);    // bus errors through the instruction-restart path (MAME's external-MMU hook)
    }
    bool berr_check(offs_t a, int rw) {
        if (!api->berr_armed || api->berr_fired) return false;
        if (this->m_run_mode != DEV::RUN_MODE_NORMAL) return false;
        if (a != api->berr_addr || rw != api->berr_rw) return false;
        api->berr_fired = 1;
        this->set_buserror_details(a, rw, this->m_mmu_tmp_fc, true);
        return true;
    }
    u8 mb(offs_t a) { return api->mem[a & api->amask]; }
    // memory-space read log (2026-11-16: mus020 takes the operands of the WinUAE-rule classifications from it)
    void rlog(offs_t a, int sz, u32 v) { api->rlog.push_back(mus20_read{a & api->amask, sz, v, (int)(this->m_mmu_tmp_fc & 7)}); }
    u8 cpu8(offs_t a) {             // CPU space: IACK vector (autovector: 24 + level), breakpoint acknowledge
        if ((a & 0xfffffff0) == 0xfffffff0) return api->iack_vector < 0 ? 0x18 + ((a >> 1) & 7) : api->iack_vector;
        if ((a & 0x000f0000) == 0) api->bkpt_cycles++;
        return 0xff;
    }
    u16 rd16(int space, offs_t a) override {
        if (space == 2) return (cpu8(a) << 8) | cpu8(a + 1);
        if (space == 0) berr_check(a, 1);
        a &= ~1u;
        u16 v = (mb(a) << 8) | mb(a + 1); rlog(a, 2, v); return v;
    }
    u8 rd8(int space, offs_t a) override {
        if (space == 2) return cpu8(a);
        if (space == 0) berr_check(a, 1);
        rlog(a, 1, mb(a)); return mb(a);
    }
    u16 rd16u(int space, offs_t a) override {
        if (space == 2) return (cpu8(a) << 8) | cpu8(a + 1);
        if (space == 0) berr_check(a, 1);
        u16 v = (mb(a) << 8) | mb(a + 1); rlog(a, 2, v); return v;
    }
    u32 rd32u(int space, offs_t a) override {
        if (space == 2) return ((u32)cpu8(a) << 24) | ((u32)cpu8(a + 1) << 16) | (cpu8(a + 2) << 8) | cpu8(a + 3);
        if (space == 0) berr_check(a, 1);
        u32 v = ((u32)mb(a) << 24) | ((u32)mb(a + 1) << 16) | (mb(a + 2) << 8) | mb(a + 3); rlog(a, 4, v); return v;
    }
    void wbyte(offs_t a, u8 d) {
        if (api->ro && api->ro(a & api->amask)) return;
        api->mem[a & api->amask] = d;
        api->wlog.push_back(mus20_write{a & api->amask, d, (int)(this->m_mmu_tmp_fc & 7)});
    }
    bool wcheck(offs_t a) {
        bool hit = berr_check(a, 0);
        return !(hit || (api->berr_fired && this->m_run_mode == DEV::RUN_MODE_NORMAL));
    }
    void wr16(offs_t a, u16 d, u16 mask) override {
        if (!wcheck((mask == 0x00ff) ? (a | 1) : a)) return;
        a &= ~1u;
        if (mask & 0xff00) wbyte(a, d >> 8);
        if (mask & 0x00ff) wbyte(a + 1, d);
    }
    void wr32(offs_t a, u32 d, u32 mask) override {
        int f = 0; while (f < 3 && !((mask >> (24 - 8 * f)) & 0xff)) f++;
        if (!wcheck(a + f)) return;
        for (int k = 0; k < 4; k++) if ((mask >> (24 - 8 * k)) & 0xff) wbyte(a + k, d >> (24 - 8 * k));
    }
    void set_state(const mus20_state &s) {
        this->m68ki_set_sr_noint_nosp(s.sr);
        for (int i = 0; i < 8; i++) { this->m_dar[i] = s.d[i]; this->m_dar[8 + i] = s.a[i]; }
        this->m_sp[0] = s.usp; this->m_sp[4] = s.isp; this->m_sp[6] = s.msp;
        this->REG_SP() = (s.sr & 0x2000) ? ((s.sr & 0x1000) ? s.msp : s.isp) : s.usp;
        this->m_vbr = s.vbr; this->m_sfc = s.sfc; this->m_dfc = s.dfc; this->m_cacr = s.cacr; this->m_caar = s.caar;
        this->m_stopped = 0;
        this->m68ki_jump(s.pc);
        this->m_pref_addr = ~0u;
    }
    void get_state(mus20_state &s) {
        s.sr = this->m68ki_get_sr();
        for (int i = 0; i < 8; i++) { s.d[i] = this->m_dar[i]; s.a[i] = this->m_dar[8 + i]; }
        s.usp = this->m_sp[0]; s.isp = this->m_sp[4]; s.msp = this->m_sp[6];
        if (!this->m_s_flag) s.usp = this->m_dar[15];
        else if (this->m_m_flag) s.msp = this->m_dar[15];
        else s.isp = this->m_dar[15];
        s.pc = this->m_pc; s.vbr = this->m_vbr; s.sfc = this->m_sfc; s.dfc = this->m_dfc;
        s.cacr = this->m_cacr; s.caar = this->m_caar;
    }
    void do_reset() { this->device_reset(); }
    void set_irq(int level) {
        for (int l = 1; l <= 7; l++) this->execute_set_input(l, l == level ? ASSERT_LINE : CLEAR_LINE);
    }
    int run1() {
        this->m_icount = 1;
        try { this->execute_run(); } catch (int) { this->m_stopped = DEV::STOP_LEVEL_HALT; }
        return 1 - this->m_icount;
    }
    bool is_stopped() { return (this->m_stopped & DEV::STOP_LEVEL_STOP) != 0; }
    bool is_halted() { return (this->m_stopped & DEV::STOP_LEVEL_HALT) != 0; }
    int ir() { return this->m_ir; }
};

template <class DEV> struct mus20_impl : mus20_model {
    mus20_dev<DEV> *d;
    mus20_impl() { d = new mus20_dev<DEV>; d->api = this; }
    ~mus20_impl() { delete d; }
    void set_state(const mus20_state &s) override { d->set_state(s); }
    void get_state(mus20_state &s) override { d->get_state(s); }
    void reset() override { d->do_reset(); d->run1(); }
    void set_irq(int level) override { d->set_irq(level); }
    int step() override { berr_fired = 0; rlog.clear(); return d->run1(); }
    bool stopped() override { return d->is_stopped(); }
    bool halted() override { return d->is_halted(); }
    int last_ir() override { return d->ir(); }
};
mus20_model *mus20_model_new(bool ec020) {
    if (ec020) return new mus20_impl<m68ec020_device>;
    return new mus20_impl<m68020_device>;
}

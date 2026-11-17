// Copyright (C) 2026 Rodimus
// Standalone C++ model of MAME's cycle-exact m68000 / m68008 / m68008FN (Olivier Galibert's microcode-derived
// generated cores, MAME src/devices/cpu/m68000: m68000.h, m68008.h, m68000-sdf.cpp, m68008-sdf8.cpp,
// m68000-decode.cpp; read-only oracle, compiled unmodified) for the m68ksv verification harness only.
// This file supplies the non-generated m68000_device / m68008_device members (MAME's m68000.cpp / m68008.cpp need the
// whole emulator framework, so their few runtime helpers are re-implemented here from their behaviour) and a small
// API: load a state, run instructions, every bus access logged with its start time in CPU clocks. Own code.
#include "emu.h"
#include "m68000.h"
#include "m68008.h"
#include "mame_model.h"

// ---------------------------------------------------------------------------------------------- m68000_device
m68000_device::m68000_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
    : m68000_device(mconfig, nullptr, tag, owner, clock) {}

m68000_device::m68000_device(const machine_config &mconfig, device_type type, const char *tag, device_t *owner, u32 clock)
    : m68000_base_device(mconfig, type, tag, owner, clock),
      m_cmpild_instr_callback(*this), m_rte_instr_callback(*this), m_tas_write_callback(*this),
      m_mmu(nullptr), m_disable_spaces(false), m_disable_specifics(false), m_disable_interrupt_callback(true) {}

u16 m68000_device::mmu_disabled::read_program(offs_t, u16) { return 0; }
void m68000_device::mmu_disabled::write_program(offs_t, u16, u16) {}
u16 m68000_device::mmu_disabled::read_data(offs_t, u16) { return 0; }
void m68000_device::mmu_disabled::write_data(offs_t, u16, u16) {}
u16 m68000_device::mmu_disabled::read_cpu(offs_t, u16) { return 0; }
void m68000_device::mmu_disabled::set_super(bool) {}
bool m68000_device::mmu_disabled::translate(int, int, offs_t &, address_space *&) { return false; }

std::unique_ptr<util::disasm_interface> m68000_device::create_disassembler() { return nullptr; }
bool m68000_device::supervisor_mode() const noexcept { return m_sr & SR_S; }
u16 m68000_device::get_fc() const noexcept { return (m_base_ssw | (m_sr & SR_S ? SSW_S : 0)) & 7; }
void m68000_device::execute_run() {}
void m68000_device::execute_set_input(int, int) {}
void m68000_device::state_import(const device_state_entry &) {}
void m68000_device::state_string_export(const device_state_entry &, std::string &) const {}
cpu_device::space_config_vector m68000_device::memory_space_config() const { return {}; }
cpu_device::space_config_vector m68000_device::memory_logical_space_config() const { return {}; }
void m68000_device::device_start() {}
void m68000_device::device_reset() {}
bool m68000_device::memory_translate(int, int, offs_t &, address_space *&) { return false; }

void m68000_device::abort_access(u32 reason)
{
    m_post_run = reason;
    m_post_run_cycles = m_icount;
    m_icount = 0;
}

void m68000_device::do_post_run()
{
    // MAME m68000.cpp: a bus error aborts the access, the bus-error state starts 10 clocks later
    m_icount = m_post_run_cycles;
    m_post_run_cycles = 0;
    if (m_post_run == PR_BERR) {
        m_inst_state = S_BUS_ERROR;
        m_inst_substate = 0;
        m_icount -= 10;
    }
    m_post_run = 0;
}

void m68000_device::update_user_super()
{
    if (m_sr & SR_S) { m_sp = 16; m_program = m_r_program; m_opcodes = m_r_opcodes; }
    else             { m_sp = 15; m_program = m_r_uprogram; m_opcodes = m_r_uopcodes; }
}

void m68000_device::update_interrupt()
{
    if (m_nmi_pending) m_int_next_state = (7 << 24) | S_INTERRUPT;
    else if (m_int_level > u32((m_sr >> 8) & 7)) m_int_next_state = (m_int_level << 24) | S_INTERRUPT;
    else m_int_next_state = 0;
}

void m68000_device::init_decode_table()
{
    m_decode_table.assign(0x10000, S_ILLEGAL);
    for (int i = 0; s_packed_decode_table[i].mask; i++) {
        u16 value = s_packed_decode_table[i].value, mask = s_packed_decode_table[i].mask, state = s_packed_decode_table[i].state;
        u16 cvalue = 0;
        do {
            if (m_decode_table[value | cvalue] == S_ILLEGAL) m_decode_table[value | cvalue] = state;
            cvalue = ((cvalue | mask) + 1) & ~mask;
        } while (cvalue);
    }
}

void m68000_device::set_ftu_const()
{
    switch (m_ird >> 12) {
    case 0x4: m_ftu = 0x80; break;
    case 0x5: case 0xe: m_ftu = (m_ird >> 9) & 7; if (!m_ftu) m_ftu = 8; break;
    case 0x6: case 0x7: m_ftu = s8(m_ird); break;
    case 0x8: case 0xc: m_ftu = 0xf; break;
    default: m_ftu = 0; break;
    }
}

void m68000_device::start_interrupt_vector_lookup()
{
    int level = m_next_state >> 24;
    if (level == 7) { m_nmi_pending = false; update_interrupt(); }
}

void m68000_device::end_interrupt_vector_lookup()
{
    m_int_vector = (m_edb & 0xff) << 2;
    m_int_next_state = 0;
}

// ---------------------------------------------------------------------------------------------- m68008_device
m68008_device::m68008_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
    : m68008_device(mconfig, nullptr, tag, owner, clock) {}
m68008_device::m68008_device(const machine_config &mconfig, device_type type, const char *tag, device_t *owner, u32 clock)
    : m68000_device(mconfig, type, tag, owner, clock), m_mmu8(nullptr) {}
std::unique_ptr<util::disasm_interface> m68008_device::create_disassembler() { return nullptr; }
void m68008_device::device_start() {}
bool m68008_device::memory_translate(int, int, offs_t &, address_space *&) { return false; }
void m68008_device::update_user_super()
{
    if (m_sr & SR_S) { m_sp = 16; m_program8 = m_r_program8; m_opcodes8 = m_r_opcodes8; }
    else             { m_sp = 15; m_program8 = m_r_uprogram8; m_opcodes8 = m_r_uopcodes8; }
}
m68008fn_device::m68008fn_device(const machine_config &mconfig, const char *tag, device_t *owner, u32 clock)
    : m68008_device(mconfig, nullptr, tag, owner, clock) {}
std::unique_ptr<util::disasm_interface> m68008fn_device::create_disassembler() { return nullptr; }
void m68008fn_device::device_start() {}

// ---------------------------------------------------------------------------------------------- model wrapper
static machine_config s_mc;

template <class BASE, bool B8>
class model_impl : public BASE, public mame_bus_if, public mame_model {
public:
    model_impl() : BASE(s_mc, "cpu", nullptr, 8000000) {
        this->init_decode_table();
        for (auto *sp : {&spec(0), &spec(1), &spec(2), &spec(3), &spec(4)}) sp->bus = this;
        spec(0).space = 0; spec(1).space = 1; spec(2).space = 0; spec(3).space = 1; spec(4).space = 2;
        if constexpr (B8) this->m_handlers_f = reinterpret_cast<const typename BASE::handler *>(BASE::s_handlers_df8);
        else this->m_handlers_f = BASE::s_handlers_df;
        this->m_handlers_p = nullptr;
        this->m_reset_cb.f = [this](int v) { reset_out = v; };
        // MAME device_start zeroes the internal state
        memset(this->m_da, 0, sizeof(this->m_da));
        this->m_ipc = this->m_pc = this->m_au = this->m_at = this->m_aob = this->m_dt = this->m_int_vector = 0;
        this->m_sp = 16; this->m_bcount = this->m_count_before_instruction_step = this->m_t = 0; this->m_movems = 0;
        this->m_isr = this->m_sr = this->m_new_sr = this->m_dbin = this->m_dbout = this->m_edb = 0;
        this->m_irc = this->m_ir = this->m_ird = this->m_ftu = this->m_aluo = this->m_alue = this->m_alub = 0;
        this->m_movemr = this->m_irdi = this->m_base_ssw = this->m_ssw = 0; this->m_dcr = 0;
        this->m_virq_state = this->m_nmi_pending = this->m_int_level = this->m_int_next_state = 0;
        this->m_nmi_uses_generic = false; this->m_last_vpa_time = 0;
        this->m_inst_state = this->m_inst_substate = 0; this->m_next_state = this->m_post_run = 0; this->m_post_run_cycles = 0;
        this->m_icount = 0;
        this->update_user_super();
    }
    // fixed specifics: 0 super data, 1 super program, 2 user data, 3 user program, 4 cpu space
    auto &spec(int i) {
        if constexpr (B8) {
            switch (i) { case 0: return this->m_r_program8; case 1: return this->m_r_opcodes8; case 2: return this->m_r_uprogram8;
                         case 3: return this->m_r_uopcodes8; default: return this->m_cpu_space8; }
        } else {
            switch (i) { case 0: return this->m_r_program; case 1: return this->m_r_opcodes; case 2: return this->m_r_uprogram;
                         case 3: return this->m_r_uopcodes; default: return this->m_cpu_space; }
        }
    }

    // bus
    u16 rd(int space, offs_t a, u16 mask, bool word) override {
        mame_access x;
        x.time = start_icount - this->m_icount;
        x.fc = this->get_fc();
        x.wr = false;
        x.size = B8 ? 1 : (word ? 2 : 1);
        a &= B8 ? 0x3fffff : 0xffffff;
        if (!B8 && !word && mask == 0x00ff) a |= 1;
        x.addr = (B8 || space == 2) ? a : (this->m_aob & 0xffffff);     // m_aob keeps A0 (odd word = aborted)
        u16 v;
        if (space == 2) {
            // interrupt acknowledge: vector byte from the harness (autovector 24 + level by default)
            int lvl = (a >> 1) & 7;
            v = iack_vector >= 0 ? (u16)iack_vector : (u16)(24 + lvl);
            if (!B8) v |= v << 8;
            x.iack = true;
        } else if (B8) v = mem ? mem[a & mem_mask] : 0;
        else {
            u32 e = a & ~1u;
            v = mem ? (u16)((mem[e & mem_mask] << 8) | mem[(e + 1) & mem_mask]) : 0;
        }
        x.val = (B8 || word) ? v : ((a & 1) ? (v & 0xff) : (v >> 8));
        log.push_back(x);
        if (berr_at >= 0 && (int)log.size() - 1 == berr_at) this->abort_access(BASE::PR_BERR);
        return v;
    }
    void wr(offs_t a, u16 d, u16 mask, bool word) override {
        mame_access x;
        x.time = start_icount - this->m_icount;
        x.fc = this->get_fc();
        x.wr = true;
        x.size = B8 ? 1 : (word ? 2 : 1);
        a &= B8 ? 0x3fffff : 0xffffff;
        if (!B8 && !word && mask == 0x00ff) a |= 1;
        x.addr = B8 ? a : (this->m_aob & 0xffffff);
        if (!B8 && word && (x.addr & 1)) { x.val = d; log.push_back(x); return; }   // aborted (address error): no write
        if (B8) { x.val = d & 0xff; if (mem) mem[a & mem_mask] = d & 0xff; }
        else if (word) { x.val = d; if (mem) { mem[a & ~1u & mem_mask] = d >> 8; mem[(a | 1) & mem_mask] = d & 0xff; } }
        else {
            x.val = (a & 1) ? (d & 0xff) : (d >> 8);
            if (mem) mem[a & mem_mask] = x.val;
        }
        log.push_back(x);
        if (berr_at >= 0 && (int)log.size() - 1 == berr_at) this->abort_access(BASE::PR_BERR);
    }

    // mame_model API
    void set_state(const mame_state &s) override {
        for (int i = 0; i < 17; i++) this->m_da[i] = s.r[i];
        this->m_sr = s.sr;
        this->m_isr = s.sr & 0x1f;          // the ALU status of the previous instruction (TRAPV tests it)
        // instruction boundary: IRD = IR = opcode at pc, IRC = word at pc + 2, PC = pc + 2, AU = pc + 4
        this->m_ird = this->m_ir = s.ir;
        this->m_irc = s.irc;
        this->m_pc = s.pc + 2;
        this->m_au = s.pc + 4;
        this->m_dbin = this->m_edb = s.irc;
        this->m_aob = s.pc + 2;
        this->m_next_state = 0;
        this->m_nmi_pending = 0;
        this->m_int_level = 0;
        this->m_post_run = 0;
        this->update_user_super();
        this->update_interrupt();
        this->set_ftu_const();
        this->m_inst_state = this->m_decode_table[this->m_ird];
        this->m_inst_substate = 0;
        if (s.sr & 0x8000) this->m_next_state = BASE::S_TRACE;
    }
    void get_state(mame_state &s) override {
        for (int i = 0; i < 17; i++) s.r[i] = this->m_da[i];
        s.sr = this->m_sr;
        s.pc = this->m_pc - 2;
        s.ir = this->m_ird;
        s.irc = this->m_irc;
    }
    void reset() override {
        this->m_sr = 0x2700 | (this->m_sr & 0x1f);    // the CCR is kept, as fx68k and m68ksv (undefined by Motorola)
        this->m_inst_state = BASE::S_RESET;
        this->m_inst_substate = 0;
        this->m_next_state = 0;
        this->m_post_run = 0;
        this->update_user_super();
    }
    void set_ipl(int level) override {
        u32 old = this->m_int_level;
        this->m_int_level = level;
        if (old != 7 && level == 7) this->m_nmi_pending = true;
        this->update_interrupt();
    }
    // runs handlers until an instruction boundary (the next state is an instruction) is reached; returns clocks
    int step() override {
        start_icount = 1000000000;
        this->m_icount = start_icount;
        bool first = true;
        for (int guard = 0; guard < 64; guard++) {
            if (!first && this->m_inst_state >= BASE::S_first_instruction) break;
            first = false;
            if (this->m_inst_state >= BASE::S_first_instruction) { this->m_ipc = this->m_pc - 2; this->m_irdi = this->m_ird; }
            if (this->m_inst_state == BASE::S_DOUBLE_FAULT) { halted = true; break; }
            (this->*(this->m_handlers_f[this->m_inst_state]))();
            if (this->m_post_run) this->do_post_run();
        }
        return start_icount - this->m_icount;
    }
    int state_id() override { return this->m_inst_state; }
    int start_icount = 0;
};

mame_model *mame_model_new(int type)
{
    if (type == 68000) return new model_impl<m68000_device, false>();
    return new model_impl<m68008_device, true>();
}

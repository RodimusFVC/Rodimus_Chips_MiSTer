// Copyright (C) 2026 Rodimus
// Minimal stand-in for MAME's emu.h so that MAME's own m68000.h / m68008.h and the generated m68000 / m68008 handler
// files (src/devices/cpu/m68000, read-only oracle, never edited) compile as a standalone C++ model inside the m68ksv
// verification harness (verify/mame/mame_model.cpp). Only what those files reference is provided. Own code.
#pragma once
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>
#include <vector>
#include <utility>
#include <bit>
#include <functional>

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32; typedef int64_t s64;
typedef u32 offs_t;
enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };
#define ATTR_COLD
#define DECLARE_DEVICE_TYPE(a, b)
enum { STATE_GENPC = -1, STATE_GENPCBASE = -2, STATE_GENFLAGS = -3 };
enum { INPUT_LINE_NMI = 32 };
enum { CLEAR_LINE = 0, ASSERT_LINE = 1 };
enum { AS_PROGRAM = 0, AS_OPCODES = 3 };

class machine_config {};
class device_t;
typedef const void *device_type;
class address_map {};
class address_space {};
class device_state_entry { public: int index() const { return 0; } };
class address_space_config { public: address_space_config() {} };
namespace util { class disasm_interface { public: virtual ~disasm_interface() {} }; }

// bus callbacks of the harness: every memory access of the model goes through one of these
struct mame_bus_if {
    virtual u16 rd(int space, offs_t a, u16 mask, bool word) = 0;    // space: 0 data, 1 program (opcodes), 2 cpu
    virtual void wr(offs_t a, u16 d, u16 mask, bool word) = 0;
    virtual ~mame_bus_if() {}
};
template <int AW, int DW, int AS, endianness_t E> struct memory_access {
    struct specific {
        mame_bus_if *bus = nullptr;
        int space = 0;
        // DW 1 = 16-bit port (word access unless a mask is given), DW 0 = 8-bit port
        u16 read_interruptible(offs_t a) const { return bus->rd(space, a, DW ? 0xffff : 0xff, DW != 0); }
        u16 read_interruptible(offs_t a, u16 m) const { return bus->rd(space, a, m, false); }
        void write_interruptible(offs_t a, u16 d) const { bus->wr(a, d, DW ? 0xffff : 0xff, DW != 0); }
        void write_interruptible(offs_t a, u16 d, u16 m) const { bus->wr(a, d, m, false); }
    };
};
struct line_cb { std::function<void(int)> f; bool isnull() const { return !f; } void operator()(int v) { if (f) f(v); } };
struct write32sm_delegate { write32sm_delegate(device_t &) {} bool isnull() const { return true; } void operator()(offs_t, u32) {} void resolve() {} template <typename... T> void set(T...) {} };
struct write8sm_delegate { write8sm_delegate(device_t &) {} bool isnull() const { return true; } void operator()(offs_t, u8) {} void resolve() {} template <typename... T> void set(T...) {} };
struct write_line_delegate { write_line_delegate(device_t &) {} bool isnull() const { return true; } void operator()(int) {} void resolve() {} template <typename... T> void set(T...) {} };
struct devcb_write_line {
    std::function<void(int)> f;
    devcb_write_line(device_t &) {}
    devcb_write_line &bind() { return *this; }
    void operator()(int v) { if (f) f(v); }
};

class device_t {
public:
    device_t(const machine_config &, device_type, const char *, device_t *, u32) {}
    virtual ~device_t() {}
    void debugger_exception_hook(int) {}
    void debugger_instruction_hook(offs_t) {}
    void debugger_wait_hook() {}
    bool debugger_enabled() const { return false; }
    template <typename... T> void logerror(T...) {}
    int standard_irq_callback(int, offs_t) { return 0; }
};
class cpu_device : public device_t {
public:
    using space_config_vector = std::vector<std::pair<int, const address_space_config *>>;
    cpu_device(const machine_config &m, device_type t, const char *tag, device_t *o, u32 c) : device_t(m, t, tag, o, c) {}
    virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }
    virtual bool cpu_is_interruptible() const { return false; }
    virtual u32 execute_min_cycles() const noexcept { return 1; }
    virtual u32 execute_max_cycles() const noexcept { return 1; }
    virtual bool execute_input_edge_triggered(int) const noexcept { return false; }
    virtual void execute_run() {}
    virtual void execute_set_input(int, int) {}
    virtual void state_import(const device_state_entry &) {}
    virtual void state_string_export(const device_state_entry &, std::string &) const {}
    virtual space_config_vector memory_space_config() const { return {}; }
    virtual space_config_vector memory_logical_space_config() const { return {}; }
    virtual void device_start() {}
    virtual void device_reset() {}
    virtual bool memory_translate(int, int, offs_t &, address_space *&) { return false; }
    bool access_to_be_redone() { return false; }
};

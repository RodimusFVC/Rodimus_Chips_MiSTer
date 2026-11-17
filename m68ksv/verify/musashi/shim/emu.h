// Copyright (C) 2026 Rodimus
// Minimal stand-in for MAME's emu.h so that MAME's Musashi (src/devices/cpu/m68000: m68kcpu.cpp, m68kops.cpp,
// m68010.cpp and their headers; read-only oracle, compiled unmodified) builds as a standalone C++ model inside the
// m68ksv verification harness (verify/musashi/musashi_model.cpp). Only what those files reference is provided; every
// memory access ends in the harness bus interface below. Own code.
#pragma once
#include <cstdint>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <vector>
#include <array>
#include <utility>
#include <functional>
#include <bit>
#include <ostream>

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32; typedef int64_t s64;
typedef u32 offs_t;
enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };
#define ATTR_COLD
#define DECLARE_DEVICE_TYPE(a, b)
#define DEFINE_DEVICE_TYPE(a, b, c, d) static const void *a = nullptr;
#define NAME(x) x, #x
#define STRUCT_MEMBER(s, m) s, #m
#define FUNC(x) &x, #x
enum { STATE_GENPC = -1, STATE_GENPCBASE = -2, STATE_GENFLAGS = -3 };
enum { INPUT_LINE_NMI = 32 };
enum { CLEAR_LINE = 0, ASSERT_LINE = 1 };
enum { AS_PROGRAM = 0, AS_DATA = 1, AS_IO = 2, AS_OPCODES = 3 };

#define WORD_ALIGNED(a) (((a) & 1) == 0)
#define DWORD_ALIGNED(a) (((a) & 3) == 0)
template <typename T> constexpr T make_bitmask(unsigned n) { return n >= sizeof(T) * 8 ? T(~T(0)) : T((T(1) << n) - 1); }
template <typename T> constexpr bool BIT(T x, int n) { return (x >> n) & 1; }
template <typename... T> std::string string_format(const char *f, T... a) { char b[256]; snprintf(b, sizeof b, f, a...); return b; }
template <typename... T> [[noreturn]] void fatalerror(const char *f, T... a) { fprintf(stderr, f, a...); abort(); }

// bus interface of the harness: every memory access of the model goes through one of these
struct musashi_bus_if {
    virtual u16 rd16(int space, offs_t a) = 0;               // space: 0 data, 1 program (opcodes), 2 cpu space
    virtual u8 rd8(int space, offs_t a) = 0;
    virtual void wr16(offs_t a, u16 d, u16 mask) = 0;        // mask: byte lanes written (ff00 / 00ff / ffff)
    // 32-bit-bus forms (MAME init32: the 68020 / 68EC020 models); the 68010 model never calls them. Defaults: composed
    // of the 16-bit accesses
    virtual u16 rd16u(int space, offs_t a) { return (a & 1) ? (u16)((rd8(space, a) << 8) | rd8(space, a + 1)) : rd16(space, a); }
    virtual u32 rd32u(int space, offs_t a) { return ((u32)rd16u(space, a) << 16) | rd16u(space, a + 2); }
    virtual void wr32(offs_t a, u32 d, u32 mask) {           // a: long-aligned; mask: byte lanes (ff000000 = byte 0)
        if (mask >> 16) wr16(a, d >> 16, (u16)(mask >> 16));
        if (mask & 0xffff) wr16(a + 2, d, (u16)mask);
    }
    virtual ~musashi_bus_if() {}
};

class machine_config {};
class device_t;
typedef const void *device_type;
class address_map;
struct address_map_entry {
    template <typename... T> address_map_entry &m(T...) { return *this; }
    template <typename... T> address_map_entry &lr8(T...) { return *this; }
};
class address_map { public: address_map_entry e; address_map_entry &operator()(offs_t, offs_t) { return e; } };
struct address_map_constructor {
    address_map_constructor() {}
    template <typename... T> address_map_constructor(T...) {}
};
class address_space_config {
public:
    address_space_config() {}
    template <typename... T> address_space_config(const char *, endianness_t, u32 dw, u32 aw, T...) : m_aw(aw) {}
    u32 addr_width() const { return m_aw; }
    u32 m_aw = 24;
};

template <int AW, int DW, int AS, endianness_t E> struct memory_access {
    struct base {
        musashi_bus_if *bus = nullptr;
        int space = 0;
        u8 read_byte(offs_t a) { return bus->rd8(space, a); }
        u16 read_word(offs_t a) { return bus->rd16(space, a); }
        u32 read_dword(offs_t a) { u32 h = bus->rd16(space, a); return (h << 16) | bus->rd16(space, a + 2); }
        void write_byte(offs_t a, u8 d) { bus->wr16(a & ~1u, d | (d << 8), (a & 1) ? 0x00ff : 0xff00); }
        void write_word(offs_t a, u16 d, u16 m = 0xffff) { bus->wr16(a, d, m); }
        void write_dword(offs_t a, u32 d) { bus->wr16(a, d >> 16, 0xffff); bus->wr16(a + 2, d, 0xffff); }
        // 32-bit-bus forms (MAME init32: the 68020 / 68EC020 models; never used by the 68010 model)
        u16 read_word_unaligned(offs_t a) { return bus->rd16u(space, a); }
        u32 read_dword_unaligned(offs_t a) { return bus->rd32u(space, a); }
        u32 read_dword(offs_t a, u32) { return read_dword(a); }
        u16 read_word(offs_t a, u16) { return read_word(a); }
        u8 read_byte(offs_t a, u8) { return read_byte(a); }
        void write_dword(offs_t a, u32 d, u32 m) { bus->wr32(a & ~3u, d, m); }
        void write_word_unaligned(offs_t a, u16 d) { write_word(a, d); }
        void write_dword_unaligned(offs_t a, u32 d) { write_dword(a, d); }
    };
    struct cache : base {};
    struct specific : base {};
};

class address_space {
public:
    musashi_bus_if *bus = nullptr;
    int space = 0;
    template <typename C> void cache(C &c) { c.bus = bus; c.space = space == 0 ? 1 : space; }
    template <typename C> void specific(C &c) { c.bus = bus; c.space = space; }
    u8 read_byte(offs_t a) { return bus->rd8(space, a); }
    u16 read_word(offs_t a, u16 = 0xffff) { return bus->rd16(space, a); }
    u32 read_dword(offs_t a) { u32 h = bus->rd16(space, a); return (h << 16) | bus->rd16(space, a + 2); }
    void write_dword(offs_t a, u32 d) { bus->wr16(a, d >> 16, 0xffff); bus->wr16(a + 2, d, 0xffff); }
};

class device_state_entry {
public:
    int index() const { return 0; }
    template <typename... T> device_state_entry &mask(T...) { return *this; }
    device_state_entry &callimport() { return *this; }
    device_state_entry &callexport() { return *this; }
    device_state_entry &noshow() { return *this; }
    template <typename... T> device_state_entry &formatstr(T...) { return *this; }
};
namespace util {
class disasm_interface {
public:
    class data_buffer { public: u8 r8(offs_t) const { return 0; } u16 r16(offs_t) const { return 0; } u32 r32(offs_t) const { return 0; } };
    virtual ~disasm_interface() {}
    virtual u32 opcode_alignment() const = 0;
    virtual offs_t disassemble(std::ostream &stream, offs_t pc, const data_buffer &opcodes, const data_buffer &params) = 0;
};
}
struct running_machine { bool side_effects_disabled() const { return false; } };
struct devcb_write_line {
    devcb_write_line(device_t &) {}
    devcb_write_line &bind() { return *this; }
    void operator()(int) {}
};

class device_t {
public:
    device_t(const machine_config &, device_type, const char *, device_t *, u32) {}
    virtual ~device_t() {}
    void debugger_exception_hook(int) {}
    void debugger_instruction_hook(offs_t) {}
    void debugger_privilege_hook() {}
    void debugger_wait_hook() {}
    template <typename... T> void logerror(T...) {}
    int standard_irq_callback(int, offs_t) { return 0; }
    const char *tag() const { return "m68010"; }
    running_machine m_machine;
    running_machine &machine() { return m_machine; }
    const running_machine &machine() const { return m_machine; }
    template <typename... T> void save_item(T...) {}
    virtual void device_start() {}
    virtual void device_reset() {}
    virtual void device_stop() {}
    virtual void device_pre_save() {}
    virtual void device_post_load() {}
};
class device_memory_interface {
public:
    using space_config_vector = std::vector<std::pair<int, const address_space_config *>>;
};
class cpu_device : public device_t {
public:
    using space_config_vector = device_memory_interface::space_config_vector;
    cpu_device(const machine_config &m, device_type t, const char *tag, device_t *o, u32 c) : device_t(m, t, tag, o, c) {}
    virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }
    virtual u32 execute_min_cycles() const noexcept { return 1; }
    virtual u32 execute_max_cycles() const noexcept { return 1; }
    virtual bool execute_input_edge_triggered(int) const noexcept { return false; }
    virtual void execute_run() {}
    virtual void execute_set_input(int, int) {}
    virtual void state_import(const device_state_entry &) {}
    virtual void state_export(const device_state_entry &) {}
    virtual void state_string_export(const device_state_entry &, std::string &) const {}
    virtual space_config_vector memory_space_config() const { return {}; }
    virtual bool memory_translate(int, int, offs_t &, address_space *&) { return false; }
    // address spaces of the harness: program / opcodes / cpu space, all on the same bus interface
    address_space m_spaces[8];
    address_space &space(int n = 0) { return m_spaces[n & 7]; }
    bool has_space(int n) const { return n != AS_OPCODES; }
    bool has_configured_map(int) const { return false; }
    int *m_icountptr = nullptr;
    void set_icountptr(int &c) { m_icountptr = &c; }
    template <typename... T> device_state_entry &state_add(T...) { static device_state_entry e; return e; }
};

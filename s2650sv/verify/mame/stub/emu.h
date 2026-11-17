// Minimal stand-in for MAME's device framework, just enough to compile the unmodified
// src/devices/cpu/s2650/s2650.cpp as a standalone instruction-level oracle (verification only).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <ostream>
#include <type_traits>
#include <utility>

typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32; typedef uint64_t u64;
typedef int8_t s8; typedef int16_t s16; typedef int32_t s32;
typedef uint32_t offs_t;
enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };
enum { AS_PROGRAM = 0, AS_DATA = 1, AS_IO = 2 };
enum { CLEAR_LINE = 0, ASSERT_LINE = 1 };
enum { INPUT_LINE_IRQ0 = 0, INPUT_LINE_IRQ1 = 1 };
enum { STATE_GENPC = -1, STATE_GENPCBASE = -2, STATE_GENFLAGS = -3 };
#define ATTR_COLD
#define NAME(x) x
typedef int device_type;
#define DECLARE_DEVICE_TYPE(Type, Class) extern const device_type Type;
#define DEFINE_DEVICE_TYPE(Type, Class, Short, Full) const device_type Type = 2650;

// Bus hooks provided by the harness
uint8_t mame_bus_read(int space, offs_t a);
void mame_bus_write(int space, offs_t a, uint8_t d);

namespace util {
template <typename T, typename U> constexpr std::make_signed_t<T> sext(T value, U width) {
    using S = std::make_signed_t<T>;
    const unsigned n = sizeof(T) * 8 - unsigned(width);
    return S(S(std::make_unsigned_t<T>(value) << n) >> n);
}
class disasm_interface {
public:
    enum { PAGED = 1 };
    struct data_buffer {};
    virtual ~disasm_interface() = default;
    virtual u32 opcode_alignment() const = 0;
    virtual u32 interface_flags() const { return 0; }
    virtual u32 page_address_bits() const { return 0; }
    virtual offs_t disassemble(std::ostream &stream, offs_t pc, const data_buffer &opcodes, const data_buffer &params) = 0;
};
}

template <typename... A> inline std::string string_format(const char *f, A... a) {
    char b[256]; snprintf(b, sizeof b, f, a...); return b;
}

struct machine_config {};
class device_t;
struct address_space_config {
    address_space_config(const char *, endianness_t, int, int) {}
};
typedef std::vector<std::pair<int, const address_space_config *>> space_config_vector;
struct device_memory_interface { typedef ::space_config_vector space_config_vector; };

template <int H, int W, int S, endianness_t E> struct memory_access {
    struct cache    { int sp = 0; u8 read_byte(offs_t a) { return mame_bus_read(sp, a); } };
    struct specific {
        int sp = 0;
        u8 read_byte(offs_t a) { return mame_bus_read(sp, a); }
        void write_byte(offs_t a, u8 d) { mame_bus_write(sp, a, d); }
    };
};
struct address_space_stub {
    int sp;
    template <typename T> void cache(T &c) { c.sp = sp; }
    template <typename T> void specific(T &c) { c.sp = sp; }
};

struct devcb_read_line {
    std::function<int()> fn; int def;
    devcb_read_line(device_t &, int d) : def(d) {}
    bool isunset() const { return !fn; }
    int operator()() { return fn ? fn() : def; }
    devcb_read_line &bind() { return *this; }
};
struct devcb_write_line {
    std::function<void(int)> fn;
    devcb_write_line(device_t &) {}
    void operator()(int s) { if (fn) fn(s); }
    devcb_write_line &bind() { return *this; }
};
struct devcb_read8 {
    std::function<u8()> fn; u8 def;
    devcb_read8(device_t &, u8 d) : def(d) {}
    u8 operator()() { return fn ? fn() : def; }
    devcb_read8 &bind() { return *this; }
};

struct device_state_entry {
    int idx;
    int index() const { return idx; }
};
struct state_entry_stub {
    state_entry_stub &callimport() { return *this; }
    state_entry_stub &callexport() { return *this; }
    state_entry_stub &noshow() { return *this; }
    state_entry_stub &formatstr(const char *) { return *this; }
    state_entry_stub &mask(u64) { return *this; }
};

class device_t {
public:
    virtual ~device_t() = default;
    const char *tag() const { return "s2650"; }
};

class cpu_device : public device_t {
public:
    cpu_device(const machine_config &, device_type, const char *, device_t *, u32) {}
    virtual void device_start() {}
    virtual void device_reset() {}
    virtual u32 execute_min_cycles() const noexcept { return 1; }
    virtual u32 execute_max_cycles() const noexcept { return 1; }
    virtual u32 execute_default_irq_vector(int) const noexcept { return 0; }
    virtual void execute_run() {}
    virtual void execute_set_input(int, int) {}
    virtual space_config_vector memory_space_config() const { return {}; }
    virtual void state_import(const device_state_entry &) {}
    virtual void state_export(const device_state_entry &) {}
    virtual void state_string_export(const device_state_entry &, std::string &) const {}
    virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }
    virtual bool get_z80_mnemonics_mode() const { return false; }
protected:
    address_space_stub space(int n) { return address_space_stub{n}; }
    template <typename T> void save_item(T &) {}
    template <typename T> state_entry_stub state_add(int, const char *, T &) { return {}; }
    void set_icountptr(int &) {}
    void debugger_instruction_hook(offs_t) {}
    void standard_irq_callback(int, offs_t) {}
    void logerror(const char *, ...) {}
};

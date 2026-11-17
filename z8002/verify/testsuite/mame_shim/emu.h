// Minimal MAME framework shim, 2026-08-20.
//
// PURPOSE: let MAME's *completely unmodified* cpu/z8000 sources compile and run
// standalone, so they can serve as the execution oracle for the z8002 test suite.
// Nothing in "Useful Stuff/mame/z8000/" is edited or copied -- z8000.cpp does
// #include "emu.h", which resolves to THIS file via -I, because a quoted include
// searches the including file's own directory first (no emu.h there) and then -I.
//
// This provides only the surface z8000.cpp / z8000.h / 8000dasm.h actually touch.
// It is NOT a MAME emulation layer: no timing, no scheduler, no save states.
// The only semantically meaningful part is the memory model at the bottom, which
// is deliberately laid out to match verilator/z8002_optest/z8002_optest_tb.sv:
// word-indexed storage, big-endian byte order within the word.

#ifndef MAME_SHIM_EMU_H
#define MAME_SHIM_EMU_H

#pragma once

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cassert>
#include <string>
#include <memory>
#include <vector>
#include <utility>
#include <ostream>

// ---------------------------------------------------------------- basic types

using u8  = uint8_t;
using u16 = uint16_t;
using u32 = uint32_t;
using u64 = uint64_t;
using s8  = int8_t;
using s16 = int16_t;
using s32 = int32_t;
using s64 = int64_t;
using offs_t = uint32_t;

#define ATTR_COLD
#define ATTR_PRINTF(x, y)

// --------------------------------------------------------------- host endian
// The register-file macros in z8000cpu.h index a union of B[16]/W[16]/L[8]/Q[4]
// through these, to place R0 in the MOST significant half of RR0/RQ0 on a
// little-endian host. Getting these wrong silently permutes every register, so
// the host assumption is asserted rather than guessed.

#if defined(__BYTE_ORDER__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#error "mame_shim/emu.h assumes a little-endian host (see BYTE*_XOR_BE below)"
#endif

#define BYTE_XOR_BE(a)   ((a) ^ 1)
#define BYTE4_XOR_BE(a)  ((a) ^ 3)
#define BYTE8_XOR_BE(a)  ((a) ^ 7)
#define BYTE_XOR_LE(a)   (a)
#define BYTE4_XOR_LE(a)  (a)
#define BYTE8_XOR_LE(a)  (a)

static inline u16 swapendian_int16(u16 val)
{
	return ((val >> 8) & 0x00ff) | ((val << 8) & 0xff00);
}

template <typename T, typename U> constexpr T BIT(T x, U n) { return (x >> n) & T(1); }

enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };

// ------------------------------------------------------------- string / log

namespace util {

template <typename... Args>
std::string string_format_impl(const char *fmt, Args... args)
{
	char buf[1024];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-security"
#pragma GCC diagnostic ignored "-Wformat-nonliteral"
	snprintf(buf, sizeof(buf), fmt, args...);
#pragma GCC diagnostic pop
	return std::string(buf);
}

template <typename... Args>
void stream_format(std::ostream &os, const char *fmt, Args... args)
{
	os << string_format_impl(fmt, args...);
}

} // namespace util

template <typename... Args>
std::string string_format(const char *fmt, Args... args)
{
	return util::string_format_impl(fmt, args...);
}

// ------------------------------------------------------- disassembler iface
// 8000dasm.h derives from this. Kept faithful enough that MAME's real
// 8000dasm.cpp compiles against it unmodified (it is linked in, so failing
// tests can be reported with a real mnemonic instead of a bare opcode word).

namespace util {

class disasm_interface
{
public:
	virtual ~disasm_interface() = default;

	class data_buffer
	{
	public:
		virtual ~data_buffer() = default;
		virtual u8  r8 (offs_t pc) const = 0;
		virtual u16 r16(offs_t pc) const = 0;
		virtual u32 r32(offs_t pc) const = 0;
		virtual u64 r64(offs_t pc) const = 0;
	};

	static constexpr u32 SUPPORTED  = 0x80000000;
	static constexpr u32 STEP_OUT   = 0x40000000;
	static constexpr u32 STEP_OVER  = 0x20000000;
	static constexpr u32 STEP_COND  = 0x10000000;

	virtual u32 opcode_alignment() const = 0;
	virtual offs_t disassemble(std::ostream &stream, offs_t pc,
	                           const data_buffer &opcodes, const data_buffer &params) = 0;
};

} // namespace util

// 8000dasm.cpp writes these unqualified inside member functions.
static constexpr u32 SUPPORTED = util::disasm_interface::SUPPORTED;
static constexpr u32 STEP_OUT  = util::disasm_interface::STEP_OUT;
static constexpr u32 STEP_OVER = util::disasm_interface::STEP_OVER;
static constexpr u32 STEP_COND = util::disasm_interface::STEP_COND;

// ------------------------------------------------------------- device types

struct device_type
{
	const char *name;
	explicit device_type(const char *n = "") : name(n) {}
};

#define DECLARE_DEVICE_TYPE(Type, Class) extern const device_type Type;
#define DEFINE_DEVICE_TYPE(Type, Class, ShortName, FullName) \
	const device_type Type = device_type(ShortName);

class machine_config { };
class device_t;

// ------------------------------------------------------------- memory model
// Backing store shared by every address space. Word-indexed and big-endian
// within the word, matching z8002_optest_tb.sv's `reg [15:0] mem [0:32767]`
// addressed as mem[addr[15:1]]. A byte at an EVEN address is the high byte.

struct shim_memory
{
	static constexpr u32 WORDS = 0x8000;   // 64 KB address space, 16-bit bus

	u16 prog[WORDS];
	u16 io[WORDS];

	// Every write the CPU performs, in order. This is what gets diffed against
	// the RTL's bus transactions -- final memory state alone would miss a write
	// of the correct value to the correct place at the wrong width.
	struct write_rec { u32 addr; u16 data; u16 mask; bool is_io; };
	write_rec writes[64];
	unsigned  n_writes;
	bool      write_overflow;

	void clear()
	{
		memset(prog, 0, sizeof(prog));
		memset(io, 0, sizeof(io));
		clear_writes();
	}
	void clear_writes() { n_writes = 0; write_overflow = false; }

	void log_write(u32 addr, u16 data, u16 mask, bool is_io)
	{
		if (n_writes < (sizeof(writes) / sizeof(writes[0])))
			writes[n_writes++] = { addr, data, mask, is_io };
		else
			write_overflow = true;
	}
};

class shim_space
{
public:
	shim_space() : m_mem(nullptr), m_store(nullptr), m_is_io(false) { }

	void bind(shim_memory *mem, u16 *store, bool is_io)
	{
		m_mem = mem; m_store = store; m_is_io = is_io;
	}

	u32 addrmask() const { return 0xffff; }

	u16 read_word(offs_t addr) const           { return m_store[(addr & 0xffff) >> 1]; }
	u16 read_word(offs_t addr, u16 mask) const { return read_word(addr) & mask; }

	u8 read_byte(offs_t addr) const
	{
		u16 w = read_word(addr & ~1);
		return (addr & 1) ? (w & 0xff) : (w >> 8);   // big-endian: even addr = high byte
	}

	void write_word(offs_t addr, u16 data, u16 mask = 0xffff)
	{
		u32 a = addr & 0xfffe;
		m_store[a >> 1] = (m_store[a >> 1] & ~mask) | (data & mask);
		m_mem->log_write(a, data, mask, m_is_io);
	}

	// z8000.cpp calls state_add(...).mask(m_program.space().addrmask())
	const shim_space &space() const { return *this; }

	// init_spaces() binds the device's cached accessors from an address_space
	template <typename T> void cache(T &target)    { target.bind(m_mem, m_store, m_is_io); }
	template <typename T> void specific(T &target) { target.bind(m_mem, m_store, m_is_io); }

private:
	shim_memory *m_mem;
	u16         *m_store;
	bool         m_is_io;
};

using address_space = shim_space;

template <int AddrBits, int DataWidth, int AddrShift, endianness_t Endian>
struct memory_access
{
	using specific = shim_space;
	using cache    = shim_space;
};

class address_space_config
{
public:
	address_space_config(const char *, endianness_t, int, int, int) { }
};

using space_config_vector = std::vector<std::pair<int, const address_space_config *>>;

// z8000.cpp defines memory_space_config() with the interface-qualified return type.
class device_memory_interface
{
public:
	using space_config_vector = ::space_config_vector;
};

enum
{
	AS_PROGRAM = 0,
	AS_DATA    = 1,
	AS_IO      = 2,
	AS_OPCODES = 3
};

// ------------------------------------------------------------------- devcb

class devcb_read16
{
public:
	template <unsigned N> class array
	{
	public:
		template <typename Owner> array(Owner &, u16 defval) : m_defval(defval) { }
		class entry
		{
		public:
			explicit entry(u16 d) : m_defval(d) { }
			u16 operator()(offs_t) const { return m_defval; }
			int bind() { return 0; }
		private:
			u16 m_defval;
		};
		entry operator[](unsigned) const { return entry(m_defval); }
	private:
		u16 m_defval;
	};
};

class devcb_write_line
{
public:
	template <typename Owner> explicit devcb_write_line(Owner &) { }
	void operator()(int) const { }
	int bind() { return 0; }
};

// ------------------------------------------------------------- device state

enum
{
	STATE_GENPC     = -1,
	STATE_GENPCBASE = -2,
	STATE_GENFLAGS  = -3
};

class device_state_entry
{
public:
	explicit device_state_entry(int index) : m_index(index) { }
	int index() const { return m_index; }

	device_state_entry &mask(u64)              { return *this; }
	device_state_entry &formatstr(const char *) { return *this; }
	device_state_entry &noshow()               { return *this; }
	device_state_entry &callimport()           { return *this; }
	device_state_entry &callexport()           { return *this; }

private:
	int m_index;
};

// ------------------------------------------------------------ execute iface

constexpr int CLEAR_LINE      = 0;
constexpr int ASSERT_LINE     = 1;
constexpr int HOLD_LINE       = 2;
constexpr int INPUT_LINE_NMI  = 61;   // value is irrelevant here, only distinctness

#define NAME(x) x

// ------------------------------------------------------------- device_t/cpu

class device_t
{
public:
	virtual ~device_t() = default;
	machine_config &machine() const { static machine_config m; return m; }

	template <typename... Args> void logerror(Args &&...) const { }
};

class cpu_device : public device_t
{
public:
	cpu_device(const machine_config &, device_type, const char *, device_t *, u32) { }

	// --- memory ---------------------------------------------------------
	// The oracle installs its backing store here before calling device_start().
	void shim_install_memory(shim_memory *mem)
	{
		m_shim_mem = mem;
		m_shim_spaces[AS_PROGRAM].bind(mem, mem->prog, false);
		m_shim_spaces[AS_IO].bind(mem, mem->io, true);
	}
	shim_memory *shim_mem() const { return m_shim_mem; }

	address_space &space(int n)          { return m_shim_spaces[n]; }
	bool has_space(int n) const          { return n == AS_PROGRAM || n == AS_IO; }
	bool has_configured_map(int) const   { return false; }

	// --- stubs ----------------------------------------------------------
	template <typename T> void set_icountptr(T &) { }
	void debugger_instruction_hook(offs_t) { }
	void debugger_wait_hook() { }
	u8 standard_irq_callback(int, offs_t) { return 0; }

	template <typename T>
	device_state_entry &state_add(int index, const char *, T &)
	{
		m_state_entries.push_back(std::make_unique<device_state_entry>(index));
		return *m_state_entries.back();
	}

	template <typename T> void save_item(T &&) { }

protected:
	virtual void device_start() { }
	virtual void device_reset() { }

	virtual u32  execute_min_cycles() const noexcept { return 1; }
	virtual u32  execute_max_cycles() const noexcept { return 1; }
	virtual u32  execute_default_irq_vector(int) const noexcept { return 0; }
	virtual bool execute_input_edge_triggered(int) const noexcept { return false; }
	virtual void execute_run() { }
	virtual void execute_set_input(int, int) { }

	virtual space_config_vector memory_space_config() const { return space_config_vector(); }
	virtual void state_string_export(const device_state_entry &, std::string &) const { }
	virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }

private:
	shim_memory   *m_shim_mem = nullptr;
	address_space  m_shim_spaces[8];
	std::vector<std::unique_ptr<device_state_entry>> m_state_entries;
};

#endif // MAME_SHIM_EMU_H

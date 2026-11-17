// MAME framework shim for the MB88xx differential test suite.
//
// Purpose: let MAME's cpu/mb88xx sources compile and run COMPLETELY UNMODIFIED
// as the oracle. Nothing here reimplements MB88 behaviour -- this is only the
// slice of MAME framework surface that mb88xx.cpp / mb88dasm.cpp actually touch.
// A hand-transcribed oracle would carry hand-transcribed bugs, which is the whole
// reason the z8002 suite was built this way.
//
// Two shim-specific tricks make the oracle observable without touching MAME:
//
//   1. Every MB88 state member is `private`, so a subclass cannot read it.
//      But device_start() calls save_item(NAME(m_PC)) etc. for ALL of them, and
//      the shim owns both NAME() and save_item(). NAME(x) is redefined to capture
//      (name, address, size), so save_item builds a complete name -> address map
//      of the oracle's entire architectural state. No `#define private public`
//      hack, no ODR violation.
//
//   2. set_icountptr(m_icount) hands us the cycle counter, so step() can run
//      exactly one instruction and report the cycles MAME charged for it.
//
// Ports are real here (unlike the z8002 shim's stubs): the K/R/SI inputs carry
// per-test seeded values, and O/P/R/SO writes are logged so they can be diffed
// against the RTL's port activity.

#ifndef MAME_SHIM_EMU_H
#define MAME_SHIM_EMU_H

#include <cstdint>
#include <cstring>
#include <cstdio>
#include <string>
#include <vector>
#include <memory>
#include <ostream>
#include <utility>

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

enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };

template <typename T, typename U> constexpr T BIT(T x, U n) { return (x >> n) & T(1); }

// mb88xx.cpp uses these two out of MAME's util layer.
template <typename... A>
inline std::string string_format(const char *fmt, A... a)
{
	char b[256];
	snprintf(b, sizeof b, fmt, a...);
	return std::string(b);
}

// Thrown, not aborted: pio_enable() fatalerrors on an unsupported serial-enable
// value, which a randomised pio context can legitimately produce. The suite
// catches this and records the test as EXCLUDED rather than crashing the run.
struct shim_fatal { std::string msg; };
template <typename... A>
[[noreturn]] inline void fatalerror(const char *fmt, A... a)
{
	char b[512];
	snprintf(b, sizeof b, fmt, a...);
	throw shim_fatal{ std::string(b) };
}

// ------------------------------------------------------- disassembler iface
namespace util {

// mb88dasm.cpp formats its output through this.
template <typename... A>
inline void stream_format(std::ostream &os, const char *fmt, A... a)
{
	char b[256];
	snprintf(b, sizeof b, fmt, a...);
	os << b;
}

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

#define FUNC(x) #x

// ------------------------------------------------------------- memory model
// MB88 is Harvard: byte-wide program ROM (up to 11-bit address) and a nibble
// data RAM (up to 7-bit address). Both are plain arrays here; the RTL's
// mb88_core.sv models data RAM as reg [3:0] ram[0:127], same shape.

struct shim_memory
{
	static constexpr u32 PROG_SIZE = 2048;   // 11-bit program space
	static constexpr u32 DATA_SIZE = 128;    // 7-bit nibble data space

	u8 prog[PROG_SIZE];
	u8 data[DATA_SIZE];

	// Data-RAM writes in order. Final RAM content is also compared, but the
	// transaction list catches a right-value/right-place/wrong-time write.
	struct write_rec { u8 addr; u8 val; };
	write_rec writes[64];
	unsigned  n_writes;
	bool      write_overflow;

	void clear()
	{
		memset(prog, 0, sizeof(prog));
		memset(data, 0, sizeof(data));
		clear_writes();
	}
	void clear_writes() { n_writes = 0; write_overflow = false; }
	void log_write(u8 a, u8 v)
	{
		if (n_writes < (sizeof(writes) / sizeof(writes[0]))) writes[n_writes++] = { a, v };
		else write_overflow = true;
	}
};

// ------------------------------------------------------------------- ports
// Inputs are supplied per test; outputs are logged. Distinguishing which port a
// write came from is done by CALL SIGNATURE, not construction order:
//   m_write_o(0, val, mask) -> 3 args -> O      (mb88xx.cpp write_pla)
//   m_write_p(val)          -> 1 arg  -> P
//   m_write_r[i](val)       -> array entry     -> R[i]
//   m_write_so(state)       -> write_line      -> SO
// That stays correct even if MAME reorders the member initialiser list.

struct shim_ports
{
	// inputs
	u8 k    = 0;
	u8 r_in[4] = { 0, 0, 0, 0 };
	int si  = 0;

	enum { PORT_O = 0, PORT_P = 1, PORT_R = 2, PORT_SO = 3 };
	struct wrec { u8 kind; u8 idx; u8 val; };
	wrec     writes[64];
	unsigned n_writes = 0;
	bool     overflow = false;

	void clear_writes() { n_writes = 0; overflow = false; }
	void log(u8 kind, u8 idx, u8 val)
	{
		if (n_writes < (sizeof(writes) / sizeof(writes[0]))) writes[n_writes++] = { kind, idx, val };
		else overflow = true;
	}
};

// The active port context. The oracle points this at its own instance.
inline shim_ports *&shim_port_ctx() { static shim_ports *p = nullptr; return p; }

class shim_space
{
public:
	void bind(shim_memory *mem, u8 *store, u32 mask, bool log)
	{
		m_mem = mem; m_store = store; m_mask = mask; m_log = log;
	}

	u32 addrmask() const { return m_mask; }

	u8   read_byte(offs_t a) const { return m_store[a & m_mask]; }
	void write_byte(offs_t a, u8 v)
	{
		m_store[a & m_mask] = v;
		if (m_log) m_mem->log_write(u8(a & m_mask), v);
	}

	const shim_space &space() const { return *this; }

	template <typename T> void cache(T &t)    { t.bind(m_mem, m_store, m_mask, m_log); }
	template <typename T> void specific(T &t) { t.bind(m_mem, m_store, m_mask, m_log); }

private:
	shim_memory *m_mem   = nullptr;
	u8          *m_store = nullptr;
	u32          m_mask  = 0;
	bool         m_log   = false;
};

using address_space = shim_space;

template <int AddrBits, int DataWidth, int AddrShift, endianness_t Endian>
struct memory_access
{
	using specific = shim_space;
	using cache    = shim_space;
};

// address_map is only exercised by the data_Nbit/program_Nbit config helpers,
// which never run in the suite (the oracle installs memory directly).
class address_map_entry
{
public:
	address_map_entry &ram() { return *this; }
	address_map_entry &rom() { return *this; }
};

class address_map
{
public:
	address_map_entry operator()(offs_t, offs_t) { return address_map_entry(); }
};

class address_map_constructor
{
public:
	address_map_constructor() = default;
	template <typename... A> address_map_constructor(A &&...) { }
};

class address_space_config
{
public:
	address_space_config() = default;
	address_space_config(const char *, endianness_t, int, int, int) { }
	address_space_config(const char *, endianness_t, int, int, int, address_map_constructor) { }
};

using space_config_vector = std::vector<std::pair<int, const address_space_config *>>;

class device_memory_interface
{
public:
	using space_config_vector = ::space_config_vector;
};

enum { AS_PROGRAM = 0, AS_DATA = 1, AS_IO = 2, AS_OPCODES = 3 };

// ------------------------------------------------------------------- devcb

class devcb_read8
{
public:
	template <typename Owner> devcb_read8(Owner &, u8 defval = 0) : m_defval(defval) { }

	// scalar read8 is only m_read_k
	u8 operator()() const
	{
		shim_ports *p = shim_port_ctx();
		return p ? p->k : m_defval;
	}
	int bind() { return 0; }

	template <unsigned N> class array
	{
	public:
		template <typename Owner> array(Owner &, u8 defval = 0) : m_defval(defval) { }
		class entry
		{
		public:
			entry(unsigned i, u8 d) : m_i(i), m_defval(d) { }
			u8 operator()() const
			{
				shim_ports *p = shim_port_ctx();
				return p ? p->r_in[m_i & 3] : m_defval;
			}
			int bind() { return 0; }
		private:
			unsigned m_i; u8 m_defval;
		};
		entry operator[](unsigned i) const { return entry(i, m_defval); }
	private:
		u8 m_defval;
	};

private:
	u8 m_defval;
};

class devcb_write8
{
public:
	template <typename Owner> explicit devcb_write8(Owner &) { }

	// 3-arg form = the O port (write_pla)
	void operator()(offs_t, u8 data, u8 = 0xff) const
	{
		if (shim_ports *p = shim_port_ctx()) p->log(shim_ports::PORT_O, 0, data & 0xff);
	}
	// 1-arg form = the P port
	void operator()(u8 data) const
	{
		if (shim_ports *p = shim_port_ctx()) p->log(shim_ports::PORT_P, 0, data & 0x0f);
	}
	int bind() { return 0; }

	template <unsigned N> class array
	{
	public:
		template <typename Owner> explicit array(Owner &) { }
		class entry
		{
		public:
			explicit entry(unsigned i) : m_i(i) { }
			void operator()(u8 data) const
			{
				if (shim_ports *p = shim_port_ctx())
					p->log(shim_ports::PORT_R, u8(m_i & 3), data & 0x0f);
			}
			int bind() { return 0; }
		private:
			unsigned m_i;
		};
		entry operator[](unsigned i) const { return entry(i); }
	};
};

class devcb_read_line
{
public:
	template <typename Owner> devcb_read_line(Owner &, int defval = 0) : m_defval(defval) { }
	int operator()() const
	{
		shim_ports *p = shim_port_ctx();
		return p ? p->si : m_defval;
	}
	int bind() { return 0; }
private:
	int m_defval;
};

class devcb_write_line
{
public:
	template <typename Owner> explicit devcb_write_line(Owner &) { }
	void operator()(int state) const
	{
		if (shim_ports *p = shim_port_ctx()) p->log(shim_ports::PORT_SO, 0, u8(state & 1));
	}
	int bind() { return 0; }
};

// ------------------------------------------------------------------ timers
// The serial engine is out of scope for the suite (see README); the timer is
// allocated but never fires, so serial-dependent opcodes are excluded rather
// than compared against a fabricated schedule.

struct attotime
{
	u64 ticks = 0;
	bool never_flag = false;
	static attotime from_hz(double)  { return attotime{ 0, false }; }
	static const attotime never;
	attotime() = default;
	attotime(u64 a, u64 b) : ticks(b) { (void)a; }
};
inline const attotime attotime::never = attotime{ 0, true };

class emu_timer
{
public:
	void adjust(attotime, int = 0, attotime = attotime()) { }
};

#define TIMER_CALLBACK_MEMBER(name) void name(s32 param)

// ------------------------------------------------------------- device state
enum { STATE_GENPC = -1, STATE_GENPCBASE = -2, STATE_GENFLAGS = -3 };

class device_state_entry
{
public:
	explicit device_state_entry(int index) : m_index(index) { }
	int index() const { return m_index; }

	device_state_entry &mask(u64)               { return *this; }
	device_state_entry &formatstr(const char *) { return *this; }
	device_state_entry &noshow()                { return *this; }
	device_state_entry &callimport()            { return *this; }
	device_state_entry &callexport()            { return *this; }

private:
	int m_index;
};

constexpr int CLEAR_LINE  = 0;
constexpr int ASSERT_LINE = 1;
constexpr int HOLD_LINE   = 2;

// ---- the save_item capture trick (see header comment) ----------------------
struct shim_named
{
	const char *name;
	void       *ptr;
	size_t      size;
};
template <typename T>
inline shim_named shim_make_named(const char *n, T *p) { return shim_named{ n, (void *)p, sizeof(T) }; }

#define NAME(x) shim_make_named(#x, &(x))

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
	cpu_device(const machine_config &, device_type, const char *, device_t *, u32 clk)
		: m_shim_clock(clk) { }

	// The oracle installs its backing store before calling device_start().
	void shim_install_memory(shim_memory *mem)
	{
		m_shim_mem = mem;
		m_shim_spaces[AS_PROGRAM].bind(mem, mem->prog, shim_memory::PROG_SIZE - 1, false);
		m_shim_spaces[AS_DATA].bind(mem, mem->data, shim_memory::DATA_SIZE - 1, true);
	}
	shim_memory *shim_mem() const { return m_shim_mem; }

	address_space &space(int n)        { return m_shim_spaces[n]; }
	bool has_space(int n) const        { return n == AS_PROGRAM || n == AS_DATA; }
	bool has_configured_map(int) const { return false; }

	u32 clock() const { return m_shim_clock; }

	// --- stubs ----------------------------------------------------------
	void debugger_instruction_hook(offs_t) { }
	void debugger_wait_hook() { }
	u8   standard_irq_callback(int, offs_t) { return 0; }
	template <typename... A> emu_timer *timer_alloc(A &&...) { return &m_shim_timer; }

	// --- observability hooks --------------------------------------------
	void set_icountptr(int &ic) { m_shim_icount = &ic; }
	int *shim_icount() const { return m_shim_icount; }

	void save_item(const shim_named &s) { m_shim_saved.push_back(s); }
	template <typename T> void save_item(const T &) { }   // anything not wrapped in NAME()

	// name -> address map of the oracle's whole architectural state
	void *shim_find(const char *name, size_t *size = nullptr) const
	{
		for (const auto &s : m_shim_saved)
			if (!strcmp(s.name, name)) { if (size) *size = s.size; return s.ptr; }
		return nullptr;
	}

	template <typename T>
	device_state_entry &state_add(int index, const char *, T &)
	{
		m_state_entries.push_back(std::make_unique<device_state_entry>(index));
		return *m_state_entries.back();
	}

protected:
	virtual void device_start() { }
	virtual void device_reset() { }

	virtual u32  execute_min_cycles() const noexcept { return 1; }
	virtual u32  execute_max_cycles() const noexcept { return 1; }
	virtual bool execute_input_edge_triggered(int) const noexcept { return false; }
	virtual u64  execute_clocks_to_cycles(u64 c) const noexcept { return c; }
	virtual u64  execute_cycles_to_clocks(u64 c) const noexcept { return c; }
	virtual void execute_run() { }
	virtual void execute_set_input(int, int) { }

	virtual space_config_vector memory_space_config() const { return space_config_vector(); }
	virtual void state_string_export(const device_state_entry &, std::string &) const { }
	virtual void state_import(const device_state_entry &) { }
	virtual void state_export(const device_state_entry &) { }
	virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }

private:
	shim_memory   *m_shim_mem    = nullptr;
	int           *m_shim_icount = nullptr;
	u32            m_shim_clock  = 0;
	emu_timer      m_shim_timer;
	address_space  m_shim_spaces[4];
	std::vector<shim_named> m_shim_saved;
	std::vector<std::unique_ptr<device_state_entry>> m_state_entries;
};

#endif // MAME_SHIM_EMU_H

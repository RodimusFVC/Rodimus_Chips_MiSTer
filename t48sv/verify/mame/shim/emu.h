// Minimal stand-in for MAME's emu.h: just enough of the device / memory /
// callback framework for src/devices/cpu/mcs48/mcs48.cpp to compile unmodified
// and run standalone under a test harness (verify/mame/mame_cmp.cpp).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstdarg>
#include <cstdlib>
#include <string>
#include <vector>
#include <memory>
#include <functional>
#include <utility>
#include <ostream>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int8_t s8;
typedef int16_t s16;
typedef int32_t s32;
typedef int64_t s64;
typedef u32 offs_t;

#define ATTR_COLD
#define NAME(x) x, #x
#define FUNC(x) &x, #x
#define CLEAR_LINE 0
#define ASSERT_LINE 1
#define TIMER_CALLBACK_MEMBER(name) void name(s32 param)

enum endianness_t { ENDIANNESS_LITTLE, ENDIANNESS_BIG };
enum { AS_PROGRAM = 0, AS_DATA = 1, AS_IO = 2 };
enum { STATE_GENPC = -1, STATE_GENPCBASE = -2, STATE_GENFLAGS = -3 };

[[noreturn]] inline void fatalerror(const char *fmt, ...) {
  va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap); abort();
}
template <typename... T> std::string string_format(const char *fmt, T... args) {
  char b[256]; snprintf(b, sizeof b, fmt, args...); return b;
}

// ---------------------------------------------------------------- harness hooks
struct mcs48_harness {
  virtual ~mcs48_harness() = default;
  virtual u8 prog_r(offs_t a) = 0;
  virtual u8 io_r(offs_t a) = 0;
  virtual void io_w(offs_t a, u8 v) = 0;
  virtual u8 port_r(int p) = 0;
  virtual void port_w(int p, u8 v) = 0;
  virtual u8 bus_r() = 0;
  virtual void bus_w(u8 v) = 0;
  virtual int test_r(int t) = 0;
  virtual void prog_w(int v) = 0;
};
extern mcs48_harness *g_harness;
extern u8 g_ram[256];

class device_t;
class machine_config {};
typedef const void *device_type;
#define DEFINE_DEVICE_TYPE(t, c, s, n) const device_type t = #s;
#define DECLARE_DEVICE_TYPE(t, c) extern const device_type t;

struct device_state_entry { int index() const { return 0; } };
struct state_add_ret {
  state_add_ret &mask(u64) { return *this; }
  state_add_ret &noshow() { return *this; }
  state_add_ret &formatstr(const char *) { return *this; }
  state_add_ret &callimport() { return *this; }
  state_add_ret &callexport() { return *this; }
};

namespace util {
class disasm_interface { public: virtual ~disasm_interface() = default; };
}

// ---------------------------------------------------------------- memory
template <int Width, int AddrShift, int Level, endianness_t E> struct memory_access {
  struct cache { u8 read_byte(offs_t a) { return g_harness->prog_r(a); } };
  struct specific {
    int space = 0;
    u8 read_byte(offs_t a) { return space == AS_DATA ? g_ram[a & 0xff] : g_harness->io_r(a); }
    void write_byte(offs_t a, u8 v) { if (space == AS_DATA) g_ram[a & 0xff] = v; else g_harness->io_w(a, v); }
  };
};
struct address_space {
  int id;
  template <typename C> void cache(C &) {}
  template <typename S> void specific(S &s) { s.space = id; }
};
struct address_map_entry {
  address_map_entry &rom() { return *this; }
  address_map_entry &ram() { return *this; }
  address_map_entry &share(const char *) { return *this; }
  template <typename V> address_map_entry &view(V &) { return *this; }
};
struct address_map { address_map_entry operator()(offs_t, offs_t) { return {}; } };
struct address_map_constructor {
  address_map_constructor() {}
  template <typename F, typename O> address_map_constructor(F, const char *, O *) {}
};
struct address_space_config {
  address_space_config(const char *, endianness_t, int, int, int, address_map_constructor = {}) {}
};
struct memory_view_entry { address_map_entry operator()(offs_t, offs_t) { return {}; } };
struct memory_view {
  bool ea = false;
  memory_view(device_t &, const char *) {}
  bool exists() const { return true; }
  void disable() { ea = true; }
  void select(int) { ea = false; }
  memory_view_entry operator[](int) { return {}; }
};
struct device_memory_interface {
  typedef std::vector<std::pair<int, const address_space_config *>> space_config_vector;
};
template <typename T> struct required_shared_ptr {
  required_shared_ptr(device_t &, const char *) {}
  T &operator[](int i) { return g_ram[i & 0xff]; }
};

// ---------------------------------------------------------------- callbacks
// p1 / p2 in / out are routed by array index; the owner sets the role
struct devcb_base { int role = 2; };   // 0, 1: P1, P2 (arrays); 2: BUS
struct devcb_read8 : devcb_base {
  devcb_read8() {}
  devcb_read8(device_t &, u8 = 0xff) {}
  u8 operator()(offs_t = 0) const {
    return role < 2 ? g_harness->port_r(role + 1) : g_harness->bus_r();
  }
  devcb_read8 &bind() { return *this; }
  template <int N> struct array {
    devcb_read8 a[N];
    array(device_t &, u8 = 0xff) { for (int i = 0; i < N; i++) a[i].role = i; }
    devcb_read8 &operator[](int i) { return a[i]; }
    const devcb_read8 &operator[](int i) const { return a[i]; }
  };
};
struct devcb_write8 : devcb_base {
  devcb_write8() {}
  devcb_write8(device_t &) {}
  void operator()(u8 v) const { if (role < 2) g_harness->port_w(role + 1, v); else g_harness->bus_w(v); }
  void operator()(offs_t, u8 v, u8 = 0xff) const { (*this)(v); }
  devcb_write8 &bind() { return *this; }
  template <int N> struct array {
    devcb_write8 a[N];
    array(device_t &) { for (int i = 0; i < N; i++) a[i].role = i; }
    devcb_write8 &operator[](int i) { return a[i]; }
    const devcb_write8 &operator[](int i) const { return a[i]; }
  };
};
struct devcb_read_line : devcb_base {
  devcb_read_line() {}
  devcb_read_line(device_t &, int = 0) {}
  int operator()() const { return g_harness->test_r(role); }
  devcb_read_line &bind() { return *this; }
  template <int N> struct array {
    devcb_read_line a[N];
    array(device_t &, int = 0) { for (int i = 0; i < N; i++) a[i].role = i; }
    devcb_read_line &operator[](int i) { return a[i]; }
    const devcb_read_line &operator[](int i) const { return a[i]; }
  };
};
struct devcb_write_line : devcb_base {
  devcb_write_line(device_t &) {}
  void operator()(int v) const { g_harness->prog_w(v); }
  devcb_write_line &bind() { return *this; }
};
struct clock_update_delegate {
  clock_update_delegate(device_t &) {}
  bool isnull() const { return true; }
  void resolve() {}
  template <typename... T> void set(T &&...) {}
  void operator()(u32) const {}
};
struct timer_expired_delegate { template <typename... T> timer_expired_delegate(T &&...) {} };
struct scheduler_t { template <typename D> void synchronize(D, s32 = 0) {} };
struct running_machine { scheduler_t s; scheduler_t &scheduler() { return s; } };

// ---------------------------------------------------------------- device
class device_t {
public:
  device_t(const machine_config &, device_type, const char *, device_t *, u32 clock) : m_clock(clock) {}
  virtual ~device_t() = default;
  u32 clock() const { return m_clock; }
  running_machine &machine() { return m_machine; }
  void logerror(const char *, ...) const {}
  template <typename T> void save_item(T &, const char *) {}
  address_space space(int id) { return address_space{id}; }
  u32 m_clock;
  running_machine m_machine;
protected:
  virtual void device_start() {}
  virtual void device_config_complete() {}
  virtual void device_reset() {}
  virtual void device_post_load() {}
};
class cpu_device : public device_t, public device_memory_interface {
public:
  cpu_device(const machine_config &mc, device_type t, const char *tag, device_t *o, u32 c)
    : device_t(mc, t, tag, o, c) {}
  void set_icountptr(int &) {}
  void standard_irq_callback(int, offs_t) {}
  void debugger_instruction_hook(offs_t) {}
  template <typename T> state_add_ret state_add(int, const char *, T &) { return {}; }
  template <typename T> state_add_ret state_add(int, const std::string &, T &) { return {}; }
protected:
  virtual u64 execute_clocks_to_cycles(u64 c) const noexcept { return c; }
  virtual u64 execute_cycles_to_clocks(u64 c) const noexcept { return c; }
  virtual u32 execute_min_cycles() const noexcept { return 1; }
  virtual u32 execute_max_cycles() const noexcept { return 1; }
  virtual void execute_run() {}
  virtual void execute_set_input(int, int) {}
  virtual device_memory_interface::space_config_vector memory_space_config() const { return {}; }
  virtual void state_import(const device_state_entry &) {}
  virtual void state_export(const device_state_entry &) {}
  virtual void state_string_export(const device_state_entry &, std::string &) const {}
  virtual std::unique_ptr<util::disasm_interface> create_disassembler() { return nullptr; }
};

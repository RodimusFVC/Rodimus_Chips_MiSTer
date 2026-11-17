// The unmodified MAME s2650.cpp, compiled against stub/emu.h, members opened for the harness (verification only)
#include "stub/emu.h"
#define private public
#define protected public
#include MAME_S2650_CPP
#undef private
#undef protected
s2650_disassembler::s2650_disassembler(config *conf) : m_config(conf) {}
offs_t s2650_disassembler::disassemble(std::ostream &, offs_t, const data_buffer &, const data_buffer &) { return 1; }

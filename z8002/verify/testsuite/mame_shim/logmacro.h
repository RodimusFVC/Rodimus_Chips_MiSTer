// Shim for MAME's logmacro.h -- see mame_shim/emu.h.
#ifndef MAME_SHIM_LOGMACRO_H
#define MAME_SHIM_LOGMACRO_H
#pragma once
#define LOG(...)            do { } while (0)
#define LOGMASKED(mask, ...) do { } while (0)
#define VERBOSE 0
#endif

// Copyright (C) 2026 Rodimus
// API of the standalone MAME m68000 / m68008 model (mame_model.cpp); harness only. Own code.
#pragma once
#include <cstdint>
#include <vector>

struct mame_access {
    int time = 0;              // CPU clocks from the start of step() to the start (S0) of this bus cycle
    int fc = 0;
    bool wr = false, iack = false;
    int size = 2;              // 1 byte, 2 word (68008: always 1)
    uint32_t addr = 0;         // byte address (odd for a low-byte access)
    uint16_t val = 0;
};
struct mame_state { uint32_t r[17]; uint16_t sr; uint32_t pc; uint16_t ir, irc; };   // r: D0-D7 A0-A6 USP SSP

struct mame_model {
    uint8_t *mem = nullptr;    // memory image, indexed by (address & mem_mask)
    uint32_t mem_mask = 0xffffff;
    std::vector<mame_access> log;
    int berr_at = -1;          // index in log of an access to end with BERR (-1: none)
    int iack_vector = -1;      // IACK vector byte (-1: autovector)
    int reset_out = 0;
    bool halted = false;
    virtual void set_state(const mame_state &s) = 0;
    virtual void get_state(mame_state &s) = 0;
    virtual void reset() = 0;
    virtual void set_ipl(int level) = 0;
    virtual int step() = 0;    // one instruction (incl. the exception processing it raises); returns clocks
    virtual int state_id() = 0;
    virtual ~mame_model() {}
};
mame_model *mame_model_new(int type);   // 68000, 68008 (FN: same core, the harness masks 22 address bits)

// Copyright (C) 2026 Rodimus
// API of the standalone Musashi 68010 model (musashi_model.cpp; MAME's Musashi compiled unmodified); harness only.
// Own code.
#pragma once
#include <cstdint>
#include <vector>

struct mus_write { uint32_t addr; uint16_t data, mask; int fc; };    // one word-lane write (mask: ff00 / 00ff / ffff)
struct mus_state {
    uint32_t d[8], a[8];        // a[7] = the active stack pointer
    uint32_t usp, ssp, pc, vbr, sfc, dfc;
    uint16_t sr;
};
struct mus_model {
    uint8_t *mem = nullptr;     // 16 MB image, big-endian bytes, indexed by address & 0xffffff
    std::vector<mus_write> wlog;
    // bus error: the first data access (not a prefetch) that covers address berr_addr with the given direction
    // faults (instruction-restart model of MAME's external-MMU path: registers restored, format-8 frame, RTE restarts)
    int berr_armed = 0; uint32_t berr_addr = 0; int berr_rw = 0;
    int berr_fired = 0;
    int bkpt_cycles = 0;        // CPU-space reads at address 0 (BKPT acknowledge)
    int iack_vector = -1;       // IACK data byte (-1: autovector)
    bool (*ro)(uint32_t) = nullptr;   // harness ROM areas: writes there are ignored (as on the m68ksv side)
    virtual void set_state(const mus_state &s) = 0;
    virtual void get_state(mus_state &s) = 0;
    virtual void reset() = 0;
    virtual void set_irq(int level) = 0;
    virtual int step() = 0;     // one instruction (with the trace exception it raises) or one interrupt entry; clocks
    virtual bool stopped() = 0;
    virtual bool halted() = 0;
    virtual int last_ir() = 0;
    virtual ~mus_model() {}
};
mus_model *mus_model_new();

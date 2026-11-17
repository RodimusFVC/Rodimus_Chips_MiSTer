// Copyright (C) 2026 Rodimus
// API of the standalone Musashi 68020 / 68EC020 model (musashi_model020.cpp; MAME's Musashi compiled unmodified);
// harness only. Own code.
#pragma once
#include <cstdint>
#include <vector>

struct mus20_write { uint32_t addr; uint8_t data; int fc; };    // one byte written (address, value, function code)
struct mus20_read { uint32_t addr; int size; uint32_t data; int fc; };   // one memory read (bytes 1 / 2 / 4; 2026-11-16)
struct mus20_state {
    uint32_t d[8], a[8];        // a[7] = the active stack pointer
    uint32_t usp, isp, msp, pc, vbr, sfc, dfc, cacr, caar;
    uint16_t sr;
};
struct mus20_model {
    uint8_t *mem = nullptr;     // 16 MB image, big-endian bytes, indexed by address & amask
    uint32_t amask = 0xffffff;  // harness memory mirror (both CPUs see the same 16 MB)
    std::vector<mus20_write> wlog;
    std::vector<mus20_read> rlog;       // memory-space reads of the last step() (cleared by step)
    int berr_armed = 0; uint32_t berr_addr = 0; int berr_rw = 0;
    int berr_fired = 0;
    int bkpt_cycles = 0;        // CPU-space reads of the breakpoint acknowledge
    int iack_vector = -1;       // IACK data byte (-1: autovector)
    bool (*ro)(uint32_t) = nullptr;   // harness ROM areas: writes there are ignored (as on the m68ksv side)
    virtual void set_state(const mus20_state &s) = 0;
    virtual void get_state(mus20_state &s) = 0;
    virtual void reset() = 0;
    virtual void set_irq(int level) = 0;
    virtual int step() = 0;     // one instruction (with the trace exception it raises) or one interrupt entry; clocks
    virtual bool stopped() = 0;
    virtual bool halted() = 0;
    virtual int last_ir() = 0;
    virtual ~mus20_model() {}
};
mus20_model *mus20_model_new(bool ec020);

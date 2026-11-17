// Copyright (C) 2026 Rodimus
// x86sv: 8088 CPU core (BIU + EU), max-mode style bus, one core clock with a CPU-clock enable.

module x86sv #(
    parameter bit NEC = 1'b0,           // NEC V20 instruction set and timing
    parameter bit NEC8080 = 1'b0        // NEC: 8080 emulation mode (BRKEM / RETEM / CALLN)
) (
    input  logic        clk,
    input  logic        ce,             // one 8088 clock per pulse
    input  logic        reset,

    output logic [19:0] ad,             // AD19-AD0 as the pins carry them this clock
    output logic        ale,
    output logic  [2:0] s20,            // S2-S0 (3'b111 passive)
    output logic  [2:0] tstate,         // 0 Ti 1 T1 2 T2 3 T3 4 T4 5 Tw
    output logic  [1:0] seg_s,          // S4-S3 (valid when seg_v)
    output logic        seg_v,
    output logic        rd,             // 8288 MRDC / IORC
    output logic        wra,            // 8288 AMWC / AIOWC
    output logic        wr,             // 8288 MWTC / IOWC
    output logic        io,
    output logic        inta,           // 8288 INTA command
    output logic  [7:0] dout,
    input  logic  [7:0] din,
    input  logic        ready,
    input  logic        intr,
    input  logic        nmi,
    input  logic        test_n,
    output logic        lock,           // LOCK (active high)
    output logic  [1:0] qs,             // QS1-QS0
    output logic  [7:0] qs_byte,        // byte taken from the queue (debug)

    output logic [15:0] dbg_ip,
    output logic [15:0] dbg_flags,
    output logic [7:0][15:0] dbg_r,     // AX CX DX BX SP BP SI DI
    output logic [3:0][15:0] dbg_s      // ES CS SS DS

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [7:0][15:0] tl_r,
    input  logic [3:0][15:0] tl_s,
    input  logic [15:0] tl_ip,
    input  logic [15:0] tl_flags,
    input  logic  [2:0] tl_qlen,
    input  logic [31:0] tl_queue,
    input  logic [19:0] tl_ad,
    input  logic        tl_md,          // MD (1 = native)
    input  logic        tl_mdwe,
    output logic        dbg_mdwe
`endif
);

logic        q_avail, q_old, q_pop, q_first;
logic  [7:0] q_byte;
logic        req, req_fast, req_pre, req_int, req_word, fgo, bus_idle, bus_t4, rel, susp, flush, susp_ok, if_flag, emu, lock_eu, lock_bus;
logic  [2:0] req_type;
logic  [1:0] req_sidx;
logic [15:0] req_segv, req_off, req_wdata, req_corr, rdata, flush_ip, cs;

x86sv_biu #(.NEC(NEC)) biu (
    .clk(clk), .ce(ce), .reset(reset),
    .eu_req(req), .eu_type(req_type), .eu_int(req_int), .eu_word(req_word), .eu_lock(lock_eu), .eu_fast(req_fast), .eu_pre(req_pre), .eu_sidx(req_sidx), .eu_segv(req_segv),
    .eu_off(req_off), .eu_wdata(req_wdata), .eu_corr(req_corr), .eu_rel(rel), .eu_rdata(rdata),
    .eu_susp(susp), .eu_flush(flush), .eu_flush_ip(flush_ip), .eu_fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok),
    .q_pop(q_pop), .q_first(q_first), .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .cs(cs), .if_flag(if_flag), .ps3(emu),
    .ad(ad), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v), .rd(rd), .wra(wra), .wr(wr),
    .io(io), .inta(inta), .lock_bus(lock_bus), .dout(dout), .din(din), .ready(ready), .qs(qs), .qs_byte(qs_byte)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_ip(tl_ip), .tl_qlen(tl_qlen), .tl_queue(tl_queue), .tl_ad(tl_ad)
`endif
);

x86sv_eu #(.NEC(NEC), .NEC8080(NEC8080)) eu (
    .clk(clk), .ce(ce), .reset(reset),
    .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .q_pop(q_pop), .q_first(q_first),
    .req(req), .req_fast(req_fast), .req_pre(req_pre), .req_type(req_type), .req_int(req_int), .req_word(req_word), .req_sidx(req_sidx), .req_segv(req_segv),
    .req_off(req_off), .req_wdata(req_wdata), .req_corr(req_corr), .rel(rel), .rdata(rdata),
    .susp(susp), .flush(flush), .flush_ip(flush_ip), .fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok), .cs(cs), .if_flag(if_flag), .lock(lock_eu), .emu(emu),
    .intr(intr), .nmi(nmi), .test_n(test_n),
    .dbg_ip(dbg_ip), .dbg_flags(dbg_flags), .dbg_r(dbg_r), .dbg_s(dbg_s)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_r(tl_r), .tl_s(tl_s), .tl_ip(tl_ip), .tl_flags(tl_flags), .tl_md(tl_md), .tl_mdwe(tl_mdwe),
    .dbg_mdwe(dbg_mdwe)
`endif
);

assign lock = lock_eu | lock_bus;

endmodule

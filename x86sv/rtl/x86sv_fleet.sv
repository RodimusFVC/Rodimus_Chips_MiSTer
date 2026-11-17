//============================================================================
//  x86sv_fleet - x86sv on the fleet's chip_pool_pkg bus types
//
//    x86sv_mcl86   mcl86_i_t / mcl86_o_t   drop-in for mcl86_cpu: request / acknowledge bus, cpu_clk pin clock
//    x86sv_i8088   i8088_i_t / i8088_o_t   8088 max-mode bus (ce, READY, 8288 commands, QS, LOCK)
//    x86sv_i8086   i8086_i_t / i8086_o_t   8086 max-mode bus (16-bit, BHE)
//    x86sv_v20     v20_i_t / v20_o_t       NEC V20 (8088 pins); NEC8080 = 1 adds the 8080 emulation mode
//    x86sv_v30     v30_i_t / v30_o_t       NEC V30 (8086 pins); NEC8080 = 1 adds the 8080 emulation mode
//
//  Copyright (C) 2026 Rodimus
//============================================================================

// mcl86: ce = rising edge of cpu_clk (sampled in the clk domain). A bus cycle raises req (type, address, write
// data) the clock after ALE and drops it on req_ack; READY to the core is low until the acknowledge has been seen,
// so an acknowledge that comes before the cycle's T3 costs nothing and a later one inserts Tw.
// HALT and INTA cycles are requested like reads (the INTA type byte is req_rdata of the second one). TEST is low.
module x86sv_mcl86 (
    input  logic                   clk,
    input  chip_pool_pkg::mcl86_i_t i,
    output chip_pool_pkg::mcl86_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic        o_req;
logic  [2:0] o_req_type;
logic [19:0] o_req_addr;
logic  [7:0] o_req_wdata;
logic        cpu_clk_q, ale_q, served;
logic  [7:0] rdata_q;
logic [19:0] ad;
logic  [7:0] dout;
logic  [2:0] s20;
logic        ale;
wire         ce = i.cpu_clk & ~cpu_clk_q;

x86sv u (
    .clk(clk), .ce(ce), .reset(i.reset), .ad(ad), .ale(ale), .s20(s20), .tstate(), .seg_s(), .seg_v(), .rd(), .wra(),
    .wr(), .io(), .inta(), .dout(dout), .din(rdata_q), .ready(served), .intr(i.intr), .nmi(i.nmi), .test_n(1'b0),
    .lock(), .qs(), .qs_byte(), .dbg_ip(), .dbg_flags(), .dbg_r(), .dbg_s()
);

always_ff @(posedge clk) begin
    cpu_clk_q <= i.cpu_clk;
    ale_q <= ale;
    if (i.reset) begin
        o_req <= 1'b0; o_req_type <= 3'b111; o_req_addr <= 20'd0; o_req_wdata <= 8'd0; served <= 1'b0;
        rdata_q <= 8'hFF;
    end else if (ale & ~ale_q) begin
        o_req <= 1'b1; o_req_type <= s20; o_req_addr <= ad; o_req_wdata <= dout; served <= 1'b0;
    end else if (o_req & i.req_ack) begin
        o_req <= 1'b0; served <= 1'b1; rdata_q <= i.req_rdata;
    end
end
assign o.req = o_req;
assign o.req_type = o_req_type;
assign o.req_addr = o_req_addr;
assign o.req_wdata = o_req_wdata;
endmodule

// i8088: the core's pins; addr / cyc hold the ALE-latched address and status through T4.
module x86sv_i8088 #(
    parameter bit NEC = 1'b0,
    parameter bit NEC8080 = 1'b0        // NEC: 8080 emulation mode
) (
    input  logic                   clk,
    input  chip_pool_pkg::i8088_i_t i,
    output chip_pool_pkg::i8088_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [19:0] ad, addr_q;
logic  [2:0] s20, cyc_q;
logic  [1:0] seg_s, qs;
logic  [7:0] dout;
logic        ale, rd, wra, wr, io, inta, lock;
x86sv #(.NEC(NEC), .NEC8080(NEC8080)) u (
    .clk(clk), .ce(i.ce), .reset(i.reset), .ad(ad), .ale(ale), .s20(s20), .tstate(), .seg_s(seg_s), .seg_v(),
    .rd(rd), .wra(wra), .wr(wr), .io(io), .inta(inta), .dout(dout), .din(i.din), .ready(i.ready), .intr(i.intr),
    .nmi(i.nmi), .test_n(i.test_n), .lock(lock), .qs(qs), .qs_byte(), .dbg_ip(), .dbg_flags(), .dbg_r(), .dbg_s()
);
always_ff @(posedge clk) if (ale) begin addr_q <= ad; cyc_q <= s20; end
assign o.addr = ale ? ad : addr_q;
assign o.cyc = ale ? s20 : cyc_q;
assign o.ale = ale;
assign o.s = s20;
assign o.seg = seg_s;
assign o.dout = dout;
assign o.mrdc_n = ~(rd & ~io);
assign o.amwc_n = ~(wra & ~io);
assign o.mwtc_n = ~(wr & ~io);
assign o.iorc_n = ~(rd & io);
assign o.aiowc_n = ~(wra & io);
assign o.iowc_n = ~(wr & io);
assign o.inta_n = ~inta;
assign o.qs = qs;
assign o.lock_n = ~lock;
assign o.ad = ad;
endmodule

// i8086: the core's pins; addr / cyc / bhe_n hold the ALE-latched values through T4.
module x86sv_i8086 #(
    parameter bit NEC = 1'b0,
    parameter bit NEC8080 = 1'b0        // NEC: 8080 emulation mode
) (
    input  logic                   clk,
    input  chip_pool_pkg::i8086_i_t i,
    output chip_pool_pkg::i8086_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [19:0] ad, addr_q;
logic  [2:0] s20, cyc_q;
logic  [1:0] seg_s, qs;
logic [15:0] dout;
logic        ale, bhe_n, bhe_q, rd, wra, wr, io, inta, lock;
x86sv16 #(.NEC(NEC), .NEC8080(NEC8080)) u (
    .clk(clk), .ce(i.ce), .reset(i.reset), .ad(ad), .bhe_n(bhe_n), .ale(ale), .s20(s20), .tstate(), .seg_s(seg_s),
    .seg_v(), .rd(rd), .wra(wra), .wr(wr), .io(io), .inta(inta), .dout(dout), .din(i.din), .ready(i.ready),
    .intr(i.intr), .nmi(i.nmi), .test_n(i.test_n), .lock(lock), .qs(qs), .qs_byte(), .dbg_ip(), .dbg_flags(), .dbg_r(),
    .dbg_s()
);
always_ff @(posedge clk) if (ale) begin addr_q <= ad; cyc_q <= s20; bhe_q <= bhe_n; end
assign o.addr = ale ? ad : addr_q;
assign o.cyc = ale ? s20 : cyc_q;
assign o.bhe_n = ale ? bhe_n : bhe_q;
assign o.ale = ale;
assign o.s = s20;
assign o.seg = seg_s;
assign o.dout = dout;
assign o.mrdc_n = ~(rd & ~io);
assign o.amwc_n = ~(wra & ~io);
assign o.mwtc_n = ~(wr & ~io);
assign o.iorc_n = ~(rd & io);
assign o.aiowc_n = ~(wra & io);
assign o.iowc_n = ~(wr & io);
assign o.inta_n = ~inta;
assign o.qs = qs;
assign o.lock_n = ~lock;
assign o.ad = ad;
endmodule

// v20 / v30: the 8088 / 8086 wrappers with the NEC instruction set (the bus types are the same structs)
module x86sv_v20 #(
    parameter bit NEC8080 = 1'b0        // 8080 emulation mode (BRKEM / RETEM / CALLN)
) (
    input  logic                 clk,
    input  chip_pool_pkg::v20_i_t i,
    output chip_pool_pkg::v20_o_t o
);
x86sv_i8088 #(.NEC(1'b1), .NEC8080(NEC8080)) u (.clk(clk), .i(i), .o(o));
endmodule

module x86sv_v30 #(
    parameter bit NEC8080 = 1'b0        // 8080 emulation mode (BRKEM / RETEM / CALLN)
) (
    input  logic                 clk,
    input  chip_pool_pkg::v30_i_t i,
    output chip_pool_pkg::v30_o_t o
);
x86sv_i8086 #(.NEC(1'b1), .NEC8080(NEC8080)) u (.clk(clk), .i(i), .o(o));
endmodule

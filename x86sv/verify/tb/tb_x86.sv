// Copyright (C) 2026 Rodimus
// Test top for the SingleStepTests runner: x86sv (or x86sv16 with TB_BUS16) with packed test-load / debug ports.

module tb_x86 (
    input  logic         clk,
    input  logic         reset,
    input  logic         tl_en,
    input  logic [223:0] tl_regs,       // moo order: ax bx cx dx cs ss ds es sp bp si di ip flags
    input  logic   [2:0] tl_qlen,
    input  logic  [47:0] tl_queue,
    input  logic  [19:0] tl_ad,
    input  logic         tl_bhe,
    input  logic         tl_md,         // MD (1 = native)
    input  logic         tl_mdwe,
    output logic         dbg_mdwe,
    output logic  [19:0] ad,
    output logic         bhe_n,
    output logic         ale,
    output logic   [2:0] s20,
    output logic   [2:0] tstate,
    output logic   [1:0] seg_s,
    output logic         seg_v,
    output logic         rd,
    output logic         wra,
    output logic         wr,
    output logic         io,
    output logic  [15:0] dout,
    input  logic  [15:0] din,
    input  logic         ready,
    input  logic         intr,
    input  logic         nmi,
    input  logic         test_n,
    output logic         lock,
    output logic         inta,
    output logic   [1:0] qs,
    output logic   [7:0] qs_byte,
    output logic [223:0] dbg_regs
);

logic [7:0][15:0] tr, dr;
logic [3:0][15:0] ts, ds;
logic [15:0] dip, dfl;

function automatic logic [15:0] tlr(input int i);
    tlr = tl_regs[i*16 +: 16];
endfunction

assign tr[0] = tlr(0); assign tr[1] = tlr(2); assign tr[2] = tlr(3); assign tr[3] = tlr(1);
assign tr[4] = tlr(8); assign tr[5] = tlr(9); assign tr[6] = tlr(10); assign tr[7] = tlr(11);
assign ts[0] = tlr(7); assign ts[1] = tlr(4); assign ts[2] = tlr(5); assign ts[3] = tlr(6);

assign dbg_regs = {dfl, dip, dr[7], dr[6], dr[5], dr[4], ds[0], ds[3], ds[2], ds[1], dr[2], dr[1], dr[3], dr[0]};

`ifdef TB_NEC
localparam bit NEC = 1'b1;
`else
localparam bit NEC = 1'b0;
`endif
`ifdef TB_E8
localparam bit E8 = 1'b1;
`else
localparam bit E8 = 1'b0;
`endif
`ifdef TB_BUS16
x86sv16 #(.NEC(NEC), .NEC8080(E8)) cpu (
    .clk(clk), .ce(1'b1), .reset(reset),
    .ad(ad), .bhe_n(bhe_n), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v), .rd(rd), .wra(wra),
    .wr(wr), .io(io), .inta(inta), .dout(dout), .din(din), .ready(ready), .intr(intr), .nmi(nmi), .test_n(test_n),
    .lock(lock), .qs(qs), .qs_byte(qs_byte),
    .dbg_ip(dip), .dbg_flags(dfl), .dbg_r(dr), .dbg_s(ds),
    .tl_en(tl_en), .tl_r(tr), .tl_s(ts), .tl_ip(tlr(12)), .tl_flags(tlr(13)),
    .tl_qlen(tl_qlen), .tl_queue(tl_queue), .tl_ad(tl_ad), .tl_bhe(tl_bhe), .tl_md(tl_md), .tl_mdwe(tl_mdwe), .dbg_mdwe(dbg_mdwe)
);
`else
assign bhe_n = 1'b1;
assign dout[15:8] = 8'd0;
x86sv #(.NEC(NEC), .NEC8080(E8)) cpu (
    .clk(clk), .ce(1'b1), .reset(reset),
    .ad(ad), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v), .rd(rd), .wra(wra), .wr(wr),
    .io(io), .inta(inta), .dout(dout[7:0]), .din(din[7:0]), .ready(ready), .intr(intr), .nmi(nmi), .test_n(test_n),
    .lock(lock), .qs(qs), .qs_byte(qs_byte),
    .dbg_ip(dip), .dbg_flags(dfl), .dbg_r(dr), .dbg_s(ds),
    .tl_en(tl_en), .tl_r(tr), .tl_s(ts), .tl_ip(tlr(12)), .tl_flags(tlr(13)),
    .tl_qlen(tl_qlen), .tl_queue(tl_queue[31:0]), .tl_ad(tl_ad), .tl_md(tl_md), .tl_mdwe(tl_mdwe), .dbg_mdwe(dbg_mdwe)
);
`endif

endmodule

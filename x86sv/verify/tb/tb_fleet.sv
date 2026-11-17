// Copyright (C) 2026 Rodimus
// Wrapper test top: x86sv_mcl86, x86sv_i8088, x86sv_i8086, x86sv_v20 and x86sv_v30 side by side, struct ports flattened
// for the C++ bus models.

module tb_fleet (
    input  logic        clk,
    input  logic        reset,
    input  logic        cpu_clk,
    input  logic        intr,
    input  logic  [7:0] m_rdata,
    input  logic        m_ack,
    output logic        m_req,
    output logic  [2:0] m_type,
    output logic [19:0] m_addr,
    output logic  [7:0] m_wdata,
    input  logic        r_ce,
    input  logic        r_ready,
    input  logic  [7:0] r_din,
    output logic [19:0] r_addr,
    output logic  [2:0] r_cyc,
    output logic        r_ale,
    output logic  [7:0] r_dout,
    output logic        r_wr_n,
    output logic        r_iow_n,
    output logic        r_lock_n,
    input  logic        w_ce,
    input  logic        w_ready,
    input  logic [15:0] w_din,
    output logic [19:0] w_addr,
    output logic  [2:0] w_cyc,
    output logic        w_bhe_n,
    output logic        w_ale,
    output logic [15:0] w_dout,
    output logic        w_wr_n,
    output logic        w_iow_n,
    input  logic        v_ce,
    input  logic        v_ready,
    input  logic [15:0] v_din,
    output logic [19:0] v_addr,
    output logic  [2:0] v_cyc,
    output logic        v_bhe_n,
    output logic        v_ale,
    output logic [15:0] v_dout,
    output logic        v_wr_n,
    output logic        v_iow_n,
    input  logic        x_ce,
    input  logic        x_ready,
    input  logic [15:0] x_din,
    output logic [19:0] x_addr,
    output logic  [2:0] x_cyc,
    output logic        x_bhe_n,
    output logic        x_ale,
    output logic [15:0] x_dout,
    output logic        x_wr_n,
    output logic        x_iow_n
);
chip_pool_pkg::mcl86_i_t mi;
chip_pool_pkg::mcl86_o_t mo;
chip_pool_pkg::i8088_i_t ri;
chip_pool_pkg::i8088_o_t ro;
assign mi.reset = reset;
assign mi.cpu_clk = cpu_clk;
assign mi.nmi = 1'b0;
assign mi.intr = intr;
assign mi.req_rdata = m_rdata;
assign mi.req_ack = m_ack;
assign m_req = mo.req;
assign m_type = mo.req_type;
assign m_addr = mo.req_addr;
assign m_wdata = mo.req_wdata;
assign ri.reset = reset;
assign ri.ce = r_ce;
assign ri.ready = r_ready;
assign ri.intr = intr;
assign ri.nmi = 1'b0;
assign ri.test_n = 1'b0;
assign ri.din = r_din;
assign r_addr = ro.addr;
assign r_cyc = ro.cyc;
assign r_ale = ro.ale;
assign r_dout = ro.dout;
assign r_wr_n = ro.mwtc_n;
assign r_iow_n = ro.iowc_n;
assign r_lock_n = ro.lock_n;
chip_pool_pkg::i8086_i_t wi;
chip_pool_pkg::i8086_o_t wo;
assign wi.reset = reset;
assign wi.ce = w_ce;
assign wi.ready = w_ready;
assign wi.intr = intr;
assign wi.nmi = 1'b0;
assign wi.test_n = 1'b0;
assign wi.din = w_din;
assign w_addr = wo.addr;
assign w_cyc = wo.cyc;
assign w_bhe_n = wo.bhe_n;
assign w_ale = wo.ale;
assign w_dout = wo.dout;
assign w_wr_n = wo.mwtc_n;
assign w_iow_n = wo.iowc_n;
x86sv_i8086 uw (.clk(clk), .i(wi), .o(wo));
chip_pool_pkg::v20_i_t vi;
chip_pool_pkg::v20_o_t vo;
assign vi.reset = reset;
assign vi.ce = v_ce;
assign vi.ready = v_ready;
assign vi.intr = intr;
assign vi.nmi = 1'b0;
assign vi.test_n = 1'b0;
assign vi.din = v_din[7:0];
assign v_addr = vo.addr;
assign v_cyc = vo.cyc;
assign v_bhe_n = 1'b1;
assign v_ale = vo.ale;
assign v_dout = {8'd0, vo.dout};
assign v_wr_n = vo.mwtc_n;
assign v_iow_n = vo.iowc_n;
x86sv_v20 uv (.clk(clk), .i(vi), .o(vo));
chip_pool_pkg::v30_i_t xi;
chip_pool_pkg::v30_o_t xo;
assign xi.reset = reset;
assign xi.ce = x_ce;
assign xi.ready = x_ready;
assign xi.intr = intr;
assign xi.nmi = 1'b0;
assign xi.test_n = 1'b0;
assign xi.din = x_din;
assign x_addr = xo.addr;
assign x_cyc = xo.cyc;
assign x_bhe_n = xo.bhe_n;
assign x_ale = xo.ale;
assign x_dout = xo.dout;
assign x_wr_n = xo.mwtc_n;
assign x_iow_n = xo.iowc_n;
x86sv_v30 ux (.clk(clk), .i(xi), .o(xo));
x86sv_mcl86 um (.clk(clk), .i(mi), .o(mo));
x86sv_i8088 ur (.clk(clk), .i(ri), .o(ro));
endmodule

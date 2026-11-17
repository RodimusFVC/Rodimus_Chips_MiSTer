//============================================================================
//  t80sv_fleet - t80sv on the fleet's chip_pool_pkg master bus types
//
//    t80sv_z80      z80_i_t     / z80_o_t      T80s  (WAIT_n / BUSRQ_n inactive; core reset)
//    t80sv_z80r     z80r_i_t    / z80r_o_t     T80s / T80se with reset_n on the bus (T2WRITE 1 Konami82, 0 Galaga)
//    t80sv_z80w     z80w_i_t    / z80w_o_t     T80s with WAIT_n (BUSRQ_n inactive; core reset)
//    t80sv_z80sed   z80sed_i_t  / z80sed_o_t   T80sed (BUSRQ_n inactive)
//    t80sv_z80pa    z80pa_i_t   / z80pa_o_t    T80pa (inte = IFF1, REG bit 210)
//    t80sv_z80pa85  z80pa85_i_t / z80pa85_o_t  T80pa Phoenix (8080 / 8085 RIM / SIM; BUSRQ_n inactive; core reset)
//
//  Parameters default to the fleet's settings; every module exposes the generics of the top it replaces.
//  T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018
//  Sorgelig and contributors (MiSTer-devel lineage). Phoenix additions by Rodimus.
//  Copyright (C) 2026 Rodimus  (SystemVerilog translation; Phoenix 8080 / 8085 additions)
//  Based on T80 (VHDL):
//    Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org). All rights reserved.
//    T80 versions by MikeJ (2005), TobiFlex, Sean Riddle; Copyright (c) 2018 Sorgelig (MiSTer-devel);
//    T80a bus timing by Fabio Belavenuto and Charlie Ingley; T80pa top level by Sorgelig.
//  Redistribution and use in source and synthezised forms, with or without modification, are permitted provided
//  that the following conditions are met: Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer. Redistributions in synthesized form must reproduce the
//  above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other
//  materials provided with the distribution. Neither the name of the author nor the names of other contributors
//  may be used to endorse or promote products derived from this software without specific prior written permission.
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
//  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
//  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
//  OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
//  ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//============================================================================

module t80sv_z80 #(
    parameter int MODE    = 0,
    parameter int T2WRITE = 1,
    parameter int IOWAIT  = 1
) (
    input  logic                   clk,
    input  logic                   reset_n,
    input  chip_pool_pkg::z80_i_t  i,
    output chip_pool_pkg::z80_o_t  o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
t80sv #(.MODE(MODE), .T2WRITE(T2WRITE), .IOWAIT(IOWAIT), .BUS(0)) u (
    .clk(clk), .reset_n(reset_n), .cen(i.ce), .cen_p(1'b0), .cen_n(1'b0), .wait_n(1'b1), .int_n(i.int_n),
    .nmi_n(i.nmi_n), .busrq_n(1'b1), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(o_a), .dout(o_dout), .m1_n(o_m1_n), .mreq_n(o_mreq_n),
    .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(), .busak_n(), .inte(), .stop(),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
endmodule

module t80sv_z80r #(
    parameter int MODE    = 0,
    parameter int T2WRITE = 1,
    parameter int IOWAIT  = 1
) (
    input  logic                   clk,
    input  chip_pool_pkg::z80r_i_t i,
    output chip_pool_pkg::z80r_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
t80sv #(.MODE(MODE), .T2WRITE(T2WRITE), .IOWAIT(IOWAIT), .BUS(0)) u (
    .clk(clk), .reset_n(i.reset_n), .cen(i.ce), .cen_p(1'b0), .cen_n(1'b0), .wait_n(1'b1), .int_n(i.int_n),
    .nmi_n(i.nmi_n), .busrq_n(1'b1), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(o_a), .dout(o_dout), .m1_n(o_m1_n), .mreq_n(o_mreq_n),
    .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(), .busak_n(), .inte(), .stop(),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
endmodule

module t80sv_z80w #(
    parameter int MODE    = 0,
    parameter int T2WRITE = 1,
    parameter int IOWAIT  = 1
) (
    input  logic                   clk,
    input  logic                   reset_n,
    input  chip_pool_pkg::z80w_i_t i,
    output chip_pool_pkg::z80w_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
t80sv #(.MODE(MODE), .T2WRITE(T2WRITE), .IOWAIT(IOWAIT), .BUS(0)) u (
    .clk(clk), .reset_n(reset_n), .cen(i.ce), .cen_p(1'b0), .cen_n(1'b0), .wait_n(i.wait_n), .int_n(i.int_n),
    .nmi_n(i.nmi_n), .busrq_n(1'b1), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(o_a), .dout(o_dout), .m1_n(o_m1_n), .mreq_n(o_mreq_n),
    .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(), .busak_n(), .inte(), .stop(),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
endmodule

module t80sv_z80sed (
    input  logic                     clk,
    input  chip_pool_pkg::z80sed_i_t i,
    output chip_pool_pkg::z80sed_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
t80sv #(.MODE(0), .T2WRITE(1), .IOWAIT(1), .BUS(1)) u (
    .clk(clk), .reset_n(i.reset_n), .cen(i.ce), .cen_p(1'b0), .cen_n(1'b0), .wait_n(i.wait_n), .int_n(i.int_n),
    .nmi_n(i.nmi_n), .busrq_n(1'b1), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(o_a), .dout(o_dout), .m1_n(o_m1_n), .mreq_n(o_mreq_n),
    .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(), .busak_n(), .inte(), .stop(),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
endmodule

module t80sv_z80pa #(
    parameter int MODE = 0
) (
    input  logic                    clk,
    input  chip_pool_pkg::z80pa_i_t i,
    output chip_pool_pkg::z80pa_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
logic o_busak_n;
logic o_inte;
t80sv #(.MODE(MODE), .BUS(2)) u (
    .clk(clk), .reset_n(i.reset_n), .cen(1'b0), .cen_p(i.cen_p), .cen_n(i.cen_n), .wait_n(i.wait_n),
    .int_n(i.int_n), .nmi_n(i.nmi_n), .busrq_n(i.busrq_n), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0),
    .dir(212'd0), .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(o_a), .dout(o_dout), .m1_n(o_m1_n),
    .mreq_n(o_mreq_n), .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(),
    .busak_n(o_busak_n), .inte(o_inte), .stop(), .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(),
    .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
assign o.busak_n = o_busak_n;
assign o.inte = o_inte;
endmodule

module t80sv_z80pa85 #(
    parameter int MODE = 0
) (
    input  logic                      clk,
    input  logic                      reset_n,
    input  chip_pool_pkg::z80pa85_i_t i,
    output chip_pool_pkg::z80pa85_o_t o
);
// Quartus 17: outputs through plain wires, struct fields assigned one by one
logic [15:0] o_a;
logic [7:0] o_dout;
logic o_m1_n;
logic o_mreq_n;
logic o_iorq_n;
logic o_rd_n;
logic o_wr_n;
logic o_rfsh_n;
logic o_sod;
t80sv #(.MODE(MODE), .BUS(2)) u (
    .clk(clk), .reset_n(reset_n), .cen(1'b0), .cen_p(i.cen_p), .cen_n(i.cen_n), .wait_n(i.wait_n), .int_n(i.int_n),
    .nmi_n(i.nmi_n), .busrq_n(1'b1), .di(i.di), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(i.i8080), .i8085(i.i8085), .rim_d(i.rim_d), .a(o_a), .dout(o_dout), .m1_n(o_m1_n), .mreq_n(o_mreq_n),
    .iorq_n(o_iorq_n), .rd_n(o_rd_n), .wr_n(o_wr_n), .rfsh_n(o_rfsh_n), .halt_n(), .busak_n(), .inte(), .stop(),
    .reg_o(), .sod(o_sod), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
assign o.a = o_a;
assign o.dout = o_dout;
assign o.m1_n = o_m1_n;
assign o.mreq_n = o_mreq_n;
assign o.iorq_n = o_iorq_n;
assign o.rd_n = o_rd_n;
assign o.wr_n = o_wr_n;
assign o.rfsh_n = o_rfsh_n;
assign o.sod = o_sod;
endmodule

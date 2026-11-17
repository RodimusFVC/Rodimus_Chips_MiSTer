//============================================================================
//  t80sv_tops - drop-in replacements for the T80 VHDL tops: same ports, same generics (as parameters)
//
//    t80sv_T80s  t80sv_T80se  t80sv_T80sed  t80sv_T80pa  t80sv_T80pa_phx (Phoenix ports)  t80sv_T8080se
//    t80sv_GBse  t80sv_T80a  t80sv_T80as
//
//  T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018
//  Sorgelig and contributors (MiSTer-devel lineage); T80a bus timing by Fabio Belavenuto and Charlie Ingley.
//  Phoenix core additions (I8080 / I8085 / RIM_D / SOD on t80sv_T80pa) by Rodimus.
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
//
//  Inputs that have a default value in the VHDL top are tri1 / tri0 nets: an instance may leave them unconnected,
//  as with the VHDL, and they read as that default.
//============================================================================

module t80sv_T80s #(
    parameter int Mode    = 0,
    parameter int T2Write = 1,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK,
    input  tri1  CEN,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(0)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(CEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n), .nmi_n(NMI_n),
    .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0), .i8080(1'b0), .i8085(1'b0),
    .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n), .rd_n(RD_n), .wr_n(WR_n),
    .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(), .sod(), .doe(), .bus_oe(),
    .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80se #(
    parameter int Mode    = 0,
    parameter int T2Write = 0,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(0)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80sed (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(0), .T2WRITE(1), .IOWAIT(1), .BUS(1)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T80pa #(
    parameter int Mode = 0
) (
    input  logic         RESET_n,
    input  logic         CLK,
    input  tri1  CEN_p,
    input  tri1  CEN_n,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic         M1_n,
    output logic         MREQ_n,
    output logic         IORQ_n,
    output logic         RD_n,
    output logic         WR_n,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0]  A,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    input  tri0  R800_mode,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR
);
t80sv #(.MODE(Mode), .BUS(2)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(1'b0), .cen_p(CEN_p), .cen_n(CEN_n), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(R800_mode), .dirset(DIRSet), .dir(DIR),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(REG),
    .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80pa with the Phoenix core additions: I8080 (8080 mode on a Mode 0 build), I8085 RIM / SIM, RIM_D, SOD
module t80sv_T80pa_phx #(
    parameter int Mode = 0
) (
    input  logic         RESET_n,
    input  logic         CLK,
    input  tri1  CEN_p,
    input  tri1  CEN_n,
    input  tri1  WAIT_n,
    input  tri1  INT_n,
    input  tri1  NMI_n,
    input  tri1  BUSRQ_n,
    output logic         M1_n,
    output logic         MREQ_n,
    output logic         IORQ_n,
    output logic         RD_n,
    output logic         WR_n,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    input  tri0  OUT0,
    output logic [15:0]  A,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    input  tri0  R800_mode,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR,
    input  tri0  I8080,
    input  tri0  I8085,
    input  tri0  [7:0] RIM_D,
    output logic         SOD
);
t80sv #(.MODE(Mode), .BUS(2)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(1'b0), .cen_p(CEN_p), .cen_n(CEN_n), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(OUT0), .r800_mode(R800_mode), .dirset(DIRSet), .dir(DIR),
    .i8080(I8080), .i8085(I8085), .rim_d(RIM_D), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(REG),
    .sod(SOD), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

module t80sv_T8080se #(
    parameter int Mode    = 2,
    parameter int T2Write = 0
) (
    input  logic        RESET_n,
    input  logic        CLK,
    input  logic        CLKEN,
    input  logic        READY,
    input  logic        HOLD,          // unused, as in T8080se
    input  logic        INT,
    output logic        INTE,
    output logic        DBIN,
    output logic        SYNC,
    output logic        VAIT,
    output logic        HLDA,
    output logic        WR_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(Mode), .T2WRITE(T2Write), .IOWAIT(0), .BUS(3)) u (
    .clk(CLK), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(READY), .int_n(~INT),
    .nmi_n(1'b1), .busrq_n(HOLD), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(), .mreq_n(), .iorq_n(), .rd_n(),
    .wr_n(WR_n), .rfsh_n(), .halt_n(), .busak_n(), .inte(INTE), .stop(), .reg_o(), .sod(), .doe(), .bus_oe(),
    .dbin(DBIN), .sync(SYNC), .vait(VAIT), .hlda(HLDA)
);
endmodule

module t80sv_GBse #(
    parameter int T2Write = 1,
    parameter int IOWait  = 1
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CLKEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic        STOP,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO
);
t80sv #(.MODE(3), .T2WRITE(T2Write), .IOWAIT(IOWait), .BUS(4), .Flag_S(0), .Flag_P(0), .Flag_X(0), .Flag_Y(0),
        .Flag_C(4), .Flag_H(5), .Flag_N(6), .Flag_Z(7)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(CLKEN), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(STOP),
    .reg_o(), .sod(), .doe(), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80a: tri-state address / control / data bus, released while BUSAK_n is low; uses both clock edges
module t80sv_T80a #(
    parameter int Mode   = 0,
    parameter int IOWait = 1
) (
    input  logic        RESET_n,
    input  logic        R800_mode,
    input  logic        CLK_n,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output tri          MREQ_n,
    output tri          IORQ_n,
    output tri          RD_n,
    output tri          WR_n,
    output tri          RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output tri   [15:0] A,
    inout  tri   [7:0]  D
);
logic        mreq_n_i, iorq_n_i, rd_n_i, wr_n_i, rfsh_n_i, bus_oe, doe;
logic [15:0] a_i;
logic [7:0]  do_i;
t80sv #(.MODE(Mode), .IOWAIT(IOWait), .BUS(5)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(1'b1), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(D), .out0(1'b0), .r800_mode(R800_mode), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(a_i), .dout(do_i), .m1_n(M1_n), .mreq_n(mreq_n_i),
    .iorq_n(iorq_n_i), .rd_n(rd_n_i), .wr_n(wr_n_i), .rfsh_n(rfsh_n_i), .halt_n(HALT_n), .busak_n(BUSAK_n),
    .inte(), .stop(), .reg_o(), .sod(), .doe(doe), .bus_oe(bus_oe), .dbin(), .sync(), .vait(), .hlda()
);
assign MREQ_n = bus_oe ? mreq_n_i : 1'bz;
assign IORQ_n = bus_oe ? iorq_n_i : 1'bz;
assign RD_n   = bus_oe ? rd_n_i : 1'bz;
assign WR_n   = bus_oe ? wr_n_i : 1'bz;
assign RFSH_n = bus_oe ? rfsh_n_i : 1'bz;
assign A      = bus_oe ? a_i : 16'bz;
assign D      = doe ? do_i : 8'bz;
endmodule

module t80sv_T80as #(
    parameter int Mode = 0
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        MREQ_n,
    output logic        IORQ_n,
    output logic        RD_n,
    output logic        WR_n,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DI,
    output logic [7:0]  DO,
    output logic        DOE
);
t80sv #(.MODE(Mode), .BUS(6)) u (
    .clk(CLK_n), .reset_n(RESET_n), .cen(1'b1), .cen_p(1'b0), .cen_n(1'b0), .wait_n(WAIT_n), .int_n(INT_n),
    .nmi_n(NMI_n), .busrq_n(BUSRQ_n), .di(DI), .out0(1'b0), .r800_mode(1'b0), .dirset(1'b0), .dir(212'd0),
    .i8080(1'b0), .i8085(1'b0), .rim_d(8'h00), .a(A), .dout(DO), .m1_n(M1_n), .mreq_n(MREQ_n), .iorq_n(IORQ_n),
    .rd_n(RD_n), .wr_n(WR_n), .rfsh_n(RFSH_n), .halt_n(HALT_n), .busak_n(BUSAK_n), .inte(), .stop(), .reg_o(),
    .sod(), .doe(DOE), .bus_oe(), .dbin(), .sync(), .vait(), .hlda()
);
endmodule

// T80 (the bare CPU entity): DInst = data bus for opcode fetch, DI = latched data for the rest
module t80sv_T80 #(
    parameter int Mode   = 0,
    parameter int IOWait = 0,
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic         RESET_n,
    input  logic         CLK_n,
    input  logic         CEN,
    input  logic         WAIT_n,
    input  logic         INT_n,
    input  logic         NMI_n,
    input  logic         BUSRQ_n,
    output logic         M1_n,
    output logic         IORQ,
    output logic         NoRead,
    output logic         Write,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    output logic [15:0]  A,
    input  logic [7:0]   DInst,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    output logic [2:0]   MC,
    output logic [2:0]   TS,
    output logic         IntCycle_n,
    output logic         IntE,
    output logic         Stop,
    input  tri0  R800_mode,
    input  tri0  out0,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR
);
t80sv_core #(.MODE(Mode), .IOWAIT(IOWait), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(RESET_n), .CLK_n(CLK_n), .CEN(CEN), .WAIT_n(WAIT_n), .INT_n(INT_n), .NMI_n(NMI_n), .BUSRQ_n(BUSRQ_n),
    .M1_n(M1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(RFSH_n), .HALT_n(HALT_n), .BUSAK_n(BUSAK_n),
    .A(A), .DInst(DInst), .DI(DI), .DO(DO), .MC(MC), .TS(TS), .IntCycle_n(IntCycle_n), .IntE(IntE), .Stop(Stop),
    .R800_mode(R800_mode), .out0(out0), .REG(REG), .DIRSet(DIRSet), .DIR(DIR), .I8080(1'b0), .I8085(1'b0),
    .RIM_D(8'h00), .SOD()
);
endmodule

// T80 entity of the Phoenix copy: Mode_g generic, runtime I8080 / I8085 / RIM_D, SOD
module t80sv_T80_phx #(
    parameter int Mode_g = 0,
    parameter int IOWait = 0,
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic         RESET_n,
    input  logic         CLK_n,
    input  logic         CEN,
    input  logic         WAIT_n,
    input  logic         INT_n,
    input  logic         NMI_n,
    input  logic         BUSRQ_n,
    output logic         M1_n,
    output logic         IORQ,
    output logic         NoRead,
    output logic         Write,
    output logic         RFSH_n,
    output logic         HALT_n,
    output logic         BUSAK_n,
    output logic [15:0]  A,
    input  logic [7:0]   DInst,
    input  logic [7:0]   DI,
    output logic [7:0]   DO,
    output logic [2:0]   MC,
    output logic [2:0]   TS,
    output logic         IntCycle_n,
    output logic         IntE,
    output logic         Stop,
    input  tri0  R800_mode,
    input  tri0  out0,
    output logic [211:0] REG,
    input  tri0  DIRSet,
    input  tri0  [211:0] DIR,
    input  tri0  I8080,
    input  tri0  I8085,
    input  tri0  [7:0] RIM_D,
    output logic         SOD
);
t80sv_core #(.MODE(Mode_g), .IOWAIT(IOWait), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(RESET_n), .CLK_n(CLK_n), .CEN(CEN), .WAIT_n(WAIT_n), .INT_n(INT_n), .NMI_n(NMI_n), .BUSRQ_n(BUSRQ_n),
    .M1_n(M1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(RFSH_n), .HALT_n(HALT_n), .BUSAK_n(BUSAK_n),
    .A(A), .DInst(DInst), .DI(DI), .DO(DO), .MC(MC), .TS(TS), .IntCycle_n(IntCycle_n), .IntE(IntE), .Stop(Stop),
    .R800_mode(R800_mode), .out0(out0), .REG(REG), .DIRSet(DIRSet), .DIR(DIR), .I8080(I8080), .I8085(I8085),
    .RIM_D(RIM_D), .SOD(SOD)
);
endmodule

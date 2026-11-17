//============================================================================
//  t80sv - Z80 / 8080 / 8085-subset / GB-Z80 CPU with the T80 bus front ends, cycle-identical to T80
//
//  One module for every T80 top; BUS selects the front end:
//    BUS_S      T80s / T80se   single CEN; T2WRITE: WR_n in T2 (1) or T3 (0)
//    BUS_SED    T80sed         single CEN; MREQ / RD / WR held through T2
//    BUS_PA     T80pa          CEN_p / CEN_n phases; WAIT_n sampled by the front end
//    BUS_8080SE T8080se        8080 pins: DBIN, SYNC, VAIT, HLDA, status word on DO in T1
//    BUS_GB     GBse           single CEN; GB-Z80 (set MODE 3 and the GB flag positions)
//    BUS_A      T80a           both clock edges, no enable; tri-state bus (see t80sv_t80a for the pins)
//    BUS_AS     T80as          both clock edges, no enable; separate DI / DO / DOE
//  The superset port list is meant to become one fleet bus type; inputs a front end does not use are ignored.
//
//  SystemVerilog translation of T80s / T80se / T80sed / T80pa / T8080se / GBse / T80a / T80as.vhd.
//  T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018
//  Sorgelig and contributors (MiSTer-devel lineage); T80a bus timing by Fabio Belavenuto and Charlie Ingley.
//  Phoenix core additions (I8080 / I8085 / RIM_D / SOD) by Rodimus.
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

module t80sv #(
    parameter int MODE    = 0,         // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    parameter int T2WRITE = 1,         // BUS_S / BUS_8080SE / BUS_GB: 0 WR_n active in T3, 1 in T2
    parameter int IOWAIT  = 1,         // BUS_S / BUS_8080SE / BUS_GB / BUS_A: 0 single-cycle I/O, 1 standard
    parameter int BUS     = 0,         // 0 S, 1 SED, 2 PA, 3 8080SE, 4 GB, 5 A, 6 AS
    parameter int Flag_C  = 0,         // flag bit positions; GB: C 4, H 5, N 6, Z 7, S / P / X / Y 0
    parameter int Flag_N  = 1,
    parameter int Flag_P  = 2,
    parameter int Flag_X  = 3,
    parameter int Flag_H  = 4,
    parameter int Flag_Y  = 5,
    parameter int Flag_Z  = 6,
    parameter int Flag_S  = 7
) (
    input  logic         clk,
    input  logic         reset_n,
    input  logic         cen,          // BUS_S / BUS_SED / BUS_8080SE / BUS_GB
    input  logic         cen_p,        // BUS_PA
    input  logic         cen_n,        // BUS_PA
    input  logic         wait_n,       // BUS_8080SE: READY
    input  logic         int_n,        // BUS_8080SE: ~INT
    input  logic         nmi_n,
    input  logic         busrq_n,      // BUS_8080SE: unused (T8080se ignores HOLD)
    input  logic [7:0]   di,           // BUS_A: the resolved data bus
    input  logic         out0,         // 0: OUT (C),0; 1: OUT (C),255
    input  logic         r800_mode,    // R800 MULUB / MULUW
    input  logic         dirset,       // load every register from dir
    input  logic [211:0] dir,          // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    input  logic         i8080,        // MODE 0: 8080 mode while high (Phoenix)
    input  logic         i8085,        // 8080 mode: RIM (opcode 20) / SIM (opcode 30)
    input  logic [7:0]   rim_d,
    output logic [15:0]  a,
    output logic [7:0]   dout,
    output logic         m1_n,
    output logic         mreq_n,
    output logic         iorq_n,
    output logic         rd_n,
    output logic         wr_n,
    output logic         rfsh_n,
    output logic         halt_n,
    output logic         busak_n,
    output logic         inte,         // IFF1 (8080 INTE)
    output logic         stop,         // GB STOP (T80 Stop = I_DJNZ)
    output logic [211:0] reg_o,        // register dump, layout as dir
    output logic         sod,
    output logic         doe,          // BUS_A / BUS_AS: CPU drives the data bus
    output logic         bus_oe,       // BUS_A: address / control drivers enabled (BUSAK_n high)
    output logic         dbin,         // BUS_8080SE
    output logic         sync,         // BUS_8080SE
    output logic         vait,         // BUS_8080SE
    output logic         hlda          // BUS_8080SE
);

localparam int BUS_SED    = 1;
localparam int BUS_PA     = 2;
localparam int BUS_8080SE = 3;
localparam int BUS_GB     = 4;
localparam int BUS_A      = 5;
localparam int BUS_AS     = 6;

// BUS_S = 0 is the default branch below
localparam int CORE_IOWAIT = (BUS == BUS_SED || BUS == BUS_PA || BUS == BUS_AS) ? 1 : IOWAIT;

logic        core_reset_n, core_cen, core_wait_n, core_busrq_n, core_nmi_n;
logic        IntCycle_n, NoRead, Write, IORQ, core_busak_n, core_m1_n, core_halt_n, core_rfsh_n;
logic [2:0]  MCycle, TState;
logic [7:0]  DI_Reg, core_do;
logic [15:0] core_a;
logic        rst;                      // asynchronous resets as posedge of the inverted input (see t80sv_core)
assign rst = ~reset_n;

t80sv_core #(.MODE(MODE), .IOWAIT(CORE_IOWAIT), .Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X),
             .Flag_H(Flag_H), .Flag_Y(Flag_Y), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) u0 (
    .RESET_n(core_reset_n), .CLK_n(clk), .CEN(core_cen), .WAIT_n(core_wait_n), .INT_n(int_n), .NMI_n(core_nmi_n),
    .BUSRQ_n(core_busrq_n), .M1_n(core_m1_n), .IORQ(IORQ), .NoRead(NoRead), .Write(Write), .RFSH_n(core_rfsh_n),
    .HALT_n(core_halt_n), .BUSAK_n(core_busak_n), .A(core_a), .DInst(di), .DI(DI_Reg), .DO(core_do), .MC(MCycle),
    .TS(TState), .IntCycle_n(IntCycle_n), .IntE(inte), .Stop(stop), .R800_mode(r800_mode), .out0(out0),
    .REG(reg_o), .DIRSet(dirset), .DIR(dir), .I8080(i8080), .I8085(i8085), .RIM_D(rim_d), .SOD(sod)
);

assign halt_n = core_halt_n;
assign a      = core_a;

generate
if (BUS == BUS_PA) begin : g_pa
    logic CEN_pol;
    logic [1:0] IntCycleD_n;           // no reset in T80pa
    wire unused_pa = &{1'b0, cen, rst};

    assign core_reset_n = reset_n;
    assign core_cen     = cen_p & ~CEN_pol;
    assign core_wait_n  = 1'b1;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n         = core_m1_n;
    assign rfsh_n       = core_rfsh_n;
    assign busak_n      = core_busak_n;
    assign dout         = core_do;
    assign doe    = 1'b0;
    assign bus_oe = 1'b1;
    assign dbin   = 1'b0;
    assign sync   = 1'b0;
    assign vait   = 1'b0;
    assign hlda   = 1'b0;

    always_ff @(posedge clk) begin
        if (!reset_n) begin
            wr_n    <= 1'b1;
            rd_n    <= 1'b1;
            iorq_n  <= 1'b1;
            mreq_n  <= 1'b1;
            DI_Reg  <= 8'h00;
            CEN_pol <= 1'b0;
        end else if (cen_p && !CEN_pol) begin
            CEN_pol <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd2) begin
                    iorq_n <= 1'b1;
                    mreq_n <= 1'b1;
                    rd_n   <= 1'b1;
                end
            end else begin
                if (TState == 3'd1 && IORQ) begin
                    wr_n   <= ~Write;
                    rd_n   <= Write;
                    iorq_n <= 1'b0;
                end
            end
        end else if (cen_n && CEN_pol) begin
            if (TState == 3'd2)
                CEN_pol <= ~wait_n;
            else
                CEN_pol <= 1'b0;
            if (TState == 3'd3 && core_busak_n)
                DI_Reg <= di;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    IntCycleD_n <= {IntCycleD_n[0], IntCycle_n};
                    rd_n   <= ~IntCycle_n;
                    mreq_n <= ~IntCycle_n;
                    iorq_n <= IntCycleD_n[1];
                end
                if (TState == 3'd3) begin
                    IntCycleD_n <= 2'b11;
                    rd_n   <= 1'b1;
                    mreq_n <= 1'b0;
                end
                if (TState == 3'd4)
                    mreq_n <= 1'b1;
            end else begin
                if (!NoRead && !IORQ) begin
                    if (TState == 3'd1) begin
                        rd_n   <= Write;
                        mreq_n <= 1'b0;
                    end
                end
                if (TState == 3'd2)
                    wr_n <= ~Write;
                if (TState == 3'd3) begin
                    wr_n   <= 1'b1;
                    rd_n   <= 1'b1;
                    iorq_n <= 1'b1;
                    mreq_n <= 1'b1;
                end
            end
        end
    end
end else if (BUS == BUS_8080SE) begin : g_8080se
    assign core_reset_n = reset_n;
    assign core_cen     = cen;
    assign core_wait_n  = wait_n;
    assign core_busrq_n = 1'b1;        // T8080se ignores HOLD
    assign core_nmi_n   = 1'b1;
    wire unused_8080se = &{1'b0, cen_p, cen_n, nmi_n, busrq_n, core_m1_n, core_rfsh_n};
    assign m1_n    = 1'b1;
    assign rfsh_n  = 1'b1;
    assign mreq_n  = 1'b1;
    assign iorq_n  = 1'b1;
    assign rd_n    = ~dbin;
    assign busak_n = core_busak_n;
    assign doe     = 1'b0;
    assign bus_oe  = 1'b1;
    assign sync    = (TState == 3'd1);
    assign vait    = (TState == 3'd2);
    assign hlda    = ~core_busak_n;

    // status word in T1
    always_comb begin
        dout = core_do;
        if (TState == 3'd1) begin
            dout[0] = ~IntCycle_n;                     // INTA
            dout[1] = Write;                           // WO_n
            dout[3] = ~core_halt_n;                    // HLTA
            dout[4] = IORQ & Write;                    // OUT
            dout[5] = (MCycle == 3'b001);              // M1
            dout[6] = IORQ & ~Write;                   // INP
            dout[7] = ~IORQ & ~Write & IntCycle_n;     // MEMR
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dbin   <= 1'b0;
            wr_n   <= 1'b1;
            DI_Reg <= 8'h00;
        end else if (cen) begin
            dbin <= 1'b0;
            wr_n <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1 || (TState == 3'd2 && !wait_n))
                    dbin <= IntCycle_n;
            end else begin
                if ((TState == 3'd1 || (TState == 3'd2 && !wait_n)) && !NoRead && !Write)
                    dbin <= 1'b1;
                if (T2WRITE == 0) begin
                    if (TState == 3'd2 && Write)
                        wr_n <= 1'b0;
                end else begin
                    if ((TState == 3'd1 || (TState == 3'd2 && !wait_n)) && Write)
                        wr_n <= 1'b0;
                end
            end
            if (TState == 3'd2 && wait_n)
                DI_Reg <= di;
        end
    end
end else if (BUS == BUS_A) begin : g_a
    logic Reset_s, Wait_s, WR_t2, Req_Inhibit, MReq_Inhibit, RD, MREQ, IORQ_int, IORQ_t1, IORQ_t2;
    logic rst_s;
    assign rst_s = ~Reset_s;
    logic [2:0] IORQ_int_inhibit;
    logic MREQ_rw, IORQ_rw;
    wire unused_a = &{1'b0, cen, cen_p, cen_n};

    assign core_reset_n = Reset_s;
    assign core_cen     = 1'b1;
    assign core_wait_n  = Wait_s;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n    = core_m1_n;
    assign rfsh_n  = core_rfsh_n;
    assign busak_n = core_busak_n;
    assign dout    = core_do;
    assign bus_oe  = core_busak_n;
    assign doe     = Write & core_busak_n;
    assign dbin = 1'b0;
    assign sync = 1'b0;
    assign vait = 1'b0;
    assign hlda = 1'b0;

    assign MREQ_rw = MREQ & (Req_Inhibit | MReq_Inhibit);
    assign IORQ_rw = IORQ & ~(IORQ_t1 | IORQ_t2);
    assign mreq_n  = ~MREQ_rw;
    assign iorq_n  = ~((IORQ_int & ~IORQ_int_inhibit[2]) | IORQ_rw);
    assign rd_n    = ~(RD & (MREQ_rw | IORQ_rw));
    assign wr_n    = ~(Write & ((WR_t2 & MREQ_rw) | IORQ_rw));

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            Reset_s <= 1'b0;
        else
            Reset_s <= 1'b1;
    end

    always_ff @(negedge clk) begin
        Wait_s <= wait_n;
        if (TState == 3'd3 && core_busak_n)
            DI_Reg <= di;
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            WR_t2 <= 1'b0;
        end else begin
            if (MCycle != 3'b001) begin
                if (TState == 3'd2)
                    WR_t2 <= Write;            // WR starts on the falling edge of T2 for MREQ
            end
            if (TState == 3'd3)
                WR_t2 <= 1'b0;
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s)
            Req_Inhibit <= 1'b1;
        else
            Req_Inhibit <= ~(MCycle == 3'b001 && TState == 3'd2 && wait_n);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s)
            MReq_Inhibit <= 1'b1;
        else
            MReq_Inhibit <= ~(MCycle == 3'b001 && TState == 3'd2 && wait_n);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            RD   <= 1'b0;
            MREQ <= 1'b0;
        end else begin
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    RD   <= IntCycle_n;
                    MREQ <= IntCycle_n;
                end
                if (TState == 3'd3) begin
                    RD   <= 1'b0;
                    MREQ <= 1'b1;
                end
                if (TState == 3'd4)
                    MREQ <= 1'b0;
            end else begin
                if (TState == 3'd1 && !NoRead) begin
                    RD   <= ~Write;
                    MREQ <= ~IORQ;
                end
                if (TState == 3'd3) begin
                    RD   <= 1'b0;
                    MREQ <= 1'b0;
                end
            end
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_int <= 1'b0;
        end else if (MCycle == 3'b001) begin
            if (TState == 3'd1)
                IORQ_int <= ~IntCycle_n;
            if (TState == 3'd2)
                IORQ_int <= 1'b0;
        end
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_int_inhibit <= 3'b111;
        end else if (!IntCycle_n) begin
            if (MCycle == 3'b001)
                IORQ_int_inhibit <= {IORQ_int_inhibit[1:0], 1'b0};
            if (MCycle == 3'b010)
                IORQ_int_inhibit <= 3'b111;
        end
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            IORQ_t1 <= 1'b1;
        end else begin
            if (TState == 3'd1)
                IORQ_t1 <= ~IntCycle_n;
            if (TState == 3'd3)
                IORQ_t1 <= 1'b1;
        end
    end

    always_ff @(posedge clk or posedge rst) begin  // T80a clears IORQ_t2 on RESET_n, not Reset_s
        if (rst)
            IORQ_t2 <= 1'b1;
        else
            IORQ_t2 <= IORQ_t1;
    end
end else if (BUS == BUS_AS) begin : g_as
    logic Reset_s, Wait_s, WR_n_i, IORQ_n_i, Req_Inhibit, MReq_Inhibit, RD, MREQ;
    logic rst_s;
    assign rst_s = ~Reset_s;
    wire unused_as = &{1'b0, cen, cen_p, cen_n};

    assign core_reset_n = Reset_s;
    assign core_cen     = 1'b1;
    assign core_wait_n  = Wait_s;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n    = core_m1_n;
    assign rfsh_n  = core_rfsh_n;
    assign busak_n = core_busak_n;
    assign dout    = core_do;
    assign bus_oe  = 1'b1;
    assign doe     = core_busak_n ? Write : 1'b0;
    assign dbin = 1'b0;
    assign sync = 1'b0;
    assign vait = 1'b0;
    assign hlda = 1'b0;

    assign mreq_n = ~MREQ | (Req_Inhibit & MReq_Inhibit);
    assign rd_n   = ~RD | Req_Inhibit;
    assign wr_n   = WR_n_i;
    assign iorq_n = IORQ_n_i;

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            Reset_s <= 1'b0;
        else
            Reset_s <= 1'b1;
    end

    always_ff @(negedge clk) begin
        Wait_s <= wait_n;
        if (TState == 3'd3 && core_busak_n)
            DI_Reg <= di;
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            WR_n_i <= 1'b1;
        end else begin
            WR_n_i <= 1'b1;
            if (TState == 3'd2)
                WR_n_i <= ~Write;
        end
    end

    always_ff @(posedge clk or posedge rst_s) begin
        if (rst_s)
            Req_Inhibit <= 1'b0;
        else
            Req_Inhibit <= (MCycle == 3'b001 && TState == 3'd2);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s)
            MReq_Inhibit <= 1'b0;
        else
            MReq_Inhibit <= (MCycle == 3'b001 && TState == 3'd2);
    end

    always_ff @(negedge clk or posedge rst_s) begin
        if (rst_s) begin
            RD       <= 1'b0;
            IORQ_n_i <= 1'b1;
            MREQ     <= 1'b0;
        end else begin
            if (MCycle == 3'b001) begin
                if (TState == 3'd1) begin
                    RD       <= IntCycle_n;
                    MREQ     <= IntCycle_n;
                    IORQ_n_i <= IntCycle_n;
                end
                if (TState == 3'd3) begin
                    RD       <= 1'b0;
                    IORQ_n_i <= 1'b1;
                    MREQ     <= 1'b1;
                end
                if (TState == 3'd4)
                    MREQ <= 1'b0;
            end else begin
                if (TState == 3'd1 && !NoRead) begin
                    RD       <= ~Write;
                    IORQ_n_i <= ~IORQ;
                    MREQ     <= ~IORQ;
                end
                if (TState == 3'd3) begin
                    RD       <= 1'b0;
                    IORQ_n_i <= 1'b1;
                    MREQ     <= 1'b0;
                end
            end
        end
    end
end else begin : g_s
    // BUS_S (T80s / T80se), BUS_SED (T80sed), BUS_GB (GBse)
    localparam bit SED = (BUS == BUS_SED);
    localparam bit GB  = (BUS == BUS_GB);
    wire unused_s = &{1'b0, cen_p, cen_n};

    assign core_reset_n = reset_n;
    assign core_cen     = cen;
    assign core_wait_n  = wait_n;
    assign core_busrq_n = busrq_n;
    assign core_nmi_n   = nmi_n;
    assign m1_n         = core_m1_n;
    assign rfsh_n       = core_rfsh_n;
    assign busak_n      = core_busak_n;
    assign dout         = core_do;
    assign doe    = 1'b0;
    assign bus_oe = 1'b1;
    assign dbin   = 1'b0;
    assign sync   = 1'b0;
    assign vait   = 1'b0;
    assign hlda   = 1'b0;

    logic t1w;                         // T1, or T2 while WAIT_n is low (T80sed: T1 or T2)
    assign t1w = TState == 3'd1 || (TState == 3'd2 && (!wait_n || SED));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            DI_Reg <= 8'h00;
        end else if (cen) begin
            rd_n   <= 1'b1;
            wr_n   <= 1'b1;
            iorq_n <= 1'b1;
            mreq_n <= 1'b1;
            if (MCycle == 3'b001) begin
                if (TState == 3'd1 || (TState == 3'd2 && !wait_n)) begin
                    rd_n   <= ~IntCycle_n;
                    mreq_n <= ~IntCycle_n;
                    if (!GB)
                        iorq_n <= IntCycle_n;
                end
                if (TState == 3'd3)
                    mreq_n <= 1'b0;
            end else if (GB && MCycle == 3'b011 && !IntCycle_n) begin
                if (TState == 3'd1)
                    iorq_n <= 1'b0;            // GB: interrupt acknowledge
            end else begin
                if (t1w && !NoRead && !Write) begin
                    rd_n   <= 1'b0;
                    iorq_n <= ~IORQ;
                    mreq_n <= IORQ;
                end
                if (T2WRITE == 0 && !SED) begin
                    if (TState == 3'd2 && Write) begin
                        wr_n   <= 1'b0;
                        iorq_n <= ~IORQ;
                        mreq_n <= IORQ;
                    end
                end else begin
                    if (t1w && Write) begin
                        wr_n   <= 1'b0;
                        iorq_n <= ~IORQ;
                        mreq_n <= IORQ;
                    end
                end
            end
            if (TState == 3'd2 && wait_n)
                DI_Reg <= di;
        end
    end
end
endgenerate

endmodule

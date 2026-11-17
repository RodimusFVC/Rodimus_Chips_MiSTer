// crtc6845sv: 6845-family CRT controller (default = fleet mc6845 incl. CRTCADJ-2026-10-24).
// Derived from mc6845.vhd (C) 2011 Mike Stirling, (C) 2015 David Banks (BBC Micro for Altera DE1 lineage);
// CRTCADJ-2026-10-24 adjust-line display fix from the MiSTer fleet (Arcade-Universal_MiSTer).
//
// Original mc6845.vhd notice (retained as its licence requires; note the non-commercial clause):
//
// Copyright (c) 2011 Mike Stirling
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//  be used to endorse or promote products derived from this software without
//  specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//  for redistributions as source code or in synthesized/hardware form without
//  specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// VARIANT: 0 fleet mc6845 (default)   1 MC6845 (CPC type 2)        2 HD6845S / UM6845 (type 0)
//          3 UM6845R (type 1)         4 AMS40489 (type 3)          5 40226 pre-ASIC (type 4)
//          6 R6545-1 / SY6545-1       7 C6545-1 / MOS 6545-1
// PHI2 is only used by VARIANT 6 (transparent addressing interleaved on phi2); tie it low otherwise.
module crtc6845sv #(parameter int VARIANT = 0)
(
    input  logic        CLOCK,
    input  logic        CLKEN,
    input  logic        nRESET,
    input  logic        ENABLE,
    input  logic        R_nW,
    input  logic        RS,
    input  logic  [7:0] DI,
    output logic  [7:0] DO,
    output logic        VSYNC,
    output logic        HSYNC,
    output logic        VBLANK,
    output logic        HBLANK,
    output logic        DE,
    output logic        CURSOR,
    input  logic        LPSTB,
    output logic [13:0] MA,
    output logic  [4:0] RA,
    input  logic        PHI2
);

// feature set per variant (all constants: unused logic folds away)
localparam bit FLEET    = VARIANT == 0;
localparam bit CHIP     = VARIANT != 0;                                   // display FF, VSYNC at C0 = 0, line cursor latch
localparam bit VSW_PROG = VARIANT == 0 || VARIANT == 2 || VARIANT == 4 || VARIANT == 5 || VARIANT == 6 || VARIANT == 7;
localparam bit HSW0_16  = VARIANT == 1 || VARIANT == 4 || VARIANT == 5 || VARIANT == 6 || VARIANT == 7;
localparam bit RD_R12   = VARIANT == 0 || VARIANT == 2;
localparam bit RD_MIR   = VARIANT == 4 || VARIANT == 5;                   // type 3/4: read index bits 2:0 select, RS ignored
localparam bit RS0_REG  = VARIANT == 0 || RD_MIR;                         // RS = 0 reads return register data
localparam bit ST_UM    = VARIANT == 3;                                   // status: b6 light pen, b5 vertical border
localparam bit ST_65    = VARIANT == 6 || VARIANT == 7;                   // status: (b7 update ready,) b6 light pen, b5 vblank
localparam bit TRANSP   = VARIANT == 6;
localparam bit ROWCOL   = VARIANT == 6 || VARIANT == 7;
localparam bit SKEW_HD  = VARIANT == 2;                                   // R8 b5:4 DE, b7:6 cursor: 0 / 1 / 2 chars / off
localparam bit SKEW_DE  = VARIANT == 4 || VARIANT == 5;                   // R8 b5:4 DE only
localparam bit SKEW_65  = VARIANT == 6 || VARIANT == 7;                   // R8 b4 DE, b5 cursor: 1 char
localparam bit IL_OK    = !(VARIANT == 6 || VARIANT == 7);
localparam bit R6Z      = VARIANT == 3;                                   // R6 = 0 forces the border at any time
localparam bit ADJ_C5   = VARIANT == 1 || VARIANT == 3;                   // separate adjust counter, rows keep counting
localparam bit ADJ_HOLD = VARIANT == 4 || VARIANT == 5;                   // row counter held at R4 during adjust
localparam bit VMA_ROW0 = VARIANT == 3;                                   // start address reloaded on every line of row 0
localparam bit R31_FF   = VARIANT == 3;
localparam bit R31_HIZ  = VARIANT == 6;

// registers
logic  [4:0] addr_reg;
logic  [7:0] r00, r01, r02;
logic  [3:0] r03v, r03h;
logic  [6:0] r04, r06, r07;
logic  [4:0] r05, r09, r10s, r11;
logic  [7:0] r08;
logic  [1:0] r10m;
logic  [5:0] r12, r14, r16;
logic  [1:0] r12x;
logic  [7:0] r13, r15, r17;
logic [13:0] upd_addr;

// counters / state
logic  [7:0] h_cnt;
logic  [3:0] hs_cnt, vs_cnt;
logic  [6:0] row;
logic  [4:0] line, adj_cnt;
logic  [4:0] field;
logic        in_adj, v_ff;
logic [13:0] ma_i, ma_row;
logic        h_de, v_de, hs, vs;
logic        cur_i, cur_line, lpstb_q, lp_full;
logic        de1, de2, cur1, cur2, hbl1, hbl2;
logic        upd_ready, upd_stb, acc_q;
logic  [2:0] upd_run;

wire         il_sv    = IL_OK & r08[1] & r08[0];       // interlace sync + video
wire         h_end    = h_cnt == r00;
wire         h_syncp  = h_cnt == r02;
wire         h_de_e   = h_cnt < r01;
wire         row_eq_t = row == r04;
wire         row_eq_d = row == r06;
wire         need_adj = r05 != 5'd0;
wire   [4:0] r05_m1   = r05 - 5'd1;
wire   [4:0] msl_raw  = (in_adj & ~ADJ_C5) ? r05_m1 : r09;
wire   [4:0] msl      = {msl_raw[4:1], msl_raw[0] & ~il_sv};
wire         line_eq  = line == msl;
wire         f_end    = ADJ_C5 ? ((in_adj & (adj_cnt == r05_m1)) | (line_eq & row_eq_t & ~need_adj & ~in_adj))
                               : (line_eq & (in_adj | (row_eq_t & ~need_adj)));
wire         r_end    = ADJ_C5 ? (line_eq & ~f_end) : (line_eq & ~in_adj);
wire         adj_go   = r_end & row_eq_t & need_adj & ~in_adj;
wire  [13:0] row_inc  = (ROWCOL & r08[2]) ? 14'h0100 : {6'd0, r01};
wire         to_start = f_end | (VMA_ROW0 & (row == 7'd0) & ~r_end);
wire  [13:0] ma_row_n = to_start ? {r12, r13} : r_end ? (ma_row + row_inc) : ma_row;
wire         v_de_e   = FLEET ? ((row < r06) & ~in_adj) : (v_ff & ~row_eq_d & ~(R6Z & (r06 == 7'd0)));
wire         vs_strb  = FLEET ? h_syncp : (h_cnt == 8'd0);
wire         vs_go    = vs | (row == r07 && line == 5'd0);
wire   [3:0] vsw      = VSW_PROG ? r03v : 4'd0;

// host interface (not gated by CLKEN)
wire         acc      = ENABLE & RS & (addr_reg == 5'd31);
wire         acc_new  = acc & ~acc_q;
wire         tr_on    = TRANSP & r08[3];
logic  [7:0] st1, st2, rd_reg, rd_data;
always_comb begin
    // type 3/4 status registers (Longshot ACCC 21.3.4), read as R10 / R11
    st1 = {~(h_end ? (ma_row_n[7:0] == 8'h00) : (ma_i[7:0] == 8'hFF)), 1'b1,
           (r03v == 4'd0) ? (vs & (vs_cnt != 4'd0)) : ~(~vs & (vs_cnt == r03v + 4'd1)),
           ~(h_cnt == r02 + {4'd0, r03h}), ~h_syncp,
           ~((r00 >= r01) & (h_cnt == r01 - 8'd1)), ~(h_cnt == {1'b0, r00[7:1]}), h_end};
    st2 = {(line == r09 & h_end) | (line == 5'd0 & ~h_end), 1'b0, ~(line == r09), 1'b1, field[4],
           ~((row == r07 - 7'd1) & (line == r09) & h_end), ~((row == r06 - 7'd1) & (line == r09) & h_end),
           ~(row_eq_t & (line == r09) & h_end)};
    rd_reg = 8'h00;
    case (addr_reg)
        5'd12:   rd_reg = RD_R12 ? {2'b00, r12} : 8'h00;
        5'd13:   rd_reg = RD_R12 ? r13 : 8'h00;
        5'd14:   rd_reg = {2'b00, r14};
        5'd15:   rd_reg = r15;
        5'd16:   rd_reg = {2'b00, r16};
        5'd17:   rd_reg = r17;
        5'd31:   rd_reg = R31_FF ? 8'hFF : 8'h00;
        default: rd_reg = 8'h00;
    endcase
    if (RD_MIR) begin
        case (addr_reg[2:0])
            3'd0:    rd_reg = {2'b00, r16};
            3'd1:    rd_reg = r17;
            3'd2:    rd_reg = st1;
            3'd3:    rd_reg = st2;
            3'd4:    rd_reg = {r12x, r12};
            3'd5:    rd_reg = r13;
            3'd6:    rd_reg = {2'b00, r14};
            default: rd_reg = r15;
        endcase
    end
    if (RS | RS0_REG)
        rd_data = rd_reg;
    else if (ST_UM)
        rd_data = {1'b0, lp_full, ~v_de, 5'd0};
    else if (ST_65)
        rd_data = {TRANSP & upd_ready, lp_full, ~v_de, 5'd0};
    else
        rd_data = 8'h00;
end

always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        addr_reg <= 5'd0;
        r00 <= 8'd0;  r01 <= 8'd0;  r02 <= 8'd0;  r03v <= 4'd0; r03h <= 4'd0;
        r04 <= 7'd0;  r05 <= 5'd0;  r06 <= 7'd0;  r07 <= 7'd0;  r08 <= 8'd0;
        r09 <= 5'd0;  r10m <= 2'd0; r10s <= 5'd0; r11 <= 5'd0;
        r12 <= 6'd0;  r13 <= 8'd0;  r14 <= 6'd0;  r15 <= 8'd0;
        DO  <= 8'd0;
        if (RD_MIR) r12x <= 2'd0;
    end
    else if (ENABLE) begin
        if (R_nW) begin
            if (!(R31_HIZ & RS & addr_reg == 5'd31))
                DO <= rd_data;
        end
        else if (!RS)
            addr_reg <= DI[4:0];
        else begin
            case (addr_reg)
                5'd0:  r00 <= DI;
                5'd1:  r01 <= DI;
                5'd2:  r02 <= DI;
                5'd3:  begin r03v <= DI[7:4]; r03h <= DI[3:0]; end
                5'd4:  r04 <= DI[6:0];
                5'd5:  r05 <= DI[4:0];
                5'd6:  r06 <= DI[6:0];
                5'd7:  r07 <= DI[6:0];
                5'd8:  r08 <= DI;
                5'd9:  r09 <= DI[4:0];
                5'd10: begin r10m <= DI[6:5]; r10s <= DI[4:0]; end
                5'd11: r11 <= DI[4:0];
                5'd12: begin r12 <= DI[5:0]; if (RD_MIR) r12x <= DI[7:6]; end
                5'd13: r13 <= DI;
                5'd14: r14 <= DI[5:0];
                5'd15: r15 <= DI;
                default: ;
            endcase
        end
    end
end

// horizontal / vertical / address counters
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        h_cnt  <= 8'd0;
        line   <= 5'd0;
        row    <= 7'd0;
        field  <= 5'd0;
        ma_row <= 14'd0;
        ma_i   <= 14'd0;
        in_adj <= 1'b0;
        if (ADJ_C5) adj_cnt <= 5'd0;
        if (CHIP) v_ff <= 1'b0;
    end
    else if (CLKEN) begin
        if (CHIP) v_ff <= (h_end & f_end) | (v_ff & ~row_eq_d);
        if (h_end) begin
            h_cnt  <= 8'd0;
            ma_row <= ma_row_n;
            ma_i   <= ma_row_n;
            if (ADJ_C5) adj_cnt <= in_adj ? adj_cnt + 5'd1 : 5'd0;
            if (f_end) begin
                line   <= 5'd0;
                row    <= 7'd0;
                field  <= field + 5'd1;
                in_adj <= 1'b0;
            end
            else if (r_end) begin
                line <= 5'd0;
                if (!(ADJ_HOLD & adj_go))
                    row <= row + 7'd1;
                if (adj_go)
                    in_adj <= 1'b1;
            end
            else if (il_sv)
                line <= {line[4:1] + 4'd1, 1'b0};
            else
                line <= line + 5'd1;
        end
        else begin
            h_cnt <= h_cnt + 8'd1;
            ma_i  <= ma_i + 14'd1;
        end
    end
end

// syncs and display enables
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        h_de   <= 1'b0;
        hs     <= 1'b0;
        hs_cnt <= 4'd0;
        v_de   <= 1'b0;
        vs     <= 1'b0;
        vs_cnt <= 4'd0;
    end
    else if (CLKEN) begin
        h_de <= h_de_e;
        v_de <= v_de_e;
        if (HSW0_16)
            hs <= (h_syncp | hs) & ~(hs & (hs_cnt == r03h));
        else
            hs <= (h_syncp | hs) & (hs_cnt != r03h);
        hs_cnt <= (h_syncp | hs) ? hs_cnt + 4'd1 : 4'd0;
        if (vs_strb) begin
            vs     <= vs_go & ~(vs & (vs_cnt == vsw));
            vs_cnt <= vs_go ? vs_cnt + 4'd1 : 4'd0;
        end
    end
end

// transparent addressing (R6545-1): an R31 access while ready asks for one update; in retrace mode it goes out on
// MA (RA4 strobe when R8 b6) after four blank characters, as MAME's 4-character update timer; phi2 mode: MA = update
// address while PHI2, R31 access increments it
wire de_next  = h_de_e & v_de_e;
wire upd_fire = tr_on & ~r08[7] & ~upd_ready & ~de_next & (upd_run == 3'd4);
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        if (TRANSP) begin
            upd_addr  <= 14'd0;
            upd_ready <= 1'b0;
            upd_stb   <= 1'b0;
            upd_run   <= 3'd0;
            acc_q     <= 1'b0;
        end
    end
    else if (TRANSP) begin
        acc_q <= acc;
        if (CLKEN) begin
            upd_stb <= upd_fire;
            if (upd_fire) begin
                upd_addr  <= upd_addr + 14'd1;
                upd_ready <= 1'b1;
                upd_run   <= 3'd0;
            end
            else if (de_next)
                upd_run <= 3'd0;
            else if (upd_run != 3'd4)
                upd_run <= upd_run + 3'd1;
        end
        if (ENABLE & ~R_nW & RS & addr_reg == 5'd18) upd_addr[13:8] <= DI[5:0];
        if (ENABLE & ~R_nW & RS & addr_reg == 5'd19) upd_addr[7:0] <= DI;
        if (acc_new & tr_on) begin
            if (r08[7])
                upd_addr <= upd_addr + 14'd1;
            else if (upd_ready) begin
                upd_ready <= 1'b0;
                upd_run   <= (h_de & v_de) ? 3'd0 : 3'd1;
            end
        end
    end
end

// memory address outputs (one character behind the counters, like the syncs)
logic [13:0] ma_q;
logic  [4:0] ra_q;
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        ra_q <= 5'd0;
        ma_q <= 14'd0;
    end
    else if (CLKEN) begin
        ra_q <= line;
        ma_q <= upd_fire ? upd_addr : ma_i;
    end
end
assign MA = (tr_on & r08[7] & PHI2) ? upd_addr : ma_q;

// cursor: fleet latches between the start / end lines of the cursor character (cleared on line 0);
// chips keep a line latch set at R10 and cleared after R11 on every line, so start > end wraps
wire cur_hit = h_de_e & v_de_e & (ma_i == {r14, r15});
wire cur_l1  = (line == r10s) | (cur_line & (FLEET ? (line != 5'd0) : 1'b1));
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        cur_i    <= 1'b0;
        cur_line <= 1'b0;
    end
    else if (CLKEN) begin
        cur_i <= cur_hit & cur_l1;
        if (FLEET ? cur_hit : h_end)
            cur_line <= cur_l1 & (line != r11);
    end
end

// light pen
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        lpstb_q <= 1'b0;
        r16 <= 6'd0;
        r17 <= 8'd0;
        if (ST_UM | ST_65) lp_full <= 1'b0;
    end
    else begin
        if (CLKEN) begin
            lpstb_q <= LPSTB;
            if (LPSTB & ~lpstb_q) begin
                r16 <= ma_i[13:8];
                r17 <= ma_i[7:0];
            end
        end
        if (ST_UM | ST_65) begin
            if (CLKEN & LPSTB & ~lpstb_q)
                lp_full <= 1'b1;
            else if (ENABLE & R_nW & RS & (addr_reg == 5'd16 | addr_reg == 5'd17))
                lp_full <= 1'b0;
        end
    end
end

// R8 skew delay line (unreset in the reference; it shifts during reset too)
wire de0  = h_de & v_de;
wire cur0 = cur_i & (r10m == 2'd0 | (r10m == 2'd2 & field[3]) | (r10m == 2'd3 & field[4]));
always_ff @(posedge CLOCK) begin
    if (CLKEN) begin
        de1  <= de0;
        de2  <= de1;
        cur1 <= cur0;
        cur2 <= cur1;
        hbl1 <= h_de;
        hbl2 <= hbl1;
    end
end

assign HSYNC  = hs;
assign VSYNC  = vs;
assign VBLANK = ~v_de;
always_comb begin
    if (SKEW_HD | SKEW_DE) begin
        DE     = r08[5] ? (~r08[4] & de2) : (r08[4] ? de1 : de0);
        HBLANK = r08[5] ? (r08[4] | ~hbl2) : (r08[4] ? ~hbl1 : ~h_de);
    end
    else if (SKEW_65) begin
        DE     = r08[4] ? de1 : de0;
        HBLANK = r08[4] ? ~hbl1 : ~h_de;
    end
    else if (FLEET) begin
        DE     = r08[5] ? (~r08[4] & de2) : de0;
        HBLANK = r08[5] ? (r08[4] | ~hbl2) : ~h_de;
    end
    else begin
        DE     = de0;
        HBLANK = ~h_de;
    end
    if (SKEW_HD)
        CURSOR = r08[7] ? (~r08[6] & cur2) : (r08[6] ? cur1 : cur0);
    else if (SKEW_65)
        CURSOR = r08[5] ? cur1 : cur0;
    else if (FLEET)
        CURSOR = r08[7] ? (~r08[6] & cur1) : (r08[6] ? cur1 : cur0);
    else
        CURSOR = cur0;
    RA = ra_q;
    if (TRANSP & r08[3] & r08[6])
        RA[4] = r08[7] ? PHI2 : upd_stb;
end

endmodule

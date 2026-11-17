//============================================================================
//
//  One instance of a compiled discrete-logic board (tools/dlogic/dl2v.py generates the board: one dlogic_cell per
//  netlist instance, wired net to net). The evaluation is dlogic_engine.sv's, unchanged: the compiled board steps one
//  time unit (1/4 tick) per ce and evaluates every cell every unit, which equals the engine / dlsim.cpp evaluating
//  only instances with a changed input (an unchanged instance recomputes the same outputs and the same state).
//  Power-up state comes from dlsim.cpp --pustate (parameters), so reset = the board after its power-up settle.
//  Copyright (C) 2026 Rodimus
//
//  SPDX-License-Identifier: BSD-3-Clause
//  Own work; license terms in the LICENSE file of this chip folder.
//
//============================================================================

// Types (dlogic_engine.sv): 0 LUT 1 DFF 2 JK 3 C93 4 C90 5 C9316 6 C9310 7 SEG7 8 ADD4 9 C193 10 C192 11 Q175
// 12 RAM256 13 T555 14 T555A 15 T555P 16 OS9602 17 DELAY 18 MUX8 19 RCD. P0 / P1 / P2 = the descriptor's (timer
// durations in units; T555P: P2 = paddle 0-3 unless a select input picks pad0 / pad1), TT = LUT truth table (bit = the inputs). ST0 = power-up {running, prev[7:0], st[15:0]};
// ARMED0 / DUE0 = a timer armed at power-up; RAM0 = 82S16 power-up contents. UNITS = 2 evaluates two consecutive
// units per ce (unit b sees unit a's state, timer and RAM write).

module dlogic_cell #(
    parameter int           TYPE   = 0,
    parameter int           NIN    = 1,
    parameter bit           RTRIG  = 1'b0,
    parameter logic [31:0]  P0     = 32'd0,
    parameter logic [31:0]  P1     = 32'd0,
    parameter logic [31:0]  P2     = 32'd0,
    parameter logic [255:0] TT     = 256'd0,
    parameter logic [24:0]  ST0    = 25'd0,
    parameter bit           ARMED0 = 1'b0,
    parameter logic [31:0]  DUE0   = 32'd0,
    parameter logic [255:0] RAM0   = 256'd0,
    parameter int           UNITS  = 1          // time units per ce: 2 = Breakout (28.6 M ticks / s at CLK_SYS 57.27 MHz)
)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        ce,             // one time unit
    input  logic [31:0] tnow,           // time of this unit (timers wake when it equals their due time)
    input  logic [15:0] in,             // input net values this unit (unused inputs tied 0)
    input  logic  [7:0] pad0,
    input  logic  [7:0] pad1,
    input  logic  [7:0] pad2,           // Pong Doubles' players 3 / 4 (P2 = paddle index when no select input)
    input  logic  [7:0] pad3,
    output logic  [7:0] want,           // output values this evaluation asks for
    input  logic [15:0] in_b,           // UNITS = 2: the second unit's inputs / wanted outputs (tnow + 1)
    output logic  [7:0] want_b
);

logic [24:0] state;                     // {running, prev, st}
logic        armed;
logic [31:0] due;
logic [255:0] ram;                      // POOL-EXCEPTION: 82S16 256 x 1, read combinationally every unit (a pool block is one clock late)

// one time unit of the instance: {ramd, ramwe, cancel, arm[31:0], want[7:0], nst[24:0]} (the engine's S_E1..S_E4)
function automatic logic [67:0] ev(input logic [24:0] stq, input logic [15:0] in, input logic woke,
                                  input logic rambit, input logic [31:0] parm0, parm1, parm2, parm3);
    logic [15:0] st, ns;
    logic  [7:0] want;
    logic [31:0] arm;
    logic        cancel, ramwe, ramd;
    logic [24:0] nst;
    logic  [7:0] prv, np;
    logic        runb, nr;
    logic  [3:0] c4;
    logic  [4:0] sum;
    logic  [2:0] q5;
    logic        trig, rst, start, y, en;
    logic  [7:0] seg;
    logic [31:0] padv;
    st = stq[15:0]; prv = stq[23:16]; runb = stq[24];
    ns = st; np = prv; nr = runb;
    want = 8'd0; arm = 32'd0; cancel = 1'b0; ramwe = 1'b0; ramd = 1'b0;
    c4 = 4'd0; sum = 5'd0; q5 = 3'd0; trig = 1'b0; rst = 1'b0; start = 1'b0; y = 1'b0; en = 1'b0;
    seg = 8'd0; padv = 32'd0;
    case (TYPE)
    0: want[0] = TT[in[7:0]];                                                   // LUT
    1: begin                                                                    // DFF: CLK D CLRQ PREQ
        if (!in[2] || !in[3]) begin want[0] = !in[3]; want[1] = !in[2]; ns[0] = !in[3]; end
        else begin
            if (in[0] && !prv[0]) ns[0] = in[1];
            want[0] = ns[0]; want[1] = !ns[0];
        end
        np[0] = in[0];
    end
    2: begin                                                                    // JK: CLK J K CLRQ (falling)
        if (!in[3]) ns[0] = 1'b0;
        else if (!in[0] && prv[0]) begin
            if (in[1] && in[2]) ns[0] = !st[0];
            else if (in[1]) ns[0] = 1'b1;
            else if (in[2]) ns[0] = 1'b0;
        end
        np[0] = in[0];
        want[0] = ns[0]; want[1] = !ns[0];
    end
    3: begin                                                                    // 7493: CLKA CLKB R1 R2
        if (in[2] && in[3]) ns[3:0] = 4'd0;
        else begin
            if (!in[0] && prv[0]) ns[0] = !ns[0];
            if (!in[1] && prv[1]) ns[3:1] = ns[3:1] + 3'd1;
        end
        np[1:0] = in[1:0];
        want[3:0] = ns[3:0];
    end
    4: begin                                                                    // 7490: A B R1 R2 R91 R92
        if (in[4] && in[5]) ns[3:0] = 4'b1001;
        else if (in[2] && in[3]) ns[3:0] = 4'd0;
        else begin
            if (!in[0] && prv[0]) ns[0] = !ns[0];
            if (!in[1] && prv[1]) begin q5 = ns[3:1]; ns[3:1] = (q5 >= 3'd4) ? 3'd0 : q5 + 3'd1; end
        end
        np[1:0] = in[1:0];
        want[3:0] = ns[3:0];
    end
    5, 6: begin                                                                 // 9316 / 9310
        c4 = (TYPE == 6) ? 4'd9 : 4'd15;
        if (!in[3]) ns[3:0] = 4'd0;
        else if (in[0] && !prv[0]) begin
            if (!in[4]) ns[3:0] = in[8:5];
            else if (in[1] && in[2]) ns[3:0] = (ns[3:0] >= c4) ? 4'd0 : ns[3:0] + 4'd1;
        end
        np[0] = in[0];
        want[3:0] = ns[3:0];
        want[4] = in[2] && ns[3:0] == c4;
    end
    7: begin                                                                    // 7448
        c4 = in[3:0];
        if (!in[5]) c4 = 4'd15;
        else if (!in[4]) c4 = 4'd8;
        else if (!in[6] && c4 == 4'd0) c4 = 4'd15;
        case (c4)
        4'd0: seg = 8'h7e; 4'd1: seg = 8'h30; 4'd2: seg = 8'h6d; 4'd3: seg = 8'h79; 4'd4: seg = 8'h33;
        4'd5: seg = 8'h5b; 4'd6: seg = 8'h1f; 4'd7: seg = 8'h70; 4'd8: seg = 8'h7f; 4'd9: seg = 8'h73;
        4'd10: seg = 8'h0d; 4'd11: seg = 8'h19; 4'd12: seg = 8'h23; 4'd13: seg = 8'h4b; 4'd14: seg = 8'h0f;
        default: seg = 8'h00;
        endcase
        for (int k = 0; k < 7; k++) want[k] = seg[6 - k];
    end
    8: begin                                                                    // 7483
        sum = {1'b0, in[3:0]} + {1'b0, in[7:4]} + {4'd0, in[8]};
        want[4:0] = sum;
    end
    9, 10: begin                                                                // 74193 / 74192
        c4 = (TYPE == 10) ? 4'd9 : 4'd15;
        if (in[4]) ns[3:0] = 4'd0;
        else if (!in[5]) ns[3:0] = in[3:0];
        else begin
            if (in[6] && !prv[0] && in[7]) ns[3:0] = (ns[3:0] + 4'd1 > c4) ? 4'd0 : ns[3:0] + 4'd1;
            if (in[7] && !prv[1] && in[6]) ns[3:0] = (ns[3:0] == 4'd0) ? c4 : ns[3:0] - 4'd1;
        end
        np[1:0] = in[7:6];
        want[3:0] = ns[3:0];
        want[4] = !(ns[3:0] == 4'd0 && !in[7]);
        want[5] = !(ns[3:0] == c4 && !in[6]);
    end
    11: begin                                                                   // 74175
        if (!in[5]) ns[3:0] = 4'd0;
        else if (in[0] && !prv[0]) ns[3:0] = in[4:1];
        np[0] = in[0];
        want[3:0] = ns[3:0]; want[7:4] = ~ns[3:0];
    end
    12: begin                                                                   // 82S16
        en = !in[8] && !in[9] && !in[10];
        ramwe = en && !in[11];
        ramd = in[12];
        want[0] = en ? !(ramwe ? in[12] : rambit) : 1'b1;
    end
    13, 15: begin                                                               // 555 mono / paddle
        trig = in[0]; rst = in[1];
        if (woke) nr = 1'b0;
        if (RTRIG) start = trig && !prv[0];
        else start = rst && !trig && (prv[0] || !prv[1]);
        if (!rst) nr = 1'b0;
        else if (start && !nr) begin
            nr = 1'b1;
            if (TYPE == 13) arm = P0;
            else begin
                case ((NIN > 2) ? {1'b0, in[2]} : P2[1:0])   // the duration for that paddle (parm, registered)
                2'd0:    padv = parm0;
                2'd1:    padv = parm1;
                2'd2:    padv = parm2;
                default: padv = parm3;
                endcase
                arm = padv;
            end
        end
        np[1:0] = {rst, trig};
        want[0] = rst && (nr || (!RTRIG && !trig));
    end
    14: begin                                                                   // 555 astable: RESET
        if (!in[0]) begin nr = 1'b0; ns[0] = 1'b0; cancel = 1'b1; end
        else if (!runb) begin nr = 1'b1; ns[0] = 1'b1; arm = P0; end
        else if (woke) begin ns[0] = !st[0]; arm = ns[0] ? P0 : P1; end
        want[0] = ns[0];
    end
    16: begin                                                                   // 9602: A B CLRQ
        trig = !in[0] || in[1];
        if (woke) nr = 1'b0;
        if (!in[2]) begin nr = 1'b0; cancel = 1'b1; end
        else if (trig && !prv[0]) begin nr = 1'b1; arm = P0; end
        np[0] = trig;
        want[0] = nr; want[1] = !nr;
    end
    17: begin                                                                   // DELAY
        if (woke) begin ns[0] = prv[0]; nr = 1'b0; end
        else if (in[0] != prv[0]) begin np[0] = in[0]; nr = 1'b1; arm = P0; end
        want[0] = ns[0];
    end
    18: begin                                                                   // 9312: D0..D7 A B C G
        y = in[11] ? 1'b0 : in[{1'b0, in[10:8]}];
        want[0] = y; want[1] = !y;
    end
    19: begin                                                                   // RCD: rise P0 / fall P1
        if (woke) begin ns[0] = prv[1]; nr = 1'b0; end
        if (in[0] != ns[0]) begin
            if (!nr || prv[1] != in[0]) begin nr = 1'b1; np = {6'd0, in[0], 1'b0}; arm = in[0] ? P0 : P1; end
        end else if (nr) begin nr = 1'b0; cancel = 1'b1; end
        want[0] = ns[0];
    end
    default: ;
    endcase
    nst = {nr, np, ns};
    ev = {ramd, ramwe, cancel, arm, want, nst};
endfunction

// unit a (tnow), and with UNITS = 2 unit b (tnow + 1) from the state unit a leaves: instance state, timer, RAM write
wire        woke_a = armed && due == tnow;
// T555P: each paddle's duration P0 + (P1 - P0) * pad / 256, registered (the multiply is off the unit path; the pad
// value is one clock old, invisible on the board and identical in the lockstep, where the pads are constant)
logic [31:0] parm [4];
always_ff @(posedge clk) begin
    parm[0] <= P0 + (((P1 - P0) * {24'd0, pad0}) >> 8);
    parm[1] <= P0 + (((P1 - P0) * {24'd0, pad1}) >> 8);
    parm[2] <= P0 + (((P1 - P0) * {24'd0, pad2}) >> 8);
    parm[3] <= P0 + (((P1 - P0) * {24'd0, pad3}) >> 8);
end

wire [67:0] ra     = ev(state, in, woke_a, ram[in[7:0]], parm[0], parm[1], parm[2], parm[3]);
wire [31:0] arm_a  = ra[64:33];
assign want = ra[32:25];
wire        armed_a = (arm_a != 32'd0) ? 1'b1 : (ra[65] || woke_a) ? 1'b0 : armed;
wire [31:0] due_a   = (arm_a != 32'd0) ? (tnow + arm_a + 32'd3) & ~32'd3 : due;

wire [31:0] tnow_b = tnow + 32'd1;
// unit b's wake without unit a's due arithmetic: a timer unit a arms (arm >= 1, due = first boundary at / after
// tnow + arm) is due at tnow + 1 only when arm = 1 and tnow + 1 is a boundary
wire        woke_b = (arm_a != 32'd0) ? (arm_a == 32'd1 && tnow[1:0] == 2'd3) : (armed_a && due == tnow_b);
wire        rb_bit = (ra[66] && in[7:0] == in_b[7:0]) ? ra[67] : ram[in_b[7:0]];
wire [67:0] rb     = (UNITS == 2) ? ev(ra[24:0], in_b, woke_b, rb_bit, parm[0], parm[1], parm[2], parm[3]) : 68'd0;
wire [31:0] arm_b  = rb[64:33];
assign want_b = rb[32:25];

// commit (the engine's S_E4): a timer due now is consumed; arming takes the first tick boundary at / after the unit's
// time + arm (time unit = 1/4 tick)
always_ff @(posedge clk) begin
    if (reset) begin
        state <= ST0; armed <= ARMED0; due <= DUE0; ram <= RAM0;
    end else if (ce) begin
        if (UNITS == 2) begin
            state <= rb[24:0];
            if (TYPE == 12 && ra[66]) ram[in[7:0]] <= ra[67];
            if (TYPE == 12 && rb[66]) ram[in_b[7:0]] <= rb[67];
            if (arm_b != 32'd0) begin armed <= 1'b1; due <= (tnow_b + arm_b + 32'd3) & ~32'd3; end
            else if (rb[65] || woke_b) begin armed <= 1'b0; due <= due_a; end
            else begin armed <= armed_a; due <= due_a; end
        end else begin
            state <= ra[24:0];
            if (TYPE == 12 && ra[66]) ram[in[7:0]] <= ra[67];
            armed <= armed_a; due <= due_a;
        end
    end
end

endmodule

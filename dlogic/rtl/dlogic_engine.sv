//============================================================================
//
//  Discrete logic engine: runs a TTL board's netlist (MAME netlist -> tools/dlogic/nl2dl.py -> dl2bin.py, MRA index 0)
//  as a timed event simulation, so a discrete-logic game is a program, not logic. Bit-exact with the reference model
//  (Pong core: the dlsim.cpp evaluator, lockstep on a per-tick FNV hash of every net).
//  v1: one processing element, sequential FSM (correctness baseline; real time needs the multi-lane version).
//  Copyright (C) 2026 Rodimus
//
//  SPDX-License-Identifier: BSD-3-Clause
//  Own work; license terms in the LICENSE file of this chip folder.
//
//============================================================================

// Time: units of 1/4 tick (a tick = one edge of the board's master clock). Every output change is scheduled
// `delay` units ahead (inertial: one pending change per net, a newer evaluation cancels an opposite one) in a
// 64-slot timing wheel; timers (555, 9602, long RC) wake on tick boundaries. Per time step: apply the wheel slot,
// on a boundary also the inputs / the clock edge / due timers, then evaluate every instance with a changed input
// (one evaluation per instance per step, outputs land >= 1 unit later, so evaluation order does not matter).
//
// Program (byte addresses): 0x0000 header, 0x0100 net table (bit0 const, bit1 value), 0x0800 truth tables,
// 0x1000 fanout index (u32 start | count << 16), 0x2000 fanout list (u16), 0x4000 + 128 * i descriptors:
//   [0] type [1] nin [2] nout [3] flags (bit0 TRIG=RESET 555, bits 5:1 timer slot) [4] p0 [8] p1 [12] p2 (u32)
//   [16] in[16] (u16) [48] out[8] (u16) [64 + 2k] rise / fall delay of output k (units)
// Types: 0 LUT (p0 = truth-table bit base) 1 DFF 2 JK 3 C93 4 C90 5 C9316 6 C9310 7 SEG7 8 ADD4 9 C193 10 C192
// 11 Q175 12 RAM256 (p0 = RAM) 13 T555 14 T555A 15 T555P 16 OS9602 17 DELAY 18 MUX8 19 RCD (see dlsim.cpp eval()).
// Limits: 1024 nets, 384 instances, 2048 fanout entries, 16 kbit truth tables, 32 timers, 4 RAM256, 32 events per
// wheel slot (err on overflow).

module dlogic_engine
(
    input  logic         clk,
    input  logic         reset,

    input  logic         prog_wr,        // program byte (MRA index 0)
    input  logic  [15:0] prog_addr,
    input  logic   [7:0] prog_data,
    input  logic         prog_done,      // high once the program is loaded: power-up runs on its rising edge

    input  logic  [15:0] in_bits,        // input slots, 1 = pressed / switched (net = default ^ in_bits)
    input  logic   [7:0] pad0,
    input  logic   [7:0] pad1,
    input  logic         go,             // may start the next tick (pacing)

    output logic         ready,          // running
    output logic         tick_strobe,    // a tick boundary (hash point: before the inputs / clock edge)
    output logic         pix_valid,      // pixel-clock edge: pix_level = weighted video probes 0..255
    output logic   [7:0] pix_level,
    output logic         line_strobe,
    output logic         frame_strobe,
    output logic   [7:0] snd_level,      // weighted sound probes, sampled each tick
    output logic         attract,
    output logic         err,            // sticky: wheel slot overflow / power-up did not settle
    output logic [1023:0] dbg_netval
);

localparam W_SLOTS = 64;

// ------------------------------------------------------------------------------------------------------------
// program load: header bytes, net table, memories
logic    [7:0] hdr [0:255];
logic [1023:0] netval, isconst, pend_v, pend_val;
logic  [511:0] dirty, woke;

wire in_hdr  = prog_wr && prog_addr[15:8]  == 8'h00;
wire in_net  = prog_wr && prog_addr[15:11] == 5'd0 && prog_addr[10:8] != 3'd0 && prog_addr[10:8] <= 3'd4;   // 0x100-0x4FF
wire in_tt   = prog_wr && prog_addr[15:11] == 5'd1;
wire in_fidx = prog_wr && prog_addr[15:12] == 4'd1;
wire in_fan  = prog_wr && prog_addr[15:12] == 4'd2;
wire in_desc = prog_wr && prog_addr[15:14] != 2'd0 && prog_addr[6:0] < 7'd80;
wire [9:0] net_ld = prog_addr[9:0] - 10'h100;

// descriptor: 640 bits, port A load, port B read
logic   [8:0] d_addr;
logic [639:0] dq;
dpram_dc #(.widthad_a(9), .width_a(640)) u_desc
(
    .clock_a(clk), .address_a(prog_addr[15:7] - 9'd128), .data_a({80{prog_data}}), .wren_a(in_desc),
    .byteena_a(80'd1 << prog_addr[6:0]), .q_a(),
    .clock_b(clk), .address_b(d_addr), .data_b(640'd0), .wren_b(1'b0), .byteena_b({80{1'b1}}), .q_b(dq)
);

// truth tables: bytes
logic [10:0] tt_addr;
logic  [7:0] ttq;
dpram_dc #(.widthad_a(11), .width_a(8)) u_tt
(
    .clock_a(clk), .address_a(in_tt ? prog_addr[10:0] : tt_addr), .data_a(prog_data), .wren_a(in_tt),
    .byteena_a(1'b1), .q_a(ttq),
    .clock_b(clk), .address_b(11'd0), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b()
);

// fanout index (u32 / net) and list (u16)
logic  [9:0] fi_addr;
logic [31:0] fiq;
dpram_dc #(.widthad_a(10), .width_a(32)) u_fidx
(
    .clock_a(clk), .address_a(in_fidx ? prog_addr[11:2] : fi_addr), .data_a({4{prog_data}}), .wren_a(in_fidx),
    .byteena_a(4'd1 << prog_addr[1:0]), .q_a(fiq),
    .clock_b(clk), .address_b(10'd0), .data_b(32'd0), .wren_b(1'b0), .byteena_b(4'hF), .q_b()
);
logic [10:0] fl_addr;
logic [15:0] flq;
dpram_dc #(.widthad_a(11), .width_a(16)) u_fan
(
    .clock_a(clk), .address_a(in_fan ? prog_addr[11:1] : fl_addr), .data_a({2{prog_data}}), .wren_a(in_fan),
    .byteena_a(2'd1 << prog_addr[0]), .q_a(flq),
    .clock_b(clk), .address_b(11'd0), .data_b(16'd0), .wren_b(1'b0), .byteena_b(2'b11), .q_b()
);

// per-instance state: [15:0] st, [23:16] prev, [24] running
logic  [8:0] s_addr;
logic [31:0] s_d, sq;
logic        s_we;
dpram_dc #(.widthad_a(9), .width_a(32)) u_state
(
    .clock_a(clk), .address_a(s_addr), .data_a(s_d), .wren_a(s_we), .byteena_a(4'hF), .q_a(sq),
    .clock_b(clk), .address_b(9'd0), .data_b(32'd0), .wren_b(1'b0), .byteena_b(4'hF), .q_b()
);

// RAM256 contents (4 x 256 bits)
logic [9:0] r_addr;
logic       r_d, r_we, rq;
dpram_dc #(.widthad_a(10), .width_a(1)) u_ram
(
    .clock_a(clk), .address_a(r_addr), .data_a(r_d), .wren_a(r_we), .byteena_a(1'b1), .q_a(rq),
    .clock_b(clk), .address_b(10'd0), .data_b(1'b0), .wren_b(1'b0), .byteena_b(1'b1), .q_b()
);

// pending change due time per net (port A: scheduler writes, port B: wheel pop reads)
logic  [9:0] pd_waddr, pd_raddr;
logic [31:0] pd_wd, pdq;
logic        pd_we;
dpram_dc #(.widthad_a(10), .width_a(32)) u_pdue
(
    .clock_a(clk), .address_a(pd_waddr), .data_a(pd_wd), .wren_a(pd_we), .byteena_a(4'hF), .q_a(),
    .clock_b(clk), .address_b(pd_raddr), .data_b(32'd0), .wren_b(1'b0), .byteena_b(4'hF), .q_b(pdq)
);

// timing wheel: 64 slots x 32 net ids
logic [10:0] wh_waddr, wh_raddr;
logic  [9:0] wh_wd, whq;
logic        wh_we;
dpram_dc #(.widthad_a(11), .width_a(10)) u_wheel
(
    .clock_a(clk), .address_a(wh_waddr), .data_a(wh_wd), .wren_a(wh_we), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(wh_raddr), .data_b(10'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(whq)
);
logic [5:0] wcnt [0:W_SLOTS-1];

// work lists: changed nets (FIFO) and dirty instances (FIFO), port A write / port B read
logic [9:0] ch_waddr, ch_raddr, ch_wp, ch_rp, ch_wd, chq;
logic       ch_we;
dpram_dc #(.widthad_a(10), .width_a(10)) u_chg
(
    .clock_a(clk), .address_a(ch_waddr), .data_a(ch_wd), .wren_a(ch_we), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(ch_raddr), .data_b(10'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(chq)
);
logic [8:0] dl_waddr, dl_raddr, dl_wp, dl_rp, dl_wd, dlq;
logic       dl_we;
dpram_dc #(.widthad_a(9), .width_a(9)) u_dirty
(
    .clock_a(clk), .address_a(dl_waddr), .data_a(dl_wd), .wren_a(dl_we), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(dl_raddr), .data_b(9'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(dlq)
);

// timers: 32 slots, due on a tick boundary
logic [31:0] t_armed;
logic [31:0] t_due  [0:31];
logic  [8:0] t_inst [0:31];

// ------------------------------------------------------------------------------------------------------------
// header fields
function automatic [9:0] h16(input integer a); h16 = {hdr[a + 1][1:0], hdr[a]}; endfunction
wire  [8:0] h_ninst  = {hdr[7][0], hdr[6]};
wire  [9:0] h_clk    = h16(8);
wire  [9:0] h_pix    = h16(16);
wire        h_pixe   = hdr[18][0];
wire  [9:0] h_line   = h16(20);
wire        h_linee  = hdr[22][0];
wire  [4:0] h_ninit  = hdr[23][4:0];
wire  [9:0] h_frame  = h16(24);
wire        h_framee = hdr[26][0];
wire  [4:0] h_nin    = hdr[27][4:0];
wire        h_hasattr = hdr[113] != 8'hFF;

logic [7:0] vlev, slev;
always_comb begin
    logic [9:0] v;
    v = 10'd0;
    slev = 8'd0;
    for (int k = 0; k < 4; k++) begin
        if (k < hdr[11][2:0] && netval[h16(32 + 2 * k)]) v = v + {2'd0, hdr[40 + k]};   // saturating video sum
        if (k < hdr[19][2:0] && netval[h16(48 + 2 * k)]) slev = slev + hdr[56 + k];       // weights sum to 255
    end
    vlev = (v > 10'd255) ? 8'd255 : v[7:0];
end

// ------------------------------------------------------------------------------------------------------------
// descriptor fields (valid while dq holds the current instance)
wire  [4:0] d_type  = dq[4:0];
wire  [4:0] d_nin   = dq[12:8];
wire  [3:0] d_nout  = dq[19:16];
wire        d_rtrig = dq[24];
wire  [4:0] d_slot  = dq[29:25];
wire [31:0] d_p0    = dq[63:32];
wire [31:0] d_p1    = dq[95:64];
wire [31:0] d_p2    = dq[127:96];

logic [15:0] inv;            // gathered input values of the current descriptor
always_comb for (int k = 0; k < 16; k++) inv[k] = netval[dq[128 + 16 * k +: 10]];

// LUT index = the inputs, masked to nin bits (unused inputs read net 0 = const 0)
wire [13:0] tt_bit = d_p0[13:0] + {6'd0, inv[7:0]};

// ------------------------------------------------------------------------------------------------------------
// evaluation (mirrors dlsim.cpp eval()); operands latched in S_E1 / S_E3
logic [15:0] e_in;
logic [31:0] e_st;
logic        e_woke, e_ttbit, e_rambit;
logic  [7:0] e_out;
logic [31:0] e_nst;
logic [31:0] e_arm;          // units, 0 = none
logic        e_cancel;       // drop the instance's timer
logic        e_ramwe, e_ramd;

always_comb begin
    logic [15:0] st, ns;
    logic  [7:0] prv, np;
    logic        runb, nr;
    logic  [3:0] c4;
    logic  [4:0] sum;
    logic  [2:0] q5;
    logic        trig, rst, start, y, en;
    logic  [7:0] seg;
    logic  [7:0] padv;
    st = e_st[15:0]; prv = e_st[23:16]; runb = e_st[24];
    ns = st; np = prv; nr = runb;
    e_out = 8'd0; e_arm = 32'd0; e_cancel = 1'b0; e_ramwe = 1'b0; e_ramd = 1'b0;
    c4 = 4'd0; sum = 5'd0; q5 = 3'd0; trig = 1'b0; rst = 1'b0; start = 1'b0; y = 1'b0; en = 1'b0;
    seg = 8'd0; padv = 8'd0;
    case (d_type)
    5'd0: e_out[0] = e_ttbit;                                                   // LUT
    5'd1: begin                                                                 // DFF: CLK D CLRQ PREQ
        if (!e_in[2] || !e_in[3]) begin e_out[0] = !e_in[3]; e_out[1] = !e_in[2]; ns[0] = !e_in[3]; end
        else begin
            if (e_in[0] && !prv[0]) ns[0] = e_in[1];
            e_out[0] = ns[0]; e_out[1] = !ns[0];
        end
        np[0] = e_in[0];
    end
    5'd2: begin                                                                 // JK: CLK J K CLRQ (falling)
        if (!e_in[3]) ns[0] = 1'b0;
        else if (!e_in[0] && prv[0]) begin
            if (e_in[1] && e_in[2]) ns[0] = !st[0];
            else if (e_in[1]) ns[0] = 1'b1;
            else if (e_in[2]) ns[0] = 1'b0;
        end
        np[0] = e_in[0];
        e_out[0] = ns[0]; e_out[1] = !ns[0];
    end
    5'd3: begin                                                                 // 7493: CLKA CLKB R1 R2
        if (e_in[2] && e_in[3]) ns[3:0] = 4'd0;
        else begin
            if (!e_in[0] && prv[0]) ns[0] = !ns[0];
            if (!e_in[1] && prv[1]) ns[3:1] = ns[3:1] + 3'd1;
        end
        np[1:0] = e_in[1:0];
        e_out[3:0] = ns[3:0];
    end
    5'd4: begin                                                                 // 7490: A B R1 R2 R91 R92
        if (e_in[4] && e_in[5]) ns[3:0] = 4'b1001;
        else if (e_in[2] && e_in[3]) ns[3:0] = 4'd0;
        else begin
            if (!e_in[0] && prv[0]) ns[0] = !ns[0];
            if (!e_in[1] && prv[1]) begin q5 = ns[3:1]; ns[3:1] = (q5 >= 3'd4) ? 3'd0 : q5 + 3'd1; end
        end
        np[1:0] = e_in[1:0];
        e_out[3:0] = ns[3:0];
    end
    5'd5, 5'd6: begin                                                           // 9316 / 9310
        c4 = (d_type == 5'd6) ? 4'd9 : 4'd15;
        if (!e_in[3]) ns[3:0] = 4'd0;
        else if (e_in[0] && !prv[0]) begin
            if (!e_in[4]) ns[3:0] = e_in[8:5];
            else if (e_in[1] && e_in[2]) ns[3:0] = (ns[3:0] >= c4) ? 4'd0 : ns[3:0] + 4'd1;
        end
        np[0] = e_in[0];
        e_out[3:0] = ns[3:0];
        e_out[4] = e_in[2] && ns[3:0] == c4;
    end
    5'd7: begin                                                                 // 7448
        c4 = e_in[3:0];
        if (!e_in[5]) c4 = 4'd15;
        else if (!e_in[4]) c4 = 4'd8;
        else if (!e_in[6] && c4 == 4'd0) c4 = 4'd15;
        case (c4)
        4'd0: seg = 8'h7e; 4'd1: seg = 8'h30; 4'd2: seg = 8'h6d; 4'd3: seg = 8'h79; 4'd4: seg = 8'h33;
        4'd5: seg = 8'h5b; 4'd6: seg = 8'h1f; 4'd7: seg = 8'h70; 4'd8: seg = 8'h7f; 4'd9: seg = 8'h73;
        4'd10: seg = 8'h0d; 4'd11: seg = 8'h19; 4'd12: seg = 8'h23; 4'd13: seg = 8'h4b; 4'd14: seg = 8'h0f;
        default: seg = 8'h00;
        endcase
        for (int k = 0; k < 7; k++) e_out[k] = seg[6 - k];
    end
    5'd8: begin                                                                 // 7483
        sum = {1'b0, e_in[3:0]} + {1'b0, e_in[7:4]} + {4'd0, e_in[8]};
        e_out[4:0] = sum;
    end
    5'd9, 5'd10: begin                                                          // 74193 / 74192
        c4 = (d_type == 5'd10) ? 4'd9 : 4'd15;
        if (e_in[4]) ns[3:0] = 4'd0;
        else if (!e_in[5]) ns[3:0] = e_in[3:0];
        else begin
            if (e_in[6] && !prv[0] && e_in[7]) ns[3:0] = (ns[3:0] + 4'd1 > c4) ? 4'd0 : ns[3:0] + 4'd1;
            if (e_in[7] && !prv[1] && e_in[6]) ns[3:0] = (ns[3:0] == 4'd0) ? c4 : ns[3:0] - 4'd1;
        end
        np[1:0] = e_in[7:6];
        e_out[3:0] = ns[3:0];
        e_out[4] = !(ns[3:0] == 4'd0 && !e_in[7]);
        e_out[5] = !(ns[3:0] == c4 && !e_in[6]);
    end
    5'd11: begin                                                                // 74175
        if (!e_in[5]) ns[3:0] = 4'd0;
        else if (e_in[0] && !prv[0]) ns[3:0] = e_in[4:1];
        np[0] = e_in[0];
        e_out[3:0] = ns[3:0]; e_out[7:4] = ~ns[3:0];
    end
    5'd12: begin                                                                // 82S16
        en = !e_in[8] && !e_in[9] && !e_in[10];
        e_ramwe = en && !e_in[11];
        e_ramd = e_in[12];
        e_out[0] = en ? !(e_ramwe ? e_in[12] : e_rambit) : 1'b1;
    end
    5'd13, 5'd15: begin                                                         // 555 mono / paddle
        trig = e_in[0]; rst = e_in[1];
        if (e_woke) nr = 1'b0;
        if (d_rtrig) start = trig && !prv[0];
        else start = rst && !trig && (prv[0] || !prv[1]);
        if (!rst) nr = 1'b0;
        else if (start && !nr) begin
            nr = 1'b1;
            if (d_type == 5'd13) e_arm = d_p0;
            else begin
                padv = ((d_nin > 5'd2) ? e_in[2] : d_p2[0]) ? pad1 : pad0;
                e_arm = d_p0 + (((d_p1 - d_p0) * {24'd0, padv}) >> 8);
            end
        end
        np[1:0] = {rst, trig};
        e_out[0] = rst && (nr || (!d_rtrig && !trig));
    end
    5'd14: begin                                                                // 555 astable: RESET
        if (!e_in[0]) begin nr = 1'b0; ns[0] = 1'b0; e_cancel = 1'b1; end
        else if (!runb) begin nr = 1'b1; ns[0] = 1'b1; e_arm = d_p0; end
        else if (e_woke) begin ns[0] = !st[0]; e_arm = ns[0] ? d_p0 : d_p1; end
        e_out[0] = ns[0];
    end
    5'd16: begin                                                                // 9602: A B CLRQ
        trig = !e_in[0] || e_in[1];
        if (e_woke) nr = 1'b0;
        if (!e_in[2]) begin nr = 1'b0; e_cancel = 1'b1; end
        else if (trig && !prv[0]) begin nr = 1'b1; e_arm = d_p0; end
        np[0] = trig;
        e_out[0] = nr; e_out[1] = !nr;
    end
    5'd17: begin                                                                // DELAY
        if (e_woke) begin ns[0] = prv[0]; nr = 1'b0; end
        else if (e_in[0] != prv[0]) begin np[0] = e_in[0]; nr = 1'b1; e_arm = d_p0; end
        e_out[0] = ns[0];
    end
    5'd18: begin                                                                // 9312: D0..D7 A B C G
        y = e_in[11] ? 1'b0 : e_in[{1'b0, e_in[10:8]}];
        e_out[0] = y; e_out[1] = !y;
    end
    5'd19: begin                                                                // RCD: rise p0 / fall p1
        if (e_woke) begin ns[0] = prv[1]; nr = 1'b0; end
        if (e_in[0] != ns[0]) begin
            if (!nr || prv[1] != e_in[0]) begin nr = 1'b1; np = {6'd0, e_in[0], 1'b0}; e_arm = e_in[0] ? d_p0 : d_p1; end
        end else if (nr) begin nr = 1'b0; e_cancel = 1'b1; end
        e_out[0] = ns[0];
    end
    default: ;
    endcase
    e_nst = {7'd0, nr, np, ns};
end

// ------------------------------------------------------------------------------------------------------------
// main FSM (every dpram_dc read: address register set in state N, data used in state N + 2)
typedef enum logic [5:0] {
    S_IDLE, S_CLR, S_INIT, S_PU, S_PU_INITV,
    S_STEP, S_POP_W, S_POP_ENT, S_POP_W2, S_POP_CHK,
    S_BOUND, S_INPUTS, S_TIMERS,
    S_FAN, S_FAN_W, S_FAN_NET, S_FAN_W2, S_FAN_IDX, S_FAN_LIST, S_FAN_W3, S_FAN_ENT,
    S_EVAL, S_EV_W, S_EV_GET, S_E0, S_E1, S_E2, S_E3, S_E4, S_OUT, S_NEXT
} state_t;
state_t sm;

logic [31:0] t;              // current time (units)
logic  [5:0] wk;             // wheel entry index while popping
logic  [9:0] pnet;
logic  [4:0] ik;             // input / init loop index
logic  [8:0] pu_i;           // power-up instance index
logic  [7:0] pu_pass;
logic        pu_any, pu;     // pu = power-up (immediate writes)
logic  [8:0] cur;            // instance being evaluated
logic  [3:0] ok;             // output loop index
logic [15:0] f_cnt;
logic [10:0] f_pos;
logic  [9:0] cnet;
logic  [2:0] tt_sel;
logic        prog_done_d;
logic [31:0] woken, wmask;
logic  [4:0] wfirst;

always_comb for (int s = 0; s < 32; s++) woken[s] = t_armed[s] && t_due[s] == t;
always_comb begin
    wfirst = 5'd0;
    for (int s = 31; s >= 0; s--) if (wmask[s]) wfirst = s[4:0];
end

assign dbg_netval = netval;
assign attract = h_hasattr ? netval[h16(112)] : 1'b0;

// output scheduling (S_OUT): one output per clock
wire  [9:0] o_net  = dq[384 + 16 * ok +: 10];
wire        o_want = e_out[ok[2:0]];
wire  [7:0] o_dly  = dq[512 + 16 * ok + (o_want ? 0 : 8) +: 8];
wire [31:0] o_due  = t + {24'd0, o_dly};
wire  [5:0] o_slot = o_due[5:0];
wire [31:0] arm_due = (t + e_arm + 32'd3) & ~32'd3;      // first tick boundary at / after t + arm

// next time step: the first occupied wheel slot before the next boundary, else the boundary
logic [31:0] t_next;
always_comb begin
    t_next = {t[31:2] + 30'd1, 2'b00};
    for (int k = 3; k >= 1; k--)
        if (k > t[1:0] && wcnt[{t[5:2], 2'b00} + k[5:0]] != 6'd0) t_next = {t[31:2], k[1:0]};
end

always_ff @(posedge clk) begin
    tick_strobe <= 1'b0; pix_valid <= 1'b0; line_strobe <= 1'b0; frame_strobe <= 1'b0;
    s_we <= 1'b0; r_we <= 1'b0; pd_we <= 1'b0; wh_we <= 1'b0; ch_we <= 1'b0; dl_we <= 1'b0;
    prog_done_d <= prog_done;

    if (in_hdr) hdr[prog_addr[7:0]] <= prog_data;
    if (in_net) begin isconst[net_ld] <= prog_data[0]; netval[net_ld] <= prog_data[1]; end

    if (reset) begin
        sm <= S_IDLE; ready <= 1'b0; err <= 1'b0;
    end else case (sm)
    S_IDLE: begin
        ready <= 1'b0;
        if (prog_wr && prog_addr == 16'd0) begin isconst <= '0; netval <= '0; err <= 1'b0; end
        if (prog_done) begin sm <= S_CLR; s_addr <= 9'd0; end      // loaded (also after an OSD reset)
    end
    S_CLR: begin                                        // instance state = 0 (cold start, as the model)
        s_we <= 1'b1; s_d <= 32'd0;
        if (s_we) s_addr <= s_addr + 9'd1;
        if (s_we && s_addr == 9'd511) begin s_we <= 1'b0; sm <= S_INIT; ik <= 5'd0; end
    end
    S_INIT: begin                                       // clear runtime state, inputs to their values
        pend_v <= '0; dirty <= '0; woke <= '0; t_armed <= '0;
        for (int s = 0; s < W_SLOTS; s++) wcnt[s] <= 6'd0;
        if (ik < h_nin && hdr[65 + 2 * ik] != 8'hFF) netval[h16(64 + 2 * ik)] <= hdr[96 + ik][0] ^ in_bits[ik];
        ik <= ik + 5'd1;
        if (ik == 5'd15) begin
            sm <= S_PU; pu <= 1'b1; pu_pass <= 8'd0; pu_i <= 9'd0; pu_any <= 1'b0; t <= 32'd0;
        end
    end
    S_PU: begin                                         // power-up: passes over every instance, immediate writes
        if (pu_i == h_ninst) begin
            pu_i <= 9'd0; pu_any <= 1'b0; pu_pass <= pu_pass + 8'd1;
            if (pu_pass == 8'd0) begin sm <= S_PU_INITV; ik <= 5'd0; end
            else if (!pu_any || pu_pass == 8'd199) begin
                err <= err | pu_any; pu <= 1'b0; ready <= 1'b1; sm <= S_NEXT;
            end
        end else begin
            cur <= pu_i; d_addr <= pu_i; s_addr <= pu_i; pu_i <= pu_i + 9'd1;
            sm <= S_E0;
        end
    end
    S_PU_INITV: begin                                   // init values re-imposed after the first pass
        if (ik < h_ninit) netval[h16(128 + 4 * ik)] <= hdr[130 + 4 * ik][0];
        ik <= ik + 5'd1;
        if (ik == 5'd15) sm <= S_PU;
    end

    // ---- time step t: pop the wheel slot ------------------------------------------------------------------
    S_STEP: begin
        ch_wp <= 10'd0; ch_rp <= 10'd0; dl_wp <= 9'd0; dl_rp <= 9'd0; wk <= 6'd0;
        wh_raddr <= {t[5:0], 5'd0};
        if (t[1:0] != 2'd0 || go) sm <= S_POP_W;        // pace: a tick starts only when allowed
    end
    S_POP_W: sm <= S_POP_ENT;
    S_POP_ENT: begin                                    // whq = entry wk
        if (wk == wcnt[t[5:0]]) begin
            wcnt[t[5:0]] <= 6'd0;
            sm <= (t[1:0] == 2'd0) ? S_BOUND : S_FAN;
        end else begin
            pd_raddr <= whq; pnet <= whq; sm <= S_POP_W2;
        end
    end
    S_POP_W2: sm <= S_POP_CHK;
    S_POP_CHK: begin
        if (pend_v[pnet] && pdq == t) begin
            pend_v[pnet] <= 1'b0;
            if (netval[pnet] != pend_val[pnet]) begin
                netval[pnet] <= pend_val[pnet];
                ch_waddr <= ch_wp; ch_wd <= pnet; ch_we <= 1'b1; ch_wp <= ch_wp + 10'd1;
            end
        end
        wk <= wk + 6'd1; wh_raddr <= {t[5:0], wk[4:0] + 5'd1};
        sm <= S_POP_W;
    end

    // ---- tick boundary: hash point, inputs, clock edge, due timers ----------------------------------------
    S_BOUND: begin
        tick_strobe <= 1'b1;
        snd_level <= slev;
        wmask <= woken; t_armed <= t_armed & ~woken;
        ik <= 5'd0;
        sm <= S_INPUTS;
    end
    S_INPUTS: begin
        if (ik == h_nin) begin                          // then the clock edge
            netval[h_clk] <= !netval[h_clk];
            ch_waddr <= ch_wp; ch_wd <= h_clk; ch_we <= 1'b1; ch_wp <= ch_wp + 10'd1;
            sm <= S_TIMERS;
        end else begin
            if (hdr[65 + 2 * ik] != 8'hFF && netval[h16(64 + 2 * ik)] != (hdr[96 + ik][0] ^ in_bits[ik])) begin
                netval[h16(64 + 2 * ik)] <= hdr[96 + ik][0] ^ in_bits[ik];
                ch_waddr <= ch_wp; ch_wd <= h16(64 + 2 * ik); ch_we <= 1'b1; ch_wp <= ch_wp + 10'd1;
            end
            ik <= ik + 5'd1;
        end
    end
    S_TIMERS: begin                                     // woken timers -> dirty (with the woke flag)
        if (wmask == 32'd0) sm <= S_FAN;
        else begin
            wmask[wfirst] <= 1'b0;
            woke[t_inst[wfirst]] <= 1'b1;
            if (!dirty[t_inst[wfirst]]) begin
                dirty[t_inst[wfirst]] <= 1'b1;
                dl_waddr <= dl_wp; dl_wd <= t_inst[wfirst]; dl_we <= 1'b1; dl_wp <= dl_wp + 9'd1;
            end
        end
    end

    // ---- fanout of the changed nets (and the raster outputs) ----------------------------------------------
    S_FAN: begin
        if (ch_rp == ch_wp) sm <= S_EVAL;
        else begin ch_raddr <= ch_rp; ch_rp <= ch_rp + 10'd1; sm <= S_FAN_W; end
    end
    S_FAN_W: sm <= S_FAN_NET;
    S_FAN_NET: begin
        cnet <= chq; fi_addr <= chq;
        if (chq == h_pix && netval[chq] == h_pixe) begin pix_valid <= 1'b1; pix_level <= vlev; end
        if (chq == h_line && netval[chq] == h_linee) line_strobe <= 1'b1;
        if (chq == h_frame && netval[chq] == h_framee) frame_strobe <= 1'b1;
        sm <= S_FAN_W2;
    end
    S_FAN_W2: sm <= S_FAN_IDX;
    S_FAN_IDX: begin f_pos <= fiq[10:0]; f_cnt <= fiq[31:16]; sm <= S_FAN_LIST; end
    S_FAN_LIST: begin
        if (f_cnt == 16'd0) sm <= S_FAN;
        else begin fl_addr <= f_pos; f_pos <= f_pos + 11'd1; f_cnt <= f_cnt - 16'd1; sm <= S_FAN_W3; end
    end
    S_FAN_W3: sm <= S_FAN_ENT;
    S_FAN_ENT: begin
        if (!dirty[flq[8:0]]) begin
            dirty[flq[8:0]] <= 1'b1;
            dl_waddr <= dl_wp; dl_wd <= flq[8:0]; dl_we <= 1'b1; dl_wp <= dl_wp + 9'd1;
        end
        sm <= S_FAN_LIST;
    end

    // ---- evaluate the dirty instances ---------------------------------------------------------------------
    S_EVAL: begin
        if (dl_rp == dl_wp) sm <= S_NEXT;
        else begin dl_raddr <= dl_rp; dl_rp <= dl_rp + 9'd1; sm <= S_EV_W; end
    end
    S_EV_W: sm <= S_EV_GET;
    S_EV_GET: begin cur <= dlq; d_addr <= dlq; s_addr <= dlq; sm <= S_E0; end
    S_E0: sm <= S_E1;                                   // dq / sq valid in S_E1
    S_E1: begin
        e_in <= inv; e_st <= sq; e_woke <= pu ? 1'b0 : woke[cur];
        tt_addr <= tt_bit[13:3]; tt_sel <= tt_bit[2:0];
        r_addr <= {d_p0[1:0], inv[7:0]};
        sm <= S_E2;
    end
    S_E2: sm <= S_E3;                                   // ttq / rq valid in S_E3
    S_E3: begin e_ttbit <= ttq[tt_sel]; e_rambit <= rq; sm <= S_E4; end
    S_E4: begin                                         // e_* settled: commit state, RAM, timer
        s_we <= 1'b1; s_d <= e_nst;
        if (e_ramwe) begin r_we <= 1'b1; r_d <= e_ramd; end
        if (e_arm != 32'd0) begin t_armed[d_slot] <= 1'b1; t_due[d_slot] <= arm_due; t_inst[d_slot] <= cur; end
        else if (e_cancel) t_armed[d_slot] <= 1'b0;
        dirty[cur] <= 1'b0; woke[cur] <= 1'b0;
        ok <= 4'd0;
        sm <= S_OUT;
    end
    S_OUT: begin
        if (ok == d_nout) sm <= pu ? S_PU : S_EVAL;
        else begin
            if (!isconst[o_net]) begin
                if (pu) begin
                    if (netval[o_net] != o_want) begin netval[o_net] <= o_want; pu_any <= 1'b1; end
                end else if (!(pend_v[o_net] && pend_val[o_net] == o_want)) begin
                    pend_v[o_net] <= 1'b0;                              // cancel an opposite pending change
                    if (o_want != netval[o_net]) begin
                        pend_v[o_net] <= 1'b1; pend_val[o_net] <= o_want;
                        pd_waddr <= o_net; pd_wd <= o_due; pd_we <= 1'b1;
                        if (wcnt[o_slot] == 6'd32) err <= 1'b1;
                        else begin
                            wh_waddr <= {o_slot, wcnt[o_slot][4:0]}; wh_wd <= o_net; wh_we <= 1'b1;
                            wcnt[o_slot] <= wcnt[o_slot] + 6'd1;
                        end
                    end
                end
            end
            ok <= ok + 4'd1;
        end
    end
    S_NEXT: begin t <= t_next; sm <= S_STEP; end
    default: sm <= S_IDLE;
    endcase
end

endmodule

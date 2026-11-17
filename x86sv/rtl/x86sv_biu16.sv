// Copyright (C) 2026 Rodimus
// x86sv 16-bit bus interface unit (8086 / V30): T-state machine, 6-byte prefetch queue, word fetches, BHE.

module x86sv_biu16 #(
    parameter bit NEC = 1'b0            // V20 bus rules (V30: inferred): no prefetch abort, an EU request at T4 blocks the prefetch
) (
    input  logic        clk,
    input  logic        ce,             // one CPU clock
    input  logic        reset,

    // EU requests: held until released
    input  logic        eu_req,
    input  logic  [2:0] eu_type,        // S2-S0 of the cycle
    input  logic        eu_int,         // internal adder cycle (IP correction): address shown, no bus cycle
    input  logic        eu_word,
    input  logic        eu_lock,        // LOCK prefix active for this cycle
    input  logic        eu_fast,        // NEC: a request right after an EU cycle may start at its T4
    input  logic        eu_pre,         // NEC: the EU requests next clock (a 3-byte queue does not prefetch at T4)
    input  logic  [1:0] eu_sidx,        // S4-S3
    input  logic [15:0] eu_segv,
    input  logic [15:0] eu_off,
    input  logic [15:0] eu_wdata,
    input  logic [15:0] eu_corr,
    output logic        eu_rel,         // read: data valid this cycle (T3); write: T2 of the last cycle
    output logic [15:0] eu_rdata,       // valid with eu_rel
    input  logic        eu_susp,
    input  logic        eu_flush,
    input  logic [15:0] eu_flush_ip,
    input  logic        eu_fgo,         // NEC: start the code fetch at the flushed address now
    output logic        bus_idle,       // NEC: bus in Ti (early flush)
    output logic        bus_t4,         // NEC: bus in T4
    output logic        susp_ok,
    input  logic        q_pop,
    input  logic        q_first,
    output logic        q_avail,
    output logic        q_old,          // the head byte was already in the queue last clock
    output logic  [7:0] q_byte,         // queue head (a register)
    input  logic [15:0] cs,
    input  logic        if_flag,
    input  logic        ps3,            // NEC: 8080 emulation mode (status on A19 / PS3)

    // bus
    output logic [19:0] ad,             // multiplexed AD19-AD0 as driven this cycle (bus-hold value when floating)
    output logic        bhe_n,          // BHE (latched at T1)
    output logic        ale,
    output logic  [2:0] s20,            // S2-S0 pins (3'b111 passive)
    output logic  [2:0] tstate,         // 0 Ti 1 T1 2 T2 3 T3 4 T4 5 Tw
    output logic  [1:0] seg_s,          // S4-S3 of the cycle (valid T2-T4)
    output logic        seg_v,
    output logic        rd,             // 8288 MRDC / IORC
    output logic        wra,            // AMWC / AIOWC
    output logic        wr,             // MWTC / IOWC
    output logic        io,
    output logic        inta,           // 8288 INTA command
    output logic        lock_bus,       // LOCK during the INTA pair
    output logic [15:0] dout,
    input  logic [15:0] din,
    input  logic        ready,
    output logic  [1:0] qs,             // QS1-QS0: 0 none 1 first 2 flush 3 subsequent
    output logic  [7:0] qs_byte

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [15:0] tl_ip,
    input  logic  [2:0] tl_qlen,
    input  logic [47:0] tl_queue,
    input  logic [19:0] tl_ad,
    input  logic        tl_bhe
`endif
);

localparam logic [2:0] TI = 3'd0, T1 = 3'd1, T2 = 3'd2, T3 = 3'd3, T4 = 3'd4, TW = 3'd5, TD = 3'd6;
localparam logic [2:0] S_INTA = 3'b000, S_CODE = 3'b100, S_MEMW = 3'b110, S_IOW = 3'b010, S_HALT = 3'b011,
                       S_PASV = 3'b111;

logic  [2:0] ts;
logic        td_code;                   // pending T1 after Td is a code fetch
logic        c_code, c_int, c_word, c_hi, c_wr, c_lck;
logic  [2:0] c_type;
logic  [1:0] c_sidx;
logic [15:0] c_segv, c_off, c_wdata, c_corr;
logic        eu_cyc;                    // EU cycle accepted and not yet released
logic        req_q;
logic        susp;
logic  [7:0] q0, q1, q2, q3, q4, q5;    // shift queue, head in q0
logic  [7:0] qn [6];
logic  [2:0] qcnt, qcnt_d;
logic        was_t4;
logic [15:0] pf_ip;
logic [19:0] ad_q;
logic [15:0] bdata;
logic  [7:0] last_qb;
logic  [7:0] rlo;
logic  [2:0] rst_cnt;                   // internal reset sequence
logic        qhn;                       // the head byte entered an empty queue this clock
logic        disc, go_p;                // NEC: discard the running prefetch; target fetch waits for T4
logic        bhe_q;

logic  [2:0] nts, cnt;
logic        start_eu, start_code, push, go_now;

wire        req_new = eu_req & ~eu_cyc;
wire        c_odd   = c_off[0];                         // cycle started at an odd address
wire        c_split = ~c_code & c_word & (c_odd | (c_type == S_INTA));  // two cycles: odd word, INTA pair
wire        c_wide  = c_word & ~c_odd & (c_type != S_INTA);             // one 16-bit transfer
wire [15:0] c_offx  = c_off + {15'd0, c_hi};
wire [19:0] c_addr  = {c_segv, 4'd0} + {4'd0, c_offx};
wire        abort   = ~NEC & (ts == T1) & c_code & (req_new | susp);   // V30: a started prefetch is never aborted
wire  [1:0] c_nb    = c_odd ? 2'd1 : 2'd2;              // bytes a code fetch brings
// prefetch decisions: at T4 from the queue count of T3 (room for a word after this fetch); on the first idle clock
// after T4 a queue of 3 or more bytes waits one more clock
wire        room_t4 = (qcnt_d + (c_code ? {1'b0, c_nb} : 3'd0)) < 3'd5;
wire        room_ti = (qcnt < 3'd5) & ~(was_t4 & (qcnt > 3'd2));
wire  [3:0] stat_n  = {ps3, if_flag, c_sidx};
wire        c_rd    = ~c_wr & (c_type != S_INTA) & (c_type != S_HALT);
wire        c_inta  = c_type == S_INTA;
// active data lanes of this cycle
wire        lane_hi = c_wide | (c_odd & ~c_hi);
wire        lane_lo = c_wide | ~c_odd | c_hi;
wire [15:0] din_m   = {lane_hi ? din[15:8] : c_addr[15:8], lane_lo ? din[7:0] : c_addr[7:0]};

assign eu_rdata = c_split ? {din[7:0], rlo} : c_wide ? din : {8'd0, c_odd ? din[15:8] : din[7:0]};
assign q_avail = qcnt != 3'd0;
assign q_old   = q_avail & ~qhn;
assign q_byte  = q0;
assign susp_ok = NEC ? ((ts != T1) & (ts != T2)) : (ts == T4) | (ts == TI) | (ts == TD) | ((ts == T1) & c_code & susp);  // = abort while suspending; NEC: the target fetch waits out T1 / T2
assign bus_idle = ts == TI;
assign bus_t4   = ts == T4;
// a word that starts at an odd address goes out byte-swapped in both cycles
assign dout    = c_odd ? {c_wdata[7:0], c_wdata[15:8]} : c_wdata;

// queue next state: pop shifts towards q0, fetched bytes land behind the remaining ones
wire q_fw = (ts == T4) & c_code & ~eu_flush & ~disc;
wire [7:0] qv [6];
assign qv[0] = q0; assign qv[1] = q1; assign qv[2] = q2; assign qv[3] = q3; assign qv[4] = q4; assign qv[5] = q5;
wire [7:0] fb0 = c_odd ? bdata[15:8] : bdata[7:0];
wire [7:0] fb1 = bdata[15:8];
logic [3:0] qi;
always_comb begin
    for (int i = 0; i < 6; i++) begin
        qi = i[3:0] + {3'd0, q_pop};               // old position that lands at i
        if (q_fw & ({1'b0, qcnt} == qi)) qn[i] = fb0;
        else if (q_fw & ~c_odd & ({1'b0, qcnt} + 4'd1 == qi)) qn[i] = fb1;
        else if (q_pop) qn[i] = (i < 5) ? qv[(i + 1) % 6] : q5;
        else qn[i] = qv[i];
    end
`ifdef X86SV_TESTLOAD
    if (tl_en) for (int i = 0; i < 6; i++) qn[i] = tl_queue[8*i +: 8];
`endif
end

// release: reads on the data cycle (T3 / last Tw), writes on T2 of the last cycle
wire rel_t1 = eu_cyc & ~c_code & c_int;
wire rel_t2 = eu_cyc & ~c_code & ~c_int & (c_wr ? (~c_split | c_hi) : (c_type == S_HALT));
wire rel_t3 = eu_cyc & ~c_code & ~c_int & ~c_wr & (c_type != S_HALT) & (~c_split | c_hi);
assign eu_rel = (rel_t1 & (ts == T1)) | (rel_t2 & (ts == T2)) | (rel_t3 & ((ts == T3) | (ts == TW)) & ready);

// pins
always_comb begin
    ad    = ad_q;
    ale   = 1'b0;
    s20   = S_PASV;
    seg_v = 1'b0;
    rd    = 1'b0;
    wra   = 1'b0;
    wr    = 1'b0;
    inta  = 1'b0;
    case (ts)
        T1: begin
            // T1 without a bus cycle (aborted prefetch, IP correction): A18 reads low
            if (c_int)        ad = {c_corr[15], 1'b0, c_corr[13:0], 4'hF};
            else if (abort)   ad = NEC ? ad_q : {c_addr[19], 1'b0, c_addr[17:0]};
            else begin
                ad  = c_addr;
                ale = 1'b1;
                s20 = c_type;
            end
        end
        T2: begin
            ad    = {stat_n, c_wr ? dout : c_addr[15:0]};
            s20   = c_type;
            seg_v = 1'b1;
            rd    = c_rd;
            wra   = c_wr;
            inta  = c_inta;
        end
        T3, TW: begin
            // S2-S0 return to passive in the T3 / Tw in which READY is high
            ad    = {stat_n, c_wr ? dout : din_m};
            s20   = ready ? S_PASV : c_type;
            seg_v = 1'b1;
            rd    = c_rd;
            wra   = c_wr;
            wr    = c_wr;
            inta  = c_inta;
        end
        T4: seg_v = 1'b1;
        default: ;
    endcase
end
assign tstate = (ts == TD) ? TI : (abort | (c_int & (ts == T1))) ? TI : ts;
assign seg_s  = c_sidx;
assign io     = (c_type == 3'b001) | (c_type == S_IOW);
assign bhe_n  = ((ts == T1) & ale) ? ~(c_addr[0] | c_wide | (c_inta & ~c_hi)) : (abort & req_q & ~was_t4) ? ~eu_word : bhe_q;
// LOCK from T2 of the first INTA cycle to T2 of the second; a locked instruction keeps LOCK to the end of its last
// bus cycle
assign lock_bus = (c_inta & (c_hi ? (ts == T1) : ((ts == T2) | (ts == T3) | (ts == TW) | (ts == T4)))) |
                  (c_lck & (ts != TI) & (ts != TD));

always_ff @(posedge clk) begin
    if (reset) begin
        ts <= TI; td_code <= 1'b0; c_lck <= 1'b0; c_code <= 1'b0; c_int <= 1'b0; c_word <= 1'b0; c_hi <= 1'b0; c_wr <= 1'b0;
        c_type <= S_PASV; c_sidx <= 2'd2; c_segv <= 16'd0; c_off <= 16'd0; c_wdata <= 16'd0; c_corr <= 16'd0;
        eu_cyc <= 1'b0; req_q <= 1'b0; susp <= 1'b0; qcnt <= 3'd0; qcnt_d <= 3'd0; was_t4 <= 1'b0; pf_ip <= 16'd0;
        qhn <= 1'b0; disc <= 1'b0; go_p <= 1'b0; ad_q <= 20'd0; bdata <= 16'd0; rst_cnt <= 3'd7; rlo <= 8'd0; qs <= 2'd0; qs_byte <= 8'd0; last_qb <= 8'd0;
        bhe_q <= 1'b1;
    end else if (ce) begin
        nts = ts;
        start_eu = 1'b0;
        start_code = 1'b0;
        push = 1'b0;
        go_now = 1'b0;
        req_q <= req_new;
        qcnt_d <= qcnt;
        was_t4 <= ts == T4;
        ad_q  <= ad;
        bhe_q <= bhe_n;

        if (rst_cnt != 3'd0) rst_cnt <= rst_cnt - 3'd1;
        case (ts)
            TI: if (rst_cnt != 3'd0) ;
                else if (req_new) begin nts = TD; td_code <= 1'b0; end
                else if (NEC & (eu_fgo | go_p)) begin nts = TD; td_code <= 1'b1; go_now = 1'b1; end
                else if (room_ti & ~susp & ~eu_susp) begin nts = TD; td_code <= 1'b1; end
            TD: begin
                nts = T1;
                if (td_code) start_code = 1'b1; else start_eu = 1'b1;
            end
            T1: if (abort) begin
                    if (req_new) begin nts = TD; td_code <= 1'b0; end
                    else nts = TI;
                end else if (c_int) nts = TI;
                else nts = T2;
            T2: nts = T3;
            T3, TW: if (ready) begin
                    nts = T4;
                    bdata <= din;
                    if (~c_code & ~c_wr & ~c_hi) rlo <= din[15:8];
                end else nts = TW;
            T4: begin
                if (c_code) push = ~disc;
                if (c_split & ~c_hi & ~c_code) begin
                    nts = T1;
                    c_hi <= 1'b1;
                end else if (req_q | (NEC & eu_fast & req_new & ~c_code)) begin nts = T1; start_eu = 1'b1; end
                else if (NEC & go_p) begin nts = T1; start_code = 1'b1; go_now = 1'b1; end
                else if (NEC & eu_fgo) begin nts = TD; td_code <= 1'b1; go_now = 1'b1; end
                else if (room_t4 & ~susp & ~(NEC & req_new) & ~(NEC & eu_pre & ~c_code & (qcnt_d == 3'd3))) begin nts = T1; start_code = 1'b1; end
                else nts = TI;
            end
            default: nts = TI;
        endcase

        if (start_eu) begin
            c_code <= 1'b0; c_lck <= eu_lock; c_int <= eu_int; c_type <= eu_type; c_word <= eu_word; c_hi <= 1'b0;
            c_wr <= (eu_type == S_MEMW) | (eu_type == S_IOW);
            c_sidx <= eu_sidx; c_segv <= eu_segv; c_off <= eu_off; c_wdata <= eu_wdata; c_corr <= eu_corr;
            eu_cyc <= 1'b1;
        end else if (start_code) begin
            c_code <= 1'b1; c_lck <= 1'b0; c_int <= 1'b0; c_type <= S_CODE; c_word <= 1'b1; c_hi <= 1'b0; c_wr <= 1'b0;
            c_sidx <= 2'd2; c_segv <= cs; c_off <= pf_ip + (push ? {14'd0, c_nb} : 16'd0);
        end else if (eu_rel) eu_cyc <= 1'b0;

        // queue
        begin
            cnt = qcnt;
            if (q_pop) begin
                cnt = cnt - 3'd1;
                last_qb <= q_byte;
            end
            qhn <= push & ~eu_flush & (cnt == 3'd0);
            if (push & ~eu_flush) begin
                cnt = cnt + {1'b0, c_nb};
                pf_ip <= pf_ip + {14'd0, c_nb};
            end
            if (eu_flush) begin
                cnt = 3'd0;
                pf_ip <= eu_flush_ip;
            end
            qcnt <= cnt;
            q0 <= qn[0]; q1 <= qn[1]; q2 <= qn[2]; q3 <= qn[3]; q4 <= qn[4]; q5 <= qn[5];
        end
        if (eu_susp) susp <= 1'b1;
        if (eu_flush & ~NEC) susp <= 1'b0;
        if (NEC & eu_fgo) susp <= 1'b0;
        // NEC: a flush while a prefetch is running discards its byte; the target fetch follows its T4
        if (NEC & eu_flush & c_code & (ts != T4) & (ts != TI) & (ts != TD)) disc <= 1'b1;
        else if (ts == T4) disc <= 1'b0;
        go_p <= NEC & (go_p | eu_fgo) & ~go_now;

        qs      <= eu_flush ? 2'd2 : q_pop ? (q_first ? 2'd1 : 2'd3) : 2'd0;
        qs_byte <= eu_flush ? last_qb : q_pop ? q_byte : 8'd0;
        ts <= nts;

`ifdef X86SV_TESTLOAD
        if (tl_en) begin
            ts <= TI; eu_cyc <= 1'b0; req_q <= 1'b0; susp <= 1'b0; c_code <= 1'b0; c_int <= 1'b0; rst_cnt <= 3'd0;
            qcnt <= tl_qlen; qcnt_d <= tl_qlen; was_t4 <= 1'b0; pf_ip <= tl_ip + {13'd0, tl_qlen};
            qhn <= 1'b0; disc <= 1'b0; go_p <= 1'b0; ad_q <= tl_ad; qs <= 2'd0; qs_byte <= 8'd0; bhe_q <= tl_bhe;
        end
`endif
    end
end

endmodule

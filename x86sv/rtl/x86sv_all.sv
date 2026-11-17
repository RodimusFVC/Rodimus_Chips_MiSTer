// Copyright (C) 2026 Rodimus
// x86sv: 8088 / 8086 CPU core, all modules in one file (generated from rtl/x86sv_*.sv by verify/tools/mkall.sh)


module x86sv_alu (
    input  logic  [3:0] op,             // 0-7 = reg field order, 8 INC, 9 DEC
    input  logic        w,
    input  logic [15:0] a,
    input  logic [15:0] b,
    input  logic        cin,
    output logic [15:0] r,
    output logic        cf,
    output logic        pf,
    output logic        af,
    output logic        zf,
    output logic        sf,
    output logic        of
);

logic [16:0] sum;
logic        c, sub, logic_op;
logic [15:0] lr, bx;

// one adder: subtraction adds the complement with an inverted carry
always_comb begin
    sub = (op == 4'd3) | (op == 4'd5) | (op == 4'd7) | (op == 4'd9);
    c = ((op == 4'd2) | (op == 4'd3)) & cin;
    bx = b ^ {16{sub}};
    sum = {1'b0, a} + {1'b0, bx} + {16'd0, c ^ sub};
    logic_op = (op == 4'd1) | (op == 4'd4) | (op == 4'd6);
    case (op[2:0])
        3'd1:    lr = a | b;
        3'd4:    lr = a & b;
        default: lr = a ^ b;
    endcase
    r  = logic_op ? lr : sum[15:0];
    if (logic_op) begin
        cf = 1'b0;
        of = 1'b0;
        af = 1'b0;
    end else begin
        cf = w ? (sum[16] ^ sub) : ((a[8] ^ b[8]) ^ r[8]);
        af = a[4] ^ b[4] ^ r[4];
        if (w) of = (a[15] ^ bx[15] ^ 1'b1) & (a[15] ^ r[15]);
        else   of = (a[7] ^ bx[7] ^ 1'b1) & (a[7] ^ r[7]);
    end
    pf = ~^r[7:0];
    zf = w ? (r == 16'd0) : (r[7:0] == 8'd0);
    sf = w ? r[15] : r[7];
end

endmodule


module x86sv_biu #(
    parameter bit NEC = 1'b0            // V20 bus rules: no prefetch abort, an EU request at T4 blocks the prefetch
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
    output logic        eu_rel,         // read: data valid this cycle (T3); write: T2 of the last byte
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
    output logic [19:0] ad,             // multiplexed AD19-AD0 as driven this cycle
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
    output logic  [7:0] dout,
    input  logic  [7:0] din,
    input  logic        ready,
    output logic  [1:0] qs,             // QS1-QS0: 0 none 1 first 2 flush 3 subsequent
    output logic  [7:0] qs_byte

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [15:0] tl_ip,
    input  logic  [2:0] tl_qlen,
    input  logic [31:0] tl_queue,
    input  logic [19:0] tl_ad
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
logic  [7:0] q0, q1, q2, q3;            // shift queue, head in q0
logic  [7:0] qn0, qn1, qn2, qn3;
logic  [2:0] qcnt, qcnt_d;
logic        was_t4;
logic [15:0] pf_ip;
logic [19:0] ad_q;
logic  [7:0] bdata;
logic  [7:0] last_qb;
logic  [7:0] rlo;
logic  [2:0] rst_cnt;                   // internal reset sequence
logic        qhn;                       // the head byte entered an empty queue this clock
logic        disc, go_p;                // NEC: discard the running prefetch; target fetch waits for T4

logic  [2:0] nts, cnt;
logic        start_eu, start_code, push, go_now;

wire        req_new = eu_req & ~eu_cyc;
wire [15:0] c_offx  = c_off + {15'd0, c_hi};
wire [19:0] c_addr  = {c_segv, 4'd0} + {4'd0, c_offx};
wire        abort   = ~NEC & (ts == T1) & c_code & (req_new | susp);   // V20: a started prefetch is never aborted
// prefetch decisions: at T4 from the queue count of T3; on the first idle clock after T4 a 3-byte queue waits
wire        room_t4 = (qcnt_d + {2'd0, c_code}) < 3'd4;
wire        room_ti = (qcnt < 3'd4) & ~(was_t4 & (qcnt == 3'd3));
wire  [3:0] stat_n  = {ps3, if_flag, c_sidx};
wire        c_rd    = ~c_wr & (c_type != S_INTA) & (c_type != S_HALT);
wire        c_inta  = c_type == S_INTA;

assign eu_rdata = {c_hi ? din : 8'd0, c_hi ? rlo : din};
assign q_avail = qcnt != 3'd0;
assign q_old   = q_avail & ~qhn;
assign q_byte  = q0;
assign susp_ok = NEC ? ((ts != T1) & (ts != T2)) : (ts == T4) | (ts == TI) | (ts == TD) | ((ts == T1) & c_code & susp);  // = abort while suspending; NEC: the target fetch waits out T1 / T2
assign bus_idle = ts == TI;
assign bus_t4   = ts == T4;

// queue next state: pop shifts towards q0, a fetched byte lands behind the remaining ones (both pop cases are
// formed in parallel and selected by q_pop last)
wire q_fw = (ts == T4) & c_code & ~eu_flush & ~disc;
always_comb begin
    qn0 = q_pop ? ((q_fw & (qcnt == 3'd1)) ? bdata : q1) : ((q_fw & (qcnt == 3'd0)) ? bdata : q0);
    qn1 = q_pop ? ((q_fw & (qcnt == 3'd2)) ? bdata : q2) : ((q_fw & (qcnt == 3'd1)) ? bdata : q1);
    qn2 = q_pop ? ((q_fw & (qcnt == 3'd3)) ? bdata : q3) : ((q_fw & (qcnt == 3'd2)) ? bdata : q2);
    qn3 = (q_fw & (qcnt == (q_pop ? 3'd4 : 3'd3))) ? bdata : q3;
`ifdef X86SV_TESTLOAD
    if (tl_en) {qn3, qn2, qn1, qn0} = tl_queue;
`endif
end


// release: reads on the data cycle (T3 / last Tw), writes on T2 of the last byte
wire rel_t1 = eu_cyc & ~c_code & c_int;
wire rel_t2 = eu_cyc & ~c_code & ~c_int & (c_wr ? (~c_word | c_hi) : (c_type == S_HALT));
wire rel_t3 = eu_cyc & ~c_code & ~c_int & ~c_wr & (c_type != S_HALT) & (~c_word | c_hi);
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
    dout  = c_hi ? c_wdata[15:8] : c_wdata[7:0];
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
            ad    = {stat_n, c_addr[15:8], c_wr ? dout : c_addr[7:0]};
            s20   = c_type;
            seg_v = 1'b1;
            rd    = c_rd;
            wra   = c_wr;
            inta  = c_inta;
        end
        T3, TW: begin
            // S2-S0 return to passive in the T3 / Tw in which READY is high (8088 datasheet, S2-S0 pin description)
            ad    = {stat_n, c_addr[15:8], c_wr ? dout : din};
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
// LOCK from T2 of the first INTA cycle to T2 of the second (8088 datasheet, Figure 9)
// a locked instruction keeps LOCK to the end of its last bus cycle (8088 datasheet, LOCK)
assign lock_bus = (c_inta & (c_hi ? (ts == T1) : ((ts == T2) | (ts == T3) | (ts == TW) | (ts == T4)))) |
                  (c_lck & (ts != TI) & (ts != TD));

always_ff @(posedge clk) begin
    if (reset) begin
        ts <= TI; td_code <= 1'b0; c_lck <= 1'b0; c_code <= 1'b0; c_int <= 1'b0; c_word <= 1'b0; c_hi <= 1'b0; c_wr <= 1'b0;
        c_type <= S_PASV; c_sidx <= 2'd2; c_segv <= 16'd0; c_off <= 16'd0; c_wdata <= 16'd0; c_corr <= 16'd0;
        eu_cyc <= 1'b0; req_q <= 1'b0; susp <= 1'b0; qcnt <= 3'd0; qcnt_d <= 3'd0; was_t4 <= 1'b0; pf_ip <= 16'd0;
        qhn <= 1'b0; disc <= 1'b0; go_p <= 1'b0; ad_q <= 20'd0; bdata <= 8'd0; rst_cnt <= 3'd7; rlo <= 8'd0; qs <= 2'd0; qs_byte <= 8'd0; last_qb <= 8'd0;
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

        if (rst_cnt != 3'd0) rst_cnt <= rst_cnt - 3'd1;
        case (ts)
            TI: if (rst_cnt != 3'd0) ;
                else if (req_new) begin nts = TD; td_code <= 1'b0; end
                else if (NEC & (eu_fgo | go_p)) begin nts = TD; td_code <= 1'b1; go_now = 1'b1; end
                else if (room_ti & ~susp) begin nts = TD; td_code <= 1'b1; end
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
                    if (~c_code & ~c_wr & ~c_hi) rlo <= din;
                end else nts = TW;
            T4: begin
                if (c_code) push = ~disc;
                if (c_word & ~c_hi & ~c_code) begin
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
            c_code <= 1'b1; c_lck <= 1'b0; c_int <= 1'b0; c_type <= S_CODE; c_word <= 1'b0; c_hi <= 1'b0; c_wr <= 1'b0;
            c_sidx <= 2'd2; c_segv <= cs; c_off <= pf_ip + {15'd0, push};
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
                cnt = cnt + 3'd1;
                pf_ip <= pf_ip + 16'd1;
            end
            if (eu_flush) begin
                cnt = 3'd0;
                pf_ip <= eu_flush_ip;
            end
            qcnt <= cnt;
            q0 <= qn0; q1 <= qn1; q2 <= qn2; q3 <= qn3;
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
            qhn <= 1'b0; disc <= 1'b0; go_p <= 1'b0; ad_q <= tl_ad; qs <= 2'd0; qs_byte <= 8'd0;
        end
`endif
    end
end

endmodule


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


module x86sv_eu #(
    parameter bit BUS16 = 1'b0,         // 8086 / V30 EU timing differences
    parameter bit NEC   = 1'b0,         // V20 / V30
    parameter bit NEC8080 = 1'b0        // V20 / V30 8080 emulation mode (with NEC)
) (
    input  logic        clk,
    input  logic        ce,
    input  logic        reset,

    input  logic        q_avail,
    input  logic        q_old,          // the head byte was already in the queue last clock
    input  logic  [7:0] q_byte,
    output logic        q_pop,
    output logic        q_first,

    output logic        req,
    output logic        req_fast,       // NEC: write right after the read that supplies its data
    output logic        req_pre,        // NEC: a request follows next clock
    output logic  [2:0] req_type,       // S2-S0 of the cycle
    output logic        req_int,        // internal IP-correction cycle
    output logic        req_word,
    output logic  [1:0] req_sidx,
    output logic [15:0] req_segv,
    output logic [15:0] req_off,
    output logic [15:0] req_wdata,
    output logic [15:0] req_corr,
    input  logic        rel,
    input  logic [15:0] rdata,
    output logic        susp,
    output logic        flush,
    output logic [15:0] flush_ip,
    output logic        fgo,            // NEC: start the code fetch at the new address
    input  logic        bus_idle,       // NEC: bus in Ti
    input  logic        bus_t4,         // NEC: bus in T4
    input  logic        susp_ok,
    output logic [15:0] cs,
    output logic        if_flag,
    output logic        lock,
    output logic        emu,            // 8080 emulation mode (MD = 0): PS3

    input  logic        intr,           // level, sampled at instruction boundaries
    input  logic        nmi,            // rising edge
    input  logic        test_n,         // WAIT input

    output logic [15:0] dbg_ip,         // offset of the last first byte read from the queue
    output logic [15:0] dbg_flags,
    output logic [7:0][15:0] dbg_r,     // AX CX DX BX SP BP SI DI
    output logic [3:0][15:0] dbg_s      // ES CS SS DS

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [7:0][15:0] tl_r,
    input  logic [3:0][15:0] tl_s,
    input  logic [15:0] tl_ip,
    input  logic [15:0] tl_flags,
    input  logic        tl_md,
    input  logic        tl_mdwe,
    output logic        dbg_mdwe
`endif
);

localparam bit EXT = BUS16 | NEC;      // options that need the step pre-delay
localparam bit E8  = NEC & NEC8080;    // 8080 emulation mode
localparam logic [2:0] S_OP = 3'd0, S_PFX = 3'd1, S_DEC = 3'd2, S_EA = 3'd3, S_EX = 3'd4, S_X0F = 3'd5;
localparam logic [5:0] K_NONE = 6'd0, K_PFX = 6'd1, K_MOVRM = 6'd2, K_MOVSR = 6'd3, K_ALURM = 6'd4, K_ALUAI = 6'd5,
                       K_ALUIM = 6'd6, K_INCR = 6'd7, K_INCRM = 6'd8, K_FLAG = 6'd9, K_JCC = 6'd10, K_JMPS = 6'd11,
                       K_JMPN = 6'd12, K_MOVI8 = 6'd13, K_MOVI16 = 6'd14, K_MOVMI = 6'd15, K_MOVAM = 6'd16,
                       K_PUSHR = 6'd17, K_POPR = 6'd18, K_PUSHS = 6'd19, K_POPS = 6'd20, K_POPM = 6'd21,
                       K_RET = 6'd22, K_CALLN = 6'd23, K_XCHGA = 6'd24, K_MISC = 6'd25, K_BCD = 6'd26,
                       K_XCHG = 6'd27, K_LEA = 6'd28, K_GRP3 = 6'd29, K_LOOP = 6'd30, K_JMPF = 6'd31,
                       K_CALLF = 6'd32, K_RETF = 6'd33, K_INT = 6'd34, K_IRET = 6'd35, K_PUSHF = 6'd36,
                       K_POPF = 6'd37, K_LDS = 6'd38, K_XLAT = 6'd39, K_IO = 6'd40, K_ESC = 6'd41,
                       K_SHIFT = 6'd42, K_AAM = 6'd43, K_AAD = 6'd44, K_STR = 6'd45, K_HLT = 6'd46,
                       K_WAIT = 6'd47;
// NEC classes (V20 / V30)
localparam logic [5:0] K_PUSHA = 6'd48, K_POPA = 6'd49, K_BOUND = 6'd50, K_PUSHI = 6'd51, K_IMULI = 6'd52,
                       K_ENTER = 6'd53, K_LEAVE = 6'd54, K_X0F = 6'd55, K_SHIFTI = 6'd56, K_INSOUT = 6'd57;
localparam int KW = NEC ? 64 : 48;      // class one-hot width
localparam logic [2:0] B_INTA = 3'b000, B_IOR = 3'b001, B_IOW = 3'b010, B_HALT = 3'b011, B_MEMR = 3'b101,
                       B_MEMW = 3'b110;
// request address sources
localparam logic [3:0] A_EA = 4'd0, A_EA2 = 4'd1, A_STK = 4'd2, A_IMM = 4'd3, A_DX = 4'd4, A_XLAT = 4'd5,
                       A_VEC = 4'd6, A_VEC2 = 4'd7, A_SI = 4'd8, A_DI = 4'd9,
                       A_BP = 4'd10,      // NEC: SS:BP (LEAVE)
                       A_PD = 4'd11;      // NEC: ES:pd (EXT: DS or override:pd)
// write data sources
localparam logic [1:0] D_DEF = 2'd0, D_FL = 2'd1, D_CS = 2'd2, D_TMP = 2'd3;
// queue byte destinations
localparam logic [2:0] Q_LO = 3'd0, Q_HI = 3'd1, Q_SX = 3'd2, Q_ZX = 3'd3, Q_SLO = 3'd4, Q_SHI = 3'd5, Q_VEC = 3'd6;

function automatic logic w_of(input logic [5:0] c, input logic [7:0] o);
    w_of = (c == K_INCR) | (c == K_MOVI16) | (c == K_MOVSR) | (c == K_XCHGA) | (c == K_LEA) | (c == K_LDS) |
           ((c == K_MOVI8) ? 1'b0 : o[0]);
endfunction

function automatic logic w_nec(input logic [5:0] c, input logic [7:0] o);
    w_nec = w_of(c, o) | (c == K_PUSHA) | (c == K_POPA) | (c == K_BOUND) | (c == K_PUSHI) | (c == K_ENTER);
endfunction

function automatic logic hm_of(input logic [5:0] c);
    hm_of = (c == K_ALURM) | (c == K_ALUIM) | (c == K_MOVRM) | (c == K_MOVSR) | (c == K_MOVMI) | (c == K_INCRM) |
            (c == K_POPM) | (c == K_XCHG) | (c == K_LEA) | (c == K_GRP3) | (c == K_LDS) | (c == K_ESC) | (c == K_SHIFT);
endfunction

function automatic logic [5:0] cls_of(input logic [7:0] o);
    casez (o)
        8'b00??_?0??: cls_of = K_ALURM;
        8'b00??_?10?: cls_of = K_ALUAI;
        8'b001?_?110: cls_of = K_PFX;
        8'h27, 8'h2F, 8'h37, 8'h3F: cls_of = K_BCD;
        8'b0100_????: cls_of = K_INCR;
        8'b0101_0???: cls_of = K_PUSHR;
        8'b0101_1???: cls_of = K_POPR;
        8'b011?_????: cls_of = K_JCC;
        8'b1000_00??: cls_of = K_ALUIM;
        8'h84, 8'h85: cls_of = K_ALURM;
        8'h86, 8'h87: cls_of = K_XCHG;
        8'b1000_10??: cls_of = K_MOVRM;
        8'h8C, 8'h8E: cls_of = K_MOVSR;
        8'h8D:        cls_of = K_LEA;
        8'h8F:        cls_of = K_POPM;
        8'b1001_0???: cls_of = K_XCHGA;
        8'h98, 8'h99, 8'h9E, 8'h9F, 8'hD6: cls_of = K_MISC;
        8'h9A:        cls_of = K_CALLF;
        8'h9B:        cls_of = K_WAIT;
        8'h9C:        cls_of = K_PUSHF;
        8'h9D:        cls_of = K_POPF;
        8'b1010_00??: cls_of = K_MOVAM;
        8'hA8, 8'hA9: cls_of = K_ALUAI;
        8'b1010_01??, 8'b1010_101?, 8'b1010_11??: cls_of = K_STR;
        8'b1011_0???: cls_of = K_MOVI8;
        8'b1011_1???: cls_of = K_MOVI16;
        8'b1100_?0??: cls_of = (o[3]) ? K_RETF : K_RET;
        8'hC4, 8'hC5: cls_of = K_LDS;
        8'hC6, 8'hC7: cls_of = K_MOVMI;
        8'hCC, 8'hCD, 8'hCE: cls_of = K_INT;
        8'hCF:        cls_of = K_IRET;
        8'b1101_00??: cls_of = K_SHIFT;
        8'hD4:        cls_of = K_AAM;
        8'hD5:        cls_of = K_AAD;
        8'hD7:        cls_of = K_XLAT;
        8'b1101_1???: cls_of = K_ESC;
        8'b1110_00??: cls_of = K_LOOP;
        8'b1110_?1??: cls_of = K_IO;
        8'hE8:        cls_of = K_CALLN;
        8'hE9:        cls_of = K_JMPN;
        8'hEA:        cls_of = K_JMPF;
        8'hEB:        cls_of = K_JMPS;
        8'hF0, 8'hF1, 8'hF2, 8'hF3: cls_of = K_PFX;
        8'hF4:        cls_of = K_HLT;
        8'hF6, 8'hF7: cls_of = K_GRP3;
        8'hF5, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD: cls_of = K_FLAG;
        8'hFE, 8'hFF: cls_of = K_INCRM;
        8'h06, 8'h0E, 8'h16, 8'h1E: cls_of = K_PUSHS;
        8'h07, 8'h0F, 8'h17, 8'h1F: cls_of = K_POPS;
        default:      cls_of = K_NONE;
    endcase
endfunction

function automatic logic hm_nec(input logic [5:0] c);
    hm_nec = hm_of(c) | (c == K_BOUND) | (c == K_IMULI) | (c == K_SHIFTI);
endfunction

// NEC: 80186 additions and NEC changes on top of the 8088 map
function automatic logic [5:0] cls_nec(input logic [7:0] o);
    casez (o)
        8'h60:        cls_nec = K_PUSHA;
        8'h61:        cls_nec = K_POPA;
        8'h62:        cls_nec = K_BOUND;
        8'h63, 8'h66, 8'h67: cls_nec = K_ESC;   // undefined / FPO2: like ESC (dummy word read of a memory operand)
        8'h64, 8'h65: cls_nec = K_PFX;          // REPNC / REPC
        8'h68, 8'h6A: cls_nec = K_PUSHI;
        8'h69, 8'h6B: cls_nec = K_IMULI;
        8'b0110_11??: cls_nec = K_INSOUT;       // INS / OUTS
        8'hC0, 8'hC1: cls_nec = K_SHIFTI;
        8'hC8:        cls_nec = K_ENTER;
        8'hC9:        cls_nec = K_LEAVE;
        8'hD6:        cls_nec = K_XLAT;
        8'h0F:        cls_nec = K_X0F;
        default:      cls_nec = cls_of(o);
    endcase
endfunction

// architectural state
logic [7:0][15:0] r;
logic [3:0][15:0] sr;
logic [15:0] ip;
logic        f_c, f_p, f_a, f_z, f_s, f_t, f_i, f_d, f_o;

// 8080 emulation mode (NEC UM section 8): MD (PSW bit 15, 1 = native) and its write enable (set by BRKEM, cleared by
// RETEM); the decoded 8080 instruction's options, registered with its opcode
logic        md, mdwe;
logic        e8;                        // 8080 instruction: ModRM preset, 8080 flag rules
logic        e_st, e_nf, e_cy, e_psw, e_abs, e_cc, e_daa, e_rst, e_calln, e_retem, e_brkem;
logic        e_hm;                      // 8080 instruction with a preset ModRM (decoded without a queue byte)
logic  [1:0] e_acm, e_eas;              // AC rule (ADD / SUB / AND / logic); EA source (HL, BC, DE, SP)
logic  [2:0] e_cn;                      // 8080 condition / RST number
logic  [7:0] e_mrm;                     // 8080: preset ModRM

// instruction state
logic  [2:0] st;
logic  [3:0] cnt;
logic  [1:0] ph;
logic  [7:0] op, mrm, vec;
logic [KW-1:0] k1;                      // decoded class of op (one-hot), registered with it
logic [63:0] kk;                        // k1 widened (NEC class bits read as 0 without NEC)
always_comb begin kk = 64'd0; kk[KW-1:0] = k1; end
wire [KW-1:0] k_one = {{(KW-1){1'b0}}, 1'b1};
wire   [5:0] hcls = NEC ? cls_nec(q_byte) : cls_of(q_byte);  // class of the queue head byte

// 8080 opcode -> native class, opcode and ModRM (registers per NEC UM figure 8-1: A AL, B CH, C CL, D DH, E DL, H BH,
// L BL, SP BP, M = DS0:[BW]); the native step sequences then run the instruction
function automatic logic [2:0] m8(input logic [2:0] i);
    case (i)
        3'd0: m8 = 3'd5; 3'd1: m8 = 3'd1; 3'd2: m8 = 3'd6; 3'd3: m8 = 3'd2;
        3'd4: m8 = 3'd7; 3'd5: m8 = 3'd3; default: m8 = 3'd0;
    endcase
endfunction
function automatic logic [2:0] p16(input logic [1:0] i);
    p16 = (i == 2'd3) ? 3'd5 : {1'b0, i} + 3'd1;
endfunction
logic [7:0] t_op, t_mrm;
logic [5:0] t_cls;
logic       t_st, t_nf, t_cy, t_psw, t_abs, t_cc, t_daa, t_rst;
logic [1:0] t_acm, t_eas;
always_comb begin
    t_op = 8'h90; t_cls = K_XCHGA; t_mrm = 8'd0; t_st = 1'b0; t_nf = 1'b0; t_cy = 1'b0; t_psw = 1'b0; t_abs = 1'b0;
    t_cc = 1'b0; t_daa = 1'b0; t_rst = 1'b0; t_acm = 2'd0; t_eas = 2'd0;
    casez (q_byte)
        8'b01??_????: begin
            t_cls = K_MOVRM;
            if (q_byte == 8'h76) begin t_op = 8'hF4; t_cls = K_HLT; end
            else if (q_byte[2:0] == 3'd6) begin t_op = 8'h8A; t_mrm = {2'b00, m8(q_byte[5:3]), 3'd7}; end
            else if (q_byte[5:3] == 3'd6) begin t_op = 8'h88; t_mrm = {2'b00, m8(q_byte[2:0]), 3'd7}; end
            else begin t_op = 8'h8A; t_mrm = {2'b11, m8(q_byte[5:3]), m8(q_byte[2:0])}; end
        end
        8'b10??_????, 8'b11??_?110: begin             // ADD ADC SUB SBB ANA XRA ORA CMP (r / M / imm)
            case (q_byte[5:3])
                3'd0: t_op = 8'h00; 3'd1: t_op = 8'h10; 3'd2: t_op = 8'h28; 3'd3: t_op = 8'h18;
                3'd4: t_op = 8'h20; 3'd5: t_op = 8'h30; 3'd6: t_op = 8'h08; default: t_op = 8'h38;
            endcase
            t_acm = (q_byte[5:3] == 3'd4) ? 2'd2 : (q_byte[5:3] == 3'd5 || q_byte[5:3] == 3'd6) ? 2'd3 :
                    (q_byte[5:4] == 2'd0) ? 2'd0 : 2'd1;
            if (q_byte[7:6] == 2'b11) begin t_cls = K_ALUAI; t_op = t_op | 8'h04; end
            else begin
                t_cls = K_ALURM; t_op = t_op | 8'h02;
                t_mrm = (q_byte[2:0] == 3'd6) ? 8'b00_000_111 : {5'b11_000, m8(q_byte[2:0])};
            end
        end
        8'b00??_0001: begin t_cls = K_MOVI16; t_op = {5'b10111, p16(q_byte[5:4])}; end                  // LXI
        8'b00??_1001: begin t_cls = K_ALURM; t_op = 8'h03; t_mrm = {5'b11_011, p16(q_byte[5:4])}; t_cy = 1'b1; end  // DAD
        8'b000?_0010: begin t_cls = K_MOVRM; t_op = 8'h88; t_mrm = 8'b00_000_111; t_eas = q_byte[4] ? 2'd2 : 2'd1; end  // STAX
        8'b000?_1010: begin t_cls = K_MOVRM; t_op = 8'h8A; t_mrm = 8'b00_000_111; t_eas = q_byte[4] ? 2'd2 : 2'd1; end  // LDAX
        8'h22:        begin t_cls = K_MOVRM; t_op = 8'h89; t_mrm = 8'b00_011_110; end                    // SHLD
        8'h2A:        begin t_cls = K_MOVRM; t_op = 8'h8B; t_mrm = 8'b00_011_110; end                    // LHLD
        8'h32:        begin t_cls = K_MOVAM; t_op = 8'hA2; end                                         // STA
        8'h3A:        begin t_cls = K_MOVAM; t_op = 8'hA0; end                                         // LDA
        8'b00??_0011: begin t_cls = K_INCR; t_op = {5'b01000, p16(q_byte[5:4])}; t_nf = 1'b1; end         // INX
        8'b00??_1011: begin t_cls = K_INCR; t_op = {5'b01001, p16(q_byte[5:4])}; t_nf = 1'b1; end         // DCX
        8'b00??_?10?: begin                                                                            // INR DCR
            t_cls = K_INCRM; t_op = 8'hFE; t_acm = {1'b0, q_byte[0]};
            t_mrm = (q_byte[5:3] == 3'd6) ? {4'b00_00, q_byte[0], 3'd7} : {4'b11_00, q_byte[0], m8(q_byte[5:3])};
        end
        8'b00??_?110: begin                                                                            // MVI
            if (q_byte[5:3] == 3'd6) begin t_cls = K_MOVMI; t_op = 8'hC6; t_mrm = 8'b00_000_111; end
            else begin t_cls = K_MOVI8; t_op = {5'b10110, m8(q_byte[5:3])}; end
        end
        8'b000?_?111: begin t_cls = K_SHIFT; t_op = 8'hD0; t_mrm = {3'b110, q_byte[4:3], 3'b000}; end    // RLC RRC RAL RAR
        8'h27:        begin t_cls = K_BCD; t_op = 8'h27; t_daa = 1'b1; end
        8'h2F:        begin t_cls = K_GRP3; t_op = 8'hF6; t_mrm = 8'b11_010_000; end                     // CMA
        8'h37:        begin t_cls = K_FLAG; t_op = 8'hF9; end                                          // STC
        8'h3F:        begin t_cls = K_FLAG; t_op = 8'hF5; end                                          // CMC
        8'hC9, 8'hD9: begin t_cls = K_RET; t_op = 8'hC3; t_st = 1'b1; end
        8'b11??_?000: begin t_cls = K_RET; t_op = 8'hC3; t_st = 1'b1; t_cc = 1'b1; end                   // Rcc
        8'hE9:        begin t_cls = K_INCRM; t_op = 8'hFF; t_mrm = 8'b11_100_011; end                    // PCHL
        8'hF9:        begin t_cls = K_MOVRM; t_op = 8'h8B; t_mrm = 8'b11_101_011; end                    // SPHL
        8'b11??_0001: begin t_cls = K_POPR; t_st = 1'b1; t_psw = q_byte[5:4] == 2'd3;
                            t_op = {5'b01011, t_psw ? 3'd0 : p16(q_byte[5:4])}; end
        8'b11??_0101: begin t_cls = K_PUSHR; t_st = 1'b1; t_psw = q_byte[5:4] == 2'd3;
                            t_op = {5'b01010, t_psw ? 3'd0 : p16(q_byte[5:4])}; end
        8'hC3, 8'hCB: begin t_cls = K_JMPN; t_op = 8'hE9; t_abs = 1'b1; end                            // JMP
        8'b11??_?010: begin t_cls = K_JMPN; t_op = 8'hE9; t_abs = 1'b1; t_cc = 1'b1; end                 // Jcc
        8'hD3:        begin t_cls = K_IO; t_op = 8'hE6; end                                            // OUT
        8'hDB:        begin t_cls = K_IO; t_op = 8'hE4; end                                            // IN
        8'hE3:        begin t_cls = K_XCHG; t_op = 8'h87; t_mrm = 8'b00_011_111; t_eas = 2'd3; end        // XTHL
        8'hEB:        begin t_cls = K_XCHG; t_op = 8'h87; t_mrm = 8'b11_010_011; end                     // XCHG
        8'hF3:        begin t_cls = K_FLAG; t_op = 8'hFA; end                                          // DI
        8'hFB:        begin t_cls = K_FLAG; t_op = 8'hFB; end                                          // EI
        8'hED:        t_cls = K_X0F;                                                                   // CALLN / RETEM escape
        8'hCD, 8'hDD, 8'hFD: begin t_cls = K_CALLN; t_op = 8'hE8; t_abs = 1'b1; t_st = 1'b1; end        // CALL
        8'b11??_?100: begin t_cls = K_CALLN; t_op = 8'hE8; t_abs = 1'b1; t_st = 1'b1; t_cc = 1'b1; end   // Ccc
        8'b11??_?111: begin t_cls = K_INCRM; t_op = 8'hFF; t_mrm = 8'b11_010_000; t_abs = 1'b1; t_st = 1'b1; t_rst = 1'b1; end  // RST
        default: ;                                                                                     // NOP
    endcase
end
wire        e8n    = E8 & ~md;            // the head byte is an 8080 opcode
wire  [5:0] hcls_e = e8n ? t_cls : hcls;
wire        e8m    = E8 & e8;             // an 8080 instruction is being decoded / executed
wire        e8h    = E8 & e_hm;
logic [15:0] imm, disp, mem, tmp, tmp2;
logic        ovr_v, rep_v, rep_z;
logic        rep_c;                     // NEC: REPC / REPNC (CMPS / SCAS test CF instead of ZF)
logic  [1:0] ovr_s;
logic        ismem, commit;
logic        nmi_q, nmi_pend;           // NMI edge latch
logic        xint;                      // interrupt sequence entered without an INT instruction
logic        xinta;                     // ... for INTR: run the INTA pair first
logic        brk, brk_wait;             // REP iteration / WAIT test interrupted
logic        tf_s;                      // TF at the start of the instruction (single-step trap at its end)
logic        lock_v;
logic [15:0] ret_ip, ip_pfx;
// registered write-back controls (decided one clock before they are applied)
logic  [7:0] wb_lo, wb_hi;              // port 1 byte-lane enables per register
logic        wb_bh;                     // byte value goes to the high lane
logic        wb_ralu, wb_rmem, wb_rimm, wb_rtmp, wb_rsh, wb_rx, wbf_sh, wb_rrm, wb_rreg, wb_rnot, wb_rbcd, wbf_bcd;
logic        wbf_tst;                   // NEC TEST r, r: flags from the operands registered in the decode clock
logic        wbf_cmp;                   // NEC CMPS: flags from the operands registered with the last read
logic        wbf_e8, wbf_cy, wbf_m8, wb_rmh;   // 8080: V kept; DAD CY only; POP PSW flags / A from the popped word
logic  [7:0] wb_f8;
logic [15:0] sho, reo, shi;             // r/m and reg operands as decoded; shifter operand (one clock behind)
logic [15:0] wb_x;
logic        wb2_ax, wb2_dx;
logic [15:0] wb2_x;
logic  [3:0] wbs_en;
logic        wbs_mem, wbs_tmp2;
logic [15:0] wbs_x;
logic        wbf_en, wbf_alu, wbf_mem, wbf_kc;
logic  [8:0] wbf_x;
logic        wsi_en, wdi_en, wcx_en;
logic        c_n, ci_x, ci_m, c_t;      // the committing instruction allows NMI / INTR (IF set, or IF from memory) / TF
logic        wbv1, wbv2, fw_en, fti_clr;
logic        u_loop;                    // step micro-op: shift loop (declared here for the shifter)
logic  [8:0] fw_v;
wire         wb_on = wbv1 | wbv2;
logic [15:0] wsi_v, wdi_v, wcx_v;
logic [15:0] md_a, md_b, md_d;          // MUL / DIV: high / remainder, low / quotient, operand
logic        md_neg, md_rneg, md_err;   // negate product / quotient, negate remainder, divide error
logic  [7:0] wcnt;
logic  [4:0] md_f;                      // DIV: S P A O Z of the last subtraction done in the loop
logic        md_first, md_qmsb, md_fitq; // first wait clock; quotient magnitude MSB; high half redundant
logic  [5:0] md_fl;                     // O S Z A P C for the write-back, registered while waiting
logic  [7:0] lc;
logic [15:0] ip_first;

logic       w;                          // word operation, registered with op
wire        d    = op[1];
wire        sh_var = op[1] | kk[K_SHIFTI];  // shift by CL, or (NEC C0 / C1) by an immediate
wire        k_sh   = k1[K_SHIFT] | kk[K_SHIFTI];
wire  [1:0] mod  = mrm[7:6];
wire  [2:0] reg_ = mrm[5:3];
wire  [2:0] rm   = mrm[2:0];

wire [15:0] reg_lo  = r[{1'b0, reg_[1:0]}];
wire [15:0] rm_lo   = r[{1'b0, rm[1:0]}];
wire [15:0] reg_val = w ? r[reg_] : {8'd0, reg_[2] ? reg_lo[15:8] : reg_lo[7:0]};
wire [15:0] rm_val  = ismem ? (w ? mem : {8'd0, mem[7:0]}) : w ? r[rm] : {8'd0, rm[2] ? rm_lo[15:8] : rm_lo[7:0]};
wire        md_v    = E8 ? md : 1'b1;
wire        c80f    = e_cn[2] ? (e_cn[1] ? f_s : f_p) : (e_cn[1] ? f_c : f_z);   // 8080 condition flag (P M / PO PE / C / Z)
wire [15:0] flags   = {md_v, 3'h7, f_o, f_d, f_i, f_t, f_s, f_z, 1'b0, f_a, 1'b0, f_p, 1'b1, f_c};
wire [7:0]  mb      = e8h ? e_mrm : q_byte;              // S_DEC: ModRM (8080: preset, no queue byte)
wire [7:0]  mrm_e   = (st == S_DEC) ? mb : mrm;          // ModRM as decoded (the queue byte in the decode clock)
wire        mav     = e8h | q_avail;
wire [2:0]  reg_e   = mrm_e[5:3];
wire [2:0]  rm_e    = mrm_e[2:0];
wire        ismem_e = (st == S_DEC) ? 1'b0 : ismem;
wire [15:0] rege_lo = r[{1'b0, reg_e[1:0]}];
wire [15:0] rme_lo  = r[{1'b0, rm_e[1:0]}];
wire [15:0] reg_val_e = w ? r[reg_e] : {8'd0, reg_e[2] ? rege_lo[15:8] : rege_lo[7:0]};
wire [15:0] rm_val_e  = ismem_e ? (w ? mem : {8'd0, mem[7:0]}) : w ? r[rm_e] : {8'd0, rm_e[2] ? rme_lo[15:8] : rme_lo[7:0]};
wire [15:0] sp_dn   = r[4] - 16'd2;
logic        wsp_en, wspc_en;
logic        wbp_en;                    // 8080 stack step: the update goes to BP
logic [15:0] wsp_v, wspc_v;
wire [15:0] sp_f    = wsp_en ? wsp_v : (E8 & e_st) ? r[5] : r[4];  // SP (8080: BP) with a pending stack-step update
wire [15:0] sp_up   = r[4] + 16'd2;
wire [15:0] cx_dec  = r[1] - 16'd1;
wire [15:0] jtarget = ip + imm;
wire  [7:0] al      = r[0][7:0];
wire  [7:0] ah      = r[0][15:8];
wire [15:0] str_d   = f_d ? (w ? 16'hFFFE : 16'hFFFF) : (w ? 16'd2 : 16'd1);

// effective address
logic [15:0] ea_base, ea_d, ea;
// the bus address uses the EA as registered in S_EA, in two stages (base + index, then + displacement); S_EA lasts
// at least two clocks after the displacement is complete
logic [15:0] ebq, eaq, xlq, spq;       // xlq: BX + AL (XLAT reads at its step 4); spq: SP - 2, registered
logic  [1:0] seg_def;
always_comb begin
    case (rm)
        3'd0: ea_base = r[3] + r[6];
        3'd1: ea_base = r[3] + r[7];
        3'd2: ea_base = r[5] + r[6];
        3'd3: ea_base = r[5] + r[7];
        3'd4: ea_base = r[6];
        3'd5: ea_base = r[7];
        3'd6: ea_base = (mod == 2'd0) ? 16'd0 : r[5];
        default: ea_base = r[3];
    endcase
    case (mod)
        2'd0:    ea_d = (rm == 3'd6) ? disp : 16'd0;
        2'd1:    ea_d = {{8{disp[7]}}, disp[7:0]};
        default: ea_d = disp;
    endcase
    ea = ea_base + ea_d;
    seg_def = ((rm == 3'd2) | (rm == 3'd3) | ((rm == 3'd6) & (mod != 2'd0))) ? 2'd2 : 2'd3;
end
wire [15:0] ea80 = e_eas[1] ? (e_eas[0] ? r[5] : r[2]) : r[1];   // 8080 LDAX / STAX (BC, DE), XTHL (SP)
wire [1:0] seg_rm = ovr_v ? ovr_s : seg_def;
wire [1:0] seg_ds = ovr_v ? ovr_s : 2'd3;


// conditions
logic cond;
always_comb begin
    case (op[3:1])
        3'd0: cond = f_o;
        3'd1: cond = f_c;
        3'd2: cond = f_z;
        3'd3: cond = f_c | f_z;
        3'd4: cond = f_s;
        3'd5: cond = f_p;
        3'd6: cond = f_s ^ f_o;
        default: cond = f_z | (f_s ^ f_o);
    endcase
    cond = cond ^ op[0];
end
logic lcond;
always_comb begin
    case (op[1:0])
        2'd0: lcond = (r[1] != 16'd1) & ~f_z;
        2'd1: lcond = (r[1] != 16'd1) & f_z;
        2'd2: lcond = r[1] != 16'd1;
        default: lcond = r[1] == 16'd0;
    endcase
end

wire irq_any = nmi_pend | (intr & f_i);

// BCD adjust (DAA DAS AAA AAS)
logic [15:0] bcd_v;
logic        bcd_c, bcd_a, bcd_o, bcd_adj;
logic  [8:0] bcd_t;
always_comb begin
    bcd_v = r[0];
    bcd_c = f_c;
    bcd_a = f_a;
    bcd_o = 1'b0;
    bcd_t = {1'b0, al};
    bcd_adj = (al[3:0] > 4'd9) | f_a;
    case (op[4:3])
        2'd0: begin                                     // DAA
            if (bcd_adj) bcd_t = {1'b0, al} + 9'd6;
            bcd_a = bcd_adj;
            bcd_c = f_c | (al > (f_a ? 8'h9F : 8'h99));
            if (bcd_c) bcd_t = bcd_t + 9'h60;
            bcd_v[7:0] = bcd_t[7:0];
            bcd_o = ~al[7] & bcd_t[7];
        end
        2'd1: begin                                     // DAS
            if (bcd_adj) bcd_t = {1'b0, al} - 9'd6;
            bcd_a = bcd_adj;
            bcd_c = f_c | (al > (f_a ? 8'h9F : 8'h99));
            if (bcd_c) bcd_t = bcd_t - 9'h60;
            bcd_v[7:0] = bcd_t[7:0];
            bcd_o = al[7] & ~bcd_t[7];
        end
        2'd2: begin                                     // AAA
            if (bcd_adj) begin bcd_t = {1'b0, al} + 9'd6; bcd_v[15:8] = ah + 8'd1; end
            bcd_a = bcd_adj; bcd_c = bcd_adj;
            bcd_v[7:0] = {4'd0, bcd_t[3:0]};
            bcd_o = ~al[7] & bcd_t[7];
        end
        default: begin                                  // AAS
            if (bcd_adj) begin bcd_t = {1'b0, al} - 9'd6; bcd_v[15:8] = ah - 8'd1; end
            bcd_a = bcd_adj; bcd_c = bcd_adj;
            bcd_v[7:0] = {4'd0, bcd_t[3:0]};
            bcd_o = al[7] & ~bcd_t[7];
        end
    endcase
    if (E8 & e_daa) begin                               // 8080 DAA (ALP 3-18): one correction from A, AC, CY
        bcd_c = f_c | (al[7:4] > 4'd9) | ((al[7:4] >= 4'd9) & (al[3:0] > 4'd9));
        bcd_t = {1'b0, al} + {1'b0, bcd_c, bcd_c, 2'b00, bcd_adj, bcd_adj, 1'b0};
        bcd_a = al[3:0] > 4'd9;
        bcd_v[7:0] = bcd_t[7:0];
        bcd_o = f_o;
    end
end
wire [7:0] bcd_f8 = op[4] ? bcd_t[7:0] : bcd_v[7:0];

// shift / rotate by one (D0-D3); D2 / D3 iterate on tmp
logic [15:0] sh_in, sh_r;
logic        sh_c, sh_o, sh_im, sh_rm, sh_rm1, sh_rot;
wire         sh_cin = (NEC & u_loop & fw_en) ? fw_v[0] : f_c;   // NEC RCL / RCR: the previous clock's carry
always_comb begin
    sh_in = (NEC & u_loop) ? tmp : shi;          // NEC: one bit per clock straight from tmp
    sh_im = w ? sh_in[15] : sh_in[7];
    sh_c  = sh_in[0];
    case (reg_)
        3'd0: begin sh_r = w ? {sh_in[14:0], sh_in[15]} : {8'd0, sh_in[6:0], sh_in[7]}; sh_c = sh_im; end
        3'd1: sh_r = w ? {sh_in[0], sh_in[15:1]} : {8'd0, sh_in[0], sh_in[7:1]};
        3'd2: begin sh_r = w ? {sh_in[14:0], sh_cin} : {8'd0, sh_in[6:0], sh_cin}; sh_c = sh_im; end
        3'd3: sh_r = w ? {sh_cin, sh_in[15:1]} : {8'd0, sh_cin, sh_in[7:1]};
        3'd4: begin sh_r = {sh_in[14:0], 1'b0}; sh_c = sh_im; end
        3'd5: sh_r = w ? {1'b0, sh_in[15:1]} : {8'd0, 1'b0, sh_in[7:1]};
        3'd6: if (NEC) begin sh_r = {sh_in[14:0], 1'b0}; sh_c = sh_im; end
              else begin sh_r = 16'hFFFF; sh_c = 1'b0; end
        default: sh_r = w ? {sh_in[15], sh_in[15:1]} : {8'd0, sh_in[7], sh_in[7:1]};
    endcase
    sh_rm  = w ? sh_r[15] : sh_r[7];
    sh_rm1 = w ? sh_r[14] : sh_r[6];
    case (reg_)
        3'd0, 3'd2, 3'd4: sh_o = sh_im ^ sh_rm;
        3'd6:             sh_o = NEC & (sh_im ^ sh_rm);
        3'd1, 3'd3:       sh_o = sh_rm ^ sh_rm1;
        3'd5:             sh_o = sh_im;
        default:          sh_o = 1'b0;
    endcase
    sh_rot = ~reg_[2];
end
wire [15:0] sh_v  = w ? sh_r : {8'd0, sh_r[7:0]};
wire  [8:0] sh_fl = sh_rot ? {sh_o, f_d, f_i, f_t, f_s, f_z, f_a, f_p, sh_c}
                           : {sh_o, f_d, f_i, f_t, sh_rm, w ? (sh_r == 16'd0) : (sh_r[7:0] == 8'd0),
                              ~NEC & (reg_ == 3'd4) & sh_r[4], ~^sh_r[7:0], sh_c};

// MUL / IMUL / DIV / IDIV / AAM / AAD: one bit per clock on one shared adder, then wait out the 8088's clock count
// (fitted to the hardware traces: MUL base + popcount(multiplier) + 1 if the high half is redundant; DIV base + 1 per
// quotient 1 bit not forced by a carry, the last bit +3 / +2)
wire        md_aam  = k1[K_AAM];
wire        md_aad  = k1[K_AAD];
logic       md_w, md_div, md_sgn;      // registered from the class and the ModRM as decoded (valid from S_EX on)
wire [15:0] md_acc  = kk[K_IMULI] ? imm : md_w ? r[0] : {{8{al[7]}}, al};
wire [15:0] md_src  = md_aam | md_aad ? {8'd0, imm[7:0]} : md_w ? rm_val : {{8{rm_val[7]}}, rm_val[7:0]};
wire        md_sa   = md_sgn & (md_div ? (md_w ? r[2][15] : ah[7]) : md_acc[15]);
wire        md_ss   = md_sgn & md_src[15];
wire [31:0] md_n    = md_w ? {r[2], r[0]} : {16'd0, r[0]};
wire [31:0] md_nneg = 32'd0 - md_n;
wire [31:0] md_nm   = md_sa ? (md_w ? md_nneg : {16'd0, md_nneg[15:0]}) : md_n;
wire [15:0] md_am   = md_sa ? 16'd0 - md_acc : md_acc;
wire [15:0] md_sm0  = md_ss ? 16'd0 - md_src : md_src;
wire [15:0] md_sm   = md_w ? md_sm0 : {8'd0, md_sm0[7:0]};
wire [15:0] md_nh   = md_aam ? 16'd0 : md_w ? md_nm[31:16] : {8'd0, md_nm[15:8]};
wire [16:0] md_pd   = {1'b0, md_a} - {1'b0, md_d};      // pre-check subtraction; its flags stay on a divide error
wire        md_pre  = ~md_pd[16];                       // quotient does not fit: divide error before the loop
wire  [8:0] md_pfl  = {md_w ? ((md_a[15] ^ md_d[15]) & (md_a[15] ^ md_pd[15])) : ((md_a[7] ^ md_d[7]) & (md_a[7] ^ md_pd[7])),
                       f_d, f_i, f_t, md_w ? md_pd[15] : md_pd[7], md_w ? (md_pd[15:0] == 16'd0) : (md_pd[7:0] == 8'd0),
                       md_a[4] ^ md_d[4] ^ md_pd[4], ~^md_pd[7:0], md_pd[16]};
// shared adder: MUL adds the multiplicand when the multiplier bit is 1, DIV subtracts the divisor from the shifted rem
wire [16:0] md_rs   = md_w ? {md_a, md_b[15]} : {8'd0, md_a[7:0], md_b[7]};
wire [16:0] md_opa  = md_div ? md_rs : {1'b0, md_w ? md_a : {8'd0, md_a[7:0]}};
wire [16:0] md_opb  = md_div ? {1'b0, md_d} : (md_b[0] ? {1'b0, md_d} : 17'd0);
wire [17:0] md_sum  = {1'b0, md_opa} + {1'b0, md_opb ^ {17{md_div}}} + {17'd0, md_div};
wire        md_top  = md_w ? md_a[15] : md_a[7];
wire        md_qb   = md_sum[17];                       // no borrow
wire        md_last = lc == 8'd1;
wire        md_dsf  = md_w ? md_sum[15] : md_sum[7];
wire        md_dof  = md_w ? ((md_rs[15] ^ md_d[15]) & (md_rs[15] ^ md_sum[15]))
                           : ((md_rs[7] ^ md_d[7]) & (md_rs[7] ^ md_sum[7]));
// results
wire [31:0] md_p    = md_w ? {md_a, md_b} : {16'd0, md_a[7:0], md_b[7:0]};
wire [31:0] md_pn   = 32'd0 - md_p;
wire [31:0] md_ps   = md_neg ? (md_w ? md_pn : {16'd0, md_pn[15:0]}) : md_p;
wire [15:0] md_hi   = md_w ? md_ps[31:16] : {8'd0, md_ps[15:8]};
wire [15:0] md_lo   = md_w ? md_ps[15:0] : {8'd0, md_ps[7:0]};
wire        md_fits = md_sgn ? (md_w ? (md_hi == {16{md_lo[15]}}) : (md_hi[7:0] == {8{md_lo[7]}})) : (md_hi == 16'd0);
wire [15:0] md_q0   = md_w ? md_b : {8'd0, md_b[7:0]};
wire        md_qmb  = md_w ? md_b[15] : md_b[7];             // |quotient| MSB (NEC IDIV flags)
wire [15:0] md_qn   = 16'd0 - md_q0;
wire [15:0] md_q    = md_neg ? (md_w ? md_qn : {8'd0, md_qn[7:0]}) : md_q0;
wire [15:0] md_r0   = md_w ? md_a : {8'd0, md_a[7:0]};
wire [15:0] md_rn   = 16'd0 - md_r0;
wire [15:0] md_rm   = md_rneg ? (md_w ? md_rn : {8'd0, md_rn[7:0]}) : md_r0;
wire        md_qovf = md_sgn & (md_w ? md_q0[15] : md_q0[7]);  // |quotient| > 7F(FF): IDIV error after the loop
wire  [8:0] md_aal  = {1'b0, md_b[7:0]} + {1'b0, al};    // AAD: AL + AH * imm
wire  [7:0] ah10    = {ah[4:0], 3'd0} + {ah[6:0], 1'b0};  // NEC AAD: AH * 10 (base fixed)
wire [15:0] md_rh   = md_w ? md_a : {8'd0, md_a[7:0]};   // results after u_mdp: high / remainder
wire [15:0] md_rl   = md_w ? md_b : {8'd0, md_b[7:0]};   // low / quotient
wire        md_rfit = md_sgn ? (md_w ? (md_rh == {16{md_rl[15]}}) : (md_rh[7:0] == {8{md_rl[7]}})) : (md_rh == 16'd0);
wire [15:0] md_ix   = md_rh + {15'd0, md_w ? md_rl[15] : md_rl[7]};  // IMUL flags: high half + sign of the low half
wire        md_ixz  = md_w ? (md_ix == 16'd0) : (md_ix[7:0] == 8'd0);
logic [5:0] md_flc;                                     // O S Z A P C of the result
always_comb begin
    if (md_aad) md_flc = {(~md_b[7] ^ al[7]) & (md_aal[7] ^ al[7]), md_aal[7], md_aal[7:0] == 8'd0,
                          md_b[4] ^ al[4] ^ md_aal[4], ~^md_aal[7:0], md_aal[8]};
    else if (md_aam) md_flc = {1'b0, md_a[7], md_a[7:0] == 8'd0, 1'b0, ~^md_a[7:0], 1'b0};
    // V20: DIV keeps the pre-check (high - divisor) flags; IDIV the flags of a test of |quotient|; IMUL those of low << 1
    else if (md_div & NEC) md_flc = md_sgn ? {1'b0, md_f[4], md_f[0], 1'b0, md_f[3], 1'b0}
                                           : {md_f[1], md_f[4], md_f[0], md_f[2], md_f[3], 1'b1};
    else if (md_div) md_flc = {md_f[1] & ~md_sgn, md_f[4], md_f[0], md_f[2], md_f[3], md_sgn ^ ~md_qmsb};
    else if (md_sgn & NEC) md_flc = {~md_rfit, md_w ? md_rl[14] : md_rl[6], md_w ? (md_rl[14:0] == 15'd0) : (md_rl[6:0] == 7'd0),
                                     md_rl[3], ~^md_rl[6:0], ~md_rfit};
    else if (md_sgn) md_flc = {~md_rfit, md_w ? md_ix[15] : md_ix[7], NEC ? (md_rl == 16'd0) : md_ixz, md_rh[4] ^ md_ix[4],
                               ~^md_ix[7:0], ~md_rfit};
    else if (NEC) md_flc = {~md_rfit, f_s, f_z, f_a, f_p, ~md_rfit};
    else md_flc = {~md_rfit, md_w ? md_rh[15] : md_rh[7], md_rh == 16'd0, 1'b0, ~^md_rh[7:0], ~md_rfit};
end
logic [7:0] md_base, md_ebase;
logic [1:0] wq;
logic       md_ssq, md_mnq;             // source sign, most negative source (registered in the setup step)
wire        md_mneg = md_sgn & ~md_sa & (md_w ? (md_src == 16'h8000) : (md_src[7:0] == 8'h80));  // most negative source
always_comb begin
    // clocks still to wait after the loop (8088 total minus the clocks the sequence itself takes)
    case ({md_aam, md_aad, md_div, md_w, md_sgn, md_rneg, md_ssq})
        7'b1010000: md_base = 8'd62;                     // AAM
        7'b0100000: md_base = 8'd44;                     // AAD
        7'b0010000: md_base = 8'd66;                     // DIV 8
        7'b0010100: md_base = 8'd87;                     // IDIV 8 by signs
        7'b0010101: md_base = 8'd86;
        7'b0010110: md_base = 8'd91;
        7'b0010111: md_base = 8'd90;
        7'b0011000: md_base = 8'd122;                    // DIV 16
        7'b0011100: md_base = 8'd143;                    // IDIV 16
        7'b0011101: md_base = 8'd142;
        7'b0011110: md_base = 8'd147;
        7'b0011111: md_base = 8'd146;
        7'b0001000: md_base = 8'd95;                     // MUL 16
        7'b0001100: md_base = 8'd105;                    // IMUL 16
        7'b0001101: md_base = 8'd116;
        7'b0001110: md_base = 8'd119;
        7'b0001111: md_base = 8'd106;
        7'b0000100: md_base = 8'd65;                     // IMUL 8
        7'b0000101: md_base = 8'd76;
        7'b0000110: md_base = 8'd79;
        7'b0000111: md_base = 8'd66;
        default:    md_base = 8'd55;                     // MUL 8
    endcase
    // divide error found before the loop: clocks until the interrupt sequence's first vector read
    md_ebase = md_aam ? 8'd8 : ~md_sgn ? 8'd11 : (md_rneg ? (md_ssq ? 8'd24 : 8'd25) : (md_ssq ? 8'd20 : 8'd21));
    if (NEC) begin
        // V20: fixed counts (MUL / DIV by size, IMUL by operand signs, IDIV by dividend sign); AAD has no loop
        case ({md_aam, md_aad, md_div, md_w, md_sgn})
            5'b10100: md_base = 8'd0;                       // AAM
            5'b01000: md_base = 8'd2;                       // AAD
            5'b00100: md_base = 8'd8;                       // DIV 8
            5'b00110: md_base = 8'd6;                       // DIV 16
            5'b00101: md_base = md_rneg ? 8'd29 : 8'd26;    // IDIV 8
            5'b00111: md_base = md_rneg ? 8'd28 : 8'd25;    // IDIV 16
            5'b00010: md_base = 8'd9;                       // MUL 16
            5'b00001: md_base = (md_rneg ^ md_ssq) ? 8'd24 : 8'd20;   // IMUL 8
            5'b00011: md_base = (md_rneg ^ md_ssq) ? 8'd23 : 8'd19;   // IMUL 16
            default:  md_base = 8'd10;                      // MUL 8
        endcase
        md_ebase = ~md_sgn ? (md_w ? 8'd9 : 8'd10) : (md_rneg ? 8'd21 : 8'd18);
        if (kk[K_IMULI]) md_base = (md_rneg ^ md_ssq) ? 8'd20 : 8'd16;
    end
end

// step sequences
//   u_q: queue byte to u_qd; u_rd / u_wr: bus cycle (u_io I/O space, u_a address, u_wd data, u_r2 read into tmp2);
//   u_susp / u_corr / u_flush (u_far: CS from tmp2) jump steps; u_end: last step before the next opcode read
// the step's micro-operations are registered: decoded one clock early for the step that follows
logic       u_q, u_rd, u_wr, u_io, u_susp, u_corr, u_flush, u_far, u_r2, u_wb, u_byte, u_ld, u_dec;
logic       u_inta, u_halt, u_hlt, u_mds, u_mdc, u_mdi, u_mdp, u_mdw, u_cf, u_endr;
logic       u_qp;                       // NEC: a queue byte that arrived this clock delays the next step by one
logic       u_fw;                       // NEC: request may start at the T4 of the read just released
logic       u_fgo, u_efl;               // NEC: start the target fetch; flush now if the bus is idle
logic       u_wfl;                      // NEC: flush with this step's bus request (not in a T4: the clock after)
logic       u_pre;                      // NEC: the next step requests the bus (a 3-byte queue does not prefetch)
logic       u_qw;                       // NEC: pop the immediate (to tmp2 low) in the T1 of this step's bus cycle
logic       qw_t, qw_got;
logic       u_pp, u_pi, u_bx;           // NEC 0F 20-3B: pointer preset, pointer step, compute into tmp
logic [2:0] u_ws;                       // NEC 0F 20-3B: lc wait value selected by the step
logic [15:0] pd;                        // NEC: BCD-string destination / bit-field pointer
logic       c4, z4;                     // NEC: BCD-string carry, nonzero result seen
logic [3:0] bf_o;                       // NEC bit field: offset
logic [4:0] bf_l;                       // NEC bit field: length 1-16
logic       efl_d;                      // NEC: early flush done
localparam int ECW = E8 ? 12 : 11;      // end-condition width (8080 condition only with NEC8080)
logic [ECW-1:0] u_ec;                   // end condition evaluated in the step's own clock
localparam logic [11:0] EC_NONE = 12'd0, EC_NCOND = 12'd1, EC_NLCOND = 12'd2, EC_NMDERR = 12'd4, EC_NAX15 = 12'd8,
                        EC_NFC = 12'd16, EC_BCD = 12'd32, EC_NOF = 12'd64, EC_NTEST = 12'd128, EC_IRQ = 12'd256,
                        EC_CX0 = 12'd512, EC_ZX = 12'd1024, EC_NC80 = 12'd2048;     // one-hot
localparam logic [ECW-1:0] E_NONE = EC_NONE[ECW-1:0], E_NCOND = EC_NCOND[ECW-1:0], E_NLCOND = EC_NLCOND[ECW-1:0],
                           E_NMDERR = EC_NMDERR[ECW-1:0], E_NAX15 = EC_NAX15[ECW-1:0], E_NFC = EC_NFC[ECW-1:0],
                           E_BCD = EC_BCD[ECW-1:0], E_NOF = EC_NOF[ECW-1:0], E_NTEST = EC_NTEST[ECW-1:0],
                           E_IRQ = EC_IRQ[ECW-1:0], E_CX0 = EC_CX0[ECW-1:0], E_ZX = EC_ZX[ECW-1:0], E_NC80 = EC_NC80[ECW-1:0];
logic [2:0] u_qd;
logic [3:0] u_a;
logic [1:0] u_wd;
logic [31:0] s1a;                       // the step that follows this one, one-hot
logic       v_q, v_bus, v_susp, v_loop, v_mdi, v_mdw, v_pl;  // what the step waits for, one-hot
logic       u_jv;
wire        is_cmp  = k1[K_ALURM] ? ((op[5:3] == 3'd7) | op[7]) : k1[K_ALUIM] ? (reg_ == 3'd7) : 1'b0;
wire        imm16   = (op == 8'h81);
wire        push5   = op[0] & (reg_[2:1] == 2'b11);       // FE / FF group (K_INCRM only)
wire  [2:0] g5      = op[0] ? reg_ : 3'd0;
wire        sh_z    = (kk[K_SHIFTI] ? imm[7:0] : r[1][7:0]) == 8'd0;     // NEC: shift count 0
wire        str_last = r[1] == 16'd1;                                   // NEC REP: this element is the last
wire        str_zx   = ((rep_c ? f_c : f_z) ^ rep_z);                   // NEC REPE / REPNE / REPC / REPNC: stop
// ALU; its result is registered (alu_q) and written back from there one clock later. An immediate high byte read in
// the last step is forwarded from the queue.
wire [15:0] imm_f = ((st == S_EX) & u_q & (u_qd == Q_HI)) ? {q_byte, imm[7:0]} : imm;
logic  [3:0] aop;
logic  [3:0] aopq;                      // ALU operation, registered from the class and the ModRM as decoded
logic        g3t;                       // GRP3 TEST, likewise
logic [15:0] a0q;                       // AX one clock behind (AX is not written in the clock before an ALU step)
wire   [2:0] reg_q = mrm_e[5:3];
wire   [3:0] aop_e = (k1[K_ALURM] | k1[K_ALUAI]) ? (op[7] ? 4'd4 : {1'b0, op[5:3]}) : k1[K_ALUIM] ? {1'b0, reg_q} :
                     k1[K_INCRM] ? (reg_q[0] ? 4'd9 : 4'd8) : k1[K_STR] ? 4'd7 :
                     k1[K_GRP3] ? ((reg_q[2:1] == 2'd0) ? 4'd4 : 4'd5) : {1'b0, op[5:3]};
// operands from the registered decode-clock values (sho / reo); a memory operand straight from mem
wire  [15:0] rmo = ismem ? (w ? mem : {8'd0, mem[7:0]}) : sho;
// NEC 0F xx (op = second byte): TEST1 / CLR1 / SET1 / NOT1 (10-1F, bit CL or imm), ROL4 / ROR4 (28 / 2A)
wire         x0f_bit  = op[7:4] == 4'h1;
wire   [7:0] x0f_cnt  = op[3] ? imm[7:0] : r[1][7:0];
wire  [15:0] x0f_mask = w ? (16'd1 << x0f_cnt[3:0]) : (16'd1 << x0f_cnt[2:0]);
wire  [15:0] x0f_bval = (op[2:1] == 2'd1) ? (rmo & ~x0f_mask) : (op[2:1] == 2'd2) ? (rmo | x0f_mask) : (rmo ^ x0f_mask);
wire   [7:0] x0f_nr   = op[1] ? {al[3:0], rmo[7:4]} : {rmo[3:0], al[3:0]};
wire   [7:0] x0f_nal  = op[1] ? rmo[7:0] : {al[3:0], rmo[7:4]};   // AL is written after r/m (ROL4 / ROR4 AL)
// NEC ADD4S SUB4S CMP4S (0F 20 22 26): dst (tmp2) +/- src (mem) +/- carry, then decimal adjust; the high digit is
// adjusted when it exceeds 9 counting the low digit's decimal carry (not after a low-nibble carry, unlike DAA)
wire         x0f_4s  = (op[7:4] == 4'h2) & ~op[3];
wire         x0f_bf  = op[7:4] == 4'h3;
wire   [8:0] s4_r    = op[1] ? ({1'b0, tmp2[7:0]} - {1'b0, mem[7:0]} - {8'd0, c4}) : ({1'b0, tmp2[7:0]} + {1'b0, mem[7:0]} + {8'd0, c4});
wire   [4:0] s4_n    = op[1] ? ({1'b0, tmp2[3:0]} - {1'b0, mem[3:0]} - {4'd0, c4}) : ({1'b0, tmp2[3:0]} + {1'b0, mem[3:0]} + {4'd0, c4});
wire         s4_la   = s4_n[4] | (s4_r[3:0] > 4'd9);
wire         s4_ha   = s4_r[8] | (s4_r[7:0] > 8'h9F) | ((s4_r[7:0] > 8'h99) & ~s4_n[4]);
wire   [7:0] s4_adj  = {1'b0, s4_ha, s4_ha, 2'b00, s4_la, s4_la, 1'b0};
wire   [7:0] s4_v    = op[1] ? s4_r[7:0] - s4_adj : s4_r[7:0] + s4_adj;
// NEC INS / EXT (0F 31 33 39 3B): offset in the r/m byte register, length - 1 in the reg byte register or imm
wire  [15:0] bf_rml  = r[{1'b0, rm[1:0]}];
wire  [15:0] bf_rgl  = r[{1'b0, reg_[1:0]}];
wire   [3:0] bf_rm4  = rm[2] ? bf_rml[11:8] : bf_rml[3:0];
wire   [3:0] bf_rg4  = reg_[2] ? bf_rgl[11:8] : bf_rgl[3:0];
wire   [4:0] bf_no   = {1'b0, bf_o} + bf_l;
wire   [4:0] bfn_l   = {1'b0, op[3] ? imm[3:0] : bf_rg4} + 5'd1;     // next bf_l / bf_o: the step decode and the
wire   [4:0] bfn_no  = {1'b0, bf_rm4} + bfn_l;                        // commit use registered conditions
wire   [4:0] bfn_x   = bfn_no - {4'd0, op[1]};
wire   [7:0] bfn_fr  = 8'd15 - {3'd0, bfn_x};                         // flags: SUB 15, offset + length (INS) / - 1 (EXT)
logic        bf_lt, bf_gt, bf_o0, bf_l5, bf_c, bf_z, bf_p, s4_n0, s4_n1;
logic  [3:0] bf_n4;
always_ff @(posedge clk) if (ce) begin
    bf_lt <= ~bfn_no[4]; bf_gt <= bfn_no[4] & (bfn_no[3:0] != 4'd0); bf_n4 <= bfn_no[3:0];
    bf_o0 <= bf_rm4 == 4'd0; bf_l5 <= bfn_l > 5'd4;
    bf_c <= bfn_fr[7]; bf_z <= bfn_fr == 8'd0; bf_p <= ~^bfn_fr;
    s4_n0 <= tmp[15:8] == 8'd0; s4_n1 <= tmp[15:8] == 8'd1;
end
wire   [7:0] bf_nof  = {4'd0, bf_n4};
wire  [15:0] bf_lm   = ~(16'hFFFF << bf_l[3:0]) | {16{bf_l[4]}};
wire  [15:0] bf_ax   = {(rm == 3'd4) ? bf_nof : ah, (rm == 3'd0) ? bf_nof : al};   // INS: AW after the offset update
wire  [31:0] bf_fld  = {16'd0, bf_ax & bf_lm} << bf_o;
wire  [31:0] bf_msk  = {16'd0, bf_lm} << bf_o;
logic [31:0] bf_fq, bf_mq;                                          // INS field and mask, registered
always_ff @(posedge clk) if (ce) begin bf_fq <= bf_fld; bf_mq <= bf_msk; end
wire  [31:0] bf_src  = {tmp2, mem} >> bf_o;
wire  [15:0] bf_v    = op[1] ? (bf_src[15:0] & bf_lm) : u_r2 ? ((tmp2 & ~bf_mq[31:16]) | bf_fq[31:16]) :
                                                            ((mem & ~bf_mq[15:0]) | bf_fq[15:0]);
wire  [15:0] bf_p2   = (op[1] ? r[6] : r[7]) + 16'd2;
logic [15:0] bxv;                                                   // computed word / byte, registered
logic        bxc;
always_ff @(posedge clk) if (ce) begin bxv <= x0f_4s ? {8'd0, s4_v} : bf_v; bxc <= s4_ha; end
wire   [6:0] bf_g    = (bf_l < 5'd4) ? (7'd16 + {1'b0, bf_l, 1'b0}) : (7'd12 + {2'd0, bf_l} + {1'b0, bf_l, 1'b0});
wire   [4:0] bf_n16  = bf_no - 5'd16;
wire   [6:0] bf_g16  = (bf_n16 < 5'd4) ? (7'd16 + {1'b0, bf_n16, 1'b0}) : (7'd12 + {2'd0, bf_n16} + {1'b0, bf_n16, 1'b0});
wire  [15:0] x0f_val  = x0f_bit ? x0f_bval : (NEC & x0f_bf) ? (u_wb ? bf_p2 : {8'd0, bf_nof}) : {8'd0, x0f_nr};
logic [15:0] aa, ab;
logic [15:0] alu_r;
logic        alu_c, alu_p, alu_a, alu_z, alu_s, alu_o;
always_comb begin
    aop = aopq;
    aa  = rmo;
    ab  = reo;
    unique case (1'b1)
        k1[K_ALURM]: begin
            aa = d ? reo : rmo; ab = d ? rmo : reo;
        end
        k1[K_ALUAI]: begin
            aa = w ? a0q : {8'd0, a0q[7:0]}; ab = w ? imm_f : {8'd0, imm[7:0]};
        end
        k1[K_ALUIM]: begin ab = w ? imm_f : {8'd0, imm[7:0]}; end
        k1[K_INCR]:  begin aop = op[3] ? 4'd9 : 4'd8; aa = r[op[2:0]]; ab = 16'd1; end
        k1[K_INCRM]: ab = 16'd1;
        k1[K_STR]:   begin
            aa  = (op[3:1] == 3'd3) ? (w ? mem : {8'd0, mem[7:0]}) : (w ? a0q : {8'd0, a0q[7:0]});
            ab  = (op[3:1] == 3'd3) ? (w ? tmp2 : {8'd0, tmp2[7:0]}) : (w ? mem : {8'd0, mem[7:0]});
        end
        k1[K_GRP3]:  if (g3t) begin ab = w ? imm_f : {8'd0, imm[7:0]}; end
                 else begin aa = 16'd0; ab = rmo; end
        kk[K_X0F]:   begin aop = 4'd4; ab = x0f_mask; end           // TEST1: flags of r/m AND mask
        default: ;
    endcase
end
x86sv_alu alu (.op(aop), .w(w), .a(aa), .b(ab), .cin(f_c), .r(alu_r), .cf(alu_c), .pf(alu_p), .af(alu_a),
               .zf(alu_z), .sf(alu_s), .of(alu_o));
// 8080 AC (ALP 1-12, chapter 3): ADD / INR carry out of bit 3; SUB / SBB / CMP / DCR the same of the complement
// addition (= no borrow); ANA the OR of the operands' bit 3; XRA / ORA 0
logic        ac3q;                      // 8080 ANA: OR of the operands' bit 3, registered with the result
logic  [1:0] wbf_acm;
logic [15:0] alu_q;
logic        alu_oq, alu_aq, alu_cq;     // O A C of alu_q; S Z P are derived from alu_q where used
wire         alu_a8 = (E8 & wbf_acm[1]) ? (~wbf_acm[0] & ac3q) : (alu_aq ^ (E8 & wbf_acm[0]));
wire  [5:0] alu_fq = {alu_oq, w ? alu_q[15] : alu_q[7], w ? (alu_q == 16'd0) : (alu_q[7:0] == 8'd0), alu_aq,
                      ~^alu_q[7:0], alu_cq};   // O S Z A P C

wire empty_body = k1[K_FLAG] | k1[K_INCR] | k1[K_NONE] | (op == 8'h98) | (op == 8'h9F) |
                  (E8 & k1[K_RET] & e_cc & (c80f ^ e_cn[0])) |     // 8080 Rcc not taken: decided in S_DEC
                  (((k1[K_MOVRM] & ~NEC) | k1[K_MOVSR] | k1[K_ESC] | (k_sh & ~sh_var & ~NEC) | (NEC & k1[K_ALURM] & op[7])) &
                   (mb[7:6] == 2'b11));
logic has_modrm;                        // registered with op
wire ea_two     = (ph == 2'd2) & (mod == 2'd2 | (mod == 2'd0 & rm == 3'd6));
logic nim;                              // NEC MOV r/m, imm: immediate high-byte slot after the EA
wire nea_imm    = k1[K_MOVMI];
wire nea_lv     = ((ph == 2'd0) & (cnt == 4'd1) & (mod == 2'd0) & (rm != 3'd6)) | ((ph == 2'd2) & (cnt == 4'd1) & (mod == 2'd1)) |
                  (ph == 2'd3);
wire nea_pop    = nim ? w : (((ph == 2'd1) & ((mod != 2'd1) | q_old)) | ((ph == 2'd2) & (mod != 2'd1) & (cnt == 4'd1) & q_old) |
                             (nea_imm & nea_lv));
// NEC LEA ends with its last address byte (no displacement: the first S_EA clock); the value takes the byte being popped
wire nlea_end   = NEC & k1[K_LEA] & (st == S_EA) & ((mod == 2'd0) & (rm != 3'd6) ? (ph == 2'd0) :
                  (((ph == 2'd1) & (mod == 2'd1) & q_old) | ((ph == 2'd2) & (mod != 2'd1) & (cnt == 4'd1) & q_old)));
wire [15:0] ea_df = (ph == 2'd1) ? {{8{q_byte[7]}}, q_byte} : (ph == 2'd2) ? {q_byte, disp[7:0]} : ea_d;
wire [15:0] ea_f  = ea_base + ea_df;

// NEC BOUND: register outside [lo, hi] (signed), registered (the check step comes two clocks after the second read)
logic bnd_out;
logic bnd_lo;                           // NEC: below the lower bound (INT 5 taken 3 clocks sooner than above the upper)
logic [15:0] spn_v;                     // NEC: SP - 2 with a pending stack-step update (back-to-back pushes)
always_ff @(posedge clk) if (ce) begin
    bnd_out <= ($signed(reg_val) < $signed(mem)) | ($signed(reg_val) > $signed(tmp2));
    bnd_lo  <= $signed(reg_val) < $signed(mem);
    spn_v <= sp_f - 16'd2;
end
logic c80q;                             // 8080 condition false, registered (flags and e_cn settle by S_DEC)
wire [11:0] ec_c = {E8 & c80q, ((NEC & rep_c) ? f_c : f_z) ^ rep_z, r[1] == 16'd0, irq_any, ~test_n, ~(kk[K_BOUND] ? bnd_out : f_o), bcd_adj, ~f_c, ~r[0][15], ~md_err, ~lcond, ~cond};
wire ec_hit = |(u_ec & ec_c[ECW-1:0]);
wire u_end  = u_endr | ec_hit;
// HALT released by NMI, or INT: V20 / V30 with IE 0 or 1 in native and 8080 mode (UM 8-2, 9-1); 8088 / 8086 only IF = 1
wire u_hold = u_hlt & ~(nmi_pend | (intr & (NEC | f_i)));
wire dly_on;                            // EXT: the step's micro-operations start after a pre-delay
wire u_done = ~dly_on & ((v_q & q_avail) | (v_bus & rel) | (v_susp & susp_ok) | (v_loop & (lc == 8'd0)) | (v_mdi & (md_err | md_last)) |
              (v_mdw & (wcnt == 8'd0)) | (v_pl & ~u_hold));


// bus request
wire        wd_d = u_wd == D_DEF;
wire        wd_alu = wd_d & ~(k1[K_MOVRM] | k1[K_MOVSR] | k1[K_MOVMI] | k1[K_MOVAM] | k1[K_IO] | k1[K_PUSHR] | k1[K_PUSHS] |
                              k1[K_POPM] | k1[K_XCHG] | k1[K_SHIFT] | k1[K_STR] | k1[K_GRP3] | k1[K_INCRM] |
                              kk[K_PUSHI] | kk[K_PUSHA] | kk[K_ENTER] | kk[K_SHIFTI] | kk[K_INSOUT] | kk[K_X0F]);
wire [15:0] wval = ({16{u_wd == D_FL}} & flags) | ({16{u_wd == D_CS}} & sr[1]) | ({16{u_wd == D_TMP}} & tmp) |
                   ({16{wd_d & (k1[K_MOVRM] | k1[K_XCHG])}} & reg_val) | ({16{wd_d & k1[K_MOVSR]}} & sr[reg_[1:0]]) |
                   ({16{wd_d & k1[K_MOVMI]}} & imm) |
                   ({16{wd_d & (k1[K_MOVAM] | k1[K_IO] | (k1[K_STR] & op[3]))}} & r[0]) |
                   ({16{wd_d & k1[K_PUSHR] & (op[2:0] == 3'd4)}} & sp_dn) |
                   ({16{wd_d & k1[K_PUSHR] & (op[2:0] != 3'd4) & ~(E8 & e_psw)}} & r[op[2:0]]) |
                   ({16{wd_d & k1[K_PUSHR] & E8 & e_psw}} & {al, flags[7:0]}) |    // 8080 PUSH PSW: A, S Z 0 AC 0 P 1 CY
                   ({16{wd_d & k1[K_PUSHS]}} & sr[op[4:3]]) | ({16{wd_d & kk[K_PUSHI]}} & imm) |
                   ({16{wd_d & kk[K_X0F]}} & x0f_val) |
                   ({16{wd_d & kk[K_PUSHA]}} & ((lc[2:0] == 3'd4) ? r[4] + 16'd8 : r[lc[2:0]])) |
                   ({16{wd_d & kk[K_ENTER] & ~u_r2}} & r[5]) | ({16{wd_d & (kk[K_INSOUT] | (kk[K_ENTER] & u_r2))}} & mem) | ({16{wd_d & (k1[K_POPM] | (k1[K_STR] & ~op[3]))}} & mem) |
                   ({16{wd_d & k1[K_GRP3] & (reg_ == 3'd2)}} & ~rm_val) |
                   ({16{wd_d & k_sh & sh_var}} & tmp) | ({16{wd_d & k_sh & ~sh_var}} & sh_v) |
                   ({16{wd_d & k1[K_INCRM] & push5 & ~ismem & (rm == 3'd4)}} & sp_dn) |
                   ({16{wd_d & k1[K_INCRM] & push5 & ~(~ismem & (rm == 3'd4))}} & rm_val) |
                   ({16{wd_alu | (wd_d & ((k1[K_GRP3] & (reg_ != 3'd2)) | (k1[K_INCRM] & ~push5)))}} & alu_q);
logic [15:0] aoff;
logic  [1:0] aseg;
logic        azero;
always_comb begin
    aseg  = seg_rm;
    azero = 1'b0;
    case (u_a)
        A_EA2:  aoff = eaq + 16'd2;
        A_STK:  begin aoff = u_wr ? ((kk[K_PUSHA] | kk[K_ENTER]) ? spn_v : spq) : NEC ? sp_f : r[4]; aseg = {1'b1, E8 & e_st}; end
        A_IMM:  begin aoff = imm; aseg = seg_ds; azero = u_io; end
        A_DX:   begin aoff = r[2]; azero = 1'b1; end
        A_XLAT: begin aoff = xlq; aseg = seg_ds; end
        A_VEC:  begin aoff = {6'd0, vec, 2'b00}; azero = 1'b1; end
        A_VEC2: begin aoff = {6'd0, vec, 2'b10}; azero = 1'b1; end
        A_SI:   begin aoff = r[6]; aseg = seg_ds; end
        A_DI:   begin aoff = r[7]; aseg = 2'd0; end
        A_BP:   if (NEC) begin aoff = r[5]; aseg = 2'd2; end else aoff = eaq;
        A_PD:   if (NEC) begin aoff = pd; aseg = (op[4] & op[1]) ? seg_ds : 2'd0; end else aoff = eaq;
        default: aoff = eaq;
    endcase
end
wire [1:0] seg_x = (azero | u_inta) ? 2'd1 : aseg;

assign req       = (st == S_EX) & ~dly_on & (u_rd | u_wr | (u_corr & ~NEC) | u_inta | u_halt);   // NEC: no IP-correction cycle
assign req_fast  = NEC & u_fw;
assign req_pre   = NEC & (st == S_EX) & u_pre;
assign req_type  = u_inta ? B_INTA : u_halt ? B_HALT : u_io ? (u_wr ? B_IOW : B_IOR) : u_wr ? B_MEMW : B_MEMR;
assign req_int   = u_corr & ~NEC;
assign req_word  = (w | u_inta | (u_a == A_STK) | (u_a == A_VEC) | (u_a == A_VEC2) | k1[K_POPM] | k1[K_ESC] |
                    (u_wd != D_DEF)) & ~u_byte;
assign req_sidx  = {seg_x[0], seg_x[1]};
assign req_segv  = (azero | u_inta) ? 16'd0 : sr[seg_x];
assign req_off   = u_inta ? 16'd0 : aoff;
assign req_wdata = wval;
assign req_corr  = xint ? ret_ip : ip;
assign susp      = (st == S_EX) & ~dly_on & u_susp;
wire   fl_nec    = (u_done & ((u_flush & ~efl_d) | (u_efl & bus_idle))) | (u_wfl & (~bus_t4 | u_fw) & ~efl_d);
assign flush     = (st == S_EX) & ~dly_on & (NEC ? fl_nec : u_flush);
assign fgo       = NEC & (st == S_EX) & u_fgo & u_done;
assign cs        = sr[1];
assign if_flag   = f_i;
assign lock      = lock_v;
assign emu       = E8 & ~md;
assign dbg_ip    = ip_first;
assign dbg_flags = flags;
`ifdef X86SV_TESTLOAD
assign dbg_mdwe  = E8 & mdwe;
`endif
assign dbg_r     = r;
assign dbg_s     = sr;

always_comb begin
    unique case (1'b1)
        k1[K_RET], k1[K_RETF], k1[K_IRET], k1[K_INT]: flush_ip = mem;
        k1[K_INCRM]: flush_ip = rm_val;
        k1[K_JMPF], k1[K_CALLF]: flush_ip = imm;
        default: flush_ip = jtarget;
    endcase
    if (E8 & e_abs) flush_ip = e_rst ? {10'd0, e_cn, 3'd0} : imm;   // 8080 JMP / CALL / RST: absolute target
end

// write-back, decoded in the clock an instruction (or a register-writing step) ends and applied from registers in
// the next clock: port 1 (any register, byte lanes), port 2 (AX / DX), segment, flags. Values already final in the
// deciding clock are computed then (cm_rv); values that arrive with that clock's edge are selected from their
// registers when applied (ALU result, memory word, immediate, tmp).
localparam logic [2:0] R_X = 3'd0, R_ALU = 3'd1, R_MEM = 3'd2, R_IMM = 3'd3, R_TMP = 3'd4, R_SH = 3'd5, R_RM = 3'd6, R_REG = 3'd7;
localparam logic [1:0] G_X = 2'd0, G_MEM = 2'd1, G_TMP2 = 2'd2;
localparam logic [1:0] F_X = 2'd0, F_ALU = 2'd1, F_MEM = 2'd2;
logic        cm_r, cm_rw, cm_s, cm_f, cm_sp, cm_d, cm_dx, cm_kc;
logic  [2:0] cm_rs;
logic  [1:0] cm_ss, cm_fs;
logic [15:0] cm_spv, cm_dv, cm_sv;
logic  [2:0] cm_ri;
logic  [1:0] cm_si;
logic [15:0] cm_rv;
logic  [8:0] cm_fv;                     // O D I T S Z A P C
wire   [8:0] fl9 = {f_o, f_d, f_i, f_t, f_s, f_z, f_a, f_p, f_c};
wire  [15:0] cm_rx = ({16{kk[K_X0F]}} & x0f_val) | ({16{kk[K_IMULI]}} & md_b) | ({16{kk[K_ENTER]}} & (r[5] - 16'd2)) |
                     ({16{k1[K_MOVSR]}} & sr[reg_e[1:0]]) | ({16{k1[K_XCHGA]}} & r[0]) | ({16{k1[K_LEA]}} & (NEC ? ea_f : ea)) |
                     ({16{k1[K_GRP3] & reg_[2]}} & (md_w ? md_b : {md_a[7:0], md_b[7:0]})) |
                     ({16{k1[K_AAM]}} & {md_b[7:0], md_a[7:0]}) | ({16{k1[K_AAD]}} & {8'd0, md_aal[7:0]}) |
                     ({16{k1[K_LOOP]}} & cx_dec) |
                     ({16{k1[K_MISC] & (op == 8'h98)}} & {{8{al[7]}}, al}) |
                     ({16{k1[K_MISC] & (op == 8'h9F)}} & {8'd0, flags[7:0]}) |
                     ({16{k1[K_MISC] & (op == 8'hD6)}} & {8'd0, {8{f_c}}});
always_comb begin
    cm_r = 1'b0; cm_rw = w; cm_ri = reg_e; cm_rs = R_ALU; cm_rv = 16'd0; cm_s = 1'b0; cm_si = reg_e[1:0];
    cm_ss = G_X; cm_sv = rm_val_e; cm_f = 1'b0; cm_fs = F_ALU; cm_kc = 1'b0; cm_fv = fl9; cm_sp = 1'b0;
    cm_spv = sp_f + imm; cm_d = 1'b0; cm_dx = 1'b1; cm_dv = 16'd0;
    unique case (1'b1)
        k1[K_MOVRM]:  begin cm_r = d | ~ismem_e; cm_ri = d ? reg_e : rm_e; cm_rs = d ? R_RM : R_REG; end
        k1[K_MOVSR]:  begin cm_s = d; cm_r = ~d & ~ismem_e; cm_ri = rm_e; cm_rs = R_X; cm_rv = sr[reg_e[1:0]]; end
        k1[K_MOVI8]:  begin cm_r = 1'b1; cm_ri = op[2:0]; cm_rs = R_IMM; end
        k1[K_MOVI16]: begin cm_r = 1'b1; cm_ri = op[2:0]; cm_rs = R_IMM; end
        k1[K_MOVMI]:  begin cm_r = ~ismem; cm_ri = rm; cm_rs = R_IMM; end
        k1[K_MOVAM]:  begin cm_r = ~d; cm_ri = 3'd0; cm_rs = R_MEM; end
        k1[K_ALURM]:  begin cm_r = ~is_cmp & (d | ~ismem); cm_ri = d ? reg_ : rm; cm_f = 1'b1; end
        k1[K_ALUAI]:  begin cm_r = (op[5:3] != 3'd7) & ~op[7]; cm_ri = 3'd0; cm_f = 1'b1; end
        k1[K_ALUIM]:  begin cm_r = ~is_cmp & ~ismem; cm_ri = rm; cm_f = 1'b1; end
        k1[K_INCR]:   begin cm_r = 1'b1; cm_ri = op[2:0]; cm_f = 1'b1; cm_kc = 1'b1; end
        k1[K_INCRM]:  if (g5[2:1] == 2'd0) begin cm_r = ~ismem; cm_ri = rm; cm_f = 1'b1; cm_kc = 1'b1; end
        k1[K_POPR]:   begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = op[2:0]; cm_rs = R_MEM; end
        k1[K_POPS]:   begin cm_s = 1'b1; cm_si = op[4:3]; cm_ss = G_MEM; end
        k1[K_POPM]:   begin cm_r = ~ismem; cm_rw = 1'b1; cm_ri = rm; cm_rs = R_MEM; end
        k1[K_RET]:    cm_sp = ~op[0];
        k1[K_RETF]:   cm_sp = ~op[0];
        k1[K_POPF]:   begin cm_f = 1'b1; cm_fs = F_MEM; end
        k1[K_IRET]:   begin cm_f = 1'b1; cm_fs = F_MEM; end
        k1[K_XCHG]:   if (u_wb | (NEC & (st == S_DEC))) begin       // V20 register form: first write decided in S_DEC
                      cm_r = 1'b1; cm_ri = (NEC & (st == S_DEC)) ? rm_e : rm; cm_rs = R_REG;
                  end else begin cm_r = 1'b1; cm_ri = reg_; cm_rs = (ismem | NEC) ? R_RM : R_TMP; end
        k1[K_XCHGA]:  begin cm_r = 1'b1; cm_ri = op[2:0]; cm_rs = R_X; cm_rv = r[0]; cm_d = 1'b1; cm_dx = 1'b0; cm_dv = r[op[2:0]]; end
        k1[K_LEA]:    begin cm_r = 1'b1; cm_rs = R_X; cm_rv = ea; end
        k1[K_STR]:    begin cm_r = (op[3:1] == 3'd6) & (~rep_v | u_dec); cm_ri = 3'd0; cm_rs = R_MEM;
                        cm_f = ((op[3:1] == 3'd3) | (op[3:1] == 3'd7)) & ~rep_v; end
        k1[K_GRP3]:   if (!reg_[2]) begin
                      cm_r = (reg_[2:1] == 2'd1) & ~ismem; cm_ri = rm; cm_rs = reg_[0] ? R_ALU : R_X;
                      cm_f = reg_[2:1] != 2'd1 || reg_[0];
                  end else begin
                      cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd0; cm_d = md_w; cm_dx = 1'b1; cm_f = 1'b1; cm_fs = F_X;
                      cm_rs = R_X; cm_rv = md_w ? md_b : {md_a[7:0], md_b[7:0]}; cm_dv = md_a;
                      cm_fv = {md_fl[5], f_d, f_i, f_t, md_fl[4:0]};
                  end
        k1[K_AAM]:    begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd0; cm_rs = R_X; cm_rv = {md_b[7:0], md_a[7:0]}; cm_f = 1'b1;
                        cm_fs = F_X; cm_fv = {md_fl[5], f_d, f_i, f_t, md_fl[4:0]}; end
        k1[K_AAD]:    begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd0; cm_rs = R_X; cm_rv = {8'd0, md_aal[7:0]}; cm_f = 1'b1;
                        cm_fs = F_X; cm_fv = {md_fl[5], f_d, f_i, f_t, md_fl[4:0]}; end
        k1[K_SHIFT]:  begin cm_r = ~ismem_e; cm_ri = rm_e; cm_rs = sh_var ? R_TMP : R_SH; cm_f = ~sh_var; cm_fs = F_X; end
        k1[K_LDS]:    begin cm_r = 1'b1; cm_rs = R_MEM; cm_s = 1'b1; cm_si = op[0] ? 2'd3 : 2'd0; cm_ss = G_TMP2; end
        k1[K_XLAT]:   begin cm_r = 1'b1; cm_rw = 1'b0; cm_ri = 3'd0; cm_rs = R_MEM; end
        kk[K_SHIFTI]: begin cm_r = ~ismem_e; cm_ri = rm_e; cm_rs = R_TMP; cm_f = 1'b0; cm_fs = F_X; end
        kk[K_X0F]:    if (x0f_bit & (op[2:1] == 2'd0)) cm_f = 1'b1;
                      else if (x0f_bit) begin cm_r = ~ismem; cm_ri = rm; cm_rs = R_X; end
                      else if (op[7:4] == 4'h2 && op[3]) begin
                          cm_r = ~ismem; cm_ri = rm; cm_rs = R_X; cm_d = 1'b1; cm_dx = 1'b0;
                          cm_dv = {(~ismem & (rm == 3'd4)) ? x0f_nr : ah, x0f_nal};
                      end else if (NEC & x0f_bf) begin
                          cm_r = 1'b1; cm_rs = R_X; cm_rw = u_wb; cm_ri = u_wb ? (op[1] ? 3'd6 : 3'd7) : rm;
                          cm_d = op[1] & ~u_wb; cm_dx = 1'b0; cm_dv = bxv;
                          cm_f = ~u_wb; cm_fs = F_X; cm_fv = {1'b0, f_d, f_i, f_t, bf_c, bf_z, 1'b0, bf_p, bf_c};
                      end else if (NEC & x0f_4s) begin
                          cm_f = 1'b1; cm_fs = F_X; cm_fv = {1'b0, f_d, f_i, f_t, c4, ~z4, c4, 1'b0, c4};
                      end
        kk[K_POPA]:   begin cm_r = lc[2:0] != 3'd4; cm_rw = 1'b1; cm_ri = lc[2:0]; cm_rs = R_MEM; end
        kk[K_IMULI]:  begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = reg_e; cm_rs = R_X; cm_rv = md_b; cm_f = 1'b1; cm_fs = F_X;
                        cm_fv = {md_fl[5], f_d, f_i, f_t, md_fl[4:0]}; end
        kk[K_ENTER]:  if (u_wb) begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd5; cm_rs = R_X; cm_rv = r[5] - 16'd2; end
                      else begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd5; cm_rs = R_TMP; cm_sp = 1'b1; cm_spv = sp_f - imm; end
        kk[K_LEAVE]:  begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd5; cm_rs = R_MEM; cm_sp = 1'b1; cm_spv = r[5] + 16'd2; end
        k1[K_IO]:     begin cm_r = ~op[1]; cm_ri = 3'd0; cm_rs = R_MEM; end
        k1[K_LOOP]:   begin cm_r = op[1:0] != 2'd3; cm_rw = 1'b1; cm_ri = 3'd1; cm_rs = R_X; cm_rv = cx_dec; end
        k1[K_BCD]:    begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd0; cm_rs = R_X; cm_f = 1'b1; cm_fs = F_X;
                        cm_fv = {bcd_o, f_d, f_i, f_t, 1'b0, 1'b0, bcd_a, 1'b0, bcd_c}; end
        k1[K_FLAG]:   begin
                      cm_f = 1'b1; cm_fs = F_X;
                      case (op[3:1])
                          3'b010:  cm_fv[0] = ~f_c;                        // F5 CMC
                          3'b100:  cm_fv[0] = op[0];                       // F8 / F9 CLC / STC
                          3'b101:  cm_fv[6] = op[0];                       // FA / FB CLI / STI
                          default: cm_fv[7] = op[0];                       // FC / FD CLD / STD
                      endcase
                  end
        k1[K_MISC]: case (op)
            8'h98:   begin cm_r = 1'b1; cm_rw = 1'b1; cm_ri = 3'd0; cm_rs = R_X; cm_rv = {{8{al[7]}}, al}; end
            8'h99:   begin cm_d = 1'b1; cm_dv = {16{r[0][15]}}; end
            8'h9E:   begin cm_f = 1'b1; cm_fs = F_X; cm_fv = {f_o, f_d, f_i, f_t, ah[7], ah[6], ah[4], ah[2], ah[0]}; end
            8'h9F:   begin cm_r = 1'b1; cm_rw = 1'b0; cm_ri = 3'd4; cm_rs = R_X; cm_rv = {8'd0, flags[7:0]}; end
            default: begin cm_r = 1'b1; cm_rw = 1'b0; cm_ri = 3'd0; cm_rs = R_X; cm_rv = {8'd0, {8{f_c}}}; end
        endcase
        default: ;
    endcase
    if (E8 & k1[K_INCR] & e_nf) cm_f = 1'b0;                     // 8080 INX / DCX: no flags
    if (E8 & k1[K_POPR] & e_psw) begin                          // 8080 POP PSW: A from the high byte, flags (wb_rmh, wbf_m8)
        cm_rw = 1'b0; cm_ri = 3'd0; cm_rs = R_X; cm_f = 1'b1; cm_fs = F_MEM;
    end
end

wire        fin  = ((st == S_DEC) & empty_body & (~has_modrm | q_avail)) | ((st == S_EX) & u_done & u_end) | nlea_end;
wire [15:0] wb_v = ({16{wb_rx}} & wb_x) | ({16{wb_ralu}} & alu_q) | ({16{wb_rmem}} & mem) | ({16{wb_rimm}} & imm) |
                   ({16{wb_rtmp}} & tmp) | ({16{wb_rsh}} & sh_v) | ({16{wb_rrm}} & sho) | ({16{wb_rreg}} & reo) |
                   ({16{wb_rnot}} & ~sho) | ({16{wb_rbcd}} & bcd_v) | ({16{E8 & wb_rmh}} & {8'd0, mem[15:8]});
wire [15:0] wbs_v = wbs_mem ? mem : wbs_tmp2 ? tmp2 : wbs_x;
wire [15:0] tst_v = sho & reo;
// NEC CMPS ends with its second read: compare the operands as they arrive registered (a dedicated subtractor)
logic [15:0] cmp_r;
logic        cmp_c, cmp_p, cmp_a, cmp_z, cmp_s, cmp_o;
generate if (NEC) begin : g_cmp
    x86sv_alu calu (.op(4'd7), .w(w), .a(w ? mem : {8'd0, mem[7:0]}), .b(w ? tmp2 : {8'd0, tmp2[7:0]}), .cin(1'b0),
                    .r(cmp_r), .cf(cmp_c), .pf(cmp_p), .af(cmp_a), .zf(cmp_z), .sf(cmp_s), .of(cmp_o));
end else begin : g_nocmp
    assign {cmp_r, cmp_c, cmp_p, cmp_a, cmp_z, cmp_s, cmp_o} = 22'd0;
end endgenerate
wire  [8:0] wbf_v = (NEC & wbf_cmp) ? {cmp_o, f_d, f_i, f_t, cmp_s, cmp_z, cmp_a, cmp_p, cmp_c} :
                    (NEC & wbf_tst) ? {1'b0, f_d, f_i, f_t, w ? tst_v[15] : tst_v[7], tst_v == 16'd0, 1'b0, ~^tst_v[7:0], 1'b0} :
                    wbf_sh ? sh_fl : wbf_bcd ? {wbf_x[8:5], wb_f8[7], wb_f8 == 8'd0, wbf_x[2], ~^wb_f8, wbf_x[0]} :
                    wbf_alu ? {alu_fq[5], f_d, f_i, f_t, alu_fq[4:3], alu_a8, alu_fq[1], wbf_kc ? f_c : alu_fq[0]} :
                    wbf_mem ? ((E8 & wbf_m8) ? {f_o, f_d, f_i, f_t, mem[7], mem[6], mem[4], mem[2], mem[0]} :
                                               {mem[11:6], mem[4], mem[2], mem[0]}) :
                    wbf_x;

// interrupt acceptance at the instruction boundary (the clock that applies the write-back), iAPX 86/88 User's
// Manual 210911 section 4.3: no interrupt after a prefix (never a boundary here) or after MOV / POP to a segment
// register; INTR also not after STI / IRET; NMI over INTR over single-step
wire seg_ld  = (k1[K_MOVSR] & d) | k1[K_POPS];
wire t_nmi   = commit & c_n & nmi_pend;
wire t_intr  = commit & intr & (ci_x | (ci_m & mem[9]));  // IF as the committing instruction leaves it
wire t_tf    = commit & c_t & tf_s;
wire take    = (st == S_OP) & (brk | brk_wait | t_nmi | t_intr | t_tf);

// next step's micro-operations (registered into u_*): the step after this one, or step 0 when S_EX is entered
wire        d_mderr = (st == S_EX) & u_mdw & md_err;    // divide error: continue as INT 0 at step 8
wire        d_mdskp = (st == S_EX) & u_mdi & md_err;    // divide error found in the loop: skip to the wait step
wire        d_bnd   = (st == S_EX) & kk[K_BOUND] & (u_ec == E_NOF) & bnd_out;  // NEC BOUND: continue as INT 5
wire [31:0] d_s1    = (st == S_EX) ? s1a : 32'd1;      // step being decoded, one-hot
wire  [7:0] d_mrm   = mrm_e;
wire        d_ismem = (st == S_EA) | ((st != S_DEC) & ismem);
wire        d_rep   = rep_v;
wire  [2:0] d_reg   = d_mrm[5:3];
wire  [2:0] d_rm    = d_mrm[2:0];
wire        d_w     = w;
wire        d_d     = d;
wire        d_is_cmp = k1[K_ALURM] ? ((op[5:3] == 3'd7) | op[7]) : k1[K_ALUIM] ? (d_reg == 3'd7) : 1'b0;
wire        d_imm16 = imm16;
wire        d_push5 = op[0] & (d_reg[2:1] == 2'b11);
wire  [2:0] d_g5    = op[0] ? d_reg : 3'd0;
logic       x_q, x_rd, x_wr, x_io, x_susp, x_corr, x_flush, x_far, x_end, x_r2, x_wb, x_byte, x_ld, x_loop, x_dec;
logic       x_inta, x_halt, x_hlt, x_mds, x_mdc, x_mdi, x_mdp, x_mdw, x_cf, x_jv, x_qp, x_fw, x_fgo, x_efl, x_wfl, x_pre, x_qw, x_pp, x_pi, x_bx;
logic [2:0] x_ws, n_ws;
logic [2:0] x_qd;
logic [3:0] x_a;
logic [ECW-1:0] x_ec;
logic [1:0] x_wd;
logic [31:0] x_j1;
logic  [4:0] x_dl, n_dl;                // EXT: pre-delay of the next step (clocks)
logic       n_q, n_rd, n_wr, n_io, n_susp, n_corr, n_flush, n_far, n_end, n_r2, n_wb, n_byte, n_ld, n_loop, n_dec;
logic       n_inta, n_halt, n_hlt, n_mds, n_mdc, n_mdi, n_mdp, n_mdw, n_cf, n_jv, n_qp, n_fw, n_fgo, n_efl, n_wfl, n_pre, n_qw, n_pp, n_pi, n_bx;
logic [2:0] n_qd;
logic [3:0] n_a;
logic [ECW-1:0] n_ec;
logic [1:0] n_wd;
logic [31:0] n_j1;
always_comb begin
    x_q = 1'b0; x_qd = Q_LO; x_rd = 1'b0; x_wr = 1'b0; x_io = 1'b0; x_susp = 1'b0; x_corr = 1'b0; x_flush = 1'b0;
    x_far = 1'b0; x_end = 1'b0; x_r2 = 1'b0; x_wb = 1'b0; x_byte = 1'b0; x_ld = 1'b0; x_loop = 1'b0; x_dec = 1'b0;
    x_inta = 1'b0; x_halt = 1'b0; x_mds = 1'b0; x_mdc = 1'b0; x_cf = 1'b0; x_mdi = 1'b0; x_mdp = 1'b0; x_mdw = 1'b0; x_ec = E_NONE; x_hlt = 1'b0; x_a = A_EA; x_wd = D_DEF;
    x_j1 = 32'd1; x_jv = 1'b0; x_dl = 5'd0; x_qp = 1'b0; x_fw = 1'b0; x_fgo = 1'b0; x_efl = 1'b0; x_wfl = 1'b0; x_pre = 1'b0; x_qw = 1'b0; x_pp = 1'b0; x_pi = 1'b0; x_bx = 1'b0; x_ws = 3'd0;
    if (NEC) begin                                              // V20 / V30 step table (V20 timing)
        unique case (1'b1)
            k1[K_MOVI8], k1[K_ALUAI], k1[K_MOVI16]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                default: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
            endcase
            k1[K_MOVAM]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: ;
                d_s1[3]: begin x_rd = ~d_d; x_wr = d_d; x_a = A_IMM; x_end = ~d_d; end
                d_s1[4]: x_end = 1'b1;
                default: ;
            endcase
            // jumps: suspend, flush early if the bus is idle the clock before, then flush and start the target fetch
            k1[K_JCC], k1[K_JMPS], k1[K_JMPN]: unique case (1'b1)
                d_s1[0]: begin x_q = 1'b1; x_qd = (k1[K_JMPN]) ? Q_LO : Q_SX; end
                d_s1[1]: begin
                    if (k1[K_JMPN]) begin x_q = 1'b1; x_qd = Q_HI; end
                    if (k1[K_JCC]) x_ec = E_NCOND;
                    x_susp = k1[K_JMPS];
                end
                d_s1[2]: x_susp = k1[K_JMPN];
                d_s1[3]: begin x_susp = k1[K_JCC]; x_efl = k1[K_JMPS]; end
                d_s1[4]: if (k1[K_JMPS]) begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end else x_efl = 1'b1;
                default: begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
            endcase
            k1[K_LOOP]: if (op[1]) unique case (1'b1)           // LOOP, JCXZ (LOOP not taken / JCXZ taken inferred)
                d_s1[0]: begin x_q = 1'b1; x_qd = Q_SX; end
                d_s1[2]: x_ec = E_NLCOND;
                d_s1[4]: x_susp = 1'b1;
                d_s1[6]: x_efl = 1'b1;
                d_s1[7]: begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase else unique case (1'b1)                         // LOOPNZ LOOPZ: test with the pop
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SX; x_ec = E_NLCOND; end
                d_s1[5]: x_susp = 1'b1;
                d_s1[7]: x_efl = 1'b1;
                d_s1[8]: begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_ALURM]: if (!d_ismem) x_end = 1'b1;
                else if (d_d | d_is_cmp) unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_end = op[7];                     // TEST
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: x_wr = 1'b1;
                    d_s1[4]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_MOVRM], k1[K_MOVSR]: if (!d_ismem) x_end = 1'b1;                 // MOV r, r: one step
                else if (d_d) unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_end = k1[K_MOVSR];
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)                // MOV r/m, sreg writes one step earlier
                    d_s1[0]: x_wr = k1[K_MOVSR];
                    d_s1[1]: begin x_wr = k1[K_MOVRM]; x_end = k1[K_MOVSR]; end
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_ALUIM]: if (!d_ismem) unique case (1'b1)        // 3 clocks after the last immediate byte
                    d_s1[0]: begin x_q = 1'b1; x_qd = (op == 8'h83) ? Q_SX : Q_LO; end
                    d_s1[1]: begin x_q = d_imm16; x_qd = Q_HI; end
                    d_s1[3]: x_end = ~d_imm16;
                    d_s1[4]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[2]: begin x_q = 1'b1; x_qd = (op == 8'h83) ? Q_SX : Q_LO; end
                    d_s1[3]: begin x_q = d_imm16; x_qd = Q_HI; x_qp = d_imm16; end
                    d_s1[5]: x_end = d_is_cmp;
                    d_s1[7]: x_wr = 1'b1;
                    d_s1[8]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_GRP3]: if (d_reg[2:1] == 2'd0) begin             // TEST r/m, imm
                    if (!d_ismem) unique case (1'b1)
                        d_s1[1]: x_q = 1'b1;
                        d_s1[2]: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
                        default: ;
                    endcase else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[3]: x_q = 1'b1;
                        d_s1[4]: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
                        d_s1[5]: x_end = 1'b1;
                        default: ;
                    endcase
                end else if (!d_reg[2]) begin
                    if (!d_ismem) x_end = d_s1[1];             // NOT / NEG
                    else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[5]: x_wr = 1'b1;
                        d_s1[6]: x_end = 1'b1;
                        default: ;
                    endcase
                end else unique case (1'b1)                         // MUL IMUL DIV IDIV
                    d_s1[0]: if (d_ismem) x_rd = 1'b1; else begin x_mds = 1'b1; x_jv = 1'b1; x_j1 = 32'd4; end
                    d_s1[1]: x_mds = 1'b1;
                    d_s1[2]: x_mdc = 1'b1;
                    d_s1[3]: x_mdi = 1'b1;
                    d_s1[4]: x_mdp = 1'b1;
                    default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
                endcase
            k1[K_AAM], k1[K_AAD]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: x_mds = 1'b1;
                d_s1[2]: begin x_mdc = 1'b1; x_jv = k1[K_AAD]; x_j1 = 32'd32; end    // AAD: no loop
                d_s1[3]: x_mdi = 1'b1;
                d_s1[4]: x_mdp = 1'b1;
                default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
            endcase
            k1[K_XCHG]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_end = 1'b1;                      // first write decided in S_DEC
                    default: x_end = 1'b1;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: x_wr = 1'b1;
                    d_s1[4]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_XCHGA]: x_end = 1'b1;
            k1[K_MISC]: case (op)
                8'h99: x_end = d_s1[2];                 // CWD: one count
                8'h9E: x_end = d_s1[0];
                default: x_end = 1'b1;
            endcase
            k1[K_BCD]: x_end = op[4] ? d_s1[4] : d_s1[0];            // AAA AAS one count, DAA DAS one step
            k1[K_LEA]: x_end = 1'b1;
            k1[K_ESC]: unique case (1'b1)                              // 63: a fixed wait after the read (lc)
                d_s1[0]: begin x_rd = 1'b1; x_ld = op == 8'h63; end
                d_s1[1]: begin x_loop = op == 8'h63; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_XLAT]: unique case (1'b1)                             // D6 (alias) reads 16 clocks later than D7
                d_s1[1]: begin x_jv = ~op[0]; x_j1 = 32'd8; end
                d_s1[2], d_s1[19]: begin x_rd = 1'b1; x_a = A_XLAT; x_byte = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_LDS]: unique case (1'b1)
                d_s1[0]: x_rd = 1'b1;
                d_s1[3]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_IO]: if (op[3]) unique case (1'b1)                    // port in DX
                    d_s1[1]: begin x_rd = ~op[1]; x_wr = op[1]; x_io = 1'b1; x_a = A_DX; x_end = ~op[1]; end
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: begin x_q = 1'b1; x_qd = Q_ZX; end
                    d_s1[2]: begin x_rd = ~op[1]; x_wr = op[1]; x_io = 1'b1; x_a = A_IMM; x_end = ~op[1]; end
                    d_s1[3]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_RET]: if (op[0]) unique case (1'b1)          // flush the clock after the read, target fetch the next
                    d_s1[0]: x_susp = 1'b1;
                    d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[2]: x_flush = 1'b1;
                    d_s1[3]: begin x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                    d_s1[2]: x_susp = 1'b1;
                    d_s1[3]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[4]: x_flush = 1'b1;
                    d_s1[5]: begin x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_RETF]: unique case (1'b1)                      // RETF imm enters at 0, RETF at 2; IP and CS reads back to back
                d_s1[0]: begin x_q = 1'b1; if (op[0]) begin x_q = 1'b0; x_susp = 1'b1; x_jv = 1'b1; x_j1 = 32'd8; end end
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: x_susp = 1'b1;
                d_s1[3]: begin x_rd = 1'b1; x_a = A_STK; end
                d_s1[4]: begin x_rd = 1'b1; x_a = A_STK; x_r2 = 1'b1; x_fw = 1'b1; end
                d_s1[6]: begin x_flush = 1'b1; x_far = 1'b1; end
                d_s1[7]: begin x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_IRET]: unique case (1'b1)                      // IP, CS, FLAGS back to back; flush with the FLAGS read
                d_s1[0]: x_susp = 1'b1;
                d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; end
                d_s1[2]: begin x_rd = 1'b1; x_a = A_STK; x_r2 = 1'b1; x_fw = 1'b1; end
                d_s1[3]: begin x_rd = 1'b1; x_a = A_STK; x_fw = 1'b1; x_wfl = 1'b1; x_far = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_CALLN]: unique case (1'b1)                      // flush when the push is taken, target fetch after it
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: x_susp = 1'b1;
                d_s1[3]: x_corr = 1'b1;
                d_s1[6]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_wfl = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_JMPF]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SLO; end
                d_s1[3]: begin x_q = 1'b1; x_qd = Q_SHI; end
                d_s1[4]: x_susp = 1'b1;
                d_s1[5]: begin x_efl = 1'b1; x_far = 1'b1; end
                d_s1[6]: begin x_flush = 1'b1; x_far = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_CALLF]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SLO; end
                d_s1[3]: begin x_q = 1'b1; x_qd = Q_SHI; end
                d_s1[4]: x_susp = 1'b1;
                d_s1[5]: x_corr = 1'b1;
                d_s1[8]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                d_s1[10]: begin x_flush = 1'b1; x_far = 1'b1; end
                d_s1[11]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_INT]: unique case (1'b1)                               // entry: INT3 0 -> 5, INT n 0 -> 6, INTO 0 -> 4; common from 10
                d_s1[0]: if (xint) begin                        // INTR (INTA pair first), NMI, TF: straight to the vector (inferred)
                    x_inta = xinta; x_susp = 1'b1; x_jv = 1'b1; x_j1 = 32'd1024;
                end else begin
                    x_q = op == 8'hCD; x_qd = Q_VEC; x_susp = op == 8'hCC; x_ec = (op == 8'hCE) ? E_NOF : E_NONE;
                    x_jv = 1'b1; x_j1 = (op == 8'hCC) ? 32'd32 : (op == 8'hCD) ? 32'd64 : 32'd16;
                end
                d_s1[8]: x_susp = 1'b1;
                d_s1[10]: begin x_rd = 1'b1; x_a = A_VEC; end
                d_s1[11]: begin x_rd = 1'b1; x_a = A_VEC2; x_r2 = 1'b1; x_fw = 1'b1; end
                d_s1[12]: x_corr = 1'b1;
                d_s1[15]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_FL; end
                d_s1[19]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                d_s1[21]: begin x_flush = 1'b1; x_far = 1'b1; end
                d_s1[22]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_fgo = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_HLT]: unique case (1'b1)                               // stop prefetching, one HALT status cycle, halt
                d_s1[0]: x_susp = 1'b1;
                d_s1[1]: x_halt = 1'b1;
                default: begin x_hlt = 1'b1; x_end = 1'b1; end
            endcase
            k1[K_WAIT]: unique case (1'b1)                              // TEST sampled every 5 clocks (WAIT = 4 + 5n)
                d_s1[0]: ;
                d_s1[1]: x_ec = E_NTEST;
                d_s1[5]: begin x_ec = E_IRQ; x_jv = 1'b1; x_j1 = 32'd2; end
                default: ;
            endcase
            k1[K_PUSHR], k1[K_PUSHS], k1[K_PUSHF]: unique case (1'b1)
                d_s1[2]: begin x_wr = 1'b1; x_a = A_STK; x_wd = (k1[K_PUSHF]) ? D_FL : D_DEF; end
                d_s1[3]: x_end = 1'b1;
                default: ;
            endcase
            k1[K_POPR], k1[K_POPS], k1[K_POPF]: unique case (1'b1)
                d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_POPM]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: begin x_rd = 1'b1; x_a = A_STK; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[2]: begin x_wr = 1'b1; x_fw = 1'b1; end
                    d_s1[3]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_INCRM]: case (d_g5)
                3'd2: if (!d_ismem) unique case (1'b1)              // CALL r/m: flush with the push
                    d_s1[2]: x_susp = 1'b1;
                    d_s1[3]: x_corr = 1'b1;
                    d_s1[5]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_wfl = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: x_susp = 1'b1;
                    d_s1[4]: x_corr = 1'b1;
                    d_s1[6]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_wfl = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd3: unique case (1'b1)                            // CALL m16:16
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[5]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; x_susp = 1'b1; end
                    d_s1[6]: x_corr = 1'b1;
                    d_s1[11]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                    d_s1[13]: begin x_flush = 1'b1; x_far = 1'b1; end
                    d_s1[14]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd4: if (!d_ismem) unique case (1'b1)              // JMP r/m
                    d_s1[0]: x_susp = 1'b1;
                    d_s1[1]: x_efl = 1'b1;
                    d_s1[2]: begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_susp = 1'b1;
                    d_s1[2]: x_efl = 1'b1;
                    d_s1[3]: begin x_flush = 1'b1; x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd5: unique case (1'b1)                            // JMP m16:16
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[5]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; x_susp = 1'b1; end
                    d_s1[7]: begin x_flush = 1'b1; x_far = 1'b1; end
                    d_s1[8]: begin x_fgo = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd6, 3'd7: if (!d_ismem) unique case (1'b1)          // PUSH r/m
                        d_s1[4]: begin x_wr = 1'b1; x_a = A_STK; end
                        d_s1[5]: x_end = 1'b1;
                        default: ;
                    endcase else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[6]: begin x_wr = 1'b1; x_a = A_STK; end
                        d_s1[7]: x_end = 1'b1;
                        default: ;
                    endcase
                default: if (!d_ismem) x_end = d_s1[1];        // INC / DEC (register form: 2 steps)
                    else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[5]: x_wr = 1'b1;
                        d_s1[6]: x_end = 1'b1;
                        default: ;
                    endcase
            endcase
            // string ops: first bus cycle at step 3 (without REP: 2 clocks earlier); REP with CX = 0 ends at step 30; per
            // element the bus cycles, then a check step that decrements CX and loops back (or goes to the tail when CX was 1
            // or the ZF / CF test ends it)
            k1[K_STR]: if (d_s1[0]) begin x_jv = 1'b1; x_j1 = d_rep ? 32'h400000 : 32'd4; end   // REP: 22 23, then 2 or 24
                else if (d_s1[23]) begin x_jv = 1'b1; x_j1 = (r[1] == 16'd0) ? 32'h1000000 : 32'd4; x_ld = 1'b1; end
                else if (d_rep & d_s1[30]) x_end = 1'b1;
                else case (op[3:1])
                3'd2: unique case (1'b1)                                    // MOVS
                    d_s1[3]: begin x_rd = 1'b1; x_a = A_SI; x_fw = 1'b1; end
                    d_s1[4]: begin x_wr = 1'b1; x_a = A_DI; x_fw = 1'b1; end
                    d_s1[5]: if (!d_rep) x_end = 1'b1;
                             else begin x_dec = 1'b1; x_jv = ~(str_last & d_w); x_j1 = str_last ? 32'd64 : 32'd8; x_ec = str_last ? E_NONE : E_IRQ; x_end = str_last & d_w; end
                    d_s1[6]: x_end = 1'b1;
                    default: ;
                endcase
                3'd5: unique case (1'b1)                                    // STOS
                    d_s1[3]: begin x_wr = 1'b1; x_a = A_DI; x_fw = 1'b1; end
                    d_s1[4]: if (!d_rep) x_end = 1'b1;
                             else begin x_dec = 1'b1; x_jv = ~(str_last & d_w); x_j1 = str_last ? 32'd32 : 32'd8; x_ec = str_last ? E_NONE : E_IRQ; x_end = str_last & d_w; end
                    d_s1[5]: begin x_loop = 1'b1; x_end = 1'b1; end     // REP ends 12 clocks after the opcode at the earliest
                    default: ;
                endcase
                3'd6: unique case (1'b1)                                    // LODS
                    d_s1[3]: begin x_rd = 1'b1; x_a = A_SI; x_end = ~d_rep; end
                    d_s1[7]: begin x_dec = 1'b1; x_jv = 1'b1; x_j1 = str_last ? 32'd256 : 32'd8; x_ec = str_last ? E_NONE : E_IRQ; end
                    d_s1[11]: x_end = 1'b1;
                    default: ;
                endcase
                3'd3: unique case (1'b1)                                    // CMPS (REP: DI read first; flags, then the test)
                    d_s1[3]: begin x_rd = 1'b1; x_a = d_rep ? A_DI : A_SI; x_r2 = d_rep; x_fw = 1'b1; end
                    d_s1[4]: begin x_rd = 1'b1; x_a = d_rep ? A_SI : A_DI; x_r2 = ~d_rep; x_fw = 1'b1; x_end = ~d_rep; end
                    d_s1[6]: x_cf = 1'b1;
                    d_s1[9]: begin x_dec = 1'b1; x_jv = 1'b1; x_j1 = (str_last | str_zx) ? 32'd1024 : 32'd8;
                                   x_ec = (str_last | str_zx) ? E_NONE : E_IRQ; end
                    d_s1[13]: x_end = 1'b1;
                    default: ;
                endcase
                default: unique case (1'b1)                                 // SCAS
                    d_s1[3]: begin x_rd = 1'b1; x_a = A_DI; end
                    d_s1[4]: x_end = ~d_rep;
                    d_s1[5]: x_cf = 1'b1;
                    d_s1[8]: begin x_dec = 1'b1; x_jv = 1'b1; x_j1 = (str_last | str_zx) ? 32'd512 : 32'd8;
                                   x_ec = (str_last | str_zx) ? E_NONE : E_IRQ; end
                    d_s1[14]: x_end = 1'b1;
                    default: ;
                endcase
                endcase
            k1[K_SHIFT]: if (!op[1] & !d_ismem) x_end = d_s1[3];       // by 1, register
                else if (!op[1]) unique case (1'b1)                       // by 1, memory
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[7]: x_wr = 1'b1;
                    d_s1[8]: x_end = 1'b1;
                    default: ;
                endcase else if (!d_ismem) unique case (1'b1)         // by CL: 1 clock per count (count 0: one clock less)
                    d_s1[0]: x_ld = 1'b1;
                    d_s1[1]: begin x_loop = 1'b1; x_jv = 1'b1; x_j1 = sh_z ? 32'd8 : 32'd4; end
                    d_s1[7]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)                       // count 0: no write
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_ld = 1'b1;
                    d_s1[2]: begin x_loop = 1'b1; x_jv = 1'b1; x_j1 = sh_z ? 32'h100000 : 32'd8; end
                    d_s1[10]: x_wr = 1'b1;
                    d_s1[11]: x_end = 1'b1;
                    d_s1[25]: x_end = 1'b1;
                    default: ;
                endcase
            k1[K_MOVMI]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    default: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
                endcase else unique case (1'b1)                // immediate taken in S_EA
                    d_s1[1]: x_wr = 1'b1;
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase
            kk[K_SHIFTI]: begin                                      // C0 / C1: count from the immediate
                if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    d_s1[1]: x_ld = 1'b1;
                    d_s1[2]: begin x_loop = 1'b1; x_jv = 1'b1; x_j1 = sh_z ? 32'd16 : 32'd8; end
                    d_s1[7]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[2]: x_q = 1'b1;
                    d_s1[4]: x_ld = 1'b1;
                    d_s1[5]: begin x_loop = 1'b1; x_jv = 1'b1; x_j1 = sh_z ? 32'h800000 : 32'd64; end
                    d_s1[10]: x_wr = 1'b1;
                    d_s1[11]: x_end = 1'b1;
                    d_s1[25]: x_end = 1'b1;
                    default: ;
                endcase
            end
            kk[K_X0F]: if (x0f_bit) begin                       // TEST1 CLR1 SET1 NOT1 (CL: 10-17, imm: 18-1F)
                if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_q = op[3];
                    d_s1[1]: x_end = ~op[3] & (op[2:1] != 2'd1);
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[2]: x_q = op[3];
                    d_s1[3]: x_end = op[2:1] == 2'd0;
                    d_s1[5]: x_wr = op[2];
                    d_s1[6]: begin x_wr = op[2:1] == 2'd1; x_end = op[2]; end
                    d_s1[7]: x_end = 1'b1;
                    default: ;
                endcase
            end else if (op[7:4] == 4'h2 && op[3]) begin        // ROL4 (28) / ROR4 (2A)
                if (!d_ismem) x_end = op[1] ? d_s1[15] : d_s1[11];
                else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[12]: x_wr = ~op[1];
                    d_s1[13]: x_end = ~op[1];
                    d_s1[16]: x_wr = op[1];
                    d_s1[17]: x_end = op[1];
                    default: ;
                endcase
            end else if (x0f_4s) unique case (1'b1)             // ADD4S SUB4S CMP4S: (CL + 1) / 2 bytes, SI / DI unchanged
                d_s1[0]: x_pp = 1'b1;                           // byte count in tmp high
                d_s1[3]: begin x_jv = s4_n0; x_j1 = 32'h80000000; end
                d_s1[4]: begin x_rd = 1'b1; x_a = A_IMM; x_ld = ~op[2]; x_ws = 3'd7; x_dl = u_wr ? lc[4:0] : 5'd0; end
                d_s1[7]: begin x_rd = 1'b1; x_a = A_PD; x_r2 = 1'b1; x_ld = op[2] | s4_n1; x_ws = 3'd6; end
                d_s1[9]: x_bx = 1'b1;
                d_s1[12]: begin x_wr = ~op[2]; x_a = A_PD; x_wd = D_TMP; x_byte = 1'b1; x_pi = 1'b1; x_jv = 1'b1;
                                x_j1 = s4_n1 ? 32'h100000 : op[2] ? 32'h2000000 : 32'h10; end
                d_s1[20]: x_loop = 1'b1;                        // the end counts from the last destination read
                d_s1[25]: begin x_loop = 1'b1; x_jv = 1'b1; x_j1 = 32'h10; end
                d_s1[21]: x_end = c4;
                d_s1[22], d_s1[31]: x_end = 1'b1;
                default: ;
            endcase else if (x0f_bf & ~op[1]) unique case (1'b1)    // INS: word at ES:DI (and DI + 2)
                d_s1[0]: x_pp = 1'b1;
                d_s1[2]: begin x_jv = bf_o0; x_j1 = 32'h400000; end
                d_s1[3]: begin x_rd = 1'b1; x_a = A_PD; x_ld = 1'b1; x_ws = 3'd0; x_dl = 5'd1; end
                d_s1[4], d_s1[9]: x_loop = 1'b1;
                d_s1[12]: begin x_loop = 1'b1; x_bx = 1'b1; end
                d_s1[19]: begin x_loop = 1'b1; x_bx = 1'b1; x_r2 = 1'b1; end
                d_s1[28]: begin x_loop = 1'b1; x_ld = bf_l5; x_ws = 3'd7; end   // 5+ bits: the write counts from before the read
                d_s1[5]: x_q = op[3];
                d_s1[8]: begin x_ld = 1'b1; x_ws = bf_lt ? 3'd6 : 3'd3; x_jv = ~bf_lt; x_j1 = 32'h8000; end
                d_s1[10]: begin x_rd = 1'b1; x_a = A_PD; x_ld = 1'b1; x_ws = 3'd1; end
                d_s1[13]: begin x_wr = 1'b1; x_a = A_PD; x_wd = D_TMP; end
                d_s1[14]: x_end = 1'b1;
                d_s1[15]: begin x_loop = 1'b1; x_bx = 1'b1; end
                d_s1[16]: begin x_wr = 1'b1; x_a = A_PD; x_wd = D_TMP; x_wb = 1'b1; x_pi = 1'b1; x_jv = 1'b1;
                                x_j1 = bf_gt ? 32'h20000 : 32'h4000; end
                d_s1[17]: begin x_rd = 1'b1; x_a = A_PD; x_r2 = 1'b1; x_ld = 1'b1; x_ws = 3'd2; end
                d_s1[20]: begin x_wr = 1'b1; x_a = A_PD; x_wd = D_TMP; x_jv = 1'b1; x_j1 = 32'h4000; end
                d_s1[24]: x_q = op[3];
                d_s1[27]: begin x_ld = 1'b1; x_ws = bf_lt ? 3'd5 : 3'd4; x_jv = ~bf_lt; x_j1 = 32'h8000; end
                d_s1[29]: begin x_rd = 1'b1; x_a = A_PD; x_ld = ~bf_l5; x_ws = 3'd1; x_jv = 1'b1; x_j1 = 32'h800; end
                default: ;
            endcase else if (x0f_bf) unique case (1'b1)               // EXT: word at DS:SI (and SI + 2)
                d_s1[0]: x_pp = 1'b1;
                d_s1[1]: x_q = op[3];
                d_s1[4]: begin x_rd = 1'b1; x_a = A_PD; x_dl = 5'd1; end
                d_s1[5]: begin x_pi = 1'b1; x_jv = ~bf_gt; x_j1 = 32'h400; end
                d_s1[9]: begin x_rd = 1'b1; x_a = A_PD; x_r2 = 1'b1; end
                d_s1[10]: x_wb = ~bf_lt;
                d_s1[11]: begin x_ld = 1'b1; x_ws = 3'd0; end
                d_s1[12]: begin x_loop = 1'b1; x_end = 1'b1; end
                default: ;
            endcase else x_end = 1'b1;
            kk[K_PUSHA]: unique case (1'b1)                             // 8 pushes, 2 clocks between; register index in lc
                d_s1[0]: x_ld = 1'b1;
                d_s1[2]: begin x_wr = 1'b1; x_a = A_STK; end
                d_s1[3]: x_end = lc == 8'd7;
                d_s1[4]: begin x_jv = 1'b1; x_j1 = 32'd4; x_pre = 1'b1; end
                default: ;
            endcase
            kk[K_POPA]: unique case (1'b1)                              // 7 pops back to back (the SP slot is not read)
                d_s1[0]: x_ld = 1'b1;
                d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; x_wb = 1'b1; x_fw = 1'b1; end
                d_s1[2]: begin x_rd = 1'b1; x_a = A_STK; x_wb = 1'b1; x_fw = 1'b1; x_jv = 1'b1; x_j1 = 32'd4; x_end = lc == 8'd1; end
                default: ;
            endcase
            kk[K_IMULI]: unique case (1'b1)                           // memory form: immediate 2 clocks after the read
                d_s1[0]: begin x_rd = d_ismem; x_q = ~d_ismem; x_qd = op[1] ? Q_SX : Q_LO; x_jv = 1'b1;
                               x_j1 = d_ismem ? 32'h100000 : 32'd4; end      // register form: immediate right after ModRM
                d_s1[20]: begin x_jv = 1'b1; x_j1 = 32'd2; end
                d_s1[1]: begin x_q = 1'b1; x_qd = op[1] ? Q_SX : Q_LO; end
                d_s1[2]: begin x_q = ~op[1]; x_qd = Q_HI; end
                d_s1[3]: x_mds = 1'b1;
                d_s1[4]: x_mdc = 1'b1;
                d_s1[5]: x_mdi = 1'b1;
                d_s1[6]: x_mdp = 1'b1;
                default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
            endcase
            kk[K_BOUND]: unique case (1'b1)
                d_s1[0]: x_rd = 1'b1;
                d_s1[3]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; end
                d_s1[6]: x_ec = E_NOF;                              // outside: INT 5 from its step 8
                default: ;
            endcase
            kk[K_ENTER]: unique case (1'b1)                             // C8 iw, ib: level in tmp2, frame in tmp
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_wr = 1'b1; x_a = A_STK; x_qw = 1'b1; x_ld = 1'b1; end   // push BP, level byte popped at its T1
                d_s1[3]: begin x_end = tmp2[7:0] == 8'd0; x_jv = 1'b1; x_j1 = (tmp2[7:0] == 8'd1) ? 32'h400 : 32'h20; end
                d_s1[6]: x_wb = 1'b1;
                d_s1[7]: begin x_rd = 1'b1; x_a = A_BP; x_wb = 1'b1; x_fw = 1'b1; end
                d_s1[8]: begin x_wr = 1'b1; x_a = A_STK; x_r2 = 1'b1; x_fw = 1'b1; x_jv = 1'b1; x_j1 = (lc == 8'd0) ? 32'h800 : 32'h80; end
                d_s1[11]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_fw = 1'b1; end
                d_s1[12]: x_end = 1'b1;
                default: ;
            endcase
            kk[K_INSOUT]: if (d_s1[0]) begin x_jv = 1'b1; x_j1 = d_rep ? 32'h400000 : 32'd8; end   // INS (6C 6D) / OUTS (6E 6F)
                else if (d_s1[23]) begin x_jv = 1'b1; x_j1 = (r[1] == 16'd0) ? 32'h1000000 : 32'd4; x_ld = 1'b1; end
                else if (d_rep & d_s1[30]) x_end = 1'b1;
                else unique case (1'b1)
                    d_s1[3]: begin x_rd = 1'b1; x_io = ~op[1]; x_a = op[1] ? A_SI : A_DX; x_fw = 1'b1; end
                    d_s1[4]: begin x_wr = 1'b1; x_io = op[1]; x_a = op[1] ? A_DX : A_DI; x_fw = 1'b1; end
                    d_s1[5]: if (!d_rep) x_end = 1'b1;
                             else begin x_dec = 1'b1; x_jv = ~(str_last & d_w); x_j1 = str_last ? 32'd64 : 32'd8; x_ec = str_last ? E_NONE : E_IRQ; x_end = str_last & d_w; end
                    d_s1[6]: x_end = 1'b1;
                    default: ;
                endcase
            kk[K_PUSHI]: unique case (1'b1)
                d_s1[0]: begin x_q = 1'b1; x_qd = op[1] ? Q_SX : Q_LO; end
                d_s1[1]: begin x_q = ~op[1]; x_qd = Q_HI; end
                d_s1[2]: begin x_wr = 1'b1; x_a = A_STK; end
                d_s1[3]: x_end = 1'b1;
                default: ;
            endcase
            kk[K_LEAVE]: unique case (1'b1)
                d_s1[1]: begin x_rd = 1'b1; x_a = A_BP; x_end = 1'b1; end
                default: ;
            endcase
            default: x_end = 1'b1;
        endcase
        if (E8 & (k1[K_CALLN] | k1[K_JMPN]) & e_cc & d_s1[1]) x_ec[ECW-1] = 1'b1;   // 8080 Jcc / Ccc not taken
        // HLT, native and 8080 mode: released with no interrupt to take (INT with IE = 0, UM 9-1) it resumes the
        // prefetch a step after the halt and continues after HLT; NMI / INT with IE = 1 end it there (interrupt entry)
        if (k1[K_HLT] & d_s1[2]) begin x_end = 1'b0; x_ec = E_IRQ; end
        if (k1[K_HLT] & d_s1[3]) begin x_hlt = 1'b0; x_fgo = 1'b1; end
    end else begin
        unique case (1'b1)
            k1[K_MOVI8], k1[K_ALUAI], k1[K_MOVI16]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                default: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
            endcase
            k1[K_MOVAM]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: ;
                d_s1[3]: begin x_rd = ~d_d; x_a = A_IMM; x_end = ~d_d; end
                d_s1[4]: ;
                default: begin x_wr = 1'b1; x_a = A_IMM; x_end = 1'b1; end
            endcase
            k1[K_JCC], k1[K_JMPS], k1[K_JMPN]: unique case (1'b1)
                d_s1[0]: begin x_q = 1'b1; x_qd = (k1[K_JMPN]) ? Q_LO : Q_SX; end
                d_s1[1]: begin
                    if (k1[K_JMPN]) begin x_q = 1'b1; x_qd = Q_HI; end
                    if (k1[K_JCC]) x_ec = E_NCOND;
                end
                d_s1[2]: x_susp = ~k1[K_JCC];
                d_s1[3]: if (k1[K_JCC]) x_susp = 1'b1; else x_corr = 1'b1;
                d_s1[4]: if (k1[K_JCC]) x_corr = 1'b1; else begin x_flush = 1'b1; x_end = 1'b1; end
                default: begin x_flush = 1'b1; x_end = 1'b1; end
            endcase
            k1[K_LOOP]: unique case (1'b1)
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SX; end
                d_s1[3]: begin x_ec = E_NLCOND; if (op[1:0] == 2'd2) begin x_jv = 1'b1; x_j1 = 32'd32; end end
                d_s1[5]: x_susp = 1'b1;
                d_s1[6]: x_corr = 1'b1;
                d_s1[7]: begin x_flush = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_ALURM]: if (!d_ismem) x_end = 1'b1;
                else if (d_d | d_is_cmp) unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[7]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_MOVRM], k1[K_MOVSR]: if (d_d) unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[2]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[3]: begin x_wr = k1[K_MOVSR]; x_end = k1[K_MOVSR]; end
                    d_s1[4]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_ALUIM]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: begin x_q = 1'b1; x_qd = (op == 8'h83) ? Q_SX : Q_LO; end
                    default: begin x_q = d_imm16; x_qd = Q_HI; x_end = 1'b1; end
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: begin x_q = 1'b1; x_qd = (op == 8'h83) ? Q_SX : Q_LO; end
                    d_s1[4]: begin x_q = d_imm16; x_qd = Q_HI; end
                    d_s1[5]: x_end = d_is_cmp;
                    d_s1[7]: begin x_wr = 1'b1; x_end = 1'b1; if (BUS16) x_dl = 5'd1; end
                    default: ;
                endcase
            k1[K_GRP3]: if (d_reg[2:1] == 2'd0) begin             // TEST r/m, imm
                    if (!d_ismem) unique case (1'b1)
                        d_s1[1]: x_q = 1'b1;
                        d_s1[2]: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
                        default: ;
                    endcase else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[3]: x_q = 1'b1;
                        d_s1[4]: begin x_q = d_w; x_qd = Q_HI; end
                        d_s1[5]: x_end = 1'b1;
                        default: ;
                    endcase
                end else if (!d_reg[2]) begin
                    if (!d_ismem) x_end = 1'b1;                // NOT / NEG
                    else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[6]: begin x_wr = 1'b1; x_end = 1'b1; end
                        default: ;
                    endcase
                end else unique case (1'b1)                         // MUL IMUL DIV IDIV
                    d_s1[0]: if (d_ismem) x_rd = 1'b1; else begin x_mds = 1'b1; x_jv = 1'b1; x_j1 = 32'd4; end
                    d_s1[1]: x_mds = 1'b1;
                    d_s1[2]: x_mdc = 1'b1;
                    d_s1[3]: x_mdi = 1'b1;
                    d_s1[4]: x_mdp = 1'b1;
                    default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
                endcase
            k1[K_AAM], k1[K_AAD]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: x_mds = 1'b1;
                d_s1[2]: x_mdc = 1'b1;
                d_s1[3]: x_mdi = 1'b1;
                d_s1[4]: x_mdp = 1'b1;
                default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
            endcase
            k1[K_XCHG]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_wb = 1'b1;
                    default: x_end = 1'b1;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[8]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_XCHGA]: x_end = 1'b1;
            k1[K_MISC]: case (op)
                8'h99: begin if (d_s1[2]) x_ec = E_NAX15; if (d_s1[3]) x_end = 1'b1; end
                8'hD6: begin if (d_s1[0]) x_ec = E_NFC; if (d_s1[1]) x_end = 1'b1; end
                8'h9E: x_end = d_s1[1];
                default: x_end = 1'b1;
            endcase
            k1[K_BCD]: if (op[4]) begin if (d_s1[5]) x_ec = E_BCD; if (d_s1[6]) x_end = 1'b1; end else x_end = d_s1[1];
            k1[K_LEA]: x_end = 1'b1;
            k1[K_ESC]: unique case (1'b1)
                d_s1[0]: x_rd = 1'b1;
                d_s1[2]: x_end = 1'b1;
                default: ;
            endcase
            k1[K_XLAT]: unique case (1'b1)
                d_s1[4]: begin x_rd = 1'b1; x_a = A_XLAT; x_byte = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_LDS]: unique case (1'b1)
                d_s1[0]: x_rd = 1'b1;
                d_s1[6]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_IO]: if (op[3]) unique case (1'b1)                    // port in DX
                    d_s1[1]: begin x_rd = ~op[1]; x_io = 1'b1; x_a = A_DX; x_end = ~op[1]; end
                    d_s1[2]: begin x_wr = op[1]; x_io = 1'b1; x_a = A_DX; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: begin x_q = 1'b1; x_qd = Q_ZX; end
                    d_s1[3]: begin x_rd = ~op[1]; x_io = 1'b1; x_a = A_IMM; x_end = ~op[1]; end
                    d_s1[4]: begin x_wr = op[1]; x_io = 1'b1; x_a = A_IMM; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_RET]: if (op[0]) unique case (1'b1)
                    d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[2]: x_susp = 1'b1;
                    d_s1[3]: begin x_flush = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                    d_s1[4]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[5]: x_susp = 1'b1;
                    d_s1[7]: begin x_flush = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_RETF], k1[K_IRET]: unique case (1'b1)                      // RETF imm enters at 0, RETF / IRET at 2
                d_s1[0]: begin x_q = 1'b1; if (op[0]) begin x_q = 1'b0; x_jv = 1'b1; x_j1 = 32'd8; end end
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[5]: begin x_rd = 1'b1; x_a = A_STK; end
                d_s1[6]: x_susp = 1'b1;
                d_s1[10]: begin x_rd = 1'b1; x_a = A_STK; x_r2 = 1'b1; end
                d_s1[11]: begin x_flush = 1'b1; x_far = 1'b1; x_end = k1[K_RETF]; end
                d_s1[14]: begin x_rd = 1'b1; x_a = A_STK; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_CALLN]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: x_susp = 1'b1;
                d_s1[3]: x_corr = 1'b1;
                d_s1[4]: x_flush = 1'b1;
                d_s1[8]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_JMPF]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SLO; end
                d_s1[3]: begin x_q = 1'b1; x_qd = Q_SHI; end
                d_s1[4]: x_susp = 1'b1;
                d_s1[6]: begin x_flush = 1'b1; x_far = 1'b1; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_CALLF]: unique case (1'b1)
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SLO; end
                d_s1[3]: begin x_q = 1'b1; x_qd = Q_SHI; end
                d_s1[4]: begin x_susp = 1'b1; if (BUS16) x_dl = 5'd1; end
                d_s1[5]: x_corr = 1'b1;
                d_s1[6]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                d_s1[11]: begin x_flush = 1'b1; x_far = 1'b1; end
                d_s1[15]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_INT]: unique case (1'b1)                               // entry: INTO 0, INT3 0 -> 2, INT n 0 -> 4; common from 8
                d_s1[0]: if (xint) begin                        // INTR: INTA pair, vector in the second; NMI / TF / div error
                    x_inta = xinta; x_jv = 1'b1; x_j1 = 32'd256;
                end else begin
                    x_q = op == 8'hCD; x_qd = Q_VEC;
                    x_jv = op != 8'hCE; x_j1 = op[0] ? 32'd16 : 32'd4;
                end
                d_s1[1]: x_ec = E_NOF;
                d_s1[8]: begin x_rd = 1'b1; x_a = A_VEC; if (BUS16) x_dl = ((op == 8'hCD) & ~xint) ? 5'd2 : 5'd1; end
                d_s1[11]: begin x_rd = 1'b1; x_a = A_VEC2; x_r2 = 1'b1; end
                d_s1[12]: x_susp = 1'b1;
                d_s1[15]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_FL; end
                d_s1[19]: x_corr = 1'b1;
                d_s1[20]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                d_s1[25]: begin x_flush = 1'b1; x_far = 1'b1; end
                d_s1[29]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_end = 1'b1; end
                d_s1[6]: x_susp = BUS16 & (op == 8'hCD) & ~xint;
                default: ;
            endcase
            k1[K_HLT]: unique case (1'b1)                               // stop prefetching, one HALT status cycle, halt
                d_s1[0]: x_susp = 1'b1;
                d_s1[1]: x_halt = 1'b1;
                default: begin x_hlt = 1'b1; x_end = 1'b1; end
            endcase
            k1[K_WAIT]: unique case (1'b1)                              // TEST sampled every 5 clocks (WAIT = 4 + 5n)
                d_s1[0]: ;
                d_s1[1]: x_ec = E_NTEST;
                d_s1[5]: begin x_ec = E_IRQ; x_jv = 1'b1; x_j1 = 32'd2; end
                default: ;
            endcase
            k1[K_PUSHR], k1[K_PUSHS], k1[K_PUSHF]: unique case (1'b1)
                d_s1[4]: begin x_wr = 1'b1; x_a = A_STK; x_wd = (k1[K_PUSHF]) ? D_FL : D_DEF; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_POPR], k1[K_POPS], k1[K_POPF]: unique case (1'b1)
                d_s1[1]: begin x_rd = 1'b1; x_a = A_STK; x_end = 1'b1; end
                default: ;
            endcase
            k1[K_POPM]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: begin x_rd = 1'b1; x_a = A_STK; x_end = ~BUS16; if (BUS16) x_dl = 5'd2; end
                    d_s1[1]: x_end = BUS16;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[3]: begin x_rd = 1'b1; x_a = A_STK; end
                    d_s1[8]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_INCRM]: case (d_g5)
                3'd2: unique case (1'b1)                            // CALL r/m (register form one step earlier)
                    d_s1[0]: begin x_rd = d_ismem; x_jv = ~d_ismem; x_j1 = 32'd8; end
                    d_s1[3]: x_susp = 1'b1;
                    d_s1[4]: x_corr = 1'b1;
                    d_s1[5]: x_flush = 1'b1;
                    d_s1[9]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_end = 1'b1; end
                    default: ;
                endcase
                3'd3: unique case (1'b1)                            // CALL m16:16
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[5]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; end
                    d_s1[7]: x_susp = 1'b1;
                    d_s1[8]: x_corr = 1'b1;
                    d_s1[9]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_CS; end
                    d_s1[14]: begin x_flush = 1'b1; x_far = 1'b1; end
                    d_s1[18]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; x_end = 1'b1; end
                    default: ;
                endcase
                3'd4: unique case (1'b1)                            // JMP r/m
                    d_s1[0]: begin x_rd = d_ismem; x_jv = ~d_ismem; x_j1 = 32'd8; end
                    d_s1[3]: x_susp = 1'b1;
                    d_s1[4]: begin x_flush = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd5: unique case (1'b1)                            // JMP m16:16
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[4]: x_susp = 1'b1;
                    d_s1[6]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; end
                    d_s1[7]: begin x_flush = 1'b1; x_far = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
                3'd6, 3'd7: if (!d_ismem) unique case (1'b1)          // PUSH r/m
                        d_s1[4]: begin x_wr = 1'b1; x_a = A_STK; x_end = 1'b1; if (BUS16) x_dl = 5'd1; end
                        default: ;
                    endcase else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[7]: begin x_wr = 1'b1; x_a = A_STK; x_end = 1'b1; end
                        default: ;
                    endcase
                default: if (!d_ismem) x_end = 1'b1;           // INC / DEC
                    else unique case (1'b1)
                        d_s1[0]: x_rd = 1'b1;
                        d_s1[6]: begin x_wr = 1'b1; x_end = 1'b1; end
                        default: ;
                    endcase
            endcase
            k1[K_STR]: if (!d_rep) case (op[3:1])               // MOVS CMPS STOS LODS SCAS without REP
                    3'd2: unique case (1'b1)
                        d_s1[2]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[5]: begin x_wr = 1'b1; x_a = A_DI; end
                        d_s1[8]: x_end = 1'b1;
                        default: ;
                    endcase
                    3'd3: unique case (1'b1)
                        d_s1[3]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[7]: begin x_rd = 1'b1; x_a = A_DI; x_r2 = 1'b1; end
                        d_s1[11]: x_end = 1'b1;
                        default: ;
                    endcase
                    3'd5: unique case (1'b1)
                        d_s1[2]: begin x_wr = 1'b1; x_a = A_DI; end
                        d_s1[5]: x_end = 1'b1;
                        default: ;
                    endcase
                    3'd6: unique case (1'b1)
                        d_s1[2]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[5]: x_end = 1'b1;
                        default: ;
                    endcase
                    default: unique case (1'b1)
                        d_s1[4]: begin x_rd = 1'b1; x_a = A_DI; end
                        d_s1[8]: x_end = 1'b1;
                        default: ;
                    endcase
                endcase else if (d_s1[4]) x_ec = E_CX0;
                else case (op[3:1])                          // REP: iteration loops back to its first bus step
                    3'd2: unique case (1'b1)
                        d_s1[9]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[12]: begin x_wr = 1'b1; x_a = A_DI; end
                        d_s1[13]: x_dec = 1'b1;
                        d_s1[16]: x_ec = E_CX0;
                        d_s1[18]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd512; end
                        default: ;
                    endcase
                    3'd3: unique case (1'b1)
                        d_s1[10]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[14]: begin x_rd = 1'b1; x_a = A_DI; x_r2 = 1'b1; end
                        d_s1[15]: x_dec = 1'b1;
                        d_s1[16]: x_cf = 1'b1;
                        d_s1[19]: x_ec = E_ZX;
                        d_s1[20]: x_ec = E_CX0;
                        d_s1[23]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd1024; end
                        default: ;
                    endcase
                    3'd5: unique case (1'b1)
                        d_s1[9]: begin x_wr = 1'b1; x_a = A_DI; end
                        d_s1[10]: x_dec = 1'b1;
                        d_s1[13]: x_ec = E_CX0;
                        d_s1[15]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd512; end
                        default: ;
                    endcase
                    3'd6: unique case (1'b1)
                        d_s1[9]: begin x_rd = 1'b1; x_a = A_SI; end
                        d_s1[10]: x_dec = 1'b1;
                        d_s1[15]: x_ec = E_CX0;
                        d_s1[17]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd512; end
                        default: ;
                    endcase
                    default: unique case (1'b1)
                        d_s1[11]: begin x_rd = 1'b1; x_a = A_DI; end
                        d_s1[12]: x_dec = 1'b1;
                        d_s1[13]: x_cf = 1'b1;
                        d_s1[16]: x_ec = E_ZX;
                        d_s1[17]: x_ec = E_CX0;
                        d_s1[21]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd2048; end
                        default: ;
                    endcase
                endcase
            k1[K_SHIFT]: if (!op[1]) unique case (1'b1)                 // by 1 (register form has no steps)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[6]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase else if (!d_ismem) unique case (1'b1)         // by CL: 4 clocks per count
                    d_s1[0]: x_ld = 1'b1;
                    d_s1[1]: x_loop = 1'b1;
                    d_s1[5]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_ld = 1'b1;
                    d_s1[2]: x_loop = 1'b1;
                    d_s1[11]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            k1[K_MOVMI]: if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    default: begin x_q = d_w; x_qd = Q_HI; x_end = 1'b1; end
                endcase else unique case (1'b1)
                    d_s1[1]: x_q = 1'b1;
                    d_s1[2]: begin x_q = d_w; x_qd = Q_HI; end
                    d_s1[5]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            kk[K_SHIFTI]: begin                                      // NEC C0 / C1: count from the immediate
                if (!d_ismem) unique case (1'b1)
                    d_s1[0]: x_q = 1'b1;
                    d_s1[1]: x_ld = 1'b1;
                    d_s1[2]: x_loop = 1'b1;
                    d_s1[6]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[1]: x_q = 1'b1;
                    d_s1[2]: x_ld = 1'b1;
                    d_s1[3]: x_loop = 1'b1;
                    d_s1[12]: begin x_wr = 1'b1; x_end = 1'b1; end
                    default: ;
                endcase
            end
            kk[K_X0F]: if (!(x0f_bit | (op[7:4] == 4'h2 && op[3]))) x_end = 1'b1;  // others not implemented
                else if (!d_ismem) unique case (1'b1)
                    d_s1[0]: begin x_q = x0f_bit & op[3]; x_end = ~(x0f_bit & op[3]); end
                    default: x_end = 1'b1;
                endcase else unique case (1'b1)
                    d_s1[0]: x_rd = 1'b1;
                    d_s1[3]: x_q = x0f_bit & op[3];
                    d_s1[7]: begin x_wr = ~(x0f_bit & (op[2:1] == 2'd0)); x_end = 1'b1; end
                    default: ;
                endcase
            kk[K_PUSHA], kk[K_POPA]: unique case (1'b1)                 // 8 stack cycles, register index in lc
                d_s1[0]: x_ld = 1'b1;
                d_s1[8]: begin x_wr = kk[K_PUSHA]; x_rd = kk[K_POPA]; x_a = A_STK; x_end = 1'b1; end
                default: begin x_wr = kk[K_PUSHA]; x_rd = kk[K_POPA]; x_a = A_STK; x_wb = kk[K_POPA]; end
            endcase
            kk[K_IMULI]: unique case (1'b1)
                d_s1[0]: x_rd = d_ismem;
                d_s1[1]: begin x_q = 1'b1; x_qd = op[1] ? Q_SX : Q_LO; end
                d_s1[2]: begin x_q = ~op[1]; x_qd = Q_HI; end
                d_s1[3]: x_mds = 1'b1;
                d_s1[4]: x_mdc = 1'b1;
                d_s1[5]: x_mdi = 1'b1;
                d_s1[6]: x_mdp = 1'b1;
                default: begin x_mdw = 1'b1; x_ec = E_NMDERR; end
            endcase
            kk[K_BOUND]: unique case (1'b1)
                d_s1[0]: x_rd = 1'b1;
                d_s1[1]: begin x_rd = 1'b1; x_a = A_EA2; x_r2 = 1'b1; end
                d_s1[3]: x_ec = E_NOF;
                default: ;
            endcase
            kk[K_ENTER]: unique case (1'b1)                             // C8 iw, ib: level in tmp2, frame in tmp
                d_s1[0]: x_q = 1'b1;
                d_s1[1]: begin x_q = 1'b1; x_qd = Q_HI; end
                d_s1[2]: begin x_q = 1'b1; x_qd = Q_SLO; end
                d_s1[3]: begin x_wr = 1'b1; x_a = A_STK; end
                d_s1[4]: begin x_ld = 1'b1; x_jv = 1'b1;
                               x_j1 = (tmp2[7:0] == 8'd0) ? 32'd1024 : (tmp2[7:0] == 8'd1) ? 32'd512 : 32'd32; end
                d_s1[5]: x_wb = 1'b1;
                d_s1[7]: begin x_rd = 1'b1; x_a = A_BP; end
                d_s1[8]: begin x_wr = 1'b1; x_a = A_STK; x_r2 = 1'b1; x_jv = 1'b1; x_j1 = (lc == 8'd0) ? 32'd512 : 32'd32; end
                d_s1[9]: begin x_wr = 1'b1; x_a = A_STK; x_wd = D_TMP; end
                d_s1[10]: x_end = 1'b1;
                default: ;
            endcase
            kk[K_INSOUT]: if (!d_rep) unique case (1'b1)               // INS (6C 6D) / OUTS (6E 6F)
                    d_s1[2]: begin x_rd = 1'b1; x_io = ~op[1]; x_a = op[1] ? A_SI : A_DX; end
                    d_s1[5]: begin x_wr = 1'b1; x_io = op[1]; x_a = op[1] ? A_DX : A_DI; end
                    d_s1[8]: x_end = 1'b1;
                    default: ;
                endcase else unique case (1'b1)
                    d_s1[4]: x_ec = E_CX0;
                    d_s1[9]: begin x_rd = 1'b1; x_io = ~op[1]; x_a = op[1] ? A_SI : A_DX; end
                    d_s1[12]: begin x_wr = 1'b1; x_io = op[1]; x_a = op[1] ? A_DX : A_DI; end
                    d_s1[13]: x_dec = 1'b1;
                    d_s1[16]: x_ec = E_CX0;
                    d_s1[18]: begin x_jv = 1'b1; x_ec = E_IRQ; x_j1 = 32'd512; end
                    default: ;
                endcase
            kk[K_PUSHI]: unique case (1'b1)
                d_s1[0]: begin x_q = 1'b1; x_qd = op[1] ? Q_SX : Q_LO; end
                d_s1[1]: begin x_q = ~op[1]; x_qd = Q_HI; end
                d_s1[2]: begin x_wr = 1'b1; x_a = A_STK; x_end = 1'b1; end
                default: ;
            endcase
            kk[K_LEAVE]: unique case (1'b1)
                d_s1[0]: begin x_rd = 1'b1; x_a = A_BP; x_end = 1'b1; end
                default: ;
            endcase
            default: x_end = 1'b1;
        endcase
    end
end

// entering the interrupt sequence (take: step 0 of INT, with or without INTA; divide error: step 8, first vector read)
always_comb begin
    n_q = x_q; n_rd = x_rd; n_wr = x_wr; n_io = x_io; n_susp = x_susp; n_corr = x_corr; n_flush = x_flush; n_far = x_far; n_end = x_end; n_r2 = x_r2; n_wb = x_wb; n_byte = x_byte; n_ld = x_ld; n_loop = x_loop; n_dec = x_dec; n_inta = x_inta; n_halt = x_halt; n_hlt = x_hlt; n_mds = x_mds; n_mdc = x_mdc; n_mdi = x_mdi; n_mdp = x_mdp; n_mdw = x_mdw; n_cf = x_cf; n_jv = x_jv; n_qd = x_qd; n_a = x_a; n_ec = x_ec; n_wd = x_wd; n_j1 = x_j1;
    n_dl = x_dl; n_qp = x_qp; n_fw = x_fw; n_fgo = x_fgo; n_efl = x_efl; n_wfl = x_wfl; n_pre = x_pre; n_qw = x_qw; n_pp = x_pp; n_pi = x_pi; n_bx = x_bx; n_ws = x_ws;
    if ((st == S_OP) | d_mderr | d_mdskp | d_bnd) begin
        n_dl = 5'd0;
        n_q = '0; n_rd = '0; n_wr = '0; n_io = '0; n_susp = '0; n_corr = '0; n_flush = '0; n_far = '0; n_end = '0; n_r2 = '0; n_wb = '0; n_byte = '0; n_ld = '0; n_loop = '0; n_dec = '0; n_inta = '0; n_halt = '0; n_hlt = '0; n_mds = '0; n_mdc = '0; n_mdi = '0; n_mdp = '0; n_mdw = '0; n_cf = '0; n_jv = '0; n_qd = '0; n_a = '0; n_ec = '0; n_wd = '0; n_j1 = '0; n_qp = '0; n_fw = '0; n_fgo = '0; n_efl = '0; n_wfl = '0; n_pre = '0; n_qw = '0; n_pp = '0; n_pi = '0; n_bx = '0; n_ws = '0;
        if (st == S_OP) begin n_inta = (t_intr | brk | brk_wait) & ~(t_nmi | (brk & nmi_pend)); n_jv = 1'b1; n_j1 = 32'd256; end
        else if (NEC & d_bnd) begin n_jv = 1'b1; n_j1 = bnd_lo ? 32'd256 : 32'd32; end
        else if (d_mderr | d_bnd) begin
            n_rd = 1'b1; n_a = A_VEC; n_jv = 1'b1; n_j1 = NEC ? 32'd2048 : 32'd512; n_susp = NEC; if (BUS16 & ~NEC) n_dl = 5'd1;
        end
        else begin n_mdw = 1'b1; n_ec = E_NMDERR; n_jv = 1'b1; n_j1 = 32'd64; end
    end
end

assign q_first   = st == S_OP;
// NEC 0F 20-3B: lc values a step can load (u_ws), registered every clock
logic [7:0] bw0, bw1, bw2, bw3, bw6, bw7, bf_lcf;
wire  [8:0] bf_cl1 = {1'b0, r[1][7:0]} + 9'd1;
always_ff @(posedge clk) if (ce) begin
    bw0 <= {4'd0, bf_o} + (~op[1] ? 8'd2 : bf_gt ? 8'd8 : bf_lt ? 8'd25 : 8'd26);
    bw1 <= {1'b0, bf_g} + {3'd0, bf_o, 1'b0} - 8'd10;
    bw2 <= {1'b0, bf_g16} - 8'd10;
    bw3 <= 8'd28 - {4'd0, bf_o};
    bw6 <= ~x0f_4s ? 8'd8 : (tmp[15:8] == 8'd1) ? 8'd11 : 8'd8;
    bw7 <= x0f_4s ? 8'd16 : {1'b0, bf_g} - 8'd1;       // 4S: next source read from the source read
end
always_comb
    case (u_ws)
        3'd0:    bf_lcf = bw0;
        3'd1:    bf_lcf = bw1;
        3'd2:    bf_lcf = bw2;
        3'd3:    bf_lcf = bw3;
        3'd4:    bf_lcf = 8'd28;
        3'd5:    bf_lcf = 8'd8;
        3'd6:    bf_lcf = bw6;
        default: bf_lcf = bw7;
    endcase
wire   qw_pop    = NEC & (st == S_EX) & u_qw & qw_t & ~qw_got;
assign q_pop     = q_avail & (qw_pop | ((st == S_OP) & ~take) | ((st == S_DEC) & has_modrm) |
                              ((st == S_EA) & (NEC ? nea_pop : ((ph == 2'd1) | ea_two))) | ((st == S_EX) & ~dly_on & u_q) |
                              (NEC & (st == S_X0F) & (ph == 2'd1)));

always_ff @(posedge clk) begin
    if (reset) begin
        st <= S_OP; cnt <= 4'd0; ph <= 2'd0; op <= 8'h90; k1 <= k_one << K_XCHGA; w <= 1'b1; has_modrm <= 1'b0; mrm <= 8'd0; vec <= 8'd0; imm <= 16'd0;
        disp <= 16'd0; lc <= 8'd0; mem <= 16'd0; tmp <= 16'd0; tmp2 <= 16'd0; ovr_v <= 1'b0; rep_v <= 1'b0; rep_z <= 1'b0; ovr_s <= 2'd0; ismem <= 1'b0;
        rep_c <= 1'b0; nim <= 1'b0;
        md <= 1'b1; mdwe <= 1'b0; e8 <= 1'b0; e_hm <= 1'b0; c80q <= 1'b0; ac3q <= 1'b0; wbf_acm <= 2'd0; e_st <= 1'b0; e_nf <= 1'b0; e_cy <= 1'b0; e_psw <= 1'b0; e_abs <= 1'b0; e_cc <= 1'b0;
        e_daa <= 1'b0; e_rst <= 1'b0; e_acm <= 2'd0; e_eas <= 2'd0; e_cn <= 3'd0; e_mrm <= 8'd0; e_calln <= 1'b0; e_retem <= 1'b0; e_brkem <= 1'b0;
        wbp_en <= 1'b0; wbf_e8 <= 1'b0; wbf_cy <= 1'b0; wbf_m8 <= 1'b0; wb_rmh <= 1'b0;
        commit <= 1'b0; ip_first <= 16'd0; nmi_q <= 1'b0; nmi_pend <= 1'b0; xint <= 1'b0; xinta <= 1'b0;
        brk <= 1'b0; brk_wait <= 1'b0; tf_s <= 1'b0; lock_v <= 1'b0; ret_ip <= 16'd0; ip_pfx <= 16'd0;
        u_q <= '0; u_rd <= '0; u_wr <= '0; u_io <= '0; u_susp <= '0; u_corr <= '0; u_flush <= '0; u_far <= '0;
        u_r2 <= '0; u_wb <= '0; u_byte <= '0; u_ld <= '0; u_loop <= '0; u_dec <= '0; u_inta <= '0; u_halt <=
        '0; u_hlt <= '0; u_mds <= '0; u_mdc <= '0; u_mdi <= '0; u_mdp <= '0; u_mdw <= '0; u_cf <= '0; u_ec <=
        '0; u_qd <= '0; u_a <= '0; u_wd <= '0; u_jv <= '0; u_endr <= 1'b0; u_qp <= 1'b0; u_fw <= 1'b0; u_fgo <= 1'b0; u_efl <= 1'b0; u_wfl <= 1'b0; u_pre <= 1'b0; u_qw <= 1'b0; u_pp <= 1'b0; u_pi <= 1'b0; u_bx <= 1'b0; u_ws <= 3'd0; efl_d <= 1'b0;
        s1a <= 32'd2; {v_q, v_bus, v_susp, v_loop, v_mdi, v_mdw} <= 6'd0; v_pl <= 1'b1;
        wb_lo <= 8'd0; wb_hi <= 8'd0; wb_bh <= 1'b0; {wb_ralu, wb_rmem, wb_rimm, wb_rtmp, wb_rx} <= 5'd0; wb_x <= 16'd0;
        wb2_ax <= 1'b0; wb2_dx <= 1'b0; wb2_x <= 16'd0; wbs_en <= 4'd0; wbs_mem <= 1'b0; wbs_tmp2 <= 1'b0; wbs_x <= 16'd0;
        wbf_en <= 1'b0; wbf_alu <= 1'b0; wbf_mem <= 1'b0; wbf_kc <= 1'b0; wbf_x <= 9'd0; wbf_tst <= 1'b0; wbf_cmp <= 1'b0;
        wsp_en <= 1'b0; wsp_v <= 16'd0; wspc_en <= 1'b0; wspc_v <= 16'd0;
        c_n <= 1'b0; ci_x <= 1'b0; ci_m <= 1'b0; c_t <= 1'b0; wbv1 <= 1'b0; wbv2 <= 1'b0; fw_en <= 1'b0; fti_clr <= 1'b0; fw_v <= 9'd0;
        wsi_en <= 1'b0; wdi_en <= 1'b0; wcx_en <= 1'b0; wsi_v <= 16'd0; wdi_v <= 16'd0; wcx_v <= 16'd0;
        md_a <= 16'd0; md_b <= 16'd0; md_d <= 16'd0; md_neg <= 1'b0; md_rneg <= 1'b0; md_ssq <= 1'b0; md_mnq <= 1'b0; wq <= 2'd0; md_err <= 1'b0; wcnt <= 8'd0;
        alu_q <= 16'd0; {alu_oq, alu_aq, alu_cq} <= 3'd0; md_f <= 5'd0; md_first <= 1'b0; md_qmsb <= 1'b0; md_fitq <= 1'b0; md_fl <= 6'd0;
        r <= '0;
        sr <= {16'd0, 16'd0, 16'hFFFF, 16'd0}; ip <= 16'd0;
        {f_c, f_p, f_a, f_z, f_s, f_t, f_i, f_d, f_o} <= 9'd0;
    end else if (ce) begin
        if (q_pop) ip <= ip + 16'd1;
        if ((st != S_EX) | u_done) begin
            s1a <= n_jv ? n_j1 : {d_s1[30:0], 1'b0};
            // a step waits for at most one of these (queue byte, bus cycle, suspend, shift loop, MD loop, MD wait)
            v_q <= n_q; v_bus <= n_rd | n_wr | (n_corr & ~NEC) | n_inta | n_halt; v_susp <= NEC ? (n_fgo & ~n_rd & ~n_wr) : n_susp; v_loop <= n_loop;
            v_mdi <= n_mdi; v_mdw <= n_mdw;
            v_pl <= ~(n_q | n_rd | n_wr | (n_corr & ~NEC) | n_inta | n_halt | (NEC ? (n_fgo & ~n_rd & ~n_wr) : n_susp) | n_loop | n_mdi | n_mdw);
            u_q <= n_q; u_rd <= n_rd; u_wr <= n_wr; u_io <= n_io; u_susp <= n_susp; u_corr <= n_corr; u_flush
            <= n_flush; u_far <= n_far; u_r2 <= n_r2; u_wb <= n_wb; u_byte <= n_byte; u_ld <= n_ld; u_loop <=
            n_loop; u_dec <= n_dec; u_inta <= n_inta; u_halt <= n_halt; u_hlt <= n_hlt; u_mds <= n_mds; u_mdc
            <= n_mdc; u_mdi <= n_mdi; u_mdp <= n_mdp; u_mdw <= n_mdw; u_cf <= n_cf; u_ec <= n_ec; u_qd <=
            n_qd; u_a <= n_a; u_wd <= n_wd; u_jv <= n_jv; u_endr <= n_end; u_qp <= n_qp; u_fw <= n_fw; u_fgo <= n_fgo; u_efl <= n_efl; u_wfl <= n_wfl; u_pre <= n_pre; u_qw <= n_qw; u_pp <= n_pp; u_pi <= n_pi; u_bx <= n_bx; u_ws <= n_ws;
        end
        alu_q <= alu_r;
        {alu_oq, alu_aq, alu_cq} <= {alu_o, alu_a, alu_c};
        ac3q <= aa[3] | ab[3];
        c80q <= c80f ^ e_cn[0];
        nmi_q <= nmi;
        if (nmi & ~nmi_q) nmi_pend <= 1'b1;

        case (st)
            S_OP: begin
                if (commit) begin
                    commit <= 1'b0;
                    rep_v <= 1'b0;
                end
                if (commit) begin
                    xint <= 1'b0;
                    lock_v <= 1'b0;
                end
                if (take) begin
                    st <= S_EX; op <= 8'hCD; k1 <= k_one << K_INT; w <= 1'b1; has_modrm <= 1'b0; xint <= 1'b1; tf_s <= f_t; brk <= 1'b0; brk_wait <= 1'b0;
                    xinta <= 1'b0; ret_ip <= brk ? ip_pfx : brk_wait ? ip_first : ip;
                    if (t_nmi | (brk & nmi_pend)) begin vec <= 8'd2; nmi_pend <= 1'b0; end
                    else if (t_intr | brk | brk_wait) xinta <= 1'b1;
                    else vec <= 8'd1;
                    if (E8) begin
                        e8 <= 1'b0; e_hm <= 1'b0; e_st <= 1'b0; e_nf <= 1'b0; e_cy <= 1'b0; e_psw <= 1'b0; e_abs <= 1'b0; e_cc <= 1'b0;
                        e_daa <= 1'b0; e_rst <= 1'b0; e_acm <= 2'd0; e_eas <= 2'd0; e_calln <= 1'b0; e_retem <= 1'b0; e_brkem <= 1'b0;
                    end
                end else if (q_avail) begin
                    op <= e8n ? t_op : q_byte;
                    k1 <= k_one << hcls_e;
                    w <= e8n ? w_nec(t_cls, t_op) : NEC ? w_nec(hcls, q_byte) : w_of(hcls, q_byte);
                    has_modrm <= e8n ? 1'b0 : NEC ? hm_nec(hcls) : hm_of(hcls);
                    ip_first <= ip;
                    if (E8) begin
                        e8 <= ~md; e_hm <= e8n & hm_nec(t_cls); e_st <= e8n & t_st; e_nf <= e8n & t_nf; e_cy <= e8n & t_cy; e_psw <= e8n & t_psw;
                        e_abs <= e8n & t_abs; e_cc <= e8n & t_cc; e_daa <= e8n & t_daa; e_rst <= e8n & t_rst;
                        e_acm <= e8n ? t_acm : 2'd0; e_eas <= e8n ? t_eas : 2'd0; e_cn <= q_byte[5:3];
                        e_calln <= 1'b0; e_retem <= 1'b0; e_brkem <= 1'b0;
                        e_mrm <= t_mrm;
                    end
                    if (hcls_e == K_PFX) begin
                        ip_pfx <= ip;
                        if (q_byte[7:1] == 7'b1111_000) lock_v <= 1'b1;
                        st <= S_PFX;
                        if (q_byte[7:5] == 3'b001) begin ovr_v <= 1'b1; ovr_s <= q_byte[4:3]; end
                        if (q_byte[7:1] == 7'b1111_001) begin rep_v <= 1'b1; rep_z <= q_byte[0]; rep_c <= 1'b0; end
                        if (NEC & (q_byte[7:1] == 7'b0110_010)) begin rep_v <= 1'b1; rep_z <= q_byte[0]; rep_c <= 1'b1; end
                    end else if (NEC & (hcls_e == K_X0F)) begin st <= S_X0F; ph <= 2'd0; end
                    else st <= S_DEC;
                end
            end
            S_PFX: st <= S_OP;
            S_X0F: if (NEC) begin                   // NEC: second opcode byte (QS "subsequent"), one clock after 0F
                if (ph == 2'd0) ph <= 2'd1;
                else if (q_avail) begin
                    op <= q_byte; w <= q_byte[0]; has_modrm <= (q_byte[7:4] != 4'h2) | q_byte[3]; st <= S_DEC;
                    if (E8 & (e8 | (q_byte == 8'hFF))) begin    // 8080 ED ED (CALLN) / ED FD (RETEM); native 0F FF (BRKEM)
                        e8 <= 1'b0; e_hm <= 1'b0; w <= 1'b1; has_modrm <= 1'b0;
                        if (~e8 | (q_byte == 8'hED)) begin op <= 8'hCD; k1 <= k_one << K_INT; e_brkem <= ~e8; e_calln <= e8; end
                        else if (q_byte == 8'hFD) begin op <= 8'hCF; k1 <= k_one << K_IRET; e_retem <= 1'b1; end
                        else begin op <= 8'h90; k1 <= k_one << K_XCHGA; end
                    end
                end
            end else st <= S_OP;
            S_DEC: begin
               
                tf_s <= f_t;
                cnt <= 4'd0;
                ismem <= 1'b0;
                if (op == 8'hCC) vec <= 8'd3;
                if (op == 8'hCE) vec <= 8'd4;
                if (!has_modrm & ~e8h) begin
                    if (empty_body) begin st <= S_OP; commit <= 1'b1; ovr_v <= 1'b0; end
                    else st <= S_EX;
                end else if (mav) begin
                    mrm <= mb;
                    if (mb[7:6] == 2'b11) begin
                        if (empty_body) begin st <= S_OP; commit <= 1'b1; ovr_v <= 1'b0; end
                        else st <= S_EX;
                    end else begin
                        st <= S_EA;
                        ismem <= 1'b1;
                        ph <= 2'd0;
                        if (mb[7:6] == 2'b00 && mb[2:0] == 3'd6) cnt <= 4'd1;
                        else if (mb[7:6] == 2'b00) cnt <= mb[2] ? 4'd4 : (mb[1] ^ mb[0]) ? 4'd7 : 4'd6;
                        else cnt <= mb[2] ? 4'd3 : (mb[1] ^ mb[0]) ? 4'd6 : 4'd5;
                        if (NEC) begin              // V20 EA adder: no mode-dependent clocks
                            ph  <= ((mb[7:6] == 2'b10) | ((mb[7:6] == 2'b00) & (mb[2:0] == 3'd6))) ? 2'd1 : 2'd0;
                            cnt <= ((mb[7:6] == 2'b00) & (mb[2:0] != 3'd6)) ? 4'd2 : 4'd1;
                        end
                    end
                end
            end
            S_EA: if (NEC & nlea_end) begin st <= S_OP; commit <= 1'b1; ovr_v <= 1'b0; end
            else if (NEC) case (ph)
                // V20: disp8 at ModRM + 2, disp16 low at + 1, high 2 clocks later; a byte that has just arrived in an
                // empty queue is taken one clock later, except the disp16 low byte; the address 2 clocks after the last
                // MOV r/m, imm: the immediate follows in the last clock (low byte) and the next (high byte)
                2'd0: if (nim) begin
                        if (~w | q_avail) begin if (w) imm[15:8] <= q_byte; nim <= 1'b0; st <= S_EX; cnt <= 4'd0; end
                    end else if (cnt != 4'd1) cnt <= cnt - 4'd1;
                    else if (!(mod == 2'd0 && rm != 3'd6)) ph <= 2'd1;
                    else if (!nea_imm) begin st <= S_EX; cnt <= 4'd0; end
                    else if (q_avail) begin imm[7:0] <= q_byte; nim <= 1'b1; ph <= 2'd0; end
                2'd1: if ((mod == 2'd1) ? q_old : q_avail) begin
                        disp <= {8'd0, q_byte}; ph <= 2'd2; cnt <= (mod == 2'd1) ? 4'd1 : 4'd2;
                    end
                2'd2: if (cnt != 4'd1) cnt <= cnt - 4'd1;
                    else if (mod != 2'd1) begin if (q_old) begin disp[15:8] <= q_byte; ph <= 2'd3; end end
                    else if (!nea_imm) begin st <= S_EX; cnt <= 4'd0; end
                    else if (q_avail) begin imm[7:0] <= q_byte; nim <= 1'b1; ph <= 2'd0; end
                default: if (!nea_imm) begin st <= S_EX; cnt <= 4'd0; end
                    else if (q_avail) begin imm[7:0] <= q_byte; nim <= 1'b1; ph <= 2'd0; end
            endcase else case (ph)
                2'd0: if (cnt != 4'd1) cnt <= cnt - 4'd1;
                    else if (mod == 2'd0 && rm != 3'd6) begin st <= S_EX; cnt <= 4'd0; end
                    else ph <= 2'd1;
                2'd1: if (q_avail) begin disp <= {8'd0, q_byte}; ph <= 2'd2; end
                2'd2: if (!ea_two || q_avail) begin
                        if (ea_two) disp[15:8] <= q_byte;
                        ph <= 2'd3;
                        cnt <= (mod == 2'd0) ? 4'd2 : 4'd3;
                    end
                default: if (cnt != 4'd1) cnt <= cnt - 4'd1;
                    else begin st <= S_EX; cnt <= 4'd0; end
            endcase
            S_EX: if (u_done) begin
                if (u_q) case (u_qd)
                    Q_LO:  imm[7:0] <= q_byte;
                    Q_HI:  imm[15:8] <= q_byte;
                    Q_SX:  imm <= {{8{q_byte[7]}}, q_byte};
                    Q_ZX:  imm <= {8'd0, q_byte};
                    Q_SLO: tmp2[7:0] <= q_byte;
                    Q_SHI: tmp2[15:8] <= q_byte;
                    default: vec <= q_byte;
                endcase
                if (u_rd) begin if (u_r2) tmp2 <= rdata; else mem <= rdata; end

                if (u_wb & ~kk[K_ENTER]) tmp <= rm_val;
                if (u_flush & ~NEC) begin ip <= flush_ip; if (u_far) sr[1] <= tmp2; end
                if (u_corr) tmp <= req_corr;
                if (u_inta) vec <= rdata[15:8];
                if (u_ld) begin
                    tmp <= kk[K_ENTER] ? (NEC ? spn_v : sp_f) : (NEC & kk[K_X0F]) ? tmp : rm_val;
                    lc <= kk[K_POPA] ? 8'd7 : kk[K_PUSHA] ? 8'd0 : kk[K_ENTER] ? tmp2[7:0] - 8'd1 :
                          kk[K_SHIFTI] ? imm[7:0] : (NEC & k1[K_ESC]) ? 8'd48 : (NEC & kk[K_X0F]) ? bf_lcf : (NEC & (k1[K_STR] | kk[K_INSOUT])) ? 8'd7 : r[1][7:0];
                end
                if ((kk[K_PUSHA] | kk[K_POPA]) & (u_rd | u_wr)) lc <= kk[K_POPA] ? lc - ((NEC & (lc == 8'd5)) ? 8'd2 : 8'd1) : lc + 8'd1;
                if (kk[K_ENTER] & u_wb) lc <= lc - 8'd1;
                if (u_mds) begin
                    lc <= md_w ? 8'd16 : 8'd8;
                    md_neg <= md_sa ^ md_ss ^ (md_div & rep_v & ~NEC);  // 8088: a REP prefix inverts the IDIV quotient
                    md_rneg <= md_sa;
                    md_ssq <= md_ss;
                    md_mnq <= md_mneg;
                    md_d <= md_aad ? {8'd0, ah} : md_sm;
                    md_err <= 1'b0;
                    if (md_div) begin
                        md_a <= md_aam ? 16'd0 : md_nh;
                        md_b <= md_aam ? {8'd0, al} : md_nm[15:0];
                    end else begin
                        md_a <= 16'd0;
                        md_b <= md_aad ? {8'd0, NEC ? ah10 : imm[7:0]} : md_am;   // NEC AAD: AH * 10, no loop
                    end
                end
                if (u_mdc & md_div) begin
                    md_err <= md_pre & ~(NEC & md_aam);        // V20 AAM 0: no divide error (AH = FF, AL kept)
                    md_f <= {md_pfl[4], md_pfl[1], md_pfl[2], md_pfl[8], md_pfl[3]};
                end
                if (u_mdp) begin
                    md_first <= 1'b1;
                    md_qmsb <= md_w ? md_q0[15] : md_q0[7];
                    md_fitq <= md_sgn ? (md_w ? (md_hi == {16{md_lo[15]}}) : (md_hi[7:0] == {8{md_lo[7]}})) : (md_hi == 16'd0);
                    if (md_div) begin md_a <= md_rm; md_b <= md_q; end
                    else begin md_a <= md_hi; md_b <= md_lo; end
                    if (NEC & md_div & md_sgn) md_f <= {md_qmb, ~^md_q0[7:0], 2'b00, md_q0 == 16'd0};
                    if (NEC & md_aam) md_fl <= md_flc;          // V20 AAM: no wait clock to register the flags in
                    if (md_div & md_qovf) begin
                        md_err <= 1'b1;
                    end
                end
                if (kk[K_BOUND] & (u_ec == E_NOF) & bnd_out) begin
                    op <= 8'hCD; k1 <= k_one << K_INT; w <= 1'b1; has_modrm <= 1'b0; xint <= 1'b1; xinta <= 1'b0; vec <= 8'd5; ret_ip <= ip;
                end
                if (u_mdw & md_err) begin                  // divide error: continue as INT 0
                    op <= 8'hCD; k1 <= k_one << K_INT; w <= 1'b1; has_modrm <= 1'b0; xint <= 1'b1; xinta <= 1'b0; vec <= 8'd0; ret_ip <= ip; md_err <= 1'b0;
                end
                if (u_end) begin
                    st <= S_OP; commit <= 1'b1; ovr_v <= 1'b0;
                    // MD: interrupt entries (INT, NMI, CALLN) leave native mode set, BRKEM clears it and enables its
                    // writes; RETI / POP PSW restore it only while enabled, RETEM always and disables (UM 12-151,
                    // 12-168, 12-169, 12-176, 12-177)
                    if (E8 & k1[K_INT]) begin md <= ~e_brkem; if (e_brkem) mdwe <= 1'b1; end
                    if (E8 & (k1[K_IRET] | k1[K_POPF]) & (mdwe | e_retem)) md <= rdata[15];
                    if (E8 & e_retem) mdwe <= 1'b0;
                    brk <= (k1[K_STR] | kk[K_INSOUT]) & rep_v & u_jv;
                    brk_wait <= k1[K_WAIT] & u_jv;
                end
            end else if (u_mdw) begin
                md_first <= 1'b0;
                md_fl <= md_flc;
            end else if (u_loop & ~(NEC & (k1[K_STR] | kk[K_INSOUT] | k1[K_ESC] | kk[K_X0F]))) begin
                cnt <= cnt + 4'd1;
                if ((cnt == 4'd3) | NEC) begin
                    cnt <= 4'd0;
                    lc <= lc - 8'd1;
                    tmp <= sh_v;
                end
            end
            default: st <= S_OP;
        endcase

        // NEC REP string ops: lc counts the clocks to the earliest end
        if (NEC & (st == S_EX) & (k1[K_STR] | kk[K_INSOUT] | k1[K_ESC] | (kk[K_X0F] & (x0f_bf | x0f_4s))) & ~(u_done & u_ld) & (lc != 8'd0)) lc <= lc - 8'd1;

        // NEC 0F 20-3B: pointers, BCD carry, computed word
        if (NEC & (st == S_EX) & u_done & kk[K_X0F]) begin
            if (u_pp) begin pd <= (op[4] & op[1]) ? r[6] : r[7]; c4 <= 1'b0; z4 <= 1'b0; if (x0f_4s) begin imm <= r[6]; tmp[15:8] <= bf_cl1[8:1]; end end
            if (u_pi) begin pd <= pd + (op[4] ? 16'd2 : 16'd1); if (x0f_4s) begin imm <= imm + 16'd1; tmp[15:8] <= tmp[15:8] - 8'd1; end end
            if (u_bx) begin
                if (x0f_4s) begin tmp[7:0] <= bxv[7:0]; c4 <= bxc; z4 <= z4 | (bxv[7:0] != 8'd0); end
                else tmp <= bxv;
            end
        end
        bf_o <= bf_rm4;
        bf_l <= bfn_l;

        // NEC: flush (ip, CS) whenever it happens in the step; the early-flush flag lives to the instruction's end
        if (NEC & (st == S_EX)) begin
            if (flush) begin ip <= flush_ip; if (u_far) sr[1] <= tmp2; efl_d <= 1'b1; end
            if (u_done & u_end) efl_d <= 1'b0;
        end
        qw_t <= NEC & bus_t4;
        if (qw_pop & q_avail) begin tmp2[7:0] <= q_byte; qw_got <= 1'b1; end
        if (u_done | reset) qw_got <= 1'b0;

        // MUL / DIV wait counter: loaded in the pre-check step from the signs registered in the setup step, then
        // counted by the loop (a quotient bit's clocks one clock later, wq), the post step and the wait step
        if (st == S_EX) begin
            if (u_mdc) begin
                wcnt <= (md_div & md_pre & ~(NEC & md_aam)) ? md_ebase + {7'd0, ismem} :
                        md_base + {7'd0, ismem & ~(NEC & kk[K_IMULI])} - {7'd0, ~NEC & ~md_div & md_mnq};
                wq <= 2'd0;
            end else if (u_mdp) wcnt <= NEC ? wcnt - {7'd0, md_div & md_qovf & ~md_w} :
                                      wcnt + {6'd0, wq} - ((md_div & md_qovf) ? 8'd3 : 8'd0);
            else if (u_mdi & ~md_err) wcnt <= NEC ? wcnt : wcnt + (md_div ? {6'd0, wq} : {7'd0, md_b[0]});
            else if (u_mdw) wcnt <= NEC ? wcnt - 8'd1 :
                                   wcnt - {7'd0, ~(md_first & ~md_div & ~md_aad & md_fitq)};  // MUL: +1 if the high half is redundant
        end
        if ((st == S_EX) & u_mdi & ~md_err) begin
                lc <= lc - 8'd1;
                if (md_div) begin
                    md_a <= md_qb ? md_sum[15:0] : md_rs[15:0];
                    md_b <= md_w ? {md_b[14:0], md_qb} : {8'd0, md_b[6:0], md_qb};
                    if (!md_top & ~NEC) md_f <= {md_dsf, ~^md_sum[7:0], md_rs[4] ^ md_d[4] ^ md_sum[4], md_dof,
                                         md_w ? (md_sum[15:0] == 16'd0) : (md_sum[7:0] == 8'd0)};
                    wq <= !md_last ? {1'b0, ~md_top & md_qb} : md_top ? 2'd2 : md_qb ? 2'd3 : 2'd0;
                end else begin
                    md_a <= md_w ? md_sum[16:1] : {8'd0, md_sum[8:1]};
                    md_b <= md_w ? {md_sum[0], md_b[15:1]} : {8'd0, md_sum[0], md_b[7:1]};
                end
        end

        // write-back: controls and values are taken every clock; wbv1 / wbv2 say the clock was one that decides them
        wbv1 <= fin;
        wbv2 <= ((st == S_EX) & u_done & (u_wb | u_dec)) | (NEC & (st == S_DEC) & k1[K_XCHG] & mav & (mb[7:6] == 2'b11));
        c_n <= ~seg_ld; c_t <= ~seg_ld & ~k1[K_WAIT];
        ci_x <= ~seg_ld & (op != 8'hFB) & ~k1[K_IRET] & ((cm_f & (cm_fs == F_X)) ? cm_fv[6] : (cm_f & (cm_fs == F_MEM)) ? 1'b0 : f_i);
        ci_m <= ~seg_ld & (op != 8'hFB) & ~k1[K_IRET] & cm_f & (cm_fs == F_MEM);
        wb_lo <= {8{cm_r & (cm_rw | ~cm_ri[2])}} & (8'd1 << (cm_rw ? cm_ri : {1'b0, cm_ri[1:0]}));
        wb_hi <= {8{cm_r & (cm_rw | cm_ri[2])}} & (8'd1 << (cm_rw ? cm_ri : {1'b0, cm_ri[1:0]}));
        wb_bh <= ~cm_rw & cm_ri[2];
        wb_ralu <= cm_rs == R_ALU; wb_rmem <= cm_rs == R_MEM; wb_rimm <= cm_rs == R_IMM; wb_rtmp <= cm_rs == R_TMP; wb_rsh <= cm_rs == R_SH; wb_rrm <= cm_rs == R_RM; wb_rreg <= cm_rs == R_REG;
        wb_rnot <= k1[K_GRP3] & ~reg_[2] & ~reg_[0]; wb_rbcd <= k1[K_BCD]; wbf_bcd <= k1[K_BCD]; wb_f8 <= bcd_f8; sho <= rm_val_e; reo <= reg_val_e;
        if (st == S_EA) begin ebq <= (E8 & (e_eas != 2'd0)) ? ea80 : ea_base; eaq <= ebq + ea_d; end
        xlq <= r[3] + {8'd0, al};
        aopq <= aop_e; g3t <= k1[K_GRP3] & (reg_q[2:1] == 2'd0); a0q <= r[0];
        spq <= ((E8 & e_st) ? r[5] : r[4]) - 16'd2;     // 8080: DS0:BP stack
        md_w <= w & ~k1[K_AAM] & ~k1[K_AAD]; md_div <= k1[K_AAM] | (k1[K_GRP3] & mrm_e[4]); md_sgn <= (k1[K_GRP3] & mrm_e[3]) | kk[K_IMULI]; shi <= sh_var ? tmp : rm_val_e;
        wb_rx <= cm_rs == R_X; wb_x <= cm_rx;
        wb2_ax <= cm_d & ~cm_dx; wb2_dx <= cm_d & cm_dx; wb2_x <= cm_dv;
        wbs_en <= {4{cm_s}} & (4'd1 << cm_si);
        wbs_mem <= cm_ss == G_MEM; wbs_tmp2 <= cm_ss == G_TMP2; wbs_x <= cm_sv;
        wbf_en <= cm_f; wbf_alu <= cm_fs == F_ALU; wbf_mem <= cm_fs == F_MEM; wbf_kc <= cm_kc; wbf_x <= cm_fv;
        wbf_sh <= k_sh & ~sh_var;
        wbf_tst <= NEC & k1[K_ALURM] & op[7] & (st == S_DEC);
        wbf_e8 <= e8m; wbf_cy <= E8 & e_cy; wbf_acm <= e_acm; wbf_m8 <= E8 & e_psw; wb_rmh <= E8 & e_psw & k1[K_POPR];
        wbf_cmp <= NEC & k1[K_STR] & (op[3:1] == 3'd3);
        wspc_en <= cm_sp; wspc_v <= cm_spv;
        wsp_en <= (st == S_EX) & u_done & (u_a == A_STK) & (u_rd | u_wr); wsp_v <= u_wr ? sp_f - 16'd2 : sp_f + ((NEC & kk[K_POPA] & (lc == 8'd5)) ? 16'd4 : 16'd2);
        wbp_en <= E8 & e_st;
        wsi_en <= (st == S_EX) & u_done & (u_a == A_SI) & (u_rd | u_wr);  wsi_v <= r[6] + str_d;
        wdi_en <= (st == S_EX) & u_done & (u_a == A_DI) & (u_rd | u_wr);  wdi_v <= r[7] + str_d;
        wcx_en <= (st == S_EX) & u_done & u_dec;                          wcx_v <= cx_dec;
        // flags written by a step: applied in the next clock, before an instruction's own write-back
        fw_en <= ((st == S_EX) & u_done & (u_cf | (u_mdc & md_div & md_pre) | (u_mdp & md_div & md_qovf))) |
                 ((st == S_EX) & ~u_done & ~u_mdw & u_loop & ((cnt == 4'd3) | NEC) & ~(NEC & (k1[K_STR] | kk[K_INSOUT] | k1[K_ESC] | kk[K_X0F])));
        fw_v <= u_cf ? {alu_fq[5], f_d, f_i, f_t, alu_fq[4:0]} : u_mdc ? md_pfl :
                u_mdp ? (NEC ? {1'b0, f_d, f_i, f_t, md_qmb, md_q0 == 16'd0, 1'b0, ~^md_q0[7:0], 1'b0}
                             : {md_f[1], f_d, f_i, f_t, md_f[4], md_f[0], md_f[2], md_f[3], 1'b0}) : sh_fl;
        fti_clr <= (st == S_EX) & u_done & (u_wd == D_FL) & k1[K_INT] & ~(E8 & (e_calln | e_brkem));   // CALLN / BRKEM keep IE, BRK
        if (wsp_en) begin if (E8 & wbp_en) r[5] <= wsp_v; else r[4] <= wsp_v; end
        if (wbv1 & wspc_en) r[4] <= wspc_v;
        if (wsi_en) r[6] <= wsi_v;
        if (wdi_en) r[7] <= wdi_v;
        if (wcx_en) r[1] <= wcx_v;
        for (int k = 0; k < 8; k++)
            if (wb_on & (wb_lo[k] | wb_hi[k])) r[k] <= {wb_hi[k] ? (wb_bh ? wb_v[7:0] : wb_v[15:8]) : r[k][15:8],
                                                        wb_lo[k] ? wb_v[7:0] : r[k][7:0]};
        if (wbv1 & wb2_ax) r[0] <= wb2_x;
        if (wbv1 & wb2_dx) r[2] <= wb2_x;
        for (int k = 0; k < 4; k++) if (wbv1 & wbs_en[k]) sr[k] <= wbs_v;
        if (fw_en) {f_o, f_d, f_i, f_t, f_s, f_z, f_a, f_p, f_c} <= fw_v;
        if (fti_clr) begin f_t <= 1'b0; f_i <= 1'b0; end
        if (wbv1 & wbf_en) begin                // 8080: V unchanged; DAD: CY only
            if (~(E8 & wbf_e8)) f_o <= wbf_v[8];
            {f_d, f_i, f_t} <= wbf_v[7:5];
            if (~(E8 & wbf_cy)) {f_s, f_z, f_a, f_p} <= wbf_v[4:1];
            f_c <= wbf_v[0];
        end

`ifdef X86SV_TESTLOAD
        if (tl_en) begin
            r <= tl_r; sr <= tl_s; ip <= tl_ip; ip_first <= tl_ip;
            {f_o, f_d, f_i, f_t, f_s, f_z} <= {tl_flags[11:6]};
            f_a <= tl_flags[4]; f_p <= tl_flags[2]; f_c <= tl_flags[0];
            st <= S_OP; commit <= 1'b0; ovr_v <= 1'b0; rep_v <= 1'b0; op <= 8'h90; nim <= 1'b0; k1 <= k_one << K_XCHGA; w <= 1'b1; has_modrm <= 1'b0; tf_s <= 1'b0;
            md <= tl_md; mdwe <= tl_mdwe; e8 <= 1'b0; e_hm <= 1'b0;
        end
`endif
    end
end

// step pre-delay counter (EXT only)
generate if (EXT) begin : g_dly
    logic [4:0] dlc;
    always_ff @(posedge clk) begin
        if (reset) dlc <= 5'd0;
        else if (ce) begin
            if ((st != S_EX) | u_done) dlc <= n_dl + {4'd0, NEC & (st == S_EX) & u_qp & u_q & ~q_old};
            else if (dlc != 5'd0) dlc <= dlc - 5'd1;
`ifdef X86SV_TESTLOAD
            if (tl_en) dlc <= 5'd0;
`endif
        end
    end
    assign dly_on = (st == S_EX) & (dlc != 5'd0);
end else begin : g_nodly
    assign dly_on = 1'b0;
end endgenerate

endmodule


module x86sv #(
    parameter bit NEC = 1'b0,           // NEC V20 instruction set and timing
    parameter bit NEC8080 = 1'b0        // NEC: 8080 emulation mode (BRKEM / RETEM / CALLN)
) (
    input  logic        clk,
    input  logic        ce,             // one 8088 clock per pulse
    input  logic        reset,

    output logic [19:0] ad,             // AD19-AD0 as the pins carry them this clock
    output logic        ale,
    output logic  [2:0] s20,            // S2-S0 (3'b111 passive)
    output logic  [2:0] tstate,         // 0 Ti 1 T1 2 T2 3 T3 4 T4 5 Tw
    output logic  [1:0] seg_s,          // S4-S3 (valid when seg_v)
    output logic        seg_v,
    output logic        rd,             // 8288 MRDC / IORC
    output logic        wra,            // 8288 AMWC / AIOWC
    output logic        wr,             // 8288 MWTC / IOWC
    output logic        io,
    output logic        inta,           // 8288 INTA command
    output logic  [7:0] dout,
    input  logic  [7:0] din,
    input  logic        ready,
    input  logic        intr,
    input  logic        nmi,
    input  logic        test_n,
    output logic        lock,           // LOCK (active high)
    output logic  [1:0] qs,             // QS1-QS0
    output logic  [7:0] qs_byte,        // byte taken from the queue (debug)

    output logic [15:0] dbg_ip,
    output logic [15:0] dbg_flags,
    output logic [7:0][15:0] dbg_r,     // AX CX DX BX SP BP SI DI
    output logic [3:0][15:0] dbg_s      // ES CS SS DS

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [7:0][15:0] tl_r,
    input  logic [3:0][15:0] tl_s,
    input  logic [15:0] tl_ip,
    input  logic [15:0] tl_flags,
    input  logic  [2:0] tl_qlen,
    input  logic [31:0] tl_queue,
    input  logic [19:0] tl_ad,
    input  logic        tl_md,          // MD (1 = native)
    input  logic        tl_mdwe,
    output logic        dbg_mdwe
`endif
);

logic        q_avail, q_old, q_pop, q_first;
logic  [7:0] q_byte;
logic        req, req_fast, req_pre, req_int, req_word, fgo, bus_idle, bus_t4, rel, susp, flush, susp_ok, if_flag, emu, lock_eu, lock_bus;
logic  [2:0] req_type;
logic  [1:0] req_sidx;
logic [15:0] req_segv, req_off, req_wdata, req_corr, rdata, flush_ip, cs;

x86sv_biu #(.NEC(NEC)) biu (
    .clk(clk), .ce(ce), .reset(reset),
    .eu_req(req), .eu_type(req_type), .eu_int(req_int), .eu_word(req_word), .eu_lock(lock_eu), .eu_fast(req_fast), .eu_pre(req_pre), .eu_sidx(req_sidx), .eu_segv(req_segv),
    .eu_off(req_off), .eu_wdata(req_wdata), .eu_corr(req_corr), .eu_rel(rel), .eu_rdata(rdata),
    .eu_susp(susp), .eu_flush(flush), .eu_flush_ip(flush_ip), .eu_fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok),
    .q_pop(q_pop), .q_first(q_first), .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .cs(cs), .if_flag(if_flag), .ps3(emu),
    .ad(ad), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v), .rd(rd), .wra(wra), .wr(wr),
    .io(io), .inta(inta), .lock_bus(lock_bus), .dout(dout), .din(din), .ready(ready), .qs(qs), .qs_byte(qs_byte)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_ip(tl_ip), .tl_qlen(tl_qlen), .tl_queue(tl_queue), .tl_ad(tl_ad)
`endif
);

x86sv_eu #(.NEC(NEC), .NEC8080(NEC8080)) eu (
    .clk(clk), .ce(ce), .reset(reset),
    .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .q_pop(q_pop), .q_first(q_first),
    .req(req), .req_fast(req_fast), .req_pre(req_pre), .req_type(req_type), .req_int(req_int), .req_word(req_word), .req_sidx(req_sidx), .req_segv(req_segv),
    .req_off(req_off), .req_wdata(req_wdata), .req_corr(req_corr), .rel(rel), .rdata(rdata),
    .susp(susp), .flush(flush), .flush_ip(flush_ip), .fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok), .cs(cs), .if_flag(if_flag), .lock(lock_eu), .emu(emu),
    .intr(intr), .nmi(nmi), .test_n(test_n),
    .dbg_ip(dbg_ip), .dbg_flags(dbg_flags), .dbg_r(dbg_r), .dbg_s(dbg_s)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_r(tl_r), .tl_s(tl_s), .tl_ip(tl_ip), .tl_flags(tl_flags), .tl_md(tl_md), .tl_mdwe(tl_mdwe),
    .dbg_mdwe(dbg_mdwe)
`endif
);

assign lock = lock_eu | lock_bus;

endmodule


module x86sv16 #(
    parameter bit NEC = 1'b0,           // NEC V30 instruction set and timing
    parameter bit NEC8080 = 1'b0        // NEC: 8080 emulation mode (BRKEM / RETEM / CALLN)
) (
    input  logic        clk,
    input  logic        ce,             // one 8088 clock per pulse
    input  logic        reset,

    output logic [19:0] ad,             // AD19-AD0 as the pins carry them this clock (bus-hold value when floating)
    output logic        bhe_n,          // BHE (as latched at T1)
    output logic        ale,
    output logic  [2:0] s20,            // S2-S0 (3'b111 passive)
    output logic  [2:0] tstate,         // 0 Ti 1 T1 2 T2 3 T3 4 T4 5 Tw
    output logic  [1:0] seg_s,          // S4-S3 (valid when seg_v)
    output logic        seg_v,
    output logic        rd,             // 8288 MRDC / IORC
    output logic        wra,            // 8288 AMWC / AIOWC
    output logic        wr,             // 8288 MWTC / IOWC
    output logic        io,
    output logic        inta,           // 8288 INTA command
    output logic [15:0] dout,
    input  logic [15:0] din,
    input  logic        ready,
    input  logic        intr,
    input  logic        nmi,
    input  logic        test_n,
    output logic        lock,           // LOCK (active high)
    output logic  [1:0] qs,             // QS1-QS0
    output logic  [7:0] qs_byte,        // byte taken from the queue (debug)

    output logic [15:0] dbg_ip,
    output logic [15:0] dbg_flags,
    output logic [7:0][15:0] dbg_r,     // AX CX DX BX SP BP SI DI
    output logic [3:0][15:0] dbg_s      // ES CS SS DS

`ifdef X86SV_TESTLOAD
   ,input  logic        tl_en,
    input  logic [7:0][15:0] tl_r,
    input  logic [3:0][15:0] tl_s,
    input  logic [15:0] tl_ip,
    input  logic [15:0] tl_flags,
    input  logic  [2:0] tl_qlen,
    input  logic [47:0] tl_queue,
    input  logic [19:0] tl_ad,
    input  logic        tl_bhe,
    input  logic        tl_md,          // MD (1 = native)
    input  logic        tl_mdwe,
    output logic        dbg_mdwe
`endif
);

logic        q_avail, q_old, q_pop, q_first;
logic  [7:0] q_byte;
logic        req, req_fast, req_pre, req_int, req_word, fgo, bus_idle, bus_t4, rel, susp, flush, susp_ok, if_flag, emu, lock_eu, lock_bus;
logic  [2:0] req_type;
logic  [1:0] req_sidx;
logic [15:0] req_segv, req_off, req_wdata, req_corr, rdata, flush_ip, cs;

x86sv_biu16 #(.NEC(NEC)) biu (
    .clk(clk), .ce(ce), .reset(reset),
    .eu_req(req), .eu_type(req_type), .eu_int(req_int), .eu_word(req_word), .eu_lock(lock_eu), .eu_fast(req_fast), .eu_pre(req_pre), .eu_sidx(req_sidx), .eu_segv(req_segv),
    .eu_off(req_off), .eu_wdata(req_wdata), .eu_corr(req_corr), .eu_rel(rel), .eu_rdata(rdata),
    .eu_susp(susp), .eu_flush(flush), .eu_flush_ip(flush_ip), .eu_fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok),
    .q_pop(q_pop), .q_first(q_first), .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .cs(cs), .if_flag(if_flag), .ps3(emu),
    .ad(ad), .bhe_n(bhe_n), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v), .rd(rd), .wra(wra), .wr(wr),
    .io(io), .inta(inta), .lock_bus(lock_bus), .dout(dout), .din(din), .ready(ready), .qs(qs), .qs_byte(qs_byte)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_ip(tl_ip), .tl_qlen(tl_qlen), .tl_queue(tl_queue), .tl_ad(tl_ad), .tl_bhe(tl_bhe)
`endif
);

x86sv_eu #(.BUS16(1'b1), .NEC(NEC), .NEC8080(NEC8080)) eu (
    .clk(clk), .ce(ce), .reset(reset),
    .q_avail(q_avail), .q_old(q_old), .q_byte(q_byte), .q_pop(q_pop), .q_first(q_first),
    .req(req), .req_fast(req_fast), .req_pre(req_pre), .req_type(req_type), .req_int(req_int), .req_word(req_word), .req_sidx(req_sidx), .req_segv(req_segv),
    .req_off(req_off), .req_wdata(req_wdata), .req_corr(req_corr), .rel(rel), .rdata(rdata),
    .susp(susp), .flush(flush), .flush_ip(flush_ip), .fgo(fgo), .bus_idle(bus_idle), .bus_t4(bus_t4), .susp_ok(susp_ok), .cs(cs), .if_flag(if_flag), .lock(lock_eu), .emu(emu),
    .intr(intr), .nmi(nmi), .test_n(test_n),
    .dbg_ip(dbg_ip), .dbg_flags(dbg_flags), .dbg_r(dbg_r), .dbg_s(dbg_s)
`ifdef X86SV_TESTLOAD
   ,.tl_en(tl_en), .tl_r(tl_r), .tl_s(tl_s), .tl_ip(tl_ip), .tl_flags(tl_flags), .tl_md(tl_md), .tl_mdwe(tl_mdwe),
    .dbg_mdwe(dbg_mdwe)
`endif
);

assign lock = lock_eu | lock_bus;

endmodule

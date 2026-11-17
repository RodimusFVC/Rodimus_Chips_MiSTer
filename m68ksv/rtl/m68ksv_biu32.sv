// Copyright (C) 2026 Rodimus
// m68ksv: bus interface unit for the 68020 / 68EC020 32-bit bus with dynamic bus sizing. The execution unit asks for
// byte / word accesses at any alignment (instruction fetches: words at even addresses) as on the 68000 (DESIGN.md 1),
// and for a long operand once (field lw: the first half of the pair carries it, see below); this unit runs each access
// as one or more physical cycles: SIZ = the operand bytes still to transfer, DSACK1 / DSACK0 tell the port width (32 /
// 16 / 8 bits, or wait) and the remaining bytes follow in further cycles, back to back, while the execution unit stays
// held at its cycle's second micro-word. Every cycle is asynchronous (the 68020 has no STERM, User's Manual Table 3-2;
// the STERM_n input is ignored since checkpoint 5). Write data goes out through the 68020
// multiplexer (every byte lane the port could use carries its byte); read data is taken from the lanes of the port
// that answered. BERR (with HALT: re-run) as the 68000 BIU. Interrupt acknowledge: a byte read at $FFFFFFF1 |
// level << 1 in CPU space, AVEC = autovector.
//
// 68020 cycle timing (checked against the MC68020 User's Manual in checkpoint 5, page numbers of docs/MC68020UM.pdf's
// manual; the 68020 build runs one micro-cycle per CPU clock: e0 on the rising edge, e1 one clk later, e2 on the falling
// edge, e3 one clk later - m68ksv.sv): S0 = the rising edge that starts the cycle (e0; address, SIZ, FC, R/W valid from
// e1, ECS / OCS from e1 to the falling edge - the manual: from S0, 5.1.1 p. 5-2, so a quarter clock late), S1 = the
// falling edge (AS; a read's DS; a write's DBEN: 5.1.3 - 5.1.6 p. 5-3 / 5-4), S2 = the next rising edge (a read's DBEN,
// the write data: 5.3.1 / 5.3.2 p. 5-31 / 5-38), S3 = the next falling edge (a write's DS). Termination: DSACK1 / DSACK0,
// AVEC and BERR sampled on falling edges from the end of S2 (data latched one clock later, on the falling edge that
// starts S5, AS / DS / a read's DBEN negated there: three clocks, 5.2.6 p. 5-24), wait states in whole clocks; BERR
// one clock after DSACK (at the latching edge) is a late bus error (Table 5-8 case 4, p. 5-54 / 5-56). The execution
// unit's second micro-word starts (e1) one clk after the rising edge before the latching edge, so its e2 / e3 take the
// data. A follow-on cycle of a sized access starts on the next rising edge (back to back).
//
// Long operands: a read of the high word of a long operand (lw_i, from the EU: read destination = the high half) runs one
// long access (SIZ = 4, sized by the port) and keeps the low word, which the following read at that address + 2 takes
// with no bus cycle (an internal cycle, the timing of a zero-wait synchronous one); with the cache off, an instruction
// fetch at a long-aligned address is a long access the same way (the next fetch, at + 2, takes the held word). Any other
// access drops the held word. Long writes stay two word requests (REPORT.md "Checkpoint 4b": the EU forms the two halves
// of a written long in different micro-words).
//
// Instruction cache (68020 User's Manual 4.1 p. 4-1 / 4-2, checked in checkpoint 5; Musashi m68ki_ic_readimm16): 64 long-word lines, direct
// mapped by A7-A2, tag = A31-A8 and FC2, a valid bit per line. With the cache on (CACR E = 1, CDIS negated) every
// instruction fetch is a long access at the aligned long address: a hit runs as an internal cycle (ECS / OCS only, no AS,
// the timing of a zero-wait synchronous cycle), a miss as a bus read of the long (SIZ = 0, dynamic sizing) that fills the
// line unless the cache is frozen (CACR F) or the read ended with a bus error. CACR C clears the cache, CE the line CAAR
// selects. Data writes do not update it (as the 68020).
// Oracles: the MC68020 User's Manual (docs/MC68020UM.pdf, bus: section 5; checkpoint 5) and MAME's Musashi m68020 (data
// placement of misaligned accesses). Own code.

module m68ksv_biu32 (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen_p, cen_n,     // raw CPU clock edges (input sampling, physical cycle timing)
    input  logic        e0, e1, e2, e3,
    input  logic  [1:0] ph,
    // from the execution unit
    input  logic        go,
    input  logic  [2:0] op,               // m68ksv_upkg::BUS_*
    input  logic        byte_i,
    input  logic        lw_i,             // this read is the high word of a long operand (high word first)
    input  logic        rmc_i,            // read-modify-write hold (CAS / CAS2: RMC from the read to the write)
    input  logic        lock_i,           // inside the locked sequence (registered in the EU)
    input  logic [31:0] addr,             // registered by the EU at e1
    input  logic [15:0] dout,             // registered by the EU at e2 (a byte on both halves)
    input  logic        abort,            // address error (odd instruction fetch): no bus cycle
    input  logic        fc2,              // FC2 of the cycle (supervisor): part of the cache tag
    // instruction cache control (m68ksv_eu: CACR / CAAR)
    input  logic  [1:0] cc_cacr,          // E, F
    input  logic        cc_clr,           // clear all lines
    input  logic        cc_ce,            // clear the line cc_idx
    input  logic  [5:0] cc_idx,
    input  logic        cdis_n,           // CDIS pin: cache disabled while low
    output logic [15:0] din,
    output logic        dv,
    output logic        iack_av,
    output logic        iack_sp,
    output logic        berr_cyc,         // the access ended with a bus error (registered at e1; a late one also at the latching edge)
    output logic        wfreeze,
    output logic        bus_free,
    output logic        berr_hold,
    // pins
    output logic [31:0] a_o,
    output logic [31:0] d_o,
    output logic        d_oe,
    input  logic [31:0] d_i,
    output logic  [1:0] siz,
    output logic        as_n,
    output logic        ds_n,
    output logic        rw,
    output logic        rmc_n,
    output logic        ecs_n,
    output logic        ocs_n,
    output logic        dben_n,
    input  logic  [1:0] dsack_n,
    input  logic        sterm_n,
    input  logic        avec_n,
    input  logic        berr_n,
    input  logic        br_n,
    output logic        bg_n,
    input  logic        bgack_n,
    input  logic        halt_n
);
import m68ksv_upkg::*;

logic  [2:0] st;          // EU view: 0 idle, 1 first micro-cycle, 2 second, TAS: 3 internal, 4 write first, 5 write second
logic  [2:0] cop;
logic        cbyte, cwr, crmc;
logic        is_rd;
assign is_rd = (cop != BUS_WR);

// dynamic sizing state: the first physical cycle uses the EU's address / data directly (first = 1)
logic        first;
logic [31:0] ca;          // address of the current physical cycle (after the first)
logic  [2:0] nr;          // operand bytes still to transfer (after the first)
logic [31:0] wb;          // write bytes still to transfer, left aligned (rotated by the bytes done)
logic  [1:0] got;         // bytes already received
logic [31:0] rb;          // received bytes ([31:24] first), latched at each data-latching edge
logic [31:0] ca_v, wb_v;
logic  [2:0] nr_v, nr0;
// long operand / long fetch pairs
logic        clong_r, clong_f, clong;   // this access transfers a long: a long operand read (from e0) / a fetch (from e1)
logic [31:0] la;          // the long's address
logic        lr_v;        // a long read's low word is held (rb[15:0]) for the next read / fetch at la + 2
logic        lr_f;        // ... and the long was an instruction fetch
logic        ghost_q;     // this access runs no bus cycle (the pair's second half)
// instruction cache: lookup by the EU's address (asynchronous MLAB read), the line read on a fetch with the cache on
logic        cdis_s;
always_ff @(posedge clk) if (cen_p) cdis_s <= cdis_n;
logic        c_on, lfa, c_hit, hit_q, fill;
logic        ab_q;            // the cycle had an address error (the EU's abort is valid in the first micro-cycle only)
logic [31:0] c_dq;            // the hit line's long, registered at the lookup (the data path starts at a register)
(* ramstyle = "MLAB, no_rw_check" *) logic [56:0] c_mem [0:63];      // {FC2, A31-A8, long}
logic [63:0] c_val;
logic [56:0] c_rd;
assign c_on  = cc_cacr[0] && cdis_s;
logic        lfa_q;
assign lfa   = lfa_q;                                               // long fetch (hit or line read), registered at go
assign c_rd  = c_mem[addr[7:2]];
assign c_hit = c_val[addr[7:2]] && (c_rd[56:32] == {fc2, addr[31:8]});
assign nr0  = (lfa || clong) ? 3'd4 : (cbyte || cop == BUS_IACK || cop == BUS_TAS) ? 3'd1 : 3'd2;
assign ca_v = first ? (lfa ? {addr[31:2], 2'b00} : addr) : ca;
assign nr_v = first ? nr0 : nr;
// the termination logic (from S2 on) uses registered sizes: nr0 latched at e2 of the first micro-word
logic  [2:0] nr0_q, nr_t;
assign nr_t = first ? nr0_q : nr;
assign wb_v = first ? (cbyte ? {dout[7:0], dout[7:0], dout[7:0], dout[7:0]} : {dout, dout}) : wb;
// the EU's address is valid from its e1 edge: in the first micro-word the pair / long-fetch decisions are taken
// combinationally from it (pins A / SIZ from e1), latched at e2
logic        pair_c, clong_fc;
assign clong = clong_r || ((st == 3'd1) ? clong_fc : clong_f);

// bytes a port takes from an access of n bytes at offset o
function automatic logic [2:0] ktake(input logic [1:0] ps, input logic [1:0] o, input logic [2:0] n);
    logic [2:0] m;
    case (ps)
    2'd0:    m = 3'd4 - {1'b0, o};
    2'd1:    m = 3'd2 - {2'b00, o[0]};
    default: m = 3'd1;
    endcase
    ktake = (n < m) ? n : m;
endfunction

// inputs sampled on the clock edges: HALT, BR, BGACK, STERM on the rising edge; BERR, DSACK, AVEC on the falling edge
logic br_s, bgack_s, halt_s;
always_ff @(posedge clk) begin
    if (cen_p) begin
        br_s    <= br_n;
        bgack_s <= bgack_n;
        halt_s  <= halt_n;
    end
end
logic berr_p;
always_ff @(posedge clk) if (cen_n) berr_p <= berr_n;
logic berr_i;
always_ff @(posedge clk) begin
    if (rst) berr_i <= 1'b1;
    else if (cen_p) berr_i <= berr_p;
end
assign berr_hold = !berr_i;

logic e0w;
assign e0w = cen_p && ph == 2'd3;

// physical cycle engine. pa: a physical cycle is in progress (from S1: strobes out, termination sampled); tk: its
// termination was recognised (0 none, 1 synchronous / internal, 2 asynchronous: latch one rising edge later armed,
// 3 latch on the next falling edge); tb: it ended with BERR (or retry); lt: it is the last of the access
logic        pa, tb, tav, lt, retry_q, rr_wait_q;
logic  [1:0] tk;
logic  [3:0] rs_en;
logic  [1:0] rs_ln [4];
logic  [2:0] kq;          // bytes this physical cycle transfers
logic        ghost_c;     // the access runs no bus cycle: pair second half, cache hit or address error
assign ghost_c = ghost_q || hit_q || ab_q;
// termination inputs as the port sees them
logic        t_sync, t_async, t_be;
logic  [1:0] psz_pin;
// (cp5, MC68020 User's Manual: the 68020 has no STERM - Table 3-2 p. 3-8, it is an MC68030 signal - so every external
// cycle is an asynchronous one, three clocks at least (5.2.6 / 5.2.7 p. 5-24); the STERM_n input is ignored. BERR takes
// precedence over DSACK1 / DSACK0 and AVEC (5.5.1 p. 5-55, Table 5-8 case 3 p. 5-54))
assign t_sync  = 1'b0;
assign t_be    = !berr_n;
assign t_async = !dsack_n[1] || !dsack_n[0] || (cop == BUS_IACK && !avec_n) || !berr_n;
// late bus error: BERR at the falling edge one clock after DSACK1 / DSACK0 was recognised - the latching edge (Table 5-8
// case 4, 5.5.1 p. 5-56). With HALT (case 6, a late retry) it is taken as a bus error as well: the execution unit takes the
// cycle's data at this edge. The execution unit sees it at that edge (berr_cyc output, combinational term)
logic        berr_late, lbe, berr_q;
assign berr_late = cen_n && pa && (tk == 2'd3) && !retry_q && !tb && !ghost_c && !berr_n;
assign psz_pin = (!dsack_n[1] && !dsack_n[0]) ? 2'd0 : !dsack_n[1] ? 2'd1 : !dsack_n[0] ? 2'd2 : 2'd0;
// the termination's byte routing (operand byte p <- data lane rs_ln[p] when rs_en[p]), registered with it
function automatic logic [1:0] lane(input logic [1:0] ps, input logic [1:0] o, input logic [1:0] p, input logic [1:0] g);
    case (ps)
    2'd0:    lane = o + p - g;
    2'd1:    lane = {1'b0, o[0]} + p - g;
    default: lane = 2'd0;
    endcase
endfunction
// release of the execution unit: the latching falling edge comes next (tk = 3) on the last physical cycle
assign wfreeze = ((st == 3'd2) || (st == 3'd5)) && (ph == 2'd0) && !((tk == 2'd3) && lt && !retry_q);

// cache line fill at the end of a line read (not a hit, not frozen, no bus error); clear all / one line
assign fill = e3 && (st == 3'd2) && lfa && !hit_q && !cc_cacr[1] && !ab_q && !berr_q;
always_ff @(posedge clk) if (fill) c_mem[addr[7:2]] <= {fc2, addr[31:8], rb};
always_ff @(posedge clk) begin
    if (rst || cc_clr) c_val <= 64'd0;
    else begin
        if (fill) c_val[addr[7:2]] <= 1'b1;
        if (cc_ce) c_val[cc_idx] <= 1'b0;
    end
end

// this cycle's read bytes merged with the earlier ones (a cache hit: the line's long)
logic [31:0] rbn, dx;
assign dx = hit_q ? c_dq : d_i;
always_comb begin
    for (int p = 0; p < 4; p++)
        case (rs_ln[p])
        2'd0:    rbn[31 - 8 * p -: 8] = rs_en[p] ? dx[31:24] : rb[31 - 8 * p -: 8];
        2'd1:    rbn[31 - 8 * p -: 8] = rs_en[p] ? dx[23:16] : rb[31 - 8 * p -: 8];
        2'd2:    rbn[31 - 8 * p -: 8] = rs_en[p] ? dx[15:8]  : rb[31 - 8 * p -: 8];
        default: rbn[31 - 8 * p -: 8] = rs_en[p] ? dx[7:0]   : rb[31 - 8 * p -: 8];
        endcase
end
// write data multiplexer: byte 0 on D31-24; D23-16 byte 0 (odd address) or 1; D15-0 by A1 / A0 (rotated operand);
// a single remaining byte on every lane
logic [7:0] w0, w1, w2, w3;
logic [31:0] wmux;
assign w0 = wb_v[31:24]; assign w1 = wb_v[23:16]; assign w2 = wb_v[15:8]; assign w3 = wb_v[7:0];
always_comb begin
    if (first ? (cbyte || cop == BUS_TAS) : (nr == 3'd1)) wmux = {w0, w0, w0, w0};      // (= nr_v == 1 for a write)
    else case (ca_v[1:0])
    2'd0: wmux = {w0, w1, w2, w3};
    2'd1: wmux = {w0, w0, w1, w2};
    2'd2: wmux = {w0, w1, w0, w1};
    default: wmux = {w0, w0, w1, w0};
    endcase
end
// the current access is the second half of a pair whose long access already ran (the EU's address is valid from e1)
logic        isf;
assign isf      = (cop == BUS_NPE) || (cop == BUS_NPF);
assign pair_c   = lr_v && (addr == la + 32'd2) && ((!lr_f && (cop == BUS_RD) && !cbyte) || (lr_f && isf && !lfa));
assign clong_fc = !pair_c && isf && !lfa && !addr[1];
// TAS: the write cycle of the locked sequence runs in st 4 / 5 like a write in st 1 / 2
logic        wphase, cwr_e, s1st, s2st;
assign wphase = (cop == BUS_TAS) && (st == 3'd4 || st == 3'd5);
assign cwr_e  = cwr || wphase;
assign s1st   = (st == 3'd1) || (st == 3'd4);
assign s2st   = (st == 3'd2) || (st == 3'd5);
logic        sa;          // asynchronous termination sampled from the falling edge after S2
logic  [1:0] fs;          // follow-on / re-run cycle: 1 S0 due (rising edge), 2 S1 due (falling edge)
logic  [2:0] kt_s, kt_a;
assign kt_s = ghost_q ? 3'd0 : ktake(2'd0, ca_v[1:0], nr_t);
assign kt_a = ktake(psz_pin, ca_v[1:0], nr_t);

always_ff @(posedge clk) begin
    if (rst) begin
        st <= 3'd0;
        as_n <= 1'b1; ds_n <= 1'b1; rw <= 1'b1; d_oe <= 1'b0; d_o <= 32'd0; dben_n <= 1'b1; ecs_n <= 1'b1; ocs_n <= 1'b1;
        rmc_n <= 1'b1;
        iack_av <= 1'b0; iack_sp <= 1'b0; berr_q <= 1'b0; lbe <= 1'b0;
        cop <= 3'd0; cbyte <= 1'b0; cwr <= 1'b0; crmc <= 1'b0; first <= 1'b1; got <= 2'd0; rb <= 32'd0; hit_q <= 1'b0; ab_q <= 1'b0;
        c_dq <= 32'd0; lfa_q <= 1'b0; clong_r <= 1'b0; clong_f <= 1'b0; la <= 32'd0; lr_v <= 1'b0; lr_f <= 1'b0; ghost_q <= 1'b0;
        ca <= 32'd0; nr <= 3'd0; wb <= 32'd0;
        pa <= 1'b0; tk <= 2'd0; tb <= 1'b0; tav <= 1'b0; lt <= 1'b0; retry_q <= 1'b0; rr_wait_q <= 1'b0;
        kq <= 3'd0; rs_en <= 4'd0; sa <= 1'b0; fs <= 2'd0;
        for (int p = 0; p < 4; p++) rs_ln[p] <= 2'd0;
    end else begin
        // ---------------- the EU's access (st)
        if (e0w) begin
            if (e0 && go) begin
                st <= 3'd1;
                cop <= op;
                cbyte <= byte_i;
                cwr <= (op == BUS_WR);
                crmc <= rmc_i;
                lfa_q <= c_on && (op == BUS_NPE || op == BUS_NPF);
                clong_r <= (op == BUS_RD) && lw_i && !byte_i;
                clong_f <= 1'b0;
                first <= 1'b1;
                got <= 2'd0;
                hit_q <= 1'b0; ghost_q <= 1'b0;
            end else case (st)
                3'd1: st <= 3'd2;
                3'd2: st <= (cop == BUS_TAS && !ab_q && !berr_q) ? 3'd3 : 3'd0;
                3'd3: begin st <= 3'd4; first <= 1'b1; got <= 2'd0; end
                3'd4: st <= 3'd5;
                default: st <= 3'd0;
            endcase
        end
        // e2 of the first micro-word: a pair's second half runs no bus cycle; a new access drops the held word, a long
        // records its address
        if (e2 && s1st) nr0_q <= nr0;
        if (e2 && st == 3'd1) begin
            ghost_q <= pair_c;
            clong_f <= clong_fc;
            if (!pair_c) begin lr_v <= 1'b0; la <= addr; end
        end
        // S0: ECS / OCS from e1 to the falling edge (also for an internal cycle: cache hit, pair second half), R/W low
        // for a write, RMC from the read of a locked sequence
        if (e1 && s1st) begin
            ecs_n <= 1'b0; if (st == 3'd1) ocs_n <= 1'b0;
            if (cwr_e) rw <= 1'b0;
            if (cop == BUS_TAS || crmc) rmc_n <= 1'b0;
        end
        if (e2 && s1st) begin ecs_n <= 1'b1; ocs_n <= 1'b1; end
        // S1 (falling edge, e2): AS, the read DS; a write's DBEN with AS (UM 5.1.6 p. 5-4, 5.3.2 state 1 p. 5-38); a cache
        // hit, a pair's second half or an address error: none
        if (e2 && st == 3'd1) begin hit_q <= lfa && c_hit && !abort; ab_q <= abort; c_dq <= c_rd[31:0]; end
        if (e2 && s1st) begin
            pa <= 1'b1; tk <= 2'd0; tb <= 1'b0; tav <= 1'b0; lt <= 1'b0; sa <= 1'b0;
            if (!(st == 3'd1 && (abort || (lfa && c_hit) || pair_c))) begin
                as_n <= 1'b0;
                if (!cwr_e) ds_n <= 1'b0; else dben_n <= 1'b0;
            end
        end
        // ---------------- termination of the physical cycle in progress
        // rising edge (S2, S4, ...): S2 - a read's DBEN (5.3.1 state 2 p. 5-31), a write's data (5.1.4 p. 5-4, 5.3.2 state 2);
        // an internal cycle ends here (cache hit, pair second half, address error, the end of a late bus error); an
        // asynchronous termination of the last falling edge arms the latch for the next falling edge
        if (cen_p && pa && !rr_wait_q) begin
            sa <= 1'b1;
            if (!sa && !ghost_c && !lbe) begin
                if (!cwr_e) dben_n <= 1'b0;
                else begin d_o <= wphase ? {dout[7:0], dout[7:0], dout[7:0], dout[7:0]} : wmux; d_oe <= 1'b1; end
            end
            if (tk == 2'd2) tk <= 2'd3;
            else if (tk == 2'd0 && (ghost_c || t_sync || lbe)) begin
                tk <= 2'd3; tb <= lbe;
                lt <= ghost_c || lbe || (nr_t <= kt_s);
                kq <= lbe ? 3'd0 : kt_s;
                for (int p = 0; p < 4; p++) begin
                    rs_en[p] <= !ghost_q && !lbe && (p >= {30'd0, got}) && (p < {30'd0, got} + {29'd0, kt_s});
                    rs_ln[p] <= lane(2'd0, ca_v[1:0], p[1:0], got);
                end
            end
        end
        // a write's DS from S3, the falling edge one clock after AS (5.1.5 p. 5-4, 5.3.2 state 3 p. 5-38), negated at the
        // latching edge below
        if (cen_n && pa && sa && cwr_e && !ghost_c && !lbe) ds_n <= 1'b0;
        // falling edge after S2 (S3, S5, ...): DSACK / AVEC / BERR
        if (cen_n && pa && sa && tk == 2'd0 && !ghost_c && t_async) begin
            tk <= 2'd2;
            tb <= t_be;
            tav <= (cop == BUS_IACK) && !avec_n && dsack_n[1] && dsack_n[0] && !t_be;
            retry_q <= t_be && !halt_s && (cop != BUS_TAS) && !crmc;
            lt <= t_be || (cop == BUS_IACK) || (nr_t <= kt_a);
            kq <= kt_a;
            for (int p = 0; p < 4; p++) begin
                rs_en[p] <= (p >= {30'd0, got}) && (p < {30'd0, got} + {29'd0, kt_a});
                rs_ln[p] <= lane(psz_pin, ca_v[1:0], p[1:0], got);
            end
        end
        // the latching falling edge: data taken, AS / DS negated; a follow-on cycle of a sized access (or the re-run
        // after BERR + HALT) starts on the next rising edge
        if (cen_n && pa && tk == 2'd3) begin
            pa <= 1'b0; tk <= 2'd0; lbe <= 1'b0;
            as_n <= 1'b1; ds_n <= 1'b1;
            if (!cwr_e) dben_n <= 1'b1;
            if (st == 3'd5 || ((tb || berr_late) && (cop == BUS_TAS || crmc))) rmc_n <= 1'b1;
            if (berr_late) begin
                // late bus error: the access ends with it - on its last physical cycle now (the execution unit sees it at
                // this edge, berr_cyc), else after one internal clock (no further cycle of a sized access)
                tb <= 1'b1;
                if (lt) berr_q <= 1'b1;
                else begin lbe <= 1'b1; pa <= 1'b1; sa <= 1'b1; end
            end else if (!retry_q) begin
                rb <= rbn;
                if (!lt) begin
                    got   <= got + kq[1:0];
                    ca    <= ca_v + {29'd0, kq};
                    nr    <= nr_t - kq;
                    case (kq)
                    3'd1:    wb <= {wb_v[23:0], wb_v[31:24]};
                    3'd2:    wb <= {wb_v[15:0], wb_v[31:16]};
                    3'd3:    wb <= {wb_v[7:0], wb_v[31:8]};
                    default: wb <= wb_v;
                    endcase
                    first <= 1'b0;
                    fs <= 2'd1;
                end
                // a long read keeps its low word for the pair's second half; a long write covers it
                if (lt && clong && !tb && st == 3'd2) begin lr_v <= 1'b1; lr_f <= clong_f; end
            end else begin
                rr_wait_q <= 1'b1;            // re-run: the same cycle once HALT is negated and the bus is free
                fs <= 2'd1;
            end
        end
        // S0 of a follow-on / re-run cycle (rising edge): ECS, R/W, write data (address and SIZ from ca / nr)
        if (cen_p && fs == 2'd1 && !(rr_wait_q && !bus_free)) begin
            fs <= 2'd2; rr_wait_q <= 1'b0; retry_q <= 1'b0;
            ecs_n <= 1'b0;
            if (cwr_e) rw <= 1'b0;
        end
        // S1 of a follow-on cycle (falling edge): AS, the read DS; termination from the following edges
        if (cen_n && fs == 2'd2) begin
            fs <= 2'd0;
            ecs_n <= 1'b1;
            as_n <= 1'b0; pa <= 1'b1; tk <= 2'd0; tb <= 1'b0; lt <= 1'b0; sa <= 1'b0;
            if (!cwr_e) ds_n <= 1'b0; else dben_n <= 1'b0;
        end
        // how the access ended (the EU reads it at the e2 of its second micro-word)
        if (e1 && s2st) berr_q <= tb;
        if (e3 && st == 3'd2 && cop == BUS_IACK) begin
            iack_av <= tav && !tb;
            iack_sp <= tb;
        end
        // end of the access: R/W high, data bus released (the e0 slot after its second micro-word); RMC stays through a
        // locked sequence's internal word
        if (e0w && s2st) begin
            rw <= 1'b1; d_oe <= 1'b0; dben_n <= 1'b1;
            if (!(cop == BUS_TAS && st == 3'd2 && !berr_q && !ab_q) && !rmc_i) rmc_n <= 1'b1;
        end
        // CAS / CAS2: RMC released at the e0 slot after the lock ends (the final prefetch is not locked)
        if (e0w && !rmc_i && crmc && !(cop == BUS_TAS && st != 3'd0)) rmc_n <= 1'b1;
    end
end

// bus arbitration: the three-wire protocol of m68ksv_biu (BR / BG / BGACK)
typedef enum logic [2:0] { A_IDLE, A_REQ, A_GNT, A_ACK, A_REQACK, A_REQACK2, A_ACKREL } arb_t;
arb_t arb, arb_n;
logic granted;
logic bg_block_q;
always_comb begin
    arb_n = arb;
    case (arb)
    A_IDLE:    if (!bg_block_q) arb_n = !bgack_s ? A_ACK : !br_s ? A_REQ : A_IDLE;
    A_REQ:     arb_n = A_GNT;
    A_GNT:     arb_n = (!br_s && bgack_s) ? A_GNT : A_ACK;
    A_ACK:     arb_n = (!br_s && !bg_block_q) ? A_REQACK : (!bgack_s && !bg_block_q) ? A_ACK : A_IDLE;
    A_REQACK:  arb_n = A_REQACK2;
    A_REQACK2: arb_n = (bgack_s && br_s) ? A_IDLE : bgack_s ? A_GNT : br_s ? A_ACKREL : A_REQACK2;
    A_ACKREL:  arb_n = A_ACK;
    default:   arb_n = A_IDLE;
    endcase
end
always_ff @(posedge clk) begin
    if (rst) begin
        arb <= A_IDLE;
        granted <= 1'b0;
        bg_n <= 1'b1;
    end else begin
        if (cen_n) begin
            arb <= arb_n;
            granted <= (arb_n == A_REQ) || (arb_n == A_GNT) || (arb_n == A_REQACK) || (arb_n == A_REQACK2);
        end
        if (cen_p) bg_n <= ~granted;
    end
end
// no grant from a cycle's S0 to its end (all physical cycles of an access, and TAS's read-modify-write)
always_ff @(posedge clk) begin
    if (rst) bg_block_q <= 1'b0;
    else if (e0) bg_block_q <= go || rmc_i || ((cop == BUS_TAS) && (st != 3'd0) && (st != 3'd5) && !(st == 3'd2 && (berr_q || ab_q)));
    else if (e3 && st == 3'd2 && cop != BUS_TAS && !rmc_i) bg_block_q <= 1'b0;
    else if (e3 && st == 3'd5) bg_block_q <= 1'b0;
end
logic bus_free_raw;
assign bus_free_raw = br_s && bgack_s && !granted;
// a CAS / CAS2 locked sequence keeps the bus: a pending request (BR) does not hold its cycles back
assign bus_free = halt_s && (bus_free_raw || (lock_i && bgack_s && !granted));

assign a_o = ca_v;
assign siz = nr_v[1:0];
assign din = (cbyte || cop == BUS_IACK) ? {8'h00, rb[31:24]} : ((lfa && addr[1]) || ghost_q) ? rb[15:0] : rb[31:16];
assign dv  = e3 && (st == 3'd2) && !ab_q && is_rd;
assign berr_cyc = berr_q || (berr_late && lt);

endmodule

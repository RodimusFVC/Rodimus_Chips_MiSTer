// Copyright (C) 2026 Rodimus
// m68ksv: bus interface unit for the asynchronous 68000 / 68010 bus, 16-bit or (68008, 68EC000 MODE = 0) 8-bit: on the
// 8-bit bus a word access is two byte cycles back to back (A0 = 0 then 1, data on D7-D0), the execution unit held for
// the second one (the 68008: 4 more clocks per word, as MAME's m68008). One bus cycle = two micro-cycles
// (S0-S7); the phase generator is frozen for wait states (before S5) and while the bus is not available at S0 (bus
// granted away, HALT, BR / BGACK). Also: E clock, VMA / VPA 6800 cycles, bus arbitration (BR / BG / BGACK).
// Pin timing per phase as the 68000: FC at S0 (from the EU), address at S1 (EU register), AS / read strobes / R/W at
// S2, write data at S3, write strobes at S4, strobes off at S7, R/W high at the next S0. An address error still runs
// the cycle with AS (and R/W) but no data strobes. Oracles: MC68000 User's Manual, fx68k (lockstep, every pin every
// phase). Own code.

module m68ksv_biu (
    input  logic        clk,
    input  logic        rst,
    input  logic        cen_p, cen_n,     // raw phase enables (E counter, input sampling)
    input  logic        e0, e1, e2, e3,
    input  logic  [1:0] ph,               // phase within the micro-cycle (0 after e0)
    input  logic        bus8,             // 8-bit data bus (constant except on the 68EC000)
    // from the execution unit
    input  logic        go,               // with e0: a cycle starts (S0)
    input  logic  [2:0] op,               // m68ksv_upkg::BUS_*
    input  logic        byte_i,
    input  logic [31:0] addr,             // registered by the EU at e1
    input  logic [15:0] dout,
    input  logic        abort,            // address error (registered by the EU at e1)
    input  logic        ghost,            // 68010 loop mode: no bus cycle (no strobes, no wait; registered at e2)
    input  logic        ghost_s2,         // the same for the cycle in its first micro-cycle, valid at e2 (S2 strobes)
    output logic [15:0] din,
    output logic        dv,               // read data valid (with e3)
    output logic        iack_av,          // last IACK ended with VPA
    output logic        iack_sp,          // last IACK ended with BERR
    output logic        berr_cyc,         // the current cycle ended with BERR (valid from e1 of its second micro-cycle)
    output logic        wfreeze,          // hold the phase generator before S5 (wait state)
    output logic        bus_free,         // a cycle may start at the next phi1 (S0)
    output logic        berr_hold,        // BERR (as synchronised) holds the next micro-cycle start (fx68k wClk)
    // pins
    output logic [15:0] d_o,
    output logic        d_oe,
    input  logic [15:0] d_i,
    output logic        as_n,
    output logic        uds_n,
    output logic        lds_n,
    output logic        a0,               // 8-bit bus: address bit 0
    output logic        rw,
    input  logic        dtack_n,
    input  logic        berr_n,
    input  logic        vpa_n,
    output logic        vma_n,
    output logic        e_clk,
    input  logic        br_n,
    output logic        bg_n,
    input  logic        bgack_n,
    input  logic        halt_n
);
import m68ksv_upkg::*;

logic  [2:0] st;          // 0 idle, 1 first micro-cycle, 2 second, TAS: 3 internal, 4 write first, 5 write second
logic        tas_be;      // TAS read phase ended with BERR: AS still to be released
// 8-bit bus, word access: the first byte cycle's termination does not release the execution unit; k8 counts the
// phases from its S5 (1) to the second byte cycle's S4 (8), whose termination then releases it as usual
logic        half;        // second byte cycle of a split word
logic  [3:0] k8;
logic  [7:0] hb;          // first (high) byte read
logic  [2:0] cop;
logic        cbyte, cwr;
logic        is_rd;
assign is_rd = (cop != BUS_WR);

// E clock: free running, ten CPU clocks (high for four), counted on the falling CPU edges; no reset (power-up 0)
logic [3:0] ecnt = 4'd1;      // power-up phase of E (arbitrary on the real part; 1 matches fx68k's)
always_ff @(posedge clk) begin
    if (cen_n) begin
        ecnt  <= (ecnt == 4'd9) ? 4'd0 : ecnt + 4'd1;
        if (ecnt == 4'd9)      e_clk <= 1'b0;
        else if (ecnt == 4'd5) e_clk <= 1'b1;
    end
end

// inputs sampled on the CPU clock edges (DTACK / BERR / IPL on the falling edge in the top / here; VPA, BR, BGACK,
// HALT on the rising edge)
logic vpa_s, br_s, bgack_s, halt_s;
always_ff @(posedge clk) begin
    if (cen_p) begin
        vpa_s   <= vpa_n;
        br_s    <= br_n;
        bgack_s <= bgack_n;
        halt_s  <= halt_n;
    end
end

// cycle in progress from S1 (address valid) to the end of S7
logic aon;
always_ff @(posedge clk) begin
    if (rst) aon <= 1'b0;
    else if (e1 && st == 3'd1) aon <= 1'b1;
    else if (cen_n && k8 == 4'd2) aon <= 1'b0;          // split word: S7 / S1 around the second byte cycle
    else if (cen_n && k8 == 4'd4) aon <= 1'b1;
    else if (e0w && st == 3'd2 && cop != BUS_TAS) aon <= 1'b0;
    else if (e0w && st == 3'd5) aon <= 1'b0;
end

// VMA: asserted on a falling edge with E count 3 while a cycle runs with VPA; the cycle then ends on count 8
always_ff @(posedge clk) begin
    if (rst) vma_n <= 1'b1;
    else if (cen_n && aon && !vpa_s && ecnt == 4'd3) vma_n <= 1'b0;
    else if (cen_p && ecnt == 4'd0) vma_n <= 1'b1;
end
logic vma_end;
assign vma_end = !vma_n && ecnt == 4'd8;

logic e0w;
assign e0w = cen_p && ph == 2'd3;

// termination, sampled at the falling edge that would start S5: DTACK, 6800 end, or - without VPA - BERR or an
// address error (an address-error cycle that meets VPA runs as a 6800 cycle: fx68k iStop). BERR counts from the
// falling edge before (fx68k: rBerr, then iStop one edge later); VPA as sampled on the last rising edge
logic berr_p;
always_ff @(posedge clk) if (cen_n) berr_p <= berr_n;
// BERR seen on a rising edge (two edges after the pin) stops the next micro-cycle from starting, in or out of a cycle
logic berr_i;
always_ff @(posedge clk) begin
    if (rst) berr_i <= 1'b1;
    else if (cen_p) berr_i <= berr_p;
end
assign berr_hold = !berr_i;
// Bus retry (MC68000 User's Manual 5.4.2): BERR together with HALT ends the cycle, the processor waits until HALT is
// negated and runs the same cycle again (same address, function code, data); never for TAS (read-modify-write: a bus
// error, HALT or not). It uses the same held-execution-unit sequence as the second byte of a split word (k8, rr = 1:
// same byte, a wait at k8 = 3 while HALT is asserted). No lockstep oracle (fx68k has no retry): manual-verified.
logic term, wst, w8, split, berr_t, retry, rr, rr_wait;
assign rr_wait = rr && !bus_free;          // re-run: HALT negated and the bus not requested / granted away
assign wst     = (st == 3'd2) || (st == 3'd5);
assign term    = ghost || !dtack_n || vma_end || (vpa_s && (abort || !berr_p));
assign berr_t  = dtack_n && !vma_end && vpa_s && !abort && !berr_p && !ghost;
assign w8      = bus8 && !cbyte && (cop != BUS_IACK) && (cop != BUS_TAS) && !abort && !ghost;
assign split   = (st == 3'd2) && (ph == 2'd0) && ((k8 == 4'd0) || (k8 == 4'd8)) && w8 && !half && (!dtack_n || vma_end);
assign retry   = (st == 3'd2) && (ph == 2'd0) && ((k8 == 4'd0) || (k8 == 4'd8)) && berr_t && !halt_s && (cop != BUS_TAS);
assign wfreeze = wst && (ph == 2'd0) && (!term || split || retry || ((k8 != 4'd0) && (k8 != 4'd8)));
always_ff @(posedge clk) begin
    if (rst) begin k8 <= 4'd0; rr <= 1'b0; end
    else if (cen_n && (split || retry)) begin k8 <= 4'd1; rr <= retry; end
    else if (k8 == 4'd3) begin if (cen_p && !rr_wait) k8 <= 4'd4; end                  // S0 on a rising edge
    else if ((cen_p || cen_n) && (k8 != 4'd0) && (k8 != 4'd8)) k8 <= k8 + 4'd1;
    else if (e1) begin k8 <= 4'd0; rr <= 1'b0; end
end

always_ff @(posedge clk) begin
    if (rst) begin
        st <= 3'd0;
        as_n <= 1'b1; uds_n <= 1'b1; lds_n <= 1'b1; rw <= 1'b1; d_oe <= 1'b0; d_o <= 16'd0;
        iack_av <= 1'b0; iack_sp <= 1'b0; berr_cyc <= 1'b0; tas_be <= 1'b0;
        cop <= 3'd0; cbyte <= 1'b0; cwr <= 1'b0; half <= 1'b0; hb <= 8'd0;
    end else begin
        // a cycle ends on the e0 slot even when the next one waits for the bus (e0 itself held back)
        if (e0w) begin
            if (e0 && go) begin
                st <= 3'd1;
                cop <= op;
                cbyte <= byte_i;
                cwr <= (op == BUS_WR);
                half <= 1'b0;
            end else case (st)
                3'd1: st <= 3'd2;
                3'd2: st <= (cop == BUS_TAS && !abort && !berr_cyc) ? 3'd3 : 3'd0;
                3'd3: st <= 3'd4;
                3'd4: st <= 3'd5;
                default: st <= 3'd0;
            endcase
        end
        // S2: AS, read strobes, R/W low for a write (AS and R/W also on an address error)
        if (e2 && st == 3'd1 && !ghost_s2) begin
            as_n <= 1'b0;
            if (is_rd) begin
                if (!abort) begin
                    uds_n <= cbyte & addr[0];
                    lds_n <= cbyte & ~addr[0];
                end
            end else
                rw <= 1'b0;
        end
        // S3: write data out
        if (e3 && st == 3'd1 && cwr) begin
            d_o  <= bus8 ? {8'h00, (!cbyte && cop != BUS_TAS) ? dout[15:8] : dout[7:0]} : dout;
            d_oe <= 1'b1;
        end
        // split word: end of the first byte cycle and the second byte cycle up to S4 (on the raw phase enables)
        if (cen_n && k8 == 4'd2) begin if (!rr) hb <= d_i[7:0]; as_n <= 1'b1; uds_n <= 1'b1; lds_n <= 1'b1; end  // S7
        if (cen_p && k8 == 4'd3 && !rr_wait) begin rw <= 1'b1; d_oe <= 1'b0; half <= half | !rr; end   // S0
        if (cen_p && k8 == 4'd5) begin                                                                   // S2
            as_n <= 1'b0;
            if (is_rd) begin uds_n <= cbyte & addr[0]; lds_n <= cbyte & ~addr[0]; end else rw <= 1'b0;
        end
        if (cen_n && k8 == 4'd6 && cwr) begin                                                            // S3
            d_o  <= bus8 ? {8'h00, (w8 && !half) ? dout[15:8] : dout[7:0]} : dout;
            d_oe <= 1'b1;
        end
        if (cen_p && k8 == 4'd7 && cwr) begin uds_n <= cbyte & addr[0]; lds_n <= cbyte & ~addr[0]; end  // S4
        // S4: write strobes
        if (e0 && st == 3'd1 && cwr && !abort) begin
            uds_n <= cbyte & addr[0];
            lds_n <= cbyte & ~addr[0];
        end
        // S5: how the cycle ended
        if (e1 && st == 3'd2) berr_cyc <= !abort && !ghost && dtack_n && !vma_end && vpa_s && !berr_p;
        // TAS read phase ended by BERR: AS is released one clock after S7 (fx68k SRMC_RES)
        if (cen_n && tas_be) begin as_n <= 1'b1; tas_be <= 1'b0; end
        // S7: strobes off
        if (e3 && st == 3'd2) begin
            if (cop != BUS_TAS || abort) as_n <= 1'b1;
            else if (berr_cyc) tas_be <= 1'b1;
            uds_n <= 1'b1;
            lds_n <= 1'b1;
            if (cop == BUS_IACK) begin
                iack_av <= !vma_n || !vpa_s;
                iack_sp <= berr_cyc;
            end
        end
        if (e0w && st == 3'd2) begin
            rw <= 1'b1;
            d_oe <= 1'b0;
        end
        // TAS write phase: R/W low, data, strobes, AS released at the end
        if (cop == BUS_TAS) begin
            if (e2 && st == 3'd4) rw <= 1'b0;
            if (e3 && st == 3'd4) begin d_o <= dout; d_oe <= 1'b1; end
            if (e0 && st == 3'd4) begin uds_n <= addr[0]; lds_n <= ~addr[0]; end
            if (e1 && st == 3'd5) berr_cyc <= dtack_n && vpa_s && !berr_p;
            if (e3 && st == 3'd5) begin as_n <= 1'b1; uds_n <= 1'b1; lds_n <= 1'b1; end
            if (e0w && st == 3'd5) begin rw <= 1'b1; d_oe <= 1'b0; end
        end
    end
end

// bus arbitration (MC68000 three-wire protocol): BG follows BR one clock later when no cycle is about to start;
// the bus stays away while BGACK is asserted; a new cycle needs BR, BGACK and HALT negated and no grant pending
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
// a cycle in its S0 (AS not yet asserted) blocks a new grant
// (8-bit bus: no grant between the two byte cycles of a word - the word is one access for the sequencer)
always_ff @(posedge clk) begin
    if (rst) bg_block_q <= 1'b0;
    else if (e0) bg_block_q <= go;
    else if (e2 && st == 3'd1 && !(bus8 && !cbyte && cop != BUS_IACK && cop != BUS_TAS)) bg_block_q <= 1'b0;
    else if ((cen_p && k8 == 4'd5) || (e3 && st == 3'd2)) bg_block_q <= 1'b0;
end
assign bus_free = halt_s && br_s && bgack_s && !granted;

assign din = bus8 ? {(w8 ? hb : 8'h00), d_i[7:0]} : cbyte ? {8'h00, addr[0] ? d_i[7:0] : d_i[15:8]} : d_i;
assign a0  = bus8 && (w8 ? half : addr[0]);
assign dv  = e3 && (st == 3'd2) && !abort && is_rd;

endmodule

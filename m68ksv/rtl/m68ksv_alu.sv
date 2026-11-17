// Copyright (C) 2026 Rodimus
// m68ksv: data ALU. Combinational; operands (and the adder controls) come from registers latched at e2, the result
// and the raw flag terms are latched at e3 (the EU forms X N Z V C from the registered terms); N and Z of most ops
// are formed from the latched result in the next phase (nzm).
// Oracles: Tom Harte / SingleStepTests 680x0 (68000) suite; MAME m68000 / Musashi for the undocumented BCD / CHK / DIV
// flag behaviour where the suite needs it. Own code.

module m68ksv_alu #(
    parameter bit IS010 = 1'b0     // 68010: byte sign extension (MOVES.B to An)
) (
    input  logic  [5:0] op,        // resolved ALU op (m68ksv_upkg::OP_*)
    input  logic  [1:0] sz,        // 0 byte, 1 word, 2 long
    input  logic [31:0] a,         // source operand
    input  logic [31:0] b,         // destination operand
    input  logic        cin,       // X in (carry / extend input; registered by the EU at e2)
    input  logic  [2:0] shtype,    // shift kind: {dir(1=left), kind(00 AS, 01 LS, 10 ROX, 11 RO)}
    input  logic  [1:0] bitop,     // 0 BTST 1 BCHG 2 BCLR 3 BSET
    input  logic        cond,      // Scc condition
    input  logic [31:0] mp,        // 16 x 16 product (registered DSP multiplier) or the DIVU / DIVS result (EU)
    input  logic        ad_sub,    // adder controls, decoded from the op one phase earlier: subtract forms
    input  logic        ad_usex,   //   ADDX SUBX NEGX (carry in from X)
    input  logic        ad_neg,    //   NEG NEGX (0 - b)
    input  logic        bcd_neg,   // NBCD (0 - b - x on the SBCD subtractor)
    input  logic        ad_ysw,    // adder y operand: ADDA / SUBA / CMPA word (bits 31-16 = a15), byte (68010 MOVES.B:
    input  logic        ad_ysb,    //   bits 31-8 = a7); decoded at e2 with the op
    input  logic  [2:0] ad_fsz,    // flag size, one-hot {long (or CMPA), word, byte}, decoded at e2
    input  logic  [3:0] rsel,      // result source, decoded from the op one phase earlier (R_* below)
    input  logic        rsub,      //   R_BCD: SBCD / NBCD (else ABCD); R_BYTE: TAS (else Scc)
    output logic [31:0] res_add,   // adder result (rsel R_ADD; the EU puts it in the last result-mux level)
    output logic [31:0] res_oth,   // every other result source
    // raw flag terms (cp4b: the EU registers them at e3 and forms X N Z V C from the registered copies, see m68ksv_eu)
    output logic        f_adc,     // adder C / V at the operand size (CMPA: 32 bits), and out of bit 15
    output logic        f_adv,
    output logic        f_adc16,
    output logic        f_adv16,
    output logic        f_abc,     // ABCD carry / V
    output logic        f_abv,
    output logic        f_sbc,     // SBCD / NBCD borrow / V
    output logic        f_sbv,
    output logic        f_sho,     // shifter: bit shifted out, ASL V
    output logic        f_shv,
    output logic        f_bitz,    // bit op: tested bit zero
    output logic  [1:0] nzm,       // N / Z rule applied to the latched result (m68ksv_eu)
    output logic  [1:0] nsz        // operand size for that rule
);
import m68ksv_upkg::*;

localparam [1:0] SZB = 2'd0, SZW = 2'd1, SZL = 2'd2;
localparam [1:0] NZ_RES = 2'd0, NZ_STICKY = 2'd1, NZ_KEEP = 2'd2;   // N Z from res / N from res, Z &= res zero / ccr_o
// result sources (m68ksv_eu decodes them from the op: function alu_rsel there)
localparam [3:0] R_B = 4'd0, R_A = 4'd1, R_SXA = 4'd2, R_ADD = 4'd3, R_AND = 4'd4, R_OR = 4'd5, R_EOR = 4'd6, R_NOT = 4'd7,
                 R_ZERO = 4'd8, R_BCD = 4'd9, R_EXT = 4'd10, R_SWAP = 4'd11, R_SHR = 4'd12, R_BIT = 4'd13, R_BYTE = 4'd14,
                 R_MP = 4'd15;

logic        cin_x;
assign cin_x = cin;
// sign / carry bit positions per size
function automatic logic msb(input logic [31:0] v, input logic [1:0] s);
    msb = (s == SZB) ? v[7] : (s == SZW) ? v[15] : v[31];
endfunction
function automatic logic zero(input logic [31:0] v, input logic [1:0] s);
    zero = (s == SZB) ? (v[7:0] == 8'd0) : (s == SZW) ? (v[15:0] == 16'd0) : (v == 32'd0);
endfunction
// BCD: binary add / subtract, then decimal correction; V = the correction flipped bit 7 (suite-verified behaviour)
logic [9:0] ab_d, ab_r, sb_d, sb_r;
logic       ab_c, sb_c, ab_hc, sb_hb;
logic [4:0] sb_lo;
logic [7:0] sb_b, sb_a;            // SBCD: b - a - x; NBCD: 0 - b - x on the same subtractor
assign sb_b = bcd_neg ? 8'd0 : b[7:0];
assign sb_a = bcd_neg ? b[7:0] : a[7:0];
always_comb begin
    // a + b + x; +6 if the low digit exceeds 9; +0x60 if (sum + low correction) > 0x9f; one correction adder
    ab_d  = {2'd0, a[7:0]} + {2'd0, b[7:0]} + {9'd0, cin_x};
    ab_hc = ({1'b0, a[3:0]} + {1'b0, b[3:0]} + {4'd0, cin_x}) > 5'd9;
    ab_c  = ab_hc ? (ab_d > 10'h99) : (ab_d > 10'h9f);
    ab_r  = ab_d + {3'd0, ab_c, ab_c, 2'd0, ab_hc, ab_hc, 1'b0};
    // sb_b - sb_a - x (10-bit two's complement); -6 if the low digit borrowed; -0x60 if the byte borrowed
    sb_d  = {2'd0, sb_b} - {2'd0, sb_a} - {9'd0, cin_x};
    sb_lo = {1'b0, sb_b[3:0]} - {1'b0, sb_a[3:0]} - {4'd0, cin_x};
    sb_hb = sb_lo[4];
    sb_r  = sb_d - {3'd0, sb_d[9], sb_d[9], 2'd0, sb_hb, sb_hb, 1'b0};
    // borrow: the byte borrowed, or the -6 correction took a non-negative difference below zero (difference < 6)
    sb_c  = sb_d[9] | (sb_hb & (sb_d[8:3] == 6'd0) & ~(sb_d[2] & sb_d[1]));
end

// shifter: one bit per micro-cycle
logic [31:0] shr;
logic        sh_out, sh_v, top, inb;
always_comb begin
    top = msb(b, sz);
    sh_out = 1'b0; inb = 1'b0; shr = b;
    if (shtype[2]) begin // left
        sh_out = top;
        case (shtype[1:0]) 2'b10: inb = cin_x; 2'b11: inb = top; default: inb = 1'b0; endcase
        shr = {b[30:0], inb};
    end else begin
        sh_out = b[0];
        case (shtype[1:0]) 2'b00: inb = top; 2'b10: inb = cin_x; 2'b11: inb = b[0]; default: inb = 1'b0; endcase
        shr = {1'b0, b[31:1]};
        if (sz == SZB) shr[7] = inb; else if (sz == SZW) shr[15] = inb; else shr[31] = inb;
    end
    sh_v = (shtype == 3'b100) && (msb(shr, sz) != top);   // ASL: msb changed
end

// bit ops
logic [4:0]  bnum;
logic [31:0] bmask;
assign bnum  = (sz == 2'd2) ? a[4:0] : {2'b00, a[2:0]};
assign bmask = 32'd1 << bnum;

// one shared adder for ADD SUB CMP ADDX SUBX NEG NEGX ADDA SUBA CMPA: r = x + (sub ? ~y : y) + carry-in
logic [31:0] sxa, ad_x, ad_y, ad_y2, ad_r;
logic [32:0] ad_r33;
logic        ad_ci;
assign sxa     = (sz == SZW) ? {{16{a[15]}}, a[15:0]} : (IS010 && sz == SZB) ? {{24{a[7]}}, a[7:0]} : a;
assign ad_x    = ad_neg ? 32'd0 : b;
// y operand from registered controls (the same value as ad_neg ? b : ad_addr ? sxa : a)
logic        ad_s16;
assign ad_s16  = ad_ysw ? a[15] : a[7];
always_comb begin
    for (int i = 0; i < 32; i++)
        ad_y[i] = ad_neg ? b[i] : (i >= 16 && (ad_ysw || ad_ysb)) ? ad_s16 : (i >= 8 && ad_ysb) ? a[7] : a[i];
end
assign ad_ci   = ad_sub ? ~(ad_usex & cin_x) : (ad_usex & cin_x);
assign ad_y2   = ad_sub ? ~ad_y : ad_y;
assign ad_r33  = {1'b0, ad_x} + {1'b0, ad_y2} + {32'd0, ad_ci};
assign ad_r    = ad_r33[31:0];
// carries into / out of the sized msb from the sum bits (carry into bit k = r[k] ^ x[k] ^ y[k]; out of bit 31 = bit 32
// of the sum): C = carry out (borrow = not carry out for the subtract forms), V = carry into msb ^ carry out. The
// same values as the textbook (x, y, r msb) forms; the msb carries come straight off the chain (cp4b flag path).
logic ad_ci7, ad_co7, ad_ci15, ad_co15, ad_ci31, ad_co31;
assign ad_ci7  = ad_r[7] ^ ad_x[7] ^ ad_y2[7];
assign ad_co7  = ad_r[8] ^ ad_x[8] ^ ad_y2[8];
assign ad_ci15 = ad_r[15] ^ ad_x[15] ^ ad_y2[15];
assign ad_co15 = ad_r[16] ^ ad_x[16] ^ ad_y2[16];
assign ad_ci31 = ad_r[31] ^ ad_x[31] ^ ad_y2[31];
assign ad_co31 = ad_r33[32];
logic ad_c, ad_v, ad_c16, ad_v16;
// (fsz decoded at e2: ad_fsz; the long terms come off the end of the chain and enter last)
logic ad_cs, ad_vs;
assign ad_cs  = (ad_fsz[0] & ad_co7) | (ad_fsz[1] & ad_co15);
assign ad_vs  = (ad_fsz[0] & (ad_ci7 ^ ad_co7)) | (ad_fsz[1] & (ad_ci15 ^ ad_co15));
assign ad_c   = (ad_fsz[2] ? ad_co31 : ad_cs) ^ ad_sub;
assign ad_v   = ad_fsz[2] ? (ad_ci31 ^ ad_co31) : ad_vs;
// the same out of bit 15 (low word of a long operation)
assign ad_c16 = ad_co15 ^ ad_sub;
assign ad_v16 = ad_ci15 ^ ad_co15;


// flags: the raw terms go to the EU, which forms X N Z V C one register stage later (cp4b flag-path split); only
// the N / Z rule and size stay here (they depend on the op alone)
assign f_adc = ad_c; assign f_adv = ad_v; assign f_adc16 = ad_c16; assign f_adv16 = ad_v16;
assign f_abc = ab_c; assign f_abv = ~ab_d[7] & ab_r[7];
assign f_sbc = sb_c; assign f_sbv = sb_d[7] & ~sb_r[7];
assign f_sho = sh_out; assign f_shv = sh_v;
assign f_bitz = !b[bnum];                     // (= (b & bmask) == 0, as a 32:1 mux; cp5)
always_comb begin
    nzm = NZ_KEEP;
    nsz = sz;
    case (op)
    OP_PASS, OP_ADD, OP_SUB, OP_CMP, OP_NEG, OP_AND, OP_OR, OP_EOR, OP_NOT, OP_CLR, OP_TST, OP_EXT,
    OP_SHFI, OP_SHF, OP_SHF1: nzm = NZ_RES;
    OP_ADDX, OP_SUBX, OP_NEGX: nzm = NZ_STICKY;
    OP_ABCD, OP_SBCD, OP_NBCD: begin nzm = NZ_STICKY; nsz = SZB; end
    OP_SWAP, OP_CMPA, OP_MUL: begin nzm = NZ_RES; nsz = SZL; end
    default: ;
    endcase
end

// result: one 16-way select on a registered code (the adder separately, res_add)
assign res_add = ad_r;
logic [31:0] r_ext, r_bit;
logic  [7:0] r_byte, r_bcd;
always_comb begin
    if (sz == SZW) r_ext = {b[31:16], {8{b[7]}}, b[7:0]}; else r_ext = {{16{b[15]}}, b[15:0]};
    case (bitop) 2'd1: r_bit = b ^ bmask; 2'd2: r_bit = b & ~bmask; 2'd3: r_bit = b | bmask; default: r_bit = b; endcase
    r_byte = rsub ? {1'b1, b[6:0]} : {8{cond}};
    r_bcd  = rsub ? sb_r[7:0] : ab_r[7:0];
    case (rsel)
    R_A:     res_oth = a;
    R_SXA:   res_oth = sxa;
    R_AND:   res_oth = a & b;
    R_OR:    res_oth = a | b;
    R_EOR:   res_oth = a ^ b;
    R_NOT:   res_oth = ~b;
    R_ZERO:  res_oth = 32'd0;
    R_BCD:   res_oth = {b[31:8], r_bcd};
    R_EXT:   res_oth = r_ext;
    R_SWAP:  res_oth = {b[15:0], b[31:16]};
    R_SHR:   res_oth = shr;
    R_BIT:   res_oth = r_bit;
    R_BYTE:  res_oth = {b[31:8], r_byte};
    R_MP:    res_oth = mp;
    default: res_oth = b;
    endcase
end

endmodule

// Copyright (C) 2026 Rodimus
// x86sv ALU: ADD OR ADC SBB AND SUB XOR CMP INC DEC, byte / word, with flag results.

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

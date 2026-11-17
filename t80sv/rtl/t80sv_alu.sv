//============================================================================
//  t80sv_alu - Z80 / 8080 ALU (combinational)
//
//  SystemVerilog translation of T80_ALU.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex,
//  Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and contributors (MiSTer-devel lineage). Phoenix core
//  additions (runtime 8080 mode) by Rodimus.
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

module t80sv_alu #(
    parameter int Flag_C = 0,
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic [1:0]  mode,          // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    input  logic        Arith16,
    input  logic        Z16,
    input  logic        WZ13,          // MEMPTR bits 13 and 11: BIT n,(HL) X / Y flags
    input  logic        WZ11,
    input  logic [1:0]  XY_State,
    input  logic [3:0]  ALU_Op,
    input  logic        Rot_Akku,
    input  logic [5:0]  IR,
    input  logic [1:0]  ISet,
    input  logic [7:0]  BusA,
    input  logic [7:0]  BusB,
    input  logic [7:0]  F_In,
    output logic [7:0]  Q,
    output logic [7:0]  F_Out
);

logic [7:0] BitMask;
logic       UseCarry, Carry7_v, Overflow_v, HalfCarry_v, Carry_v;
logic [7:0] Q_v;
logic [7:0] B_i;

assign BitMask  = 8'd1 << IR[5:3];
assign UseCarry = ~ALU_Op[2] & ALU_Op[0];
assign B_i      = ALU_Op[1] ? ~BusB : BusB;

// three-stage adder: half carry out of bit 3, carry out of bit 6 and bit 7
assign {HalfCarry_v, Q_v[3:0]} = {1'b0, BusA[3:0]} + {1'b0, B_i[3:0]} + {4'd0, ALU_Op[1] ^ (UseCarry & F_In[Flag_C])};
assign {Carry7_v, Q_v[6:4]}    = {1'b0, BusA[6:4]} + {1'b0, B_i[6:4]} + {3'd0, HalfCarry_v};
assign {Carry_v, Q_v[7]}       = {1'b0, BusA[7]} + {1'b0, B_i[7]} + {1'b0, Carry7_v};

// 8080: P is parity for add / sub too
assign Overflow_v = (mode == 2'd2) ? ~^Q_v : (Carry_v ^ Carry7_v);

logic [7:0] Q_t;
logic [8:0] DAA_Q;

always_comb begin
    Q_t   = 8'h00;     // VHDL "--------"
    F_Out = F_In;
    DAA_Q = 9'h000;
    case (ALU_Op)
    4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101, 4'b0110, 4'b0111: begin
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_C] = 1'b0;
        case (ALU_Op[2:0])
        3'b000, 3'b001: begin                  // ADD, ADC
            Q_t = Q_v;
            F_Out[Flag_C] = Carry_v;
            F_Out[Flag_H] = HalfCarry_v;
            F_Out[Flag_P] = Overflow_v;
        end
        3'b010, 3'b011, 3'b111: begin          // SUB, SBC, CP
            Q_t = Q_v;
            F_Out[Flag_N] = 1'b1;
            F_Out[Flag_C] = ~Carry_v;
            F_Out[Flag_H] = ~HalfCarry_v;
            F_Out[Flag_P] = Overflow_v;
        end
        3'b100: begin                          // AND
            Q_t = BusA & BusB;
            F_Out[Flag_H] = 1'b1;
        end
        3'b101: begin                          // XOR
            Q_t = BusA ^ BusB;
            F_Out[Flag_H] = 1'b0;
        end
        default: begin                         // OR
            Q_t = BusA | BusB;
            F_Out[Flag_H] = 1'b0;
        end
        endcase
        if (ALU_Op[2:0] == 3'b111) begin       // CP: X / Y from the operand
            F_Out[Flag_X] = BusB[3];
            F_Out[Flag_Y] = BusB[5];
        end else begin
            F_Out[Flag_X] = Q_t[3];
            F_Out[Flag_Y] = Q_t[5];
        end
        if (Q_t == 8'h00) begin
            F_Out[Flag_Z] = 1'b1;
            if (Z16)
                F_Out[Flag_Z] = F_In[Flag_Z];  // 16-bit ADC / SBC
        end else begin
            F_Out[Flag_Z] = 1'b0;
        end
        F_Out[Flag_S] = Q_t[7];
        case (ALU_Op[2:0])
        3'b000, 3'b001, 3'b010, 3'b011, 3'b111: ;
        default: F_Out[Flag_P] = ~^Q_t;
        endcase
        if (Arith16) begin
            F_Out[Flag_S] = F_In[Flag_S];
            F_Out[Flag_Z] = F_In[Flag_Z];
            F_Out[Flag_P] = F_In[Flag_P];
        end
    end
    4'b1100: begin                             // DAA
        if (mode == 2'd3) begin
            F_Out[Flag_H] = 1'b0;
            F_Out[Flag_C] = F_In[Flag_C];
            DAA_Q = {1'b0, BusA};
            if (!F_In[Flag_N]) begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H])
                    DAA_Q = DAA_Q + 9'd6;
                if (DAA_Q[8:4] > 5'd9 || F_In[Flag_C])
                    DAA_Q = DAA_Q + 9'd96;
            end else begin
                if (F_In[Flag_H]) begin
                    DAA_Q = DAA_Q - 9'd6;
                    if (!F_In[Flag_C])
                        DAA_Q[8] = 1'b0;
                end
                if (F_In[Flag_C])
                    DAA_Q = DAA_Q - 9'd96;
            end
        end else begin
            F_Out[Flag_H] = F_In[Flag_H];
            F_Out[Flag_C] = F_In[Flag_C];
            DAA_Q = {1'b0, BusA};
            if (!F_In[Flag_N]) begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin
                    F_Out[Flag_H] = (DAA_Q[3:0] > 4'd9);
                    DAA_Q = DAA_Q + 9'd6;
                end
                if (DAA_Q[8:4] > 5'd9 || F_In[Flag_C])
                    DAA_Q = DAA_Q + 9'd96;
            end else begin
                if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin
                    if (DAA_Q[3:0] > 4'd5)
                        F_Out[Flag_H] = 1'b0;
                    DAA_Q[7:0] = DAA_Q[7:0] - 8'd6;
                end
                if (BusA > 8'd153 || F_In[Flag_C])
                    DAA_Q = DAA_Q - 9'd352;
            end
        end
        F_Out[Flag_X] = DAA_Q[3];
        F_Out[Flag_Y] = DAA_Q[5];
        F_Out[Flag_C] = F_In[Flag_C] | DAA_Q[8];
        Q_t = DAA_Q[7:0];
        F_Out[Flag_Z] = (DAA_Q[7:0] == 8'h00);
        F_Out[Flag_S] = DAA_Q[7];
        F_Out[Flag_P] = ~^DAA_Q[7:0];
    end
    4'b1101, 4'b1110: begin                    // RLD, RRD
        Q_t[7:4] = BusA[7:4];
        Q_t[3:0] = ALU_Op[0] ? BusB[7:4] : BusB[3:0];
        F_Out[Flag_H] = 1'b0;
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_X] = Q_t[3];
        F_Out[Flag_Y] = Q_t[5];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_P] = ~^Q_t;
    end
    4'b1001: begin                             // BIT
        Q_t = BusB & BitMask;
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_P] = (Q_t == 8'h00);
        F_Out[Flag_H] = 1'b1;
        F_Out[Flag_N] = 1'b0;
        if (IR[2:0] == 3'b110 || XY_State != 2'b00) begin  // BIT n,(HL) / (IX+d): X / Y from MEMPTR
            F_Out[Flag_X] = WZ11;
            F_Out[Flag_Y] = WZ13;
        end else begin
            F_Out[Flag_X] = BusB[3];
            F_Out[Flag_Y] = BusB[5];
        end
    end
    4'b1010: Q_t = BusB | BitMask;             // SET
    4'b1011: Q_t = BusB & ~BitMask;            // RES
    4'b1000: begin                             // rotate / shift
        case (IR[5:3])
        3'b000: begin Q_t = {BusA[6:0], BusA[7]};     F_Out[Flag_C] = BusA[7]; end  // RLC
        3'b010: begin Q_t = {BusA[6:0], F_In[Flag_C]}; F_Out[Flag_C] = BusA[7]; end // RL
        3'b001: begin Q_t = {BusA[0], BusA[7:1]};     F_Out[Flag_C] = BusA[0]; end  // RRC
        3'b011: begin Q_t = {F_In[Flag_C], BusA[7:1]}; F_Out[Flag_C] = BusA[0]; end // RR
        3'b100: begin Q_t = {BusA[6:0], 1'b0};        F_Out[Flag_C] = BusA[7]; end  // SLA
        3'b110: begin                                                               // SLL (undocumented) / GB SWAP
            if (mode == 2'd3) begin
                Q_t = {BusA[3:0], BusA[7:4]};
                F_Out[Flag_C] = 1'b0;
            end else begin
                Q_t = {BusA[6:0], 1'b1};
                F_Out[Flag_C] = BusA[7];
            end
        end
        3'b101: begin Q_t = {BusA[7], BusA[7:1]};     F_Out[Flag_C] = BusA[0]; end  // SRA
        default: begin Q_t = {1'b0, BusA[7:1]};       F_Out[Flag_C] = BusA[0]; end  // SRL
        endcase
        F_Out[Flag_H] = 1'b0;
        F_Out[Flag_N] = 1'b0;
        F_Out[Flag_X] = Q_t[3];
        F_Out[Flag_Y] = Q_t[5];
        F_Out[Flag_S] = Q_t[7];
        F_Out[Flag_Z] = (Q_t == 8'h00);
        F_Out[Flag_P] = ~^Q_t;
        if (ISet == 2'b00) begin               // RLCA / RLA / RRCA / RRA keep S, Z, P
            F_Out[Flag_P] = F_In[Flag_P];
            F_Out[Flag_S] = F_In[Flag_S];
            F_Out[Flag_Z] = F_In[Flag_Z];
        end
        if (mode == 2'd3 && Rot_Akku)
            F_Out[Flag_Z] = 1'b0;
    end
    default: ;
    endcase
    Q = Q_t;
end

endmodule

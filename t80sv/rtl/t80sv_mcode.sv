//============================================================================
//  t80sv_mcode - Z80 / 8080 microcode decoder (combinational)
//
//  SystemVerilog translation of T80_MCode.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ, TobiFlex,
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
//  The case body is generated from the VHDL by verify/tools/mcode2sv.py.
//============================================================================

module t80sv_mcode #(
    parameter int MODE   = 0,          // build mode; is_cc_true follows it (GB has no PO / PE / P / M)
    parameter int Flag_C = 0,
    parameter int Flag_P = 2,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic [1:0] mode,           // runtime mode: 0 Z80, 1 fast Z80, 2 8080, 3 GB
    input  logic [7:0] IR,
    input  logic [1:0] ISet,
    input  logic [2:0] MCycle,
    input  logic [7:0] F,
    input  logic       NMICycle,
    input  logic       IntCycle,
    input  logic [1:0] XY_State,
    input  logic       R800_mode,
    output logic [2:0] MCycles,
    output logic [2:0] TStates,
    output logic [1:0] Prefix,         // none, CB, ED, DD / FD
    output logic       Inc_PC,
    output logic       Inc_WZ,
    output logic [3:0] IncDec_16,      // BC, DE, HL, SP; bit 3 = decrement
    output logic       Read_To_Reg,
    output logic       Read_To_Acc,
    output logic [3:0] Set_BusA_To,    // B, C, D, E, H, L, DI, A, SP(L), SP(M), 0, F
    output logic [3:0] Set_BusB_To,    // B, C, D, E, H, L, DI, A, SP(L), SP(M), 1, F, PC(L), PC(M), 0
    output logic [3:0] ALU_Op,
    output logic       Save_ALU,
    output logic       Rot_Akku,
    output logic       PreserveC,
    output logic       Arith16,
    output logic [2:0] Set_Addr_To,
    output logic       IORQ,
    output logic       Jump,
    output logic       JumpE,
    output logic       JumpXY,
    output logic       Call,
    output logic       RstP,
    output logic       LDZ,
    output logic       LDW,
    output logic       LDSPHL,
    output logic       LDHLSP,
    output logic       ADDSPdd,
    output logic [2:0] Special_LD,     // A,I; A,R; I,A; R,A; none
    output logic       ExchangeDH,
    output logic       ExchangeRp,
    output logic       ExchangeAF,
    output logic       ExchangeRS,
    output logic       ExchangeWH,
    output logic       I_DJNZ,
    output logic       I_CPL,
    output logic       I_CCF,
    output logic       I_SCF,
    output logic       I_RETN,
    output logic       I_BT,
    output logic       I_BC,
    output logic       I_BTR,
    output logic       I_RLD,
    output logic       I_RRD,
    output logic       I_INRC,
    output logic       I_MULUB,
    output logic       I_MULU,
    output logic [1:0] SetWZ,
    output logic       SetDI,
    output logic       SetEI,
    output logic [1:0] IMode,
    output logic       Halt,
    output logic       NoRead,
    output logic       Write,
    output logic       No_PC,
    output logic       XYbit_undoc
);

localparam logic [2:0] aNone = 3'b111;
localparam logic [2:0] aBC   = 3'b000;
localparam logic [2:0] aDE   = 3'b001;
localparam logic [2:0] aXY   = 3'b010;
localparam logic [2:0] aIOA  = 3'b100;
localparam logic [2:0] aSP   = 3'b101;
localparam logic [2:0] aZI   = 3'b110;

function automatic logic is_cc_true(input logic [7:0] f, input logic [2:0] cc);
    if (MODE == 3) begin
        case (cc)
        3'b000: is_cc_true = ~f[Flag_Z];
        3'b001: is_cc_true =  f[Flag_Z];
        3'b010: is_cc_true = ~f[Flag_C];
        3'b011: is_cc_true =  f[Flag_C];
        default: is_cc_true = 1'b0;
        endcase
    end else begin
    case (cc)
    3'b000: is_cc_true = ~f[Flag_Z];   // NZ
    3'b001: is_cc_true =  f[Flag_Z];   // Z
    3'b010: is_cc_true = ~f[Flag_C];   // NC
    3'b011: is_cc_true =  f[Flag_C];   // C
    3'b100: is_cc_true = ~f[Flag_P];   // PO
    3'b101: is_cc_true =  f[Flag_P];   // PE
    3'b110: is_cc_true = ~f[Flag_S];   // P
    default: is_cc_true = f[Flag_S];   // M
    endcase
    end
endfunction

logic [2:0] DDD, SSS;
logic [1:0] DPair;
assign DDD   = IR[5:3];
assign SSS   = IR[2:0];
assign DPair = IR[5:4];

always_comb begin
	MCycles = 3'b001;
	if (MCycle == 3'b001) begin
		TStates = 3'b100;
	end else begin
		TStates = 3'b011;
	end
	Prefix = 2'b00;
	Inc_PC = 1'b0;
	Inc_WZ = 1'b0;
	IncDec_16 = 4'b0000;
	Read_To_Acc = 1'b0;
	Read_To_Reg = 1'b0;
	Set_BusB_To = 4'b0000;
	Set_BusA_To = 4'b0000;
	ALU_Op = {1'b0, IR[5:3]};
	Save_ALU = 1'b0;
	Rot_Akku = 1'b0;
	PreserveC = 1'b0;
	Arith16 = 1'b0;
	IORQ = 1'b0;
	Set_Addr_To = aNone;
	Jump = 1'b0;
	JumpE = 1'b0;
	JumpXY = 1'b0;
	Call = 1'b0;
	RstP = 1'b0;
	LDZ = 1'b0;
	LDW = 1'b0;
	LDSPHL = 1'b0;
	LDHLSP = 1'b0;
	ADDSPdd = 1'b0;
	Special_LD = 3'b000;
	ExchangeDH = 1'b0;
	ExchangeRp = 1'b0;
	ExchangeAF = 1'b0;
	ExchangeRS = 1'b0;
	ExchangeWH = 1'b0;
	I_DJNZ = 1'b0;
	I_CPL = 1'b0;
	I_CCF = 1'b0;
	I_SCF = 1'b0;
	I_RETN = 1'b0;
	I_BT = 1'b0;
	I_BC = 1'b0;
	I_BTR = 1'b0;
	I_RLD = 1'b0;
	I_RRD = 1'b0;
	I_INRC = 1'b0;
	I_MULUB = 1'b0;
	I_MULU = 1'b0;
	SetDI = 1'b0;
	SetEI = 1'b0;
	IMode = 2'b11;
	Halt = 1'b0;
	NoRead = 1'b0;
	Write = 1'b0;
	No_PC = 1'b0;
	XYbit_undoc = 1'b0;
	SetWZ = 2'b00;
	case (ISet)
	2'b00: begin
		case (IR)
		8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h47, 8'h48,
		8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4F, 8'h50, 8'h51,
		8'h52, 8'h53, 8'h54, 8'h55, 8'h57, 8'h58, 8'h59, 8'h5A,
		8'h5B, 8'h5C, 8'h5D, 8'h5F, 8'h60, 8'h61, 8'h62, 8'h63,
		8'h64, 8'h65, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6F, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D,
		8'h7F: begin
			Set_BusB_To[2:0] = SSS;
			ExchangeRp = 1'b1;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
		end
		8'h06, 8'h0E, 8'h16, 8'h1E, 8'h26, 8'h2E, 8'h3E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Set_BusA_To[2:0] = DDD;
				Read_To_Reg = 1'b1;
			end
			default: ;
			endcase
		end
		8'h46, 8'h4E, 8'h56, 8'h5E, 8'h66, 8'h6E, 8'h7E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Set_BusA_To[2:0] = DDD;
				Read_To_Reg = 1'b1;
			end
			default: ;
			endcase
		end
		8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75, 8'h77: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h36: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Set_Addr_To = aXY;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h0A: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
			end
			3'd2: begin
				Read_To_Acc = 1'b1;
			end
			default: ;
			endcase
		end
		8'h1A: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aDE;
			end
			3'd2: begin
				Read_To_Acc = 1'b1;
			end
			default: ;
			endcase
		end
		8'h3A: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					Read_To_Acc = 1'b1;
					IncDec_16 = 4'b1110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
				end
				3'd4: begin
					Read_To_Acc = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h02: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				Set_BusB_To = 4'b0111;
				SetWZ = 2'b10;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h12: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aDE;
				Set_BusB_To = 4'b0111;
				SetWZ = 2'b10;
			end
			3'd2: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h32: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
					Set_BusB_To = 4'b0111;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					SetWZ = 2'b10;
					Inc_PC = 1'b1;
					Set_BusB_To = 4'b0111;
				end
				3'd4: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h01, 8'h11, 8'h21, 8'h31: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1000;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b1;
				end
			end
			3'd3: begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1001;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'h2A: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					Read_To_Acc = 1'b1;
					IncDec_16 = 4'b0110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
				end
				3'd4: begin
					Set_BusA_To[2:0] = 3'b101;
					Read_To_Reg = 1'b1;
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
				end
				3'd5: begin
					Set_BusA_To[2:0] = 3'b100;
					Read_To_Reg = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h22: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aXY;
					Set_BusB_To = 4'b0111;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b0110;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
					Set_BusB_To = 4'b0101;
				end
				3'd4: begin
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
					Write = 1'b1;
					Set_BusB_To = 4'b0100;
				end
				3'd5: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hF9: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				if (MCycle == 3'b010) begin
					LDSPHL = 1'b1;
				end
			end else begin
				TStates = 3'b110;
				LDSPHL = 1'b1;
			end
		end
		8'hC5, 8'hD5, 8'hE5, 8'hF5: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b0111;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
				end
				3'd3: begin
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b1011;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b1;
						Set_BusB_To[3] = 1'b0;
					end
					Write = 1'b1;
				end
				3'd4: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b0111;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
				end
				3'd2: begin
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					if (DPair == 2'b11) begin
						Set_BusB_To = 4'b1011;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b1;
						Set_BusB_To[3] = 1'b0;
					end
					Write = 1'b1;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC1, 8'hD1, 8'hE1, 8'hF1: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aSP;
			end
			3'd2: begin
				IncDec_16 = 4'b0111;
				Set_Addr_To = aSP;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b1011;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b1;
				end
			end
			3'd3: begin
				IncDec_16 = 4'b0111;
				Read_To_Reg = 1'b1;
				if (DPair == 2'b11) begin
					Set_BusA_To[3:0] = 4'b0111;
				end else begin
					Set_BusA_To[2:1] = DPair;
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'hEB: begin
			if (mode != 3) begin
				ExchangeDH = 1'b1;
			end
		end
		8'h08: begin
			if (mode == 3) begin
				MCycles = 3'b101;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Set_Addr_To = aZI;
					Inc_PC = 1'b1;
					LDW = 1'b1;
					Set_BusB_To = 4'b1000;
				end
				3'd4: begin
					Inc_WZ = 1'b1;
					Set_Addr_To = aZI;
					Write = 1'b1;
					Set_BusB_To = 4'b1001;
				end
				3'd5: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				ExchangeAF = 1'b1;
			end
		end
		8'hD9: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd3: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
					SetEI = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				ExchangeRS = 1'b1;
			end
		end
		8'hE3: begin
			if (mode != 3) begin
				MCycles = 3'b101;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					Set_Addr_To = aSP;
					LDZ = 1'b1;
					IncDec_16 = 4'b0111;
				end
				3'd3: begin
					TStates = 3'b100;
					Set_BusB_To = 4'b0100;
					Set_Addr_To = aSP;
					LDW = 1'b1;
				end
				3'd4: begin
					Set_BusB_To = 4'b0101;
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
				end
				3'd5: begin
					ExchangeWH = 1'b1;
					TStates = 3'b101;
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h87, 8'h88,
		8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8F, 8'h90, 8'h91,
		8'h92, 8'h93, 8'h94, 8'h95, 8'h97, 8'h98, 8'h99, 8'h9A,
		8'h9B, 8'h9C, 8'h9D, 8'h9F, 8'hA0, 8'hA1, 8'hA2, 8'hA3,
		8'hA4, 8'hA5, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC,
		8'hAD, 8'hAF, 8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5,
		8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBF: begin
			Set_BusB_To[2:0] = SSS;
			Set_BusA_To[2:0] = 3'b111;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
		end
		8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusB_To[2:0] = SSS;
				Set_BusA_To[2:0] = 3'b111;
			end
			default: ;
			endcase
		end
		8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE: begin
			MCycles = 3'b010;
			if (MCycle == 3'b010) begin
				Inc_PC = 1'b1;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusB_To[2:0] = SSS;
				Set_BusA_To[2:0] = 3'b111;
			end
		end
		8'h04, 8'h0C, 8'h14, 8'h1C, 8'h24, 8'h2C, 8'h3C: begin
			Set_BusB_To = 4'b1010;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
			PreserveC = 1'b1;
			ALU_Op = 4'b0000;
		end
		8'h34: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				TStates = 3'b100;
				Set_Addr_To = aXY;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				ALU_Op = 4'b0000;
				Set_BusB_To = 4'b1010;
				Set_BusA_To[2:0] = DDD;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h05, 8'h0D, 8'h15, 8'h1D, 8'h25, 8'h2D, 8'h3D: begin
			Set_BusB_To = 4'b1010;
			Set_BusA_To[2:0] = DDD;
			Read_To_Reg = 1'b1;
			Save_ALU = 1'b1;
			PreserveC = 1'b1;
			ALU_Op = 4'b0010;
		end
		8'h35: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				TStates = 3'b100;
				Set_Addr_To = aXY;
				ALU_Op = 4'b0010;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				Set_BusB_To = 4'b1010;
				Set_BusA_To[2:0] = DDD;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h27: begin
			Set_BusA_To[2:0] = 3'b111;
			Read_To_Reg = 1'b1;
			ALU_Op = 4'b1100;
			Save_ALU = 1'b1;
		end
		8'h2F: begin
			I_CPL = 1'b1;
		end
		8'h3F: begin
			I_CCF = 1'b1;
		end
		8'h37: begin
			I_SCF = 1'b1;
		end
		8'h00: begin
			if (NMICycle == 1'b1) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end else if (IntCycle == 1'b1) begin
				if (mode == 3) begin
					MCycles = 3'b100;
					case (MCycle)
					3'd1: begin
						TStates = 3'b110;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1101;
					end
					3'd2: begin
						Write = 1'b1;
					end
					3'd3: begin
						LDZ = 1'b1;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1100;
					end
					3'd4: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end else begin
					MCycles = 3'b101;
					case (MCycle)
					3'd1: begin
						TStates = 3'b101;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1101;
					end
					3'd2: begin
						Write = 1'b1;
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						Set_BusB_To = 4'b1100;
					end
					3'd3: begin
						Write = 1'b1;
					end
					3'd4: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd5: begin
						Jump = 1'b1;
					end
					default: ;
					endcase
				end
			end
		end
		8'h76: begin
			Halt = 1'b1;
		end
		8'hF3: begin
			SetDI = 1'b1;
		end
		8'hFB: begin
			SetEI = 1'b1;
		end
		8'h09, 8'h19, 8'h29, 8'h39: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					ALU_Op = 4'b0000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_BusA_To[2:0] = 3'b101;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
						Set_BusB_To[0] = 1'b1;
					end
					default: begin
						Set_BusB_To = 4'b1000;
					end
					endcase
					TStates = 3'b100;
					Arith16 = 1'b1;
					SetWZ = 2'b11;
				end
				3'd2: begin
					NoRead = 1'b1;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0001;
					Set_BusA_To[2:0] = 3'b100;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
					end
					default: begin
						Set_BusB_To = 4'b1001;
					end
					endcase
					Arith16 = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					No_PC = 1'b1;
				end
				3'd2: begin
					NoRead = 1'b1;
					ALU_Op = 4'b0000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_BusA_To[2:0] = 3'b101;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
						Set_BusB_To[0] = 1'b1;
					end
					default: begin
						Set_BusB_To = 4'b1000;
					end
					endcase
					TStates = 3'b100;
					Arith16 = 1'b1;
					SetWZ = 2'b11;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0001;
					Set_BusA_To[2:0] = 3'b100;
					case (IR[5:4])
					2'd0, 2'd1, 2'd2: begin
						Set_BusB_To[2:1] = IR[5:4];
					end
					default: begin
						Set_BusB_To = 4'b1001;
					end
					endcase
					Arith16 = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h03, 8'h13, 8'h23, 8'h33: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd2: begin
					IncDec_16[3:2] = 2'b01;
					IncDec_16[1:0] = DPair;
				end
				default: ;
				endcase
			end else begin
				TStates = 3'b110;
				IncDec_16[3:2] = 2'b01;
				IncDec_16[1:0] = DPair;
			end
		end
		8'h0B, 8'h1B, 8'h2B, 8'h3B: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd2: begin
					IncDec_16[3:2] = 2'b11;
					IncDec_16[1:0] = DPair;
				end
				default: ;
				endcase
			end else begin
				TStates = 3'b110;
				IncDec_16[3:2] = 2'b11;
				IncDec_16[1:0] = DPair;
			end
		end
		8'h07, 8'h17, 8'h0F, 8'h1F: begin
			Set_BusA_To[2:0] = 3'b111;
			ALU_Op = 4'b1000;
			Read_To_Reg = 1'b1;
			Rot_Akku = 1'b1;
			Save_ALU = 1'b1;
		end
		8'hC3: begin
			if (mode == 3) begin
				MCycles = 3'b100;
			end else begin
				MCycles = 3'b011;
			end
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Inc_PC = 1'b1;
				Jump = 1'b1;
				if (mode != 3) begin
					LDW = 1'b1;
				end
			end
			default: ;
			endcase
		end
		8'hC2, 8'hCA, 8'hD2, 8'hDA, 8'hE2, 8'hEA, 8'hF2, 8'hFA: begin
			if (IR[5] == 1'b1 && mode == 3) begin
				case (IR[4:3])
				2'b00: begin
					MCycles = 3'b010;
					case (MCycle)
					3'd1: begin
						Set_Addr_To = aBC;
						Set_BusB_To = 4'b0111;
						IORQ = 1'b1;
					end
					3'd2: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b01: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd3: begin
						Set_Addr_To = aZI;
						Inc_PC = 1'b1;
						Set_BusB_To = 4'b0111;
					end
					3'd4: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b10: begin
					MCycles = 3'b010;
					case (MCycle)
					3'd1: begin
						Set_Addr_To = aBC;
						IORQ = 1'b1;
					end
					3'd2: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				2'b11: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						LDZ = 1'b1;
					end
					3'd3: begin
						Set_Addr_To = aZI;
						Inc_PC = 1'b1;
					end
					3'd4: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				endcase
			end else begin
				if (mode == 3) begin
					MCycles = 3'b100;
				end else begin
					MCycles = 3'b011;
				end
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					if (mode != 3) begin
						LDW = 1'b1;
					end
					Inc_PC = 1'b1;
					if (is_cc_true(F, IR[5:3])) begin
						Jump = 1'b1;
					end else if (mode == 3) begin
						MCycles = 3'b011;
					end
				end
				default: ;
				endcase
			end
		end
		8'h18: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h38: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_C] == 1'b0) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h30: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_C] == 1'b1) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h28: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_Z] == 1'b0) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'h20: begin
			if (mode != 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					if (F[Flag_Z] == 1'b1) begin
						MCycles = 3'b010;
					end else begin
						No_PC = 1'b1;
					end
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'hE9: begin
			JumpXY = 1'b1;
		end
		8'h10: begin
			if (mode == 3) begin
				MCycles = 3'b010;
				I_DJNZ = 1'b1;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
				end
				default: ;
				endcase
			end else if (mode < 2) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					I_DJNZ = 1'b1;
					Set_BusB_To = 4'b1010;
					Set_BusA_To[2:0] = 3'b000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					ALU_Op = 4'b0010;
				end
				3'd2: begin
					I_DJNZ = 1'b1;
					Inc_PC = 1'b1;
					No_PC = 1'b1;
				end
				3'd3: begin
					NoRead = 1'b1;
					JumpE = 1'b1;
					TStates = 3'b101;
				end
				default: ;
				endcase
			end
		end
		8'hCD: begin
			if (mode == 3) begin
				MCycles = 3'b110;
			end else begin
				MCycles = 3'b101;
			end
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				IncDec_16 = 4'b1111;
				Inc_PC = 1'b1;
				TStates = 3'b100;
				Set_Addr_To = aSP;
				LDW = 1'b1;
				Set_BusB_To = 4'b1101;
			end
			3'd4: begin
				Write = 1'b1;
				IncDec_16 = 4'b1111;
				Set_Addr_To = aSP;
				Set_BusB_To = 4'b1100;
			end
			3'd5: begin
				Write = 1'b1;
				Call = 1'b1;
			end
			default: ;
			endcase
		end
		8'hC4, 8'hCC, 8'hD4, 8'hDC, 8'hE4, 8'hEC, 8'hF4, 8'hFC: begin
			if (IR[5] == 1'b0 || mode != 3) begin
				if (mode == 3) begin
					MCycles = 3'b110;
				end else begin
					MCycles = 3'b101;
				end
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					LDZ = 1'b1;
				end
				3'd3: begin
					Inc_PC = 1'b1;
					LDW = 1'b1;
					if (is_cc_true(F, IR[5:3])) begin
						IncDec_16 = 4'b1111;
						Set_Addr_To = aSP;
						TStates = 3'b100;
						Set_BusB_To = 4'b1101;
					end else begin
						MCycles = 3'b011;
					end
				end
				3'd4: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd5: begin
					Write = 1'b1;
					Call = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC9: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					Set_Addr_To = aSP;
				end
				3'd3: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd4: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					Set_Addr_To = aSP;
				end
				3'd2: begin
					IncDec_16 = 4'b0111;
					Set_Addr_To = aSP;
					LDZ = 1'b1;
				end
				3'd3: begin
					Jump = 1'b1;
					IncDec_16 = 4'b0111;
				end
				default: ;
				endcase
			end
		end
		8'hC0, 8'hC8, 8'hD0, 8'hD8, 8'hE0, 8'hE8, 8'hF0, 8'hF8: begin
			if (IR[5] == 1'b1 && mode == 3) begin
				case (IR[4:3])
				2'b00: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						Set_Addr_To = aIOA;
						Set_BusB_To = 4'b0111;
					end
					3'd3: begin
						Write = 1'b1;
					end
					default: ;
					endcase
				end
				2'b01: begin
					MCycles = 3'b100;
					case (MCycle)
					3'd3: begin
						Inc_PC = 1'b1;
						ADDSPdd = 1'b1;
					end
					default: ;
					endcase
				end
				2'b10: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd2: begin
						Inc_PC = 1'b1;
						Set_Addr_To = aIOA;
					end
					3'd3: begin
						Read_To_Acc = 1'b1;
					end
					default: ;
					endcase
				end
				2'b11: begin
					MCycles = 3'b011;
					case (MCycle)
					3'd1: begin
						Inc_PC = 1'b1;
					end
					3'd2: begin
						LDHLSP = 1'b1;
						Inc_PC = 1'b1;
					end
					3'd3: begin
						LDHLSP = 1'b1;
					end
					default: ;
					endcase
				end
				endcase
			end else begin
				if (mode == 3) begin
					MCycles = 3'b101;
					case (MCycle)
					3'd2: begin
						if (is_cc_true(F, IR[5:3])) begin
							Set_Addr_To = aSP;
						end else begin
							MCycles = 3'b010;
						end
						TStates = 3'b101;
					end
					3'd3: begin
						IncDec_16 = 4'b0111;
						Set_Addr_To = aSP;
						LDZ = 1'b1;
					end
					3'd4: begin
						Jump = 1'b1;
						IncDec_16 = 4'b0111;
					end
					default: ;
					endcase
				end else begin
					MCycles = 3'b011;
					case (MCycle)
					3'd1: begin
						if (is_cc_true(F, IR[5:3])) begin
							Set_Addr_To = aSP;
						end else begin
							MCycles = 3'b001;
						end
						TStates = 3'b101;
					end
					3'd2: begin
						IncDec_16 = 4'b0111;
						Set_Addr_To = aSP;
						LDZ = 1'b1;
					end
					3'd3: begin
						Jump = 1'b1;
						IncDec_16 = 4'b0111;
					end
					default: ;
					endcase
				end
			end
		end
		8'hC7, 8'hCF, 8'hD7, 8'hDF, 8'hE7, 8'hEF, 8'hF7, 8'hFF: begin
			if (mode == 3) begin
				MCycles = 3'b100;
				case (MCycle)
				3'd2: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd3: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd4: begin
					Write = 1'b1;
					RstP = 1'b1;
				end
				default: ;
				endcase
			end else begin
				MCycles = 3'b011;
				case (MCycle)
				3'd1: begin
					TStates = 3'b101;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1101;
				end
				3'd2: begin
					Write = 1'b1;
					IncDec_16 = 4'b1111;
					Set_Addr_To = aSP;
					Set_BusB_To = 4'b1100;
				end
				3'd3: begin
					Write = 1'b1;
					RstP = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hDB: begin
			if (mode != 3) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					Set_Addr_To = aIOA;
				end
				3'd3: begin
					Read_To_Acc = 1'b1;
					IORQ = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hD3: begin
			if (mode != 3) begin
				MCycles = 3'b011;
				case (MCycle)
				3'd2: begin
					Inc_PC = 1'b1;
					Set_Addr_To = aIOA;
					Set_BusB_To = 4'b0111;
				end
				3'd3: begin
					Write = 1'b1;
					IORQ = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hCB: begin
			if (mode != 2) begin
				Prefix = 2'b01;
			end
		end
		8'hED: begin
			if (mode < 2) begin
				Prefix = 2'b10;
			end
		end
		8'hDD, 8'hFD: begin
			if (mode < 2) begin
				Prefix = 2'b11;
			end
		end
		endcase
	end
	2'b01: begin
		Set_BusA_To[2:0] = IR[2:0];
		Set_BusB_To[2:0] = IR[2:0];
		case (IR)
		8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h07, 8'h10,
		8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h17, 8'h08, 8'h09,
		8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0F, 8'h18, 8'h19, 8'h1A,
		8'h1B, 8'h1C, 8'h1D, 8'h1F, 8'h20, 8'h21, 8'h22, 8'h23,
		8'h24, 8'h25, 8'h27, 8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C,
		8'h2D, 8'h2F, 8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35,
		8'h37, 8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3F: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1000;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h06, 8'h16, 8'h0E, 8'h1E, 8'h2E, 8'h3E, 8'h26, 8'h36: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h40, 8'h41, 8'h42, 8'h43, 8'h44, 8'h45, 8'h47, 8'h48,
		8'h49, 8'h4A, 8'h4B, 8'h4C, 8'h4D, 8'h4F, 8'h50, 8'h51,
		8'h52, 8'h53, 8'h54, 8'h55, 8'h57, 8'h58, 8'h59, 8'h5A,
		8'h5B, 8'h5C, 8'h5D, 8'h5F, 8'h60, 8'h61, 8'h62, 8'h63,
		8'h64, 8'h65, 8'h67, 8'h68, 8'h69, 8'h6A, 8'h6B, 8'h6C,
		8'h6D, 8'h6F, 8'h70, 8'h71, 8'h72, 8'h73, 8'h74, 8'h75,
		8'h77, 8'h78, 8'h79, 8'h7A, 8'h7B, 8'h7C, 8'h7D, 8'h7F: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					Set_BusB_To[2:0] = IR[2:0];
					ALU_Op = 4'b1001;
				end
			end else begin
				MCycles = 3'b010;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1001;
					TStates = 3'b100;
				end
				default: ;
				endcase
			end
		end
		8'h46, 8'h4E, 8'h56, 8'h5E, 8'h66, 8'h6E, 8'h76, 8'h7E: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1001;
				TStates = 3'b100;
			end
			default: ;
			endcase
		end
		8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC7, 8'hC8,
		8'hC9, 8'hCA, 8'hCB, 8'hCC, 8'hCD, 8'hCF, 8'hD0, 8'hD1,
		8'hD2, 8'hD3, 8'hD4, 8'hD5, 8'hD7, 8'hD8, 8'hD9, 8'hDA,
		8'hDB, 8'hDC, 8'hDD, 8'hDF, 8'hE0, 8'hE1, 8'hE2, 8'hE3,
		8'hE4, 8'hE5, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
		8'hED, 8'hEF, 8'hF0, 8'hF1, 8'hF2, 8'hF3, 8'hF4, 8'hF5,
		8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD, 8'hFF: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1010;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1010;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'hC6, 8'hCE, 8'hD6, 8'hDE, 8'hE6, 8'hEE, 8'hF6, 8'hFE: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1010;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h87, 8'h88,
		8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8F, 8'h90, 8'h91,
		8'h92, 8'h93, 8'h94, 8'h95, 8'h97, 8'h98, 8'h99, 8'h9A,
		8'h9B, 8'h9C, 8'h9D, 8'h9F, 8'hA0, 8'hA1, 8'hA2, 8'hA3,
		8'hA4, 8'hA5, 8'hA7, 8'hA8, 8'hA9, 8'hAA, 8'hAB, 8'hAC,
		8'hAD, 8'hAF, 8'hB0, 8'hB1, 8'hB2, 8'hB3, 8'hB4, 8'hB5,
		8'hB7, 8'hB8, 8'hB9, 8'hBA, 8'hBB, 8'hBC, 8'hBD, 8'hBF: begin
			if (XY_State==2'b00) begin
				if (MCycle == 3'b001) begin
					ALU_Op = 4'b1011;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
				end
			end else begin
				MCycles = 3'b011;
				XYbit_undoc = 1'b1;
				case (MCycle)
				3'd1, 3'd7: begin
					Set_Addr_To = aXY;
				end
				3'd2: begin
					ALU_Op = 4'b1011;
					Read_To_Reg = 1'b1;
					Save_ALU = 1'b1;
					Set_Addr_To = aXY;
					TStates = 3'b100;
				end
				3'd3: begin
					Write = 1'b1;
				end
				default: ;
				endcase
			end
		end
		8'h86, 8'h8E, 8'h96, 8'h9E, 8'hA6, 8'hAE, 8'hB6, 8'hBE: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1, 3'd7: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				ALU_Op = 4'b1011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_Addr_To = aXY;
				TStates = 3'b100;
			end
			3'd3: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		endcase
	end
	default: begin
		case (IR)
		8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
		8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
		8'h10, 8'h11, 8'h12, 8'h13, 8'h14, 8'h15, 8'h16, 8'h17,
		8'h18, 8'h19, 8'h1A, 8'h1B, 8'h1C, 8'h1D, 8'h1E, 8'h1F,
		8'h20, 8'h21, 8'h22, 8'h23, 8'h24, 8'h25, 8'h26, 8'h27,
		8'h28, 8'h29, 8'h2A, 8'h2B, 8'h2C, 8'h2D, 8'h2E, 8'h2F,
		8'h30, 8'h31, 8'h32, 8'h33, 8'h34, 8'h35, 8'h36, 8'h37,
		8'h38, 8'h39, 8'h3A, 8'h3B, 8'h3C, 8'h3D, 8'h3E, 8'h3F,
		8'h80, 8'h81, 8'h82, 8'h83, 8'h84, 8'h85, 8'h86, 8'h87,
		8'h88, 8'h89, 8'h8A, 8'h8B, 8'h8C, 8'h8D, 8'h8E, 8'h8F,
		8'h90, 8'h91, 8'h92, 8'h93, 8'h94, 8'h95, 8'h96, 8'h97,
		8'h98, 8'h99, 8'h9A, 8'h9B, 8'h9C, 8'h9D, 8'h9E, 8'h9F,
		8'hA4, 8'hA5, 8'hA6, 8'hA7, 8'hAC, 8'hAD, 8'hAE, 8'hAF,
		8'hB4, 8'hB5, 8'hB6, 8'hB7, 8'hBC, 8'hBD, 8'hBE, 8'hBF,
		8'hC0, 8'hC2, 8'hC4, 8'hC5, 8'hC6, 8'hC7, 8'hC8, 8'hCA,
		8'hCB, 8'hCC, 8'hCD, 8'hCE, 8'hCF, 8'hD0, 8'hD2, 8'hD3,
		8'hD4, 8'hD5, 8'hD6, 8'hD7, 8'hD8, 8'hDA, 8'hDB, 8'hDC,
		8'hDD, 8'hDE, 8'hDF, 8'hE0, 8'hE1, 8'hE2, 8'hE3, 8'hE4,
		8'hE5, 8'hE6, 8'hE7, 8'hE8, 8'hE9, 8'hEA, 8'hEB, 8'hEC,
		8'hED, 8'hEE, 8'hEF, 8'hF0, 8'hF1, 8'hF2, 8'hF4, 8'hF5,
		8'hF6, 8'hF7, 8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFD,
		8'hFE, 8'hFF: ;
		8'h77, 8'h7F: ;
		8'h57: begin
			Special_LD = 3'b100;
			TStates = 3'b101;
		end
		8'h5F: begin
			Special_LD = 3'b101;
			TStates = 3'b101;
		end
		8'h47: begin
			Special_LD = 3'b110;
			TStates = 3'b101;
		end
		8'h4F: begin
			Special_LD = 3'b111;
			TStates = 3'b101;
		end
		8'h4B, 8'h5B, 8'h6B, 8'h7B: begin
			MCycles = 3'b101;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Set_Addr_To = aZI;
				Inc_PC = 1'b1;
				LDW = 1'b1;
			end
			3'd4: begin
				Read_To_Reg = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusA_To = 4'b1000;
				end else begin
					Set_BusA_To[2:1] = IR[5:4];
					Set_BusA_To[0] = 1'b1;
				end
				Inc_WZ = 1'b1;
				Set_Addr_To = aZI;
			end
			3'd5: begin
				Read_To_Reg = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusA_To = 4'b1001;
				end else begin
					Set_BusA_To[2:1] = IR[5:4];
					Set_BusA_To[0] = 1'b0;
				end
			end
			default: ;
			endcase
		end
		8'h43, 8'h53, 8'h63, 8'h73: begin
			MCycles = 3'b101;
			case (MCycle)
			3'd2: begin
				Inc_PC = 1'b1;
				LDZ = 1'b1;
			end
			3'd3: begin
				Set_Addr_To = aZI;
				Inc_PC = 1'b1;
				LDW = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusB_To = 4'b1000;
				end else begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
					Set_BusB_To[3] = 1'b0;
				end
			end
			3'd4: begin
				Inc_WZ = 1'b1;
				Set_Addr_To = aZI;
				Write = 1'b1;
				if (IR[5:4] == 2'b11) begin
					Set_BusB_To = 4'b1001;
				end else begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b0;
					Set_BusB_To[3] = 1'b0;
				end
			end
			3'd5: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'hA0, 8'hA8, 8'hB0, 8'hB8: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				IncDec_16 = 4'b1100;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b0000;
				Set_Addr_To = aDE;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
			end
			3'd3: begin
				I_BT = 1'b1;
				TStates = 3'b101;
				Write = 1'b1;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0101;
				end else begin
					IncDec_16 = 4'b1101;
				end
				No_PC = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hA1, 8'hA9, 8'hB1, 8'hB9: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
				IncDec_16 = 4'b1100;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b0111;
				Save_ALU = 1'b1;
				PreserveC = 1'b1;
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				I_BC = 1'b1;
				TStates = 3'b101;
				No_PC = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'h44, 8'h4C, 8'h54, 8'h5C, 8'h64, 8'h6C, 8'h74, 8'h7C: begin
			ALU_Op = 4'b0010;
			Set_BusB_To = 4'b0111;
			Set_BusA_To = 4'b1010;
			Read_To_Acc = 1'b1;
			Save_ALU = 1'b1;
		end
		8'h46, 8'h4E, 8'h66, 8'h6E: begin
			IMode = 2'b00;
		end
		8'h56, 8'h76: begin
			IMode = 2'b01;
		end
		8'h5E, 8'h7E: begin
			IMode = 2'b10;
		end
		8'h4A, 8'h5A, 8'h6A, 8'h7A: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				No_PC = 1'b1;
			end
			3'd2: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0001;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b101;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
				end
				default: begin
					Set_BusB_To = 4'b1000;
				end
				endcase
				TStates = 3'b100;
				SetWZ = 2'b11;
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0001;
				Set_BusA_To[2:0] = 3'b100;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b0;
				end
				default: begin
					Set_BusB_To = 4'b1001;
				end
				endcase
			end
			default: ;
			endcase
		end
		8'h42, 8'h52, 8'h62, 8'h72: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				No_PC = 1'b1;
			end
			3'd2: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b101;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
					Set_BusB_To[0] = 1'b1;
				end
				default: begin
					Set_BusB_To = 4'b1000;
				end
				endcase
				TStates = 3'b100;
				SetWZ = 2'b11;
				No_PC = 1'b1;
			end
			3'd3: begin
				NoRead = 1'b1;
				ALU_Op = 4'b0011;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				Set_BusA_To[2:0] = 3'b100;
				case (IR[5:4])
				2'd0, 2'd1, 2'd2: begin
					Set_BusB_To[2:1] = IR[5:4];
				end
				default: begin
					Set_BusB_To = 4'b1001;
				end
				endcase
			end
			default: ;
			endcase
		end
		8'h6F: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Set_BusB_To[2:0] = 3'b110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b1101;
				Save_ALU = 1'b1;
				No_PC = 1'b1;
			end
			3'd3: begin
				TStates = 3'b100;
				I_RLD = 1'b1;
				NoRead = 1'b1;
				Set_Addr_To = aXY;
			end
			3'd4: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h67: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aXY;
			end
			3'd2: begin
				Read_To_Reg = 1'b1;
				Set_BusB_To[2:0] = 3'b110;
				Set_BusA_To[2:0] = 3'b111;
				ALU_Op = 4'b1110;
				Save_ALU = 1'b1;
				No_PC = 1'b1;
			end
			3'd3: begin
				TStates = 3'b100;
				I_RRD = 1'b1;
				NoRead = 1'b1;
				Set_Addr_To = aXY;
			end
			3'd4: begin
				Write = 1'b1;
			end
			default: ;
			endcase
		end
		8'h45, 8'h4D, 8'h55, 8'h5D, 8'h65, 8'h6D, 8'h75, 8'h7D: begin
			MCycles = 3'b011;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aSP;
			end
			3'd2: begin
				IncDec_16 = 4'b0111;
				Set_Addr_To = aSP;
				LDZ = 1'b1;
			end
			3'd3: begin
				Jump = 1'b1;
				IncDec_16 = 4'b0111;
				LDW = 1'b1;
				I_RETN = 1'b1;
			end
			default: ;
			endcase
		end
		8'h40, 8'h48, 8'h50, 8'h58, 8'h60, 8'h68, 8'h70, 8'h78: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				SetWZ = 2'b01;
			end
			3'd2: begin
				IORQ = 1'b1;
				if (IR[5:3] != 3'b110) begin
					Read_To_Reg = 1'b1;
					Set_BusA_To[2:0] = IR[5:3];
				end
				I_INRC = 1'b1;
			end
			default: ;
			endcase
		end
		8'h41, 8'h49, 8'h51, 8'h59, 8'h61, 8'h69, 8'h71, 8'h79: begin
			MCycles = 3'b010;
			case (MCycle)
			3'd1: begin
				Set_Addr_To = aBC;
				SetWZ = 2'b01;
				Set_BusB_To[2:0] = IR[5:3];
				if (IR[5:3] == 3'b110) begin
					Set_BusB_To[3] = 1'b1;
				end
			end
			3'd2: begin
				Write = 1'b1;
				IORQ = 1'b1;
			end
			default: ;
			endcase
		end
		8'hA2, 8'hAA, 8'hB2, 8'hBA: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				TStates = 3'b101;
				Set_Addr_To = aBC;
				Set_BusB_To = 4'b1010;
				Set_BusA_To = 4'b0000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0010;
				SetWZ = 2'b11;
				IncDec_16[3] = IR[3];
			end
			3'd2: begin
				IORQ = 1'b1;
				Set_BusB_To = 4'b0110;
				Set_Addr_To = aXY;
			end
			3'd3: begin
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				Write = 1'b1;
				I_BTR = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hA3, 8'hAB, 8'hB3, 8'hBB: begin
			MCycles = 3'b100;
			case (MCycle)
			3'd1: begin
				TStates = 3'b101;
				Set_Addr_To = aXY;
				Set_BusB_To = 4'b1010;
				Set_BusA_To = 4'b0000;
				Read_To_Reg = 1'b1;
				Save_ALU = 1'b1;
				ALU_Op = 4'b0010;
			end
			3'd2: begin
				Set_BusB_To = 4'b0110;
				Set_Addr_To = aBC;
				SetWZ = 2'b11;
				IncDec_16[3] = IR[3];
			end
			3'd3: begin
				if (IR[3] == 1'b0) begin
					IncDec_16 = 4'b0110;
				end else begin
					IncDec_16 = 4'b1110;
				end
				IORQ = 1'b1;
				Write = 1'b1;
				I_BTR = 1'b1;
			end
			3'd4: begin
				NoRead = 1'b1;
				TStates = 3'b101;
			end
			default: ;
			endcase
		end
		8'hC1, 8'hC9, 8'hD1, 8'hD9: begin
			if (R800_mode == 1'b1) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					I_MULUB = 1'b1;
					Set_BusB_To[2:0] = IR[5:3];
					Set_BusB_To[3] = 1'b0;
				end
				3'd2: begin
					NoRead = 1'b1;
					I_MULU = 1'b1;
					Set_BusA_To[2:0] = 3'b100;
				end
				default: ;
				endcase
			end
		end
		8'hC3, 8'hF3: begin
			if (R800_mode == 1'b1) begin
				MCycles = 3'b010;
				case (MCycle)
				3'd1: begin
					NoRead = 1'b1;
					if (DPair == 2'b11) begin
						Set_BusB_To[3:0] = 4'b1000;
					end else begin
						Set_BusB_To[2:1] = DPair;
						Set_BusB_To[0] = 1'b0;
						Set_BusB_To[3] = 1'b0;
					end
					Set_BusA_To[2:0] = 3'b100;
				end
				3'd2: begin
					TStates = 3'b101;
					NoRead = 1'b1;
					I_MULU = 1'b1;
					Set_BusA_To[2:0] = 3'b100;
				end
				default: ;
				endcase
			end
		end
		endcase
	end
	endcase
	if (mode == 1) begin
		if (!(MCycle == 3'b001)) begin
			TStates = 3'b011;
		end
	end
	if (mode == 3) begin
		if (!(MCycle == 3'b001)) begin
			TStates = 3'b100;
		end
	end
	if (mode < 2) begin
		if (MCycle == 3'b110) begin
			Inc_PC = 1'b1;
			if (mode == 1) begin
				Set_Addr_To = aXY;
				TStates = 3'b100;
				Set_BusB_To[2:0] = SSS;
				Set_BusB_To[3] = 1'b0;
			end
			if (IR == 8'h36 || IR == 8'hCB) begin
				Set_Addr_To = aNone;
			end
			if (!(IR == 8'h36 || ISet == 2'b01)) begin
				No_PC = 1'b1;
			end
		end
		if (MCycle == 3'b111) begin
			if (mode == 0) begin
				TStates = 3'b101;
			end
			if (ISet != 2'b01) begin
				Set_Addr_To = aXY;
			end
			Set_BusB_To[2:0] = SSS;
			Set_BusB_To[3] = 1'b0;
			if (IR == 8'h36 || ISet == 2'b01) begin
				Inc_PC = 1'b1;
			end else begin
				NoRead = 1'b1;
			end
		end
	end
end

endmodule

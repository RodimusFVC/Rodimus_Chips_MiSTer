// t65sv: 6502-family CPU core in SystemVerilog.
//
// Derived from T65 (VHDL), the 65xx compatible microprocessor core by Daniel Wallner, with fixes and
// extensions by Mike Johnson (MikeJ), Wolfgang Scherr (WoS), Morten Leikvoll (ML), SzGy and
// contributors, as maintained in the MiSTer-devel lineage (T65 Ver 315 SzGy April 2020).
//
// With all parameters at their defaults and Mode = 2'b00 this core is cycle- and pin-identical to
// T65 Ver 315 Mode "00", including the places where T65 differs from real NMOS silicon.
//
// Original T65 notice (retained as its licence requires):
//
// Copyright (c) 2002...2015
//               Daniel Wallner (jesus <at> opencores <dot> org)
//               Mike Johnson   (mikej <at> fpgaarcade <dot> com)
//               Wolfgang Scherr (WoS <at> pin4 <dot> at>
//               Morten Leikvoll ()
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

module t65sv #(
  // 0: NMOS only (Mode input ignored). 1: WDC 65C02, 2: Rockwell R65C02,
  // 3: Synertek/GTE 65SC02. When nonzero, Mode != 2'b00 selects the 65C02 at runtime.
  parameter int C02        = 0,
  // 1: always 65C02 (Mode ignored), for tops that are only ever a 65C02; the NMOS table folds away.
  parameter bit C02_FIXED  = 1'b0,
  // 1: 2A03/2A07 behaviour, D flag settable but ADC/SBC/ARR always binary (NMOS path).
  parameter bit NO_DECIMAL = 1'b0,
  // 1: the core is a W65C816S (module t65sv816; Mode, SO_n and BCD_en are ignored). The 6502 logic then drives
  // nothing and synthesis removes it. 0: no 65C816 logic at all.
  parameter bit C816       = 1'b0
) (
  input  logic [1:0]  Mode,
  input  logic        Res_n,
  input  logic        Enable,
  input  logic        Clk,
  input  logic        Rdy,
  /* verilator lint_off UNUSED */
  input  logic        Abort_n,   // accepted for port compatibility; T65 ignores it too
  /* verilator lint_on UNUSED */
  input  logic        IRQ_n,
  input  logic        NMI_n,
  input  logic        SO_n,
  input  logic        BCD_en,  // upstream T65 (C64_MiSTer) extension: 0 = decimal mode disabled (2A03)
  output logic        R_W_n,
  output logic        Sync,
  output logic        EF,
  output logic        MF,
  output logic        XF,
  output logic        ML_n,
  output logic        VP_n,
  output logic        VDA,
  output logic        VPA,
  output logic [23:0] A,
  input  logic [7:0]  DI,
  output logic [7:0]  DO,
  output logic [63:0] Regs,
  output logic [47:0] DEBUG,   // {I, A, X, Y, S, P}: T65's T_t65_dbg record, packed
  output logic        NMI_ack
);

  // ---------------------------------------------------------------- encodings
  localparam logic [2:0] CYC_SYNC = 3'd0;

  localparam logic [4:0] ALU_OR  = 5'd0,  ALU_AND = 5'd1,  ALU_EOR = 5'd2,  ALU_ADC = 5'd3,
                         ALU_EQ1 = 5'd4,  ALU_EQ2 = 5'd5,  ALU_CMP = 5'd6,  ALU_SBC = 5'd7,
                         ALU_ASL = 5'd8,  ALU_ROL = 5'd9,  ALU_LSR = 5'd10, ALU_ROR = 5'd11,
                         ALU_BIT = 5'd12, ALU_DEC = 5'd13, ALU_INC = 5'd14, ALU_ARR = 5'd15,
                         ALU_ANC = 5'd16, ALU_SAX = 5'd17, ALU_XAA = 5'd18,
                         ALU_TSB = 5'd19, ALU_TRB = 5'd20, ALU_BITZ = 5'd21, ALU_RSMB = 5'd22;

  localparam logic [3:0] BA_DI = 4'd0, BA_ABC = 4'd1, BA_X = 4'd2, BA_Y = 4'd3, BA_S = 4'd4,
                         BA_P = 4'd5, BA_DA = 4'd6, BA_DAO = 4'd7, BA_DAX = 4'd8, BA_AAX = 4'd9;

  localparam logic [1:0] AD_PBR = 2'd0, AD_SP = 2'd1, AD_ZPG = 2'd2, AD_BA = 2'd3;

  localparam logic [3:0] WD_DL = 4'd0, WD_ABC = 4'd1, WD_X = 4'd2, WD_Y = 4'd3, WD_S = 4'd4,
                         WD_P = 4'd5, WD_PCL = 4'd6, WD_PCH = 4'd7, WD_AX = 4'd8, WD_AXB = 4'd9,
                         WD_XB = 4'd10, WD_YB = 4'd11, WD_ZERO = 4'd12;

  // ---------------------------------------------------------------- registers
  logic [7:0]  ABC, X, Y;
  logic [7:0]  P, AD, DL;
  logic [7:0]  BAH;
  logic [8:0]  BAL;
  logic [7:0]  PBR, DBR;
  logic [15:0] PC, S;
  logic        EF_i, MF_i, XF_i;
  logic [7:0]  IR;
  logic [2:0]  MCycle;
  logic [1:0]  Mode_r;
  logic        BCD_en_r;
  logic [4:0]  ALU_Op_r;
  logic [3:0]  Write_Data_r;
  logic [1:0]  Set_Addr_To_r;
  logic        RstCycle, IRQCycle, NMICycle;
  logic        SO_n_o, IRQ_n_o, NMI_n_o, NMIAct;
  logic [7:0]  BusA_r, BusB, BusB_r;
  logic        Res_n_i, Res_n_d;
  logic        rdy_mod;
  logic        WRn_i;
  logic        NMI_entered;

  // outputs of the 6502 / 65C02 logic (the ports are driven from these, or from the 65C816 engine; with C816 = 1
  // they have no load)
  /* verilator lint_off UNUSED */
  logic        o_R_W_n, o_Sync, o_EF, o_MF, o_XF, o_ML_n, o_VP_n, o_VDA, o_VPA, o_NMI_ack;
  logic [23:0] o_A;
  logic [7:0]  o_DO;
  logic [63:0] o_Regs;
  logic [47:0] o_DEBUG;
  /* verilator lint_on UNUSED */

  // ---------------------------------------------------------------- combinational
  logic [7:0]  BusA, ALU_Q, P_Out, DO_r, PwithB;
  logic [8:0]  PCAdder;
  logic        Break, really_rdy;

  logic [8:0]  PCRel;
  logic        c02;
  logic        dec_en;

  // micro code outputs (NMOS table n_*, 65C02 table c_*, selected per instruction by c02)
  logic [2:0]  LCycle, n_LCycle, c_LCycle;
  logic [4:0]  ALU_Op, n_ALU_Op, c_ALU_Op;
  logic [3:0]  Set_BusA_To, n_Set_BusA_To, c_Set_BusA_To;
  logic [1:0]  Set_Addr_To, n_Set_Addr_To, c_Set_Addr_To;
  logic [3:0]  Write_Data, n_Write_Data, c_Write_Data;
  logic [1:0]  Jump, n_Jump, c_Jump;
  logic [1:0]  BAAdd, n_BAAdd, c_BAAdd;
  logic [1:0]  BAQuirk, n_BAQuirk;
  logic        BreakAtNA, n_BreakAtNA;
  logic        ADAdd, n_ADAdd, c_ADAdd;
  logic        AddY, n_AddY, c_AddY;
  logic        PCAdd, n_PCAdd, c_PCAdd;
  logic        Inc_S, n_Inc_S, c_Inc_S;
  logic        Dec_S, n_Dec_S, c_Dec_S;
  logic        LDA, n_LDA, c_LDA;
  logic        LDP, n_LDP, c_LDP;
  logic        LDX, n_LDX, c_LDX;
  logic        LDY, n_LDY, c_LDY;
  logic        LDS, n_LDS, c_LDS;
  logic        LDDI, n_LDDI, c_LDDI;
  logic        LDALU, n_LDALU, c_LDALU;
  logic        LDAD, n_LDAD, c_LDAD;
  logic        LDBAL, n_LDBAL, c_LDBAL;
  logic        LDBAH, n_LDBAH, c_LDBAH;
  logic        SaveP, n_SaveP, c_SaveP;
  logic        Write, n_Write, c_Write;
  logic        n_ALUmore;
  // 65C02-only controls
  logic        PCDec, c_PCDec;       // PC <= PC - 1 (JMP (a,x) dummy read of the operand)
  logic        PCHfix, c_PCHfix;     // branch page cross: PCH +/- 1 one cycle after PCL
  logic        BAInc16, c_BAInc16;   // 16-bit pointer increment (JMP (a) has no page-wrap bug)
  logic        Hold, c_Hold;         // WAI / STP

  // ================================================================ NMOS micro code
  logic n_Branch;
  always_comb begin
    case (IR[7:5])
      3'd0: n_Branch = ~P[7];
      3'd1: n_Branch =  P[7];
      3'd2: n_Branch = ~P[6];
      3'd3: n_Branch =  P[6];
      3'd4: n_Branch = ~P[0];
      3'd5: n_Branch =  P[0];
      3'd6: n_Branch = ~P[1];
      default: n_Branch = P[1];
    endcase
  end

  always_comb begin
    n_LCycle      = 3'd1;
    n_Set_BusA_To = BA_ABC;
    n_Set_Addr_To = AD_PBR;
    n_Write_Data  = WD_DL;
    n_Jump        = 2'b00;
    n_BAAdd       = 2'b00;
    n_BAQuirk     = 2'b00;
    n_BreakAtNA   = 1'b0;
    n_ADAdd       = 1'b0;
    n_PCAdd       = 1'b0;
    n_Inc_S       = 1'b0;
    n_Dec_S       = 1'b0;
    n_LDA         = 1'b0;
    n_LDP         = 1'b0;
    n_LDX         = 1'b0;
    n_LDY         = 1'b0;
    n_LDS         = 1'b0;
    n_LDDI        = 1'b0;
    n_LDALU       = 1'b0;
    n_LDAD        = 1'b0;
    n_LDBAL       = 1'b0;
    n_LDBAH       = 1'b0;
    n_SaveP       = 1'b0;
    n_Write       = 1'b0;
    n_AddY        = 1'b0;
    n_ALUmore     = 1'b0;

    case (IR[7:5])
      3'b100: begin
        case (IR[1:0])
          2'b00: begin
            n_Set_BusA_To = BA_Y;
            n_Write_Data  = (IR[4:2] == 3'b111 && !rdy_mod) ? WD_YB : WD_Y;   // SHY $9C
          end
          2'b10: begin
            n_Set_BusA_To = BA_X;
            n_Write_Data  = (IR[4:2] == 3'b111 && !rdy_mod) ? WD_XB : WD_X;   // SHX $9E
          end
          2'b11: begin
            if (IR[4:2] == 3'b110) begin                                      // SHS $9B
              n_Set_BusA_To = BA_AAX;
              n_LDS = 1'b1;
            end else
              n_Set_BusA_To = BA_ABC;
            if ((IR[4:2] == 3'b111 || IR[4:2] == 3'b110 || IR[4:2] == 3'b100) && !rdy_mod)
              n_Write_Data = WD_AXB;
            else
              n_Write_Data = WD_AX;
          end
          default: n_Write_Data = WD_ABC;
        endcase
      end
      3'b101: begin
        n_Set_BusA_To = BA_DI;
        case (IR[1:0])
          2'b00: if (IR[4] != 1'b1 || IR[2] != 1'b0) n_LDY = 1'b1;
          2'b01: n_LDA = 1'b1;
          2'b10: n_LDX = 1'b1;
          default: begin
            n_LDX = 1'b1;
            n_LDA = 1'b1;
            if (IR[4:2] == 3'b110) begin                                      // LAS $BB
              n_Set_BusA_To = BA_S;
              n_LDS = 1'b1;
            end
          end
        endcase
      end
      3'b110: begin
        if (IR[1:0] == 2'b00) begin
          if (!IR[4]) n_LDY = 1'b1;
          n_Set_BusA_To = BA_Y;
        end else
          n_Set_BusA_To = BA_ABC;
      end
      3'b111: begin
        if (IR[1:0] == 2'b00) begin
          if (!IR[4]) n_LDX = 1'b1;
          n_Set_BusA_To = BA_X;
        end else
          n_Set_BusA_To = BA_ABC;
      end
      default: ;
    endcase

    if (IR[7:6] != 2'b10 && IR[1])
      n_Set_BusA_To = (IR == 8'hEB) ? BA_ABC : BA_DI;

    case (IR[4:0])
      5'b00000, 5'b01000, 5'b01010, 5'b11000, 5'b11010: begin
        // implied
        case (IR)
          8'h00: begin                                                        // BRK
            n_LCycle = 3'd6;
            case (MCycle)
              3'd1: begin n_Set_Addr_To = AD_SP; n_Write_Data = WD_PCH; n_Write = 1'b1; end
              3'd2: begin n_Dec_S = 1'b1; n_Set_Addr_To = AD_SP; n_Write_Data = WD_PCL; n_Write = 1'b1; end
              3'd3: begin n_Dec_S = 1'b1; n_Set_Addr_To = AD_SP; n_Write_Data = WD_P; n_Write = 1'b1; end
              3'd4: begin n_Dec_S = 1'b1; n_Set_Addr_To = AD_BA; end
              3'd5: begin n_LDDI = 1'b1; n_Set_Addr_To = AD_BA; end
              3'd6: n_Jump = 2'b10;
              default: ;
            endcase
          end
          8'h20: begin                                                        // JSR
            n_LCycle = 3'd5;
            case (MCycle)
              3'd1: begin n_Jump = 2'b01; n_LDDI = 1'b1; n_Set_Addr_To = AD_SP; end
              3'd2: begin n_Set_Addr_To = AD_SP; n_Write_Data = WD_PCH; n_Write = 1'b1; end
              3'd3: begin n_Dec_S = 1'b1; n_Set_Addr_To = AD_SP; n_Write_Data = WD_PCL; n_Write = 1'b1; end
              3'd4: n_Dec_S = 1'b1;
              3'd5: n_Jump = 2'b10;
              default: ;
            endcase
          end
          8'h40: begin                                                        // RTI
            n_LCycle = 3'd5;
            case (MCycle)
              3'd1: n_Set_Addr_To = AD_SP;
              3'd2: begin n_Inc_S = 1'b1; n_Set_Addr_To = AD_SP; end
              3'd3: begin n_Inc_S = 1'b1; n_Set_Addr_To = AD_SP; n_Set_BusA_To = BA_DI; end
              3'd4: begin n_LDP = 1'b1; n_Inc_S = 1'b1; n_LDDI = 1'b1; n_Set_Addr_To = AD_SP; end
              3'd5: n_Jump = 2'b10;
              default: ;
            endcase
          end
          8'h60: begin                                                        // RTS
            n_LCycle = 3'd5;
            case (MCycle)
              3'd1: n_Set_Addr_To = AD_SP;
              3'd2: begin n_Inc_S = 1'b1; n_Set_Addr_To = AD_SP; end
              3'd3: begin n_Inc_S = 1'b1; n_LDDI = 1'b1; n_Set_Addr_To = AD_SP; end
              3'd4: n_Jump = 2'b10;
              3'd5: n_Jump = 2'b01;
              default: ;
            endcase
          end
          8'h08, 8'h48, 8'h5A, 8'hDA: begin                                   // PHP, PHA; $5A/$DA NOP
            n_LCycle = IR[1] ? 3'd1 : 3'd2;
            case (MCycle)
              3'd1: if (!IR[1]) begin
                n_Write = 1'b1;
                n_Write_Data = IR[6] ? WD_ABC : WD_P;
                n_Set_Addr_To = AD_SP;
              end
              3'd2: n_Dec_S = 1'b1;
              default: ;
            endcase
          end
          8'h28, 8'h68, 8'h7A, 8'hFA: begin                                   // PLP, PLA; $7A/$FA NOP
            n_LCycle = IR[1] ? 3'd1 : 3'd3;
            if (IR[7:4] == 4'b0010) n_LDP = 1'b1;
            if (IR[7:4] == 4'b0110) n_LDA = 1'b1;
            case (MCycle)
              3'd0: if (!IR[1]) n_SaveP = 1'b1;
              3'd1: if (!IR[1]) begin n_Set_Addr_To = AD_SP; n_LDP = 1'b0; end
              3'd2: begin n_Inc_S = 1'b1; n_Set_Addr_To = AD_SP; n_LDP = 1'b0; end
              3'd3: n_Set_BusA_To = BA_DI;
              default: ;
            endcase
          end
          8'hA0, 8'hC0, 8'hE0: if (MCycle == 3'd1) n_Jump = 2'b01;             // n_LDY/CPY/CPX #
          8'h88: begin n_LDY = 1'b1; if (MCycle == 3'd1) n_Set_BusA_To = BA_Y; end // DEY
          8'hCA: begin n_LDX = 1'b1; if (MCycle == 3'd1) n_Set_BusA_To = BA_X; end // DEX
          8'h1A, 8'h3A: begin                                                 // NOP (65C02 INC/DEC A)
            n_LCycle = 3'd1;
            if (MCycle == 3'd1) n_Set_BusA_To = BA_S;
          end
          8'h0A, 8'h2A, 8'h4A, 8'h6A: begin n_LDA = 1'b1; n_Set_BusA_To = BA_ABC; end
          8'h8A, 8'h98: n_LDA = 1'b1;                                           // TXA, TYA
          8'hAA, 8'hA8: if (MCycle == 3'd1) n_Set_BusA_To = BA_ABC;             // TAX, TAY
          8'h9A: n_LDS = 1'b1;                                                  // TXS
          8'hBA: begin n_LDX = 1'b1; if (MCycle == 3'd1) n_Set_BusA_To = BA_S; end // TSX
          8'h80: if (MCycle == 3'd1) n_Jump = 2'b01;                            // NOP #
          default: ;
        endcase
      end

      5'b00001, 5'b00011: begin
        // (zp,X)
        n_LCycle = 3'd5;
        if (IR[7:6] != 2'b10) begin
          n_LDA = 1'b1;
          if (IR[1]) n_LCycle = 3'd7;
        end
        case (MCycle)
          3'd1: begin n_Jump = 2'b01; n_LDAD = 1'b1; n_Set_Addr_To = AD_ZPG; end
          3'd2: begin n_ADAdd = 1'b1; n_Set_Addr_To = AD_ZPG; end
          3'd3: begin n_BAAdd = 2'b01; n_LDBAL = 1'b1; n_Set_Addr_To = AD_ZPG; end
          3'd4: begin
            n_LDBAH = 1'b1;
            if (IR[7:5] == 3'b100) n_Write = 1'b1;
            n_Set_Addr_To = AD_BA;
          end
          3'd5: if (IR[1] && IR[7:6] != 2'b10) begin
            n_Set_Addr_To = AD_BA; n_Write = 1'b1; n_LDDI = 1'b1;
          end
          3'd6: begin n_Write = 1'b1; n_LDALU = 1'b1; n_SaveP = 1'b1; n_Set_Addr_To = AD_BA; end
          3'd7: begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
          default: ;
        endcase
      end

      5'b01001: begin
        // immediate
        if (IR[7:5] != 3'b100) n_LDA = 1'b1;
        if (MCycle == 3'd1) n_Jump = 2'b01;
      end

      5'b01011: begin
        // undocumented immediates
        case (IR[7:5])
          3'b000, 3'b001, 3'b010, 3'b011: begin n_Set_BusA_To = BA_DA; n_LDA = 1'b1; end
          3'b100: begin n_Set_BusA_To = BA_DAX; n_LDA = 1'b1; end
          3'b110: begin n_Set_BusA_To = BA_AAX; n_LDX = 1'b1; end
          3'b101: begin n_Set_BusA_To = BA_DAO; n_LDA = 1'b1; end
          default: n_LDA = 1'b1;
        endcase
        if (MCycle == 3'd1) n_Jump = 2'b01;
      end

      5'b00010, 5'b10010: begin
        // immediate, NOP #, JAM
        if (MCycle == 3'd1) begin
          if (IR == 8'hA2) begin
            n_Jump = 2'b01;
            n_LDX  = 1'b1;
          end else if (IR[7:4] == 4'b1000 || IR[7:4] == 4'b1100 || IR[7:4] == 4'b1110)
            n_Jump = 2'b01;
        end
      end

      5'b00100: begin
        // zero page (BIT/STY/n_LDY/CPY/CPX/NOP)
        n_LCycle = 3'd2;
        case (MCycle)
          3'd0: if (IR[7:5] == 3'b001) n_SaveP = 1'b1;
          3'd1: begin
            n_Jump = 2'b01; n_LDAD = 1'b1;
            if (IR[7:5] == 3'b100) n_Write = 1'b1;
            n_Set_Addr_To = AD_ZPG;
          end
          default: ;
        endcase
      end

      5'b00101, 5'b00110, 5'b00111: begin
        // zero page
        if (IR[7:6] != 2'b10 && IR[1]) begin
          // read-modify-write
          n_LCycle = 3'd4;
          if (IR[0]) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDAD = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd2: begin n_LDDI = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd3: begin n_LDALU = 1'b1; n_SaveP = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd4: if (IR[0]) begin n_Set_BusA_To = BA_ABC; n_ALUmore = 1'b1; n_LDDI = 1'b1; end
            default: ;
          endcase
        end else begin
          n_LCycle = 3'd2;
          if (IR[7:6] != 2'b10) n_LDA = 1'b1;
          if (MCycle == 3'd1) begin
            n_Jump = 2'b01; n_LDAD = 1'b1;
            if (IR[7:5] == 3'b100) n_Write = 1'b1;
            n_Set_Addr_To = AD_ZPG;
          end
        end
      end

      5'b01100: begin
        // absolute (BIT/JMP/STY/n_LDY/CPY/CPX/NOP)
        if (IR[7:6] == 2'b01) begin
          if (!IR[5]) begin                                                   // JMP abs
            n_LCycle = 3'd2;
            case (MCycle)
              3'd1: begin n_Jump = 2'b01; n_LDDI = 1'b1; end
              3'd2: n_Jump = 2'b10;
              default: ;
            endcase
          end else begin                                                      // JMP (abs)
            n_LCycle = 3'd4;
            case (MCycle)
              3'd1: begin n_Jump = 2'b01; n_LDDI = 1'b1; n_LDBAL = 1'b1; end
              3'd2: begin n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA; end
              3'd3: begin n_LDDI = 1'b1; n_Set_Addr_To = AD_BA; n_BAAdd = 2'b01; end
              3'd4: n_Jump = 2'b10;
              default: ;
            endcase
          end
        end else begin
          n_LCycle = 3'd3;
          case (MCycle)
            3'd0: if (IR[7:5] == 3'b001) n_SaveP = 1'b1;
            3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
            3'd2: begin
              n_Jump = 2'b01; n_LDBAH = 1'b1;
              if (IR[7:5] == 3'b100) n_Write = 1'b1;
              n_Set_Addr_To = AD_BA;
            end
            default: ;
          endcase
        end
      end

      5'b01101, 5'b01110, 5'b01111: begin
        // absolute
        if (IR[7:6] != 2'b10 && IR[1]) begin
          // read-modify-write
          n_LCycle = 3'd5;
          if (IR[0]) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
            3'd2: begin n_Jump = 2'b01; n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA; end
            3'd3: begin n_LDDI = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_BA; end
            3'd4: begin n_Write = 1'b1; n_LDALU = 1'b1; n_SaveP = 1'b1; n_Set_Addr_To = AD_BA; end
            3'd5: if (IR[0]) begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
            default: ;
          endcase
        end else begin
          n_LCycle = 3'd3;
          if (IR[7:6] != 2'b10) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
            3'd2: begin
              n_Jump = 2'b01; n_LDBAH = 1'b1;
              if (IR[7:5] == 3'b100) n_Write = 1'b1;
              n_Set_Addr_To = AD_BA;
            end
            default: ;
          endcase
        end
      end

      5'b10000: begin
        // relative: T2 ends a not-taken branch, Break ends a taken one without page cross
        n_LCycle = n_Branch ? 3'd3 : 3'd1;
        case (MCycle)
          3'd1: begin n_Jump = 2'b01; n_LDDI = 1'b1; end
          3'd2: begin n_Jump = 2'b11; n_PCAdd = 1'b1; end
          default: ;
        endcase
      end

      5'b10001, 5'b10011: begin
        // (zp),Y
        n_LCycle = 3'd5;
        if (IR[7:6] != 2'b10) begin
          n_LDA = 1'b1;
          if (IR[1]) n_LCycle = 3'd7;
        end
        case (MCycle)
          3'd1: begin n_Jump = 2'b01; n_LDAD = 1'b1; n_Set_Addr_To = AD_ZPG; end
          3'd2: begin n_LDBAL = 1'b1; n_BAAdd = 2'b01; n_Set_Addr_To = AD_ZPG; end
          3'd3: begin n_Set_BusA_To = BA_Y; n_BAAdd = 2'b10; n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA; end
          3'd4: begin
            n_BAAdd = 2'b11;
            if (IR[7:5] == 3'b100) begin
              n_Write = 1'b1;
              if (IR[3:0] == 4'h3) n_BAQuirk = 2'b10;                           // SHA (zp),Y: copy
            end else if (!IR[1] || IR == 8'hB3)
              n_BreakAtNA = 1'b1;
            n_Set_Addr_To = AD_BA;
          end
          3'd5: if (IR[1] && IR[7:6] != 2'b10) begin
            n_Set_Addr_To = AD_BA; n_LDDI = 1'b1; n_Write = 1'b1;
          end
          3'd6: begin n_LDALU = 1'b1; n_SaveP = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_BA; end
          3'd7: begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
          default: ;
        endcase
      end

      5'b10100, 5'b10101, 5'b10110, 5'b10111: begin
        // zp,X / zp,Y
        if (IR[7:6] != 2'b10 && IR[1]) begin
          // read-modify-write
          if (IR[0]) n_LDA = 1'b1;
          n_LCycle = 3'd5;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDAD = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd2: begin n_ADAdd = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd3: begin n_LDDI = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd4: begin
              n_LDALU = 1'b1; n_SaveP = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_ZPG;
              if (IR[0]) n_LDDI = 1'b1;
            end
            3'd5: if (IR[0]) begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
            default: ;
          endcase
        end else begin
          n_LCycle = 3'd3;
          if (IR[7:6] != 2'b10 && IR[0]) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDAD = 1'b1; n_Set_Addr_To = AD_ZPG; end
            3'd2: begin
              n_ADAdd = 1'b1;
              if (IR[3:1] == 3'b011) n_AddY = 1'b1;
              if (IR[7:5] == 3'b100) n_Write = 1'b1;
              n_Set_Addr_To = AD_ZPG;
            end
            default: ;
          endcase
        end
      end

      5'b11001, 5'b11011: begin
        // abs,Y
        n_LCycle = 3'd4;
        if (IR[7:6] != 2'b10) begin
          n_LDA = 1'b1;
          if (IR[1]) n_LCycle = 3'd6;
        end
        case (MCycle)
          3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
          3'd2: begin
            n_Jump = 2'b01; n_Set_BusA_To = BA_Y; n_BAAdd = 2'b10; n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA;
          end
          3'd3: begin
            n_BAAdd = 2'b11;
            if (IR[7:5] == 3'b100) begin
              n_Write = 1'b1;
              if (IR[3:0] == 4'hB) n_BAQuirk = 2'b01;                           // SHS: and
            end else if (!IR[1] || IR == 8'hBB)
              n_BreakAtNA = 1'b1;
            n_Set_Addr_To = AD_BA;
          end
          3'd4: if (IR[1] && IR[7:6] != 2'b10) begin
            n_Set_Addr_To = AD_BA; n_LDDI = 1'b1; n_Write = 1'b1;
          end
          3'd5: begin n_Write = 1'b1; n_LDALU = 1'b1; n_Set_Addr_To = AD_BA; n_SaveP = 1'b1; end
          3'd6: begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
          default: ;
        endcase
      end

      5'b11100, 5'b11101, 5'b11110, 5'b11111: begin
        // abs,X / abs,Y ($BE/$BF/$9E/$9F)
        if (IR[7:6] != 2'b10 && IR[1]) begin
          // read-modify-write
          n_LCycle = 3'd6;
          if (IR[0]) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
            3'd2: begin
              n_Jump = 2'b01; n_Set_BusA_To = BA_X; n_BAAdd = 2'b10; n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA;
            end
            3'd3: begin n_BAAdd = 2'b11; n_Set_Addr_To = AD_BA; end
            3'd4: begin n_LDDI = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_BA; end
            3'd5: begin n_LDALU = 1'b1; n_SaveP = 1'b1; n_Write = 1'b1; n_Set_Addr_To = AD_BA; end
            3'd6: if (IR[0]) begin n_ALUmore = 1'b1; n_Set_BusA_To = BA_ABC; end
            default: ;
          endcase
        end else begin
          n_LCycle = 3'd4;
          if (IR[7:6] != 2'b10 && IR[1:0] != 2'b00) n_LDA = 1'b1;
          case (MCycle)
            3'd1: begin n_Jump = 2'b01; n_LDBAL = 1'b1; end
            3'd2: begin
              n_Jump = 2'b01;
              n_Set_BusA_To = (IR[7:6] == 2'b10 && IR[4:1] == 4'b1111) ? BA_Y : BA_X;
              n_BAAdd = 2'b10; n_LDBAH = 1'b1; n_Set_Addr_To = AD_BA;
            end
            3'd3: begin
              n_BAAdd = 2'b11;
              if (IR[7:5] == 3'b100) begin
                n_Write = 1'b1;
                case (IR[1:0])
                  2'b00, 2'b10: n_BAQuirk = 2'b01;                              // SHY/SHX: and
                  2'b11:        n_BAQuirk = 2'b10;                              // SHA: copy
                  default: ;
                endcase
              end else
                n_BreakAtNA = 1'b1;
              n_Set_Addr_To = AD_BA;
            end
            default: ;
          endcase
        end
      end
      default: ;
    endcase
  end

  // ALU operation decode
  always_comb begin
    case (IR[1:0])
      2'b00: begin
        case (IR[4:2])
          3'b000, 3'b001, 3'b011: begin
            case (IR[7:5])
              3'b110, 3'b111: n_ALU_Op = ALU_CMP;
              3'b101:         n_ALU_Op = ALU_EQ2;
              3'b001:         n_ALU_Op = ALU_BIT;
              default:        n_ALU_Op = ALU_EQ1;
            endcase
          end
          3'b010: begin
            case (IR[7:5])
              3'b111, 3'b110: n_ALU_Op = ALU_INC;
              3'b100:         n_ALU_Op = ALU_DEC;
              default:        n_ALU_Op = ALU_EQ2;
            endcase
          end
          3'b110: n_ALU_Op = (IR[7:5] == 3'b100) ? ALU_EQ2 : ALU_EQ1;
          default: n_ALU_Op = (IR[7:5] == 3'b101) ? ALU_EQ2 : ALU_EQ1;
        endcase
      end
      2'b01: begin
        case (IR[7:5])
          3'd0: n_ALU_Op = ALU_OR;
          3'd1: n_ALU_Op = ALU_AND;
          3'd2: n_ALU_Op = ALU_EOR;
          3'd3: n_ALU_Op = ALU_ADC;
          3'd4: n_ALU_Op = ALU_EQ1;
          3'd5: n_ALU_Op = ALU_EQ2;
          3'd6: n_ALU_Op = ALU_CMP;
          default: n_ALU_Op = ALU_SBC;
        endcase
      end
      2'b10: begin
        case (IR[7:5])
          3'd0: n_ALU_Op = ALU_ASL;
          3'd1: n_ALU_Op = ALU_ROL;
          3'd2: n_ALU_Op = ALU_LSR;
          3'd3: n_ALU_Op = ALU_ROR;
          3'd4: n_ALU_Op = (IR[4:2] == 3'b010) ? ALU_EQ2 : ALU_EQ1;
          3'd5: n_ALU_Op = ALU_EQ2;
          3'd6: n_ALU_Op = ALU_DEC;
          default: n_ALU_Op = ALU_INC;
        endcase
      end
      default: begin
        if (IR[7:5] == 3'd5)
          n_ALU_Op = (IR == 8'hBB) ? ALU_AND : ALU_EQ2;
        else if (IR == 8'h6B) n_ALU_Op = ALU_ARR;
        else if (IR == 8'h8B) n_ALU_Op = ALU_XAA;
        else if (IR == 8'h0B || IR == 8'h2B) n_ALU_Op = ALU_ANC;
        else if (IR == 8'hEB) n_ALU_Op = ALU_SBC;
        else if (n_ALUmore) begin
          case (IR[7:5])
            3'd0: n_ALU_Op = ALU_OR;
            3'd1: n_ALU_Op = ALU_AND;
            3'd2: n_ALU_Op = ALU_EOR;
            3'd3: n_ALU_Op = ALU_ADC;
            3'd4: n_ALU_Op = ALU_EQ1;
            3'd6: n_ALU_Op = ALU_CMP;
            default: n_ALU_Op = ALU_SBC;
          endcase
        end else begin
          case (IR[7:5])
            3'd0: n_ALU_Op = ALU_ASL;
            3'd1: n_ALU_Op = ALU_ROL;
            3'd2: n_ALU_Op = ALU_LSR;
            3'd3: n_ALU_Op = ALU_ROR;
            3'd4: n_ALU_Op = ALU_BIT;
            3'd6: n_ALU_Op = (IR[4:2] == 3'b010) ? ALU_SAX : ALU_DEC;          // $CB SBX
            default: n_ALU_Op = ALU_INC;
          endcase
        end
      end
    endcase
  end


  // ================================================================ 65C02 micro code
  // Bus cycles follow SingleStepTests wdc65c02 / rockwell65c02 / synertek65c02.
  localparam bit C02_BITOPS = (C02 == 1) || (C02 == 2);   // RMB/SMB/BBR/BBS
  localparam bit C02_WAISTP = (C02 == 1);

  localparam logic [3:0] AM_IMP = 4'd0, AM_IMM = 4'd1, AM_ZP = 4'd2, AM_ZPX = 4'd3, AM_ABS = 4'd4,
                         AM_ABX = 4'd5, AM_IZX = 4'd6, AM_IZY = 4'd7, AM_IZP = 4'd8, AM_RZP = 4'd9,
                         AM_RZPX = 4'd10, AM_RABS = 4'd11, AM_RABX = 4'd12, AM_SPC = 4'd13;

  always_comb begin : c02_mcode
    logic       col01, xtra, wr, idxy, alw, savep0, cy, d3, bbt, cyx, cyy;
    logic [3:0] am;
    logic [7:0] bal8;

    c_LCycle      = 3'd1;
    c_Set_BusA_To = BA_ABC;
    c_Set_Addr_To = AD_PBR;
    c_Write_Data  = WD_DL;
    c_Jump        = 2'b00;
    c_BAAdd       = 2'b00;
    c_ADAdd       = 1'b0;
    c_AddY        = 1'b0;
    c_PCAdd       = 1'b0;
    c_Inc_S       = 1'b0;
    c_Dec_S       = 1'b0;
    c_LDA         = 1'b0;
    c_LDP         = 1'b0;
    c_LDX         = 1'b0;
    c_LDY         = 1'b0;
    c_LDS         = 1'b0;
    c_LDDI        = 1'b0;
    c_LDALU       = 1'b0;
    c_LDAD        = 1'b0;
    c_LDBAL       = 1'b0;
    c_LDBAH       = 1'b0;
    c_SaveP       = 1'b0;
    c_Write       = 1'b0;
    c_PCDec       = 1'b0;
    c_PCHfix      = 1'b0;
    c_BAInc16     = 1'b0;
    c_Hold        = 1'b0;
    c_ALU_Op      = ALU_EQ1;

    col01  = (IR[1:0] == 2'b01) || (IR[4:0] == 5'b10010);    // ORA..SBC, incl. (zp)
    xtra   = col01 && IR[6:5] == 2'b11 && dec_en;            // decimal ADC/SBC: one more read of the EA
    cyx    = BAL[7:0] > ~X;                                  // carry out of BAL + X (BA add this cycle)
    cyy    = BAL[7:0] > ~Y;
    bal8   = BAL[7:0];
    bbt    = (bal8[IR[6:4]] == IR[7]);                       // BBR/BBS: operand byte held in BAL
    wr     = 1'b0;
    idxy   = 1'b0;
    alw    = 1'b0;
    savep0 = 1'b0;
    am     = AM_IMP;

    if (C02 != 0) begin
      // ---- register / bus selection
      if (col01) begin
        case (IR[7:5])
          3'b100: c_Write_Data = WD_ABC;
          3'b101: begin c_Set_BusA_To = BA_DI; c_LDA = 1'b1; end
          default: c_LDA = 1'b1;     // CMP reloads A unchanged: that is how T65 commits its flags
        endcase
      end else begin
        case (IR[1:0])
          2'b00: begin
            case (IR[7:5])
              3'b100: begin c_Set_BusA_To = BA_Y; c_Write_Data = WD_Y; end
              3'b101: begin c_Set_BusA_To = BA_DI; if (!IR[4] || IR[2]) c_LDY = 1'b1; end
              3'b110: begin c_Set_BusA_To = BA_Y; if (!IR[4]) c_LDY = 1'b1; end
              3'b111: begin c_Set_BusA_To = BA_X; if (!IR[4]) c_LDX = 1'b1; end
              default: ;
            endcase
          end
          2'b10: begin
            case (IR[7:5])
              3'b100: begin c_Set_BusA_To = BA_X; c_Write_Data = WD_X; end
              3'b101: begin c_Set_BusA_To = BA_DI; c_LDX = 1'b1; end
              default: c_Set_BusA_To = BA_DI;
            endcase
          end
          default: c_Set_BusA_To = BA_DI;
        endcase
      end

      // ---- ALU operation
      if (col01) begin
        case (IR[7:5])
          3'd0: c_ALU_Op = ALU_OR;
          3'd1: c_ALU_Op = ALU_AND;
          3'd2: c_ALU_Op = ALU_EOR;
          3'd3: c_ALU_Op = ALU_ADC;
          3'd4: c_ALU_Op = (IR == 8'h89) ? ALU_BITZ : ALU_EQ1;
          3'd5: c_ALU_Op = ALU_EQ2;
          3'd6: c_ALU_Op = ALU_CMP;
          default: c_ALU_Op = ALU_SBC;
        endcase
      end else begin
        case (IR)
          8'h04, 8'h0C: c_ALU_Op = ALU_TSB;
          8'h14, 8'h1C: c_ALU_Op = ALU_TRB;
          8'h34, 8'h3C: c_ALU_Op = ALU_BIT;
          8'h1A:        c_ALU_Op = ALU_INC;
          8'h3A:        c_ALU_Op = ALU_DEC;
          8'h7A, 8'hFA: c_ALU_Op = ALU_EQ2;
          default:      c_ALU_Op = (IR[1:0] == 2'b11) ? ALU_RSMB : n_ALU_Op;
        endcase
      end

      // ---- addressing template
      case (IR[4:0])
        5'b00000: am = (IR[7] && IR[6:5] != 2'b00) ? AM_IMM : AM_SPC;     // LDY/CPY/CPX # vs BRK/JSR/RTI/RTS/BRA
        5'b01000: am = IR[7] ? AM_IMP : AM_SPC;                            // PHP/PLP/PHA/PLA
        5'b11010: am = IR[6] ? AM_SPC : AM_IMP;                           // PHY/PLY/PHX/PLX
        5'b10000, 5'b01111, 5'b11111: am = AM_SPC;
        5'b00001: begin am = AM_IZX; wr = (IR[7:5] == 3'b100); end
        5'b00010: am = AM_IMM;
        5'b10010: begin am = AM_IZP; wr = (IR[7:5] == 3'b100); end
        5'b00100: begin am = (IR[7:5] == 3'b000) ? AM_RZP : AM_ZP; wr = (IR[7:5] == 3'b011 || IR[7:5] == 3'b100); end
        5'b00101: begin am = AM_ZP; wr = (IR[7:5] == 3'b100); end
        5'b00110: begin am = (IR[7:6] == 2'b10) ? AM_ZP : AM_RZP; wr = (IR[7:5] == 3'b100); end
        5'b00111: am = AM_RZP;                                             // RMB/SMB
        5'b01001: am = AM_IMM;
        5'b01100: begin
          am = (IR[7:5] == 3'b000) ? AM_RABS : (IR[7:6] == 2'b01) ? AM_SPC : AM_ABS;
          wr = (IR[7:5] == 3'b100);
        end
        5'b01101: begin am = AM_ABS; wr = (IR[7:5] == 3'b100); end
        5'b01110: begin am = (IR[7:6] == 2'b10) ? AM_ABS : AM_RABS; wr = (IR[7:5] == 3'b100); end
        5'b10001: begin am = AM_IZY; wr = (IR[7:5] == 3'b100); end
        5'b10100: begin am = (IR[7:5] == 3'b000) ? AM_RZP : AM_ZPX; wr = (IR[7:5] == 3'b011 || IR[7:5] == 3'b100); end
        5'b10101: begin am = AM_ZPX; wr = (IR[7:5] == 3'b100); end
        5'b10110: begin am = (IR[7:6] == 2'b10) ? AM_ZPX : AM_RZPX; wr = (IR[7:5] == 3'b100); idxy = (IR[7:6] == 2'b10); end
        5'b10111: am = AM_RZP;
        5'b11001: begin am = AM_ABX; idxy = 1'b1; wr = (IR[7:5] == 3'b100); end
        5'b11100: begin
          case (IR[7:5])
            3'b000: am = AM_RABS;                                  // TRB abs
            3'b001, 3'b101: am = AM_ABX;                           // BIT abs,X / LDY abs,X
            3'b100: begin am = AM_ABS; wr = 1'b1; end              // STZ abs
            default: am = AM_SPC;                                  // JMP (a,x), NOPs
          endcase
        end
        5'b11101: begin am = AM_ABX; wr = (IR[7:5] == 3'b100); end
        5'b11110: begin
          case (IR[7:5])
            3'b100: begin am = AM_ABX; wr = 1'b1; end              // STZ abs,X
            3'b101: begin am = AM_ABX; idxy = 1'b1; end            // LDX abs,Y
            default: begin am = AM_RABX; alw = IR[7]; end          // INC/DEC abs,X always 7 cycles
          endcase
        end
        5'b01011, 5'b11011: am = AM_SPC;                                   // WAI / STP (others are 1-cycle NOPs)
        default: am = AM_IMP;
      endcase
      if (IR == 8'h89 || IR[7:5] == 3'b001 && (IR[4:0] == 5'b00100 || IR[4:0] == 5'b01100 ||
                                              IR[4:0] == 5'b10100 || IR[4:0] == 5'b11100))
        savep0 = 1'b1;                                             // BIT: flags at the next fetch
      if (IR == 8'h64 || IR == 8'h74 || IR == 8'h9C || IR == 8'h9E) c_Write_Data = WD_ZERO;
      if (MCycle == CYC_SYNC && savep0) c_SaveP = 1'b1;

      cy = idxy ? cyy : cyx;
      d3 = alw | BAL[8];

      case (am)
        AM_IMM: begin
          // decimal: PC stays on the operand, the extra cycle re-reads it (SST shows a constant dummy address)
          c_LCycle = xtra ? 3'd2 : 3'd1;
          if (MCycle == 3'd1 && !xtra || MCycle == 3'd2) c_Jump = 2'b01;
        end
        AM_ZP: begin
          c_LCycle = xtra ? 3'd3 : 3'd2;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Write = wr; c_Set_Addr_To = AD_ZPG; end
            3'd2: if (xtra) c_Set_Addr_To = AD_ZPG;
            default: ;
          endcase
        end
        AM_ZPX: begin
          c_LCycle = xtra ? 3'd4 : 3'd3;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_ADAdd = 1'b1; c_AddY = idxy; c_Write = wr; c_Set_Addr_To = AD_ZPG; end
            3'd3: if (xtra) c_Set_Addr_To = AD_ZPG;
            default: ;
          endcase
        end
        AM_ABS: begin
          c_LCycle = xtra ? 3'd4 : 3'd3;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
            3'd2: begin c_Jump = 2'b01; c_LDBAH = 1'b1; c_Write = wr; c_Set_Addr_To = AD_BA; end
            3'd3: if (xtra) c_Set_Addr_To = AD_BA;
            default: ;
          endcase
        end
        AM_ABX: begin
          // page cross (or any store): dummy read of the last operand byte, PC is held there
          c_LCycle = wr ? 3'd4 : (3'd3 + {2'b00, BAL[8]} + {2'b00, xtra});
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
            3'd2: begin
              c_LDBAH = 1'b1; c_Set_BusA_To = idxy ? BA_Y : BA_X; c_BAAdd = 2'b10;
              c_Set_Addr_To = (wr || cy) ? AD_PBR : AD_BA;
            end
            3'd3: begin
              c_Jump = 2'b01;
              if (wr || BAL[8]) begin c_BAAdd = 2'b11; c_Write = wr; c_Set_Addr_To = AD_BA; end
              else if (xtra) c_Set_Addr_To = AD_BA;
            end
            3'd4: if (xtra && BAL[8]) c_Set_Addr_To = AD_BA;
            default: ;
          endcase
        end
        AM_IZX: begin
          c_LCycle = xtra ? 3'd6 : 3'd5;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_ADAdd = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd3: begin c_BAAdd = 2'b01; c_LDBAL = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd4: begin c_LDBAH = 1'b1; c_Write = wr; c_Set_Addr_To = AD_BA; end
            3'd5: if (xtra) c_Set_Addr_To = AD_BA;
            default: ;
          endcase
        end
        AM_IZP: begin
          c_LCycle = xtra ? 3'd5 : 3'd4;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_LDBAL = 1'b1; c_BAAdd = 2'b01; c_Set_Addr_To = AD_ZPG; end
            3'd3: begin c_LDBAH = 1'b1; c_Write = wr; c_Set_Addr_To = AD_BA; end
            3'd4: if (xtra) c_Set_Addr_To = AD_BA;
            default: ;
          endcase
        end
        AM_IZY: begin
          // PC stays on the operand byte until the dummy read of it
          c_LCycle = wr ? 3'd5 : (3'd4 + {2'b00, BAL[8]} + {2'b00, xtra});
          case (MCycle)
            3'd1: begin c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_LDBAL = 1'b1; c_BAAdd = 2'b01; c_Set_Addr_To = AD_ZPG; end
            3'd3: begin
              c_LDBAH = 1'b1; c_Set_BusA_To = BA_Y; c_BAAdd = 2'b10;
              c_Set_Addr_To = (wr || cyy) ? AD_PBR : AD_BA;
            end
            3'd4: begin
              c_Jump = 2'b01;
              if (wr || BAL[8]) begin c_BAAdd = 2'b11; c_Write = wr; c_Set_Addr_To = AD_BA; end
              else if (xtra) c_Set_Addr_To = AD_BA;
            end
            3'd5: if (xtra && BAL[8]) c_Set_Addr_To = AD_BA;
            default: ;
          endcase
        end
        AM_RZP: begin
          c_LCycle = 3'd4;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_LDDI = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd3: begin c_LDALU = 1'b1; c_SaveP = 1'b1; c_Write = 1'b1; c_Set_Addr_To = AD_ZPG; end
            default: ;
          endcase
        end
        AM_RZPX: begin
          c_LCycle = 3'd5;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd2: begin c_ADAdd = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd3: begin c_LDDI = 1'b1; c_Set_Addr_To = AD_ZPG; end
            3'd4: begin c_LDALU = 1'b1; c_SaveP = 1'b1; c_Write = 1'b1; c_Set_Addr_To = AD_ZPG; end
            default: ;
          endcase
        end
        AM_RABS: begin
          c_LCycle = 3'd5;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
            3'd2: begin c_Jump = 2'b01; c_LDBAH = 1'b1; c_Set_Addr_To = AD_BA; end
            3'd3: begin c_LDDI = 1'b1; c_Set_Addr_To = AD_BA; end
            3'd4: begin c_LDALU = 1'b1; c_SaveP = 1'b1; c_Write = 1'b1; c_Set_Addr_To = AD_BA; end
            default: ;
          endcase
        end
        AM_RABX: begin
          c_LCycle = d3 ? 3'd6 : 3'd5;
          case (MCycle)
            3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
            3'd2: begin
              c_LDBAH = 1'b1; c_Set_BusA_To = BA_X; c_BAAdd = 2'b10;
              c_Set_Addr_To = (alw || cyx) ? AD_PBR : AD_BA;
            end
            3'd3: begin
              c_Jump = 2'b01; c_Set_Addr_To = AD_BA;
              if (d3) c_BAAdd = 2'b11; else c_LDDI = 1'b1;
            end
            3'd4: begin
              c_Set_Addr_To = AD_BA;
              if (d3) c_LDDI = 1'b1; else begin c_LDALU = 1'b1; c_SaveP = 1'b1; c_Write = 1'b1; end
            end
            3'd5: if (d3) begin c_LDALU = 1'b1; c_SaveP = 1'b1; c_Write = 1'b1; c_Set_Addr_To = AD_BA; end
            default: ;
          endcase
        end
        AM_SPC: begin
          case (IR)
            8'h00: begin                                                      // BRK
              c_LCycle = 3'd6;
              case (MCycle)
                3'd1: begin c_Set_Addr_To = AD_SP; c_Write_Data = WD_PCH; c_Write = 1'b1; end
                3'd2: begin c_Dec_S = 1'b1; c_Set_Addr_To = AD_SP; c_Write_Data = WD_PCL; c_Write = 1'b1; end
                3'd3: begin c_Dec_S = 1'b1; c_Set_Addr_To = AD_SP; c_Write_Data = WD_P; c_Write = 1'b1; end
                3'd4: begin c_Dec_S = 1'b1; c_Set_Addr_To = AD_BA; end
                3'd5: begin c_LDDI = 1'b1; c_Set_Addr_To = AD_BA; end
                3'd6: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'h20: begin                                                      // JSR
              c_LCycle = 3'd5;
              case (MCycle)
                3'd1: begin c_Jump = 2'b01; c_LDDI = 1'b1; c_Set_Addr_To = AD_SP; end
                3'd2: begin c_Set_Addr_To = AD_SP; c_Write_Data = WD_PCH; c_Write = 1'b1; end
                3'd3: begin c_Dec_S = 1'b1; c_Set_Addr_To = AD_SP; c_Write_Data = WD_PCL; c_Write = 1'b1; end
                3'd4: c_Dec_S = 1'b1;
                3'd5: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'h40: begin                                                      // RTI
              c_LCycle = 3'd5;
              case (MCycle)
                3'd1: c_Set_Addr_To = AD_SP;
                3'd2: begin c_Inc_S = 1'b1; c_Set_Addr_To = AD_SP; end
                3'd3: begin c_Inc_S = 1'b1; c_Set_Addr_To = AD_SP; c_Set_BusA_To = BA_DI; end
                3'd4: begin c_LDP = 1'b1; c_Inc_S = 1'b1; c_LDDI = 1'b1; c_Set_Addr_To = AD_SP; end
                3'd5: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'h60: begin                                                      // RTS
              c_LCycle = 3'd5;
              case (MCycle)
                3'd1: c_Set_Addr_To = AD_SP;
                3'd2: begin c_Inc_S = 1'b1; c_Set_Addr_To = AD_SP; end
                3'd3: begin c_Inc_S = 1'b1; c_LDDI = 1'b1; c_Set_Addr_To = AD_SP; end
                3'd4: c_Jump = 2'b10;
                3'd5: c_Jump = 2'b01;
                default: ;
              endcase
            end
            8'h08, 8'h48, 8'h5A, 8'hDA: begin                                 // PHP PHA PHY PHX
              c_LCycle = 3'd2;
              case (MCycle)
                3'd1: begin
                  c_Write = 1'b1; c_Set_Addr_To = AD_SP;
                  case (IR[7:6])
                    2'b00: c_Write_Data = WD_P;
                    2'b01: c_Write_Data = IR[4] ? WD_Y : WD_ABC;
                    default: c_Write_Data = WD_X;
                  endcase
                end
                3'd2: c_Dec_S = 1'b1;
                default: ;
              endcase
            end
            8'h28, 8'h68, 8'h7A, 8'hFA: begin                                 // PLP PLA PLY PLX
              c_LCycle = 3'd3;
              c_LDP = (IR[7:4] == 4'h2);
              c_LDA = (IR[7:4] == 4'h6);
              c_LDY = (IR[7:4] == 4'h7);
              c_LDX = (IR[7:4] == 4'hF);
              case (MCycle)
                3'd0: c_SaveP = 1'b1;
                3'd1: begin c_Set_Addr_To = AD_SP; c_LDP = 1'b0; end
                3'd2: begin c_Inc_S = 1'b1; c_Set_Addr_To = AD_SP; c_LDP = 1'b0; end
                3'd3: c_Set_BusA_To = BA_DI;
                default: ;
              endcase
            end
            8'h4C: begin                                                      // JMP a
              c_LCycle = 3'd2;
              case (MCycle)
                3'd1: begin c_Jump = 2'b01; c_LDDI = 1'b1; end
                3'd2: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'h6C: begin                                                      // JMP (a)
              c_LCycle = 3'd5;
              case (MCycle)
                3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
                3'd2: begin c_LDBAH = 1'b1; c_Set_Addr_To = AD_BA; end
                3'd3: begin c_LDDI = 1'b1; c_BAAdd = 2'b01; c_Set_Addr_To = AD_BA; end   // c4 re-reads without carry
                3'd4: begin c_BAAdd = 2'b11; c_Set_Addr_To = AD_BA; end
                3'd5: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'h7C: begin                                                      // JMP (a,x)
              c_LCycle = 3'd5;
              case (MCycle)
                3'd1: begin c_Jump = 2'b01; c_LDBAL = 1'b1; end
                3'd2: begin c_LDBAH = 1'b1; c_Set_BusA_To = BA_X; c_BAAdd = 2'b10; c_PCDec = 1'b1; end
                3'd3: begin c_BAAdd = 2'b11; c_Set_Addr_To = AD_BA; end
                3'd4: begin c_LDDI = 1'b1; c_BAInc16 = 1'b1; c_Set_Addr_To = AD_BA; end
                3'd5: c_Jump = 2'b10;
                default: ;
              endcase
            end
            8'hCB: if (C02_WAISTP) begin                                      // WAI
              c_LCycle = 3'd2;
              if (MCycle == 3'd2) c_Hold = IRQ_n_o & ~NMIAct;
            end
            8'hDB: if (C02_WAISTP) begin                                      // STP
              c_LCycle = 3'd2;
              if (MCycle == 3'd2) c_Hold = 1'b1;
            end
            default: begin
              if (IR[4:0] == 5'b10000 || IR == 8'h80) begin                   // Bxx, BRA
                c_LCycle = (n_Branch || IR == 8'h80) ? 3'd3 : 3'd1;
                case (MCycle)
                  3'd1: begin c_Jump = 2'b01; c_LDDI = 1'b1; end
                  3'd2: begin c_Jump = 2'b11; c_PCAdd = 1'b1; end
                  3'd3: c_PCHfix = 1'b1;
                  default: ;
                endcase
              end else if (IR[3:0] == 4'hF) begin                            // BBR / BBS
                c_LCycle = bbt ? 3'd6 : 3'd4;
                case (MCycle)
                  3'd1: begin c_Jump = 2'b01; c_LDAD = 1'b1; c_Set_Addr_To = AD_ZPG; end
                  3'd2: begin c_LDBAL = 1'b1; c_Set_Addr_To = AD_ZPG; end
                  3'd4: begin c_Jump = 2'b01; c_LDDI = 1'b1; end
                  3'd5: begin c_PCAdd = 1'b1; c_Jump = PCRel[8] ? 2'b00 : 2'b11; end
                  3'd6: begin c_PCAdd = 1'b1; c_Jump = 2'b11; c_PCHfix = 1'b1; end
                  default: ;
                endcase
              end else if (IR[3:0] == 4'hC) begin                            // $5C/$DC/$FC: 3-byte 4-cycle NOPs
                c_LCycle = 3'd3;
                if (MCycle == 3'd1 || MCycle == 3'd3) c_Jump = 2'b01;
              end
            end
          endcase
        end
        default: begin                                                        // implied
          case (IR)
            8'h0A, 8'h2A, 8'h4A, 8'h6A, 8'h1A, 8'h3A: begin c_LDA = 1'b1; c_Set_BusA_To = BA_ABC; end
            8'h8A, 8'h98: c_LDA = 1'b1;
            8'hAA, 8'hA8: if (MCycle == 3'd1) c_Set_BusA_To = BA_ABC;
            8'h88: begin c_LDY = 1'b1; if (MCycle == 3'd1) c_Set_BusA_To = BA_Y; end
            8'hCA: begin c_LDX = 1'b1; if (MCycle == 3'd1) c_Set_BusA_To = BA_X; end
            8'h9A: c_LDS = 1'b1;
            8'hBA: begin c_LDX = 1'b1; if (MCycle == 3'd1) c_Set_BusA_To = BA_S; end
            default: ;
          endcase
        end
      endcase
    end
  end

  // a 1-byte 1-cycle 65C02 NOP is fetched and retired in the same cycle:
  // $x3/$xB, plus $x7/$xF without bit ops; WDC uses $CB/$DB for WAI/STP
  function automatic logic one_cycle_nop(input logic [7:0] op);
    if (op[1:0] != 2'b11)
      one_cycle_nop = 1'b0;
    else if (op[2])
      one_cycle_nop = !C02_BITOPS;
    else
      one_cycle_nop = !(C02_WAISTP && (op == 8'hCB || op == 8'hDB));
  endfunction

  // Mode is latched per instruction like T65; also gating with the pin makes a tied-off Mode fold the
  // whole 65C02 path away combinationally (no reliance on register constant propagation)
  assign c02         = (C02 != 0) && (C02_FIXED || (Mode_r != 2'b00) && (Mode != 2'b00));
  assign LCycle      = c02 ? c_LCycle      : n_LCycle;
  assign ALU_Op      = c02 ? c_ALU_Op      : n_ALU_Op;
  assign Set_BusA_To = c02 ? c_Set_BusA_To : n_Set_BusA_To;
  assign Set_Addr_To = c02 ? c_Set_Addr_To : n_Set_Addr_To;
  assign Write_Data  = c02 ? c_Write_Data  : n_Write_Data;
  assign Jump        = c02 ? c_Jump        : n_Jump;
  assign BAAdd       = c02 ? c_BAAdd       : n_BAAdd;
  assign BAQuirk     = c02 ? 2'b00         : n_BAQuirk;
  assign BreakAtNA   = c02 ? 1'b0          : n_BreakAtNA;
  assign ADAdd       = c02 ? c_ADAdd       : n_ADAdd;
  assign AddY        = c02 ? c_AddY        : n_AddY;
  assign PCAdd       = c02 ? c_PCAdd       : n_PCAdd;
  assign Inc_S       = c02 ? c_Inc_S       : n_Inc_S;
  assign Dec_S       = c02 ? c_Dec_S       : n_Dec_S;
  assign LDA         = c02 ? c_LDA         : n_LDA;
  assign LDP         = c02 ? c_LDP         : n_LDP;
  assign LDX         = c02 ? c_LDX         : n_LDX;
  assign LDY         = c02 ? c_LDY         : n_LDY;
  assign LDS         = c02 ? c_LDS         : n_LDS;
  assign LDDI        = c02 ? c_LDDI        : n_LDDI;
  assign LDALU       = c02 ? c_LDALU       : n_LDALU;
  assign LDAD        = c02 ? c_LDAD        : n_LDAD;
  assign LDBAL       = c02 ? c_LDBAL       : n_LDBAL;
  assign LDBAH       = c02 ? c_LDBAH       : n_LDBAH;
  assign SaveP       = c02 ? c_SaveP       : n_SaveP;
  assign Write       = c02 ? c_Write       : n_Write;
  assign PCDec       = c02 & c_PCDec;
  assign PCHfix      = c02 & c_PCHfix;
  assign BAInc16     = c02 & c_BAInc16;
  assign Hold        = c02 & c_Hold;

  // ================================================================ ALU
  logic       ADC_Z, ADC_C, ADC_V, ADC_N;
  logic [7:0] ADC_Q;
  logic       SBC_Z, SBC_C, SBC_V, SBC_N;
  logic [7:0] SBC_Q, SBX_Q;

  assign dec_en = !NO_DECIMAL && BCD_en_r && P[3];

  // T65's nibble adders carry a '1' in bit 0 to inject the carry; bit 0 of the sums is never used
  /* verilator lint_off UNUSED */
  always_comb begin : alu_adc
    logic [6:0] al, ah;
    logic       c;
    al = {2'b00, BusA_r[3:0], P[0]} + {2'b00, BusB[3:0], 1'b1};
    ah = {2'b00, BusA_r[7:4], al[5]} + {2'b00, BusB[7:4], 1'b1};
    ADC_Z = (al[4:1] == 4'd0) && (ah[4:1] == 4'd0);
    if (al[5:1] > 5'd9 && dec_en)
      al[6:1] = al[6:1] + 6'd6;
    c  = al[6] | al[5];
    ah = {2'b00, BusA_r[7:4], c} + {2'b00, BusB[7:4], 1'b1};
    ADC_N = ah[4];
    ADC_V = (ah[4] ^ BusA_r[7]) & ~(BusA_r[7] ^ BusB[7]);
    if (ah[5:1] > 5'd9 && dec_en)
      ah[6:1] = ah[6:1] + 6'd6;
    ADC_C = ah[6] | ah[5];
    ADC_Q = {ah[4:1], al[4:1]};
  end

  always_comb begin : alu_sbc
    logic [6:0] al;
    logic [5:0] ah;
    logic       c, ct;
    ct = (ALU_Op_r == ALU_AND) || (ALU_Op_r == ALU_ADC) || (ALU_Op_r == ALU_EQ2) ||
         (ALU_Op_r == ALU_SBC) || (ALU_Op_r == ALU_ROL) || (ALU_Op_r == ALU_ROR) ||
         (ALU_Op_r == ALU_INC);
    c  = P[0] | ~ct;
    al = {2'b00, BusA_r[3:0], c} - {2'b00, BusB[3:0], 1'b1};
    ah = {1'b0, BusA_r[7:4], 1'b0} - {1'b0, BusB[7:4], al[5]};
    SBC_Z = (al[4:1] == 4'd0) && (ah[4:1] == 4'd0);
    SBC_C = ~ah[5];
    SBC_V = (ah[4] ^ BusA_r[7]) & (BusA_r[7] ^ BusB[7]);
    SBC_N = ah[4];
    SBX_Q = {ah[4:1], al[4:1]};
    if (dec_en) begin
      if (al[5]) al[5:1] = al[5:1] - 5'd6;
      ah = {1'b0, BusA_r[7:4], 1'b0} - {1'b0, BusB[7:4], al[6]};
      if (ah[5]) ah[5:1] = ah[5:1] - 5'd6;
    end
    SBC_Q = {ah[4:1], al[4:1]};
  end
  /* verilator lint_on UNUSED */

  // 65C02 decimal SBC (Bruce Clark, sequence 3)
  logic [8:0] C02_diff;
  logic       C02_lo_borrow;
  logic [7:0] C02_SBC_Q;
  assign C02_diff      = {1'b0, BusA_r} - {1'b0, BusB} - {8'd0, ~P[0]};
  assign C02_lo_borrow = {1'b0, BusA_r[3:0]} < {1'b0, BusB[3:0]} + {4'd0, ~P[0]};
  assign C02_SBC_Q     = C02_diff[7:0] - (C02_diff[8] ? 8'h60 : 8'h00) - (C02_lo_borrow ? 8'h06 : 8'h00);

  always_comb begin : alu_main
    logic [7:0] q_t, q2_t, bm;
    P_Out = P;
    q_t   = BusA_r;
    q2_t  = BusA_r;
    bm    = 8'h01 << IR[6:4];
    case (ALU_Op_r)
      ALU_OR:  q_t = BusA_r | BusB;
      ALU_AND: q_t = BusA_r & BusB;
      ALU_EOR: q_t = BusA_r ^ BusB;
      ALU_ADC: begin P_Out[6] = ADC_V; P_Out[0] = ADC_C; q_t = ADC_Q; end
      ALU_CMP: P_Out[0] = SBC_C;
      ALU_SAX: begin P_Out[0] = SBC_C; q_t = SBX_Q; end
      ALU_SBC: begin P_Out[6] = SBC_V; P_Out[0] = SBC_C; q_t = (c02 && dec_en) ? C02_SBC_Q : SBC_Q; end
      ALU_TSB: q_t = BusA_r | BusB;
      ALU_TRB: q_t = ~BusA_r & BusB;
      ALU_RSMB: q_t = IR[7] ? (BusA_r | bm) : (BusA_r & ~bm);
      ALU_ASL: begin q_t = {BusA_r[6:0], 1'b0};  P_Out[0] = BusA_r[7]; end
      ALU_ROL: begin q_t = {BusA_r[6:0], P[0]};  P_Out[0] = BusA_r[7]; end
      ALU_LSR: begin q_t = {1'b0, BusA_r[7:1]};  P_Out[0] = BusA_r[0]; end
      ALU_ROR: begin q_t = {P[0], BusA_r[7:1]};  P_Out[0] = BusA_r[0]; end
      ALU_ARR: begin
        q_t = {P[0], BusA_r[7:1] & BusB[7:1]};
        P_Out[6] = q_t[5] ^ q_t[6];
        q2_t = q_t;
        if (dec_en) begin
          if ((BusA_r[3:0] & BusB[3:0]) > 4'd4) q2_t[3:0] = q_t[3:0] + 4'd6;
          if ((BusA_r[7:4] & BusB[7:4]) > 4'd4) begin
            q2_t[7:4] = q_t[7:4] + 4'd6;
            P_Out[0] = 1'b1;
          end else
            P_Out[0] = 1'b0;
        end else
          P_Out[0] = q_t[6];
      end
      ALU_BIT: P_Out[6] = BusB[6];
      ALU_DEC: q_t = BusA_r - 8'd1;
      ALU_INC: q_t = BusA_r + 8'd1;
      default: ;
    endcase

    case (ALU_Op_r)
      ALU_ADC: begin P_Out[7] = c02 ? q_t[7] : ADC_N; P_Out[1] = c02 ? (q_t == 8'd0) : ADC_Z; end
      ALU_SBC: begin P_Out[7] = c02 ? q_t[7] : SBC_N; P_Out[1] = c02 ? (q_t == 8'd0) : SBC_Z; end
      ALU_CMP, ALU_SAX: begin P_Out[7] = SBC_N; P_Out[1] = SBC_Z; end
      ALU_EQ1, ALU_RSMB: ;
      ALU_TSB, ALU_TRB, ALU_BITZ: P_Out[1] = ((BusA_r & BusB) == 8'd0);
      ALU_BIT: begin P_Out[7] = BusB[7]; P_Out[1] = ((BusA_r & BusB) == 8'd0); end
      ALU_ANC: begin P_Out[7] = q_t[7]; P_Out[0] = q_t[7]; P_Out[1] = (q_t == 8'd0); end
      default: begin P_Out[7] = q_t[7]; P_Out[1] = (q_t == 8'd0); end
    endcase

    ALU_Q = (ALU_Op_r == ALU_ARR) ? q2_t : q_t;
  end

  // ================================================================ top level
  assign o_NMI_ack  = NMIAct;
  assign really_rdy = Rdy | ~WRn_i;
  assign o_Sync     = (MCycle == 3'd0);
  assign o_EF       = EF_i;
  assign o_MF       = MF_i;
  assign o_XF       = XF_i;
  assign o_R_W_n    = WRn_i;
  assign o_ML_n     = ~(IR[7:6] != 2'b10 && IR[2:1] == 2'b11 && MCycle[2:1] != 2'b00);
  assign o_VP_n     = ~(IRQCycle && (MCycle == 3'd5 || MCycle == 3'd6));
  assign o_VDA      = (Set_Addr_To_r != AD_PBR);
  assign o_VPA      = ~Jump[1];
  assign o_DEBUG    = {IR, ABC, X, Y, S[7:0], P};
  assign o_Regs     = {PC, S, P, Y, X, ABC};

  // the 65xx design requires at least two clock cycles before starting its reset sequence
  always_ff @(posedge Clk or negedge Res_n) begin
    if (!Res_n) begin
      Res_n_i <= 1'b0;
      Res_n_d <= 1'b0;
    end else begin
      Res_n_i <= Res_n_d;
      Res_n_d <= 1'b1;
    end
  end

  always_ff @(posedge Clk or negedge Res_n_i) begin
    if (!Res_n_i) begin
      PC            <= 16'd0;
      IR            <= 8'd0;
      S             <= 16'd0;
      PBR           <= 8'd0;
      DBR           <= 8'd0;
      Mode_r        <= 2'b00;
      BCD_en_r      <= 1'b1;
      ALU_Op_r      <= ALU_BIT;
      Write_Data_r  <= WD_DL;
      Set_Addr_To_r <= AD_PBR;
      WRn_i         <= 1'b1;
      EF_i          <= 1'b1;
      MF_i          <= 1'b1;
      XF_i          <= 1'b1;
    end else if (Enable && really_rdy) begin
      WRn_i <= ~Write | RstCycle;
      PBR   <= 8'hFF;
      DBR   <= 8'hFF;
      EF_i  <= 1'b0;
      MF_i  <= 1'b0;
      XF_i  <= 1'b0;

      if (MCycle == CYC_SYNC) begin
        Mode_r <= Mode;
        BCD_en_r <= BCD_en;
        if (!IRQCycle && !NMICycle) PC <= PC + 16'd1;
        IR <= (IRQCycle || NMICycle) ? 8'h00 : DI;
        if (LDS) S[7:0] <= ALU_Q;
      end

      ALU_Op_r      <= ALU_Op;
      Write_Data_r  <= Write_Data;
      Set_Addr_To_r <= Break ? AD_PBR : Set_Addr_To;

      if (Inc_S) S <= S + 16'd1;
      if (Dec_S && !RstCycle) S <= S - 16'd1;

      if (IR == 8'h00 && MCycle == 3'd1 && !IRQCycle && !NMICycle) PC <= PC + 16'd1;

      case (Jump)
        2'b01: PC <= PC + 16'd1;
        2'b10: PC <= {DI, DL};
        2'b11: begin
          if (PCAdder[8] && !c02) PC[15:8] <= DL[7] ? PC[15:8] - 8'd1 : PC[15:8] + 8'd1;
          PC[7:0] <= PCAdder[7:0];
        end
        default: ;
      endcase
      if (PCHfix) PC[15:8] <= DL[7] ? PC[15:8] - 8'd1 : PC[15:8] + 8'd1;
      if (PCDec)  PC <= PC - 16'd1;
    end
  end

  // T65 never resets these; they hold their value while Res_n_i is low (Res_n_i acts as a synchronous enable)
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge Clk) begin
    if (Res_n_i && Enable) begin
      if (MCycle == CYC_SYNC)
        rdy_mod <= 1'b0;
      else if (((MCycle == 3'd3 && IR != 8'h93) || (MCycle == 3'd4 && IR == 8'h93)) && !Rdy)
        rdy_mod <= 1'b1;
    end
  end

  assign PCRel   = {1'b0, PC[7:0]} + {DL[7], DL};
  assign PCAdder = PCAdd ? PCRel : {1'b0, PC[7:0]};

  // flags
  always_ff @(posedge Clk or negedge Res_n_i) begin
    if (!Res_n_i)
      P <= 8'h00;
    else begin
      if (Enable && really_rdy) begin : p_upd
        logic [7:0] tmpP;
        tmpP = P;
        if (MCycle == CYC_SYNC && (LDA || LDX || LDY)) tmpP = P_Out;
        if (SaveP) tmpP = P_Out;
        if (LDP)   tmpP = ALU_Q;
        if (IR[4:0] == 5'b11000) begin
          case (IR[7:5])
            3'b000: tmpP[0] = 1'b0;      // CLC
            3'b001: tmpP[0] = 1'b1;      // SEC
            3'b010: tmpP[2] = 1'b0;      // CLI
            3'b011: tmpP[2] = 1'b1;      // SEI
            3'b101: tmpP[6] = 1'b0;      // CLV
            3'b110: tmpP[3] = 1'b0;      // CLD
            3'b111: tmpP[3] = 1'b1;      // SED
            default: ;
          endcase
        end
        tmpP[4] = 1'b1;
        if (IR == 8'h00 && MCycle == 3'd4 && !RstCycle) begin
          tmpP[2] = 1'b1;
          if (c02) tmpP[3] = 1'b0;
        end
        if (RstCycle) begin
          tmpP[2] = 1'b1;
          tmpP[3] = 1'b0;
        end
        tmpP[5] = 1'b1;
        P <= tmpP;
      end
      if (SO_n_o && !SO_n) P[6] <= 1'b1;
    end
  end

  always_ff @(posedge Clk) begin
    if (Res_n_i) begin
      if (Enable) begin
        if (really_rdy && MCycle == CYC_SYNC) begin
          if (LDA) ABC <= ALU_Q;
          if (LDX) X   <= ALU_Q;
          if (LDY) Y   <= ALU_Q;
        end
        // interrupt inputs are not sampled during the operand cycle of a branch
        if (IR[4:0] != 5'b10000 || Jump != 2'b01 || !really_rdy) IRQ_n_o <= IRQ_n;
        if (IR[4:0] != 5'b10000 || Jump != 2'b01) NMI_n_o <= NMI_n;
      end
      SO_n_o <= SO_n;
    end
  end

  // ================================================================ buses
  always_ff @(posedge Clk or negedge Res_n_i) begin
    if (!Res_n_i) begin
      BusA_r <= 8'd0;
      BusB   <= 8'd0;
      BusB_r <= 8'd0;
      AD     <= 8'd0;
      BAL    <= 9'd0;
      BAH    <= 8'd0;
      DL     <= 8'd0;
    end else if (Enable && really_rdy) begin
      BusA_r <= BusA;
      BusB   <= DI;
      if (Set_Addr_To_r == AD_PBR || Set_Addr_To_r == AD_ZPG) BusB_r <= DI + 8'd1;

      case (BAAdd)
        2'b01: begin AD <= AD + 8'd1; BAL <= BAL + 9'd1; end
        2'b10: BAL <= {1'b0, BAL[7:0]} + {1'b0, BusA};
        2'b11: if (BAL[8]) begin
          case (BAQuirk)
            2'b00: BAH <= BAH + 8'd1;
            2'b01: BAH <= (BAH + 8'd1) & DO_r;
            2'b10: BAH <= DO_r;
            default: ;
          endcase
        end
        default: ;
      endcase

      if (BAInc16) {BAH, BAL[7:0]} <= {BAH, BAL[7:0]} + 16'd1;
      if (ADAdd) AD <= AD + (AddY ? Y : X);

      if (IR == 8'h00) begin
        BAL <= 9'h1FF;
        BAH <= 8'hFF;
        if (RstCycle)
          BAL[2:0] <= 3'b100;
        else if (NMICycle || (NMIAct && MCycle == 3'd4) || NMI_entered)
          BAL[2:0] <= 3'b010;
        else
          BAL[2:0] <= 3'b110;
        if (Set_Addr_To_r == AD_BA) BAL[0] <= 1'b1;
      end

      if (LDDI)  DL <= DI;
      if (LDALU) DL <= ALU_Q;
      if (LDAD)  AD <= DI;
      if (LDBAL) BAL[7:0] <= DI;
      if (LDBAL && c02) BAL[8] <= 1'b0;   // T65 keeps a stale carry here; the 65C02 table relies on a clean one
      if (LDBAH) BAH <= DI;
    end
  end

  always_ff @(posedge Clk) begin
    if (Res_n_i && Enable && really_rdy)
      NMI_entered <= (IR == 8'h00 && MCycle == 3'd4 && !RstCycle &&
                      (NMICycle || NMIAct || NMI_entered)) ? 1'b1 : 1'b0;
  end

  assign Break = (BreakAtNA & ~BAL[8]) | (PCAdd & ~PCAdder[8]);

  always_comb begin
    case (Set_BusA_To)
      BA_DI:   BusA = DI;
      BA_ABC:  BusA = ABC;
      BA_X:    BusA = X;
      BA_Y:    BusA = Y;
      BA_S:    BusA = S[7:0];
      BA_P:    BusA = P;
      BA_DA:   BusA = ABC & DI;
      BA_DAO:  BusA = (ABC | 8'hEE) & DI;
      BA_DAX:  BusA = (ABC | 8'hEE) & DI & X;
      default: BusA = ABC & X;   // BA_AAX
    endcase
  end

  always_comb begin
    case (Set_Addr_To_r)
      AD_SP:   o_A = {16'h0001, S[7:0]};
      AD_ZPG:  o_A = {DBR, 8'h00, AD};
      AD_BA:   o_A = {8'h00, BAH, BAL[7:0]};
      default: o_A = {PBR, PC[15:8], c02 ? PC[7:0] : PCAdder[7:0]};
    endcase
  end

  // P pushed with B clear on IRQ/NMI entry
  assign PwithB = (IRQCycle || NMICycle) ? (P & 8'hEF) : P;
  assign o_DO   = DO_r;

  always_comb begin
    case (Write_Data_r)
      WD_DL:   DO_r = DL;
      WD_ABC:  DO_r = ABC;
      WD_X:    DO_r = X;
      WD_Y:    DO_r = Y;
      WD_S:    DO_r = S[7:0];
      WD_P:    DO_r = PwithB;
      WD_PCL:  DO_r = PC[7:0];
      WD_PCH:  DO_r = PC[15:8];
      WD_AX:   DO_r = ABC & X;
      WD_AXB:  DO_r = ABC & X & BusB_r;
      WD_XB:   DO_r = X & BusB_r;
      WD_YB:   DO_r = Y & BusB_r;
      default: DO_r = 8'h00;       // WD_ZERO (STZ)
    endcase
  end

  // ================================================================ state machine
  always_ff @(posedge Clk or negedge Res_n_i) begin
    if (!Res_n_i) begin
      MCycle   <= 3'd1;
      RstCycle <= 1'b1;
      IRQCycle <= 1'b0;
      NMICycle <= 1'b0;
      NMIAct   <= 1'b0;
    end else if (Enable) begin
      if (really_rdy && !Hold) begin
        if (c02 && MCycle == CYC_SYNC && !IRQCycle && !NMICycle && one_cycle_nop(DI))
          MCycle <= CYC_SYNC;
        else if (MCycle == LCycle || Break) begin
          MCycle   <= 3'd0;
          RstCycle <= 1'b0;
          IRQCycle <= 1'b0;
          NMICycle <= 1'b0;
          if (NMIAct && IR != 8'h00) begin
            NMICycle <= 1'b1;
            NMIAct   <= 1'b0;
          end else if (!IRQ_n_o && !P[2])
            IRQCycle <= 1'b1;
        end else
          MCycle <= MCycle + 3'd1;
      end
      if (NMI_n_o && !NMI_n && (IR[4:0] != 5'b10000 || Jump != 2'b01)) NMIAct <= 1'b1;
      if (NMI_entered) NMIAct <= 1'b0;
    end
  end

  // ================================================================ port selection
  generate
    if (C816) begin : g_c816
      // T65's Regs / DEBUG layouts carry the low bytes; D, DBR, PBR, E and the high bytes are not exported there
      /* verilator lint_off UNUSED */
      logic [15:0] r_pc, r_c, r_x, r_y, r_s, r_d;
      logic [7:0]  r_dbr, r_pbr, r_p, r_ir;
      logic        r_e, wait_n;
      /* verilator lint_on UNUSED */
      t65sv816 u_816 (
        .Clk(Clk), .Enable(Enable), .Res_n(Res_n), .Rdy(Rdy), .Abort_n(Abort_n), .IRQ_n(IRQ_n), .NMI_n(NMI_n),
        .DI(DI), .A(A), .DO(DO), .R_W_n(R_W_n), .VDA(VDA), .VPA(VPA), .VP_n(VP_n), .ML_n(ML_n), .E(EF), .MF(MF),
        .XF(XF), .Sync(Sync), .Wait_n(wait_n), .NMI_ack(NMI_ack), .Regs_PC(r_pc), .Regs_C(r_c), .Regs_X(r_x),
        .Regs_Y(r_y), .Regs_S(r_s), .Regs_D(r_d), .Regs_DBR(r_dbr), .Regs_PBR(r_pbr), .Regs_P(r_p), .Regs_E(r_e),
        .Regs_IR(r_ir));
      assign Regs  = {r_pc, r_s, r_p, r_y[7:0], r_x[7:0], r_c[7:0]};
      assign DEBUG = {r_ir, r_c[7:0], r_x[7:0], r_y[7:0], r_s[7:0], r_p};
    end else begin : g_6502
      assign A = o_A;         assign DO = o_DO;       assign R_W_n = o_R_W_n; assign Sync = o_Sync;
      assign EF = o_EF;       assign MF = o_MF;       assign XF = o_XF;       assign ML_n = o_ML_n;
      assign VP_n = o_VP_n;   assign VDA = o_VDA;     assign VPA = o_VPA;     assign NMI_ack = o_NMI_ack;
      assign Regs = o_Regs;   assign DEBUG = o_DEBUG;
    end
  endgenerate

endmodule

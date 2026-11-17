// t65sv816: W65C816S core (emulation + native modes, ABORT, WAI/STP, MVN/MVP), bus-cycle exact against
// SingleStepTests 65816. Part of t65sv; derived-work notice and licence: see t65sv.sv.
//
// Sequencer: every instruction is a short list of micro-ops (one per bus cycle, index K = 1..), looked up
// from the opcode. A micro-op may carry a skip condition (8-bit width, DL = 0, no index carry, branch not
// taken, ...); skipped micro-ops take no time. K reaching an END entry is the opcode fetch of the next
// instruction (or the first cycle of an interrupt).
module t65sv816 (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  input  logic        Abort_n,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  input  logic [7:0]  DI,
  output logic [23:0] A,
  output logic [7:0]  DO,
  output logic        R_W_n,
  output logic        VDA,
  output logic        VPA,
  output logic        VP_n,     // vector pull
  output logic        ML_n,     // memory lock
  output logic        E,        // emulation flag pin
  output logic        MF,       // M as seen on the MX pin
  output logic        XF,       // X as seen on the MX pin
  output logic        Sync,     // opcode fetch (VDA & VPA)
  output logic        Wait_n,   // low while WAI waits (the chip pulls RDY low)
  output logic        NMI_ack,  // one-cycle pulse when an NMI is taken
  output logic [15:0] Regs_PC,
  output logic [15:0] Regs_C,
  output logic [15:0] Regs_X,
  output logic [15:0] Regs_Y,
  output logic [15:0] Regs_S,
  output logic [15:0] Regs_D,
  output logic [7:0]  Regs_DBR,
  output logic [7:0]  Regs_PBR,
  output logic [7:0]  Regs_P,
  output logic        Regs_E,
  output logic [7:0]  Regs_IR
);
  // ------------------------------------------------------------------ micro-op kinds
  localparam logic [5:0]
    U_END  = 6'd0,   // opcode fetch (next instruction)
    U_OP1  = 6'd1,   // operand byte 1 -> OPR[7:0], DAT[7:0]
    U_OP2  = 6'd2,   // operand byte 2 -> OPR[15:8], DAT[15:8]
    U_OP3  = 6'd3,   // operand byte 3 -> BNK
    U_IMM1 = 6'd4,   // immediate low byte (executes if 8-bit)
    U_IMM2 = 6'd5,   // immediate high byte (executes)
    U_IOPC = 6'd6,   // internal, address PBR:PC
    U_IO   = 6'd7,   // internal, previous address
    U_IOX  = 6'd8,   // internal, index-carry address (bank:high:(low+index) without the carry)
    U_DRL  = 6'd9,   // data read EA (executes if 8-bit)
    U_DRH  = 6'd10,  // data read EA+1 (executes)
    U_DWL  = 6'd11,  // data write EA
    U_DWH  = 6'd12,  // data write EA+1
    U_MRL  = 6'd13,  // read-modify-write: read EA
    U_MRH  = 6'd14,  //   read EA+1
    U_MOD  = 6'd15,  //   modify (native: internal; emulation: rewrite old value)
    U_MWH  = 6'd16,  //   write EA+1
    U_MWL  = 6'd17,  //   write EA
    U_PRL  = 6'd18,  // pointer read EA -> DAT[7:0]
    U_PRH  = 6'd19,  // pointer read EA+1 -> DAT[15:8]
    U_PRB  = 6'd20,  // pointer read EA+2 -> BNK
    U_PSHH = 6'd21,  // push high byte of the push source
    U_PSHL = 6'd22,  // push low byte
    U_PSHK = 6'd23,  // push PBR
    U_PSHB = 6'd24,  // push DBR
    U_PSHP = 6'd25,  // push P
    U_PULL = 6'd26,  // pull -> DAT[7:0]
    U_PULH = 6'd27,  // pull -> DAT[15:8]
    U_PULB = 6'd28,  // pull -> BNK
    U_PULP = 6'd29,  // pull -> P
    U_VECL = 6'd30,  // vector low
    U_VECH = 6'd31,  // vector high
    U_MVR  = 6'd32,  // block move read
    U_MVW  = 6'd33,  // block move write
    U_WAIT = 6'd34,  // WAI: waiting for an interrupt
    U_STOP = 6'd35;  // STP: stopped until reset

  // skip conditions
  localparam logic [3:0] S_NO = 4'd0, S_W8 = 4'd1, S_DL0 = 4'd2, S_IDX = 4'd3, S_NT = 4'd4, S_BPX = 4'd5,
                         S_EMU = 4'd6;

  // end-of-cycle actions
  localparam logic [4:0] A_NONE = 5'd0, A_EADP = 5'd1, A_EADPX = 5'd2, A_EADPY = 5'd3,   // EADPX/Y: index step of d,x d,y (d,x)
                         A_EASR = 5'd4,
                         A_EAABS = 5'd5, A_EAABX = 5'd6, A_EAABY = 5'd7, A_EALNG = 5'd8, A_EALNX = 5'd9,
                         A_EAPTR = 5'd10, A_EAPTY = 5'd11, A_EAPTL = 5'd12, A_EAPLY = 5'd13, A_EAAB0 = 5'd14,
                         A_EAPBX = 5'd15, A_JMP = 5'd16, A_JML = 5'd17, A_JMPI = 5'd18, A_JMLI = 5'd19,
                         A_JSR = 5'd20, A_JSL = 5'd21, A_RTS = 5'd22, A_RTL = 5'd23, A_BR = 5'd24,
                         A_BRL = 5'd25, A_PER = 5'd26, A_EXEC = 5'd27, A_PCI = 5'd28, A_MV = 5'd29,
                         A_VEC = 5'd30, A_PBR = 5'd31;

  // addressing modes of the data instructions
  localparam logic [4:0] AM_IMM = 5'd1, AM_DP = 5'd2, AM_DPX = 5'd3, AM_DPY = 5'd4,
                         AM_DPI = 5'd5, AM_DPIL = 5'd6, AM_DPXI = 5'd7, AM_DPIY = 5'd8, AM_DPILY = 5'd9,
                         AM_ABS = 5'd10, AM_ABX = 5'd11, AM_ABY = 5'd12, AM_ABL = 5'd13, AM_ALX = 5'd14,
                         AM_SR = 5'd15, AM_SRIY = 5'd16, AM_SPC = 5'd17;
  localparam logic [1:0] K_RD = 2'd0, K_WR = 2'd1, K_RMW = 2'd2;
  localparam logic [4:0] O_LDA = 5'd0, O_LDX = 5'd1, O_LDY = 5'd2, O_STA = 5'd3, O_STX = 5'd4, O_STY = 5'd5,
                         O_STZ = 5'd6, O_ORA = 5'd7, O_AND = 5'd8, O_EOR = 5'd9, O_ADC = 5'd10, O_SBC = 5'd11,
                         O_CMP = 5'd12, O_CPX = 5'd13, O_CPY = 5'd14, O_BIT = 5'd15, O_ASL = 5'd16,
                         O_ROL = 5'd17, O_LSR = 5'd18, O_ROR = 5'd19, O_INC = 5'd20, O_DEC = 5'd21,
                         O_TSB = 5'd22, O_TRB = 5'd23, O_BITI = 5'd24;
  // EA increment wrap
  localparam logic [1:0] W24 = 2'd0, W16 = 2'd1, W8 = 2'd2;
  // interrupt kinds
  localparam logic [2:0] I_IRQ = 3'd0, I_NMI = 3'd1, I_ABT = 3'd2, I_RES = 3'd3;

  // ------------------------------------------------------------------ state
  logic [15:0] C, X, Y, S, D, PC;
  logic [7:0]  DBR, PBR, P;
  logic        Ef;
  logic [7:0]  IR;
  logic [3:0]  K;
  logic        INTR;         // running sequence is a hardware interrupt / reset (IR = 00)
  logic [2:0]  IK;
  logic [23:0] EA, IAD, LA;
  logic [1:0]  EAW;
  logic [15:0] OPR, DAT, SP;
  logic [7:0]  BNK;
  logic        CX;           // index / branch page carry
  logic        sM, sX, sE;   // M / X / E as at the start of the instruction (pins)
  logic        nmi_pend, nmi_d, abt_pend;
  logic        res_pend;     // reset sequence pending (taken at the first fetch after reset)
  // ABORT: architectural state at the start of the instruction
  logic [15:0] aC, aX, aY, aS, aD, aPC;
  logic [7:0]  aDBR, aPBR, aP;
  logic        aE;

  logic Mf, Xf;
  assign Mf = Ef | P[5];
  assign Xf = Ef | P[4];

  assign Regs_PC = PC; assign Regs_C = C; assign Regs_X = X; assign Regs_Y = Y; assign Regs_S = S;
  assign Regs_D = D; assign Regs_DBR = DBR; assign Regs_PBR = PBR; assign Regs_P = P; assign Regs_E = Ef;
  assign Regs_IR = IR;

  // ------------------------------------------------------------------ decode (data instructions)
  logic [4:0] am, op;
  logic [1:0] kd;
  logic       wx;
  always_comb begin
    am = AM_SPC; op = O_LDA; kd = K_RD; wx = 1'b0;
    if (IR[1:0] == 2'b01 || IR[4:0] == 5'b10010 || (IR[1:0] == 2'b11 && IR[2]) || IR[3:0] == 4'h3) begin
      case (IR[7:5])
        3'd0: op = O_ORA; 3'd1: op = O_AND; 3'd2: op = O_EOR; 3'd3: op = O_ADC;
        3'd4: begin op = O_STA; kd = K_WR; end
        3'd5: op = O_LDA; 3'd6: op = O_CMP; default: op = O_SBC;
      endcase
      case (IR[4:0])
        5'h01: am = AM_DPXI;  5'h11: am = AM_DPIY;  5'h12: am = AM_DPI;
        5'h03: am = AM_SR;    5'h13: am = AM_SRIY;
        5'h05: am = AM_DP;    5'h15: am = AM_DPX;
        5'h07: am = AM_DPIL;  5'h17: am = AM_DPILY;
        5'h09: am = AM_IMM;   5'h19: am = AM_ABY;
        5'h0D: am = AM_ABS;   5'h1D: am = AM_ABX;
        5'h0F: am = AM_ABL;   5'h1F: am = AM_ALX;
        default: am = AM_SPC;
      endcase
      if (IR == 8'h89) begin op = O_BITI; kd = K_RD; end
    end else if (IR[1:0] == 2'b10 && IR[2]) begin
      case (IR[7:5])
        3'd0: begin op = O_ASL; kd = K_RMW; end
        3'd1: begin op = O_ROL; kd = K_RMW; end
        3'd2: begin op = O_LSR; kd = K_RMW; end
        3'd3: begin op = O_ROR; kd = K_RMW; end
        3'd4: begin op = O_STX; kd = K_WR; wx = 1'b1; end
        3'd5: begin op = O_LDX; kd = K_RD; wx = 1'b1; end
        3'd6: begin op = O_DEC; kd = K_RMW; end
        default: begin op = O_INC; kd = K_RMW; end
      endcase
      case ({IR[4], IR[3]})
        2'b00: am = AM_DP;
        2'b10: am = (IR[7:6] == 2'b10) ? AM_DPY : AM_DPX;
        2'b01: am = AM_ABS;
        default: am = (IR == 8'hBE) ? AM_ABY : AM_ABX;
      endcase
      if (IR == 8'h9E) begin op = O_STZ; kd = K_WR; wx = 1'b0; end
    end else begin
      case (IR)
        8'h04: begin am = AM_DP;  op = O_TSB; kd = K_RMW; end
        8'h0C: begin am = AM_ABS; op = O_TSB; kd = K_RMW; end
        8'h14: begin am = AM_DP;  op = O_TRB; kd = K_RMW; end
        8'h1C: begin am = AM_ABS; op = O_TRB; kd = K_RMW; end
        8'h24: begin am = AM_DP;  op = O_BIT; end
        8'h34: begin am = AM_DPX; op = O_BIT; end
        8'h2C: begin am = AM_ABS; op = O_BIT; end
        8'h3C: begin am = AM_ABX; op = O_BIT; end
        8'h64: begin am = AM_DP;  op = O_STZ; kd = K_WR; end
        8'h74: begin am = AM_DPX; op = O_STZ; kd = K_WR; end
        8'h9C: begin am = AM_ABS; op = O_STZ; kd = K_WR; end
        8'h84: begin am = AM_DP;  op = O_STY; kd = K_WR; wx = 1'b1; end
        8'h94: begin am = AM_DPX; op = O_STY; kd = K_WR; wx = 1'b1; end
        8'h8C: begin am = AM_ABS; op = O_STY; kd = K_WR; wx = 1'b1; end
        8'hA4: begin am = AM_DP;  op = O_LDY; wx = 1'b1; end
        8'hB4: begin am = AM_DPX; op = O_LDY; wx = 1'b1; end
        8'hAC: begin am = AM_ABS; op = O_LDY; wx = 1'b1; end
        8'hBC: begin am = AM_ABX; op = O_LDY; wx = 1'b1; end
        8'hC4: begin am = AM_DP;  op = O_CPY; wx = 1'b1; end
        8'hCC: begin am = AM_ABS; op = O_CPY; wx = 1'b1; end
        8'hE4: begin am = AM_DP;  op = O_CPX; wx = 1'b1; end
        8'hEC: begin am = AM_ABS; op = O_CPX; wx = 1'b1; end
        8'hA0: begin am = AM_IMM; op = O_LDY; wx = 1'b1; end
        8'hA2: begin am = AM_IMM; op = O_LDX; wx = 1'b1; end
        8'hC0: begin am = AM_IMM; op = O_CPY; wx = 1'b1; end
        8'hE0: begin am = AM_IMM; op = O_CPX; wx = 1'b1; end
        // index-width stack ops
        8'hDA, 8'hFA, 8'h5A, 8'h7A: wx = 1'b1;
        default: am = AM_SPC;
      endcase
    end
  end

  // operand width of the running instruction (PLD / PEA / PEI / PER / PHD and the 16-bit transfers are 16-bit
  // regardless; PLB is 8-bit)
  logic w16;
  always_comb begin
    case (IR)
      8'h0B, 8'h2B, 8'hD4, 8'hF4, 8'h62: w16 = 1'b1;
      8'hAB: w16 = 1'b0;
      default: w16 = wx ? !Xf : !Mf;
    endcase
  end

  // "new" 65816 stack instructions: in emulation they address the stack with the full 16-bit S
  logic newstk;
  always_comb begin
    case (IR)
      8'hAB, 8'h0B, 8'h2B, 8'h62, 8'hD4, 8'hF4, 8'h22, 8'h6B, 8'hFC: newstk = !INTR;
      default: newstk = 1'b0;
    endcase
  end

  // ------------------------------------------------------------------ micro-program
  function automatic logic [14:0] mk(input logic [5:0] kind, input logic [3:0] sk, input logic [4:0] act);
    mk = {act, sk, kind};
  endfunction

  // data part of a data instruction, starting at step d0
  function automatic logic [14:0] dpart(input logic [1:0] kd_, input logic [3:0] i);
    dpart = mk(U_END, S_NO, A_NONE);
    case (kd_)
      K_RD: case (i)
              4'd0: dpart = mk(U_DRL, S_NO, A_NONE);
              4'd1: dpart = mk(U_DRH, S_W8, A_NONE);
              default: ;
            endcase
      K_WR: case (i)
              4'd0: dpart = mk(U_DWL, S_NO, A_NONE);
              4'd1: dpart = mk(U_DWH, S_W8, A_NONE);
              default: ;
            endcase
      default: case (i)
              4'd0: dpart = mk(U_MRL, S_NO, A_NONE);
              4'd1: dpart = mk(U_MRH, S_W8, A_NONE);
              4'd2: dpart = mk(U_MOD, S_NO, A_NONE);
              4'd3: dpart = mk(U_MWH, S_W8, A_NONE);
              4'd4: dpart = mk(U_MWL, S_NO, A_NONE);
              default: ;
            endcase
    endcase
  endfunction

  function automatic logic [14:0] uprog(input logic [7:0] ir, input logic [3:0] k, input logic intr,
                                        input logic [4:0] am_, input logic [1:0] kd_);
    logic [3:0] ixs;   // skip condition of the index-carry cycle
    uprog = mk(U_END, S_NO, A_NONE);
    ixs = (kd_ == K_RD) ? S_IDX : S_NO;
    if (am_ != AM_SPC) begin
      case (am_)
        AM_IMM:  case (k)
                   4'd1: uprog = mk(U_IMM1, S_NO, A_NONE);
                   4'd2: uprog = mk(U_IMM2, S_W8, A_NONE);
                   default: ;
                 endcase
        AM_DP:   case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   default: uprog = dpart(kd_, k - 4'd3);
                 endcase
        AM_DPX, AM_DPY:
                 case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   4'd3: uprog = mk(U_IO, S_NO, (am_ == AM_DPX) ? A_EADPX : A_EADPY);
                   default: uprog = dpart(kd_, k - 4'd4);
                 endcase
        AM_SR:   case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EASR);
                   4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                   default: uprog = dpart(kd_, k - 4'd3);
                 endcase
        AM_DPI:  case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   4'd3: uprog = mk(U_PRL, S_NO, A_NONE);
                   4'd4: uprog = mk(U_PRH, S_NO, A_EAPTR);
                   default: uprog = dpart(kd_, k - 4'd5);
                 endcase
        AM_DPXI: case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   4'd3: uprog = mk(U_IO, S_NO, A_EADPX);
                   4'd4: uprog = mk(U_PRL, S_NO, A_NONE);
                   4'd5: uprog = mk(U_PRH, S_NO, A_EAPTR);
                   default: uprog = dpart(kd_, k - 4'd6);
                 endcase
        AM_DPIY: case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   4'd3: uprog = mk(U_PRL, S_NO, A_NONE);
                   4'd4: uprog = mk(U_PRH, S_NO, A_EAPTY);
                   4'd5: uprog = mk(U_IOX, ixs, A_NONE);
                   default: uprog = dpart(kd_, k - 4'd6);
                 endcase
        AM_DPIL, AM_DPILY:
                 case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
                   4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
                   4'd3: uprog = mk(U_PRL, S_NO, A_NONE);
                   4'd4: uprog = mk(U_PRH, S_NO, A_NONE);
                   4'd5: uprog = mk(U_PRB, S_NO, (am_ == AM_DPIL) ? A_EAPTL : A_EAPLY);
                   default: uprog = dpart(kd_, k - 4'd6);
                 endcase
        AM_SRIY: case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_EASR);
                   4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                   4'd3: uprog = mk(U_PRL, S_NO, A_NONE);
                   4'd4: uprog = mk(U_PRH, S_NO, A_EAPTY);
                   4'd5: uprog = mk(U_IO, S_NO, A_NONE);
                   default: uprog = dpart(kd_, k - 4'd6);
                 endcase
        AM_ABS:  case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
                   4'd2: uprog = mk(U_OP2, S_NO, A_EAABS);
                   default: uprog = dpart(kd_, k - 4'd3);
                 endcase
        AM_ABX, AM_ABY:
                 case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
                   4'd2: uprog = mk(U_OP2, S_NO, (am_ == AM_ABX) ? A_EAABX : A_EAABY);
                   4'd3: uprog = mk(U_IOX, ixs, A_NONE);
                   default: uprog = dpart(kd_, k - 4'd4);
                 endcase
        default: // AM_ABL, AM_ALX
                 case (k)
                   4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
                   4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
                   4'd3: uprog = mk(U_OP3, S_NO, (am_ == AM_ABL) ? A_EALNG : A_EALNX);
                   default: uprog = dpart(kd_, k - 4'd4);
                 endcase
      endcase
    end else begin
      case (ir)
        8'h00, 8'h02: // BRK, COP, hardware interrupts and reset
          case (k)
            4'd1: uprog = intr ? mk(U_IOPC, S_NO, A_NONE) : mk(U_OP1, S_NO, A_NONE);
            4'd2: uprog = mk(U_PSHK, S_EMU, A_NONE);
            4'd3: uprog = mk(U_PSHH, S_NO, A_NONE);
            4'd4: uprog = mk(U_PSHL, S_NO, A_NONE);
            4'd5: uprog = mk(U_PSHP, S_NO, A_NONE);
            4'd6: uprog = mk(U_VECL, S_NO, A_NONE);
            4'd7: uprog = mk(U_VECH, S_NO, A_VEC);
            default: ;
          endcase
        8'h08: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_PSHP, S_NO, A_NONE); default: ; endcase
        8'h8B: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_PSHB, S_NO, A_NONE); default: ; endcase
        8'h4B: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_PSHK, S_NO, A_NONE); default: ; endcase
        8'h0B, 8'h48, 8'hDA, 8'h5A: // PHD, PHA, PHX, PHY
          case (k)
            4'd1: uprog = mk(U_IOPC, S_NO, A_NONE);
            4'd2: uprog = mk(U_PSHH, S_W8, A_NONE);
            4'd3: uprog = mk(U_PSHL, S_NO, A_NONE);
            default: ;
          endcase
        8'h28: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PULP, S_NO, A_NONE); default: ; endcase
        8'h2B, 8'h68, 8'hFA, 8'h7A, 8'hAB: // PLD, PLA, PLX, PLY, PLB
          case (k)
            4'd1: uprog = mk(U_IOPC, S_NO, A_NONE);
            4'd2: uprog = mk(U_IO, S_NO, A_NONE);
            4'd3: uprog = mk(U_PULL, S_NO, A_NONE);
            4'd4: uprog = mk(U_PULH, S_W8, A_NONE);
            default: ;
          endcase
        8'hF4: // PEA
          case (k)
            4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
            4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
            4'd3: uprog = mk(U_PSHH, S_NO, A_NONE);
            4'd4: uprog = mk(U_PSHL, S_NO, A_NONE);
            default: ;
          endcase
        8'hD4: // PEI
          case (k)
            4'd1: uprog = mk(U_OP1, S_NO, A_EADP);
            4'd2: uprog = mk(U_IO, S_DL0, A_NONE);
            4'd3: uprog = mk(U_PRL, S_NO, A_NONE);
            4'd4: uprog = mk(U_PRH, S_NO, A_NONE);
            4'd5: uprog = mk(U_PSHH, S_NO, A_NONE);
            4'd6: uprog = mk(U_PSHL, S_NO, A_NONE);
            default: ;
          endcase
        8'h62: // PER
          case (k)
            4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
            4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
            4'd3: uprog = mk(U_IO, S_NO, A_PER);
            4'd4: uprog = mk(U_PSHH, S_NO, A_NONE);
            4'd5: uprog = mk(U_PSHL, S_NO, A_NONE);
            default: ;
          endcase
        8'hEB: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_EXEC); default: ; endcase
        8'h42: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_PCI); default: ; endcase
        8'hC2, 8'hE2: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_EXEC); default: ; endcase
        8'h10, 8'h30, 8'h50, 8'h70, 8'h90, 8'hB0, 8'hD0, 8'hF0, 8'h80:
          case (k)
            4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
            4'd2: uprog = mk(U_IO, S_NT, A_BR);
            4'd3: uprog = mk(U_IO, S_BPX, A_NONE);
            default: ;
          endcase
        8'h82: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
                        4'd3: uprog = mk(U_IO, S_NO, A_BRL); default: ; endcase
        8'h4C: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_JMP); default: ; endcase
        8'h5C: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
                        4'd3: uprog = mk(U_OP3, S_NO, A_JML); default: ; endcase
        8'h6C: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_EAAB0);
                        4'd3: uprog = mk(U_PRL, S_NO, A_NONE); 4'd4: uprog = mk(U_PRH, S_NO, A_JMPI); default: ; endcase
        8'h7C: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_EAPBX);
                        4'd3: uprog = mk(U_IO, S_NO, A_NONE); 4'd4: uprog = mk(U_PRL, S_NO, A_NONE);
                        4'd5: uprog = mk(U_PRH, S_NO, A_JMPI); default: ; endcase
        8'hDC: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_EAAB0);
                        4'd3: uprog = mk(U_PRL, S_NO, A_NONE); 4'd4: uprog = mk(U_PRH, S_NO, A_NONE);
                        4'd5: uprog = mk(U_PRB, S_NO, A_JMLI); default: ; endcase
        8'h20: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
                        4'd3: uprog = mk(U_IO, S_NO, A_NONE); 4'd4: uprog = mk(U_PSHH, S_NO, A_NONE);
                        4'd5: uprog = mk(U_PSHL, S_NO, A_JSR); default: ; endcase
        8'h22: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PSHK, S_NO, A_NONE); 4'd4: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd5: uprog = mk(U_OP3, S_NO, A_NONE); 4'd6: uprog = mk(U_PSHH, S_NO, A_NONE);
                        4'd7: uprog = mk(U_PSHL, S_NO, A_JSL); default: ; endcase
        8'hFC: case (k) 4'd1: uprog = mk(U_OP1, S_NO, A_NONE); 4'd2: uprog = mk(U_PSHH, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PSHL, S_NO, A_NONE); 4'd4: uprog = mk(U_OP2, S_NO, A_EAPBX);
                        4'd5: uprog = mk(U_IO, S_NO, A_NONE); 4'd6: uprog = mk(U_PRL, S_NO, A_NONE);
                        4'd7: uprog = mk(U_PRH, S_NO, A_JMPI); default: ; endcase
        8'h60: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PULL, S_NO, A_NONE); 4'd4: uprog = mk(U_PULH, S_NO, A_NONE);
                        4'd5: uprog = mk(U_IO, S_NO, A_RTS); default: ; endcase
        8'h6B: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PULL, S_NO, A_NONE); 4'd4: uprog = mk(U_PULH, S_NO, A_NONE);
                        4'd5: uprog = mk(U_PULB, S_NO, A_RTL); default: ; endcase
        8'h40: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_PULP, S_NO, A_NONE); 4'd4: uprog = mk(U_PULL, S_NO, A_NONE);
                        4'd5: uprog = mk(U_PULH, S_NO, A_RTS); 4'd6: uprog = mk(U_PULB, S_EMU, A_PBR); default: ; endcase
        8'h54, 8'h44: // MVN, MVP
          case (k)
            4'd1: uprog = mk(U_OP1, S_NO, A_NONE);
            4'd2: uprog = mk(U_OP2, S_NO, A_NONE);
            4'd3: uprog = mk(U_MVR, S_NO, A_NONE);
            4'd4: uprog = mk(U_MVW, S_NO, A_NONE);
            4'd5: uprog = mk(U_IO, S_NO, A_NONE);
            4'd6: uprog = mk(U_IO, S_NO, A_MV);
            default: ;
          endcase
        8'hCB: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_WAIT, S_NO, A_NONE); default: ; endcase
        8'hDB: case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_NONE); 4'd2: uprog = mk(U_IO, S_NO, A_NONE);
                        4'd3: uprog = mk(U_STOP, S_NO, A_NONE); default: ; endcase
        default: // one-cycle implied operations (transfers, flags, INC/DEC/shift A, INX..., XCE, NOP)
          case (k) 4'd1: uprog = mk(U_IOPC, S_NO, A_EXEC); default: ; endcase
      endcase
    end
  endfunction

  // ------------------------------------------------------------------ ALU
  // add with carry (sub: b already inverted), 65816 decimal algorithm; returns {C, V, result}
  function automatic logic [17:0] addc(input logic [15:0] a, input logic [15:0] b, input logic ci,
                                       input logic dec, input logic sub, input logic w);
    logic [19:0] r;
    logic        t7, t15;
    logic        c, v;
    logic [15:0] res;
    if (!dec) begin
      r = {4'd0, a} + {4'd0, b} + {19'd0, ci};
      res = r[15:0];
      c = w ? r[16] : r[8];
      v = w ? (~(a[15] ^ b[15]) & (a[15] ^ r[15])) : (~(a[7] ^ b[7]) & (a[7] ^ r[7]));
    end else begin
      // nibble 0
      r = {16'd0, a[3:0]} + {16'd0, b[3:0]} + {19'd0, ci};
      if (sub) begin c = (r > 20'h0000F); if (!c) r = r - 20'h6; end
      else     begin if (r > 20'h00009) r = r + 20'h6; c = (r > 20'h0000F); end
      // nibble 1
      r = {12'd0, a[7:4], 4'd0} + {12'd0, b[7:4], 4'd0} + {15'd0, c, 4'd0} + {16'd0, r[3:0]};
      t7 = r[7]; t15 = 1'b0;
      if (w) begin
        if (sub) begin c = (r > 20'h000FF); if (!c) r = r - 20'h60; end
        else     begin if (r > 20'h0009F) r = r + 20'h60; c = (r > 20'h000FF); end
        // nibble 2
        r = {8'd0, a[11:8], 8'd0} + {8'd0, b[11:8], 8'd0} + {11'd0, c, 8'd0} + {12'd0, r[7:0]};
        if (sub) begin c = (r > 20'h00FFF); if (!c) r = r - 20'h600; end
        else     begin if (r > 20'h009FF) r = r + 20'h600; c = (r > 20'h00FFF); end
        // nibble 3
        r = {4'd0, a[15:12], 12'd0} + {4'd0, b[15:12], 12'd0} + {7'd0, c, 12'd0} + {8'd0, r[11:0]};
        t15 = r[15];
        v = ~(a[15] ^ b[15]) & (a[15] ^ t15);
        if (sub) begin c = (r > 20'h0FFFF); if (!c) r = r - 20'h6000; end
        else     begin if (r > 20'h09FFF) r = r + 20'h6000; c = (r > 20'h0FFFF); end
      end else begin
        v = ~(a[7] ^ b[7]) & (a[7] ^ t7);
        if (sub) begin c = (r > 20'h000FF); if (!c) r = r - 20'h60; end
        else     begin if (r > 20'h0009F) r = r + 20'h60; c = (r > 20'h000FF); end
      end
      res = r[15:0];
    end
    addc = {c, v, res};
  endfunction

  // read-type operation: returns {dst(0 none,1 C,2 X,3 Y), value16, P}
  function automatic logic [25:0] alu_rd(input logic [4:0] o, input logic [15:0] v, input logic w,
                                         input logic [15:0] c_, input logic [15:0] x_, input logic [15:0] y_,
                                         input logic [7:0] p_);
    logic [15:0] m, t, res;
    logic [17:0] ar;
    logic [16:0] d;
    logic [1:0]  dst;
    logic [7:0]  pp;
    m = w ? 16'hFFFF : 16'h00FF;
    pp = p_; dst = 2'd0; res = 16'd0; t = 16'd0;
    case (o)
      O_LDA: begin t = v & m; dst = 2'd1; res = w ? v : {c_[15:8], v[7:0]}; end
      O_LDX: begin t = v & m; dst = 2'd2; res = v & m; end
      O_LDY: begin t = v & m; dst = 2'd3; res = v & m; end
      O_ORA: begin t = (c_ | v) & m; dst = 2'd1; res = w ? t : {c_[15:8], t[7:0]}; end
      O_AND: begin t = (c_ & v) & m; dst = 2'd1; res = w ? t : {c_[15:8], t[7:0]}; end
      O_EOR: begin t = (c_ ^ v) & m; dst = 2'd1; res = w ? t : {c_[15:8], t[7:0]}; end
      O_ADC, O_SBC: begin
        ar = addc(c_ & m, (o == O_SBC) ? (~v & m) : (v & m), p_[0], p_[3], o == O_SBC, w);
        t = ar[15:0] & m; dst = 2'd1; res = w ? t : {c_[15:8], t[7:0]};
        pp[0] = ar[17]; pp[6] = ar[16];
      end
      O_CMP, O_CPX, O_CPY: begin
        d = {1'b0, ((o == O_CMP) ? c_ : (o == O_CPX) ? x_ : y_) & m} - {1'b0, v & m};
        t = d[15:0] & m;
        pp[0] = !d[16];
      end
      O_BIT: begin
        t = c_ & v & m;
        pp[7] = w ? v[15] : v[7];
        pp[6] = w ? v[14] : v[6];
      end
      default: t = c_ & v & m;   // O_BITI
    endcase
    pp[1] = (t == 16'd0);
    if (o != O_BIT && o != O_BITI) pp[7] = w ? t[15] : t[7];
    alu_rd = {dst, res, pp};
  endfunction

  // read-modify-write operation: returns {value16, P}
  function automatic logic [23:0] alu_rmw(input logic [4:0] o, input logic [15:0] v, input logic w,
                                          input logic [15:0] acc, input logic [7:0] p_);
    logic [15:0] r, m;
    logic [7:0]  pp;
    m = w ? 16'hFFFF : 16'h00FF;
    pp = p_;
    case (o)
      O_ASL: begin r = (v << 1) & m; pp[0] = w ? v[15] : v[7]; end
      O_ROL: begin r = ((v << 1) | {15'd0, p_[0]}) & m; pp[0] = w ? v[15] : v[7]; end
      O_LSR: begin r = (v & m) >> 1; pp[0] = v[0]; end
      O_ROR: begin r = ((v & m) >> 1) | (p_[0] ? (w ? 16'h8000 : 16'h0080) : 16'h0000); pp[0] = v[0]; end
      O_INC: r = (v + 16'd1) & m;
      O_DEC: r = (v - 16'd1) & m;
      O_TSB: r = (v | acc) & m;
      default: r = (v & ~acc) & m;   // O_TRB
    endcase
    if (o == O_TSB || o == O_TRB) pp[1] = ((acc & v & m) == 16'd0);
    else begin pp[1] = (r == 16'd0); pp[7] = w ? r[15] : r[7]; end
    alu_rmw = {r, pp};
  endfunction

  // P with the emulation-mode constraints applied (M = X = 1)
  function automatic logic [7:0] pfix(input logic [7:0] p_, input logic e_);
    pfix = e_ ? (p_ | 8'h30) : p_;
  endfunction

  // EA + 1 with the wrap of the running addressing mode
  function automatic logic [23:0] einc(input logic [23:0] a, input logic [1:0] wm);
    case (wm)
      W24:     einc = a + 24'd1;
      W16:     einc = {a[23:16], a[15:0] + 16'd1};
      default: einc = {a[23:8], a[7:0] + 8'd1};
    endcase
  endfunction

  logic branch_taken;
  always_comb begin
    case (IR[7:6])
      2'd0: branch_taken = (P[7] == IR[5]);
      2'd1: branch_taken = (P[6] == IR[5]);
      2'd2: branch_taken = (P[0] == IR[5]);
      default: branch_taken = (P[1] == IR[5]);
    endcase
    if (IR == 8'h80) branch_taken = 1'b1;
  end

  // ------------------------------------------------------------------ current micro-op (skips resolved)
  /* verilator lint_off UNUSED */
  logic [14:0] u0;          // the running micro-op (its skip condition was resolved a cycle earlier)
  logic [14:0] u1;          // the next micro-op: only its skip condition is used
  /* verilator lint_on UNUSED */
  logic [5:0]  uk;
  logic [4:0]  ua;
  logic        dl0;
  assign dl0 = (D[7:0] == 8'h00);

  function automatic logic skipf(input logic [3:0] s, input logic w16_, input logic dl0_, input logic xf_,
                                 input logic cx_, input logic bt, input logic e_);
    case (s)
      S_W8:  skipf = !w16_;
      S_DL0: skipf = dl0_;
      S_IDX: skipf = xf_ && !cx_;
      S_NT:  skipf = !bt;
      S_BPX: skipf = !(bt && e_ && cx_);
      S_EMU: skipf = e_;
      default: skipf = 1'b0;
    endcase
  endfunction

  // The skip condition of the next micro-op is resolved one cycle early (with the index / branch carry this cycle
  // produces), so the running micro-op is a plain table lookup. A skipped micro-op is never followed by another
  // skippable one, except after a branch not taken, which ends the instruction (step 15 is END in every program).
  always_comb begin
    u0 = uprog(IR, K, INTR, am, kd);
    u1 = uprog(IR, K + 4'd1, INTR, am, kd);
    uk = u0[5:0];
    ua = u0[14:10];
  end


  // ------------------------------------------------------------------ cycle
  logic [15:0] nC, nX, nY, nS, nD, nPC, nOPR, nDAT, nSP;
  logic [7:0]  nDBR, nPBR, nP, nIR, nBNK;
  logic        nE, nINTR, nCX;
  logic [2:0]  nIK;
  logic [23:0] nEA, nIAD;
  logic [1:0]  nEAW;
  logic [3:0]  nK;
  logic        fetch, nmi_take;

  logic [23:0] ab;
  logic        rw, vda, vpa, vpb, mlb;
  logic [7:0]  dout;



  logic [23:0] ea1, ea2;
  assign ea1 = einc(EA, EAW);
  assign ea2 = einc(ea1, EAW);

  logic [15:0] xmask;
  assign xmask = Xf ? 16'h00FF : 16'hFFFF;

  // shared adders: one for every effective address, one for PC, one for the stack pointer, one per index
  // register, one read-modify-write unit
  logic [23:0] ea_base, ea_sum;
  logic [15:0] ea_add, pc_bas, pc_add, pc_sum, sp_bas, sp_sum, s_pull, xs, ys;
  logic        pull;
  logic [4:0]  rmw_op;
  logic [15:0] rmw_v;
  logic        rmw_w;
  logic [23:0] rmw_r;
  always_comb begin
    ea_base = {DBR, DI, OPR[7:0]}; ea_add = 16'd0;
    case (ua)
      A_EADP:  begin ea_base = {8'h00, D}; ea_add = {8'h00, DI}; end
      A_EADPX: begin ea_base = EA; ea_add = X; end
      A_EADPY: begin ea_base = EA; ea_add = Y; end
      A_EASR:  begin ea_base = {8'h00, S}; ea_add = {8'h00, DI}; end
      A_EAABX: ea_add = X;
      A_EAABY: ea_add = Y;
      A_EALNG: ea_base = {DI, OPR};
      A_EALNX: begin ea_base = {DI, OPR}; ea_add = X; end
      A_EAPTR: ea_base = {DBR, DI, DAT[7:0]};
      A_EAPTY: begin ea_base = {DBR, DI, DAT[7:0]}; ea_add = Y; end
      A_EAPTL: ea_base = {DI, DAT};
      A_EAPLY: begin ea_base = {DI, DAT}; ea_add = Y; end
      A_EAAB0: ea_base = {8'h00, DI, OPR[7:0]};
      A_EAPBX: begin ea_base = {PBR, DI, OPR[7:0]}; ea_add = X; end
      default: ;
    endcase
    ea_sum = ea_base + {8'h00, ea_add};

    pc_bas = PC; pc_add = 16'd1;
    case (ua)
      A_BR:         pc_add = {{8{OPR[7]}}, OPR[7:0]};
      A_BRL, A_PER: pc_add = OPR;
      A_MV:         pc_add = 16'hFFFD;
      A_RTS, A_RTL: pc_bas = DAT;
      default: ;
    endcase
    if ((uk == U_PSHH || uk == U_PSHL) && (IR == 8'h20 || IR == 8'h22)) pc_add = 16'hFFFF;   // JSR / JSL push PC-1
    pc_sum = pc_bas + pc_add;

    // stack: "old" instructions stay in page 1 in emulation, "new" ones use the 16-bit S
    pull = (uk == U_PULL || uk == U_PULH || uk == U_PULB || uk == U_PULP);
    sp_bas = (Ef && !newstk) ? {8'h01, S[7:0]} : SP;
    sp_sum = sp_bas + (pull ? 16'h0001 : 16'hFFFF);
    s_pull = (Ef && !newstk) ? {8'h01, sp_sum[7:0]} : sp_sum;

    xs = X + ((IR == 8'h44 || IR == 8'hCA) ? 16'hFFFF : 16'h0001);   // MVP / DEX count down
    ys = Y + ((IR == 8'h44 || IR == 8'h88) ? 16'hFFFF : 16'h0001);   // MVP / DEY count down

    if (uk == U_MOD) begin rmw_op = op; rmw_v = DAT; rmw_w = w16; end
    else begin
      rmw_v = C; rmw_w = !Mf;
      case (IR)
        8'h1A:   rmw_op = O_INC;
        8'h3A:   rmw_op = O_DEC;
        8'h0A:   rmw_op = O_ASL;
        8'h2A:   rmw_op = O_ROL;
        8'h4A:   rmw_op = O_LSR;
        default: rmw_op = O_ROR;
      endcase
    end
    rmw_r = alu_rmw(rmw_op, rmw_v, rmw_w, C, P);
  end

  // push source
  logic [15:0] psrc;
  always_comb begin
    case (IR)
      8'h48: psrc = C;
      8'hDA: psrc = X;
      8'h5A: psrc = Y;
      8'h0B: psrc = D;
      8'hF4, 8'hD4, 8'h62: psrc = DAT;
      8'h20, 8'h22: psrc = pc_sum;   // PC - 1
      default: psrc = PC;   // JSR (a,x), BRK, COP, interrupts
    endcase
  end

  always_comb begin : cyc
    logic [25:0] ar;
    logic [15:0] t16, v16, src;
    logic [7:0]  t8;
    logic        e_dpw;
    logic        do_ex;

    nC = C; nX = X; nY = Y; nS = S; nD = D; nPC = PC; nDBR = DBR; nPBR = PBR; nP = P; nE = Ef;
    nIR = IR; nBNK = BNK; nOPR = OPR; nDAT = DAT; nSP = SP; nINTR = INTR; nIK = IK; nCX = CX;
    nEA = EA; nIAD = IAD; nEAW = EAW; nK = K + 4'd1;
    ab = LA; rw = 1'b1; vda = 1'b0; vpa = 1'b0; vpb = 1'b0; mlb = 1'b0; dout = 8'h00;
    fetch = 1'b0; nmi_take = 1'b0;
    ar = 26'd0; t16 = 16'd0; v16 = 16'd0; src = 16'd0; t8 = 8'd0; do_ex = 1'b0;
    e_dpw = Ef && dl0;

    case (uk)
      U_END: begin
        fetch = 1'b1;
        ab = {PBR, PC}; vda = 1'b1; vpa = 1'b1;
        nK = 4'd1; nSP = S; nCX = 1'b0;
        if (res_pend) begin
          nIR = 8'h00; nINTR = 1'b1; nIK = I_RES;
        end else if (abt_pend || nmi_pend || (!IRQ_n && !P[2])) begin
          nIR = 8'h00; nINTR = 1'b1;
          nIK = abt_pend ? I_ABT : nmi_pend ? I_NMI : I_IRQ;
          nmi_take = !abt_pend && nmi_pend;
          if (abt_pend) begin
            nC = aC; nX = aX; nY = aY; nS = aS; nSP = aS; nD = aD; nPC = aPC; nDBR = aDBR; nPBR = aPBR;
            nP = aP; nE = aE;
          end
        end else begin
          nIR = DI; nINTR = 1'b0;
          nPC = pc_sum;
        end
      end
      U_OP1, U_IMM1: begin
        ab = {PBR, PC}; vpa = 1'b1; nPC = pc_sum;
        nOPR[7:0] = DI; nDAT[7:0] = DI;
        if (uk == U_IMM1 && !w16) do_ex = 1'b1;
      end
      U_OP2, U_IMM2: begin
        ab = {PBR, PC}; vpa = 1'b1; nPC = pc_sum;
        nOPR[15:8] = DI; nDAT[15:8] = DI;
        if (uk == U_IMM2) do_ex = 1'b1;
      end
      U_OP3: begin
        ab = {PBR, PC}; vpa = 1'b1; nPC = pc_sum; nBNK = DI;
      end
      U_IOPC: ab = {PBR, PC};
      U_IO: ab = LA;
      U_IOX: ab = IAD;
      U_DRL: begin ab = EA;  vda = 1'b1; nDAT[7:0] = DI; if (!w16) do_ex = 1'b1; end
      U_DRH: begin ab = ea1; vda = 1'b1; nDAT[15:8] = DI; do_ex = 1'b1; end
      U_DWL, U_DWH: begin
        ab = (uk == U_DWL) ? EA : ea1; vda = 1'b1; rw = 1'b0;
        case (op)
          O_STA: src = C;
          O_STX: src = X;
          O_STY: src = Y;
          default: src = 16'd0;
        endcase
        dout = (uk == U_DWL) ? src[7:0] : src[15:8];
      end
      U_MRL: begin ab = EA;  vda = 1'b1; mlb = 1'b1; nDAT[7:0] = DI; end
      U_MRH: begin ab = ea1; vda = 1'b1; mlb = 1'b1; nDAT[15:8] = DI; end
      U_MOD: begin
        ab = LA; mlb = 1'b1;
        if (Ef) begin rw = 1'b0; dout = DAT[7:0]; end
        nDAT = rmw_r[23:8]; nP = rmw_r[7:0];
      end
      U_MWH: begin ab = ea1; vda = 1'b1; mlb = 1'b1; rw = 1'b0; dout = DAT[15:8]; end
      U_MWL: begin ab = EA;  vda = 1'b1; mlb = 1'b1; rw = 1'b0; dout = DAT[7:0]; end
      U_PRL: begin ab = EA;  vda = 1'b1; nDAT[7:0] = DI; end
      U_PRH: begin ab = ea1; vda = 1'b1; nDAT[15:8] = DI; end
      U_PRB: begin ab = ea2; vda = 1'b1; nBNK = DI; end
      U_PSHH, U_PSHL, U_PSHK, U_PSHB, U_PSHP: begin
        ab = {8'h00, sp_bas}; vda = 1'b1; rw = 1'b0;
        case (uk)
          U_PSHH: dout = psrc[15:8];
          U_PSHL: dout = psrc[7:0];
          U_PSHK: dout = PBR;
          U_PSHB: dout = DBR;
          default: dout = (INTR && IK != I_RES) ? (pfix(P, Ef) & ~(Ef ? 8'h10 : 8'h00)) : pfix(P, Ef);
        endcase
        if (INTR && IK == I_RES) begin rw = 1'b1; dout = 8'h00; end   // reset: the pushes are reads
        nSP = (Ef && !newstk) ? {8'h01, sp_sum[7:0]} : sp_sum;
        nS = Ef ? {8'h01, sp_sum[7:0]} : sp_sum;
      end
      U_PULL, U_PULH, U_PULB, U_PULP: begin
        ab = {8'h00, s_pull}; vda = 1'b1;
        nSP = s_pull;
        nS = Ef ? {8'h01, s_pull[7:0]} : s_pull;
        case (uk)
          U_PULL: nDAT[7:0] = DI;
          U_PULH: nDAT[15:8] = DI;
          U_PULB: nBNK = DI;
          default: nP = pfix(DI, Ef);
        endcase
        // stack loads execute on their last byte
        if ((uk == U_PULL && !w16) || uk == U_PULH) begin
          v16 = (uk == U_PULH) ? {DI, DAT[7:0]} : {8'h00, DI};
          case (IR)
            8'h68: begin
              nC = w16 ? v16 : {C[15:8], v16[7:0]};
              nP[1] = w16 ? (v16 == 16'd0) : (v16[7:0] == 8'd0); nP[7] = w16 ? v16[15] : v16[7];
            end
            8'hFA, 8'h7A: begin
              if (IR == 8'hFA) nX = v16; else nY = v16;
              nP[1] = (v16 == 16'd0); nP[7] = w16 ? v16[15] : v16[7];
            end
            8'h2B: begin nD = v16; nP[1] = (v16 == 16'd0); nP[7] = v16[15]; end
            8'hAB: begin nDBR = v16[7:0]; nP[1] = (v16[7:0] == 8'd0); nP[7] = v16[7]; end
            default: ;
          endcase
        end
        if (uk == U_PULP) begin
          if (nP[4]) begin nX[15:8] = 8'h00; nY[15:8] = 8'h00; end
        end
      end
      U_VECL, U_VECH: begin
        vda = 1'b1; vpb = 1'b1;
        if (INTR) begin
          case (IK)
            I_RES:   t8 = 8'hFC;
            I_ABT:   t8 = Ef ? 8'hF8 : 8'hE8;
            I_NMI:   t8 = Ef ? 8'hFA : 8'hEA;
            default: t8 = Ef ? 8'hFE : 8'hEE;
          endcase
        end else if (IR == 8'h02) t8 = Ef ? 8'hF4 : 8'hE4;
        else t8 = Ef ? 8'hFE : 8'hE6;
        ab = {16'h00FF, t8 | {7'd0, uk == U_VECH}};
        if (uk == U_VECL) nDAT[7:0] = DI;
      end
      U_MVR: begin ab = {OPR[15:8], X}; vda = 1'b1; nDAT[7:0] = DI; end
      U_MVW: begin ab = {OPR[7:0], Y}; vda = 1'b1; rw = 1'b0; dout = DAT[7:0]; end
      U_WAIT: begin
        ab = LA;
        nK = K;
        if (nmi_pend || !IRQ_n || abt_pend) nK = K + 4'd1;
      end
      U_STOP: begin ab = LA; nK = K; end
      default: ;
    endcase

    // execute a read-type data operation on its last operand byte
    if (do_ex) begin
      v16 = (uk == U_DRH || uk == U_IMM2) ? {DI, DAT[7:0]} : {8'h00, DI};
      ar = alu_rd(op, v16, w16, C, X, Y, P);
      case (ar[25:24])
        2'd1: nC = ar[23:8];
        2'd2: nX = ar[23:8];
        2'd3: nY = ar[23:8];
        default: ;
      endcase
      nP = ar[7:0];
    end

    // end-of-cycle actions
    case (ua)
      A_EADP: begin
        nEA = {8'h00, ea_sum[15:0]};
        // emulation, DL = 0: the direct page wraps within its page (not for [d], [d],y, PEI)
        nEAW = (e_dpw && !(am == AM_DPIL || am == AM_DPILY || IR == 8'hD4)) ? W8 : W16;
      end
      A_EADPX, A_EADPY: nEA = e_dpw ? {EA[23:8], ea_sum[7:0]} : {8'h00, ea_sum[15:0]};
      A_EASR: begin nEA = {8'h00, ea_sum[15:0]}; nEAW = W16; end
      A_EAABX, A_EAABY, A_EAPTY: begin
        nEA = ea_sum; nEAW = W24;
        nIAD = {ea_base[23:8], ea_sum[7:0]}; nCX = ea_sum[8] ^ ea_base[8] ^ ea_add[8];
      end
      A_EAABS, A_EALNG, A_EALNX, A_EAPTR, A_EAPTL, A_EAPLY: begin nEA = ea_sum; nEAW = W24; end
      A_EAAB0: begin nEA = ea_sum; nEAW = W16; end
      A_EAPBX: begin nEA = {PBR, ea_sum[15:0]}; nEAW = W16; end
      A_JMP:  nPC = {DI, OPR[7:0]};
      A_JML:  begin nPC = OPR; nPBR = DI; end
      A_JMPI: nPC = {DI, DAT[7:0]};
      A_JMLI: begin nPC = DAT; nPBR = DI; end
      A_JSR:  nPC = OPR;
      A_JSL:  begin nPC = OPR; nPBR = BNK; end
      A_RTS:  nPC = (IR == 8'h40) ? {DI, DAT[7:0]} : pc_sum;
      A_RTL:  begin nPC = pc_sum; nPBR = DI; end
      A_PBR:  nPBR = DI;
      A_BR: begin
        nCX = (pc_sum[15:8] != PC[15:8]);
        nPC = pc_sum;
      end
      A_BRL: nPC = pc_sum;
      A_PER: nDAT = pc_sum;
      A_PCI: nPC = pc_sum;
      A_VEC: begin
        nPC = {DI, DAT[7:0]}; nPBR = 8'h00;
        nP[2] = 1'b1; nP[3] = 1'b0;
        nINTR = 1'b0;
      end
      A_MV: begin
        nX = xs & xmask; nY = ys & xmask;
        nC = C - 16'd1;
        nDBR = OPR[7:0];
        if (C != 16'h0000) nPC = pc_sum;   // PC - 3: repeat
      end
      A_EXEC: begin
        case (IR)
          8'h18: nP[0] = 1'b0;
          8'h38: nP[0] = 1'b1;
          8'h58: nP[2] = 1'b0;
          8'h78: nP[2] = 1'b1;
          8'hB8: nP[6] = 1'b0;
          8'hD8: nP[3] = 1'b0;
          8'hF8: nP[3] = 1'b1;
          8'hC2: nP = pfix(P & ~OPR[7:0], Ef);
          8'hE2: begin nP = P | OPR[7:0]; if (OPR[4]) begin nX[15:8] = 8'h00; nY[15:8] = 8'h00; end end
          8'hFB: begin
            nE = P[0]; nP[0] = Ef;
            if (P[0]) begin nP[5:4] = 2'b11; nX[15:8] = 8'h00; nY[15:8] = 8'h00; nS[15:8] = 8'h01; end
          end
          8'hEB: begin
            nC = {C[7:0], C[15:8]};
            nP[1] = (C[15:8] == 8'd0); nP[7] = C[15];
          end
          8'h9A: nS = Ef ? {8'h01, X[7:0]} : X;
          8'h1B: nS = Ef ? {8'h01, C[7:0]} : C;
          8'h5B: begin nD = C; nP[1] = (C == 16'd0); nP[7] = C[15]; end
          8'h7B: begin nC = D; nP[1] = (D == 16'd0); nP[7] = D[15]; end
          8'h3B: begin nC = S; nP[1] = (S == 16'd0); nP[7] = S[15]; end
          8'hEA: ;
          8'hAA, 8'hA8, 8'hBA, 8'h9B, 8'hBB, 8'hE8, 8'hC8, 8'hCA, 8'h88: begin
            // results in an index register (X width)
            case (IR)
              8'hAA, 8'hA8: t16 = C;
              8'hBA:        t16 = S;
              8'h9B:        t16 = X;
              8'hBB:        t16 = Y;
              8'hE8, 8'hCA: t16 = xs;
              default:      t16 = ys;
            endcase
            t16 = t16 & xmask;
            if (IR == 8'hAA || IR == 8'hBA || IR == 8'hE8 || IR == 8'hCA || IR == 8'hBB) nX = t16; else nY = t16;
            nP[1] = (t16 == 16'd0); nP[7] = Xf ? t16[7] : t16[15];
          end
          8'h8A, 8'h98: begin
            t16 = (IR == 8'h8A) ? X : Y;
            if (Mf) begin nC[7:0] = t16[7:0]; nP[1] = (t16[7:0] == 8'd0); nP[7] = t16[7]; end
            else    begin nC = t16; nP[1] = (t16 == 16'd0); nP[7] = t16[15]; end
          end
          default: begin
            // accumulator read-modify-write: INC A, DEC A, ASL A, ROL A, LSR A, ROR A
            nC = Mf ? {C[15:8], rmw_r[15:8]} : rmw_r[23:8];
            nP = rmw_r[7:0];
          end
        endcase
      end
      default: ;
    endcase

    // next micro-op skipped?
    if (uk != U_END && uk != U_WAIT && uk != U_STOP && u1[5:0] != U_END &&
        skipf(u1[9:6], w16, dl0, Xf, nCX, branch_taken, Ef))
      nK = (u1[9:6] == S_NT) ? 4'd15 : K + 4'd2;
  end

  // pins: M / X / E as at the start of the instruction (the opcode fetch already shows the new values)
  assign A = ab; assign R_W_n = rw; assign VDA = vda; assign VPA = vpa; assign VP_n = !vpb; assign ML_n = !mlb;
  assign DO = dout;
  assign Sync = vda & vpa;
  assign E  = fetch ? Ef : sE;
  assign MF = fetch ? Mf : sM;
  assign XF = fetch ? Xf : sX;
  assign Wait_n = (uk != U_WAIT);
  assign NMI_ack = nmi_take & Enable & Rdy;

  always_ff @(posedge Clk or negedge Res_n) begin
    if (!Res_n) begin
      IR <= 8'h00; K <= 4'd0; INTR <= 1'b1; IK <= I_RES; res_pend <= 1'b1;
      Ef <= 1'b1; P <= 8'h34; D <= 16'h0000; DBR <= 8'h00; PBR <= 8'h00;
      S <= 16'h01FF; X <= 16'h0000; Y <= 16'h0000;
      nmi_pend <= 1'b0; nmi_d <= 1'b1; abt_pend <= 1'b0;
      sM <= 1'b1; sX <= 1'b1; sE <= 1'b1;
    end else if (Enable && Rdy) begin
      X <= nX; Y <= nY; S <= nS; D <= nD; DBR <= nDBR; PBR <= nPBR; P <= pfix(nP, nE);
      Ef <= nE; IR <= nIR; K <= nK; INTR <= nINTR; IK <= nIK;
      if (fetch) begin
        sM <= Mf; sX <= Xf; sE <= Ef;
        res_pend <= 1'b0;
        abt_pend <= 1'b0;
      end
      nmi_d <= NMI_n;
      if (nmi_take) nmi_pend <= 1'b0;
      else if (nmi_d && !NMI_n) nmi_pend <= 1'b1;
      if (!Abort_n && !fetch) abt_pend <= 1'b1;
    end
  end

  // registers without reset (they hold while Res_n is low)
  /* verilator lint_off SYNCASYNCNET */
  always_ff @(posedge Clk) begin
    if (Res_n && Enable && Rdy) begin
      C <= nC; PC <= nPC;
      EA <= nEA; IAD <= nIAD; EAW <= nEAW; OPR <= nOPR; DAT <= nDAT; BNK <= nBNK; SP <= nSP; CX <= nCX;
      LA <= ab;
      if (fetch) begin
        aC <= C; aX <= X; aY <= Y; aS <= S; aD <= D; aPC <= PC; aDBR <= DBR; aPBR <= PBR; aP <= P; aE <= Ef;
      end
    end
  end
  /* verilator lint_on SYNCASYNCNET */
endmodule

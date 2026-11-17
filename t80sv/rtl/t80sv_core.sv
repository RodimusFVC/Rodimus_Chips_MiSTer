//============================================================================
//  t80sv_core - Z80 / 8080 / 8085-subset CPU core, cycle-identical to T80 (MiSTer-devel T80 v350 / 351)
//
//  SystemVerilog translation of T80.vhd + T80_Reg.vhd. T80 (c) 2001-2002 Daniel Wallner; T80(b) MikeJ,
//  TobiFlex, Sean Riddle; T80(c) v350 / 351 (c) 2018 Sorgelig and contributors (MiSTer-devel lineage).
//  Phoenix core additions (runtime I8080 = 8080 mode, I8085 RIM / SIM / SOD) by Rodimus.
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

module t80sv_core #(
    parameter int MODE   = 0,          // 0 Z80, 1 fast Z80, 2 8080, 3 GB
    parameter int IOWAIT = 0,          // 0 single-cycle I/O, 1 standard I/O cycle
    parameter int Flag_C = 0,          // flag bit positions (GB: C 4, H 5, N 6, Z 7, S / P / X / Y 0)
    parameter int Flag_N = 1,
    parameter int Flag_P = 2,
    parameter int Flag_X = 3,
    parameter int Flag_H = 4,
    parameter int Flag_Y = 5,
    parameter int Flag_Z = 6,
    parameter int Flag_S = 7
) (
    input  logic        RESET_n,
    input  logic        CLK_n,
    input  logic        CEN,
    input  logic        WAIT_n,
    input  logic        INT_n,
    input  logic        NMI_n,
    input  logic        BUSRQ_n,
    output logic        M1_n,
    output logic        IORQ,
    output logic        NoRead,
    output logic        Write,
    output logic        RFSH_n,
    output logic        HALT_n,
    output logic        BUSAK_n,
    output logic [15:0] A,
    input  logic [7:0]  DInst,
    input  logic [7:0]  DI,
    output logic [7:0]  DO,
    output logic [2:0]  MC,
    output logic [2:0]  TS,
    output logic        IntCycle_n,
    output logic        IntE,
    output logic        Stop,
    input  logic        R800_mode,
    input  logic        out0,          // 0: OUT (C),0; 1: OUT (C),255
    output logic [211:0] REG,          // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    input  logic        DIRSet,        // load all registers from DIR
    input  logic [211:0] DIR,
    input  logic        I8080,         // MODE 0 build: 8080 mode while high
    input  logic        I8085,         // 8080 mode: opcode 20 = RIM (A <= RIM_D), 30 = SIM (SOD)
    input  logic [7:0]  RIM_D,
    output logic        SOD
);

localparam logic [2:0] aBC  = 3'b000;
localparam logic [2:0] aDE  = 3'b001;
localparam logic [2:0] aXY  = 3'b010;
localparam logic [2:0] aIOA = 3'b100;
localparam logic [2:0] aSP  = 3'b101;
localparam logic [2:0] aZI  = 3'b110;

localparam logic [1:0] MODE2 = MODE[1:0];
logic [1:0] mode;                      // MODE, or 2 (8080) while I8080 = 1 on a MODE 0 build
assign mode = (MODE == 0 && I8080) ? 2'd2 : MODE2;

// Registers
logic [7:0]  ACC, F, Ap, Fp, I, R;
logic [15:0] SP, PC;

logic [7:0]  RegDIH, RegDIL;
logic [15:0] RegBusA, RegBusB, RegBusC;
logic [2:0]  RegAddrA_r, RegAddrA, RegAddrB_r, RegAddrB, RegAddrC;
logic        RegWEH, RegWEL;
logic        Alternate;

// Help registers
logic [15:0] WZ;                       // MEMPTR
logic [7:0]  IR;
logic [1:0]  ISet;
logic [15:0] RegBusA_r;
logic [15:0] ID16;
logic [7:0]  Save_Mux;
logic [31:0] MULU_Prod32, MULU_tmp;
logic [15:0] MULU_Fakt1;
logic [15:0] TmpAddr2;
logic [127:0] DOR;

logic [2:0]  TState;
logic [2:0]  MCycle;
logic        IntE_FF1, IntE_FF2;
logic        Halt_FF;
logic        BusReq_s = 1'b0;
logic        BusAck = 1'b0;
logic        ClkEn;
logic        NMI_s;
logic        OldNMI_n;
logic [1:0]  IStatus;

logic [7:0]  DI_Reg;
logic        T_Res;
logic [1:0]  XY_State;
logic [2:0]  Pre_XY_F_M;
logic        NextIs_XY_Fetch;
logic        XY_Ind;
logic        No_BTR;
logic        BTR_r;
logic        Auto_Wait;
logic        Auto_Wait_t1;
logic        Auto_Wait_t2;
logic        IncDecZ;
logic        SOD_r;

// ALU
logic [7:0]  BusB, BusA, ALU_Q, F_Out;

// Registered microcode outputs
logic [4:0]  Read_To_Reg_r;
logic        Arith16_r, Z16_r;
logic [3:0]  ALU_Op_r;
logic        Save_ALU_r, PreserveC_r;
logic [2:0]  MCycles;
logic        I_RXDD;

// Microcode outputs
logic [2:0]  MCycles_d, TStates;
logic        IntCycle, NMICycle;
logic        Inc_PC, Inc_WZ;
logic [3:0]  IncDec_16;
logic [1:0]  Prefix;
logic        Read_To_Acc, Read_To_Reg;
logic [3:0]  Set_BusB_To, Set_BusA_To, ALU_Op;
logic        Save_ALU, Rot_Akku, PreserveC, Arith16;
logic [2:0]  Set_Addr_To;
logic        Jump, JumpE, JumpXY, Call, RstP, LDZ, LDW, LDSPHL, LDHLSP, ADDSPdd;
logic        IORQ_i;
logic [2:0]  Special_LD;
logic        ExchangeDH, ExchangeRp, ExchangeAF, ExchangeRS, ExchangeWH;
logic        I_DJNZ, I_CPL, I_CCF, I_SCF, I_RETN, I_BT, I_BC, I_BTR, I_RLD, I_RRD, I_INRC, I_MULUB, I_MULU;
logic [1:0]  SetWZ;
logic        SetDI, SetEI;
logic [1:0]  IMode;
logic        Halt, XYbit_undoc, No_PC;

assign REG = Alternate ? {IntE_FF2, IntE_FF1, IStatus, DOR[127:112], DOR[47:0], DOR[63:48], DOR[111:64], PC, SP, R, I, Fp, Ap, F, ACC}
                       : {IntE_FF2, IntE_FF1, IStatus, DOR, PC, SP, R, I, Fp, Ap, F, ACC};

t80sv_mcode #(.MODE(MODE), .Flag_C(Flag_C), .Flag_P(Flag_P), .Flag_Z(Flag_Z), .Flag_S(Flag_S)) mcode (
    .mode(mode), .IR(IR), .ISet(ISet), .MCycle(MCycle), .F(F), .NMICycle(NMICycle), .IntCycle(IntCycle),
    .XY_State(XY_State), .R800_mode(R800_mode), .Rot_Akku(Rot_Akku), .LDHLSP(LDHLSP), .ADDSPdd(ADDSPdd),
    .I_MULUB(I_MULUB), .I_MULU(I_MULU), .MCycles(MCycles_d), .TStates(TStates), .Prefix(Prefix), .Inc_PC(Inc_PC),
    .Inc_WZ(Inc_WZ), .IncDec_16(IncDec_16), .Read_To_Reg(Read_To_Reg), .Read_To_Acc(Read_To_Acc),
    .Set_BusA_To(Set_BusA_To), .Set_BusB_To(Set_BusB_To), .ALU_Op(ALU_Op), .Save_ALU(Save_ALU),
    .PreserveC(PreserveC), .Arith16(Arith16), .Set_Addr_To(Set_Addr_To), .IORQ(IORQ_i), .Jump(Jump),
    .JumpE(JumpE), .JumpXY(JumpXY), .Call(Call), .RstP(RstP), .LDZ(LDZ), .LDW(LDW), .LDSPHL(LDSPHL),
    .Special_LD(Special_LD), .ExchangeDH(ExchangeDH), .ExchangeRp(ExchangeRp), .ExchangeAF(ExchangeAF),
    .ExchangeRS(ExchangeRS), .ExchangeWH(ExchangeWH), .I_DJNZ(I_DJNZ), .I_CPL(I_CPL), .I_CCF(I_CCF),
    .I_SCF(I_SCF), .I_RETN(I_RETN), .I_BT(I_BT), .I_BC(I_BC), .I_BTR(I_BTR), .I_RLD(I_RLD), .I_RRD(I_RRD),
    .I_INRC(I_INRC), .SetWZ(SetWZ), .SetDI(SetDI), .SetEI(SetEI), .IMode(IMode), .Halt(Halt),
    .NoRead(NoRead), .Write(Write), .No_PC(No_PC), .XYbit_undoc(XYbit_undoc)
);

t80sv_alu #(.Flag_C(Flag_C), .Flag_N(Flag_N), .Flag_P(Flag_P), .Flag_X(Flag_X), .Flag_H(Flag_H), .Flag_Y(Flag_Y),
            .Flag_Z(Flag_Z), .Flag_S(Flag_S)) alu (
    .mode(mode), .Arith16(Arith16_r), .Z16(Z16_r), .WZ13(WZ[13]), .WZ11(WZ[11]), .XY_State(XY_State),
    .ALU_Op(ALU_Op_r), .Rot_Akku(Rot_Akku), .IR(IR[5:0]), .ISet(ISet), .BusA(BusA), .BusB(BusB), .F_In(F), .Q(ALU_Q), .F_Out(F_Out)
);

// asynchronous reset as posedge of the inverted input: also takes effect when RESET_n is low from time 0
logic rst;
assign rst = ~RESET_n;

assign ClkEn = CEN & ~BusAck;

assign T_Res = (TState == TStates);

assign NextIs_XY_Fetch = XY_State != 2'b00 && !XY_Ind &&
                         (Set_Addr_To == aXY || (MCycle == 3'b001 && IR == 8'hCB) || (MCycle == 3'b001 && IR == 8'h36));

assign Save_Mux = ExchangeRp ? BusB : (!Save_ALU_r ? DI_Reg : ALU_Q);

//----------------------------------------------------------------------------
// Q (Zilog Z80): SCF / CCF take flag bits 5 and 3 from (Q xor F) or A, where Q = F if the previous
// instruction changed the flags and Q = 0 if it did not (POP AF and EX AF,AF' do not count; a prefix is
// an instruction of its own). One bit is enough: QF = "the previous instruction wrote F", so Q xor F is 0
// when QF = 1 and F when QF = 0. Fw collects the flag writes of the instruction in progress. An
// instruction's last flag writes happen in T1 / T2 of the next opcode fetch (the ALU result of the last
// M-cycle, and the block-instruction P/V, X, Y updates, while IR still holds the old opcode), so Fw passes to
// QF at T3 of the opcode fetch, and SCF / CCF read QF at T4.
// fw_now lists every write to F in the always_ff below except POP AF (Read_To_Reg_r 11011), EX AF,AF'
// and DIRSet.
//----------------------------------------------------------------------------
logic QF, Fw, fw_now, fw_late;
logic       BlkRep;                   // MCycle 4 of a repeating LDIR / CPIR / INIR / OTIR (and the D forms)
logic [3:0] BTR_B;                    // INIR / OTIR family: B after the decrement (BusA at the P/V update)
assign BlkRep = ISet == 2'b10 && IR[7:4] == 4'hB && !IR[2] && MCycle == 3'b100;
assign fw_late = !(MCycle == 3'b001 && !TState[2]);            // the "MCycle > 1, or MCycle 1 TState > 3" branch
assign fw_now  = (LDHLSP && MCycle == 3'b011 && TState == 3'd1) ||
                 (ADDSPdd && TState == 3'd1) ||
                 (fw_late && T_Res && (I_CPL || I_CCF || I_SCF)) ||
                 (fw_late && ((TState == 3'd2 && I_BTR && IR[0]) || (TState == 3'd1 && I_BTR && !IR[0]))) ||
                 (TState == 3'd3 && Special_LD[2] && !Special_LD[1]) ||
                 ((!I_DJNZ && Save_ALU_r && ALU_Op_r[3:1] != 3'b101) || ALU_Op_r == 4'b1001) ||   // not SET / RES: F is written back unchanged
                 (T_Res && I_INRC) ||
                 I_BT || I_BC ||
                 (BlkRep && T_Res);

always_ff @(posedge CLK_n or posedge rst) begin
    if (rst) begin
        QF <= 1'b0;
        Fw <= 1'b0;
    end else if (ClkEn && !DIRSet) begin
        if (MCycle == 3'b001 && TState == 3'd3) begin
            QF <= Fw;
            Fw <= fw_now;
        end else if (fw_now)
            Fw <= 1'b1;
    end
end

// process-variable equivalents; only some bits of each are used
/* verilator lint_off UNUSED */
logic [15:0] DI_sext;
logic [8:0]  ioq_sum, ioq_par;
logic [7:0]  bc_n;
assign DI_sext = {{8{DI_Reg[7]}}, DI_Reg};
assign ioq_sum = {1'b0, DI_Reg} + {1'b0, ID16[7:0]};             // INI / OUTI etc. flag source
assign ioq_par = (ioq_sum & 9'b000000111) ^ {1'b0, BusA};
assign bc_n    = ALU_Q - {7'd0, F_Out[Flag_H]};
logic [8:0]  temp_c;
logic [4:0]  temp_h;
assign temp_c  = {1'b0, SP[7:0]} + {1'b0, Save_Mux};             // LD HL,SP+e / ADD SP,e (GB) flags
assign temp_h  = {1'b0, SP[3:0]} + {1'b0, Save_Mux[3:0]};
/* verilator lint_on UNUSED */

always_ff @(posedge CLK_n or posedge rst) begin
    if (rst) begin
        PC <= 16'h0000;
        A <= 16'h0000;
        WZ <= 16'h0000;
        IR <= 8'h00;
        ISet <= 2'b00;
        XY_State <= 2'b00;
        IStatus <= 2'b00;
        MCycles <= 3'b000;
        DO <= 8'h00;
        ACC <= (MODE == 3) ? 8'h00 : 8'hFF;
        F <= (MODE == 3) ? 8'hF0 : 8'hFF;
        Ap <= 8'hFF;
        Fp <= 8'hFF;
        I <= 8'h00;
        R <= 8'h00;
        SP <= 16'hFFFF;
        Alternate <= 1'b0;
        Read_To_Reg_r <= 5'b00000;
        Arith16_r <= 1'b0;
        BTR_r <= 1'b0;
        Z16_r <= 1'b0;
        ALU_Op_r <= 4'b0000;
        Save_ALU_r <= 1'b0;
        PreserveC_r <= 1'b0;
        XY_Ind <= 1'b0;
        I_RXDD <= 1'b0;
        SOD_r <= 1'b0;
        BTR_B <= 4'h0;
    end else if (DIRSet) begin
        ACC <= DIR[7:0];
        F <= DIR[15:8];
        Ap <= DIR[23:16];
        Fp <= DIR[31:24];
        I <= DIR[39:32];
        R <= DIR[47:40];
        SP <= DIR[63:48];
        PC <= DIR[79:64];
        A <= DIR[79:64];
        IStatus <= DIR[209:208];
    end else if (ClkEn) begin
        ALU_Op_r <= 4'b0000;
        Save_ALU_r <= 1'b0;
        Read_To_Reg_r <= 5'b00000;

        MCycles <= MCycles_d;

        if (LDHLSP && MCycle == 3'b011 && TState == 3'd1) begin
            F[Flag_Z] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_H] <= temp_h[4];
            F[Flag_C] <= temp_c[8];
        end

        if (ADDSPdd && TState == 3'd1) begin
            F[Flag_Z] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_H] <= temp_h[4];
            F[Flag_C] <= temp_c[8];
        end

        if (mode == 2'd3)
            IStatus <= 2'b10;
        else if (IMode != 2'b11)
            IStatus <= IMode;

        Arith16_r <= Arith16;
        PreserveC_r <= PreserveC;
        Z16_r <= (ISet == 2'b10 && !ALU_Op[2] && ALU_Op[0] && MCycle == 3'b011);

        if (MCycle == 3'b001 && !TState[2]) begin
            // MCycle 1, TState 1..3
            if (TState == 3'd2 && WAIT_n) begin
                if (mode < 2) begin
                    A[7:0] <= R;
                    A[15:8] <= I;
                    R[6:0] <= R[6:0] + 7'd1;
                end

                if (!Jump && !Call && !NMICycle && !IntCycle && !(Halt_FF || Halt))
                    PC <= PC + 16'd1;

                if (IntCycle && IStatus == 2'b01)
                    IR <= 8'hFF;
                else if (Halt_FF || (IntCycle && IStatus == 2'b10) || NMICycle)
                    IR <= 8'h00;
                else
                    IR <= DInst;

                if (mode <= 1 && IntCycle && IStatus == 2'b10)
                    WZ[7:0] <= DInst;          // IM 2 vector low byte

                ISet <= 2'b00;
                if (Prefix != 2'b00) begin
                    if (Prefix == 2'b11) begin
                        if (IR[5])
                            XY_State <= 2'b10;
                        else
                            XY_State <= 2'b01;
                    end else begin
                        if (Prefix == 2'b10) begin
                            XY_State <= 2'b00;
                            XY_Ind <= 1'b0;
                        end
                        ISet <= Prefix;
                    end
                end else begin
                    XY_State <= 2'b00;
                    XY_Ind <= 1'b0;
                end
            end
        end else begin
            // MCycle > 1, or MCycle 1 TState > 3
            if (MCycle == 3'b110) begin
                XY_Ind <= 1'b1;
                if (Prefix == 2'b01)
                    ISet <= 2'b01;
            end

            if (T_Res) begin
                BTR_r <= (I_BT | I_BC | I_BTR) & ~No_BTR;
                if (Jump) begin
                    A[15:8] <= DI_Reg;
                    A[7:0] <= WZ[7:0];
                    PC[15:8] <= DI_Reg;
                    PC[7:0] <= WZ[7:0];
                end else if (JumpXY) begin
                    A <= RegBusC;
                    PC <= RegBusC;
                end else if (Call || RstP) begin
                    A <= WZ;
                    PC <= WZ;
                end else if (MCycle == MCycles && NMICycle) begin
                    A <= 16'h0066;
                    PC <= 16'h0066;
                end else if (((mode != 2'd3 && MCycle == 3'b011) || (mode == 2'd3 && MCycle == 3'b100)) && IntCycle && IStatus == 2'b10) begin
                    A[15:8] <= I;
                    A[7:0] <= WZ[7:0];
                    PC[15:8] <= I;
                    PC[7:0] <= WZ[7:0];
                end else begin
                    case (Set_Addr_To)
                    aXY: begin
                        if (XY_State == 2'b00) begin
                            A <= RegBusC;
                            if (SetWZ == 2'b01)
                                WZ <= RegBusC + 16'd1;   // RLD / RRD
                        end
                        else if (NextIs_XY_Fetch)
                            A <= PC;
                        else
                            A <= WZ;
                    end
                    aIOA: begin
                        if (mode == 2'd3)
                            A[15:8] <= 8'hFF;      // GB: memory-mapped I/O
                        else if (mode == 2'd2)
                            A[15:8] <= DI_Reg;     // 8080 duplicates the port number
                        else
                            A[15:8] <= ACC;
                        A[7:0] <= DI_Reg;
                        if (SetWZ == 2'b10)
                            WZ <= {ACC, DI_Reg + 8'd1};  // OUT (n),A
                        else
                            WZ <= {ACC, DI_Reg} + 16'd1;
                    end
                    aSP: A <= SP;
                    aBC: begin
                        if (mode == 2'd3 && IORQ_i) begin
                            A[15:8] <= 8'hFF;      // GB: memory-mapped I/O
                            A[7:0] <= RegBusC[7:0];
                        end else begin
                            A <= RegBusC;
                            if (SetWZ == 2'b01)
                                WZ <= RegBusC + 16'd1;
                            if (SetWZ == 2'b10) begin
                                WZ[7:0] <= RegBusC[7:0] + 8'd1;
                                WZ[15:8] <= ACC;
                            end
                        end
                    end
                    aDE: begin
                        A <= RegBusC;
                        if (SetWZ == 2'b01)
                            WZ <= RegBusC + 16'd1;       // LD A,(DE)
                        if (SetWZ == 2'b10) begin
                            WZ[7:0] <= RegBusC[7:0] + 8'd1;
                            WZ[15:8] <= ACC;
                        end
                    end
                    aZI: begin
                        if (Inc_WZ) begin
                            A <= WZ + 16'd1;
                            WZ <= WZ + 16'd1;            // LD (nn),rr / LD rr,(nn): MEMPTR = nn + 1
                        end else begin
                            A[15:8] <= DI_Reg;
                            A[7:0] <= WZ[7:0];
                            if (SetWZ == 2'b01)
                                WZ <= {DI_Reg, WZ[7:0]} + 16'd1;  // LD A,(nn)
                            if (SetWZ == 2'b10) begin
                                WZ[7:0] <= WZ[7:0] + 8'd1;
                                WZ[15:8] <= ACC;
                            end
                        end
                    end
                    default: begin
                        if (ISet == 2'b10 && IR[7:4] == 4'hB && IR[2:1] == 2'b01 && MCycle == 3'b011 && !No_BTR)
                            A <= RegBusA_r;    // INIR, INDR, OTIR, OTDR
                        else if (!No_PC || No_BTR || (I_DJNZ && IncDecZ) || mode > 1)
                            A <= PC;
                    end
                    endcase
                end

                if (SetWZ == 2'b11)
                    WZ <= ID16;

                // CPI / CPD (and CPIR / CPDR when they stop): MEMPTR + 1 / - 1, at the end of the (HL) read.
                // A repeating CPIR / CPDR then sets MEMPTR = PC + 1 in MCycle 3 (I_BC, below).
                if (ISet == 2'b10 && IR[7:5] == 3'b101 && IR[2:0] == 3'b001 && MCycle == 3'b010)
                    WZ <= IR[3] ? WZ - 16'd1 : WZ + 16'd1;

                // A repeating block instruction (MCycle 4 only runs when it repeats; PC is back at the
                // instruction): flag bits 5 / 3 = PC bits 13 / 11. INIR / INDR / OTIR / OTDR also change H and
                // P/V by the carry and B, and set MEMPTR = PC + 1 (LDIR / CPIR set it in MCycle 3, below).
                // N = bit 7 of the byte transferred, C = H = carry of the INI / OUTI sum (set in MCycle 3).
                if (BlkRep && !mode[1]) begin
                    F[Flag_Y] <= PC[13];
                    F[Flag_X] <= PC[11];
                    if (IR[1]) begin
                        WZ <= PC + 16'd1;
                        if (F[Flag_C]) begin
                            if (F[Flag_N]) begin
                                F[Flag_P] <= F[Flag_P] ^ (^(BTR_B[2:0] - 3'd1));
                                F[Flag_H] <= BTR_B[3:0] == 4'h0;
                            end else begin
                                F[Flag_P] <= F[Flag_P] ^ (^(BTR_B[2:0] + 3'd1));
                                F[Flag_H] <= BTR_B[3:0] == 4'hF;
                            end
                        end else
                            F[Flag_P] <= F[Flag_P] ^ (^BTR_B[2:0]);
                    end
                end

                Save_ALU_r <= Save_ALU;
                ALU_Op_r <= ALU_Op;

                if (mode == 2'd3) begin
                    if (I_CPL) begin
                        ACC <= ~ACC;
                        F[Flag_H] <= 1'b1;
                        F[Flag_N] <= 1'b1;
                    end
                    if (I_CCF) begin
                        F[Flag_C] <= ~F[Flag_C];
                        F[Flag_H] <= 1'b0;
                        F[Flag_N] <= 1'b0;
                    end
                    if (I_SCF) begin
                        F[Flag_C] <= 1'b1;
                        F[Flag_H] <= 1'b0;
                        F[Flag_N] <= 1'b0;
                    end
                end else begin
                    if (I_CPL) begin
                        ACC <= ~ACC;
                        F[Flag_Y] <= ~ACC[5];
                        F[Flag_H] <= 1'b1;
                        F[Flag_X] <= ~ACC[3];
                        F[Flag_N] <= 1'b1;
                    end
                    if (I_CCF) begin
                        F[Flag_C] <= ~F[Flag_C];
                        F[Flag_Y] <= ACC[5] | (!mode[1] && !QF && F[Flag_Y]);   // (Q xor F) or A
                        F[Flag_H] <= F[Flag_C];
                        F[Flag_X] <= ACC[3] | (!mode[1] && !QF && F[Flag_X]);
                        F[Flag_N] <= 1'b0;
                    end
                    if (I_SCF) begin
                        F[Flag_C] <= 1'b1;
                        F[Flag_Y] <= ACC[5] | (!mode[1] && !QF && F[Flag_Y]);
                        F[Flag_H] <= 1'b0;
                        F[Flag_X] <= ACC[3] | (!mode[1] && !QF && F[Flag_X]);
                        F[Flag_N] <= 1'b0;
                    end
                end
            end

            if ((TState == 3'd2 && I_BTR && IR[0]) || (TState == 3'd1 && I_BTR && !IR[0])) begin
                F[Flag_N] <= DI_Reg[7];
                F[Flag_C] <= ioq_sum[8];
                F[Flag_H] <= ioq_sum[8];
                F[Flag_P] <= ~^ioq_par[7:0];
                BTR_B <= BusA[3:0];
            end

            if (TState == 3'd2 && WAIT_n) begin
                if (ISet == 2'b01 && MCycle == 3'b111)
                    IR <= DInst;
                if (JumpE) begin
                    PC <= PC + DI_sext;
                    WZ <= PC + DI_sext;
                end else if (Inc_PC) begin
                    PC <= PC + 16'd1;
                end
                if (BTR_r)
                    PC <= PC - 16'd2;
                if (RstP) begin
                    WZ <= 16'h0000;
                    WZ[5:3] <= IR[5:3];
                end
            end
            if (TState == 3'd3 && MCycle == 3'b110)
                WZ <= RegBusC + DI_sext;

            if (MCycle == 3'b011 && TState == 3'd4 && !No_BTR) begin
                if (I_BT || I_BC)
                    WZ <= PC - 16'd1;
            end

            if ((TState == 3'd2 && WAIT_n) || (TState == 3'd4 && MCycle == 3'b001)) begin
                if (IncDec_16[2:0] == 3'b111) begin
                    if (IncDec_16[3])
                        SP <= SP - 16'd1;
                    else
                        SP <= SP + 16'd1;
                end
            end

            if (ADDSPdd && TState == 3'd2) begin
                WZ <= SP;
                SP <= SP + {{8{Save_Mux[7]}}, Save_Mux};
            end

            if (LDSPHL)
                SP <= RegBusC;
            if (ExchangeAF) begin
                Ap <= ACC;
                ACC <= Ap;
                Fp <= F;
                F <= Fp;
            end
            if (ExchangeRS)
                Alternate <= ~Alternate;
        end

        if (TState == 3'd3) begin
            if (LDZ)
                WZ[7:0] <= DI_Reg;
            if (LDW)
                WZ[15:8] <= DI_Reg;

            if (Special_LD[2]) begin
                case (Special_LD[1:0])
                2'b00: begin
                    ACC <= I;
                    F[Flag_P] <= IntE_FF2;
                    F[Flag_S] <= I[7];
                    F[Flag_Z] <= (I == 8'h00);
                    F[Flag_Y] <= I[5];
                    F[Flag_H] <= 1'b0;
                    F[Flag_X] <= I[3];
                    F[Flag_N] <= 1'b0;
                end
                2'b01: begin
                    ACC <= R;
                    F[Flag_P] <= IntE_FF2;
                    F[Flag_S] <= R[7];
                    F[Flag_Z] <= (R == 8'h00);
                    F[Flag_Y] <= R[5];
                    F[Flag_H] <= 1'b0;
                    F[Flag_X] <= R[3];
                    F[Flag_N] <= 1'b0;
                end
                2'b10: I <= ACC;
                default: R <= ACC;
                endcase
            end
        end

        if ((!I_DJNZ && Save_ALU_r) || ALU_Op_r == 4'b1001) begin
            if (mode == 2'd3) begin
                F[6] <= F_Out[6];
                F[5] <= F_Out[5];
                F[7] <= F_Out[7];
                if (!PreserveC_r)
                    F[4] <= F_Out[4];
            end else begin
                F[7:1] <= F_Out[7:1];
                if (!PreserveC_r)
                    F[Flag_C] <= F_Out[0];
            end
        end
        if (T_Res && I_INRC) begin
            F[Flag_H] <= 1'b0;
            F[Flag_N] <= 1'b0;
            F[Flag_X] <= DI_Reg[3];
            F[Flag_Y] <= DI_Reg[5];
            F[Flag_Z] <= (DI_Reg == 8'h00);
            F[Flag_S] <= DI_Reg[7];
            F[Flag_P] <= ~^DI_Reg;
        end

        if (TState == 3'd1 && !Auto_Wait_t1) begin
            I_RXDD <= I_RLD | I_RRD;   // keep DO from M3 for RLD / RRD
            if (!I_RXDD)
                DO <= BusB;
            if (I_RLD) begin
                DO[3:0] <= BusA[3:0];
                DO[7:4] <= BusB[3:0];
            end
            if (I_RRD) begin
                DO[3:0] <= BusB[7:4];
                DO[7:4] <= BusA[3:0];
            end
        end

        if (T_Res) begin
            Read_To_Reg_r[3:0] <= Set_BusA_To;
            Read_To_Reg_r[4] <= Read_To_Reg;
            if (Read_To_Acc) begin
                Read_To_Reg_r[3:0] <= 4'b0111;
                Read_To_Reg_r[4] <= 1'b1;
            end
        end

        if (TState == 3'd1 && I_BT) begin
            F[Flag_X] <= ALU_Q[3];
            F[Flag_Y] <= ALU_Q[1];
            F[Flag_H] <= 1'b0;
            F[Flag_N] <= 1'b0;
        end
        if (TState == 3'd1 && I_BC) begin
            F[Flag_X] <= bc_n[3];
            F[Flag_Y] <= bc_n[1];
        end
        if (I_BC || I_BT)
            F[Flag_P] <= IncDecZ;

        if ((TState == 3'd1 && !Save_ALU_r && !Auto_Wait_t1) || (Save_ALU_r && ALU_Op_r != 4'b0111)) begin
            case (Read_To_Reg_r)
            5'b10111: ACC <= Save_Mux;
            5'b10110: DO <= Save_Mux;
            5'b11000: SP[7:0] <= Save_Mux;
            5'b11001: SP[15:8] <= Save_Mux;
            5'b11011: begin
                if (mode == 2'd3) begin
                    F[7:4] <= Save_Mux[7:4];
                    F[3:0] <= 4'b0000;     // GB: F bits 3..0 always read 0
                end else begin
                    F <= Save_Mux;
                end
            end
            default: ;
            endcase
            if (XYbit_undoc)
                DO <= ALU_Q;
        end

        // 8085 RIM: opcode 20 loads A last in M1 (after any write-back of the previous instruction)
        if (I8085 && mode == 2'd2 && MCycle == 3'b001 && TState == 3'd4 && ISet == 2'b00 && IR == 8'h20)
            ACC <= RIM_D;
        // 8085 SIM: opcode 30, A[6] (SOE) latches A[7] into SOD; the interrupt-mask half is not modelled
        if (I8085 && mode == 2'd2 && MCycle == 3'b001 && TState == 3'd4 && ISet == 2'b00 && IR == 8'h30 && ACC[6])
            SOD_r <= ACC[7];
    end
end

//----------------------------------------------------------------------------
// R800 multiply (MULUB / MULUW)
//----------------------------------------------------------------------------
logic [19:0] MULU_hi;
assign MULU_hi  = (MULU_Fakt1 * MULU_Prod32[3:0]) + {4'd0, MULU_Prod32[31:16]};
assign MULU_tmp = {MULU_hi, MULU_Prod32[15:4]};

always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        if (T_Res) begin
            if (I_MULUB) begin
                MULU_Prod32[7:0] <= ACC;
                MULU_Prod32[15:8] <= 8'h00;     // VHDL "--------"
                MULU_Prod32[31:16] <= 16'h0000;
                MULU_Fakt1[7:0] <= 8'h00;
                if (Set_BusB_To[0])
                    MULU_Fakt1[15:8] <= RegBusB[7:0];
                else
                    MULU_Fakt1[15:8] <= RegBusB[15:8];
            end else begin
                MULU_Prod32[15:0] <= RegBusA;
                MULU_Prod32[31:16] <= 16'h0000;
                MULU_Fakt1 <= RegBusB;
            end
        end else begin
            MULU_Prod32 <= MULU_tmp;
        end
    end
end

//----------------------------------------------------------------------------
// BC('), DE('), HL('), IX and IY
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        // Bus A / write
        RegAddrA_r <= {Alternate, Set_BusA_To[2:1]};
        if (!XY_Ind && XY_State != 2'b00 && Set_BusA_To[2:1] == 2'b10)
            RegAddrA_r <= {XY_State[1], 2'b11};

        // Bus B
        RegAddrB_r <= {Alternate, Set_BusB_To[2:1]};
        if (!XY_Ind && XY_State != 2'b00 && Set_BusB_To[2:1] == 2'b10)
            RegAddrB_r <= {XY_State[1], 2'b11};

        // Address from register
        RegAddrC <= {Alternate, Set_Addr_To[1:0]};
        // JP (HL), LD SP,HL
        if (JumpXY || LDSPHL)
            RegAddrC <= {Alternate, 2'b10};
        if (((JumpXY || LDSPHL) && XY_State != 2'b00) || MCycle == 3'b110)
            RegAddrC <= {XY_State[1], 2'b11};

        if (I_DJNZ && Save_ALU_r && mode < 2)
            IncDecZ <= F_Out[Flag_Z];
        if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001)) && IncDec_16[2:0] == 3'b100)
            IncDecZ <= (ID16 != 16'h0000);

        RegBusA_r <= RegBusA;
    end
end

always_comb begin
    // 16-bit increment / decrement. With DD / FD the prefix only replaces HL: INC / DEC BC, DE keep their pair.
    if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001 && IncDec_16[2])) &&
        (XY_State == 2'b00 || !IncDec_16[1]))
        RegAddrA = {Alternate, IncDec_16[1:0]};
    else if ((TState == 3'd2 || (TState == 3'd3 && MCycle == 3'b001 && IncDec_16[2])) && IncDec_16[1:0] == 2'b10)
        RegAddrA = {XY_State[1], 2'b11};
    else if (ExchangeDH && TState == 3'd3)
        RegAddrA = {Alternate, 2'b10};                     // EX DE,HL
    else if ((ExchangeDH || I_MULU) && TState == 3'd4)
        RegAddrA = {Alternate, 2'b01};
    else if (ExchangeWH && XY_State == 2'b00 && TState == 3'd4)
        RegAddrA = {Alternate, 2'b10};                     // EX (SP),HL: HL (IX, IY) <= WZ
    else if (ExchangeWH && TState == 3'd4)
        RegAddrA = {XY_State[1], 2'b11};
    else if (LDHLSP && TState == 3'd4)
        RegAddrA = 3'b010;
    else
        RegAddrA = RegAddrA_r;
end

assign RegAddrB = (ExchangeDH && TState == 3'd3) ? {Alternate, 2'b01} : RegAddrB_r;

assign ID16 = IncDec_16[3] ? RegBusA - 16'd1 : RegBusA + 16'd1;

always_comb begin
    RegWEH = 1'b0;
    RegWEL = 1'b0;
    if ((TState == 3'd1 && !Save_ALU_r && !Auto_Wait_t1) || (Save_ALU_r && ALU_Op_r != 4'b0111)) begin
        case (Read_To_Reg_r)
        5'b10000, 5'b10001, 5'b10010, 5'b10011, 5'b10100, 5'b10101: begin
            RegWEH = ~Read_To_Reg_r[0];
            RegWEL = Read_To_Reg_r[0];
        end
        default: ;
        endcase
    end
    if (I_MULU && (T_Res || TState == 3'd4)) begin       // TState 4: DE write
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (ExchangeDH && (TState == 3'd3 || TState == 3'd4)) begin
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (((LDHLSP && MCycle == 3'b010) || ExchangeWH) && TState == 3'd4) begin
        RegWEH = 1'b1;
        RegWEL = 1'b1;
    end
    if (IncDec_16[2] && ((TState == 3'd2 && WAIT_n && MCycle != 3'b001) || (TState == 3'd3 && MCycle == 3'b001))) begin
        case (IncDec_16[1:0])
        2'b00, 2'b01, 2'b10: begin
            RegWEH = 1'b1;
            RegWEL = 1'b1;
        end
        default: ;
        endcase
    end
end

always_comb begin
    RegDIH = Save_Mux;
    RegDIL = Save_Mux;
    if (I_MULU) begin
        if (T_Res) begin
            RegDIH = MULU_Prod32[31:24];
            RegDIL = MULU_Prod32[23:16];
        end else begin
            RegDIH = MULU_tmp[15:8];               // TState 4: DE write
            RegDIL = MULU_tmp[7:0];
        end
    end
    if (LDHLSP && MCycle == 3'b010 && TState == 3'd4) begin
        RegDIH = TmpAddr2[15:8];
        RegDIL = TmpAddr2[7:0];
    end
    if (ExchangeDH && TState == 3'd3) begin
        RegDIH = RegBusB[15:8];
        RegDIL = RegBusB[7:0];
    end
    if (ExchangeDH && TState == 3'd4) begin
        RegDIH = RegBusA_r[15:8];
        RegDIL = RegBusA_r[7:0];
    end
    if (ExchangeWH && TState == 3'd4) begin
        RegDIH = WZ[15:8];
        RegDIL = WZ[7:0];
    end
    if (IncDec_16[2] && ((TState == 3'd2 && MCycle != 3'b001) || (TState == 3'd3 && MCycle == 3'b001))) begin
        RegDIH = ID16[15:8];
        RegDIL = ID16[7:0];
    end
end

assign TmpAddr2 = SP + {{8{Save_Mux[7]}}, Save_Mux};

// register file (T80_Reg): 8 x 16 bits, write port A, asynchronous read ports A, B, C
logic [7:0] RegsH [0:7];
logic [7:0] RegsL [0:7];

always_ff @(posedge CLK_n) begin
    if (DIRSet) begin
        RegsL[0] <= DIR[87:80];   RegsH[0] <= DIR[95:88];
        RegsL[1] <= DIR[103:96];  RegsH[1] <= DIR[111:104];
        RegsL[2] <= DIR[119:112]; RegsH[2] <= DIR[127:120];
        RegsL[3] <= DIR[135:128]; RegsH[3] <= DIR[143:136];
        RegsL[4] <= DIR[151:144]; RegsH[4] <= DIR[159:152];
        RegsL[5] <= DIR[167:160]; RegsH[5] <= DIR[175:168];
        RegsL[6] <= DIR[183:176]; RegsH[6] <= DIR[191:184];
        RegsL[7] <= DIR[199:192]; RegsH[7] <= DIR[207:200];
    end else if (ClkEn) begin
        if (RegWEH)
            RegsH[RegAddrA] <= RegDIH;
        if (RegWEL)
            RegsL[RegAddrA] <= RegDIL;
    end
end

assign RegBusA = {RegsH[RegAddrA], RegsL[RegAddrA]};
assign RegBusB = {RegsH[RegAddrB], RegsL[RegAddrB]};
assign RegBusC = {RegsH[RegAddrC], RegsL[RegAddrC]};
assign DOR = {RegsH[7], RegsL[7], RegsH[6], RegsL[6], RegsH[5], RegsL[5], RegsH[4], RegsL[4],
              RegsH[3], RegsL[3], RegsH[2], RegsL[2], RegsH[1], RegsL[1], RegsH[0], RegsL[0]};

//----------------------------------------------------------------------------
// Buses
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n) begin
    if (ClkEn) begin
        case (Set_BusB_To)
        4'b0111: BusB <= ACC;
        4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101: BusB <= Set_BusB_To[0] ? RegBusB[7:0] : RegBusB[15:8];
        4'b0110: BusB <= DI_Reg;
        4'b1000: BusB <= SP[7:0];
        4'b1001: BusB <= SP[15:8];
        4'b1010: BusB <= 8'h01;
        4'b1011: BusB <= F;
        4'b1100: BusB <= PC[7:0];
        4'b1101: BusB <= PC[15:8];
        4'b1110: BusB <= (IR == 8'h71 && out0) ? 8'hFF : 8'h00;
        default: BusB <= 8'h00;        // VHDL "--------"
        endcase

        case (Set_BusA_To)
        4'b0111: BusA <= ACC;
        4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101: BusA <= Set_BusA_To[0] ? RegBusA[7:0] : RegBusA[15:8];
        4'b0110: BusA <= DI_Reg;
        4'b1000: BusA <= SP[7:0];
        4'b1001: BusA <= SP[15:8];
        4'b1010: BusA <= 8'h00;
        default: BusA <= 8'h00;        // VHDL "--------"
        endcase
        if (XYbit_undoc) begin
            BusA <= DI_Reg;
            BusB <= DI_Reg;
        end
    end
end

//----------------------------------------------------------------------------
// External control signals
//----------------------------------------------------------------------------
always_ff @(posedge CLK_n or posedge rst) begin
    if (rst)
        RFSH_n <= 1'b1;
    else if (!DIRSet && CEN)
        RFSH_n <= ~(MCycle == 3'b001 && ((TState == 3'd2 && WAIT_n) || TState == 3'd3));
end

assign MC         = MCycle;
assign TS         = TState;
assign DI_Reg     = DI;
assign HALT_n     = ~Halt_FF;
assign BUSAK_n    = ~(BusAck & RESET_n);
assign IntCycle_n = ~IntCycle;
assign IntE       = IntE_FF1;
assign IORQ       = IORQ_i;
assign Stop       = I_DJNZ;
assign SOD        = SOD_r;

//----------------------------------------------------------------------------
// Main state machine
//----------------------------------------------------------------------------
// OldNMI_n and BusReq_s / BusAck are not reset in T80 (BusReq_s / BusAck power up 0)
always_ff @(posedge CLK_n) begin
    if (RESET_n && !DIRSet)
        OldNMI_n <= NMI_n;
end

always_ff @(posedge CLK_n or posedge rst) begin
    if (rst) begin
        MCycle <= 3'b001;
        TState <= 3'd0;
        Pre_XY_F_M <= 3'b000;
        Halt_FF <= 1'b0;
        NMICycle <= 1'b0;
        IntCycle <= 1'b0;
        IntE_FF1 <= 1'b0;
        IntE_FF2 <= 1'b0;
        No_BTR <= 1'b0;
        Auto_Wait_t1 <= 1'b0;
        Auto_Wait_t2 <= 1'b0;
        M1_n <= 1'b1;
        NMI_s <= 1'b0;
    end else if (DIRSet) begin
        IntE_FF2 <= DIR[211];
        IntE_FF1 <= DIR[210];
    end else begin
        if (!NMI_n && OldNMI_n)
            NMI_s <= 1'b1;

        if (CEN) begin
            Auto_Wait_t2 <= Auto_Wait_t1;
            if (T_Res) begin
                Auto_Wait_t1 <= 1'b0;
                Auto_Wait_t2 <= 1'b0;
            end else begin
                Auto_Wait_t1 <= Auto_Wait | IORQ_i;
            end
            No_BTR <= (I_BT & (~IR[4] | ~F[Flag_P])) |
                      (I_BC & (~IR[4] | F[Flag_Z] | ~F[Flag_P])) |
                      (I_BTR & (~IR[4] | F[Flag_Z]));
            if (TState == 3'd2) begin
                if (SetEI) begin
                    IntE_FF1 <= 1'b1;
                    IntE_FF2 <= 1'b1;
                end
                if (I_RETN)
                    IntE_FF1 <= IntE_FF2;
            end
            if (TState == 3'd3) begin
                if (SetDI) begin
                    IntE_FF1 <= 1'b0;
                    IntE_FF2 <= 1'b0;
                end
            end
            if (IntCycle || NMICycle)
                Halt_FF <= 1'b0;
            if (MCycle == 3'b001 && TState == 3'd2 && WAIT_n)
                M1_n <= 1'b1;
            if (!(BusReq_s && BusAck)) begin
                if (TState == 3'd2 && !WAIT_n) begin
                end else if (T_Res) begin
                    if (Halt && !(mode == 2'd3 && !INT_n && !IntE_FF1))  // GB halt bug: INT_n low with IME 0
                        Halt_FF <= 1'b1;
                    if (!BusReq_s) begin
                        TState <= 3'd1;
                        if (IntCycle && mode == 2'd3) begin              // GB: interrupt read in MCycle 3
                            if (MCycle == 3'b010)
                                M1_n <= 1'b0;
                            else
                                M1_n <= 1'b1;
                        end
                        if (NextIs_XY_Fetch) begin
                            MCycle <= 3'b110;
                            Pre_XY_F_M <= MCycle;
                            if (IR == 8'h36 && mode == 2'd0)
                                Pre_XY_F_M <= 3'b010;
                        end else if (MCycle == 3'b111 || (MCycle == 3'b110 && mode == 2'd1 && ISet != 2'b01)) begin
                            MCycle <= Pre_XY_F_M + 3'd1;
                        end else if (MCycle == MCycles || No_BTR || (MCycle == 3'b010 && I_DJNZ && IncDecZ)) begin
                            M1_n <= 1'b0;
                            MCycle <= 3'b001;
                            IntCycle <= 1'b0;
                            NMICycle <= 1'b0;
                            if (NMI_s && Prefix == 2'b00) begin
                                NMI_s <= 1'b0;
                                NMICycle <= 1'b1;
                                IntE_FF1 <= 1'b0;
                            end else if (IntE_FF1 && !INT_n && Prefix == 2'b00 && !SetEI) begin
                                IntCycle <= 1'b1;
                                IntE_FF1 <= 1'b0;
                                IntE_FF2 <= 1'b0;
                            end else if (Halt_FF && !INT_n && mode == 2'd3) begin
                                Halt_FF <= 1'b0;
                            end
                        end else begin
                            MCycle <= MCycle + 3'd1;
                        end
                    end
                end else begin
                    if (!((Auto_Wait && !Auto_Wait_t2) || (IOWAIT == 1 && IORQ_i && !Auto_Wait_t1)))
                        TState <= TState + 3'd1;
                end
            end
            if (TState == 3'd0)
                M1_n <= 1'b0;
        end
    end
end

// BusReq_s / BusAck: same clocking as the state machine above, without its reset
always_ff @(posedge CLK_n) begin
    if (RESET_n && !DIRSet && CEN) begin
        BusReq_s <= ~BUSRQ_n;
        if (!(BusReq_s && BusAck)) begin
            BusAck <= 1'b0;
            if (!(TState == 3'd2 && !WAIT_n) && T_Res && BusReq_s)
                BusAck <= 1'b1;
        end
    end
end

assign Auto_Wait = IntCycle && MCycle == 3'b001;

endmodule

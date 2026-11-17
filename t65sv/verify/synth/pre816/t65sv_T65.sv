// t65sv_T65: drop-in replacement for the T65 entity (same ports, DEBUG record packed {I,A,X,Y,S,P}).
// Mode 2'b00 = NMOS 6502 identical to T65 Ver 315; 2'b01/2'b10/2'b11 = 65C02 of flavour C02
// (65C816 is not implemented; T65 itself never distinguishes "10" from "01").
// Derived from T65 by Daniel Wallner; MikeJ, WoS, SzGy and contributors (MiSTer-devel lineage); licence: see t65sv.sv.
module t65sv_T65 #(
  parameter int C02        = 1,     // 65C02 flavour for Mode != 00: 1 WDC, 2 Rockwell, 3 65SC02, 0 none
  parameter bit NO_DECIMAL = 1'b0,
  parameter bit C02_FIXED  = 1'b0   // 1: always the 65C02 (Mode ignored)
) (
  input  logic [1:0]  Mode,
  input  logic        Res_n,
  input  logic        Enable,
  input  logic        Clk,
  input  logic        Rdy,
  input  logic        Abort_n,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  input  logic        SO_n,
  input  tri1         BCD_en,   // optional (upstream C64_MiSTer T65 port); unconnected = decimal enabled
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
  output logic [47:0] DEBUG,
  output logic        NMI_ack
);
  t65sv #(.C02(C02), .NO_DECIMAL(NO_DECIMAL), .C02_FIXED(C02_FIXED)) u_core (
    .Mode(Mode), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(Abort_n),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .BCD_en(BCD_en), .R_W_n(R_W_n), .Sync(Sync), .EF(EF), .MF(MF),
    .XF(XF), .ML_n(ML_n), .VP_n(VP_n), .VDA(VDA), .VPA(VPA), .A(A), .DI(DI), .DO(DO),
    .Regs(Regs), .DEBUG(DEBUG), .NMI_ack(NMI_ack));
endmodule

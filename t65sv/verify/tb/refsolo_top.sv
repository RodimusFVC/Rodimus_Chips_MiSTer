// T65 oracle alone with the solo_top port names (used to measure T65 Mode "01" against the 65C02 references)
module solo_top (
  input  logic        Clk, Res_n, Enable, Rdy, Abort_n, IRQ_n, NMI_n, SO_n,
  input  logic [1:0]  Mode,
  input  logic [7:0]  DI,
  output logic        r_R_W_n, r_Sync, r_EF, r_MF, r_XF, r_ML_n, r_VP_n, r_VDA, r_VPA, r_NMI_ack,
  output logic [23:0] r_A,
  output logic [7:0]  r_DO,
  output logic [63:0] r_Regs,
  output logic [47:0] r_DEBUG
);
  ref_T65 u_ref (
    .Mode(Mode), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(Abort_n),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .DI(DI),
    .R_W_n(r_R_W_n), .Sync(r_Sync), .EF(r_EF), .MF(r_MF), .XF(r_XF), .ML_n(r_ML_n),
    .VP_n(r_VP_n), .VDA(r_VDA), .VPA(r_VPA), .A(r_A), .DO(r_DO), .Regs(r_Regs),
    .DEBUG_I(r_DEBUG[47:40]), .DEBUG_A(r_DEBUG[39:32]), .DEBUG_X(r_DEBUG[31:24]),
    .DEBUG_Y(r_DEBUG[23:16]), .DEBUG_S(r_DEBUG[15:8]), .DEBUG_P(r_DEBUG[7:0]), .NMI_ack(r_NMI_ack));
endmodule

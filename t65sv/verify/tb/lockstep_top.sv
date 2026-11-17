// Lockstep: GHDL-converted T65 (oracle) and t65sv driven by identical stimulus.
module lockstep_top (
  input  logic        Clk, Res_n, Enable, Rdy, Abort_n, IRQ_n, NMI_n, SO_n,
  input  logic [1:0]  Mode,
  input  logic [7:0]  DI,
  output logic        r_R_W_n, r_Sync, r_EF, r_MF, r_XF, r_ML_n, r_VP_n, r_VDA, r_VPA, r_NMI_ack,
  output logic [23:0] r_A,
  output logic [7:0]  r_DO,
  output logic [63:0] r_Regs,
  output logic [47:0] r_DEBUG,
  output logic        d_R_W_n, d_Sync, d_EF, d_MF, d_XF, d_ML_n, d_VP_n, d_VDA, d_VPA, d_NMI_ack,
  output logic [23:0] d_A,
  output logic [7:0]  d_DO,
  output logic [63:0] d_Regs,
  output logic [47:0] d_DEBUG
);
  ref_T65 u_ref (
    .Mode(Mode), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(Abort_n),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .DI(DI),
    .R_W_n(r_R_W_n), .Sync(r_Sync), .EF(r_EF), .MF(r_MF), .XF(r_XF), .ML_n(r_ML_n),
    .VP_n(r_VP_n), .VDA(r_VDA), .VPA(r_VPA), .A(r_A), .DO(r_DO), .Regs(r_Regs),
    .DEBUG_I(r_DEBUG[47:40]), .DEBUG_A(r_DEBUG[39:32]), .DEBUG_X(r_DEBUG[31:24]),
    .DEBUG_Y(r_DEBUG[23:16]), .DEBUG_S(r_DEBUG[15:8]), .DEBUG_P(r_DEBUG[7:0]),
    .NMI_ack(r_NMI_ack));

  t65sv_T65 u_dut (
    .Mode(Mode), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(Abort_n),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .DI(DI),
    .R_W_n(d_R_W_n), .Sync(d_Sync), .EF(d_EF), .MF(d_MF), .XF(d_XF), .ML_n(d_ML_n),
    .VP_n(d_VP_n), .VDA(d_VDA), .VPA(d_VPA), .A(d_A), .DO(d_DO), .Regs(d_Regs),
    .DEBUG(d_DEBUG), .NMI_ack(d_NMI_ack));
endmodule

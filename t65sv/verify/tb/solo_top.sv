// Single t65sv instance with r_* port names so the lockstep C++ drivers can run it alone (variant testing).
module solo_top #(parameter int C02 = 0, parameter bit NO_DECIMAL = 1'b0, parameter bit C02_FIXED = 1'b0) (
  input  logic        Clk, Res_n, Enable, Rdy, Abort_n, IRQ_n, NMI_n, SO_n,
  input  logic [1:0]  Mode,
  input  logic [7:0]  DI,
  output logic        r_R_W_n, r_Sync, r_EF, r_MF, r_XF, r_ML_n, r_VP_n, r_VDA, r_VPA, r_NMI_ack,
  output logic [23:0] r_A,
  output logic [7:0]  r_DO,
  output logic [63:0] r_Regs,
  output logic [47:0] r_DEBUG
);
  t65sv_T65 #(.C02(C02), .NO_DECIMAL(NO_DECIMAL), .C02_FIXED(C02_FIXED)) u_dut (
    .Mode(Mode), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(Abort_n),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .DI(DI),
    .R_W_n(r_R_W_n), .Sync(r_Sync), .EF(r_EF), .MF(r_MF), .XF(r_XF), .ML_n(r_ML_n),
    .VP_n(r_VP_n), .VDA(r_VDA), .VPA(r_VPA), .A(r_A), .DO(r_DO), .Regs(r_Regs),
    .DEBUG(r_DEBUG), .NMI_ack(r_NMI_ack));
endmodule

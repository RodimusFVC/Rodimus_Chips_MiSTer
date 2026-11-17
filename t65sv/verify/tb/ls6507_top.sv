// 6507 wrapper vs T65 oracle (IRQ/NMI/SO tied off, 13 address lines compared)
module ls6507_top (input logic Clk, Res_n, Enable, Rdy, input logic [7:0] DI,
                   output logic [12:0] r_A, d_A, output logic [7:0] r_DO, d_DO, output logic r_RW, d_RW);
  logic [23:0] ra;
  ref_T65 u_ref (.Mode(2'b00), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(1'b1),
    .IRQ_n(1'b1), .NMI_n(1'b1), .SO_n(1'b1), .DI(DI), .R_W_n(r_RW), .Sync(), .EF(), .MF(), .XF(), .ML_n(),
    .VP_n(), .VDA(), .VPA(), .A(ra), .DO(r_DO), .Regs(), .DEBUG_I(), .DEBUG_A(), .DEBUG_X(), .DEBUG_Y(),
    .DEBUG_S(), .DEBUG_P(), .NMI_ack());
  assign r_A = ra[12:0];
  t65sv_6507 u_dut (.Clk(Clk), .Enable(Enable), .Res_n(Res_n), .Rdy(Rdy), .R_W_n(d_RW), .A(d_A), .DI(DI), .DO(d_DO));
endmodule

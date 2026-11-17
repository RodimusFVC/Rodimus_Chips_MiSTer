// Fleet configuration: Mode=00, Abort_n=SO_n=1; only A, DO, R_W_n, Sync are used.
module fleet_ref (input clk, res_n, enable, rdy, irq_n, nmi_n, input [7:0] di,
                  output [23:0] a, output [7:0] dout, output rw, output sync);
  ref_T65 u (.Mode(2'b00), .Res_n(res_n), .Enable(enable), .Clk(clk), .Rdy(rdy), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(1'b1), .DI(di), .R_W_n(rw), .Sync(sync), .EF(), .MF(), .XF(),
    .ML_n(), .VP_n(), .VDA(), .VPA(), .A(a), .DO(dout), .Regs(), .DEBUG_I(), .DEBUG_A(), .DEBUG_X(),
    .DEBUG_Y(), .DEBUG_S(), .DEBUG_P(), .NMI_ack());
endmodule
module fleet_sv #(parameter int C02 = 1) (input clk, res_n, enable, rdy, irq_n, nmi_n, input [7:0] di,
                  output [23:0] a, output [7:0] dout, output rw, output sync);
  t65sv_T65 #(.C02(C02)) u (.Mode(2'b00), .Res_n(res_n), .Enable(enable), .Clk(clk), .Rdy(rdy), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(1'b1), .BCD_en(1'b1), .DI(di), .R_W_n(rw), .Sync(sync), .EF(), .MF(), .XF(),
    .ML_n(), .VP_n(), .VDA(), .VPA(), .A(a), .DO(dout), .Regs(), .DEBUG(), .NMI_ack());
endmodule
// Full T65 port in use (all outputs observed), runtime Mode input, for the 65C02-capable comparison.
module full_ref (input clk, res_n, enable, rdy, irq_n, nmi_n, so_n, input [1:0] mode, input [7:0] di,
                 output [23:0] a, output [7:0] dout, output rw, output sync, output [63:0] regs, output [6:0] misc);
  ref_T65 u (.Mode(mode), .Res_n(res_n), .Enable(enable), .Clk(clk), .Rdy(rdy), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(so_n), .DI(di), .R_W_n(rw), .Sync(sync), .EF(misc[0]), .MF(misc[1]), .XF(misc[2]),
    .ML_n(misc[3]), .VP_n(misc[4]), .VDA(misc[5]), .VPA(misc[6]), .A(a), .DO(dout), .Regs(regs), .DEBUG_I(), .DEBUG_A(), .DEBUG_X(),
    .DEBUG_Y(), .DEBUG_S(), .DEBUG_P(), .NMI_ack());
endmodule
module full_sv #(parameter int C02 = 1) (input clk, res_n, enable, rdy, irq_n, nmi_n, so_n, input [1:0] mode, input [7:0] di,
                 output [23:0] a, output [7:0] dout, output rw, output sync, output [63:0] regs, output [6:0] misc);
  t65sv_T65 #(.C02(C02)) u (.Mode(mode), .Res_n(res_n), .Enable(enable), .Clk(clk), .Rdy(rdy), .Abort_n(1'b1),
    .IRQ_n(irq_n), .NMI_n(nmi_n), .SO_n(so_n), .BCD_en(1'b1), .DI(di), .R_W_n(rw), .Sync(sync), .EF(misc[0]), .MF(misc[1]), .XF(misc[2]),
    .ML_n(misc[3]), .VP_n(misc[4]), .VDA(misc[5]), .VPA(misc[6]), .A(a), .DO(dout), .Regs(regs), .DEBUG(), .NMI_ack());
endmodule

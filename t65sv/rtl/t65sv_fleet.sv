// t65sv_t65: t65sv on the fleet's chip_pool_pkg bus types (t65_i_t / t65_o_t).
// Derived from T65 by Daniel Wallner; MikeJ, WoS, SzGy and contributors (MiSTer-devel lineage); licence: see t65sv.sv.
// Mode 00, Abort_n = SO_n = 1, like every fleet T65 instance. Sync is a separate output (t65_o_t has
// no field for it); leave it unconnected where it is not needed.
module t65sv_t65 (
  input  logic                      clk,
  input  chip_pool_pkg::t65_i_t     i,
  output chip_pool_pkg::t65_o_t     o,
  output logic                      sync
);
  /* verilator lint_off UNUSED */
  logic [23:0] a24;   // A[23:16] is T65's dummy bank byte
  /* verilator lint_on UNUSED */
  logic [7:0]  dout;
  logic        rw;

  t65sv #(.C02(0)) u_core (
    .Mode(2'b00), .Res_n(i.res_n), .Enable(i.enable), .Clk(clk), .Rdy(i.rdy), .Abort_n(1'b1),
    .IRQ_n(i.irq_n), .NMI_n(i.nmi_n), .SO_n(1'b1), .BCD_en(1'b1), .R_W_n(rw), .Sync(sync),
    .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),
    .A(a24), .DI(i.di), .DO(dout), .Regs(), .DEBUG(), .NMI_ack());

  assign o.a    = a24[15:0];
  assign o.dout = dout;
  assign o.rw   = rw;
endmodule

// t65sv variant tops: 6510/8500, 6507, 2A03/2A07, 65C02 (WDC / Rockwell / 65SC02), 65C816.
// Derived from T65 by Daniel Wallner; MikeJ, WoS, SzGy and contributors (MiSTer-devel lineage); licence: see t65sv.sv.

// 6510/8500 on-chip I/O port: $0000 = data direction (1 = output), $0001 = data.
module t65sv_ioport #(
  parameter int PORT_BITS = 6   // pins P0..P(PORT_BITS-1); higher bits have no pin and keep their last driven level
) (
  input  logic       Clk,
  input  logic       Res_n,
  input  logic       Enable,
  input  logic [15:0] A,
  input  logic       R_W_n,
  input  logic [7:0] DO,
  input  logic [7:0] P_I,       // pin levels when configured as input
  output logic       Sel,       // CPU is addressing $0000/$0001
  output logic [7:0] Rd,        // value the CPU reads at $0000/$0001
  output logic [7:0] P_O,       // data register
  output logic [7:0] P_DDR      // data direction register
);
  logic [7:0] ddr, data, held, pins;

  assign Sel   = (A[15:1] == 15'd0);
  assign P_O   = data;
  assign P_DDR = ddr;

  always_comb begin
    pins = P_I;
    if (PORT_BITS < 8) pins = (P_I & ((8'h01 << PORT_BITS) - 8'h01)) | (held & ~((8'h01 << PORT_BITS) - 8'h01));
  end

  assign Rd = A[0] ? ((data & ddr) | (pins & ~ddr)) : ddr;

  always_ff @(posedge Clk or negedge Res_n) begin
    if (!Res_n) begin
      ddr  <= 8'h00;
      data <= 8'h00;
      held <= 8'h00;
    end else begin
      held <= (data & ddr) | (held & ~ddr);
      if (Enable && Sel && !R_W_n) begin
        if (A[0]) data <= DO;
        else      ddr  <= DO;
      end
    end
  end
endmodule

// MOS 6510 / 8500: NMOS core (identical to T65 Mode "00") plus the I/O port.
// The external bus still sees $0000/$0001 accesses (as on the real chip); reads there return the port.
// AEC only tells the system when the CPU drives the bus (the core itself is stopped with RDY).
module t65sv_6510 #(
  parameter int PORT_BITS = 6
) (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  input  logic        AEC,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  output logic        R_W_n,
  output logic        Sync,
  output logic        Bus_En,   // = AEC: address, data and R/W are valid on the external bus
  output logic [15:0] A,
  input  logic [7:0]  DI,
  output logic [7:0]  DO,
  input  logic [7:0]  P_I,
  output logic [7:0]  P_O,
  output logic [7:0]  P_DDR
);
  /* verilator lint_off UNUSED */
  logic [23:0] a24;   // A[23:16] is T65's dummy bank byte
  /* verilator lint_on UNUSED */
  logic [7:0]  di_core, port_rd;
  logic        port_sel;

  assign A      = a24[15:0];
  assign Bus_En = AEC;
  assign di_core = !R_W_n ? DO : port_sel ? port_rd : DI;

  t65sv #(.C02(0)) u_core (
    .Mode(2'b00), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(1'b1),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(1'b1), .BCD_en(1'b1), .R_W_n(R_W_n), .Sync(Sync),
    .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),
    .A(a24), .DI(di_core), .DO(DO), .Regs(), .DEBUG(), .NMI_ack());

  t65sv_ioport #(.PORT_BITS(PORT_BITS)) u_port (
    .Clk(Clk), .Res_n(Res_n), .Enable(Enable), .A(a24[15:0]), .R_W_n(R_W_n), .DO(DO),
    .P_I(P_I), .Sel(port_sel), .Rd(port_rd), .P_O(P_O), .P_DDR(P_DDR));
endmodule

// MOS 6507: 13 address lines, no IRQ/NMI/SO pins.
module t65sv_6507 (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  output logic        R_W_n,
  output logic [12:0] A,
  input  logic [7:0]  DI,
  output logic [7:0]  DO
);
  /* verilator lint_off UNUSED */
  logic [23:0] a24;   // A[23:16] is T65's dummy bank byte
  /* verilator lint_on UNUSED */
  assign A = a24[12:0];
  t65sv #(.C02(0)) u_core (
    .Mode(2'b00), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(1'b1),
    .IRQ_n(1'b1), .NMI_n(1'b1), .SO_n(1'b1), .BCD_en(1'b1), .R_W_n(R_W_n), .Sync(),
    .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),
    .A(a24), .DI(DI), .DO(DO), .Regs(), .DEBUG(), .NMI_ack());
endmodule

// Ricoh 2A03 / 2A07 CPU part: NMOS core, D flag settable but ADC/SBC/ARR always binary.
module t65sv_2A03 (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  output logic        R_W_n,
  output logic        Sync,
  output logic [15:0] A,
  input  logic [7:0]  DI,
  output logic [7:0]  DO
);
  /* verilator lint_off UNUSED */
  logic [23:0] a24;   // A[23:16] is T65's dummy bank byte
  /* verilator lint_on UNUSED */
  assign A = a24[15:0];
  t65sv #(.C02(0), .NO_DECIMAL(1'b1)) u_core (
    .Mode(2'b00), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(1'b1),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(1'b1), .BCD_en(1'b1), .R_W_n(R_W_n), .Sync(Sync),
    .EF(), .MF(), .XF(), .ML_n(), .VP_n(), .VDA(), .VPA(),
    .A(a24), .DI(DI), .DO(DO), .Regs(), .DEBUG(), .NMI_ack());
endmodule

// 65C02: FLAVOUR 1 = WDC W65C02S (RMB/SMB/BBR/BBS, WAI/STP), 2 = Rockwell R65C02 (bit ops),
// 3 = Synertek/GTE 65SC02 (neither).
module t65sv_65C02 #(
  parameter int FLAVOUR = 1
) (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  input  logic        SO_n,
  output logic        R_W_n,
  output logic        Sync,
  output logic        VP_n,
  output logic        ML_n,
  output logic [15:0] A,
  input  logic [7:0]  DI,
  output logic [7:0]  DO
);
  /* verilator lint_off UNUSED */
  logic [23:0] a24;   // A[23:16] is T65's dummy bank byte
  /* verilator lint_on UNUSED */
  assign A = a24[15:0];
  t65sv #(.C02(FLAVOUR), .C02_FIXED(1'b1)) u_core (
    .Mode(2'b01), .Res_n(Res_n), .Enable(Enable), .Clk(Clk), .Rdy(Rdy), .Abort_n(1'b1),
    .IRQ_n(IRQ_n), .NMI_n(NMI_n), .SO_n(SO_n), .BCD_en(1'b1), .R_W_n(R_W_n), .Sync(Sync),
    .EF(), .MF(), .XF(), .ML_n(ML_n), .VP_n(VP_n), .VDA(), .VPA(),
    .A(a24), .DI(DI), .DO(DO), .Regs(), .DEBUG(), .NMI_ack());
endmodule

// W65C816S with its own pin names. M and X are separate outputs (the chip multiplexes them on MX with PHI2).
// Wait_n is low while WAI waits (the chip drives its RDY pin low then). Same engine as t65sv #(.C816(1)).
module t65sv_65C816 (
  input  logic        Clk,
  input  logic        Enable,
  input  logic        Res_n,
  input  logic        Rdy,
  input  logic        Abort_n,
  input  logic        IRQ_n,
  input  logic        NMI_n,
  output logic [23:0] A,        // {bank (D7..D0 during PHI2 low on the chip), A15..A0}
  input  logic [7:0]  DI,
  output logic [7:0]  DO,
  output logic        R_W_n,
  output logic        VDA,
  output logic        VPA,
  output logic        VP_n,
  output logic        ML_n,
  output logic        E,
  output logic        MF,
  output logic        XF,
  output logic        Wait_n
);
  t65sv816 u_816 (
    .Clk(Clk), .Enable(Enable), .Res_n(Res_n), .Rdy(Rdy), .Abort_n(Abort_n), .IRQ_n(IRQ_n), .NMI_n(NMI_n),
    .DI(DI), .A(A), .DO(DO), .R_W_n(R_W_n), .VDA(VDA), .VPA(VPA), .VP_n(VP_n), .ML_n(ML_n), .E(E), .MF(MF),
    .XF(XF), .Sync(), .Wait_n(Wait_n), .NMI_ack(), .Regs_PC(), .Regs_C(), .Regs_X(), .Regs_Y(), .Regs_S(),
    .Regs_D(), .Regs_DBR(), .Regs_PBR(), .Regs_P(), .Regs_E(), .Regs_IR());
endmodule

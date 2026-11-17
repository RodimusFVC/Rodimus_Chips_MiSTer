// ============================================================================
// Pin-level tri-state tops (T48 system/t80xx.vhd): quasi-bidirectional ports
// drive strongly only in the low-impedance phase or when 0, otherwise float to
// the external pull-up; BUS / T0 are driven while their direction bit is set.
// For FPGA-internal use prefer the *_notri tops.
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

// quasi-bidirectional pin: strong while low-impedance or 0, else pulled up
// Quartus 17: module-level generate loops need generate / endgenerate and a literal bound (w = pin width).
`define T48SV_QB(pin, val, limp, lbl, w) \
  generate for (qb = 0; qb < w; qb = qb + 1) begin : lbl \
    assign pin[qb] = (limp || !val[qb]) ? val[qb] : 1'bz; \
  end endgenerate

module t48sv_t8039 (
  input  logic       xtal_i,
  input  logic       reset_n_i,
  inout  wire        t0_b,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  inout  wire  [7:0] db_b,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  output logic       prog_n_o
);
  genvar qb;
  logic       t0_s, t0_dir_s, db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s;
  logic [7:0] db_s, p1_s, p2_s;

  t48sv_t8039_notri #(.gate_port_input_g(0)) t8039_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_b), .t0_o(t0_s),
    .t0_dir_o(t0_dir_s), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_b), .db_o(db_s), .db_dir_o(db_dir_s), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), .p2h_low_imp_o(p2h_limp_s),
    .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), .prog_n_o(prog_n_o)
  );

  assign t0_b = t0_dir_s ? t0_s : 1'bz;
  assign db_b = db_dir_s ? db_s : 8'hzz;
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8)
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz;
  end endgenerate
endmodule

module t48sv_t8048 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_n_i,
  inout  wire        t0_b,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  inout  wire  [7:0] db_b,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  output logic       prog_n_o
);
  genvar qb;
  logic       t0_s, t0_dir_s, db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s;
  logic [7:0] db_s, p1_s, p2_s;

  t48sv_t8048_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8048_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_b), .t0_o(t0_s),
    .t0_dir_o(t0_dir_s), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_b), .db_o(db_s), .db_dir_o(db_dir_s), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), .p2h_low_imp_o(p2h_limp_s),
    .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), .prog_n_o(prog_n_o)
  );

  assign t0_b = t0_dir_s ? t0_s : 1'bz;
  assign db_b = db_dir_s ? db_s : 8'hzz;
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8)
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz;
  end endgenerate
endmodule

// UPI-41 family pin tops: 0 = 8041, 1 = 8041A, 2 = 8042AH
`define T48SV_UPI_TRI(name, notri) \
module name #( \
  parameter        ROM_INIT_FILE = "" \
) ( \
  input  logic       xtal_i, \
  input  logic       reset_n_i, \
  input  logic       t0_i, \
  input  logic       cs_n_i, \
  input  logic       rd_n_i, \
  input  logic       a0_i, \
  input  logic       wr_n_i, \
  output logic       sync_o, \
  inout  wire  [7:0] db_b, \
  input  logic       t1_i, \
  inout  wire  [7:0] p2_b, \
  inout  wire  [7:0] p1_b, \
  output logic       prog_n_o \
); \
  genvar qb; \
  logic       db_dir_s, p1_limp_s, p2l_limp_s, p2h_limp_s; \
  logic [7:0] db_s, p1_s, p2_s; \
  notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) notri_b ( \
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_n_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i), \
    .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_b), .db_o(db_s), \
    .db_dir_o(db_dir_s), .t1_i(t1_i), .p2_i(p2_b), .p2_o(p2_s), .p2l_low_imp_o(p2l_limp_s), \
    .p2h_low_imp_o(p2h_limp_s), .p1_i(p1_b), .p1_o(p1_s), .p1_low_imp_o(p1_limp_s), \
    .prog_n_o(prog_n_o) \
  ); \
  assign db_b = db_dir_s ? db_s : 8'hzz; \
  `T48SV_QB(p1_b, p1_s, p1_limp_s, g_p1_b, 8) \
  generate for (qb = 0; qb < 8; qb = qb + 1) begin : g_p2_b \
    assign p2_b[qb] = ((qb < 4 ? p2l_limp_s : p2h_limp_s) || !p2_s[qb]) ? p2_s[qb] : 1'bz; \
  end endgenerate \
endmodule

`T48SV_UPI_TRI(t48sv_t8041, t48sv_t8041_notri)
`T48SV_UPI_TRI(t48sv_t8041a, t48sv_t8041a_notri)
`T48SV_UPI_TRI(t48sv_t8042ah, t48sv_t8042ah_notri)

module t48sv_t8021 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_i,
  output logic       ale_o,
  input  logic       t1_i,
  inout  wire  [3:0] p2_b,
  inout  wire  [7:0] p1_b,
  inout  wire  [7:0] p0_b,
  output logic       prog_n_o
);
  genvar qb;
  logic [3:0] p2_s;
  logic [7:0] p1_s, p0_s;

  t48sv_t8021_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8021_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_i(reset_i), .ale_o(ale_o), .t1_i(t1_i),
    .p2_i(p2_b), .p2_o(p2_s), .p1_i(p1_b), .p1_o(p1_s), .p0_i(p0_b), .p0_o(p0_s),
    .prog_n_o(prog_n_o)
  );

  // T48 drives the 8021 ports open-drain only (no low-impedance phase)
  `T48SV_QB(p2_b, p2_s, 1'b0, g_p2_b, 4)
  `T48SV_QB(p1_b, p1_s, 1'b0, g_p1_b, 8)
  `T48SV_QB(p0_b, p0_s, 1'b0, g_p0_b, 8)
endmodule

module t48sv_t8022 #(
  parameter        ROM_INIT_FILE = ""
) (
  input  logic       xtal_i,
  input  logic       reset_i,
  input  logic       t0_i,
  output logic       ale_o,
  input  logic       t1_i,
  inout  wire  [7:0] p2_b,
  inout  wire  [7:0] p1_b,
  inout  wire  [7:0] p0_b,
  output logic       prog_n_o,
  input  logic [7:0] an0_i,
  input  logic [7:0] an1_i
);
  genvar qb;
  logic [7:0] p2_s, p1_s, p0_s;

  t48sv_t8022_notri #(.gate_port_input_g(0), .ROM_INIT_FILE(ROM_INIT_FILE)) t8022_notri_b (
    .xtal_i(xtal_i), .xtal_en_i(1'b1), .reset_i(reset_i), .t0_i(t0_i), .ale_o(ale_o),
    .t1_i(t1_i), .p2_i(p2_b), .p2_o(p2_s), .p1_i(p1_b), .p1_o(p1_s), .p0_i(p0_b), .p0_o(p0_s),
    .prog_n_o(prog_n_o), .an0_i(an0_i), .an1_i(an1_i)
  );

  `T48SV_QB(p2_b, p2_s, 1'b0, g_p2_b, 8)
  `T48SV_QB(p1_b, p1_s, 1'b0, g_p1_b, 8)
  `T48SV_QB(p0_b, p0_s, 1'b0, g_p0_b, 8)
endmodule

// ============================================================================
// t48sv_mcs48_pool: t48sv 8035 / 8039 / 8040 on the MiSTer fleet master bus
// (chip_pool_pkg::mcs48_i_t / mcs48_o_t), program ROM external on pmem.
// Same core and timing as t48sv_t8039_notri_extrom (T48 r295 behaviour).
//   RAM_AW 6 = 64 B (8035), 7 = 128 B (8039), 8 = 256 B (8040)
// Needs the core's chip_pool_pkg; not part of t48sv_all.sv.
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_mcs48_pool #(
  parameter int    RAM_AW   = 7,
  parameter int    GATE     = 0,       // gate_port_input_g
  parameter bit    EA       = 1'b0,
  parameter        RAMSTYLE = "MLAB, no_rw_check"
) (
  input  logic                     clk,
  input  chip_pool_pkg::mcs48_i_t  i,
  output chip_pool_pkg::mcs48_o_t  o
);

  wire [7:0]  p1_w, p2_w, db_w;
  wire [11:0] pmem_a_w;
  wire        rd_n_w, wr_n_w, ale_w, db_dir_w;

  t48sv_t8039_notri_extrom #(
    .gate_port_input_g(GATE), .ram_addr_width_g(RAM_AW), .RAMSTYLE(RAMSTYLE)
  ) mcs48 (
    .xtal_i(clk), .xtal_en_i(i.xtal_en), .reset_n_i(i.reset_n), .t0_i(i.t0), .t0_o(),
    .t0_dir_o(), .int_n_i(i.int_n), .ea_i(EA), .rd_n_o(rd_n_w), .psen_n_o(), .wr_n_o(wr_n_w),
    .ale_o(ale_w), .db_i(i.db), .db_o(db_w), .db_dir_o(db_dir_w), .t1_i(i.t1), .p2_i(i.p2_in),
    .p2_o(p2_w), .p2l_low_imp_o(), .p2h_low_imp_o(), .p1_i(i.p1_in), .p1_o(p1_w),
    .p1_low_imp_o(), .prog_n_o(), .pmem_addr_o(pmem_a_w), .pmem_data_i(i.pmem_d)
  );

  assign o.p1     = p1_w;
  assign o.p2     = p2_w;
  assign o.pmem_a = pmem_a_w;
  assign o.rd_n   = rd_n_w;
  assign o.wr_n   = wr_n_w;
  assign o.ale    = ale_w;
  assign o.db     = db_w;
  assign o.db_dir = db_dir_w;

endmodule

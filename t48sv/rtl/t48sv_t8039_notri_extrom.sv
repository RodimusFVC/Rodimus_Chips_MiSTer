// ============================================================================
// t48sv_t8039_notri_extrom: drop-in for the MiSTer fleet's t8039_notri_extrom
// (fleet derivation of Arnim Laeuger's T48 t8039_notri: program ROM external on
// pmem_addr_o / pmem_data_i, internal RAM 2**ram_addr_width_g bytes:
// 7 = 128 B (8039), 6 = 64 B (8035), 8 = 256 B (8040)). T48 r295 behaviour.
// ============================================================================

module t48sv_t8039_notri_extrom #(
  parameter int    gate_port_input_g = 1,
  parameter int    ram_addr_width_g  = 7,
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_n_i,
  input  logic        t0_i,
  output logic        t0_o,
  output logic        t0_dir_o,
  input  logic        int_n_i,
  input  logic        ea_i,
  output logic        rd_n_o,
  output logic        psen_n_o,
  output logic        wr_n_o,
  output logic        ale_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic        db_dir_o,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic       xtal3_s, dmem_we_s;
  logic [7:0] dmem_addr_s, dmem_data_from_s, dmem_data_to_s;
  logic [7:0] p1_out_s, p2_out_s;

  t48sv_t48_core #(
    .xtal_div_3_g(1), .register_mnemonic_g(1), .include_port1_g(1), .include_port2_g(1),
    .include_bus_g(1), .include_timer_g(1), .sample_t1_state_g(4), .REV2023(0)
  ) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_o),
    .pmem_data_i(pmem_data_i)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_ram #(.AW(ram_addr_width_g), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[ram_addr_width_g-1:0]), .we_i(dmem_we_s),
    .d_i(dmem_data_to_s), .d_o(dmem_data_from_s)
  );

endmodule

// ============================================================================
// Drop-in replacements for the T48 core entities (same ports and generics)
//   t48sv_t48_core    <- t48_core   (r295 by default: REV2023 = 0)
//   t48sv_upi41_core  <- upi41_core (2023+ release incl. fleet sts_o / IBF ack)
//   t48sv_t21_core    <- t21_core
//   t48sv_t22_core    <- t22_core
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_t48_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int include_port1_g     = 1,
  parameter int include_port2_g     = 1,
  parameter int include_bus_g       = 1,
  parameter int include_timer_g     = 1,
  parameter int sample_t1_state_g   = 4,
  parameter int REV2023             = 0
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
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
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  t48sv_core #(
    .VARIANT(0), .REV2023(REV2023), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .INCLUDE_PORT1(include_port1_g),
    .INCLUDE_PORT2(include_port2_g), .INCLUDE_BUS(include_bus_g),
    .INCLUDE_TIMER(include_timer_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), .p0_i(8'h00), .p0_o(),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

endmodule


module t48sv_upi41_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4,
  parameter int is_upi_type_a_g     = 1,
  parameter int UPI_IBF_ACK         = 1
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  input  logic        t0_i,
  input  logic        cs_n_i,
  input  logic        rd_n_i,
  input  logic        a0_i,
  input  logic        wr_n_i,
  output logic        sync_o,
  input  logic [7:0]  db_i,
  output logic [7:0]  db_o,
  output logic [7:0]  sts_o,
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
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [10:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic [11:0] pmem_addr_s;

  t48sv_core #(
    .VARIANT(1), .UPI_TYPE_A(is_upi_type_a_g), .REV2023(1),
    .UPI_IBF_ACK(UPI_IBF_ACK), .XTAL_DIV_3(xtal_div_3_g), .REGISTER_MNEMONIC(register_mnemonic_g),
    .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(),
    .t0_dir_o(), .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(sync_o),
    .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o), .p1_i(p1_i), .p1_o(p1_o),
    .p1_low_imp_o(p1_low_imp_o), .p0_i(8'h00), .p0_o(), .prog_n_o(prog_n_o), .clk_i(clk_i),
    .en_clk_i(en_clk_i), .xtal3_o(xtal3_o), .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o),
    .dmem_data_i(dmem_data_i), .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_i), .cs_n_i(cs_n_i), .rd_n_i(rd_n_i), .wr_n_i(wr_n_i), .a0_i(a0_i),
    .sts_o(sts_o), .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

  assign pmem_addr_o = pmem_addr_s[10:0];

endmodule


module t48sv_t21_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  output logic        ale_o,
  input  logic        t1_i,
  input  logic [3:0]  p2_i,
  output logic [3:0]  p2_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  input  logic [7:0]  p0_i,
  output logic [7:0]  p0_o,
  output logic        prog_n_o,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  logic [7:0] p2_s;

  t48sv_core #(
    .VARIANT(2), .REV2023(1), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(1'b0), .t0_o(), .t0_dir_o(),
    .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(ale_o), .db_i(8'h00),
    .db_o(), .db_dir_o(), .t1_i(t1_i), .p2_i({4'h0, p2_i}), .p2_o(p2_s), .p2l_low_imp_o(),
    .p2h_low_imp_o(), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(), .p0_i(p0_i), .p0_o(p0_o),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

  assign p2_o = p2_s[3:0];

endmodule


module t48sv_t22_core #(
  parameter int xtal_div_3_g        = 1,
  parameter int register_mnemonic_g = 1,
  parameter int sample_t1_state_g   = 4
) (
  input  logic        xtal_i,
  input  logic        xtal_en_i,
  input  logic        reset_i,
  output logic        ale_o,
  input  logic        t0_i,
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  input  logic [7:0]  p0_i,
  output logic [7:0]  p0_o,
  output logic        prog_n_o,
  output logic        adc_sel_an_o,
  output logic        adc_sh_o,
  output logic [7:0]  adc_sar_o,
  input  logic        adc_comp_i,
  input  logic        clk_i,
  input  logic        en_clk_i,
  output logic        xtal3_o,
  output logic [7:0]  dmem_addr_o,
  output logic        dmem_we_o,
  input  logic [7:0]  dmem_data_i,
  output logic [7:0]  dmem_data_o,
  output logic [11:0] pmem_addr_o,
  input  logic [7:0]  pmem_data_i
);

  t48sv_core #(
    .VARIANT(3), .REV2023(1), .XTAL_DIV_3(xtal_div_3_g),
    .REGISTER_MNEMONIC(register_mnemonic_g), .SAMPLE_T1_STATE(sample_t1_state_g)
  ) core (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_i), .t0_i(t0_i), .t0_o(), .t0_dir_o(),
    .int_n_i(1'b1), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(ale_o), .db_i(8'h00),
    .db_o(), .db_dir_o(), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(),
    .p2h_low_imp_o(), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(), .p0_i(p0_i), .p0_o(p0_o),
    .prog_n_o(prog_n_o), .clk_i(clk_i), .en_clk_i(en_clk_i), .xtal3_o(xtal3_o),
    .dmem_addr_o(dmem_addr_o), .dmem_we_o(dmem_we_o), .dmem_data_i(dmem_data_i),
    .dmem_data_o(dmem_data_o), .pmem_addr_o(pmem_addr_o), .pmem_data_i(pmem_data_i),
    .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0), .sts_o(),
    .adc_sel_an_o(adc_sel_an_o), .adc_sh_o(adc_sh_o), .adc_sar_o(adc_sar_o),
    .adc_comp_i(adc_comp_i)
  );

endmodule


// ----------------------------------------------------------------------------
// Internal data RAM: registered address, unregistered read (generic_ram_ena).
// MLAB by default; "logic" for registers, "M10K" for block RAM. Device RAM powers
// up cleared, so no HDL init (an init would block MLAB inference).
// no_rw_check: en_clk pulses are >= 3 XTAL clocks apart and the address register
// reloads every clock, so same-edge read-during-write is never observed.
// ----------------------------------------------------------------------------
module t48sv_ram #(
  parameter int    AW       = 7,
  parameter        RAMSTYLE = "MLAB, no_rw_check"
) (
  input  logic          clk_i,
  input  logic [AW-1:0] a_i,
  input  logic          we_i,
  input  logic [7:0]    d_i,
  output logic [7:0]    d_o
);

  (* ramstyle = RAMSTYLE *) logic [7:0] mem [0:(1<<AW)-1];
  logic [AW-1:0] a_q;

  always_ff @(posedge clk_i) begin
    if (we_i) mem[a_i] <= d_i;
    a_q <= a_i;
  end

  assign d_o = mem[a_q];

endmodule


// ----------------------------------------------------------------------------
// Internal program ROM (t48_rom / t49_rom / syn_rom): registered address
// ----------------------------------------------------------------------------
module t48sv_rom #(
  parameter int    AW        = 10,
  parameter        INIT_FILE = ""
) (
  input  logic          clk_i,
  input  logic [AW-1:0] a_i,
  output logic [7:0]    d_o
);

  logic [7:0]    rom [0:(1<<AW)-1];
  logic [AW-1:0] a_q;

  initial begin
    for (int i = 0; i < (1<<AW); i++) rom[i] = 8'h00;
    if (INIT_FILE != "") $readmemh(INIT_FILE, rom);
  end

  always_ff @(posedge clk_i) a_q <= a_i;

  assign d_o = rom[a_q];

endmodule

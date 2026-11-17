// t48sv core + 256 B data RAM for the instruction-level comparison with MAME.
// VARIANT: 0 MCS-48 (r295 / 2023 by REV2023), 1 UPI-41A, 2 8021, 3 8022
module mame_dut #(
  parameter int VARIANT = 0,
  parameter int REV2023 = 0
) (
  input  logic        clk,
  input  logic        reset_n,
  input  logic [7:0]  pmem_data_i,
  input  logic [7:0]  db_i,
  input  logic [7:0]  p1_i,
  input  logic [7:0]  p2_i,
  input  logic        t0_i,
  input  logic        t1_i,
  input  logic        int_n_i,
  output logic [11:0] pmem_addr_o,
  output logic [7:0]  p1_o,
  output logic [7:0]  p2_o,
  output logic [7:0]  acc_o,
  output logic [11:0] pc_o,
  output logic [3:0]  psw_o,
  output logic [2:0]  sp_o,
  output logic        f1_o,
  output logic        mb_o,
  output logic [7:0]  timer_o,
  output logic [4:0]  presc_o,
  output logic [1:0]  tsel_o,
  output logic        tflag_o,
  output logic        tovf_o,
  output logic        tie_o,
  output logic        ie_o,
  output logic        iprog_o,
  output logic [2:0]  mstate_o,
  output logic        mcyc_o,
  output logic        scyc_o,
  output logic [7:0]  opc_o,
  output logic        inj_o,
  output logic [7:0]  p2q_o
);
  logic [7:0]  ram [0:255];
  logic [7:0]  a_q, dmem_addr, dmem_wd, dmem_rd;
  logic        dmem_we, xtal3;
  logic [11:0] pa;
  logic [7:0]  p0_o;
  // quasi-bidirectional ports read as pin & latch (T48 gate_port_input_g = 1, as MAME)

  initial for (int i = 0; i < 256; i++) ram[i] = 8'h00;
  always_ff @(posedge clk) begin
    if (dmem_we) ram[dmem_addr] <= dmem_wd;
    a_q <= dmem_addr;
  end
  assign dmem_rd = ram[a_q];

  t48sv_core #(.VARIANT(VARIANT == 0 ? 0 : VARIANT == 1 ? 1 : VARIANT), .UPI_TYPE_A(1),
               .REV2023(VARIANT == 0 ? REV2023 : 1)) core (
    .xtal_i(clk), .xtal_en_i(1'b1), .reset_i(reset_n), .t0_i(t0_i), .t0_o(), .t0_dir_o(),
    .int_n_i(int_n_i), .ea_i(1'b0), .rd_n_o(), .psen_n_o(), .wr_n_o(), .ale_o(), .db_i(db_i),
    .db_o(), .db_dir_o(), .t1_i(t1_i), .p2_i(p2_i & p2_o), .p2_o(p2_o), .p2l_low_imp_o(),
    .p2h_low_imp_o(), .p1_i(p1_i & p1_o), .p1_o(p1_o), .p1_low_imp_o(), .p0_i(db_i & p0_o), .p0_o(p0_o),
    .prog_n_o(), .clk_i(clk), .en_clk_i(xtal3), .xtal3_o(xtal3), .dmem_addr_o(dmem_addr),
    .dmem_we_o(dmem_we), .dmem_data_i(dmem_rd), .dmem_data_o(dmem_wd), .pmem_addr_o(pa),
    .pmem_data_i(pmem_data_i), .cs_n_i(1'b1), .rd_n_i(1'b1), .wr_n_i(1'b1), .a0_i(1'b0),
    .sts_o(), .adc_sel_an_o(), .adc_sh_o(), .adc_sar_o(), .adc_comp_i(1'b0)
  );

  assign pmem_addr_o = pa;
  assign acc_o    = core.alu_b.accu_q;
  assign pc_o     = core.pmem_ctrl_b.pc_q;
  assign psw_o    = core.psw_b.psw_q;
  assign sp_o     = core.psw_b.sp_q;
  assign f1_o     = core.decoder_b.f1_q;
  assign mb_o     = core.decoder_b.mb_q;
  assign timer_o  = core.g_timer.timer_b.counter_q;
  assign presc_o  = core.g_timer.timer_b.prescaler_q;
  assign tsel_o   = core.g_timer.timer_b.inc_sel_q;
  assign tflag_o  = core.decoder_b.timer_flag_q;
  assign tovf_o   = core.decoder_b.timer_overflow_q;
  assign tie_o    = core.decoder_b.timer_int_enable_q;
  assign ie_o     = core.decoder_b.int_enable_q;
  assign iprog_o  = core.decoder_b.int_in_progress_q;
  assign mstate_o = core.clock_ctrl_b.mstate_q;
  assign mcyc_o   = core.clock_ctrl_b.multi_cycle_q;
  assign scyc_o   = core.clock_ctrl_b.second_cycle_q;
  assign opc_o    = core.decoder_b.opc_opcode_q;
  assign inj_o    = core.decoder_b.injected_int_q;
  assign p2q_o    = core.g_p2.p2_b.p2_q;

  export "DPI-C" function ram_peek;
  function automatic int ram_peek(input int i);
    return int'(ram[i]);
  endfunction
endmodule

// ============================================================================
// t48sv - MCS-48 / UPI-41 / MCS-21/22 family core in SystemVerilog
//
// Derived from the T48 uController core by Arnim Laeuger (opencores.org/
// github.com/devsaurus/t48), cycle-for-cycle equivalent to:
//   - T48 r295 (2009-04-01), as run by the MiSTer fleet through
//     t8039_notri_extrom (fleet derivation of Laeuger's t8039_notri) and t48_core
//   - the T48 2023+ release (UPI-41 / 8021 / 8022 / 8243 support), REV2023 = 1
// Written for the MiSTer fleet (Cyclone V, Quartus 17.0).
//
// Original T48 notice (retained as its licence requires):
//
// Copyright (c) 2004, 2005, Arnim Laeuger (arniml@opencores.org)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
// ============================================================================

// ============================================================================
// t48sv_core: one parameterised core for the whole family
//   VARIANT VAR_MCS48 (8035/39/40/48/49/50, 87xx), VAR_UPI41 (8041/41A/42),
//           VAR_MCS21 (8021), VAR_MCS22 (8022)
//   REV2023 0: T48 r295 behaviour (MiSTer fleet), 1: T48 2023+ release
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_core #(
  parameter int VARIANT           = 0,  // 0 MCS-48, 1 UPI-41, 2 MCS-21, 3 MCS-22
  parameter int UPI_TYPE_A        = 0,
  parameter int REV2023           = 0,
  parameter int UPI_IBF_ACK       = 1,
  parameter int XTAL_DIV_3        = 1,
  parameter int REGISTER_MNEMONIC = 1,
  parameter int INCLUDE_PORT1     = 1,
  parameter int INCLUDE_PORT2     = 1,
  parameter int INCLUDE_BUS       = 1,
  parameter int INCLUDE_TIMER     = 1,
  parameter int SAMPLE_T1_STATE   = 4
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
  input  logic [7:0]  pmem_data_i,
  // UPI-41 host interface
  input  logic        cs_n_i,
  input  logic        rd_n_i,
  input  logic        wr_n_i,
  input  logic        a0_i,
  output logic [7:0]  sts_o,
  // 8022 A/D converter
  output logic        adc_sel_an_o,
  output logic        adc_sh_o,
  output logic [7:0]  adc_sar_o,
  input  logic        adc_comp_i
);

  localparam int VAR_MCS48 = 0, VAR_UPI41 = 1, VAR_MCS21 = 2, VAR_MCS22 = 3;

  localparam bit IS_UPI   = VARIANT == VAR_UPI41;
  localparam bit IS_MCS2X = VARIANT == VAR_MCS21 || VARIANT == VAR_MCS22;
  localparam bit IS_MCS48 = VARIANT == VAR_MCS48;
  localparam bit IS_MCS22 = VARIANT == VAR_MCS22;
  localparam bit HAS_BUS  = IS_MCS48 && INCLUDE_BUS == 1;
  localparam bit HAS_TIM  = !IS_MCS48 || INCLUDE_TIMER == 1;
  localparam bit HAS_P1   = !IS_MCS48 || INCLUDE_PORT1 == 1;
  localparam bit HAS_P2   = !IS_MCS48 || INCLUDE_PORT2 == 1;

  logic [7:0]  t48_data;
  logic        xtal_en_s, t0_s, t1_s, en_clk;
  // module data outputs (0xFF when idle, AND-ed onto the internal bus)
  logic [7:0]  alu_data, bus_data, dec_data, dm_data, pm_data, p0_data, p1_data, p2_data;
  logic [7:0]  psw_data, tim_data, adc_data;
  // control
  logic        alu_write_accu, alu_write_shadow, alu_write_temp_reg, alu_read_alu;
  logic        alu_carry, alu_aux_carry, alu_use_carry, alu_da_high, alu_da_overflow;
  logic        alu_accu_low, alu_p06, alu_p60, alu_add_inc, alu_add_dec;
  logic [3:0]  alu_op;
  logic [7:0]  accu;
  logic        bus_write_bus, bus_read_bus, bus_output_pcl, bus_bidir_bus;
  logic        bus_ibf, bus_obf, bus_int_n, bus_set_f1, bus_clear_f1, bus_ibf_int;
  logic        bus_en_dma, bus_en_flags, bus_write_sts, bus_mint_ibf_n, bus_mint_obf;
  logic        bus_dma, bus_drq;
  logic        clk_multi_cycle, clk_assert_psen, clk_assert_prog, clk_assert_rd, clk_assert_wr;
  logic [2:0]  clk_mstate;
  logic        clk_second_cycle, psen_s, prog_s, rd_s, wr_s, ale_s, xtal3_s;
  logic        cnd_compute_take, cnd_take_branch, cnd_f1, cnd_tf;
  logic [3:0]  cnd_branch_cond;
  logic [2:0]  cnd_comp_value;
  logic        dm_write_dmem_addr, dm_write_dmem, dm_read_dmem;
  logic [1:0]  dm_addr_type;
  logic        p0_write_p0, p0_read_p0;
  logic        p1_write_p1, p1_read_p1, p1_read_reg;
  logic        p2_write_p2, p2_write_exp, p2_read_p2, p2_read_reg, p2_read_exp, p2_output_pch;
  logic [7:0]  p2_core_in, p2_core_out;
  logic        pm_write_pcl, pm_read_pcl, pm_write_pch, pm_read_pch, pm_read_pmem, pm_inc_pc;
  logic        pm_write_pmem_addr;
  logic [1:0]  pm_addr_type;
  logic [11:0] pmem_addr_s, pc;
  logic        psw_read_psw, psw_read_sp, psw_write_psw, psw_write_sp, psw_special_data;
  logic        psw_carry, psw_aux_carry, psw_f0, psw_bs;
  logic        psw_inc_stackp, psw_dec_stackp, psw_write_carry, psw_write_aux_carry;
  logic        psw_write_f0, psw_write_bs;
  logic [2:0]  sp;
  logic        tim_overflow, tim_read_timer, tim_write_timer, tim_start_t, tim_start_cnt;
  logic        tim_stop_tcnt;
  logic        adc_sel_an0, adc_sel_an1, adc_read_adc;
  logic        dec_int_n, cnd_int_n, mb, istrobe;

  assign en_clk = en_clk_i;

  // 8021 / 8022: one extra XTAL/2 stage
  generate
    if (IS_MCS2X) begin : g_xtal2
      logic xtal_mcs2x_q;
      always_ff @(posedge xtal_i or negedge reset_i)
        if (!reset_i)       xtal_mcs2x_q <= 1'b0;
        else if (xtal_en_i) xtal_mcs2x_q <= ~xtal_mcs2x_q;
      assign xtal_en_s = xtal_en_i & xtal_mcs2x_q;
    end else begin : g_xtal1
      assign xtal_en_s = xtal_en_i;
    end
  endgenerate

  assign t0_s      = (VARIANT == VAR_MCS21) ? 1'b0 : t0_i;
  assign t1_s      = t1_i;
  assign cnd_int_n = IS_UPI ? bus_int_n : IS_MCS2X ? 1'b1 : int_n_i;
  assign dec_int_n = IS_UPI ? bus_int_n : (VARIANT == VAR_MCS21) ? 1'b1 : IS_MCS22 ? t0_s : int_n_i;

  assign t48_data = alu_data & bus_data & dec_data & dm_data & pm_data & p0_data & p1_data &
                    p2_data & psw_data & tim_data & adc_data;

  t48sv_alu alu_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(alu_data),
    .write_accu_i(alu_write_accu), .write_shadow_i(alu_write_shadow),
    .write_temp_reg_i(alu_write_temp_reg), .read_alu_i(alu_read_alu), .carry_i(psw_carry),
    .carry_o(alu_carry), .aux_carry_o(alu_aux_carry), .alu_op_i(alu_op),
    .use_carry_i(alu_use_carry), .add_inc_i(alu_add_inc), .add_dec_i(alu_add_dec),
    .da_high_i(alu_da_high), .da_overflow_o(alu_da_overflow),
    .accu_low_i(alu_accu_low), .p06_temp_reg_i(alu_p06), .p60_temp_reg_i(alu_p60), .accu_o(accu)
  );

  t48sv_clock_ctrl #(.XTAL_DIV_3(XTAL_DIV_3)) clock_ctrl_b (
    .clk_i(clk_i), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s), .res_n_i(reset_i), .en_clk_i(en_clk),
    .xtal3_o(xtal3_s), .t0_o(t0_o), .multi_cycle_i(clk_multi_cycle),
    .assert_psen_i(clk_assert_psen), .assert_prog_i(clk_assert_prog),
    .assert_rd_i(clk_assert_rd), .assert_wr_i(clk_assert_wr), .mstate_o(clk_mstate),
    .second_cycle_o(clk_second_cycle), .ale_o(ale_s), .psen_o(psen_s), .prog_o(prog_s),
    .rd_o(rd_s), .wr_o(wr_s)
  );

  t48sv_cond_branch cond_branch_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .compute_take_i(cnd_compute_take),
    .branch_cond_i(cnd_branch_cond), .take_branch_o(cnd_take_branch), .accu_i(alu_data),
    .t0_i(t0_s), .t1_i(t1_s), .int_n_i(cnd_int_n), .f0_i(psw_f0), .f1_i(cnd_f1), .tf_i(cnd_tf),
    .carry_i(psw_carry), .ibf_i(IS_UPI ? bus_ibf : 1'b0), .obf_i(IS_UPI ? bus_obf : 1'b0),
    .comp_value_i(cnd_comp_value)
  );

  generate
    if (IS_UPI) begin : g_upi_bus
      t48sv_upi_db_bus #(.TYPE_A(1), .IBF_ACK(UPI_IBF_ACK)) db_bus_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(bus_data),
        .write_bus_i(bus_write_bus), .read_bus_i(bus_read_bus), .write_sts_i(bus_write_sts),
        .set_f1_o(bus_set_f1), .clear_f1_o(bus_clear_f1), .f0_i(psw_f0), .f1_i(cnd_f1),
        .ibf_o(bus_ibf), .obf_o(bus_obf), .int_n_o(bus_int_n), .ibf_int_i(bus_ibf_int),
        .en_dma_i(bus_en_dma), .en_flags_i(bus_en_flags), .write_p2_i(p2_write_p2),
        .mint_ibf_n_o(bus_mint_ibf_n), .mint_obf_o(bus_mint_obf), .dma_o(bus_dma), .drq_o(bus_drq),
        .dack_n_i(p2_i[7]), .a0_i(a0_i), .cs_n_i(cs_n_i), .rd_n_i(rd_n_i), .wr_n_i(wr_n_i),
        .db_i(db_i), .db_o(db_o), .sts_o(sts_o), .db_dir_o(db_dir_o)
      );
    end else begin : g_no_upi_bus
      assign {bus_ibf, bus_obf, bus_set_f1, bus_clear_f1, bus_mint_obf, bus_dma, bus_drq} = '0;
      assign bus_int_n      = 1'b1;
      assign bus_mint_ibf_n = 1'b1;
      assign sts_o          = 8'h00;
      if (HAS_BUS) begin : g_bus
        t48sv_db_bus db_bus_b (
          .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .ea_i(ea_i), .data_i(t48_data),
          .data_o(bus_data), .write_bus_i(bus_write_bus), .read_bus_i(bus_read_bus),
          .output_pcl_i(bus_output_pcl), .bidir_bus_i(bus_bidir_bus), .pcl_i(pmem_addr_s[7:0]),
          .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o)
        );
      end else begin : g_no_bus
        assign bus_data = 8'hFF;
        assign db_o     = 8'h00;
        assign db_dir_o = 1'b0;
      end
    end
  endgenerate

  t48sv_decoder #(
    .REGISTER_MNEMONIC(REGISTER_MNEMONIC), .VARIANT(VARIANT), .UPI_TYPE_A(UPI_TYPE_A),
    .REV2023(REV2023)
  ) decoder_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s),
    .ea_i(IS_MCS48 ? ea_i : 1'b0), .ale_i(ale_s), .int_n_i(dec_int_n), .t0_dir_o(t0_dir_o),
    .data_i(t48_data), .data_o(dec_data),
    .alu_write_accu_o(alu_write_accu), .alu_write_shadow_o(alu_write_shadow),
    .alu_write_temp_reg_o(alu_write_temp_reg), .alu_read_alu_o(alu_read_alu),
    .bus_write_bus_o(bus_write_bus), .bus_read_bus_o(bus_read_bus),
    .bus_set_f1_i(bus_set_f1), .bus_clear_f1_i(bus_clear_f1), .bus_ibf_int_o(bus_ibf_int),
    .bus_en_dma_o(bus_en_dma), .bus_en_flags_o(bus_en_flags), .bus_write_sts_o(bus_write_sts),
    .dm_write_dmem_addr_o(dm_write_dmem_addr), .dm_write_dmem_o(dm_write_dmem),
    .dm_read_dmem_o(dm_read_dmem), .p0_write_p0_o(p0_write_p0), .p0_read_p0_o(p0_read_p0),
    .p1_write_p1_o(p1_write_p1), .p1_read_p1_o(p1_read_p1), .p2_write_p2_o(p2_write_p2),
    .p2_write_exp_o(p2_write_exp), .p2_read_p2_o(p2_read_p2), .p2_read_exp_o(p2_read_exp),
    .pm_write_pcl_o(pm_write_pcl), .pm_read_pcl_o(pm_read_pcl), .pm_write_pch_o(pm_write_pch),
    .pm_read_pch_o(pm_read_pch), .pm_read_pmem_o(pm_read_pmem),
    .psw_read_psw_o(psw_read_psw), .psw_read_sp_o(psw_read_sp), .psw_write_psw_o(psw_write_psw),
    .psw_write_sp_o(psw_write_sp), .alu_carry_i(alu_carry), .alu_op_o(alu_op),
    .alu_use_carry_o(alu_use_carry), .alu_add_inc_o(alu_add_inc), .alu_add_dec_o(alu_add_dec), .alu_da_high_o(alu_da_high), .alu_accu_low_o(alu_accu_low),
    .alu_p06_temp_reg_o(alu_p06), .alu_p60_temp_reg_o(alu_p60),
    .alu_da_overflow_i(alu_da_overflow), .bus_output_pcl_o(bus_output_pcl),
    .bus_bidir_bus_o(bus_bidir_bus), .clk_multi_cycle_o(clk_multi_cycle),
    .clk_assert_psen_o(clk_assert_psen), .clk_assert_prog_o(clk_assert_prog),
    .clk_assert_rd_o(clk_assert_rd), .clk_assert_wr_o(clk_assert_wr),
    .clk_mstate_i(clk_mstate), .clk_second_cycle_i(clk_second_cycle),
    .cnd_compute_take_o(cnd_compute_take), .cnd_branch_cond_o(cnd_branch_cond),
    .cnd_take_branch_i(cnd_take_branch), .cnd_comp_value_o(cnd_comp_value), .cnd_f1_o(cnd_f1),
    .cnd_tf_o(cnd_tf), .dm_addr_type_o(dm_addr_type), .p1_read_reg_o(p1_read_reg),
    .p2_read_reg_o(p2_read_reg), .p2_output_pch_o(p2_output_pch), .pm_inc_pc_o(pm_inc_pc),
    .pm_write_pmem_addr_o(pm_write_pmem_addr), .pm_addr_type_o(pm_addr_type),
    .psw_special_data_o(psw_special_data), .psw_carry_i(psw_carry),
    .psw_aux_carry_i(psw_aux_carry), .psw_f0_i(psw_f0), .psw_inc_stackp_o(psw_inc_stackp),
    .psw_dec_stackp_o(psw_dec_stackp), .psw_write_carry_o(psw_write_carry),
    .psw_write_aux_carry_o(psw_write_aux_carry), .psw_write_f0_o(psw_write_f0),
    .psw_write_bs_o(psw_write_bs), .tim_read_timer_o(tim_read_timer),
    .tim_write_timer_o(tim_write_timer), .tim_start_t_o(tim_start_t),
    .tim_start_cnt_o(tim_start_cnt), .tim_stop_tcnt_o(tim_stop_tcnt),
    .tim_overflow_i(tim_overflow), .adc_sel_an0_o(adc_sel_an0), .adc_sel_an1_o(adc_sel_an1),
    .adc_read_adc_o(adc_read_adc), .mb_o(mb), .istrobe_o(istrobe)
  );

  t48sv_dmem_ctrl dmem_ctrl_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data),
    .write_dmem_addr_i(dm_write_dmem_addr), .write_dmem_i(dm_write_dmem),
    .read_dmem_i(dm_read_dmem), .addr_type_i(dm_addr_type), .bank_select_i(psw_bs),
    .data_o(dm_data), .dmem_data_i(dmem_data_i), .dmem_addr_o(dmem_addr_o),
    .dmem_we_o(dmem_we_o), .dmem_data_o(dmem_data_o)
  );

  generate
    if (HAS_TIM) begin : g_timer
      t48sv_timer #(.SAMPLE_T1_STATE(SAMPLE_T1_STATE)) timer_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .t1_i(t1_s), .mstate_i(clk_mstate),
        .data_i(t48_data), .data_o(tim_data), .read_timer_i(tim_read_timer),
        .write_timer_i(tim_write_timer), .start_t_i(tim_start_t), .start_cnt_i(tim_start_cnt),
        .stop_tcnt_i(tim_stop_tcnt), .overflow_o(tim_overflow)
      );
    end else begin : g_no_timer
      assign tim_data     = 8'hFF;
      assign tim_overflow = 1'b0;
    end

    if (IS_MCS2X) begin : g_p0
      t48sv_port p0_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(p0_data),
        .write_i(p0_write_p0), .read_i(p0_read_p0), .read_reg_i(1'b0), .port_i(p0_i),
        .port_o(p0_o), .low_imp_o()
      );
    end else begin : g_no_p0
      assign p0_data = 8'hFF;
      assign p0_o    = 8'h00;
    end

    if (HAS_P1) begin : g_p1
      t48sv_port p1_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(p1_data),
        .write_i(p1_write_p1), .read_i(p1_read_p1), .read_reg_i(IS_MCS2X ? 1'b0 : p1_read_reg),
        .port_i(p1_i), .port_o(p1_o), .low_imp_o(p1_low_imp_o)
      );
    end else begin : g_no_p1
      assign p1_data      = 8'hFF;
      assign p1_o         = 8'h00;
      assign p1_low_imp_o = 1'b0;
    end

    if (HAS_P2) begin : g_p2
      t48sv_p2 p2_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .xtal_i(xtal_i), .xtal_en_i(xtal_en_s),
        .data_i(t48_data), .data_o(p2_data), .write_p2_i(p2_write_p2), .write_exp_i(p2_write_exp),
        .read_p2_i(p2_read_p2), .read_reg_i(IS_MCS2X ? 1'b0 : p2_read_reg),
        .read_exp_i(p2_read_exp), .output_pch_i(p2_output_pch), .pch_i(pmem_addr_s[11:8]),
        .p2_i(p2_core_in), .p2_o(p2_core_out), .p2l_low_imp_o(p2l_low_imp_o),
        .p2h_low_imp_o(p2h_low_imp_o)
      );
    end else begin : g_no_p2
      assign p2_data       = 8'hFF;
      assign p2_core_out   = 8'h00;
      assign p2l_low_imp_o = 1'b0;
      assign p2h_low_imp_o = 1'b0;
    end

    if (IS_MCS22) begin : g_adc
      t48sv_adc adc_b (
        .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .ale_i(ale_s), .mstate_i(clk_mstate),
        .sel_an0_i(adc_sel_an0), .sel_an1_i(adc_sel_an1), .read_adc_i(adc_read_adc),
        .data_o(adc_data), .sel_an_o(adc_sel_an_o), .sh_o(adc_sh_o), .sar_o(adc_sar_o),
        .comp_i(adc_comp_i)
      );
    end else begin : g_no_adc
      assign adc_data     = 8'hFF;
      assign adc_sel_an_o = 1'b0;
      assign adc_sh_o     = 1'b0;
      assign adc_sar_o    = 8'h00;
    end
  endgenerate

  // 8021: 4-bit P2; UPI-41A: P24..P27 carry OBF / IBF / DRQ when enabled
  assign p2_core_in = (VARIANT == VAR_MCS21) ? {4'h0, p2_i[3:0]} : p2_i;
  assign p2_o = (VARIANT == VAR_MCS21) ? {4'h0, p2_core_out[3:0]} :
                IS_UPI ? {p2_core_out[7], bus_dma ? bus_drq : p2_core_out[6],
                          p2_core_out[5] & bus_mint_ibf_n, p2_core_out[4] & bus_mint_obf,
                          p2_core_out[3:0]} :
                p2_core_out;

  t48sv_pmem_ctrl pmem_ctrl_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(pm_data),
    .write_pcl_i(pm_write_pcl), .read_pcl_i(pm_read_pcl), .write_pch_i(pm_write_pch),
    .read_pch_i(pm_read_pch), .inc_pc_i(pm_inc_pc), .write_pmem_addr_i(pm_write_pmem_addr),
    .addr_type_i(pm_addr_type), .read_pmem_i(pm_read_pmem), .pmem_addr_o(pmem_addr_s), .pc_o(pc),
    .pmem_data_i(pmem_data_i)
  );

  t48sv_psw psw_b (
    .clk_i(clk_i), .res_n_i(reset_i), .en_clk_i(en_clk), .data_i(t48_data), .data_o(psw_data),
    .read_psw_i(psw_read_psw), .read_sp_i(psw_read_sp), .write_psw_i(psw_write_psw),
    .write_sp_i(psw_write_sp), .special_data_i(psw_special_data), .inc_stackp_i(psw_inc_stackp),
    .dec_stackp_i(psw_dec_stackp), .write_carry_i(psw_write_carry),
    .write_aux_carry_i(psw_write_aux_carry), .write_f0_i(psw_write_f0), .write_bs_i(psw_write_bs),
    .carry_o(psw_carry), .aux_carry_i(alu_aux_carry), .aux_carry_o(psw_aux_carry), .f0_o(psw_f0),
    .bs_o(psw_bs), .sp_o(sp)
  );

  assign ale_o       = ale_s;
  assign psen_n_o    = (IS_MCS48) ? ~psen_s : 1'b1;
  assign prog_n_o    = ~prog_s;
  assign rd_n_o      = (IS_MCS48) ? ~rd_s : 1'b1;
  assign wr_n_o      = (IS_MCS48) ? ~wr_s : 1'b1;
  assign xtal3_o     = xtal3_s;
  assign pmem_addr_o = pmem_addr_s;

endmodule

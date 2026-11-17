// ============================================================================
// t48sv instruction decoder, machine-cycle control and interrupt controller
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

module t48sv_decoder #(
  parameter int REGISTER_MNEMONIC = 1,
  parameter int VARIANT           = 0,  // 0 MCS-48, 1 UPI-41, 2 MCS-21, 3 MCS-22
  parameter int UPI_TYPE_A        = 0,
  parameter int REV2023           = 0
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       ea_i,
  input  logic       ale_i,
  input  logic       int_n_i,
  output logic       t0_dir_o,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  output logic       alu_write_accu_o,
  output logic       alu_write_shadow_o,
  output logic       alu_write_temp_reg_o,
  output logic       alu_read_alu_o,
  output logic       bus_write_bus_o,
  output logic       bus_read_bus_o,
  input  logic       bus_set_f1_i,
  input  logic       bus_clear_f1_i,
  output logic       bus_ibf_int_o,
  output logic       bus_en_dma_o,
  output logic       bus_en_flags_o,
  output logic       bus_write_sts_o,
  output logic       dm_write_dmem_addr_o,
  output logic       dm_write_dmem_o,
  output logic       dm_read_dmem_o,
  output logic       p0_write_p0_o,
  output logic       p0_read_p0_o,
  output logic       p1_write_p1_o,
  output logic       p1_read_p1_o,
  output logic       p2_write_p2_o,
  output logic       p2_write_exp_o,
  output logic       p2_read_p2_o,
  output logic       p2_read_exp_o,
  output logic       pm_write_pcl_o,
  output logic       pm_read_pcl_o,
  output logic       pm_write_pch_o,
  output logic       pm_read_pch_o,
  output logic       pm_read_pmem_o,
  output logic       psw_read_psw_o,
  output logic       psw_read_sp_o,
  output logic       psw_write_psw_o,
  output logic       psw_write_sp_o,
  input  logic       alu_carry_i,
  output logic [3:0] alu_op_o,
  output logic       alu_use_carry_o,
  output logic       alu_add_inc_o,
  output logic       alu_add_dec_o,
  output logic       alu_da_high_o,
  output logic       alu_accu_low_o,
  output logic       alu_p06_temp_reg_o,
  output logic       alu_p60_temp_reg_o,
  input  logic       alu_da_overflow_i,
  output logic       bus_output_pcl_o,
  output logic       bus_bidir_bus_o,
  output logic       clk_multi_cycle_o,
  output logic       clk_assert_psen_o,
  output logic       clk_assert_prog_o,
  output logic       clk_assert_rd_o,
  output logic       clk_assert_wr_o,
  input  logic [2:0] clk_mstate_i,
  input  logic       clk_second_cycle_i,
  output logic       cnd_compute_take_o,
  output logic [3:0] cnd_branch_cond_o,
  input  logic       cnd_take_branch_i,
  output logic [2:0] cnd_comp_value_o,
  output logic       cnd_f1_o,
  output logic       cnd_tf_o,
  output logic [1:0] dm_addr_type_o,
  output logic       p1_read_reg_o,
  output logic       p2_read_reg_o,
  output logic       p2_output_pch_o,
  output logic       pm_inc_pc_o,
  output logic       pm_write_pmem_addr_o,
  output logic [1:0] pm_addr_type_o,
  output logic       psw_special_data_o,
  input  logic       psw_carry_i,
  input  logic       psw_aux_carry_i,
  input  logic       psw_f0_i,
  output logic       psw_inc_stackp_o,
  output logic       psw_dec_stackp_o,
  output logic       psw_write_carry_o,
  output logic       psw_write_aux_carry_o,
  output logic       psw_write_f0_o,
  output logic       psw_write_bs_o,
  output logic       tim_read_timer_o,
  output logic       tim_write_timer_o,
  output logic       tim_start_t_o,
  output logic       tim_start_cnt_o,
  output logic       tim_stop_tcnt_o,
  input  logic       tim_overflow_i,
  output logic       adc_sel_an0_o,
  output logic       adc_sel_an1_o,
  output logic       adc_read_adc_o,
  output logic       mb_o,
  output logic       istrobe_o
);

  localparam logic [2:0] M1 = 3'd0, M2 = 3'd1, M3 = 3'd2, M4 = 3'd3, M5 = 3'd4;
  localparam int VAR_MCS48 = 0, VAR_UPI41 = 1, VAR_MCS21 = 2, VAR_MCS22 = 3;
  localparam logic [3:0] ALU_AND = 4'd0, ALU_OR = 4'd1, ALU_XOR = 4'd2, ALU_CPL = 4'd3,
                         ALU_CLR = 4'd4, ALU_RL = 4'd5, ALU_RR = 4'd6, ALU_SWAP = 4'd7,
                         ALU_DEC = 4'd8, ALU_INC = 4'd9, ALU_ADD = 4'd10, ALU_CONCAT = 4'd11,
                         ALU_NOP = 4'd12, COND_ON_BIT = 4'd0, COND_Z = 4'd1, COND_C = 4'd2,
                         COND_F0 = 4'd3, COND_F1 = 4'd4, COND_INT = 4'd5, COND_T0 = 4'd6,
                         COND_T1 = 4'd7, COND_TF = 4'd8, COND_NIBF = 4'd9, COND_OBF = 4'd10;
  localparam logic [1:0] DM_PLAIN = 2'd0, DM_REG = 2'd1, DM_STACK = 2'd2, DM_STACK_HIGH = 2'd3,
                         PM_PC = 2'd0, PM_PAGE = 2'd1, PM_PAGE3 = 2'd2;

  localparam bit IS_UPI   = VARIANT == VAR_UPI41;
  localparam bit IS_MCS2X = VARIANT == VAR_MCS21 || VARIANT == VAR_MCS22;
  localparam bit IS_MCS22 = VARIANT == VAR_MCS22;

  // mnemonics
  localparam logic [6:0]
    MN_ADD = 7'd1, MN_ADD_A_DATA = 7'd2, MN_ANL = 7'd3, MN_ANL_A_DATA = 7'd4, MN_ANL_EXT = 7'd5,
    MN_CALL = 7'd6, MN_CLR_A = 7'd7, MN_CLR_C = 7'd8, MN_CLR_F = 7'd9, MN_CPL_A = 7'd10,
    MN_CPL_C = 7'd11, MN_CPL_F = 7'd12, MN_DA = 7'd13, MN_DEC = 7'd14, MN_DIS_EN_I = 7'd15,
    MN_DIS_EN_TCNTI = 7'd16, MN_DJNZ = 7'd17, MN_ENT0_CLK = 7'd18, MN_IN = 7'd19, MN_INC = 7'd20,
    MN_INS = 7'd21, MN_JBB = 7'd22, MN_JC = 7'd23, MN_JF = 7'd24, MN_JMP = 7'd25, MN_JMPP = 7'd26,
    MN_JNI = 7'd27, MN_JT = 7'd28, MN_JTF = 7'd29, MN_JZ = 7'd30, MN_MOV_A_DATA = 7'd31,
    MN_MOV_A_PSW = 7'd32, MN_MOV_A_RR = 7'd33, MN_MOV_PSW_A = 7'd34, MN_MOV_RR = 7'd35,
    MN_MOV_RR_DATA = 7'd36, MN_MOV_T = 7'd37, MN_MOVD_A_PP = 7'd38, MN_MOVP = 7'd39, MN_MOVX = 7'd40,
    MN_NOP = 7'd41, MN_ORL = 7'd42, MN_ORL_A_DATA = 7'd43, MN_ORL_EXT = 7'd44, MN_OUTD_PP_A = 7'd45,
    MN_OUTL_EXT = 7'd46, MN_RET = 7'd47, MN_RETR = 7'd48, MN_RL = 7'd49, MN_RR = 7'd50,
    MN_SEL_MB = 7'd51, MN_SEL_RB = 7'd52, MN_STOP_TCNT = 7'd53, MN_STRT = 7'd54, MN_SWAP = 7'd55,
    MN_XCH = 7'd56, MN_XRL = 7'd57, MN_XRL_A_DATA = 7'd58, MN_IN_DBB = 7'd59, MN_OUT_DBB = 7'd60,
    MN_JNIBF = 7'd61, MN_JOBF = 7'd62, MN_EN_DMA_FLAGS = 7'd63, MN_MOV_STS = 7'd64,
    MN_IN_P0 = 7'd65, MN_OUTL_P0 = 7'd66, MN_RAD = 7'd67, MN_RETI = 7'd68, MN_SEL_AN = 7'd69;

  localparam bit IS_48    = VARIANT == VAR_MCS48;
  localparam bit IS_48UPI = IS_48 || IS_UPI;
  localparam bit IS_UPIA  = IS_UPI && UPI_TYPE_A == 1;

  // opcode -> {mnemonic, multi_cycle}; one flat table, variant columns fold away
  function automatic logic [7:0] decode(input logic [7:0] op);
    logic [6:0] m;
    logic       c;
    m = MN_NOP;
    c = 1'b0;
    casez (op)
      // ---- all variants
      8'b0110_1???, 8'b0110_000?, 8'b0111_1???, 8'b0111_000?: m = MN_ADD;
      8'h03, 8'h13:                         begin m = MN_ADD_A_DATA; c = 1'b1; end
      8'b0101_1???, 8'b0101_000?:           m = MN_ANL;
      8'h53:                                begin m = MN_ANL_A_DATA; c = 1'b1; end
      8'b???1_0100:                         begin m = MN_CALL; c = 1'b1; end
      8'h27:                                m = MN_CLR_A;
      8'h97:                                m = MN_CLR_C;
      8'h37:                                m = MN_CPL_A;
      8'hA7:                                m = MN_CPL_C;
      8'h57:                                m = MN_DA;
      8'h07:                                m = MN_DEC;
      8'b1110_1???:                         begin m = MN_DJNZ; c = 1'b1; end
      8'h09, 8'h0A:                         begin m = MN_IN; c = 1'b1; end
      8'h17, 8'b0001_1???, 8'b0001_000?:    m = MN_INC;
      8'hF6, 8'hE6:                         begin m = MN_JC; c = 1'b1; end
      8'b???0_0100:                         begin m = MN_JMP; c = 1'b1; end
      8'hB3:                                begin m = MN_JMPP; c = 1'b1; end
      8'h16:                                begin m = MN_JTF; c = 1'b1; end
      8'h96, 8'hC6:                         begin m = MN_JZ; c = 1'b1; end
      8'h23:                                begin m = MN_MOV_A_DATA; c = 1'b1; end
      8'b1111_1???, 8'b1111_000?:           m = MN_MOV_A_RR;
      8'b1010_1???, 8'b1010_000?:           m = MN_MOV_RR;
      8'b1011_1???, 8'b1011_000?:           begin m = MN_MOV_RR_DATA; c = 1'b1; end
      8'h62, 8'h42:                         m = MN_MOV_T;
      8'b0000_11??:                         begin m = MN_MOVD_A_PP; c = 1'b1; end
      8'hA3:                                begin m = MN_MOVP; c = 1'b1; end
      8'b0100_1???, 8'b0100_000?:           m = MN_ORL;
      8'h43:                                begin m = MN_ORL_A_DATA; c = 1'b1; end
      8'b0011_11??, 8'b1001_11??, 8'b1000_11??: begin m = MN_OUTD_PP_A; c = 1'b1; end
      8'h39, 8'h3A:                         begin m = MN_OUTL_EXT; c = 1'b1; end
      8'h83:                                begin m = MN_RET; c = 1'b1; end
      8'hE7, 8'hF7:                         m = MN_RL;
      8'h77, 8'h67:                         m = MN_RR;
      8'h65:                                m = MN_STOP_TCNT;
      8'h45, 8'h55:                         m = MN_STRT;
      8'h47:                                m = MN_SWAP;
      8'b0010_1???, 8'b0010_000?, 8'b0011_000?: m = MN_XCH;
      8'b1101_1???, 8'b1101_000?:           m = MN_XRL;
      8'hD3:                                begin m = MN_XRL_A_DATA; c = 1'b1; end
      // ---- variant specific
      8'h99, 8'h9A, 8'h98:  if (IS_48UPI && (op != 8'h98 || IS_48)) begin m = MN_ANL_EXT; c = 1'b1; end
      8'h89, 8'h8A, 8'h88:  if (IS_48UPI && (op != 8'h88 || IS_48)) begin m = MN_ORL_EXT; c = 1'b1; end
      8'hA5, 8'hB5:         if (IS_48UPI) m = op[4] ? MN_CPL_F : MN_CLR_F;
      8'h85, 8'h95:         if (IS_48UPI) m = op[4] ? MN_CPL_F : MN_CLR_F;
                            else if (IS_MCS22) m = MN_SEL_AN;
      8'b1100_1???:         if (IS_48UPI) m = MN_DEC;
      8'h05, 8'h15:         if (IS_48UPI || IS_MCS22) m = MN_DIS_EN_I;
      8'h25, 8'h35:         if (IS_48UPI || IS_MCS22) m = MN_DIS_EN_TCNTI;
      8'b???1_0010:         if (IS_48UPI) begin m = MN_JBB; c = 1'b1; end
      8'hB6, 8'h76:         if (IS_48UPI) begin m = MN_JF; c = 1'b1; end
      8'h46, 8'h56:         begin m = MN_JT; c = 1'b1; end
      8'h26, 8'h36:         if (IS_48UPI || IS_MCS22) begin m = MN_JT; c = 1'b1; end
      8'hC7:                if (IS_48UPI) m = MN_MOV_A_PSW;
      8'hD7:                if (IS_48UPI) m = MN_MOV_PSW_A;
      8'hE3:                if (IS_48UPI) begin m = MN_MOVP; c = 1'b1; end
      8'h93:                if (IS_48UPI) begin m = MN_RETR; c = 1'b1; end
                            else if (IS_MCS22) begin m = MN_RETI; c = 1'b1; end
      8'hC5, 8'hD5:         if (IS_48UPI) m = MN_SEL_RB;
      8'h75:                if (IS_48) m = MN_ENT0_CLK;
      8'h08:                if (IS_48) begin m = MN_INS; c = 1'b1; end
                            else if (IS_MCS2X) begin m = MN_IN_P0; c = 1'b1; end
      8'h86:                if (IS_48) begin m = MN_JNI; c = 1'b1; end
                            else if (IS_UPI) begin m = MN_JOBF; c = 1'b1; end
      8'h80:                if (IS_48) begin m = MN_MOVX; c = 1'b1; end
                            else if (IS_MCS22) begin m = MN_RAD; c = 1'b1; end
      8'h81, 8'h91:         if (IS_48) begin m = MN_MOVX; c = 1'b1; end
      8'h90:                if (IS_48) begin m = MN_MOVX; c = 1'b1; end
                            else if (IS_UPIA) m = MN_MOV_STS;
                            else if (IS_MCS2X) begin m = MN_OUTL_P0; c = 1'b1; end
      8'h02:                if (IS_48) begin m = MN_OUTL_EXT; c = 1'b1; end
                            else if (IS_UPI) m = MN_OUT_DBB;
      8'hE5, 8'hF5:         if (IS_48) m = MN_SEL_MB;
                            else if (IS_UPIA) m = MN_EN_DMA_FLAGS;
      8'h22:                if (IS_UPI) m = MN_IN_DBB;
      8'hD6:                if (IS_UPI) begin m = MN_JNIBF; c = 1'b1; end
      default: ;
    endcase
    decode = {m, c};
  endfunction

  logic [7:0] opc_opcode_q;
  logic [7:0] mn_rec_s;
  logic [6:0] mnemonic_q, mn;
  logic       opc_multi_cycle_s, opc_read_bus_s, opc_inj_int_s;
  logic       last_cycle_s, assert_psen_s;
  logic       branch_taken_s, branch_taken_q;
  logic       pm_inc_pc_s, pm_write_pmem_addr_s, add_inc_pc_s, add_write_pmem_addr_s;
  logic       clear_f1_s, cpl_f1_s, f1_q;
  logic       clear_mb_s, set_mb_s, mb_q, mb_v;
  logic       ent0_clk_s, t0_dir_q;
  logic [7:0] data_s;
  logic       read_dec_s;
  logic       bus_read_bus_s, add_read_bus_s, dm_write_dmem_s;
  logic       p2_output_exp_s, movx_first_cycle_s;
  logic       jtf_executed_s, en_tcnti_s, dis_tcnti_s, en_i_s, dis_i_s;
  logic       retr_executed_s, int_executed_s;
  logic       injected_int_q, istrobe_res_q, istrobe_q;
  logic       need_address_v;
  // interrupt controller
  logic [1:0] int_state_q, int_state_s;   // 0 idle, 1 pending, 2 int
  logic       timer_flag_q, timer_overflow_q, timer_int_enable_q, int_enable_q;
  logic       int_q, ale_q, int_type_q, int_in_progress_q;
  logic       int_pending_s, int_in_progress_s, tim_int_s;

  assign mn_rec_s = decode(opc_opcode_q);

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      opc_opcode_q <= 8'h00;
      mnemonic_q   <= MN_NOP;
    end else if (en_clk_i) begin
      if (opc_read_bus_s)     opc_opcode_q <= data_i;
      else if (opc_inj_int_s) opc_opcode_q <= 8'h14;
      else                    mnemonic_q   <= mn_rec_s[7:1];
    end

  assign opc_multi_cycle_s = mn_rec_s[0];
  assign mn                = (REGISTER_MNEMONIC == 1) ? mnemonic_q : mn_rec_s[7:1];
  assign last_cycle_s      = ~opc_multi_cycle_s | clk_second_cycle_i;

  // --------------------------------------------------------------------------
  // machine cycle: opcode fetch, PC increment, external program memory
  // --------------------------------------------------------------------------
  always_comb begin
    clk_assert_psen_o    = 1'b0;
    pm_inc_pc_s          = 1'b0;
    pm_write_pmem_addr_s = 1'b0;
    pm_read_pmem_o       = 1'b0;
    bus_output_pcl_o     = 1'b0;
    p2_output_pch_o      = 1'b0;
    opc_read_bus_s       = 1'b0;
    opc_inj_int_s        = 1'b0;
    bus_read_bus_s       = 1'b0;
    need_address_v       = ~clk_second_cycle_i | assert_psen_s;
    case (clk_mstate_i)
      M1: begin
        if (need_address_v) begin
          if (!ea_i) begin
            if (!int_pending_s) pm_read_pmem_o = 1'b1;
          end else begin
            if (!int_pending_s) bus_read_bus_s = 1'b1;
            p2_output_pch_o = 1'b1;
          end
        end
        if (!clk_second_cycle_i) begin
          if (!int_pending_s) opc_read_bus_s = 1'b1;
          else                opc_inj_int_s  = 1'b1;
        end
      end
      M2: if (need_address_v && !branch_taken_q && !int_pending_s) pm_inc_pc_s = 1'b1;
      M3: if (need_address_v) pm_write_pmem_addr_s = 1'b1;
      M4: if (ea_i && ((!clk_second_cycle_i && assert_psen_s) || last_cycle_s)) begin
            clk_assert_psen_o = 1'b1;
            p2_output_pch_o   = 1'b1;
            bus_output_pcl_o  = 1'b1;
          end
      M5: if (ea_i && (need_address_v || last_cycle_s) && !p2_output_exp_s && !movx_first_cycle_s)
            p2_output_pch_o = 1'b1;
      default: ;
    endcase
  end

  // --------------------------------------------------------------------------
  // instruction decode
  // --------------------------------------------------------------------------
  always_comb begin
    data_s                = 8'h00;   // T48: '-', resolved to 0 as GHDL does
    read_dec_s            = 1'b0;
    branch_taken_s        = 1'b0;
    clear_f1_s            = 1'b0;
    cpl_f1_s              = 1'b0;
    clear_mb_s            = 1'b0;
    set_mb_s              = 1'b0;
    add_inc_pc_s          = 1'b0;
    assert_psen_s         = 1'b0;
    alu_write_accu_o      = 1'b0;
    alu_write_shadow_o    = 1'b0;
    alu_write_temp_reg_o  = 1'b0;
    alu_p06_temp_reg_o    = 1'b0;
    alu_p60_temp_reg_o    = 1'b0;
    alu_read_alu_o        = 1'b0;
    bus_write_bus_o       = 1'b0;
    bus_bidir_bus_o       = 1'b0;
    bus_ibf_int_o         = 1'b0;
    bus_en_dma_o          = 1'b0;
    bus_en_flags_o        = 1'b0;
    bus_write_sts_o       = 1'b0;
    dm_write_dmem_addr_o  = 1'b0;
    dm_write_dmem_s       = 1'b0;
    dm_read_dmem_o        = 1'b0;
    pm_write_pcl_o        = 1'b0;
    pm_read_pcl_o         = 1'b0;
    pm_write_pch_o        = 1'b0;
    pm_read_pch_o         = 1'b0;
    pm_addr_type_o        = PM_PC;
    psw_read_psw_o        = 1'b0;
    psw_read_sp_o         = 1'b0;
    psw_write_psw_o       = 1'b0;
    psw_write_sp_o        = 1'b0;
    alu_op_o              = ALU_NOP;
    alu_da_high_o         = 1'b0;
    alu_accu_low_o        = 1'b0;
    clk_assert_prog_o     = 1'b0;
    clk_assert_rd_o       = 1'b0;
    clk_assert_wr_o       = 1'b0;
    cnd_branch_cond_o     = COND_ON_BIT;
    cnd_compute_take_o    = 1'b0;
    cnd_comp_value_o      = opc_opcode_q[7:5];
    dm_addr_type_o        = DM_REG;
    tim_read_timer_o      = 1'b0;
    tim_write_timer_o     = 1'b0;
    tim_start_t_o         = 1'b0;
    tim_start_cnt_o       = 1'b0;
    tim_stop_tcnt_o       = 1'b0;
    p0_write_p0_o         = 1'b0;
    p0_read_p0_o          = 1'b0;
    p1_write_p1_o         = 1'b0;
    p1_read_p1_o          = 1'b0;
    p1_read_reg_o         = 1'b0;
    p2_write_p2_o         = 1'b0;
    p2_write_exp_o        = 1'b0;
    p2_read_p2_o          = 1'b0;
    p2_read_reg_o         = 1'b0;
    p2_read_exp_o         = 1'b0;
    p2_output_exp_s       = 1'b0;
    psw_special_data_o    = 1'b0;
    psw_inc_stackp_o      = 1'b0;
    psw_dec_stackp_o      = 1'b0;
    psw_write_carry_o     = 1'b0;
    psw_write_aux_carry_o = 1'b0;
    psw_write_f0_o        = 1'b0;
    psw_write_bs_o        = 1'b0;
    adc_sel_an0_o         = 1'b0;
    adc_sel_an1_o         = 1'b0;
    adc_read_adc_o        = 1'b0;
    jtf_executed_s        = 1'b0;
    en_tcnti_s            = 1'b0;
    dis_tcnti_s           = 1'b0;
    en_i_s                = 1'b0;
    dis_i_s               = 1'b0;
    retr_executed_s       = 1'b0;
    int_executed_s        = 1'b0;
    add_write_pmem_addr_s = 1'b0;
    ent0_clk_s            = 1'b0;
    add_read_bus_s        = 1'b0;
    movx_first_cycle_s    = 1'b0;

    mb_v = int_in_progress_s ? 1'b0 : mb_q;

    // register address for Rr / @Rr in M2 of every instruction
    if (!clk_second_cycle_i && clk_mstate_i == M2) begin
      data_s               = {5'b00000, opc_opcode_q[3] ? opc_opcode_q[2:1] : 2'b00, opc_opcode_q[0]};
      read_dec_s           = 1'b1;
      dm_write_dmem_addr_o = 1'b1;
      dm_addr_type_o       = DM_REG;
    end

    case (mn)
      // ---------------------------------------------------------- arithmetic
      MN_ADD, MN_ANL, MN_ORL, MN_XRL:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_temp_reg_o = 1'b1;
              end
          M5: begin
                alu_op_o         = (mn == MN_ADD) ? ALU_ADD : (mn == MN_ANL) ? ALU_AND :
                                   (mn == MN_ORL) ? ALU_OR : ALU_XOR;
                alu_read_alu_o   = 1'b1;
                alu_write_accu_o = 1'b1;
                if (mn == MN_ADD) begin
                  psw_special_data_o    = alu_carry_i;
                  psw_write_carry_o     = 1'b1;
                  psw_write_aux_carry_o = 1'b1;
                end
              end
          default: ;
        endcase

      MN_ADD_A_DATA, MN_ANL_A_DATA, MN_ORL_A_DATA, MN_XRL_A_DATA: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i)
          case (clk_mstate_i)
            M1: alu_write_temp_reg_o = 1'b1;
            M3: begin
                  alu_op_o         = (mn == MN_ADD_A_DATA) ? ALU_ADD : (mn == MN_ANL_A_DATA) ? ALU_AND :
                                     (mn == MN_ORL_A_DATA) ? ALU_OR : ALU_XOR;
                  alu_read_alu_o   = 1'b1;
                  alu_write_accu_o = 1'b1;
                  if (mn == MN_ADD_A_DATA) begin
                      psw_special_data_o    = alu_carry_i;
                    psw_write_carry_o     = 1'b1;
                    psw_write_aux_carry_o = 1'b1;
                  end
                end
            default: ;
          endcase
      end

      MN_ANL_EXT, MN_ORL_EXT: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M5) begin
            if (opc_opcode_q[1:0] == 2'b00) add_read_bus_s = 1'b1;
            else if (!opc_opcode_q[1]) begin
              p1_read_p1_o  = 1'b1;
              p1_read_reg_o = 1'b1;
            end else begin
              p2_read_p2_o  = 1'b1;
              p2_read_reg_o = 1'b1;
            end
            alu_write_temp_reg_o = 1'b1;
          end
        end else
          case (clk_mstate_i)
            M1: alu_write_shadow_o = 1'b1;
            M2: begin
                  alu_read_alu_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
            M3: begin
                  alu_op_o       = (mn == MN_ANL_EXT) ? ALU_AND : ALU_OR;
                  alu_read_alu_o = 1'b1;
                  if (opc_opcode_q[1:0] == 2'b00) bus_write_bus_o = 1'b1;
                  else if (!opc_opcode_q[1])      p1_write_p1_o   = 1'b1;
                  else                            p2_write_p2_o   = 1'b1;
                end
            default: ;
          endcase
      end

      // -------------------------------------------------------------- CALL
      MN_CALL: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  psw_read_sp_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK;
                  if (!int_pending_s && !IS_MCS2X) add_inc_pc_s = 1'b1;
                end
            M4: begin
                  pm_read_pcl_o   = 1'b1;
                  dm_write_dmem_s = 1'b1;
                end
            M5: begin
                  psw_read_psw_o       = 1'b1;
                  pm_read_pch_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK_HIGH;
                  dm_write_dmem_s      = 1'b1;
                  psw_inc_stackp_o     = 1'b1;
                end
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: begin
                  pm_write_pcl_o = 1'b1;
                  branch_taken_s = 1'b1;
                  if (int_pending_s) begin
                    data_s = {5'b00000, tim_int_s, 2'b11};
                    if (!tim_int_s) bus_ibf_int_o = 1'b1;
                    read_dec_s = 1'b1;
                  end
                end
            M2: begin
                  pm_write_pch_o = 1'b1;
                  read_dec_s     = 1'b1;
                  if (!int_pending_s)
                    data_s = {4'b0000, mb_v, opc_opcode_q[7:5]};
                  else begin
                    data_s         = 8'h00;
                    int_executed_s = 1'b1;
                  end
                end
            default: ;
          endcase
      end

      // ------------------------------------------------- single-cycle misc
      MN_CLR_A:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_CLR;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_CLR_C:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = 1'b0;
          psw_write_carry_o  = 1'b1;
        end
      MN_CLR_F:
        if (clk_mstate_i == M3) begin
          if (!opc_opcode_q[5]) begin
            psw_special_data_o = 1'b0;
            psw_write_f0_o     = 1'b1;
          end else
            clear_f1_s = 1'b1;
        end
      MN_CPL_A:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_CPL;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_CPL_C:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = ~psw_carry_i;
          psw_write_carry_o  = 1'b1;
        end
      MN_CPL_F:
        if (clk_mstate_i == M3) begin
          if (!opc_opcode_q[5]) begin
            psw_special_data_o = ~psw_f0_i;
            psw_write_f0_o     = 1'b1;
          end else
            cpl_f1_s = 1'b1;
        end

      MN_DA: begin
        alu_op_o = ALU_ADD;
        case (clk_mstate_i)
          M3: alu_p06_temp_reg_o = 1'b1;
          M4: begin
                if (psw_aux_carry_i || alu_da_overflow_i) begin
                  alu_read_alu_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
                alu_p60_temp_reg_o = 1'b1;
              end
          M5: begin
                alu_da_high_o = 1'b1;
                if (alu_da_overflow_i)
                  psw_special_data_o = alu_carry_i;
                else begin
                  alu_op_o           = ALU_NOP;
                  psw_special_data_o = 1'b0;
                end
                alu_read_alu_o    = 1'b1;
                alu_write_accu_o  = 1'b1;
                psw_write_carry_o = 1'b1;
              end
          default: ;
        endcase
      end

      MN_DEC:
        case (clk_mstate_i)
          M4: if (opc_opcode_q[6]) begin
                dm_read_dmem_o     = 1'b1;
                alu_write_shadow_o = 1'b1;
              end
          M5: begin
                alu_op_o       = ALU_DEC;
                alu_read_alu_o = 1'b1;
                if (!opc_opcode_q[6]) alu_write_accu_o = 1'b1;
                else                  dm_write_dmem_s  = 1'b1;
              end
          default: ;
        endcase

      MN_DIS_EN_I:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) dis_i_s = 1'b1;
          else                 en_i_s  = 1'b1;
        end
      MN_DIS_EN_TCNTI:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) dis_tcnti_s = 1'b1;
          else                 en_tcnti_s  = 1'b1;
        end

      MN_DJNZ: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M4: begin
                  dm_read_dmem_o     = 1'b1;
                  alu_write_shadow_o = 1'b1;
                end
            M5: begin
                  alu_op_o            = ALU_DEC;
                  alu_read_alu_o      = 1'b1;
                  dm_write_dmem_s     = 1'b1;
                  cnd_compute_take_o  = 1'b1;
                  cnd_branch_cond_o   = COND_Z;
                  cnd_comp_value_o[0] = 1'b0;
                end
            default: ;
          endcase
        else if (clk_mstate_i == M1 && cnd_take_branch_i) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      MN_EN_DMA_FLAGS:
        if (clk_mstate_i == M4) begin
          if (!opc_opcode_q[4]) bus_en_dma_o   = 1'b1;
          else                  bus_en_flags_o = 1'b1;
        end
      MN_ENT0_CLK:
        if (clk_mstate_i == M3) ent0_clk_s = 1'b1;

      // ------------------------------------------------------------ ports
      MN_IN:
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          if (!opc_opcode_q[1]) p1_read_p1_o = 1'b1;
          else                  p2_read_p2_o = 1'b1;
        end
      MN_IN_DBB:
        if (clk_mstate_i == M4) begin
          alu_write_accu_o = 1'b1;
          add_read_bus_s   = 1'b1;
        end
      MN_IN_P0:
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          p0_read_p0_o     = 1'b1;
        end
      MN_INS: begin
        clk_assert_rd_o = 1'b1;
        if (clk_second_cycle_i && clk_mstate_i == M2) begin
          alu_write_accu_o = 1'b1;
          add_read_bus_s   = 1'b1;
        end
      end

      MN_INC:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: if (opc_opcode_q[3:2] != 2'b01) begin
                dm_read_dmem_o     = 1'b1;
                alu_write_shadow_o = 1'b1;
              end
          M5: begin
                alu_op_o       = ALU_INC;
                alu_read_alu_o = 1'b1;
                if (opc_opcode_q[3:2] == 2'b01) alu_write_accu_o = 1'b1;
                else                            dm_write_dmem_s  = 1'b1;
              end
          default: ;
        endcase

      // ---------------------------------------------- conditional jumps
      MN_JBB, MN_JC, MN_JF, MN_JNI, MN_JNIBF, MN_JOBF, MN_JT, MN_JTF, MN_JZ: begin
        assert_psen_s = 1'b1;
        case (mn)
          MN_JBB:   cnd_branch_cond_o = COND_ON_BIT;
          MN_JC:    cnd_branch_cond_o = COND_C;
          MN_JNI:   cnd_branch_cond_o = COND_INT;
          MN_JNIBF: cnd_branch_cond_o = COND_NIBF;
          MN_JOBF:  cnd_branch_cond_o = COND_OBF;
          MN_JT:    cnd_branch_cond_o = opc_opcode_q[6] ? COND_T1 : COND_T0;
          MN_JTF:   cnd_branch_cond_o = COND_TF;
          MN_JZ:    cnd_branch_cond_o = COND_Z;
          default:  ;
        endcase
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            cnd_compute_take_o = 1'b1;
            case (mn)
              MN_JBB: alu_read_alu_o = 1'b1;
              MN_JC, MN_JT: cnd_comp_value_o[0] = opc_opcode_q[4];
              MN_JF:  cnd_branch_cond_o = opc_opcode_q[7] ? COND_F0 : COND_F1;
              MN_JTF: jtf_executed_s = 1'b1;
              MN_JZ: begin
                alu_read_alu_o      = 1'b1;
                cnd_comp_value_o[0] = opc_opcode_q[6];
              end
              default: ;
            endcase
          end
        end else if (clk_mstate_i == M1 && cnd_take_branch_i) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      // ---------------------------------------------------------- jumps
      MN_JMP: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i)
          case (clk_mstate_i)
            M1: begin
                  pm_write_pcl_o = 1'b1;
                  branch_taken_s = 1'b1;
                end
            M2: begin
                  data_s         = {4'b0000, mb_v, opc_opcode_q[7:5]};
                  read_dec_s     = 1'b1;
                  pm_write_pch_o = 1'b1;
                end
            default: ;
          endcase
      end
      MN_JMPP: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            alu_read_alu_o = 1'b1;
            pm_addr_type_o = PM_PAGE;
          end
        end else if (clk_mstate_i == M1) begin
          pm_write_pcl_o = 1'b1;
          branch_taken_s = 1'b1;
        end
      end

      // ----------------------------------------------------------- moves
      MN_MOV_A_DATA: begin
        assert_psen_s = 1'b1;
        if (clk_second_cycle_i && clk_mstate_i == M1) alu_write_accu_o = 1'b1;
      end
      MN_MOV_A_RR:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_temp_reg_o = 1'b1;
                alu_write_accu_o     = 1'b1;
              end
          default: ;
        endcase
      MN_MOV_A_PSW:
        if (clk_mstate_i == M3) begin
          psw_read_psw_o   = 1'b1;
          psw_read_sp_o    = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      MN_MOV_PSW_A:
        if (clk_mstate_i == M3) begin
          alu_read_alu_o  = 1'b1;
          psw_write_psw_o = 1'b1;
          psw_write_sp_o  = 1'b1;
        end
      MN_MOV_RR:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M5: begin
                alu_read_alu_o  = 1'b1;
                dm_write_dmem_s = 1'b1;
              end
          default: ;
        endcase
      MN_MOV_RR_DATA: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i && clk_mstate_i == M3 && !opc_opcode_q[3]) begin
          dm_read_dmem_o       = 1'b1;
          dm_write_dmem_addr_o = 1'b1;
          dm_addr_type_o       = DM_PLAIN;
        end
        if (clk_second_cycle_i && clk_mstate_i == M1) dm_write_dmem_s = 1'b1;
      end
      MN_MOV_STS:
        if (clk_mstate_i == M4) begin
          alu_read_alu_o  = 1'b1;
          bus_write_sts_o = 1'b1;
        end
      MN_MOV_T:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[5]) begin
            alu_read_alu_o    = 1'b1;
            tim_write_timer_o = 1'b1;
          end else begin
            tim_read_timer_o = 1'b1;
            alu_write_accu_o = 1'b1;
          end
        end

      // ------------------------------------------------- 8243 expander
      MN_OUTD_PP_A: begin
        clk_assert_prog_o = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  data_s[7:4] = 4'b0000;
                  data_s[1:0] = opc_opcode_q[1:0];
                  case (opc_opcode_q[7:4])
                    4'b1001: data_s[3:2] = 2'b11;
                    4'b1000: data_s[3:2] = 2'b10;
                    4'b0011: data_s[3:2] = 2'b01;
                    default: ;
                  endcase
                  read_dec_s     = 1'b1;
                  p2_write_exp_o = 1'b1;
                end
            M4: begin
                  p2_output_exp_s = 1'b1;
                  alu_read_alu_o  = 1'b1;
                  p2_write_exp_o  = 1'b1;
                end
            M5: p2_output_exp_s = 1'b1;
            default: ;
          endcase
        else if (clk_mstate_i == M1 || clk_mstate_i == M2)
          p2_output_exp_s = 1'b1;
      end
      MN_MOVD_A_PP: begin
        clk_assert_prog_o = 1'b1;
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: begin
                  data_s         = {6'b000000, opc_opcode_q[1:0]};
                  read_dec_s     = 1'b1;
                  p2_write_exp_o = 1'b1;
                end
            M4: begin
                  p2_output_exp_s = 1'b1;
                  data_s[3:0]     = 4'b1111;
                  read_dec_s      = 1'b1;
                  p2_write_exp_o  = 1'b1;
                end
            M5: p2_output_exp_s = 1'b1;
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: p2_output_exp_s = 1'b1;
            M2: begin
                  p2_read_p2_o     = 1'b1;
                  p2_output_exp_s  = 1'b1;
                  p2_read_exp_o    = 1'b1;
                  alu_write_accu_o = 1'b1;
                end
            default: ;
          endcase
      end

      MN_MOVP: begin
        assert_psen_s = 1'b1;
        if (!clk_second_cycle_i) begin
          if (clk_mstate_i == M3) begin
            alu_read_alu_o = 1'b1;
            pm_addr_type_o = opc_opcode_q[6] ? PM_PAGE3 : PM_PAGE;
          end
        end else if (clk_mstate_i == M1) begin
          alu_write_accu_o = 1'b1;
          branch_taken_s   = 1'b1;
        end
      end

      MN_MOVX: begin
        bus_bidir_bus_o = 1'b1;
        if (!opc_opcode_q[4]) clk_assert_rd_o = 1'b1;
        else                  clk_assert_wr_o = 1'b1;
        if (!clk_second_cycle_i) begin
          movx_first_cycle_s = 1'b1;
          case (clk_mstate_i)
            M3: begin
                  dm_read_dmem_o  = 1'b1;
                  bus_write_bus_o = 1'b1;
                end
            M5: if (opc_opcode_q[4]) begin
                  alu_read_alu_o  = 1'b1;
                  bus_write_bus_o = 1'b1;
                end
            default: ;
          endcase
        end else if (clk_mstate_i == M2) begin
          if (!opc_opcode_q[4]) begin
            add_read_bus_s   = 1'b1;
            alu_write_accu_o = 1'b1;
          end else begin
            alu_read_alu_o  = 1'b1;
            bus_write_bus_o = 1'b1;
          end
        end
      end

      MN_OUT_DBB:
        if (clk_mstate_i == M4) begin
          alu_read_alu_o  = 1'b1;
          bus_write_bus_o = 1'b1;
        end
      MN_OUTL_EXT: begin
        if (!opc_opcode_q[4]) clk_assert_wr_o = 1'b1;
        if (!clk_second_cycle_i && clk_mstate_i == M4) begin
          alu_read_alu_o = 1'b1;
          if (opc_opcode_q[4]) begin
            if (!opc_opcode_q[1]) p1_write_p1_o = 1'b1;
            else                  p2_write_p2_o = 1'b1;
          end else
            bus_write_bus_o = 1'b1;
        end
      end
      MN_OUTL_P0:
        if (!clk_second_cycle_i && clk_mstate_i == M4) begin
          alu_read_alu_o = 1'b1;
          p0_write_p0_o  = 1'b1;
        end
      MN_RAD:
        if (clk_second_cycle_i && clk_mstate_i == M3) begin
          adc_read_adc_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end

      // ----------------------------------------------------------- returns
      MN_RET, MN_RETR, MN_RETI: begin
        if (!clk_second_cycle_i)
          case (clk_mstate_i)
            M3: psw_dec_stackp_o = 1'b1;
            M4: begin
                  psw_read_sp_o        = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK;
                end
            M5: begin
                  dm_read_dmem_o       = 1'b1;
                  pm_write_pcl_o       = 1'b1;
                  dm_write_dmem_addr_o = 1'b1;
                  dm_addr_type_o       = DM_STACK_HIGH;
                end
            default: ;
          endcase
        else
          case (clk_mstate_i)
            M1: begin
                  dm_read_dmem_o = 1'b1;
                  pm_write_pch_o = 1'b1;
                  if (mn == MN_RETR) begin
                    psw_write_psw_o = 1'b1;
                    retr_executed_s = 1'b1;
                  end else if (mn == MN_RETI)
                    retr_executed_s = 1'b1;
                end
            M2: begin
                  if (IS_MCS2X && mn == MN_RET) add_inc_pc_s = 1'b1;
                  if (REV2023 == 0) add_write_pmem_addr_s = 1'b1;
                end
            M3: if (REV2023 == 1) add_write_pmem_addr_s = 1'b1;
            default: ;
          endcase
      end

      // ------------------------------------------------------- rotates etc
      MN_RL:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_RL;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
          if (opc_opcode_q[4]) begin
            psw_special_data_o = alu_carry_i;
            psw_write_carry_o  = 1'b1;
          end
        end
      MN_RR:
        if (clk_mstate_i == M3) begin
          alu_op_o         = ALU_RR;
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
          if (!opc_opcode_q[4]) begin
            psw_special_data_o = alu_carry_i;
            psw_write_carry_o  = 1'b1;
          end
        end
      MN_SEL_AN:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) adc_sel_an0_o = 1'b1;
          else                 adc_sel_an1_o = 1'b1;
        end
      MN_SEL_MB:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) set_mb_s   = 1'b1;
          else                 clear_mb_s = 1'b1;
        end
      MN_SEL_RB:
        if (clk_mstate_i == M3) begin
          psw_special_data_o = opc_opcode_q[4];
          psw_write_bs_o     = 1'b1;
        end
      MN_STOP_TCNT:
        if (clk_mstate_i == M3) tim_stop_tcnt_o = 1'b1;
      MN_STRT:
        if (clk_mstate_i == M3) begin
          if (opc_opcode_q[4]) tim_start_t_o   = 1'b1;
          else                 tim_start_cnt_o = 1'b1;
        end
      MN_SWAP: begin
        alu_op_o = ALU_SWAP;
        if (clk_mstate_i == M3) begin
          alu_read_alu_o   = 1'b1;
          alu_write_accu_o = 1'b1;
        end
      end
      MN_XCH:
        case (clk_mstate_i)
          M3: if (!opc_opcode_q[3]) begin
                dm_read_dmem_o       = 1'b1;
                dm_write_dmem_addr_o = 1'b1;
                dm_addr_type_o       = DM_PLAIN;
              end
          M4: begin
                dm_read_dmem_o       = 1'b1;
                alu_write_accu_o     = 1'b1;
                alu_write_temp_reg_o = 1'b1;
                if (opc_opcode_q[4]) alu_accu_low_o = 1'b1;
              end
          M5: begin
                dm_write_dmem_s = 1'b1;
                alu_read_alu_o  = 1'b1;
                if (opc_opcode_q[4]) alu_op_o = ALU_CONCAT;
              end
          default: ;
        endcase
      default: ;
    endcase
  end

  // --------------------------------------------------------------------------
  // decoder registers
  // --------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      branch_taken_q <= 1'b0;
      f1_q           <= 1'b0;
      mb_q           <= 1'b0;
      t0_dir_q       <= 1'b0;
      istrobe_res_q  <= 1'b1;
      istrobe_q      <= 1'b0;
      injected_int_q <= 1'b0;
    end else begin
      if (IS_UPI) begin
        if (bus_set_f1_i)        f1_q <= 1'b1;
        else if (bus_clear_f1_i) f1_q <= 1'b0;
      end
      if (en_clk_i) begin
        if (branch_taken_s)      branch_taken_q <= 1'b1;
        else if (clk_mstate_i == M5) branch_taken_q <= 1'b0;
        if (clear_f1_s)          f1_q <= 1'b0;
        else if (cpl_f1_s)       f1_q <= ~f1_q;
        if (clear_mb_s)          mb_q <= 1'b0;
        else if (set_mb_s)       mb_q <= 1'b1;
        if (ent0_clk_s)          t0_dir_q <= 1'b1;
        if (opc_inj_int_s)       injected_int_q <= 1'b1;
        else if (clk_mstate_i == M5 && last_cycle_s) injected_int_q <= 1'b0;
        if (clk_mstate_i == M5 && last_cycle_s) istrobe_res_q <= 1'b0;
      end
      istrobe_q <= clk_mstate_i == M5 && last_cycle_s && !injected_int_q && !istrobe_res_q;
    end

  // adder operand / carry-in selection depends on the mnemonic only: it is observed
  // only in the states where the ALU result or its carries are consumed
  assign alu_use_carry_o = (((mn == MN_ADD || mn == MN_ADD_A_DATA) && opc_opcode_q[4]) ||
                            (mn == MN_RL && opc_opcode_q[4]) || (mn == MN_RR && !opc_opcode_q[4]));
  assign alu_add_inc_o   = mn == MN_INC;
  assign alu_add_dec_o   = mn == MN_DEC || mn == MN_DJNZ;
  assign clk_multi_cycle_o    = opc_multi_cycle_s;
  assign cnd_f1_o             = f1_q;
  assign cnd_tf_o             = timer_flag_q;
  assign data_o               = read_dec_s ? data_s : 8'hFF;
  assign dm_write_dmem_o      = dm_write_dmem_s & en_clk_i;
  assign pm_inc_pc_o          = pm_inc_pc_s | add_inc_pc_s;
  assign pm_write_pmem_addr_o = pm_write_pmem_addr_s | add_write_pmem_addr_s;
  assign t0_dir_o             = t0_dir_q;
  assign bus_read_bus_o       = bus_read_bus_s | add_read_bus_s;
  assign mb_o                 = mb_q;
  assign istrobe_o            = istrobe_q;

  // --------------------------------------------------------------------------
  // interrupt controller ("Interrupt Logic", The Single Component MCS-48 System)
  // --------------------------------------------------------------------------
  always_comb begin
    int_state_s = int_state_q;
    case (int_state_q)
      2'd0:    if (int_in_progress_q && last_cycle_s && clk_mstate_i == M5) int_state_s = 2'd1;
      2'd1:    if (int_executed_s)  int_state_s = 2'd2;
      2'd2:    if (retr_executed_s) int_state_s = 2'd0;
      default: int_state_s = 2'd0;
    endcase
  end

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      timer_flag_q       <= 1'b0;
      timer_overflow_q   <= 1'b0;
      timer_int_enable_q <= 1'b0;
      int_enable_q       <= 1'b0;
      int_type_q         <= 1'b0;
      int_state_q        <= 2'd0;
      int_in_progress_q  <= 1'b0;
    end else if (en_clk_i) begin
      int_state_q <= int_state_s;
      if (jtf_executed_s)      timer_flag_q <= 1'b0;
      else if (tim_overflow_i) timer_flag_q <= 1'b1;
      if ((!int_type_q && int_executed_s) || !timer_int_enable_q) timer_overflow_q <= 1'b0;
      else if (tim_overflow_i) timer_overflow_q <= 1'b1;
      if (dis_tcnti_s)     timer_int_enable_q <= 1'b0;
      else if (en_tcnti_s) timer_int_enable_q <= 1'b1;
      if (dis_i_s)     int_enable_q <= 1'b0;
      else if (en_i_s) int_enable_q <= 1'b1;
      if (retr_executed_s)
        int_in_progress_q <= 1'b0;
      else if ((int_q && int_enable_q) || timer_overflow_q) begin
        int_in_progress_q <= 1'b1;
        if (!int_in_progress_q) int_type_q <= int_q & int_enable_q;
      end
    end

  // INT is sampled at an ALE edge of the last cycle: falling (r295) or rising (2023+)
  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      int_q <= 1'b0;
      ale_q <= 1'b0;
    end else if (xtal_en_i) begin
      ale_q <= ale_i;
      if (last_cycle_s && ((REV2023 == 1) ? (!ale_q && ale_i) : (ale_q && !ale_i)))
        int_q <= ~int_n_i;
    end

  assign tim_int_s         = ~int_type_q;
  assign int_pending_s     = int_state_q == 2'd1;
  assign int_in_progress_s = int_in_progress_q && int_state_q != 2'd0;

endmodule

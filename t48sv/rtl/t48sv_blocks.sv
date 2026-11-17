// ============================================================================
// t48sv datapath blocks (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// All registers: asynchronous active-low reset, as in T48.
// ============================================================================

// ----------------------------------------------------------------------------
// Clock control: XTAL/3 divider, machine states, ALE / PSEN / PROG / RD / WR
// ----------------------------------------------------------------------------
module t48sv_clock_ctrl #(
  parameter int XTAL_DIV_3 = 1
) (
  input  logic       clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  output logic       xtal3_o,
  output logic       t0_o,
  input  logic       multi_cycle_i,
  input  logic       assert_psen_i,
  input  logic       assert_prog_i,
  input  logic       assert_rd_i,
  input  logic       assert_wr_i,
  output logic [2:0] mstate_o,
  output logic       second_cycle_o,
  output logic       ale_o,
  output logic       psen_o,
  output logic       prog_o,
  output logic       rd_o,
  output logic       wr_o
);

  localparam logic [2:0] M1 = 3'd0, M2 = 3'd1, M3 = 3'd2, M4 = 3'd3, M5 = 3'd4;

  logic       x2_s, x3_s;
  logic [2:0] mstate_q;
  logic       ale_q, psen_q, prog_q, rd_q, wr_q;
  logic       second_cycle_q, multi_cycle_q;

  generate
    if (XTAL_DIV_3 == 1) begin : g_div3
      logic [1:0] xtal_q;
      logic       t0_q;
      always_ff @(posedge xtal_i or negedge res_n_i)
        if (!res_n_i) begin
          xtal_q <= 2'd0;
          t0_q   <= 1'b0;
        end else if (xtal_en_i) begin
          xtal_q <= (xtal_q < 2'd2) ? xtal_q + 2'd1 : 2'd0;
          t0_q   <= x3_s;
        end
      assign x2_s = xtal_en_i & (xtal_q == 2'd1);
      assign x3_s = xtal_en_i & (xtal_q == 2'd2);
      assign t0_o = t0_q;
    end else begin : g_nodiv
      assign x2_s = xtal_en_i;
      assign x3_s = xtal_en_i;
      assign t0_o = xtal_i;
    end
  endgenerate

  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      ale_q  <= 1'b0;
      psen_q <= 1'b0;
      prog_q <= 1'b0;
      rd_q   <= 1'b0;
      wr_q   <= 1'b0;
    end else begin
      case (mstate_q)
        M5: if (x2_s && !second_cycle_q) begin
              if (assert_rd_i) rd_q <= 1'b1;
              if (assert_wr_i) wr_q <= 1'b1;
            end
        M1: if (x3_s) psen_q <= 1'b0;
        M2: if (x3_s) begin
              rd_q   <= 1'b0;
              wr_q   <= 1'b0;
              prog_q <= 1'b0;
            end
        M3: if (x3_s) ale_q <= 1'b1;
        M4: begin
              if (x3_s && assert_psen_i) psen_q <= 1'b1;
              if (x3_s && multi_cycle_q && !second_cycle_q && assert_prog_i) prog_q <= 1'b1;
              if (x2_s) ale_q <= 1'b0;
            end
        default: begin
              ale_q  <= 1'b0;
              psen_q <= 1'b0;
              prog_q <= 1'b0;
              rd_q   <= 1'b0;
              wr_q   <= 1'b0;
            end
      endcase
    end

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)
      mstate_q <= M3;
    else if (en_clk_i)
      mstate_q <= (mstate_q == M5 || mstate_q > M5) ? M1 : mstate_q + 3'd1;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      multi_cycle_q  <= 1'b0;
      second_cycle_q <= 1'b0;
    end else if (en_clk_i) begin
      if (mstate_q == M5 && multi_cycle_q && second_cycle_q) begin
        multi_cycle_q  <= 1'b0;
        second_cycle_q <= 1'b0;
      end else begin
        if (mstate_q == M2 && multi_cycle_i) multi_cycle_q  <= 1'b1;
        if (mstate_q == M5 && multi_cycle_q) second_cycle_q <= 1'b1;
      end
    end

  assign xtal3_o        = x3_s;
  assign mstate_o       = mstate_q;
  assign second_cycle_o = second_cycle_q;
  assign ale_o          = ale_q;
  assign psen_o         = psen_q;
  assign prog_o         = prog_q;
  assign rd_o           = rd_q;
  assign wr_o           = wr_q;

endmodule


// ----------------------------------------------------------------------------
// ALU: accumulator, shadow and temp registers
// ----------------------------------------------------------------------------
module t48sv_alu (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_accu_i,
  input  logic       write_shadow_i,
  input  logic       write_temp_reg_i,
  input  logic       read_alu_i,
  input  logic       carry_i,
  output logic       carry_o,
  output logic       aux_carry_o,
  input  logic [3:0] alu_op_i,
  input  logic       use_carry_i,
  input  logic       add_inc_i,
  input  logic       add_dec_i,
  input  logic       da_high_i,
  output logic       da_overflow_o,
  input  logic       accu_low_i,
  input  logic       p06_temp_reg_i,
  input  logic       p60_temp_reg_i,
  output logic [7:0] accu_o
);

  localparam logic [3:0] ALU_AND = 4'd0, ALU_OR = 4'd1, ALU_XOR = 4'd2, ALU_CPL = 4'd3,
                         ALU_CLR = 4'd4, ALU_RL = 4'd5, ALU_RR = 4'd6, ALU_SWAP = 4'd7,
                         ALU_DEC = 4'd8, ALU_INC = 4'd9, ALU_ADD = 4'd10, ALU_CONCAT = 4'd11,
                         ALU_NOP = 4'd12;

  logic [7:0] accu_q, shadow_q, temp_q;
  logic [7:0] in_a, in_b, data_s;
  logic [8:0] add_b, add_r;
  logic [3:0] da_nib;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      accu_q   <= 8'h00;
      shadow_q <= 8'h00;
      temp_q   <= 8'h00;
    end else if (en_clk_i) begin
      if (write_accu_i) begin
        if (accu_low_i) accu_q[3:0] <= data_i[3:0];
        else            accu_q      <= data_i;
      end
      shadow_q <= write_shadow_i ? data_i : accu_q;
      if (p06_temp_reg_i)        temp_q <= 8'h06;
      else if (p60_temp_reg_i)   temp_q <= 8'h60;
      else if (write_temp_reg_i) temp_q <= data_i;
    end

  assign in_a = shadow_q;
  assign in_b = temp_q;

  always_comb begin
    add_b = add_inc_i ? 9'h001 : add_dec_i ? 9'h1FF : {1'b0, in_b};
    add_r = {1'b0, in_a} + add_b + {8'h00, use_carry_i & carry_i};
  end
  assign aux_carry_o = add_r[4] ^ in_a[4] ^ in_b[4];

  always_comb begin
    data_s  = 8'h00;
    carry_o = 1'b0;
    case (alu_op_i)
      ALU_AND:    data_s = in_a & in_b;
      ALU_OR:     data_s = in_a | in_b;
      ALU_XOR:    data_s = in_a ^ in_b;
      ALU_ADD:    begin data_s = add_r[7:0]; carry_o = add_r[8]; end
      ALU_CPL:    data_s = ~in_a;
      ALU_CLR:    data_s = 8'h00;
      ALU_RL:     begin data_s = {in_a[6:0], use_carry_i ? carry_i : in_a[7]}; carry_o = in_a[7]; end
      ALU_RR:     begin data_s = {use_carry_i ? carry_i : in_a[0], in_a[7:1]}; carry_o = in_a[0]; end
      ALU_SWAP:   data_s = {in_a[3:0], in_a[7:4]};
      ALU_DEC,
      ALU_INC:    data_s = add_r[7:0];
      ALU_CONCAT: data_s = {in_b[7:4], in_a[3:0]};
      ALU_NOP:    data_s = in_a;
      default:    data_s = 8'h00;
    endcase
  end

  assign da_nib        = da_high_i ? shadow_q[7:4] : shadow_q[3:0];
  assign da_overflow_o = da_nib > 4'd9;
  assign data_o        = read_alu_i ? data_s : 8'hFF;
  assign accu_o        = accu_q;

endmodule


// ----------------------------------------------------------------------------
// Conditional branch decision
// ----------------------------------------------------------------------------
module t48sv_cond_branch (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       compute_take_i,
  input  logic [3:0] branch_cond_i,
  output logic       take_branch_o,
  input  logic [7:0] accu_i,
  input  logic       t0_i,
  input  logic       t1_i,
  input  logic       int_n_i,
  input  logic       f0_i,
  input  logic       f1_i,
  input  logic       tf_i,
  input  logic       carry_i,
  input  logic       ibf_i,
  input  logic       obf_i,
  input  logic [2:0] comp_value_i
);

  localparam logic [3:0] COND_ON_BIT = 4'd0, COND_Z = 4'd1, COND_C = 4'd2, COND_F0 = 4'd3,
                         COND_F1 = 4'd4, COND_INT = 4'd5, COND_T0 = 4'd6, COND_T1 = 4'd7,
                         COND_TF = 4'd8, COND_NIBF = 4'd9, COND_OBF = 4'd10;

  logic take_s, take_q;

  always_comb
    case (branch_cond_i)
      COND_ON_BIT: take_s = accu_i[comp_value_i];
      COND_Z:      take_s = (|accu_i) == ~comp_value_i[0];
      COND_C:      take_s = carry_i == comp_value_i[0];
      COND_F0:     take_s = f0_i;
      COND_F1:     take_s = f1_i;
      COND_INT:    take_s = ~int_n_i;
      COND_T0:     take_s = t0_i == comp_value_i[0];
      COND_T1:     take_s = t1_i == comp_value_i[0];
      COND_TF:     take_s = tf_i;
      COND_NIBF:   take_s = ~ibf_i;
      COND_OBF:    take_s = obf_i;
      default:     take_s = 1'b0;
    endcase

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)                       take_q <= 1'b0;
    else if (en_clk_i && compute_take_i) take_q <= take_s;

  assign take_branch_o = take_q;

endmodule


// ----------------------------------------------------------------------------
// MCS-48 BUS port
// ----------------------------------------------------------------------------
module t48sv_db_bus (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       ea_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_bus_i,
  input  logic       read_bus_i,
  input  logic       output_pcl_i,
  input  logic       bidir_bus_i,
  input  logic [7:0] pcl_i,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o
);

  logic [7:0] bus_q;
  logic       dir_q, dir_qq;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      bus_q  <= 8'h00;
      dir_q  <= 1'b0;
      dir_qq <= 1'b0;
    end else if (en_clk_i) begin
      dir_qq <= write_bus_i | dir_q;
      if (write_bus_i) begin
        bus_q <= data_i;
        dir_q <= 1'b1;
      end else if (ea_i || bidir_bus_i)
        dir_q <= 1'b0;
    end

  assign db_o     = output_pcl_i ? pcl_i : bus_q;
  assign db_dir_o = dir_qq | output_pcl_i;
  assign data_o   = read_bus_i ? db_i : 8'hFF;

endmodule


// ----------------------------------------------------------------------------
// UPI-41 data bus buffer (DBBIN / DBBOUT / STATUS), host side synchronous
// IBF_ACK = 1: IN A,DBB also releases the IBF interrupt (fleet DECO edit)
// ----------------------------------------------------------------------------
module t48sv_upi_db_bus #(
  parameter int TYPE_A  = 1,
  parameter int IBF_ACK = 1
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_bus_i,
  input  logic       read_bus_i,
  input  logic       write_sts_i,
  output logic       set_f1_o,
  output logic       clear_f1_o,
  input  logic       f0_i,
  input  logic       f1_i,
  output logic       ibf_o,
  output logic       obf_o,
  output logic       int_n_o,
  input  logic       ibf_int_i,
  input  logic       en_dma_i,
  input  logic       en_flags_i,
  input  logic       write_p2_i,
  output logic       mint_ibf_n_o,
  output logic       mint_obf_o,
  output logic       dma_o,
  output logic       drq_o,
  input  logic       dack_n_i,
  input  logic       a0_i,
  input  logic       cs_n_i,
  input  logic       rd_n_i,
  input  logic       wr_n_i,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic [7:0] sts_o,
  output logic       db_dir_o
);

  logic       read_s, write_s, read_q, write_q, read_pulse_s, write_pulse_s;
  logic       dack_s, ext_acc_s;
  logic       a0_q, ibf_q, obf_q, int_n_q, drq_q;
  logic [7:0] dbbin_q, dbbout_q, status_q;
  logic [3:0] sts_q;
  logic       dma_q, flags_q;

  assign dack_s    = ~dack_n_i & dma_q;
  assign ext_acc_s = ~cs_n_i | dack_s;
  assign read_s    = ext_acc_s & ~rd_n_i;
  assign write_s   = ext_acc_s & ~wr_n_i;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      read_q   <= 1'b0;
      write_q  <= 1'b0;
      a0_q     <= 1'b0;
      status_q <= 8'h00;
    end else begin
      read_q  <= read_s;
      write_q <= write_s;
      if (dack_s)                a0_q <= 1'b0;
      else if (read_s || write_s) a0_q <= a0_i;
      if (!read_s) status_q <= {(TYPE_A == 1) ? sts_q : 4'b0000, f1_i, f0_i, ibf_q, obf_q};
    end

  assign read_pulse_s  = read_q & ~read_s;
  assign write_pulse_s = write_q & ~write_s;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      dbbin_q  <= 8'h00;
      dbbout_q <= 8'h00;
      sts_q    <= 4'h0;
      ibf_q    <= 1'b0;
      obf_q    <= 1'b0;
      int_n_q  <= 1'b1;
      dma_q    <= 1'b0;
      drq_q    <= 1'b0;
      flags_q  <= 1'b0;
    end else begin
      if (read_pulse_s && !a0_q)
        obf_q <= 1'b0;
      else if (write_pulse_s) begin
        dbbin_q <= db_i;
        ibf_q   <= 1'b1;
        int_n_q <= 1'b0;
      end
      if (dack_s && (read_s || write_s)) drq_q <= 1'b0;
      if (en_clk_i) begin
        if (write_bus_i) begin
          dbbout_q <= data_i;
          obf_q    <= 1'b1;
        end else if (read_bus_i) begin
          ibf_q <= 1'b0;
          if (IBF_ACK == 1) int_n_q <= 1'b1;
        end else if (write_sts_i)
          sts_q <= data_i[7:4];
        if (ibf_int_i) int_n_q <= 1'b1;
        if (TYPE_A == 1) begin
          if (en_dma_i) begin
            dma_q <= 1'b1;
            drq_q <= 1'b0;
          end
          if (en_flags_i) flags_q <= 1'b1;
          if (dma_q && write_p2_i && data_i[6]) drq_q <= 1'b1;
        end
      end
    end

  assign set_f1_o     = write_pulse_s & a0_q;
  assign clear_f1_o   = write_pulse_s & ~a0_q;
  assign ibf_o        = ibf_q;
  assign obf_o        = obf_q;
  assign int_n_o      = int_n_q;
  assign drq_o        = drq_q;
  assign db_o         = (~a0_i | (dack_s & dma_q)) ? dbbout_q : status_q;
  assign sts_o        = status_q;
  assign db_dir_o     = read_s;
  assign data_o       = read_bus_i ? dbbin_q : 8'hFF;
  assign mint_ibf_n_o = ~(flags_q & ibf_q);
  assign mint_obf_o   = ~(flags_q & ~obf_q);
  assign dma_o        = dma_q;

endmodule


// ----------------------------------------------------------------------------
// Data memory address control
// ----------------------------------------------------------------------------
module t48sv_dmem_ctrl (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  input  logic       write_dmem_addr_i,
  input  logic       write_dmem_i,
  input  logic       read_dmem_i,
  input  logic [1:0] addr_type_i,
  input  logic       bank_select_i,
  output logic [7:0] data_o,
  input  logic [7:0] dmem_data_i,
  output logic [7:0] dmem_addr_o,
  output logic       dmem_we_o,
  output logic [7:0] dmem_data_o
);

  localparam logic [1:0] DM_PLAIN = 2'd0, DM_REG = 2'd1, DM_STACK = 2'd2;

  logic [7:0] addr_s, addr_q;
  logic [5:0] stack_v;

  assign stack_v = {2'b00, data_i[2:0], 1'b0} + 6'd8;

  always_comb
    case (addr_type_i)
      DM_PLAIN: addr_s = data_i;
      DM_REG:   addr_s = {3'b000, {2{bank_select_i}}, data_i[2:0]};
      DM_STACK: addr_s = {2'b00, stack_v};
      default:  addr_s = {addr_q[7:1], 1'b1};
    endcase

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i)                           addr_q <= 8'h00;
    else if (en_clk_i && write_dmem_addr_i) addr_q <= addr_s;

  assign dmem_addr_o = (write_dmem_addr_i && en_clk_i) ? addr_s : addr_q;
  assign dmem_data_o = data_i;
  assign data_o      = read_dmem_i ? dmem_data_i : 8'hFF;
  assign dmem_we_o   = write_dmem_i;

endmodule


// ----------------------------------------------------------------------------
// Program counter and program memory address
// ----------------------------------------------------------------------------
module t48sv_pmem_ctrl (
  input  logic        clk_i,
  input  logic        res_n_i,
  input  logic        en_clk_i,
  input  logic [7:0]  data_i,
  output logic [7:0]  data_o,
  input  logic        write_pcl_i,
  input  logic        read_pcl_i,
  input  logic        write_pch_i,
  input  logic        read_pch_i,
  input  logic        inc_pc_i,
  input  logic        write_pmem_addr_i,
  input  logic [1:0]  addr_type_i,
  input  logic        read_pmem_i,
  output logic [11:0] pmem_addr_o,
  output logic [11:0] pc_o,
  input  logic [7:0]  pmem_data_i
);

  localparam logic [1:0] PM_PAGE = 2'd1, PM_PAGE3 = 2'd2;

  logic [11:0] pc_q, addr_s, addr_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      pc_q   <= 12'h000;
      addr_q <= 12'h000;
    end else if (en_clk_i) begin
      if (write_pcl_i)      pc_q[7:0]  <= data_i;
      else if (write_pch_i) pc_q[11:8] <= data_i[3:0];
      else if (inc_pc_i)    pc_q[10:0] <= pc_q[10:0] + 11'd1;
      if (write_pmem_addr_i) addr_q <= addr_s;
    end

  always_comb
    case (addr_type_i)
      PM_PAGE:  addr_s = {pc_q[11:8], data_i};
      PM_PAGE3: addr_s = {4'b0011, data_i};
      default:  addr_s = pc_q;
    endcase

  always_comb
    if (read_pmem_i)     data_o = pmem_data_i;
    else if (read_pcl_i) data_o = pc_q[7:0];
    else if (read_pch_i) data_o = {4'hF, pc_q[11:8]};
    else                 data_o = 8'hFF;

  assign pmem_addr_o = addr_q;
  assign pc_o        = pc_q;

endmodule


// ----------------------------------------------------------------------------
// PSW: CY AC F0 BS + stack pointer
// ----------------------------------------------------------------------------
module t48sv_psw (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       read_psw_i,
  input  logic       read_sp_i,
  input  logic       write_psw_i,
  input  logic       write_sp_i,
  input  logic       special_data_i,
  input  logic       inc_stackp_i,
  input  logic       dec_stackp_i,
  input  logic       write_carry_i,
  input  logic       write_aux_carry_i,
  input  logic       write_f0_i,
  input  logic       write_bs_i,
  output logic       carry_o,
  input  logic       aux_carry_i,
  output logic       aux_carry_o,
  output logic       f0_o,
  output logic       bs_o,
  output logic [2:0] sp_o
);

  logic [3:0] psw_q;   // CY AC F0 BS
  logic [2:0] sp_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      psw_q <= 4'h0;
      sp_q  <= 3'd0;
    end else if (en_clk_i) begin
      if (write_psw_i) psw_q <= data_i[7:4];
      if (dec_stackp_i)      sp_q <= sp_q - 3'd1;
      else if (inc_stackp_i) sp_q <= sp_q + 3'd1;
      else if (write_sp_i)   sp_q <= data_i[2:0];
      if (write_carry_i)     psw_q[3] <= special_data_i;
      if (write_aux_carry_i) psw_q[2] <= aux_carry_i;
      if (write_f0_i)        psw_q[1] <= special_data_i;
      if (write_bs_i)        psw_q[0] <= special_data_i;
    end

  assign data_o      = {read_psw_i ? psw_q : 4'hF, read_sp_i ? {1'b1, sp_q} : 4'hF};
  assign carry_o     = psw_q[3];
  assign aux_carry_o = psw_q[2];
  assign f0_o        = psw_q[1];
  assign bs_o        = psw_q[0];
  assign sp_o        = sp_q;

endmodule


// ----------------------------------------------------------------------------
// Timer / event counter with /32 prescaler
// ----------------------------------------------------------------------------
module t48sv_timer #(
  parameter int SAMPLE_T1_STATE = 4
) (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       t1_i,
  input  logic [2:0] mstate_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       read_timer_i,
  input  logic       write_timer_i,
  input  logic       start_t_i,
  input  logic       start_cnt_i,
  input  logic       stop_tcnt_i,
  output logic       overflow_o
);

  localparam logic [2:0] M3 = 3'd2, M4 = 3'd3;

  logic [7:0] counter_q;
  logic       overflow_q, t1_q;
  logic [4:0] prescaler_q;
  logic [1:0] inc_sel_q;     // 0 none, 1 timer, 2 counter
  logic       sample_s, increment_s;

  assign sample_s    = mstate_i == ((SAMPLE_T1_STATE == 3) ? M3 : M4);
  assign increment_s = (inc_sel_q == 2'd1) ? (mstate_i == M4 && prescaler_q == 5'd31) :
                       (inc_sel_q == 2'd2) ? (sample_s && t1_q && !t1_i) : 1'b0;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      overflow_q  <= 1'b0;
      t1_q        <= 1'b0;
      prescaler_q <= 5'd0;
      inc_sel_q   <= 2'd0;
      counter_q   <= 8'h00;
    end else if (en_clk_i) begin
      overflow_q <= 1'b0;
      if (write_timer_i)
        counter_q <= data_i;
      else if (increment_s) begin
        counter_q <= counter_q + 8'd1;
        if (counter_q == 8'hFF) overflow_q <= 1'b1;
      end
      if (sample_s) t1_q <= t1_i;
      if (start_t_i)          prescaler_q <= 5'd0;
      else if (mstate_i == M3) prescaler_q <= prescaler_q + 5'd1;
      if (start_t_i)        inc_sel_q <= 2'd1;
      else if (start_cnt_i) inc_sel_q <= 2'd2;
      else if (stop_tcnt_i) inc_sel_q <= 2'd0;
    end

  assign data_o     = read_timer_i ? counter_q : 8'hFF;
  assign overflow_o = overflow_q;

endmodule


// ----------------------------------------------------------------------------
// Quasi-bidirectional port (P1, and P0 of the 8021/8022)
// ----------------------------------------------------------------------------
module t48sv_port (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_i,
  input  logic       read_i,
  input  logic       read_reg_i,
  input  logic [7:0] port_i,
  output logic [7:0] port_o,
  output logic       low_imp_o
);

  logic [7:0] port_q;
  logic       low_imp_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      port_q    <= 8'hFF;
      low_imp_q <= 1'b0;
    end else if (en_clk_i) begin
      if (write_i) port_q <= data_i;
      low_imp_q <= write_i;
    end

  assign data_o    = !read_i ? 8'hFF : read_reg_i ? port_q : port_i;
  assign port_o    = port_q;
  assign low_imp_o = low_imp_q;

endmodule


// ----------------------------------------------------------------------------
// Port 2: quasi-bidirectional, PCH output during external fetch, 8243 nibble
// ----------------------------------------------------------------------------
module t48sv_p2 (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic [7:0] data_i,
  output logic [7:0] data_o,
  input  logic       write_p2_i,
  input  logic       write_exp_i,
  input  logic       read_p2_i,
  input  logic       read_reg_i,
  input  logic       read_exp_i,
  input  logic       output_pch_i,
  input  logic [3:0] pch_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o
);

  logic [7:0] p2_q, p2_out_q;
  logic       l_low_imp_q, h_low_imp_q, l_del_q, h_del_q, en_clk_q, output_pch_q;

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      p2_q        <= 8'hFF;
      l_low_imp_q <= 1'b0;
      h_low_imp_q <= 1'b0;
    end else if (en_clk_i) begin
      l_low_imp_q <= write_p2_i | write_exp_i;
      h_low_imp_q <= write_p2_i;
      if (write_p2_i)       p2_q      <= data_i;
      else if (write_exp_i) p2_q[3:0] <= data_i[3:0];
    end

  always_ff @(posedge xtal_i or negedge res_n_i)
    if (!res_n_i) begin
      p2_out_q     <= 8'hFF;
      l_del_q      <= 1'b0;
      h_del_q      <= 1'b0;
      output_pch_q <= 1'b0;
      en_clk_q     <= 1'b0;
    end else if (xtal_en_i) begin
      en_clk_q     <= en_clk_i;
      p2_out_q     <= {p2_q[7:4], output_pch_i ? pch_i : p2_q[3:0]};
      output_pch_q <= output_pch_i;
      l_del_q      <= en_clk_q & ((output_pch_q ^ output_pch_i) | l_low_imp_q);
      h_del_q      <= en_clk_q & h_low_imp_q;
    end

  assign data_o        = !read_p2_i ? 8'hFF : read_reg_i ? p2_q :
                         read_exp_i ? {4'h0, p2_i[3:0]} : p2_i;
  assign p2_o          = p2_out_q;
  assign p2l_low_imp_o = l_del_q;
  assign p2h_low_imp_o = h_del_q;

endmodule


// ----------------------------------------------------------------------------
// 8022 A/D converter sequencer (successive approximation, comparator external)
// ----------------------------------------------------------------------------
module t48sv_adc (
  input  logic       clk_i,
  input  logic       res_n_i,
  input  logic       en_clk_i,
  input  logic       ale_i,
  input  logic [2:0] mstate_i,
  input  logic       sel_an0_i,
  input  logic       sel_an1_i,
  input  logic       read_adc_i,
  output logic [7:0] data_o,
  output logic       sel_an_o,
  output logic       sh_o,
  output logic [7:0] sar_o,
  input  logic       comp_i
);

  localparam logic [2:0] M1 = 3'd0, M3 = 3'd2;

  // 0 = sample/hold, 1..8 = converting bit 7..0
  logic [3:0] state_q;
  logic       ale_q, sel_an_q;
  logic [7:0] sar_q, crr_q;
  logic [7:0] bit_s;     // SAR bit under test

  assign bit_s = 8'h80 >> (state_q - 4'd1);

  always_ff @(posedge clk_i or negedge res_n_i)
    if (!res_n_i) begin
      ale_q    <= 1'b0;
      sar_q    <= 8'h00;
      crr_q    <= 8'h00;
      sel_an_q <= 1'b0;
      state_q  <= 4'd0;
    end else begin
      if (ale_i)         ale_q <= 1'b1;
      else if (en_clk_i) ale_q <= ale_i;
      if (en_clk_i) begin
        if (sel_an0_i)      sel_an_q <= 1'b0;
        else if (sel_an1_i) sel_an_q <= 1'b1;
        if (state_q == 4'd0) begin
          if (ale_q) begin
            state_q <= 4'd1;
            sar_q   <= 8'h80;
          end
        end else if (state_q > 4'd8)
          state_q <= 4'd0;
        else if (mstate_i == (state_q[0] ? M1 : M3)) begin
          sar_q <= sar_q & ~bit_s | (comp_i ? bit_s : 8'h00) | (bit_s >> 1);
          if (state_q == 4'd8) crr_q <= {sar_q[7:1], comp_i};
          state_q <= (state_q == 4'd8) ? 4'd0 : state_q + 4'd1;
        end
        if (sel_an0_i || sel_an1_i) state_q <= 4'd0;
      end
    end

  assign sh_o     = (state_q == 4'd0) & ale_q & en_clk_i;
  assign sar_o    = sar_q;
  assign sel_an_o = sel_an_q;
  assign data_o   = read_adc_i ? crr_q : 8'hFF;

endmodule

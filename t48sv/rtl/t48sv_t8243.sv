// ============================================================================
// t48sv 8243 I/O expander (T48 t8243 by Arnim Laeuger; attribution in t48sv_core.sv)
//   t48sv_t8243_core         generic core, CLK_FALL_LEVEL selects the edge of the
//                            instruction-latch register (1: rising, 0: falling)
//   t48sv_t8243_sync_notri   synchronous version: PROG edges become enables
//   t48sv_t8243_async_notri  PROG itself is the clock (as the real 8243)
//   t48sv_t8243              pin-compatible tri-state version
// T48 leaves P2 / port data undefined ('-') where unselected; t48sv drives 0.
// ============================================================================

module t48sv_t8243_core #(
  parameter int clk_fall_level_g = 0
) (
  input  logic       clk_i,
  input  logic       clk_rise_en_i,
  input  logic       clk_fall_en_i,
  input  logic       reset_n_i,
  input  logic       cs_n_i,
  input  logic       prog_n_i,
  input  logic [3:0] p2_i,
  output logic [3:0] p2_o,
  output logic       p2_en_o,
  input  logic [3:0] p4_i,
  output logic [3:0] p4_o,
  output logic       p4_en_o,
  input  logic [3:0] p5_i,
  output logic [3:0] p5_o,
  output logic       p5_en_o,
  input  logic [3:0] p6_i,
  output logic [3:0] p6_o,
  output logic       p6_en_o,
  input  logic [3:0] p7_i,
  output logic [3:0] p7_o,
  output logic       p7_en_o
);

  // instruction: 0 read, 1 write, 2 ORLD, 3 ANLD (= P2[3:2] at the PROG falling edge)
  logic [1:0] instr_q;
  logic [3:0] sel_q, en_q;          // one-hot port 4..7
  logic       p2_en_q;
  logic [3:0] latch_q [0:3];
  logic [3:0] port_v, data_s;

  generate
    if (clk_fall_level_g == 1) begin : g_rise
      always_ff @(posedge clk_i or posedge cs_n_i)
        if (cs_n_i) begin
          sel_q   <= 4'b0000;
          p2_en_q <= 1'b0;
          instr_q <= 2'd1;
        end else if (clk_fall_en_i) begin
          sel_q   <= 4'b0001 << p2_i[1:0];
          p2_en_q <= p2_i[3:2] == 2'b00;
          instr_q <= p2_i[3:2];
        end
    end else begin : g_fall
      always_ff @(negedge clk_i or posedge cs_n_i)
        if (cs_n_i) begin
          sel_q   <= 4'b0000;
          p2_en_q <= 1'b0;
          instr_q <= 2'd1;
        end else if (clk_fall_en_i) begin
          sel_q   <= 4'b0001 << p2_i[1:0];
          p2_en_q <= p2_i[3:2] == 2'b00;
          instr_q <= p2_i[3:2];
        end
    end
  endgenerate

  always_ff @(posedge clk_i or negedge reset_n_i)
    if (!reset_n_i) begin
      en_q       <= 4'b0000;
      latch_q[0] <= 4'h0;
      latch_q[1] <= 4'h0;
      latch_q[2] <= 4'h0;
      latch_q[3] <= 4'h0;
    end else if (!cs_n_i && clk_rise_en_i) begin
      for (int i = 0; i < 4; i++)
        if (sel_q[i]) begin
          en_q[i] <= instr_q != 2'd0;
          if (instr_q != 2'd0) latch_q[i] <= data_s;
        end
    end

  always_comb begin
    case (sel_q)
      4'b0001: begin port_v = latch_q[0]; p2_o = p4_i; end
      4'b0010: begin port_v = latch_q[1]; p2_o = p5_i; end
      4'b0100: begin port_v = latch_q[2]; p2_o = p6_i; end
      4'b1000: begin port_v = latch_q[3]; p2_o = p7_i; end
      default: begin port_v = 4'h0;       p2_o = 4'h0; end
    endcase
    case (instr_q)
      2'd1:    data_s = p2_i;
      2'd2:    data_s = p2_i | port_v;
      2'd3:    data_s = p2_i & port_v;
      default: data_s = 4'h0;
    endcase
  end

  assign p2_en_o = !cs_n_i && !prog_n_i && p2_en_q;
  assign p4_o    = latch_q[0];
  assign p5_o    = latch_q[1];
  assign p6_o    = latch_q[2];
  assign p7_o    = latch_q[3];
  assign p4_en_o = en_q[0];
  assign p5_en_o = en_q[1];
  assign p6_en_o = en_q[2];
  assign p7_en_o = en_q[3];

endmodule


`define T48SV_8243_PORTS \
  input  logic       cs_n_i,   \
  input  logic       prog_n_i, \
  input  logic [3:0] p2_i,     \
  output logic [3:0] p2_o,     \
  output logic       p2_en_o,  \
  input  logic [3:0] p4_i,     \
  output logic [3:0] p4_o,     \
  output logic       p4_en_o,  \
  input  logic [3:0] p5_i,     \
  output logic [3:0] p5_o,     \
  output logic       p5_en_o,  \
  input  logic [3:0] p6_i,     \
  output logic [3:0] p6_o,     \
  output logic       p6_en_o,  \
  input  logic [3:0] p7_i,     \
  output logic [3:0] p7_o,     \
  output logic       p7_en_o

`define T48SV_8243_CONN \
  .cs_n_i(cs_n_i), .prog_n_i(prog_n_i), .p2_i(p2_i), .p2_o(p2_o), .p2_en_o(p2_en_o), \
  .p4_i(p4_i), .p4_o(p4_o), .p4_en_o(p4_en_o), .p5_i(p5_i), .p5_o(p5_o), .p5_en_o(p5_en_o), \
  .p6_i(p6_i), .p6_o(p6_o), .p6_en_o(p6_en_o), .p7_i(p7_i), .p7_o(p7_o), .p7_en_o(p7_en_o)

module t48sv_t8243_sync_notri (
  input  logic clk_i,
  input  logic clk_en_i,
  input  logic reset_n_i,
  `T48SV_8243_PORTS
);
  logic prog_n_q;

  always_ff @(posedge clk_i or negedge reset_n_i)
    if (!reset_n_i)    prog_n_q <= 1'b1;
    else if (clk_en_i) prog_n_q <= prog_n_i;

  t48sv_t8243_core #(.clk_fall_level_g(1)) t8243_core_b (
    .clk_i(clk_i), .clk_rise_en_i(clk_en_i & ~prog_n_q & prog_n_i),
    .clk_fall_en_i(clk_en_i & prog_n_q & ~prog_n_i), .reset_n_i(reset_n_i), `T48SV_8243_CONN
  );
endmodule

module t48sv_t8243_async_notri (
  input  logic reset_n_i,
  `T48SV_8243_PORTS
);
  t48sv_t8243_core #(.clk_fall_level_g(0)) t8243_core_b (
    .clk_i(prog_n_i), .clk_rise_en_i(1'b1), .clk_fall_en_i(1'b1), .reset_n_i(reset_n_i),
    `T48SV_8243_CONN
  );
endmodule

module t48sv_t8243 (
  input  logic       cs_n_i,
  input  logic       prog_n_i,
  inout  wire  [3:0] p2_b,
  inout  wire  [3:0] p4_b,
  inout  wire  [3:0] p5_b,
  inout  wire  [3:0] p6_b,
  inout  wire  [3:0] p7_b
);
  logic [3:0] p2_s, p4_s, p5_s, p6_s, p7_s;
  logic       p2_en_s, p4_en_s, p5_en_s, p6_en_s, p7_en_s;

  t48sv_t8243_async_notri t8243_async_notri_b (
    .reset_n_i(1'b1), .cs_n_i(cs_n_i), .prog_n_i(prog_n_i),
    .p2_i(p2_b), .p2_o(p2_s), .p2_en_o(p2_en_s), .p4_i(p4_b), .p4_o(p4_s), .p4_en_o(p4_en_s),
    .p5_i(p5_b), .p5_o(p5_s), .p5_en_o(p5_en_s), .p6_i(p6_b), .p6_o(p6_s), .p6_en_o(p6_en_s),
    .p7_i(p7_b), .p7_o(p7_s), .p7_en_o(p7_en_s)
  );

  assign p2_b = p2_en_s ? p2_s : 4'bzzzz;
  assign p4_b = p4_en_s ? p4_s : 4'bzzzz;
  assign p5_b = p5_en_s ? p5_s : 4'bzzzz;
  assign p6_b = p6_en_s ? p6_s : 4'bzzzz;
  assign p7_b = p7_en_s ? p7_s : 4'bzzzz;
endmodule

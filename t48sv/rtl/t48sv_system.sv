// ============================================================================
// Drop-in replacements for the T48 system tops (system/*_notri.vhd, t8050_wb)
// Same ports and generics as the T48 originals, plus:
//   REV2023       1 = T48 2023+ release behaviour (default), 0 = r295 (fleet)
//   ROM_INIT_FILE $readmemh image for the internal program ROM
//   RAMSTYLE      Quartus ramstyle for the internal data RAM
// (T48 by Arnim Laeuger; attribution in t48sv_core.sv)
// ============================================================================

// ----------------------------------------------------------------------------
// MCS-48 (8039 / 8048) system: core + RAM (+ ROM), shared by the drop-ins below
// ----------------------------------------------------------------------------
module t48sv_mcs48_system #(
  parameter int    gate_port_input_g = 1,
  parameter int    ROM_AW            = 0,      // 0: no internal ROM
  parameter int    RAM_AW            = 7,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_n_i,
  input  logic       t0_i,
  output logic       t0_o,
  output logic       t0_dir_o,
  input  logic       int_n_i,
  input  logic       ea_i,
  output logic       rd_n_o,
  output logic       psen_n_o,
  output logic       wr_n_o,
  output logic       ale_o,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  output logic       p1_low_imp_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s, ea_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s;
  logic [11:0] pmem_addr_s;

  t48sv_t48_core #(.REV2023(REV2023)) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_s), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  generate
    if (ROM_AW > 0) begin : g_rom
      // EA is forced high outside the internal ROM
      if (ROM_AW < 12) begin : g_ea
        assign ea_s = ea_i | (pmem_addr_s[11:ROM_AW] != '0);
      end else begin : g_ea4k
        assign ea_s = ea_i;
      end
      t48sv_rom #(.AW(ROM_AW), .INIT_FILE(ROM_INIT_FILE)) rom_b (
        .clk_i(xtal_i), .a_i(pmem_addr_s[ROM_AW-1:0]), .d_o(pmem_data_s)
      );
    end else begin : g_no_rom
      assign ea_s        = ea_i;
      assign pmem_data_s = 8'h00;
    end
  endgenerate

  t48sv_ram #(.AW(RAM_AW), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[RAM_AW-1:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


`define T48SV_MCS48_PORTS \
  input  logic       xtal_i,        \
  input  logic       xtal_en_i,     \
  input  logic       reset_n_i,     \
  input  logic       t0_i,          \
  output logic       t0_o,          \
  output logic       t0_dir_o,      \
  input  logic       int_n_i,       \
  input  logic       ea_i,          \
  output logic       rd_n_o,        \
  output logic       psen_n_o,      \
  output logic       wr_n_o,        \
  output logic       ale_o,         \
  input  logic [7:0] db_i,          \
  output logic [7:0] db_o,          \
  output logic       db_dir_o,      \
  input  logic       t1_i,          \
  input  logic [7:0] p2_i,          \
  output logic [7:0] p2_o,          \
  output logic       p2l_low_imp_o, \
  output logic       p2h_low_imp_o, \
  input  logic [7:0] p1_i,          \
  output logic [7:0] p1_o,          \
  output logic       p1_low_imp_o,  \
  output logic       prog_n_o

`define T48SV_MCS48_CONN \
  .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_n_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o), \
  .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_o), .psen_n_o(psen_n_o), \
  .wr_n_o(wr_n_o), .ale_o(ale_o), .db_i(db_i), .db_o(db_o), .db_dir_o(db_dir_o), .t1_i(t1_i), \
  .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o), \
  .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o)

module t48sv_t8039_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(0), .RAM_AW(7),
                       .REV2023(REV2023), .RAMSTYLE(RAMSTYLE)) sys (`T48SV_MCS48_CONN);
endmodule

module t48sv_t8048_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(10), .RAM_AW(6),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule

// 8049 / 8050 class parts: 2K / 4K ROM, 128 / 256 B RAM (no T48 top of their own)
module t48sv_t8049_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(11), .RAM_AW(7),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule

module t48sv_t8050_notri #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_MCS48_PORTS);
  t48sv_mcs48_system #(.gate_port_input_g(gate_port_input_g), .ROM_AW(12), .RAM_AW(8),
                       .REV2023(REV2023), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_MCS48_CONN);
endmodule


// ----------------------------------------------------------------------------
// UPI-41 systems: 8041 (1K/64B), 8041A (1K/64B), 8042AH (2K/256B) as in T48
// ----------------------------------------------------------------------------
module t48sv_upi41_system #(
  parameter int    gate_port_input_g = 1,
  parameter int    TYPE_A            = 1,
  parameter int    ROM_AW            = 10,
  parameter int    RAM_AW            = 6,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_n_i,
  input  logic       t0_i,
  input  logic       cs_n_i,
  input  logic       rd_n_i,
  input  logic       a0_i,
  input  logic       wr_n_i,
  output logic       sync_o,
  input  logic [7:0] db_i,
  output logic [7:0] db_o,
  output logic       db_dir_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  output logic       p2l_low_imp_o,
  output logic       p2h_low_imp_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  output logic       p1_low_imp_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s;
  logic [10:0] pmem_addr_s;

  t48sv_upi41_core #(.is_upi_type_a_g(TYPE_A)) upi41_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i),
    .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_i), .db_o(db_o),
    .sts_o(), .db_dir_o(db_dir_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_rom #(.AW(ROM_AW), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[ROM_AW-1:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(RAM_AW), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[RAM_AW-1:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


`define T48SV_UPI41_PORTS \
  input  logic       xtal_i,        \
  input  logic       xtal_en_i,     \
  input  logic       reset_n_i,     \
  input  logic       t0_i,          \
  input  logic       cs_n_i,        \
  input  logic       rd_n_i,        \
  input  logic       a0_i,          \
  input  logic       wr_n_i,        \
  output logic       sync_o,        \
  input  logic [7:0] db_i,          \
  output logic [7:0] db_o,          \
  output logic       db_dir_o,      \
  input  logic       t1_i,          \
  input  logic [7:0] p2_i,          \
  output logic [7:0] p2_o,          \
  output logic       p2l_low_imp_o, \
  output logic       p2h_low_imp_o, \
  input  logic [7:0] p1_i,          \
  output logic [7:0] p1_o,          \
  output logic       p1_low_imp_o,  \
  output logic       prog_n_o

`define T48SV_UPI41_CONN \
  .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_n_i(reset_n_i), .t0_i(t0_i), .cs_n_i(cs_n_i), \
  .rd_n_i(rd_n_i), .a0_i(a0_i), .wr_n_i(wr_n_i), .sync_o(sync_o), .db_i(db_i), .db_o(db_o), \
  .db_dir_o(db_dir_o), .t1_i(t1_i), .p2_i(p2_i), .p2_o(p2_o), .p2l_low_imp_o(p2l_low_imp_o), \
  .p2h_low_imp_o(p2h_low_imp_o), .p1_i(p1_i), .p1_o(p1_o), .p1_low_imp_o(p1_low_imp_o), \
  .prog_n_o(prog_n_o)

module t48sv_t8041_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(0), .ROM_AW(10),
                       .RAM_AW(6), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule

module t48sv_t8041a_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(1), .ROM_AW(10),
                       .RAM_AW(6), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule

module t48sv_t8042ah_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (`T48SV_UPI41_PORTS);
  t48sv_upi41_system #(.gate_port_input_g(gate_port_input_g), .TYPE_A(1), .ROM_AW(11),
                       .RAM_AW(8), .ROM_INIT_FILE(ROM_INIT_FILE), .RAMSTYLE(RAMSTYLE))
    sys (`T48SV_UPI41_CONN);
endmodule


// ----------------------------------------------------------------------------
// 8021 (1K / 64 B, 4-bit P2) and 8022 (2K / 64 B, A/D on AN0 / AN1)
// ----------------------------------------------------------------------------
module t48sv_t8021_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_i,
  output logic       ale_o,
  input  logic       t1_i,
  input  logic [3:0] p2_i,
  output logic [3:0] p2_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  input  logic [7:0] p0_i,
  output logic [7:0] p0_o,
  output logic       prog_n_o
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p0_out_s, p1_out_s;
  logic [3:0]  p2_out_s;
  logic [11:0] pmem_addr_s;

  // RESET is active high on the 8021 / 8022
  t48sv_t21_core t21_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(~reset_i), .ale_o(ale_o), .t1_i(t1_i),
    .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p0_i((gate_port_input_g == 1) ? (p0_i & p0_out_s) : p0_i), .p0_o(p0_out_s),
    .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s), .xtal3_o(xtal3_s),
    .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s), .dmem_data_i(dmem_data_from_s),
    .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s), .pmem_data_i(pmem_data_s)
  );

  assign p0_o = p0_out_s;
  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  t48sv_rom #(.AW(10), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[9:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(6), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[5:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule

module t48sv_t8022_notri #(
  parameter int    gate_port_input_g = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic       xtal_i,
  input  logic       xtal_en_i,
  input  logic       reset_i,
  input  logic       t0_i,
  output logic       ale_o,
  input  logic       t1_i,
  input  logic [7:0] p2_i,
  output logic [7:0] p2_o,
  input  logic [7:0] p1_i,
  output logic [7:0] p1_o,
  input  logic [7:0] p0_i,
  output logic [7:0] p0_o,
  output logic       prog_n_o,
  input  logic [7:0] an0_i,
  input  logic [7:0] an1_i
);

  logic        xtal3_s, dmem_we_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p0_out_s, p1_out_s, p2_out_s;
  logic [11:0] pmem_addr_s;
  logic        adc_sel_an_s, adc_sh_s, adc_comp_s;
  logic [7:0]  adc_sar_s, an_q;

  t48sv_t22_core t22_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_i), .reset_i(~reset_i), .ale_o(ale_o), .t0_i(t0_i),
    .t1_i(t1_i), .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p0_i((gate_port_input_g == 1) ? (p0_i & p0_out_s) : p0_i), .p0_o(p0_out_s),
    .prog_n_o(prog_n_o), .adc_sel_an_o(adc_sel_an_s), .adc_sh_o(adc_sh_s),
    .adc_sar_o(adc_sar_s), .adc_comp_i(adc_comp_s), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p0_o = p0_out_s;
  assign p1_o = p1_out_s;
  assign p2_o = p2_out_s;

  // sample & hold plus comparator of the analog front end (no reset, as in T48)
  always_ff @(posedge xtal_i)
    if (adc_sh_s) an_q <= adc_sel_an_s ? an1_i : an0_i;
  assign adc_comp_s = an_q >= adc_sar_s;

  t48sv_rom #(.AW(11), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s[10:0]), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(6), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s[5:0]), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule


// ----------------------------------------------------------------------------
// t8050_wb: 8050 (4K / 256 B) with a Wishbone master on the BUS port
// ----------------------------------------------------------------------------
module t48sv_t8050_wb #(
  parameter int    gate_port_input_g = 1,
  parameter int    REV2023           = 1,
  parameter        ROM_INIT_FILE     = "",
  parameter        RAMSTYLE          = "MLAB, no_rw_check"
) (
  input  logic        xtal_i,
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
  input  logic        t1_i,
  input  logic [7:0]  p2_i,
  output logic [7:0]  p2_o,
  output logic        p2l_low_imp_o,
  output logic        p2h_low_imp_o,
  input  logic [7:0]  p1_i,
  output logic [7:0]  p1_o,
  output logic        p1_low_imp_o,
  output logic        prog_n_o,
  output logic        wb_cyc_o,
  output logic        wb_stb_o,
  output logic        wb_we_o,
  output logic [23:0] wb_adr_o,
  input  logic        wb_ack_i,
  input  logic [7:0]  wb_dat_i,
  output logic [7:0]  wb_dat_o
);

  logic        xtal3_s, dmem_we_s, ale_s, wr_n_s, rd_n_s, xtal_en_s;
  logic [7:0]  dmem_addr_s, dmem_data_from_s, dmem_data_to_s, pmem_data_s;
  logic [7:0]  p1_out_s, p2_out_s, db_to_t48, db_from_t48, wb_dat_q;
  logic [11:0] pmem_addr_s;
  logic [23:0] adr_q;
  logic [1:0]  state_q;     // 0 idle, 1 cycle, 2 wait for RD / WR inactive
  logic        sel_adr1_s, sel_adr2_s, sel_wb_s, wr_s, rd_s;

  t48sv_t48_core #(.REV2023(REV2023)) t48_core_b (
    .xtal_i(xtal_i), .xtal_en_i(xtal_en_s), .reset_i(reset_n_i), .t0_i(t0_i), .t0_o(t0_o),
    .t0_dir_o(t0_dir_o), .int_n_i(int_n_i), .ea_i(ea_i), .rd_n_o(rd_n_s), .psen_n_o(psen_n_o),
    .wr_n_o(wr_n_s), .ale_o(ale_s), .db_i(db_to_t48), .db_o(db_from_t48), .db_dir_o(),
    .t1_i(t1_i), .p2_i((gate_port_input_g == 1) ? (p2_i & p2_out_s) : p2_i), .p2_o(p2_out_s),
    .p2l_low_imp_o(p2l_low_imp_o), .p2h_low_imp_o(p2h_low_imp_o),
    .p1_i((gate_port_input_g == 1) ? (p1_i & p1_out_s) : p1_i), .p1_o(p1_out_s),
    .p1_low_imp_o(p1_low_imp_o), .prog_n_o(prog_n_o), .clk_i(xtal_i), .en_clk_i(xtal3_s),
    .xtal3_o(xtal3_s), .dmem_addr_o(dmem_addr_s), .dmem_we_o(dmem_we_s),
    .dmem_data_i(dmem_data_from_s), .dmem_data_o(dmem_data_to_s), .pmem_addr_o(pmem_addr_s),
    .pmem_data_i(pmem_data_s)
  );

  assign p1_o   = p1_out_s;
  assign p2_o   = p2_out_s;
  assign ale_o  = ale_s;
  assign wr_n_o = wr_n_s;
  assign rd_n_o = rd_n_s;

  // Wishbone master (t48_wb_master): P2.4 = 1 selects the address registers
  assign sel_adr1_s = p2_out_s[4] && adr_q[7:0] == 8'h00;
  assign sel_adr2_s = p2_out_s[4] && adr_q[7:0] == 8'h01;
  assign sel_wb_s   = !p2_out_s[4];
  assign wr_s       = !wr_n_s;
  assign rd_s       = !rd_n_s;

  always_ff @(posedge xtal_i or negedge reset_n_i)
    if (!reset_n_i) begin
      adr_q    <= 24'h000000;
      wb_dat_q <= 8'h00;
      state_q  <= 2'd0;
    end else begin
      if (ale_s)               adr_q[7:0]   <= db_from_t48;
      if (wr_s && sel_adr1_s)  adr_q[15:8]  <= db_from_t48;
      if (wr_s && sel_adr2_s)  adr_q[23:16] <= db_from_t48;
      if (wb_ack_i)            wb_dat_q     <= wb_dat_i;
      case (state_q)
        2'd0:    state_q <= (sel_wb_s && (wr_s || rd_s)) ? 2'd1 : 2'd0;
        2'd1:    state_q <= wb_ack_i ? 2'd2 : 2'd1;
        2'd2:    state_q <= (!wr_s && !rd_s) ? 2'd0 : 2'd2;
        default: state_q <= 2'd0;
      endcase
    end

  assign wb_cyc_o  = state_q == 2'd1;
  assign wb_stb_o  = state_q == 2'd1;
  assign xtal_en_s = state_q != 2'd1;
  assign db_to_t48 = sel_adr1_s ? adr_q[15:8] : sel_adr2_s ? adr_q[23:16] : wb_dat_q;
  assign wb_adr_o  = adr_q;
  assign wb_dat_o  = db_from_t48;
  assign wb_we_o   = wr_s && sel_wb_s;

  t48sv_rom #(.AW(12), .INIT_FILE(ROM_INIT_FILE)) rom_b (
    .clk_i(xtal_i), .a_i(pmem_addr_s), .d_o(pmem_data_s)
  );

  t48sv_ram #(.AW(8), .RAMSTYLE(RAMSTYLE)) ram_b (
    .clk_i(xtal_i), .a_i(dmem_addr_s), .we_i(dmem_we_s), .d_i(dmem_data_to_s),
    .d_o(dmem_data_from_s)
  );

endmodule

// Lockstep: crtc6845sv drop-in vs the GHDL-converted fixed and stock mc6845, same stimulus.
module tb_lockstep
(
    input  logic        CLOCK,
    input  logic        CLKEN,
    input  logic        nRESET,
    input  logic        ENABLE,
    input  logic        R_nW,
    input  logic        RS,
    input  logic  [7:0] DI,
    input  logic        LPSTB,
    output logic [39:0] o_dut,
    output logic [39:0] o_fix,
    output logic [39:0] o_stk,
    output logic        fix_in_adj,
    output logic  [6:0] fix_row,
    output logic  [6:0] fix_r06,
    output logic  [6:0] fix_r04,
    output logic  [4:0] fix_r05
);

logic [7:0] d_do, f_do, s_do;
logic [13:0] d_ma, f_ma, s_ma;
logic [4:0] d_ra, f_ra, s_ra;
logic d_vs, d_hs, d_vb, d_hb, d_de, d_cu;
logic f_vs, f_hs, f_vb, f_hb, f_de, f_cu;
logic s_vs, s_hs, s_vb, s_hb, s_de, s_cu;

crtc6845sv_mc6845 dut (.CLOCK, .CLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(d_do), .VSYNC(d_vs), .HSYNC(d_hs),
    .VBLANK(d_vb), .HBLANK(d_hb), .DE(d_de), .CURSOR(d_cu), .LPSTB, .MA(d_ma), .RA(d_ra));
mc6845_fixed fix (.CLOCK, .CLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(f_do), .VSYNC(f_vs), .HSYNC(f_hs),
    .VBLANK(f_vb), .HBLANK(f_hb), .DE(f_de), .CURSOR(f_cu), .LPSTB, .MA(f_ma), .RA(f_ra));
mc6845_stock stk (.CLOCK, .CLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(s_do), .VSYNC(s_vs), .HSYNC(s_hs),
    .VBLANK(s_vb), .HBLANK(s_hb), .DE(s_de), .CURSOR(s_cu), .LPSTB, .MA(s_ma), .RA(s_ra));

// {DO, MA, RA, VSYNC, HSYNC, VBLANK, HBLANK, DE, CURSOR}  (8+14+5+6 = 33 bits)
assign o_dut = {7'd0, d_do, d_ma, d_ra, d_vs, d_hs, d_vb, d_hb, d_de, d_cu};
assign o_fix = {7'd0, f_do, f_ma, f_ra, f_vs, f_hs, f_vb, f_hb, f_de, f_cu};
assign o_stk = {7'd0, s_do, s_ma, s_ra, s_vs, s_hs, s_vb, s_hb, s_de, s_cu};

assign fix_in_adj = fix.in_adj_s;
assign fix_row    = fix.row_counter;
assign fix_r06    = fix.r06_v_displayed;
assign fix_r04    = fix.r04_v_total;
assign fix_r05    = fix.r05_v_total_adj;

endmodule

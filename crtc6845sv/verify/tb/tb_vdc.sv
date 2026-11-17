// VDC oracle bench: crtc6845sv_vdc as 8563 and 8568 on one host bus, each with its own video RAM (C++ side).
module tb_vdc
(
    input  logic        CLOCK,
    input  logic        DCLKEN,
    input  logic        nRESET,
    input  logic        ENABLE,
    input  logic        R_nW,
    input  logic        RS,
    input  logic  [7:0] DI,
    input  logic  [7:0] VDI_A,
    input  logic  [7:0] VDI_B,
    output logic [15:0] VA_A, VA_B,
    output logic  [7:0] VDO_A, VDO_B,
    output logic        VWE_A, VWE_B,
    output logic  [7:0] DO_A, DO_B,
    output logic  [3:0] RGBI_A, RGBI_B,
    output logic        DE_A, DE_B, PIXCE_A, HSYNC_A, VSYNC_A, HSYNC_B, VSYNC_B, nINTR_A, nINTR_B, CSYNC_B,
    output logic        dbg_cclk, dbg_hs, dbg_vs, dbg_line_en, dbg_line_start, dbg_pf_valid, dbg_blk, dbg_wr_pend
);

crtc6845sv_vdc #(.VARIANT(8)) a (.CLOCK, .DCLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(DO_A), .LPSTB(1'b0),
    .VA(VA_A), .VDO(VDO_A), .VWE(VWE_A), .VDI(VDI_A), .RGBI(RGBI_A), .DE(DE_A), .PIXCE(PIXCE_A), .HSYNC(HSYNC_A),
    .VSYNC(VSYNC_A), .VBLANK(), .nINTR(nINTR_A), .CSYNC());
crtc6845sv_vdc #(.VARIANT(9)) b (.CLOCK, .DCLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(DO_B), .LPSTB(1'b0),
    .VA(VA_B), .VDO(VDO_B), .VWE(VWE_B), .VDI(VDI_B), .RGBI(RGBI_B), .DE(DE_B), .PIXCE(), .HSYNC(HSYNC_B),
    .VSYNC(VSYNC_B), .VBLANK(), .nINTR(nINTR_B), .CSYNC(CSYNC_B));

assign dbg_cclk       = a.cclk;
assign dbg_hs         = a.hs;
assign dbg_vs         = a.vsync_q;
assign dbg_line_en    = a.line_en;
assign dbg_line_start = a.line_start;
assign dbg_pf_valid   = a.pf_valid;
assign dbg_blk        = a.blk_active;
assign dbg_wr_pend    = a.cpu_wr_req;

endmodule

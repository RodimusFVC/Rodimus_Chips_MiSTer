// Amstrad AMS40489 ASIC CRTC (CPC CRTC type 3).
module crtc6845sv_ams40489
(
    input  logic        CLOCK,
    input  logic        CLKEN,
    input  logic        nRESET,
    input  logic        ENABLE,
    input  logic        R_nW,
    input  logic        RS,
    input  logic  [7:0] DI,
    output logic  [7:0] DO,
    output logic        VSYNC,
    output logic        HSYNC,
    output logic        VBLANK,
    output logic        HBLANK,
    output logic        DE,
    output logic        CURSOR,
    input  logic        LPSTB,
    output logic [13:0] MA,
    output logic  [4:0] RA
);

crtc6845sv #(.VARIANT(4)) core
(
    .CLOCK(CLOCK), .CLKEN(CLKEN), .nRESET(nRESET), .ENABLE(ENABLE), .R_nW(R_nW), .RS(RS), .DI(DI), .DO(DO),
    .VSYNC(VSYNC), .HSYNC(HSYNC), .VBLANK(VBLANK), .HBLANK(HBLANK), .DE(DE), .CURSOR(CURSOR), .LPSTB(LPSTB),
    .MA(MA), .RA(RA), .PHI2(1'b0)
);

endmodule

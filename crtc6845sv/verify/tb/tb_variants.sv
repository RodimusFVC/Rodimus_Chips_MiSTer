// All crtc6845sv variants side by side on one bus, for the MAME frame-level oracle.
module tb_variants
(
    input  logic        CLOCK,
    input  logic        CLKEN,
    input  logic        nRESET,
    input  logic        ENABLE,
    input  logic        R_nW,
    input  logic        RS,
    input  logic  [7:0] DI,
    input  logic        LPSTB,
    input  logic        PHI2,
    output logic [39:0] o0, o1, o2, o3, o4, o5, o6, o7
);
`define CRTC_INST(n) \
    logic [7:0] do``n; logic [13:0] ma``n; logic [4:0] ra``n; logic vs``n, hs``n, vb``n, hb``n, de``n, cu``n; \
    crtc6845sv #(.VARIANT(n)) v``n (.CLOCK, .CLKEN, .nRESET, .ENABLE, .R_nW, .RS, .DI, .DO(do``n), .VSYNC(vs``n), \
        .HSYNC(hs``n), .VBLANK(vb``n), .HBLANK(hb``n), .DE(de``n), .CURSOR(cu``n), .LPSTB, .MA(ma``n), .RA(ra``n), .PHI2); \
    assign o``n = {7'd0, do``n, ma``n, ra``n, vs``n, hs``n, vb``n, hb``n, de``n, cu``n};
`CRTC_INST(0)
`CRTC_INST(1)
`CRTC_INST(2)
`CRTC_INST(3)
`CRTC_INST(4)
`CRTC_INST(5)
`CRTC_INST(6)
`CRTC_INST(7)
endmodule

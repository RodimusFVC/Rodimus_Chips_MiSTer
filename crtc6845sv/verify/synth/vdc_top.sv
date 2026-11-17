module vdc8563_top (input logic CLOCK, DCLKEN, nRESET, ENABLE, R_nW, RS, LPSTB, input logic [7:0] DI, VDI,
    output logic [7:0] DO, VDO, output logic [15:0] VA, output logic VWE, output logic [3:0] RGBI,
    output logic DE, PIXCE, HSYNC, VSYNC, VBLANK, nINTR, CSYNC);
crtc6845sv_vdc #(.VARIANT(8)) u (.*);
endmodule
module vdc8568_top (input logic CLOCK, DCLKEN, nRESET, ENABLE, R_nW, RS, LPSTB, input logic [7:0] DI, VDI,
    output logic [7:0] DO, VDO, output logic [15:0] VA, output logic VWE, output logic [3:0] RGBI,
    output logic DE, PIXCE, HSYNC, VSYNC, VBLANK, nINTR, CSYNC);
crtc6845sv_vdc #(.VARIANT(9)) u (.*);
endmodule

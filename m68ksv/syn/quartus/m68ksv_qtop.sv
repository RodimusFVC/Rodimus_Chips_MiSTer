// Copyright (C) 2026 Rodimus
// Quartus 17 timing / size test for m68ksv: the CPU on 8 KB of M10K (mirrored over the 16 MB space), CPU clock
// enables made inside (cen_p / cen_n = clk / 4), input pins registered, bus activity registered to output pins so
// nothing is optimised away. Revision macros: M68KSV_CPU=<value> selects the CPU parameter (default 68000; 68008,
// 68009 = 68008FN, 68001 = 68EC000, 68010, 68020, 68021 = 68EC020); M68KSV_QTOP_FX68K builds fx68k (github.com/ijor/fx68k)
// in the same top instead, as the size reference; M68KSV_RES=1 (revisions m68ksv_qtop_<cpu>_lh) builds m68ksv's
// logic-heavy setting (parameter RES = 1: fewer M10K, more ALMs, the same behaviour). On the 8-bit bus (68008, 68EC000
// with mode_pin low at reset) the RAM is addressed per byte with A0 / DS_n, data on D7-D0; mode_pin is a real input so
// both 68EC000 bus widths stay in the netlist. 68020 / 68EC020: the RAM is one 32-bit port (four byte lanes, DSACK1 /
// DSACK0 from dtack_pin, AVEC from vpa_pin), mode_pin drives CDIS so the instruction cache stays in the netlist.

module m68ksv_qtop (
    input  logic       clk,             // core clock (m68ksv_qtop.sdc: 96 MHz)
    input  logic       reset_pin,
    input  logic       dtack_pin,
    input  logic [2:0] ipl_pin,
    input  logic       vpa_pin,
    input  logic       berr_pin,
    input  logic       mode_pin,        // 68EC000 MODE (unused by the other configurations)
    output logic [7:0] bus_sig,         // XOR of every bus address / data byte
    output logic [2:0] fc_out,
    output logic       halt_out
);

`ifdef M68KSV_CPU
localparam int CPU = `M68KSV_CPU;
`else
localparam int CPU = 68000;
`endif

logic        reset_n, dtack_n, vpa_n, berr_n, mode;
logic  [2:0] ipl_n;
logic  [1:0] div;
logic        cen_p, cen_n;
always_ff @(posedge clk) begin
    reset_n <= ~reset_pin; dtack_n <= ~dtack_pin; ipl_n <= ~ipl_pin; vpa_n <= ~vpa_pin; berr_n <= ~berr_pin; mode <= mode_pin;
    div   <= div + 2'd1;
    cen_p <= div == 2'd3;
    cen_n <= div == 2'd1;
end

logic [23:1] a;
logic [15:0] dout, din;
logic        as_n, uds_n, lds_n, rw, a0, ds_n;
logic  [2:0] fc;
logic        halted_n;

`ifdef M68KSV_QTOP_FX68K
assign a0 = 1'b0; assign ds_n = 1'b1;
fx68k cpu (
    .clk(clk), .HALTn(1'b1), .extReset(~reset_n), .pwrUp(~reset_n), .enPhi1(cen_p), .enPhi2(cen_n),
    .eRWn(rw), .ASn(as_n), .LDSn(lds_n), .UDSn(uds_n), .E(), .VMAn(),
    .FC0(fc[0]), .FC1(fc[1]), .FC2(fc[2]), .BGn(), .oRESETn(), .oHALTEDn(halted_n),
    .DTACKn(dtack_n), .VPAn(vpa_n), .BERRn(berr_n), .BRn(1'b1), .BGACKn(1'b1),
    .IPL0n(ipl_n[0]), .IPL1n(ipl_n[1]), .IPL2n(ipl_n[2]), .iEdb(din), .oEdb(dout), .eab(a)
);
`else
logic        d_oe, reset_o;
logic [31:0] a32, dout32, din32;
logic  [1:0] siz;
logic        rmc_n, ecs_n, ocs_n, dben_n, ipend_n;
`ifdef M68KSV_RES
m68ksv #(.CPU(CPU), .RES(`M68KSV_RES)) cpu (       // M68KSV_RES=1: the logic-heavy setting (revisions *_lh)
`else
m68ksv #(.CPU(CPU)) cpu (
`endif
    .clk(clk), .cen_p(cen_p), .cen_n(cen_n), .RESET_n_i(reset_n), .RESET_n_o(reset_o), .HALT_n_i(reset_n),
    .HALT_n_o(halted_n), .A(a), .A0(a0), .DS_n(ds_n), .MODE(mode), .D_i(din), .D_o(dout), .D_oe(d_oe), .AS_n(as_n),
    .UDS_n(uds_n), .LDS_n(lds_n),
    .RW(rw), .FC(fc), .DTACK_n(dtack_n), .BERR_n(berr_n), .VPA_n(vpa_n), .VMA_n(), .E(), .IPL_n(ipl_n), .BR_n(1'b1),
    .BG_n(), .BGACK_n(1'b1), .dbg_fin(), .dbg_upc(), .dbg_pc(), .dbg_sr(), .dbg_ir(), .dbg_irc(), .dbg_ra(5'd0),
    .dbg_rd(), .dbg_vbr(), .dbg_sfc(), .dbg_dfc(),
    .A32(a32), .D32_i(din32), .D32_o(dout32), .SIZ(siz), .DSACK_n({dtack_n, dtack_n}), .STERM_n(1'b1), .AVEC_n(vpa_n),
    .CDIS_n(mode), .RMC_n(rmc_n), .ECS_n(ecs_n), .OCS_n(ocs_n), .DBEN_n(dben_n), .IPEND_n(ipend_n), .dbg_cacr(), .dbg_caar()
);
`endif

// 8 KB RAM as two byte lanes, written while a write strobe is active; on the 8-bit bus the lane is chosen by A0
`ifdef M68KSV_QTOP_FX68K
localparam bit B8C = 1'b0;
localparam bit Q20 = 1'b0;
`else
localparam bit B8C = (CPU == 68008) || (CPU == 68009) || (CPU == 68001);
localparam bit Q20 = (CPU == 68020) || (CPU == 68021);
`endif
genvar l;                                // Quartus 17: genvar at module scope, not inside the for (error 10170)
generate
if (Q20) begin : g_ram32
`ifndef M68KSV_QTOP_FX68K
// 68020: 8 KB as four byte lanes of a 32-bit port; a write enables the lanes from A1 / A0 for the SIZ bytes up to the
// long boundary (the 68020 data multiplexer puts each byte on its own lane for a 32-bit port)
logic [2:0] nb;
assign nb = (siz == 2'd0) ? 3'd4 : {1'b0, siz};
for (l = 0; l < 4; l = l + 1) begin : g_lane
    logic       we;
    logic [7:0] ram [2048];
    logic [7:0] rq;
    localparam logic [2:0] L3 = l;
    assign we = !as_n && !rw && !ds_n && (L3 >= {1'b0, a32[1:0]}) && (L3 < {1'b0, a32[1:0]} + nb);
    always_ff @(posedge clk) begin
        if (we) ram[a32[12:2]] <= dout32[31 - 8 * l -: 8];
        rq <= ram[a32[12:2]];
    end
    assign din32[31 - 8 * l -: 8] = rq;
end
assign din   = 16'd0;
always_ff @(posedge clk) begin
    if (!as_n) bus_sig <= bus_sig ^ a32[31:24] ^ a32[23:16] ^ a32[15:8] ^ a32[7:0] ^ dout32[31:24] ^ dout32[23:16] ^
                          dout32[15:8] ^ dout32[7:0] ^ {rw, siz, rmc_n, ecs_n, fc};
    else bus_sig <= bus_sig ^ {ocs_n, dben_n, ipend_n, 5'd0};
    fc_out   <= fc;
    halt_out <= ~halted_n;
end
`endif
end else begin : g_ram16
`ifndef M68KSV_QTOP_FX68K
assign din32 = 32'd0;
`endif
logic       mode8, bus8;
always_ff @(posedge clk) if (!reset_n) mode8 <= ~mode;        // the CPU samples MODE during reset the same way
assign bus8 = B8C && ((CPU != 68001) || mode8);
logic       we_hi, we_lo;
logic [7:0] wd_hi;
assign we_hi = !as_n && !rw && (bus8 ? (!ds_n && !a0) : !uds_n);
assign we_lo = !as_n && !rw && (bus8 ? (!ds_n && a0) : !lds_n);
assign wd_hi = bus8 ? dout[7:0] : dout[15:8];
logic [7:0] ram_hi [4096];
logic [7:0] ram_lo [4096];
logic [7:0] rq_hi, rq_lo;
logic       a0_q;
always_ff @(posedge clk) begin
    if (we_hi) ram_hi[a[12:1]] <= wd_hi;
    if (we_lo) ram_lo[a[12:1]] <= dout[7:0];
    rq_hi <= ram_hi[a[12:1]];
    rq_lo <= ram_lo[a[12:1]];
    a0_q  <= a0;
end
assign din = bus8 ? {8'h00, a0_q ? rq_lo : rq_hi} : {rq_hi, rq_lo};

always_ff @(posedge clk) begin
    if (!as_n) bus_sig <= bus_sig ^ a[23:16] ^ a[15:8] ^ {a[7:1], rw} ^ dout[15:8] ^ dout[7:0] ^ {1'b0, a0, ds_n, uds_n, lds_n, fc};
    fc_out   <= fc;
    halt_out <= ~halted_n;
end
end
endgenerate

endmodule

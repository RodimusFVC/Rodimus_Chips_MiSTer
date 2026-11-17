// Copyright (C) 2026 Rodimus
// m68ksv on the proposed master bus type (fleet_types.svh): 68000, 68008 / 68008FN (8-bit bus: o.a[0] = A0, o.ds_n),
// 68EC000 (i.mode sampled at reset; 8-bit mode as the 68008, with A0 / DS also on o.uds_n / o.lds_n), 68010 (as the
// 68000), 68020 / 68EC020 (CPU = 68020 / 68021: o.a = A31-A0 (EC020: A23-A0), o.d / i.d 32 bits, o.ds_n, o.siz,
// i.dsack_n / i.sterm_n / i.avec_n / i.cdis_n; i.dtack_n / i.vpa_n unused). Fields are assigned one by one (Quartus 17:
// no whole-struct outputs driven from a sub-instance).

module m68ksv_fleet #(
    parameter int CPU = 68000,
    parameter int RES = 0           // 0 = BRAM-heavy (default), 1 = logic-heavy (fewer M10K, more ALMs); same behaviour
) (
    input  logic    clk,
    input  logic    cen_p,
    input  logic    cen_n,
    input  m68ksv_fleet_pkg::m68k_i_t i,
    output m68ksv_fleet_pkg::m68k_o_t o
);

logic [23:1] a;
logic [15:0] d_o;
logic        d_oe, as_n, uds_n, lds_n, rw, vma_n, e, bg_n, halt_n, reset_n, a0, ds_n;
logic  [2:0] fc;
logic [31:0] a32, d32_o;
logic  [1:0] siz;
logic        rmc_n, ecs_n, ocs_n, dben_n, ipend_n;
localparam bit IS020 = (CPU == 68020) || (CPU == 68021);

m68ksv #(.CPU(CPU), .RES(RES)) cpu (
    .clk(clk), .cen_p(cen_p), .cen_n(cen_n), .RESET_n_i(i.reset_n), .RESET_n_o(reset_n), .HALT_n_i(i.halt_n),
    .HALT_n_o(halt_n), .A(a), .A0(a0), .DS_n(ds_n), .MODE(i.mode), .D_i(i.d[15:0]), .D_o(d_o), .D_oe(d_oe), .AS_n(as_n), .UDS_n(uds_n), .LDS_n(lds_n),
    .RW(rw), .FC(fc), .DTACK_n(i.dtack_n), .BERR_n(i.berr_n), .VPA_n(i.vpa_n), .VMA_n(vma_n), .E(e), .IPL_n(i.ipl_n),
    .BR_n(i.br_n), .BG_n(bg_n), .BGACK_n(i.bgack_n), .dbg_fin(), .dbg_upc(), .dbg_pc(), .dbg_sr(), .dbg_ir(),
    .dbg_irc(), .dbg_ra(5'd0), .dbg_rd(), .dbg_vbr(), .dbg_sfc(), .dbg_dfc(),
    .A32(a32), .D32_i(i.d), .D32_o(d32_o), .SIZ(siz), .DSACK_n(i.dsack_n), .STERM_n(i.sterm_n), .AVEC_n(i.avec_n),
    .CDIS_n(i.cdis_n), .RMC_n(rmc_n), .ECS_n(ecs_n), .OCS_n(ocs_n), .DBEN_n(dben_n), .IPEND_n(ipend_n), .dbg_cacr(),
    .dbg_caar()
);

assign o.a       = IS020 ? a32 : {8'd0, a, a0};
assign o.d       = IS020 ? d32_o : {16'd0, d_o};
assign o.d_oe    = d_oe;
assign o.as_n    = as_n;
assign o.uds_n   = uds_n;
assign o.lds_n   = lds_n;
assign o.ds_n    = ds_n;
assign o.rw      = rw;
assign o.siz     = siz;
assign o.fc      = fc;
assign o.rmc_n   = rmc_n;            // (constant 1 / SIZ 0 from m68ksv on the 16-bit CPUs)
assign o.ecs_n   = ecs_n;
assign o.ocs_n   = ocs_n;
assign o.dben_n  = dben_n;
assign o.ipend_n = ipend_n;
assign o.vma_n   = vma_n;
assign o.e       = e;
assign o.bg_n    = bg_n;
assign o.halt_n  = halt_n;
assign o.reset_n = reset_n;

endmodule

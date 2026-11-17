// Copyright (C) 2026 Rodimus
// m68ksv: our own 680x0 CPU core; parameter CPU selects the family member (DESIGN.md 9): 68000, 68008 (DIP48),
// 68009 (68008 PLCC52 "FN"), 68001 (68EC000; bus width from the MODE pin at reset), 68010, 68020, 68021 (68EC020).
// One clock; cen_p / cen_n are the rising / falling edges of the CPU clock as enables (like fx68k's enPhi1 / enPhi2)
// and must alternate. Oracles: Tom Harte / SingleStepTests 680x0 suite, fx68k, MAME m68000 / Musashi. Own code.

module m68ksv #(
    parameter int CPU = 68000,
    parameter int RES = 0              // control storage (DESIGN.md 3): 0 = BRAM-heavy (default: microcode and decode ROMs in
                                       // M10K, fewest ALMs), 1 = logic-heavy (two-level microcode, opcode decode in logic:
                                       // fewest M10K); the same CPU clock for clock either way
) (
    input  logic        clk,
    input  logic        cen_p,
    input  logic        cen_n,
    // reset / halt (68000 rule: external reset when both RESET_n and HALT_n are low)
    input  logic        RESET_n_i,
    output logic        RESET_n_o,     // RESET instruction (open drain in a real system)
    input  logic        HALT_n_i,
    output logic        HALT_n_o,      // double bus fault
    // bus
    output logic [23:1] A,             // 68008: A19-A1, 68008FN: A21-A1 (the rest 0)
    output logic        A0,            // 8-bit bus (68008, 68EC000 MODE = 0): address bit 0; 16-bit bus: 0
    output logic        DS_n,          // 8-bit bus: data strobe; 16-bit bus: 1
    input  logic        MODE,          // 68EC000: sampled during reset, 0 = 8-bit bus (D7-D0, UDS_n = A0, LDS_n = DS_n)
    input  logic [15:0] D_i,           // 8-bit bus: D7-D0
    output logic [15:0] D_o,
    output logic        D_oe,
    output logic        AS_n,
    output logic        UDS_n,
    output logic        LDS_n,
    output logic        RW,
    output logic  [2:0] FC,
    input  logic        DTACK_n,
    input  logic        BERR_n,
    input  logic        VPA_n,
    output logic        VMA_n,
    output logic        E,
    input  logic  [2:0] IPL_n,         // 68008 DIP48: IPL_n[2] = the combined IPL2 / IPL0 pin, IPL_n[0] unused
    input  logic        BR_n,
    output logic        BG_n,
    input  logic        BGACK_n,       // not on the 68008 DIP48 (ignored)
    // debug / state
    output logic        dbg_fin,
    output logic [10:0] dbg_upc,
    output logic [31:0] dbg_pc,
    output logic [15:0] dbg_sr,
    output logic [15:0] dbg_ir,
    output logic [15:0] dbg_irc,
    input  logic  [4:0] dbg_ra,        // register read port: 0-7 D0-D7, 8-14 A0-A6, 15 USP, 16 SSP
    output logic [31:0] dbg_rd,        // register dbg_ra as of the previous clock
    output logic [31:0] dbg_vbr,       // 68010: VBR, SFC, DFC (0 on the 68000 family)
    output logic  [2:0] dbg_sfc,
    output logic  [2:0] dbg_dfc,
    // 68020 / 68EC020 bus (the 68000 family / 68010 leave these open: outputs constant, inputs unused); AS_n, DS_n,
    // RW, FC, D_oe, BERR_n, HALT, RESET, IPL_n, BR_n / BG_n / BGACK_n are shared with the ports above
    output logic [31:0] A32,           // byte address (68EC020: A23-A0, the rest 0)
    input  logic [31:0] D32_i,
    output logic [31:0] D32_o,
    output logic  [1:0] SIZ,
    input  logic  [1:0] DSACK_n,
    input  logic        STERM_n,
    input  logic        AVEC_n,
    input  logic        CDIS_n,
    output logic        RMC_n,
    output logic        ECS_n,
    output logic        OCS_n,
    output logic        DBEN_n,
    output logic        IPEND_n,
    output logic  [1:0] dbg_cacr,      // 68020 CACR (E, F) and CAAR (0 elsewhere)
    output logic [31:0] dbg_caar
`ifdef M68KSV_TESTLOAD
    ,
    input  logic        tl_en,
    input  logic [15:0][31:0] tl_r,
    input  logic [31:0] tl_usp,
    input  logic [31:0] tl_ssp,
    input  logic [15:0] tl_sr,
    input  logic [31:0] tl_pc,
    input  logic [15:0] tl_ir,
    input  logic [15:0] tl_irc,
    output logic [10:0] tl_aeupc,
    output logic [31:0] tl_aefpc
`endif
);

generate
if (CPU != 68000 && CPU != 68008 && CPU != 68009 && CPU != 68001 && CPU != 68010 && CPU != 68020 && CPU != 68021) begin : g_unimplemented
    // members not implemented yet fail elaboration on purpose
    m68ksv_cpu_not_implemented_yet u_stop ();
end
endgenerate
localparam bit IS8 = (CPU == 68008) || (CPU == 68009);     // 68008: always the 8-bit bus
localparam bit ISEC = (CPU == 68001);                      // 68EC000: MODE latch
localparam bit DIP48 = (CPU == 68008);
localparam bit IS020 = (CPU == 68020) || (CPU == 68021);   // 32-bit bus (m68ksv_biu32)

// reset synchroniser
logic rst_q, rst;
always_ff @(posedge clk) begin
    rst_q <= ~RESET_n_i & (IS020 || ~HALT_n_i);     // 68020: RESET alone
    rst   <= rst_q;
end
// bus width: 68008 8-bit; 68EC000 MODE sampled while reset is asserted (the one run-time choice in the family)
logic mode8, bus8;
always_ff @(posedge clk) if (rst) mode8 <= ~MODE;
assign bus8 = IS8 ? 1'b1 : ISEC ? mode8 : 1'b0;
logic [2:0] ipl_pin;
logic       bgack_pin;
assign ipl_pin   = DIP48 ? {IPL_n[2], IPL_n[1], IPL_n[2]} : IPL_n;
assign bgack_pin = DIP48 ? 1'b1 : BGACK_n;

// phase generator: e1 e2 e3 e0 on alternating cen_n / cen_p; frozen before e1 (S5) for wait states and at e0 while
// a bus cycle is due to start but the bus is not available (granted away, HALT)
logic [1:0] ph;
logic       e0, e1, e2, e3, wfreeze, bus_free, bq_want, berr_hold;
generate
if (IS020) begin : g_ph020
    // 68020 / 68EC020 (checkpoint 4b): one micro-cycle per CPU clock - e0 on the rising edge, e1 one clk later, e2 on
    // the falling edge, e3 one clk later. Needs two clk or more between consecutive CPU edges (CPU clock <= clk / 4).
    logic cpd, cnd;
    always_ff @(posedge clk) begin cpd <= cen_p; cnd <= cen_n; end
    assign e1 = cpd && ph == 2'd0 && !wfreeze;
    assign e2 = cen_n && ph == 2'd1;
    assign e3 = cnd && ph == 2'd2;
end else begin : g_ph000
    assign e1 = cen_n && ph == 2'd0 && !wfreeze;
    assign e2 = cen_p && ph == 2'd1;
    assign e3 = cen_n && ph == 2'd2;
end
endgenerate
assign e0 = cen_p && ph == 2'd3 && !(bq_want && !bus_free) && !berr_hold;
always_ff @(posedge clk) begin
    if (rst) ph <= 2'd1;                            // e2 e3 first: RESET+0 starts 4 phases after reset
    else if (e0 || e1 || e2 || e3) ph <= ph + 2'd1;
end
// reset mid-instruction: the 68000 (fx68k) has made the register / CCR writes of the micro-word whose T3 (= e2) has
// passed; m68ksv makes them at e3 / e0, so the execution unit runs the rest of that word (e3 and / or e0) before its
// reset takes hold (the BIU resets at once; RESET is held for many clocks)
logic rst_d, fl_e0n, fl_e3, fl_e0, rst_eu;
always_ff @(posedge clk) begin
    rst_d  <= rst;
    fl_e0n <= rst && !rst_d && (ph == 2'd2);
end
assign fl_e3  = rst && !rst_d && (ph == 2'd2);
assign fl_e0  = (rst && !rst_d && (ph == 2'd3)) || fl_e0n;
assign rst_eu = rst && !fl_e3 && !fl_e0;

// interrupts: IPL sampled on two falling CPU edges; pending when stable and above the mask, or on a level-7 edge
// (cleared while a level-7 interrupt is acknowledged - FC = 7 with level 7 being taken, fx68k - or when stable at /
// below the mask)
logic [2:0] ipl_r, ipl_i, int_lvl, int_inl, b_fc;
logic       int_pend, nmi_prev;
logic [15:0] sr_w;
always_ff @(posedge clk) begin
    if (rst) begin
        ipl_r <= 3'd0; ipl_i <= 3'd0; int_pend <= 1'b0; nmi_prev <= 1'b0;
    end else begin
        if (cen_n) begin
            ipl_r    <= ~ipl_pin;
            ipl_i    <= ipl_r;
            nmi_prev <= ipl_i == 3'd7;
            if (ipl_i == ipl_r && ((ipl_i == 3'd7 && !nmi_prev) || ipl_i > sr_w[10:8])) int_pend <= 1'b1;
            else if ((int_inl == 3'd7 && b_fc == 3'd7) || (ipl_i == ipl_r && ipl_i != 3'd7 && !(ipl_i > sr_w[10:8])))
                int_pend <= 1'b0;
        end
    end
end

logic        bq_go, bq_byte, bq_lw, bq_rmc, bq_lock, b_abort, b_ghost, b_ghost_s2, b_dv, b_iack_av, b_iack_sp, b_berr, rsto, halted, stopped;
logic  [2:0] bq_op;
logic [31:0] b_addr;
logic [15:0] b_dout, b_din;
logic        b_uds_n, b_lds_n, b_a0;
logic  [1:0] cc_cacr;
logic        cc_clr, cc_ce;
logic  [5:0] cc_idx;

m68ksv_eu #(.CPU(CPU), .RES(RES)) eu (
    .clk(clk), .rst(rst_eu), .e0(e0 || fl_e0), .e1(e1), .e2(e2), .e3(e3 || fl_e3), .e0w(cen_p && ph == 2'd3), .ph(ph),
    .b_ghost(b_ghost), .b_ghost_s2(b_ghost_s2), .bq_go(bq_go), .bq_op(bq_op), .bq_byte(bq_byte), .bq_lw(bq_lw), .bq_rmc(bq_rmc), .bq_lock(bq_lock), .b_addr(b_addr), .b_dout(b_dout), .b_fc(b_fc),
    .b_abort(b_abort), .b_din(b_din), .b_dv(b_dv), .b_iack_av(b_iack_av), .b_iack_sp(b_iack_sp), .b_berr(b_berr),
    .ipl(ipl_i), .int_pend(int_pend), .int_lvl(int_lvl), .int_inl(int_inl), .bq_want(bq_want),
    .rsto(rsto), .halted(halted), .stopped(stopped),
    .dbg_fin(dbg_fin), .dbg_upc(dbg_upc), .dbg_pc(dbg_pc), .dbg_sr(sr_w), .dbg_ir(dbg_ir), .dbg_irc(dbg_irc),
    .dbg_ra(dbg_ra), .dbg_rd(dbg_rd), .dbg_vbr(dbg_vbr), .dbg_sfc(dbg_sfc), .dbg_dfc(dbg_dfc),
    .cc_cacr(cc_cacr), .cc_clr(cc_clr), .cc_ce(cc_ce), .cc_idx(cc_idx), .dbg_cacr(dbg_cacr), .dbg_caar(dbg_caar)
`ifdef M68KSV_TESTLOAD
    , .tl_en(tl_en), .tl_r(tl_r), .tl_usp(tl_usp), .tl_ssp(tl_ssp), .tl_sr(tl_sr), .tl_pc(tl_pc), .tl_ir(tl_ir),
    .tl_irc(tl_irc), .tl_aeupc(tl_aeupc), .tl_aefpc(tl_aefpc)
`endif
);

generate
if (IS020) begin : g_biu32
    // 68020 / 68EC020: 32-bit bus, dynamic sizing, instruction cache. The MC68EC020 has no ECS, OCS, DBEN, IPEND or BGACK
    // (MC68020 User's Manual Table 3-2 p. 3-8; two-wire arbitration, 5.7.2 p. 5-70): those outputs stay negated, BGACK_n
    // is ignored (cp5)
    localparam bit EC = (CPU == 68021);
    logic [31:0] a32;
    logic        ds32_n, ecs32_n, ocs32_n, dben32_n;
    m68ksv_biu32 biu (
        .clk(clk), .rst(rst), .cen_p(cen_p), .cen_n(cen_n), .e0(e0), .e1(e1), .e2(e2), .e3(e3), .ph(ph),
        .go(bq_go), .op(bq_op), .byte_i(bq_byte), .lw_i(bq_lw), .rmc_i(bq_rmc), .lock_i(bq_lock), .addr(b_addr), .dout(b_dout),
        .abort(b_abort), .fc2(b_fc[2]), .cc_cacr(cc_cacr), .cc_clr(cc_clr), .cc_ce(cc_ce), .cc_idx(cc_idx), .cdis_n(CDIS_n),
        .din(b_din), .dv(b_dv), .iack_av(b_iack_av), .iack_sp(b_iack_sp), .berr_cyc(b_berr), .wfreeze(wfreeze),
        .bus_free(bus_free), .berr_hold(berr_hold),
        .a_o(a32), .d_o(D32_o), .d_oe(D_oe), .d_i(D32_i), .siz(SIZ), .as_n(AS_n), .ds_n(ds32_n), .rw(RW), .rmc_n(RMC_n),
        .ecs_n(ecs32_n), .ocs_n(ocs32_n), .dben_n(dben32_n), .dsack_n(DSACK_n), .sterm_n(STERM_n), .avec_n(AVEC_n),
        .berr_n(BERR_n), .br_n(BR_n), .bg_n(BG_n), .bgack_n(EC ? 1'b1 : BGACK_n), .halt_n(HALT_n_i)
    );
    assign ECS_n   = EC ? 1'b1 : ecs32_n;
    assign OCS_n   = EC ? 1'b1 : ocs32_n;
    assign DBEN_n  = EC ? 1'b1 : dben32_n;
    assign A32     = (CPU == 68021) ? {8'd0, a32[23:0]} : a32;
    assign A       = a32[23:1];
    assign A0      = a32[0];
    assign DS_n    = ds32_n;
    assign UDS_n   = 1'b1;
    assign LDS_n   = 1'b1;
    assign D_o     = 16'd0;
    assign VMA_n   = 1'b1;
    assign E       = 1'b0;
    assign IPEND_n = EC ? 1'b1 : ~int_pend;
end else begin : g_biu16
    m68ksv_biu biu (
        .clk(clk), .rst(rst), .cen_p(cen_p), .cen_n(cen_n), .e0(e0), .e1(e1), .e2(e2), .e3(e3), .ph(ph), .bus8(bus8),
        .go(bq_go), .op(bq_op), .byte_i(bq_byte), .addr(b_addr), .dout(b_dout), .abort(b_abort), .ghost(b_ghost), .ghost_s2(b_ghost_s2),
        .din(b_din), .dv(b_dv), .iack_av(b_iack_av), .iack_sp(b_iack_sp), .berr_cyc(b_berr), .wfreeze(wfreeze),
        .bus_free(bus_free), .berr_hold(berr_hold),
        .d_o(D_o), .d_oe(D_oe), .d_i(D_i), .as_n(AS_n), .uds_n(b_uds_n), .lds_n(b_lds_n), .a0(b_a0), .rw(RW),
        .dtack_n(DTACK_n), .berr_n(BERR_n), .vpa_n(VPA_n), .vma_n(VMA_n), .e_clk(E),
        .br_n(BR_n), .bg_n(BG_n), .bgack_n(bgack_pin), .halt_n(HALT_n_i)
    );
    // address pins per package; 8-bit bus strobes: 68008 DS_n / A0, 68EC000 8-bit mode on the UDS_n / LDS_n pins
    assign A         = (CPU == 68008) ? {4'd0, b_addr[19:1]} : (CPU == 68009) ? {2'd0, b_addr[21:1]} : b_addr[23:1];
    assign A0        = b_a0;
    assign DS_n      = bus8 ? (b_uds_n & b_lds_n) : 1'b1;
    assign UDS_n     = IS8 ? 1'b1 : bus8 ? b_a0 : b_uds_n;          // 68EC000 8-bit: the pin carries A0
    assign LDS_n     = IS8 ? 1'b1 : bus8 ? (b_uds_n & b_lds_n) : b_lds_n;
    assign A32       = 32'd0;
    assign D32_o     = 32'd0;
    assign SIZ       = 2'd0;
    assign RMC_n     = 1'b1;
    assign ECS_n     = 1'b1;
    assign OCS_n     = 1'b1;
    assign DBEN_n    = 1'b1;
    assign IPEND_n   = 1'b1;
end
endgenerate
assign FC        = b_fc;
assign dbg_sr    = sr_w;
assign RESET_n_o = ~rsto;
assign HALT_n_o  = ~halted;

endmodule

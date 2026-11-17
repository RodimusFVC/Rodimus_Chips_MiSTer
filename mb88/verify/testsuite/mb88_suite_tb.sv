// DUT wrapper for the MB88 differential test suite.
//
// Wraps rtl/cpu/mb88_sv/mb88_core.sv with the program ROM the core expects
// externally, plus taps for every piece of architectural state so the driver can
// diff against MAME. Taps are read hierarchically (the z8002_suite_tb pattern),
// so mb88_core.sv itself needs no edits.
//
// ce is driven every clock by the harness, so "cycles per instruction" here means
// ce pulses consumed between retires -- which is exactly the quantity that must
// match MAME's burn_cycles(oc). The core has `reg [1:0] state` and latches op1 for
// two-byte instructions, so this is measured, not assumed.
//
// ena_timer is driven by the harness rather than mb88.sv's ÷32 prescaler, so the
// timer can be exercised deterministically (one pulse = one prescaler expiry).

module mb88_suite_tb (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        ce,
    input  wire        ena_timer,

    // pins
    input  wire [3:0]  k_in,
    input  wire [15:0] r_in,
    input  wire        si_in,
    input  wire        irq_n,
    input  wire        tc_in,

    // port outputs
    output wire [15:0] r_out_tap,
    output wire [3:0]  p_out_tap,
    output wire [7:0]  o_out_tap,
    output wire        o_wr_tap,
    output wire        so_out_tap,

    // architectural state
    output wire [10:0] dbg_pc,
    output wire [10:0] dbg_fetch_pc,
    output wire [3:0]  a_tap, x_tap, y_tap,
    output wire        st_tap, zf_tap, cf_tap, vf_tap, sf_tap, if_tap,
    output wire [1:0]  si_tap,
    output wire [3:0]  th_tap, tl_tap, sb_tap,
    output wire [7:0]  pio_tap,
    output wire [15:0] sp0_tap, sp1_tap, sp2_tap, sp3_tap,
    output wire [2:0]  pend_tap,
    output wire        inirq_tap,
    output wire        retire_tap,
    output wire        illegal_tap,
    output wire [511:0] ram_tap
);
    // ---- program ROM: byte-wide, 11-bit address, loaded by the driver --------
    reg [7:0] prog [0:2047] /* verilator public */;
    wire [10:0] prog_addr;
    wire [7:0]  prog_data = prog[prog_addr];

    assign r_out_tap  = r_out;
    assign p_out_tap  = p_out;
    assign o_out_tap  = o_out;
    assign o_wr_tap   = o_wr;
    assign so_out_tap = so_out;

    wire [15:0] r_out;
    wire [3:0]  p_out;
    wire [7:0]  o_out;
    wire        so_out;
    // Kangaroo's / ChampionBaseball's copy of mb88_core predates the o_wr O-port
    // strobe that PolePosition's namco_51xx.sv needs. Build with
    // +define+MB88_NO_OWR to validate those copies through this same suite.
`ifdef MB88_NO_OWR
    wire        o_wr = 1'b0;
`else
    wire        o_wr;
`endif

    // ---- hierarchical taps into the core's state ---------------------------
    assign st_tap  = mb88_i.st;
    assign zf_tap  = mb88_i.zf;
    assign cf_tap  = mb88_i.cf;
    assign vf_tap  = mb88_i.vf;
    assign sf_tap  = mb88_i.sf;
    assign if_tap  = mb88_i.iflag;
    assign si_tap  = mb88_i.SI;
    assign th_tap  = mb88_i.TH;
    assign tl_tap  = mb88_i.TL;
    assign sb_tap  = mb88_i.SB;
    assign pio_tap = mb88_i.pio;
    assign sp0_tap = mb88_i.SP[0];
    assign sp1_tap = mb88_i.SP[1];
    assign sp2_tap = mb88_i.SP[2];
    assign sp3_tap = mb88_i.SP[3];
    assign pend_tap  = mb88_i.pending_irq;
    assign inirq_tap = mb88_i.in_irq;

    mb88_core mb88_i
    (
        .clk        (clk),
        .ce         (ce),
        .reset_n    (reset_n),
        .ena_timer  (ena_timer),
        .prog_addr  (prog_addr),
        .prog_data  (prog_data),
        .k_in       (k_in),
        .r_in       (r_in),
        .r_out      (r_out),
        .p_out      (p_out),
        .o_out      (o_out),
`ifndef MB88_NO_OWR
        .o_wr       (o_wr),
`endif
        .si_in      (si_in),
        .so_out     (so_out),
        .irq_n      (irq_n),
        .tc_in      (tc_in),
        .int_req    (1'b0),
        .int_vec    (6'd0),
        .dbg_pc         (dbg_pc),
        .dbg_fetch_pc   (dbg_fetch_pc),
        .dbg_a          (a_tap),
        .dbg_x          (x_tap),
        .dbg_y          (y_tap),
        .dbg_st         (),
        .dbg_zf         (),
        .dbg_cf         (),
        .dbg_retire     (retire_tap),
        .dbg_int_ack    (),
        .dbg_illegal    (illegal_tap),
        .dbg_ram        (ram_tap)
    );
endmodule

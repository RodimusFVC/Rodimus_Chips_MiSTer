// Lockstep top: GHDL-converted sgs2650 (reference) and s2650sv on the same inputs (verification only)
/* verilator lint_off DECLFILENAME */
module tb_top #(parameter bit VER_B = 1'b0, parameter bit RAS_MLAB = 1'b1) (
    input  logic        clk, reset, ack, irq, sense,
    input  logic  [7:0] dr, ivec,
    output logic        r_req, r_wr, r_mio, r_ene, r_dc, r_intack, r_flag,
    output logic [14:0] r_ad,
    output logic  [7:0] r_dw,
    output logic  [1:0] r_ph,
    output logic        d_req, d_wr, d_mio, d_ene, d_dc, d_intack, d_flag,
    output logic [14:0] d_ad,
    output logic  [7:0] d_dw,
    output logic  [1:0] d_ph,
    // architectural state probes: {r0,r1,r2,r3,r1b,r2b,r3b,psl,psu}, iar, ras, state
    output logic [71:0] r_regs, d_regs,
    output logic [14:0] r_iar, d_iar,
    output logic [119:0] r_ras, d_ras,
    output logic  [3:0] r_state,
    output logic [10:0] d_state
);
    generate
        if (!VER_B) begin : g_a
            ref_s2650_cpu rf (.clk, .reset, .ack, .dr, .irq, .ivec, .sense, .req(r_req), .ad(r_ad), .wr(r_wr),
                               .dw(r_dw), .mio(r_mio), .ene(r_ene), .dc(r_dc), .ph(r_ph), .intack(r_intack), .flag(r_flag));
            assign r_regs = {rf.cpu.r0, rf.cpu.r1, rf.cpu.r2, rf.cpu.r3, rf.cpu.r1b, rf.cpu.r2b, rf.cpu.r3b,
                             rf.cpu.psl, rf.cpu.psu};
            assign r_iar = rf.cpu.iar;
            assign r_state = rf.cpu.state;
            assign r_ras = {rf.cpu.ras[7], rf.cpu.ras[6], rf.cpu.ras[5], rf.cpu.ras[4],
                            rf.cpu.ras[3], rf.cpu.ras[2], rf.cpu.ras[1], rf.cpu.ras[0]};
        end else begin : g_b
            ref_b_cpu rf (.clk, .reset, .ack, .dr, .irq, .ivec, .sense, .req(r_req), .ad(r_ad), .wr(r_wr),
                           .dw(r_dw), .mio(r_mio), .ene(r_ene), .dc(r_dc), .ph(r_ph), .intack(r_intack), .flag(r_flag));
            assign r_regs = {rf.cpu.r0, rf.cpu.r1, rf.cpu.r2, rf.cpu.r3, rf.cpu.r1b, rf.cpu.r2b, rf.cpu.r3b,
                             rf.cpu.psl, rf.cpu.psu};
            assign r_iar = rf.cpu.iar;
            assign r_state = rf.cpu.state;
            assign r_ras = {rf.cpu.ras[7], rf.cpu.ras[6], rf.cpu.ras[5], rf.cpu.ras[4],
                            rf.cpu.ras[3], rf.cpu.ras[2], rf.cpu.ras[1], rf.cpu.ras[0]};
        end
    endgenerate

    s2650sv #(.VER_B(VER_B), .RAS_MLAB(RAS_MLAB)) dut (.clk, .reset, .ack, .dr, .irq, .ivec, .sense,
        .req(d_req), .ad(d_ad), .wr(d_wr), .dw(d_dw), .mio(d_mio), .ene(d_ene), .dc(d_dc), .ph(d_ph),
        .intack(d_intack), .flag(d_flag));

    assign d_regs = {dut.r0, dut.r1, dut.r2, dut.r3, dut.r1b, dut.r2b, dut.r3b, dut.psl, dut.psu};
    assign d_iar = dut.iar;
    assign d_state = dut.st;
    generate
        if (RAS_MLAB) begin : g_dm
            assign d_ras = {dut.g_ras_mlab.ras[7], dut.g_ras_mlab.ras[6], dut.g_ras_mlab.ras[5], dut.g_ras_mlab.ras[4],
                            dut.g_ras_mlab.ras[3], dut.g_ras_mlab.ras[2], dut.g_ras_mlab.ras[1], dut.g_ras_mlab.ras[0]};
        end else begin : g_dr
            assign d_ras = {dut.g_ras_reg.ras[7], dut.g_ras_reg.ras[6], dut.g_ras_reg.ras[5], dut.g_ras_reg.ras[4],
                            dut.g_ras_reg.ras[3], dut.g_ras_reg.ras[2], dut.g_ras_reg.ras[1], dut.g_ras_reg.ras[0]};
        end
    endgenerate
endmodule

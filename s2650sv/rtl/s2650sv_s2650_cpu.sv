//------------------------------------------------------------------------------
// s2650sv_s2650_cpu : drop-in for the fleet's s2650_cpu wrapper (sgs2650, TEMlib "DO"),
// same ports, no parameters, 2650A
//------------------------------------------------------------------------------

module s2650sv_s2650_cpu (
    input  logic        clk,
    input  logic        reset,
    output logic        req,
    input  logic        ack,
    output logic [14:0] ad,
    output logic        wr,
    output logic  [7:0] dw,
    input  logic  [7:0] dr,
    output logic        mio,
    output logic        ene,
    output logic        dc,
    output logic  [1:0] ph,
    input  logic        irq,
    output logic        intack,
    input  logic  [7:0] ivec,
    input  logic        sense,
    output logic        flag
);

    s2650sv #(.VER_B(1'b0)) cpu (
        .clk(clk), .reset(reset), .req(req), .ack(ack), .ad(ad), .wr(wr), .dw(dw), .dr(dr),
        .mio(mio), .ene(ene), .dc(dc), .ph(ph), .irq(irq), .intack(intack), .ivec(ivec),
        .sense(sense), .flag(flag)
    );

endmodule

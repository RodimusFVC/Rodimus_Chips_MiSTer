//------------------------------------------------------------------------------
// s2650sv_pool : s2650sv on the fleet bus types (chip_pool_pkg::s2650_i_t / s2650_o_t),
// ivec fixed per board, flag unused. For the Pacman package (reset_n instead of reset)
// change the one marked line to .reset(~i.reset_n).
//------------------------------------------------------------------------------

module s2650sv_pool #(
    parameter logic [7:0] IVEC = 8'h03
) (
    input  logic                     clk,
    input  chip_pool_pkg::s2650_i_t  i,
    output chip_pool_pkg::s2650_o_t  o
);

    wire        req, wr, mio, ene, dc, intack;
    wire [14:0] ad;
    wire  [7:0] dw;
    wire  [1:0] ph;

    s2650sv #(.VER_B(1'b0)) cpu (
        .clk(clk),
        .reset(i.reset),        // Pacman: .reset(~i.reset_n)
        .req(req), .ack(i.ack), .ad(ad), .wr(wr), .dw(dw), .dr(i.dr), .mio(mio), .ene(ene), .dc(dc), .ph(ph),
        .irq(i.irq), .intack(intack), .ivec(IVEC), .sense(i.sense), .flag()
    );

    assign o.req = req;  assign o.ad  = ad;   assign o.wr = wr;  assign o.dw     = dw;     assign o.mio = mio;
    assign o.ene = ene;  assign o.dc  = dc;   assign o.ph = ph;  assign o.intack = intack;

endmodule

// s2650_cpu port shim around the GHDL-converted sgs2650 with VER_B=true (verification only)
module ref_b_cpu(input clk, input reset, input ack, input [7:0] dr, input irq, input [7:0] ivec, input sense,
                 output req, output [14:0] ad, output wr, output [7:0] dw, output mio, output ene, output dc,
                 output [1:0] ph, output intack, output flag);
  ref_sgs2650_b cpu(.ack(ack), .dr(dr), .\int (irq), .ivec(ivec), .sense(sense), .reset(reset), .clk(clk),
                    .reset_na(1'b1), .req(req), .ad(ad), .wr(wr), .dw(dw), .mio(mio), .ene(ene), .dc(dc), .ph(ph),
                    .intack(intack), .flag(flag));
endmodule

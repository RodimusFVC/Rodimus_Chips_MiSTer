// tb.sv - all seven sn76489sv variants side by side on one write stream (verify/run.sh).
module tb (
    input  logic        clk,
    input  logic        rst,
    input  logic        ce,
    input  logic        wr_n,
    input  logic  [7:0] din,
    output logic  [6:0] tick,            // variant v ticked on this edge (sampled after it)
    output logic [27:0] outs,            // 4 output bits per variant
    output logic  [6:0] ready,
    output logic [76:0] sound            // 11 bits per variant
);
    for (genvar v = 0; v < 7; v++) begin : g
        logic signed [10:0] s;
        sn76489sv #(.VARIANT(v)) psg (.rst(rst), .clk(clk), .ce(ce), .wr_n(wr_n), .cs_n(wr_n), .din(din),
                                      .sound(s), .ready(ready[v]));
        assign tick[v]          = psg.tick;
        assign outs[4*v +: 4]   = psg.out;
        assign sound[11*v +: 11] = s;
    end
endmodule

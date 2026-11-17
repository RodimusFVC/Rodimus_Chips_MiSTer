module tdflt;
logic clk = 0, rst_n = 0;
wire [15:0] a; wire [7:0] dout; wire m1, mreq, iorq, rd, wr, rfsh;
// Tutankham-style instance: WAIT_n, NMI_n, BUSRQ_n, OUT0 left unconnected (VHDL defaults)
t80sv_T80s c8 (.RESET_n(rst_n), .CLK(clk), .CEN(1'b1), .INT_n(1'b1), .M1_n(m1), .MREQ_n(mreq), .IORQ_n(iorq),
    .RD_n(rd), .WR_n(wr), .RFSH_n(rfsh), .A(a), .DI(8'h00), .DO(dout));
initial begin
    repeat (4) begin #5 clk = 1; #5 clk = 0; end
    rst_n = 1;
    repeat (200) begin #5 clk = 1; #5 clk = 0; end
    $display("A after 200 clocks of NOPs: %04x (expect PC ~0032)", a);
    if (a < 16'h0030) $fatal(1, "CPU did not run: defaults not applied");
    $finish;
end
endmodule

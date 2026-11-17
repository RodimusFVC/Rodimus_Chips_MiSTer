// Copyright (C) 2026 Rodimus
// m68ksv: one copy of the register file (32 x 32 bits, two MLABs): one write port, one read port with a read
// address registered every clock and an unregistered output (rd = entry addressed at the previous clock edge).
// The execution unit keeps several copies with a common write port, one per group of read ports (DESIGN.md 4).
// no_rw_check: no consumer samples rd in the clock after a write to the address registered at that same edge
// (M68KSV_SIMCHECK makes the simulation return garbage in exactly that case, so a violation fails the suite).
// No HDL init (an init blocks MLAB inference; the 68000 registers are undefined after reset anyway). Own code.

module m68ksv_rf (
    input  logic        clk,
    input  logic        we,
    input  logic  [4:0] wa,
    input  logic [31:0] wd,
    input  logic  [4:0] ra,
    output logic [31:0] rd
);

(* ramstyle = "MLAB, no_rw_check" *) logic [31:0] mem [0:31];
logic [4:0] ra_q;

always_ff @(posedge clk) begin
    if (we) mem[wa] <= wd;
    ra_q <= ra;
end

`ifdef M68KSV_SIMCHECK
logic coll;
always_ff @(posedge clk) coll <= we && (wa == ra);
assign rd = coll ? 32'hdead_beef : mem[ra_q];
`else
assign rd = mem[ra_q];
`endif

endmodule

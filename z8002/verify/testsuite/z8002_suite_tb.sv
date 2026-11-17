// DUT wrapper for the z8002 differential test suite.
//
// Derived from verilator/z8002_optest/z8002_optest_tb.sv (proven harness) with the
// write bus exposed, so the driver can record exactly which words the RTL wrote
// instead of diffing all 64 KB per test.
//
// Memory is word-indexed with a combinational read, matching the contract every
// *_FETCH/*_RD state pair in z8002.sv assumes. A full-word write is correct even
// for byte stores: z8002.sv:2304 implements those as a word-aligned read-modify-
// write (which is also why the unconnected `wordacc` is safe here) -- see the
// "Open contract gap -- wordacc" entry in the core's Claude note.

module z8002_suite_tb (
    input  wire clk,
    input  wire reset_n,
    output wire [15:0] dbg_pc,
    output wire [15:0] dbg_fcw,
    output wire        dbg_retire,
    output wire        dbg_illegal,
    output wire [15:0] addr_tap,
    output wire [15:0] dout_tap,
    output wire        mreq_tap,
    output wire        we_tap,
    output wire        iorq_tap,
    output wire        wordacc_tap,
    output wire [15:0] target_cycles_tap,
    output wire [15:0] cyc_count_tap
);
    assign target_cycles_tap = z8002_i.target_cycles;
    assign cyc_count_tap     = z8002_i.cyc_count;
    wire [15:0] addr, dout;
    reg  [15:0] din;
    wire        mreq, iorq, we, wordacc;
    wire [15:0] dbg_ir;
    wire [255:0] dbg_regs /* verilator public */;

    assign addr_tap    = addr;
    assign dout_tap    = dout;
    assign mreq_tap    = mreq;
    assign we_tap      = we;
    assign iorq_tap    = iorq;
    assign wordacc_tap = wordacc;

    reg [15:0] mem [0:32767] /* verilator public */;

    always @(*) din = mem[addr[15:1]];

    always @(posedge clk) begin
        if (we && mreq) mem[addr[15:1]] <= dout;
    end

    z8002 z8002_i (
        .clk(clk), .ce(1'b1), .reset_n(reset_n),
        .addr(addr), .dout(dout), .din(din),
        .mreq(mreq), .iorq(iorq), .we(we), .wordacc(wordacc),
        .wait_n(1'b1), .nmi_n(1'b1), .nvi_n(1'b1), .vi_n(1'b1),
        .dbg_pc(dbg_pc), .dbg_fcw(dbg_fcw), .dbg_ir(dbg_ir),
        .dbg_retire(dbg_retire), .dbg_illegal(dbg_illegal),
        .dbg_regs(dbg_regs)
    );
endmodule

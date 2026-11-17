// Minimal standalone Verilator harness for the z8002 core, built to unit-test the
// BATCH 8 2026-07-27 opcodes (0x71 LD rd,rs(rx); 0x5D indexed LDL store; 0xB0 DAB)
// with hand-known expected values, WITHOUT running the full PolePosition boot (those
// three opcodes only occur 69-96% deep into the real MAME boot trace -- full-boot
// co-sim would need tens of millions more cycles than reached so far this session).
// Real production z8002.sv wired directly; memory is a simple combinational-read /
// clocked-write behavioral array (matches the "read reflects mem[addr] same cycle
// addr changes" contract every existing *_FETCH/*_RD state pair in z8002.sv assumes).
module z8002_optest_tb (
    input  wire clk,
    input  wire reset_n,
    output wire [15:0] dbg_pc,
    output wire [15:0] dbg_fcw,
    output wire        dbg_retire,
    output wire        dbg_illegal,
    output wire [15:0] addr_tap,
    output wire [15:0] din_tap,
    output wire        mreq_tap,
    output wire        we_tap,
    output wire [15:0] target_cycles_tap,
    output wire [15:0] cyc_count_tap
);
    assign target_cycles_tap = z8002_i.target_cycles;
    assign cyc_count_tap     = z8002_i.cyc_count;
    wire [15:0] addr, dout;
    reg  [15:0] din;
    assign addr_tap = addr;
    assign din_tap  = din;
    assign mreq_tap = mreq;
    assign we_tap   = we;
    wire        mreq, iorq, we, wordacc;
    wire [15:0] dbg_ir;
    wire [255:0] dbg_regs /* verilator public */;

    // z8002's `addr` is a BYTE address (bit0 always 0 for word ops, matching real
    // Z8002 semantics -- confirmed against PolePosition_subcpu.sv's own convention,
    // e.g. `sub1_rom_idx = sub1_addr[13:1]`). This array is WORD-indexed, so drop
    // the byte-select bit rather than using `addr` directly.
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

// Copyright (C) 2026 Rodimus
// Quartus 17 timing / size test for x86sv: the CPU on 8 KB of M10K (mirrored over 1 MB), ce = clk / 4, every
// input pin registered, I/O writes and bus activity registered to output pins so nothing is optimised away.
// Configuration (revision VERILOG_MACRO): none = 8088, X86SV_BUS16 = 8086, X86SV_NEC = V20, both = V30; X86SV_NEC8080
// adds the 8080 emulation mode to V20 / V30.

module x86sv_qtop (
    input  logic       clk,             // core clock (x86sv_qtop.sdc: 80 MHz)
    input  logic       reset_pin,
    input  logic       ready_pin,
    input  logic       intr_pin,
    input  logic       nmi_pin,
    input  logic       test_n_pin,
    output logic [7:0] port_out,        // last byte written to any I/O port
    output logic [7:0] bus_sig,         // XOR of every bus address / data byte
    output logic       lock_out,
    output logic [1:0] qs_out
);

logic        reset, ready, intr, nmi, test_n;
logic  [1:0] div;
logic        ce;
always_ff @(posedge clk) begin
    reset <= reset_pin; ready <= ready_pin; intr <= intr_pin; nmi <= nmi_pin; test_n <= test_n_pin;
    div <= div + 2'd1;
    ce <= div == 2'd3;
end

logic [19:0] ad;
logic        ale, rd, wra, wr, io, inta, lock;
logic  [2:0] s20, tstate;
logic  [1:0] seg_s, qs;
logic        seg_v;
logic  [7:0] qs_byte;
logic [15:0] dbg_ip, dbg_flags;
logic [7:0][15:0] dbg_r;
logic [3:0][15:0] dbg_s;
`ifdef X86SV_NEC
localparam bit NEC = 1'b1;
`else
localparam bit NEC = 1'b0;
`endif
`ifdef X86SV_NEC8080
localparam bit NEC8080 = 1'b1;
`else
localparam bit NEC8080 = 1'b0;
`endif

`ifdef X86SV_BUS16
logic        bhe_n;
logic [15:0] dout, din;

x86sv16 #(.NEC(NEC), .NEC8080(NEC8080)) cpu (
    .clk(clk), .ce(ce), .reset(reset), .ad(ad), .bhe_n(bhe_n), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s),
    .seg_v(seg_v), .rd(rd), .wra(wra), .wr(wr), .io(io), .inta(inta), .dout(dout), .din(din), .ready(ready), .intr(intr),
    .nmi(nmi), .test_n(test_n), .lock(lock), .qs(qs), .qs_byte(qs_byte), .dbg_ip(dbg_ip), .dbg_flags(dbg_flags),
    .dbg_r(dbg_r), .dbg_s(dbg_s)
);

// 8 KB RAM as two 4 KB byte lanes, address and BHE taken at ALE, written in the data clock of a memory write
logic  [7:0] ram_lo [4096];
logic  [7:0] ram_hi [4096];
logic [12:0] ra;
logic        rb;
logic  [7:0] rq_lo, rq_hi;
always_ff @(posedge clk) begin
    if (ale) begin ra <= ad[12:0]; rb <= bhe_n; end
    if (ce & wr & ~io & ready & ~ra[0]) ram_lo[ra[12:1]] <= dout[7:0];
    if (ce & wr & ~io & ready & ~rb) ram_hi[ra[12:1]] <= dout[15:8];
    rq_lo <= ram_lo[ale ? ad[12:1] : ra[12:1]];
    rq_hi <= ram_hi[ale ? ad[12:1] : ra[12:1]];
end
assign din = io ? {ra[7:0], ra[7:0]} : {rq_hi, rq_lo};

always_ff @(posedge clk) begin
    if (ce & wr & io & ready) port_out <= dout[7:0] ^ dout[15:8];
    if (ce) bus_sig <= bus_sig ^ ad[19:12] ^ ad[11:4] ^ dout[7:0] ^ dout[15:8] ^ {s20, seg_s, qs[1], bhe_n, inta};
    lock_out <= lock;
    qs_out <= qs;
end
`else
logic  [7:0] dout, din;

x86sv #(.NEC(NEC), .NEC8080(NEC8080)) cpu (
    .clk(clk), .ce(ce), .reset(reset), .ad(ad), .ale(ale), .s20(s20), .tstate(tstate), .seg_s(seg_s), .seg_v(seg_v),
    .rd(rd), .wra(wra), .wr(wr), .io(io), .inta(inta), .dout(dout), .din(din), .ready(ready), .intr(intr), .nmi(nmi),
    .test_n(test_n), .lock(lock), .qs(qs), .qs_byte(qs_byte), .dbg_ip(dbg_ip), .dbg_flags(dbg_flags), .dbg_r(dbg_r),
    .dbg_s(dbg_s)
);

// 8 KB RAM, address taken at ALE, written in the data clock of a memory write
logic  [7:0] ram [8192];
logic [12:0] ra;
logic  [7:0] rq;
always_ff @(posedge clk) begin
    if (ale) ra <= ad[12:0];
    if (ce & wr & ~io & ready) ram[ra] <= dout;
    rq <= ram[ale ? ad[12:0] : ra];
end
assign din = io ? ra[7:0] : rq;

always_ff @(posedge clk) begin
    if (ce & wr & io & ready) port_out <= dout;
    if (ce) bus_sig <= bus_sig ^ ad[19:12] ^ ad[11:4] ^ dout ^ {s20, seg_s, qs, inta};
    lock_out <= lock;
    qs_out <= qs;
end
`endif

endmodule

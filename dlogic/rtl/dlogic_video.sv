//============================================================================
//
//  Video stage for dlogic_engine: framebuffer + native raster + colour overlay.
//  The engine's pixel / line / frame events are written into a framebuffer (MAME's visible window of the board's
//  raster), which is scanned out at the board's own timing (totals, sync, pixel rate from the program header), so
//  the picture is stable even when the engine runs slower than real time. Overlay: up to 16 colour rectangles
//  (MAME multiply overlays, e.g. Breakout's cellophane) applied at native resolution; HDMI = MiSTer's scaler.
//  Copyright (C) 2026 Rodimus
//
//  SPDX-License-Identifier: BSD-3-Clause
//  Own work; license terms in the LICENSE file of this chip folder.
//
//============================================================================

// Program header bytes used (see dlogic_engine.sv / dl2bin.py): 12 u32 tick_hz (pixel rate = tick_hz / 2),
// 192 u16 window x0, x1, y0, y1 (raster coordinates from the line / frame events), 201 u8 overlay rect count,
// 204 u16 h total, h sync start, h sync length, v total, v sync start, v sync length (sync relative to the first
// active pixel / line). Rects at 0x3000: u16 x0, x1, y0, y1 (raster coordinates), u8 r, g, b, pad.
// Framebuffer: 2 bits / pixel, address {y[7:0], x[9:0]} (window <= 1024 x 256).

module dlogic_video #(parameter int CLK_HZ = 40000000)
(
    input  logic        clk,
    input  logic        reset,

    input  logic        prog_wr,         // program bytes (snooped: header + overlay)
    input  logic [15:0] prog_addr,
    input  logic  [7:0] prog_data,

    input  logic        pix_valid,       // from dlogic_engine
    input  logic  [7:0] pix_level,
    input  logic        line_strobe,
    input  logic        frame_strobe,

    output logic        ce_pix,
    output logic  [7:0] r, g, b,
    output logic        hs, vs, hblank, vblank
);

logic [7:0] hdr [0:63];          // header bytes 192..255
logic [7:0] ovl [0:191];         // 16 rects x 12 bytes
logic [7:0] thz [0:3];           // tick_hz
always_ff @(posedge clk) if (prog_wr) begin
    if (prog_addr[15:6] == 10'd3) hdr[prog_addr[5:0]] <= prog_data;                       // 0x00C0-0x00FF
    if (prog_addr[15:8] == 8'h30 && prog_addr[7:0] < 8'd192) ovl[prog_addr[7:0]] <= prog_data;
    if (prog_addr[15:2] == 14'd3) thz[prog_addr[1:0]] <= prog_data;                         // 12..15
end
function automatic [15:0] hw(input integer a); hw = {hdr[a - 191], hdr[a - 192]}; endfunction
function automatic [15:0] ow(input integer a); ow = {ovl[a + 1], ovl[a]}; endfunction

wire [9:0] wx0 = hw(192), wx1 = hw(194);
wire [8:0] wy0 = hw(196), wy1 = hw(198);
wire [4:0] nrect = hdr[9][4:0];
wire [10:0] htot = hw(204), hss = hw(206), hsl = hw(208);
wire  [9:0] vtot = hw(210), vss = hw(212), vsl = hw(214);
wire [31:0] pix_hz = {thz[3], thz[2], thz[1], thz[0]} >> 1;

// ---- framebuffer writer (engine side) -----------------------------------------------------------------------
logic [10:0] ex;
logic  [9:0] ey;
logic [17:0] fw_addr;
logic  [1:0] fw_d;
logic        fw_we;
always_ff @(posedge clk) begin
    fw_we <= 1'b0;
    if (pix_valid) begin
        if (ex >= {1'b0, wx0} && ex < {1'b0, wx1} && ey >= {1'b0, wy0} && ey < {1'b0, wy1}) begin
            fw_addr <= {ey[7:0] - wy0[7:0], ex[9:0] - wx0};
            fw_d <= pix_level[7:6];
            fw_we <= 1'b1;
        end
        if (ex != 11'h7FF) ex <= ex + 11'd1;
    end
    if (line_strobe) begin ex <= 11'd0; if (ey != 10'h3FF) ey <= ey + 10'd1; end
    if (frame_strobe) ey <= 10'd0;
end

logic [17:0] fr_addr;
logic  [1:0] frq;
dpram_dc #(.widthad_a(18), .width_a(2)) u_fb
(
    .clock_a(clk), .address_a(fw_addr), .data_a(fw_d), .wren_a(fw_we), .byteena_a(1'b1), .q_a(),
    .clock_b(clk), .address_b(fr_addr), .data_b(2'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b(frq)
);

// ---- output raster at the board's pixel rate ---------------------------------------------------------------
logic [31:0] acc;
always_ff @(posedge clk) begin
    ce_pix <= 1'b0;
    if (pix_hz != 32'd0) begin
        if (acc + pix_hz >= CLK_HZ) begin acc <= acc + pix_hz - CLK_HZ; ce_pix <= 1'b1; end
        else acc <= acc + pix_hz;
    end
end

wire [10:0] aw = {1'b0, wx1 - wx0};
wire  [9:0] ah = {1'b0, wy1 - wy0};
logic [10:0] hc;
logic  [9:0] vc;
logic        act_d, hs_d, vs_d, hb_d, vb_d;
logic  [7:0] or_r, or_g, or_b;

// overlay colour of the pixel being fetched (raster coordinates = window position + window origin)
logic [7:0] cr, cg, cb;
always_comb begin
    logic [10:0] rx;
    logic  [9:0] ry;
    rx = hc + {1'b0, wx0};
    ry = vc + {1'b0, wy0};
    cr = 8'd255; cg = 8'd255; cb = 8'd255;
    for (int k = 15; k >= 0; k--)
        if (k < nrect && rx >= ow(12 * k) && rx < ow(12 * k + 2) && ry >= ow(12 * k + 4) && ry < ow(12 * k + 6)) begin
            cr = ovl[12 * k + 8]; cg = ovl[12 * k + 9]; cb = ovl[12 * k + 10];
        end
end

// level x overlay colour, 16-bit products (an 8-bit context would truncate them to 0)
wire  [7:0] lv = {frq, frq, frq, frq};
wire [15:0] pr = {8'd0, lv} * {8'd0, or_r};
wire [15:0] pg = {8'd0, lv} * {8'd0, or_g};
wire [15:0] pb = {8'd0, lv} * {8'd0, or_b};

always_ff @(posedge clk) begin
    if (reset) begin hc <= 11'd0; vc <= 10'd0; end
    else if (ce_pix) begin
        // stage 2: the framebuffer word fetched at the previous ce is this pixel
        r <= act_d ? pr[15:8] : 8'd0;
        g <= act_d ? pg[15:8] : 8'd0;
        b <= act_d ? pb[15:8] : 8'd0;
        hs <= hs_d; vs <= vs_d; hblank <= hb_d; vblank <= vb_d;
        // stage 1: fetch (hc, vc)
        fr_addr <= {vc[7:0], hc[9:0]};
        act_d <= hc < aw && vc < ah;
        hb_d <= hc >= aw;
        vb_d <= vc >= ah;
        hs_d <= hc >= hss && hc < hss + hsl;
        vs_d <= vc >= vss && vc < vss + vsl;
        or_r <= cr; or_g <= cg; or_b <= cb;
        if (hc + 11'd1 >= htot) begin
            hc <= 11'd0;
            vc <= (vc + 10'd1 >= vtot) ? 10'd0 : vc + 10'd1;
        end else hc <= hc + 11'd1;
    end
end

endmodule

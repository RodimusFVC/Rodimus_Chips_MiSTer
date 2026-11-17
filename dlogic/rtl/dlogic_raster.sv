//============================================================================
//
//  Video stage for a compiled discrete-logic board (tools/dlogic/dl2v.py): the board's own pixel / line / frame
//  events, in real time, become a native raster: one output pixel per pixel-clock edge, blanking = MAME's visible
//  window, sync placed as the board timing says (relative to the first active pixel / line, so the window and the
//  syncs line up as on the board). Colour overlay: up to 16 multiply rectangles (MAME overlays, e.g. Breakout's
//  cellophane) in board raster coordinates. HDMI = MiSTer's scaler.
//  Orientation (FB-2026-10-28): an in-core frame buffer of the active window (4-bit levels; the overlay is applied
//  after it, at each pixel's board position) turns the picture for BOTH outputs (CRT and HDMI see the same raster):
//    orient 2 (180, Flip Screen): native timing, one frame late. Each active pixel's slot is read, then rewritten with
//      the new pixel; the slot order alternates direction every frame, so the slot read holds the mirrored pixel of
//      the previous frame (one buffer, no tearing).
//    orient 1 / 3 (90 CW / CCW): a new raster, frame-locked to the board: 256 lines of (board frame clocks / 256),
//      one pixel every 8 clocks, the board's active lines across, the active columns down (k columns per line,
//      k = the smallest of 1-4 giving <= 240 lines; brightest of the k, so thin bright objects stay). Double buffer.
//  Copyright (C) 2026 Rodimus
//
//  SPDX-License-Identifier: BSD-3-Clause
//  Own work; license terms in the LICENSE file of this chip folder.
//
//============================================================================

// geom = {vsl, vss, vtot, hsl, hss, htot, wy1, wy0, wx1, wx0} (u16 each): window x / y in raster coordinates (pixels
// after the line event, lines after the frame event); h / v total, sync start (relative to the first active pixel /
// line) and length. Overlay rect k = rects[96k +: 96] = {pad, b, g, r, y1, y0, x1, x0} (u16 x0 x1 y0 y1, u8 r g b pad,
// the MRA's little-endian byte order), nrect of them; the lowest index wins where rects overlap.
// FBAW: frame buffer words (4 bit) = 2^FBAW >= the largest active window (flip) and >= 2 x the rotated picture.

module dlogic_raster #(parameter int FBAW = 18)
(
    input  logic          clk,
    input  logic          reset,

    input  logic          pix_ev,        // from the board (its first time unit this clock)
    input  logic    [7:0] level,
    input  logic          line_ev,
    input  logic          frame_ev,
    input  tri0           pix_ev2,       // two-unit boards (Breakout): the second unit's events, after the first's
    input  tri0     [7:0] level2,
    input  tri0           line_ev2,
    input  tri0           frame_ev2,
    input  logic  [159:0] geom,
    input  tri0     [1:0] orient,        // the picture's rotation, x 90 deg CW: 0 native, 1 CW, 2 180, 3 CCW

    input  logic    [4:0] nrect,
    input  logic [1535:0] rects,

    output logic          ce_pix,
    output logic    [7:0] r, g, b,
    output logic          hs, vs, hblank, vblank
);

wire [15:0] wx0 = geom[15:0],    wx1 = geom[31:16],  wy0 = geom[47:32],   wy1 = geom[63:48];
wire [15:0] htot = geom[79:64],  hss = geom[95:80],  hsl = geom[111:96];
wire [15:0] vtot = geom[127:112], vss = geom[143:128], vsl = geom[159:144];
wire [15:0] wact = wx1 - wx0, hact = wy1 - wy0;                  // active window: columns, lines
wire  [2:0] kdiv = (wact <= 16'd240) ? 3'd1 : (wact <= 16'd480) ? 3'd2 : (wact <= 16'd720) ? 3'd3 : 3'd4;

wire rot_m = orient[0];                  // 90 / 270: the rotated raster
wire flp_m = orient == 2'd2;             // 180: native timing from the frame buffer
wire fev   = frame_ev | frame_ev2;

logic [15:0] x, y;                       // raster position of the next pixel / current line

// this clock's events in unit order: the pixel (at most one per clock) is drawn at (ex, ey); (xn, yn) = after both
logic [15:0] ex, ey, xn, yn;
logic  [7:0] elev;
logic        epix;
always_comb begin
    xn = x; yn = y; ex = x; ey = y; elev = level; epix = 1'b0;
    if (pix_ev) begin epix = 1'b1; ex = xn; ey = yn; elev = level; xn = xn + 16'd1; end
    if (line_ev) begin xn = 16'd0; yn = yn + 16'd1; end
    if (frame_ev) yn = 16'd0;
    if (pix_ev2 && !epix) begin epix = 1'b1; ex = xn; ey = yn; elev = level2; xn = xn + 16'd1; end
    if (line_ev2) begin xn = 16'd0; yn = yn + 16'd1; end
    if (frame_ev2) yn = 16'd0;
end

// position relative to the first active pixel / line, wrapped by the totals (sync may straddle the line start)
wire [15:0] px = (ex >= wx0) ? ex - wx0 : ex + htot - wx0;
wire [15:0] py = (ey >= wy0) ? ey - wy0 : ey + vtot - wy0;
wire        act0 = ex >= wx0 && ex < wx1 && ey >= wy0 && ey < wy1;

// overlay colour {r, g, b} at board position (ox, oy)
function automatic [23:0] ovl(input [15:0] ox, input [15:0] oy, input [4:0] n, input [1535:0] rs);
    reg [95:0] q;
    integer    k;
    begin
        ovl = 24'hFFFFFF;
        for (k = 15; k >= 0; k = k - 1) begin
            q = rs[96 * k +: 96];
            if (k < n && ox >= q[15:0] && ox < q[31:16] && oy >= q[47:32] && oy < q[63:48])
                ovl = {q[71:64], q[79:72], q[87:80]};
        end
    end
endfunction

/////////////////////////////  frame buffer  /////////////////////////////

// POOL-EXCEPTION: the video stage's own frame buffer (one per core, in the shared video stage, not a board RAM)
logic [FBAW-1:0] wa_a, ra_b;
logic      [3:0] wd_a, q_b;
logic            we_a;
/* verilator lint_off PINCONNECTEMPTY */
/* verilator lint_off PINMISSING */
dpram_dc #(.widthad_a(FBAW), .width_a(4)) fb
(
    .clock_a(clk), .address_a(wa_a), .data_a(wd_a), .wren_a(we_a), .q_a(),
    .clock_b(clk), .address_b(ra_b), .data_b(4'd0), .wren_b(1'b0), .q_b(q_b)
);
/* verilator lint_on PINMISSING */
/* verilator lint_on PINCONNECTEMPTY */

// 180: slot of active pixel t = t (even frames) or ptot - 1 - t (odd); read now, rewritten next clock
logic [FBAW-1:0] tpix, ptot, fw_addr;
logic            fdir, fw_en;
logic      [3:0] fw_data;
wire  [FBAW-1:0] fa = fdir ? ptot - 1'd1 - tpix : tpix;

// 90 / 270 writer: k-column groups of each active line -> [wsel][line * G + group], brightest of the group
logic      [2:0] kc;
logic      [8:0] gq, gm;                 // group in this line; groups per line (measured)
logic [FBAW-2:0] rowb;
logic      [3:0] mxa;
logic            wsel;
wire       [3:0] lq   = elev[7:4];
wire       [3:0] mxn  = (kc == 3'd0 || lq > mxa) ? lq : mxa;
wire             gend = kc == kdiv - 3'd1 || ex == wx1 - 16'd1;
wire  [FBAW-2:0] rw_off = rowb + {{(FBAW-10){1'b0}}, gq};

// 90 / 270 reader: frame-locked raster, 256 lines of fl / 256 clocks, a pixel every 8 clocks
logic     [20:0] fcnt, fl;
logic     [12:0] hc;
logic      [7:0] vc;
logic            rsel;
wire      [12:0] lw     = (fl[20:8] < 13'd1000) ? 13'd3640 : fl[20:8];
wire      [12:0] hstart = ((((lw - {hact[9:0], 3'd0}) >> 1) + 13'd128) & ~13'd7);
wire      [12:0] hrel   = hc - hstart;
wire             in_h   = hc >= hstart && {3'd0, hrel[12:3]} < hact[12:0];
wire       [7:0] vstart = 8'd12 + ((8'd240 - gm[7:0]) >> 1);
wire       [7:0] rj     = vc - vstart;
wire             in_v   = vc >= vstart && {1'b0, rj} < gm;
wire             tick   = hc[2:0] == 3'd1;  // the pixel; its coordinates are registered the clock before (hc[2:0] 0)
wire      [15:0] ri     = {6'd0, hrel[12:3]};
logic     [15:0] gg, yr, sx, sy;          // column group, active line, board position (registered)
logic            rin_h, rin_v;
wire      [24:0] yg     = yr * {7'd0, gm};
wire      [24:0] rsum   = yg + {9'd0, gg};
wire  [FBAW-2:0] r_off  = rsum[FBAW-2:0];

// RAM ports: 90 / 270 = writer on a, reader on b; else the 180 slot (read on b, rewritten on a; written at 0 too so a
// switch to 180 shows a picture within a frame)
always_comb begin
    if (rot_m) begin
        we_a = epix && act0 && gend; wa_a = {wsel, rw_off}; wd_a = mxn;
        ra_b = {rsel, r_off};
    end else begin
        we_a = fw_en; wa_a = fw_addr; wd_a = fw_data;
        ra_b = fa;
    end
end

/////////////////////////////  pipeline  /////////////////////////////

// stage 0: the pixel (board event, or the rotated raster's tick): timing flags, overlay colour at its board position,
// level (or: from the RAM in stage 1); stage 1: level; stage 2: level x overlay
wire [23:0] col = ovl(rot_m ? sx : flp_m ? wx0 + wx1 - 16'd1 - ex : ex,
                      rot_m ? sy : flp_m ? wy0 + wy1 - 16'd1 - ey : ey, nrect, rects);

logic       p0, act_0, hb_0, vb_0, hs_0, vs_0, ram0, p1, act1, hb1, vb1, hs1, vs1;
logic [7:0] lv0, or0, og0, ob0, lv1, or1, og1, ob1;
wire [15:0] pr = {8'd0, lv1} * {8'd0, or1};
wire [15:0] pg = {8'd0, lv1} * {8'd0, og1};
wire [15:0] pb = {8'd0, lv1} * {8'd0, ob1};

always_ff @(posedge clk) begin
    p0 <= 1'b0; p1 <= 1'b0; ce_pix <= 1'b0; fw_en <= 1'b0;
    fcnt <= fcnt + 21'd1;
    if (reset) begin
        x <= 16'd0; y <= 16'd0; tpix <= '0; ptot <= '0; fdir <= 1'b0;
        kc <= 3'd0; gq <= 9'd0; gm <= 9'd240; rowb <= '0; mxa <= 4'd0; wsel <= 1'b0;
        fcnt <= 21'd0; fl <= 21'd0; hc <= 13'd0; vc <= 8'd0; rsel <= 1'b1;
    end else begin
        x <= xn; y <= yn;

        // 180 slots
        if (fev) begin ptot <= tpix; tpix <= '0; fdir <= ~fdir; end
        else if (epix && act0) tpix <= tpix + 1'd1;
        if (epix && act0) begin fw_en <= 1'b1; fw_addr <= fa; fw_data <= lq; end

        // 90 / 270 writer
        if (fev) begin rowb <= '0; gq <= 9'd0; kc <= 3'd0; wsel <= ~wsel; end
        else if (epix && act0) begin
            if (gend) begin
                kc <= 3'd0; gq <= gq + 9'd1;
                if (ex == wx1 - 16'd1) begin rowb <= rw_off + 1'd1; gm <= gq + 9'd1; gq <= 9'd0; end
            end else begin
                kc <= kc + 3'd1; mxa <= mxn;
            end
        end

        // 90 / 270 raster: restarts on the board's frame (reads the frame just written), free-runs while paused
        if (fev) begin fl <= fcnt; fcnt <= 21'd0; hc <= 13'd0; vc <= 8'd0; rsel <= wsel; end
        else if (hc == lw - 13'd1) begin hc <= 13'd0; vc <= vc + 8'd1; end
        else hc <= hc + 13'd1;
        if (hc[2:0] == 3'd0) begin
            gg <= (orient == 2'd1) ? {8'd0, rj} : {7'd0, gm} - 16'd1 - {8'd0, rj};
            yr <= (orient == 2'd1) ? hact - 16'd1 - ri : ri;
            sx <= wx0 + ((orient == 2'd1) ? {8'd0, rj} : {7'd0, gm} - 16'd1 - {8'd0, rj}) * {13'd0, kdiv};
            sy <= wy0 + ((orient == 2'd1) ? hact - 16'd1 - ri : ri);
            rin_h <= in_h; rin_v <= in_v;
        end

        // stage 0
        if (rot_m ? tick : epix) begin
            p0 <= 1'b1;
            {or0, og0, ob0} <= col;
            lv0 <= elev;
            ram0 <= rot_m || flp_m;
            if (rot_m) begin
                act_0 <= rin_h && rin_v; hb_0 <= !rin_h; vb_0 <= !rin_v;
                hs_0 <= hc < 13'd270; vs_0 <= vc < 8'd3;
            end else begin
                act_0 <= act0;
                hb_0 <= !(ex >= wx0 && ex < wx1);
                vb_0 <= !(ey >= wy0 && ey < wy1);
                hs_0 <= px >= hss && px < hss + hsl;
                vs_0 <= py >= vss && py < vss + vsl;
            end
        end

        // stage 1
        if (p0) begin
            p1 <= 1'b1;
            lv1 <= ram0 ? {q_b, q_b} : lv0;
            or1 <= or0; og1 <= og0; ob1 <= ob0;
            act1 <= act_0; hb1 <= hb_0; vb1 <= vb_0; hs1 <= hs_0; vs1 <= vs_0;
        end

        // stage 2
        if (p1) begin
            ce_pix <= 1'b1;
            r <= act1 ? pr[15:8] : 8'd0;
            g <= act1 ? pg[15:8] : 8'd0;
            b <= act1 ? pb[15:8] : 8'd0;
            hblank <= hb1; vblank <= vb1; hs <= hs1; vs <= vs1;
        end
    end
end

endmodule

// Pre-variant core (first version, lockstep-proven at 960M cycles); used only as the equivalence "gold".
module crtc6845sv_v1
(
    input  logic        CLOCK, CLKEN, nRESET, ENABLE, R_nW, RS,
    input  logic  [7:0] DI,
    output logic  [7:0] DO,
    output logic        VSYNC, HSYNC, VBLANK, HBLANK, DE, CURSOR,
    input  logic        LPSTB,
    output logic [13:0] MA,
    output logic  [4:0] RA,
    input  logic        PHI2
);
logic [13:0] ma_q;
logic  [4:0] ra_q;
assign MA = ma_q;
assign RA = ra_q;
logic  [4:0] addr_reg;
logic  [7:0] r00, r01, r02;
logic  [3:0] r03v, r03h;
logic  [6:0] r04, r06, r07;
logic  [4:0] r05, r09, r10s, r11;
logic  [7:0] r08;
logic  [1:0] r10m;
logic  [5:0] r12, r14, r16;
logic  [7:0] r13, r15, r17;
logic  [7:0] h_cnt;
logic  [3:0] hs_cnt, vs_cnt;
logic  [6:0] row;
logic  [4:0] line;
logic  [4:0] field;
logic        in_adj;
logic [13:0] ma_i, ma_row;
logic        h_de, v_de, hs, vs;
logic        cur_i, cur_line, lpstb_q;
logic        de1, de2, cur1, hbl1, hbl2;
wire         il_sv    = r08[1] & r08[0];
wire         h_end    = h_cnt == r00;
wire         h_syncp  = h_cnt == r02;
wire         h_de_e   = h_cnt < r01;
wire         v_de_e   = (row < r06) & ~in_adj;
wire         row_eq_t = row == r04;
wire         need_adj = r05 != 5'd0;
wire   [4:0] msl_raw  = in_adj ? (r05 - 5'd1) : r09;
wire   [4:0] msl      = {msl_raw[4:1], msl_raw[0] & ~il_sv};
wire         line_eq  = line == msl;
wire         f_end    = line_eq & (in_adj | (row_eq_t & ~need_adj));
wire         r_end    = line_eq & ~in_adj;
wire  [13:0] ma_row_n = f_end ? {r12, r13} : r_end ? (ma_row + {6'd0, r01}) : ma_row;
logic  [7:0] rd_data;
always_comb begin
    case (addr_reg)
        5'd12:   rd_data = {2'b00, r12};
        5'd13:   rd_data = r13;
        5'd14:   rd_data = {2'b00, r14};
        5'd15:   rd_data = r15;
        5'd16:   rd_data = {2'b00, r16};
        5'd17:   rd_data = r17;
        default: rd_data = 8'h00;
    endcase
end
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        addr_reg <= 5'd0;
        r00 <= 8'd0;  r01 <= 8'd0;  r02 <= 8'd0;  r03v <= 4'd0; r03h <= 4'd0;
        r04 <= 7'd0;  r05 <= 5'd0;  r06 <= 7'd0;  r07 <= 7'd0;  r08 <= 8'd0;
        r09 <= 5'd0;  r10m <= 2'd0; r10s <= 5'd0; r11 <= 5'd0;
        r12 <= 6'd0;  r13 <= 8'd0;  r14 <= 6'd0;  r15 <= 8'd0;
        DO  <= 8'd0;
    end
    else if (ENABLE) begin
        if (R_nW) DO <= rd_data;
        else if (!RS) addr_reg <= DI[4:0];
        else begin
            case (addr_reg)
                5'd0:  r00 <= DI;   5'd1:  r01 <= DI;   5'd2:  r02 <= DI;
                5'd3:  begin r03v <= DI[7:4]; r03h <= DI[3:0]; end
                5'd4:  r04 <= DI[6:0]; 5'd5:  r05 <= DI[4:0]; 5'd6:  r06 <= DI[6:0]; 5'd7:  r07 <= DI[6:0];
                5'd8:  r08 <= DI;   5'd9:  r09 <= DI[4:0];
                5'd10: begin r10m <= DI[6:5]; r10s <= DI[4:0]; end
                5'd11: r11 <= DI[4:0]; 5'd12: r12 <= DI[5:0]; 5'd13: r13 <= DI; 5'd14: r14 <= DI[5:0]; 5'd15: r15 <= DI;
                default: ;
            endcase
        end
    end
end
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin
        h_cnt <= 8'd0; line <= 5'd0; row <= 7'd0; field <= 5'd0; ma_row <= 14'd0; ma_i <= 14'd0; in_adj <= 1'b0;
    end
    else if (CLKEN) begin
        if (h_end) begin
            h_cnt <= 8'd0; ma_row <= ma_row_n; ma_i <= ma_row_n;
            if (f_end) begin line <= 5'd0; row <= 7'd0; field <= field + 5'd1; in_adj <= 1'b0; end
            else if (r_end) begin line <= 5'd0; row <= row + 7'd1; if (row_eq_t & need_adj) in_adj <= 1'b1; end
            else if (il_sv) line <= {line[4:1] + 4'd1, 1'b0};
            else line <= line + 5'd1;
        end
        else begin h_cnt <= h_cnt + 8'd1; ma_i <= ma_i + 14'd1; end
    end
end
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin h_de <= 1'b0; hs <= 1'b0; hs_cnt <= 4'd0; v_de <= 1'b0; vs <= 1'b0; vs_cnt <= 4'd0; end
    else if (CLKEN) begin
        h_de <= h_de_e; v_de <= v_de_e;
        hs <= (h_syncp | hs) & (hs_cnt != r03h);
        hs_cnt <= (h_syncp | hs) ? hs_cnt + 4'd1 : 4'd0;
        if (h_syncp) begin
            vs     <= (vs | (row == r07 && line == 5'd0)) & ~(vs & (vs_cnt == r03v));
            vs_cnt <= (vs | (row == r07 && line == 5'd0)) ? vs_cnt + 4'd1 : 4'd0;
        end
    end
end
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin ra_q <= 5'd0; ma_q <= 14'd0; end
    else if (CLKEN) begin ra_q <= line; ma_q <= ma_i; end
end
wire cur_hit = h_de_e & v_de_e & (ma_i == {r14, r15});
wire cur_l1  = (line == r10s) | (cur_line & (line != 5'd0));
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin cur_i <= 1'b0; cur_line <= 1'b0; end
    else if (CLKEN) begin cur_i <= cur_hit & cur_l1; if (cur_hit) cur_line <= cur_l1 & (line != r11); end
end
always_ff @(posedge CLOCK or negedge nRESET) begin
    if (!nRESET) begin lpstb_q <= 1'b0; r16 <= 6'd0; r17 <= 8'd0; end
    else if (CLKEN) begin lpstb_q <= LPSTB; if (LPSTB & ~lpstb_q) begin r16 <= ma_i[13:8]; r17 <= ma_i[7:0]; end end
end
wire de0  = h_de & v_de;
wire cur0 = cur_i & (r10m == 2'd0 | (r10m == 2'd2 & field[3]) | (r10m == 2'd3 & field[4]));
always_ff @(posedge CLOCK) begin
    if (CLKEN) begin de1 <= de0; de2 <= de1; cur1 <= cur0; hbl1 <= h_de; hbl2 <= hbl1; end
end
assign HSYNC  = hs;
assign VSYNC  = vs;
assign VBLANK = ~v_de;
assign DE     = r08[5] ? (~r08[4] & de2) : de0;
assign HBLANK = r08[5] ? (r08[4] | ~hbl2) : ~h_de;
assign CURSOR = r08[7] ? (~r08[6] & cur1) : (r08[6] ? cur1 : cur0);
endmodule

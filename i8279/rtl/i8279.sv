//============================================================================
//
//  i8279.sv - Intel 8279 programmable keyboard / display interface
//  Copyright (C) 2026 Rodimus
//
//  Based on MAME i8279.cpp (Robbbert, BSD-3-Clause)
//
//  Bus: cs selects the chip, a0 = 1 command / status, a0 = 0 data. wr and rd are one-clock strobes (one per CPU
//  access: reads of the data port advance pointers / pop the FIFO). dout is combinational.
//  ce = the chip's CLK input as an enable. Internal scan: every 64 prescaled clocks (prescaler = command 1, >= 2,
//  31 at reset), one row of the RL inputs is read and one display digit is output on sl / disp.
//  Keyboard modes as MAME: 0 / 1 = scanned keyboard into the 8-byte FIFO (MAME's N-key path, debounce = the same
//  key in three scans), 2 = sensor matrix (RL row copied into sensor RAM), 3 = strobed (FIFO on a rising ctrl).
//  Right-entry auto-increment is not implemented (as MAME). disp_a / disp_q read display RAM for a board's LEDs.
//
//  Redistribution and use in source and synthesized forms, with or without modification, are permitted
//  provided that the above copyright notice is retained. THIS SOFTWARE IS PROVIDED "AS IS" WITHOUT WARRANTY.
//
//============================================================================

module i8279
(
    input             clk,
    input             reset,
    input             ce,

    input             cs,
    input             a0,
    input             rd,
    input             wr,
    input       [7:0] din,
    output reg  [7:0] dout,

    input       [7:0] rl,               // return lines (active low, as the pins)
    input             shift,
    input             ctrl,

    output reg  [3:0] sl = 4'd0,        // scan lines (decoded mode: active-low one-hot)
    output      [7:0] disp,             // display outputs {A3..A0, B3..B0} for the digit on sl
    output reg        irq = 1'b0,

    input       [3:0] disp_a,
    output      [7:0] disp_q
);

reg [4:0] cmd [8];
reg [7:0] d_ram [16];
reg [7:0] s_ram [8];
reg [7:0] fifo  [8];
reg [7:0] status = 8'd0;
reg [3:0] d_ptr = 4'd0;
reg [2:0] s_ptr = 3'd0;
reg       read_flag = 1'b0, autoinc = 1'b0, se_mode = 1'b0, ctrl_d = 1'b0;
reg [3:0] scanner = 4'd0;
reg [5:0] key_down = 6'd0;
reg [1:0] debounce = 2'd0;
reg [4:0] pre = 5'd0;
reg [5:0] t64 = 6'd0;

wire       decoded  = cmd[0][0];
wire [1:0] kbd_type = cmd[0][2:1];
wire [3:0] smask    = decoded ? 4'd3 : cmd[0][3] ? 4'd15 : 4'd7;
wire       sensor   = kbd_type == 2'd2;
wire [4:0] pdiv     = (cmd[1] >= 5'd2) ? cmd[1] : 5'd2;

assign disp   = d_ram[scanner & smask];
assign disp_q = d_ram[disp_a];

always @(*) begin
    if (a0)             dout = status;
    else if (read_flag) dout = d_ram[d_ptr];
    else if (sensor)    dout = s_ram[s_ptr];
    else                dout = fifo[0];
end

// push one key into the FIFO (MAME new_fifo); returns the new status
function automatic [7:0] push_status(input [7:0] st);
    if (st[5] || st[6])  push_status = st;
    else if (st[3])      push_status = st | 8'h20;
    else if (st[2:0] == 3'd7) push_status = st | 8'h08;
    else                 push_status = (st & 8'hE8) | {5'd0, st[2:0] + 3'd1};
endfunction

wire       scan_tick = ce && pre == pdiv - 5'd1 && t64 == 6'd63;
wire [7:0] rli       = ~rl;
wire [2:0] row       = scanner[2:0];
wire [7:0] kdown     = rli & ~s_ram[row];
wire       strobe    = ctrl && !ctrl_d;

// lowest new key in this row (MAME walks bits 0-7 and the last match wins within the loop; one key at a time here)
reg  [2:0] kbit;
reg        kany;
always @(*) begin
    kbit = 3'd0;
    kany = 1'b0;
    for (int i = 7; i >= 0; i--) if (kdown[i]) begin kbit = i[2:0]; kany = 1'b1; end
end

integer n;
always @(posedge clk) begin
    if (reset) begin
        cmd[0] <= 5'd8; cmd[1] <= 5'd31; cmd[2] <= 5'd0; cmd[3] <= 5'd0;
        cmd[4] <= 5'd0; cmd[5] <= 5'd0;  cmd[6] <= 5'd0; cmd[7] <= 5'd0;
        for (n = 0; n < 16; n = n + 1) d_ram[n] <= 8'd0;
        for (n = 0; n < 8;  n = n + 1) begin s_ram[n] <= 8'd0; fifo[n] <= 8'd0; end
        status <= 8'd0; d_ptr <= 4'd0; s_ptr <= 3'd0;
        read_flag <= 1'b0; autoinc <= 1'b0; se_mode <= 1'b0; ctrl_d <= 1'b0;
        scanner <= 4'd0; sl <= 4'd0; key_down <= 6'd0; debounce <= 2'd0; pre <= 5'd0; t64 <= 6'd0;
        irq <= 1'b0;
    end else begin
        // scan clock
        if (ce) begin
            if (pre >= pdiv - 5'd1) begin
                pre <= 5'd0;
                t64 <= t64 + 6'd1;
            end else
                pre <= pre + 5'd1;
        end

        if (scan_tick) begin
            ctrl_d <= ctrl;
            case (kbd_type)
                2'd2: begin
                    if (kdown != 8'd0 && !se_mode) status[6] <= 1'b1;
                    if (s_ram[row] != rli) begin s_ram[row] <= rli; irq <= 1'b1; end
                end
                2'd3: begin
                    if (strobe) begin
                        if (!status[5] && !status[6] && !status[3]) fifo[status[2:0]] <= rli;
                        status <= push_status(status);
                        if (status[2:0] == 3'd0 && !status[5] && !status[6]) irq <= 1'b1;
                    end
                    s_ram[row] <= rli;
                end
                default: begin                              // scanned keyboard (N-key path)
                    if (kany) begin
                        if (debounce == 2'd0) begin
                            key_down <= {row, kbit};
                            debounce <= 2'd1;
                        end else if (key_down == {row, kbit}) begin
                            if (debounce == 2'd2) begin
                                if (!status[5] && !status[6] && !status[3])
                                    fifo[status[2:0]] <= {ctrl, shift, row, kbit};
                                status <= push_status(status);
                                if (status[2:0] == 3'd0 && !status[5] && !status[6] && !status[3]) irq <= 1'b1;
                                s_ram[row] <= (s_ram[row] & rli) | (8'd1 << kbit);
                                debounce <= 2'd0;
                            end else
                                debounce <= debounce + 2'd1;
                        end
                    end
                    if (key_down[5:3] == row && !rli[key_down[2:0]]) debounce <= 2'd0;
                    if (!(kany && debounce == 2'd2 && key_down == {row, kbit})) s_ram[row] <= s_ram[row] & rli;
                end
            endcase
            scanner <= decoded ? ((scanner + 4'd1) & 4'd3) : scanner + 4'd1;
            sl      <= decoded ? ~(4'd1 << ((scanner + 4'd1) & 4'd3)) : scanner + 4'd1;
        end

        // CPU access
        if (cs && wr) begin
            if (a0) begin                                   // command
                cmd[din[7:5]] <= din[4:0];
                case (din[7:5])
                    3'd2: begin
                        read_flag <= 1'b0;
                        if (cmd[0][2:1] == 2'd2) begin autoinc <= din[4]; s_ptr <= din[2:0]; end
                    end
                    3'd3: begin read_flag <= 1'b1; d_ptr <= din[3:0]; autoinc <= din[4]; end
                    3'd4: begin d_ptr <= din[3:0]; autoinc <= din[4]; end
                    3'd6: begin                             // clear
                        if (din[4] | din[0])
                            for (n = 0; n < 16; n = n + 1)
                                d_ram[n] <= (din[3:2] == 2'd2) ? 8'h20 : (din[3:2] == 2'd3) ? 8'hFF : 8'h00;
                        status[7] <= 1'b0;
                        d_ptr <= 4'd0;
                        if (din[1] | din[0]) begin
                            status <= {status[7] & 1'b0, 7'd0};
                            s_ptr <= 3'd0;
                            debounce <= 2'd0;
                            irq <= 1'b0;
                        end
                    end
                    3'd7: begin irq <= 1'b0; se_mode <= din[4]; status[6] <= 1'b0; end
                    default: ;
                endcase
            end else begin                                  // display RAM write
                if (!(cmd[0][4] && autoinc)) begin
                    d_ram[d_ptr] <= {cmd[5][3] ? d_ram[d_ptr][7:4] : din[7:4], cmd[5][2] ? d_ram[d_ptr][3:0] : din[3:0]};
                    if (autoinc) d_ptr <= d_ptr + 4'd1;
                end
            end
        end
        if (cs && rd && !a0) begin                          // data read side effects
            if (read_flag) begin
                if (autoinc) d_ptr <= d_ptr + 4'd1;
            end else if (sensor) begin
                if (autoinc) s_ptr <= s_ptr + 3'd1;
                else         irq <= 1'b0;
            end else begin
                case (status[5:3])
                    3'b000: begin
                        if (status[2:0] == 3'd0) status[4] <= 1'b1;
                        else begin
                            for (n = 1; n < 8; n = n + 1) fifo[n - 1] <= fifo[n];
                            status[2:0] <= status[2:0] - 3'd1;
                            if (status[2:0] == 3'd1) irq <= 1'b0;
                        end
                    end
                    3'b101, 3'b001: begin
                        for (n = 1; n < 8; n = n + 1) fifo[n - 1] <= fifo[n];
                        status[5] <= 1'b0; status[3] <= 1'b0;
                    end
                    default: ;
                endcase
            end
        end
    end
end

endmodule

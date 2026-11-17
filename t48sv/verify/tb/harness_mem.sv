// Harness memories shared by both sides of a lockstep run.
// harness_ram: generic_ram_ena behaviour (registered address, 256 bytes)
module harness_ram (
  input  logic       clk_i,
  input  logic [7:0] a_i,
  input  logic       we_i,
  input  logic [7:0] d_i,
  output logic [7:0] d_o
);
  logic [7:0] mem [0:255];
  logic [7:0] a_q;
  initial for (int i = 0; i < 256; i++) mem[i] = 8'h00;
  always_ff @(posedge clk_i) begin
    if (we_i) mem[a_i] <= d_i;
    a_q <= a_i;
  end
  assign d_o = mem[a_q];
endmodule

// black-box ROMs of the reference system tops (t48_rom / t49_rom / syn_rom)
module harness_rom_10 (input logic clk_i, input logic [9:0] rom_addr_i, output logic [7:0] rom_data_o);
  logic [7:0] rom [0:1023];
  logic [9:0] a_q;
  initial $readmemh("rom10.hex", rom);
  always_ff @(posedge clk_i) a_q <= rom_addr_i;
  assign rom_data_o = rom[a_q];
endmodule
module harness_rom_11 (input logic clk_i, input logic [10:0] rom_addr_i, output logic [7:0] rom_data_o);
  logic [7:0] rom [0:2047];
  logic [10:0] a_q;
  initial $readmemh("rom11.hex", rom);
  always_ff @(posedge clk_i) a_q <= rom_addr_i;
  assign rom_data_o = rom[a_q];
endmodule
module harness_rom_12 (input logic clk_i, input logic [11:0] rom_addr_i, output logic [7:0] rom_data_o);
  logic [7:0] rom [0:4095];
  logic [11:0] a_q;
  initial $readmemh("rom12.hex", rom);
  always_ff @(posedge clk_i) a_q <= rom_addr_i;
  assign rom_data_o = rom[a_q];
endmodule

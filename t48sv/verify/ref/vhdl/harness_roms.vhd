-- Harness-only architectures for the ROM entities T48 leaves to the integrator
-- (t48_rom, t49_rom, syn_rom): an unbound component, so GHDL synth emits a
-- black box that the Verilator harness implements as a loadable memory.
library ieee;
use ieee.std_logic_1164.all;
architecture harness of t48_rom is
  component harness_rom_10
    port (clk_i : in std_logic; rom_addr_i : in std_logic_vector(9 downto 0);
          rom_data_o : out std_logic_vector(7 downto 0));
  end component;
begin
  rom_b : harness_rom_10 port map (clk_i => clk_i, rom_addr_i => rom_addr_i, rom_data_o => rom_data_o);
end harness;
library ieee;
use ieee.std_logic_1164.all;
architecture harness of t49_rom is
  component harness_rom_11
    port (clk_i : in std_logic; rom_addr_i : in std_logic_vector(10 downto 0);
          rom_data_o : out std_logic_vector(7 downto 0));
  end component;
begin
  rom_b : harness_rom_11 port map (clk_i => clk_i, rom_addr_i => rom_addr_i, rom_data_o => rom_data_o);
end harness;

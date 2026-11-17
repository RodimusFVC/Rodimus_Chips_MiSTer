-- Harness-only architectures for syn_rom / syn_ram (t8050_wb). Upstream's were
-- LPM_ROM / LPM_RAM_DQ with registered address and unregistered output; the ROM
-- is a black box implemented by the Verilator harness, the RAM reuses T48's own
-- generic_ram_ena (same registered-address / unregistered-output behaviour).
library ieee;
use ieee.std_logic_1164.all;
architecture harness of syn_rom is
  component harness_rom_12
    port (clk_i : in std_logic; rom_addr_i : in std_logic_vector(11 downto 0);
          rom_data_o : out std_logic_vector(7 downto 0));
  end component;
begin
  rom_b : harness_rom_12 port map (clk_i => clk_i, rom_addr_i => rom_addr_i, rom_data_o => rom_data_o);
end harness;
library ieee;
use ieee.std_logic_1164.all;
architecture harness of syn_ram is
begin
  ram_b : entity work.generic_ram_ena
    generic map (addr_width_g => address_width_g, data_width_g => 8)
    port map (clk_i => clk_i, a_i => ram_addr_i, we_i => ram_we_i, ena_i => '1',
              d_i => ram_data_i, d_o => ram_data_o);
end harness;

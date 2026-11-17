-- Lockstep of the unmodified T48 8243 (VHDL, GHDL simulation) against t48sv
-- (Verilator, through the cosim glue). Random PROG / CS / P2 / port stimulus;
-- every output is compared after every input event. Bits where T48 itself
-- drives '-' (don't care) are masked and counted.
library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

entity tb_8243_cmp is
  generic (async_g : integer := 0; steps_g : integer := 200000; seed_g : integer := 1);
end tb_8243_cmp;

architecture behav of tb_8243_cmp is
  type iarr is array (0 to 127) of integer;
  function cs_create(kind : integer) return integer is
  begin assert false severity failure; return 0; end;
  attribute foreign of cs_create : function is "VHPIDIRECT cs_create";
  procedure cs_eval(h : integer; i : iarr; o : out iarr) is
  begin assert false severity failure; end;
  attribute foreign of cs_eval : procedure is "VHPIDIRECT cs_eval";

  signal clk, clk_en, reset_n, cs_n, prog_n : std_logic := '0';
  signal p2_i, p4_i, p5_i, p6_i, p7_i : std_logic_vector(3 downto 0) := "0000";
  signal p2_o, p4_o, p5_o, p6_o, p7_o : std_logic_vector(3 downto 0);
  signal p2_en, p4_en, p5_en, p6_en, p7_en : std_logic;
begin
  sync: if async_g = 0 generate
    dut : entity work.t8243_sync_notri port map (
      clk_i => clk, clk_en_i => clk_en, reset_n_i => reset_n, cs_n_i => cs_n, prog_n_i => prog_n,
      p2_i => p2_i, p2_o => p2_o, p2_en_o => p2_en, p4_i => p4_i, p4_o => p4_o, p4_en_o => p4_en,
      p5_i => p5_i, p5_o => p5_o, p5_en_o => p5_en, p6_i => p6_i, p6_o => p6_o, p6_en_o => p6_en,
      p7_i => p7_i, p7_o => p7_o, p7_en_o => p7_en);
  end generate;
  async: if async_g = 1 generate
    dut : entity work.t8243_async_notri port map (
      reset_n_i => reset_n, cs_n_i => cs_n, prog_n_i => prog_n,
      p2_i => p2_i, p2_o => p2_o, p2_en_o => p2_en, p4_i => p4_i, p4_o => p4_o, p4_en_o => p4_en,
      p5_i => p5_i, p5_o => p5_o, p5_en_o => p5_en, p6_i => p6_i, p6_o => p6_o, p6_en_o => p6_en,
      p7_i => p7_i, p7_o => p7_o, p7_en_o => p7_en);
  end generate;

  stim : process
    variable s1, s2 : positive := 1;
    variable r : real;
    variable h, n, k, mism, masked : integer := 0;
    variable i, o : iarr;
    variable exp : std_logic_vector(24 downto 0);
    function rnd(p : real; r : real) return std_logic is
    begin if r < p then return '1'; else return '0'; end if; end;
    procedure rvec(variable v : out std_logic_vector(3 downto 0)) is
      variable x : real;
    begin
      for b in 0 to 3 loop uniform(s1, s2, x); v(b) := rnd(0.5, x); end loop;
    end;
    variable v : std_logic_vector(3 downto 0);
  begin
    s1 := seed_g; s2 := seed_g + 7;
    -- kinds 16 / 18 = t8243_sync_notri / t8243_async_notri in gen_cosim.py
    h := cs_create(16 + 2 * async_g);
    reset_n <= '0';
    for step in 0 to 2 * steps_g loop
      -- even steps: clock edges only (clk, PROG); odd steps: data / control only,
      -- so no input changes in the same delta as the edge that samples it
      if step mod 2 = 0 then
        if async_g = 0 then clk <= not clk; end if;
        uniform(s1, s2, r); if r < 0.3 and async_g = 1 then prog_n <= not prog_n; end if;
      else
        uniform(s1, s2, r); if r < 0.3 and async_g = 0 then prog_n <= not prog_n; end if;
        if step = 41 then reset_n <= '1'; end if;
        uniform(s1, s2, r); if r < 0.1 and async_g = 0 then clk_en <= not clk_en; end if;
        uniform(s1, s2, r); if r < 0.02 then cs_n <= not cs_n; end if;
        uniform(s1, s2, r); if r < 0.3 then rvec(v); p2_i <= v; end if;
        uniform(s1, s2, r); if r < 0.05 then rvec(v); p4_i <= v; end if;
        uniform(s1, s2, r); if r < 0.05 then rvec(v); p5_i <= v; end if;
        uniform(s1, s2, r); if r < 0.05 then rvec(v); p6_i <= v; end if;
        uniform(s1, s2, r); if r < 0.05 then rvec(v); p7_i <= v; end if;
        uniform(s1, s2, r); if r < 0.0005 then reset_n <= '0'; elsif r > 0.999 then reset_n <= '1'; end if;
      end if;
      wait for 5 ns;
      -- t48sv sees the same inputs (entity port order of t8243_*_notri)
      k := 0;
      if async_g = 0 then
        i(0) := 1 when clk = '1' else 0; i(1) := 1 when clk_en = '1' else 0; k := 2;
      end if;
      i(k) := 1 when reset_n = '1' else 0;
      i(k+1) := 1 when cs_n = '1' else 0;
      i(k+2) := 1 when prog_n = '1' else 0;
      k := k + 3;
      for b in 0 to 3 loop i(k + b) := 1 when p2_i(b) = '1' else 0; end loop;
      for b in 0 to 3 loop i(k + 4 + b) := 1 when p4_i(b) = '1' else 0; end loop;
      for b in 0 to 3 loop i(k + 8 + b) := 1 when p5_i(b) = '1' else 0; end loop;
      for b in 0 to 3 loop i(k + 12 + b) := 1 when p6_i(b) = '1' else 0; end loop;
      for b in 0 to 3 loop i(k + 16 + b) := 1 when p7_i(b) = '1' else 0; end loop;
      cs_eval(h, i, o);
      exp := p7_en & p7_o & p6_en & p6_o & p5_en & p5_o & p4_en & p4_o & p2_en & p2_o;
      for b in 0 to 24 loop
        if exp(b) = '0' or exp(b) = '1' then
          if (exp(b) = '1') /= (o(b) = 1) then
            mism := mism + 1;
            if mism < 10 then
              report "MISMATCH step " & integer'image(step) & " bit " & integer'image(b) &
                     " t48=" & std_logic'image(exp(b)) & " cs_n=" & std_logic'image(cs_n) &
                     " prog_n=" & std_logic'image(prog_n) & " p2_i=" & to_string(p2_i) &
                     " rst=" & std_logic'image(reset_n) severity note;
            end if;
          end if;
        else
          masked := masked + 1;
        end if;
      end loop;
      n := n + 1;
    end loop;
    report "RESULT8243 async=" & integer'image(async_g) & " steps=" & integer'image(n) &
           " mismatches=" & integer'image(mism) & " masked_dont_care_bits=" & integer'image(masked)
      severity note;
    wait;
  end process;
end behav;

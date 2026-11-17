-- Cross-check of the GHDL-converted reference: replays a stimulus file through the original VHDL
-- (s2650_cpu / sgs2650) in the GHDL simulator and compares every output bit with the file
-- (outputs of the converted netlist under Verilator). 'U' / 'X' bits in the VHDL are counted, not compared.
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE std.textio.ALL;
USE ieee.std_logic_textio.ALL;

ENTITY tb_xcheck IS
  GENERIC (FNAME : string := "stim.txt");
END ENTITY;

ARCHITECTURE sim OF tb_xcheck IS
  SIGNAL clk, reset, ack, irq, sense : std_logic := '0';
  SIGNAL dr, ivec : std_logic_vector(7 DOWNTO 0) := x"00";
  SIGNAL req, wr, mio, ene, dc, intack, flag : std_logic;
  SIGNAL ad : std_logic_vector(14 DOWNTO 0);
  SIGNAL dw : std_logic_vector(7 DOWNTO 0);
  SIGNAL ph : std_logic_vector(1 DOWNTO 0);
BEGIN
  dut : ENTITY work.s2650_cpu
    PORT MAP (clk => clk, reset => reset, req => req, ack => ack, ad => ad, wr => wr, dw => dw, dr => dr,
              mio => mio, ene => ene, dc => dc, ph => ph, irq => irq, intack => intack, ivec => ivec,
              sense => sense, flag => flag);

  PROCESS
    FILE f : text OPEN read_mode IS FNAME;
    VARIABLE l, o : line;
    VARIABLE i_rst, i_ack, i_irq, i_sns : integer;
    VARIABLE i_dr, i_iv : std_logic_vector(7 DOWNTO 0);
    VARIABLE r : std_logic_vector(31 DOWNTO 0);
    VARIABLE got : std_logic_vector(31 DOWNTO 0);
    VARIABLE ncyc, nbits, nundef, nmis : natural := 0;
  BEGIN
    WHILE NOT endfile(f) LOOP
      readline(f, l);
      read(l, i_rst); read(l, i_ack); read(l, i_irq); read(l, i_sns); hread(l, i_dr); hread(l, i_iv); hread(l, r);
      IF i_rst = 1 THEN reset <= '1'; ELSE reset <= '0'; END IF;
      IF i_ack = 1 THEN ack <= '1'; ELSE ack <= '0'; END IF;
      IF i_irq = 1 THEN irq <= '1'; ELSE irq <= '0'; END IF;
      IF i_sns = 1 THEN sense <= '1'; ELSE sense <= '0'; END IF;
      dr <= i_dr; ivec <= i_iv;
      WAIT FOR 5 ns;
      got := flag & intack & ph & dc & ene & mio & dw & wr & ad & req;
      FOR k IN 0 TO 31 LOOP
        IF got(k) = '0' OR got(k) = '1' THEN
          nbits := nbits + 1;
          IF got(k) /= r(k) THEN
            nmis := nmis + 1;
            IF nmis <= 10 THEN
              write(o, string'("MISMATCH cycle ")); write(o, ncyc); write(o, string'(" bit ")); write(o, k);
              writeline(output, o);
            END IF;
          END IF;
        ELSE
          nundef := nundef + 1;
        END IF;
      END LOOP;
      clk <= '1'; WAIT FOR 5 ns; clk <= '0';
      ncyc := ncyc + 1;
    END LOOP;
    write(o, string'("xcheck ")); write(o, FNAME); write(o, string'(": cycles ")); write(o, ncyc);
    write(o, string'(", output bits compared ")); write(o, nbits); write(o, string'(", undefined in VHDL (U/X) "));
    write(o, nundef); write(o, string'(", mismatches ")); write(o, nmis);
    writeline(output, o);
    WAIT;
  END PROCESS;
END ARCHITECTURE;

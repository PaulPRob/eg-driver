-- Simulation stand-in for the Spartan-6 BUFIO2, which Vivado's UNISIM does
-- not model (its retarget entity stops the simulation).  With DIVIDE_BYPASS
-- it is a wire, which is how vcxo_clk uses it.
library ieee;
use ieee.std_logic_1164.all;

entity BUFIO2 is
  generic (
    DIVIDE_BYPASS : boolean := TRUE;
    DIVIDE        : integer := 1;
    I_INVERT      : boolean := FALSE;
    USE_DOUBLER   : boolean := FALSE
    );
  port (
    DIVCLK       : out std_ulogic;
    IOCLK        : out std_ulogic;
    SERDESSTROBE : out std_ulogic;
    I            : in  std_ulogic
    );
end entity;

architecture sim of BUFIO2 is
begin
  assert DIVIDE_BYPASS and not I_INVERT and not USE_DOUBLER
    report "bufio2_sim only models DIVIDE_BYPASS = TRUE" severity failure;
  DIVCLK       <= I;
  IOCLK        <= I;
  SERDESSTROBE <= '0';
end architecture;

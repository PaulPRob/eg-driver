-------------------------------------------------------------------------------
-- (c) Copyright - Commonwealth Scientific and Industrial Research Organisation
-- (CSIRO) - 2009
--
-- All Rights Reserved.
--
-- Restricted Use.
--
-- Copyright protects this code. Except as permitted by the Copyright Act, you
-- may only use the code as expressly permitted under the terms on which the
-- code was licensed to you.
--
-------------------------------------------------------------------------------
--
-- File Name: eg_clk_reset.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: EG Clock Reset Module
--
-- Description: 
--
--
-- Compiler options:
-- 
-- 
-- Dependencies:
-- 
-- 
-- 
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library unisim;
use unisim.vcomponents.all;
use work.all;

entity eg_clk_reset is
port(

    vco_16m : in  std_logic;
    locked  : in  std_logic;           -- ATNF MOD FOR EG: vcxo_clk lock
    reset   : out std_logic

);

end eg_clk_reset;

architecture behavioral of eg_clk_reset is

  signal sig_reset_hold_count : std_logic_vector(15 downto 0) := x"0000";
  signal sig_reset            : std_logic                     := '1';

begin

-- ATNF MOD FOR EG --
-- Restart the hold whenever vcxo_clk is out of lock, so clocks_gen only runs
-- from a stable 16 MHz.  locked is '1' when the VCXO is used directly.
-- END ATNF MOD --
process(vco_16m, locked, sig_reset_hold_count, sig_reset)
  begin
    if locked = '0' then
      sig_reset_hold_count <= (others => '0');
      sig_reset            <= '1';
    elsif rising_edge(vco_16m) then
      if sig_reset_hold_count = x"FFFF" then
        sig_reset_hold_count <= sig_reset_hold_count;
        sig_reset            <= '0';
      else
        sig_reset_hold_count <= sig_reset_hold_count + 1;
        sig_reset            <= '1';
      end if;
    else
      sig_reset_hold_count <= sig_reset_hold_count;
      sig_reset            <= sig_reset;
    end if;
end process;

  reset <= sig_reset;

end behavioral;


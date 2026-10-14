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
-- File Name: clocks_gen.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Clock Generator
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

entity clocks_gen is
port (
    vco_16m : in  std_logic;            -- bufferred clock
    rst     : in  std_logic;
    xfs     : in  std_logic;
    clocks  : out std_logic_vector(17 downto 0)

);
end entity;

architecture structure of clocks_gen is

  signal sig_qclk_buffered : std_logic;
  signal sig_count_top     : std_logic_vector(3 downto 0) := "0000";
  signal sig_count_bottom  : std_logic_vector(9 downto 0) := "0000000000";
  signal sig_8mhzb_b       : std_logic;
  signal sig_8mhzb_ub      : std_logic;
  signal sig_4mhzb_ub      : std_logic;
  signal sig_2mhzb_ub      : std_logic;
  signal sig_1mhzb_b       : std_logic;
  signal sig_1mhzb_ub      : std_logic;
  signal sig_1mhzq_b       : std_logic;
  signal sig_1mhzq_ub      : std_logic;
  signal sig_1mhzd_ub      : std_logic;
  
  
begin

-- Buffer Q clock. this signal will then be used for all sub clocks
  bufg_qclk      : bufg port map (i => sig_1mhzq_ub, o => sig_1mhzq_b);
  bufg_clkt_1mhz : bufg port map (i => sig_1mhzb_ub, o => sig_1mhzb_b);


process(vco_16m, rst, sig_count_top)
  begin
    if rst = '1' then
      sig_count_top <= (others => '0');
    elsif rising_edge(vco_16m) then
      sig_count_top <= sig_count_top + 1;
    else
      sig_count_top <= sig_count_top;
    end if;
end process;

  sig_8mhzb_ub <= sig_count_top(0);
  sig_4mhzb_ub <= sig_count_top(1);
  sig_2mhzb_ub <= sig_count_top(2);
  sig_1mhzb_ub <= sig_count_top(3);
  sig_1mhzd_ub <= not sig_count_top(3);


sys_clk_gen : process(vco_16m, sig_count_top, rst, sig_1mhzq_ub)
  begin
    if rst = '1' then
      sig_1mhzq_ub <= '0';
      
    elsif rising_edge(vco_16m) then

      -- rising_edge(CLKQ)
      if sig_count_top = 3 then
        sig_1mhzq_ub <= '1';

      -- falling_edge(CLKQ)
      elsif sig_count_top = 11 then
        sig_1mhzq_ub <= '0';
      else
        sig_1mhzq_ub <= sig_1mhzq_ub;
      end if;
    else
      sig_1mhzq_ub <= sig_1mhzq_ub;
    end if;

end process;



us_counter_inst : process(sig_1mhzq_b, xfs, sig_count_bottom)
  begin
    if rising_edge(sig_1mhzq_b) then
      if xfs = '1' or sig_count_bottom = 999 then
        sig_count_bottom <= (others => '0');
      else
        sig_count_bottom <= sig_count_bottom + 1;
      end if;
    else
      sig_count_bottom <= sig_count_bottom;
    end if;
end process;

  sig_2mhzb_ub <= sig_count_top(2);
  sig_1mhzb_ub <= sig_count_top(3);



  clocks(0)  <= vco_16m;
  clocks(1)  <= sig_8mhzb_ub;
  clocks(2)  <= sig_4mhzb_ub;
  clocks(3)  <= sig_2mhzb_ub;
  clocks(4)  <= sig_1mhzb_b;
  clocks(5)  <= sig_1mhzd_ub;
  clocks(6)  <= sig_1mhzq_ub;
  clocks(7)  <= sig_count_bottom(0);
  clocks(8)  <= sig_count_bottom(1);
  clocks(9)  <= sig_count_bottom(2);
  clocks(10) <= sig_count_bottom(3);
  clocks(11) <= sig_count_bottom(4);
  clocks(12) <= sig_count_bottom(5);
  clocks(13) <= sig_count_bottom(6);
  clocks(14) <= sig_count_bottom(7);
  clocks(15) <= sig_count_bottom(8);
  clocks(16) <= sig_count_bottom(9);
  clocks(17) <= sig_1mhzb_ub;

  
  
end architecture;

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
-- File Name: onewire_clk.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Onewire Clock Module
--
-- Description: Module divides down the bus clock to 31.25 Mhz
--
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


entity onewire_clk is
  port(

    bclk  : in  std_logic;
    reset : in  std_logic;
    clk   : out std_logic
	 
	 );

end onewire_clk;

architecture behavioral of onewire_clk is

signal sig_count : std_logic_vector(1 downto 0) := "00";

begin

----------------------------------------------------------------------------------
--Clock Division to 31.25mhz
----------------------------------------------------------------------------------

  process(bclk, reset, sig_count)
  begin
    if reset = '1' then
      sig_count <= "00";
    elsif rising_edge(bclk) then
      sig_count <= sig_count + 1;
    else
      sig_count <= sig_count;
    end if;
  end process;


  clk25_bufg : bufg
    port map (
      o => clk,                         -- Clock buffer output
      i => sig_count(0)                 -- Clock buffer input
      );

end behavioral;


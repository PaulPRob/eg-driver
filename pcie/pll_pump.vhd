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
-- File Name: pll_pump.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: PLL Pump
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
use ieee.numeric_std.all;
use work.clocks_package.all;
library unisim;
use unisim.vcomponents.all;


entity pll_pump is
  port (
    bat_serial : in  std_logic;
    clocks     : in  std_logic_vector(17 downto 0);
    up         : out std_logic;
    down       : out std_logic
    );
end entity;

architecture structure of pll_pump is
  
  signal clocks_local : clocks_t;

  type state is (low, high);
  signal current_state : state;


begin
  
  clocks_local <= slv_to_clocks(clocks);

  -- Determines whether clkt leads (UP=1; DOWN=0) or lags (UP=0; DOWN=1) the bat signal.
  -- If both signals are in phase or the exact phase relationship cannot be determined, set UP=1; DOWN=1.
  -- Since the duty cycle of bat varies (between 33% and 66%), only the rising edges can be used to
  -- compare the phase relationship of the two signals.


  current_state <= low when bat_serial = '0' and clocks_local.clkt_1mhz_ub = '0' else
                    high when bat_serial = '1' and clocks_local.clkt_1mhz_ub = '1' else
                    current_state;


  up   <= '0' when current_state = low and bat_serial = '1' and clocks_local.clkt_1mhz_ub = '0' else '1';
  down <= '0' when current_state = low and bat_serial = '0' and clocks_local.clkt_1mhz_ub = '1' else '1';
  

end structure;

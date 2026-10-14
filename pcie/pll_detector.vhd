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
-- File Name: pll_detector.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Phase Locked Loop Detector
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

entity pll_detector is
  port (
    bat_serial : in std_logic;
    clocks     : in std_logic_vector(17 downto 0);

    out_of_lock : out std_logic
    );
end entity;

architecture structure of pll_detector is

  signal sig_clocks : clocks_t;

  signal sig_bat_low         : std_logic;
  signal sig_bat_high        : std_logic;
  signal sig_bat_phase_error : std_logic;

  -- When the msb of the count goes high, the numbers of errors is assumed to have exceeded the allowable threshold.
  -- To make out_of_lock more sensitive to errors, reduce the width of the following counter.
  signal sig_bat_phase_error_count : unsigned(4 downto 0);

  signal sig_out_of_lock_local : std_logic;

begin

  sig_clocks <= slv_to_clocks(clocks);

  process(sig_clocks.vco_16m, sig_clocks.clkt_1mhz_ub, sig_clocks.clkb_2mhz, sig_clocks.clkb_4mhz, sig_clocks.clkb_8mhz)
    variable vco_count : unsigned(3 downto 0);
  begin
    vco_count := sig_clocks.clkt_1mhz_ub & sig_clocks.clkb_2mhz & sig_clocks.clkb_4mhz & sig_clocks.clkb_8mhz;
    if rising_edge(sig_clocks.vco_16m) then

      -- 62.5ns before rising_edge(CLKT)
      if vco_count = 6 then
        sig_bat_low <= bat_serial;

      -- 62.5ns after rising_edge(CLKT)
      elsif vco_count = 8 then
        sig_bat_high <= bat_serial;
      end if;

      if sig_bat_low = '0' and sig_bat_high = '1' then
        sig_bat_phase_error <= '0';
      else
        sig_bat_phase_error <= '1';
      end if;

      if sig_bat_phase_error = '0' then
        sig_bat_phase_error_count <= to_unsigned(0, sig_bat_phase_error_count'length);
      elsif sig_bat_phase_error_count(sig_bat_phase_error_count'high) = '0' then
        sig_bat_phase_error_count <= sig_bat_phase_error_count + 1;
      end if;
    end if;
  end process;

  out_of_lock <= sig_bat_phase_error_count(sig_bat_phase_error_count'high);

end structure;

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
-- File Name: waveform_quad.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Waveform Quad
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

package waveform_quad_pkg is
  type wf_sel_t is array(0 to 3) of std_logic_vector(3 downto 0);
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.waveform_quad_pkg.all;
use work.clocks_package.all;

entity waveform_quad is
  port (
    clocks : in clocks_t;
    rst    : in std_logic;

    wf_500khz : in std_logic;
    wf_250khz : in std_logic;

    prescale : in unsigned(15 downto 0);
    wf_sel   : in wf_sel_t;

    wf_out : out std_logic_vector(3 downto 0)
    );
end entity;

architecture structure of waveform_quad is

  -- PS = prescale + 1

  -- divider_count(0) => 1 / (PS *   2) MHz
  -- divider_count(1) => 1 / (PS *   4) MHz
  -- divider_count(2) => 1 / (PS *   8) MHz
  -- divider_count(3) => 1 / (PS *  16) MHz
  -- divider_count(4) => 1 / (PS *  32) MHz
  -- divider_count(5) => 1 / (PS *  64) MHz
  -- divider_count(6) => 1 / (PS * 128) MHz
  -- divider_count(7) => 1 / (PS * 256) MHz.
  signal prescale_count : unsigned(15+1 downto 0);
  signal divider_count  : unsigned(7 downto 0);

  -- 1/(PS*32)MHz       Quadrature.
  signal quadrature : std_logic;
  signal waveform_table : std_logic_vector(15 downto 0);
  signal enable_waveforms : std_logic;

begin
  process(clocks.vco_16m, clocks.clkt_1mhz_ub, clocks.clkb_2mhz, clocks.clkb_4mhz, clocks.clkb_8mhz)
    variable vco_count : unsigned(3 downto 0);
  begin
    vco_count := clocks.clkt_1mhz_ub & clocks.clkb_2mhz & clocks.clkb_4mhz & clocks.clkb_8mhz;
    if rising_edge(clocks.vco_16m) and vco_count = 3 then

      if rst = '0' then
        enable_waveforms <= '1';
      elsif rst = '1' then
        enable_waveforms <= '0';
      end if;

      if rst = '1' or enable_waveforms = '0' then
        prescale_count <= to_unsigned(0, prescale_count'length);
        divider_count  <= unsigned(not std_logic_vector(to_unsigned(0, divider_count'length)));

        wf_out(0) <= '0';
        wf_out(1) <= '0';
        wf_out(2) <= '0';
        wf_out(3) <= '0';
      else
        if prescale_count = prescale then
          prescale_count <= to_unsigned(0, prescale_count'length);
          divider_count  <= divider_count - 1;
        else
          prescale_count <= prescale_count + 1;
        end if;

        if divider_count(4 downto 0) = "01000" then
          quadrature <= '1';
        elsif divider_count(4 downto 0) = "11000" then
          quadrature <= '0';
        end if;

        wf_out(0) <= waveform_table(to_integer(unsigned(wf_sel(0))));
        wf_out(1) <= waveform_table(to_integer(unsigned(wf_sel(1))));
        wf_out(2) <= waveform_table(to_integer(unsigned(wf_sel(2))));
        wf_out(3) <= waveform_table(to_integer(unsigned(wf_sel(3))));
      end if;

    end if;
  end process;

  waveform_table <= '1' &
                        '1' &
                        '0' &
                        '0' &
                        wf_500khz &
                        wf_250khz &
                        quadrature &
                        divider_count(7) &
                        divider_count(6) &
                        divider_count(5) &
                        divider_count(4) &
                        divider_count(3) &
                        divider_count(2) &
                        divider_count(1) &
                        divider_count(0) &
                        '0';

end architecture;

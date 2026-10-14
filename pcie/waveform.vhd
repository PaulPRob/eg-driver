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
-- File Name: waveform.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Waveform
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
use work.pci_package.all;
use work.waveform_quad_pkg.all;

entity waveform is
  port (
    clocks              : in std_logic_vector(17 downto 0);
    waveform_control    : in std_logic_vector(63 downto 0);
    event_output_status : in std_logic_vector(1 downto 0);

    waveform_status : out std_logic_vector(9 downto 0);
    wf_out          : out std_logic_vector(7 downto 0)
    );
end waveform;

architecture structure of waveform is
  signal clocks_local              : clocks_t;
  signal waveform_control_local    : waveform_control_t;
  signal event_output_status_local : event_output_status_t;
  signal sig_wf_out : std_logic_vector(7 downto 0);

  -- 500kHz and 250kHz signals.
  signal divider_1mhz_count : unsigned(1 downto 0);

  signal waveform_status_local : waveform_status_t;

  signal sink : std_logic;

begin
  clocks_local              <= slv_to_clocks(clocks);
  waveform_control_local    <= slv_to_waveform_control(waveform_control);
  event_output_status_local <= slv_to_event_output_status(event_output_status);

  process(clocks_local.clkt_1mhz_ub, clocks_local.clkb_2mhz, clocks_local.clkb_4mhz,
          clocks_local.clkb_8mhz)
    variable vco_count : unsigned(2 downto 0);
  begin
    vco_count := clocks_local.clkt_1mhz_ub & clocks_local.clkb_2mhz & clocks_local.clkb_4mhz;
    if rising_edge(clocks_local.clkb_8mhz) and vco_count = 1 then
      if event_output_status_local.waveform_generator_event_line = '1' then
        divider_1mhz_count <= divider_1mhz_count + 1;
      else
        divider_1mhz_count <= to_unsigned(0, divider_1mhz_count'length);
      end if;
    end if;
  end process;

  wf_out_0_3_inst : block is
    signal wf_sel_local : wf_sel_t;
  begin
    wf_sel_local <= (waveform_control_local.waveform_selection_0,
                       waveform_control_local.waveform_selection_1,
                       waveform_control_local.waveform_selection_2,
                       waveform_control_local.waveform_selection_3);

    wf_out_0_3 : entity work.waveform_quad port map (
      clocks => clocks_local,
      rst    => not event_output_status_local.waveform_generator_event_line,

      wf_500khz => divider_1mhz_count(1),
      wf_250khz => divider_1mhz_count(0),

      prescale => waveform_control_local.prescale_counter_0_3,
      wf_sel   => wf_sel_local,

      wf_out => sig_wf_out(3 downto 0)
      );
  end block;

  wf_out_4_7_inst : block is
    signal wf_sel_local : wf_sel_t;
  begin
    wf_sel_local <= (waveform_control_local.waveform_selection_4,
                        waveform_control_local.waveform_selection_5,
                        waveform_control_local.waveform_selection_6,
                        waveform_control_local.waveform_selection_7);

    wf_out_4_7 : entity work.waveform_quad port map (
      clocks => clocks_local,
      rst    => not event_output_status_local.waveform_generator_event_line,

      wf_500khz => divider_1mhz_count(1),
      wf_250khz => divider_1mhz_count(0),

      prescale => waveform_control_local.prescale_counter_4_7,
      wf_sel   => wf_sel_local,

      wf_out => sig_wf_out(7 downto 4)
      );
  end block;

  waveform_status_local.waveform_output_0_state <= sig_wf_out(0);
  waveform_status_local.waveform_output_1_state <= sig_wf_out(1);
  waveform_status_local.waveform_output_2_state <= sig_wf_out(2);
  waveform_status_local.waveform_output_3_state <= sig_wf_out(3);
  waveform_status_local.waveform_output_4_state <= sig_wf_out(4);
  waveform_status_local.waveform_output_5_state <= sig_wf_out(5);
  waveform_status_local.waveform_output_6_state <= sig_wf_out(6);
  waveform_status_local.waveform_output_7_state <= sig_wf_out(7);
  waveform_status_local.waveform_output_0_3_enabled <=
    event_output_status_local.waveform_generator_event_line;
  waveform_status_local.waveform_output_4_7_enabled <=
    event_output_status_local.waveform_generator_event_line;

  waveform_status <= waveform_status_to_slv(waveform_status_local);

   wf_out <= sig_wf_out;

end architecture;

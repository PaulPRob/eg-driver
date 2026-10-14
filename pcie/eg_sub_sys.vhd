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
-- File Name: eg_sub_sys.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Event Generator Sub System
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
use     ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library unisim;
use unisim.vcomponents.all;
use work.all;

entity eg_sub_sys is port (
    
	 -- PLL --
	 bat_serial       : in  std_logic;
	 up               : out std_logic;
	 down             : out std_logic;
	 vco_16m          : in  std_logic;
	 
	 -- Timing --
	 se_event_out     : out std_logic_vector(15 downto 8);
	 se_event_strobe  : out std_logic;
	 clkb_2mhz        : out std_logic;
	 clkb_8mhz        : out std_logic;
	 clkdata          : out std_logic;
	 clkd_1mhz        : out std_logic;
	 clkq_1mhz        : out std_logic;
	 clkt_1mhz        : out std_logic;
	 cntr_in          : in  std_logic;
	 cntr_out         : out std_logic;
	 t2ppms           : out std_logic;
	 t4ppms           : out std_logic;
	 t8ppms           : out std_logic;
	 t16ppms          : out std_logic;
	 t31ppms          : out std_logic;
	 t62ppms          : out std_logic;
	 t125khz          : out std_logic;
	 t250khz          : out std_logic;
	 t500khz          : out std_logic;
	 unused_input     : in  std_logic;
	 x1sclk           : out std_logic;
	 x1sec            : out std_logic;
	 xfs              : out std_logic;
	 extint0          : in  std_logic;
	 ext_trig0        : in  std_logic;
	 ext_trig1        : in  std_logic;
	 msclk            : out std_logic;
	
	 --Waveform out -- 
	 wf_out           : out std_logic_vector(7 downto 0);

	 --Event out --
	 event_out        : out std_logic_vector(15 downto 0);
	 event_strobe     : out std_logic;
	
	 -- LEDS out --
	 out_of_lock      : out std_logic;
	 running          : out std_logic;
	 
	 -- One Wire Serial No. --
    onewire_oe     : out std_logic;                            
    onewire_o      : out std_logic;                               
    onewire_i      : in std_logic;	

    write_ident_fifo_data 	: in std_logic_vector(7 downto 0);
    write_ident_fifo_load  : in std_logic;
    write_ident_fifo_reset : in std_logic;
    
    -- PCI signals --
    clocks      : out std_logic_vector(17 downto 0);
    trn_reset_n : in  std_logic;
    bclk 		 : in std_logic;
    
    master_control      : in std_logic_vector(8 downto 0);
    interrupt_control   : in std_logic_vector(14 downto 0);
    clear_interrupts    : in std_logic_vector(13 downto 0);
    interrupt_status    : out std_logic_vector(13 downto 0);
    event_output_control: in std_logic_vector(12 downto 0);
    waveform_control    : in std_logic_vector(63 downto 0);
    master_status       : out std_logic_vector(11 downto 0);
    event_output_status : out std_logic_vector(1 downto 0);
    waveform_status     : out std_logic_vector(9 downto 0);

    frame_byte          : out std_logic_vector(7 downto 0);
    frame_byte_load     : in std_logic;
    async_event_read    : out std_logic_vector(15 downto 0);

    async_event_write   : in std_logic_vector(15 downto 0);
    async_event_write_load: in std_logic;

    ls_sync_event       : in std_logic_vector(7 downto 0);
    ls_sync_event_load  : in std_logic;
    ms_sync_event       : in std_logic_vector(7 downto 0);
    ms_sync_event_load  : in std_logic;

    rising_control      : in std_logic_vector(31 downto 0);
    clear_rising        : in std_logic_vector(31 downto 0);
    rising_status       : out std_logic_vector(31 downto 0);

    falling_control     : in std_logic_vector(31 downto 0);
    clear_falling       : in std_logic_vector(31 downto 0);
    falling_status      : out std_logic_vector(31 downto 0);
    
    lint1                : out std_logic;
    ident_serial_out_address_inc  : in std_logic
 
 );

begin

end eg_sub_sys;


architecture structure of eg_sub_sys is 
   
  signal sig_bat                     : std_logic_vector(47 downto 0);
  signal sig_event_out               : std_logic_vector(15 downto 0);
  signal sig_event_strobe            : std_logic;
  signal sig_out_of_lock             : std_logic;
  signal sig_event_generator_running : std_logic;
  signal sig_wf_out                  : std_logic_vector(7 downto 0);
  signal sig_x1sec                   : std_logic;
  signal sig_xfs                     : std_logic;
  signal sig_ls_ref_fifo_empty       : std_logic;
  signal sig_ms_ref_fifo_empty       : std_logic;
  signal sig_ls_ref_fifo_half        : std_logic;
  signal sig_ms_ref_fifo_half        : std_logic;
  signal sig_ls_ref_fifo_full        : std_logic;
  signal sig_ms_ref_fifo_full        : std_logic;
  signal sig_clocks                  : std_logic_vector(17 downto 0);
  signal sig_event_output_status     : std_logic_vector(1 downto 0);
  signal sig_internal_interrupt      : std_logic;
  signal sig_late_event              : std_logic;
  signal sig_checksum_error          : std_logic;
  signal sig_false_sync              : std_logic;
  signal sig_frame_fifo_empty        : std_logic;
  signal sig_frame_loaded            : std_logic;
  signal sig_missed_sync             : std_logic;
  signal sig_serial_number           : std_logic;
  signal sig_reset                   : STD_LOGIC := '1';
		
	
begin

  Inst_reset_hold : entity eg_clk_reset port map (
    vco_16m => vco_16m,
    reset   => sig_reset
	 );
  
  Inst_clocks_gen : entity clocks_gen port map (
    clocks(17 downto 0) => sig_clocks(17 downto 0),
    rst                 => sig_reset,
    xfs                 => sig_xfs,
    vco_16m             => vco_16m
	 );

  Inst_event_gen : entity event_gen port map (
    async_event_write(15 downto 0)    => async_event_write(15 downto 0),
    async_event_write_load            => async_event_write_load,
    bat(47 downto 0)                  => sig_bat(47 downto 0),
    bclk                              => bclk,
    clocks(17 downto 0)               => sig_clocks(17 downto 0),
    event_output_control(12 downto 0) => event_output_control(12 downto 0),
    event_output_status(1 downto 0)   => sig_event_output_status(1 downto 0),
    event_out(15 downto 0)            => sig_event_out(15 downto 0),
    event_strobe                      => sig_event_strobe,
    internal_interrupt                => sig_internal_interrupt,
    late_event                        => sig_late_event,
    ls_ref_fifo_empty                 => sig_ls_ref_fifo_empty,
    ls_ref_fifo_full                  => sig_ls_ref_fifo_full,
    ls_ref_fifo_half                  => sig_ls_ref_fifo_half,
    ls_sync_event(7 downto 0)         => ls_sync_event(7 downto 0),
    ls_sync_event_load                => ls_sync_event_load,
    master_control(8 downto 0)        => master_control(8 downto 0),
    ms_ref_fifo_empty                 => sig_ms_ref_fifo_empty,
    ms_ref_fifo_full                  => sig_ms_ref_fifo_full,
    ms_ref_fifo_half                  => sig_ms_ref_fifo_half,
    ms_sync_event(7 downto 0)         => ms_sync_event(7 downto 0),
    ms_sync_event_load                => ms_sync_event_load,
    running                           => sig_event_generator_running
    );

  Inst_frame_gen : entity frame_gen port map (
    bad_checksum               => sig_checksum_error,
    bat_slv(47 downto 0)       => sig_bat(47 downto 0),
    bat_serial                 => bat_serial,
    bclk                       => bclk,
    clkdata                    => clkdata,
    clocks(17 downto 0)        => sig_clocks(17 downto 0),
    false_sync                 => sig_false_sync,
    frame_byte(7 downto 0)     => frame_byte(7 downto 0),
    frame_byte_load            => frame_byte_load,
    frame_fifo_empty           => sig_frame_fifo_empty,
    frame_fifo_full            => open,
    frame_loaded               => sig_frame_loaded,
    master_control(8 downto 0) => master_control(8 downto 0),
    missed_sync                => sig_missed_sync,
    x1sec                      => sig_x1sec,
    xfs                        => sig_xfs
	 );

  Inst_interrupt_status_gen : entity interrupt_status_gen port map (
    bclk                           => bclk,
    checksum_error                 => sig_checksum_error,
    clear_falling(31 downto 0)     => clear_falling(31 downto 0),
    clear_interrupts(13 downto 0)  => clear_interrupts(13 downto 0),
    clear_rising(31 downto 0)      => clear_rising(31 downto 0),
    clocks(17 downto 0)            => sig_clocks(17 downto 0),
    dma_done                       => '0',
    event(15 downto 0)             => sig_event_out(15 downto 0),
    external_interrupt             => extint0,
    falling_control(31 downto 0)   => falling_control(31 downto 0),
    falling_status(31 downto 0)    => falling_status(31 downto 0),
    false_sync                     => sig_false_sync,
    finished                       => not sig_event_generator_running,
    frame_loaded                   => sig_frame_loaded,
    internal_interrupt             => sig_internal_interrupt,
    interrupt_control(14 downto 0) => interrupt_control(14 downto 0),
    interrupt_status(13 downto 0)  => interrupt_status(13 downto 0),
    late_event                     => sig_late_event,
    lint1                          => lint1,
    ls_ref_fifo_empty              => not sig_ls_ref_fifo_empty,
    ls_ref_fifo_half               => not sig_ls_ref_fifo_half,
    missed_sync                    => sig_missed_sync,
    ms_ref_fifo_empty              => not sig_ms_ref_fifo_empty,
    ms_ref_fifo_half               => not sig_ms_ref_fifo_half,
    one_second                     => sig_x1sec,
    pll_dropout                    => sig_out_of_lock,
    rising_control(31 downto 0)    => rising_control(31 downto 0),
    rising_status(31 downto 0)     => rising_status(31 downto 0),
    strobe                         => sig_event_strobe,
    waveforms(7 downto 0)          => sig_wf_out(7 downto 0)
	 );

  Inst_master_status_gen : entity master_status_gen port map (
    event_generator_running    => sig_event_generator_running,
    frame_fifo_empty           => sig_frame_fifo_empty,
    frame_loaded               => sig_frame_loaded,
    late_event                 => sig_late_event,
    ls_ref_fifo_empty          => not sig_ls_ref_fifo_empty,
    ls_ref_fifo_full           => not sig_ls_ref_fifo_full,
    ls_ref_fifo_half_empty     => not sig_ls_ref_fifo_half,
    master_status(11 downto 0) => master_status(11 downto 0),
    ms_ref_fifo_empty          => not sig_ms_ref_fifo_empty,
    ms_ref_fifo_full           => not sig_ms_ref_fifo_full,
    ms_ref_fifo_half_empty     => not sig_ms_ref_fifo_half,
    pll                        => sig_out_of_lock,
    serial_number              => sig_serial_number
    );

  Inst_pll_detector : entity pll_detector port map (
    bat_serial          => bat_serial,
    clocks(17 downto 0) => sig_clocks(17 downto 0),
    out_of_lock         => sig_out_of_lock
    );

  Inst_pll_pump : entity pll_pump port map (
    bat_serial          => bat_serial,
    clocks(17 downto 0) => sig_clocks(17 downto 0),
    down                => down,
    up                  => up
    );

  Inst_timing : entity timing port map (
    clkb_2mhz => clkb_2mhz,
    clkb_8mhz => clkb_8mhz,
    clkd_1mhz => clkd_1mhz,
    clkq_1mhz => clkq_1mhz,
    clkt_1mhz => clkt_1mhz,
    clocks    => sig_clocks,
    cntr_in   => cntr_in,
    cntr_out  => cntr_out,
    ext_trig0 => ext_trig0,
    ext_trig1 => ext_trig1,
    msclk     => msclk,
    t2ppms    => t2ppms,
    t4ppms    => t4ppms,
    t8ppms    => t8ppms,
    t16ppms   => t16ppms,
    t31ppms   => t31ppms,
    t62ppms   => t62ppms,
    t125khz   => t125khz,
    t250khz   => t250khz,
    t500khz   => t500khz,
    x1sclk    => x1sclk
    );

  Inst_waveform : entity waveform port map (
    clocks(17 downto 0)             => sig_clocks(17 downto 0),
    event_output_status(1 downto 0) => sig_event_output_status(1 downto 0),
    waveform_control(63 downto 0)   => waveform_control(63 downto 0),
    waveform_status(9 downto 0)     => waveform_status(9 downto 0),
    wf_out(7 downto 0)              => sig_wf_out(7 downto 0)
    );

  
  Inst_ident_prom_top : entity ident_prom_top port map (
    bclk                         => bclk,
    reset                        => not trn_reset_n,
    master_control               => master_control,
    ident_serial_out_address_inc => ident_serial_out_address_inc,
    read_serial_out              => sig_serial_number,
    write_ident_fifo_data        => write_ident_fifo_data,
    write_ident_fifo_load        => write_ident_fifo_load,
    write_ident_fifo_reset       => write_ident_fifo_reset,
    onewire_oe                   => onewire_oe,
    onewire_o                    => onewire_o,
    onewire_i                    => onewire_i
    );


	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

  
  async_event_read                <= sig_event_out;
  event_output_status(1 downto 0) <= sig_event_output_status(1 downto 0);
  clocks(17 downto 0)             <= sig_clocks(17 downto 0);

  se_event_out(15 downto 8) <= sig_event_out(7 downto 0);
  xfs             <= sig_xfs;
  x1sec           <= sig_x1sec;
  se_event_strobe <= sig_event_strobe;

  wf_out <= sig_wf_out;

  event_out    <= sig_event_out;
  event_strobe <= sig_event_strobe;

  out_of_lock <= sig_out_of_lock;
  running     <= sig_event_generator_running;
  
  
end structure;



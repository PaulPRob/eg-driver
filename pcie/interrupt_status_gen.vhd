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
-- File Name: interrupt_status_gen.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Interrupt Status Generator
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

library IEEE;
use IEEE.std_logic_1164.all;
use work.clocks_package.all;
use work.pci_package.all;

entity interrupt_status_gen is port (
    bclk               : in std_logic;
    interrupt_control  : in std_logic_vector(14 downto 0);
    clear_interrupts   : in std_logic_vector(13 downto 0);

    ls_ref_fifo_empty  : in std_logic;
    ms_ref_fifo_empty  : in std_logic;
    ls_ref_fifo_half   : in std_logic;
    ms_ref_fifo_half   : in std_logic;

    external_interrupt : in std_logic;
    late_event         : in std_logic;
    checksum_error     : in std_logic;
    false_sync         : in std_logic;
    missed_sync        : in std_logic;
    frame_loaded       : in std_logic;
    dma_done           : in std_logic;
    internal_interrupt : in std_logic;
    pll_dropout        : in std_logic;
    one_second         : in std_logic;                   
    finished           : in std_logic;

    lint1              : out std_logic;
    interrupt_status   : out std_logic_vector(13 downto 0);

    clocks             : in std_logic_vector(17 downto 0);

    waveforms          : in std_logic_vector(7 downto 0);
    event              : event_t;
    strobe             : std_logic;

    rising_control     : in std_logic_vector(31 downto 0);
    clear_rising       : in std_logic_vector(31 downto 0);
    rising_status      : out std_logic_vector(31 downto 0);

    falling_control    : in std_logic_vector(31 downto 0);
    clear_falling      : in std_logic_vector(31 downto 0);
    falling_status     : out std_logic_vector(31 downto 0)

   );
end entity;

architecture structure of interrupt_status_gen is
  
  signal sig_interrupt_control:  interrupt_control_t;
  signal sig_clear_interrupts:  interrupts_t;
 
  signal ls_ref_fifo_empty_status: std_logic;
  signal ms_ref_fifo_empty_status: std_logic;
  signal ls_ref_fifo_half_status: std_logic;
  signal ms_ref_fifo_half_status: std_logic;

  signal sig_interrupt_status:  interrupt_status_t;

  signal sig_clocks:    clocks_t;

  signal sig_rising_control:  supplementary_interrupts_t;
  signal sig_clear_rising:  supplementary_interrupts_t;
  signal sig_rising_status:  supplementary_interrupts_t;

  signal sig_falling_control:  supplementary_interrupts_t;
  signal sig_clear_falling:  supplementary_interrupts_t;
  signal sig_falling_status:  supplementary_interrupts_t;
    
begin
  
  sig_interrupt_control <= slv_to_interrupt_control(interrupt_control);
  sig_clear_interrupts <= slv_to_interrupts(clear_interrupts);
  sig_clocks <= slv_to_clocks(clocks);

  interrupt_status <= interrupt_status_to_slv(sig_interrupt_status);

  sig_rising_control  <= slv_to_supplementary_interrupts(rising_control);
  sig_clear_rising  <= slv_to_supplementary_interrupts(clear_rising);

  sig_falling_control  <= slv_to_supplementary_interrupts(falling_control);
  sig_clear_falling  <= slv_to_supplementary_interrupts(clear_falling);

  rising_status    <= supplementary_interrupts_to_slv(sig_rising_status);
  falling_status    <= supplementary_interrupts_to_slv(sig_falling_status);

  -- REF_FIFO_INTERRUPTS
  -- There are two interrupts relating to the reference fifo: ref_fifo_empty and ref_fifo_half_empty.

  -- Most interrupts are generated on the rising edge of only one input signal.
  -- For example, checksum_error interrupt is generated when there is a rising edge on the checksum_error input.

  -- The ref_fifo interrupts are different because each of them can be generated from the rising edge of two input signals. 
  -- For example, ref_fifo_empty interrupt is generated when there is a rising edge on the ls_ref_fifo_empty input *or* the ms_ref_fifo_empty input.

  ------------------------------------------------------------
  -- REFERENCE FIFO INTERRUPTS.
  ls_ref_fifo_empty_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.ref_fifo_empty,
    trigger=>ls_ref_fifo_empty,
    enable => sig_interrupt_control.ref_fifo_empty,
    status=>ls_ref_fifo_empty_status);

  ms_ref_fifo_empty_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.ref_fifo_empty,
    trigger=>ms_ref_fifo_empty,
    enable => sig_interrupt_control.ref_fifo_empty,
    status=>ms_ref_fifo_empty_status);

  ls_ref_fifo_half_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.ref_fifo_half_empty,
    trigger=>ls_ref_fifo_half,
    enable => sig_interrupt_control.ref_fifo_half_empty,
    status=>ls_ref_fifo_half_status);

  ms_ref_fifo_half_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.ref_fifo_half_empty,
    trigger=>ms_ref_fifo_half,
    enable => sig_interrupt_control.ref_fifo_half_empty,
    status=>ms_ref_fifo_half_status);

  sig_interrupt_status.ref_fifo_empty        <= ls_ref_fifo_empty_status or ms_ref_fifo_empty_status;
  sig_interrupt_status.ref_fifo_half_empty  <= ls_ref_fifo_half_status or ms_ref_fifo_half_status;
  ------------------------------------------------------------

  ------------------------------------------------------------
  -- OTHER INTERRUPTS.
  late_event_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.late_event,
    trigger=>late_event,
    enable => sig_interrupt_control.late_event,
    status=>sig_interrupt_status.late_event);

  checksum_error_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.checksum_error,
    trigger=>checksum_error,
    enable => sig_interrupt_control.checksum_error,
    status=>sig_interrupt_status.checksum_error);

  false_sync_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.false_sync,
    trigger=>false_sync,
    enable => sig_interrupt_control.false_sync,
    status=>sig_interrupt_status.false_sync);

  missed_sync_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.missed_sync,
    trigger=>missed_sync,
    enable => sig_interrupt_control.missed_sync,
    status=>sig_interrupt_status.missed_sync);

  frame_loaded_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.frame_loaded,
    trigger=>frame_loaded,
    enable => sig_interrupt_control.frame_loaded,
    status=>sig_interrupt_status.frame_loaded);

  dma_done_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.dma_done,
    trigger=>dma_done,
    enable => sig_interrupt_control.dma_done,
    status=>sig_interrupt_status.dma_done);

  external_interrupt_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.external_interrupt,
    trigger=>external_interrupt,
    enable => sig_interrupt_control.external_interrupt,
    status=>sig_interrupt_status.external_interrupt);

  internal_interrupt_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.internal_interrupt,
    trigger=>internal_interrupt,
    enable => sig_interrupt_control.internal_interrupt,
    status=>sig_interrupt_status.internal_interrupt);

  pll_dropout_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.pll_dropout,
    trigger=>pll_dropout,
    enable => sig_interrupt_control.pll_dropout,
    status=>sig_interrupt_status.pll_dropout);

  one_second_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.one_second,
    trigger=>one_second,
    enable => sig_interrupt_control.one_second,
    status=>sig_interrupt_status.one_second);

  finished_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_interrupts.finished,
    trigger=>finished,
    enable => sig_interrupt_control.finished,
    status=>sig_interrupt_status.finished);
  ------------------------------------------------------------


  ------------------------------------------------------------
  -- RISING_STATUS
  rising_event_buffer_gen: for n in 0 to 15 generate
    rising_event0_buffer: entity work.interrupt_buffer port map (clk=>bclk,
                                                                 rst=>sig_clear_rising.event(n),
                                                                 trigger=>event(n),
                                                                 enable => sig_rising_control.event(n),
                                                                 status=>sig_rising_status.event(n));
  end generate rising_event_buffer_gen;

  rising_wfg_buffer_gen: for n in 0 to 7 generate
    rising_waveforms0_buffer: entity work.interrupt_buffer port map (clk=>bclk,
                                                                     rst=>sig_clear_rising.waveforms(n),
                                                                     trigger=>waveforms(n),
                                                                     enable => sig_rising_control.waveforms(n),
                                                                     status=>sig_rising_status.waveforms(n));
  end generate rising_wfg_buffer_gen;

  rising_t2ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.t2ppms,
    trigger=>sig_clocks.t2ppms,
    enable => sig_rising_control.t2ppms,
    status=>sig_rising_status.t2ppms);

  rising_t4ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.t4ppms,
    trigger=>sig_clocks.t4ppms,
    enable => sig_rising_control.t4ppms,
    status=>sig_rising_status.t4ppms);

  rising_t8ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.t8ppms,
    trigger=>sig_clocks.t8ppms,
    enable => sig_rising_control.t8ppms,
    status=>sig_rising_status.t8ppms);

  rising_t16ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.t16ppms,
    trigger=>sig_clocks.t16ppms,
    enable => sig_rising_control.t16ppms,
    status=>sig_rising_status.t16ppms);

  rising_unused0_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.unused0,
    trigger=> '0',
    enable => sig_rising_control.unused0,
    status=>sig_rising_status.unused0);

  rising_unused1_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.unused1,
    trigger=> '0',
    enable => sig_rising_control.unused1,
    status=>sig_rising_status.unused1);

  rising_unused2_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.unused2,
    trigger=> '0',
    enable => sig_rising_control.unused2,
    status=>sig_rising_status.unused2);

  rising_event_strobe_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_rising.strobe,
    trigger=>strobe,
    enable => sig_rising_control.strobe,
    status=>sig_rising_status.strobe);
  ------------------------------------------------------------


  ------------------------------------------------------------
  -- FALLING_STATUS

  falling_event_buffer_gen: for n in 0 to 15 generate

    falling_event_buffer: entity work.interrupt_buffer port map (clk=>bclk,
                                                                 rst=>sig_clear_falling.event(n),
                                                                 trigger=>not event(n),
                                                                 enable => sig_falling_control.event(n),
                                                                 status=>sig_falling_status.event(n));  
  end generate falling_event_buffer_gen;
                          

  falling_wfg_buffer_gen: for n in 0 to 7 generate
    falling_waveforms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
                                                                     rst=>sig_clear_falling.waveforms(n),
                                                                     trigger=>not waveforms(n),
                                                                     enable => sig_falling_control.waveforms(n),
                                                                     status=>sig_falling_status.waveforms(n));
  end generate falling_wfg_buffer_gen;

  
  falling_t2ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.t2ppms,
    trigger=>not sig_clocks.t2ppms,
    enable => sig_falling_control.t2ppms,
    status=>sig_falling_status.t2ppms);

  falling_t4ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.t4ppms,
    trigger=>not sig_clocks.t4ppms,
    enable => sig_falling_control.t4ppms,
    status=>sig_falling_status.t4ppms);

  falling_t8ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.t8ppms,
    trigger=>not sig_clocks.t8ppms,
    enable => sig_falling_control.t8ppms,
    status=>sig_falling_status.t8ppms);

  falling_t16ppms_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.t16ppms,
    trigger=>not sig_clocks.t16ppms,
    enable => sig_falling_control.t16ppms,
    status=>sig_falling_status.t16ppms);

  falling_unused0_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.unused0,
    trigger=> '0',
    enable => sig_falling_control.unused0,
    status=>sig_falling_status.unused0);

  falling_unused1_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.unused1,
    trigger=> '0',
    enable => sig_falling_control.unused1,
    status=>sig_falling_status.unused1);

  falling_unused2_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.unused2,
    trigger=> '0',
    enable => sig_falling_control.unused2,
    status=>sig_falling_status.unused2);

  falling_event_strobe_buffer: entity work.interrupt_buffer port map (clk=>bclk,
    rst=>sig_clear_falling.strobe,
    trigger=>not strobe,
    enable => sig_falling_control.strobe,
    status=>sig_falling_status.strobe);
  ------------------------------------------------------------

  sig_interrupt_status.supplementary_interrupt  <=
    (sig_rising_control.event(0)  and sig_rising_status.event(0)) or
    (sig_rising_control.event(1)  and sig_rising_status.event(1)) or
    (sig_rising_control.event(2)  and sig_rising_status.event(2)) or
    (sig_rising_control.event(3)  and sig_rising_status.event(3)) or
    (sig_rising_control.event(4)  and sig_rising_status.event(4)) or
    (sig_rising_control.event(5)  and sig_rising_status.event(5)) or
    (sig_rising_control.event(6)  and sig_rising_status.event(6)) or
    (sig_rising_control.event(7)  and sig_rising_status.event(7)) or
    (sig_rising_control.event(8)  and sig_rising_status.event(8)) or
    (sig_rising_control.event(9)  and sig_rising_status.event(9)) or
    (sig_rising_control.event(10)  and sig_rising_status.event(10)) or
    (sig_rising_control.event(11)  and sig_rising_status.event(11)) or
    (sig_rising_control.event(12)  and sig_rising_status.event(12)) or
    (sig_rising_control.event(13)  and sig_rising_status.event(13)) or
    (sig_rising_control.event(14)  and sig_rising_status.event(14)) or
    (sig_rising_control.event(15)  and sig_rising_status.event(15)) or
    (sig_rising_control.t2ppms  and sig_rising_status.t2ppms) or
    (sig_rising_control.t4ppms  and sig_rising_status.t4ppms) or
    (sig_rising_control.t8ppms  and sig_rising_status.t8ppms) or
    (sig_rising_control.t16ppms  and sig_rising_status.t16ppms) or
    (sig_rising_control.strobe  and sig_rising_status.strobe) or


    (sig_falling_control.event(0)  and sig_falling_status.event(0)) or
    (sig_falling_control.event(1)  and sig_falling_status.event(1)) or
    (sig_falling_control.event(2)  and sig_falling_status.event(2)) or
    (sig_falling_control.event(3)  and sig_falling_status.event(3)) or
    (sig_falling_control.event(4)  and sig_falling_status.event(4)) or
    (sig_falling_control.event(5)  and sig_falling_status.event(5)) or
    (sig_falling_control.event(6)  and sig_falling_status.event(6)) or
    (sig_falling_control.event(7)  and sig_falling_status.event(7)) or
    (sig_falling_control.event(8)  and sig_falling_status.event(8)) or
    (sig_falling_control.event(9)  and sig_falling_status.event(9)) or
    (sig_falling_control.event(10) and sig_falling_status.event(10)) or
    (sig_falling_control.event(11) and sig_falling_status.event(11)) or
    (sig_falling_control.event(12) and sig_falling_status.event(12)) or
    (sig_falling_control.event(13) and sig_falling_status.event(13)) or
    (sig_falling_control.event(14) and sig_falling_status.event(14)) or
    (sig_falling_control.event(15) and sig_falling_status.event(15)) or
    (sig_falling_control.t2ppms  and sig_falling_status.t2ppms) or
    (sig_falling_control.t4ppms  and sig_falling_status.t4ppms) or
    (sig_falling_control.t8ppms  and sig_falling_status.t8ppms) or
    (sig_falling_control.t16ppms  and sig_falling_status.t16ppms) or
    (sig_falling_control.strobe   and sig_falling_status.strobe);


     lint1  <=  sig_interrupt_control.enable_interrupt and (
      (sig_interrupt_control.ref_fifo_empty and sig_interrupt_status.ref_fifo_empty) or
      (sig_interrupt_control.ref_fifo_half_empty and sig_interrupt_status.ref_fifo_half_empty) or
      (sig_interrupt_control.external_interrupt and sig_interrupt_status.external_interrupt) or
      (sig_interrupt_control.late_event and sig_interrupt_status.late_event) or
      (sig_interrupt_control.checksum_error and sig_interrupt_status.checksum_error) or
      (sig_interrupt_control.false_sync and sig_interrupt_status.false_sync) or
      (sig_interrupt_control.missed_sync and sig_interrupt_status.missed_sync) or
      (sig_interrupt_control.frame_loaded and sig_interrupt_status.frame_loaded) or
      (sig_interrupt_control.dma_done and sig_interrupt_status.dma_done) or
      (sig_interrupt_control.internal_interrupt and sig_interrupt_status.internal_interrupt) or
      (sig_interrupt_control.pll_dropout and sig_interrupt_status.pll_dropout) or
      (sig_interrupt_control.one_second and sig_interrupt_status.one_second) or
      (sig_interrupt_control.finished and sig_interrupt_status.finished) or
      (sig_interrupt_control.supplementary_interrupt and sig_interrupt_status.supplementary_interrupt));
     
       
	  
end structure;

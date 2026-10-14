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
-- File Name: eg.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Event Generator System Top Level
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

Library IEEE;
Use     IEEE.std_logic_1164.all;
use work.all;
Library UNISIM;
use UNISIM.vcomponents.all;

entity EG is 

  generic
    (
      FAST_TRAIN                        : boolean    := FALSE
      );

  port (
    
    -----------------------------------
    -- PCIe Signals --
    -----------------------------------
    pci_exp_txp : out std_logic;
    pci_exp_txn : out std_logic;
    pci_exp_rxp : in  std_logic;
    pci_exp_rxn : in  std_logic;

    sys_clk_p   : in  std_logic;
    sys_clk_n   : in  std_logic;
    sys_reset_n : in  std_logic;
    
    pci_lnk_up_debug_led : out std_logic; 
    

    ------------------------------------
    -- EG System --
    ------------------------------------
    
    -- PLL --
    vco_16m          : in    std_logic;
    up               : out   std_logic;
    down             : out   std_logic;
    bat              : in    std_logic;
    
    -- Timing --
    t125khz          : out   std_logic;
    t250khz          : out   std_logic;
    t500khz          : out   std_logic;
    clkd_1mhz        : out   std_logic;
    clkq_1mhz        : out   std_logic;
    clkt_1mhz        : out   std_logic;
    clkb_2mhz        : out   std_logic;
    clkb_8mhz        : out   std_logic;
    
    t8ppms           : out   std_logic;
    t16ppms          : out   std_logic;
    t31ppms          : out   std_logic;
    t62ppms          : out   std_logic;
    
    msclk            : out   std_logic;
    xfs              : out   std_logic;
    
    t2ppms           : out   std_logic;
    t4ppms           : out   std_logic;
    
    clkdata          : out   std_logic;
    busevent         : out   std_logic;
    cntr_out         : out   std_logic;
    x1sclk           : out   std_logic;
    x1sec            : out   std_logic;
    se_event_strobe  : out   std_logic;
    
    unused_input     : in    std_logic;
    extint0          : in    std_logic;
    ext_trig0        : in    std_logic;
    ext_trig1        : in    std_logic;
    cntr_in          : in    std_logic;
    
    se_event_out     : out   std_logic_vector(15 downto 8);
    
    u13_dir_in       : in    std_logic;
    u14_dir_in       : in    std_logic;
    u15_dir_in       : in    std_logic;
    u16_dir_in       : in    std_logic;
    u17_dir_in       : in    std_logic;
    
    u13_dir          : out    std_logic;
    u14_dir      		: out    std_logic;
    u15_dir				: out    std_logic;
    u16_dir          : out    std_logic;
    u17_dir          : out    std_logic;
    
    -- Event Out --
    event_out       : out   std_logic_vector(15 downto 0);
    event_strobe    : out   std_logic;
    
    -- Waveform Out --
    wf_out           : out   std_logic_vector(7 downto 0);
    
    -- LEDS Out --
    out_of_lock      : out   std_logic;
    running          : out   std_logic;

    
    -- Ident Serial Onewire  --
    serial_onewire  : inout std_logic;
    
    
    --Remote JTAG Interface
    jtag_core_tdo : in std_logic;
    jtag_core_select : out std_logic
    
    );


end EG;
------------------------------------------------------------

------------------------------------------------------------
architecture structure of EG is 


  -- EG Signals --
  signal   sig_vco16m_ibufg : std_logic;
  signal   sig_vco16m_bufg : std_logic;
  signal   sig_vco16m_bufio2 : std_logic;
  signal   sig_bclk : std_logic;
  
  -- EG PCI Signals --
  signal sig_clocks: std_logic_vector(17 downto 0);
  signal sig_master_control: std_logic_vector(8 downto 0);
  signal sig_interrupt_control: std_logic_vector(14 downto 0);
  signal sig_clear_interrupts: std_logic_vector(13 downto 0);
  signal sig_event_output_control: std_logic_vector(12 downto 0);
  signal sig_waveform_control : std_logic_vector(63 downto 0);
  signal sig_master_status : std_logic_vector(11 downto 0);
  signal sig_interrupt_status : std_logic_vector(13 downto 0);
  signal sig_event_output_status : std_logic_vector(1 downto 0);
  signal sig_waveform_status : std_logic_vector(9 downto 0);
  signal sig_frame_byte  : std_logic_vector(7 downto 0);
  signal sig_frame_byte_load  : std_logic;
  signal sig_async_event_read : std_logic_vector(15 downto 0);
  signal sig_async_event_write : std_logic_vector(15 downto 0);
  signal sig_async_event_write_load: std_logic;
  signal sig_ls_sync_event : std_logic_vector(7 downto 0);
  signal sig_ls_sync_event_load : std_logic;
  signal sig_ms_sync_event : std_logic_vector(7 downto 0);
  signal sig_ms_sync_event_load : std_logic;
  signal sig_rising_control : std_logic_vector(31 downto 0);
  signal sig_clear_rising : std_logic_vector(31 downto 0);
  signal sig_rising_status : std_logic_vector(31 downto 0);
  signal sig_falling_control : std_logic_vector(31 downto 0);
  signal sig_clear_falling  : std_logic_vector(31 downto 0);
  signal sig_falling_status  : std_logic_vector(31 downto 0);
  signal sig_lint1: std_logic;
  signal sig_ident_serial_out_address_inc: std_logic;
  signal sig_write_ident_fifo_data: std_logic_vector(7 downto 0);
  signal sig_write_ident_fifo_load: std_logic;
  signal sig_write_ident_fifo_reset: std_logic;
  
  --Serial onewire interface --
  signal sig_onewire_i: std_logic;
  signal sig_onewire_o: std_logic;
  signal sig_onewire_oe: std_logic;
  
  -- PCIe Signals --
  signal sys_clk_c : std_logic;
  signal sig_trn_lnk_up_n : std_logic;
  signal sig_trn_reset_n : std_logic;
  signal sig_sys_reset_n_c : std_logic;	

  signal sig_rd_addr       : std_logic_vector(10 downto 0);
  signal sig_rd_be         : std_logic_vector(3 downto 0);
  signal sig_rd_data       : std_logic_vector(31 downto 0);
  signal sig_rd_en	   : std_logic;

  signal sig_wr_addr       : std_logic_vector(10 downto 0);
  signal sig_wr_be         : std_logic_vector(7 downto 0);
  signal sig_wr_data       : std_logic_vector(31 downto 0);
  signal sig_wr_en         : std_logic;
  signal sig_wr_busy       : std_logic;
  signal sig_reset : std_logic;
  -- Interrupt signaling
  signal sig_cfg_interrupt_n             : std_logic;
  signal sig_cfg_interrupt_rdy_n         : std_logic;
  signal sig_cfg_interrupt_assert_n      : std_logic;
  signal sig_cfg_interrupt_di            : std_logic_vector(7 downto 0);
  signal sig_cfg_interrupt_mmenable      : std_logic_vector(2 downto 0);
  signal sig_cfg_interrupt_msienable     : std_logic;
  signal sig_cfg_command_int_en          : std_logic;
  
begin

  
  Inst_eg_sub_sys : entity eg_sub_sys 
    port map (

      --PLL --
      bat_serial        => bat,
      up                => up,
      down              => down,
      vco_16m           => sig_vco16m_bufg,
      
      --Timing --
      clkb_2mhz         => clkb_2mhz,
      clkb_8mhz         => clkb_8mhz,
      clkdata           => clkdata,
      clkd_1mhz         => clkd_1mhz,
      clkq_1mhz         => clkq_1mhz,
      clkt_1mhz         => clkt_1mhz, 
      cntr_in           => cntr_in,
      cntr_out          => cntr_out,
      se_event_out      => se_event_out,
      se_event_strobe   => se_event_strobe,
      t2ppms            => t2ppms,
      t4ppms            => t4ppms,
      t8ppms            => t8ppms,
      t16ppms           => t16ppms,
      t31ppms           => t31ppms,
      t62ppms           => t62ppms,
      t125khz           => t125khz,
      t250khz           => t250khz,
      t500khz           => t500khz,
      unused_input      => unused_input,
      x1sclk            => x1sclk,
      x1sec             => x1sec,
      xfs               => xfs,
      extint0           => extint0,
      ext_trig0         => ext_trig0,
      ext_trig1         => ext_trig1,
      msclk             => msclk,
      
      -- Waveform --	 
      wf_out            => wf_out,
      
      -- Event out --
      event_out         => event_out,
      event_strobe      => event_strobe,
      
      -- LEDS out --
      out_of_lock       => out_of_lock,
      running           => running,
      
      -- One Wire Serial No. --
      onewire_oe => sig_onewire_oe,    
      onewire_o  => sig_onewire_o,     
      onewire_i  => sig_onewire_i,        
      -- PCI Signals --
      clocks 				  => sig_clocks, 	  
      trn_reset_n        => sig_trn_reset_n,
      bclk               => sig_bclk,
      lint1              => sig_lint1,
      
      master_control      => sig_master_control,
      interrupt_control   => sig_interrupt_control, 
      clear_interrupts    => sig_clear_interrupts,    
      event_output_control => sig_event_output_control,
      waveform_control    => sig_waveform_control,
      master_status       => sig_master_status,   
      interrupt_status    => sig_interrupt_status,   
      event_output_status  => sig_event_output_status,
      waveform_status      => sig_waveform_status,   

      frame_byte => sig_frame_byte,        
      frame_byte_load =>  sig_frame_byte_load,    
      async_event_read  => sig_async_event_read, 

      async_event_write  => sig_async_event_write,
      async_event_write_load => sig_async_event_write_load,

      ls_sync_event => sig_ls_sync_event ,     
      ls_sync_event_load  => sig_ls_sync_event_load, 
      ms_sync_event => sig_ms_sync_event,     
      ms_sync_event_load => sig_ms_sync_event_load,
      
      rising_control => sig_rising_control,     
      clear_rising  =>  sig_clear_rising,    
      rising_status  =>  sig_rising_status,   

      falling_control  => sig_falling_control, 
      clear_falling    => sig_clear_falling, 
      falling_status   =>  sig_falling_status,

      ident_serial_out_address_inc => sig_ident_serial_out_address_inc,
      write_ident_fifo_data => sig_write_ident_fifo_data,
      write_ident_fifo_load => sig_write_ident_fifo_load,
      write_ident_fifo_reset => sig_write_ident_fifo_reset
      );


  Inst_eg_pci_interface : entity pci_interface 
    
    port map (
      
      -- EG PCI Signals --
      bclk   => sig_bclk,
      clocks => sig_clocks,  
      
      master_control    => sig_master_control,
      master_status => sig_master_status, 
      
      interrupt_control  => sig_interrupt_control, 
      interrupt_status =>   sig_interrupt_status,
      clear_interrupts   => sig_clear_interrupts,    
      
      rising_control => sig_rising_control,     
      clear_rising  =>  sig_clear_rising,    
      rising_status  => sig_rising_status,  
      
      falling_control  => sig_falling_control, 
      clear_falling    => sig_clear_falling, 
      falling_status   =>  sig_falling_status,
      
      event_output_control => sig_event_output_control,
      event_output_status => sig_event_output_status,
      
      waveform_control => sig_waveform_control,
      waveform_status => sig_waveform_status,
      
      frame_byte => sig_frame_byte,        
      frame_byte_load =>  sig_frame_byte_load,    

      async_event_read  => sig_async_event_read,
      
      async_event_write  => sig_async_event_write,
      async_event_write_load => sig_async_event_write_load,
      
      ls_sync_event => sig_ls_sync_event ,     
      ls_sync_event_load  => sig_ls_sync_event_load, 
      ms_sync_event => sig_ms_sync_event,     
      ms_sync_event_load => sig_ms_sync_event_load,

      busevent => busevent,	  
      lint1    => sig_lint1,
      
      ident_serial_out_address_inc => sig_ident_serial_out_address_inc,
      write_ident_fifo_data => sig_write_ident_fifo_data,
      write_ident_fifo_load => sig_write_ident_fifo_load,
      write_ident_fifo_reset => sig_write_ident_fifo_reset,

      
      -- Memory read/write control --
      rst_n  => sig_reset,
      wr_en_i => sig_wr_en,
      rd_addr_i => sig_rd_addr,
      rd_be_i => sig_rd_be,
      wr_addr_i => sig_wr_addr,
      wr_be_i => sig_wr_be,
      wr_data_i => sig_wr_data,
      wr_busy_o => sig_wr_busy,
      rd_data_o => sig_rd_data,
      rd_en_i => sig_rd_en,
      
      cfg_interrupt_n => sig_cfg_interrupt_n,
      cfg_interrupt_assert_n => sig_cfg_interrupt_assert_n,
      cfg_interrupt_di => sig_cfg_interrupt_di,
      cfg_interrupt_rdy_n => sig_cfg_interrupt_rdy_n,
      cfg_interrupt_msienable => sig_cfg_interrupt_msienable,
      cfg_command_int_en => sig_cfg_command_int_en
      );

  PCIE: entity xilinx_pcie_1_1_ep_s6
    generic map
    (
      FAST_TRAIN => FALSE                        
      )
    port map
    (  
      
      -- PCIe Signals --
      pci_exp_txp => pci_exp_txp,
      pci_exp_txn => pci_exp_txn,
      pci_exp_rxp => pci_exp_rxp,
      pci_exp_rxn => pci_exp_rxn,

      sys_clk_c   => sys_clk_c,
      sys_reset_n_c => sig_sys_reset_n_c,
      
      trn_lnk_up_n =>  sig_trn_lnk_up_n,
      trn_reset_n  =>  sig_trn_reset_n,
      
      -- Memory read/write control --
      bclk_o => sig_bclk,
      wr_en_o => sig_wr_en,
      rd_addr_o => sig_rd_addr,
      rd_be_o => sig_rd_be,
      wr_addr_o => sig_wr_addr,
      wr_be_o => sig_wr_be,
      wr_data_o => sig_wr_data,
      wr_busy_i => sig_wr_busy,
      rd_data_i => sig_rd_data,
      rd_en_o => sig_rd_en,
      reset_o => sig_reset,
      
      cfg_interrupt_n => sig_cfg_interrupt_n,
      cfg_interrupt_assert_n => sig_cfg_interrupt_assert_n,
      cfg_interrupt_di => sig_cfg_interrupt_di,
      cfg_interrupt_rdy_n => sig_cfg_interrupt_rdy_n,
      cfg_interrupt_do  => open,
--      cfg_interrupt_mmenable => sig_cfg_interrupt_mmenable,
      cfg_interrupt_msienable => sig_cfg_interrupt_msienable,
      cfg_command_int_en => sig_cfg_command_int_en
      
      );

  
  ---------------------------------------------------------
  -- Clock Input Buffer for differential system clock
  ---------------------------------------------------------
  refclk_ibuf : IBUFDS
    port map
    (
      O  => sys_clk_c,
      I  => sys_clk_p,
      IB => sys_clk_n
      );


  ---------------------------------------------------------
  -- Input buffer for system reset signal --
  ---------------------------------------------------------
  sys_reset_n_ibuf : IBUF
    port map
    (
      O  => sig_sys_reset_n_c,
      I  => sys_reset_n
      );

  
  -----------------------------------------------------------
  -- VCO Clock buffers --
  -----------------------------------------------------------
  vco16m_ibufg : IBUFG
    generic map (
      IBUF_LOW_PWR => TRUE, -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
      IOSTANDARD => "DEFAULT")
    port map (
      O => sig_vco16m_ibufg, -- Clock buffer output
      I => VCO_16M  -- Clock buffer input (connect directly to top-level port)
      );

  vco16m_bufio2 : BUFIO2
    generic map (
      DIVIDE => 1,           -- DIVCLK divider (1-8)
      DIVIDE_BYPASS => TRUE, -- Bypass the divider circuitry (TRUE/FALSE)
      I_INVERT => FALSE,     -- Invert clock (TRUE/FALSE)
      USE_DOUBLER => FALSE   -- Use doubler circuitry (TRUE/FALSE)
      )
    port map (
      DIVCLK => sig_vco16m_bufio2,             -- 1-bit Divided clock output
      IOCLK => open,                 -- 1-bit I/O output clock
      SERDESSTROBE => open,         -- 1-bit Output SERDES strobe (connect to ISERDES/OSERDES)
      I => sig_vco16m_ibufg         -- 1-bit Clock input (connect to IBUFG)
      );


  vco16m_bufg : BUFG
    port map (
      O => sig_vco16m_bufg,     -- Clock buffer output
      I => sig_vco16m_bufio2      -- Clock buffer input
      );

  
  ---------------------------------------------------------
  -- IO buffer for serial 1 wire interface --
  ---------------------------------------------------------
  serial_onewire_pullup: pullup port map (o => serial_onewire); 
  
  serial_onewire_iobuf : IOBUF
    generic map 
    (
      DRIVE => 8,
      IOSTANDARD => "LVCMOS33",
      SLEW => "SLOW"
      )
    port map 
    (
      I => sig_onewire_o,       -- Buffer input
      IO => serial_onewire,     -- Buffer inout port (connect directly to top-level port)
      O => sig_onewire_i,       -- Buffer output
      T => sig_onewire_oe       -- 3-state enable input, high=input, low=output 
      );
  
  ---------------------------------------------------------
  -- Output buffers for Timing IC bus direction control --
  ---------------------------------------------------------
  U13_obuf : OBUF
    port map
    (
      O => u13_dir,
      I => u13_dir_in
      );
  
  U14_obuf : OBUF
    port map
    (
      O => u14_dir,
      I => u14_dir_in
      );
  
  U15_obuf : OBUF
    port map
    (
      O => u15_dir,
      I => u15_dir_in
      );
  
  U16_obuf : OBUF
    port map
    (
      O => u16_dir,
      I => u16_dir_in
      );
  
  U17_obuf : OBUF
    port map
    (
      O => u17_dir,
      I => u17_dir_in
      );
  
  
  -----------------------------------------------------------------
  -- Concurrent Signal Assignments --
  -----------------------------------------------------------------

  pci_lnk_up_debug_led <= sig_trn_lnk_up_n;
  jtag_core_select <= '1';
  
  
end structure;



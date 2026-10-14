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
-- File Name: eg_registers.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Event Generator Registers
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
use IEEE.numeric_std.all;
use work.clocks_package.all;
use work.pci_package.all;
Library UNISIM;
use UNISIM.vcomponents.all;

entity eg_registers is
port(

      -- EG PCI interface Signals --
  bclk        : in std_logic;
  rst_n       : in  STD_LOGIC;
  
  be_i        : in std_logic_vector(3 downto 0);
  address     : in std_logic_vector(7 downto 0);
  
  wr_en_i     : in std_logic;
  rd_en_i     : in std_logic;
  
  wr_data_i_0 : in     std_logic_vector(7 downto 0);
  wr_data_i_1 : in    std_logic_vector(7 downto 0);
  wr_data_i_2 : in    std_logic_vector(7 downto 0);
  wr_data_i_3 : in    std_logic_vector(7 downto 0);

  rd_data_o_0 : out    std_logic_vector(7 downto 0);
  rd_data_o_1 : out    std_logic_vector(7 downto 0);
  rd_data_o_2 : out    std_logic_vector(7 downto 0);
  rd_data_o_3 : out    std_logic_vector(7 downto 0);

  clocks      : in std_logic_vector(17 downto 0);
  
  master_control      : out std_logic_vector(8 downto 0);
  master_status       : in std_logic_vector(11 downto 0);
  
  interrupt_control   : out std_logic_vector(14 downto 0);
  interrupt_status    : in std_logic_vector(13 downto 0);
  
  rising_control      : out std_logic_vector(31 downto 0);
  rising_status       : in std_logic_vector(31 downto 0);
  
  falling_control     : out std_logic_vector(31 downto 0);
  falling_status      : in std_logic_vector(31 downto 0);
  
  event_output_control: out std_logic_vector(12 downto 0);
  event_output_status : in std_logic_vector(1 downto 0);
  
  waveform_control    : out std_logic_vector(63 downto 0);
  waveform_status     : in std_logic_vector(9 downto 0);

  frame_byte          : in std_logic_vector(7 downto 0);
  frame_byte_load     : out std_logic;
  
  async_event_read    : in std_logic_vector(15 downto 0);

  async_event_write   : out std_logic_vector(15 downto 0);
  async_event_write_load: out std_logic;

  ls_sync_event       : out std_logic_vector(7 downto 0);
  ls_sync_event_load  : out std_logic;
  ms_sync_event       : out std_logic_vector(7 downto 0);
  ms_sync_event_load  : out std_logic;

  ident_serial_out_address_inc     : out std_logic;
  
  write_ident_fifo_data : out std_logic_vector(7 downto 0);
  write_ident_fifo_load  : out std_logic;
  write_ident_fifo_reset : out std_logic
  );	  
end eg_registers;

architecture Behavioral of eg_registers is

 signal clocks_local:        clocks_t;
 signal master_control_local:    master_control_t;
 signal master_status_local:     master_status_t;
 signal interrupt_control_local:   interrupt_control_t;
 signal interrupt_status_local:   interrupt_status_t;
 signal event_output_control_local: event_output_control_t;
 signal event_output_status_local:  event_output_status_t;
 signal waveform_control_local:   waveform_control_t;
 signal waveform_status_local:    waveform_status_t;
 signal rising_control_local:    supplementary_interrupts_t;
 signal rising_status_local:     supplementary_interrupts_t;
 signal falling_control_local:    supplementary_interrupts_t;
 signal falling_status_local:    supplementary_interrupts_t;
 
 signal sig_rd_data_o_0: std_logic_vector(7 downto 0);
 signal sig_rd_data_o_1: std_logic_vector(7 downto 0);
 signal sig_rd_data_o_2: std_logic_vector(7 downto 0);
 signal sig_rd_data_o_3: std_logic_vector(7 downto 0);
 
 signal sig_ls_sync_event: std_logic_vector(7 downto 0);
 signal sig_ms_sync_event: std_logic_vector(7 downto 0);
 
 signal sig_reset_ref_fifo_raw: std_logic;
 signal sig_write_ident_fifo_reset_raw: std_logic;
 
 signal sig_async_event_write_msb: std_logic_vector(7 downto 0);

 signal sig_ident_fifo_data: std_logic_vector(7 downto 0);

 -- ATNF MOD FOR EG: reset values for the interrupt enable registers --
 constant INTERRUPT_CONTROL_OFF   : std_logic_vector(14 downto 0) := (others => '0');
 constant SUPPLEMENTARY_CTRL_OFF  : std_logic_vector(31 downto 0) := (others => '0');


begin

	-----------------------------------------------------------------
	-- Components --
	-----------------------------------------------------------------

	Inst_clk_pulse_prom_rst: entity work.clk_pulse 
	generic map (target_address=>x"00")
	port map (bclk => bclk,
				 en_i => wr_en_i,
				 be_i => be_i(0),
				 data_i => wr_data_i_0(3),
				 address => address,
				 data_o => master_control_local.serial_prom_reset);
				 
	Inst_grab_frame_buffer: entity work.control_buffer
	generic map (target_address=>x"00", target_en_i=>'1')
	port map (in_clk=>bclk, 
				 en_i=> wr_en_i, 
				 addr_i=>address,
				 be_i=> be_i(0), 
				 in_data=> wr_data_i_0(3),
				 out_clk=>clocks_local.clkt_1mhz, 
				 out_data=>master_control_local.grab_frame);

	Inst2_purge_event_buffer: entity work.control_buffer
	generic map (target_address=>x"00", target_en_i=>'1')
	port map (in_clk=> bclk, 
				 en_i=> wr_en_i, 
				 addr_i=> address,
				 be_i=>be_i(0), 
				 in_data=>wr_data_i_0(4),
				 out_clk=>clocks_local.clkt_1mhz, 
				 out_data=>master_control_local.purge_event);

	Inst_async_event_write_load_buffer: entity work.delayed_control_buffer
	generic map (target_address=>x"08", target_en_i=>'1')
	port map (in_clk=> bclk, 
				 en_i=> wr_en_i, 
				 addr_i=> address,
				 be_i=>be_i(2), 
				 in_data=>'1',
				 out_clk=> clocks_local.clkt_1mhz, 
				 out_data=> async_event_write_load);

	Inst2_clk_pulse_ident_addr: entity work.clk_pulse 
	generic map (target_address=>x"04")
	port map (bclk => bclk,
				 en_i => rd_en_i,
				 be_i => be_i(2),
				 data_i => '1',
				 address => address,
				 data_o => ident_serial_out_address_inc);

	Inst_async_event_write: entity work.async_event_write 
	port map(bclk => bclk,
				be_i => be_i(3),
				address => address,
				wr_en_i => wr_en_i,
				wr_data_i_2 => wr_data_i_2,
				wr_data_i_3 => wr_data_i_3,
				async_event_write_msb => sig_async_event_write_msb,
				async_event_write => async_event_write);

	fd_inst_ref_fifo:  fd 
	port map(d => sig_reset_ref_fifo_raw, 
				q => master_control_local.reset_ref_fifo, 
				c => bclk);

	fd_inst_ident_fifo:  fd 
	port map(d => sig_write_ident_fifo_reset_raw,
				q => write_ident_fifo_reset, 
				c => bclk);


	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

	master_control    <= master_control_to_slv(master_control_local);
	master_status_local    <= slv_to_master_status(master_status);

	interrupt_control   <= interrupt_control_to_slv(interrupt_control_local);
	interrupt_status_local  <= slv_to_interrupt_status(interrupt_status);

	event_output_status_local <= slv_to_event_output_status(event_output_status);
	waveform_status_local   <= slv_to_waveform_status(waveform_status);

	rising_status_local    <= slv_to_supplementary_interrupts(rising_status);
	falling_status_local   <= slv_to_supplementary_interrupts(falling_status);

	event_output_control <= event_output_control_to_slv(event_output_control_local);
	waveform_control   <= waveform_control_to_slv(waveform_control_local);

	rising_control    <= supplementary_interrupts_to_slv(rising_control_local);
	falling_control    <= supplementary_interrupts_to_slv(falling_control_local);
	 
	clocks_local       <= slv_to_clocks(clocks);

	rd_data_o_0 <= sig_rd_data_o_0;
	rd_data_o_1 <= sig_rd_data_o_1;
	rd_data_o_2 <= sig_rd_data_o_2;
	rd_data_o_3 <= sig_rd_data_o_3;

	sig_ls_sync_event <= wr_data_i_2 when
                             wr_en_i='1' and address=x"04" and be_i(2)='1' else sig_ls_sync_event;
	ls_sync_event <= sig_ls_sync_event;

	sig_ms_sync_event <= wr_data_i_3 when
                             wr_en_i='1' and address=x"04" and be_i(3)='1' else sig_ms_sync_event;
	ms_sync_event <= sig_ms_sync_event;

	ls_sync_event_load <= '1' when wr_en_i='1' and address=x"04" and be_i(2)='1' else '0';
	ms_sync_event_load <= '1' when wr_en_i='1' and address=x"04" and be_i(3)='1' else '0';   

	frame_byte_load <= '1' when rd_en_i='1' and address=x"04" and be_i(2)='1' else '0';

	sig_ident_fifo_data <= wr_data_i_0 when
                               wr_en_i='1' and address=x"30" and be_i(0)='1' else sig_ident_fifo_data;
	write_ident_fifo_data <= sig_ident_fifo_data;

	write_ident_fifo_load <= '1' when
                                 wr_en_i='1' and address=x"30" and be_i(0)='1' else '0';

	sig_write_ident_fifo_reset_raw <= '1' when
                                          wr_en_i='1' and address=x"00" and be_i(0)='1' and
                                          wr_data_i_0(6)='1' else '0';
	sig_reset_ref_fifo_raw <= '1' when
                                  wr_en_i='1' and address=x"00" and be_i(0)='1' and
                                  wr_data_i_0(2)='1' else '0';
	 
------------------------------------------------------------------------------

-- EG register interface --

 process(bclk, rst_n)
  begin
  
  if rst_n='0' then
  
  sig_rd_data_o_0 <= x"00";
  sig_rd_data_o_1 <= x"00";
  sig_rd_data_o_2 <= x"00";
  sig_rd_data_o_3 <= x"00";

  -- ATNF MOD FOR EG --
  -- Disable every interrupt source on PCIe reset.  A warm reboot asserts
  -- PERST# but does not reload the FPGA, so enables left set by the last
  -- driver would otherwise survive and assert INTx as soon as the link comes
  -- up - before any driver is loaded to service it.  On a shared line Linux
  -- then disables the IRQ ("nobody cared") and the EG gets no interrupts at
  -- all once its driver loads.  Waveform and event output settings are left
  -- alone so outputs to external equipment do not change on a host reboot.
  interrupt_control_local <= slv_to_interrupt_control(INTERRUPT_CONTROL_OFF);
  rising_control_local    <= slv_to_supplementary_interrupts(SUPPLEMENTARY_CTRL_OFF);
  falling_control_local   <= slv_to_supplementary_interrupts(SUPPLEMENTARY_CTRL_OFF);
  -- END ATNF MOD --

  elsif rising_edge(bclk) then

  
   if address=x"00" then
    -- Master Control / Status register (Read / Write).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0)  <= master_control_local.dma_enable;
      sig_rd_data_o_0(1)  <= master_control_local.insert_4_wait_states;
      sig_rd_data_o_0(2)  <= master_status_local.pll;
      sig_rd_data_o_0(3)  <= master_status_local.frame_loaded;
      sig_rd_data_o_0(4)  <= master_status_local.late_event;
      sig_rd_data_o_0(5)  <= master_status_local.event_generator_running;
      sig_rd_data_o_0(6) <= master_control_local.ident_write;
      
     elsif wr_en_i='1' then
      master_control_local.dma_enable    <= wr_data_i_0(0);
      master_control_local.insert_4_wait_states  <= wr_data_i_0(1);
      master_control_local.ident_write <= wr_data_i_0(6);
      
    end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then 
      sig_rd_data_o_1(0) <= master_status_local.frame_fifo_empty;
      sig_rd_data_o_1(1) <= master_status_local.ls_ref_fifo_empty;
      sig_rd_data_o_1(2) <= master_status_local.ms_ref_fifo_empty;
      sig_rd_data_o_1(3) <= master_status_local.ls_ref_fifo_half_empty;
      sig_rd_data_o_1(4) <= master_status_local.ms_ref_fifo_half_empty;
      sig_rd_data_o_1(5) <= master_status_local.ls_ref_fifo_full;
      sig_rd_data_o_1(6) <= master_status_local.ms_ref_fifo_full;
      sig_rd_data_o_1(7) <= master_status_local.serial_number;
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Interrupt Control register (Read / Write).
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0)  <= interrupt_control_local.ref_fifo_empty;
      sig_rd_data_o_2(1)  <= interrupt_control_local.ref_fifo_half_empty;
      sig_rd_data_o_2(3)  <= interrupt_control_local.late_event;
      sig_rd_data_o_2(4)  <= interrupt_control_local.checksum_error;
      sig_rd_data_o_2(5)  <= interrupt_control_local.false_sync;
      sig_rd_data_o_2(6)  <= interrupt_control_local.missed_sync;
      sig_rd_data_o_2(7)  <= interrupt_control_local.frame_loaded;
     elsif wr_en_i='1' then
      interrupt_control_local.ref_fifo_empty   <= wr_data_i_2(0);
      interrupt_control_local.ref_fifo_half_empty  <= wr_data_i_2(1);
      interrupt_control_local.late_event    <= wr_data_i_2(3);
      interrupt_control_local.checksum_error   <= wr_data_i_2(4);
      interrupt_control_local.false_sync    <= wr_data_i_2(5);
      interrupt_control_local.missed_sync    <= wr_data_i_2(6);
      interrupt_control_local.frame_loaded    <= wr_data_i_2(7);
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0)  <= interrupt_control_local.dma_done;
      sig_rd_data_o_3(1)  <= interrupt_control_local.external_interrupt;
      sig_rd_data_o_3(2)  <= interrupt_control_local.internal_interrupt;
      sig_rd_data_o_3(3)  <= interrupt_control_local.pll_dropout;
      sig_rd_data_o_3(4)  <= interrupt_control_local.one_second;
      sig_rd_data_o_3(5)  <= interrupt_control_local.finished;
      sig_rd_data_o_3(6)  <= interrupt_control_local.supplementary_interrupt;
      sig_rd_data_o_3(7)  <= interrupt_control_local.enable_interrupt;
     elsif wr_en_i='1' then
      interrupt_control_local.dma_done             <= wr_data_i_3(0);
      interrupt_control_local.external_interrupt   <= wr_data_i_3(1);
      interrupt_control_local.internal_interrupt   <= wr_data_i_3(2);
      interrupt_control_local.pll_dropout          <= wr_data_i_3(3);
      interrupt_control_local.one_second           <= wr_data_i_3(4);
      interrupt_control_local.finished             <= wr_data_i_3(5);
      interrupt_control_local.supplementary_interrupt <= wr_data_i_3(6);
      interrupt_control_local.enable_interrupt     <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"04" then
    -- Interrupt Status (Read).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= interrupt_status_local.ref_fifo_empty;
      sig_rd_data_o_0(1) <= interrupt_status_local.ref_fifo_half_empty;
      sig_rd_data_o_0(2) <= '0';
      sig_rd_data_o_0(3) <= interrupt_status_local.late_event;
      sig_rd_data_o_0(4) <= interrupt_status_local.checksum_error;
      sig_rd_data_o_0(5) <= interrupt_status_local.false_sync;
      sig_rd_data_o_0(6) <= interrupt_status_local.missed_sync;
      sig_rd_data_o_0(7) <= interrupt_status_local.frame_loaded;
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= interrupt_status_local.dma_done;
      sig_rd_data_o_1(1) <= interrupt_status_local.external_interrupt;
      sig_rd_data_o_1(2) <= interrupt_status_local.internal_interrupt;
      sig_rd_data_o_1(3) <= interrupt_status_local.pll_dropout;
      sig_rd_data_o_1(4) <= interrupt_status_local.one_second;
      sig_rd_data_o_1(5) <= interrupt_status_local.finished;
      sig_rd_data_o_1(6) <= interrupt_status_local.supplementary_interrupt;
      sig_rd_data_o_1(7) <= '0';
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reference FIFO (Write), Frame FIFO (Read).
    if be_i(2) = '1' then
     if rd_en_i='1' then
      sig_rd_data_o_2 <= frame_byte;
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"08" then
    -- Event Output Controller control / status register (Read / Write).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= event_output_control_local.waveform_generator_event_line_select(0);
      sig_rd_data_o_0(1) <= event_output_control_local.waveform_generator_event_line_select(1);
      sig_rd_data_o_0(2) <= event_output_control_local.waveform_generator_event_line_select(2);
      sig_rd_data_o_0(3) <= event_output_control_local.waveform_generator_event_line_select(3);
      sig_rd_data_o_0(4) <= event_output_control_local.waveform_generator_event_line_enable;
      sig_rd_data_o_0(5) <= event_output_status_local.waveform_generator_event_line;
      sig_rd_data_o_0(6) <= event_output_control_local.expert_mode;
      sig_rd_data_o_0(7) <= event_output_control_local.free_run_event_strobe;
     elsif wr_en_i='1' then
      event_output_control_local.waveform_generator_event_line_select(0) <= wr_data_i_0(0);
      event_output_control_local.waveform_generator_event_line_select(1) <= wr_data_i_0(1);
      event_output_control_local.waveform_generator_event_line_select(2) <= wr_data_i_0(2);
      event_output_control_local.waveform_generator_event_line_select(3) <= wr_data_i_0(3);
      event_output_control_local.waveform_generator_event_line_enable  <=   wr_data_i_0(4);
      event_output_control_local.expert_mode <= wr_data_i_0(6);
      event_output_control_local.free_run_event_strobe <= wr_data_i_0(7);
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= event_output_control_local.timed_interrupt_event_line_select(0);
      sig_rd_data_o_1(1) <= event_output_control_local.timed_interrupt_event_line_select(1);
      sig_rd_data_o_1(2) <= event_output_control_local.timed_interrupt_event_line_select(2);
      sig_rd_data_o_1(3) <= event_output_control_local.timed_interrupt_event_line_select(3);
      sig_rd_data_o_1(4) <= event_output_control_local.timed_interrupt_event_line_enable;
      sig_rd_data_o_1(5) <= event_output_control_local.timed_interrupt_output_enable;
      sig_rd_data_o_1(6) <= event_output_status_local.timed_interrupt_event_line;
     
     elsif wr_en_i='1' then
      event_output_control_local.timed_interrupt_event_line_select(0) <= wr_data_i_1(0);
      event_output_control_local.timed_interrupt_event_line_select(1) <= wr_data_i_1(1);
      event_output_control_local.timed_interrupt_event_line_select(2) <= wr_data_i_1(2);
      event_output_control_local.timed_interrupt_event_line_select(3) <= wr_data_i_1(3);
      event_output_control_local.timed_interrupt_event_line_enable  <= wr_data_i_1(4);
      event_output_control_local.timed_interrupt_output_enable   <= wr_data_i_1(5);
     end if;
    end if;
    -- Event Output Controller current event (Read) and asynchronous event (Write).
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0) <= async_event_read(0);
      sig_rd_data_o_2(1) <= async_event_read(1);
      sig_rd_data_o_2(2) <= async_event_read(2);
      sig_rd_data_o_2(3) <= async_event_read(3);
      sig_rd_data_o_2(4) <= async_event_read(4);
      sig_rd_data_o_2(5) <= async_event_read(5);
      sig_rd_data_o_2(6) <= async_event_read(6);
      sig_rd_data_o_2(7) <= async_event_read(7);
     elsif wr_en_i='1' then
  
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0) <= async_event_read(8);
      sig_rd_data_o_3(1) <= async_event_read(9);
      sig_rd_data_o_3(2) <= async_event_read(10);
      sig_rd_data_o_3(3) <= async_event_read(11);
      sig_rd_data_o_3(4) <= async_event_read(12);
      sig_rd_data_o_3(5) <= async_event_read(13);
      sig_rd_data_o_3(6) <= async_event_read(14);
      sig_rd_data_o_3(7) <= async_event_read(15);
     elsif wr_en_i='1' then
      sig_async_event_write_msb(0) <= wr_data_i_3(0);
      sig_async_event_write_msb(1) <= wr_data_i_3(1);
      sig_async_event_write_msb(2) <= wr_data_i_3(2);
      sig_async_event_write_msb(3) <= wr_data_i_3(3);
      sig_async_event_write_msb(4) <= wr_data_i_3(4);
      sig_async_event_write_msb(5) <= wr_data_i_3(5);
      sig_async_event_write_msb(6) <= wr_data_i_3(6);
      sig_async_event_write_msb(7) <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"0C" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"10" then
    -- Waveform Generator status register (Read / Write).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0)  <= waveform_status_local.waveform_output_0_state;
      sig_rd_data_o_0(1)  <= waveform_status_local.waveform_output_1_state;
      sig_rd_data_o_0(2)  <= waveform_status_local.waveform_output_2_state;
      sig_rd_data_o_0(3)  <= waveform_status_local.waveform_output_3_state;
      sig_rd_data_o_0(4)  <= waveform_status_local.waveform_output_0_3_enabled;
    
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0)  <= waveform_status_local.waveform_output_4_state;
      sig_rd_data_o_1(1)  <= waveform_status_local.waveform_output_5_state;
      sig_rd_data_o_1(2)  <= waveform_status_local.waveform_output_6_state;
      sig_rd_data_o_1(3)  <= waveform_status_local.waveform_output_7_state;
      sig_rd_data_o_1(4)  <= waveform_status_local.waveform_output_4_7_enabled;
  
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Waveform Generator LS Byte Prescale count (Write).
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0) <= waveform_control_local.prescale_counter_0_3(0);
      sig_rd_data_o_2(1) <= waveform_control_local.prescale_counter_0_3(1);
      sig_rd_data_o_2(2) <= waveform_control_local.prescale_counter_0_3(2);
      sig_rd_data_o_2(3) <= waveform_control_local.prescale_counter_0_3(3);
      sig_rd_data_o_2(4) <= waveform_control_local.prescale_counter_0_3(4);
      sig_rd_data_o_2(5) <= waveform_control_local.prescale_counter_0_3(5);
      sig_rd_data_o_2(6) <= waveform_control_local.prescale_counter_0_3(6);
      sig_rd_data_o_2(7) <= waveform_control_local.prescale_counter_0_3(7);
     elsif wr_en_i='1' then
      waveform_control_local.prescale_counter_0_3(0) <= wr_data_i_2(0);
      waveform_control_local.prescale_counter_0_3(1) <= wr_data_i_2(1);
      waveform_control_local.prescale_counter_0_3(2) <= wr_data_i_2(2);
      waveform_control_local.prescale_counter_0_3(3) <= wr_data_i_2(3);
      waveform_control_local.prescale_counter_0_3(4) <= wr_data_i_2(4);
      waveform_control_local.prescale_counter_0_3(5) <= wr_data_i_2(5);
      waveform_control_local.prescale_counter_0_3(6) <= wr_data_i_2(6);
      waveform_control_local.prescale_counter_0_3(7) <= wr_data_i_2(7);
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0) <= waveform_control_local.prescale_counter_4_7(0);
      sig_rd_data_o_3(1) <= waveform_control_local.prescale_counter_4_7(1);
      sig_rd_data_o_3(2) <= waveform_control_local.prescale_counter_4_7(2);
      sig_rd_data_o_3(3) <= waveform_control_local.prescale_counter_4_7(3);
      sig_rd_data_o_3(4) <= waveform_control_local.prescale_counter_4_7(4);
      sig_rd_data_o_3(5) <= waveform_control_local.prescale_counter_4_7(5);
      sig_rd_data_o_3(6) <= waveform_control_local.prescale_counter_4_7(6);
      sig_rd_data_o_3(7) <= waveform_control_local.prescale_counter_4_7(7);
     elsif wr_en_i='1' then
      waveform_control_local.prescale_counter_4_7(0) <= wr_data_i_3(0);
      waveform_control_local.prescale_counter_4_7(1) <= wr_data_i_3(1);
      waveform_control_local.prescale_counter_4_7(2) <= wr_data_i_3(2);
      waveform_control_local.prescale_counter_4_7(3) <= wr_data_i_3(3);
      waveform_control_local.prescale_counter_4_7(4) <= wr_data_i_3(4);
      waveform_control_local.prescale_counter_4_7(5) <= wr_data_i_3(5);
      waveform_control_local.prescale_counter_4_7(6) <= wr_data_i_3(6);
      waveform_control_local.prescale_counter_4_7(7) <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"14" then
    -- Waveform Generator MS Byte Prescale count (Write).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= waveform_control_local.prescale_counter_0_3(8);
      sig_rd_data_o_0(1) <= waveform_control_local.prescale_counter_0_3(9);
      sig_rd_data_o_0(2) <= waveform_control_local.prescale_counter_0_3(10);
      sig_rd_data_o_0(3) <= waveform_control_local.prescale_counter_0_3(11);
      sig_rd_data_o_0(4) <= waveform_control_local.prescale_counter_0_3(12);
      sig_rd_data_o_0(5) <= waveform_control_local.prescale_counter_0_3(13);
      sig_rd_data_o_0(6) <= waveform_control_local.prescale_counter_0_3(14);
      sig_rd_data_o_0(7) <= waveform_control_local.prescale_counter_0_3(15);
     elsif wr_en_i='1' then
      waveform_control_local.prescale_counter_0_3(8) <= wr_data_i_0(0);
      waveform_control_local.prescale_counter_0_3(9) <= wr_data_i_0(1);
      waveform_control_local.prescale_counter_0_3(10) <= wr_data_i_0(2);
      waveform_control_local.prescale_counter_0_3(11) <= wr_data_i_0(3);
      waveform_control_local.prescale_counter_0_3(12) <= wr_data_i_0(4);
      waveform_control_local.prescale_counter_0_3(13) <= wr_data_i_0(5);
      waveform_control_local.prescale_counter_0_3(14) <= wr_data_i_0(6);
      waveform_control_local.prescale_counter_0_3(15) <= wr_data_i_0(7);
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= waveform_control_local.prescale_counter_4_7(8);
      sig_rd_data_o_1(1) <= waveform_control_local.prescale_counter_4_7(9);
      sig_rd_data_o_1(2) <= waveform_control_local.prescale_counter_4_7(10);
      sig_rd_data_o_1(3) <= waveform_control_local.prescale_counter_4_7(11);
      sig_rd_data_o_1(4) <= waveform_control_local.prescale_counter_4_7(12);
      sig_rd_data_o_1(5) <= waveform_control_local.prescale_counter_4_7(13);
      sig_rd_data_o_1(6) <= waveform_control_local.prescale_counter_4_7(14);
      sig_rd_data_o_1(7) <= waveform_control_local.prescale_counter_4_7(15);
     elsif wr_en_i='1' then
      waveform_control_local.prescale_counter_4_7(8) <= wr_data_i_1(0);
      waveform_control_local.prescale_counter_4_7(9) <= wr_data_i_1(1);
      waveform_control_local.prescale_counter_4_7(10) <= wr_data_i_1(2);
      waveform_control_local.prescale_counter_4_7(11) <= wr_data_i_1(3);
      waveform_control_local.prescale_counter_4_7(12) <= wr_data_i_1(4);
      waveform_control_local.prescale_counter_4_7(13) <= wr_data_i_1(5);
      waveform_control_local.prescale_counter_4_7(14) <= wr_data_i_1(6);
      waveform_control_local.prescale_counter_4_7(15) <= wr_data_i_1(7);
     end if;
    end if;
    -- Waveform Generator outputs 0 - 3 source select (Read / Write).
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0) <= waveform_control_local.waveform_selection_0(0);
      sig_rd_data_o_2(1) <= waveform_control_local.waveform_selection_0(1);
      sig_rd_data_o_2(2) <= waveform_control_local.waveform_selection_0(2);
      sig_rd_data_o_2(3) <= waveform_control_local.waveform_selection_0(3);
      sig_rd_data_o_2(4) <= waveform_control_local.waveform_selection_1(0);
      sig_rd_data_o_2(5) <= waveform_control_local.waveform_selection_1(1);
      sig_rd_data_o_2(6) <= waveform_control_local.waveform_selection_1(2);
      sig_rd_data_o_2(7) <= waveform_control_local.waveform_selection_1(3);
     elsif wr_en_i='1' then
      waveform_control_local.waveform_selection_0(0) <= wr_data_i_2(0);
      waveform_control_local.waveform_selection_0(1) <= wr_data_i_2(1);
      waveform_control_local.waveform_selection_0(2) <= wr_data_i_2(2);
      waveform_control_local.waveform_selection_0(3) <= wr_data_i_2(3);
      waveform_control_local.waveform_selection_1(0) <= wr_data_i_2(4);
      waveform_control_local.waveform_selection_1(1) <= wr_data_i_2(5);
      waveform_control_local.waveform_selection_1(2) <= wr_data_i_2(6);
      waveform_control_local.waveform_selection_1(3) <= wr_data_i_2(7);
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0) <= waveform_control_local.waveform_selection_4(0);
      sig_rd_data_o_3(1) <= waveform_control_local.waveform_selection_4(1);
      sig_rd_data_o_3(2) <= waveform_control_local.waveform_selection_4(2);
      sig_rd_data_o_3(3) <= waveform_control_local.waveform_selection_4(3);
      sig_rd_data_o_3(4) <= waveform_control_local.waveform_selection_5(0);
      sig_rd_data_o_3(5) <= waveform_control_local.waveform_selection_5(1);
      sig_rd_data_o_3(6) <= waveform_control_local.waveform_selection_5(2);
      sig_rd_data_o_3(7) <= waveform_control_local.waveform_selection_5(3);
     elsif wr_en_i='1' then
      waveform_control_local.waveform_selection_4(0) <= wr_data_i_3(0);
      waveform_control_local.waveform_selection_4(1) <= wr_data_i_3(1);
      waveform_control_local.waveform_selection_4(2) <= wr_data_i_3(2);
      waveform_control_local.waveform_selection_4(3) <= wr_data_i_3(3);
      waveform_control_local.waveform_selection_5(0) <= wr_data_i_3(4);
      waveform_control_local.waveform_selection_5(1) <= wr_data_i_3(5);
      waveform_control_local.waveform_selection_5(2) <= wr_data_i_3(6);
      waveform_control_local.waveform_selection_5(3) <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"18" then
    -- Waveform Generator outputs 4 - 7 source select (Read / Write).
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= waveform_control_local.waveform_selection_2(0);
      sig_rd_data_o_0(1) <= waveform_control_local.waveform_selection_2(1);
      sig_rd_data_o_0(2) <= waveform_control_local.waveform_selection_2(2);
      sig_rd_data_o_0(3) <= waveform_control_local.waveform_selection_2(3);
      sig_rd_data_o_0(4) <= waveform_control_local.waveform_selection_3(0);
      sig_rd_data_o_0(5) <= waveform_control_local.waveform_selection_3(1);
      sig_rd_data_o_0(6) <= waveform_control_local.waveform_selection_3(2);
      sig_rd_data_o_0(7) <= waveform_control_local.waveform_selection_3(3);
     elsif wr_en_i='1' then
      waveform_control_local.waveform_selection_2(0) <= wr_data_i_0(0);
      waveform_control_local.waveform_selection_2(1) <= wr_data_i_0(1);
      waveform_control_local.waveform_selection_2(2) <= wr_data_i_0(2);
      waveform_control_local.waveform_selection_2(3) <= wr_data_i_0(3);
      waveform_control_local.waveform_selection_3(0) <= wr_data_i_0(4);
      waveform_control_local.waveform_selection_3(1) <= wr_data_i_0(5);
      waveform_control_local.waveform_selection_3(2) <= wr_data_i_0(6);
      waveform_control_local.waveform_selection_3(3) <= wr_data_i_0(7);
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= waveform_control_local.waveform_selection_6(0);
      sig_rd_data_o_1(1) <= waveform_control_local.waveform_selection_6(1);
      sig_rd_data_o_1(2) <= waveform_control_local.waveform_selection_6(2);
      sig_rd_data_o_1(3) <= waveform_control_local.waveform_selection_6(3);
      sig_rd_data_o_1(4) <= waveform_control_local.waveform_selection_7(0);
      sig_rd_data_o_1(5) <= waveform_control_local.waveform_selection_7(1);
      sig_rd_data_o_1(6) <= waveform_control_local.waveform_selection_7(2);
      sig_rd_data_o_1(7) <= waveform_control_local.waveform_selection_7(3);
     elsif wr_en_i='1' then
      waveform_control_local.waveform_selection_6(0) <= wr_data_i_1(0);
      waveform_control_local.waveform_selection_6(1) <= wr_data_i_1(1);
      waveform_control_local.waveform_selection_6(2) <= wr_data_i_1(2);
      waveform_control_local.waveform_selection_6(3) <= wr_data_i_1(3);
      waveform_control_local.waveform_selection_7(0) <= wr_data_i_1(4);
      waveform_control_local.waveform_selection_7(1) <= wr_data_i_1(5);
      waveform_control_local.waveform_selection_7(2) <= wr_data_i_1(6);
      waveform_control_local.waveform_selection_7(3) <= wr_data_i_1(7);
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"1C" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"20" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0)  <= rising_control_local.event(0);
      sig_rd_data_o_0(1)  <= rising_control_local.event(1);
      sig_rd_data_o_0(2)  <= rising_control_local.event(2);
      sig_rd_data_o_0(3)  <= rising_control_local.event(3);
      sig_rd_data_o_0(4)  <= rising_control_local.event(4);
      sig_rd_data_o_0(5)  <= rising_control_local.event(5);
      sig_rd_data_o_0(6)  <= rising_control_local.event(6);
      sig_rd_data_o_0(7)  <= rising_control_local.event(7);
     elsif wr_en_i='1' then
      rising_control_local.event(0) <= wr_data_i_0(0);
      rising_control_local.event(1) <= wr_data_i_0(1);
      rising_control_local.event(2) <= wr_data_i_0(2);
      rising_control_local.event(3) <= wr_data_i_0(3);
      rising_control_local.event(4) <= wr_data_i_0(4);
      rising_control_local.event(5) <= wr_data_i_0(5);
      rising_control_local.event(6) <= wr_data_i_0(6);
      rising_control_local.event(7) <= wr_data_i_0(7);
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0)  <= rising_control_local.event(8);
      sig_rd_data_o_1(1)  <= rising_control_local.event(9);
      sig_rd_data_o_1(2)  <= rising_control_local.event(10);
      sig_rd_data_o_1(3)  <= rising_control_local.event(11);
      sig_rd_data_o_1(4)  <= rising_control_local.event(12);
      sig_rd_data_o_1(5)  <= rising_control_local.event(13);
      sig_rd_data_o_1(6)  <= rising_control_local.event(14);
      sig_rd_data_o_1(7)  <= rising_control_local.event(15);
     elsif wr_en_i='1' then
      rising_control_local.event(8)  <= wr_data_i_1(0);
      rising_control_local.event(9)  <= wr_data_i_1(1);
      rising_control_local.event(10) <= wr_data_i_1(2);
      rising_control_local.event(11) <= wr_data_i_1(3);
      rising_control_local.event(12) <= wr_data_i_1(4);
      rising_control_local.event(13) <= wr_data_i_1(5);
      rising_control_local.event(14) <= wr_data_i_1(6);
      rising_control_local.event(15) <= wr_data_i_1(7);
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0)  <= rising_control_local.waveforms(0);
      sig_rd_data_o_2(1)  <= rising_control_local.waveforms(1);
      sig_rd_data_o_2(2)  <= rising_control_local.waveforms(2);
      sig_rd_data_o_2(3)  <= rising_control_local.waveforms(3);
      sig_rd_data_o_2(4)  <= rising_control_local.waveforms(4);
      sig_rd_data_o_2(5)  <= rising_control_local.waveforms(5);
      sig_rd_data_o_2(6)  <= rising_control_local.waveforms(6);
      sig_rd_data_o_2(7)  <= rising_control_local.waveforms(7);
     elsif wr_en_i='1' then
      rising_control_local.waveforms(0) <= wr_data_i_2(0);
      rising_control_local.waveforms(1) <= wr_data_i_2(1);
      rising_control_local.waveforms(2) <= wr_data_i_2(2);
      rising_control_local.waveforms(3) <= wr_data_i_2(3);
      rising_control_local.waveforms(4) <= wr_data_i_2(4);
      rising_control_local.waveforms(5) <= wr_data_i_2(5);
      rising_control_local.waveforms(6) <= wr_data_i_2(6);
      rising_control_local.waveforms(7) <= wr_data_i_2(7);
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0)  <= rising_control_local.t2ppms;
      sig_rd_data_o_3(1)  <= rising_control_local.t4ppms;
      sig_rd_data_o_3(2)  <= rising_control_local.t8ppms;
      sig_rd_data_o_3(3)  <= rising_control_local.t16ppms;
      sig_rd_data_o_3(4)  <= rising_control_local.unused0;
      sig_rd_data_o_3(5)  <= rising_control_local.unused1;
      sig_rd_data_o_3(6)  <= rising_control_local.unused2;
      sig_rd_data_o_3(7)  <= rising_control_local.strobe;
     elsif wr_en_i='1' then
      rising_control_local.t2ppms  <= wr_data_i_3(0);
      rising_control_local.t4ppms  <= wr_data_i_3(1);
      rising_control_local.t8ppms  <= wr_data_i_3(2);
      rising_control_local.t16ppms <= wr_data_i_3(3);
      rising_control_local.unused0 <= wr_data_i_3(4);
      rising_control_local.unused1 <= wr_data_i_3(5);
      rising_control_local.unused2 <= wr_data_i_3(6);
      rising_control_local.strobe  <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"24" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= rising_status_local.event(0);
      sig_rd_data_o_0(1) <= rising_status_local.event(1);
      sig_rd_data_o_0(2) <= rising_status_local.event(2);
      sig_rd_data_o_0(3) <= rising_status_local.event(3);
      sig_rd_data_o_0(4) <= rising_status_local.event(4);
      sig_rd_data_o_0(5) <= rising_status_local.event(5);
      sig_rd_data_o_0(6) <= rising_status_local.event(6);
      sig_rd_data_o_0(7) <= rising_status_local.event(7);
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= rising_status_local.event(8);
      sig_rd_data_o_1(1) <= rising_status_local.event(9);
      sig_rd_data_o_1(2) <= rising_status_local.event(10);
      sig_rd_data_o_1(3) <= rising_status_local.event(11);
      sig_rd_data_o_1(4) <= rising_status_local.event(12);
      sig_rd_data_o_1(5) <= rising_status_local.event(13);
      sig_rd_data_o_1(6) <= rising_status_local.event(14);
      sig_rd_data_o_1(7) <= rising_status_local.event(15);
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0) <= rising_status_local.waveforms(0);
      sig_rd_data_o_2(1) <= rising_status_local.waveforms(1);
      sig_rd_data_o_2(2) <= rising_status_local.waveforms(2);
      sig_rd_data_o_2(3) <= rising_status_local.waveforms(3);
      sig_rd_data_o_2(4) <= rising_status_local.waveforms(4);
      sig_rd_data_o_2(5) <= rising_status_local.waveforms(5);
      sig_rd_data_o_2(6) <= rising_status_local.waveforms(6);
      sig_rd_data_o_2(7) <= rising_status_local.waveforms(7);
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0) <= rising_status_local.t2ppms;
      sig_rd_data_o_3(1) <= rising_status_local.t4ppms;
      sig_rd_data_o_3(2) <= rising_status_local.t8ppms;
      sig_rd_data_o_3(3) <= rising_status_local.t16ppms;
      sig_rd_data_o_3(4) <= rising_status_local.unused0;
      sig_rd_data_o_3(5) <= rising_status_local.unused1;
      sig_rd_data_o_3(6) <= rising_status_local.unused2;
      sig_rd_data_o_3(7) <= rising_status_local.strobe;
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"28" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0)  <= falling_control_local.event(0);
      sig_rd_data_o_0(1)  <= falling_control_local.event(1);
      sig_rd_data_o_0(2)  <= falling_control_local.event(2);
      sig_rd_data_o_0(3)  <= falling_control_local.event(3);
      sig_rd_data_o_0(4)  <= falling_control_local.event(4);
      sig_rd_data_o_0(5)  <= falling_control_local.event(5);
      sig_rd_data_o_0(6)  <= falling_control_local.event(6);
      sig_rd_data_o_0(7)  <= falling_control_local.event(7);
     elsif wr_en_i='1' then
      falling_control_local.event(0) <= wr_data_i_0(0);
      falling_control_local.event(1) <= wr_data_i_0(1);
      falling_control_local.event(2) <= wr_data_i_0(2);
      falling_control_local.event(3) <= wr_data_i_0(3);
      falling_control_local.event(4) <= wr_data_i_0(4);
      falling_control_local.event(5) <= wr_data_i_0(5);
      falling_control_local.event(6) <= wr_data_i_0(6);
      falling_control_local.event(7) <= wr_data_i_0(7);
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0)  <= falling_control_local.event(8);
      sig_rd_data_o_1(1)  <= falling_control_local.event(9);
      sig_rd_data_o_1(2)  <= falling_control_local.event(10);
      sig_rd_data_o_1(3)  <= falling_control_local.event(11);
      sig_rd_data_o_1(4)  <= falling_control_local.event(12);
      sig_rd_data_o_1(5)  <= falling_control_local.event(13);
      sig_rd_data_o_1(6)  <= falling_control_local.event(14);
      sig_rd_data_o_1(7)  <= falling_control_local.event(15);
     elsif wr_en_i='1' then
      falling_control_local.event(8)  <= wr_data_i_1(0);
      falling_control_local.event(9)  <= wr_data_i_1(1);
      falling_control_local.event(10) <= wr_data_i_1(2);
      falling_control_local.event(11) <= wr_data_i_1(3);
      falling_control_local.event(12) <= wr_data_i_1(4);
      falling_control_local.event(13) <= wr_data_i_1(5);
      falling_control_local.event(14) <= wr_data_i_1(6);
      falling_control_local.event(15) <= wr_data_i_1(7);
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0)  <= falling_control_local.waveforms(0);
      sig_rd_data_o_2(1)  <= falling_control_local.waveforms(1);
      sig_rd_data_o_2(2)  <= falling_control_local.waveforms(2);
      sig_rd_data_o_2(3)  <= falling_control_local.waveforms(3);
      sig_rd_data_o_2(4)  <= falling_control_local.waveforms(4);
      sig_rd_data_o_2(5)  <= falling_control_local.waveforms(5);
      sig_rd_data_o_2(6)  <= falling_control_local.waveforms(6);
      sig_rd_data_o_2(7)  <= falling_control_local.waveforms(7);
     elsif wr_en_i='1' then
      falling_control_local.waveforms(0) <= wr_data_i_2(0);
      falling_control_local.waveforms(1) <= wr_data_i_2(1);
      falling_control_local.waveforms(2) <= wr_data_i_2(2);
      falling_control_local.waveforms(3) <= wr_data_i_2(3);
      falling_control_local.waveforms(4) <= wr_data_i_2(4);
      falling_control_local.waveforms(5) <= wr_data_i_2(5);
      falling_control_local.waveforms(6) <= wr_data_i_2(6);
      falling_control_local.waveforms(7) <= wr_data_i_2(7);
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0)  <= falling_control_local.t2ppms;
      sig_rd_data_o_3(1)  <= falling_control_local.t4ppms;
      sig_rd_data_o_3(2)  <= falling_control_local.t8ppms;
      sig_rd_data_o_3(3)  <= falling_control_local.t16ppms;
      sig_rd_data_o_3(4)  <= falling_control_local.unused0;
      sig_rd_data_o_3(5)  <= falling_control_local.unused1;
      sig_rd_data_o_3(6)  <= falling_control_local.unused2;
      sig_rd_data_o_3(7)  <= falling_control_local.strobe;
     elsif wr_en_i='1' then
      falling_control_local.t2ppms  <= wr_data_i_3(0);
      falling_control_local.t4ppms  <= wr_data_i_3(1);
      falling_control_local.t8ppms  <= wr_data_i_3(2);
      falling_control_local.t16ppms  <= wr_data_i_3(3);
      falling_control_local.unused0  <= wr_data_i_3(4);
      falling_control_local.unused1  <= wr_data_i_3(5);
      falling_control_local.unused2  <= wr_data_i_3(6);
      falling_control_local.strobe  <= wr_data_i_3(7);
     end if;
    end if;

   elsif address=x"2C" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_0(0) <= falling_status_local.event(0);
      sig_rd_data_o_0(1) <= falling_status_local.event(1);
      sig_rd_data_o_0(2) <= falling_status_local.event(2);
      sig_rd_data_o_0(3) <= falling_status_local.event(3);
      sig_rd_data_o_0(4) <= falling_status_local.event(4);
      sig_rd_data_o_0(5) <= falling_status_local.event(5);
      sig_rd_data_o_0(6) <= falling_status_local.event(6);
      sig_rd_data_o_0(7) <= falling_status_local.event(7);
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_1(0) <= falling_status_local.event(8);
      sig_rd_data_o_1(1) <= falling_status_local.event(9);
      sig_rd_data_o_1(2) <= falling_status_local.event(10);
      sig_rd_data_o_1(3) <= falling_status_local.event(11);
      sig_rd_data_o_1(4) <= falling_status_local.event(12);
      sig_rd_data_o_1(5) <= falling_status_local.event(13);
      sig_rd_data_o_1(6) <= falling_status_local.event(14);
      sig_rd_data_o_1(7) <= falling_status_local.event(15);
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_2(0) <= falling_status_local.waveforms(0);
      sig_rd_data_o_2(1) <= falling_status_local.waveforms(1);
      sig_rd_data_o_2(2) <= falling_status_local.waveforms(2);
      sig_rd_data_o_2(3) <= falling_status_local.waveforms(3);
      sig_rd_data_o_2(4) <= falling_status_local.waveforms(4);
      sig_rd_data_o_2(5) <= falling_status_local.waveforms(5);
      sig_rd_data_o_2(6) <= falling_status_local.waveforms(6);
      sig_rd_data_o_2(7) <= falling_status_local.waveforms(7);
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
      sig_rd_data_o_3(0) <= falling_status_local.t2ppms;
      sig_rd_data_o_3(1) <= falling_status_local.t4ppms;
      sig_rd_data_o_3(2) <= falling_status_local.t8ppms;
      sig_rd_data_o_3(3) <= falling_status_local.t16ppms;
      sig_rd_data_o_3(4) <= falling_status_local.unused0;
      sig_rd_data_o_3(5) <= falling_status_local.unused1;
      sig_rd_data_o_3(6) <= falling_status_local.unused2;
      sig_rd_data_o_3(7) <= falling_status_local.strobe;
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"30" then
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"34" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"38" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   elsif address=x"3C" then
    -- Reserved.
    if be_i(0)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(1)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    -- Reserved.
    if be_i(2)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;
    if be_i(3)='1' then
     if rd_en_i='1' then
     elsif wr_en_i='1' then
     end if;
    end if;

   end if;

  end if;
 end process;


end Behavioral;


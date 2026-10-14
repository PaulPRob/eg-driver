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
-- File Name: pci_interface.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: PCIe Top Level
--
-- Description: The top level block of the PCIe interface responsible for read and
-- write transactions.
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

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
Library UNISIM;
use UNISIM.vcomponents.all;


entity pci_interface is port (
    
    -- EG PCI interface signals --
    bclk        : in std_logic;
    clocks      : in std_logic_vector(17 downto 0);
    
    master_control      : out std_logic_vector(8 downto 0);
    master_status       : in std_logic_vector(11 downto 0);
    
    interrupt_control   : out std_logic_vector(14 downto 0);
    clear_interrupts    : out std_logic_vector(13 downto 0);
    interrupt_status    : in std_logic_vector(13 downto 0);
    
    rising_control      : out std_logic_vector(31 downto 0);
    clear_rising        : out std_logic_vector(31 downto 0);
    rising_status       : in std_logic_vector(31 downto 0);
    
    falling_control     : out std_logic_vector(31 downto 0);
    clear_falling       : out std_logic_vector(31 downto 0);
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

    busevent            : out std_logic;
    lint1               : in std_logic;
    
    ident_serial_out_address_inc     : out std_logic;
    
    write_ident_fifo_data : out std_logic_vector(7 downto 0);
    write_ident_fifo_load  : out std_logic;
    write_ident_fifo_reset : out std_logic;
    
    
    -- PCIe core interrupt signals --
    cfg_interrupt_msienable : in  std_logic;
    cfg_interrupt_assert_n  : out std_logic;
    cfg_interrupt_rdy_n     : in  std_logic;
    cfg_command_int_en      : in  std_logic;
    cfg_interrupt_n         : out std_logic;
    cfg_interrupt_di        : out std_logic_vector(7 downto 0);
    
    
    -- Memory read/write control --
    rst_n                   : in  std_logic;
    wr_en_i                 : in  std_logic;
    rd_addr_i               : in  std_logic_vector (10 downto 0);
    rd_be_i                 : in  std_logic_vector (3 downto 0);
    wr_addr_i               : in  std_logic_vector (10 downto 0);
    wr_be_i                 : in  std_logic_vector (7 downto 0);
    wr_data_i               : in  std_logic_vector (31 downto 0);
    wr_busy_o               : out  std_logic;
    rd_data_o               : out  std_logic_vector (31 downto 0);
    rd_en_i                 : in std_logic
    
    );
end entity;

architecture structure of pci_interface is

  signal wr_data_i_0 :     std_logic_vector(7 downto 0);
  signal wr_data_i_1 :     std_logic_vector(7 downto 0);
  signal wr_data_i_2 :     std_logic_vector(7 downto 0);
  signal wr_data_i_3 :     std_logic_vector(7 downto 0);

  signal rd_data_o_0 :     std_logic_vector(7 downto 0);
  signal rd_data_o_1 :     std_logic_vector(7 downto 0);
  signal rd_data_o_2 :     std_logic_vector(7 downto 0);
  signal rd_data_o_3 :     std_logic_vector(7 downto 0);
  
  signal be_i: std_logic_vector(3 downto 0);
  signal addr_i: std_logic_vector(7 downto 0);
  signal address: std_logic_vector(7 downto 0);
  
  
begin


-----------------------------------------------------------------
-- Instantiate Components --
-----------------------------------------------------------------

  Inst_pcie_interrupt: entity work.pcie_interrupt 
    port map (bclk => bclk,
              rst_n => rst_n,
              lint1 => lint1,
              cfg_interrupt_msienable => cfg_interrupt_msienable,
              cfg_interrupt_assert_n  => cfg_interrupt_assert_n,
              cfg_interrupt_rdy_n   => cfg_interrupt_rdy_n,
              cfg_command_int_en => cfg_command_int_en,
              cfg_interrupt_n => cfg_interrupt_n,
              cfg_interrupt_di => cfg_interrupt_di);


  Inst_pcie_clear_interrupts: entity work.pci_clear_interrupts 
    port map (bclk => bclk,
              rd_en_i => rd_en_i,
              be_i => be_i,
              address => address,
              clear_rising  => clear_rising,
              clear_falling  => clear_falling,
              clear_interrupts => clear_interrupts);
  

  Inst_eg_registers: entity work.eg_registers 
    port map(bclk => bclk,        
             rst_n => rst_n, 
             be_i => be_i,
             address => address,
             wr_en_i => wr_en_i,
             rd_en_i => rd_en_i,
             wr_data_i_0 => wr_data_i_0, 
             wr_data_i_1 => wr_data_i_1,
             wr_data_i_2 => wr_data_i_2,
             wr_data_i_3 => wr_data_i_3,
             rd_data_o_0 => rd_data_o_0,
             rd_data_o_1 => rd_data_o_1,
             rd_data_o_2 => rd_data_o_2,
             rd_data_o_3 => rd_data_o_3,
             clocks => clocks,
             master_control => master_control,      
             master_status  => master_status,       
             interrupt_control => interrupt_control,   
             interrupt_status => interrupt_status,    
             rising_control => rising_control,      
             rising_status => rising_status,      
             falling_control => falling_control,     
             falling_status => falling_status,     
             event_output_control => event_output_control,
             event_output_status => event_output_status, 
             waveform_control  => waveform_control,    
             waveform_status => waveform_status,    
             frame_byte => frame_byte,        
             frame_byte_load => frame_byte_load,
             async_event_read => async_event_read,
             async_event_write =>  async_event_write,
             async_event_write_load => async_event_write_load,
             ls_sync_event => ls_sync_event,
             ls_sync_event_load => ls_sync_event_load,
             ms_sync_event  => ms_sync_event,
             ms_sync_event_load  => ms_sync_event_load,
             ident_serial_out_address_inc => ident_serial_out_address_inc,
             write_ident_fifo_data => write_ident_fifo_data,
             write_ident_fifo_load => write_ident_fifo_load,
             write_ident_fifo_reset => write_ident_fifo_reset);
  
  
-----------------------------------------------------------------
-- Concurrent Signal Assignments --
-----------------------------------------------------------------

  wr_busy_o <= '1' when  wr_en_i = '1' else '0';

  addr_i <=wr_addr_i(7 downto 0) when wr_en_i='1' else rd_addr_i(7 downto 0);
  address(7 downto 2) <= addr_i(5 downto 0);
  address(1 downto 0) <= "00";

  be_i<=wr_be_i(3 downto 0) when wr_en_i='1' else rd_be_i(3 downto 0);

  busevent <= wr_en_i or rd_en_i;


  -- Rename a few of the commonly used signals to make the code more readable --

  wr_data_i_3 <= wr_data_i(7 downto 0);
  wr_data_i_2 <= wr_data_i(15 downto 8);
  wr_data_i_1 <= wr_data_i(23 downto 16);
  wr_data_i_0 <= wr_data_i(31 downto 24);

  rd_data_o(7 downto 0)   <=  rd_data_o_3;
  rd_data_o(15 downto 8)  <=  rd_data_o_2;
  rd_data_o(23 downto 16) <=  rd_data_o_1;
  rd_data_o(31 downto 24) <=  rd_data_o_0;
  
end architecture;

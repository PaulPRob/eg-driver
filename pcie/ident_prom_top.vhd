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
-- File Name: ident_prom_top.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Ident PROM Top Module
--
-- Description: The top level block of identity read write modules
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
use work.pci_package.all;


entity ident_prom_top is
  port (

    bclk  : in std_logic;
    reset : in std_logic;

    -- Read --
    master_control               : in  std_logic_vector(8 downto 0);
    ident_serial_out_address_inc : in  std_logic;
    read_serial_out              : out std_logic;

    -- Write --
    write_ident_fifo_data  : in std_logic_vector(7 downto 0);
    write_ident_fifo_load  : in std_logic;
    write_ident_fifo_reset : in std_logic;


    -- 1 Wire Interface --
    onewire_oe : out std_logic;
    onewire_o  : out std_logic;
    onewire_i  : in  std_logic
    );    

end entity;

architecture behavioral of ident_prom_top is
  
--  signal master_control_local : master_control_t;

  signal clk                       : std_logic;
  signal sig_empty_write           : std_logic;
  signal sig_running               : std_logic;
  signal sig_onewire_error         : std_logic;  -- ATNF MOD FOR EG
  signal sig_ident_fifo_dout_write : std_logic_vector(7 downto 0);
  signal sig_strobe                : std_logic;
  signal sig_mode                  : std_logic_vector(1 downto 0);
  signal sig_serial_address        : std_logic_vector(7 downto 0);
  signal sig_serial_read_data      : std_logic_vector(63 downto 0);
  signal sig_read_address          : std_logic_vector(7 downto 0);
  signal sig_read_strobe           : std_logic:= '0';
  signal sig_write_strobe          : std_logic:= '0';
  signal sig_write_address         : std_logic_vector(7 downto 0) := "00000000";
  signal sig_ident_pop_write       : std_logic:= '0';
  signal sig_serial_write_data     : std_logic_vector(63 downto 0);
  signal sig_re_read_prom          : std_logic:= '0';
  signal sig_write_state           : std_logic:= '0';
  signal sig_read_prom_done        : std_logic:= '0';
  signal sig_ident_ram_data_read   : std_logic_vector(63 downto 0);
  signal sig_ident_ram_addr_rd     : std_logic_vector(4 downto 0);

  -- Constants --
  constant fifo_width_write       : integer := 8;
  constant fifo_depth_write       : integer := 128;
  constant fifo_addr_length_write : integer := 7;

  
begin

---------------------------------------------------------------------------------
-- Instantiate Components --
---------------------------------------------------------------------------------
  
  Inst_ident_clk : entity onewire_clk
    port map(bclk  => bclk,
             reset => reset,
             clk   => clk);


  Inst_onewire_prom : entity onewire_ctrl
    port map (clk            => clk,
              reset          => reset,
              strobe => sig_strobe,
              mode           => sig_mode,
              mem_address    => sig_serial_address,
              mem_read_data  => sig_serial_read_data,
              mem_write_data => sig_serial_write_data,
              error          => sig_onewire_error,  -- ATNF MOD FOR EG: was open
              running => sig_running,
              onewire_oe     => onewire_oe,
              onewire_o      => onewire_o,
              onewire_i      => onewire_i);


  Inst_ident_write_fifo : entity work.async_fifo
    generic map (width          => fifo_width_write,
                 depth          => fifo_depth_write,
                 address_length => fifo_addr_length_write)
    port map (wclk     => bclk,
                 we    => write_ident_fifo_load,
                 wd    => write_ident_fifo_data,
                 rclk  => clk,
                 re    => sig_ident_pop_write,
                 rd    => sig_ident_fifo_dout_write,
                 rst   => write_ident_fifo_reset,
                 empty => sig_empty_write,
                 low   => open,
                 half  => open,
                 high  => open,
                 full  => open);


  Inst_ident_write : entity ident_write_s_m
    port map (clk                   => clk,
              reset                 => reset,
              master_control        => master_control,
              ident_fifo_dout_write => sig_ident_fifo_dout_write,
              ident_pop_write       => sig_ident_pop_write,
              empty_write           => sig_empty_write,
              serial_write_data     => sig_serial_write_data,
              write_address         => sig_write_address,
              write_strobe          => sig_write_strobe,
              one_wire_running      => sig_running,
              write_state           => sig_write_state,
              re_read_prom          => sig_re_read_prom);


  Inst_ident_read : entity ident_read_s_m
    port map (clk                  => clk,
              reset                => reset,
              onewire_read_data    => sig_serial_read_data,
              onewire_read_address => sig_read_address,
              onewire_read_strobe  => sig_read_strobe,
              one_wire_running     => sig_running,
              one_wire_error       => sig_onewire_error,  -- ATNF MOD FOR EG
              re_read_prom         => sig_re_read_prom,
              read_prom_done       => sig_read_prom_done,
              ident_ram_addr_rd    => sig_ident_ram_addr_rd,
              ident_ram_data_read  => sig_ident_ram_data_read);


  Inst_ident_serial_rd : entity ident_serial_read
    port map (bclk                         => bclk,
              reset                        => reset,
              master_control               => master_control,
              ident_serial_out_address_inc => ident_serial_out_address_inc,
              read_serial_out              => read_serial_out,
              ident_ram_data_read          => sig_ident_ram_data_read,
              ident_ram_addr_rd            => sig_ident_ram_addr_rd);


---------------------------------------------------------------------------------
-- Concurrent Signal Assignments --
---------------------------------------------------------------------------------

--  master_control_local <= slv_to_master_control(master_control);

-- Read/Write MUX's --

  sig_mode           <= "11"              when sig_write_state = '1' else "10";
  sig_strobe         <= sig_write_strobe  when sig_write_state = '1' else sig_read_strobe;
  sig_serial_address <= sig_write_address when sig_write_state = '1' else sig_read_address;
  
end behavioral;


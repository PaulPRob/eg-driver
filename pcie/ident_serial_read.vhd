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
-- File Name: ident_serial_read.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Ident Serial Read
--
-- Description: Reads out the ident string through the MSB of the master control register 
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


entity ident_serial_read is
  port(
    bclk                         : in  std_logic;
    reset                        : in  std_logic;
    master_control               : in  std_logic_vector(8 downto 0);
    ident_serial_out_address_inc : in  std_logic;
    read_serial_out              : out std_logic;
    ident_ram_data_read          : in  std_logic_vector(63 downto 0);
    ident_ram_addr_rd            : out std_logic_vector(4 downto 0)
    );

end ident_serial_read;

architecture behavioral of ident_serial_read is

  signal master_control_local : master_control_t;

  signal sig_serial_out_index         : integer range 0 to 63;
  signal sig_ident_ram_addr_rd        : std_logic_vector(4 downto 0) := "00000";
  signal sig_ident_ram_data_read_swap : std_logic_vector(63 downto 0);

begin

 --Serial Read Out Ident String--

 process(bclk)
  begin
       if rising_edge(bclk) then
         
         if (reset = '1' or master_control_local.serial_prom_reset = '1') then
             sig_serial_out_index <= 0;              sig_ident_ram_addr_rd <= (others => '0');
                                                                             
         elsif ident_serial_out_address_inc = '1' then
             sig_serial_out_index <= sig_serial_out_index+1; 
				 
				 if (sig_serial_out_index = 63) then
					
					sig_ident_ram_addr_rd <= sig_ident_ram_addr_rd+1;
					sig_serial_out_index  <= 0;
					
				 end if;
        end if;
       end if; 
 end process; 

	---------------------------------------------------------------
	--Concurrent Signal Assignments
	---------------------------------------------------------------
  
  master_control_local <= slv_to_master_control(master_control);                
  sig_ident_ram_data_read_swap(7 downto 0) <= ident_ram_data_read(63 downto 56);
  sig_ident_ram_data_read_swap(15 downto 8)  <= ident_ram_data_read(55 downto 48);
  sig_ident_ram_data_read_swap(23 downto 16) <= ident_ram_data_read(47 downto 40);
  sig_ident_ram_data_read_swap(31 downto 24) <= ident_ram_data_read(39 downto 32);

  sig_ident_ram_data_read_swap(39 downto 32) <= ident_ram_data_read(31 downto 24);
  sig_ident_ram_data_read_swap(47 downto 40) <= ident_ram_data_read(23 downto 16);
  sig_ident_ram_data_read_swap(55 downto 48) <= ident_ram_data_read(15 downto 8);
  sig_ident_ram_data_read_swap(63 downto 56) <= ident_ram_data_read(7 downto 0);

  read_serial_out <= sig_ident_ram_data_read_swap(sig_serial_out_index); 
  ident_ram_addr_rd <= sig_ident_ram_addr_rd;

end behavioral;


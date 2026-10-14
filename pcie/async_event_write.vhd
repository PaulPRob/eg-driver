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
-- File Name: async_event_write.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Async Event Write
--
-- Description: Writes async events.
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

entity async_event_write is
port(
	bclk: in std_logic;
	be_i: in std_logic;
	address: in std_logic_vector(7 downto 0);
	wr_en_i: in std_logic;
	wr_data_i_2: in std_logic_vector(7 downto 0);
	wr_data_i_3: in std_logic_vector(7 downto 0);
	async_event_write_msb: in std_logic_vector(7 downto 0);
	async_event_write: out std_logic_vector(15 downto 0)
);
end async_event_write;

architecture Behavioral of async_event_write is

signal sig_async_event_write: std_logic_vector(15 downto 0);

begin

 -- ASYNC_EVENT_WRITE --
	process(bclk)
	 begin
	  if rising_edge(bclk) then

		if wr_en_i='1' and address=x"08" then
		 if be_i='1' then
		  sig_async_event_write <= wr_data_i_3 & wr_data_i_2; 
		 else
		  sig_async_event_write <= async_event_write_msb & wr_data_i_2; 
		 end if;
		end if;

	  end if;
	end process;

	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

	async_event_write <= sig_async_event_write;


end Behavioral;


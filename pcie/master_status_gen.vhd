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
-- File Name: master_status_gen.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Event Master Status Generator
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
use work.pci_package.all;

entity master_status_gen is port
   (
	 pll					 	: in	std_logic;
	 serial_number		   	: in	std_logic;
	 frame_loaded				: in	std_logic;
	 late_event			  	: in	std_logic;
	 event_generator_running 	: in	std_logic;
	 frame_fifo_empty			: in	std_logic;
	 ls_ref_fifo_empty		  : in	std_logic;
	 ms_ref_fifo_empty		  : in	std_logic;
	 ls_ref_fifo_half_empty	 : in	std_logic;
	 ms_ref_fifo_half_empty	 : in	std_logic;
	 ls_ref_fifo_full		   : in	std_logic;
	 ms_ref_fifo_full		   : in	std_logic;
    master_status		   : out   std_logic_vector(11 downto 0)
   );
end master_status_gen;

architecture structure of master_status_gen is
	signal master_status_local: master_status_t;
begin
	master_status_local.pll						<= pll;
	master_status_local.serial_number			<= serial_number;
	master_status_local.frame_loaded			<= frame_loaded;
	master_status_local.late_event				<= late_event;
	master_status_local.event_generator_running	<= event_generator_running;
	master_status_local.frame_fifo_empty		<= frame_fifo_empty;
	master_status_local.ls_ref_fifo_empty		<= ls_ref_fifo_empty;
	master_status_local.ms_ref_fifo_empty		<= ms_ref_fifo_empty;
	master_status_local.ls_ref_fifo_half_empty	<= ls_ref_fifo_half_empty;
	master_status_local.ms_ref_fifo_half_empty	<= ms_ref_fifo_half_empty;
	master_status_local.ls_ref_fifo_full		<= ls_ref_fifo_full;
	master_status_local.ms_ref_fifo_full		<= ms_ref_fifo_full;

	master_status <= master_status_to_slv(master_status_local);

end structure;
------------------------------------------------------------
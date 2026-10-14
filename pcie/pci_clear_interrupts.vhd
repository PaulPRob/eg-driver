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
-- File Name: pci_clear_interrupts.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 

-- Title: PCI Clear Interrupts
--
-- Description: 
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
use work.clocks_package.all;
use work.pci_package.all;
Library UNISIM;
use UNISIM.vcomponents.all;


entity pci_clear_interrupts is
port(
    
	bclk: in std_logic;
	rd_en_i: in std_logic;
	be_i: in std_logic_vector(3 downto 0);
	address: in std_logic_vector(7 downto 0);
	clear_rising: out std_logic_vector(31 downto 0);
	clear_falling: out std_logic_vector(31 downto 0);
	clear_interrupts: out std_logic_vector(13 downto 0)
	
	);
   
end pci_clear_interrupts;

architecture Behavioral of pci_clear_interrupts is

signal clear_interrupts_local:   interrupts_t;
signal clear_rising_local:     supplementary_interrupts_t;
signal clear_falling_local:     supplementary_interrupts_t;
 
begin


	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

	clear_interrupts   <= interrupts_to_slv(clear_interrupts_local);
	clear_rising     <= supplementary_interrupts_to_slv(clear_rising_local);
	clear_falling     <= supplementary_interrupts_to_slv(clear_falling_local);


-- CLEAR_INTERRUPTS --
 process(bclk)
 begin
  if rising_edge(bclk) then

   -- CLEAR_INTERRUPTS BYTE 0
   if rd_en_i='1' and address=x"04" and be_i(0)='1' then
    clear_interrupts_local.ref_fifo_empty    <= '1';
    clear_interrupts_local.ref_fifo_half_empty <= '1';
    clear_interrupts_local.late_event      <= '1';
    clear_interrupts_local.checksum_error    <= '1';
    clear_interrupts_local.false_sync      <= '1';
    clear_interrupts_local.missed_sync     <= '1';
    clear_interrupts_local.frame_loaded     <= '1';
    clear_interrupts_local.dma_done       <= '1';
   else
    clear_interrupts_local.ref_fifo_empty    <= '0';
    clear_interrupts_local.ref_fifo_half_empty <= '0';
    clear_interrupts_local.late_event      <= '0';
    clear_interrupts_local.checksum_error    <= '0';
    clear_interrupts_local.false_sync      <= '0';
    clear_interrupts_local.missed_sync     <= '0';
    clear_interrupts_local.frame_loaded     <= '0';
    clear_interrupts_local.dma_done       <= '0';
   end if;

   -- CLEAR_INTERRUPTS BYTE 1
   if rd_en_i='1' and address=x"04" and be_i(1)='1' then
    clear_interrupts_local.external_interrupt    <= '1';
    clear_interrupts_local.internal_interrupt    <= '1';
    clear_interrupts_local.pll_dropout       <= '1';
    clear_interrupts_local.one_second        <= '1';
    clear_interrupts_local.finished         <= '1';
    clear_interrupts_local.supplementary_interrupt <= '1';
   else
    clear_interrupts_local.external_interrupt    <= '0';
    clear_interrupts_local.internal_interrupt    <= '0';
    clear_interrupts_local.pll_dropout       <= '0';
    clear_interrupts_local.one_second        <= '0';
    clear_interrupts_local.finished         <= '0';
    clear_interrupts_local.supplementary_interrupt <= '0';
   end if;

   -- CLEAR_RISING BYTE 0
   if rd_en_i='1' and address=x"24" and be_i(0)='1' then
    clear_rising_local.event(0)  <= '1';
    clear_rising_local.event(1)  <= '1';
    clear_rising_local.event(2)  <= '1';
    clear_rising_local.event(3)  <= '1';
    clear_rising_local.event(4)  <= '1';
    clear_rising_local.event(5)  <= '1';
    clear_rising_local.event(6)  <= '1';
    clear_rising_local.event(7)  <= '1';
   else
    clear_rising_local.event(0)  <= '0';
    clear_rising_local.event(1)  <= '0';
    clear_rising_local.event(2)  <= '0';
    clear_rising_local.event(3)  <= '0';
    clear_rising_local.event(4)  <= '0';
    clear_rising_local.event(5)  <= '0';
    clear_rising_local.event(6)  <= '0';
    clear_rising_local.event(7)  <= '0';
   end if;

   -- CLEAR_RISING BYTE 1
   if rd_en_i='1' and address=x"24" and be_i(1)='1' then
    clear_rising_local.event(8)  <= '1';
    clear_rising_local.event(9)  <= '1';
    clear_rising_local.event(10) <= '1';
    clear_rising_local.event(11) <= '1';
    clear_rising_local.event(12) <= '1';
    clear_rising_local.event(13) <= '1';
    clear_rising_local.event(14) <= '1';
    clear_rising_local.event(15) <= '1';
   else
    clear_rising_local.event(8)  <= '0';
    clear_rising_local.event(9)  <= '0';
    clear_rising_local.event(10) <= '0';
    clear_rising_local.event(11) <= '0';
    clear_rising_local.event(12) <= '0';
    clear_rising_local.event(13) <= '0';
    clear_rising_local.event(14) <= '0';
    clear_rising_local.event(15) <= '0';
   end if;

   -- CLEAR_RISING BYTE 2
   if rd_en_i='1' and address=x"24" and be_i(2)='1' then
    clear_rising_local.waveforms(0)  <= '1';
    clear_rising_local.waveforms(1)  <= '1';
    clear_rising_local.waveforms(2)  <= '1';
    clear_rising_local.waveforms(3)  <= '1';
    clear_rising_local.waveforms(4)  <= '1';
    clear_rising_local.waveforms(5)  <= '1';
    clear_rising_local.waveforms(6)  <= '1';
    clear_rising_local.waveforms(7)  <= '1';
   else
    clear_rising_local.waveforms(0)  <= '0';
    clear_rising_local.waveforms(1)  <= '0';
    clear_rising_local.waveforms(2)  <= '0';
    clear_rising_local.waveforms(3)  <= '0';
    clear_rising_local.waveforms(4)  <= '0';
    clear_rising_local.waveforms(5)  <= '0';
    clear_rising_local.waveforms(6)  <= '0';
    clear_rising_local.waveforms(7)  <= '0';
   end if;

   -- CLEAR_RISING BYTE 3
   if rd_en_i='1' and address=x"24" and be_i(3)='1' then
    clear_rising_local.t2ppms   <= '1';
    clear_rising_local.t4ppms   <= '1';
    clear_rising_local.t8ppms   <= '1';
    clear_rising_local.t16ppms  <= '1';
    clear_rising_local.unused0  <= '1';
    clear_rising_local.unused1  <= '1';
    clear_rising_local.unused2  <= '1';
    clear_rising_local.strobe   <= '1';
   else
    clear_rising_local.t2ppms   <= '0';
    clear_rising_local.t4ppms   <= '0';
    clear_rising_local.t8ppms   <= '0';
    clear_rising_local.t16ppms  <= '0';
    clear_rising_local.unused0  <= '0';
    clear_rising_local.unused1  <= '0';
    clear_rising_local.unused2  <= '0';
    clear_rising_local.strobe   <= '0';
   end if;

   -- CLEAR_FALLING BYTE 0
   if rd_en_i='1' and address=x"2C" and be_i(0)='1' then
    clear_falling_local.event(0) <= '1';
    clear_falling_local.event(1) <= '1';
    clear_falling_local.event(2) <= '1';
    clear_falling_local.event(3) <= '1';
    clear_falling_local.event(4) <= '1';
    clear_falling_local.event(5) <= '1';
    clear_falling_local.event(6) <= '1';
    clear_falling_local.event(7) <= '1';
   else
    clear_falling_local.event(0) <= '0';
    clear_falling_local.event(1) <= '0';
    clear_falling_local.event(2) <= '0';
    clear_falling_local.event(3) <= '0';
    clear_falling_local.event(4) <= '0';
    clear_falling_local.event(5) <= '0';
    clear_falling_local.event(6) <= '0';
    clear_falling_local.event(7) <= '0';
   end if;

   -- CLEAR_FALLING BYTE 1
   if rd_en_i='1' and address=x"2C" and be_i(1)='1' then
    clear_falling_local.event(8) <= '1';
    clear_falling_local.event(9) <= '1';
    clear_falling_local.event(10) <= '1';
    clear_falling_local.event(11) <= '1';
    clear_falling_local.event(12) <= '1';
    clear_falling_local.event(13) <= '1';
    clear_falling_local.event(14) <= '1';
    clear_falling_local.event(15) <= '1';
   else
    clear_falling_local.event(8) <= '0';
    clear_falling_local.event(9) <= '0';
    clear_falling_local.event(10) <= '0';
    clear_falling_local.event(11) <= '0';
    clear_falling_local.event(12) <= '0';
    clear_falling_local.event(13) <= '0';
    clear_falling_local.event(14) <= '0';
    clear_falling_local.event(15) <= '0';
   end if;

   -- CLEAR_FALLING BYTE 2
   if rd_en_i='1' and address=x"2C" and be_i(2)='1' then
    clear_falling_local.waveforms(0)  <= '1';
    clear_falling_local.waveforms(1)  <= '1';
    clear_falling_local.waveforms(2)  <= '1';
    clear_falling_local.waveforms(3)  <= '1';
    clear_falling_local.waveforms(4)  <= '1';
    clear_falling_local.waveforms(5)  <= '1';
    clear_falling_local.waveforms(6)  <= '1';
    clear_falling_local.waveforms(7)  <= '1';
   else
    clear_falling_local.waveforms(0)  <= '0';
    clear_falling_local.waveforms(1)  <= '0';
    clear_falling_local.waveforms(2)  <= '0';
    clear_falling_local.waveforms(3)  <= '0';
    clear_falling_local.waveforms(4)  <= '0';
    clear_falling_local.waveforms(5)  <= '0';
    clear_falling_local.waveforms(6)  <= '0';
    clear_falling_local.waveforms(7)  <= '0';
   end if;

   -- CLEAR_FALLING BYTE 3
   if rd_en_i='1' and address=x"2C" and be_i(3)='1' then
    clear_falling_local.t2ppms  <= '1';
    clear_falling_local.t4ppms  <= '1';
    clear_falling_local.t8ppms  <= '1';
    clear_falling_local.t16ppms  <= '1';
    clear_falling_local.unused0  <= '1';
    clear_falling_local.unused1  <= '1';
    clear_falling_local.unused2  <= '1';
    clear_falling_local.strobe  <= '1';
   else
    clear_falling_local.t2ppms  <= '0';
    clear_falling_local.t4ppms  <= '0';
    clear_falling_local.t8ppms  <= '0';
    clear_falling_local.t16ppms  <= '0';
    clear_falling_local.unused0  <= '0';
    clear_falling_local.unused1  <= '0';
    clear_falling_local.unused2  <= '0';
    clear_falling_local.strobe  <= '0';
   end if;

  end if;
 end process;



end Behavioral;


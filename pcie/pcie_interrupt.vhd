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
-- File Name: pcie_interrupt.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: PCIe Interrupt State Machine
--
-- Description: This state machine detects legacy or message signaled interrupts and services
-- them accordingly.
-- 
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
use ieee.numeric_std.all;
use work.clocks_package.all;
use work.pci_package.all;
library unisim;
use unisim.vcomponents.all;

-------------------------------------------------------------------------------


entity pcie_interrupt is
  port (

    bclk                    : in  std_logic;
    rst_n                   : in  std_logic;
    lint1                   : in  std_logic;
    cfg_interrupt_msienable : in  std_logic;
    cfg_interrupt_assert_n  : out std_logic;
    cfg_interrupt_rdy_n     : in  std_logic;
    cfg_command_int_en      : in  std_logic;
    cfg_interrupt_n         : out std_logic;
    cfg_interrupt_di        : out std_logic_vector(7 downto 0)

    );

end pcie_interrupt;


architecture behavioral of pcie_interrupt is

  -- Interrupt States --
  type intr_state_type is (
    INTERRUPT_IDLE,
    SEND_INTERRUPT,
    WAIT_CORE_ACCEPT,
    WAIT_USER_APP,
    USER_APP_ACCEPT
    );

  signal intr_state                 : intr_state_type;
  signal sig_cfg_interrupt_n        : std_logic;
  signal sig_cfg_interrupt_assert_n : std_logic;

  
begin


-----------------------------------------------------------------
-- Interrupt Handling --
-----------------------------------------------------------------


  process(bclk, rst_n)

  begin

    if (rst_n = '0') then

      sig_cfg_interrupt_assert_n <= '1';
      sig_cfg_interrupt_n        <= '1';
      intr_state                 <= INTERRUPT_IDLE;

    elsif rising_edge(bclk) then

      case (intr_state) is
        
        
        when INTERRUPT_IDLE => 		if (lint1 = '1') then
                                         intr_state <= SEND_INTERRUPT;
                                    else
                                         intr_state <= INTERRUPT_IDLE;
                                    end if;
                                        
                                        
        when SEND_INTERRUPT =>      sig_cfg_interrupt_n <= '0';
                                    sig_cfg_interrupt_assert_n <= '0';
                                    intr_state <= WAIT_CORE_ACCEPT;
                                        
        when WAIT_CORE_ACCEPT =>    if (cfg_interrupt_rdy_n = '0') then
                                         intr_state          <= WAIT_USER_APP;
                                         sig_cfg_interrupt_n <= '1';
                                    else
                                         intr_state <= WAIT_CORE_ACCEPT;
                                    end if;
                                   
        when WAIT_USER_APP =>       if (lint1 = '0') then
													 sig_cfg_interrupt_n        <= '0';
													 sig_cfg_interrupt_assert_n <= '1';
													 intr_state <= USER_APP_ACCEPT;
                                    else
                                        intr_state <= WAIT_USER_APP;
                                    end if;
                                   
        when USER_APP_ACCEPT =>     if (cfg_interrupt_rdy_n = '0') then
                                        intr_state          <= INTERRUPT_IDLE;
                                        sig_cfg_interrupt_n <= '1';
                                    else
                                        intr_state <= USER_APP_ACCEPT;
                                    end if;
                                   
        when others =>              intr_state <= INTERRUPT_IDLE;
                                   
      end case;
      
    end if;
  end process;


	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

  cfg_interrupt_n <= sig_cfg_interrupt_n;
  cfg_interrupt_di <= x"00";
  cfg_interrupt_assert_n <= sig_cfg_interrupt_assert_n;



end behavioral;


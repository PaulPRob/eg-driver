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
-- File Name: interrupt_buffer.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Interrupt Buffer
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

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity interrupt_buffer is
  port (
    clk     : in     std_logic;
    rst     : in     std_logic;
    trigger : in     std_logic;
    enable  : in     std_logic;
    status  : out std_logic
    );
end entity;

architecture structure of interrupt_buffer is

  signal trigger_rising_edge         : std_logic;
  signal trigger_rising_edge_clocked : std_logic;
  signal sig_status: std_logic;

begin

process(trigger_rising_edge_clocked, trigger)
  begin
    if trigger_rising_edge_clocked = '1' then
      trigger_rising_edge <= '0';
    elsif rising_edge(trigger) then
      if enable = '1' then
        trigger_rising_edge <= '1';
      else
        trigger_rising_edge <= '0';
      end if;
    end if;
end process;


process(clk)
  begin
    if rising_edge(clk) then
      if trigger_rising_edge = '1' then
        trigger_rising_edge_clocked <= '1';
      else
        trigger_rising_edge_clocked <= '0';
      end if;
    end if;
end process;


process(clk)
  begin
    if rising_edge(clk) then
      if trigger_rising_edge_clocked = '1' or (sig_status = '1' and rst = '0') then
        sig_status <= '1';
      else
        sig_status <= '0';
      end if;
    end if;
end process;

status <=sig_status;

end architecture;




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
-- File Name: delayed_control_buffer.vhd         
-- Designer: Jesse Kovac
-- Created:      
-- Title: Delayed Control Buffer
-- Description:  
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity delayed_control_buffer is
  generic (
    target_address : std_logic_vector(7 downto 0) := x"00";
    target_en_i    : std_logic                    := '1'
    );
  port (
    in_clk   : in  std_logic;
    en_i     : in  std_logic;
    addr_i   : in  std_logic_vector(7 downto 0);
    be_i     : in  std_logic;
    in_data  : in  std_logic;
    out_clk  : in  std_logic;
    out_data : out std_logic
    );
end entity;

architecture structure of delayed_control_buffer is

  signal trigger         : std_logic;
  signal delayed_trigger : std_logic;
  signal latch           : std_logic;
  signal clocked_latch   : std_logic;

begin



  process(in_clk)
  begin
    
    if rising_edge(in_clk) then

      if (en_i = target_en_i)
        and addr_i(7 downto 0) = target_address and be_i = '1' then
        trigger <= in_data;
      else
        trigger <= '0';
      end if;

      if trigger = '1' then
        delayed_trigger <= '1';
      else
        delayed_trigger <= '0';
      end if;

    end if;
  end process;

--------------------------------------------------------------------------

  process(out_clk, delayed_trigger, clocked_latch, latch)
  begin
    if clocked_latch = '0' and (delayed_trigger = '1' or latch = '1') then
      latch <= '1';
    else
      latch <= '0';
    end if;
  end process;


--------------------------------------------------------------------------

  process(out_clk)
  begin
    if rising_edge(out_clk) then
      if latch = '1' then
        clocked_latch <= '1';
      else
        clocked_latch <= '0';
      end if;
    end if;
  end process;


	-----------------------------------------------------------------
	-- Concurrent Signal Assignments --
	-----------------------------------------------------------------

  out_data <= clocked_latch;

end architecture;

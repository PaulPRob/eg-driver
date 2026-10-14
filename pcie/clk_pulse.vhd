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
-- File Name: clk_pulse.vhd         
-- Designer: Jesse Kovac
-- Created:      
-- Title: Clock Pulse
-- Description: This process generates a pulse for one clock cycle of the bus clock.  
--
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;


entity clk_pulse is
generic (
    target_address : std_logic_vector(7 downto 0) := x"00"
    );
port(

    bclk    : in  std_logic;
    en_i    : in  std_logic;
    be_i    : in  std_logic;
    data_i  : in  std_logic;
    address : in  std_logic_vector(7 downto 0);
    data_o  : out std_logic

    );
end clk_pulse;


architecture behavioral of clk_pulse is

begin

  process(bclk)

  begin

    if rising_edge(bclk) then

      if (address = target_address and en_i = '1' and be_i = '1' and data_i = '1') then

        data_o <= '1';
        
      else

        data_o <= '0';

      end if;
    end if;

  end process;


end behavioral;


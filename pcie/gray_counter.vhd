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
-- File Name: gray_counter.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: PCIe Top Level
--
-- Description: Gray Counter
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

-- For example, the 4 bit gray code is:
-- dec  gray    binary
-- 0    0000    0000
-- 1    0001    0001
-- 2    0011    0010
-- 3    0010    0011
-- 4    0110    0100
-- 5    0111    0101
-- 6    0101    0110
-- 7    0100    0111
-- 8    1100    1000
-- 9    1101    1001
-- 10   1111    1010
-- 11   1110    1011
-- 12   1010    1100
-- 13   1011    1101
-- 14   1001    1110
-- 15   1000    1111

entity gray_counter is
generic (
    constant bits : integer := 4
    );
port (
    clk : in std_logic;
    rst : in std_logic;
    en  : in std_logic;

    binary : out std_logic_vector(bits-1 downto 0);
    gray   : out std_logic_vector(bits-1 downto 0)
    );
end entity;

architecture structure of gray_counter is
  signal next_binary : std_logic_vector(bits-1 downto 0);
  signal sig_binary  : std_logic_vector(bits-1 downto 0);
  signal sig_gray    : std_logic_vector(bits-1 downto 0);
begin

  process(rst, clk, en)
  begin

    if rst = '1' then
      sig_binary  <= std_logic_vector(to_unsigned(0, bits));
      next_binary <= std_logic_vector(to_unsigned(1, bits));
      sig_gray    <= std_logic_vector(to_unsigned(0, bits));

    elsif rising_edge(clk) and en = '1' then
      sig_binary  <= std_logic_vector(unsigned(sig_binary) + 1);
      next_binary <= std_logic_vector(unsigned(next_binary) + 1);

      for i in 0 to bits-1 loop
        if i < bits-1 then
          sig_gray(i) <= next_binary(i) xor next_binary(i+1);
        else
          sig_gray(i) <= next_binary(i);
        end if;
      end loop;

    end if;
  end process;

  binary <= sig_binary;
  gray   <= sig_gray;
  
end architecture;


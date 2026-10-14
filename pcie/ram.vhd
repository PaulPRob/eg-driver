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
-- File Name: ram.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: RAM
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

entity ram is
  generic (
    constant width : integer := 8;
    constant depth : integer := 64
    );
  port (
    clk : in std_logic;

    address : in integer range 0 to depth-1;
    din_en  : in std_logic;
    din     : in std_logic_vector(width-1 downto 0);
    dual_address : in  integer range 0 to depth-1;
    dual_dout    : out std_logic_vector(width-1 downto 0)
    );
end entity;

architecture structure of ram is

  type ram_t is array (depth-1 downto 0) of std_logic_vector (width-1 downto 0);
  signal ram               : ram_t;
  signal read_dual_address : integer range 0 to depth-1;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if (din_en = '1') then
        ram(address) <= din;
      end if;
      read_dual_address <= dual_address;
    end if;
  end process;

  dual_dout <= ram(read_dual_address);

end architecture;

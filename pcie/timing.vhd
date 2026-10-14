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
-- File Name: timing.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Timing
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
use work.clocks_package.all;

entity timing is port (
  clocks : in std_logic_vector(17 downto 0);

  clkb_8mhz : out std_logic;
  clkb_2mhz : out std_logic;
  clkt_1mhz : out std_logic;
  clkd_1mhz : out std_logic;
  clkq_1mhz : out std_logic;
  t500khz   : out std_logic;
  t250khz   : out std_logic;
  t125khz   : out std_logic;
  t62ppms   : out std_logic;
  t31ppms   : out std_logic;
  t16ppms   : out std_logic;
  t8ppms    : out std_logic;
  t4ppms    : out std_logic;
  t2ppms    : out std_logic;

  cntr_in   : in  std_logic;            -- Not implemented.
  ext_trig0 : in  std_logic;            -- Not implemented.
  ext_trig1 : in  std_logic;            -- Not implemented.
  cntr_out  : out std_logic;            -- Not implemented
  msclk     : out std_logic;            -- Not implemented.
  x1sclk    : out std_logic             -- Not implemented.
  );
end timing;
------------------------------------------------------------

------------------------------------------------------------
architecture structure of timing is
  signal clocks_local : clocks_t;
begin

  clocks_local <= slv_to_clocks(clocks);

  clkb_8mhz <= clocks_local.clkb_8mhz;
  clkb_2mhz <= clocks_local.clkb_2mhz;
  clkt_1mhz <= clocks_local.clkt_1mhz_ub;
  clkd_1mhz <= clocks_local.clkd_1mhz;
  clkq_1mhz <= clocks_local.clkq_1mhz;

  t500khz <= clocks_local.t500khz;
  t250khz <= clocks_local.t250khz;
  t125khz <= clocks_local.t125khz;
  t62ppms <= clocks_local.t62ppms;
  t31ppms <= clocks_local.t31ppms;
  t16ppms <= clocks_local.t16ppms;
  t8ppms  <= clocks_local.t8ppms;
  t4ppms  <= clocks_local.t4ppms;
  t2ppms  <= clocks_local.t2ppms;
  msclk   <= clocks_local.t1ppms;

  cntr_out <= '0';
  x1sclk   <= '0';
  
end structure;
------------------------------------------------------------

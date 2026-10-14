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
-- File Name: clocks_package.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Clock Package
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

package clocks_package is

  type clocks_t is record
    vco_16m      : std_logic;
    clkb_8mhz    : std_logic;
    clkb_4mhz    : std_logic;
    clkb_2mhz    : std_logic;
    clkt_1mhz    : std_logic;
    clkd_1mhz    : std_logic;
    clkq_1mhz    : std_logic;
    t500khz      : std_logic;
    t250khz      : std_logic;
    t125khz      : std_logic;
    t62ppms      : std_logic;
    t31ppms      : std_logic;
    t16ppms      : std_logic;
    t8ppms       : std_logic;
    t4ppms       : std_logic;
    t2ppms       : std_logic;
    t1ppms       : std_logic;
    clkt_1mhz_ub : std_logic;
  end record;

  function clocks_to_slv (clocks : clocks_t) return std_logic_vector;

  function slv_to_clocks(slv : std_logic_vector) return clocks_t;

end package;

package body clocks_package is

  ------------------------------------------------------------
  -- ********_TO_SLV
  function clocks_to_slv (clocks : clocks_t) return std_logic_vector is
    variable slv : std_logic_vector(17 downto 0);
  begin
    slv(0)  := clocks.vco_16m;
    slv(1)  := clocks.clkb_8mhz;
    slv(2)  := clocks.clkb_4mhz;
    slv(3)  := clocks.clkb_2mhz;
    slv(4)  := clocks.clkt_1mhz;
    slv(5)  := clocks.clkd_1mhz;
    slv(6)  := clocks.clkq_1mhz;
    slv(7)  := clocks.t500khz;
    slv(8)  := clocks.t250khz;
    slv(9)  := clocks.t125khz;
    slv(10) := clocks.t62ppms;
    slv(11) := clocks.t31ppms;
    slv(12) := clocks.t16ppms;
    slv(13) := clocks.t8ppms;
    slv(14) := clocks.t4ppms;
    slv(15) := clocks.t2ppms;
    slv(16) := clocks.t1ppms;
    slv(17) := clocks.clkt_1mhz_ub;
    return slv;
  end;
  ------------------------------------------------------------

  ------------------------------------------------------------
  -- SLV_TO_********
  function slv_to_clocks(slv : std_logic_vector) return clocks_t is
    variable clocks : clocks_t;
  begin
    clocks.vco_16m      := slv(0);
    clocks.clkb_8mhz    := slv(1);
    clocks.clkb_4mhz    := slv(2);
    clocks.clkb_2mhz    := slv(3);
    clocks.clkt_1mhz    := slv(4);
    clocks.clkd_1mhz    := slv(5);
    clocks.clkq_1mhz    := slv(6);
    clocks.t500khz      := slv(7);
    clocks.t250khz      := slv(8);
    clocks.t125khz      := slv(9);
    clocks.t62ppms      := slv(10);
    clocks.t31ppms      := slv(11);
    clocks.t16ppms      := slv(12);
    clocks.t8ppms       := slv(13);
    clocks.t4ppms       := slv(14);
    clocks.t2ppms       := slv(15);
    clocks.t1ppms       := slv(16);
    clocks.clkt_1mhz_ub := slv(17);
    return clocks;
  end;
  ------------------------------------------------------------

end package body;


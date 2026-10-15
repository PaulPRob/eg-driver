-------------------------------------------------------------------------------
-- (c) Copyright - Commonwealth Scientific and Industrial Research Organisation
-- (CSIRO) - 2026
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
-- File Name: vcxo_clk.vhd
-- Type: RTL
--
-- Title: VCXO Clock Input
--
-- Description: ATNF MOD FOR EG
--
-- Buffers the VCXO and delivers the 16 MHz clock that the rest of the EG is
-- built around: clocks_gen divides it by 16 for the 1 MHz CLKT that
-- pll_pump phase locks to BAT through the VCXO.
--
--   VCXO_MHZ = 16   The VCXO clock is used directly (IBUFG - BUFIO2 - BUFG),
--                   exactly as before this module existed.  locked is '1'.
--
--   otherwise       A PLL_BASE makes 16 MHz from the VCXO:
--                     VCO   = VCXO_MHZ * (800 / VCXO_MHZ) = 800 MHz
--                     CLKOUT0 = 800 MHz / 50 = 16 MHz
--                   so VCXO_MHZ must divide 800 and be at least 19 (the
--                   PLL's minimum input frequency), e.g. 20, 25, 32, 40, 50.
--                   The 16 MHz output is frequency locked to the VCXO, so the
--                   BAT loop still steers the VCXO through UP/DOWN.
--
--                   locked follows the PLL LOCKED output.  eg_clk_reset
--                   holds clocks_gen in reset while it is low.
--
--                   A Spartan-6 PLL has to be reset after it loses lock (for
--                   example when the VCXO stops or its supply is cycled); it
--                   does not reacquire on its own.  A watchdog clocked by
--                   bclk pulses RST if LOCKED stays low for 2^16 bclk cycles
--                   (1.05 ms at 62.5 MHz), and keeps doing so until the PLL
--                   locks.  bclk is the PCIe user clock, which stops while
--                   PERST# is asserted, so the watchdog runs whenever the
--                   host is out of reset.
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;

entity vcxo_clk is
  generic (
    VCXO_MHZ : integer := 16
    );
  port (
    vco_in  : in  std_logic;            -- VCXO pin
    bclk    : in  std_logic;            -- PCIe user clock, for the watchdog
    vco_16m : out std_logic;            -- 16 MHz, on a global buffer
    locked  : out std_logic
    );
end vcxo_clk;

architecture structure of vcxo_clk is

  constant PLL_VCO_MHZ : integer := 800;

  signal sig_vco_ibufg : std_logic;
  signal sig_pll_rst   : std_logic := '0';  -- used only by gen_pll

begin

  vco_ibufg : IBUFG
    generic map (
      IBUF_LOW_PWR => TRUE,
      IOSTANDARD   => "DEFAULT")
    port map (
      O => sig_vco_ibufg,
      I => vco_in
      );

  -----------------------------------------------------------
  -- 16 MHz VCXO: use it directly --
  -----------------------------------------------------------
  gen_direct : if VCXO_MHZ = 16 generate
    signal sig_vco_bufio2 : std_logic;
  begin

    vco_bufio2 : BUFIO2
      generic map (
        DIVIDE        => 1,
        DIVIDE_BYPASS => TRUE,
        I_INVERT      => FALSE,
        USE_DOUBLER   => FALSE
        )
      port map (
        DIVCLK       => sig_vco_bufio2,
        IOCLK        => open,
        SERDESSTROBE => open,
        I            => sig_vco_ibufg
        );

    vco_bufg : BUFG
      port map (
        O => vco_16m,
        I => sig_vco_bufio2
        );

    locked <= '1';

  end generate;

  -----------------------------------------------------------
  -- Any other VCXO: synthesise 16 MHz with a PLL --
  -----------------------------------------------------------
  gen_pll : if VCXO_MHZ /= 16 generate
    signal sig_clkfb       : std_logic;
    signal sig_clkout0     : std_logic;
    signal sig_pll_locked  : std_logic;
    signal sig_locked_meta : std_logic := '0';
    signal sig_locked_sync : std_logic := '0';
    signal sig_wd_count    : unsigned(15 downto 0) := (others => '0');
  begin

    assert VCXO_MHZ >= 19 and PLL_VCO_MHZ mod VCXO_MHZ = 0
      and PLL_VCO_MHZ / VCXO_MHZ <= 64
      report "vcxo_clk: VCXO_MHZ must be 16, or divide 800 and be 19 or more"
      severity failure;

    vco_pll : PLL_BASE
      generic map (
        BANDWIDTH      => "OPTIMIZED",
        CLK_FEEDBACK   => "CLKFBOUT",
        COMPENSATION   => "INTERNAL",
        DIVCLK_DIVIDE  => 1,
        CLKFBOUT_MULT  => PLL_VCO_MHZ / VCXO_MHZ,
        CLKFBOUT_PHASE => 0.0,
        CLKIN_PERIOD   => 1000.0 / real(VCXO_MHZ),
        CLKOUT0_DIVIDE => PLL_VCO_MHZ / 16,
        CLKOUT0_PHASE  => 0.0
        )
      port map (
        CLKIN    => sig_vco_ibufg,
        CLKFBIN  => sig_clkfb,
        RST      => sig_pll_rst,
        CLKFBOUT => sig_clkfb,
        CLKOUT0  => sig_clkout0,
        CLKOUT1  => open,
        CLKOUT2  => open,
        CLKOUT3  => open,
        CLKOUT4  => open,
        CLKOUT5  => open,
        LOCKED   => sig_pll_locked
        );

    vco_bufg : BUFG
      port map (
        O => vco_16m,
        I => sig_clkout0
        );

    -- Reset the PLL if it has been out of lock for 2^16 bclk cycles.  RST is
    -- held for the last 16 counts, then the count wraps and waits again.
    process(bclk)
    begin
      if rising_edge(bclk) then
        sig_locked_meta <= sig_pll_locked;
        sig_locked_sync <= sig_locked_meta;

        if sig_locked_sync = '1' then
          sig_wd_count <= (others => '0');
          sig_pll_rst  <= '0';
        else
          sig_wd_count <= sig_wd_count + 1;
          if sig_wd_count(15 downto 4) = (15 downto 4 => '1') then
            sig_pll_rst <= '1';
          else
            sig_pll_rst <= '0';
          end if;
        end if;
      end if;
    end process;

    locked <= sig_pll_locked;

  end generate;

end structure;

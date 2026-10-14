-- Simulation-only stand-in for ipcore_dir/eg_ref_fifo (FIFO Generator v5.3).
--
-- The real core is FIFO Generator v5.3 from ISE 11.4, whose behavioural model
-- lives in XilinxCoreLib, which Vivado does not ship.  This entity has the
-- same ports and maps the same parameter values (taken from
-- ipcore_dir/eg_ref_fifo.vhd) onto the FIFO Generator v13.0 behavioural model
-- that Vivado does ship.  Flag timing and depth follow the same rules in both
-- versions for this configuration (independent clocks, block RAM, FWFT), but
-- this is a model of the core, not the core: reset behaviour in particular is
-- v13's, not v5.3's.
--
-- Generated from ipcore_dir/eg_ref_fifo.vhd.  Parameters with no v13
-- equivalent and not mapped: none.
library ieee;
use ieee.std_logic_1164.all;

library fifo_generator_v13_0_7;

entity eg_ref_fifo is
  port (
    rst       : in  std_logic;
    wr_clk    : in  std_logic;
    rd_clk    : in  std_logic;
    din       : in  std_logic_vector(63 downto 0);
    wr_en     : in  std_logic;
    rd_en     : in  std_logic;
    dout      : out std_logic_vector(63 downto 0);
    full      : out std_logic;
    empty     : out std_logic;
    prog_full : out std_logic);
end entity;

architecture sim of eg_ref_fifo is
begin
  fifo : entity fifo_generator_v13_0_7.fifo_generator_v13_0_7_conv
    generic map (
      C_HAS_INT_CLK                   => 0,
      C_WR_RESPONSE_LATENCY           => 1,
      C_RD_FREQ                       => 1,
      C_HAS_SRST                      => 0,
      C_ENABLE_RST_SYNC               => 1,
      C_HAS_RD_DATA_COUNT             => 0,
      C_DIN_WIDTH                     => 64,
      C_HAS_WR_DATA_COUNT             => 0,
      C_FULL_FLAGS_RST_VAL            => 1,
      C_IMPLEMENTATION_TYPE           => 2,
      C_FAMILY                        => "spartan6",
      C_USE_EMBEDDED_REG              => 0,
      C_HAS_WR_RST                    => 0,
      C_WR_FREQ                       => 1,
      C_USE_DOUT_RST                  => 1,
      C_UNDERFLOW_LOW                 => 0,
      C_HAS_MEMINIT_FILE              => 0,
      C_HAS_OVERFLOW                  => 0,
      C_PRELOAD_LATENCY               => 0,
      C_DOUT_WIDTH                    => 64,
      C_MSGON_VAL                     => 1,
      C_RD_DEPTH                      => 1024,
      C_DEFAULT_VALUE                 => "BlankString",
      C_MIF_FILE_NAME                 => "BlankString",
      C_ERROR_INJECTION_TYPE          => 0,
      C_HAS_UNDERFLOW                 => 0,
      C_HAS_RD_RST                    => 0,
      C_HAS_ALMOST_FULL               => 0,
      C_HAS_RST                       => 1,
      C_DATA_COUNT_WIDTH              => 10,
      C_HAS_WR_ACK                    => 0,
      C_USE_ECC                       => 0,
      C_WR_ACK_LOW                    => 0,
      C_COMMON_CLOCK                  => 0,
      C_RD_PNTR_WIDTH                 => 10,
      C_USE_FWFT_DATA_COUNT           => 0,
      C_HAS_ALMOST_EMPTY              => 0,
      C_RD_DATA_COUNT_WIDTH           => 10,
      C_ENABLE_RLOCS                  => 0,
      C_WR_PNTR_WIDTH                 => 10,
      C_OVERFLOW_LOW                  => 0,
      C_PROG_EMPTY_TYPE               => 0,
      C_OPTIMIZATION_MODE             => 0,
      C_WR_DATA_COUNT_WIDTH           => 10,
      C_PRELOAD_REGS                  => 1,
      C_DOUT_RST_VAL                  => "0",
      C_HAS_DATA_COUNT                => 0,
      C_PROG_FULL_THRESH_NEGATE_VAL   => 511,
      C_WR_DEPTH                      => 1024,
      C_PROG_EMPTY_THRESH_NEGATE_VAL  => 5,
      C_PROG_EMPTY_THRESH_ASSERT_VAL  => 4,
      C_HAS_VALID                     => 0,
      C_INIT_WR_PNTR_VAL              => 0,
      C_PROG_FULL_THRESH_ASSERT_VAL   => 512,
      C_USE_FIFO16_FLAGS              => 0,
      C_HAS_BACKUP                    => 0,
      C_VALID_LOW                     => 0,
      C_PRIM_FIFO_TYPE                => "1kx36",
      C_COUNT_TYPE                    => 0,
      C_PROG_FULL_TYPE                => 2,
      C_MEMORY_TYPE                   => 1,
      C_EN_SAFETY_CKT                 => 0,
      C_INTERFACE_TYPE                => 0)
    port map (
      rst => rst, wr_clk => wr_clk, rd_clk => rd_clk,
      din => din, wr_en => wr_en, rd_en => rd_en,
      dout => dout, full => full, empty => empty, prog_full => prog_full);
end architecture;

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
-- File Name: aync_fifo.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Async FIFO
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

entity async_fifo is
  generic (                             -- Constraints
    constant width          : integer := 8;   --
    constant depth          : integer := 16;  -- depth >= 16
    constant address_length : integer := 4  -- address_length == ceil(log(depth)/log(2)) &&
                                            -- address_length % 2 == 0
    );
port (
    wclk : in std_logic;
    we   : in std_logic;
    wd   : in std_logic_vector(width-1 downto 0);

    rclk : in  std_logic;
    re   : in  std_logic;
    rd   : out std_logic_vector(width-1 downto 0);

    rst : in std_logic;

    empty : out std_logic;
    low   : out std_logic;
    half  : out std_logic;
    high  : out std_logic;
    full  : out std_logic

 );
end entity;

architecture structure of async_fifo is
  signal wa_binary : std_logic_vector(address_length-1 downto 0);
  signal wa_gray   : std_logic_vector(address_length-1 downto 0);
  signal ra_binary : std_logic_vector(address_length-1 downto 0);
  signal ra_gray   : std_logic_vector(address_length-1 downto 0);

  type direction_t is (nearly_empty, nearly_full);
  signal direction : direction_t;

  type ram_t is array (0 to depth-1) of std_logic_vector (width-1 downto 0);
  signal ram : ram_t;

  signal sig_empty : std_logic;
  signal sig_low   : std_logic;
  signal sig_half  : std_logic;
  signal sig_high  : std_logic;
  signal sig_full  : std_logic;
  
begin

  ram_port_map_block : block is
    signal wa_binary_integer : integer range 0 to depth-1;
    signal ra_binary_integer : integer range 0 to depth-1;
  begin
    wa_binary_integer <= to_integer(unsigned(wa_binary));
    ra_binary_integer <= to_integer(unsigned(ra_binary));

    ram_port_map : entity work.ram
      generic map (
        width => width,
        depth => depth
        )
      port map (
        clk => wclk,

        address => wa_binary_integer,
        din_en  => we,
        din     => wd,
        -- dout => ,

        dual_address => ra_binary_integer,
        dual_dout    => rd
        );
  end block;

  wa_port_map : entity work.gray_counter
    generic map (
      bits => address_length
      )
    port map (
      clk => wclk,
      rst => rst,
      en  => we,

      binary => wa_binary,
      gray   => wa_gray
      );

  ra_port_map : entity work.gray_counter
    generic map (
      bits => address_length
      )
    port map (
      clk => rclk,
      rst => rst,
      en  => re,

      binary => ra_binary,
      gray   => ra_gray
      );

  direction_block : block is
    signal ra_quadrant : std_logic_vector(1 downto 0);
    signal wa_quadrant : std_logic_vector(1 downto 0);
  begin
    wa_quadrant <= wa_gray(address_length-1 downto address_length-2);
    ra_quadrant <= ra_gray(address_length-1 downto address_length-2);

    -- gray code
    -- 00
    -- 01
    -- 11
    -- 10
    direction <= nearly_empty
                 when rst = '1'
                 or (ra_quadrant = "00" and wa_quadrant = "01")
                 or (ra_quadrant = "01" and wa_quadrant = "11")
                 or (ra_quadrant = "11" and wa_quadrant = "10")
                 or (ra_quadrant = "10" and wa_quadrant = "00")
                 else nearly_full
                 when (wa_quadrant = "00" and ra_quadrant = "01")
                 or (wa_quadrant = "01" and ra_quadrant = "11")
                 or (wa_quadrant = "11" and ra_quadrant = "10")
                 or (wa_quadrant = "10" and ra_quadrant = "00") else
                 direction;

    -- 'sig_half' can only become true after a read or write.
    -- Therefore 'sig_half' becomes asynchronous to rclk when writes are taking place.
    -- Similarly 'sig_half' becomes asynchronous to wclk when reads are taking place.
    sig_half <= '1' when (ra_gray(address_length-3 downto 0) =
                          wa_gray(address_length-3 downto 0)) and
                (ra_quadrant = not wa_quadrant) else '0';

    -- The following two status bits are unique in that they can be true over a range of values.
    -- If the FIFO is less than one quarter full: sig_low==1 and sig_high==0.
    -- If the FIFO is more than three quarter full: sig_low==0 and sig_high==1.
    -- If the FIFO is between one and three quarters full,
    -- the values of 'sig_low' and 'sig_high' will not change (latched).
    sig_low  <= '1' when direction = nearly_empty else '0';
    sig_high <= '1' when direction = nearly_full  else '0';
    
  end block;

  -- 'empty' can only become true after a read.
  process(rclk, wa_gray, ra_gray, direction)
  begin
    if wa_gray = ra_gray and direction = nearly_empty then
      sig_empty <= '1';
    elsif rising_edge(rclk) then
      if wa_gray = ra_gray and direction = nearly_empty then
        sig_empty <= '1';
      else
        sig_empty <= '0';
      end if;
    end if;
  end process;

  -- 'full' can only become true after a write.
  process(wclk, wa_gray, ra_gray, direction)
  begin
    if wa_gray = ra_gray and direction = nearly_full then
      sig_full <= '1';
    elsif rising_edge(wclk) then
      if wa_gray = ra_gray and direction = nearly_full then
        sig_full <= '1';
      else
        sig_full <= '0';
      end if;
    end if;
  end process;

  empty <= sig_empty;
  low   <= sig_low;
  half  <= sig_half;
  high  <= sig_high;
  full  <= sig_full;
  
end architecture;


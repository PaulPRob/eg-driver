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
-- File Name: frame_gen.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Frame Generator
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
use work.pci_package.all;



entity frame_gen is port (
  
  bat_serial     : in std_logic;
  bclk           : in std_logic;
  clocks         : in std_logic_vector(17 downto 0);
  master_control : in std_logic_vector(8 downto 0);

  clkdata : out std_logic;
  x1sec   : out std_logic;
  xfs     : out std_logic;

  bat_slv : out std_logic_vector(47 downto 0);

  frame_loaded : out std_logic;
  false_sync   : out std_logic;
  missed_sync  : out std_logic;
  bad_checksum : out std_logic;

  frame_fifo_empty : out std_logic;
  frame_fifo_full  : out std_logic;

  frame_byte_load : in  std_logic;
  frame_byte      : out std_logic_vector(7 downto 0)

);
end entity;

architecture structure of frame_gen is

  -- Inputs
  signal sig_clocks         : clocks_t;
  signal sig_master_control : master_control_t;

  -- Control signals used to read data from bat_serial.
  signal sig_ones          : integer range 0 to 40;
  signal sig_clkdata_count : integer range 0 to 1002;
  signal sig_clkdata       : std_logic;
  signal sig_pre_x1sec     : std_logic;
  signal sig_x1sec         : std_logic;
  signal sig_word_count    : integer range 0 to 58;
  signal sig_bit_count     : integer range 0 to 17;

  signal sig_end_frame     : std_logic;
  signal sig_loading_frame : std_logic;
  signal sig_checksum      : std_logic_vector(15 downto 0);
  signal sig_frame_loaded  : std_logic;
  signal sig_bad_checksum  : std_logic;

  -- Storage for the data read from bat_serial.
  signal sig_bat_buffer : unsigned(47 downto 0);
  signal bat            : unsigned(47 downto 0);
  signal sig_byte       : std_logic_vector(7 downto 0);
  signal sig_push_byte  : std_logic;
  
begin

  sig_clocks         <= slv_to_clocks(clocks);
  sig_master_control <= slv_to_master_control(master_control);

  frame_fifo : entity work.async_fifo
    generic map (
      width          => 8,
      depth          => 112,
      address_length => 7
      )
    port map (
      wclk => sig_clocks.clkt_1mhz,
      we   => sig_push_byte,
      wd   => sig_byte,

      rclk => bclk,
      re   => frame_byte_load,
      rd   => frame_byte,

      rst => sig_master_control.grab_frame,

      empty => frame_fifo_empty,
      low   => open,
      half  => open,
      high  => open,
      full  => frame_fifo_full


      );


  process(sig_clocks.clkt_1mhz)
  begin
    if falling_edge(sig_clocks.clkt_1mhz) then

      -- Determine clkdata.
      sig_clkdata <= bat_serial;

      -- Determine ones.
      if bat_serial = '1' then
        if sig_ones < 40 then
          sig_ones <= sig_ones + 1;
        end if;
      else
        sig_ones <= 0;
      end if;

      -- Determine end_frame.
      if bat_serial = '0' and sig_ones >= 24 then
        sig_end_frame <= '1';
      else
        sig_end_frame <= '0';
      end if;

      -- Determine xfs.
      if sig_end_frame = '1' then
        xfs <= '1';
      else
        xfs <= '0';
      end if;

      -- Determine pre_x1sec.
      if bat_serial = '0' and sig_ones >= 40 then
        sig_pre_x1sec <= '1';
      else
        sig_pre_x1sec <= '0';
      end if;

      -- Determine x1sec.
      if sig_pre_x1sec = '1' then
        sig_x1sec <= '1';
      elsif sig_clkdata_count = 0 then
        sig_x1sec <= '0';
      end if;

    end if;
  end process;


  process(sig_clocks.clkt_1mhz)
  begin
    if rising_edge(sig_clocks.clkt_1mhz) then

      -- Perform checksum.
      if sig_end_frame = '1' then
        sig_checksum <= "11111111" & "11111111";
      else
        if sig_clkdata_count <= 951 then
          sig_checksum <= (sig_checksum(14) xor (sig_clkdata xor sig_checksum(15)))  -- 15
                          & sig_checksum(13)                     -- 14
                          & sig_checksum(12)                     -- 13
                          & sig_checksum(11)                     -- 12
                          & sig_checksum(10)                     -- 11
                          & sig_checksum(9)                      -- 10
                          & sig_checksum(8)                      --  9
                          & sig_checksum(7)                      --  8
                          & sig_checksum(6)                      --  7
                          & sig_checksum(5)                      --  6
                          & sig_checksum(4)                      --  5
                          & sig_checksum(3)                      --  4
                          & sig_checksum(2)                      --  3
                          & (sig_checksum(1) xor (sig_clkdata xor sig_checksum(15)))  --  2
                          & sig_checksum(0)                      --  1
                          & (sig_clkdata xor sig_checksum(15));  --  0
        elsif sig_clkdata_count = 952 then
          if sig_checksum = "00000000" & "00000000" then
            sig_bad_checksum <= '0';
          else
            sig_bad_checksum <= '1';
          end if;
        end if;
      end if;

      -- Discard every 17th bit. Only use bits 0 to 15.
      if sig_end_frame = '1' then
        sig_bit_count  <= 0;
        sig_word_count <= 0;
      else
        if sig_bit_count = 16 then
          sig_bit_count  <= 0;
          sig_word_count <= sig_word_count + 1;
        else
          sig_bit_count <= sig_bit_count + 1;
        end if;
      end if;

      -- Store incoming bat bits in a buffer.
      if sig_word_count <= 2 and sig_bit_count <= 15 then
        sig_bat_buffer(47)          <= sig_clkdata;
        sig_bat_buffer(46 downto 0) <= sig_bat_buffer(47 downto 1);
      end if;

      -- Store frame bytes in the fifo.
      -- Frame consists of 56, 16 bit words. Each word is followed by a '0'.
      sig_push_byte     <= '0';
      if sig_word_count <= 55 and sig_loading_frame = '1' then

        -- Load sig_clkdata into byte buffer.
        if sig_bit_count <= 15 then
          sig_byte(7)          <= sig_clkdata;
          sig_byte(6 downto 0) <= sig_byte(7 downto 1);
        end if;

        -- If the byte buffer is full, write it to the fifo.                  
        if sig_bit_count = 7 or sig_bit_count = 15 then
          sig_push_byte <= '1';
        end if;
      end if;

      -- Determine whether we need to begin a frame loading sequence now,
      -- at the start of the next frame or not at all.
      if sig_end_frame = '1' then
        if sig_master_control.grab_frame = '1' or sig_frame_loaded = '0' then
          sig_loading_frame <= '1';
          sig_frame_loaded  <= '0';
        end if;
      else
        if sig_master_control.grab_frame = '1' then
          sig_loading_frame <= '0';
          sig_frame_loaded  <= '0';
        end if;
      end if;

      -- Determine whether to finish the current (if any) frame loading sequence.
      -- Determine the bat.
      if sig_end_frame = '1' then
        sig_clkdata_count <= 0;

        false_sync  <= '0';
        missed_sync <= '0';
        if sig_clkdata_count < 997 then
          false_sync <= '1';
        elsif sig_clkdata_count >= 1002 then
          missed_sync <= '1';
        else
          if sig_bad_checksum = '0' then
            bat <= sig_bat_buffer;
            if sig_loading_frame = '1' then
              sig_loading_frame <= '0';
              sig_frame_loaded  <= '1';
            end if;
          else
            bat <= bat + 1;
          end if;
        end if;
      else
        if sig_clkdata_count < 1002 then
          sig_clkdata_count <= sig_clkdata_count + 1;
        end if;

        bat <= bat + 1;
      end if;

    end if;
  end process;


  bat_slv      <= std_logic_vector(bat);
  clkdata      <= sig_clkdata;
  x1sec        <= sig_x1sec;
  frame_loaded <= sig_frame_loaded;
  bad_checksum <= sig_bad_checksum;

end architecture;


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
-- File Name: event_gen.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: Event Generator 
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


entity event_gen is

 port (
    bclk                 : in std_logic;
    clocks               : in std_logic_vector(17 downto 0);
    bat                  : in std_logic_vector(47 downto 0);
    master_control       : in std_logic_vector(8 downto 0);
    event_output_control : in std_logic_vector(12 downto 0);

    async_event_write      : in event_t;
    async_event_write_load : in std_logic;

    ls_sync_event      : in std_logic_vector(7 downto 0);
    ls_sync_event_load : in std_logic;
    ms_sync_event      : in std_logic_vector(7 downto 0);
    ms_sync_event_load : in std_logic;

    event_output_status : out    std_logic_vector(1 downto 0);
    internal_interrupt  : out    std_logic;
    event_out           : out    std_logic_vector(15 downto 0);
    event_strobe        : out    std_logic;

    running           : out    std_logic;
    
	 late_event        : out    std_logic;
    
	 ls_ref_fifo_empty : out std_logic;
    ms_ref_fifo_empty : out std_logic;
    ls_ref_fifo_half  : out std_logic;
    ms_ref_fifo_half  : out std_logic;
    ls_ref_fifo_full  : out std_logic;
    ms_ref_fifo_full  : out std_logic
 );
 end entity;

architecture structure of event_gen is
   
  component eg_ref_fifo
	port (
		rst: in std_logic;
		wr_clk: in std_logic;
		rd_clk: in std_logic;
		din: in std_logic_vector(63 downto 0);
		wr_en: in std_logic;
		rd_en: in std_logic;
		dout: out std_logic_vector(63 downto 0);
		full: out std_logic;
		empty: out std_logic;
		prog_full: out std_logic);
  end component;
 
  attribute syn_black_box : boolean;
  attribute syn_black_box of eg_ref_fifo: component is true;

  signal clocks_local               : clocks_t;
  signal master_control_local       : master_control_t;
  signal event_output_control_local : event_output_control_t;

  signal ref_fifo_pop  : std_logic;
  signal sig_conv_ref_fifo_dout : synchronous_event_t;

  signal next_event       : synchronous_event_t;
  
  type tense_t is (past, present, future);
  signal next_event_tense : tense_t;

  signal write_event_out : std_logic;

  signal event_output_status_local : event_output_status_t;

  signal sig_running : std_logic;

  signal sig_event_out : std_logic_vector(15 downto 0);

  signal sig_ref_fifo_empty : std_logic;
  signal sig_ref_fifo_half  : std_logic;
  signal sig_ref_fifo_full  : std_logic;
  
  signal ls_byte_count : unsigned(1 downto 0);
  signal ls_buffer     : std_logic_vector(23 downto 0);
  signal ms_byte_count : unsigned(1 downto 0);
  signal ms_buffer     : std_logic_vector(23 downto 0);

  signal sig_ref_fifo_din : std_logic_vector(63 downto 0);
  signal sig_ref_fifo_push : std_logic;
  
  signal sig_ref_fifo_dout : std_logic_vector(63 downto 0);
	
  signal sig_fifo_dout_slv : std_logic_vector(63 downto 0);
 
begin
 
 Inst_eg_ref_fifo : eg_ref_fifo
 port map (
		rst => master_control_local.reset_ref_fifo,
		wr_clk => bclk,
		rd_clk => clocks_local.clkt_1mhz,
		din => sig_ref_fifo_din,
		wr_en => sig_ref_fifo_push,
		rd_en => ref_fifo_pop,
		dout => sig_ref_fifo_dout,
		full => sig_ref_fifo_full,
		empty => sig_ref_fifo_empty,
		prog_full => sig_ref_fifo_half
		);

	---------------------------------------------------------------------------------
	-- Concurrent Signal Assignments --
	---------------------------------------------------------------------------------

  clocks_local               <= slv_to_clocks(clocks);
  master_control_local       <= slv_to_master_control(master_control);
  event_output_control_local <= slv_to_event_output_control(event_output_control);

  sig_ref_fifo_din(31 downto 0) <= ls_buffer & ls_sync_event;
  sig_ref_fifo_din(63 downto 32) <= ms_buffer & ms_sync_event;

  sig_ref_fifo_push <= '1' when ls_sync_event_load = '1' and ls_byte_count = 3 and 
									ms_sync_event_load = '1' and ms_byte_count = 3 else '0';
  
  
  -- Host PC writes words in the following order: LS time, Middle time, MS time, event.
  -- The std_logic_vector(63 downto 0) to synchronous_event_t conversion function is
  -- defined in pci_package.vhd.
  -- It expects the words in the following order (MS word downto LS word): Event,
  -- MS time, Middle time, LS time.
  sig_fifo_dout_slv <= sig_ref_fifo_dout(39 downto 32) & sig_ref_fifo_dout(7 downto 0)
                     & sig_ref_fifo_dout(47 downto 40) & sig_ref_fifo_dout(15 downto 8)
                     & sig_ref_fifo_dout(55 downto 48) & sig_ref_fifo_dout(23 downto 16)
                     & sig_ref_fifo_dout(63 downto 56) & sig_ref_fifo_dout(31 downto 24);
  sig_conv_ref_fifo_dout <= slv_to_synchronous_event(sig_fifo_dout_slv);
 
  write_event_out <= '1' when
                     (sig_running = '1' and
                      (next_event_tense = present or next_event_tense = past or
                       master_control_local.purge_event = '1'))
                     or async_event_write_load = '1'
                     else '0';
  
  ref_fifo_pop <= '1' when
                  sig_ref_fifo_empty = '0' and
                  (sig_running = '0' or write_event_out = '1') else '0';
 
  
  event_output_status_local.timed_interrupt_event_line <=
    sig_event_out(to_integer(unsigned(event_output_control_local.timed_interrupt_event_line_select)))
    when event_output_control_local.timed_interrupt_event_line_enable = '1'
    else '0';

  event_output_status_local.waveform_generator_event_line <=
    sig_event_out(to_integer(unsigned(event_output_control_local.waveform_generator_event_line_select)))
    when event_output_control_local.waveform_generator_event_line_enable = '1'
    else '0';

  internal_interrupt  <= event_output_status_local.timed_interrupt_event_line;
  event_output_status <= event_output_status_to_slv(event_output_status_local);

  event_out <= sig_event_out;
  
  ls_ref_fifo_empty <= sig_ref_fifo_empty;
  ms_ref_fifo_empty <= sig_ref_fifo_empty;
  ls_ref_fifo_half <= sig_ref_fifo_half;
  ms_ref_fifo_half <= sig_ref_fifo_half;
  ls_ref_fifo_full <= sig_ref_fifo_full;
  ms_ref_fifo_full <= sig_ref_fifo_full;
  
  running <= sig_running;

-------------------------------------------------------------------------------

process(bclk)
    begin
      if rising_edge(bclk) then
        if master_control_local.reset_ref_fifo = '1' then
          ls_byte_count <= to_unsigned(0, ls_byte_count'length);
          ms_byte_count <= to_unsigned(0, ms_byte_count'length);
        else
          if ls_sync_event_load = '1' then
            ls_byte_count <= ls_byte_count + 1;
            ls_buffer     <= ls_buffer(15 downto 0) & ls_sync_event;
          end if;
          if ms_sync_event_load = '1' then
            ms_byte_count <= ms_byte_count + 1;
            ms_buffer     <= ms_buffer(15 downto 0) & ms_sync_event;
          end if;
        end if;
      end if;
 end process;


-------------------------------------------------------------------------------
   
 process(bat, next_event.bat)
  begin
    if (bat(47 downto 46) = "00" or bat(47 downto 46) = "11") then
      -- Signed comparison.
      if signed(std_logic_vector(bat)) < signed(std_logic_vector(next_event.bat)) then
        next_event_tense <= future;
      elsif signed(std_logic_vector(bat)) = signed(std_logic_vector(next_event.bat)) then
        next_event_tense <= present;
      else
        next_event_tense <= past;
      end if;
    else
      -- Unsigned comparison.
      if bat < next_event.bat then
        next_event_tense <= future;
      elsif bat = next_event.bat then
        next_event_tense <= present;
      else
        next_event_tense <= past;
      end if;
    end if;
 end process;

-------------------------------------------------------------------------------
  
  process(clocks_local.clkt_1mhz)
  begin
    if rising_edge(clocks_local.clkt_1mhz) then

      if ref_fifo_pop = '1' then
        next_event <= sig_conv_ref_fifo_dout;
      end if;

      if ref_fifo_pop = '1' or (sig_running = '1' and write_event_out = '0') then
        sig_running <= '1';
      else
        sig_running <= '0';
      end if;

      -- ERD 8/6/05
      if sig_running = '1' and next_event_tense = past then
        late_event <= '1';
      else late_event <= '0';
      end if;
      -- end ERD
      

    end if;
  end process;


-------------------------------------------------------------------------------
  
  process(clocks_local.vco_16m, clocks_local.clkt_1mhz_ub, clocks_local.clkb_2mhz,
          clocks_local.clkb_4mhz, clocks_local.clkb_8mhz)
    variable vco_count : unsigned(3 downto 0);
  begin
    vco_count := clocks_local.clkt_1mhz_ub & clocks_local.clkb_2mhz &
                 clocks_local.clkb_4mhz & clocks_local.clkb_8mhz;

    --  TESU Event Setup (192 before rising_edge(CLKT))
    if rising_edge(clocks_local.vco_16m) and vco_count = 4 then
      if write_event_out = '1' then
        if async_event_write_load = '1' then
          sig_event_out <= async_event_write;
        else
          sig_event_out <= next_event.event;
        end if;
      end if;
    end if;
  end process;

-------------------------------------------------------------------------------

 process(clocks_local.vco_16m, clocks_local.clkt_1mhz_ub, clocks_local.clkb_2mhz,
          clocks_local.clkb_4mhz, clocks_local.clkb_8mhz)
    variable vco_count : unsigned(3 downto 0);
  begin
    vco_count := clocks_local.clkt_1mhz_ub & clocks_local.clkb_2mhz &
                 clocks_local.clkb_4mhz & clocks_local.clkb_8mhz;
    if rising_edge(clocks_local.vco_16m) then

      -- rising_edge(CLKT)
      if vco_count = 7 and
        (write_event_out = '1' or event_output_control_local.free_run_event_strobe = '1') then
        event_strobe <= '1';

      -- falling_edge(CLKQ)
      elsif vco_count = 11 then
        event_strobe <= '0';
      end if;
    end if;
 end process;


end architecture;

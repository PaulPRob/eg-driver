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
-- File Name:    onewire_core.vhd
-- Type:         RTL
-- Designer: 
-- Created:      10:29:30 14/06/2006 
-- Template Rev: 0.1
--
-- Title:        Onewire Physical interface
--
-- Description:  Main state machine for drivinga one wire bus, can issue reset 
--               pulse and read and write data. The design will work for any 
--               1-wire device
--
-------------------------------------------------------------------------------

library ieee;
library unisim;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.utils_pkg.all;
use unisim.vcomponents.all;

entity onewire_core is
  generic (
    con_input_clk : integer := 31;      -- Input clock frequency in MHz
    con_tslot     : integer := 70;      -- Time slot duration, for reads and writes, TW0L+TREC (us) 
    con_tmsr      : integer := 10;      -- Read window sample time (us)
    con_trl       : integer := 6;       -- Read low time (us)
    con_tw0l      : integer := 65;      -- Write 0 low time (us)
    con_tw1l      : integer := 10;      -- Write 1 low time (us)
    con_trsth     : integer := 500;     -- Reset recovery time (us)
    con_trstl     : integer := 500;     -- Reset low time (us)
    con_tmsp      : integer := 65);     -- Presence detect sample time (us)
  port(
    clk   : in std_logic;               -- Main clock signal
    reset : in std_logic;               -- Main reset

    go      : in  std_logic;            -- Start signal, rising edge to go
    running : out std_logic;            -- Running signal            

    sel : in std_logic_vector(1 downto 0);  -- Type of operation: 00 Issue presence pulse
                                            --                    01 Write a 8 bit word
                                            --                    10 Read an 8 bit word

    data_i   : in  std_logic_vector(7 downto 0);  -- Write data
    data_o   : out std_logic_vector(7 downto 0);  -- Read data
    presence : out std_logic;                     -- Output of reset pulse

    -- CRC Signals
    crc8      : out std_logic_vector(7 downto 0);
    crc16     : out std_logic_vector(15 downto 0);
    crc_reset : in  std_logic;          -- Reset the CRC to 0's


    onewire_oe : out std_logic;         -- Data Trisate enable (active low)
    onewire_o  : out std_logic;         -- Data output
    onewire_i  : in  std_logic);        -- Data input

end onewire_core;

architecture brains of onewire_core is

------------------------------------------- TYPES -----------------------------------------------

  type fsm_states is (s_idle,
                      s_reset_pulse, s_reset_pulse_wait, s_reset_pulse_sample, s_reset_pulse_recovery,
                      s_write_data, s_write_data_wait, s_write_data_shift, s_write_data_recovery,
                      s_read_data, s_read_data_wait, s_read_data_sample, s_read_data_recovery,
                      s_finished);

----------------------------------------- CONSTANTS ---------------------------------------------

  -- The width of the counter, in bits, used to divide down the clock
  constant con_counter_width : integer := ceil_log2(con_trsth*con_input_clk);  -- Pick the largest time constant to determine the width of the counter

  -- Clock generator constants
  constant con_tslot_cnt : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_tslot*con_input_clk, con_counter_width);
  constant con_tmsr_cnt  : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_tmsr*con_input_clk, con_counter_width);
  constant con_trl_cnt   : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_trl*con_input_clk, con_counter_width);
  constant con_tw0l_cnt  : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_tw0l*con_input_clk, con_counter_width);
  constant con_tw1l_cnt  : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_tw1l*con_input_clk, con_counter_width);
  constant con_trsth_cnt : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_trsth*con_input_clk, con_counter_width);
  constant con_trstl_cnt : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_trstl*con_input_clk, con_counter_width);
  constant con_tmsp_cnt  : std_logic_vector(con_counter_width-1 downto 0) := to_vector(con_tmsp*con_input_clk, con_counter_width);

----------------------------------------- VARIABLES -----------------------------------------------

  -- Onewire Signals
  signal sig_onewire_i, sig_onewire_oe : std_logic;

  -- Control Signals
  signal sig_go_edge, sig_go : std_logic;

  -- Core FSM Signals
  signal sig_write_data    : std_logic;
  signal sig_state         : fsm_states;
  signal sig_base_counter  : std_logic_vector(con_counter_width-1 downto 0);
  signal sig_reset_counter : std_logic;

  -- CRC Signals
  signal sig_crc_data : std_logic;
  signal sig_crc16    : std_logic_vector(15 downto 0);
  signal sig_crc8     : std_logic_vector(7 downto 0);

begin

--------------------------------- IO REGISTERING ----------------------------------

  onewire_o <= '0';

  onewire_i_reg  : fd port map (c => clk, d => onewire_i, q => sig_onewire_i);
  onewire_oe_reg : fd port map (c => clk, d => sig_onewire_oe, q => onewire_oe);

  running <= '1' when sig_state /= s_idle or go = '1' else '0';

  go_reg : fd port map (c => clk, d => go, q => sig_go);

  sig_go_edge <= not(sig_go) and go;

  crc16 <= sig_crc16;
  crc8  <= sig_crc8;

---------------------------------- CRC GENERATOR ----------------------------------

  crc_gen:
  process(clk)
    variable var_crc8  : std_logic_vector(7 downto 0);
    variable var_crc16 : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      if crc_reset = '1' then
        var_crc8  := (others => '0');
        var_crc16 := (others => '0');
      else
        if sig_state = s_write_data_shift or sig_state = s_read_data_sample then
          -- X8+X5+X4+1 (0x00 on success)
          var_crc8 := (sig_crc8(0) xor sig_crc_data) &
                      sig_crc8(7 downto 5) &
                      (sig_crc8(4) xor (sig_crc8(0) xor sig_crc_data)) &
                      (sig_crc8(3) xor (sig_crc8(0) xor sig_crc_data)) &
                      sig_crc8(2 downto 1);

          -- X16+X15+X2+1 (0xB001 on success)
          var_crc16 := (sig_crc16(0) xor sig_crc_data) &
                       sig_crc16(15) &
                       (sig_crc16(14) xor (sig_crc16(0) xor sig_crc_data)) &
                       sig_crc16(13 downto 2) &
                       (sig_crc16(1) xor (sig_crc16(0) xor sig_crc_data));
        end if;
      end if;
    end if;
    sig_crc8  <= var_crc8;
    sig_crc16 <= var_crc16;
  end process;

  sig_crc_data <= sig_write_data when sel(0) = '1' else
                  sig_onewire_i;

---------------------------------- DATA SHIFTER -----------------------------------

  data_shifter:
  process(clk)
    variable var_shifter : std_logic_vector(7 downto 0);
    variable var_present : std_logic;
  begin
    if rising_edge(clk) then
      if sig_go_edge = '1' and sig_state = s_idle then
        var_shifter := data_i;
      else
        if sig_state = s_write_data_shift or sig_state = s_read_data_sample then
          var_shifter := sig_onewire_i & var_shifter(7 downto 1);
        end if;
      end if;

      if sig_state = s_reset_pulse_sample then
        var_present := not(sig_onewire_i);
      end if;
    end if;
    data_o         <= var_shifter;
    sig_write_data <= var_shifter(0);
    presence       <= var_present;
  end process;

  sig_onewire_oe <= '0' when sig_state = s_reset_pulse or sig_state = s_write_data or sig_state = s_read_data else
                    sig_write_data when sig_state = s_write_data_wait else
                    '1';

------------------------------- MAIN STATE MACHINE --------------------------------
-- OPERATION: Simple state machine based on a counter and the timing constants as
--            defined by the device datasheet. 


  main_fsm:
  process(clk)
    variable var_state         : fsm_states;
    variable var_reset_counter : std_logic;
    variable var_bitcount      : std_logic_vector(2 downto 0);
  begin
    if rising_edge(clk) then
      if reset = '1' then
        var_state         := s_idle;
        var_reset_counter := '0';
        var_bitcount      := (others => '0');
      else
        var_reset_counter := '0';
        case var_state is
          when s_idle =>                -- FSM is off
            if sig_go_edge = '1' then
              if sel = "00" then
                var_state := s_reset_pulse;
              elsif sel = "01" then
                var_state := s_write_data;
              else
                var_state := s_read_data;
              end if;
              var_reset_counter := '1';
              var_bitcount      := (others => '0');
            end if;
          --------------
          when s_reset_pulse =>  -- Hold the IO line low until tRSTL has expired then release
            if sig_base_counter = con_trstl_cnt then
              var_reset_counter := '1';
              var_state         := s_reset_pulse_wait;
            end if;
          when s_reset_pulse_wait =>
            if sig_base_counter = con_tmsp_cnt then
              var_state := s_reset_pulse_sample;
            end if;
          when s_reset_pulse_sample =>
            var_state := s_reset_pulse_recovery;
          when s_reset_pulse_recovery =>
            if sig_base_counter = con_trsth_cnt then
              var_state := s_finished;
            end if;
          --------------
          when s_write_data =>  -- Create the time slot first then transmit the data
            if sig_base_counter = con_tw1l_cnt then
              var_state := s_write_data_wait;
            end if;
          when s_write_data_wait =>
            if sig_base_counter = con_tw0l_cnt then
              var_state := s_write_data_shift;
            end if;
          when s_write_data_shift =>
            var_state := s_write_data_recovery;
          when s_write_data_recovery =>
            if sig_base_counter = con_tslot_cnt then
              if var_bitcount = "111" then
                var_state := s_finished;
              else
                var_bitcount      := var_bitcount+1;
                var_state         := s_write_data;
                var_reset_counter := '1';
              end if;
            end if;
          --------------
          when s_read_data =>
            if sig_base_counter = con_trl_cnt then
              var_state := s_read_data_wait;
            end if;
          when s_read_data_wait =>
            if sig_base_counter = con_tmsr_cnt then
              var_state := s_read_data_sample;
            end if;
          when s_read_data_sample =>
            var_state := s_read_data_recovery;
          when s_read_data_recovery =>
            if sig_base_counter = con_tslot_cnt then
              if var_bitcount = "111" then
                var_state := s_finished;
              else
                var_bitcount      := var_bitcount+1;
                var_state         := s_read_data;
                var_reset_counter := '1';
              end if;
            end if;
          --------------
          when s_finished =>
            var_state := s_idle;
        end case;
      end if;
    end if;

    sig_state         <= var_state;
    sig_reset_counter <= var_reset_counter;
  end process;

  base_counter:
  process(clk)
    variable var_basecounter : std_logic_vector(con_counter_width-1 downto 0);
  begin
    if rising_edge(clk) then
      if sig_reset_counter = '1' then
        var_basecounter := (others => '0');
      else
        var_basecounter := var_basecounter + 1;
      end if;
    end if;
    sig_base_counter <= var_basecounter;
  end process;


end brains;





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
-- File Name:    onewire_ctrl.vhd
-- Type:         RTL
-- Designer: 
-- Created:      10:55:56 07/15/2009 
-- Template Rev: 0.1
--
-- Title:        Onewire PROM Interface 
--
-- Description:  Allows read and wirte access to the internal EEPROM of the 
--               Dallas 1 wire ROM chips. 
--
-------------------------------------------------------------------------------

library ieee;
library unisim;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use unisim.vcomponents.all;
use work.all;


entity onewire_ctrl is
  port (


    clk   : in std_logic;
    reset : in std_logic;

    -- Control Interface
    strobe      : in std_logic;
    mode        : in std_logic_vector(1 downto 0);  -- Operation Mode
                                                    -- 10 : Read Data
                                                    -- 11 : Write data
    
	 mem_address : in std_logic_vector(7 downto 0);  -- Address of reaad/write command

    mem_read_data  : out std_logic_vector(63 downto 0);  -- Read data from ROM
    mem_write_data : in  std_logic_vector(63 downto 0);  -- Write data to ROM

    error   : out std_logic;  -- Indicate the previous transaction ended in error
    running : out std_logic;  -- Inidicates if the state machine is busy


    -- Onewire Interface
    onewire_oe : out std_logic;         -- Data Trisate enable (active low)
    onewire_o  : out std_logic;         -- Data output
    onewire_i  : in  std_logic          -- Data input  

    );                                  
end onewire_ctrl;

architecture structure of onewire_ctrl is

------------------------------------------- TYPES -----------------------------------------------

  type fsm_states is (s_idle, s_no_device, s_read_mem_reset, s_read_mem_present, s_read_mem_skip_rom,
                      s_read_mem_cmd, s_read_mem_address1, s_read_mem_address2, s_read_mem_data,
                      s_write_scratchpad_reset, s_write_scratchpad_present, s_write_scratchpad_skip_rom,
                      s_write_scratchpad_cmd, s_write_scratchpad_address1, s_write_scratchpad_address2,
                      s_write_scratchpad_data, s_write_scratchpad_read_crc, s_read_scratchpad_reset,
                      s_read_scratchpad_present, s_read_scratchpad_skip_rom, s_read_scratchpad_cmd,
                      s_read_scratchpad_registers, s_write_mem_reset, s_write_mem_present, s_write_mem_skip_rom,
                      s_write_mem_cmd, s_write_mem_address1, s_write_mem_address2, s_write_mem_es, s_write_mem_wait,
                      s_write_mem_read_success);

----------------------------------------- VARIABLES -----------------------------------------------


  -- Core FSM Signals
  signal sig_state      : fsm_states;
  signal sig_latch_data : std_logic;

  -- Address Signals
  signal sig_mem_address : std_logic_vector(15 downto 0);

  -- Register Signals
  signal sig_mem_data : std_logic_vector(63 downto 0);

  -- Programming Wait Counter
  signal sig_prog_wait : std_logic_vector(17 downto 0);

  -- Onewire Signals
  signal sig_onewire_command                                         : std_logic_vector(1 downto 0);
  signal sig_onewire_start, sig_onewire_running, sig_onewire_present : std_logic;
  signal sig_onewire_data_i, sig_onewire_data_o                      : std_logic_vector(7 downto 0);
  signal sig_onewire_crc8                                            : std_logic_vector(7 downto 0);
  signal sig_onewire_crc16                                           : std_logic_vector(15 downto 0);
  signal sig_onewire_crc_reset                                       : std_logic;
  
begin


----------------------------------------------------------------------------------
-- Data Latch: Stores the data read from the 1-wire device. Implemented as a 128 entry FIFO

  data_latch:
  process(clk)
    variable var_mem_data : std_logic_vector(63 downto 0) := (others => '1');
  begin
    if rising_edge(clk) then
      if strobe = '1' and sig_state = s_idle then
        var_mem_data := mem_write_data;
      else
        if sig_latch_data = '1' then
          var_mem_data := sig_onewire_data_o & var_mem_data(63 downto 8);
        end if;
      end if;
    end if;
    sig_mem_data <= var_mem_data;
  end process;

  mem_read_data <= sig_mem_data;

----------------------------------------------------------------------------------
-- Status Latches: Indicates the status of the core

  error_latch:
  process(clk)
    variable var_error : std_logic;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        var_error := '0';
      else
        if sig_state = s_no_device then
          var_error := '1';
        elsif strobe = '1' then
          var_error := '0';
        end if;
      end if;
    end if;
    error <= var_error;
  end process;

  running <= '1' when sig_state /= s_idle else '0';


----------------------------------------------------------------------------------
-- Programming Counter: Counts down the 10ms for the programming of the chip to be 
--                      complete

  prog_count:
  process(clk)
    variable var_progwait : std_logic_vector(17 downto 0);
  begin
    if rising_edge(clk) then
      if sig_state /= s_write_mem_wait then
        var_progwait := (others => '1');
      else
        var_progwait := var_progwait - 1;
      end if;
    end if;
    sig_prog_wait <= var_progwait;
  end process;

----------------------------------------------------------------------------------
-- Main FSM: Top level control state machine responsible for sequencing the ROM
--           retrieval and the EEPROM read and write


  main_fsm:
  process(clk)
    variable var_state                         : fsm_states;
    variable var_onewire_start, var_latch_data : std_logic;
    variable var_byte_counter                  : std_logic_vector(2 downto 0);
    
  begin
    if rising_edge(clk) then
      if reset = '1' then
        var_state         := s_idle;
        var_onewire_start := '0';
        var_latch_data    := '0';
      else
        var_onewire_start := '0';
        var_latch_data    := '0';
        case sig_state is
          when s_idle =>
            
            if strobe = '1' then
              
              if mode = "10" then
                var_state := s_read_mem_reset;
              elsif mode = "11" then
                var_state := s_write_scratchpad_reset;
              end if;
              
            end if;
            

          when s_read_mem_reset =>      -- Issue Reset Pulse
            var_onewire_start := '1';
            var_state         := s_read_mem_present;
          when s_read_mem_present =>
            if sig_onewire_running = '0' then
              if sig_onewire_present = '1' then
                var_state         := s_read_mem_skip_rom;
                var_onewire_start := '1';
              else
                var_state := s_no_device;
              end if;
            end if;
          when s_read_mem_skip_rom =>   -- Issue the skip ROM command
            if sig_onewire_running = '0' then
              var_state         := s_read_mem_cmd;
              var_onewire_start := '1';
            end if;
          when s_read_mem_cmd =>        -- Issue the read memory command
            if sig_onewire_running = '0' then
              var_state         := s_read_mem_address1;
              var_onewire_start := '1';
            end if;
          when s_read_mem_address1 =>   -- Send start memory address
            if sig_onewire_running = '0' then
              var_state         := s_read_mem_address2;
              var_onewire_start := '1';
            end if;
          when s_read_mem_address2 =>
            var_byte_counter := (others => '0');
            if sig_onewire_running = '0' then
              var_state         := s_read_mem_data;
              var_onewire_start := '1';
            end if;
          when s_read_mem_data =>
            if sig_onewire_running = '0' then
              var_latch_data := '1';
              if var_byte_counter = "111" then
                var_state := s_idle;
              else
                var_byte_counter  := var_byte_counter + 1;
                var_onewire_start := '1';
              end if;
            end if;
          ------------
          when s_write_scratchpad_reset =>     -- Issue Reset Pulse
            var_onewire_start := '1';
            var_state         := s_write_scratchpad_present;
          when s_write_scratchpad_present =>
            if sig_onewire_running = '0' then
              if sig_onewire_present = '1' then
                var_state         := s_write_scratchpad_skip_rom;
                var_onewire_start := '1';
              else
                var_state := s_no_device;
              end if;
            end if;
          when s_write_scratchpad_skip_rom =>  -- Issue the skip ROM command
            if sig_onewire_running = '0' then
              var_state         := s_write_scratchpad_cmd;
              var_onewire_start := '1';
            end if;
          when s_write_scratchpad_cmd =>  -- Issue the write scratchpad memory command
            if sig_onewire_running = '0' then
              var_state         := s_write_scratchpad_address1;
              var_onewire_start := '1';
            end if;
          when s_write_scratchpad_address1 =>  -- Send start memory address
            if sig_onewire_running = '0' then
              var_state         := s_write_scratchpad_address2;
              var_onewire_start := '1';
            end if;
          when s_write_scratchpad_address2 =>
            var_byte_counter := (others => '0');
            if sig_onewire_running = '0' then
              var_state         := s_write_scratchpad_data;
              var_onewire_start := '1';
              var_latch_data    := '1';
            end if;
          when s_write_scratchpad_data =>
            if sig_onewire_running = '0' then
              var_latch_data := '1';
              if var_byte_counter = "111" then
                var_state         := s_write_scratchpad_read_crc;
                var_byte_counter  := (others => '0');
                var_onewire_start := '1';
              else
                var_byte_counter  := var_byte_counter + 1;
                var_onewire_start := '1';
              end if;
            end if;
          when s_write_scratchpad_read_crc =>
            if sig_onewire_running = '0' then
              if var_byte_counter = "001" then
                if sig_onewire_crc16 = x"b001" then
                  var_state := s_read_scratchpad_reset;
                else
                  var_state := s_no_device;
                end if;
              else
                var_byte_counter  := var_byte_counter + 1;
                var_onewire_start := '1';
              end if;
            end if;
          -------------- 
          when s_read_scratchpad_reset =>      -- Issue Reset Pulse
            var_onewire_start := '1';
            var_state         := s_read_scratchpad_present;
          when s_read_scratchpad_present =>
            if sig_onewire_running = '0' then
              if sig_onewire_present = '1' then
                var_state         := s_read_scratchpad_skip_rom;
                var_onewire_start := '1';
              else
                var_state := s_no_device;
              end if;
            end if;
          when s_read_scratchpad_skip_rom =>   -- Issue the skip ROM command
            if sig_onewire_running = '0' then
              var_state         := s_read_scratchpad_cmd;
              var_onewire_start := '1';
            end if;
          when s_read_scratchpad_cmd =>  -- Issue the write scratchpad memory command
            var_byte_counter := (others => '0');
            if sig_onewire_running = '0' then
              var_state         := s_read_scratchpad_registers;
              var_onewire_start := '1';
            end if;
          when s_read_scratchpad_registers =>
            if sig_onewire_running = '0' then
              var_latch_data := '1';
              if var_byte_counter = "010" then
                var_state := s_write_mem_reset;
              else
                var_byte_counter  := var_byte_counter + 1;
                var_onewire_start := '1';
              end if;
            end if;
          -------------- 
          when s_write_mem_reset =>     -- Issue Reset Pulse
            var_onewire_start := '1';
            var_state         := s_write_mem_present;
          when s_write_mem_present =>
            if sig_onewire_running = '0' then
              if sig_onewire_present = '1' then
                var_state         := s_write_mem_skip_rom;
                var_onewire_start := '1';
              else
                var_state := s_no_device;
              end if;
            end if;
          when s_write_mem_skip_rom =>  -- Issue the skip ROM command
            if sig_onewire_running = '0' then
              var_state         := s_write_mem_cmd;
              var_onewire_start := '1';
            end if;
          when s_write_mem_cmd =>  -- Issue the write scratchpad memory command
            if sig_onewire_running = '0' then
              var_state         := s_write_mem_address1;
              var_onewire_start := '1';
            end if;
          when s_write_mem_address1 =>  -- Send start memory address
            if sig_onewire_running = '0' then
              var_state         := s_write_mem_address2;
              var_onewire_start := '1';
            end if;
          when s_write_mem_address2 =>
            if sig_onewire_running = '0' then
              var_state         := s_write_mem_es;
              var_onewire_start := '1';
            end if;
          when s_write_mem_es =>
            if sig_onewire_running = '0' then
              var_state := s_write_mem_wait;
            end if;
          when s_write_mem_wait =>  -- Wait for  tPROGRMAX for EEPROM to write
            if sig_prog_wait = 0 then   -- About 10 ms
              var_onewire_start := '1';
              var_state         := s_write_mem_read_success;
            end if;
          when s_write_mem_read_success =>
            if sig_onewire_running = '0' then
              if sig_onewire_data_o = x"aa" then
                var_state := s_idle;
              else
                var_state := s_no_device;
              end if;
            end if;

          -------------- 
          when s_no_device =>
            var_state := s_idle;
        end case;
      end if;
    end if;

    sig_state         <= var_state;
    sig_onewire_start <= var_onewire_start;
    sig_latch_data    <= var_latch_data;
    
  end process;


  --------------

  sig_mem_address <= x"00" & mem_address(7 downto 3) & "000";  -- Always on an 8 byte boundry

  --------------
  -- Assign the control signals based the the state machine 

  sig_onewire_command <= "10" when sig_state = s_read_mem_data or sig_state = s_write_scratchpad_read_crc or sig_state = s_read_scratchpad_registers or sig_state = s_write_mem_read_success else
                         "00" when sig_state = s_read_mem_present or sig_state = s_write_scratchpad_present or sig_state = s_read_scratchpad_present or sig_state = s_write_mem_present else
                         "01";

  sig_onewire_data_i <= x"cc" when sig_state = s_read_mem_skip_rom or sig_state = s_write_scratchpad_skip_rom or sig_state = s_read_scratchpad_skip_rom or sig_state = s_write_mem_skip_rom else
                          x"f0"                        when sig_state = s_read_mem_cmd else
                          x"0f"                        when sig_state = s_write_scratchpad_cmd else
                          x"55"                        when sig_state = s_write_mem_cmd else
                          x"aa"                        when sig_state = s_read_scratchpad_cmd else
                          sig_mem_address(7 downto 0)  when sig_state = s_read_mem_address1 or sig_state = s_write_scratchpad_address1 else
                          sig_mem_address(15 downto 8) when sig_state = s_read_mem_address2 or sig_state = s_write_scratchpad_address2 else
                          sig_mem_data(7 downto 0)     when sig_state = s_write_scratchpad_data else
                          sig_mem_data(47 downto 40)   when sig_state = s_write_mem_address1 else
                          sig_mem_data(55 downto 48)   when sig_state = s_write_mem_address2 else
                          sig_mem_data(63 downto 56)   when sig_state = s_write_mem_es else
                          x"00";

  sig_onewire_crc_reset <= '0' when sig_state = s_write_scratchpad_cmd or sig_state = s_write_scratchpad_address1 or sig_state = s_write_scratchpad_address2 or sig_state = s_write_scratchpad_data or sig_state = s_write_scratchpad_read_crc else
                           '1';

----------------------------------------------------------------------------------
-- The Physical layer of the 1-wire interface

  inst_onewire_core : entity onewire_core

    port map (clk        => clk,
              reset      => reset,
              go         => sig_onewire_start,
              running    => sig_onewire_running,
              sel        => sig_onewire_command,
              data_i     => sig_onewire_data_i,
              data_o     => sig_onewire_data_o,
              presence   => sig_onewire_present,
              crc8       => sig_onewire_crc8,
              crc16      => sig_onewire_crc16,
              crc_reset  => sig_onewire_crc_reset,
              onewire_oe => onewire_oe,
              onewire_o  => onewire_o,
              onewire_i  => onewire_i);

end structure;


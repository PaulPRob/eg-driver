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
-- File Name: ident_read_s_m.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Ident Read State Machine
--
-- Description: State machine to read out the ident string from the onewire PROM.
--              This module also instantiates 32x64 RAM to store the contents read from the 
--              onewire PROM.
--
--              ATNF MOD FOR EG: the first read waits POWERUP_WAIT clocks
--              after reset, and a block that ends in a onewire error (no
--              presence pulse) is retried up to MAX_RETRIES times, RETRY_WAIT
--              clocks apart.  A block that never reads is stored as zeros.
--              See the comment above the read state machine.
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
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library unisim;
use unisim.vcomponents.all;
use work.all;



entity ident_read_s_m is

  -- ATNF MOD FOR EG: in clk cycles at 31.25 MHz, 2^20 = 33.6 ms and
  -- 2^15 = 1.05 ms.  The testbench shortens them.
  generic(
    POWERUP_WAIT : natural := 1048576;
    RETRY_WAIT   : natural := 32768;
    MAX_RETRIES  : natural := 15
    );
  -- END ATNF MOD --

  port(

    clk                  : in  std_logic;
    reset                : in  std_logic;
    onewire_read_data    : in  std_logic_vector(63 downto 0);
    onewire_read_address : out std_logic_vector(7 downto 0);
    onewire_read_strobe  : out std_logic;
    one_wire_running     : in  std_logic;
    one_wire_error       : in  std_logic;  -- ATNF MOD FOR EG
    re_read_prom        : in  std_logic;
    read_prom_done       : out std_logic;
    ident_ram_addr_rd    : in  std_logic_vector(4 downto 0);
    ident_ram_data_read  : out std_logic_vector(63 downto 0)


    );

end ident_read_s_m;

architecture behavioral of ident_read_s_m is

  type read_ident_state_type is
    (POWER_UP_WAIT,                     -- ATNF MOD FOR EG
     START_READ,
     READ_STROBE_HIGH,
     READ_STROBE_LOW,
     BUSY_WAIT,
     CHECK_ERROR,                       -- ATNF MOD FOR EG
     RETRY_WAIT_STATE,                  -- ATNF MOD FOR EG
     WRITE_RAM_HIGH,
     WRITE_RAM_LOW,
     COPY_EIGHT_BYTE,
     INCREMENT_ADDRESS,
     CHECK_PROM_EMPTY,
     READ_DONE);

  signal sig_read_state : read_ident_state_type;

  signal sig_read_prom_done : std_logic := '0';

  signal sig_onewire_read_address : std_logic_vector(7 downto 0) := "00000000";

  signal sig_ident_ram_addr_wr : std_logic_vector(4 downto 0);
  signal sig_ident_ram_data_wr : std_logic_vector(63 downto 0);
  signal sig_ident_ram_wr_en   : std_logic := '0';

  signal sig_ident_ram_data_read : std_logic_vector(63 downto 0);

  signal sig_onewire_read_strobe : std_logic := '0';

  -- ATNF MOD FOR EG --
  signal sig_wait_count  : integer range 0 to POWERUP_WAIT + RETRY_WAIT := POWERUP_WAIT;
  signal sig_retry_count : integer range 0 to MAX_RETRIES := 0;
  -- END ATNF MOD --


begin


----------------------------------------------
--RAM to store data read from onewire PROM
----------------------------------------------
  
  ram32x1 : for n in 0 to 63 generate
    
    ram32x1d_inst : ram32x1d
      generic map (
        init => x"00000000")                  -- Initial contents of RAM
      port map (
        dpo   => sig_ident_ram_data_read(n),  -- Read-only 1-bit data output
        spo   => open,                        -- R/W 1-bit data output
        a0    => sig_ident_ram_addr_wr(0),    -- R/W address[0] input bit
        a1    => sig_ident_ram_addr_wr(1),    -- R/W address[1] input bit
        a2    => sig_ident_ram_addr_wr(2),    -- R/W address[2] input bit
        a3    => sig_ident_ram_addr_wr(3),    -- R/W address[3] input bit
        a4    => sig_ident_ram_addr_wr(4),    -- R/W address[4] input bit
        d     => sig_ident_ram_data_wr(n),    -- Write 1-bit data input
        dpra0 => ident_ram_addr_rd(0),        -- Read-only address[0] input bit
        dpra1 => ident_ram_addr_rd(1),        -- Read-only address[1] input bit
        dpra2 => ident_ram_addr_rd(2),        -- Read-only address[2] input bit
        dpra3 => ident_ram_addr_rd(3),        -- Read-only address[3] input bit
        dpra4 => ident_ram_addr_rd(4),        -- Read-only address[4] input bit
        wclk  => clk,                         -- Write clock input
        we    => sig_ident_ram_wr_en          -- Write enable input
        );

  end generate;


----------------------------------------------
--Read State Machine
----------------------------------------------

  -- ATNF MOD FOR EG --
  -- The read used to start as soon as reset was released, which is when the
  -- PCIe link comes up.  Loading from the PROM at 16 MHz, that is so soon
  -- after configuration that the onewire EEPROM does not answer the first
  -- reset pulse.  onewire_ctrl then flags an error that nothing looked at,
  -- so the first 8 bytes (the preamble and "PCI EV") were stored as zeros
  -- and the driver read an empty ident.  The read now waits POWERUP_WAIT
  -- clocks first, and retries a block that fails, RETRY_WAIT clocks apart,
  -- MAX_RETRIES times before storing it as zeros and moving on.
  -- END ATNF MOD --

  process(clk, reset)

  begin

    if (reset = '1') then


      sig_read_state <= POWER_UP_WAIT;
      sig_onewire_read_strobe <= '0';
      sig_wait_count <= POWERUP_WAIT;   -- ATNF MOD FOR EG
      sig_retry_count <= 0;             -- ATNF MOD FOR EG

    elsif rising_edge(clk) then

      case (sig_read_state) is


        -- ATNF MOD FOR EG: let the EEPROM power up before the first read --
        when POWER_UP_WAIT =>       if (sig_wait_count = 0) then
                                        sig_read_state <= START_READ;
                                    else
                                        sig_wait_count <= sig_wait_count - 1;
                                        sig_read_state <= POWER_UP_WAIT;
                                    end if;
        -- END ATNF MOD --

        when START_READ =>			if (one_wire_running = '0') then
												  sig_ident_ram_addr_wr    <= (others => '0');
												  sig_onewire_read_address <= (others => '0');
												  sig_onewire_read_strobe  <= '0';
												  sig_ident_ram_wr_en      <= '0';
												  sig_retry_count          <= 0;  -- ATNF MOD FOR EG
												  sig_read_state           <= READ_STROBE_HIGH;
											   else
												  sig_read_state <= START_READ;
											   end if;
                                                        
                                                        
        when READ_STROBE_HIGH =>    sig_onewire_read_strobe <= '1';
                                    sig_read_state <= READ_STROBE_LOW;
                                                
        when READ_STROBE_LOW =>     sig_onewire_read_strobe <= '0';
                                    sig_read_state <= BUSY_WAIT;
                                                
        when BUSY_WAIT =>           if (one_wire_running = '0') then
                                        sig_read_state <= CHECK_ERROR;  -- ATNF MOD FOR EG
											   else
												    sig_read_state <= BUSY_WAIT;
											   end if;

        -- ATNF MOD FOR EG: retry a block the EEPROM did not answer --
        when CHECK_ERROR =>         if (one_wire_error = '0') then
                                        sig_read_state <= COPY_EIGHT_BYTE;
                                    elsif (sig_retry_count = MAX_RETRIES) then
                                        sig_ident_ram_data_wr <= (others => '0');
                                        sig_read_state <= WRITE_RAM_HIGH;
                                    else
                                        sig_retry_count <= sig_retry_count + 1;
                                        sig_wait_count <= RETRY_WAIT;
                                        sig_read_state <= RETRY_WAIT_STATE;
                                    end if;

        when RETRY_WAIT_STATE =>    if (sig_wait_count = 0) then
                                        sig_read_state <= READ_STROBE_HIGH;
                                    else
                                        sig_wait_count <= sig_wait_count - 1;
                                        sig_read_state <= RETRY_WAIT_STATE;
                                    end if;
        -- END ATNF MOD --

        when COPY_EIGHT_BYTE =>     sig_ident_ram_data_wr <= onewire_read_data;
                                    sig_read_state <= WRITE_RAM_HIGH;
                                                
        when WRITE_RAM_HIGH =>      sig_ident_ram_wr_en <= '1';
                                    sig_read_state <= WRITE_RAM_LOW;
                                                
        when WRITE_RAM_LOW =>       sig_ident_ram_wr_en <= '0';
                                    sig_read_state <= INCREMENT_ADDRESS;
                                                
        when INCREMENT_ADDRESS =>   sig_onewire_read_address(7 downto 3) <= sig_onewire_read_address(7 downto 3)+1;
                                    sig_ident_ram_addr_wr <= sig_ident_ram_addr_wr+1;
                                    sig_retry_count <= 0;  -- ATNF MOD FOR EG
                                    sig_read_state <= CHECK_PROM_EMPTY;
                                        
                                        
        when CHECK_PROM_EMPTY =>    if (sig_ident_ram_addr_wr(4) = '1') then
                                        sig_read_state <= READ_DONE;
                                    else
                                        sig_read_state <= READ_STROBE_HIGH;
                                    end if;
                                                
        when READ_DONE => 				if (re_read_prom = '0') then
                                        sig_read_prom_done <= '1';
                                        sig_read_state <= READ_DONE;
                                    else
													 sig_read_prom_done <= '0';
													 sig_read_state <= START_READ;
                                    end if;
                                                        
        when others => 					sig_read_state <= START_READ;
                                                                
        end case;
      
    end if;
  end process;


-----------------------------------------------------
-- Concurrent Signal Assignments
-----------------------------------------------------

  read_prom_done       <= sig_read_prom_done;
  onewire_read_strobe  <= sig_onewire_read_strobe;
  onewire_read_address <= sig_onewire_read_address;
  ident_ram_data_read  <= sig_ident_ram_data_read;



end behavioral;


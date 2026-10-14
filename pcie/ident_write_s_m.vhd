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
-- File Name: ident_write_s_m.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: Thu Apr 30 18:09:15 2009
-- Template Rev: 1.0
--
-- Title: Ident Write State Machine
--
-- Description: State machine to write an ident string to onewire PROM. 
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
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library unisim;
use unisim.vcomponents.all;
use work.all;
use work.pci_package.all;

entity ident_write_s_m is

  port(

    clk                   : in  std_logic;
    reset                 : in  std_logic;
    master_control        : in  std_logic_vector(8 downto 0);
    ident_fifo_dout_write : in  std_logic_vector(7 downto 0);
    ident_pop_write       : out std_logic;
    empty_write           : in  std_logic;
    serial_write_data     : out std_logic_vector(63 downto 0);
    write_address         : out std_logic_vector(7 downto 0);
    write_strobe          : out std_logic;
    one_wire_running      : in  std_logic;
    write_state           : out std_logic;
    re_read_prom          : out std_logic

    );

end ident_write_s_m;

architecture behavioral of ident_write_s_m is

  type write_ident_state_type is
    (WRITE_IDLE,
     START_IDENT_WRITE,
     COLLECT_BYTES,
     CHECK_EMPTY_FIFO,
     POP_FIFO_HIGH,
     POP_FIFO_LOW,
     CHECK_FINISHED,
     INCREMENT_ADDRESS,
     WRITE_STROBE_LOW,
     WRITE_STROBE_HIGH);

  signal sig_write_state : write_ident_state_type;

  signal master_control_local : master_control_t;

  signal sig_write_byte_count  : std_logic_vector(2 downto 0) := "000";
  signal sig_write_strobe      : std_logic                    := '0';
  signal sig_write_address     : std_logic_vector(7 downto 0) := "00000000";
  signal sig_ident_pop_write   : std_logic                    := '0';
  signal sig_serial_write_data : std_logic_vector(63 downto 0);
  signal sig_re_read_prom      : std_logic                    := '0';


begin

  master_control_local <= slv_to_master_control(master_control);

----------------------------------------------
--Write State Machine   
----------------------------------------------

  process(clk, reset)

  begin

    if (reset = '1') then

      sig_write_state               <= WRITE_IDLE;
      sig_write_byte_count          <= "000";
      sig_write_strobe              <= '0';
      sig_write_address(7 downto 3) <= "00000";
      sig_ident_pop_write           <= '0';
      sig_re_read_prom              <= '0';

    elsif rising_edge(clk) then

      case (sig_write_state) is
        
        
        when WRITE_IDLE => 			if (master_control_local.ident_write = '1') then
                                        sig_write_state <= START_IDENT_WRITE;
                                    else
													 sig_re_read_prom     <= '0';
													 sig_write_state      <= WRITE_IDLE;
													 sig_write_byte_count <= "000";
													 sig_write_address    <= (others => '0');
                                    end if;
                                                        
                                                        
        when START_IDENT_WRITE => 	if (master_control_local.ident_write = '0') then
                                          sig_write_state <= COLLECT_BYTES;
                                    else
                                          sig_write_state <= START_IDENT_WRITE;
                                    end if;
                                        
                                        
        when POP_FIFO_HIGH =>       sig_ident_pop_write <= '1';
                                    sig_write_state <= POP_FIFO_LOW;
                                                
                                                
        when POP_FIFO_LOW =>        sig_ident_pop_write <= '0';
                                    sig_write_state <= CHECK_EMPTY_FIFO;
                                                
                                                
        when CHECK_EMPTY_FIFO =>    if (empty_write = '0' and sig_write_byte_count /= "000") then
                                           sig_write_state <= COLLECT_BYTES;
                                    else
                                           sig_write_state <= WRITE_STROBE_HIGH;
                                    end if;
                                                
        when COLLECT_BYTES =>       sig_write_byte_count <= sig_write_byte_count+1;
                                                
												if (sig_write_byte_count = "000") then
												  sig_serial_write_data(63 downto 56) <= ident_fifo_dout_write;
												  sig_write_state  <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "001") then
												  sig_serial_write_data(55 downto 48) <= ident_fifo_dout_write;
												  sig_write_state  <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "010") then
												  sig_serial_write_data(47 downto 40) <= ident_fifo_dout_write;
												  sig_write_state <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "011") then
												  sig_serial_write_data(39 downto 32) <= ident_fifo_dout_write;
												  sig_write_state <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "100") then
												  sig_serial_write_data(31 downto 24) <= ident_fifo_dout_write;
												  sig_write_state <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "101") then
												  sig_serial_write_data(23 downto 16) <= ident_fifo_dout_write;
												  sig_write_state  <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "110") then
												  sig_serial_write_data(15 downto 8) <= ident_fifo_dout_write;
												  sig_write_state <= POP_FIFO_HIGH;
												  
												  
												elsif(sig_write_byte_count = "111") then
												  sig_serial_write_data(7 downto 0) <= ident_fifo_dout_write;
												  sig_write_state <= POP_FIFO_HIGH;
												  
												else
												  sig_write_state <= COLLECT_BYTES;
												end if;
                                                
                                                
        when WRITE_STROBE_HIGH =>  sig_write_strobe <= '1';
                                   sig_write_state <= WRITE_STROBE_LOW;
                                        
        when WRITE_STROBE_LOW =>   sig_write_strobe <= '0';
                                   sig_write_state <= CHECK_FINISHED;
                                        
        when CHECK_FINISHED =>     if (one_wire_running = '0') then
                                                  
                                      if (empty_write = '0') then
                                          sig_write_state <= INCREMENT_ADDRESS;
                                      else
														sig_re_read_prom <= '1';
														sig_write_state  <= WRITE_IDLE;
                                      end if;
                                                
											  else
												  sig_write_state <= CHECK_FINISHED;
											  end if;


       when INCREMENT_ADDRESS =>  sig_write_address(7 downto 3) <= sig_write_address(7 downto 3) + 1;
                                  sig_write_state <= COLLECT_BYTES;

       when others => 				 sig_write_state <= WRITE_IDLE;
      
      end case;

    end if;
  end process;


-------------------------------------------------------
-- Concurrent Signal Assignments
-------------------------------------------------------

  serial_write_data <= sig_serial_write_data;
  write_strobe      <= sig_write_strobe;
  ident_pop_write   <= sig_ident_pop_write;
  re_read_prom      <= sig_re_read_prom;
  write_address     <= sig_write_address;
  write_state       <= '0' when sig_write_state = write_idle else '1';

end behavioral;

-- Testbench for the eg_registers reset change (#4): interrupt enables are
-- cleared by rst_n, waveform settings are not.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_regs is
end entity;

architecture sim of tb_regs is
  constant CLK_PERIOD : time := 16 ns;
  signal bclk  : std_logic := '0';
  signal clk1m : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal be    : std_logic_vector(3 downto 0) := "0000";
  signal addr  : std_logic_vector(7 downto 0) := x"00";
  signal wr_en, rd_en : std_logic := '0';
  signal d0, d1, d2, d3 : std_logic_vector(7 downto 0) := x"00";
  signal q0, q1, q2, q3 : std_logic_vector(7 downto 0);
  signal clocks : std_logic_vector(17 downto 0);
  signal master_control       : std_logic_vector(8 downto 0);
  signal interrupt_control    : std_logic_vector(14 downto 0);
  signal rising_control       : std_logic_vector(31 downto 0);
  signal falling_control      : std_logic_vector(31 downto 0);
  signal event_output_control : std_logic_vector(12 downto 0);
  signal waveform_control     : std_logic_vector(63 downto 0);
  signal failures : natural := 0;
  signal done : boolean := false;
begin
  bclk  <= not bclk after CLK_PERIOD / 2 when not done;
  clk1m <= not clk1m after 500 ns when not done;
  clocks <= (others => clk1m);

  dut : entity work.eg_registers
    port map (
      bclk => bclk, rst_n => rst_n, be_i => be, address => addr,
      wr_en_i => wr_en, rd_en_i => rd_en,
      wr_data_i_0 => d0, wr_data_i_1 => d1, wr_data_i_2 => d2, wr_data_i_3 => d3,
      rd_data_o_0 => q0, rd_data_o_1 => q1, rd_data_o_2 => q2, rd_data_o_3 => q3,
      clocks => clocks,
      master_control => master_control, master_status => (others => '0'),
      interrupt_control => interrupt_control, interrupt_status => (others => '0'),
      rising_control => rising_control, rising_status => (others => '0'),
      falling_control => falling_control, falling_status => (others => '0'),
      event_output_control => event_output_control, event_output_status => "00",
      waveform_control => waveform_control, waveform_status => (others => '0'),
      frame_byte => x"00", frame_byte_load => open,
      async_event_read => (others => '0'), async_event_write => open,
      async_event_write_load => open,
      ls_sync_event => open, ls_sync_event_load => open,
      ms_sync_event => open, ms_sync_event_load => open,
      ident_serial_out_address_inc => open,
      write_ident_fifo_data => open, write_ident_fifo_load => open,
      write_ident_fifo_reset => open);

  stim : process
    procedure wr(a : std_logic_vector(7 downto 0); b : std_logic_vector(3 downto 0);
                 v0, v1, v2, v3 : std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(bclk);
      addr <= a; be <= b; d0 <= v0; d1 <= v1; d2 <= v2; d3 <= v3; wr_en <= '1';
      wait until rising_edge(bclk);
      wr_en <= '0'; be <= "0000";
    end procedure;
    procedure check(cond : boolean; msg : string) is
    begin
      if cond then report "PASS: " & msg;
      else report "FAIL: " & msg severity error; failures <= failures + 1; end if;
    end procedure;
    variable wf_before : std_logic_vector(63 downto 0);
    variable eo_before : std_logic_vector(12 downto 0);
  begin
    wait for 5 * CLK_PERIOD;
    rst_n <= '1';
    wait for 5 * CLK_PERIOD;

    -- interrupt control (bytes 2,3 of 0x00), rising (0x20), falling (0x28),
    -- waveform prescale (0x10 bytes 2,3), event output control (0x08 bytes 0,1)
    wr(x"00", "1100", x"00", x"00", x"FB", x"FF");
    wr(x"20", "1111", x"FF", x"FF", x"FF", x"FF");
    wr(x"28", "1111", x"FF", x"FF", x"FF", x"FF");
    wr(x"10", "1100", x"00", x"00", x"A5", x"5A");
    wr(x"08", "0011", x"9F", x"3F", x"00", x"00");
    wait for 3 * CLK_PERIOD;

    check(interrupt_control /= (14 downto 0 => '0'), "interrupt enables written");
    check(rising_control  = x"FFFFFFFF", "rising enables written");
    check(falling_control = x"FFFFFFFF", "falling enables written");
    check(waveform_control /= (63 downto 0 => '0'), "waveform prescale written");
    wf_before := waveform_control;
    eo_before := event_output_control;

    -- PCIe reset (warm reboot / link down)
    wait until rising_edge(bclk);
    rst_n <= '0';
    wait for 3 * CLK_PERIOD;
    rst_n <= '1';
    wait for 3 * CLK_PERIOD;

    check(interrupt_control = (14 downto 0 => '0'), "interrupt enables cleared by reset");
    check(rising_control  = x"00000000", "rising enables cleared by reset");
    check(falling_control = x"00000000", "falling enables cleared by reset");
    check(waveform_control = wf_before, "waveform settings kept across reset");
    check(event_output_control = eo_before, "event output settings kept across reset");

    -- registers still writable after reset
    wr(x"00", "1000", x"00", x"00", x"00", x"80");
    wait for 2 * CLK_PERIOD;
    check(interrupt_control(14) = '1', "enable_interrupt writable after reset");

    wait for 5 * CLK_PERIOD;
    if failures = 0 then report "RESULT: ALL PASS";
    else report "RESULT: " & integer'image(failures) & " FAILURE(S)"; end if;
    done <= true;
    wait;
  end process;
end architecture;

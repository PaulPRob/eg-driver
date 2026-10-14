-- Testbench for the reference event path: eg_registers + event_gen + the
-- reference FIFO (eg_ref_fifo_sim.vhd stand-in for the v5.3 core).
--
-- The testbench writes registers the way the driver's writew()/writeb() do on
-- x86 - little-endian, so a 16-bit write to offset 6 puts the low byte on
-- lane 2 and the high byte on lane 3 of the dword at 0x04.
--
--   T1  one event, driver word order (BAT LS, mid, MS, event): fires when
--       BAT matches and not one count earlier
--   T2  GetFifoSize()'s pattern - byte writes to FIFO_REG+1 only - never
--       pushes, and leaves the two byte counters out of step until a reset
--   T3  capacity: events accepted before FIFO full, and where prog_full
--       (half) asserts
--   T4  drain: every event comes out once, in order; half-empty edge
--   T5  one-cycle FIFO reset empties the FIFO
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_eventgen is
end entity;

architecture sim of tb_eventgen is
  constant BCLK_PERIOD : time := 16 ns;
  constant VCO_PERIOD  : time := 62.5 ns;   -- 16 MHz

  signal bclk  : std_logic := '0';
  signal vco   : std_logic := '0';
  signal vcnt  : unsigned(3 downto 0) := (others => '0');
  signal clocks : std_logic_vector(17 downto 0) := (others => '0');
  signal done  : boolean := false;

  -- eg_registers bus
  signal be    : std_logic_vector(3 downto 0) := "0000";
  signal addr  : std_logic_vector(7 downto 0) := x"00";
  signal wr_en : std_logic := '0';
  signal d0, d1, d2, d3 : std_logic_vector(7 downto 0) := x"00";

  signal master_control       : std_logic_vector(8 downto 0);
  signal event_output_control : std_logic_vector(12 downto 0);
  signal async_event_write    : std_logic_vector(15 downto 0);
  signal async_event_write_load : std_logic;
  signal ls_sync_event, ms_sync_event : std_logic_vector(7 downto 0);
  signal ls_sync_event_load, ms_sync_event_load : std_logic;

  signal bat          : std_logic_vector(47 downto 0) := (others => '0');
  signal event_out    : std_logic_vector(15 downto 0);
  signal event_strobe : std_logic;
  signal running      : std_logic;
  signal late_event   : std_logic;
  signal fifo_empty, fifo_half, fifo_full : std_logic;

  -- drain monitor
  signal strobes      : natural := 0;
  signal order_errors : natural := 0;
  signal strobe_q     : std_logic := '0';
  signal half_q       : std_logic := '0';
  signal strobes_at_half_drop : integer := -1;
  signal mon_clear    : boolean := false;

  signal failures : natural := 0;
begin
  bclk <= not bclk after BCLK_PERIOD / 2 when not done;
  vco  <= not vco  after VCO_PERIOD / 2  when not done;

  -- 16 MHz VCO divided down as clocks_gen does: 8, 4, 2, 1 MHz
  process(vco)
  begin
    if rising_edge(vco) then
      vcnt <= vcnt + 1;
    end if;
  end process;
  clocks(0)  <= vco;
  clocks(1)  <= vcnt(0);
  clocks(2)  <= vcnt(1);
  clocks(3)  <= vcnt(2);
  clocks(4)  <= vcnt(3);   -- clkt_1mhz
  clocks(17) <= vcnt(3);   -- clkt_1mhz_ub

  regs : entity work.eg_registers
    port map (
      bclk => bclk, rst_n => '1', be_i => be, address => addr,
      wr_en_i => wr_en, rd_en_i => '0',
      wr_data_i_0 => d0, wr_data_i_1 => d1, wr_data_i_2 => d2, wr_data_i_3 => d3,
      rd_data_o_0 => open, rd_data_o_1 => open, rd_data_o_2 => open, rd_data_o_3 => open,
      clocks => clocks,
      master_control => master_control, master_status => (others => '0'),
      interrupt_control => open, interrupt_status => (others => '0'),
      rising_control => open, rising_status => (others => '0'),
      falling_control => open, falling_status => (others => '0'),
      event_output_control => event_output_control, event_output_status => "00",
      waveform_control => open, waveform_status => (others => '0'),
      frame_byte => x"00", frame_byte_load => open,
      async_event_read => (others => '0'),
      async_event_write => async_event_write,
      async_event_write_load => async_event_write_load,
      ls_sync_event => ls_sync_event, ls_sync_event_load => ls_sync_event_load,
      ms_sync_event => ms_sync_event, ms_sync_event_load => ms_sync_event_load,
      ident_serial_out_address_inc => open,
      write_ident_fifo_data => open, write_ident_fifo_load => open,
      write_ident_fifo_reset => open);

  eg : entity work.event_gen
    port map (
      bclk => bclk, clocks => clocks, bat => bat,
      master_control => master_control,
      event_output_control => event_output_control,
      async_event_write => async_event_write,
      async_event_write_load => async_event_write_load,
      ls_sync_event => ls_sync_event, ls_sync_event_load => ls_sync_event_load,
      ms_sync_event => ms_sync_event, ms_sync_event_load => ms_sync_event_load,
      event_output_status => open, internal_interrupt => open,
      event_out => event_out, event_strobe => event_strobe,
      running => running, late_event => late_event,
      ls_ref_fifo_empty => fifo_empty, ms_ref_fifo_empty => open,
      ls_ref_fifo_half => fifo_half, ms_ref_fifo_half => open,
      ls_ref_fifo_full => fifo_full, ms_ref_fifo_full => open);

  -- Count output events and check they come out in the order written
  -- (T3 writes event value i for the i-th event).
  monitor : process(vco)
  begin
    if rising_edge(vco) then
      strobe_q <= event_strobe;
      half_q   <= fifo_half;
      if mon_clear then
        strobes <= 0;
        order_errors <= 0;
        strobes_at_half_drop <= -1;
      elsif event_strobe = '1' and strobe_q = '0' then
        if to_integer(unsigned(event_out)) /= strobes then
          order_errors <= order_errors + 1;
        end if;
        strobes <= strobes + 1;
      end if;
      if not mon_clear and half_q = '1' and fifo_half = '0' and strobes_at_half_drop < 0 then
        strobes_at_half_drop <= strobes;
      end if;
    end if;
  end process;

  stim : process
    -- 16-bit MMIO write at byte offset off, x86 little-endian lanes
    procedure writew(off : natural; v : std_logic_vector(15 downto 0)) is
      variable lane : natural := off mod 4;
    begin
      wait until rising_edge(bclk);
      addr <= std_logic_vector(to_unsigned(off - lane, 8));
      be <= "0000"; d0 <= x"00"; d1 <= x"00"; d2 <= x"00"; d3 <= x"00";
      if lane = 0 then
        be <= "0011"; d0 <= v(7 downto 0); d1 <= v(15 downto 8);
      else
        be <= "1100"; d2 <= v(7 downto 0); d3 <= v(15 downto 8);
      end if;
      wr_en <= '1';
      wait until rising_edge(bclk);
      wr_en <= '0'; be <= "0000";
      for i in 1 to 4 loop          -- PCIe write spacing
        wait until rising_edge(bclk);
      end loop;
    end procedure;

    procedure writeb(off : natural; v : std_logic_vector(7 downto 0)) is
      variable lane : natural := off mod 4;
    begin
      wait until rising_edge(bclk);
      addr <= std_logic_vector(to_unsigned(off - lane, 8));
      be <= (others => '0'); be(lane) <= '1';
      d0 <= v; d1 <= v; d2 <= v; d3 <= v;
      wr_en <= '1';
      wait until rising_edge(bclk);
      wr_en <= '0'; be <= "0000";
      for i in 1 to 4 loop
        wait until rising_edge(bclk);
      end loop;
    end procedure;

    -- the driver's EGWrite(): four writew(FIFO_REG) in this order
    procedure write_event(b : std_logic_vector(47 downto 0);
                          e : std_logic_vector(15 downto 0)) is
    begin
      writew(6, b(15 downto 0));
      writew(6, b(31 downto 16));
      writew(6, b(47 downto 32));
      writew(6, e);
    end procedure;

    -- writew(MASTER_REG, MA_PLLResetRefFifo), then let the read side settle
    procedure reset_fifo is
    begin
      writew(0, x"0004");
      wait for 10 us;
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then report "PASS: " & msg;
      else report "FAIL: " & msg severity error; failures <= failures + 1; end if;
    end procedure;

    variable n, half_at : integer;
  begin
    wait for 2 us;
    reset_fifo;

    ---------------------------------------------------------------- T1
    report "--- T1: event word order";
    bat <= x"123456789ABB";                  -- one count before the event
    write_event(x"123456789ABC", x"ABCD");
    wait for 10 us;
    check(running = '1', "T1 event taken from the FIFO and pending");
    check(event_out /= x"ABCD", "T1 event not output before its BAT");
    bat <= x"123456789ABC";
    wait for 4 us;
    check(event_out = x"ABCD", "T1 event output at its BAT");
    check(running = '0', "T1 generator idle afterwards");

    ---------------------------------------------------------------- T2
    report "--- T2: GetFifoSize() byte-write pattern";
    bat <= (others => '0');
    reset_fifo;
    for i in 1 to 2000 loop
      writeb(7, x"00");                      -- eg_writeb(FIFO_REG + 1, 0)
    end loop;
    wait for 10 us;
    check(fifo_empty = '1' and fifo_full = '0' and running = '0',
          "T2 2000 MS-byte writes pushed nothing (FIFO empty, not full)");
    -- three more leave the MS byte counter one ahead of the LS one
    for i in 1 to 3 loop
      writeb(7, x"00");
    end loop;
    write_event(x"000100000000", x"1111");
    wait for 10 us;
    check(fifo_empty = '1' and running = '0',
          "T2 counters out of step: a whole event written afterwards is lost");
    reset_fifo;
    write_event(x"000100000000", x"1111");
    wait for 10 us;
    check(running = '1', "T2 FIFO reset puts the counters back in step");
    -- flush that pending event before T3
    bat <= x"7FFFFFFFFFFF";
    wait for 5 us;
    bat <= (others => '0');
    reset_fifo;

    ---------------------------------------------------------------- T3
    report "--- T3: capacity";
    -- like EGWrite(): check 'not full' before each event, stop when full
    n := 0;
    half_at := -1;
    mon_clear <= true;
    wait until rising_edge(vco);
    wait until rising_edge(vco);
    mon_clear <= false;
    while fifo_full = '0' and n < 1100 loop
      write_event(std_logic_vector(to_unsigned(16#1000000# + n, 48)),
                  std_logic_vector(to_unsigned(n, 16)));
      n := n + 1;
      if fifo_half = '1' and half_at < 0 then
        half_at := n;
      end if;
    end loop;
    report "T3 events accepted before FIFO full: " & integer'image(n) &
           ", prog_full (half) first seen after event " & integer'image(half_at);
    check(n = 1026, "T3 capacity is 1025 in the FIFO + 1 held by the generator");
    check(half_at = 513, "T3 prog_full asserts at 512 events in the FIFO");

    ---------------------------------------------------------------- T4
    report "--- T4: drain";
    bat <= x"7FFFFFFFFFFF";                  -- every event is now due
    wait for 1100 us;
    check(fifo_empty = '1' and running = '0', "T4 FIFO drained");
    check(strobes = n, "T4 every event output once (" & integer'image(strobes) &
                       " of " & integer'image(n) & ")");
    check(order_errors = 0, "T4 events output in the order written");
    report "T4 half-empty (prog_full falling) after " &
           integer'image(strobes_at_half_drop) & " events output";
    -- The negate threshold is 511; where the flag actually drops depends on
    -- how the model counts (and the v13 model does not model the clock
    -- domain synchronisation delay), so allow a couple of entries either way.
    check(strobes_at_half_drop >= n - 1 - 511 and strobes_at_half_drop <= n - 1 - 509,
          "T4 half-empty within 2 entries of the 511 negate threshold (" &
          integer'image(n - 1 - strobes_at_half_drop) & " left)");

    ---------------------------------------------------------------- T5
    report "--- T5: one-cycle FIFO reset";
    bat <= (others => '0');
    for i in 0 to 9 loop
      write_event(std_logic_vector(to_unsigned(16#1000000# + i, 48)), x"5555");
    end loop;
    wait for 10 us;
    check(fifo_empty = '0', "T5 FIFO holds events before reset");
    writew(0, x"0004");
    wait for 10 us;
    check(fifo_empty = '1' and fifo_full = '0',
          "T5 one-bclk reset pulse empties the FIFO (v13 model)");

    wait for 2 us;
    if failures = 0 then report "RESULT: ALL PASS";
    else report "RESULT: " & integer'image(failures) & " FAILURE(S)"; end if;
    done <= true;
    wait;
  end process;
end architecture;

-- Testbench for the ident read power-up wait and retry (ident_read_s_m).
--
-- A behavioural stand-in for onewire_ctrl answers each read strobe after a
-- few clocks, with the block's data or, for a set number of attempts, with
-- error (no presence pulse) and junk on the data lines.  Block 0 fails three
-- times and then reads, as the EEPROM did at power-up; block 2 never reads.
--
--   T1  no read is attempted until POWERUP_WAIT clocks after reset
--   T2  block 0 is retried until it reads, RETRY_WAIT clocks apart, and is
--       stored with its data, not zeros or junk
--   T3  block 2 gives up after MAX_RETRIES retries and is stored as zeros
--   T4  every other block reads first time and is stored with its data
--   T5  the read finishes (read_prom_done)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_ident is
end entity;

architecture sim of tb_ident is
  constant CLK_PERIOD   : time    := 32 ns;   -- 31.25 MHz
  constant POWERUP_WAIT : natural := 200;
  constant RETRY_WAIT   : natural := 50;
  constant MAX_RETRIES  : natural := 4;
  constant BUSY_CLKS    : natural := 20;
  constant BLOCKS       : natural := 16;

  type nat_array is array (0 to BLOCKS - 1) of natural;
  -- Attempts that fail before a block reads.  Block 2 always fails.
  constant FAILS : nat_array := (0 => 3, 2 => 1000, others => 0);

  signal clk     : std_logic := '0';
  signal reset   : std_logic := '1';
  signal rd_data : std_logic_vector(63 downto 0) := (others => '0');
  signal rd_addr : std_logic_vector(7 downto 0);
  signal strobe  : std_logic;
  signal running : std_logic := '0';
  signal ow_error : std_logic := '0';
  signal done    : std_logic;
  signal ram_rd_addr : std_logic_vector(4 downto 0) := "00000";
  signal ram_data    : std_logic_vector(63 downto 0);

  signal attempts    : nat_array := (others => 0);
  signal last_start  : nat_array := (others => 0);
  signal min_gap     : natural := natural'high;  -- clocks between block 0 attempts
  signal cycle       : natural := 0;
  signal first_start : natural := 0;
  signal started     : boolean := false;
  signal failures    : natural := 0;
  signal finished    : boolean := false;

  function pattern(b : natural) return std_logic_vector is
    variable v : std_logic_vector(63 downto 0);
  begin
    for i in 0 to 7 loop
      v(8 * i + 7 downto 8 * i) := std_logic_vector(to_unsigned(16 * b + i + 1, 8));
    end loop;
    return v;
  end function;
begin
  clk <= not clk after CLK_PERIOD / 2 when not finished;

  dut : entity work.ident_read_s_m
    generic map (POWERUP_WAIT => POWERUP_WAIT, RETRY_WAIT => RETRY_WAIT,
                 MAX_RETRIES => MAX_RETRIES)
    port map (
      clk => clk, reset => reset,
      onewire_read_data => rd_data, onewire_read_address => rd_addr,
      onewire_read_strobe => strobe, one_wire_running => running,
      one_wire_error => ow_error, re_read_prom => '0', read_prom_done => done,
      ident_ram_addr_rd => ram_rd_addr, ident_ram_data_read => ram_data);

  -- onewire_ctrl stand-in: ow_error is cleared by a strobe and set at the end
  -- of a transaction the device did not answer, as in onewire_ctrl.
  onewire : process(clk)
    variable busy : natural := 0;
    variable b    : natural;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        cycle <= 0;
      else
        cycle <= cycle + 1;
      end if;
      if strobe = '1' and running = '0' then
        b := to_integer(unsigned(rd_addr(7 downto 3)));
        if not started then
          first_start <= cycle;
          started <= true;
        end if;
        if b = 0 and attempts(0) > 0 and cycle - last_start(0) < min_gap then
          min_gap <= cycle - last_start(0);
        end if;
        last_start(b) <= cycle;
        attempts(b) <= attempts(b) + 1;
        ow_error <= '0';
        running <= '1';
        busy := BUSY_CLKS;
      elsif running = '1' then
        if busy = 0 then
          running <= '0';
          b := to_integer(unsigned(rd_addr(7 downto 3)));
          if attempts(b) <= FAILS(b) then
            ow_error <= '1';
            rd_data <= x"DEADBEEFDEADBEEF";
          else
            rd_data <= pattern(b);
          end if;
        else
          busy := busy - 1;
        end if;
      end if;
    end if;
  end process;

  stim : process
    procedure check(cond : boolean; msg : string) is
    begin
      if cond then report "PASS: " & msg;
      else report "FAIL: " & msg severity error; failures <= failures + 1; end if;
    end procedure;
    variable ok : boolean;
  begin
    wait for 5 * CLK_PERIOD;
    wait until falling_edge(clk);
    reset <= '0';

    wait until done = '1' for 100 us;
    check(done = '1', "T5 read finished");

    check(started and first_start >= POWERUP_WAIT,
          "T1 first read " & integer'image(first_start) &
          " clocks after reset, wait is " & integer'image(POWERUP_WAIT));

    check(attempts(0) = FAILS(0) + 1,
          "T2 block 0 read in " & integer'image(attempts(0)) & " attempts");
    check(min_gap >= RETRY_WAIT,
          "T2 block 0 retries " & integer'image(min_gap) & " clocks apart");
    ram_rd_addr <= "00000";
    wait for CLK_PERIOD;
    check(ram_data = pattern(0), "T2 block 0 stored with its data");

    check(attempts(2) = MAX_RETRIES + 1,
          "T3 block 2 tried " & integer'image(attempts(2)) & " times");
    ram_rd_addr <= "00010";
    wait for CLK_PERIOD;
    check(ram_data = x"0000000000000000", "T3 block 2 stored as zeros");

    ok := true;
    for b in 0 to BLOCKS - 1 loop
      if b /= 0 and b /= 2 then
        ram_rd_addr <= std_logic_vector(to_unsigned(b, 5));
        wait for CLK_PERIOD;
        if ram_data /= pattern(b) or attempts(b) /= 1 then
          report "block " & integer'image(b) & " wrong" severity error;
          ok := false;
        end if;
      end if;
    end loop;
    check(ok, "T4 other blocks read first time with their data");

    wait for CLK_PERIOD;
    if failures = 0 then report "RESULT: ALL PASS";
    else report "RESULT: " & integer'image(failures) & " FAILURE(S)"; end if;
    finished <= true;
    wait;
  end process;
end architecture;

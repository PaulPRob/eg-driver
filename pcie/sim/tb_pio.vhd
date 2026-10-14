-- Testbench for PIO_EP (RX + TX engines) with a behavioural TRN model.
--
-- Scenarios
--   A  single 1-DW MRd                         -> 1 CplD, SC, 1 rd_en cycle
--   E  1-DW MWr then MRd                       -> write delivered, CplD
--   B  MRd with the core stalling DW1 of CplD  -> rd_en must stay 1 cycle
--   D  2-DW MRd (unsupported length)           -> Cpl with UR, no rd_en
--   C  two MRds back to back, core stalling the
--      CplD EOF beat for 10 cycles             -> both CplDs must arrive
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_pio is
end entity;

architecture sim of tb_pio is
  constant CLK_PERIOD : time := 16 ns;

  signal clk   : std_logic := '0';
  signal rst_n : std_logic := '0';

  signal trn_td         : std_logic_vector(31 downto 0);
  signal trn_tsof_n     : std_logic;
  signal trn_teof_n     : std_logic;
  signal trn_tsrc_rdy_n : std_logic;
  signal trn_tsrc_dsc_n : std_logic;
  signal trn_tdst_rdy_n : std_logic;

  signal trn_rd         : std_logic_vector(31 downto 0) := (others => '0');
  signal trn_rsof_n     : std_logic := '1';
  signal trn_reof_n     : std_logic := '1';
  signal trn_rsrc_rdy_n : std_logic := '1';
  signal trn_rdst_rdy_n : std_logic;

  signal req_compl, compl_done : std_logic;

  signal wr_en    : std_logic;
  signal rd_en    : std_logic;
  signal rd_addr  : std_logic_vector(10 downto 0);
  signal rd_be    : std_logic_vector(3 downto 0);
  signal wr_addr  : std_logic_vector(10 downto 0);
  signal wr_be    : std_logic_vector(7 downto 0);
  signal wr_data  : std_logic_vector(31 downto 0);
  signal rd_data  : std_logic_vector(31 downto 0) := (others => '0');

  -- register model
  signal rd_en_cycles : natural := 0;   -- total cycles rd_en was high
  signal rd_en_pulses : natural := 0;   -- rising edges of rd_en
  signal rd_en_q      : std_logic := '0';
  signal writes       : natural := 0;
  signal last_wr_data : std_logic_vector(31 downto 0) := (others => '0');

  -- completion sink
  type dw_array is array (natural range <>) of std_logic_vector(31 downto 0);
  signal stall_beat : integer := -1;    -- beat index to stall, -1 = none
  signal stall_len  : natural := 0;
  signal stall_cnt  : natural := 0;
  signal beat_idx   : natural := 0;
  signal cpl_count  : natural := 0;
  signal last_status: std_logic_vector(2 downto 0) := "000";
  signal last_fmt   : std_logic_vector(6 downto 0) := (others => '0');
  signal last_tag   : std_logic_vector(7 downto 0) := (others => '0');
  signal last_data  : std_logic_vector(31 downto 0) := (others => '0');
  signal last_beats : natural := 0;

  signal failures : natural := 0;
  signal done     : boolean := false;
begin
  clk <= not clk after CLK_PERIOD / 2 when not done;

  dut : entity work.PIO_EP
    port map (
      clk => clk, rst_n => rst_n,
      trn_td => trn_td, trn_tsof_n => trn_tsof_n, trn_teof_n => trn_teof_n,
      trn_tsrc_rdy_n => trn_tsrc_rdy_n, trn_tsrc_dsc_n => trn_tsrc_dsc_n,
      trn_tdst_rdy_n => trn_tdst_rdy_n, trn_tdst_dsc_n => '1',
      trn_rd => trn_rd, trn_rsof_n => trn_rsof_n, trn_reof_n => trn_reof_n,
      trn_rsrc_rdy_n => trn_rsrc_rdy_n, trn_rsrc_dsc_n => '1',
      trn_rbar_hit_n => "1111110", trn_rdst_rdy_n => trn_rdst_rdy_n,
      req_compl_o => req_compl, compl_done_o => compl_done,
      cfg_completer_id => x"0300", cfg_bus_mstr_enable => '1',
      wr_en_o => wr_en, rd_addr_o => rd_addr, rd_be_o => rd_be,
      wr_addr_o => wr_addr, wr_be_o => wr_be, wr_data_o => wr_data,
      wr_busy_i => wr_en, rd_data_i => rd_data, rd_en_o => rd_en);

  -- Register model: like eg_registers, data is captured on each rd_en cycle.
  -- The returned value carries the pulse count so repeated reads show up.
  regs : process(clk)
  begin
    if rising_edge(clk) then
      rd_en_q <= rd_en;
      if rd_en = '1' then
        rd_en_cycles <= rd_en_cycles + 1;
        rd_data <= x"DA" & std_logic_vector(to_unsigned(rd_en_cycles + 1, 8)) &
                   "00000" & rd_addr;
        if rd_en_q = '0' then
          rd_en_pulses <= rd_en_pulses + 1;
        end if;
      end if;
      if wr_en = '1' then
        writes <= writes + 1;
        last_wr_data <= wr_data;
      end if;
    end if;
  end process;

  -- Completion sink.  dst_rdy is combinational so a stall can be placed on
  -- an exact beat of the TLP.
  trn_tdst_rdy_n <= '1' when trn_tsrc_rdy_n = '0' and beat_idx = stall_beat
                             and stall_cnt < stall_len else '0';

  sink : process(clk)
    variable hdr : dw_array(0 to 3);
  begin
    if rising_edge(clk) then
      if trn_tsrc_rdy_n = '0' and trn_tdst_rdy_n = '1' then
        stall_cnt <= stall_cnt + 1;
      end if;
      if trn_tsrc_rdy_n = '0' and trn_tdst_rdy_n = '0' then
        stall_cnt <= 0;
        if beat_idx <= 3 then
          hdr(beat_idx) := trn_td;
        end if;
        if trn_teof_n = '0' then
          cpl_count   <= cpl_count + 1;
          last_fmt    <= hdr(0)(30 downto 24);
          last_status <= hdr(1)(15 downto 13);
          last_tag    <= hdr(2)(15 downto 8);
          last_data   <= hdr(3);
          last_beats  <= beat_idx + 1;
          beat_idx    <= 0;
        else
          beat_idx <= beat_idx + 1;
        end if;
      end if;
    end if;
  end process;

  stim : process
    procedure send(dws : dw_array) is
    begin
      for i in dws'range loop
        trn_rd         <= dws(i);
        trn_rsof_n     <= '0' when i = dws'low  else '1';
        trn_reof_n     <= '0' when i = dws'high else '1';
        trn_rsrc_rdy_n <= '0';
        loop
          wait until rising_edge(clk);
          exit when trn_rdst_rdy_n = '0';
        end loop;
      end loop;
      trn_rsrc_rdy_n <= '1';
      trn_rsof_n <= '1';
      trn_reof_n <= '1';
    end procedure;

    -- 3DW MRd header: length, requester 0100, tag, BEs, BAR0 + addr
    function mrd(len : natural; tag : natural; addr : natural) return dw_array is
      variable h : dw_array(0 to 2) := (others => (others => '0'));
    begin
      h(0)(9 downto 0) := std_logic_vector(to_unsigned(len, 10));
      h(1) := x"0100" & std_logic_vector(to_unsigned(tag, 8)) & x"0F";
      if len > 1 then
        h(1)(7 downto 4) := x"F";   -- last BE
      end if;
      h(2) := x"F0000" & std_logic_vector(to_unsigned(addr, 12));
      return h;
    end function;

    -- wait for cpl_count to reach n, or time out
    procedure wait_cpl(n : natural; ok : out boolean) is
    begin
      for i in 1 to 200 loop
        wait until rising_edge(clk);
        if cpl_count >= n then
          ok := true;
          return;
        end if;
      end loop;
      ok := false;
    end procedure;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "PASS: " & msg;
      else
        report "FAIL: " & msg severity error;
        failures <= failures + 1;
      end if;
    end procedure;

    function alive(b : boolean) return string is
    begin
      if b then return "alive"; else return "LOCKED UP"; end if;
    end function;

    variable ok : boolean;
    variable c0, p0, cyc0 : natural;
  begin
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);
    rst_n <= '1';
    wait for 5 * CLK_PERIOD;
    wait until rising_edge(clk);

    ---------------------------------------------------------------- A
    report "--- A: single 1-DW MRd";
    c0 := cpl_count; p0 := rd_en_pulses; cyc0 := rd_en_cycles;
    send(mrd(1, 16#11#, 16#04#));
    wait_cpl(c0 + 1, ok);
    check(ok, "A completion received");
    if ok then
      check(last_fmt = "1001010", "A is a CplD");
      check(last_status = "000", "A status is SC");
      check(last_tag = x"11", "A tag echoed");
      -- rd_addr(10:9) is the BAR region select ("01" for BAR0)
      check(last_data(8 downto 0) = "000000001", "A data from register 0x04");
    end if;
    wait for 4 * CLK_PERIOD;
    check(rd_en_pulses - p0 = 1 and rd_en_cycles - cyc0 = 1,
          "A rd_en exactly one cycle (cycles=" &
          integer'image(rd_en_cycles - cyc0) & ")");

    ---------------------------------------------------------------- E
    report "--- E: MWr then MRd";
    send((x"40000001", x"0100000F", x"F0000008", x"12345678"));
    wait for 6 * CLK_PERIOD;
    check(last_wr_data = x"12345678", "E write delivered");
    c0 := cpl_count;
    send(mrd(1, 16#22#, 16#08#));
    wait_cpl(c0 + 1, ok);
    check(ok and last_tag = x"22", "E read after write completed");

    ---------------------------------------------------------------- B
    report "--- B: MRd, core stalls CplD DW1 for 6 cycles";
    c0 := cpl_count; p0 := rd_en_pulses; cyc0 := rd_en_cycles;
    stall_beat <= 1; stall_len <= 6;
    send(mrd(1, 16#33#, 16#04#));
    wait_cpl(c0 + 1, ok);
    stall_beat <= -1;
    check(ok and last_tag = x"33", "B completion received");
    wait for 4 * CLK_PERIOD;
    check(rd_en_cycles - cyc0 = 1,
          "B rd_en exactly one cycle under back-pressure (cycles=" &
          integer'image(rd_en_cycles - cyc0) & ")");

    ---------------------------------------------------------------- D
    report "--- D: 2-DW MRd (unsupported length)";
    c0 := cpl_count; cyc0 := rd_en_cycles;
    send(mrd(2, 16#44#, 16#04#));
    wait_cpl(c0 + 1, ok);
    check(ok, "D completion received (no completion timeout)");
    if ok then
      check(last_fmt = "0001010", "D is a Cpl (no data)");
      check(last_status = "001", "D status is UR");
      check(last_tag = x"44", "D tag echoed");
      check(last_beats = 3, "D is 3 DW long");
    end if;
    wait for 4 * CLK_PERIOD;
    check(rd_en_cycles = cyc0, "D caused no register read");
    -- the engine must still work afterwards
    c0 := cpl_count;
    send(mrd(1, 16#45#, 16#04#));
    wait_cpl(c0 + 1, ok);
    check(ok and last_tag = x"45" and last_status = "000",
          "D normal read after UR completed");

    ---------------------------------------------------------------- C
    report "--- C: two MRds back to back, core stalls CplD EOF for 10 cycles";
    c0 := cpl_count;
    stall_beat <= 3; stall_len <= 10;
    send(mrd(1, 16#55#, 16#04#));
    send(mrd(1, 16#66#, 16#00#));
    wait_cpl(c0 + 2, ok);
    stall_beat <= -1;
    check(ok, "C both completions received (got " &
          integer'image(cpl_count - c0) & " of 2)");
    if ok then
      check(last_tag = x"66", "C second completion has the second tag");
    end if;
    -- and the endpoint must still answer
    c0 := cpl_count;
    send(mrd(1, 16#77#, 16#04#));
    wait_cpl(c0 + 1, ok);
    check(ok, "C endpoint still answers afterwards");

    ---------------------------------------------------------------- G
    -- Sweep: N reads queued back to back, every CplD EOF stalled for S
    -- cycles.  Reports completions received and whether the endpoint
    -- still answers a probe read afterwards (a permanent lock-up would not).
    report "--- G: sweep of EOF stall length and queue depth";
    for nreads in 2 to 3 loop
      for s in 0 to 12 loop
        c0 := cpl_count;
        stall_beat <= 3; stall_len <= s;
        for r in 1 to nreads loop
          send(mrd(1, 16#80# + r, 16#04#));
        end loop;
        wait_cpl(c0 + nreads, ok);
        stall_beat <= -1;
        p0 := cpl_count - c0;
        wait for 20 * CLK_PERIOD;
        c0 := cpl_count;
        send(mrd(1, 16#F0#, 16#04#));
        wait_cpl(c0 + 1, ok);
        check(p0 = nreads and ok,
              "G reads=" & integer'image(nreads) & " stall=" & integer'image(s) &
              ": " & integer'image(p0) & "/" & integer'image(nreads) &
              " completions, endpoint " & alive(ok));
        exit when not ok;
      end loop;
    end loop;

    wait for 10 * CLK_PERIOD;
    if failures = 0 then
      report "RESULT: ALL PASS";
    else
      report "RESULT: " & integer'image(failures) & " FAILURE(S)";
    end if;
    done <= true;
    wait;
  end process;
end architecture;

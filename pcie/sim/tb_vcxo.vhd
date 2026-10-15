-- Testbench for vcxo_clk and the VCXO_MHZ generic: the VCXO input, the
-- 16 MHz it produces, the eg_clk_reset hold, and the BAT phase lock loop
-- through eg_sub_sys.
--
-- The VCXO is modelled here.  Its frequency is
--   VCXO_MHZ * (1 + OFFSET + control)
-- where control is clamped to +/-PULL and comes from a charge pump and loop
-- filter driven by UP/DOWN: each pump pulse adds KI * width to an
-- integrator and sets a proportional term KP * width until the next pulse.
-- The gains give a critically damped loop with a ~20 us time constant once
-- the phase error is within the linear range (a few ns); larger errors slew
-- at the PULL limit.  They are chosen to keep the run short, not to match
-- the real loop filter.
--
-- BAT is a 1 MHz reference with rising edges exactly 1 us apart and high
-- for 1/3 or 2/3 of each period (serial data bits), as pll_pump expects.
--
-- Tests (run with VCXO_MHZ = 16 and 50):
--   T1  locked: '1' at once when direct, PLL locks when VCXO_MHZ /= 16
--   T2  CLKT starts 65536 cycles of 16 MHz after lock (eg_clk_reset hold)
--   T3  16 MHz is exactly VCXO * 16 / VCXO_MHZ (edge count ratio)
--   T4  the BAT loop locks: out_of_lock clears and stays clear, CLKT is
--       1 MHz to < 1 ppm and its rising edge is within 10 ns of BAT's
--   T5  (PLL only) VCXO stops for 20 us: locked drops, CLKT stops at once,
--       the PLL relocks when the VCXO returns, CLKT restarts after the hold
--       and the BAT loop locks again
--
-- Needs --timeprecision_vhdl 1fs: one ppm of a 20 ns period is 20 fs.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_vcxo is
  generic (
    VCXO_MHZ : integer := 50
    );
end entity;

architecture sim of tb_vcxo is
  constant F_NOM     : real := real(VCXO_MHZ) * 1.0e6;
  constant OFFSET    : real := 50.0e-6;   -- free-running error of the VCXO
  constant PULL      : real := 250.0e-6;  -- tuning range either side
  constant KP        : real := 1.0e5;     -- per second of pump pulse
  constant KI        : real := 2.5e3;
  constant BAT_PHASE : time := 337 ns;    -- first BAT rising edge
  constant HOLD      : time := 65544 * 62.5 ns;  -- 65536 hold + 8 to CLKT

  signal vcxo        : std_logic := '0';
  signal vcxo_run    : boolean := true;
  signal bclk        : std_logic := '0';
  signal trn_reset_n : std_logic := '0';
  signal bat         : std_logic := '0';
  signal y_int       : real := 0.0;
  signal y_prop      : real := 0.0;

  signal vco_16m, locked              : std_logic;
  signal up, down, clkt, out_of_lock  : std_logic;

  signal n_vcxo, n_16m, n_clkt : natural := 0;
  signal t_clkt, t_bat         : time := 0 ns;
  signal n_pll_rst             : natural := 0;
  signal done                  : boolean := false;

  component vcxo_clk is
    generic (VCXO_MHZ : integer);
    port (
      vco_in  : in  std_logic;
      bclk    : in  std_logic;
      vco_16m : out std_logic;
      locked  : out std_logic
      );
  end component;

  function clamp(x, lim : real) return real is
  begin
    if x > lim then return lim;
    elsif x < -lim then return -lim;
    else return x;
    end if;
  end function;

  function to_us(t : time) return string is
  begin
    return real'image(real(t / 1 ns) / 1000.0) & " us";
  end function;

begin

  bclk <= not bclk after 8 ns when not done;
  trn_reset_n <= '1' after 1 us;

  -- VCXO: half periods accumulated in fs with the fraction carried, so the
  -- mean frequency is exact.
  vcxo_p : process
    variable frac : real := 0.0;
    variable n    : integer;
  begin
    if done then
      wait;
    end if;
    if not vcxo_run then
      vcxo <= '0';
      wait until vcxo_run;
      frac := 0.0;
    end if;
    frac := frac + 0.5e15 /
            (F_NOM * (1.0 + OFFSET + clamp(y_int + y_prop, PULL)));
    n := integer(floor(frac));
    frac := frac - real(n);
    wait for n * 1 fs;
    vcxo <= not vcxo;
  end process;

  -- Charge pump and loop filter.  UP low: BAT leads CLKT, speed up.
  pump_p : process(up, down)
    variable t0  : time := 0 ns;
    variable sgn : integer := 0;
    variable cur : integer;
    variable e   : real;
  begin
    if up = '0' then
      cur := 1;
    elsif down = '0' then
      cur := -1;
    else
      cur := 0;
    end if;
    if cur /= sgn then
      if sgn /= 0 then
        e := real(sgn) * real((now - t0) / 1 fs) * 1.0e-15;
        y_int  <= clamp(y_int + KI * e, PULL);
        y_prop <= clamp(KP * e, PULL);
      end if;
      sgn := cur;
      t0  := now;
    end if;
  end process;

  bat_p : process
    variable lfsr : unsigned(15 downto 0) := x"ACE1";
  begin
    wait for BAT_PHASE;
    while not done loop
      bat <= '1';
      if lfsr(0) = '1' then
        wait for 667 ns;
        bat <= '0';
        wait for 333 ns;
      else
        wait for 333 ns;
        bat <= '0';
        wait for 667 ns;
      end if;
      lfsr := (lfsr(0) xor lfsr(2) xor lfsr(3) xor lfsr(5)) & lfsr(15 downto 1);
    end loop;
    wait;
  end process;

  n_vcxo <= n_vcxo + 1 when rising_edge(vcxo);
  n_16m  <= n_16m + 1 when rising_edge(vco_16m);
  n_clkt <= n_clkt + 1 when rising_edge(clkt);
  t_clkt <= now when rising_edge(clkt);
  t_bat  <= now when rising_edge(bat);

  -- a component, so cfg_tb_vcxo can bind bufio2_sim inside it
  u_vcxo : vcxo_clk
    generic map (VCXO_MHZ => VCXO_MHZ)
    port map (
      vco_in  => vcxo,
      bclk    => bclk,
      vco_16m => vco_16m,
      locked  => locked
      );

  u_sub : entity work.eg_sub_sys
    port map (
      bat_serial => bat, up => up, down => down,
      vco_16m => vco_16m, vco_locked => locked,
      se_event_out => open, se_event_strobe => open,
      clkb_2mhz => open, clkb_8mhz => open, clkdata => open,
      clkd_1mhz => open, clkq_1mhz => open, clkt_1mhz => clkt,
      cntr_in => '0', cntr_out => open,
      t2ppms => open, t4ppms => open, t8ppms => open, t16ppms => open,
      t31ppms => open, t62ppms => open, t125khz => open, t250khz => open,
      t500khz => open, unused_input => '0', x1sclk => open, x1sec => open,
      xfs => open, extint0 => '0', ext_trig0 => '0', ext_trig1 => '0',
      msclk => open, wf_out => open, event_out => open, event_strobe => open,
      out_of_lock => out_of_lock, running => open,
      onewire_oe => open, onewire_o => open, onewire_i => '1',
      write_ident_fifo_data => x"00", write_ident_fifo_load => '0',
      write_ident_fifo_reset => '0',
      clocks => open, trn_reset_n => trn_reset_n, bclk => bclk,
      master_control => (others => '0'),
      interrupt_control => (others => '0'),
      clear_interrupts => (others => '0'), interrupt_status => open,
      event_output_control => (others => '0'),
      waveform_control => (others => '0'),
      master_status => open, event_output_status => open,
      waveform_status => open,
      frame_byte => open, frame_byte_load => '0', async_event_read => open,
      async_event_write => (others => '0'), async_event_write_load => '0',
      ls_sync_event => x"00", ls_sync_event_load => '0',
      ms_sync_event => x"00", ms_sync_event_load => '0',
      rising_control => (others => '0'), clear_rising => (others => '0'),
      rising_status => open,
      falling_control => (others => '0'), clear_falling => (others => '0'),
      falling_status => open,
      lint1 => open, ident_serial_out_address_inc => '0'
      );

  -- counts watchdog resets; after u_vcxo so the external name is elaborated
  b_rst_count : block
    alias pll_rst is <<signal .tb_vcxo.u_vcxo.sig_pll_rst : std_logic>>;
  begin
    n_pll_rst <= n_pll_rst + 1 when rising_edge(pll_rst);
  end block;

  main : process
    variable failures : natural := 0;

    procedure check(cond : boolean; msg : string) is
    begin
      if cond then
        report "PASS: " & msg;
      else
        report "FAIL: " & msg severity error;
        failures := failures + 1;
      end if;
    end procedure;

    -- T2: CLKT must not run during the hold, then start HOLD after lock.
    procedure check_hold(t_lock : time; tag : string) is
      variable n0 : natural;
      variable d  : time;
    begin
      n0 := n_clkt;
      wait until rising_edge(clkt) for HOLD + 100 us;
      d := now - t_lock;
      wait for 1 ns;                    -- let the edge counters update
      report "T2 " & tag & ": first CLKT edge " & to_us(d) & " after lock";
      check(n_clkt = n0 + 1, tag & ": no CLKT edge during the reset hold");
      -- the VCXO may be at the edge of its pull range: allow +/-0.1%
      check(d > HOLD * 0.999 and d < HOLD * 1.001,
            tag & ": CLKT starts 65536 x 62.5 ns after lock");
    end procedure;

    -- T4: wait for the BAT loop to lock, then check it over 1 ms.
    procedure check_bat_lock(tag : string) is
      variable t0, t1, ph : time;
      variable n0         : natural;
      variable ppm        : real;
    begin
      t0 := now;
      wait until out_of_lock = '0' for 10 ms;
      check(out_of_lock = '0', tag & ": out_of_lock clears");
      report "T4 " & tag & ": out_of_lock cleared " & to_us(now - t0) &
        " after CLKT started";

      -- let the loop settle, then measure over exactly 1000 CLKT periods
      wait for 500 us;
      wait until rising_edge(clkt);
      t0 := now;
      wait for 1 ns;
      n0 := n_clkt;
      wait until n_clkt = n0 + 1000 for 1001 us;
      check(n_clkt = n0 + 1000, tag & ": CLKT keeps running");
      check(out_of_lock = '0' and out_of_lock'last_event >= now - t0,
            tag & ": out_of_lock stays clear for 1 ms");
      t1 := t_clkt;
      ppm := real((t1 - t0 - 1 ms) / 1 ps) / 1000.0;
      report "T4 " & tag & ": CLKT frequency error " & real'image(ppm) &
        " ppm";
      check(abs(ppm) < 1.0, tag & ": CLKT is 1 MHz to < 1 ppm");

      -- phase of CLKT's rising edge against BAT's (CLKT late is positive)
      wait until rising_edge(clkt);
      wait for 1 ns;
      ph := t_clkt - t_bat;
      if ph > 500 ns then
        ph := ph - 1 us;
      end if;
      report "T4 " & tag & ": CLKT - BAT phase " &
        integer'image(ph / 1 fs) & " fs";
      check(abs(ph) < 10 ns, tag & ": CLKT edge within 10 ns of BAT edge");
    end procedure;

    variable t_lock, t_loss : time;
    variable a16, av, b16, bv, expect, n0 : natural;

  begin
    report "--- tb_vcxo, VCXO_MHZ = " & integer'image(VCXO_MHZ);

    -- T1
    if VCXO_MHZ = 16 then
      wait for 1 ns;
      check(locked = '1', "direct: locked is '1' from the start");
      t_lock := 0 ns;
    else
      wait until locked = '1' for 1 ms;
      check(locked = '1', "PLL locks to the VCXO");
      t_lock := now;
      report "T1 PLL locked at " & to_us(t_lock);
    end if;

    -- T2
    check_hold(t_lock, "startup");

    -- T3: count VCXO edges across 1600 cycles of 16 MHz
    wait until rising_edge(vco_16m);
    wait for 1 ns;
    a16 := n_16m;
    av  := n_vcxo;
    wait until n_16m = a16 + 1600;
    wait for 1 ns;
    bv := n_vcxo;
    expect := 1600 * VCXO_MHZ / 16;
    report "T3 " & integer'image(bv - av) & " VCXO cycles in 1600 of 16 MHz";
    check(bv - av >= expect - 1 and bv - av <= expect + 1,
          "16 MHz = VCXO x 16 / " & integer'image(VCXO_MHZ));

    -- T4
    check_bat_lock("startup");

    -- T5
    if VCXO_MHZ /= 16 then
      vcxo_run <= false;
      wait until locked = '0' for 20 us;
      check(locked = '0', "PLL reports loss of lock when the VCXO stops");
      t_loss := now;
      report "T5 lock lost " & to_us(t_loss);
      wait for 1 ns;
      n0 := n_clkt;
      wait for 20 us;
      vcxo_run <= true;

      wait until locked = '1' for 5 ms;
      check(locked = '1', "PLL relocks after the VCXO returns");
      t_lock := now;
      report "T5 relocked " & to_us(t_lock - t_loss) & " after loss, " &
        integer'image(n_pll_rst) & " watchdog PLL reset(s)";
      check(n_clkt = n0, "CLKT stopped while out of lock");
      check_hold(t_lock, "relock");
      check_bat_lock("relock");
    end if;

    if failures = 0 then
      report "RESULT: ALL PASS";
    else
      report "RESULT: " & integer'image(failures) & " FAILURE(S)";
    end if;
    done <= true;
    -- the PLL model keeps scheduling events after its input stops, so the
    -- simulation would never run out of events
    std.env.finish;
  end process;

end architecture;

-- Vivado's UNISIM BUFIO2 stops the simulation, so bind vcxo_clk's BUFIO2 to
-- the stand-in in bufio2_sim.vhd.
configuration cfg_tb_vcxo of tb_vcxo is
  for sim
    for u_vcxo : vcxo_clk
      use entity work.vcxo_clk(structure);
      for structure
        for gen_direct
          for vco_bufio2 : BUFIO2
            use entity work.BUFIO2(sim);
          end for;
        end for;
      end for;
    end for;
  end for;
end configuration;

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
-- File Name: pci_package.vhd
-- Contributing Authors: J.Kovac
-- Type: RTL
-- Created: 
-- Template Rev: 1.0
--
-- Title: PCI Package
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

package pci_package is

  subtype bat_t is std_logic_vector(6*8-1 downto 0);
  subtype event_t is std_logic_vector(2*8-1 downto 0);
  subtype waveforms_t is std_logic_vector(7 downto 0);

  type supplementary_interrupts_t is record
    strobe    : std_logic;
    unused2   : std_logic;
    unused1   : std_logic;
    unused0   : std_logic;
    t16ppms   : std_logic;
    t8ppms    : std_logic;
    t4ppms    : std_logic;
    t2ppms    : std_logic;
    waveforms : waveforms_t;
    event     : event_t;
  end record;

  type synchronous_event_t is record
    bat   : bat_t;
    event : event_t;
  end record;

  type master_control_t is record
    dma_enable           : std_logic;   -- Read/Write
    insert_4_wait_states : std_logic;   -- Read/Write
    grab_frame           : std_logic;   -- Write
    reset_ref_fifo       : std_logic;   -- Write
    purge_event          : std_logic;   -- Write
    serial_prom_reset    : std_logic;   -- Write
    ident_write          : std_logic;   --Write
  end record;

  type master_status_t is record
    pll                     : std_logic;  -- Read
    frame_loaded            : std_logic;  -- Read
    late_event              : std_logic;  -- Read
    event_generator_running : std_logic;  -- Read
    frame_fifo_empty        : std_logic;  -- Read
    ls_ref_fifo_empty       : std_logic;  -- Read
    ms_ref_fifo_empty       : std_logic;  -- Read
    ls_ref_fifo_half_empty  : std_logic;  -- Read
    ms_ref_fifo_half_empty  : std_logic;  -- Read
    ls_ref_fifo_full        : std_logic;  -- Read
    ms_ref_fifo_full        : std_logic;  -- Read
    serial_number           : std_logic;  -- Read
  end record;

  type interrupt_control_t is record
    ref_fifo_empty          : std_logic;  -- Read/Write
    ref_fifo_half_empty     : std_logic;  -- Read/Write
    late_event              : std_logic;  -- Read/Write
    checksum_error          : std_logic;  -- Read/Write
    false_sync              : std_logic;  -- Read/Write
    missed_sync             : std_logic;  -- Read/Write
    frame_loaded            : std_logic;  -- Read/Write
    dma_done                : std_logic;  -- Read/Write
    external_interrupt      : std_logic;  -- Read/Write
    internal_interrupt      : std_logic;  -- Read/Write
    pll_dropout             : std_logic;  -- Read/Write
    one_second              : std_logic;  -- Read/Write
    finished                : std_logic;  -- Read/Write
    supplementary_interrupt : std_logic;  -- Read/Write
    enable_interrupt        : std_logic;  -- Read/Write
  end record;

  type interrupt_status_t is record
    ref_fifo_empty          : std_logic;  -- Read
    ref_fifo_half_empty     : std_logic;  -- Read
    late_event              : std_logic;  -- Read
    checksum_error          : std_logic;  -- Read
    false_sync              : std_logic;  -- Read
    missed_sync             : std_logic;  -- Read
    frame_loaded            : std_logic;  -- Read
    dma_done                : std_logic;  -- Read
    external_interrupt      : std_logic;  -- Read
    internal_interrupt      : std_logic;  -- Read
    pll_dropout             : std_logic;  -- Read
    one_second              : std_logic;  -- Read
    finished                : std_logic;  -- Read
    supplementary_interrupt : std_logic;  -- Read
  end record;

  type interrupts_t is record
    ref_fifo_empty          : std_logic;  -- Read
    ref_fifo_half_empty     : std_logic;  -- Read
    late_event              : std_logic;  -- Read
    checksum_error          : std_logic;  -- Read
    false_sync              : std_logic;  -- Read
    missed_sync             : std_logic;  -- Read
    frame_loaded            : std_logic;  -- Read
    dma_done                : std_logic;  -- Read
    external_interrupt      : std_logic;  -- Read
    internal_interrupt      : std_logic;  -- Read
    pll_dropout             : std_logic;  -- Read
    one_second              : std_logic;  -- Read
    finished                : std_logic;  -- Read
    supplementary_interrupt : std_logic;  -- Read
  end record;

  type event_output_control_t is record
    timed_interrupt_event_line_select    : std_logic_vector(3 downto 0);  -- Read/Write
    timed_interrupt_event_line_enable    : std_logic;  -- Read/Write
    timed_interrupt_output_enable        : std_logic;  -- Read/Write
    waveform_generator_event_line_select : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_generator_event_line_enable : std_logic;  -- Read/Write
    free_run_event_strobe                : std_logic;  -- Read/Write
    expert_mode                          : std_logic;  -- Read/Write
  end record;

  type event_output_status_t is record
    waveform_generator_event_line : std_logic;  -- Read
    timed_interrupt_event_line    : std_logic;  -- Read
  end record;

  type waveform_control_t is record
    prescale_counter_0_3 : unsigned(15 downto 0);         -- Read/Write
    prescale_counter_4_7 : unsigned(15 downto 0);         -- Read/Write
    waveform_selection_0 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_1 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_2 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_3 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_4 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_5 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_6 : std_logic_vector(3 downto 0);  -- Read/Write
    waveform_selection_7 : std_logic_vector(3 downto 0);  -- Read/Write
  end record;

  type waveform_status_t is record
    waveform_output_0_state     : std_logic;  -- Read
    waveform_output_1_state     : std_logic;  -- Read
    waveform_output_2_state     : std_logic;  -- Read
    waveform_output_3_state     : std_logic;  -- Read
    waveform_output_4_state     : std_logic;  -- Read
    waveform_output_5_state     : std_logic;  -- Read
    waveform_output_6_state     : std_logic;  -- Read
    waveform_output_7_state     : std_logic;  -- Read
    waveform_output_0_3_enabled : std_logic;  -- Read
    waveform_output_4_7_enabled : std_logic;  -- Read
  end record;

  type pci_command_t is record
    not_lwr : std_logic;
    address : std_logic_vector(7 downto 0);
    not_lbe : std_logic_vector(3 downto 0);
    data    : std_logic_vector(31 downto 0);
  end record;

  function supplementary_interrupts_to_slv (supplementary_interrupts : supplementary_interrupts_t) return std_logic_vector;
  function synchronous_event_to_slv (synchronous_event               : synchronous_event_t) return std_logic_vector;
  function master_control_to_slv (master_control                     : master_control_t) return std_logic_vector;
  function master_status_to_slv (master_status                       : master_status_t) return std_logic_vector;
  function interrupt_control_to_slv (interrupt_control               : interrupt_control_t) return std_logic_vector;
  function interrupt_status_to_slv (interrupt_status                 : interrupt_status_t) return std_logic_vector;
  function interrupts_to_slv (interrupts                             : interrupts_t) return std_logic_vector;
  function event_output_control_to_slv (event_output_control         : event_output_control_t) return std_logic_vector;
  function event_output_status_to_slv (event_output_status           : event_output_status_t) return std_logic_vector;
  function waveform_control_to_slv (waveform_control                 : waveform_control_t) return std_logic_vector;
  function waveform_status_to_slv (waveform_status                   : waveform_status_t) return std_logic_vector;
  function pci_command_to_slv (pci_command                           : pci_command_t) return std_logic_vector;

  function slv_to_supplementary_interrupts(slv : std_logic_vector) return supplementary_interrupts_t;
  function slv_to_synchronous_event(slv        : std_logic_vector) return synchronous_event_t;
  function slv_to_master_control(slv           : std_logic_vector) return master_control_t;
  function slv_to_master_status(slv            : std_logic_vector) return master_status_t;
  function slv_to_interrupt_control(slv        : std_logic_vector) return interrupt_control_t;
  function slv_to_interrupt_status(slv         : std_logic_vector) return interrupt_status_t;
  function slv_to_interrupts(slv               : std_logic_vector) return interrupts_t;
  function slv_to_event_output_control(slv     : std_logic_vector) return event_output_control_t;
  function slv_to_event_output_status(slv      : std_logic_vector) return event_output_status_t;
  function slv_to_waveform_control(slv         : std_logic_vector) return waveform_control_t;
  function slv_to_waveform_status(slv          : std_logic_vector) return waveform_status_t;
  function slv_to_pci_command(slv              : std_logic_vector) return pci_command_t;

end package;

package body pci_package is

  ------------------------------------------------------------
  -- ********_TO_SLV
  function supplementary_interrupts_to_slv (supplementary_interrupts : supplementary_interrupts_t) return std_logic_vector is
    variable slv : std_logic_vector(31 downto 0);
  begin
    slv(15 downto 0)  := supplementary_interrupts.event;
    slv(23 downto 16) := supplementary_interrupts.waveforms;
    slv(24)           := supplementary_interrupts.t2ppms;
    slv(25)           := supplementary_interrupts.t4ppms;
    slv(26)           := supplementary_interrupts.t8ppms;
    slv(27)           := supplementary_interrupts.t16ppms;
    slv(28)           := supplementary_interrupts.unused0;
    slv(29)           := supplementary_interrupts.unused1;
    slv(30)           := supplementary_interrupts.unused2;
    slv(31)           := supplementary_interrupts.strobe;
    return slv;
  end;

  function synchronous_event_to_slv (synchronous_event : synchronous_event_t) return std_logic_vector is
    variable slv : std_logic_vector(63 downto 0);
  begin
    slv(47 downto 0)  := synchronous_event.bat;
    slv(63 downto 48) := synchronous_event.event;
    return slv;
  end;

  function master_control_to_slv (master_control : master_control_t) return std_logic_vector is
    variable slv : std_logic_vector(8 downto 0);
  begin
    slv(0) := master_control.dma_enable;
    slv(1) := master_control.insert_4_wait_states;
    slv(2) := master_control.grab_frame;
    slv(5) := master_control.reset_ref_fifo;
    slv(6) := master_control.purge_event;
    slv(7) := master_control.serial_prom_reset;
    slv(8) := master_control.ident_write;
    return slv;
  end;

  function master_status_to_slv (master_status : master_status_t) return std_logic_vector is
    variable slv : std_logic_vector(11 downto 0);
  begin
    slv(0)  := master_status.pll;
    slv(1)  := master_status.frame_loaded;
    slv(2)  := master_status.late_event;
    slv(3)  := master_status.event_generator_running;
    slv(4)  := master_status.frame_fifo_empty;
    slv(5)  := master_status.ls_ref_fifo_empty;
    slv(6)  := master_status.ms_ref_fifo_empty;
    slv(7)  := master_status.ls_ref_fifo_half_empty;
    slv(8)  := master_status.ms_ref_fifo_half_empty;
    slv(9)  := master_status.ls_ref_fifo_full;
    slv(10) := master_status.ms_ref_fifo_full;
    slv(11) := master_status.serial_number;
    return slv;
  end;

  function interrupt_control_to_slv (interrupt_control : interrupt_control_t) return std_logic_vector is
    variable slv : std_logic_vector(14 downto 0);
  begin
    slv(0)  := interrupt_control.ref_fifo_empty;
    slv(1)  := interrupt_control.ref_fifo_half_empty;
    slv(2)  := interrupt_control.late_event;
    slv(3)  := interrupt_control.checksum_error;
    slv(4)  := interrupt_control.false_sync;
    slv(5)  := interrupt_control.missed_sync;
    slv(6)  := interrupt_control.frame_loaded;
    slv(7)  := interrupt_control.dma_done;
    slv(8)  := interrupt_control.external_interrupt;
    slv(9)  := interrupt_control.internal_interrupt;
    slv(10) := interrupt_control.pll_dropout;
    slv(11) := interrupt_control.one_second;
    slv(12) := interrupt_control.finished;
    slv(13) := interrupt_control.supplementary_interrupt;
    slv(14) := interrupt_control.enable_interrupt;
    return slv;
  end;

  function interrupt_status_to_slv (interrupt_status : interrupt_status_t) return std_logic_vector is
    variable slv : std_logic_vector(13 downto 0);
  begin
    slv(0)  := interrupt_status.ref_fifo_empty;
    slv(1)  := interrupt_status.ref_fifo_half_empty;
    slv(2)  := interrupt_status.late_event;
    slv(3)  := interrupt_status.checksum_error;
    slv(4)  := interrupt_status.false_sync;
    slv(5)  := interrupt_status.missed_sync;
    slv(6)  := interrupt_status.frame_loaded;
    slv(7)  := interrupt_status.dma_done;
    slv(8)  := interrupt_status.external_interrupt;
    slv(9)  := interrupt_status.internal_interrupt;
    slv(10) := interrupt_status.pll_dropout;
    slv(11) := interrupt_status.one_second;
    slv(12) := interrupt_status.finished;
    slv(13) := interrupt_status.supplementary_interrupt;
    return slv;
  end;

  function interrupts_to_slv (interrupts : interrupts_t) return std_logic_vector is
    variable slv : std_logic_vector(13 downto 0);
  begin
    slv(0)  := interrupts.ref_fifo_empty;
    slv(1)  := interrupts.ref_fifo_half_empty;
    slv(2)  := interrupts.late_event;
    slv(3)  := interrupts.checksum_error;
    slv(4)  := interrupts.false_sync;
    slv(5)  := interrupts.missed_sync;
    slv(6)  := interrupts.frame_loaded;
    slv(7)  := interrupts.dma_done;
    slv(8)  := interrupts.external_interrupt;
    slv(9)  := interrupts.internal_interrupt;
    slv(10) := interrupts.pll_dropout;
    slv(11) := interrupts.one_second;
    slv(12) := interrupts.finished;
    slv(13) := interrupts.supplementary_interrupt;
    return slv;
  end;

  function event_output_control_to_slv (event_output_control : event_output_control_t) return std_logic_vector is
    variable slv : std_logic_vector(12 downto 0);
  begin
    slv(3 downto 0) := event_output_control.timed_interrupt_event_line_select;
    slv(4)          := event_output_control.timed_interrupt_event_line_enable;
    slv(5)          := event_output_control.timed_interrupt_output_enable;
    slv(9 downto 6) := event_output_control.waveform_generator_event_line_select;
    slv(10)         := event_output_control.waveform_generator_event_line_enable;
    slv(11)         := event_output_control.free_run_event_strobe;
    slv(12)         := event_output_control.expert_mode;
    return slv;
  end;

  function event_output_status_to_slv (event_output_status : event_output_status_t) return std_logic_vector is
    variable slv : std_logic_vector(1 downto 0);
  begin
    slv(0) := event_output_status.waveform_generator_event_line;
    slv(1) := event_output_status.timed_interrupt_event_line;
    return slv;
  end;

  function waveform_control_to_slv (waveform_control : waveform_control_t) return std_logic_vector is
    variable slv : std_logic_vector(63 downto 0);
  begin
    slv(15 downto 0)  := std_logic_vector(waveform_control.prescale_counter_0_3);
    slv(31 downto 16) := std_logic_vector(waveform_control.prescale_counter_4_7);
    slv(35 downto 32) := waveform_control.waveform_selection_0;
    slv(39 downto 36) := waveform_control.waveform_selection_1;
    slv(43 downto 40) := waveform_control.waveform_selection_2;
    slv(47 downto 44) := waveform_control.waveform_selection_3;
    slv(51 downto 48) := waveform_control.waveform_selection_4;
    slv(55 downto 52) := waveform_control.waveform_selection_5;
    slv(59 downto 56) := waveform_control.waveform_selection_6;
    slv(63 downto 60) := waveform_control.waveform_selection_7;
    return slv;
  end;

  function waveform_status_to_slv (waveform_status : waveform_status_t) return std_logic_vector is
    variable slv : std_logic_vector(9 downto 0);
  begin
    slv(0) := waveform_status.waveform_output_0_state;
    slv(1) := waveform_status.waveform_output_1_state;
    slv(2) := waveform_status.waveform_output_2_state;
    slv(3) := waveform_status.waveform_output_3_state;
    slv(4) := waveform_status.waveform_output_4_state;
    slv(5) := waveform_status.waveform_output_5_state;
    slv(6) := waveform_status.waveform_output_6_state;
    slv(7) := waveform_status.waveform_output_7_state;
    slv(8) := waveform_status.waveform_output_0_3_enabled;
    slv(9) := waveform_status.waveform_output_4_7_enabled;
    return slv;
  end;

  function pci_command_to_slv (pci_command : pci_command_t) return std_logic_vector is
    variable slv : std_logic_vector(44 downto 0);
  begin
    slv(0)            := pci_command.not_lwr;              --  1   0 downto  0
    slv(8 downto 1)   := pci_command.address(7 downto 0);  --  8   8 downto  1
    slv(12 downto 9)  := pci_command.not_lbe(3 downto 0);  --  4  12 downto  9
    slv(44 downto 13) := pci_command.data(31 downto 0);    -- 32  44 downto 13
    return slv;
  end;
  ------------------------------------------------------------

  ------------------------------------------------------------
  -- SLV_TO_********
  function slv_to_supplementary_interrupts(slv : std_logic_vector) return supplementary_interrupts_t is
    variable supplementary_interrupts : supplementary_interrupts_t;
  begin
    supplementary_interrupts.event     := slv(15 downto 0);
    supplementary_interrupts.waveforms := slv(23 downto 16);
    supplementary_interrupts.t2ppms    := slv(24);
    supplementary_interrupts.t4ppms    := slv(25);
    supplementary_interrupts.t8ppms    := slv(26);
    supplementary_interrupts.t16ppms   := slv(27);
    supplementary_interrupts.unused0   := slv(28);
    supplementary_interrupts.unused1   := slv(29);
    supplementary_interrupts.unused2   := slv(30);
    supplementary_interrupts.strobe    := slv(31);
    return supplementary_interrupts;
  end;

  function slv_to_synchronous_event(slv : std_logic_vector) return synchronous_event_t is
    variable synchronous_event : synchronous_event_t;
  begin
    synchronous_event.bat   := slv(47 downto 0);
    synchronous_event.event := slv(63 downto 48);
    return synchronous_event;
  end;

  function slv_to_master_control(slv : std_logic_vector) return master_control_t is
    variable master_control : master_control_t;
  begin
    master_control.dma_enable           := slv(0);
    master_control.insert_4_wait_states := slv(1);
    master_control.grab_frame           := slv(2);
    master_control.reset_ref_fifo       := slv(5);
    master_control.purge_event          := slv(6);
    master_control.serial_prom_reset    := slv(7);
    master_control.ident_write          := slv(8);
    return master_control;
  end;

  function slv_to_master_status(slv : std_logic_vector) return master_status_t is
    variable master_status : master_status_t;
  begin
    master_status.pll                     := slv(0);
    master_status.frame_loaded            := slv(1);
    master_status.late_event              := slv(2);
    master_status.event_generator_running := slv(3);
    master_status.frame_fifo_empty        := slv(4);
    master_status.ls_ref_fifo_empty       := slv(5);
    master_status.ms_ref_fifo_empty       := slv(6);
    master_status.ls_ref_fifo_half_empty  := slv(7);
    master_status.ms_ref_fifo_half_empty  := slv(8);
    master_status.ls_ref_fifo_full        := slv(9);
    master_status.ms_ref_fifo_full        := slv(10);
    master_status.serial_number           := slv(11);
    return master_status;
  end;

  function slv_to_interrupt_control(slv : std_logic_vector) return interrupt_control_t is
    variable interrupt_control : interrupt_control_t;
  begin
    interrupt_control.ref_fifo_empty          := slv(0);
    interrupt_control.ref_fifo_half_empty     := slv(1);
    interrupt_control.late_event              := slv(2);
    interrupt_control.checksum_error          := slv(3);
    interrupt_control.false_sync              := slv(4);
    interrupt_control.missed_sync             := slv(5);
    interrupt_control.frame_loaded            := slv(6);
    interrupt_control.dma_done                := slv(7);
    interrupt_control.external_interrupt      := slv(8);
    interrupt_control.internal_interrupt      := slv(9);
    interrupt_control.pll_dropout             := slv(10);
    interrupt_control.one_second              := slv(11);
    interrupt_control.finished                := slv(12);
    interrupt_control.supplementary_interrupt := slv(13);
    interrupt_control.enable_interrupt        := slv(14);
    return interrupt_control;
  end;

  function slv_to_interrupt_status(slv : std_logic_vector) return interrupt_status_t is
    variable interrupt_status : interrupt_status_t;
  begin
    interrupt_status.ref_fifo_empty          := slv(0);
    interrupt_status.ref_fifo_half_empty     := slv(1);
    interrupt_status.late_event              := slv(2);
    interrupt_status.checksum_error          := slv(3);
    interrupt_status.false_sync              := slv(4);
    interrupt_status.missed_sync             := slv(5);
    interrupt_status.frame_loaded            := slv(6);
    interrupt_status.dma_done                := slv(7);
    interrupt_status.external_interrupt      := slv(8);
    interrupt_status.internal_interrupt      := slv(9);
    interrupt_status.pll_dropout             := slv(10);
    interrupt_status.one_second              := slv(11);
    interrupt_status.finished                := slv(12);
    interrupt_status.supplementary_interrupt := slv(13);
    return interrupt_status;
  end;

  function slv_to_interrupts(slv : std_logic_vector) return interrupts_t is
    variable interrupts : interrupts_t;
  begin
    interrupts.ref_fifo_empty          := slv(0);
    interrupts.ref_fifo_half_empty     := slv(1);
    interrupts.late_event              := slv(2);
    interrupts.checksum_error          := slv(3);
    interrupts.false_sync              := slv(4);
    interrupts.missed_sync             := slv(5);
    interrupts.frame_loaded            := slv(6);
    interrupts.dma_done                := slv(7);
    interrupts.external_interrupt      := slv(8);
    interrupts.internal_interrupt      := slv(9);
    interrupts.pll_dropout             := slv(10);
    interrupts.one_second              := slv(11);
    interrupts.finished                := slv(12);
    interrupts.supplementary_interrupt := slv(13);
    return interrupts;
  end;

  function slv_to_event_output_control(slv : std_logic_vector) return event_output_control_t is
    variable event_output_control : event_output_control_t;
  begin
    event_output_control.timed_interrupt_event_line_select    := slv(3 downto 0);
    event_output_control.timed_interrupt_event_line_enable    := slv(4);
    event_output_control.timed_interrupt_output_enable        := slv(5);
    event_output_control.waveform_generator_event_line_select := slv(9 downto 6);
    event_output_control.waveform_generator_event_line_enable := slv(10);
    event_output_control.free_run_event_strobe                := slv(11);
    event_output_control.expert_mode                          := slv(12);
    return event_output_control;
  end;

  function slv_to_event_output_status(slv : std_logic_vector) return event_output_status_t is
    variable event_output_status : event_output_status_t;
  begin
    event_output_status.waveform_generator_event_line := slv(0);
    event_output_status.timed_interrupt_event_line    := slv(1);
    return event_output_status;
  end;

  function slv_to_waveform_control(slv : std_logic_vector) return waveform_control_t is
    variable waveform_control : waveform_control_t;
  begin
    waveform_control.prescale_counter_0_3 := unsigned(slv(15 downto 0));
    waveform_control.prescale_counter_4_7 := unsigned(slv(31 downto 16));
    waveform_control.waveform_selection_0 := slv(35 downto 32);
    waveform_control.waveform_selection_1 := slv(39 downto 36);
    waveform_control.waveform_selection_2 := slv(43 downto 40);
    waveform_control.waveform_selection_3 := slv(47 downto 44);
    waveform_control.waveform_selection_4 := slv(51 downto 48);
    waveform_control.waveform_selection_5 := slv(55 downto 52);
    waveform_control.waveform_selection_6 := slv(59 downto 56);
    waveform_control.waveform_selection_7 := slv(63 downto 60);
    return waveform_control;
  end;

  function slv_to_waveform_status(slv : std_logic_vector) return waveform_status_t is
    variable waveform_status : waveform_status_t;
  begin
    waveform_status.waveform_output_0_state     := slv(0);
    waveform_status.waveform_output_1_state     := slv(1);
    waveform_status.waveform_output_2_state     := slv(2);
    waveform_status.waveform_output_3_state     := slv(3);
    waveform_status.waveform_output_4_state     := slv(4);
    waveform_status.waveform_output_5_state     := slv(5);
    waveform_status.waveform_output_6_state     := slv(6);
    waveform_status.waveform_output_7_state     := slv(7);
    waveform_status.waveform_output_0_3_enabled := slv(8);
    waveform_status.waveform_output_4_7_enabled := slv(9);
    return waveform_status;
  end;

  function slv_to_pci_command(slv : std_logic_vector) return pci_command_t is
    variable pci_command : pci_command_t;
  begin
    pci_command.not_lwr             := slv(0);
    pci_command.address(7 downto 0) := slv(8 downto 1);
    pci_command.not_lbe(3 downto 0) := slv(12 downto 9);
    pci_command.data(31 downto 0)   := slv(44 downto 13);
    return pci_command;
  end;
  ------------------------------------------------------------

end package body;


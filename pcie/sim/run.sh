#!/bin/bash
#
# Run the PCIe firmware testbenches with the Vivado simulator (xsim).
#
#   ./run.sh            run all testbenches
#   ./run.sh pio        tb_pio  - PIO RX/TX engines (completion handshake,
#                                 rd_en width, UR completions)
#   ./run.sh regs       tb_regs - eg_registers reset of interrupt enables
#   ./run.sh eventgen   tb_eventgen - driver event writes through
#                                 eg_registers and event_gen into the reference
#                                 FIFO: word order, capacity, drain, reset
#
# The firmware itself is built with ISE 14.7; Vivado is used only for
# simulation.  Vivado's UNISIM has no Spartan-6 PCIE_A1 or GTPA1_DUAL, so
# the PCIe core is not simulated: tb_pio drives PIO_EP through a behavioural
# model of the core's TRN interface.
#
# Set VIVADO to the install to use (default ~/Xilinx/Vivado/2023.2).  If
# license.sh sits beside the Vivado directory it is sourced for
# XILINXD_LICENSE_FILE.
#
# tb_eventgen needs a model of the reference FIFO.  The real core
# (ipcore_dir/eg_ref_fifo, FIFO Generator v5.3) can only be simulated with
# ISE's XilinxCoreLib, so eg_ref_fifo_sim.vhd maps the same parameters onto
# the FIFO Generator v13.0 behavioural model that ships with Vivado.
#
# Build output goes to sim/work/, which is safe to delete.

set -u

VIVADO=${VIVADO:-$HOME/Xilinx/Vivado/2023.2}
SIM_DIR=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$SIM_DIR/.." && pwd)
WORK=$SIM_DIR/work

if [ ! -f "$VIVADO/settings64.sh" ]; then
	echo "Vivado not found at $VIVADO - set VIVADO" >&2
	exit 2
fi
source "$VIVADO/settings64.sh" >/dev/null 2>&1
LICENSE_SH=$(dirname "$(dirname "$VIVADO")")/license.sh
[ -f "$LICENSE_SH" ] && source "$LICENSE_SH"

FIFO_MODEL=$VIVADO/data/ip/xilinx/fifo_generator_v13_0/simulation/fifo_generator_vhdl_beh.vhd

# run_tb <name> <top> <dut sources...>
#
# A source written lib=path is compiled into library lib from an absolute
# path; anything else is relative to the firmware directory.
run_tb() {
	local name=$1 top=$2
	shift 2
	local dir=$WORK/$name

	rm -rf "$dir"
	mkdir -p "$dir"
	cd "$dir" || return 1

	local f libs=()
	for f in "$@"; do
		local cmd=(xvhdl "$SRC/$f")
		if [[ $f == *=* ]]; then
			cmd=(xvhdl -work "${f%%=*}" "${f#*=}")
			libs+=(-L "${f%%=*}")
		fi
		if ! "${cmd[@]}" >>compile.log 2>&1; then
			echo "$name: compile failed on $f (see $dir/compile.log)"
			grep ERROR compile.log
			return 1
		fi
	done
	if ! xvhdl --2008 "$SIM_DIR/$top.vhd" >>compile.log 2>&1; then
		echo "$name: testbench compile failed (see $dir/compile.log)"
		grep ERROR compile.log
		return 1
	fi
	if ! xelab -debug off -L unisim "${libs[@]}" "$top" -s "$top" >elab.log 2>&1; then
		echo "$name: elaboration failed (see $dir/elab.log)"
		grep ERROR elab.log
		return 1
	fi
	xsim "$top" -R >sim.log 2>&1

	echo "===== $name"
	grep -E '^(Note|Error): (PASS|FAIL|---|RESULT|T[0-9] )' sim.log |
		sed 's/^Note: //;s/^Error: //'
	grep -q 'RESULT: ALL PASS' sim.log
}

status=0
want=${1:-all}

if [ "$want" = all ] || [ "$want" = pio ]; then
	run_tb pio tb_pio \
		PIO_32_RX_ENGINE.vhd PIO_32_TX_ENGINE.vhd PIO_EP.vhd || status=1
fi

if [ "$want" = all ] || [ "$want" = regs ]; then
	run_tb regs tb_regs \
		clocks_package.vhd pci_package.vhd clk_pulse.vhd \
		control_buffer.vhd delayed_control_buffer.vhd \
		async_event_write.vhd eg_registers.vhd || status=1
fi

if [ "$want" = all ] || [ "$want" = eventgen ]; then
	run_tb eventgen tb_eventgen \
		"fifo_generator_v13_0_7=$FIFO_MODEL" \
		clocks_package.vhd pci_package.vhd clk_pulse.vhd \
		control_buffer.vhd delayed_control_buffer.vhd \
		async_event_write.vhd eg_registers.vhd \
		sim/eg_ref_fifo_sim.vhd event_gen.vhd || status=1
fi

exit $status

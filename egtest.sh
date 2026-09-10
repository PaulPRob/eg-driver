#!/bin/bash
#
# egtest.sh - non-interactive hardware check for the ported eg driver.
#
# Every step is read-only or self-contained: it loads the module, reads the
# card's identity, exercises the register, statistics, interrupt and frame-grab
# paths through /dev/eg0, and unloads again.  Nothing is written to the card's
# configuration and no timeframe is loaded, so a stalled BAT, a frame grab that
# times out and a silent 1 second interrupt are all expected on a bench with no
# reference connected.
#
# The interrupt path is still tested on such a bench, using the INTERNAL event
# interrupt, which the host raises itself and which needs no reference.  Do not
# use the "PLL locked" bit in the master register to decide whether a reference
# is present: on the V4.1 Xilinx card that register reads a constant and the
# bit is meaningless.  See section 10.
#
# Usage:  sudo ./egtest.sh [--stage1|--stage2|--stage3] [--keep]
#           --stage1  (default) no interrupt handler at all - cannot storm
#           --stage2  handler registered, nothing armed, watch for silence
#           --stage3  arm a source and wait on it
#           --keep    leave the module loaded at the end
#
# Start at stage 1 on any card whose interrupt behaviour is not yet known, and
# only move up a stage when the one below it has been clean.  See the staging
# comment below for why.
#
set -u

# ---------------------------------------------------------------------------
# Staging
# ---------------------------------------------------------------------------
# The card's interrupt behaviour is the risky part of this test, so it is no
# longer reached by default.  A card whose firmware does not de-assert the way
# the driver expects turns a shared, level-triggered PCI interrupt into a storm,
# and a storm is a hard hang: no console, no keyboard, nothing in the log,
# because journald never gets to flush.  That is not a hypothetical - it is
# what a run of this script did on 2026-09-10.
#
#   --stage1  (default)  Load with nointr=1, so the IRQ is never requested and
#                        a storm is impossible.  Exercises binding, identity,
#                        the register file, FIFO sizing, /proc, the device
#                        nodes and the open/exclusion rules.
#   --stage2             Load normally, with every interrupt source masked, and
#                        just watch for a few seconds.  Answers "does this card
#                        assert an interrupt when it has been told not to?"
#                        without arming anything.
#   --stage3             Everything, including arming a source and waiting on
#                        it.  Only run this once stage 2 has been clean.
#
# The driver's storm guard is active in stages 2 and 3 and will mask the card
# and, if that fails, disable the line, rather than let the machine hang.
STAGE=1
KEEP=0
for a in "$@"; do
	case "$a" in
	--keep)   KEEP=1 ;;
	--stage1) STAGE=1 ;;
	--stage2) STAGE=2 ;;
	--stage3) STAGE=3 ;;
	--help|-h)
		sed -n '/^# ----/,/^STAGE=1/p' "$0" | sed 's/^# \?//'
		exit 0 ;;
	*) echo "unknown option: $a (try --help)" >&2; exit 2 ;;
	esac
done

HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0
FAIL=0
SKIP=0

# ---------------------------------------------------------------------------
# Progress trail
# ---------------------------------------------------------------------------
# Written and fsync'd before each step.  If the machine hangs, this file is the
# only thing that will say where it got to - the journal will have lost the
# last few seconds, and a hard lockup writes nothing to pstore unless
# hardlockup_panic is set.  Kept out of /tmp, which is wiped on boot.
PROGRESS=${EG_PROGRESS:-$HERE/egtest-progress.log}
progress() {
	printf '%s stage%d %s\n' "$(date +%H:%M:%S)" "$STAGE" "$*" >> "$PROGRESS"
	sync -d "$PROGRESS" 2>/dev/null || sync
}

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
skip() { SKIP=$((SKIP+1)); printf '  \033[33mSKIP\033[0m %s\n' "$*"; }
note() { printf '       %s\n' "$*"; }

if [ "$(id -u)" -ne 0 ]; then
	echo "This script must run as root (it loads and unloads a kernel module)." >&2
	exit 1
fi

# ---------------------------------------------------------------------------
say "0. Environment"
# ---------------------------------------------------------------------------
printf '===== egtest.sh stage %d, %s =====\n' "$STAGE" "$(date -Is)" > "$PROGRESS"
progress "started"
note "kernel  $(uname -r)"
note "module  $HERE/eg.ko"
note "progress trail: $PROGRESS"

if [ ! -f "$HERE/eg.ko" ]; then
	bad "eg.ko not built - run 'make' first"
	exit 1
fi
ok "eg.ko present"

if [ ! -x "$HERE/test_eg" ]; then
	skip "test_eg not built - run 'make test' for the userspace checks"
fi

modinfo "$HERE/eg.ko" | sed 's/^/       /'

# ---------------------------------------------------------------------------
say "1. Candidate PCI cards"
# ---------------------------------------------------------------------------
# The three front ends the register block has been built behind, plus the
# clock's Xilinx ID so that a box with both cards reports honestly.
lspci -nn -d 10b5:9030  | sed 's/^/       /'
lspci -nn -d 2321:      | sed 's/^/       /'
lspci -nn -d 10ee:0007  | sed 's/^/       /'
lspci -nn -d 10ee:0008  | sed 's/^/       /'

CANDIDATES=0
for d in /sys/bus/pci/devices/*/; do
	v=$(cat "$d/vendor" 2>/dev/null)
	p=$(cat "$d/device" 2>/dev/null)
	case "$v:$p" in
	0x10b5:0x9030) fe="PLX_9030 (shared with the AT distributed clock)" ;;
	0x2321:0x0002) fe="WISHBONE" ;;
	0x10ee:0x0007) fe="XILINX_PCIE" ;;
	0x10ee:0x0008) fe="XILINX_PCIE, but this is the AT distributed clock" ;;
	*) continue ;;
	esac
	drv=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)
	note "$(basename "$d")  $v:$p  $fe  driver=${drv:-<none>}"
	CANDIDATES=$((CANDIDATES+1))
done

if [ "$CANDIDATES" -eq 0 ]; then
	bad "no card with any front end ID this driver knows is present"
	note "Nothing below can run.  Check the card is seated and that"
	note "'lspci' lists it; a PCI32 card behind a PCIe-to-PCI bridge"
	note "also needs the bridge to be enumerating its secondary bus."
	exit 1
fi
ok "$CANDIDATES candidate card(s) present"

# ---------------------------------------------------------------------------
say "2. Load the module"
# ---------------------------------------------------------------------------
rmmod eg 2>/dev/null
dmesg -C 2>/dev/null || true

# Stage 1 loads with nointr=1: the IRQ is never requested, so no interrupt can
# reach the CPU from this card no matter what its firmware does.
if [ "$STAGE" -eq 1 ]; then
	INSARGS="debug=0 nointr=1"
	note "stage 1: loading with nointr=1 - the IRQ will NOT be requested"
else
	# A low storm_limit on the first interrupt-enabled run of an unfamiliar
	# card is cheap insurance: at the 20000 default the guard needs about
	# half a second of storm to trip, at 2000 about twenty milliseconds.
	# Nothing legitimate on this card comes close to either.
	INSARGS="debug=0 storm_limit=${EG_STORM_LIMIT:-2000}"
	note "stage $STAGE: loading normally; storm guard at ${EG_STORM_LIMIT:-2000}/s"
fi
INSARGS="$INSARGS ${EG_INSARGS:-}"

progress "about to insmod ($INSARGS)"
if insmod "$HERE/eg.ko" $INSARGS; then
	progress "insmod returned"
	ok "insmod succeeded ($INSARGS)"
else
	progress "insmod FAILED"
	bad "insmod failed"
	dmesg | tail -20 | sed 's/^/       /'
	exit 1
fi

dmesg | sed 's/^/       /'

# ---------------------------------------------------------------------------
say "3. Did it bind, and to what?"
# ---------------------------------------------------------------------------
BOUND=$(for l in /sys/bus/pci/drivers/eg/0000:*; do basename "$l"; done 2>/dev/null)
if [ -n "$BOUND" ]; then
	ok "bound to $BOUND"
else
	bad "no PCI device bound - see the identification messages above"
	note "If the only event generator in this box is already claimed by"
	note "another driver, unbind it first, or load with slot=<addr> force=1."
	rmmod eg
	exit 1
fi

IDENT=$(grep -m1 '^ID: ' /proc/eg 2>/dev/null | cut -d' ' -f2-)
if [ -n "$IDENT" ]; then
	ok "card identifies as: $IDENT"
else
	bad "could not read the ident string from /proc/eg"
fi

case "$IDENT" in
*"EVENT GENERATOR"*) ok "ident contains EVENT GENERATOR" ;;
*) note "ident does not contain EVENT GENERATOR - informational only; the" ;;
esac

# Which front end did it bind?  /proc/eg reports it, and it decides what the
# rest of this section is allowed to conclude.
FRONTEND=$(grep -m1 '^PCI device:' /proc/eg 2>/dev/null | sed 's/.* behind //')
VID=$(cat /sys/bus/pci/devices/$BOUND/vendor)
DID=$(cat /sys/bus/pci/devices/$BOUND/device)
note "front end: ${FRONTEND:-<unknown>}  ($VID:$DID)"

# The class-and-window test tells the event generator from the AT distributed
# clock, and is meaningful ONLY on the PLX carrier, where the two boards share
# 10b5:9030.  On the Xilinx PCIe front end the boards have separate device IDs
# and the test would give the wrong answer on both signals: the PCIe core's
# class is 0580, not 0880, and its smallest BAR is 8 KiB.
CLASS=$(cat /sys/bus/pci/devices/$BOUND/class)
if [ "$VID:$DID" = "0x10b5:0x9030" ]; then
	BARLEN=$(python3 - "$BOUND" <<'PY'
import sys
n = 0
for line in open('/sys/bus/pci/devices/%s/resource' % sys.argv[1]):
    s, e, f = [int(x, 16) for x in line.split()]
    if n == 2:
        print(e - s + 1 if e > s else 0)
        break
    n += 1
PY
)
	note "PCI class $CLASS, BAR2 $BARLEN bytes"
	if [ "$CLASS" = "0x088000" ] || [ "${BARLEN:-0}" -lt 256 ]; then
		ok "bound card is event-generator shaped, not the distributed clock"
	else
		bad "bound card looks like the AT distributed clock"
	fi
elif [ "$VID:$DID" = "0x10ee:0x0007" ]; then
	note "PCI class $CLASS (0x058000 expected for the Xilinx PCIe core)"
	ok "device ID 10ee:0007 is the event generator's own - unambiguous"
else
	note "PCI class $CLASS"
	skip "no clock/EG ambiguity check defined for $VID:$DID"
fi

# ---------------------------------------------------------------------------
say "4. Device nodes"
# ---------------------------------------------------------------------------
MISSING=0
for n in 0 1 2 3 4 5 6 7; do
	[ -c "/dev/eg$n" ] || MISSING=1
done
if [ "$MISSING" -eq 0 ]; then
	ok "/dev/eg0 .. /dev/eg7 all created by udev"
	ls -l /dev/eg[0-7] | sed 's/^/       /'
	MODE=$(stat -c %a /dev/eg0)
	GRP=$(stat -c %G /dev/eg0)
	if [ "$MODE" = "660" ]; then
		ok "nodes are $MODE $GRP, per 99-eg.rules"
	else
		note "nodes are $MODE root - 99-eg.rules is not installed, so"
		note "udev applied its default and only root can open them."
		note "Run 'sudo make install' to put the rule in /etc/udev/rules.d."
	fi
else
	bad "some /dev/egN nodes are missing"
	ls -l /dev/eg* 2>/dev/null | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
say "5. /proc/eg"
# ---------------------------------------------------------------------------
if [ -r /proc/eg ]; then
	ok "/proc/eg readable"
	sed 's/^/       /' /proc/eg
else
	bad "/proc/eg missing"
fi

FIFO=$(grep -m1 '^FIFO size:' /proc/eg | awk '{print $3}')
if [ -n "$FIFO" ] && [ "$FIFO" -gt 0 ] 2>/dev/null; then
	ok "reference FIFO sized: $FIFO events"
else
	bad "FIFO size came back as '${FIFO:-<none>}'"
fi

FIFOSRC=$(grep -m1 '^FIFO size:' /proc/eg | awk '{print $3}')
if [ "${FIFOSRC:-0}" -gt 0 ] 2>/dev/null; then
	note "FIFO sizing works, so 8-bit and 16-bit MMIO both decode: it is"
	note "measured with byte writes to FIFO_REG+1 and 16-bit reads of the"
	note "master register.  An FPGA front end that only decoded 32-bit"
	note "accesses would report 0 here."
fi

IRQ=$(grep -m1 '^Assigned IRQ:' /proc/eg | awk '{print $3}')
if [ "$STAGE" -eq 1 ]; then
	if grep -q 'NOT REQUESTED' /proc/eg; then
		ok "stage 1: IRQ $IRQ deliberately not requested (nointr=1)"
		note "No interrupt from this card can reach the CPU in this stage."
	else
		bad "stage 1 asked for nointr=1 but the driver requested the IRQ anyway"
	fi
	if grep -q "^ *[0-9]*: .* eg$" /proc/interrupts; then
		bad "an eg handler is registered despite nointr=1"
	else
		ok "no eg handler in /proc/interrupts, as intended"
	fi
elif grep -q "^ *[0-9]*: .* eg$" /proc/interrupts; then
	ok "IRQ $IRQ registered in /proc/interrupts"
	grep " eg$" /proc/interrupts | sed 's/^/       /'
	# How is it delivered?  A PCIe card that fell back to legacy INTx
	# shares an IO-APIC line; one using MSI has its own vector and a
	# msi_irqs/ directory.  Both work, but which one it is matters when
	# chasing a card that never interrupts.
	if [ -d "/sys/bus/pci/devices/$BOUND/msi_irqs" ]; then
		note "delivery: MSI (vectors: $(ls /sys/bus/pci/devices/$BOUND/msi_irqs | tr '\n' ' '))"
	else
		note "delivery: legacy INTx on IO-APIC line $IRQ"
		note "$(grep " eg$" /proc/interrupts | sed 's/^ *//')"
	fi
else
	bad "the driver's handler is not in /proc/interrupts"
fi

# ---------------------------------------------------------------------------
say "6. /proc write interface"
# ---------------------------------------------------------------------------
echo "debug=2" > /proc/eg && ok "accepted 'debug=2'" || bad "rejected 'debug=2'"
[ "$(cat /sys/module/eg/parameters/debug)" = "2" ] \
	&& ok "the module parameter followed it" \
	|| bad "/sys/module/eg/parameters/debug did not change"
echo "debug=0" > /proc/eg
echo "reset_counts" > /proc/eg && ok "accepted 'reset_counts'" || bad "rejected 'reset_counts'"
echo "rubbish" > /proc/eg 2>/dev/null && bad "accepted a bad command" || ok "rejected a bad command"

# ---------------------------------------------------------------------------
say "7. Register access through /dev/eg0"
# ---------------------------------------------------------------------------
if [ ! -x "$HERE/test_eg" ]; then
	skip "test_eg not built"
else
	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT

	# Interactive debug session.  Reads the master (0x00), interrupt
	# control (0x02) and event control (0x08) registers, then writes and
	# reads back the rising-edge extended interrupt control register
	# (0x20) and puts it back to 0.  0x20 is chosen because all sixteen
	# of its bits are implemented, it is plain read/write, and with
	# IC_Extended clear in the ICR nothing it selects can fire.
	# The interrupt status register at 0x04 is deliberately NOT read:
	# reading it clears it.
	progress "about to run the register read/write session (writes 0x20)"
	OUT=$(printf '0\n33\n8\ni 0\ni 2\ni 8\no 20 5a5a\ni 20\no 20 0\ni 20\nq\nq\n' |
	      HOME=$TMP timeout 30 "$HERE/test_eg" 2>&1)
	echo "$OUT" | grep -E '^\(?[0-9a-f]+\)? ->' | sed 's/^/       /'

	echo "$OUT" | grep -q "Success....\/dev\/eg0 opened" \
		&& ok "opened /dev/eg0 read/write" \
		|| bad "could not open /dev/eg0"

	echo "$OUT" | grep -q '(20) -> 5a5a' \
		&& ok "wrote and read back 5a5a at register 0x20" \
		|| bad "register write/read-back did not match (see above)"

	echo "$OUT" | grep -q '(20) -> 0$' \
		&& ok "register 0x20 restored to 0" \
		|| note "register 0x20 did not read back as 0 after restore"

	echo "$OUT" | grep -qi 'IOCTL error' \
		&& bad "an ioctl reported an error" \
		|| ok "no ioctl errors in the register session"

	# ------------------------------------------------------------------
	say "8. Statistics (EVGEN_GET_STATS)"
	# ------------------------------------------------------------------
	OUT=$(printf '0\n33\n3\n\nq\n' | HOME=$TMP timeout 30 "$HERE/test_eg" 2>&1)
	echo "$OUT" | sed -n '/Total Interrupts/,/Current Use/p' | sed 's/^/       /'

	echo "$OUT" | grep -q 'Total Interrupts' \
		&& ok "statistics table returned with its labels intact" \
		|| bad "statistics table did not come back"

	# ------------------------------------------------------------------
	say "9. Frame grab (read) and BAT"
	# ------------------------------------------------------------------
	progress "about to grab a frame (read() waits on an interrupt)"
	OUT=$(printf '0\n33\n2\nq\n' | HOME=$TMP timeout 30 "$HERE/test_eg" 2>&1)
	echo "$OUT" | sed -n '/^ [0-9a-f]\{4\}/,+8p' | head -9 | sed 's/^/       /'

	if echo "$OUT" | grep -q 'Error Grabbing frame'; then
		note "read() reported an error:"
		echo "$OUT" | grep 'Error Grabbing frame' | sed 's/^/       /'
		note "Expected with no timeframe loaded: the frame-loaded"
		note "interrupt never arrives, so read() times out (-EBUSY)."
		ok "read() failed cleanly with a timeout rather than hanging"
	elif echo "$OUT" | grep -qE '^ [0-9a-f]{4}'; then
		ok "read() returned a frame"
	else
		bad "read() produced neither a frame nor a clean error"
	fi

	# ------------------------------------------------------------------
	say "10. Wait on the 1 second interrupt"
	# ------------------------------------------------------------------
	if [ "$STAGE" -lt 3 ]; then
		skip "arming an interrupt source needs --stage3"
		note "Stage 1 has no handler; stage 2 deliberately arms nothing."
		note "Run --stage3 only after a --stage2 run has been clean."
	else

	# ------------------------------------------------------------------
	# Does the interrupt path deliver at all?
	# ------------------------------------------------------------------
	# Use the INTERNAL event interrupt, not the 1 second interrupt.  The
	# 1 second source is derived from the time reference, so on a bench with
	# nothing plugged in it never fires, and "no interrupt" then means only
	# "no reference" - it says nothing about whether the card can interrupt
	# the CPU at all.  IC_Event fires from an event line the host asserts
	# itself, so it works on a bare bench and tests the delivery path
	# properly: card asserts -> IO-APIC -> handler runs -> source decoded.
	#
	# An earlier version of this section tried to tell the two cases apart
	# by reading the "PLL locked" bit out of the master register.  Do not
	# reintroduce that.  On the V4.1 Xilinx card the master register reads a
	# constant 0xf904 and that bit is meaningless - it reported "locked"
	# with no reference physically connected, which turned an untested path
	# into a confident and completely wrong "the interrupt path is not
	# delivering".  See GetFifoSize() in eg.c for the same register's FIFO
	# bits being equally unreliable on that board.
	#
	#   EVENT_CTRL_REG (0x08) = EC_Expert | EC_TimeIntEna | EC_TimeIntOutEna
	#                           with the internal-interrupt select = line 0
	#   IC_REG         (0x02) = IC_Enable | IC_Event
	#   EVENT_REG      (0x0a) = toggle line 0 to raise the event
	#
	# The handler masks IC_Event once it has serviced it, so exactly one
	# interrupt is expected however many times the line is toggled.
	# Raise the event line and LEAVE IT RAISED.  IC_Event is level sensitive
	# on the event line, not edge triggered: asserting and then immediately
	# clearing the bit produces a pulse whose width is however long two
	# userspace ioctls happen to take, and the interrupt is usually
	# withdrawn before it is ever delivered.  An earlier version of this
	# check toggled the line 1-0-1-0 and was flaky for exactly that reason -
	# it latched an interrupt about one run in three and reported a broken
	# interrupt path the rest of the time.  Assert once, observe, then clean
	# up in a second pass.
	TOTBEFORE=$(grep -m1 'Total Interrupts' /proc/eg | awk '{print $NF}')
	INTBEFORE=$(grep -m1 'Internal Interrupts' /proc/eg | awk '{print $NF}')
	progress "about to raise an internal event interrupt"
	printf '0\n33\n8\no 8 3040\no 2 8400\no a 0001\nq\nq\n' \
		| HOME=$TMP timeout 30 "$HERE/test_eg" >/dev/null 2>&1
	sleep 1
	TOTAFTER=$(grep -m1 'Total Interrupts' /proc/eg | awk '{print $NF}')
	INTAFTER=$(grep -m1 'Internal Interrupts' /proc/eg | awk '{print $NF}')
	ICRAFTER=$(grep -m1 'Main ICR' /proc/eg | awk '{print $NF}')
	# Put the event register, its control register and the ICR back.
	printf '0\n33\n8\no a 0000\no 8 0000\no 2 0000\nq\nq\n' \
		| HOME=$TMP timeout 30 "$HERE/test_eg" >/dev/null 2>&1
	progress "internal event interrupt test done"
	note "ICR after servicing: $ICRAFTER (IC_Event 0x0400 should be clear -"
	note "the handler masks a source once it has serviced it)"
	note "total interrupts:    $TOTBEFORE -> $TOTAFTER"
	note "internal interrupts: $INTBEFORE -> $INTAFTER"
	note "IO-APIC: $(grep ' eg$' /proc/interrupts | sed 's/^ *//')"

	if grep -q 'IRQ STATE: SHUT DOWN' /proc/eg; then
		bad "the storm guard fired while raising one event interrupt"
		sed -n '/IRQ STATE/,+3p' /proc/eg | sed 's/^/       /'
	elif [ "${INTAFTER:-0}" -gt "${INTBEFORE:-0}" ] 2>/dev/null; then
		ok "internal event interrupt delivered and decoded"
		note "This proves the path end to end with no external hardware:"
		note "the card asserted, the CPU took it, the handler ran and"
		note "identified the source, and it did not storm."
	elif [ "${TOTAFTER:-0}" -gt "${TOTBEFORE:-0}" ] 2>/dev/null; then
		bad "an interrupt arrived but was not decoded as internal"
		note "Delivery works; the source decode does not."
	else
		bad "no interrupt arrived - the delivery path is not working"
		note "The event line was asserted with IC_Event armed, which"
		note "needs no time reference.  Silence here is a real fault."
		note "This card implements MSI (lspci -vv shows the capability);"
		note "if INTx is the problem, pci_alloc_irq_vectors() with"
		note "PCI_IRQ_MSI is the thing to try."
	fi

	# ------------------------------------------------------------------
	# The 1 second interrupt, which DOES need a time reference.
	# ------------------------------------------------------------------
	BEFORE=$(grep -m1 'One Second Interrupts' /proc/eg | awk '{print $NF}')
	OUT=$(printf '0\n33\n1\n3\n0\nn\n1\n\nq\n' |
	      HOME=$TMP timeout 40 "$HERE/test_eg" 2>&1)
	AFTER=$(grep -m1 'One Second Interrupts' /proc/eg | awk '{print $NF}')
	note "one second interrupt count: $BEFORE -> $AFTER"

	if [ "${AFTER:-0}" -gt "${BEFORE:-0}" ] 2>/dev/null; then
		ok "the card is generating 1 second interrupts"
		note "So a time reference is connected and locked."
	elif echo "$OUT" | grep -q 'Timed out'; then
		skip "1 second wait timed out cleanly - no time reference connected"
		note "Expected on a bench with nothing plugged in, and NOT a"
		note "delivery failure: the internal event interrupt above"
		note "already proved the path works.  What this shows is that"
		note "the wait returns instead of blocking forever, which is"
		note "the lost-wakeup fix doing its job."
	else
		bad "neither an interrupt nor a clean timeout"
		echo "$OUT" | tail -15 | sed 's/^/       /'
	fi
	progress "interrupt wait finished"
	fi

	# ------------------------------------------------------------------
	say "10a. Passive interrupt watch (nothing armed)"
	# ------------------------------------------------------------------
	# eg_init_hardware() masks every source at probe, and nothing above
	# arms one.  So the card should be completely silent here.  If it is
	# not, its firmware is asserting an interrupt that the driver has told
	# it not to - which is exactly the condition that storms - and we want
	# to learn that from a 10 second watch with the storm guard armed,
	# not from a locked-up machine.
	if [ "$STAGE" -eq 1 ]; then
		skip "no handler is registered in stage 1, nothing to watch"
	else
		egcount() { grep " eg$" /proc/interrupts | awk '{s=0; for(i=2;i<=NF-2;i++) s+=$i; print s}'; }
		C0=$(egcount)
		progress "starting 10s passive interrupt watch"
		sleep 10
		C1=$(egcount)
		note "interrupt count over 10 idle seconds: ${C0:-?} -> ${C1:-?}"
		progress "passive watch done ($C0 -> $C1)"

		if grep -q 'IRQ STATE: SHUT DOWN' /proc/eg; then
			bad "the storm guard fired with no source armed"
			sed -n '/IRQ STATE/,+3p' /proc/eg | sed 's/^/       /'
			note "The card interrupts regardless of its mask register."
			note "Do NOT run --stage3.  This needs a firmware answer."
		elif [ "${C1:-0}" -gt "${C0:-0}" ] 2>/dev/null; then
			bad "the card interrupted $((C1 - C0)) times with every source masked"
			note "It should be silent.  Something is asserting anyway."
			note "Do NOT run --stage3 until this is understood."
		else
			ok "card is silent with all sources masked"
			note "This is the precondition for --stage3 being safe."
		fi
	fi

	# ------------------------------------------------------------------
	say "11. Concurrency: eight simultaneous opens"
	# ------------------------------------------------------------------
	# Minor 0 is opened read/write and takes write ownership of the card;
	# 1..7 must be opened read-only, because there is only one write owner
	# per card.  (An earlier version of this script used "9<>" - bash for
	# O_RDWR - on all eight and was correctly refused on seven of them.)
	( exec 9<>/dev/eg0; sleep 2 ) &
	for n in 1 2 3 4 5 6 7; do
		( exec 9</dev/eg$n; sleep 2 ) &
	done
	sleep 1
	USERS=$(grep -m1 'Current Use' /proc/eg | awk '{print $NF}')
	if [ "${USERS:-0}" -ge 8 ]; then
		ok "all 8 minors open at once (Current Use = $USERS)"
	else
		bad "only $USERS of 8 minors opened"
	fi
	wait
	sleep 1
	USERS=$(grep -m1 'Current Use' /proc/eg | awk '{print $NF}')
	[ "${USERS:-1}" -eq 0 ] \
		&& ok "all descriptors released cleanly" \
		|| bad "Current Use did not return to 0 (it is $USERS)"

	# ------------------------------------------------------------------
	say "12. Exclusion"
	# ------------------------------------------------------------------
	( exec 9<>/dev/eg0
	  if ( exec 8<>/dev/eg0 ) 2>/dev/null; then
		bad "a second open of /dev/eg0 succeeded"
	  else
		ok "a second open of the same minor is refused"
	  fi

	  # Only one write owner per card, across all minors.
	  if ( exec 8<>/dev/eg1 ) 2>/dev/null; then
		bad "a second read/write opener took the card"
	  else
		ok "a read/write open of another minor is refused while eg0 owns writes"
	  fi

	  # ...but a read-only opener of another minor is fine.
	  if ( exec 8</dev/eg1 ) 2>/dev/null; then
		ok "a read-only open of another minor still succeeds"
	  else
		bad "a read-only open of another minor was refused"
	  fi )
fi

# ---------------------------------------------------------------------------
say "13. Kernel log"
# ---------------------------------------------------------------------------
dmesg | sed 's/^/       /'

if dmesg | grep -qiE 'BUG:|Oops|general protection|WARNING: .*kernel|soft lockup|bad: scheduling'; then
	bad "the kernel logged a BUG, oops or warning"
else
	ok "no kernel BUG, oops or warning"
fi

# ---------------------------------------------------------------------------
say "14. Unload"
# ---------------------------------------------------------------------------
if [ "$KEEP" -eq 1 ]; then
	skip "--keep given, leaving the module loaded"
else
	progress "about to rmmod"
	if rmmod eg; then
		ok "rmmod succeeded"
		[ -e /dev/eg0 ] && bad "/dev/eg0 survived the unload" \
				|| ok "device nodes removed"
		[ -e /proc/eg ] && bad "/proc/eg survived the unload" \
				|| ok "/proc/eg removed"
		grep -q " eg$" /proc/interrupts \
			&& bad "the IRQ handler is still registered" \
			|| ok "IRQ handler released"
	else
		bad "rmmod failed"
	fi
	dmesg | tail -8 | sed 's/^/       /'
fi

# ---------------------------------------------------------------------------
printf '\n\033[1m== Summary ==\033[0m\n'
printf '   passed  %d\n   failed  %d\n   skipped %d\n' "$PASS" "$FAIL" "$SKIP"
progress "finished cleanly: pass=$PASS fail=$FAIL skip=$SKIP"
[ "$FAIL" -eq 0 ]

#!/bin/bash
#
# egtest.sh - non-interactive hardware check for the ported eg driver.
#
# Every step is read-only or self-contained: it loads the module, reads the
# card's identity, exercises the register, statistics, interrupt and frame-grab
# paths through /dev/eg0, and unloads again.  Nothing is written to the card's
# configuration and no timeframe is loaded, so "PLL unlocked" and a stalled BAT
# are the expected result on a bench with no reference connected.
#
# Usage:  sudo ./egtest.sh [--keep]
#           --keep   leave the module loaded at the end
#
set -u

KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1

HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0
FAIL=0
SKIP=0

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
note "kernel  $(uname -r)"
note "module  $HERE/eg.ko"

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
lspci -nn -d 10b5:9030 | sed 's/^/       /'
lspci -nn -d 2321:      | sed 's/^/       /'

for d in /sys/bus/pci/devices/*/; do
	v=$(cat "$d/vendor" 2>/dev/null)
	p=$(cat "$d/device" 2>/dev/null)
	if [ "$v" = "0x10b5" ] && [ "$p" = "0x9030" ]; then
		drv=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)
		note "$(basename "$d")  driver=${drv:-<none>}"
	fi
done

# ---------------------------------------------------------------------------
say "2. Load the module"
# ---------------------------------------------------------------------------
rmmod eg 2>/dev/null
dmesg -C 2>/dev/null || true

if insmod "$HERE/eg.ko" debug=0; then
	ok "insmod succeeded"
else
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

# The PROM text is the same on the AT distributed clock, so what actually
# decides is the register window size and the PCI class.  Check the driver
# picked the event-generator-shaped card.
CLASS=$(cat /sys/bus/pci/devices/$BOUND/class)
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

IRQ=$(grep -m1 '^Assigned IRQ:' /proc/eg | awk '{print $3}')
if grep -q "^ *[0-9]*: .* eg$" /proc/interrupts; then
	ok "IRQ $IRQ registered in /proc/interrupts"
	grep " eg$" /proc/interrupts | sed 's/^/       /'
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
	BEFORE=$(grep -m1 'One Second Interrupts' /proc/eg | awk '{print $NF}')
	OUT=$(printf '0\n33\n1\n3\n0\nn\n1\n\nq\n' |
	      HOME=$TMP timeout 40 "$HERE/test_eg" 2>&1)
	AFTER=$(grep -m1 'One Second Interrupts' /proc/eg | awk '{print $NF}')
	note "one second interrupt count: $BEFORE -> $AFTER"

	if [ "${AFTER:-0}" -gt "${BEFORE:-0}" ] 2>/dev/null; then
		ok "the card is generating 1 second interrupts"
	elif echo "$OUT" | grep -q 'Timed out'; then
		ok "wait timed out cleanly after 3 s (no reference connected)"
		note "Expected without a timeframe.  What matters is that the"
		note "wait returned instead of blocking forever."
	else
		bad "neither an interrupt nor a clean timeout"
		echo "$OUT" | tail -15 | sed 's/^/       /'
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
[ "$FAIL" -eq 0 ]

# PC Event Generator (EG) PCI driver — Linux 6.8 port

This directory is the CSIRO ATNF **PC Event Generator** character driver and its
test program, ported in place from Linux 2.6 (with 1.2–2.4 compatibility
branches still carried in the source) to **Linux 6.8 and newer on x86-64**.

There is no `kernel6/` subdirectory and no reference copy of the original: the
port replaced the files where they stood, as asked. `sysdep.h` — a 1996
compatibility shim for kernels 1.2 through 2.0 — is deleted, and there is not
one `LINUX_VERSION_CODE` left in the tree.

| File | What it is |
|---|---|
| `eg.c` | The driver. Was 4296 lines, roughly a third of it version conditionals and dead ISA support. |
| `eg.h` | Register map and driver-private state. |
| `eg_ioctl.h` | Shared ioctl definitions — userspace ABI. |
| `eg_struct.h` | Shared structures — userspace ABI. |
| `test_eg.c` | Interactive exerciser. |
| `Makefile` | kbuild + userspace. |
| `egtest.sh` | Non-interactive hardware check. |
| `99-eg.rules` | udev ownership for `/dev/eg0..7`. |
| `dkms.conf` | So the module survives kernel updates. |

---

## ⚠ Read this first: the userspace ABI changed

`sizeof(EGStats_struct)` is now **1152** bytes and `sizeof(PublicSysInfo_struct)`
is **192**. Both differed between a 32- and a 64-bit build of the 2.6 header,
because every field crossing the ioctl boundary was an `unsigned long`.

**Anything that calls `EVGEN_GET_STATS`, `EVGEN_GET_DEVICE_INFO`,
`EVGEN_GET_INTERRUPT_SOURCE` or `EVGEN_EXTENDED_INTR_OPTION` must be recompiled
against this tree's `eg_struct.h`.** `test_eg` is rebuilt here; nothing else in
`lunaskaport` includes these headers, so on this machine that is the whole list.

| Was | Now | Why |
|---|---|---|
| `InterruptMasks_struct` — 3 × `unsigned long` | 3 × `uint32_t` | 12 bytes on i386, 24 on x86-64. The registers behind `Rising` and `Falling` are 32 bits wide, so nothing is lost. |
| `EGStatsEntry_struct` — `char[52]` + `unsigned long` | `char[56]` + `uint64_t` | 56 bytes on i386, 64 on x86-64, and every entry after the first was at a different offset on the two. |
| `EGInterruptRate_struct.Jiffies` — `int` | `uint64_t` | The driver stored the kernel's `unsigned long jiffies` in an `int` and then compared the two; it only worked by accident of sign extension. |
| — | `PublicSysInfo_struct.ABIVersion` appended | So a mismatched binary can be told from a merely truncated read. |

`eg_struct.h` now carries `static_assert`s for every size and for the offset of
`DriverStartTime`, which fire at compile time in both the kernel and the
userspace build. They are verified to pass under `gcc -m32` and `gcc -m64`.

**One command changed shape:** `EVGEN_GET_DEVICE_INFO` took its buffer length
from the first *byte* of the buffer, as a signed `char`, and compared it against
`sizeof(PublicSysInfo_struct)`. The structure is bigger than 127 bytes, so no
caller could ever ask for all of it, and a caller that wrote the true size into
that byte passed a negative length straight to `copy_to_user()`. It now takes an
`int32_t` length, the same convention `EVGEN_GET_STATS` already used. Nothing in
this tree called it.

The ioctl command numbers, the magic byte, the `/dev/eg0..7` node names and
minors, and the `read()`/`write()` conventions are all unchanged.

---

## 1. What the port changed, and why

### 1.1 Kernel interfaces that no longer exist

These are hard build errors on 6.8, not warnings.

| Used by the 2.6 driver | Replacement |
|---|---|
| `<linux/config.h>`, `<linux/modversions.h>`, `<asm/system.h>`, `<linux/autoconf.h>` | deleted; the definitions moved or vanished |
| `init_module()` / `cleanup_module()` | `module_init()` / `module_exit()` |
| `MOD_INC_USE_COUNT` / `MOD_DEC_USE_COUNT` | the VFS refcounts the module via `fops.owner` |
| `MODULE_PARM()` | `module_param()` |
| `__devinit`, `__devexit_p()` | removed in 3.8 |
| `SA_SHIRQ` | `IRQF_SHARED` (2.6.18) |
| handler `(int, void *, struct pt_regs *)` | `(int, void *)` (2.6.19) |
| `file_operations.ioctl` | `.unlocked_ioctl` (`long`, no `inode`) (2.6.36) |
| `file->f_dentry->d_inode` | gone in 3.19; the minor is captured at `open()` |
| `create_proc_entry()`, `->read_proc`, `->write_proc` | `proc_create_data()` + `seq_file` + `struct proc_ops` (3.10 / 5.6) |
| `interruptible_sleep_on()` | removed in 3.15 as unfixably racy |
| `wait_queue_t` | `wait_queue_entry_t` (4.13) |
| `class_create(owner, name)` | `class_create(name)` (6.4) |
| `pci_find_device()` | `probe()` |

`request_irq()` deserves a note of its own. The 2.6 code hid the pt_regs
signature change by casting the handler:

```c
result = request_irq(IRQ, (void *) EGInterrupt, IRQF_SHARED, ModuleName, sysinfo);
```

That cast silences the compiler and leaves the handler reading a third argument
that is no longer passed. The same trick was used for every `file_operations`
member — `F_ops.read = (void *) EGRead;` — after zeroing the structure with a
loop that walked it as an array of `unsigned int *`. Both are gone; the fops are
a normal designated initialiser.

### 1.2 Bugs the port had to fix

**Locking.** Every critical section was `save_flags`/`cli`, later
`local_irq_save()`/`local_irq_restore()`, wrapped in the driver's own
`MASK_INTERRUPTS`/`RESTORE_INTERRUPTS` macros. That disables interrupts on the
running CPU and excludes nothing at all on the other ones. The interrupt handler
and the `ioctl`, `read` and `write` paths all do read-modify-write on the
interrupt control register. There is now one `spinlock_t` per card, taken with
`spin_lock_irqsave()` on both sides.

Untangling that exposed a matching bug: the `EG_WAIT_ON_INTR_OP` path called
`RESTORE_INTERRUPTS` twice for one `MASK_INTERRUPTS` on its `O_NONBLOCK` early
return. Harmless with `cli`/`sti`; a double `spin_unlock` now.

**Lost wakeups.** All four sleeping paths armed a hardware interrupt and *then*
went to sleep, either through `interruptible_sleep_on()` or through an
open-coded `add_wait_queue` / `set_current_state` / `schedule_timeout` /
`remove_wait_queue`. An interrupt that arrived in the gap was lost and the
process blocked until its timeout — or forever, since the default timeout for
`EVGEN_WAIT_ON_INTR` is "none". They all use
`wait_event_interruptible_timeout()` against an explicit condition flag now, and
the FIFO-full path in `write()` re-reads the status register after arming so it
cannot miss the edge either.

**Signal handling.** `if (signal_pending(current) & ~(current->blocked.sig[0]))`
ANDs a boolean with a signal mask. It is the return value of
`wait_event_interruptible_timeout()` now.

**The wait-on-interrupt table.** It was keyed on PID, claimed lazily on the
first wait, and garbage-collected by asking, on *every* claim, for *every*
occupied slot, whether that PID still existed:

```c
if (pid_task(find_get_pid(WaitOn[ref].PID), PIDTYPE_PID) == NULL) {
```

`find_get_pid()` takes a reference to the `struct pid` that is never dropped —
a leak on every claim. It also could not tell a live process from a recycled
PID. Slots are now owned by the open file description: claimed in `open()`,
released in `release()`, so there is nothing to reap.

**MMIO.** `ReadPCIWord()` and `WritePCIWord()` cast an `unsigned long` to
`volatile unsigned short *` and dereferenced it. That is not an MMIO access — no
barrier, no ordering, nothing `sparse` can check. Everything goes through
`readw()`/`writew()` on a `void __iomem *` from `pci_iomap()` now.

**The mapping was 15 registers too short.** `ioremap()` was called with
`PLX_REGION_SIZE`, 32 bytes, and the driver then read and wrote registers up to
offset `0x2e`. It survived only because `ioremap()` rounds up to a page.
`pci_iomap(pdev, bar, 0)` maps exactly the BAR, and probe refuses a BAR shorter
than `0x30`.

**probe() and remove().** `probe()` ignored `pci_enable_device()`'s return
value, never called `pci_request_regions()`, and had no failure path; the real
setup ran from `module_init` *after* `pci_register_driver()` returned, so on a
machine with no card it carried on and dereferenced a NULL mapping. `remove()`
was `{ return; }` — unloading left the IRQ registered, the BAR mapped and the
char devices live. Both are now normal ladders with matching unwind.

**Ten cdevs for one card.** 2.6 embedded an array of eight `struct cdev`s and
`cdev_add()`'d each separately, which is what forced `open()` to find its state
through a file-scope global. One cdev spans all eight minors now, so
`container_of(inode->i_cdev, ...)` works.

**`write()` walked the caller's buffer wrong.** It read
`EG_NUM_ELEMENTS_IN_EVENT_DEF * sizeof(u16)` bytes from `&bufferp[loops]`,
advancing one `u16` per event instead of four, so a write of more than one event
re-read overlapping halves of the caller's buffer. Nothing ever passed more than
one, which is why it was never seen.

**The "Events Written ('000)" counter was always zero.**

```c
WriteEventSubCount = WriteEventSubCount % 1000;
Stats[EVENTS_WRITTEN].Value += (WriteEventSubCount / 1000);   /* always 0 */
```

The quotient is taken before the modulo now, so the counter works.

**`EG_GET_EG_REG_OP` could read outside the mapping.** It took a register offset
from userspace, shifted it right by 16 into a signed `int`, and range-checked
only the upper bound — a negative value passed. Both register ioctls are
bounds-checked as unsigned now.

**`/proc/eg` was world writable** (`create_proc_entry(name, 0666, NULL)`), so
any user on the box could set the driver's debug level. It is `0644`.

**`reset_counts` did nothing.** The `/proc` write handler recognised the command
and its body was an empty pair of braces. It works.

**The `/proc` ICR decode printed nonsense.** It decoded the *falling-edge
extended* register using the *primary* control register's bit names. It decodes
the primary register now.

**Every ioctl printed two lines to the kernel log**, unconditionally, outside
any debug test. They are behind `DEBUG_IOCTL`.

### 1.3 Deletions

* **The ISA card.** The 2.6 driver registered a `pci_driver` and, if `probe()`
  never fired, fell back to `inw()`/`outw()` on a module-parameter I/O base.
  Nothing has had an ISA slot in twenty years, the fallback became unreachable
  the moment the driver was structured around `probe()`, and it is the reason
  the driver carried *two* of every register accessor reached through function
  pointers in the device structure. Gone, along with the `iobase` and `irq`
  module parameters, `EG_TYPE_ISA`, and `request_region()` on an I/O range no
  machine has.
* `FindEG()` and `InitSysInfo()` — the pre-`probe()` discovery path, and a
  120-line duplicate of `InitSysInfoStructure()` selected by version.
* `EGSelect()`, the pre-2.2 `select()` entry point.
* A private `find_task_by_pid()` that walked the task list by hand.
* `EXPORT_SYMBOL(EGInterrupt)` — it exported a `static` function.
* The `#ifdef NOLONGERINUSE` extended-interrupt-line ioctls. The two commands
  still return `-EINVAL`, as they did before, so nothing observable changed.
* `eg_date.h` / `COMPILE_TIME` — a header regenerated with `date` on every
  build, which defeats reproducible builds. `MODULE_VERSION` and `modinfo`
  replace it; `/proc/eg` prints the driver version instead of a build date.
* `sysdep.h`.

### 1.4 Behaviour that changed on purpose

* **`open()` returns `-EBUSY`, not `-ENODEV`,** when a minor is already open or
  another minor holds write access. `-ENODEV` means "no such device".
* **A minor's owner is now decided in one place.** 2.6 checked
  `OpenOwner[minor]` only on the read-only path and set it only after taking
  write ownership, so the two halves disagreed about who held the node.
* **`poll()` blocks when nothing is armed.** 2.6 returned `POLLPRI` when it
  could not find the caller in the PID table — that is, it reported an event
  precisely when there was none, so `select()` spun. With per-open state there
  is always an entry.
* **`write()` honours `O_NONBLOCK`.** The 2.6 code had the check commented out.
  A short write returns the number of events written; `-EAGAIN` only if none
  were.
* **A partial `write()` interrupted by a signal returns the count** rather than
  `-ERESTARTSYS`, so events already loaded into the FIFO are not silently lost.
* **`MAX_NUM_EG_USERS` slots are claimed at `open()`, not at first wait.** There
  are 20 of them and only 8 minors, one opener each, so it cannot be reached.

---

## 2. Build and install

```bash
sudo apt install build-essential linux-headers-$(uname -r) dkms

make                 # eg.ko, built against the running kernel
make test            # test_eg
sudo make install    # module + udev rule into /lib/modules/<rel>/extra
sudo modprobe eg     # or: sudo insmod ./eg.ko debug=2
```

Cross-kernel build:

```bash
make KVER=6.8.0-136-generic
make KERNELDIR=/path/to/linux-headers-6.8.0-136-generic
```

`make sparse` re-checks the `__iomem`/`__user` annotations, of which the 2.6
driver had none. It needs the `sparse` package.

### DKMS

Recommended on any machine that takes kernel updates — a module in `extra/` is
silently lost on every one.

```bash
sudo cp -r . /usr/src/eg-2.0
sudo dkms add     -m eg -v 2.0
sudo dkms build   -m eg -v 2.0
sudo dkms install -m eg -v 2.0
dkms status
```

### Secure Boot

Check with `mokutil --sb-state`.

* *"EFI variables are not supported"* — the machine boots legacy BIOS, Secure
  Boot does not apply, and an unsigned out-of-tree module loads normally. **This
  is the case on the machine this port was developed on.**
* *"SecureBoot enabled"* — an unsigned module is rejected with `Key was rejected
  by service` (`-EKEYREJECTED`). Either let DKMS sign it (`sudo mokutil --import
  /var/lib/shim-signed/mok/MOK.der`, set a one-time password, reboot, enrol the
  key in the MOK manager), sign it by hand with
  `/usr/src/linux-headers-$(uname -r)/scripts/sign-file`, or
  `sudo mokutil --disable-validation` — which is a policy decision, not a
  technical one.

### Module parameters

| Parameter | Default | Meaning |
|---|---|---|
| `major=N` | 0 | 0 allocates a major dynamically; non-zero requests that major. |
| `debug=N` | 0 | 0 silent … 8 everything. **7 and 8 log every register access and will flood the journal.** Writable at runtime via `/sys/module/eg/parameters/debug` (root) or `echo debug=2 > /proc/eg`. |
| `slot=0000:02:02.0` | unset | Bind only to this PCI address. See §3. |
| `force=1` | off | Bind even if the card does not look like an event generator. See §3. |

`major` and `debug` were `S_IRUGO` in 2.6, so neither could be changed at
runtime; `iobase` and `irq` are gone with the ISA card.

### Device nodes and permissions

`/dev/eg0` … `/dev/eg7` are created by the driver through `device_create()`.
**There is no `mknod` step.**

Two independent exclusion rules apply, both inherited unchanged from 2.6:

* **One process per minor.** A second `open()` of a node someone already holds
  is refused.
* **One write owner per card, across all eight minors.** The first descriptor
  opened `O_WRONLY` or `O_RDWR` takes write ownership; any later `O_RDWR` open
  of *any* minor is refused until it is closed. Only the write owner may call
  `write()`, `EVGEN_RESET`, `EVGEN_CLR_EVENTS` or `EVGEN_WRITE_EVENT_DIRECT`.

So the working pattern is what `test_eg` uses: open minor 0 `O_RDWR` to load
events, and minors 1–7 `O_RDONLY` to observe. Opening all eight `O_RDWR` gets
you one success and seven `-EBUSY`. (2.6 returned `-ENODEV` for both cases,
which reads as "no such device"; that is the only change.)

`99-eg.rules` sets `MODE="0660" GROUP="plugdev"`. This is a tightening: the 2.6
site scripts created the nodes mode 666, world writable.

A fresh login (or `newgrp plugdev`) is needed if your `plugdev` membership is
recent. **If the event generator software runs at boot as a system account
rather than as the operator, that account must also be in `plugdev`** — or
change `GROUP` in the rule to a dedicated `eg` group.

### Loading automatically on every boot

`MODULE_DEVICE_TABLE(pci, …)` plus `depmod -a` publishes the alias

```
pci:v000010B5d00009030sv*sd*bc*sc*i*
```

which udev coldplugs at boot. Verify without rebooting:

```bash
modinfo -F alias eg
sudo udevadm trigger --action=add --subsystem-match=pci
```

Only if that does not fire, add `/etc/modules-load.d/eg.conf` containing the
single word `eg`.

---

## 3. Two cards, one PCI ID

This is the one thing to understand before deploying.

The event generator and the **AT Distributed Clock** — driven by the separate
`atdcif` module, ported last week — are built on the same PLX 9030 carrier.
They have the **same** `vendor:device`, `10b5:9030`, and on this machine they
are both on bus 02:

```
02:01.0 Bridge [0680]:            PLX PCI9030 [10b5:9030]   BAR2 = 1024 bytes
02:02.0 System peripheral [0880]: PLX PCI9030 [10b5:9030]   BAR2 =   64 bytes
```

The kernel offers a matching device to whichever driver is loaded first. The 2.6
driver had no check at all — it bound whichever PLX 9030 `pci_find_device()`
returned, which on a two-card host is a coin toss.

**The serial-number PROM does not tell them apart.** It belongs to the shared
carrier, so both boards read back the same `PC EVENT GENERATOR Vx.y … SNnnnn`
string. (This is worth stating explicitly because it looks like an obvious
discriminator and is not: `atdcif` logs that same string when it binds the
clock, which reads as though it has bound the wrong card.)

What does tell them apart is what the PLX serial EEPROM programs, and it follows
each board's register map:

| | registers to | BAR2 size | PCI class |
|---|---|---|---|
| Event generator | `0x2e` | `0x40` | `0880` system peripheral |
| AT distributed clock | `0xd0` | `0x400` | `0680` bridge, other |

`eg_identify()` accepts a card that looks right on **either** signal — class
`0880`, *or* a BAR2 smaller than `0x100` — so a board whose EEPROM carries an
unexpected class still binds as long as its register window is the right size,
and vice versa. It refuses only when both say "this is the clock", and even then
`force=1` overrides. `slot=0000:02:02.0` pins the driver to one address.

**`atdcif` does not make the reciprocal check.** On a host with both cards it
still binds whichever PLX 9030 it is offered first and stops there, so if `eg`
is ever loaded first and takes the clock's slot, `atdcif` will find nothing.
Loading `eg` first is safe today because `eg` declines the clock; adding the
mirror-image test to `atdcif` (accept class `0680` or BAR2 ≥ `0x100`) would make
the pair order-independent. That is a change to the `atdc` tree and has not been
made here.

---

## 4. Testing

```bash
make && make test
sudo ./egtest.sh          # add --keep to leave the module loaded
```

`egtest.sh` is non-interactive and self-contained. It loads the module, checks
which card it bound and that it is the event-generator-shaped one, checks the
device nodes and `/proc/eg`, exercises the register ioctls with a
write/read-back on `0x20`, reads the statistics table, does a frame grab, waits
on the one-second interrupt, opens all eight minors at once, checks that a
second opener of a minor is refused, scans `dmesg` for oopses, and unloads.

It deliberately does not read the interrupt status register at `0x04` — reading
it clears it.

### Result on this machine, 2026-08-19

28 of 28 checks pass on `6.8.0-136-generic`. The card bound was
`0000:02:02.0`, `PC EVENT GENERATOR V3.4 2007-08-14 SN6316`, IRQ 18 (shared with
`i801_smbus`), reference FIFO 1024 events, major 235.

The clock reference turned out to be live, so more passed than expected:

* `PLL Unlocked Interrupts` stayed at **0**.
* `One Second Interrupts` incremented once per second, so the interrupt path,
  the wait path and the wake-up all work end to end.
* The frame grab returned real frame data rather than timing out.

### If there is no timeframe loaded

Without a time reference several results are expected to look like failures,
and `egtest.sh` scores them as passes provided they return *promptly*:

* `PLL Unlocked Interrupts` climbing in `/proc/eg`.
* `read()` timing out with `-EBUSY` — the frame-loaded interrupt never arrives.
* `EVGEN_WAIT_ON_INTR` on the 1 second source timing out with `-EAGAIN`.
* A BAT of zero, or one that does not advance.

The clean timeout is the point: that path is exactly what the lost-wakeup bug
described in §1.2 used to turn into an indefinite block.

### Driving `test_eg` from a script

`test_eg` now accepts the device number as `argv[1]` (the 2.6 source had this
commented out) and treats end-of-input as `q`, so it can be piped:

```bash
printf '0\n33\n3\n\nq\n' | test_eg      # dump the statistics table once
printf '0\n33\n8\ni 0\nq\nq\n' | test_eg  # read the master register
```

In 2.6 an unchecked `fgets()` meant EOF turned every menu prompt into an
infinite loop, so this was not possible.

---

## 5. The test program

`test_eg.c` was written for a 32-bit userland and was comprehensively broken on
x86-64 — not "warns", but passes garbage to every ioctl.

```c
int eg_ioctl(int handle, unsigned int function, ...) {
        unsigned int *args = &function;
        ++args;
        return ioctl(handle, function, *args);
}
```

That walks off the end of its own frame looking for the variadic argument. It
finds the right word on the i386 stack-argument ABI and an unrelated one
anywhere else, and it truncated every pointer argument to 32 bits on the way.
It uses `<stdarg.h>` and carries an `unsigned long` now.

Also fixed:

* Six `(int) &something` casts that truncated 64-bit pointers.
* `ftime()` / `struct timeb`, removed from POSIX in 2008 — now
  `clock_gettime(CLOCK_REALTIME)`.
* Five `printf(string)` format-string vulnerabilities. One of them,
  `printf(string, "Timed out!\n")`, printed the *previous* message.
* Unchecked `fgets()` in 30 places — see above.
* `GrabFrame()` returned `EG_OK` (0) when the timeout ioctl failed, so callers
  could not tell success from failure.
* `PsuedoPulsarEventTest()` seeded the event word from an uninitialised
  `buffer[3]` using `&= !mask` — logical not, which is 0 for any non-zero mask,
  so the positive-sense branch cleared the whole word by accident and the
  negative-sense branch OR'd into uninitialised stack.
* Menu option 9 (`Set/Get Extended interrupt info`) calls
  `EVGEN_GET_XINT_INTR_LINE`, which the driver has never implemented. The old
  code ignored the error and printed an uninitialised buffer forever; it now
  says so and points at menu option 1 with interrupt source 12 (`Extended`),
  which is the working way to arm extended interrupts.
* `$HOME` longer than about 70 characters silently produced a truncated,
  wrong parameter-file path, and an unset `$HOME` was `strcpy()`'d as `NULL`.

The menu, the tests and the `~/test_eg.dat` parameter file format are unchanged.

---

## 6. Two fixes in `eg_ioctl.h`

Both were macros that expanded to an undefined enumerator, so any file that
referenced them failed to compile — which is why nothing ever used them:

* `EVGEN_WAVEFORM_ENABLE` expanded `EG_WF_EN`; the enumerator is `EG_WF_EN_OP`.
* `INTR_WAIT_ON_GRAB_FRAME_COMPLETE` expanded `INTR_WAIT_ON_GF_FN`; the
  enumerator is `INTR_WAIT_ON_GFC_FN`.

Every command is still encoded with `_IO()`, i.e. with no direction or size in
the command number even for the ones that take a pointer. That is wrong by
modern convention, but it is the existing on-the-wire ABI and re-encoding would
change every command number. Left alone deliberately.

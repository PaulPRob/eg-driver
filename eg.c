// SPDX-License-Identifier: GPL-2.0
/*
 * eg.c - CSIRO ATNF PC Event Generator (EG) PCI character driver.
 *
 * Ported from Linux 2.6 (with 1.2 - 2.4 compatibility branches still in it) to
 * Linux 6.8 and newer on x86-64.  The hardware access sequences, the register
 * semantics, the ioctl numbers and the read()/write() conventions are
 * unchanged; everything that changed is either a kernel interface that no
 * longer exists or a bug that a modern kernel turns from latent into fatal.
 *
 * ===========================================================================
 * What had to change, and why
 * ===========================================================================
 *
 * Build-breaking kernel interface removals
 * ----------------------------------------
 *   <linux/config.h>, <linux/modversions.h>, <asm/system.h>,
 *   <linux/autoconf.h>            all deleted from the kernel long ago.
 *   init_module()/cleanup_module()  replaced by module_init/module_exit.
 *   MOD_INC_USE_COUNT             gone since 2.6; the VFS refcounts the module.
 *   MODULE_PARM()                 replaced by module_param().
 *   __devinit / __devexit_p()     removed in 3.8.
 *   SA_SHIRQ                      renamed IRQF_SHARED in 2.6.18.
 *   irq handler (int, void *, struct pt_regs *)
 *                                 lost its pt_regs argument in 2.6.19.  The
 *                                 2.6 code hid this by casting the handler to
 *                                 (void *) at request_irq() time, which
 *                                 compiles and then corrupts the stack.
 *   file_operations.ioctl         replaced by .unlocked_ioctl (long, no inode)
 *                                 when the BKL was removed in 2.6.36.
 *   file->f_dentry->d_inode       f_dentry went in 3.19.  The minor is now
 *                                 captured at open() instead of being dug out
 *                                 of the dentry on every call.
 *   create_proc_entry(), ->read_proc, ->write_proc
 *                                 removed in 3.10.  /proc/eg is now
 *                                 proc_create() + seq_file + struct proc_ops.
 *   interruptible_sleep_on()      removed in 3.15 as unfixably racy.
 *   wait_queue_t                  renamed wait_queue_entry_t in 4.13.
 *   struct class * / class_create()
 *                                 lost its owner argument in 6.4.
 *
 * Correctness fixes that a modern kernel exposes
 * ----------------------------------------------
 *  1. Locking.  Every critical section used save_flags/cli, later
 *     local_irq_save()/local_irq_restore().  That disables interrupts on the
 *     running CPU only, so on any SMP machine - which is all of them now - it
 *     excluded nothing.  The interrupt handler and the ioctl/read/write paths
 *     both do read-modify-write on the interrupt control register.  There is
 *     now one spinlock per card, taken with spin_lock_irqsave() on both sides.
 *
 *     One consequence had to be untangled: EG_WAIT_ON_INTR_OP had a path that
 *     called RESTORE_INTERRUPTS twice for one MASK_INTERRUPTS (the O_NONBLOCK
 *     early return, after the enable block had already restored).  Harmless
 *     with cli/sti, a double spin_unlock now.
 *
 *  2. Sleeping.  interruptible_sleep_on() and the open-coded
 *     add_wait_queue / set_current_state / schedule_timeout / remove_wait_queue
 *     sequences both lose a wakeup that arrives between arming the hardware
 *     interrupt and going to sleep - the driver would then block forever on a
 *     one-second interrupt it had already been sent.  All four wait sites now
 *     use wait_event_interruptible_timeout() against an explicit condition
 *     flag set by the handler, and the FIFO-full path re-reads the status
 *     register after arming so it cannot miss an edge either.
 *
 *  3. Signal handling.  "if (signal_pending(current) & ~(current->blocked.sig[0]))"
 *     ANDs a boolean with a signal mask.  Replaced by the return value of
 *     wait_event_interruptible_timeout().
 *
 *  4. The wait-on-interrupt table.  It was keyed on PID, claimed lazily, and
 *     garbage-collected by asking pid_task(find_get_pid(pid)) whether each
 *     recorded PID still existed - leaking a struct pid reference every time,
 *     on every claim, for every occupied slot.  It also misidentified a slot
 *     as live if the PID was recycled.  Slots are now owned by the open file
 *     description: claimed in open(), released in release().
 *
 *  5. MMIO.  ReadPCIWord()/WritePCIWord() cast an unsigned long to
 *     "volatile unsigned short *" and dereferenced it.  That is not an MMIO
 *     access: it has no compiler barrier, no ordering, and sparse cannot check
 *     it.  All register access now goes through readw()/writew() on a
 *     void __iomem * from pci_iomap().
 *
 *  6. The mapping was too short.  ioremap() was called with PLX_REGION_SIZE,
 *     32 bytes, and the driver then read and wrote registers up to offset
 *     0x2e.  It survived only because ioremap() rounds to a page.  pci_iomap()
 *     now maps the whole BAR and probe() refuses a BAR shorter than 0x30.
 *
 *  7. probe() ignored pci_enable_device()'s return value, never called
 *     pci_request_regions(), and had no failure path.  The real setup ran from
 *     module_init *after* pci_register_driver() returned, so on a machine with
 *     no card it happily carried on and dereferenced a NULL mapping.
 *
 *  8. remove() was an empty "return;".  Unloading the module left the IRQ
 *     registered, the BAR mapped and the char devices live.
 *
 *  9. write() advanced the user pointer by one u16 per event instead of four,
 *     so a write of n>1 events re-read overlapping halves of the caller's
 *     buffer.  Nothing ever passed n>1, which is why it was never seen.
 *
 * 10. The "Events Written ('000)" counter did
 *         sub %= 1000;  stats += sub / 1000;
 *     i.e. added zero, always.  The quotient is now taken before the modulo.
 *
 * 11. EG_GET_EG_REG_OP took a register offset from userspace, shifted it right
 *     by 16 and range-checked only the upper bound, so a negative value passed
 *     the check and read outside the mapping.  Both register ioctls are now
 *     bounds-checked as unsigned.
 *
 * 12. Card identification.  The PLX 9030 ID this driver matches on is shared
 *     with the AT Distributed Clock on the same carrier, and 2.6 bound to
 *     whichever of the two the PCI scan reached first.  See eg_identify().
 *
 * 13. Unconditional printk() on every single ioctl ("Ioctl being called")
 *     is now behind DEBUG_IOCTL.
 *
 * Deletions
 * ---------
 *   The ISA card and everything that supported it: two complete sets of
 *   register accessors reached through function pointers in the device
 *   structure, the iobase/irq module parameters, EG_TYPE_ISA, and the
 *   request_region()/release_region() calls on an I/O range no machine has.
 *   FindEG() and pci_find_device(), replaced by probe().
 *   EGSelect(), the pre-2.2 select() entry point.
 *   A private find_task_by_pid() reimplementation that walked the task list.
 *   EXPORT_SYMBOL(EGInterrupt) - it exported a static function.
 *   The #ifdef NOLONGERINUSE extended-interrupt-line ioctls.
 *   eg_date.h / COMPILE_TIME: a header regenerated on every build, which
 *   defeats reproducible builds.  MODULE_VERSION and modinfo replace it.
 */

#include "eg.h"

/*
 * ---------------------------------------------------------------------------
 * Module parameters
 * ---------------------------------------------------------------------------
 *
 * All four 2.6 parameters were declared S_IRUGO, and "iobase" and "irq" only
 * meant anything to the deleted ISA path.  What is left is major, debug (now
 * writable at runtime, which is the root-only equivalent of the /proc knob),
 * and two new ones for the card-identification problem described at
 * eg_identify().
 */
static int major = EVGEN_MAJOR;
int eg_debug = DEBUG_OFF;
static char *slot;
static bool force;

module_param(major, int, 0444);
MODULE_PARM_DESC(major,
		 "[major=X] X=0 (default) allocates a major number dynamically; 1<=X<=255 requests major X.");
module_param_named(debug, eg_debug, int, 0644);
MODULE_PARM_DESC(debug,
		 "[debug=Y] 0 = silent (default) through 8 = everything.  7 and 8 log every register access and will flood the journal.");
module_param(slot, charp, 0444);
MODULE_PARM_DESC(slot,
		 "[slot=0000:02:01.0] bind only to this PCI address; by default any matching card is considered.");
module_param(force, bool, 0444);
MODULE_PARM_DESC(force,
		 "[force=1] bind even if the card looks like the AT distributed clock rather than an event generator.  See eg_identify().");

MODULE_AUTHOR("CSIRO ATNF");
MODULE_DESCRIPTION("CSIRO ATNF PC Event Generator (EG) PCI Char Driver");
MODULE_LICENSE("GPL");
MODULE_VERSION(EG_VERSION);

/*
 * One event generator per host, as in 2.6 - the state was a single file-scope
 * "EGSysInfo_struct SysInfo" there.  The difference is that a second card is
 * now refused with a message instead of silently overwriting the first one's
 * state.
 */
static struct eg_dev *eg_the_card;
static DEFINE_MUTEX(eg_bind_lock);

static struct class *eg_class;

/*
 * ---------------------------------------------------------------------------
 * Register access
 * ---------------------------------------------------------------------------
 *
 * Was four function pointers in the device structure (ReadWord, WriteWord,
 * ReadByte, WriteByte), assigned to either the PCI or the ISA implementation
 * at probe time and called as (*sysinfo).ReadWord(BaseAddr + OFFSET) - pointer
 * arithmetic on an unsigned long, cast to a volatile pointer and dereferenced.
 *
 * With the ISA card gone there is one implementation, and taking the offset
 * separately from the mapping keeps the debug output meaningful: printing the
 * absolute address was useless anyway, since modern printk hashes kernel
 * pointers.
 */
u16 eg_readw(struct eg_dev *dev, unsigned int off)
{
	u16 p = readw(dev->bar + off);

	eg_dbg(DEBUG_PCI, "Read 16 bits %04x from +%02x\n", p, off);
	return p;
}

void eg_writew(struct eg_dev *dev, unsigned int off, u16 data)
{
	writew(data, dev->bar + off);
	eg_dbg(DEBUG_PCI, "Wrote 16 bits %04x to +%02x\n", data, off);
}

u8 eg_readb(struct eg_dev *dev, unsigned int off)
{
	u8 p = readb(dev->bar + off);

	eg_dbg(DEBUG_PCI, "Read 8 bits %02x from +%02x\n", p, off);
	return p;
}

void eg_writeb(struct eg_dev *dev, unsigned int off, u8 data)
{
	writeb(data, dev->bar + off);
	eg_dbg(DEBUG_PCI, "Wrote 8 bits %02x to +%02x\n", data, off);
}

/* Wishbone bridge registers live in a different BAR and are 32 bits wide. */
static u32 eg_wb_readl(struct eg_dev *dev, unsigned int off)
{
	return readl(dev->wishbone + off);
}

static void eg_wb_writel(struct eg_dev *dev, unsigned int off, u32 data)
{
	writel(data, dev->wishbone + off);
}

/*
 * ---------------------------------------------------------------------------
 * Waiting
 * ---------------------------------------------------------------------------
 *
 * timeout is in jiffies; 0 means "no timeout configured", which the 2.6 driver
 * expressed by passing MAX_SCHEDULE_TIMEOUT to schedule_timeout().
 *
 * Returns 0 if it timed out, -ERESTARTSYS if a signal arrived, and a positive
 * value otherwise - the same three cases the old code tried to distinguish by
 * inspecting current->timeout and current->blocked afterwards.
 */
static long eg_wait(struct eg_user *u, int timeout)
{
	long t = timeout ? timeout : MAX_SCHEDULE_TIMEOUT;

	return wait_event_interruptible_timeout(u->wq, u->pending, t);
}

/* Arm one user for a set of hardware interrupt bits.  Caller holds dev->lock. */
static void eg_arm_locked(struct eg_user *u, u32 primary, u32 rising,
			  u32 falling)
{
	u->pending = false;
	u->src.Primary = 0;
	u->src.Rising = 0;
	u->src.Falling = 0;
	u->req.Primary = primary;
	u->req.Rising = rising;
	u->req.Falling = falling;
}

static void eg_disarm(struct eg_dev *dev, struct eg_user *u)
{
	unsigned long flags;

	spin_lock_irqsave(&dev->lock, flags);
	u->req.Primary = 0;
	u->req.Rising = 0;
	u->req.Falling = 0;
	spin_unlock_irqrestore(&dev->lock, flags);
}

/****************************************************************************
*
* Get the firmware version/serial number string from the event generator PROM.
* NOTE- This function assumes exclusive use of the event generator.
*
* RETURNS: 0 if OK, or an error code otherwise
*
* Unchanged from 2.6 apart from the accessors and the string being built in a
* local buffer rather than written into the structure a bit at a time, so that
* a failed read cannot leave a half-decoded string on display.
****************************************************************************/

#define TIME_DELAY 10
#define MAXBITS    1000

static int GetEGSerial(struct eg_dev *dev)
{
	char string[MAX_EG_IDENT_LENGTH + 4];
	int n, bit;

	memset(string, 0, sizeof(string));

	if (dev->pub.Status != EG_LD_STATUS_OK) {
		pr_warn(EG_DRV_NAME ": no EG present, cannot read serial number\n");
		return ER_NoEventGen;
	}

	/*
	 * Reset the version/serial number PROM and set 'insert 4 wait states'.
	 * NOTE- '4 wait states' is needed to properly clock the PROM.
	 */
	eg_writew(dev, MASTER_REG, MA_4Waits | MA_LoadedGrabFrame);
	udelay(TIME_DELAY);

	/*
	 * The version/serial number preamble consists of any number of 1s,
	 * followed by a 0, followed by seven more bits, so first find the 0
	 * bit.  NOTE- before reading each bit insert a delay, because 'insert
	 * 4 wait states' is not enough (per E Davis).
	 */
	for (n = 0; n < MAXBITS; n++) {
		udelay(TIME_DELAY);
		if ((eg_readw(dev, MASTER_REG) & MA_SerNumBit) == 0)
			break;
		eg_readw(dev, FIFO_REG);  /* inc PROM address counter */
	}

	if (n >= MAXBITS) {
		eg_writew(dev, MASTER_REG, 0);
		pr_warn(EG_DRV_NAME ": no serial number preamble\n");
		return ER_EGPreambleError;
	}

	/* skip remaining bits in preamble */
	for (n = 0; n < 8; n++) {
		udelay(TIME_DELAY);
		eg_readw(dev, FIFO_REG);
	}

	/* now read characters until a null (end-of-string) is found */
	for (n = 0; n < MAX_EG_IDENT_LENGTH; n++) {
		string[n] = '\0';
		for (bit = 0; bit < 8; bit++) {
			udelay(TIME_DELAY);
			if (eg_readw(dev, MASTER_REG) & MA_SerNumBit)
				string[n] |= (1 << bit);

			eg_dbg(DEBUG_IFRW, "ident[%d] = %02x\n", n,
			       string[n] & 0x7f);
			udelay(TIME_DELAY);
			eg_readw(dev, FIFO_REG); /* inc PROM address counter */
		}
		if (string[n] == '\0')
			break;
	}

	/* reset 'insert 4 wait states' */
	eg_writew(dev, MASTER_REG, 0);

	if (n >= MAX_EG_IDENT_LENGTH)
		return ER_EGSerNumTooLong;

	strscpy(dev->pub.IdentString, string, sizeof(dev->pub.IdentString));
	return 0;
}

/*****************************************************************************
*
* Determine the size of the event generator reference FIFO
* NOTE- This function assumes exclusive use of the event generator.
*
* RETURNS: FIFO size in number of 4-byte events which the FIFO will hold, or
*          0 if error
*
*****************************************************************************/

#define TOOBIG 30000

static int GetFifoSize(struct eg_dev *dev)
{
	int count;

	/* reset reference fifo */
	eg_writew(dev, MASTER_REG, MA_PLLResetRefFifo | MA_LatePurgeEvent);

	/*
	 * Find the size by filling the MS reference FIFO until the 'MS Ref FIFO
	 * Full' signal becomes true.  Doing only byte transfers to the FIFO
	 * prevents the EG from consuming any of the FIFO.  Using the MS byte
	 * requires no delay between inserting a FIFO entry and checking the
	 * FIFO full signal since this is a "fast signal".
	 */
	for (count = 1; count < TOOBIG; count++) {
		eg_writeb(dev, FIFO_REG + 1, 0);
		if ((~eg_readw(dev, MASTER_REG) & MA_MSRefFifoFull) != 0)
			break;
	}

	/* reset reference fifo */
	eg_writew(dev, MASTER_REG, MA_PLLResetRefFifo | MA_LatePurgeEvent);

	/*
	 * Each event is 48 bits of BAT plus 16 bits of event bits = 64 bits.
	 * Multiply count by 2 for the LS and MS FIFOs, divide by 8 for 64 bits.
	 */
	return (count == TOOBIG) ? 0 : count / 4;
}

/*
 * ---------------------------------------------------------------------------
 * Card identification
 * ---------------------------------------------------------------------------
 *
 * PLX_VENDOR_ID:PLX_DEVICE_ID (10b5:9030) is the generic PLX 9030 bridge ID.
 * The AT Distributed Clock, driven by the separate "atdcif" module, sits on
 * the same carrier and is normally in the same chassis - on the machine this
 * port was developed on the two cards are 02:01.0 and 02:02.0, with identical
 * vendor:device IDs.  The kernel offers both to whichever driver is loaded
 * first, and the 2.6 driver bound whichever PLX 9030 pci_find_device()
 * returned, so on a two-card host which card you got was a coin toss.
 *
 * The obvious check does not work.  The serial-number PROM is part of the
 * shared carrier, so BOTH boards read back "PC EVENT GENERATOR Vx.y ...
 * SNnnnn"; it is logged here because it carries the board serial number, but
 * it cannot be used to tell the two apart.
 *
 * What can is the size of the register window the PLX serial EEPROM programs
 * into BAR2, which is sized to each board's register map:
 *
 *	event generator		registers to 0x2e	BAR2 0x40 bytes
 *	AT distributed clock	registers to 0xd0	BAR2 0x400 bytes
 *
 * and the PCI class the same EEPROM supplies - 0880 (system peripheral) for
 * the event generator, 0680 (bridge, other) for the clock.
 *
 * A card is accepted if it looks like an event generator on EITHER signal, so
 * a board whose EEPROM was programmed with an unexpected class still binds as
 * long as its register window is event-generator sized, and vice versa.  It is
 * refused only when both say "this is the clock" - and even then "force=1"
 * overrides, with "slot=" to pin the driver to one PCI address.
 *
 * Note that atdcif does not currently make the reciprocal check, so on a host
 * with both cards it is still the load order that decides what atdcif gets.
 */
static int eg_identify(struct eg_dev *dev)
{
	unsigned int class = dev->pdev->class >> 8;
	bool class_ok = (class == EG_PCI_CLASS);
	bool size_ok = (dev->region_size < EG_MAX_REGION_SIZE);
	u16 csr;

	csr = eg_readw(dev, MASTER_REG);
	if (csr == 0xffff) {
		pr_warn(EG_DRV_NAME
			": %s: master register reads all ones - nothing decoding behind %s\n",
			pci_name(dev->pdev), dev->bar_name);
		return -ENODEV;
	}

	if (!class_ok && !size_ok) {
		if (!force) {
			pr_notice(EG_DRV_NAME
				  ": %s: PCI class %04x with a %llu byte BAR%d - this is the AT distributed clock, not an event generator\n",
				  pci_name(dev->pdev), class,
				  (unsigned long long)dev->region_size,
				  dev->bar_no);
			pr_notice(EG_DRV_NAME
				  ": %s: leaving it for atdcif.  Override with force=1, or pin this driver with slot=<address>.\n",
				  pci_name(dev->pdev));
			return -ENODEV;
		}
		pr_warn(EG_DRV_NAME
			": %s: does not look like an event generator (class %04x, BAR%d %llu bytes); binding anyway because force=1\n",
			pci_name(dev->pdev), class, dev->bar_no,
			(unsigned long long)dev->region_size);
	}

	eg_dbg(DEBUG_CRIT, "identity: class %04x (%s), BAR%d %llu bytes (%s)\n",
	       class, class_ok ? "expected" : "unexpected", dev->bar_no,
	       (unsigned long long)dev->region_size,
	       size_ok ? "expected" : "unexpected");

	dev->pub.Status = EG_LD_STATUS_OK;

	/*
	 * Informational only.  The string identifies the carrier and carries
	 * the board serial number; it is the same text on the clock.
	 */
	if (GetEGSerial(dev) == 0) {
		pr_info(EG_DRV_NAME ": %s: ID: %s\n", pci_name(dev->pdev),
			dev->pub.IdentString);
		if (!strstr(dev->pub.IdentString, EG_IDENT_SIGNATURE))
			pr_notice(EG_DRV_NAME
				  ": %s: PROM does not contain \"%s\" - unexpected, but not fatal\n",
				  pci_name(dev->pdev), EG_IDENT_SIGNATURE);
	} else {
		pr_warn(EG_DRV_NAME ": %s: serial number PROM unreadable\n",
			pci_name(dev->pdev));
		strscpy(dev->pub.IdentString, "NOT AVAILABLE",
			sizeof(dev->pub.IdentString));
	}

	return 0;
}

/*
 * Put the card into a known state.  Was the tail of init_module() in 2.6 and
 * then, verbatim again, InitialiseEGHardware().
 */
static void eg_init_hardware(struct eg_dev *dev)
{
	/* turn off all interrupts */
	eg_writew(dev, IC_REG, 0);
	/* clear the IS register */
	eg_readw(dev, IS_REG);

	/* turn off all extended interrupts */
	eg_writew(dev, XIC_RE_REG_0, 0);
	eg_writew(dev, XIC_RE_REG_1, 0);
	eg_writew(dev, XIC_FE_REG_0, 0);
	eg_writew(dev, XIC_FE_REG_1, 0);

	/* clear the extended IS registers */
	eg_readw(dev, XIS_RE_REG_0);
	eg_readw(dev, XIS_RE_REG_1);
	eg_readw(dev, XIS_FE_REG_0);
	eg_readw(dev, XIS_FE_REG_1);

	dev->pub.FifoSize = GetFifoSize(dev);
	if (dev->pub.FifoSize != 0)
		pr_info(EG_DRV_NAME ": FIFO size: %d events\n",
			dev->pub.FifoSize);
	else
		pr_warn(EG_DRV_NAME ": FIFO size: NOT AVAILABLE\n");

	/* reset reference FIFO */
	eg_writew(dev, MASTER_REG, MA_PLLResetRefFifo | MA_LatePurgeEvent);

	/*
	 * Clear all event outputs.  To do this set the event output
	 * control/status register 'expert bit', which allows setting the host
	 * event register, clear the event register, then reset the 'expert bit'.
	 */
	eg_writew(dev, EVENT_CTRL_REG, EC_Expert);
	eg_writew(dev, EVENT_REG, 0);
	eg_writew(dev, EVENT_CTRL_REG, 0);
}

/*
 * ---------------------------------------------------------------------------
 * The interrupt handler
 * ---------------------------------------------------------------------------
 *
 * Same logic as 2.6, with the pt_regs argument gone, the accessors changed,
 * and the whole body under dev->lock so that its read-modify-write of the
 * interrupt control register cannot race the ioctl paths doing the same thing.
 */
static irqreturn_t EGInterrupt(int irq, void *dev_id)
{
	struct eg_dev *dev = dev_id;
	unsigned long flags;
	unsigned int icr, isr, l_isr;
	u32 icxre, icxfe, isxre, isxfe;
	u32 xire_off = 0, xife_off = 0;
	u16 interrupts_off = 0;
	int ref, ir;

	spin_lock_irqsave(&dev->lock, flags);

	/* Mod for Wishbone interface (A. Brown) */
	if (dev->wishbone) {
		/*
		 * Clear the wishbone interrupt if there was one; the secondary
		 * status registers below carry the information we act on.
		 */
		eg_wb_readl(dev, WISHBONE_ISR);
		eg_wb_readl(dev, WISHBONE_ICR);
	}

	/* find out which interrupts are enabled */
	icr = eg_readw(dev, IC_REG);

	/* get which signals caused the interrupt */
	isr = eg_readw(dev, IS_REG);

	isr &= icr;

	if (isr == 0) {
		spin_unlock_irqrestore(&dev->lock, flags);
		return IRQ_NONE;
	}

	dev->stats.List[STATS_INTERRUPT_COUNT].Value++;

	if (isr & IC_FIFOHalfEmpty) {
		dev->stats.List[STATS_HALF_EMPTY_INTR_COUNT].Value++;
		interrupts_off |= IC_FIFOHalfEmpty;
	}

	/*
	 * For the four error sources, count how many arrive within one jiffy
	 * and mask the source if it exceeds MAX_INTERRUPT_RATE, so that a card
	 * screaming at line rate cannot livelock the machine.  Re-enabled below
	 * once the jiffy has moved on.
	 */
	if (isr & IC_LateEvent) {
		dev->stats.List[STATS_LATE_EVENT_INTR_COUNT].Value++;
		ir = IR_LATE_EVENT;
		if (jiffies == dev->pub.InterruptRate[ir].Jiffies) {
			if (++dev->pub.InterruptRate[ir].Count >
			    MAX_INTERRUPT_RATE)
				interrupts_off |= IC_LateEvent;
		} else {
			dev->pub.InterruptRate[ir].Jiffies = jiffies;
			dev->pub.InterruptRate[ir].Count = 0;
		}
	}

	if (isr & IC_CheckSumError) {
		dev->stats.List[STATS_CHECK_SUM_INTR_COUNT].Value++;
		ir = IR_CHECK_SUM;
		if (jiffies == dev->pub.InterruptRate[ir].Jiffies) {
			if (++dev->pub.InterruptRate[ir].Count >
			    MAX_INTERRUPT_RATE)
				interrupts_off |= IC_CheckSumError;
		} else {
			dev->pub.InterruptRate[ir].Jiffies = jiffies;
			dev->pub.InterruptRate[ir].Count = 0;
		}
	}

	if (isr & IC_FalseSync) {
		dev->stats.List[STATS_FALSE_SYNC_INTR_COUNT].Value++;
		ir = IR_FALSE_SYNC;
		if (jiffies == dev->pub.InterruptRate[ir].Jiffies) {
			if (++dev->pub.InterruptRate[ir].Count >
			    MAX_INTERRUPT_RATE)
				interrupts_off |= IC_FalseSync;
		} else {
			dev->pub.InterruptRate[ir].Jiffies = jiffies;
			dev->pub.InterruptRate[ir].Count = 0;
		}
	}

	if (isr & IC_MissedSync) {
		dev->stats.List[STATS_MISSED_SYNC_INTR_COUNT].Value++;
		ir = IR_MISSED_SYNC;
		if (jiffies == dev->pub.InterruptRate[ir].Jiffies) {
			if (++dev->pub.InterruptRate[ir].Count >
			    MAX_INTERRUPT_RATE)
				interrupts_off |= IC_MissedSync;
		} else {
			dev->pub.InterruptRate[ir].Jiffies = jiffies;
			dev->pub.InterruptRate[ir].Count = 0;
		}
	}

	if (isr & IC_FrameLoaded) {
		dev->stats.List[STATS_FRAME_LOADED_INTR_COUNT].Value++;
		eg_dbg(DEBUG_INTERRUPT, "FrameLoaded interrupt\n");
		interrupts_off |= IC_FrameLoaded;
	}

	if (isr & IC_ExtInt) {
		dev->stats.List[STATS_EXTERNAL_INTR_COUNT].Value++;
		interrupts_off |= IC_ExtInt;
	}

	/* internal event */
	if (isr & IC_Event) {
		dev->stats.List[STATS_INTERNAL_INTR_COUNT].Value++;
		interrupts_off |= IC_Event;
	}

	if (isr & IC_PLLUnlocked)
		dev->stats.List[STATS_PLL_UNLOCKED_INTR_COUNT].Value++;

	if (isr & IC_1Second) {
		dev->stats.List[STATS_ONE_SECOND_INTR_COUNT].Value++;
		interrupts_off |= IC_1Second;
	}

	if (isr & IC_Finished) {
		dev->stats.List[STATS_FINISHED_INTR_COUNT].Value++;
		interrupts_off |= IC_Finished;
	}

	if (isr & IC_Extended)
		dev->stats.List[STATS_EXTENDED_INTR_COUNT].Value++;

	/* read extended control registers - rising edge */
	icxre = eg_readw(dev, XIC_RE_REG_0) |
		((u32)eg_readw(dev, XIC_RE_REG_1) << XI_REG_WIDTH);

	/* falling edge */
	icxfe = eg_readw(dev, XIC_FE_REG_0) |
		((u32)eg_readw(dev, XIC_FE_REG_1) << XI_REG_WIDTH);

	/* read extended status registers, aligned to the control registers */
	isxre = eg_readw(dev, XIS_RE_REG_0) |
		((u32)eg_readw(dev, XIS_RE_REG_1) << XI_REG_WIDTH);

	isxfe = eg_readw(dev, XIS_FE_REG_0) |
		((u32)eg_readw(dev, XIS_FE_REG_1) << XI_REG_WIDTH);

	eg_dbg(DEBUG_INTERRUPT, "XIntr: ICR: %08x %08x ISR: %08x %08x\n",
	       icxre, icxfe, isxre, isxfe);

	isxre &= icxre;
	xire_off = isxre;

	isxfe &= icxfe;
	xife_off = isxfe;

	l_isr = (isr & IC_PhysicalIntrMask) & ~IC_Extended;

	for (ref = 0; ref < MAX_NUM_EG_USERS; ++ref) {
		struct eg_user *u = &dev->users[ref];

		if (!u->in_use)
			continue;

		if ((l_isr & u->req.Primary) == 0 &&
		    (isxre & u->req.Rising) == 0 &&
		    (isxfe & u->req.Falling) == 0)
			continue;

		/* record which lines triggered the interrupt */
		u->src.Primary = l_isr & u->req.Primary;
		u->src.Rising  = isxre & u->req.Rising;
		u->src.Falling = isxfe & u->req.Falling;

		u->req.Primary = 0;
		u->req.Rising = 0;
		u->req.Falling = 0;

		u->pending = true;
		wake_up_interruptible(&u->wq);
	}

	/*
	 * See which rate-limited interrupts are currently off, and if the
	 * jiffy in which each was last serviced has passed, turn it back on.
	 */
	if ((icr & IC_LateEvent) == 0 &&
	    jiffies != dev->pub.InterruptRate[IR_LATE_EVENT].Jiffies)
		icr |= IC_LateEvent;

	if ((icr & IC_CheckSumError) == 0 &&
	    jiffies != dev->pub.InterruptRate[IR_CHECK_SUM].Jiffies)
		icr |= IC_CheckSumError;

	if ((icr & IC_FalseSync) == 0 &&
	    jiffies != dev->pub.InterruptRate[IR_FALSE_SYNC].Jiffies)
		icr |= IC_FalseSync;

	if ((icr & IC_MissedSync) == 0 &&
	    jiffies != dev->pub.InterruptRate[IR_MISSED_SYNC].Jiffies)
		icr |= IC_MissedSync;

	/* turn off flagged interrupts */
	if (interrupts_off != 0) {
		icr &= ~interrupts_off;
		eg_writew(dev, IC_REG, icr);
	}

	if (xire_off != 0) {
		icxre &= ~xire_off;
		eg_writew(dev, XIC_RE_REG_0, icxre & XI_REG_0_Mask);
		eg_writew(dev, XIC_RE_REG_1,
			  (icxre >> XI_REG_WIDTH) & XI_REG_1_Mask);
	}
	if (xife_off != 0) {
		icxfe &= ~xife_off;
		eg_writew(dev, XIC_FE_REG_0, icxfe & XI_REG_0_Mask);
		eg_writew(dev, XIC_FE_REG_1,
			  (icxfe >> XI_REG_WIDTH) & XI_REG_1_Mask);
	}

	/* if no extended interrupts remain enabled, drop the extended bit */
	if (icxre == 0 && icxfe == 0) {
		icr &= ~IC_Extended;
		eg_writew(dev, IC_REG, icr);
	}

	spin_unlock_irqrestore(&dev->lock, flags);

	return IRQ_HANDLED;
}

/**********************************************************************
   Open an Event Generator device
**********************************************************************/

static int EGOpen(struct inode *inode, struct file *filp)
{
	struct eg_dev *dev = container_of(inode->i_cdev, struct eg_dev, cdev);
	int minor = iminor(inode);
	struct eg_user *u = NULL;
	unsigned long flags;
	int ref;
	u16 data;

	if (minor >= MAX_NUM_EG_DEVICES)
		return -ENODEV;

	eg_dbg(DEBUG_INFO, "open requested on device %d:%d\n",
	       imajor(inode), minor);

	spin_lock_irqsave(&dev->lock, flags);

	/*
	 * One opener per minor, as in 2.6.  The 2.6 code compared
	 * OpenOwner[minor] against 0 for the read-only case but did not set it
	 * for the write case until after it had already taken write ownership,
	 * so the two halves disagreed about who held the node; both are now
	 * decided in one place under the lock.
	 */
	if (dev->open_owner[minor] != 0) {
		spin_unlock_irqrestore(&dev->lock, flags);
		eg_dbg(DEBUG_INFO, "minor %d already has an owner\n", minor);
		return -EBUSY;
	}

	if ((filp->f_flags & O_ACCMODE) == O_WRONLY ||
	    (filp->f_flags & O_ACCMODE) == O_RDWR) {
		if (dev->write_owner != -1) {
			spin_unlock_irqrestore(&dev->lock, flags);
			eg_dbg(DEBUG_INFO, "device already has a write owner\n");
			return -EBUSY;
		}
		dev->write_owner = minor;

		/* Enable the late event interrupt */
		data = eg_readw(dev, IC_REG);
		eg_writew(dev, IC_REG, data | IC_LateEvent | IC_Enable);
	}

	for (ref = 0; ref < MAX_NUM_EG_USERS; ++ref) {
		if (!dev->users[ref].in_use) {
			u = &dev->users[ref];
			break;
		}
	}

	if (!u) {
		if (dev->write_owner == minor)
			dev->write_owner = -1;
		spin_unlock_irqrestore(&dev->lock, flags);
		pr_warn(EG_DRV_NAME ": no free wait slot (max %d opens)\n",
			MAX_NUM_EG_USERS);
		return -EBUSY;
	}

	u->in_use = true;
	u->minor = minor;
	u->dev = dev;
	u->pending = false;
	memset(&u->req, 0, sizeof(u->req));
	memset(&u->src, 0, sizeof(u->src));

	dev->open_owner[minor] = task_tgid_nr(current);
	dev->stats.List[STATS_USE_COUNT].Value++;

	spin_unlock_irqrestore(&dev->lock, flags);

	filp->private_data = u;

	/*
	 * Kept from 2.6: the driver's own O_NONBLOCK flag is controlled with
	 * EVGEN_SET_OPTION / EVGEN_CLEAR_OPTION, so whatever open() was given
	 * is discarded here.
	 */
	spin_lock(&filp->f_lock);
	filp->f_flags &= ~O_NONBLOCK;
	spin_unlock(&filp->f_lock);

	return 0;
}

static int EGClose(struct inode *inode, struct file *filp)
{
	struct eg_user *u = filp->private_data;
	struct eg_dev *dev = u->dev;
	int minor = u->minor;
	unsigned long flags;

	spin_lock_irqsave(&dev->lock, flags);

	if (dev->write_owner == minor)
		dev->write_owner = -1;

	if (dev->grab_frame_initiator == minor)
		dev->grab_frame_initiator = -1;

	dev->open_owner[minor] = 0;
	dev->stats.List[STATS_USE_COUNT].Value--;

	/*
	 * Release the slot, and wake anyone sleeping on it first.  In 2.6 the
	 * slot stayed occupied until some later claim noticed the PID was gone.
	 */
	u->in_use = false;
	u->pending = true;
	memset(&u->req, 0, sizeof(u->req));

	spin_unlock_irqrestore(&dev->lock, flags);

	wake_up_interruptible(&u->wq);

	eg_dbg(DEBUG_INFO, "closing event generator minor %d\n", minor);

	return 0;
}

/*
 * ---------------------------------------------------------------------------
 * read() - grab a frame off the clock bus
 * ---------------------------------------------------------------------------
 *
 * If a grab is already under way the new request piggybacks on it rather than
 * starting a second one.
 */
static ssize_t EGInitiateGrabFrame(struct eg_dev *dev, struct eg_user *u,
				   char __user *retbuffer, size_t count)
{
	unsigned long flags;
	int minor = u->minor;
	int timeout = dev->wait_grab_frame_timeout[minor];
	size_t length;
	u16 data;
	long ret;
	int n;

	eg_dbg(DEBUG_IF, "IGF: initiating\n");

	spin_lock_irqsave(&dev->lock, flags);

	eg_arm_locked(u, IC_FrameLoaded, 0, 0);

	/* Set up the interrupt */
	data = eg_readw(dev, IC_REG);
	eg_dbg(DEBUG_IF, "IGF: current ICR %04x\n", data);
	eg_writew(dev, IC_REG, data | IC_FrameLoaded | IC_Enable);

	/* initiate the grab frame */
	data = eg_readw(dev, MASTER_REG);
	eg_writew(dev, MASTER_REG,
		  (data & ~(MA_PLLResetRefFifo | MA_LatePurgeEvent)) |
		  MA_LoadedGrabFrame);

	spin_unlock_irqrestore(&dev->lock, flags);

	eg_dbg(DEBUG_IF, "IGF: waiting, timeout %d jiffies\n", timeout);

	ret = eg_wait(u, timeout);

	eg_disarm(dev, u);

	if (ret == -ERESTARTSYS)
		return -ERESTARTSYS;

	if (timeout != 0 && ret == 0) {
		eg_dbg(DEBUG_IF, "IGF: timed out\n");
		return -EBUSY;
	}

	eg_dbg(DEBUG_IF, "IGF: awake, %llu frame loaded interrupts\n",
	       dev->stats.List[STATS_FRAME_LOADED_INTR_COUNT].Value);

	/*
	 * Download the frame from the FIFO into the shared buffer.  Each read
	 * returns one byte of the frame in its low half; userspace reassembles
	 * the 48-bit BAT from the first six bytes.
	 */
	for (n = 0; n < MAX_LENGTH_FRAME; ++n) {
		udelay(1);
		dev->frame_data[n] = eg_readw(dev, FIFO_REG);
	}

	/* let anyone piggybacking on this operation know */
	spin_lock_irqsave(&dev->lock, flags);
	for (n = 0; n < MAX_NUM_EG_USERS; ++n) {
		struct eg_user *p = &dev->users[n];

		if (p->in_use && (p->req.Primary & IC_GrabFrameComplete)) {
			p->src.Primary |= IC_GrabFrameComplete;
			p->req.Primary = 0;
			p->pending = true;
			wake_up_interruptible(&p->wq);
		}
	}
	spin_unlock_irqrestore(&dev->lock, flags);

	length = min_t(size_t, count, MAX_LENGTH_FRAME);

	if (copy_to_user(retbuffer, dev->frame_data, length))
		return -EFAULT;

	return length;
}

static ssize_t EGPiggyBackGrabFrame(struct eg_dev *dev, struct eg_user *u,
				    char __user *retbuffer, size_t count)
{
	unsigned long flags;
	int timeout = dev->wait_grab_frame_timeout[u->minor];
	size_t length;
	long ret;

	eg_dbg(DEBUG_IF, "PBRF: pid %d\n", task_pid_nr(current));

	spin_lock_irqsave(&dev->lock, flags);
	eg_arm_locked(u, IC_GrabFrameComplete, 0, 0);
	spin_unlock_irqrestore(&dev->lock, flags);

	ret = eg_wait(u, timeout);

	eg_disarm(dev, u);

	if (ret == -ERESTARTSYS)
		return -ERESTARTSYS;

	if (timeout != 0 && ret == 0) {
		eg_dbg(DEBUG_IF, "PBRF: timed out\n");
		return -EAGAIN;
	}

	length = min_t(size_t, count, MAX_LENGTH_FRAME);

	if (copy_to_user(retbuffer, dev->frame_data, length))
		return -EFAULT;

	return length;
}

static ssize_t EGRead(struct file *filp, char __user *retbuffer, size_t count,
		      loff_t *offset)
{
	struct eg_user *u = filp->private_data;
	struct eg_dev *dev = u->dev;
	unsigned long flags;
	bool initiator;
	ssize_t ret;

	eg_dbg(DEBUG_IF, "read: minor %d, count %zu\n", u->minor, count);

	if (count == 0)
		return 0;

	/*
	 * Claim the right to initiate, or fall back to piggybacking on whoever
	 * already has it.  In 2.6 the test and the claim were separated by a
	 * local_irq_restore(), so two CPUs could both decide they were the
	 * initiator.
	 */
	spin_lock_irqsave(&dev->lock, flags);
	initiator = (dev->grab_frame_initiator == -1);
	if (initiator)
		dev->grab_frame_initiator = u->minor;
	spin_unlock_irqrestore(&dev->lock, flags);

	if (initiator) {
		ret = EGInitiateGrabFrame(dev, u, retbuffer, count);

		spin_lock_irqsave(&dev->lock, flags);
		dev->grab_frame_initiator = -1;
		spin_unlock_irqrestore(&dev->lock, flags);

		return ret;
	}

	return EGPiggyBackGrabFrame(dev, u, retbuffer, count);
}

/*************************************************************************
              The write() implementation

 Write transfers a block of Time/Events to the EG.
 Only devices opened for write can perform this function.
 Event format is the same as the Event Generator expects, i.e.:
 0 : BAT[0-15]  LS BAT.
 1 : BAT[16-31]
 2 : BAT[32-47] MS BAT.
 3 : Event[0-15]

 The call to write is slightly different from a normal write: the third
 parameter is not the size of the array "data" but the number of EVENTS in
 that array.  Writing one event passes 1, not 8.

     int write(handle, unsigned short int *data, int num_events);

 The return value is likewise a count of events, not of bytes.
*************************************************************************/

static ssize_t EGWrite(struct file *filp, const char __user *inbuffer,
		       size_t count, loff_t *offset)
{
	struct eg_user *u = filp->private_data;
	struct eg_dev *dev = u->dev;
	const u16 __user *bufferp = (const u16 __user *)inbuffer;
	unsigned long flags;
	u16 egbuffer[EG_NUM_ELEMENTS_IN_EVENT_DEF];
	size_t loops = 0;
	unsigned int written;
	u16 data;
	long ret;

	/* check that this device was opened for write access */
	if (u->minor != dev->write_owner)
		return -EINVAL;

	if (count == 0)
		return 0;

	while (loops < count) {
		dev->write_state = WRITE_STATE_WRITING;

		/*
		 * 2.6 read from &bufferp[loops], advancing one u16 per event
		 * instead of EG_NUM_ELEMENTS_IN_EVENT_DEF of them.
		 */
		if (copy_from_user(egbuffer,
				   &bufferp[loops * EG_NUM_ELEMENTS_IN_EVENT_DEF],
				   sizeof(egbuffer))) {
			pr_warn(EG_DRV_NAME ": write: copy from user failed\n");
			dev->write_state = WRITE_STATE_USC_FAIL;
			return loops ? (ssize_t)loops : -EFAULT;
		}

		/* is there room in the FIFO?  If not, wait for half empty. */
		data = eg_readw(dev, MASTER_REG);

		if ((data & MA_MSRefFifoFull) == 0) {
			dev->write_state = WRITE_STATE_FIFO_FULL;

			if (filp->f_flags & O_NONBLOCK) {
				dev->write_state = WRITE_STATE_IDLE;
				return loops ? (ssize_t)loops : -EAGAIN;
			}

			spin_lock_irqsave(&dev->lock, flags);

			eg_arm_locked(u, IC_FIFOHalfEmpty, 0, 0);

			data = eg_readw(dev, IC_REG);
			eg_writew(dev, IC_REG,
				  (data | IC_Enable | IC_FIFOHalfEmpty) &
				  IC_PhysicalIntrMask);

			/*
			 * Close the window between arming and sleeping: if the
			 * FIFO drained while we were setting this up, the edge
			 * is already gone and nothing would ever wake us.
			 */
			if (eg_readw(dev, MASTER_REG) & MA_MSRefFifoHalfEmpty)
				u->pending = true;

			spin_unlock_irqrestore(&dev->lock, flags);

			dev->write_state = WRITE_STATE_WAIT_ON_HE_INTERRUPT;

			ret = eg_wait(u, 0);

			eg_disarm(dev, u);

			dev->write_state = WRITE_STATE_WAIT_ON_HE_DONE;

			if (ret == -ERESTARTSYS) {
				dev->write_state = WRITE_STATE_SIGNAL_RECVD;
				return loops ? (ssize_t)loops : -ERESTARTSYS;
			}

			data = eg_readw(dev, MASTER_REG);
			if ((data & MA_MSRefFifoHalfEmpty) == 0) {
				pr_warn(EG_DRV_NAME
					": write: half empty interrupt but FIFO is not half empty\n");
				continue;
			}
			dev->write_state = WRITE_STATE_HE_INTR_ARRIVED;
		}

		eg_writew(dev, FIFO_REG, egbuffer[0]);
		eg_writew(dev, FIFO_REG, egbuffer[1]);
		eg_writew(dev, FIFO_REG, egbuffer[2]);
		eg_writew(dev, FIFO_REG, egbuffer[3]);

		++loops;
	}

	dev->write_state = WRITE_STATE_IDLE;

	/*
	 * Keep a tab on the number of events written, in thousands.  2.6 took
	 * the modulo first and then divided the remainder by 1000, so this
	 * counter was permanently zero.
	 */
	dev->write_event_subcount += loops;
	written = dev->write_event_subcount / 1000;
	if (written) {
		dev->write_event_subcount %= 1000;
		dev->stats.List[STATS_EVENTS_WRITTEN_COUNT].Value += written;
	}

	return loops;
}

/*
 * Translate the hardware interrupt source bits recorded by the handler into
 * the INTR_WAIT_ON_* bits userspace speaks.
 */
static void TransferInterruptSourceInfo(struct eg_user *u,
					InterruptMasks_struct *imp)
{
	memset(imp, 0, sizeof(*imp));

	if (u->src.Primary & IC_1Second)
		imp->Primary |= INTR_WAIT_ON_1SEC;
	if (u->src.Primary & IC_Event)
		imp->Primary |= INTR_WAIT_ON_INTERNAL;
	if (u->src.Primary & IC_ExtInt)
		imp->Primary |= INTR_WAIT_ON_EXTERNAL;
	if (u->src.Primary & IC_Finished)
		imp->Primary |= INTR_WAIT_ON_FINISHED;
	if (u->src.Primary & IC_LateEvent)
		imp->Primary |= INTR_WAIT_ON_LATE_EVENT;
	if (u->src.Primary & IC_FrameLoaded)
		imp->Primary |= INTR_WAIT_ON_FRAME_LOADED;
	if (u->src.Primary & IC_FIFOHalfEmpty)
		imp->Primary |= INTR_WAIT_ON_FIFO_HALF_EMPTY;
	if (u->src.Primary & IC_GrabFrameComplete)
		imp->Primary |= INTR_WAIT_ON_GRAB_FRAME_COMPLETE;

	imp->Rising = u->src.Rising;
	imp->Falling = u->src.Falling;
}

/*
 * Common body of EG_WAIT_ON_INTR_OP and EG_WAIT_ON_EXTENDED_INTR_OP.
 *
 * The 2.6 version of this ran to 200 lines with three nested version
 * conditionals, restored interrupts twice on one path, and open-coded the
 * sleep.  The register programming is identical.
 */
static long eg_wait_on_intr(struct file *filp, struct eg_user *u,
			    const InterruptMasks_struct *IM)
{
	struct eg_dev *dev = u->dev;
	unsigned long flags;
	u32 interrupt = 0;
	int wait_on_flag = 0;
	int timeout;
	u16 data;
	long ret;

	if (IM->Primary & INTR_WAIT_ON_1SEC) {
		interrupt |= IC_1Second;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_INTERNAL) {
		interrupt |= IC_Event;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_EXTERNAL) {
		interrupt |= IC_ExtInt;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_FINISHED) {
		interrupt |= IC_Finished;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_LATE_EVENT) {
		interrupt |= IC_LateEvent;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_FRAME_LOADED) {
		interrupt |= IC_FrameLoaded;
		++wait_on_flag;
	}
	if (IM->Primary & INTR_WAIT_ON_FIFO_HALF_EMPTY) {
		interrupt |= IC_FIFOHalfEmpty;
		++wait_on_flag;
	}

	if (IM->Rising != 0 || IM->Falling != 0) {
		interrupt |= IC_Extended;
		++wait_on_flag;
	}

	if (wait_on_flag == 0)
		return -EINVAL;

	spin_lock_irqsave(&dev->lock, flags);

	eg_arm_locked(u, interrupt, IM->Rising, IM->Falling);

	data = eg_readw(dev, IC_REG);
	data |= (interrupt | IC_Enable) & IC_PhysicalIntrMask;
	eg_writew(dev, IC_REG, data);

	if (interrupt & IC_Extended) {
		data = eg_readw(dev, XIC_RE_REG_0);
		data |= IM->Rising & XI_REG_0_Mask;
		eg_writew(dev, XIC_RE_REG_0, data);

		data = eg_readw(dev, XIC_RE_REG_1);
		data |= (IM->Rising >> XI_REG_WIDTH) & XI_REG_1_Mask;
		eg_writew(dev, XIC_RE_REG_1, data);

		data = eg_readw(dev, XIC_FE_REG_0);
		data |= IM->Falling & XI_REG_0_Mask;
		eg_writew(dev, XIC_FE_REG_0, data);

		data = eg_readw(dev, XIC_FE_REG_1);
		data |= (IM->Falling >> XI_REG_WIDTH) & XI_REG_1_Mask;
		eg_writew(dev, XIC_FE_REG_1, data);
	}

	spin_unlock_irqrestore(&dev->lock, flags);

	/*
	 * Non-blocking mode: the interrupt is armed, the caller will find out
	 * about it through poll()/select() on the exception set.
	 */
	if (filp->f_flags & O_NONBLOCK)
		return 0;

	timeout = dev->wait_intr_timeout[u->minor];

	ret = eg_wait(u, timeout);

	eg_disarm(dev, u);

	if (ret == -ERESTARTSYS)
		return -ERESTARTSYS;

	if (timeout != 0 && ret == 0)
		return -EAGAIN;

	return 0;
}

/*************************************************************************
              The ioctl() implementation
*************************************************************************/

static long EGIoctl(struct file *filp, unsigned int cmd, unsigned long parameters)
{
	void __user *uarg = (void __user *)parameters;
	struct eg_user *u = filp->private_data;
	struct eg_dev *dev = u->dev;
	int minor = u->minor;
	InterruptMasks_struct IM;
	unsigned long flags;
	unsigned int reg;
	int data, reg1, reg2;
	int interrupt, n;
	int wfnum;
	int op, type;
	int32_t size;
	unsigned char c;
	u32 bitPos;

	type = _IOC_TYPE(cmd);
	op = _IOC_NR(cmd);

	/* 2.6 printed these two lines unconditionally, on every ioctl. */
	eg_dbg(DEBUG_IOCTL, "ioctl cmd %08x: type %x, op %x\n", cmd, type, op);

	if (type != EVGEN_IOC_MAGIC)
		return -EINVAL;

	switch (op) {

/*************************************************************************
 EG_RESET_OP does a software reset of the EG. Only a write access owner
 can reset the EG
*************************************************************************/
	case EG_RESET_OP:
		if (minor != dev->write_owner)
			return -EINVAL;

		spin_lock_irqsave(&dev->lock, flags);

		data = eg_readw(dev, MASTER_REG) |
		       MA_LatePurgeEvent | MA_PLLResetRefFifo;
		eg_writew(dev, MASTER_REG, data);

		/* reset the interrupt rate monitors */
		interrupt = 0;
		for (n = 0; n < MAX_NUM_IR_POINTS; ++n) {
			dev->pub.InterruptRate[n].Jiffies = jiffies;
			dev->pub.InterruptRate[n].Count = 0;
			interrupt |= dev->pub.InterruptRate[n].InterruptBit;
		}

		data = eg_readw(dev, IC_REG);
		eg_writew(dev, IC_REG, data | interrupt | IC_Enable);

		spin_unlock_irqrestore(&dev->lock, flags);

		return 0;

/*************************************************************************
 EG_WAIT_ON_INTR_OP allows a user to wait for a particular interrupt.
 Both read and write opened devices can perform this function.
*************************************************************************/
	case EG_WAIT_ON_INTR_OP:
		memset(&IM, 0, sizeof(IM));
		IM.Primary = (u32)parameters;
		eg_dbg(DEBUG_IOCTL, "WOI: primary mask %08x\n", IM.Primary);
		return eg_wait_on_intr(filp, u, &IM);

	case EG_WAIT_ON_EXTENDED_INTR_OP:
		if (copy_from_user(&IM, uarg, sizeof(IM))) {
			pr_warn(EG_DRV_NAME
				": unable to read WaitOnInterrupt struct from user\n");
			return -EFAULT;
		}
		eg_dbg(DEBUG_IOCTL, "WOI: masks P:%08x R:%08x F:%08x\n",
		       IM.Primary, IM.Rising, IM.Falling);
		return eg_wait_on_intr(filp, u, &IM);

	case EG_RD_CURRENT_EVENT_OP:
		data = eg_readw(dev, EVENT_REG);
		if (copy_to_user(uarg, &data, sizeof(int)))
			return -EFAULT;
		return 0;

/*************************************************************************
 EG_WR_EVENT_DIRECT_OP allows the user to write directly to the event
 output register.  Only write opened devices can perform this function.
*************************************************************************/
	case EG_WR_EVENT_DIRECT_OP:
		if (minor != dev->write_owner)
			return -EINVAL;

		spin_lock_irqsave(&dev->lock, flags);

		/* set expert mode */
		data = eg_readw(dev, EVENT_CTRL_REG);
		eg_writew(dev, EVENT_CTRL_REG, data | EC_Expert);

		/* put the event out */
		eg_writew(dev, EVENT_REG, parameters & 0xffff);

		/*
		 * Delay a few microseconds before switching expert mode off.
		 * It takes up to 2 us to spit out the event, because the output
		 * operation is synchronised to the 1 us time frame.
		 */
		udelay(2);

		/*
		 * Restore the output control register.  2.6 dropped the lock
		 * before this write, so the register could be clobbered by a
		 * concurrent caller in between.
		 */
		eg_writew(dev, EVENT_CTRL_REG, data);

		spin_unlock_irqrestore(&dev->lock, flags);

		return 0;

/*************************************************************************
 EG_GET_INT_INTR_LINE_OP returns the event line used to cause an internal
 interrupt.
   int n;
   err = ioctl(handle, EVGEN_GET_INT_INTR_LINE, &n);
 If the MSB of n is set then the line is not enabled.
*************************************************************************/
	case EG_GET_INT_INTR_LINE_OP:
		data = eg_readw(dev, EVENT_CTRL_REG);

		if ((data & EC_TimeIntEna) == 0)
			data = ((data & EC_Int_Intr_Sel_Mask) >>
				EC_Int_Intr_Sel_Mask_Sft) | 0x80000000;
		else
			data = (data & EC_Int_Intr_Sel_Mask) >>
			       EC_Int_Intr_Sel_Mask_Sft;

		if (copy_to_user(uarg, &data, sizeof(int)))
			return -EFAULT;
		return 0;

/*************************************************************************
 EG_SET_INT_INTR_LINE_OP sets the event line used to cause an internal
 interrupt.
   err = ioctl(handle, EVGEN_SET_INT_INTR_LINE, 3);
*************************************************************************/
	case EG_SET_INT_INTR_LINE_OP:
		spin_lock_irqsave(&dev->lock, flags);

		data = eg_readw(dev, EVENT_CTRL_REG);
		data = (data & ~EC_Int_Intr_Sel_Mask) |
		       ((parameters << EC_Int_Intr_Sel_Mask_Sft) &
			EC_Int_Intr_Sel_Mask) |
		       EC_TimeIntEna | EC_TimeIntOutEna;
		eg_writew(dev, EVENT_CTRL_REG, data);

		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

/*************************************************************************
 EG_CLR_EVENTS_OP resets the FIFO and purges any pending event.
 Only write opened devices can perform this function.
*************************************************************************/
	case EG_CLR_EVENTS_OP:
		if (minor != dev->write_owner)
			return -EINVAL;

		spin_lock_irqsave(&dev->lock, flags);

		data = eg_readw(dev, MASTER_REG);

		/* reset the FIFO */
		eg_writew(dev, MASTER_REG,
			  (data & ~(MA_LoadedGrabFrame | MA_LatePurgeEvent)) |
			  MA_PLLResetRefFifo);

		/* purge the last event */
		eg_writew(dev, MASTER_REG,
			  (data & ~(MA_LoadedGrabFrame | MA_PLLResetRefFifo)) |
			  MA_LatePurgeEvent);

		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

/*************************************************************************
 EG_GET_EG_REG_OP returns the current value of an EG register.
 This function is for testing and should not be used by general code.
 'parameters' points to a user int that on entry holds the register offset
 in the top 16 bits, and on return holds the offset and the contents:
 32       16  15     0
 | address |  | data |
*************************************************************************/
	case EG_GET_EG_REG_OP:
		if (copy_from_user(&n, uarg, sizeof(int)))
			return -EFAULT;

		/*
		 * 2.6 kept this in a signed int and checked only "n >
		 * LAST_EG_REG", so a negative offset read outside the mapping.
		 */
		reg = ((unsigned int)n >> 16) & ~1u;
		if (reg > LAST_EG_REG)
			return -EINVAL;

		data = eg_readw(dev, reg);
		data |= (int)(reg << 16);   /* merge address and data */

		if (copy_to_user(uarg, &data, sizeof(int)))
			return -EFAULT;
		return 0;

/*************************************************************************
 EG_SET_EG_REG_OP sets the value of an EG register.
 'parameters' holds the register offset in the top 16 bits and the data in
 the bottom 16.
*************************************************************************/
	case EG_SET_EG_REG_OP:
		data = parameters & 0xffff;

		reg = ((unsigned int)(parameters >> 16)) & ~1u;
		if (reg > LAST_EG_REG)
			return -EINVAL;

		eg_writew(dev, reg, data);
		return 0;

	case EG_RD_EV_CNTRL_REG_OP:
		data = eg_readw(dev, EVENT_CTRL_REG);
		if (copy_to_user(uarg, &data, sizeof(int)))
			return -EFAULT;
		return 0;

	case EG_WR_EV_CNTRL_REG_OP:
		eg_writew(dev, EVENT_CTRL_REG, parameters & 0xffff);
		return 0;

	case EG_GET_TIMEOUT_OP:
		if (copy_from_user(&data, uarg, sizeof(int)))
			return -EFAULT;

		if (data & WAIT_ON_INTR_TO_FLAG)
			data = (dev->wait_intr_timeout[minor] * 1000) / HZ;
		else if (data & WAIT_GRAB_FRAME_TO_FLAG)
			data = (dev->wait_grab_frame_timeout[minor] * 1000) / HZ;
		else
			return -EINVAL;

		if (copy_to_user(uarg, &data, sizeof(int)))
			return -EFAULT;
		return 0;

	case EG_SET_TIMEOUT_OP:
		/*
		 * The time in 'parameters' is in ms.  Zero means no timeout;
		 * anything else is rounded up to at least one tick.
		 */
		data = parameters & WAIT_TO_OPTION_MASK;

		if ((parameters & ~(unsigned long)WAIT_TO_OPTION_MASK) == 0) {
			n = 0;
		} else {
			n = (HZ * (parameters & ~(unsigned long)WAIT_TO_OPTION_MASK)) / 1000;
			if (n == 0)
				++n;
		}

		eg_dbg(DEBUG_IOCTL, "setting timeout %lu ms = %d jiffies\n",
		       parameters & ~(unsigned long)WAIT_TO_OPTION_MASK, n);

		if (data == WAIT_ON_INTR_TO_FLAG)
			dev->wait_intr_timeout[minor] = n;
		else if (data == WAIT_GRAB_FRAME_TO_FLAG)
			dev->wait_grab_frame_timeout[minor] = n;
		else
			return -EINVAL;

		return 0;

/******************************************************************
 EG_GET_STATS_OP: the caller puts the size of its buffer in the first int
 of that buffer and gets back as much of EGStats_struct as fits.
******************************************************************/
	case EG_GET_STATS_OP:
		if (copy_from_user(&size, uarg, sizeof(size)))
			return -EFAULT;

		if (size <= 0)
			return -EINVAL;

		if (size > (int32_t)sizeof(EGStats_struct))
			size = sizeof(EGStats_struct);

		/* fill out the dynamic entries */
		dev->stats.List[STATS_DRIVER_UPTIME].Value =
			(jiffies - dev->pub.DriverStartTime) / HZ;

		if (copy_to_user(uarg, &dev->stats, size))
			return -EFAULT;
		return 0;

/******************************************************************
 EG_GET_IDENT_OP: the caller puts the size of its char buffer in the first
 byte of that buffer.
   char ident[120];
   ident[0] = 120;
   err = ioctl(handle, EVGEN_GET_IDENT, ident);
******************************************************************/
	case EG_GET_IDENT_OP:
		if (copy_from_user(&c, uarg, sizeof(c)))
			return -EFAULT;

		if (c == 0)
			return -EINVAL;

		if (c > MAX_EG_IDENT_LENGTH)
			c = MAX_EG_IDENT_LENGTH;

		if (copy_to_user(uarg, dev->pub.IdentString, c))
			return -EFAULT;
		return 0;

/******************************************************************
 EG_GET_FIFO_SIZE_OP: 'parameters' points to an int.
   int fifo_size;
   err = ioctl(handle, EVGEN_GET_FIFO_SIZE, &fifo_size);
******************************************************************/
	case EG_GET_FIFO_SIZE_OP:
		if (copy_to_user(uarg, &dev->pub.FifoSize, sizeof(int32_t)))
			return -EFAULT;
		return 0;

	case EG_GET_ERR_STATUS_OP:
		if (copy_from_user(&op, uarg, sizeof(int)))
			return -EFAULT;

		if ((op & (ERROR_STATUS_LATE_EVENT | ERROR_STATUS_CHECK_SUM |
			   ERROR_STATUS_FALSE_SYNC | ERROR_STATUS_MISSED_SYNC)) == 0)
			return -EINVAL;

		n = 0;
		if ((op & ERROR_STATUS_LATE_EVENT) &&
		    dev->pub.InterruptRate[IR_LATE_EVENT].Count > MAX_INTERRUPT_RATE)
			n |= ERROR_STATUS_LATE_EVENT;

		if ((op & ERROR_STATUS_CHECK_SUM) &&
		    dev->pub.InterruptRate[IR_CHECK_SUM].Count > MAX_INTERRUPT_RATE)
			n |= ERROR_STATUS_CHECK_SUM;

		if ((op & ERROR_STATUS_FALSE_SYNC) &&
		    dev->pub.InterruptRate[IR_FALSE_SYNC].Count > MAX_INTERRUPT_RATE)
			n |= ERROR_STATUS_FALSE_SYNC;

		if ((op & ERROR_STATUS_MISSED_SYNC) &&
		    dev->pub.InterruptRate[IR_MISSED_SYNC].Count > MAX_INTERRUPT_RATE)
			n |= ERROR_STATUS_MISSED_SYNC;

		if (copy_to_user(uarg, &n, sizeof(int)))
			return -EFAULT;
		return 0;

	case EG_CLEAR_ERR_STATUS_OP:
		if (copy_from_user(&op, uarg, sizeof(int)))
			return -EFAULT;

		if ((op & (ERROR_STATUS_LATE_EVENT | ERROR_STATUS_CHECK_SUM |
			   ERROR_STATUS_FALSE_SYNC | ERROR_STATUS_MISSED_SYNC)) == 0)
			return -EINVAL;

		n = 0;
		interrupt = 0;

		spin_lock_irqsave(&dev->lock, flags);

		if (op & ERROR_STATUS_LATE_EVENT) {
			n = dev->pub.InterruptRate[IR_LATE_EVENT].Count;
			dev->pub.InterruptRate[IR_LATE_EVENT].Count = 0;
			dev->pub.InterruptRate[IR_LATE_EVENT].Jiffies = jiffies;
			interrupt |= dev->pub.InterruptRate[IR_LATE_EVENT].InterruptBit;
		}
		if (op & ERROR_STATUS_CHECK_SUM) {
			n = dev->pub.InterruptRate[IR_CHECK_SUM].Count;
			dev->pub.InterruptRate[IR_CHECK_SUM].Count = 0;
			dev->pub.InterruptRate[IR_CHECK_SUM].Jiffies = jiffies;
			interrupt |= dev->pub.InterruptRate[IR_CHECK_SUM].InterruptBit;
		}
		if (op & ERROR_STATUS_FALSE_SYNC) {
			n = dev->pub.InterruptRate[IR_FALSE_SYNC].Count;
			dev->pub.InterruptRate[IR_FALSE_SYNC].Count = 0;
			dev->pub.InterruptRate[IR_FALSE_SYNC].Jiffies = jiffies;
			interrupt |= dev->pub.InterruptRate[IR_FALSE_SYNC].InterruptBit;
		}
		if (op & ERROR_STATUS_MISSED_SYNC) {
			n = dev->pub.InterruptRate[IR_MISSED_SYNC].Count;
			dev->pub.InterruptRate[IR_MISSED_SYNC].Count = 0;
			dev->pub.InterruptRate[IR_MISSED_SYNC].Jiffies = jiffies;
			interrupt |= dev->pub.InterruptRate[IR_MISSED_SYNC].InterruptBit;
		}

		data = eg_readw(dev, IC_REG);
		eg_writew(dev, IC_REG, data | interrupt | IC_Enable);

		spin_unlock_irqrestore(&dev->lock, flags);

		if (copy_to_user(uarg, &n, sizeof(int)))
			return -EFAULT;
		return 0;

	case EG_SET_WFPS_03_OP:
		spin_lock_irqsave(&dev->lock, flags);
		dev->pub.lsbPrescaleReg |= parameters & 0x00ff;
		eg_writew(dev, WFG_PRESCALE_0, dev->pub.lsbPrescaleReg);

		dev->pub.msbPrescaleReg |= (parameters >> 8) & 0x00ff;
		eg_writew(dev, WFG_PRESCALE_1, dev->pub.msbPrescaleReg);
		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

	case EG_SET_WFPS_47_OP:
		spin_lock_irqsave(&dev->lock, flags);
		dev->pub.lsbPrescaleReg |= (parameters << 8) & 0xff00;
		eg_writew(dev, WFG_PRESCALE_0, dev->pub.lsbPrescaleReg);

		dev->pub.msbPrescaleReg |= parameters & 0xff00;
		eg_writew(dev, WFG_PRESCALE_1, dev->pub.msbPrescaleReg);
		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

	case EG_WF_SEL_OP:
		spin_lock_irqsave(&dev->lock, flags);

		reg1 = eg_readw(dev, WFG_SELECT_1);
		reg2 = eg_readw(dev, WFG_SELECT_2);
		bitPos = 0x01000000;

		for (wfnum = 0; wfnum < 8; ++wfnum) {
			if (!(parameters & (bitPos << wfnum)))
				continue;

			switch (wfnum) {
			case 0:
				reg1 |= parameters & 0x000f;
				break;
			case 1:
				reg1 |= (parameters << 4) & 0x00f0;
				break;
			case 2:
				reg2 |= parameters & 0x000f;
				break;
			case 3:
				reg2 |= (parameters << 4) & 0x00f0;
				break;
			case 4:
				reg1 |= (parameters << 8) & 0x0f00;
				break;
			case 5:
				reg1 |= (parameters << 12) & 0xf000;
				break;
			case 6:
				reg2 |= (parameters << 8) & 0x0f00;
				break;
			case 7:
				reg2 |= (parameters << 12) & 0xf000;
				break;
			}
		}

		eg_writew(dev, WFG_SELECT_1, reg1);
		eg_writew(dev, WFG_SELECT_2, reg2);

		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

	case EG_WF_CON_OP:
		spin_lock_irqsave(&dev->lock, flags);
		data = eg_readw(dev, EVENT_CTRL_REG);
		data |= parameters & 0x000f;
		eg_writew(dev, EVENT_CTRL_REG, data);
		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

	case EG_WF_EN_OP:
		spin_lock_irqsave(&dev->lock, flags);
		data = eg_readw(dev, EVENT_CTRL_REG);
		data |= (parameters << 4) & 0x0010;
		eg_writew(dev, EVENT_CTRL_REG, data);
		spin_unlock_irqrestore(&dev->lock, flags);
		return 0;

/******************************************************************
 EG_DEBUGGING_OP: sub-function in the top 16 bits, argument in the low 16.
   err = ioctl(handle, EVGEN_DEBUGGING, (DEBUG_SET_DEBUG_LEVEL << 16) | 1);
******************************************************************/
	case EG_DEBUGGING_OP:
		data = parameters >> 16;

		switch (data) {
		case DEBUG_SET_DEBUG_LEVEL:
			n = parameters & 0xffff;
			if (n < DEBUG_OFF || n >= DEBUG_LEVEL_END)
				return -EINVAL;
			eg_debug = n;
			pr_info(EG_DRV_NAME ": debug level set to %d\n",
				eg_debug);
			return 0;

		case DEBUG_CALL_ISR:
			EGInterrupt(dev->irq, dev);
			return 0;

		default:
			return -EINVAL;
		}

/******************************************************************
 EG_GET_DEVICE_INFO_OP: the caller puts the size of its buffer in the first
 int32_t of that buffer and gets back as much of PublicSysInfo_struct as fits.

   PublicSysInfo_struct info;
   *((int32_t *) &info) = sizeof(info);
   err = ioctl(handle, EVGEN_GET_DEVICE_INFO, &info);

 ABI NOTE: 2.6 read the length from the first *byte* as a signed char, then
 compared it against sizeof(PublicSysInfo_struct).  The structure is larger
 than 127 bytes, so no caller could ever ask for all of it, and a caller that
 wrote the real size into that byte passed a negative length straight through
 to copy_to_user().  The length is now an int32_t, matching EG_GET_STATS_OP.
 Nothing in this tree called it.
******************************************************************/
	case EG_GET_DEVICE_INFO_OP:
		if (copy_from_user(&size, uarg, sizeof(size)))
			return -EFAULT;

		if (size <= 0)
			return -EINVAL;

		if (size > (int32_t)sizeof(PublicSysInfo_struct))
			size = sizeof(PublicSysInfo_struct);

		dev->pub.WriteOwner = dev->write_owner;

		if (copy_to_user(uarg, &dev->pub, size))
			return -EFAULT;
		return 0;

	case EG_GET_INTR_SRC_OP:
		spin_lock_irqsave(&dev->lock, flags);
		TransferInterruptSourceInfo(u, &IM);
		spin_unlock_irqrestore(&dev->lock, flags);

		eg_dbg(DEBUG_IOCTL, "GIS: src %08x %08x %08x\n",
		       IM.Primary, IM.Rising, IM.Falling);

		if (copy_to_user(uarg, &IM, sizeof(IM)))
			return -EFAULT;
		return 0;

	case EG_SET_OPTION_OP:
		eg_dbg(DEBUG_IOCTL, "setting option %08lx\n", parameters);
		if (parameters & EG_OPTION_NON_BLOCKING) {
			spin_lock(&filp->f_lock);
			filp->f_flags |= O_NONBLOCK;
			spin_unlock(&filp->f_lock);
		}
		return 0;

	case EG_CLEAR_OPTION_OP:
		eg_dbg(DEBUG_IOCTL, "clearing option %08lx\n", parameters);
		if (parameters & EG_OPTION_NON_BLOCKING) {
			spin_lock(&filp->f_lock);
			filp->f_flags &= ~O_NONBLOCK;
			spin_unlock(&filp->f_lock);
		}
		return 0;

	/*
	 * EG_GET_XINT_INTR_LINE_OP / EG_SET_XINT_INTR_LINE_OP were already
	 * #ifdef'd out under NOLONGERINUSE in 2.6 and marked "No longer
	 * implemented" in eg_ioctl.h.  They fall through to -EINVAL, which is
	 * what the 2.6 driver returned for them too; the dead code is deleted.
	 */
	default:
		return -EINVAL;
	}
}

/*
 * poll() - report an interrupt the caller armed with EVGEN_WAIT_ON_INTR in
 * non-blocking mode.  select() callers put the descriptor in the exception
 * set, which is EPOLLPRI.
 *
 * The 2.6 version returned POLLPRI when it could not find an entry for the
 * caller in the PID table - that is, it reported an event whenever the caller
 * had not armed one, so select() spun.  With per-open state there is always an
 * entry and the "nothing armed, nothing fired" case now blocks properly.
 */
static __poll_t EGPoll(struct file *filp, poll_table *wait)
{
	struct eg_user *u = filp->private_data;
	struct eg_dev *dev = u->dev;
	unsigned long flags;
	__poll_t mask = 0;

	poll_wait(filp, &u->wq, wait);

	spin_lock_irqsave(&dev->lock, flags);
	if ((u->src.Primary & (IC_PhysicalIntrMask | IC_LogicalMask)) != 0 ||
	    u->src.Rising != 0 || u->src.Falling != 0)
		mask = EPOLLPRI;
	spin_unlock_irqrestore(&dev->lock, flags);

	eg_dbg(DEBUG_IF, "poll: minor %d -> %x\n", u->minor, mask);

	return mask;
}

static const struct file_operations eg_fops = {
	.owner		= THIS_MODULE,
	.read		= EGRead,
	.write		= EGWrite,
	.unlocked_ioctl	= EGIoctl,
	.compat_ioctl	= compat_ptr_ioctl,
	.open		= EGOpen,
	.release	= EGClose,
	.poll		= EGPoll,
	.llseek		= no_llseek,
};

/*************************************************************************
              Entry into the /proc file system

 2.6 used create_proc_entry() with ->read_proc and ->write_proc, both removed
 in 3.10, and hand-rolled the page accounting with a running "if (noe + ci <
 PAGE_SIZE - 1)" test around every sprintf - including one place where the
 length of the *previous* message was used to bound the next one.  seq_file
 does all of that.

 It was also created mode 0666, world writable, which let any user on the box
 set the driver's debug level.  It is 0644 now; use the module parameter under
 /sys/module/eg/parameters/debug, which is root-only too.
*************************************************************************/

static void eg_proc_decode_icr(struct seq_file *s, unsigned int icr)
{
	static const struct {
		unsigned int bit;
		const char *name;
	} bits[] = {
		{ IC_FIFOHalfEmpty, "FIFOHalfEmpty" },
		{ IC_LateEvent,     "LateEvent" },
		{ IC_CheckSumError, "CheckSumError" },
		{ IC_FalseSync,     "FalseSync" },
		{ IC_MissedSync,    "MissedSync" },
		{ IC_FrameLoaded,   "FrameLoaded" },
		{ IC_ExtInt,        "ExtInt" },
		{ IC_Event,         "Event" },
		{ IC_PLLUnlocked,   "PLLUnlocked" },
		{ IC_1Second,       "1Second" },
		{ IC_Finished,      "Finished" },
		{ IC_Extended,      "Extended" },
		{ IC_Enable,        "Enable" },
	};
	int i, m = 0;

	for (i = 0; i < ARRAY_SIZE(bits); ++i) {
		if (!(icr & bits[i].bit))
			continue;
		seq_printf(s, "%s%s", m++ ? ", " : " ", bits[i].name);
	}
	if (m)
		seq_puts(s, "\n");
}

static const char *eg_write_state_name(int state)
{
	switch (state) {
	case WRITE_STATE_IDLE:			return "IDLE";
	case WRITE_STATE_WRITING:		return "WRITING";
	case WRITE_STATE_FIFO_FULL:		return "FIFO_FULL";
	case WRITE_STATE_USC_FAIL:		return "USC_FAIL";
	case WRITE_STATE_CLAIM_ENTRY_FAIL:	return "CLAIM_ENTRY_FAIL";
	case WRITE_STATE_WAIT_ON_HE_INTERRUPT:	return "WAIT_ON_HE_INTR";
	case WRITE_STATE_WAIT_ON_HE_DONE:	return "WAIT_ON_HE_DONE";
	case WRITE_STATE_SIGNAL_RECVD:		return "SIGNAL_RECVD";
	case WRITE_STATE_HE_INTR_ARRIVED:	return "HE_INTR_ARRIVED";
	default:				return "UNKNOWN";
	}
}

static int eg_proc_show(struct seq_file *s, void *v)
{
	struct eg_dev *dev = s->private;
	unsigned long flags;
	unsigned int icr;
	u32 icxre, icxfe;
	int n;

	seq_printf(s, "Driver version: %s\n", EG_VERSION);
	seq_printf(s, "PCI device: %s (%04x:%04x) behind %s\n",
		   pci_name(dev->pdev), dev->vendor, dev->device,
		   dev->bar_name);

	if (strlen(dev->pub.IdentString) > 2)
		seq_printf(s, "ID: %s\n", dev->pub.IdentString);
	else
		seq_puts(s, "ID: NOT AVAILABLE\n");

	seq_printf(s, "FIFO size: %d events\n", dev->pub.FifoSize);
	seq_printf(s, "Assigned IRQ: %d%s\n", dev->irq,
		   dev->irq_ok ? "" : " (NOT REGISTERED)");
	seq_printf(s, "PCI bus addr: %pa  Region: BAR%d, %llu bytes\n",
		   &dev->hw_addr, dev->bar_no,
		   (unsigned long long)dev->region_size);

	spin_lock_irqsave(&dev->lock, flags);
	icr = eg_readw(dev, IC_REG);
	icxre = eg_readw(dev, XIC_RE_REG_0) |
		((u32)eg_readw(dev, XIC_RE_REG_1) << XI_REG_WIDTH);
	icxfe = eg_readw(dev, XIC_FE_REG_0) |
		((u32)eg_readw(dev, XIC_FE_REG_1) << XI_REG_WIDTH);
	spin_unlock_irqrestore(&dev->lock, flags);

	seq_printf(s, "Main ICR: %04x\n", icr);
	/*
	 * 2.6 decoded the *falling edge* extended register here using the
	 * primary control register's bit names, which is meaningless.  The
	 * primary register is what the names belong to.
	 */
	eg_proc_decode_icr(s, icr);

	seq_printf(s, "Rising Edge ICR: %08x\n", icxre);
	seq_printf(s, "Falling Edge ICR: %08x\n", icxfe);

	seq_printf(s, "Max interrupt rate: %d\n", MAX_INTERRUPT_RATE);
	seq_printf(s, "Write owner (minor): %d\n", dev->write_owner);
	seq_printf(s, "WRITE_STATE: %s\n",
		   eg_write_state_name(dev->write_state));

	dev->stats.List[STATS_DRIVER_UPTIME].Value =
		(jiffies - dev->pub.DriverStartTime) / HZ;

	for (n = 0; n < STATS_MAX_NUM_STATS_ENTRIES; ++n) {
		if (dev->stats.List[n].Label[0] == 0)
			continue;
		seq_printf(s, "%s: %llu\n", dev->stats.List[n].Label,
			   dev->stats.List[n].Value);
	}

	return 0;
}

static int eg_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, eg_proc_show, pde_data(inode));
}

static ssize_t eg_proc_write(struct file *file, const char __user *arg,
			     size_t count, loff_t *ppos)
{
	char buf[MAX_PROC_LINE_LENGTH + 4];
	char *cmd;
	size_t len;
	int n;

	len = min(count, (size_t)MAX_PROC_LINE_LENGTH);

	if (copy_from_user(buf, arg, len))
		return -EFAULT;
	buf[len] = '\0';

	/*
	 * 2.6 terminated the command by scanning forward for the first byte
	 * <= ' ' and writing a NUL over it, which turns an empty write into a
	 * walk off the end of the buffer.
	 */
	cmd = strim(buf);

	eg_dbg(DEBUG_IF, "/proc write: <%s>\n", cmd);

	if (sscanf(cmd, "debug=%d", &n) == 1) {
		if (n >= DEBUG_OFF && n < DEBUG_LEVEL_END) {
			eg_debug = n;
			pr_info(EG_DRV_NAME ": debug level set to %d\n", n);
		} else {
			return -EINVAL;
		}
	} else if (strncmp(cmd, "reset_counts", 12) == 0) {
		struct eg_dev *dev = pde_data(file_inode(file));
		unsigned long flags;
		int i;

		/*
		 * 2.6 recognised this command and then did nothing at all -
		 * the body was an empty pair of braces.  It now works.
		 */
		spin_lock_irqsave(&dev->lock, flags);
		for (i = 0; i < STATS_MAX_NUM_STATS_ENTRIES; ++i) {
			if (i == STATS_USE_COUNT || i == STATS_DRIVER_UPTIME)
				continue;
			dev->stats.List[i].Value = 0;
		}
		spin_unlock_irqrestore(&dev->lock, flags);
		pr_info(EG_DRV_NAME ": statistics counters reset\n");
	} else {
		return -EINVAL;
	}

	return count;
}

static const struct proc_ops eg_proc_ops = {
	.proc_open	= eg_proc_open,
	.proc_read	= seq_read,
	.proc_lseek	= seq_lseek,
	.proc_release	= single_release,
	.proc_write	= eg_proc_write,
};

/*
 * ---------------------------------------------------------------------------
 * Device state initialisation
 * ---------------------------------------------------------------------------
 *
 * Was InitSysInfo() and then, copied out almost line for line,
 * InitSysInfoStructure() - two near-identical 120-line functions selected by
 * LINUX_VERSION_CODE, each with the same chain of 16 "else if (n == ...)"
 * comparisons to fill in a table of constant strings.  It is a table now.
 */
static const char * const eg_stats_labels[STATS_MAX_NUM_STATS_ENTRIES] = {
	[STATS_INTERRUPT_COUNT]		= "Total Interrupts",
	[STATS_HALF_EMPTY_INTR_COUNT]	= "Half Empty Interrupts",
	[STATS_LATE_EVENT_INTR_COUNT]	= "Late Event Interrupts",
	[STATS_CHECK_SUM_INTR_COUNT]	= "Check Sum Interrupts",
	[STATS_FALSE_SYNC_INTR_COUNT]	= "False Sync Interrupts",
	[STATS_MISSED_SYNC_INTR_COUNT]	= "Missed Sync Interrupts",
	[STATS_FRAME_LOADED_INTR_COUNT]	= "Frame Loaded Interrupts",
	[STATS_EXTERNAL_INTR_COUNT]	= "External Interrupts",
	[STATS_INTERNAL_INTR_COUNT]	= "Internal Interrupts",
	[STATS_PLL_UNLOCKED_INTR_COUNT]	= "PLL Unlocked Interrupts",
	[STATS_ONE_SECOND_INTR_COUNT]	= "One Second Interrupts",
	[STATS_FINISHED_INTR_COUNT]	= "Finished Interrupts",
	[STATS_EXTENDED_INTR_COUNT]	= "Extended Interrupts",
	[STATS_EVENTS_WRITTEN_COUNT]	= "Events Written ('000)",
	[STATS_DRIVER_UPTIME]		= "Driver Uptime (s)",
	[STATS_USE_COUNT]		= "Current Use",
	[STATS_END_MARKER]		= "",
};

static const int eg_rate_bits[MAX_NUM_IR_POINTS] = {
	[IR_LATE_EVENT]		= IC_LateEvent,
	[IR_CHECK_SUM]		= IC_CheckSumError,
	[IR_FALSE_SYNC]		= IC_FalseSync,
	[IR_MISSED_SYNC]	= IC_MissedSync,
	[IR_INTERNAL]		= IC_Event,
};

static void eg_init_state(struct eg_dev *dev)
{
	int n;

	spin_lock_init(&dev->lock);

	dev->pub.DriverStartTime = jiffies;
	dev->pub.Status = EG_LD_STATUS_OK;
	dev->pub.WriteOwner = -1;
	dev->pub.ABIVersion = EG_ABI_VERSION;

	dev->write_owner = -1;
	dev->grab_frame_initiator = -1;
	dev->write_state = WRITE_STATE_IDLE;

	for (n = 0; n < STATS_MAX_NUM_STATS_ENTRIES; ++n) {
		if (eg_stats_labels[n])
			strscpy(dev->stats.List[n].Label, eg_stats_labels[n],
				sizeof(dev->stats.List[n].Label));
	}

	for (n = 0; n < MAX_NUM_EG_USERS; ++n) {
		init_waitqueue_head(&dev->users[n].wq);
		dev->users[n].in_use = false;
		dev->users[n].minor = -1;
		dev->users[n].dev = dev;
	}

	for (n = 0; n < MAX_NUM_EG_DEVICES; ++n) {
		/* 0 means no timeout; the user can set one later */
		dev->wait_intr_timeout[n] = 0;
		dev->wait_grab_frame_timeout[n] =
			(HZ * EG_DEFAULT_GRAB_FRAME_TO_MS) / 1000;

		/* keep the default at a couple of jiffies if HZ is coarse */
		if (EG_DEFAULT_GRAB_FRAME_TO_MS > 0 &&
		    dev->wait_grab_frame_timeout[n] == 0)
			dev->wait_grab_frame_timeout[n] = 2;
	}

	for (n = 0; n < MAX_NUM_IR_POINTS; ++n) {
		dev->pub.InterruptRate[n].Jiffies = jiffies;
		dev->pub.InterruptRate[n].Count = 0;
		dev->pub.InterruptRate[n].InterruptBit = eg_rate_bits[n];
	}
}

/*
 * ---------------------------------------------------------------------------
 * PCI binding
 * ---------------------------------------------------------------------------
 */
static const struct pci_device_id eg_id_table[] = {
	{ PCI_DEVICE(PLX_VENDOR_ID, PLX_DEVICE_ID) },
	{ PCI_DEVICE(WISHBONE_VENDOR_ID, WISHBONE_DEVICE_ID) },
	/*
	 * The 2.6 table also carried { PCI_DEVICE(0, 0) } before its
	 * terminator.  Vendor 0 is not a valid PCI vendor ID, so it matched
	 * nothing; dropped.
	 */
	{ 0, }
};
MODULE_DEVICE_TABLE(pci, eg_id_table);

static int eg_register_chrdev(struct eg_dev *dev)
{
	int ret, n;

	if (major) {
		dev->devt = MKDEV(major, FIRST_DEVICE_MINOR_NUMBER);
		ret = register_chrdev_region(dev->devt, MAX_NUM_EG_DEVICES,
					     EG_DRV_NAME);
	} else {
		ret = alloc_chrdev_region(&dev->devt, FIRST_DEVICE_MINOR_NUMBER,
					  MAX_NUM_EG_DEVICES, EG_DRV_NAME);
	}
	if (ret) {
		pr_err(EG_DRV_NAME ": unable to register char device region (%d)\n",
		       ret);
		return ret;
	}

	pr_info(EG_DRV_NAME ": major %d assigned\n", MAJOR(dev->devt));

	/*
	 * One cdev spanning all MAX_NUM_EG_DEVICES minors.  2.6 embedded an
	 * array of eight struct cdevs in the device structure and cdev_add()'d
	 * each one separately, which is what forced open() to find its state
	 * through a file-scope global instead of container_of(inode->i_cdev).
	 */
	cdev_init(&dev->cdev, &eg_fops);
	dev->cdev.owner = THIS_MODULE;

	ret = cdev_add(&dev->cdev, dev->devt, MAX_NUM_EG_DEVICES);
	if (ret) {
		pr_err(EG_DRV_NAME ": cdev_add failed (%d)\n", ret);
		unregister_chrdev_region(dev->devt, MAX_NUM_EG_DEVICES);
		return ret;
	}

	/*
	 * Create the device nodes.  2.6 relied on the operator running mknod
	 * by hand; there is no static /dev any more.
	 */
	for (n = 0; n < MAX_NUM_EG_DEVICES; ++n) {
		struct device *d;

		d = device_create(eg_class, &dev->pdev->dev,
				  MKDEV(MAJOR(dev->devt),
					FIRST_DEVICE_MINOR_NUMBER + n),
				  NULL, EG_DRV_NAME "%d", n);
		if (IS_ERR(d)) {
			ret = PTR_ERR(d);
			pr_err(EG_DRV_NAME ": device_create for minor %d failed (%d)\n",
			       n, ret);
			while (--n >= 0)
				device_destroy(eg_class,
					       MKDEV(MAJOR(dev->devt),
						     FIRST_DEVICE_MINOR_NUMBER + n));
			cdev_del(&dev->cdev);
			unregister_chrdev_region(dev->devt, MAX_NUM_EG_DEVICES);
			return ret;
		}
	}

	return 0;
}

static void eg_unregister_chrdev(struct eg_dev *dev)
{
	int n;

	for (n = 0; n < MAX_NUM_EG_DEVICES; ++n)
		device_destroy(eg_class, MKDEV(MAJOR(dev->devt),
					       FIRST_DEVICE_MINOR_NUMBER + n));

	cdev_del(&dev->cdev);
	unregister_chrdev_region(dev->devt, MAX_NUM_EG_DEVICES);
}

static int eg_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	struct eg_dev *dev;
	int ret;

	if (slot && *slot && strcmp(slot, pci_name(pdev)) != 0) {
		dev_info(&pdev->dev,
			 EG_DRV_NAME ": skipping, slot=%s was requested\n", slot);
		return -ENODEV;
	}

	mutex_lock(&eg_bind_lock);
	if (eg_the_card) {
		mutex_unlock(&eg_bind_lock);
		dev_notice(&pdev->dev,
			   EG_DRV_NAME ": a card is already bound; this driver supports one event generator per host\n");
		return -EBUSY;
	}
	mutex_unlock(&eg_bind_lock);

	dev = kzalloc(sizeof(*dev), GFP_KERNEL);
	if (!dev)
		return -ENOMEM;

	dev->pdev = pdev;
	dev->vendor = pdev->vendor;
	dev->device = pdev->device;

	eg_init_state(dev);

	if (pdev->vendor == WISHBONE_VENDOR_ID &&
	    pdev->device == WISHBONE_DEVICE_ID) {
		dev->bar_no = WISHBONE_BAR;
		dev->bar_name = WISHBONE_STRING;
	} else {
		dev->bar_no = PLX_BAR;
		dev->bar_name = PLX_STRING;
	}

	pr_info(EG_DRV_NAME ": probing %s (%04x:%04x) behind %s\n",
		pci_name(pdev), dev->vendor, dev->device, dev->bar_name);

	ret = pci_enable_device(pdev);
	if (ret) {
		dev_err(&pdev->dev, EG_DRV_NAME ": pci_enable_device failed (%d)\n",
			ret);
		goto err_free;
	}

	ret = pci_request_regions(pdev, EG_DRV_NAME);
	if (ret) {
		dev_err(&pdev->dev, EG_DRV_NAME ": pci_request_regions failed (%d)\n",
			ret);
		goto err_disable;
	}

	dev->hw_addr = pci_resource_start(pdev, dev->bar_no);
	dev->region_size = pci_resource_len(pdev, dev->bar_no);

	if (dev->region_size < EG_MIN_REGION_SIZE) {
		dev_err(&pdev->dev,
			EG_DRV_NAME ": BAR%d is %llu bytes, need at least %d\n",
			dev->bar_no, (unsigned long long)dev->region_size,
			EG_MIN_REGION_SIZE);
		ret = -ENODEV;
		goto err_release;
	}

	dev->bar = pci_iomap(pdev, dev->bar_no, 0);
	if (!dev->bar) {
		dev_err(&pdev->dev, EG_DRV_NAME ": cannot map BAR%d\n",
			dev->bar_no);
		ret = -ENOMEM;
		goto err_release;
	}

	pr_info(EG_DRV_NAME ": BAR%d at %pa, %llu bytes, mapped\n",
		dev->bar_no, &dev->hw_addr,
		(unsigned long long)dev->region_size);

	/* Mod for Wishbone interface (A. Brown) */
	if (pdev->vendor == WISHBONE_VENDOR_ID) {
		dev->wishbone = pci_iomap(pdev, WISHBONE_CONFIG_BAR,
					  WISHBONE_CONFIG_SIZE);
		if (!dev->wishbone) {
			dev_err(&pdev->dev,
				EG_DRV_NAME ": cannot map wishbone config BAR%d\n",
				WISHBONE_CONFIG_BAR);
			ret = -ENOMEM;
			goto err_unmap;
		}
	}

	ret = eg_identify(dev);
	if (ret)
		goto err_unmap_wb;

	eg_init_hardware(dev);

	ret = eg_register_chrdev(dev);
	if (ret)
		goto err_unmap_wb;

	dev->irq = pdev->irq;
	ret = request_irq(dev->irq, EGInterrupt, IRQF_SHARED, EG_DRV_NAME, dev);
	if (ret) {
		/*
		 * 2.6 set Private.IRQ = -1 and carried on, then used that -1
		 * as a register offset in one of the debug paths.  Carrying on
		 * without interrupts is still the right call - every register
		 * ioctl works - but it is now recorded properly and reported.
		 */
		pr_warn(EG_DRV_NAME ": can't get IRQ %d (%d); continuing without interrupts\n",
			dev->irq, ret);
		dev->irq_ok = false;
	} else {
		dev->irq_ok = true;
		pr_info(EG_DRV_NAME ": IRQ line = %d\n", dev->irq);
	}

	/* Mod for Wishbone interface (A. Brown) */
	if (dev->wishbone) {
		u32 dword = eg_wb_readl(dev, WISHBONE_ICR);

		/* enable interrupt propagation on the PCI core, just in case */
		eg_wb_writel(dev, WISHBONE_ICR, dword | INT_PROP_EN);
	}

	dev->proc = proc_create_data(EG_DRV_NAME, 0644, NULL, &eg_proc_ops, dev);
	if (!dev->proc)
		pr_warn(EG_DRV_NAME ": unable to create /proc/" EG_DRV_NAME "\n");

	pci_set_drvdata(pdev, dev);

	mutex_lock(&eg_bind_lock);
	eg_the_card = dev;
	mutex_unlock(&eg_bind_lock);

	pr_info(EG_DRV_NAME ": initialisation complete\n");
	return 0;

err_unmap_wb:
	if (dev->wishbone)
		pci_iounmap(pdev, dev->wishbone);
err_unmap:
	pci_iounmap(pdev, dev->bar);
err_release:
	pci_release_regions(pdev);
err_disable:
	pci_disable_device(pdev);
err_free:
	kfree(dev);
	return ret;
}

/*
 * remove() was "static void eg_remove(struct pci_dev *dev) { return; }" in
 * 2.6.  The teardown that belongs here was in end_module(), where it ran
 * after pci_unregister_driver() had already been called - or, if the module
 * was never loaded far enough, not at all.
 */
static void eg_remove(struct pci_dev *pdev)
{
	struct eg_dev *dev = pci_get_drvdata(pdev);
	unsigned long uptime;
	unsigned long flags;

	if (!dev)
		return;

	if (dev->proc)
		remove_proc_entry(EG_DRV_NAME, NULL);

	/* turn off all interrupts before the handler goes away */
	spin_lock_irqsave(&dev->lock, flags);
	eg_writew(dev, IC_REG, 0);
	eg_writew(dev, XIC_RE_REG_0, 0);
	eg_writew(dev, XIC_RE_REG_1, 0);
	eg_writew(dev, XIC_FE_REG_0, 0);
	eg_writew(dev, XIC_FE_REG_1, 0);
	spin_unlock_irqrestore(&dev->lock, flags);

	if (dev->irq_ok) {
		pr_info(EG_DRV_NAME ": freeing interrupt %d\n", dev->irq);
		free_irq(dev->irq, dev);
	}

	eg_unregister_chrdev(dev);

	uptime = (jiffies - dev->pub.DriverStartTime) / HZ;
	pr_info(EG_DRV_NAME ": driver uptime %lu:%02lu:%02lu:%02lu\n",
		uptime / (24 * 3600),
		(uptime % (24 * 3600)) / 3600,
		((uptime % (24 * 3600)) % 3600) / 60,
		((uptime % (24 * 3600)) % 3600) % 60);

	pr_info(EG_DRV_NAME ": total interrupts: %llu, events ('000): %llu\n",
		dev->stats.List[STATS_INTERRUPT_COUNT].Value,
		dev->stats.List[STATS_EVENTS_WRITTEN_COUNT].Value);

	if (dev->wishbone)
		pci_iounmap(pdev, dev->wishbone);
	pci_iounmap(pdev, dev->bar);
	pci_release_regions(pdev);
	pci_disable_device(pdev);

	mutex_lock(&eg_bind_lock);
	if (eg_the_card == dev)
		eg_the_card = NULL;
	mutex_unlock(&eg_bind_lock);

	pci_set_drvdata(pdev, NULL);
	kfree(dev);
}

static struct pci_driver eg_driver = {
	.name		= EG_DRV_NAME,
	.id_table	= eg_id_table,
	.probe		= eg_probe,
	.remove		= eg_remove,
};

static int __init eg_init(void)
{
	int ret;

	pr_info(EG_DRV_NAME ": event generator driver version %s\n", EG_VERSION);
	pr_info(EG_DRV_NAME ": debug level set to: %d\n", eg_debug);

	eg_class = class_create(EG_DRV_NAME);
	if (IS_ERR(eg_class)) {
		ret = PTR_ERR(eg_class);
		pr_err(EG_DRV_NAME ": class_create failed (%d)\n", ret);
		return ret;
	}

	ret = pci_register_driver(&eg_driver);
	if (ret) {
		pr_err(EG_DRV_NAME ": failed to register driver (%d)\n", ret);
		class_destroy(eg_class);
		return ret;
	}

	return 0;
}

static void __exit eg_exit(void)
{
	pci_unregister_driver(&eg_driver);
	class_destroy(eg_class);
}

module_init(eg_init);
module_exit(eg_exit);

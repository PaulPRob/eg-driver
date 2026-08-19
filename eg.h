/* SPDX-License-Identifier: GPL-2.0 */
/*******************************************************************
 * eg.h -- hardware definitions and driver-private state for the CSIRO ATNF
 *         PC Event Generator (EG) PCI card.
 *
 * PORT NOTE (2.6 -> 6.8)
 * ----------------------
 * This header used to be included by nothing but eg.c yet still pulled in
 * "sysdep.h", a 1996-era compatibility shim for kernels 1.2 through 2.0.
 * That file is deleted; there are no LINUX_VERSION_CODE conditionals left
 * anywhere in this tree.
 *
 * Removed from this header:
 *
 *   VERSION_CODE()            - the version-conditional machinery it fed.
 *   TYPE()/NUM()             - minor-number splitting the driver never used.
 *   EVGEN_USE_PROC           - guarded by EVGEN_DEBUG, which was never set.
 *   U32/U16/U8/I32/I16/I8    - private typedefs shadowing <linux/types.h>.
 *   AMCC_VENDOR_ID and friends - a PCI front end this card never shipped on.
 *   EG_DEFAULT_IO_BASE, EG_DEFAULT_IRQ, EG_IO_EXTENT, EG_TYPE_ISA
 *                            - the ISA card.  See the ISA note below.
 *   The commented-out block of 1990s function prototypes at the end.
 *
 * The ISA card: the 2.6 driver registered a pci_driver and, if probe() never
 * fired, fell back to inw()/outw() on a module-parameter I/O base.  Nothing
 * has had an ISA slot for twenty years, the fallback could not be reached at
 * all once the driver was structured around probe(), and it is the reason the
 * driver carried two of every register accessor behind function pointers.
 * All of it is gone: this is a PCI driver, the accessors are direct MMIO, and
 * the "iobase" and "irq" module parameters no longer exist.
 *******************************************************************/

#ifndef EG_H
#define EG_H

#include <linux/cdev.h>
#include <linux/delay.h>
#include <linux/device.h>
#include <linux/fs.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/pci.h>
#include <linux/poll.h>
#include <linux/proc_fs.h>
#include <linux/sched.h>
#include <linux/sched/signal.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/types.h>
#include <linux/uaccess.h>
#include <linux/wait.h>

#include "eg_ioctl.h"
#include "eg_struct.h"

/************************************************************************/
/* Driver identity                                                      */
/************************************************************************/

#define EG_DRV_NAME                    "eg"
#define EG_VERSION                     "2.0"
#define MODULE_NAME                    EG_DRV_NAME

#ifndef EVGEN_MAJOR
#define EVGEN_MAJOR 0   /* dynamic major by default */
#endif

#define EVENT_BUFFER_SIZE              2048
#define EG_DEFAULT_GRAB_FRAME_TO_MS    5
#define EG_NUM_ELEMENTS_IN_EVENT_DEF   4

#define MAX_PROC_LINE_LENGTH 128

/************************************************************************
 * Debug levels.  Selected with the "debug" module parameter, with
 * EVGEN_DEBUGGING, or by writing "debug=N" to /proc/eg.
 *
 * DEBUG_OFF        -- No debug info
 * DEBUG_CRIT       -- Display critical information
 * DEBUG_INFO       -- Display all information
 * DEBUG_IOCTL      -- Display every ioctl
 * DEBUG_IF         -- Display all interface transactions except reads/writes
 * DEBUG_IFRW       -- Display all interface reads/writes.  Will dramatically
 *                     reduce the throughput of the driver.
 * DEBUG_INTERRUPT  -- Display interrupt handling
 * DEBUG_PCI        -- Display every PCI register access.  Will flood the log.
 * DEBUG_ALL        -- Everything
 ************************************************************************/
enum {
  DEBUG_OFF = 0,
  DEBUG_CRIT,
  DEBUG_INFO,
  DEBUG_IOCTL,
  DEBUG_IF,
  DEBUG_IFRW,
  DEBUG_INTERRUPT,
  DEBUG_PCI,
  DEBUG_ALL,
  DEBUG_LEVEL_END  /* Always put this at the end */
};

extern int eg_debug;

#define eg_dbg(level, fmt, ...)						\
	do {								\
		if (eg_debug >= (level))				\
			pr_info(EG_DRV_NAME ": " fmt, ##__VA_ARGS__);	\
	} while (0)

/************************************************************************/
/* Event Generator Linux Driver status bit assignment                   */
/************************************************************************/
#define EG_LD_STATUS_OK            0x0
#define EG_LD_STATUS_NOT_THERE     0x1

/**********************************************************
 * PCI interface definitions
 *
 * PLX_VENDOR_ID:PLX_DEVICE_ID (10b5:9030) is the generic PLX 9030 bridge ID.
 * The ATNF AT Distributed Clock, driven by the separate "atdcif" module, is
 * built on the same carrier and is normally in the same chassis, so it has the
 * identical vendor:device.  The kernel offers both cards to whichever of the
 * two drivers is loaded first, and the 2.6 driver took whichever PLX 9030
 * pci_find_device() returned - which on a two-card host is a coin toss.
 *
 * The serial-number PROM does NOT tell them apart: it holds the carrier's
 * identity, and both boards read back the same "PC EVENT GENERATOR Vx.y ...
 * SNnnnn" text.  What does tell them apart is the size of the register window
 * the PLX EEPROM programs into BAR2, which follows each board's register map:
 *
 *   Event generator   registers to 0x2e   BAR2 = 0x40 bytes,  PCI class 0880
 *   AT Distributed    registers to 0xd0   BAR2 = 0x400 bytes, PCI class 0680
 *
 * eg_identify() uses both signals.  See the comment on that function.
 **********************************************************/
#define PLX_VENDOR_ID              0x10b5
#define PLX_DEVICE_ID              0x9030
#define PLX_BAR                         2
#define PLX_STRING                 "PLX_9030"
#define WISHBONE_VENDOR_ID         0x2321
#define WISHBONE_DEVICE_ID         0x0002
#define WISHBONE_BAR                    3
#define WISHBONE_CONFIG_BAR             0
#define WISHBONE_CONFIG_SIZE       0x1000
#define WISHBONE_STRING            "WISHBONE"

/*
 * The highest register offset this driver touches is XIS_FE_REG_1 at 0x2e, so
 * any BAR shorter than 0x30 cannot be the event generator's register block.
 * The 2.6 driver ioremap()'d a fixed 32 bytes (PLX_REGION_SIZE) and then read
 * and wrote up to 0x2e, i.e. 15 registers past the end of its own mapping; it
 * only worked because ioremap() rounds up to a page.  The whole BAR is mapped
 * now and anything below this floor is rejected.
 */
#define EG_MIN_REGION_SIZE         0x0030

/*
 * ...and anything at or above this ceiling is a register window far larger
 * than the event generator's 46-byte register file, which on a mixed host
 * means it is the clock.  See eg_identify().
 */
#define EG_MAX_REGION_SIZE         0x0100

/* PCI class the event generator's PLX EEPROM programs: system peripheral. */
#define EG_PCI_CLASS               0x0880

/* What the shared carrier's serial-number PROM says.  Logged, not enforced. */
#define EG_IDENT_SIGNATURE         "EVENT GENERATOR"

/* Wishbone bridge registers, in the config BAR */
#define	WISHBONE_ICR		0x01EC	/* Interrupt Control register  */
#define WISHBONE_ISR		0x01F0	/* Interrupt Status register   */

/* Wishbone interrupt enables and masks */
#define INT			0x0001	/* WB interrupt mask                */
#define INT_PROP_EN		0x0001	/* WB interrupt propagation enable  */
#define WB_EINT_EN		0x0002	/* WB error interrupt enable        */
#define WB_EINT			0x0002	/* WB error interrupt mask          */

/************************************************************************/
/* event generator registers and bit assignments                        */
/************************************************************************/

#define MASTER_REG      0x0	/* master control/status register offset */

#define MA_4Waits                  0x2	/* insert 4 wait states */
#define MA_PLLResetRefFifo         0x4	/* R-PLL is locked/W-reset ref FIFO */
#define MA_LoadedGrabFrame         0x8	/* R-frame loaded/W-grab frame */
#define MA_LatePurgeEvent         0x10	/* R-late event/W-purge event */
#define MA_FrameFifoEmpty        0x100	/* frame FIFO empty */
#define MA_MSRefFifoEmpty        0x400	/* MS reference FIFO empty */
#define MA_MSRefFifoHalfEmpty   0x1000	/* MS reference FIFO half empty */
#define MA_LSRefFifoFull        0x2000	/* LS reference FIFO not full */
#define MA_MSRefFifoFull        0x4000	/* MS reference FIFO not full */
#define MA_SerNumBit            0x8000	/* current serial number bit */

#define IC_REG         0x2	/* interrupt control register offset */
#define IS_REG         0x4	/* interrupt status register offset */

/* NOTE- bit definitions in interrupt control and status registers
         are the same except for enable bit in control register */
#define IC_FIFOHalfEmpty        0x00002	/* reference FIFO half empty */
#define IC_LateEvent            0x00008	/* late event */
#define IC_CheckSumError        0x00010	/* checksum error */
#define IC_FalseSync            0x00020	/* false sync */
#define IC_MissedSync           0x00040	/* missed sync */
#define IC_FrameLoaded          0x00080	/* frame loaded */
#define IC_ExtInt               0x00200 /* external interrupt */
#define IC_Event                0x00400	/* event */
#define IC_PLLUnlocked          0x00800	/* phase lock loop unlocked */
#define IC_1Second              0x01000	/* 1 second interrupt */
#define IC_Finished             0x02000	/* All events have been processed */
#define IC_Extended             0x04000	/* An extended interrupt occurred */
#define IC_Enable               0x08000	/* enable interrupts */
#define IC_PhysicalIntrMask     ( IC_FIFOHalfEmpty | IC_LateEvent | \
                                  IC_CheckSumError | IC_FalseSync | \
                                  IC_MissedSync | IC_FrameLoaded | \
                                  IC_ExtInt | IC_Event | \
				  IC_PLLUnlocked | IC_1Second | \
                                  IC_Finished | IC_Extended | IC_Enable )

#define IC_GrabFrameComplete     0x10000 /* grab Frame Complete (software) */
#define IC_LogicalMask          0x10000	/* Logical interrupts mask */

#define FIFO_REG        0x6	/* R-frame FIFO/W-reference FIFO */

#define EVENT_CTRL_REG  0x8	/* event output control/status reg offset */

#define EC_Expert               0x0040	/* allow setting host event reg */
#define EC_FreeRunStrobe        0x0080	/* Strobe will free run */
#define EC_Int_Intr_Sel_Mask_Sft     8  /* amount to shift data */
#define EC_Int_Intr_Sel_Mask   (0x000f << EC_Int_Intr_Sel_Mask_Sft)
                                        /* Internal intr select line mask */
#define EC_TimeIntEna           0x1000	/* timed interrupt enable */
#define EC_TimeIntOutEna        0x2000	/* timed interrupt output enable */

#define EVENT_REG        0xa	/* host event register offset */

#define WFG_STATUS_REG     0x10
#define WFG_PRESCALE_0     0x12
#define WFG_PRESCALE_1     0x14
#define WFG_SELECT_1       0x16
#define WFG_SELECT_2       0x18

/* Rising edge interrupts */
#define  XI_REG_0_Mask        0xffff
#define  XI_REG_1_WFG_Mask    0x00ff
#define  XI_REG_1_T_Mask      0x0f00
#define  XI_REG_1_Unused_Mask 0x7000
#define  XI_REG_1_Strb_Mask   0x8000
#define  XI_REG_1_Mask        (XI_REG_1_WFG_Mask | XI_REG_1_T_Mask | \
			       XI_REG_1_Strb_Mask)
#define  XI_REG_WIDTH         16

#define XIC_RE_REG_0       0x20     /* extended intr ctrl reg 0 offset */
#define XIC_RE_REG_1       0x22     /* extended intr ctrl reg 1 offset */
#define XIS_RE_REG_0       0x24     /* extended intr status reg 0 offset */
#define XIS_RE_REG_1       0x26     /* extended intr status reg 1 offset */

/* Falling edge interrupts */
#define XIC_FE_REG_0       0x28     /* extended intr ctrl reg 0 offset */
#define XIC_FE_REG_1       0x2a     /* extended intr ctrl reg 1 offset */
#define XIS_FE_REG_0       0x2c     /* extended intr status reg 0 offset */
#define XIS_FE_REG_1       0x2e     /* extended intr status reg 1 offset */

#define LAST_EG_REG        0x2e	    /* highest address offset in EG */

#define ER_NoEventGen        -1
#define ER_EGPreambleError   -2
#define ER_EGSerNumTooLong   -3

enum {
  WRITE_STATE_IDLE = 0,
  WRITE_STATE_WRITING,
  WRITE_STATE_FIFO_FULL,
  WRITE_STATE_USC_FAIL,
  WRITE_STATE_CLAIM_ENTRY_FAIL,
  WRITE_STATE_WAIT_ON_HE_INTERRUPT,
  WRITE_STATE_WAIT_ON_HE_DONE,
  WRITE_STATE_SIGNAL_RECVD,
  WRITE_STATE_HE_INTR_ARRIVED
};

/************************************************************************/
/* Driver-private state                                                 */
/*                                                                      */
/* Was PrivateSysInfo_struct / EGSysInfo_struct in eg_struct.h, declared */
/* inside #ifdef __KERNEL__ in a header shared with userspace, with a    */
/* single file-scope instance called "SysInfo".  Per-card state is now   */
/* kzalloc'd in probe(), and no kernel structure appears in a UAPI       */
/* header.                                                              */
/************************************************************************/

struct eg_dev;

/*
 * Per-open context.  In 2.6 this was an entry in a PID-keyed table claimed
 * lazily on the first wait, and reclaimed by walking every entry on every
 * claim asking whether that PID still existed - with pid_task(find_get_pid())
 * which took a reference to the struct pid and never dropped it.  It is now
 * claimed by open() and released by release(), so no reaping is needed and no
 * reference leaks.
 */
struct eg_user {
	struct eg_dev		*dev;
	int			minor;
	bool			in_use;
	wait_queue_head_t	wq;
	bool			pending;	/* wake-up condition */
	InterruptMasks_struct	req;		/* armed sources, hw bits */
	InterruptMasks_struct	src;		/* sources that fired */
};

struct eg_dev {
	struct pci_dev		*pdev;
	void __iomem		*bar;		/* register block */
	void __iomem		*wishbone;	/* wishbone bridge, or NULL */
	int			bar_no;
	const char		*bar_name;
	resource_size_t		hw_addr;
	resource_size_t		region_size;
	u16			vendor;
	u16			device;

	int			irq;
	bool			irq_ok;

	/*
	 * Serialises register read-modify-write against the interrupt handler
	 * and protects everything below.  The 2.6 driver used local_irq_save()
	 * and local_irq_restore() for this, which disables interrupts on the
	 * running CPU only and so does not exclude anything at all on SMP.
	 */
	spinlock_t		lock;

	dev_t			devt;
	struct cdev		cdev;		/* one cdev over all minors */
	struct class		*cls;

	struct proc_dir_entry	*proc;

	struct eg_user		users[MAX_NUM_EG_USERS];

	int			write_owner;	/* minor with write access */
	pid_t			open_owner[MAX_NUM_EG_DEVICES];
	int			grab_frame_initiator;
	int			write_state;
	unsigned int		write_event_subcount;

	/*
	 * One byte per frame FIFO read: the frame FIFO returns a byte in the
	 * low half of each 16-bit read, and userspace reassembles the 48-bit
	 * BAT from the first six.  The truncating assignment is deliberate and
	 * is what read() has always returned.
	 */
	u8			frame_data[MAX_LENGTH_FRAME + 10];

	/* Per-minor timeouts, in jiffies.  0 means wait forever. */
	int			wait_intr_timeout[MAX_NUM_EG_DEVICES];
	int			wait_grab_frame_timeout[MAX_NUM_EG_DEVICES];

	EGStats_struct		stats;
	PublicSysInfo_struct	pub;
};

/* eg.c */
u16  eg_readw(struct eg_dev *dev, unsigned int off);
void eg_writew(struct eg_dev *dev, unsigned int off, u16 data);
u8   eg_readb(struct eg_dev *dev, unsigned int off);
void eg_writeb(struct eg_dev *dev, unsigned int off, u8 data);

#endif /* EG_H */

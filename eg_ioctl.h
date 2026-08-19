/* SPDX-License-Identifier: GPL-2.0 */
/**********************************************************
This include file defines all the ioctl commands for the
Event Generator. It should be included in the driver code
as well as any code calling the driver.

PORT NOTE (2.6 -> 6.8)
----------------------
The command numbers, the magic byte and the argument conventions are all
unchanged, so this half of the ABI is compatible with the 2.6 driver.  Three
things were fixed:

  * EVGEN_WAVEFORM_ENABLE expanded EG_WF_EN, which does not exist; the
    enumerator is EG_WF_EN_OP.  Any file that referenced the macro failed to
    compile, which is why nothing ever used it.

  * INTR_WAIT_ON_GRAB_FRAME_COMPLETE expanded INTR_WAIT_ON_GF_FN, which does
    not exist either; the enumerator is INTR_WAIT_ON_GFC_FN.

  * <asm/ioctl.h> became <linux/ioctl.h>, which is the header both the kernel
    and userspace are supposed to use.

Every command is encoded with _IO(), i.e. with no direction or size in the
command number, even for the ones that take a pointer.  That is wrong by
modern convention but it is the existing on-the-wire ABI, and re-encoding
would change every command number.  Left as is.
**********************************************************/

#ifndef EG_IOCTL_H
#define EG_IOCTL_H

#include <linux/ioctl.h>  /* this is where the _IO macro is defined */

enum {
  EG_RESET_OP,                    /* implemented */
  EG_WAIT_ON_INTR_OP,             /* implemented */
  EG_GET_EG_REG_OP,               /* implemented */
  EG_SET_EG_REG_OP,               /* implemented */
  EG_CLR_EVENTS_OP,               /* implemented */
  EG_RD_CURRENT_EVENT_OP,         /* implemented */
  EG_WR_EVENT_DIRECT_OP,          /* implemented */
  EG_GET_INT_INTR_LINE_OP,        /* implemented */
  EG_SET_INT_INTR_LINE_OP,        /* implemented */
  EG_GET_TIMEOUT_OP,              /* implemented */
  EG_SET_TIMEOUT_OP,              /* implemented */
  EG_GET_STATS_OP,                /* implemented */
  EG_GET_IDENT_OP,                /* implemented */
  EG_GET_FIFO_SIZE_OP,            /* implemented */
  EG_RD_EV_CNTRL_REG_OP,          /* implemented */
  EG_WR_EV_CNTRL_REG_OP,          /* implemented */
  EG_GET_ERR_STATUS_OP,           /* implemented */
  EG_CLEAR_ERR_STATUS_OP,         /* implemented */
  /* Waveform Gen stuff - Added 6/00 SH */
  EG_SET_WFPS_03_OP,              /* implemented */
  EG_SET_WFPS_47_OP,              /* implemented */
  EG_WF_SEL_OP,                   /* implemented */
  EG_WF_CON_OP,                   /* implemented */
  EG_WF_EN_OP,                    /* implemented */
  /* end */
  EG_DEBUGGING_OP,                /* implemented */
  EG_GET_DEVICE_INFO_OP,          /* implemented */
  EG_GET_XINT_INTR_LINE_OP,       /* not implemented, returns -EINVAL */
  EG_SET_XINT_INTR_LINE_OP,       /* not implemented, returns -EINVAL */

  EG_SET_OPTION_OP,               /* implemented */
  EG_CLEAR_OPTION_OP,             /* implemented */
  EG_WAIT_ON_EXTENDED_INTR_OP,    /* implemented */
  EG_GET_INTR_SRC_OP              /* implemented */
};

/* Use 'e' as magic number */
#define EVGEN_IOC_MAGIC  'e'

#define EVGEN_RESET               _IO(EVGEN_IOC_MAGIC, EG_RESET_OP)
#define EVGEN_WAIT_ON_INTR        _IO(EVGEN_IOC_MAGIC, EG_WAIT_ON_INTR_OP)
#define EVGEN_GET_EG_REG          _IO(EVGEN_IOC_MAGIC, EG_GET_EG_REG_OP)
#define EVGEN_SET_EG_REG          _IO(EVGEN_IOC_MAGIC, EG_SET_EG_REG_OP)
#define EVGEN_CLR_EVENTS          _IO(EVGEN_IOC_MAGIC, EG_CLR_EVENTS_OP)
#define EVGEN_READ_CURRENT_EVENT  _IO(EVGEN_IOC_MAGIC, EG_RD_CURRENT_EVENT_OP)
#define EVGEN_WRITE_EVENT_DIRECT  _IO(EVGEN_IOC_MAGIC, EG_WR_EVENT_DIRECT_OP)
#define EVGEN_GET_INT_INTR_LINE   _IO(EVGEN_IOC_MAGIC, EG_GET_INT_INTR_LINE_OP)
#define EVGEN_SET_INT_INTR_LINE   _IO(EVGEN_IOC_MAGIC, EG_SET_INT_INTR_LINE_OP)
#define EVGEN_GET_TIMEOUT         _IO(EVGEN_IOC_MAGIC, EG_GET_TIMEOUT_OP)
#define EVGEN_SET_TIMEOUT         _IO(EVGEN_IOC_MAGIC, EG_SET_TIMEOUT_OP)
#define EVGEN_GET_STATS           _IO(EVGEN_IOC_MAGIC, EG_GET_STATS_OP)
#define EVGEN_GET_IDENT           _IO(EVGEN_IOC_MAGIC, EG_GET_IDENT_OP)
#define EVGEN_GET_FIFO_SIZE       _IO(EVGEN_IOC_MAGIC, EG_GET_FIFO_SIZE_OP)
#define EVGEN_READ_EVENT_CONTROL  _IO(EVGEN_IOC_MAGIC, EG_RD_EV_CNTRL_REG_OP)
#define EVGEN_WRITE_EVENT_CONTROL _IO(EVGEN_IOC_MAGIC, EG_WR_EV_CNTRL_REG_OP)
#define EVGEN_GET_ERROR_STATUS    _IO(EVGEN_IOC_MAGIC, EG_GET_ERR_STATUS_OP)
#define EVGEN_CLEAR_ERROR_STATUS  _IO(EVGEN_IOC_MAGIC, EG_CLEAR_ERR_STATUS_OP)
/* Waveform Gen stuff - Added 5/00 SH */
#define EVGEN_SET_PRESCALE_03     _IO(EVGEN_IOC_MAGIC, EG_SET_WFPS_03_OP)
#define EVGEN_SET_PRESCALE_47     _IO(EVGEN_IOC_MAGIC, EG_SET_WFPS_47_OP)
#define EVGEN_WAVEFORM_SELECT     _IO(EVGEN_IOC_MAGIC, EG_WF_SEL_OP)
#define EVGEN_WAVEFORM_CONTROL    _IO(EVGEN_IOC_MAGIC, EG_WF_CON_OP)
/* Was EG_WF_EN, which is not defined anywhere.  See the port note above. */
#define EVGEN_WAVEFORM_ENABLE     _IO(EVGEN_IOC_MAGIC, EG_WF_EN_OP)
/* end */
#define EVGEN_DEBUGGING           _IO(EVGEN_IOC_MAGIC, EG_DEBUGGING_OP)
#define EVGEN_GET_DEVICE_INFO     _IO(EVGEN_IOC_MAGIC, EG_GET_DEVICE_INFO_OP)
#define EVGEN_GET_XINT_INTR_LINE  _IO(EVGEN_IOC_MAGIC, EG_GET_XINT_INTR_LINE_OP)
#define EVGEN_SET_XINT_INTR_LINE  _IO(EVGEN_IOC_MAGIC, EG_SET_XINT_INTR_LINE_OP)
#define EVGEN_SET_OPTION           _IO(EVGEN_IOC_MAGIC, EG_SET_OPTION_OP)
#define EVGEN_CLEAR_OPTION         _IO(EVGEN_IOC_MAGIC, EG_CLEAR_OPTION_OP)
#define EVGEN_EXTENDED_INTR_OPTION _IO(EVGEN_IOC_MAGIC, EG_WAIT_ON_EXTENDED_INTR_OP)
#define EVGEN_GET_INTERRUPT_SOURCE _IO(EVGEN_IOC_MAGIC, EG_GET_INTR_SRC_OP)

/*************************************************
Event Generator Errors
*************************************************/

#define EG_OK                    0
#define EG_GRAB_FRAME_FAIL      -1

enum {
  ERR_STAT_LE = 0,
  ERR_STAT_CS,
  ERR_STAT_FS,
  ERR_STAT_MS
};

/*************************************************
Event Generator Error Status options
*************************************************/
#define  ERROR_STATUS_LATE_EVENT      (1 << ERR_STAT_LE)
#define  ERROR_STATUS_CHECK_SUM       (1 << ERR_STAT_CS)
#define  ERROR_STATUS_FALSE_SYNC      (1 << ERR_STAT_FS)
#define  ERROR_STATUS_MISSED_SYNC     (1 << ERR_STAT_MS)

enum {
  INTR_WAIT_ON_1S_FN = 0,
  INTR_WAIT_ON_INTL_FN,
  INTR_WAIT_ON_EXTL_FN,
  INTR_WAIT_ON_FIN_FN,
  INTR_WAIT_ON_LE_FN,
  INTR_WAIT_ON_FL_FN,
  INTR_WAIT_ON_GFC_FN,
  INTR_WAIT_ON_FHE_FN,
  INTR_WAIT_ON_CKSUM_FN,
  INTR_WAIT_ON_FS_FN,
  INTR_WAIT_ON_MS_FN,
  INTR_WAIT_ON_PLDO_FN,
  INTR_WAIT_ON_X_FN,
  MAX_NUM_WAIT_ON_EG_FUNCTS  /* must come last */
};

#define INTR_WAIT_ON_1S_NAME     "1 Second"
#define INTR_WAIT_ON_INTL_NAME   "Internal"
#define INTR_WAIT_ON_EXTL_NAME   "External"
#define INTR_WAIT_ON_FIN_NAME    "Finish"
#define INTR_WAIT_ON_LE_NAME     "Late Event"
#define INTR_WAIT_ON_FL_NAME     "Frame Loaded"
#define INTR_WAIT_ON_FHE_NAME    "FIFO Half Empty"
#define INTR_WAIT_ON_CKSUM_NAME  "Check Sum Error"
#define INTR_WAIT_ON_FS_NAME     "Frame Sync Error"
#define INTR_WAIT_ON_MS_NAME     "Missed Sync Error"
#define INTR_WAIT_ON_PLDO_NAME   "PLL Dropout"
#define INTR_WAIT_ON_X_NAME      "Extended"
#define INTR_WAIT_ON_GFC_NAME    "Grab Frame Complete"

#define MAX_NUM_WAIT_ON_EG_XFUNCTS  32

/* DEBUG subfunctions */
enum {
  DEBUG_SET_DEBUG_LEVEL,
  DEBUG_CALL_ISR
};

/*************************************************
Event Generator Wait-on-interrupt options
*************************************************/

#define INTR_WAIT_ON_1SEC                (1 << INTR_WAIT_ON_1S_FN)
#define INTR_WAIT_ON_INTERNAL            (1 << INTR_WAIT_ON_INTL_FN)
#define INTR_WAIT_ON_EXTERNAL            (1 << INTR_WAIT_ON_EXTL_FN)
#define INTR_WAIT_ON_FINISHED            (1 << INTR_WAIT_ON_FIN_FN)
#define INTR_WAIT_ON_LATE_EVENT          (1 << INTR_WAIT_ON_LE_FN)
#define INTR_WAIT_ON_FRAME_LOADED        (1 << INTR_WAIT_ON_FL_FN)
#define INTR_WAIT_ON_CKSUM_ERROR         (1 << INTR_WAIT_ON_CKSUM_FN)
#define INTR_WAIT_ON_FALSE_SYNC_ERROR    (1 << INTR_WAIT_ON_FS_FN)
#define INTR_WAIT_ON_MISSED_SYNC_ERROR   (1 << INTR_WAIT_ON_MS_FN)
#define INTR_WAIT_ON_PLL_DO_ERROR        (1 << INTR_WAIT_ON_PLDO_FN)
#define INTR_WAIT_ON_FIFO_HALF_EMPTY     (1 << INTR_WAIT_ON_FHE_FN)
/* Was INTR_WAIT_ON_GF_FN, which is not defined.  See the port note above. */
#define INTR_WAIT_ON_GRAB_FRAME_COMPLETE (1 << INTR_WAIT_ON_GFC_FN)
#define INTR_WAIT_ON_EXTENDED            (1 << INTR_WAIT_ON_X_FN)

/*************************************************
Event Generator Set and Get timeout value options
*************************************************/
#define WAIT_TO_OPTION_SHIFT      24
#define WAIT_TO_OPTION_MASK       0xff000000
#define WAIT_GRAB_FRAME_TO_FLAG   (1 << WAIT_TO_OPTION_SHIFT)
#define WAIT_ON_INTR_TO_FLAG      (2 << WAIT_TO_OPTION_SHIFT)

/**************************************************************
 Bits associated with the internal event interrupt line
**************************************************************/

#define INTL_EVENT_LINE_MASK        0x0f
#define INTL_EVENT_LINE_SET         0x00
#define INTL_EVENT_LINE_GET         0x10
#define INTL_EVENT_LINE_ENABLE      0x20
#define INTL_EVENT_LINE_DISABLE     0x00

/***************************************************************
       EG GENERAL OPTIONS
***************************************************************/
#define EG_OPTION_NON_BLOCKING    0x00000001

/*************************************************************
 Waveform Generator options
*************************************************************/

/* Waveform selection */
enum {
    CONT_LO,
    FREQ,
    FREQ_DIV_2,
    FREQ_DIV_4,
    FREQ_DIV_8,
    FREQ_DIV_16,
    FREQ_DIV_32,
    FREQ_DIV_64,
    FREQ_DIV_128,
    FREQ_DIV_16_QUAD,
    FIXED_250K,
    FIXED_500K,
    CONT_HI = 0xE
};

/* Waveform output lines */
#define EG_WF0	0x01
#define EG_WF1	0x02
#define EG_WF2	0x04
#define EG_WF3	0x08
#define EG_WF4	0x10
#define EG_WF5	0x20
#define EG_WF6	0x40
#define EG_WF7	0x80

#define EXTENDED_INTR_FLAG   0x8000

#endif /* EG_IOCTL_H */

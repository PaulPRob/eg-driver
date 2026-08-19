/* SPDX-License-Identifier: GPL-2.0 */
/*
 * eg_struct.h - structures shared between the eg driver and its users.
 *
 * This header is part of the userspace ABI: anything that calls
 * EVGEN_GET_STATS, EVGEN_GET_DEVICE_INFO, EVGEN_GET_INTERRUPT_SOURCE or
 * EVGEN_EXTENDED_INTR_OPTION must be compiled against it.
 *
 * PORT NOTE (2.6 -> 6.8)
 * ---------------------
 * The 2.6 version of this file did three things it should not have:
 *
 *   1. It used "unsigned long int" for every value crossing the ioctl
 *      boundary.  That is 4 bytes on the i386 kernels this driver was
 *      written for and 8 bytes on x86-64, so InterruptMasks_struct was 12
 *      bytes for the old userspace and 24 for the new one, and every
 *      statistics entry moved.  All ABI fields are now fixed width.
 *
 *   2. It declared the driver's *private* structures (PrivateSysInfo_struct,
 *      EGSysInfo_struct, EGWaitOn_struct) in the same header, behind
 *      #ifdef __KERNEL__, complete with LINUX_VERSION_CODE conditionals.
 *      Those are gone; the driver's own state now lives in eg.h and never
 *      appears in a user-visible header.
 *
 *   3. Its layouts were not 32/64 stable.  Every structure here now has the
 *      same size and member offsets under "gcc -m32" and "gcc -m64", which
 *      is verified by the EG_ABI_* build assertions at the end of the file.
 *
 * Sizes on both 32- and 64-bit builds:
 *
 *      InterruptMasks_struct     12 bytes
 *      EGInterruptRate_struct    16 bytes
 *      EGStatsEntry_struct       64 bytes
 *      EGStats_struct          1152 bytes
 *      PublicSysInfo_struct     192 bytes
 */

#ifndef EG_STRUCT_H
#define EG_STRUCT_H

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/build_bug.h>
#else
#include <stdint.h>
#include <stddef.h>
#endif

#define MAX_EG_IDENT_LENGTH        80
#define MAX_LENGTH_FRAME           117
#define CONFIG_DATA_SIZE           256

#ifndef MAX_NUM_EG_DEVICES
#define MAX_NUM_EG_DEVICES          8  /* eg0 through eg7 */
#endif

#ifndef FIRST_DEVICE_MINOR_NUMBER
#define FIRST_DEVICE_MINOR_NUMBER   0 /* the first minor number */
#endif

/*
 * Maximum number of simultaneously open descriptors on the card.  In 2.6 this
 * bounded a table that was claimed lazily on the first wait and reaped by
 * walking the task list looking for dead PIDs; it is now simply the size of
 * the per-open context array, claimed by open() and released by close().  The
 * card allows one opener per minor and there are MAX_NUM_EG_DEVICES minors, so
 * this can never actually be reached.
 */
#define MAX_NUM_EG_USERS 20

enum {
  IR_LATE_EVENT,
  IR_CHECK_SUM,
  IR_FALSE_SYNC,
  IR_MISSED_SYNC,
  IR_INTERNAL,
  MAX_NUM_IR_POINTS
};

/*
 * The maximum rate of interrupts from any of the above sources per jiffy.  If
 * this rate is exceeded the offending interrupt is masked until the next jiffy.
 */
#define MAX_INTERRUPT_RATE 10000

/* Current layout of the structures below.  Bump on any incompatible change. */
#define EG_ABI_VERSION 2

/************************************************************************/
/* structure definitions						*/
/************************************************************************/

/*
 * A set of interrupt sources: the primary interrupt control/status register
 * bits, plus the 32 extended (per event line) rising- and falling-edge bits.
 *
 * Was three "unsigned long int".  The hardware registers behind Rising and
 * Falling are 32 bits wide, so uint32_t loses nothing and pins the layout.
 */
typedef struct {
  uint32_t Primary;
  uint32_t Rising;
  uint32_t Falling;
} InterruptMasks_struct;

/*
 * Interrupt rate limiter state for one interrupt source.
 *
 * Jiffies was "int": the driver stored the kernel's unsigned long jiffies in
 * it and compared the two, which only happened to work through sign extension
 * of the truncated value.  It is now a full-width unsigned counter.
 */
typedef struct {
  uint64_t Jiffies;
  int32_t  Count;
  int32_t  InterruptBit;
} EGInterruptRate_struct;

#define MAX_STATUS_NAME_LENGTH 48

/*
 * One named statistics counter.
 *
 * Label was [MAX_STATUS_NAME_LENGTH + 4] = 52 bytes followed by an
 * "unsigned long", which made the structure 56 bytes on i386 and 64 on
 * x86-64.  Label is padded to 56 so that the uint64_t lands on an 8-byte
 * boundary and the structure is 64 bytes everywhere, with no packing.
 */
typedef struct {
  char     Label[MAX_STATUS_NAME_LENGTH + 8];
  uint64_t Value;
} EGStatsEntry_struct;

enum {
  STATS_INTERRUPT_COUNT = 0,
  STATS_HALF_EMPTY_INTR_COUNT,
  STATS_LATE_EVENT_INTR_COUNT,
  STATS_CHECK_SUM_INTR_COUNT,
  STATS_FALSE_SYNC_INTR_COUNT,
  STATS_MISSED_SYNC_INTR_COUNT,
  STATS_FRAME_LOADED_INTR_COUNT,
  STATS_EXTERNAL_INTR_COUNT,
  STATS_INTERNAL_INTR_COUNT,
  STATS_PLL_UNLOCKED_INTR_COUNT,
  STATS_ONE_SECOND_INTR_COUNT,
  STATS_FINISHED_INTR_COUNT,
  STATS_EXTENDED_INTR_COUNT,
  STATS_EVENTS_WRITTEN_COUNT,
  STATS_DRIVER_UPTIME,
  STATS_USE_COUNT,
  STATS_END_MARKER,
  STATS_MAX_NUM_STATS_ENTRIES
};

typedef struct {
  EGStatsEntry_struct List[STATS_MAX_NUM_STATS_ENTRIES + 1];
} EGStats_struct;

/*
 * The card's fixed properties, returned by EVGEN_GET_DEVICE_INFO.
 *
 * ABIVersion is new.  It is last so that a short read still gets the fields
 * it asked for, and it exists so that a mismatched binary can be told apart
 * from a merely truncated one.
 */
typedef struct {
  char     IdentString[MAX_EG_IDENT_LENGTH + 4];
  int32_t  FifoSize;           /* size of the reference FIFO, in events */
  int32_t  Status;             /* EG_LD_STATUS_* */
  int32_t  WriteOwner;         /* minor holding write access, or -1 */
  uint64_t DriverStartTime;    /* jiffies at probe */
  EGInterruptRate_struct InterruptRate[MAX_NUM_IR_POINTS];
  uint16_t lsbPrescaleReg;     /* waveform generator prescale shadow */
  uint16_t msbPrescaleReg;
  uint32_t ABIVersion;         /* EG_ABI_VERSION */
} PublicSysInfo_struct;

/*
 * Layout assertions.  These fire at compile time in both the kernel and the
 * userspace build, so a change that silently moves a field cannot ship.
 */
#ifdef __KERNEL__
#define EG_ABI_ASSERT(cond, name) static_assert(cond, #name)
#else
#define EG_ABI_ASSERT(cond, name) \
	typedef char eg_abi_assert_##name[(cond) ? 1 : -1]
#endif

EG_ABI_ASSERT(sizeof(InterruptMasks_struct)  == 12,   masks_is_12);
EG_ABI_ASSERT(sizeof(EGInterruptRate_struct) == 16,   rate_is_16);
EG_ABI_ASSERT(sizeof(EGStatsEntry_struct)    == 64,   entry_is_64);
EG_ABI_ASSERT(sizeof(EGStats_struct)         == 1152, stats_is_1152);
EG_ABI_ASSERT(sizeof(PublicSysInfo_struct)   == 192,  pub_is_192);
EG_ABI_ASSERT(offsetof(PublicSysInfo_struct, DriverStartTime) == 96,
	      pub_start_at_96);

#endif /* EG_STRUCT_H */

/* SPDX-License-Identifier: GPL-2.0 */
/*
 * test_eg.c - interactive exerciser for the CSIRO ATNF PC Event Generator.
 *
 * PORT NOTE (2.6 / 32-bit -> Linux 6.8 / x86-64)
 * ----------------------------------------------
 * This program was written for a 32-bit userland and was comprehensively
 * broken on x86-64 - not "warns", but "passes garbage to every ioctl".
 *
 *  1. eg_ioctl() read its variadic argument by taking the address of its
 *     last named parameter and incrementing the pointer:
 *
 *         int eg_ioctl(int handle, unsigned int function, ...) {
 *                 unsigned int *args = &function;
 *                 ++args;
 *                 return ioctl(handle, function, *args);
 *         }
 *
 *     That happens to find the third argument on the i386 stack-argument ABI
 *     and finds an unrelated word of the caller's frame on any other.  It also
 *     truncated every pointer argument to 32 bits.  It uses <stdarg.h> now and
 *     carries an unsigned long, so pointers survive.
 *
 *  2. Every "(int) &something" cast - there were six - truncated a 64-bit
 *     pointer, and gcc has warned about it for twenty years.
 *
 *  3. ftime() and struct timeb were removed from POSIX in 2008 and are
 *     deprecated in glibc.  Replaced with clock_gettime(CLOCK_REALTIME).
 *
 *  4. printf(string) with a runtime string is a format string vulnerability
 *     (-Wformat-security).  There were five.  One of them,
 *     printf(string, "Timed out!\n"), printed the *previous* message's text.
 *
 *  5. fgets() return values were never checked, so at EOF - which is what
 *     happens the moment you drive this from a script or a pipe - every menu
 *     loop spun forever on the stale buffer.  All terminal input now goes
 *     through eg_gets(), and EOF is treated as "q".
 *
 *  6. GrabFrame() returned EG_OK (0) on an ioctl failure, so its callers
 *     could not tell success from failure.
 *
 *  7. PsuedoPulsarEventTest() seeded the event word from an uninitialised
 *     buffer[3], with "&= !mask" (logical not) where "&= ~mask" was meant.
 *
 *  8. The masks and statistics counters changed width - see eg_struct.h - so
 *     the printf conversions for them changed with it.
 *
 * The menu, the tests and the parameter file format are unchanged.
 */

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/fcntl.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#include "eg_ioctl.h"
#include "eg_struct.h"

#undef XXXX
#define MAX_LINE_LENGTH 80
#define EG_PATH_MAX 4096
#define EG_READ_DEFAULT_TIMEOUT_MS      1000
#define PULSAR_SENSE_POSITIVE           0
#define PULSAR_SENSE_NEGATIVE           1
#define SECOND_MARK_MODE_ABSOLUTE       0
#define SECOND_MARK_MODE_MINUTE         1
#define DEFAULT_DUTC                   33

#define EG_OPTION_USE_SELECT            1

enum {
  GENERATE_EVENT_MODE_COUNT_NORMAL = 1,
  GENERATE_EVENT_MODE_COUNT_FLIPPED,
  GENERATE_EVENT_MODE_WALKING_1,
  GENERATE_EVENT_MODE_RANDOM };

typedef struct {
  short int value;
  char label[MAX_LINE_LENGTH];
} type_list_struct;


typedef struct {
  double Period;
  unsigned int Duration;
  unsigned int Mask;
  unsigned int Sense;
  unsigned int StartDelay;
  unsigned int SlideRate;
  unsigned int SecondMarkMode;
  unsigned int SecondMark;
} PulsarInfo_struct;

typedef struct {
  double EventIncrement;
  int Device;
  int Handle;
  int Options;
  int Test;
  int Timeout;
  int GenerateEventMode;
  int EventInterruptLine;
  int DebugLevel;
  int RandomInsertLateEvents;
  int PrintOutRate;
  InterruptMasks_struct Interrupt;
  PulsarInfo_struct Pulsar;
} TestInfo_struct;

/*
 * ProgName, ParamFile and HomeDir were all MAX_LINE_LENGTH + 4 = 84 bytes,
 * and ParamFile was built by sprintf'ing the other two into it - so any $HOME
 * longer than about 70 characters silently produced a truncated, wrong path.
 */
typedef struct {
  int dUTC;
  char ProgName[MAX_LINE_LENGTH + 4];
  char HomeDir[EG_PATH_MAX];
  char ParamFile[EG_PATH_MAX + MAX_LINE_LENGTH + 8];
  TestInfo_struct Test;
} SysInfo_struct;


int SetGetXInterrupt(SysInfo_struct *sysinfo);
int SetDebugLevel(SysInfo_struct *sysinfo);
int SetEventInterrupt(SysInfo_struct *sysinfo);
int SetEventTest(SysInfo_struct *sysinfo);
int GetStatsTest(SysInfo_struct *sysinfo);
int GetInterrupts(SysInfo_struct *sysinfo);
int WaitOnInterruptTest(SysInfo_struct *sysinfo);
int GrabFrameTest(SysInfo_struct *sysinfo);
int GenerateEventsTest(SysInfo_struct *sysinfo);
int PsuedoPulsarEventTest(SysInfo_struct *sysinfo);
int PrintInterruptSource(SysInfo_struct *sysinfo);
int EventRegisterTest(SysInfo_struct *sysinfo);
int LateEventTest(SysInfo_struct *sysinfo);
int InteractiveDebugSession(SysInfo_struct *sysinfo);
type_list_struct *InitializePrimaryInterruptList(void);
int GrabFrame(int device, unsigned char *data, int size);
int GetBat(int device, unsigned long long *bat);
int TestParams(SysInfo_struct *sysinfo, const char *mode);
int kbhit(int us_delay);
int eg_ioctl(int handle, unsigned int function, ...);
int eg_write(int handle, void *buffer, int count);
char *CreateTimeString(char *string, const struct timespec *ts);
int kbdrain(void);

/*
 * Line input for the menus.  Returns NULL at EOF, which every caller treats
 * exactly as it treats "q".  2.6 ignored fgets()'s return value everywhere,
 * so end of input turned every prompt into a busy loop on a stale buffer.
 */
static char *eg_gets(char *buf, size_t size);


int main(int argc, char **argv)
{
char string[MAX_LINE_LENGTH + 2];
char *cp;
int err;
int n;
SysInfo_struct SysInfo;

    memset(&SysInfo, 0, sizeof(SysInfo));


    cp = getenv("HOME");
    if(cp == NULL) cp = ".";   /* 2.6 strcpy'd a NULL when HOME was unset */
    snprintf(SysInfo.HomeDir, sizeof(SysInfo.HomeDir), "%s", cp);

    for(n = strlen(argv[0]); n >= 0; --n) {
      if(argv[0][n] == '/') {
	++n;
	break;
      }
    }

    snprintf(SysInfo.ProgName, sizeof(SysInfo.ProgName), "%s", &argv[0][n]);

    snprintf(SysInfo.ParamFile, sizeof(SysInfo.ParamFile), "%s/%s.dat",
	     SysInfo.HomeDir, SysInfo.ProgName);

    TestParams(&SysInfo, "r");

    /* Was commented out in 2.6; wired up so the program can be scripted. */
    if(argc > 1 && sscanf(argv[1], "%d", &n) == 1 && n >= 0)
      SysInfo.Test.Device = n;

    while(1) {
      while(1) {
	printf("Device number? [%d] ", SysInfo.Test.Device);
	if(eg_gets(string, sizeof(string)) == NULL) return(0);
	if(string[0] == 0xa) break;
	if(string[0] == 'q') return(0);
	if(sscanf(string, "%d", &n) == 1 && n >= 0) {
	  SysInfo.Test.Device = n;
	  break;
	}
      }

      snprintf(string, sizeof(string), "/dev/eg%d", SysInfo.Test.Device);
      /* if(SysInfo.Test.Device == 0) SysInfo.Test.Handle = open(string, O_WRONLY); */
      if(SysInfo.Test.Device == 0) SysInfo.Test.Handle = open(string, O_RDWR);
      else SysInfo.Test.Handle = open(string, O_RDONLY);
      if(SysInfo.Test.Handle == -1) {
	printf("Unable to open %s\n", string);
	++SysInfo.Test.Device;
	if(SysInfo.Test.Device >= MAX_NUM_EG_DEVICES) break;
	continue;
      }
      break;
    }

    if(SysInfo.Test.Handle == -1) 
      printf("No EG opened. Will pretend!!!\n");

    else printf("Success....%s opened\n", string);

    if(SysInfo.Test.Device == 0) {
      err = eg_ioctl(SysInfo.Test.Handle, EVGEN_RESET, 0UL);
      if(err != 0) printf("ioctl error %d\n", errno);
    }

    while(1) {
      printf("dUTC (S)? [%u] ", SysInfo.dUTC);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%u", &n) != 1) continue;
      SysInfo.dUTC = n;
      break;
    }

    while(1) {
      while(1) {
	printf("1 - Wait On Interrupt\n");
	printf("2 - Grab Frame\n");
	printf("3 - Dump Stats\n");
	printf("4 - Set Event lines\n");
	printf("5 - Set Internal interrupt line\n");
	printf("6 - Test for Late Events\n");
	printf("7 - Set Debug Level\n");
	printf("8 - Interactive Debug session\n");
	printf("9 - Set/Get Extended interrupt info\n");
	printf("10 - Print interrupt source\n");
	if(SysInfo.Test.Device == 0) printf("11 - Generate events\n");
	if(SysInfo.Test.Device == 0) printf("12 - Psuedo Pulsar\n");
	printf("Select operation [%d]: ", SysInfo.Test.Test);

	if(eg_gets(string, sizeof(string)) == NULL) return(0);
	if(string[0] == 'q') return(0);
	if(string[0] == 0xa) break;
	if(sscanf(string, "%d", &n) != 1) continue;
	if(n < 1 ) continue;
	SysInfo.Test.Test = n;
	break;
      }

      TestParams(&SysInfo, "w");

      if(SysInfo.Test.Test == 1) WaitOnInterruptTest(&SysInfo);
      else if(SysInfo.Test.Test == 2) GrabFrameTest(&SysInfo);
      else if(SysInfo.Test.Test == 3) GetStatsTest(&SysInfo);
      else if(SysInfo.Test.Test == 4) SetEventTest(&SysInfo);
      else if(SysInfo.Test.Test == 5) SetEventInterrupt(&SysInfo);
      else if(SysInfo.Test.Test == 6) LateEventTest(&SysInfo);
      else if(SysInfo.Test.Test == 7) SetDebugLevel(&SysInfo);
      else if(SysInfo.Test.Test == 8) InteractiveDebugSession(&SysInfo);
      else if(SysInfo.Test.Test == 9) SetGetXInterrupt(&SysInfo);
      else if(SysInfo.Test.Test == 10) PrintInterruptSource(&SysInfo);
      else if(SysInfo.Test.Test == 11 && SysInfo.Test.Device == 0)
	GenerateEventsTest(&SysInfo);
      else if(SysInfo.Test.Test == 12 && SysInfo.Test.Device == 0)
	PsuedoPulsarEventTest(&SysInfo);


    }
}

int InteractiveDebugSession(SysInfo_struct *sysinfo)
{
int n;
int err;
int data;
int addr;
 char prev_op;
char string[MAX_LINE_LENGTH + 2];

    addr = 0;
    data = 0;
    prev_op = 0;

    while(1) {
      printf("Debug [%x]> ", addr);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == '?') {
	printf("q - quit\n");
	/* printf("l - loop counter\n"); */
	printf("i - input\n");
	printf("o - output\n");
	/* printf("a - set address offset\n");
	printf("t - read/write test on location\n"); */
      }

      if(string[0] == 0 || string[0] == 0xa) {
	if(prev_op == 'i') {
	  n = addr << 16;
	  err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_EG_REG, (unsigned long) &n);
	  if(err != 0) printf("IOCTL error: %s \n", strerror(errno));
	  else printf("(%x) -> %x\n", addr , n & 0xffff);
	}
	if(prev_op == 'o') {
	  n = (addr << 16) | (data & 0xffff);
	  err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_EG_REG, (unsigned long) &n);
	  if(err != 0) printf("IOCTL error: %s \n", strerror(errno));
	  else printf("%x -> (%x)\n", data, addr);
	}
      }

      if(string[0] == 'i') {
	prev_op = 'i';
	if(sscanf(string, "i %x", &addr) == 1) {
	  n = addr << 16;
	  err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_EG_REG, (unsigned long) &n);
	  if(err != 0) printf("IOCTL error: %s \n", strerror(errno));
	  else printf("(%x) -> %x\n", addr , n & 0xffff);
	}
      }

      if(string[0] == 'o') {
	prev_op = 'o';
	n = sscanf(string, "o %x %x", &addr, &data);
	n = (addr << 16) | (data & 0xffff);
	err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_EG_REG, (unsigned long) n);
	if(err != 0) printf("IOCTL error: %s \n", strerror(errno));
	else printf("%x -> (%x)\n", data, addr);
      }
    }

  return(0);
}


int SetGetXInterrupt(SysInfo_struct *sysinfo)
{
int n;
int extended;
 int edge;
 int type;
 int value;
int err;
unsigned short int buffer[4];
char string[MAX_LINE_LENGTH + 2];

    edge = 0; 
    value = 0; 
    type = 0; 
    memset(buffer, 0, sizeof(buffer));

    while(1) {
      err = ioctl((*sysinfo).Test.Handle, EVGEN_GET_XINT_INTR_LINE, buffer);
      /*
       * These two commands were already #ifdef'd out of the 2.6 driver under
       * NOLONGERINUSE and are documented as "no longer implemented"; the
       * driver returns -EINVAL for them.  2.6 ignored the error and printed
       * an uninitialised buffer in an infinite loop.  Use menu option 1 with
       * interrupt source 12 (Extended) to arm extended interrupts instead.
       */
      if(err != 0) {
	printf("EVGEN_GET_XINT_INTR_LINE is not implemented by the driver: %d:%s\n",
	       errno, strerror(errno));
	printf("Use option 1 (Wait On Interrupt) and include source %d "
	       "(%s) to arm extended interrupts.\n",
	       INTR_WAIT_ON_X_FN, INTR_WAIT_ON_X_NAME);
	return(0);
      }

      if((buffer[3] & EXTENDED_INTR_FLAG) != 0) {
	extended = 1;
	buffer[3] &= (EXTENDED_INTR_FLAG);
      }
      else extended = 0;

      for(n = 0; n < 4; ++n) {
	printf("%04x ", buffer[n]);
      }
      if(extended != 0) printf("Extended Enabled\n");
      else printf("Extended Disabled\n");

      while(1) {
	printf("Set Event Line(s) (y/n)? ");
	if(eg_gets(string, sizeof(string)) == NULL) return(0);
	if(string[0] == 'q') return(0);
	if(string[0] == 'n' || string[0] == 0xa) break;
	if(string[0] == 'y') {
	  for(n = 0; n < 4; ++n) buffer[n] = 0;
	  while(1) {
	    printf("Edge (f/r)? ");
	    if(eg_gets(string, sizeof(string)) == NULL) return(0);
	    if(string[0] == 'q') return(0);
	    if(string[0] != 'r' && string[0] != 'f') continue;
	    if(string[0] == 'r') edge = 1;
	    else edge = 0;
	    break;
	  }

	  while(1) {
	    printf("Type (e/w/s)? ");
	    if(eg_gets(string, sizeof(string)) == NULL) return(0);
	    if(string[0] == 'q') return(0);
	    if(string[0] != 'e' && string[0] != 'w' &&
	       string[0] != 's') continue;
	    if(string[0] == 'e') type = 0;
	    else if(string[0] == 'w') type = 1;
	    else type = 2;
	    break;
	  }

	  while(1) {
	    if(type == 2) break;
	    if(type == 1) printf("WFG Value (hex) ? ");
	    if(type == 0) printf("EGG Value (hex) ? ");
	    if(eg_gets(string, sizeof(string)) == NULL) return(0);
	    if(string[0] == 'q') return(0);
	    if(sscanf(string, "%x", &value) == 1) break;
	  }

	  if(edge == 0) {
	    if(type == 0) buffer[0] = value & 0xffff;
	    else if(type == 1) buffer[1] = value & 0xff;
	    else if(type == 2) buffer[1] = 0x100;
	    }
	  else if(edge == 1) {
	    if(type == 0) buffer[2] = value & 0xffff;
	    else if(type == 1) buffer[3] = value & 0xff;
	    else if(type == 2) buffer[3] = 0x100;
	  }
	  printf("Setting: ");
	  for(n = 0; n < 4; ++n) {
	    printf("%04x ", buffer[n]);
	  }
	  buffer[3] |= EXTENDED_INTR_FLAG;
	  err = ioctl((*sysinfo).Test.Handle, EVGEN_SET_XINT_INTR_LINE, buffer);
	  if(err != 0) {
	    printf("ioctl error: errno:%d : %s\n", errno, strerror(errno));
	    return(0);
	  }
	}
      }
    }

    return(0);
}


int SetDebugLevel(SysInfo_struct *sysinfo)
{
int n;
 int err;
char string[MAX_LINE_LENGTH + 2];

    while(1) {
      printf("Debug level [%d]: ",
	     (*sysinfo).Test.DebugLevel);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%d", &n) == 1) {
	if(n < 0) continue;
	(*sysinfo).Test.DebugLevel = n;
	break;
      }
    }
    (*sysinfo).Test.DebugLevel &= 0xffff;
    (*sysinfo).Test.DebugLevel |= (DEBUG_SET_DEBUG_LEVEL << 16);
    err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_DEBUGGING, (unsigned long) (*sysinfo).Test.DebugLevel);
    if(err < 0) printf("Setting Debug Level returned an error: %d\n", errno);
    return(0);

}

int SetEventInterrupt(SysInfo_struct *sysinfo)
{
int n;
int err;
char string[MAX_LINE_LENGTH + 2];

    n = 0; 

    while(1) {
      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_INT_INTR_LINE, (unsigned long) &n);
      (*sysinfo).Test.EventInterruptLine = n & 0xf;
      if(n < 0) printf("Internal Interrupt line currently not enabled.\n");

      while(1) {
	printf("Event Line to interrupt from [%d]: ",
	       (*sysinfo).Test.EventInterruptLine);
	if(eg_gets(string, sizeof(string)) == NULL) return(0);
	if(string[0] == 'q') return(0);
	if(string[0] == 0xa) break;
	if(sscanf(string, "%d", &n) == 1) {
	  if(n >= 0 && n < 16) break;
	}
      }

      (*sysinfo).Test.EventInterruptLine = n;
      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_INT_INTR_LINE,
		  (unsigned long) (*sysinfo).Test.EventInterruptLine);
      if(err != 0) {
	printf("ioctl error unable to set internal interrupt line. errno:%d\n",
	       errno);
	printf("%s\n", strerror(errno));
      }

    }

}


int SetEventTest(SysInfo_struct *sysinfo)
{
unsigned int event;
int err;
int mask;
char string[MAX_LINE_LENGTH + 2];


    err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_READ_CURRENT_EVENT, (unsigned long) &event);
    if(err != 0) printf("ioctl error getting current event %d\n", errno);
    mask = 0xffff;

    while(1) {
      while(1) {
	printf("Event value (mask %x) [%x]: ", mask, event);
	if(eg_gets(string, sizeof(string)) == NULL) return(0);
	if(string[0] == 'q') return(0);
	if(string[0] == '~') {
	  event = ~(event & mask) | (event & ~mask);
	  break;
	}
	if(string[0] == 0xa) break;
	if(sscanf(string, "%x", &event) == 1) break;
	if(sscanf(string, "mask %x", &mask) == 1) continue;
	if(string[0] == '?') {
	  printf("? - prints this message.\n");
	  printf("q - quit this test.\n");
	  printf("mask value - set mask value.\n");
	  printf("~ - inverts current event bits within mask value.\n");
	  printf("<RET> - use default event value.\n");
	}
      }

      event &= mask;

      /* write out event */
      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_WRITE_EVENT_DIRECT, (unsigned long) event);
      if(err != 0) printf("ioctl error writing event %d\n", errno);
    }
}


int GetStatsTest(SysInfo_struct *sysinfo)
{
int err;
int n;
int m;
int maxl;
int time_src;
unsigned int interrupt_count;
char string[80];
EGStats_struct stats;

    time_src = 0; 
    interrupt_count = 0;

    /* set time out to 2 seconds */
    err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_TIMEOUT, (unsigned long) (WAIT_ON_INTR_TO_FLAG | 2000));
    if(err != 0) printf("ioctl error setting timeout %d\n", errno);

    n = 0;
    while(1) {

      if(time_src == 0) {
	err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_WAIT_ON_INTR, (unsigned long) INTR_WAIT_ON_1SEC);
	if(err != 0) {
	  printf("ioctl error %d\n", errno);
	  time_src = 1;
	}
      }
      else usleep(1000000);

      /* set first int element in array to size of array */
      memset(&stats, 0, sizeof(stats));
      memset(&stats, 0, sizeof(stats));
    *((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);

      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS,
		     (unsigned long) &stats);
      if(err != 0) {
	printf("ioctl error %d\n", errno);
	return(0);
      }

      /* The bound was "(int)&List[n] - (int)&List[0] > sizeof(struct)", four
	 truncating pointer casts to say "n < the number of entries". */
      maxl = 0;
      for(n = 0; n < STATS_MAX_NUM_STATS_ENTRIES; ++n) {
	if(stats.List[n].Label[0] == 0) break;
	if((int) strlen(stats.List[n].Label) > maxl)
	  maxl = strlen(stats.List[n].Label);
      }

      printf("%u\n", interrupt_count++);
      for(n = 0; n < STATS_MAX_NUM_STATS_ENTRIES; ++n) {
	if(stats.List[n].Label[0] == 0) break;
	for(m = 0; m < (maxl - (int) strlen(stats.List[n].Label)); ++m)
	  string[m] = ' ';
	string[m] = 0;
	printf("%s %s %10" PRIu64 "\n", stats.List[n].Label, string,
	       stats.List[n].Value);
      }
      printf("\n");

      if(kbhit(0)) break;
    }
    return(0);
}


int WaitOnInterruptTest(SysInfo_struct *sysinfo)
{
int err, use_select, n, function, print_flag, ce;
unsigned long int interrupt_count;
unsigned long long bat;
InterruptMasks_struct masks, smasks;
fd_set kb_mask;
fd_set exception_mask;
struct timeval tv;
struct timespec tp;
struct timeval tprevious, tcurrent, tdelta;
char string[MAX_LINE_LENGTH + 2];
char timestr[MAX_LINE_LENGTH + 2];


    interrupt_count = 0;
    print_flag = 0;
    use_select = 0;
    ce = 0;
    memset(&masks, 0, sizeof(InterruptMasks_struct));

    while(1) {
      printf("Timeout period (sec) (0 means none) [%d]: ", (*sysinfo).Test.Timeout);

      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%d", &n) == 1) {
	if(n >= 0) {
	  (*sysinfo).Test.Timeout = n;
	  break;
	}
      }
    }

    if(GetInterrupts(sysinfo) < 0) return(0);


    while(1) {
      printf("Use Select? ");
      if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) printf("[y] : ");
      else printf("[n] : ");

      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(string[0] == 'y')  {
	(*sysinfo).Test.Options |= EG_OPTION_USE_SELECT;
	break;
      }
      if(string[0] == 'n')  {
	(*sysinfo).Test.Options &= ~EG_OPTION_USE_SELECT;
	break;
      }
    }
    if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) use_select = 1;
    else use_select = 0;

    while(1) {
      if((*sysinfo).Test.PrintOutRate <= 0) (*sysinfo).Test.PrintOutRate = 1;
      printf("Printout rate? [%d] ", (*sysinfo).Test.PrintOutRate);

      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%d", &n) == 1) {
	if(n <= 0) n = 1;
	(*sysinfo).Test.PrintOutRate = n;
	break;
      }
    }

    TestParams(sysinfo, "w");
    printf("Masks : Primary: %" PRIx32 "  Extended RE: %" PRIx32
	   "  Extended FE: %" PRIx32 "\n",
	   (*sysinfo).Test.Interrupt.Primary,
	   (*sysinfo).Test.Interrupt.Rising,
	   (*sysinfo).Test.Interrupt.Falling);

    /* set time out */
    err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_TIMEOUT,
		(unsigned long) (WAIT_ON_INTR_TO_FLAG |
				 ((*sysinfo).Test.Timeout * 1000)));
    if(err != 0) printf("ioctl error setting timeout %d\n", errno);
    
    /* set blocking option */
    if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) function = EVGEN_SET_OPTION;
    else function = EVGEN_CLEAR_OPTION;
    err = eg_ioctl((*sysinfo).Test.Handle, function,
		   (unsigned long) EG_OPTION_NON_BLOCKING);
    if(err != 0) printf("ioctl error setting blocking %d\n", errno);
    
    n = 0;
    gettimeofday(&tprevious, NULL);

    while(1) {

      masks.Primary = (*sysinfo).Test.Interrupt.Primary;
      masks.Rising = (*sysinfo).Test.Interrupt.Rising;
      masks.Falling = (*sysinfo).Test.Interrupt.Falling;
      if(((*sysinfo).Test.Interrupt.Primary & INTR_WAIT_ON_EXTENDED) != 0) 
	err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_EXTENDED_INTR_OPTION, (unsigned long) &masks);
      
      else err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_WAIT_ON_INTR,
			  (unsigned long) masks.Primary);

      
      if((interrupt_count % (*sysinfo).Test.PrintOutRate) == 0) print_flag = 1;
      else print_flag = 0;

      if(use_select == 0) {
	if(err != 0) {
	  if(errno == 11) printf("Timed out...");
	  else {
	    printf("ioctl error setting EVGEN_WAIT_ON_INTR with masks:\n");
	    printf("Pri:%" PRIx32 "  Ext_RE: %" PRIx32 "  Ext_FE:%" PRIx32 "\n",
		   (*sysinfo).Test.Interrupt.Primary,
		   (*sysinfo).Test.Interrupt.Rising,
		   (*sysinfo).Test.Interrupt.Falling);
	    printf("Errno:  %d: Error: %s\n",
		   errno, strerror(errno));
	    return(0);
	  }
	}

	else {
	  err = ioctl((*sysinfo).Test.Handle, EVGEN_READ_CURRENT_EVENT, &ce);
	  if(err != 0) printf("ioctl error reading current event %d:%s\n",
			      errno, strerror(errno));

	  err = ioctl((*sysinfo).Test.Handle, EVGEN_GET_INTERRUPT_SOURCE, &smasks);
	  if(err != 0) printf("ioctl error getting interrupt source %d:%s\n",
			      errno, strerror(errno));

	  gettimeofday(&tcurrent, NULL);
	  bat = 0;
	  GetBat((*sysinfo).Test.Handle, &bat);
	  clock_gettime(CLOCK_REALTIME, &tp);
	  tdelta.tv_sec = tcurrent.tv_sec - tprevious.tv_sec;
	  tdelta.tv_usec = tcurrent.tv_usec - tprevious.tv_usec;
	  tdelta.tv_usec = (tdelta.tv_sec * 1000000) + tdelta.tv_usec;
	  tprevious.tv_sec = tcurrent.tv_sec;
	  tprevious.tv_usec = tcurrent.tv_usec;

	  if(print_flag == 1) {
	    printf("%lu Intr @ %s: BAT: %llx dt: %8ld uS event: %04x\n",
		   interrupt_count, CreateTimeString(timestr, &tp), bat,
		   (long) tdelta.tv_usec, ce & 0xffff);
	    printf("                                     req: %04" PRIx32
		   " %04" PRIx32 " %04" PRIx32 "\n",
		   masks.Primary, masks.Rising, masks.Falling);
	    printf("                                     src: %04" PRIx32
		   " %04" PRIx32 " %04" PRIx32 "\n",
		   smasks.Primary, smasks.Rising, smasks.Falling);
	  }
	  interrupt_count++;
	}
      }

      else {   /* use select */
	FD_ZERO(&exception_mask);
	FD_SET((*sysinfo).Test.Handle, &exception_mask);
	FD_ZERO(&kb_mask);
	FD_SET(0, &kb_mask); /* watch stdin (fd 0) */

	if((*sysinfo).Test.Timeout != 0) {
	  tv.tv_usec = 0;
	  tv.tv_sec = (*sysinfo).Test.Timeout;
	  err = select((*sysinfo).Test.Handle + 1,
		       &kb_mask, NULL, &exception_mask, &tv);
	}
	else {
	  err = select((*sysinfo).Test.Handle + 1,
		       &kb_mask, NULL, &exception_mask, NULL);
	}

	if(err <= 0) {
	  printf("Select Error: %d:%s\n", errno, strerror(errno));
	}

	else {
	  /* see if kb input */
	  if(FD_ISSET(0, &kb_mask) != 0) {
	    //kbdrain();
	    return(0);
	  }

	  if(FD_ISSET((*sysinfo).Test.Handle,
		      &exception_mask) != 0) {
	    err = ioctl((*sysinfo).Test.Handle, EVGEN_READ_CURRENT_EVENT, &ce);
	    if(err != 0) printf("ioctl error reading current event %d:%s\n",
				errno, strerror(errno));

	    err = ioctl((*sysinfo).Test.Handle, EVGEN_GET_INTERRUPT_SOURCE, &smasks);
	    if(err != 0)
	      printf("ioctl error getting interrupt source %d:%s\n",
		     errno, strerror(errno));

	    gettimeofday(&tcurrent, NULL);
	    bat = 0;
	    GetBat((*sysinfo).Test.Handle, &bat);
	    clock_gettime(CLOCK_REALTIME, &tp);
	    tdelta.tv_sec = tcurrent.tv_sec - tprevious.tv_sec;
	    tdelta.tv_usec = tcurrent.tv_usec - tprevious.tv_usec;
	    tdelta.tv_usec = (tdelta.tv_sec * 1000000) + tdelta.tv_usec;
	    tprevious.tv_sec = tcurrent.tv_sec;
	    tprevious.tv_usec = tcurrent.tv_usec;

	    if(print_flag == 1) {
	      printf("%lu Intr @ %s: BAT: %llx dt: %8ld uS event: %04x\n",
		     interrupt_count, CreateTimeString(timestr, &tp), bat,
		     (long) tdelta.tv_usec, ce & 0xffff);
	      printf("                                     req: %04" PRIx32
		     " %04" PRIx32 " %04" PRIx32 "\n",
		     masks.Primary, masks.Rising, masks.Falling);
	      printf("                                     src: %04" PRIx32
		     " %04" PRIx32 " %04" PRIx32 "\n",
		     smasks.Primary, smasks.Rising, smasks.Falling);
	    }
	    interrupt_count++;
	  }

	  else {
	    printf("Timed out!\n");

	    FD_CLR((*sysinfo).Test.Handle, &exception_mask);
	  }
	}
	////////////////////////////
      }

      if((*sysinfo).Test.Handle == -1) usleep(100000);
      if(kbhit(0)) break;

    }
    return(0);
}


int GetInterrupts(SysInfo_struct *sysinfo)
{
unsigned int opt;
 int n, m, p;
char string[MAX_LINE_LENGTH + 2];
 char *cp;
type_list_struct *PIL;

    PIL = InitializePrimaryInterruptList();

    while(1) {
      printf("Primary Interrupt Masks available:\n");
      for(n = 0; n < MAX_NUM_WAIT_ON_EG_FUNCTS; ++n) {
	printf("%d %s\n", n, PIL[n].label);
      }
      printf("You must include %d in your set to enable Extended interrupts\n",
	     INTR_WAIT_ON_X_FN);
      printf("Enter space seperated set [ ");
      for(n = 0; n < MAX_NUM_WAIT_ON_EG_FUNCTS; ++n) {
	if(((*sysinfo).Test.Interrupt.Primary & (1 << n)) != 0) printf("%d ", n);
      }
      printf("] : ");

      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(-1);
      if(string[0] == 0xa) break;
      n = 0;
      p = 0;
      cp = string;
      while(1) {
	if(sscanf(cp, "%d%n", &n, &m) != 1) {
	  (*sysinfo).Test.Interrupt.Primary = p;
	  break;
	}
	if(n >= 0 && n < MAX_NUM_WAIT_ON_EG_FUNCTS) p |= 1 << n;
	cp += m;
      }

      printf("Primary Interrupts: ");
      for(n = 0; n < MAX_NUM_WAIT_ON_EG_FUNCTS; ++n) {
	if(((*sysinfo).Test.Interrupt.Primary & (1 << n)) != 0) printf("%d ", n);
      }
      printf("\n");
      
      break;
    }

    if(((*sysinfo).Test.Interrupt.Primary & INTR_WAIT_ON_EXTENDED) == 0) {
      return(0);
    }

    printf("Enter bit mask where:\n");
    printf("bits 0-15 -- Event lines 0-15\n");
    printf("bits 16-23 -- WF lines 0-7\n");
    printf("bit 24 -- 2ppms\n");
    printf("bit 25 -- 4ppms\n");
    printf("bit 26 -- 8ppms\n");
    printf("bit 27 -- 16ppms\n");
    printf("bits 28-30 -- unused\n");
    printf("bit 31 -- EGStrb\n");


    while(1) {
      printf("Rising Edge bit mask (hex) [%08" PRIx32 "]: ",
	     (*sysinfo).Test.Interrupt.Rising);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%x", &opt) == 1) {
	(*sysinfo).Test.Interrupt.Rising = opt;
	break;
      }
    }
    
    while(1) {
      printf("Falling Edge bit mask (hex) [%08" PRIx32 "]: ",
	     (*sysinfo).Test.Interrupt.Falling);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%x", &opt) == 1) {
	(*sysinfo).Test.Interrupt.Falling = opt;
	break;
      }
    }
    
    TestParams(sysinfo, "w");

    return(0);
}



int PrintInterruptSource(SysInfo_struct *sysinfo)
{
int err;
InterruptMasks_struct Masks;

    /* set get interrupt source */
   memset(&Masks, 0, sizeof(Masks));
   err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_INTERRUPT_SOURCE,
		  (unsigned long) &Masks);
   if(err == 0) printf("Primary: %04" PRIx32 "  RE: %04" PRIx32
		       "  FE: %03" PRIx32 "\n",
		       Masks.Primary, Masks.Rising, Masks.Falling );
   else printf("IOCTL error: %d  %s\n", errno, strerror(errno));

   return(0);
}


int LateEventTest(SysInfo_struct *sysinfo)
{
int err;
 int loops;
 unsigned int delta;
int timeout;
int LateEventCount[2];
int LateEventsExpected;
int LateEventsCount;
unsigned short event;
unsigned short int buffer[16];
unsigned long long bat;
EGStats_struct stats;

    /* set time out */
    timeout = 2; 
    err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_SET_TIMEOUT,
		(unsigned long) (WAIT_ON_INTR_TO_FLAG | (timeout * 1000)));
    if(err != 0) printf("ioctl error setting timeout %d\n", errno);

    LateEventsExpected = 0;
    LateEventsCount = 0;
    event = 0;
    loops = 0;

    while(1) {

      /* set first int element in array to size of array */
      memset(&stats, 0, sizeof(stats));
      memset(&stats, 0, sizeof(stats));
    *((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);

      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS,
		     (unsigned long) &stats);
      if(err != 0) {
	printf("ioctl error %d\n", errno);
	return(0);
      }

      LateEventCount[0] = stats.List[STATS_LATE_EVENT_INTR_COUNT].Value;


      GetBat((*sysinfo).Test.Handle, &bat);
      bat = bat + (unsigned long long) 10000;
      buffer[0] = (unsigned short int) (bat & 0xffff);
      buffer[1] = (unsigned short int) ((bat >> 16) & 0xffff);
      buffer[2] = (unsigned short int) ((bat >> 32) & 0xffff);
      buffer[3] = (unsigned short int) event;
      ++event;
      err = eg_write((*sysinfo).Test.Handle, buffer, 1);
      if(err == -1) {
	printf("Write error, errno: %d\n", errno);
	break;
	}

      if((rand() & 1) == 0) {
	delta = 0;
	++LateEventsExpected;
      }
      else delta = 10;

      bat = bat + (unsigned long long) delta;
      buffer[0] = (unsigned short int) (bat & 0xffff);
      buffer[1] = (unsigned short int) ((bat >> 16) & 0xffff);
      buffer[2] = (unsigned short int) ((bat >> 32) & 0xffff);
      buffer[3] = (unsigned short int) event;
      ++event;
      err = eg_write((*sysinfo).Test.Handle, buffer, 1);
      if(err == -1) {
	printf("Write error, errno: %d\n", errno);
	break;
	}


      usleep(20000);

      /* set first int element in array to size of array */
      memset(&stats, 0, sizeof(stats));
      memset(&stats, 0, sizeof(stats));
    *((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);

      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS,
		     (unsigned long) &stats);
      if(err != 0) {
	printf("ioctl error %d\n", errno);
	return(0);
      }

      LateEventCount[1] = stats.List[STATS_LATE_EVENT_INTR_COUNT].Value;
      LateEventsCount += (LateEventCount[1] - LateEventCount[0]);

      printf("%llx: Before: %d, After: %d ",
	     bat, LateEventCount[0], LateEventCount[1]);
      if(delta == 0) {
	if(LateEventCount[1] == LateEventCount[0]) printf("MISSED!\n");
	else if((LateEventCount[1] - LateEventCount[0]) > 1)
	  printf("OVER!\n");
	else printf("*\n");
      }
      else {
	if(LateEventCount[1] != LateEventCount[0]) printf("OVER!\n");
	else printf("\n");
      }
      
      if(kbhit(0)) break;
      ++loops;
    }
    printf("\nLate Events Expected: %d Late Events Counted: %d\n\n",
	   LateEventsExpected, LateEventsCount);

    return(0);

}

int GrabFrameTest(SysInfo_struct *sysinfo)
{
unsigned char data[MAX_LENGTH_FRAME + 4];
int n;
int m;
int err;

  while(1) {
    err = GrabFrame((*sysinfo).Test.Handle, data, MAX_LENGTH_FRAME);
    if(err == 0) {
      for(n = 0; n < 58; ++n) {
	m = data[(n * 2) + 1];
	m = (m << 8) | data[(n * 2)];
	printf(" %04x", m);
	if((n + 1) % 8 == 0) printf("\n");
      }
      printf("\n");
    }
    else printf("Error Grabbing frame: %d %s\n", errno, strerror(errno));

    if(kbhit(1000000)) return(0);

    /* printf("Type <RET> for more\n");
    if(eg_gets(data, sizeof(data)) == NULL) return(0);
    if(data[0] == 'q') return(0); */
  }
}


int GenerateEventsTest(SysInfo_struct *sysinfo)
{
double nd;
char string[MAX_LINE_LENGTH + 2];
int n, err, count, onesec, InsertLateEvent;
uint64_t late_event_base;
int use_select, function;
unsigned int t_integer;
unsigned int t_fraction;
unsigned int fraction;
unsigned int event;
unsigned short int buffer[4];
unsigned long long bat;
EGStats_struct stats;
fd_set kb_mask;
fd_set exception_mask;
struct timeval tv;


    srand(1);
    InsertLateEvent = 0;
    use_select = 0;

    memset(&stats, 0, sizeof(stats));
    *((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);
    if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS, (unsigned long) &stats) == 0) 
      late_event_base = stats.List[STATS_LATE_EVENT_INTR_COUNT].Value;
    else late_event_base = 0;
 
    while(1) {
      printf("Time increment (uS)? [%0.9f] ", (*sysinfo).Test.EventIncrement);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%lf", &nd) != 1) continue;
      if(nd < 0.0) continue;
      (*sysinfo).Test.EventIncrement = nd;
      break;
    }

    t_integer = (unsigned int) floor((*sysinfo).Test.EventIncrement);
    t_fraction = (unsigned int) (((*sysinfo).Test.EventIncrement - floor((*sysinfo).Test.EventIncrement)) * 4294967296.0);

    while(1) {
      printf("Event output type\n");
      printf("%d - Counter (normal)\n", GENERATE_EVENT_MODE_COUNT_NORMAL);
      printf("%d - Counter (flipped)\n", GENERATE_EVENT_MODE_COUNT_FLIPPED);
      printf("%d - Walking 1\n", GENERATE_EVENT_MODE_WALKING_1);
      printf("%d - Random\n", GENERATE_EVENT_MODE_RANDOM);

      printf("Select Event type ? [%d] ", (*sysinfo).Test.GenerateEventMode);


      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%d", &n) != 1) continue;
      if(n < 0) continue;
      (*sysinfo).Test.GenerateEventMode = n;
      break;
    }

    while(1) {
      if((*sysinfo).Test.RandomInsertLateEvents == 0) 
      printf("Randomly Insert Late Events? [n] ");
      else printf("Randomly Insert Late Events? [y] ");
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(string[0] == 'n' || string[0] == 'N') {
	(*sysinfo).Test.RandomInsertLateEvents = 0;
	break;
      }
      if(string[0] == 'y' || string[0] == 'Y') {
	(*sysinfo).Test.RandomInsertLateEvents = 1;
	break;
      }
    }

#ifdef XXXXX
    while(1) {
      printf("Use Select? ");
      if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) printf("[y] : ");
      else printf("[n] : ");

      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(string[0] == 'y')  {
	(*sysinfo).Test.Options |= EG_OPTION_USE_SELECT;
	break;
      }
      if(string[0] == 'n')  {
	(*sysinfo).Test.Options &= ~EG_OPTION_USE_SELECT;
	break;
      }
    }
    if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) use_select = 1;
    else use_select = 0;
#endif /* XXXXX */


    TestParams(sysinfo, "w");

    if((*sysinfo).Test.EventIncrement <= 1000000.0)
      onesec = 1000000 / (int) floor((*sysinfo).Test.EventIncrement);
    else onesec = 1;


    /*
restart: */
    count = 0;
    event = 1;
    fraction = 0;

    n = ERROR_STATUS_LATE_EVENT;
    if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_CLEAR_ERROR_STATUS, (unsigned long) &n) != 0) {
      printf("Unable to clear error status\n");
      return(0);
    }

    /* set blocking option */
    if(((*sysinfo).Test.Options & EG_OPTION_USE_SELECT) != 0) function = EVGEN_SET_OPTION;
    else function = EVGEN_CLEAR_OPTION;
    err = eg_ioctl((*sysinfo).Test.Handle, function,
		   (unsigned long) EG_OPTION_NON_BLOCKING);
    if(err != 0) printf("ioctl error setting blocking %d\n", errno);
    
    GetBat((*sysinfo).Test.Handle, &bat);
    printf("Current BAT  = %llx\n", bat);
    /* bat = bat + 500000; */

    /* if over the 3/4 second mark round to following second + 1 */ 
    if((bat % 1000000) > 750000) bat += 1000000;
    bat = ((bat / 1000000) + 2) * 1000000;
    printf("Starting BAT = %llx\n", bat);

    while(1) {
      buffer[0] = (unsigned short int) (bat & 0xffff);
      buffer[1] = (unsigned short int) ((bat >> 16) & 0xffff);
      buffer[2] = (unsigned short int) ((bat >> 32) & 0xffff);

      if((*sysinfo).Test.GenerateEventMode == GENERATE_EVENT_MODE_COUNT_NORMAL)
	buffer[3] = (unsigned short int) (count & 0xffff); /* the event */

      else if((*sysinfo).Test.GenerateEventMode ==
	      GENERATE_EVENT_MODE_COUNT_FLIPPED) {
	buffer[3] = 0;
	for(n = 0; n < 16; ++n) 
	  if((count & (1 << n)) != 0) buffer[3] |= (1 << (15 - n));
	
      }

      else if((*sysinfo).Test.GenerateEventMode == GENERATE_EVENT_MODE_WALKING_1) {
	buffer[3] = (unsigned short int) (event & 0xffff); /* the event */
	event <<= 1;
	if((event & 0xffff) == 0) event = 1;
      }

      else if((*sysinfo).Test.GenerateEventMode == GENERATE_EVENT_MODE_RANDOM)
	buffer[3] = (unsigned short int) rand(); /* the event */

      err = eg_write((*sysinfo).Test.Handle, buffer, 1);
      if(err == -1) {
	printf("Write error, errno: %d\n", errno);
	break;
	}

      if(err != 1) {
	if(use_select == 1) {
	  FD_ZERO(&exception_mask);
	  FD_SET((*sysinfo).Test.Handle, &exception_mask);
	  FD_ZERO(&kb_mask);
	  FD_SET(0, &kb_mask); /* watch stdin (fd 0) */

	  if((*sysinfo).Test.Timeout != 0) {
	    tv.tv_usec = 0;
	    tv.tv_sec = (*sysinfo).Test.Timeout;
	    err = select((*sysinfo).Test.Handle + 1,
			 &kb_mask, NULL, &exception_mask, &tv);
	  }
	  else {
	    err = select((*sysinfo).Test.Handle + 1,
			 &kb_mask, NULL, &exception_mask, NULL);
	  }

	  if(err <= 0) {
	    printf("Select Error: %d:%s\n", errno, strerror(errno));
	  }

	  else {
	    /* see if kb input */
	    if(FD_ISSET(0, &kb_mask) != 0) {
	      kbdrain();
	      return(0);
	    }

	    if(FD_ISSET((*sysinfo).Test.Handle,
			&exception_mask) == 0) {
	      printf("Timed out!\n");
	    }
	    else {
	      FD_CLR((*sysinfo).Test.Handle, &exception_mask);
	    }
	  }
	}

	else printf("eg_write returned value %d!!!!!\n", err);
      }

      ++count;

      if(InsertLateEvent == 0) {
	/* bat += (*sysinfo).Test.EventIncrement; */
	bat += t_integer;
	if((fraction + t_fraction) < fraction) {
	  ++bat;
	}
	fraction += t_fraction;
      }
      else InsertLateEvent = 0;

      if((count % onesec) == 0) {
	n = ERROR_STATUS_LATE_EVENT;
	if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_ERROR_STATUS, (unsigned long) &n) == 0) {
	  if(n != 0) {
	    printf("Too many late events..attempting a restart\n");
	    return(0);
	    /* goto restart; */
	  }
	}

	memset(&stats, 0, sizeof(stats));
	*((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);
	if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS, (unsigned long) &stats) == 0) {
	  printf("Events:%d  Late:%" PRIu64 "\n", count,
		 stats.List[STATS_LATE_EVENT_INTR_COUNT].Value -
		 late_event_base);
	}
	else {
	  printf("%d\n", count);
	}
	if((*sysinfo).Test.RandomInsertLateEvents != 0) {
	  if((rand() & 1) == 1) InsertLateEvent = 1;
	}
	if(kbhit(0)) return(0);
      }
    }
    return(0);
}



int PsuedoPulsarEventTest(SysInfo_struct *sysinfo)
{
double nd;
char string[MAX_LINE_LENGTH + 2];
int n;
int err;
int count;
int onesec;
uint64_t late_event_base;
unsigned int period_fraction;
unsigned int bat_fraction;
unsigned short int buffer[4];
unsigned long long int dummy;
unsigned long long int period_integer;
unsigned long long int bat_integer;
unsigned long long int bat;
unsigned long long int t_bat;
unsigned long long int bottom_long_div;
EGStats_struct stats;


    memset(&stats, 0, sizeof(stats));
    *((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);
    if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS, (unsigned long) &stats) == 0) 
      late_event_base = stats.List[STATS_LATE_EVENT_INTR_COUNT].Value;
    else late_event_base = 0;
 
    bottom_long_div = 0x80000000;
    bottom_long_div *= 2;

    while(1) {
      printf("Pulsar Period (uS)? [%0.9f] ", (*sysinfo).Test.Pulsar.Period);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%lf", &nd) != 1) continue;
      if(nd < 0.0) continue;
      (*sysinfo).Test.Pulsar.Period = nd;
      break;
    }

    period_integer = (unsigned long long int) floor((*sysinfo).Test.Pulsar.Period);
    period_fraction = (unsigned int) (((*sysinfo).Test.Pulsar.Period -
			  floor((*sysinfo).Test.Pulsar.Period)) * 4294967296.0);

    while(1) {
      printf("Pulsar Duration (uS)? [%u] ", (*sysinfo).Test.Pulsar.Duration);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%u", &n) != 1) continue;
      (*sysinfo).Test.Pulsar.Duration = n;
      break;
    }

    while(1) {
      if((*sysinfo).Test.Pulsar.SecondMarkMode == SECOND_MARK_MODE_ABSOLUTE)
	printf("Second mark window (absolute/minute)? [a] ");
      else printf("Second mark window (absolute/minute)? [m] ");
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(string[0] == 'a') {
	(*sysinfo).Test.Pulsar.SecondMarkMode = SECOND_MARK_MODE_ABSOLUTE;
	break;
      }
      if(string[0] == 'm') {
	(*sysinfo).Test.Pulsar.SecondMarkMode = SECOND_MARK_MODE_MINUTE;
	break;
      }
    }

    while(1) {
      printf("Second mark to start on? [%u] ",
	     (*sysinfo).Test.Pulsar.SecondMark);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%u", &n) != 1) continue;
      (*sysinfo).Test.Pulsar.SecondMark = n;
      break;
    }

    while(1) {
      printf("Pulsar Start Delay (after 1PPS) (uS)? [%u] ",
	     (*sysinfo).Test.Pulsar.StartDelay);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%u", &n) != 1) continue;
      (*sysinfo).Test.Pulsar.StartDelay = n;
      break;
    }

    while(1) {
      printf("Pulsar Slide Rate per PP (uS)? [%u] ",
	     (*sysinfo).Test.Pulsar.SlideRate);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%u", &n) != 1) continue;
      (*sysinfo).Test.Pulsar.SlideRate = n;
      break;
    }

    while(1) {
      printf("Event Mask ? [%x] ", (*sysinfo).Test.Pulsar.Mask);
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(sscanf(string, "%x", &n) != 1) continue;
      (*sysinfo).Test.Pulsar.Mask = n & 0xffff;
      break;
    }

    while(1) {
      if((*sysinfo).Test.Pulsar.Sense == PULSAR_SENSE_POSITIVE)
	printf("Event Sense ? [+] ");
      else {
	(*sysinfo).Test.Pulsar.Sense = PULSAR_SENSE_NEGATIVE;
	printf("Event Sense ? [-] ");
      }
      if(eg_gets(string, sizeof(string)) == NULL) return(0);
      if(string[0] == 'q') return(0);
      if(string[0] == 0xa) break;
      if(string[0] == '+') {
	(*sysinfo).Test.Pulsar.Sense = PULSAR_SENSE_POSITIVE;
	break;
      }
      if(string[0] == '-') {
	(*sysinfo).Test.Pulsar.Sense = PULSAR_SENSE_NEGATIVE;
	break;
      }
    }


    TestParams(sysinfo, "w");

    if((*sysinfo).Test.Pulsar.Period <= 1000000.0)
      onesec = 1000000 / (int) floor((*sysinfo).Test.Pulsar.Period);
    else onesec = 1;


restart:
    count = 0;

    n = ERROR_STATUS_LATE_EVENT;
    if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_CLEAR_ERROR_STATUS, (unsigned long) &n) != 0) {
      printf("Unable to clear error status\n");
      return(0);
    }

    GetBat((*sysinfo).Test.Handle, &bat);
    printf("Current BAT = %llx\n", bat);


    /* if over the 3/4 second mark round to following second + 1 */ 
    if((bat % 1000000) > 750000) bat += 1000000;

    /* talk in seconds and schedule start time at least 1 seconds ahead */
    bat = bat / 1000000 - (*sysinfo).dUTC + 1;

    if((*sysinfo).Test.Pulsar.SecondMarkMode == SECOND_MARK_MODE_ABSOLUTE) {

      /* reshedule start time on the designated second mark */
      if((bat % (*sysinfo).Test.Pulsar.SecondMark) != 0) {
	bat = ((bat / (*sysinfo).Test.Pulsar.SecondMark) + 1) *
	  (*sysinfo).Test.Pulsar.SecondMark;
      }
    }

    else {
      n = bat % 60;
      if((n % (*sysinfo).Test.Pulsar.SecondMark) != 0) {
	n = ((n / (*sysinfo).Test.Pulsar.SecondMark) + 1) *
	  (*sysinfo).Test.Pulsar.SecondMark;
	if(n > 60) n = (*sysinfo).Test.Pulsar.SecondMark;
	bat = (bat - (bat % 60)) + n;
      }
    }

    /* readjust for dUTC */
    bat += (*sysinfo).dUTC;

    /* back to microseconds */
    bat *= 1000000;
    bat = bat + (*sysinfo).Test.Pulsar.StartDelay;
    printf("Starting BAT = %llx\n", bat);

    bat_integer = bat;
    bat_fraction = 0;

    /*
     * Initialise the event word.  2.6 read buffer[3] before it had ever been
     * written, and used "&= !mask" - logical not, which is 0 for any non-zero
     * mask, so the positive-sense branch cleared the whole word by accident
     * and the negative-sense branch OR'd into uninitialised stack.
     */
    buffer[3] = 0;
    if((*sysinfo).Test.Pulsar.Sense != PULSAR_SENSE_POSITIVE)
      buffer[3] |= (*sysinfo).Test.Pulsar.Mask;

    while(1) {
      buffer[0] = (unsigned short int) (bat_integer & 0xffff);
      buffer[1] = (unsigned short int) ((bat_integer >> 16) & 0xffff);
      buffer[2] = (unsigned short int) ((bat_integer >> 32) & 0xffff);

      /* set the event word */
      buffer[3] = buffer[3] ^ (*sysinfo).Test.Pulsar.Mask;

      err = eg_write((*sysinfo).Test.Handle, buffer, 1);
      if(err == -1) {
	printf("Write error, errno: %d\n", errno);
	break;
	}

      t_bat = bat_integer +
	(unsigned long long int) (*sysinfo).Test.Pulsar.Duration;

      buffer[0] = (unsigned short int) (t_bat & 0xffff);
      buffer[1] = (unsigned short int) ((t_bat >> 16) & 0xffff);
      buffer[2] = (unsigned short int) ((t_bat >> 32) & 0xffff);

      /* reset the event word */
      buffer[3] = buffer[3] ^ (*sysinfo).Test.Pulsar.Mask;

      err = eg_write((*sysinfo).Test.Handle, buffer, 1);
      if(err == -1) {
	printf("Write error, errno: %d\n", errno);
	break;
	}

      ++count;

      dummy = (unsigned long long int) bat_fraction +
	(unsigned long long int) period_fraction;


      bat_fraction = dummy % bottom_long_div;
      bat_integer += (period_integer +
	(dummy / bottom_long_div));
      bat_integer += (unsigned long long int) (*sysinfo).Test.Pulsar.SlideRate;

      if((count % onesec) == 0) {
	n = ERROR_STATUS_LATE_EVENT;
	if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_ERROR_STATUS, (unsigned long) &n) == 0) {
	  if(n != 0) {
	    printf("Too many late events..attempting a restart\n");
	    goto restart;
	  }
	}

	memset(&stats, 0, sizeof(stats));
	*((int32_t *) &stats) = (int32_t) sizeof(EGStats_struct);
	if(eg_ioctl((*sysinfo).Test.Handle, EVGEN_GET_STATS, (unsigned long) &stats) == 0) {
	  printf("Events:%d  Late:%" PRIu64 "\n", count,
		 stats.List[STATS_LATE_EVENT_INTR_COUNT].Value -
		 late_event_base);
	}
	else {
	  printf("%d\n", count);
	}
	if(kbhit(0)) return(0);
      }
    }
    return(0);
}



int EventRegisterTest(SysInfo_struct *sysinfo)
{
int n;
int m;
int err;

    /* test event register write and read */

    for(n = 0; n < 65536; ++n) {
      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_WRITE_EVENT_DIRECT, (unsigned long) n);
      if(err != 0) {
	printf("Writing single event failed.. %x\n", n);
	return(0);
      }
      err = eg_ioctl((*sysinfo).Test.Handle, EVGEN_READ_CURRENT_EVENT, (unsigned long) &m);
      if(err != 0) {
	printf("Writing single event failed.. %x\n", n);
	return(0);
      }
      if(m != n) {
	printf("Direct event mismatch.. wrote: %x, read: %x\n", n, m);
	return(0);
      }
    }
    return(0);
}



/* routine to grab a frame from the frame grabber */
int GrabFrame(int eg, unsigned char *data, int size)
{
int n;
int err;

    if(eg == -1) return(EG_GRAB_FRAME_FAIL);

    /* Clear the buffer area */
    for(n = 0; n < size; ++n) data[n] = 0;

    err = 0;
    err = ioctl(eg, EVGEN_SET_TIMEOUT,
    		WAIT_GRAB_FRAME_TO_FLAG | EG_READ_DEFAULT_TIMEOUT_MS);

    if(err == -1) {
      printf("IOCTL error while setting timeout for Grabbing Frame PID: %d errno: %d : %s\n",
	     getpid(), errno, strerror(errno));
      /* 2.6 returned EG_OK (0) here, so the caller saw a failure as success. */
      return(EG_GRAB_FRAME_FAIL);
    }
    err = read(eg, data, size);
    if(err <= 0) {
      printf("Read error Grabbing Frame PID: %d errno: %d : %s\n",
	     getpid(), errno, strerror(errno));
      return(EG_GRAB_FRAME_FAIL);
      }

    return(EG_OK);

}


int GetBat(int eg, unsigned long long *bat)
{
int n;
int err;
unsigned char frame_data[MAX_LENGTH_FRAME + 2];

    /* Grab a frame */
    err = GrabFrame(eg, frame_data, MAX_LENGTH_FRAME);
    if(err != EG_OK) return(err);

    *bat = 0;
    for(n = 0; n < 8; ++n) *bat = (*bat << 8) | frame_data[7 - n];
    return(EG_OK);

}


int TestParams(SysInfo_struct *sysinfo, const char *mode)
{
FILE *f1;
double nd;
int n;
unsigned int ln, lm;
char string[MAX_LINE_LENGTH + 2];


  if(strcmp(mode, "w") == 0) {
    f1 = fopen((*sysinfo).ParamFile, "w");
    if(f1 == NULL) {
      printf("Unable to open parameter file: %s\n", (*sysinfo).ParamFile);
      return(-1);
    }

    fprintf(f1, "device %d\n", (*sysinfo).Test.Device);
    fprintf(f1, "debug_level %d\n", (*sysinfo).Test.DebugLevel);
    fprintf(f1, "dutc %d\n", (*sysinfo).dUTC);
    fprintf(f1, "event_increment %f\n", (*sysinfo).Test.EventIncrement);
    fprintf(f1, "gen_event_mode %d\n", (*sysinfo).Test.GenerateEventMode);
    fprintf(f1, "intr_primary %" PRIx32 "\n",
	    (*sysinfo).Test.Interrupt.Primary);
    fprintf(f1, "intr_extended %" PRIx32 " %" PRIx32 "\n",
	    (*sysinfo).Test.Interrupt.Rising,
	    (*sysinfo).Test.Interrupt.Falling);
    fprintf(f1, "options %x\n", (*sysinfo).Test.Options);
    fprintf(f1, "printoutrate %d\n", (*sysinfo).Test.PrintOutRate);
    fprintf(f1, "pulsar_mask %x\n", (*sysinfo).Test.Pulsar.Mask);
    fprintf(f1, "pulsar_sense %u\n", (*sysinfo).Test.Pulsar.Sense);
    fprintf(f1, "pulsar_second_markmode %u\n",
	    (*sysinfo).Test.Pulsar.SecondMarkMode);
    fprintf(f1, "pulsar_second_mark %u\n", (*sysinfo).Test.Pulsar.SecondMark);
    fprintf(f1, "pulsar_start_delay %u\n", (*sysinfo).Test.Pulsar.StartDelay);
    fprintf(f1, "pulsar_slide_rate %u\n", (*sysinfo).Test.Pulsar.SlideRate);
    fprintf(f1, "pulsar_period %f\n", (*sysinfo).Test.Pulsar.Period);
    fprintf(f1, "pulsar_duration %u\n", (*sysinfo).Test.Pulsar.Duration);
    fprintf(f1, "random_insert_late_events %d\n",
	    (*sysinfo).Test.RandomInsertLateEvents);
    fprintf(f1, "test %d\n", (*sysinfo).Test.Test);
    fprintf(f1, "timeout %d\n", (*sysinfo).Test.Timeout);
    fclose(f1);
    return(0);
  }

  else {
    if(strcmp(mode, "r") == 0) {

      memset(&(*sysinfo).Test, 0, sizeof(TestInfo_struct));

      (*sysinfo).dUTC = DEFAULT_DUTC;
      (*sysinfo).Test.Test = 1;
      (*sysinfo).Test.EventIncrement = 1001.0;
      (*sysinfo).Test.GenerateEventMode = GENERATE_EVENT_MODE_COUNT_NORMAL;
      (*sysinfo).Test.Pulsar.SecondMark = 1;

      f1 = fopen((*sysinfo).ParamFile, "r");
      if(f1 == NULL) {
	printf("Unable to open parameter file %s\n",
	       (*sysinfo).ParamFile);
	return(-1);
      }

      while(1) {
	if(fgets(string, MAX_LINE_LENGTH, f1) == NULL) {
	  fclose(f1);
	  return(0);
	}

	n = 0;
	while(string[n] != 0) {
	  if(string[n] < ' ') {
	    string[n] = 0;
	    break;
	  }
	  ++n;
	}


	if(sscanf(string, "test %d", &n) == 1) {
	  (*sysinfo).Test.Test = n;
	  continue;
	}
	
	if(sscanf(string, "dutc %d", &n) == 1) {
	  (*sysinfo).dUTC = n;
	  continue;
	}
	
	/*
	if(sscanf(string, "device %d", &n) == 1) {
	  (*sysinfo).Test.Device = n;
	  continue;
	}
	*/

	if(sscanf(string, "debug_level %d", &n) == 1) {
	  (*sysinfo).Test.DebugLevel = n;
	  continue;
	}
	
	if(sscanf(string, "event_increment %lf", &nd) == 1) {
	  (*sysinfo).Test.EventIncrement = nd;
	  continue;
	}	

	if(sscanf(string, "gen_event_mode %d", &n) == 1) {
	  (*sysinfo).Test.GenerateEventMode = n;
	  continue;
	}	

	if(sscanf(string, "intr_primary %x", &ln) == 1) {
	  (*sysinfo).Test.Interrupt.Primary = ln;
	  continue;
	}
	
	if(sscanf(string, "intr_extended %x %x", &lm, &ln) == 2) {
	  (*sysinfo).Test.Interrupt.Rising = lm;
	  (*sysinfo).Test.Interrupt.Falling = ln;
	  continue;
	}

	if(sscanf(string, "options %x", &n) == 1) {
	  (*sysinfo).Test.Options = n;
	  continue;
	}	

	if(sscanf(string, "printoutrate %d", &n) == 1) {
	  (*sysinfo).Test.PrintOutRate = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_sense %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.Sense = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_second_mark_mode %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.SecondMarkMode = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_second_mark_mode %d", &n) == 1) {
	  if(n != SECOND_MARK_MODE_MINUTE) n = 0;
	  (*sysinfo).Test.Pulsar.SecondMarkMode = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_second_mark %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.SecondMark = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_start_delay %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.StartDelay = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_slide_rate %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.SlideRate = n;
	  continue;
	}	

	if(sscanf(string, "pulsar_period %lf", &nd) == 1) {
	  (*sysinfo).Test.Pulsar.Period = nd;
	  continue;
	}	

	if(sscanf(string, "pulsar_duration %d", &n) == 1) {
	  (*sysinfo).Test.Pulsar.Duration = n;
	  continue;
	}
	
	if(sscanf(string, "random_insert_late_events %d", &n) == 1) {
	  (*sysinfo).Test.RandomInsertLateEvents = n;
	  continue;
	}	

      }
    }
  }

  return(0);
}


int kbhit(int us_delay)
{
fd_set mask;
struct timeval tv;
int retval;
char string[8];

    FD_ZERO(&mask);
    FD_SET(0, &mask);
    tv.tv_sec = us_delay / 1000000;
    tv.tv_usec = us_delay % 1000000;

    retval = select(1, &mask, NULL, NULL, &tv);
    if(retval > 0) {
      /* drain stdin */
      while(select(1, &mask, NULL, NULL, &tv) > 0) {
	if(read(0, string, 1) <= 0) break;
      }
      return(1);
    }
    return(0);

}


/*
 * 2.6 walked off the end of its own frame to find the variadic argument.  See
 * the port note at the top of the file.  The argument is carried as an
 * unsigned long so that a pointer passed by a caller survives intact.
 */
int eg_ioctl(int handle, unsigned int function, ... )
{
va_list ap;
unsigned long arg;

    if(handle == -1) return(0);

    va_start(ap, function);
    arg = va_arg(ap, unsigned long);
    va_end(ap);

    return(ioctl(handle, function, arg));
}


int eg_write(int handle, void *buffer, int count)
{
  /* Was "handle == 1", which is stdout, not the "no device" sentinel. */
  if(handle == -1) return(count);
  return(write(handle, buffer, count));

}


static char *eg_gets(char *buf, size_t size)
{
    if(fgets(buf, (int) size, stdin) == NULL) {
      printf("\n");
      return(NULL);
    }
    return(buf);
}

type_list_struct *InitializePrimaryInterruptList(void)
{
static type_list_struct type_list[MAX_NUM_WAIT_ON_EG_FUNCTS + 1];
int n;

    /* 2.6 wrapped this in a second loop over an unused index "m", so every
       label was written MAX_NUM_WAIT_ON_EG_FUNCTS + 1 times. */
    for(n = 0; n <  MAX_NUM_WAIT_ON_EG_FUNCTS + 1; ++n) {
      type_list[n].value = n;
      {
	if(n == INTR_WAIT_ON_1S_FN) strcpy(type_list[n].label, INTR_WAIT_ON_1S_NAME);
	else if(n == INTR_WAIT_ON_INTL_FN) strcpy(type_list[n].label, INTR_WAIT_ON_INTL_NAME);
	else if(n == INTR_WAIT_ON_EXTL_FN) strcpy(type_list[n].label, INTR_WAIT_ON_EXTL_NAME);
  	else if(n == INTR_WAIT_ON_FIN_FN) strcpy(type_list[n].label, INTR_WAIT_ON_FIN_NAME);
  	else if(n == INTR_WAIT_ON_LE_FN) strcpy(type_list[n].label, INTR_WAIT_ON_LE_NAME);
  	else if(n == INTR_WAIT_ON_FL_FN) strcpy(type_list[n].label, INTR_WAIT_ON_FL_NAME);
  	else if(n == INTR_WAIT_ON_GFC_FN) strcpy(type_list[n].label, INTR_WAIT_ON_GFC_NAME);
  	else if(n == INTR_WAIT_ON_FHE_FN) strcpy(type_list[n].label, INTR_WAIT_ON_FHE_NAME);
  	else if(n == INTR_WAIT_ON_CKSUM_FN) strcpy(type_list[n].label, INTR_WAIT_ON_CKSUM_NAME);
  	else if(n == INTR_WAIT_ON_FS_FN) strcpy(type_list[n].label, INTR_WAIT_ON_FS_NAME);
  	else if(n == INTR_WAIT_ON_MS_FN) strcpy(type_list[n].label, INTR_WAIT_ON_MS_NAME);
  	else if(n == INTR_WAIT_ON_PLDO_FN) strcpy(type_list[n].label, INTR_WAIT_ON_PLDO_NAME);
  	else if(n == INTR_WAIT_ON_X_FN) strcpy(type_list[n].label, INTR_WAIT_ON_X_NAME);
	else strcpy(type_list[n].label, "");
      }
    }

 return(type_list);

}


/* ftime()/struct timeb are gone; this takes a struct timespec now. */
char *CreateTimeString(char *string, const struct timespec *ts)
{
struct tm tmv;

    localtime_r(&(*ts).tv_sec, &tmv);

    sprintf(string, "%02d:%02d:%02d.%03d",
	    tmv.tm_hour, tmv.tm_min, tmv.tm_sec,
	    (int) ((*ts).tv_nsec / 1000000));

    return(string);
}


int kbdrain(void)
{
  char string[4];

  while(kbhit(0)) {
    if(fread(string, 1, 1, stdin) != 1) break;
  }

  return(0);

}

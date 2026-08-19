# Makefile for the CSIRO ATNF PC Event Generator (EG) PCI driver, Linux 6.8+.
#
# The 2.6 makefile built the module and the test program from one flat set of
# rules, hand-rolled the compiler flags (-O3 -fomit-frame-pointer for a kernel
# object, which kbuild owns), regenerated an "eg_date.h" containing the build
# date on every single build, and had an "install:" target that copied eg.o
# into a tftpboot directory.  All of that is gone.
#
#   make                build eg.ko against the running kernel
#   make test           build test_eg
#   make sparse         re-check the __iomem / __user annotations
#   sudo make install   module + udev rule into /lib/modules/<rel>/extra
#   sudo make load      insmod ./eg.ko           (PARAMS="debug=2" to add args)
#   sudo make unload

ifneq ($(KERNELRELEASE),)

# ---- kbuild pass ------------------------------------------------------------
obj-m		:= eg.o

ccflags-y	+= -Wall -Wextra -Wno-unused-parameter

else

# ---- command line pass ------------------------------------------------------
KVER		?= $(shell uname -r)
KERNELDIR	?= /lib/modules/$(KVER)/build
PWD		:= $(shell pwd)
MODDESTDIR	:= /lib/modules/$(KVER)/extra
BINDIR		?= /usr/local/bin
UDEVDIR		?= /etc/udev/rules.d
DOCDIR		?= /usr/local/share/doc/eg

CC		?= gcc
CFLAGS		?= -O2 -g -Wall -Wextra -Wno-unused-parameter
CPPFLAGS	+= -I.
LDLIBS		+= -lm

.PHONY: all modules test sparse clean install uninstall install-test load unload

# Only the module: DKMS invokes the default target in an environment where
# nothing is promised about the userspace toolchain.
all: modules

modules:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) modules

# Sparse checks the __user / __iomem annotations, of which the 2.6 driver had
# none at all.  Needs the "sparse" package.
sparse:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) C=2 CF="-D__CHECK_ENDIAN__" modules

test: test_eg

test_eg: test_eg.c eg_ioctl.h eg_struct.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ $< $(LDLIBS)

clean:
	$(MAKE) -C $(KERNELDIR) M=$(PWD) clean
	rm -f test_eg

install: modules
	install -d $(DESTDIR)$(MODDESTDIR)
	install -m 644 eg.ko $(DESTDIR)$(MODDESTDIR)
	install -d $(DESTDIR)$(UDEVDIR)
	install -m 644 99-eg.rules $(DESTDIR)$(UDEVDIR)/
	install -d $(DESTDIR)$(DOCDIR)
	install -m 644 README.md $(DESTDIR)$(DOCDIR)/
	depmod -a $(KVER)
	@echo "Installed.  Load with 'modprobe eg' (see README.md section 2)."

uninstall:
	rm -f $(DESTDIR)$(MODDESTDIR)/eg.ko
	rm -f $(DESTDIR)$(UDEVDIR)/99-eg.rules
	rm -f $(DESTDIR)$(DOCDIR)/README.md
	depmod -a $(KVER)

install-test: test
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 test_eg $(DESTDIR)$(BINDIR)/
	install -m 755 egtest.sh $(DESTDIR)$(BINDIR)/

load:
	insmod ./eg.ko $(PARAMS)

unload:
	rmmod eg

endif

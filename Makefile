# xv6-plus Operating System Makefile
# Professional build system for xv6-plus

# Project directories
SRCDIR = src
KERNELDIR = $(SRCDIR)/kernel
USERDIR = $(SRCDIR)/user
BOOTDIR = $(SRCDIR)/boot
BUILDDIR = build
TOOLSDIR = tools
CONFIGDIR = config
DOCSDIR = docs

# Include directories
INCLUDES = -I$(KERNELDIR)/include

# Kernel object files organized by subsystem
KERNEL_CORE_OBJS = \
	$(BUILDDIR)/main.o \
	$(BUILDDIR)/trap.o \
	$(BUILDDIR)/trapasm.o \
	$(BUILDDIR)/syscall.o \
	$(BUILDDIR)/swtch.o \
	$(BUILDDIR)/vectors.o \
	$(BUILDDIR)/string.o \
	$(BUILDDIR)/ai_system.o \
	$(BUILDDIR)/ai_testgen.o \
	$(BUILDDIR)/ai_recovery.o \
	$(BUILDDIR)/ai_debug.o \
	$(BUILDDIR)/ai_syscall.o \
	$(BUILDDIR)/ai_quantum.o \
	$(BUILDDIR)/ai_impossible.o \
	$(BUILDDIR)/ai_hyperloop.o \
	$(BUILDDIR)/bpf.o \
	$(BUILDDIR)/bpf_jit.o \
	$(BUILDDIR)/bpf_map.o \
	$(BUILDDIR)/bpf_verify.o \
	$(BUILDDIR)/crash.o \
	$(BUILDDIR)/crash_log.o \
	$(BUILDDIR)/crash_analysis.o \
	$(BUILDDIR)/coredump.o \
	$(BUILDDIR)/clone_namespace.o \
	$(BUILDDIR)/cpuaffinity.o \
	$(BUILDDIR)/futex.o \
	$(BUILDDIR)/livepatch.o \
	$(BUILDDIR)/lp_manage.o \
	$(BUILDDIR)/lp_trace.o \
	$(BUILDDIR)/lp_detect.o \
	$(BUILDDIR)/rcu.o \
	$(BUILDDIR)/reclaim.o \
	$(BUILDDIR)/reclaim_logic.o \
	$(BUILDDIR)/rt.o \
	$(BUILDDIR)/rt_mutex.o \
	$(BUILDDIR)/rt_schedule.o \
	$(BUILDDIR)/seqlock.o \
	$(BUILDDIR)/smp.o \
	$(BUILDDIR)/stm.o \
	$(BUILDDIR)/syscontainer.o

KERNEL_PROC_OBJS = \
	$(BUILDDIR)/proc.o \
	$(BUILDDIR)/exec.o \
	$(BUILDDIR)/sysproc.o \
	$(BUILDDIR)/spinlock.o \
	$(BUILDDIR)/sleeplock.o

KERNEL_MM_OBJS = \
	$(BUILDDIR)/vm.o \
	$(BUILDDIR)/kalloc.o \
	$(BUILDDIR)/mmap.o \
	$(BUILDDIR)/cow.o

KERNEL_FS_OBJS = \
	$(BUILDDIR)/fs.o \
	$(BUILDDIR)/file.o \
	$(BUILDDIR)/sysfile.o \
	$(BUILDDIR)/bio.o \
	$(BUILDDIR)/ide.o \
	$(BUILDDIR)/log.o \
	$(BUILDDIR)/pipe.o

KERNEL_DRIVERS_OBJS = \
	$(BUILDDIR)/console.o \
	$(BUILDDIR)/uart.o \
	$(BUILDDIR)/kbd.o \
	$(BUILDDIR)/lapic.o \
	$(BUILDDIR)/ioapic.o \
	$(BUILDDIR)/mp.o \
	$(BUILDDIR)/picirq.o

KERNEL_SYSCALLS_OBJS = \
	$(BUILDDIR)/mmap_syscall.o \
	$(BUILDDIR)/crash_syscall.o \
	$(BUILDDIR)/lp_syscall.o \
	$(BUILDDIR)/reclaim_syscall.o \
	$(BUILDDIR)/stm_syscall.o \
	$(BUILDDIR)/rt_syscall.o

# All kernel objects
KERNEL_OBJS = $(KERNEL_CORE_OBJS) $(KERNEL_PROC_OBJS) $(KERNEL_MM_OBJS) $(KERNEL_FS_OBJS) $(KERNEL_DRIVERS_OBJS) $(KERNEL_SYSCALLS_OBJS)

# User programs
USER_PROGS = \
	$(BUILDDIR)/_init \
	$(BUILDDIR)/_sh \
	$(BUILDDIR)/_cat \
	$(BUILDDIR)/_echo \
	$(BUILDDIR)/_grep \
	$(BUILDDIR)/_kill \
	$(BUILDDIR)/_ln \
	$(BUILDDIR)/_ls \
	$(BUILDDIR)/_mkdir \
	$(BUILDDIR)/_rm \
	$(BUILDDIR)/_wc \
	$(BUILDDIR)/_forktest \
	$(BUILDDIR)/_stressfs \
	$(BUILDDIR)/_usertests \
	$(BUILDDIR)/_zombie

# Cross-compiling toolchain
ifeq ($(origin TOOLPREFIX), undefined)
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'make TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# QEMU emulator
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	elif which qemu-system-x86_64 > /dev/null; \
	then echo qemu-system-x86_64; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# Compiler and linker settings
CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump

CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer -Wno-array-bounds -Wno-infinite-recursion
CFLAGS += $(INCLUDES)
CFLAGS += -fno-stack-protector
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide
ASFLAGS += $(INCLUDES)
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)

# Create build directory
$(shell mkdir -p $(BUILDDIR))

# Default target
all: $(BUILDDIR)/xv6.img

# Kernel compilation rules
$(BUILDDIR)/%.o: $(KERNELDIR)/core/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/core/%.S
	$(CC) $(ASFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/proc/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/mm/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/fs/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/drivers/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/syscalls/%.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/%.o: $(KERNELDIR)/syscalls/%.S
	$(CC) $(ASFLAGS) -c -o $@ $<

# Boot loader
$(BUILDDIR)/bootblock: $(BOOTDIR)/bootasm.S $(BOOTDIR)/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -I$(KERNELDIR)/include -c $(BOOTDIR)/bootmain.c -o $(BUILDDIR)/bootmain.o
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I$(KERNELDIR)/include -c $(BOOTDIR)/bootasm.S -o $(BUILDDIR)/bootasm.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o $(BUILDDIR)/bootblock.o $(BUILDDIR)/bootasm.o $(BUILDDIR)/bootmain.o
	$(OBJDUMP) -S $(BUILDDIR)/bootblock.o > $(BUILDDIR)/bootblock.asm
	$(OBJCOPY) -S -O binary -j .text $(BUILDDIR)/bootblock.o $(BUILDDIR)/bootblock
	$(TOOLSDIR)/sign.pl $(BUILDDIR)/bootblock

# Entry code
$(BUILDDIR)/entryother: $(BOOTDIR)/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I$(KERNELDIR)/include -c $(BOOTDIR)/entryother.S -o $(BUILDDIR)/entryother.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o $(BUILDDIR)/bootblockother.o $(BUILDDIR)/entryother.o
	$(OBJCOPY) -S -O binary -j .text $(BUILDDIR)/bootblockother.o $(BUILDDIR)/entryother
	$(OBJDUMP) -S $(BUILDDIR)/bootblockother.o > $(BUILDDIR)/entryother.asm

# Init code
$(BUILDDIR)/initcode: $(BOOTDIR)/initcode.S
	$(CC) $(CFLAGS) -nostdinc -I$(KERNELDIR)/include -c $(BOOTDIR)/initcode.S -o $(BUILDDIR)/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $(BUILDDIR)/initcode.out $(BUILDDIR)/initcode.o
	$(OBJCOPY) -S -O binary $(BUILDDIR)/initcode.out $(BUILDDIR)/initcode
	$(OBJDUMP) -S $(BUILDDIR)/initcode.o > $(BUILDDIR)/initcode.asm

# Vectors
$(BUILDDIR)/vectors.S: $(KERNELDIR)/core/vectors.pl
	$(KERNELDIR)/core/vectors.pl > $(BUILDDIR)/vectors.S

$(BUILDDIR)/vectors.o: $(BUILDDIR)/vectors.S
	$(CC) $(ASFLAGS) -c $(BUILDDIR)/vectors.S -o $(BUILDDIR)/vectors.o

# Kernel
$(BUILDDIR)/kernel: $(KERNEL_OBJS) $(BUILDDIR)/entry.o $(BUILDDIR)/entryother $(BUILDDIR)/initcode $(CONFIGDIR)/kernel.ld
	cd $(BUILDDIR) && $(LD) $(LDFLAGS) -T ../$(CONFIGDIR)/kernel.ld -o kernel entry.o $(patsubst $(BUILDDIR)/%,%,$(KERNEL_OBJS)) -b binary initcode entryother
	$(OBJDUMP) -S $(BUILDDIR)/kernel > $(BUILDDIR)/kernel.asm
	$(OBJDUMP) -t $(BUILDDIR)/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILDDIR)/kernel.sym

# User library
$(BUILDDIR)/ulib.o: $(USERDIR)/lib/ulib.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/usys.o: $(KERNELDIR)/syscalls/usys.S
	$(CC) $(ASFLAGS) -c -o $@ $<

$(BUILDDIR)/printf.o: $(KERNELDIR)/core/printf.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/uprintf.o: $(KERNELDIR)/core/printf.c
	$(CC) $(CFLAGS) -c -o $@ $<

$(BUILDDIR)/umalloc.o: $(USERDIR)/lib/umalloc.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Programs that define their own printf
$(BUILDDIR)/_forktest: $(USERDIR)/bin/forktest.c $(BUILDDIR)/ulib.o $(BUILDDIR)/usys.o $(BUILDDIR)/umalloc.o
	$(CC) $(CFLAGS) -c -o $(BUILDDIR)/forktest.o $(USERDIR)/bin/forktest.c
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $(BUILDDIR)/forktest.o $(BUILDDIR)/ulib.o $(BUILDDIR)/usys.o $(BUILDDIR)/umalloc.o
	$(OBJDUMP) -S $@ > $(BUILDDIR)/forktest.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILDDIR)/forktest.sym

# User programs that need printf
$(BUILDDIR)/_%: $(USERDIR)/bin/%.c $(BUILDDIR)/ulib.o $(BUILDDIR)/usys.o $(BUILDDIR)/uprintf.o $(BUILDDIR)/umalloc.o
	$(CC) $(CFLAGS) -c -o $(BUILDDIR)/$*.o $(USERDIR)/bin/$*.c
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $(BUILDDIR)/$*.o $(BUILDDIR)/ulib.o $(BUILDDIR)/usys.o $(BUILDDIR)/uprintf.o $(BUILDDIR)/umalloc.o
	$(OBJDUMP) -S $@ > $(BUILDDIR)/$*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILDDIR)/$*.sym

# File system
$(BUILDDIR)/fs.img: $(TOOLSDIR)/mkfs.c $(BUILDDIR)/README $(USER_PROGS)
	gcc -Werror -Wall -I$(KERNELDIR)/include -D_GNU_SOURCE -Wno-implicit-function-declaration -o $(BUILDDIR)/mkfs $(TOOLSDIR)/mkfs.c
	cd $(BUILDDIR) && ./mkfs fs.img README $(patsubst $(BUILDDIR)/%,%,$(USER_PROGS))

# README for filesystem
$(BUILDDIR)/README: $(DOCSDIR)/README
	cp $(DOCSDIR)/README $(BUILDDIR)/README

# Main disk image
$(BUILDDIR)/xv6.img: $(BUILDDIR)/bootblock $(BUILDDIR)/kernel $(BUILDDIR)/fs.img
	dd if=/dev/zero of=$(BUILDDIR)/xv6.img count=10000
	dd if=$(BUILDDIR)/bootblock of=$(BUILDDIR)/xv6.img conv=notrunc
	dd if=$(BUILDDIR)/kernel of=$(BUILDDIR)/xv6.img seek=1 conv=notrunc

# Run targets
qemu: $(BUILDDIR)/xv6.img
	$(QEMU) -serial mon:stdio -drive file=$(BUILDDIR)/xv6.img,index=0,media=disk,format=raw -smp 2 -m 512

qemu-nox: $(BUILDDIR)/xv6.img
	$(QEMU) -nographic -drive file=$(BUILDDIR)/xv6.img,index=0,media=disk,format=raw -smp 2 -m 512

qemu-gdb: $(BUILDDIR)/xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio -drive file=$(BUILDDIR)/xv6.img,index=0,media=disk,format=raw -smp 2 -m 512 -S -gdb tcp::26000

qemu-nox-gdb: $(BUILDDIR)/xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic -drive file=$(BUILDDIR)/xv6.img,index=0,media=disk,format=raw -smp 2 -m 512 -S -gdb tcp::26000

# GDB setup
.gdbinit: $(CONFIGDIR)/.gdbinit.tmpl
	sed "s/localhost:1234/localhost:26000/" < $(CONFIGDIR)/.gdbinit.tmpl > .gdbinit

# Clean targets
clean:
	rm -rf $(BUILDDIR)/*
	rm -f .gdbinit

distclean: clean
	rm -rf $(BUILDDIR)

# Help target
help:
	@echo "xv6-plus Build System"
	@echo "===================="
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build complete system (default)"
	@echo "  qemu         - Run in QEMU with graphics"
	@echo "  qemu-nox     - Run in QEMU without graphics"
	@echo "  qemu-gdb     - Run in QEMU with GDB support"
	@echo "  qemu-nox-gdb - Run in QEMU without graphics, with GDB"
	@echo "  clean        - Remove build artifacts"
	@echo "  distclean    - Remove all generated files"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Environment Variables:"
	@echo "  TOOLPREFIX   - Cross-compiler prefix (default: auto-detect)"
	@echo "  QEMU         - QEMU executable path (default: auto-detect)"

# Include dependency files
-include $(BUILDDIR)/*.d

.PHONY: all clean distclean qemu qemu-nox qemu-gdb qemu-nox-gdb help
# Makefile for Logitech G733 HID-BPF Battery Program
#
# Targets:
#   make              - Build BPF object file
#   make verify       - Check object integrity
#   make clean        - Remove built files

.PHONY: all verify clean distclean check_deps

PROG_NAME := g733_bpf
OUTPUT := $(PROG_NAME).bpf.o
SOURCE := $(PROG_NAME).c

KERNEL_VERSION := $(shell uname -r)
KERNEL_BUILD_DIR := /lib/modules/$(KERNEL_VERSION)/build
VMLINUX_BTF := /sys/kernel/btf/vmlinux
VMLINUX_H := vmlinux.h

CC := clang
CLANG_BPF := $(CC)
LLVM_OBJDUMP := llvm-objdump

INCLUDES := -I/usr/include/bpf -I$(KERNEL_BUILD_DIR)/include
CFLAGS := -O2 -g -target bpf -D__KERNEL__ -D__BPF_CORE__ $(INCLUDES)

all: check_deps $(OUTPUT)

check_deps:
	@echo "Checking dependencies..."
	@command -v $(CC) >/dev/null 2>&1 || { echo "ERROR: clang not found"; exit 1; }
	@command -v bpftool >/dev/null 2>&1 || { echo "ERROR: bpftool not found"; exit 1; }
	@test -f $(VMLINUX_BTF) || { echo "ERROR: vmlinux.h not found at $(VMLINUX_BTF)"; exit 1; }
	@echo "✓ All dependencies found"

$(VMLINUX_H): check_deps
	@echo "Generating vmlinux.h from kernel BTF..."
	@bpftool btf dump file $(VMLINUX_BTF) format c > $@
	@echo "✓ Generated $@"

$(OUTPUT): $(SOURCE) $(VMLINUX_H)
	@echo "Compiling $(PROG_NAME)..."
	@$(CLANG_BPF) $(CFLAGS) -c $(SOURCE) -o $@
	@echo "✓ Built: $@"

verify: $(OUTPUT)
	@echo "Verifying BPF object..."
	@$(LLVM_OBJDUMP) -h $(OUTPUT) | grep -E '\.text|struct_ops'
	@$(LLVM_OBJDUMP) -d $(OUTPUT) | head -30

clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(OUTPUT) $(VMLINUX_H)

distclean: clean
	@rm -f *.o *.a *.so

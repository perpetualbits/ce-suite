# SPDX-License-Identifier: BSD-3-Clause
# SPDX-FileCopyrightText: 2026 Roland Nagtegaal <perpetualbits@gmail.com>

# Set QEMU_SRC to your QEMU fork/checkout (with CE Suite patches applied)
QEMU_SRC  ?= $(error Set QEMU_SRC to your QEMU source directory)
QEMU_BUILD ?= $(QEMU_SRC)/build

.PHONY: configure build run-test clean patch-status

# Configure QEMU for RISC-V targets only (faster build)
configure:
	cd $(QEMU_SRC) && ./configure \
	  --target-list=riscv64-softmmu,riscv64-linux-user \
	  --enable-debug

# Build QEMU
build: configure
	$(MAKE) -C $(QEMU_BUILD) -j$$(nproc)

# Apply CE Suite patches to a clean QEMU checkout
apply-patches:
	cd $(QEMU_SRC) && git am $(CURDIR)/patches/*.patch

# Run a bare-metal CE Suite test (once test binary exists)
run-bare:
	$(QEMU_BUILD)/qemu-system-riscv64 \
	  -machine virt -nographic -bios none \
	  -kernel tests/ce_bare_test.elf

# Show which patches are applied
patch-status:
	cd $(QEMU_SRC) && git log --oneline upstream/master..HEAD

clean:
	$(MAKE) -C $(QEMU_BUILD) clean

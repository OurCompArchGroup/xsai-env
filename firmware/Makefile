# RISC-V Firmware Build System
# Requirements: RISCV environment variable must point to toolchain root

SHELL := /bin/bash
SHELLFLAGS := -eu -o pipefail -c
GIT_FORCE_INIT ?= 0
GIT_FORCE_FLAG := $(if $(filter 1 true TRUE yes YES,$(GIT_FORCE_INIT)),--force,)

# Environment setup
export RISCV ?= /opt/riscv/
export ARCH := riscv
export CROSS_COMPILE := riscv64-unknown-linux-gnu-

# Directory setup
XS_PROJECT_ROOT ?= $(abspath $(dir $(firstword $(MAKEFILE_LIST)))/..)
export WORK_DIR := $(XS_PROJECT_ROOT)/firmware

export RISCV_LINUX_HOME := $(WORK_DIR)/riscv-linux
export RISCV_ROOTFS_HOME := $(WORK_DIR)/riscv-rootfs
export OPENSBI := $(WORK_DIR)/opensbi
export WORKLOAD_BUILD_ENV_HOME := $(WORK_DIR)/nemu_board
export GCPT_HOME ?= $(WORK_DIR)/LibCheckpoint
export GCPT_RESTORE_HOME ?= $(WORK_DIR)/gcpt_restore
export PATH := $(RISCV)/bin:$(PATH)

-include $(RISCV_ROOTFS_HOME)/riscv-lib-paths.mk
DIRECT_MAP_MEM_START ?=
DIRECT_MAP_MEM_SIZE ?=
DTS_DIRECT_MAP_ARGS := $(if $(and $(DIRECT_MAP_MEM_START),$(DIRECT_MAP_MEM_SIZE)),--direct-map-mem $(DIRECT_MAP_MEM_START) $(DIRECT_MAP_MEM_SIZE),)
# Memory layout: QEMU size, kernel RAM, XSAI DMA pool — all defaults from mk/memory.mk
include $(XS_PROJECT_ROOT)/mk/memory.mk
XSAI_COMPATIBLE ?= xiangshan,ai-nemu-board xiangshan,nemu-board
XSAI_MODEL ?= XiangShan AI
XSAI_EXTRA_ISA_EXTENSIONS ?= zame zammai8i32
XSAI_DTB_FILE := $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan_ai.dtb
INITRAMFS_BASE_SOURCES := $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-common-base.txt \
                          $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-common-libs.txt \
                          $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-disk-xsai-base.txt
INITRAMFS_WORKLOAD_SOURCE ?= $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-disk-xsai-workload.txt
GEN_INIT_CPIO := $(RISCV_LINUX_HOME)/usr/gen_init_cpio
INITRAMFS_BUILD_DIR := $(WORK_DIR)/build
INITRAMFS_CPIO := $(INITRAMFS_BUILD_DIR)/initramfs.cpio
INITRAMFS_BASE_CPIO := $(INITRAMFS_BUILD_DIR)/initramfs-base.cpio
INITRAMFS_WORKLOAD_CPIO := $(INITRAMFS_BUILD_DIR)/initramfs-workload.cpio
COMBINED_PAYLOAD := $(INITRAMFS_BUILD_DIR)/combined_payload.bin
INITRAMFS_ALIGN := 1048576
# Linux kernel version
LINUX_VERSION := 6.18
LINUX_TARBALL := linux-$(LINUX_VERSION).tar.xz
LINUX_URL := https://cdn.kernel.org/pub/linux/kernel/v6.x/$(LINUX_TARBALL)

# Build targets
LINUX_IMAGE := $(RISCV_LINUX_HOME)/arch/riscv/boot/Image
STD_DTB_FILE := $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan.dtb
DTB_FILE ?= $(XSAI_DTB_FILE)
OPENSBI_QEMU_BUILD_ROOT := $(OPENSBI)/build-qemu
OPENSBI_NEMU_BUILD_ROOT := $(OPENSBI)/build-nemu
OPENSBI_QEMU_PAYLOAD := $(OPENSBI_QEMU_BUILD_ROOT)/platform/generic/firmware/fw_payload.bin
OPENSBI_NEMU_PAYLOAD := $(OPENSBI_NEMU_BUILD_ROOT)/platform/generic/firmware/fw_payload.bin
OPENSBI_PAYLOAD ?= $(OPENSBI_QEMU_PAYLOAD)
GCPT_QEMU_BUILD_ROOT := $(GCPT_RESTORE_HOME)/build-qemu
GCPT_NEMU_BUILD_ROOT := $(GCPT_RESTORE_HOME)/build-nemu
GCPT_QEMU_BIN := $(GCPT_QEMU_BUILD_ROOT)/build/gcpt.bin
GCPT_NEMU_BIN := $(GCPT_NEMU_BUILD_ROOT)/build/gcpt.bin
GCPT_BOOT_BIN := $(GCPT_QEMU_BIN)
GCPT_RESTORE_BUILD_ROOT := $(GCPT_RESTORE_HOME)/restore-only
GCPT_RESTORE_BIN := $(GCPT_RESTORE_BUILD_ROOT)/build/gcpt.bin
GCPT_BIN := $(GCPT_QEMU_BIN)
FIRMWARE_LOG_DIR ?= $(XS_PROJECT_ROOT)/log
BUILD_LOG_TAIL_LINES ?= 50
ROOTFS_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/rootfs-build.log
LINUX_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/linux-build.log
LINUX_CONFIG_STAMP ?= $(RISCV_LINUX_HOME)/.xsai-linux-config.stamp
LINUX_CONFIG_INTENT ?= $(RISCV_LINUX_HOME)/.xsai-linux-config.intent
OPENSBI_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/opensbi-build.log
GCPT_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/gcpt-build.log
OPENSBI_QEMU_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/opensbi-qemu-build.log
OPENSBI_NEMU_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/opensbi-nemu-build.log
GCPT_QEMU_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/gcpt-qemu-build.log
GCPT_NEMU_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/gcpt-nemu-build.log
SHOW_FIRMWARE_BUILD_LOGS ?= 0
SHOW_ROOTFS_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_LINUX_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_OPENSBI_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_GCPT_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
HALF_NPROC ?= $(shell n=$$(nproc); echo $$(( ($$n + 1) / 2 )))
LINUX_MAKE_JOBS ?= $(HALF_NPROC)
FIRMWARE_MAKE_JOBS ?= $(HALF_NPROC)
ROOTFS_MAKE_JOBS ?= $(FIRMWARE_MAKE_JOBS)
OPENSBI_MAKE_JOBS ?= $(FIRMWARE_MAKE_JOBS)
GCPT_MAKE_JOBS ?= $(FIRMWARE_MAKE_JOBS)
FORCE_LINUX_CONFIG ?= 0
XSAI_INIT_MODE ?= manual
ifeq ($(XSAI_INIT_MODE),ci)
XSAI_WORKLOAD ?= llama-fake-bench-suite
XSAI_AUTO_EXIT ?= 1
XSAI_DROP_SHELL ?= 0
else
ifeq ($(XSAI_INIT_MODE),shell)
XSAI_WORKLOAD ?= none
XSAI_AUTO_EXIT ?= 0
XSAI_DROP_SHELL ?= 1
else
XSAI_WORKLOAD ?= llama-fake-bench-suite
XSAI_AUTO_EXIT ?= 0
XSAI_DROP_SHELL ?= 1
endif
endif
XSAI_RUN_AFTER_WORKLOAD ?= 1
XSAI_DUMP_THP ?= 1
XSAI_TRACE_WORKLOAD ?= 1
XSAI_GGML_AME_LOG ?= 0
XSAI_GGML_AME_PACKED_Q8 ?= 1
export XSAI_INIT_MODE XSAI_WORKLOAD XSAI_AUTO_EXIT XSAI_DROP_SHELL
export XSAI_RUN_AFTER_WORKLOAD XSAI_DUMP_THP XSAI_TRACE_WORKLOAD
export XSAI_GGML_AME_LOG XSAI_GGML_AME_PACKED_Q8

.PHONY: all check-env download-linux setup-submodules init init-force build-rootfs build-linux build-initramfs-base build-initramfs build-combined-payload build-dtb build-dtb-std build-dtb-xsai build-opensbi build-opensbi-qemu build-opensbi-nemu _build-opensbi build-gcpt build-gcpt-qemu build-gcpt-nemu _build-gcpt build-gcpt-restore build-gcpt-clean clean distclean help

all: build-dtb build-gcpt-qemu build-gcpt-nemu build-gcpt-restore
	@echo "✓ Build complete!"
	@echo "  Linux Image: $(LINUX_IMAGE)"
	@echo "  DTB: $(DTB_FILE)"
	@echo "  QEMU OpenSBI Payload: $(OPENSBI_QEMU_PAYLOAD)"
	@echo "  NEMU OpenSBI Payload: $(OPENSBI_NEMU_PAYLOAD)"
	@echo "  QEMU GCPT Boot Binary: $(GCPT_QEMU_BIN)"
	@echo "  NEMU GCPT Boot Binary: $(GCPT_NEMU_BIN)"
	@echo "  GCPT Restore Binary: $(GCPT_RESTORE_BIN)"

help:
	@echo "RISC-V Firmware Build System"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Set RISCV environment variable to toolchain root"
	@echo "  - Ensure riscv64-unknown-linux-gnu-gcc is in PATH"
	@echo ""
	@echo "Targets:"
	@echo "  all              - Build everything (default)"
	@echo "                     SHOW_FIRMWARE_BUILD_LOGS=1 to stream all major build logs"
	@echo "  check-env        - Verify environment setup"
	@echo "  download-linux   - Download Linux kernel"
	@echo "  setup-submodules - Initialize git submodules"
	@echo "  init-force       - Force initialize firmware submodules"
	@echo "  build-rootfs     - Build root filesystem"
	@echo "                     SHOW_ROOTFS_BUILD_LOG=1 to stream full rootfs build logs"
	@echo "                     ROOTFS_MAKE_JOBS=$(ROOTFS_MAKE_JOBS)"
	@echo "                     XSAI_INIT_MODE=$(XSAI_INIT_MODE) XSAI_WORKLOAD=$(XSAI_WORKLOAD)"
	@echo "                     XSAI_AUTO_EXIT=$(XSAI_AUTO_EXIT) XSAI_DROP_SHELL=$(XSAI_DROP_SHELL)"
	@echo "  build-linux      - Build Linux kernel"
	@echo "                     SHOW_LINUX_BUILD_LOG=1 to stream full kernel build logs"
	@echo "                     LINUX_MAKE_JOBS=$(LINUX_MAKE_JOBS)"
	@echo "                     FORCE_LINUX_CONFIG=1 to rerun defconfig/olddefconfig/prepare"
# 	@echo "                     INITRAMFS_SOURCE=$(INITRAMFS_SOURCE)"
# 	@echo "                     INITRAMFS_COMMON_SOURCES=$(INITRAMFS_COMMON_SOURCES)"
	@echo "  build-dtb        - Build XSAI device tree blob (default)"
	@echo "  build-dtb-std    - Build standard XiangShan device tree blob"
	@echo "                     Optional: DIRECT_MAP_MEM_START=0x100000000 DIRECT_MAP_MEM_SIZE=0x180000000"
	@echo "  build-dtb-xsai   - Build XSAI-specific device tree blob"
	@echo "  build-opensbi    - Build QEMU OpenSBI firmware payload (runtime DTB)"
	@echo "  build-opensbi-nemu - Build NEMU OpenSBI firmware payload (embedded DTB)"
	@echo "  build-gcpt       - Build QEMU bootable GCPT binary linked with the payload"
	@echo "  build-gcpt-nemu  - Build NEMU bootable GCPT binary linked with the payload"
	@echo "  build-gcpt-restore - Build restore-only GCPT binary for checkpoint resume"
	@echo "                     SHOW_OPENSBI_BUILD_LOG=1 to stream full OpenSBI build logs"
	@echo "                     SHOW_GCPT_BUILD_LOG=1 to stream full GCPT build logs"
	@echo "                     OPENSBI_MAKE_JOBS=$(OPENSBI_MAKE_JOBS) GCPT_MAKE_JOBS=$(GCPT_MAKE_JOBS)"
	@echo "  build-gcpt-clean - Force clean rebuild of GCPT (after editing csr.h etc.)"
	@echo "  clean            - Clean build artifacts"
	@echo "  distclean        - Deep clean: remove downloads and deinit submodules"

check-env:
	@echo "Checking environment..."
	@if [ -z "$(RISCV)" ]; then \
		echo "✗ Error: RISCV environment variable not set"; \
		exit 1; \
	fi
	@if [ ! -f "$(RISCV)/bin/$(CROSS_COMPILE)gcc" ]; then \
		echo "✗ Error: Compiler not found at $(RISCV)/bin/$(CROSS_COMPILE)gcc"; \
		exit 1; \
	fi
	@echo "✓ Environment OK"
	@echo "  RISCV=$(RISCV)"
	@echo "  Compiler: $(shell $(RISCV)/bin/$(CROSS_COMPILE)gcc --version | head -n1)"

download-linux: $(LINUX_TARBALL)
	@echo "Extracting Linux kernel..."
	@if [ ! -d "$(WORK_DIR)/linux-$(LINUX_VERSION)" ]; then \
		tar xf $(LINUX_TARBALL) -C $(WORK_DIR); \
		echo "✓ Linux kernel extracted"; \
	else \
		echo "✓ Linux kernel already extracted"; \
	fi
	@ln -sfn linux-$(LINUX_VERSION) $(RISCV_LINUX_HOME)
	@echo "Applying Matrix kernel patch (if needed)..."
	@if [ -f "$(RISCV_LINUX_HOME)/arch/riscv/kernel/matrix.c" ] && \
	    grep -q "^#define SR_MS" "$(RISCV_LINUX_HOME)/arch/riscv/include/asm/csr.h"; then \
		echo "✓ Matrix patch already present"; \
	else \
		bash $(WORK_DIR)/patches/apply-matrix-patch.sh "$(RISCV_LINUX_HOME)" && \
		echo "✓ Matrix patch applied"; \
	fi

init: download-linux
	git -C "$(XS_PROJECT_ROOT)" submodule update --init $(GIT_FORCE_FLAG) firmware/LibCheckpoint firmware/gcpt_restore firmware/nemu_board firmware/riscv-rootfs
	git -C "$(XS_PROJECT_ROOT)" -c submodule.firmware/opensbi.update=checkout submodule update --init --checkout $(GIT_FORCE_FLAG) firmware/opensbi
	git -C "$(XS_PROJECT_ROOT)" -c submodule.firmware/opensbi.update=checkout submodule update --init --checkout $(GIT_FORCE_FLAG) --recursive firmware/opensbi

init-force:
	$(MAKE) init GIT_FORCE_INIT=1
$(LINUX_TARBALL):
	@echo "Downloading Linux kernel $(LINUX_VERSION)..."
	@wget -q --show-progress $(LINUX_URL)

setup-submodules:
	@echo "Initializing submodules..."
	@echo "git submodule update --init --recursive"
	@echo "✓ Submodules initialized"

build-rootfs: setup-submodules
	@echo "Building root filesystem..."
	@echo "  XSAI init: mode=$(XSAI_INIT_MODE) workload=$(XSAI_WORKLOAD) auto_exit=$(XSAI_AUTO_EXIT) drop_shell=$(XSAI_DROP_SHELL)"
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_ROOTFS_BUILD_LOG)" = "1" ]; then \
		echo "$$(date '+[fw %F %T %z] START build-rootfs jobs=$(ROOTFS_MAKE_JOBS)')"; \
		cd $(RISCV_ROOTFS_HOME) && $(MAKE) rootfsimg -j$(ROOTFS_MAKE_JOBS); \
		echo "$$(date '+[fw %F %T %z] END build-rootfs')"; \
	else \
		( echo "$$(date '+[fw %F %T %z] START build-rootfs jobs=$(ROOTFS_MAKE_JOBS)')" && \
		  cd $(RISCV_ROOTFS_HOME) && $(MAKE) rootfsimg -j$(ROOTFS_MAKE_JOBS) && \
		  echo "$$(date '+[fw %F %T %z] END build-rootfs')" ) > "$(ROOTFS_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ Root filesystem build failed. Full log: $(ROOTFS_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(ROOTFS_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(ROOTFS_BUILD_LOG)"; \
			exit $$status; \
		}; \
		echo "  Rootfs build log: $(ROOTFS_BUILD_LOG)"; \
	fi
	@echo "✓ Root filesystem built"

build-linux:
	@echo "Configuring Linux kernel..."
	@mkdir -p $(dir $(LINUX_CONFIG_STAMP))
	@cd $(RISCV_LINUX_HOME) && \
		{ \
			echo "defconfig=$$(sha256sum "$(WORKLOAD_BUILD_ENV_HOME)/configs/xiangshan_defconfig" | awk '{print $$1}')"; \
			echo "INITRAMFS_SOURCE=external"; \
			echo "CONFIG_BLOCK=y"; \
			echo "CONFIG_BLK_DEV=y"; \
			echo "CONFIG_VIRTIO_MENU=y"; \
			echo "CONFIG_VIRTIO_MMIO=y"; \
			echo "CONFIG_VIRTIO_BLK=y"; \
			echo "CONFIG_SYSFS=y"; \
			echo "CONFIG_TMPFS=y"; \
			echo "CONFIG_DEVTMPFS=y"; \
			echo "CONFIG_EXT4_FS=y"; \
			echo "CONFIG_BINFMT_SCRIPT=y"; \
			echo "CONFIG_RISCV_ISA_V=y"; \
			echo "CONFIG_RISCV_ISA_V_DEFAULT_ENABLE=y"; \
			echo "CONFIG_RISCV_ISA_V_UCOPY_THRESHOLD=768"; \
			echo "CONFIG_RISCV_ISA_V_PREEMPTIVE=y"; \
			echo "CONFIG_RISCV_ISA_ZICBOZ=n"; \
			echo "CONFIG_RISCV_ISA_ZICBOP=n"; \
			echo "CONFIG_RISCV_ISA_ZICBOM=n"; \
			echo "CONFIG_SMP=n"; \
			echo "CONFIG_DEVMEM=y"; \
			echo "CONFIG_STRICT_DEVMEM=n"; \
			echo "CONFIG_IO_STRICT_DEVMEM=n"; \
			echo "CONFIG_FLATMEM_MANUAL=n"; \
			echo "CONFIG_SPARSEMEM_MANUAL=y"; \
			echo "CONFIG_SPARSEMEM_VMEMMAP=y"; \
			echo "CONFIG_DEFERRED_STRUCT_PAGE_INIT=y"; \
			echo "CONFIG_TRANSPARENT_HUGEPAGE=y"; \
			echo "CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS=n"; \
			echo "CONFIG_TRANSPARENT_HUGEPAGE_MADVISE=y"; \
			echo "CONFIG_PERF_EVENTS=y"; \
			echo "CONFIG_RISCV_PMU_SBI=y"; \
		} > "$(LINUX_CONFIG_INTENT)" && \
		INTENT_HASH=$$(sha256sum "$(LINUX_CONFIG_INTENT)" | awk '{print $$1}') && \
		CONFIG_HASH=missing && \
		if [ -f .config ]; then CONFIG_HASH=$$(sha256sum .config | awk '{print $$1}'); fi && \
		NEED_CONFIG=0 && \
		if [ "$(FORCE_LINUX_CONFIG)" = "1" ]; then \
			echo "  Linux config refresh reason: FORCE_LINUX_CONFIG=1"; \
			NEED_CONFIG=1; \
		elif [ ! -f .config ] || [ ! -f include/config/auto.conf ] || [ ! -f include/generated/autoconf.h ]; then \
			echo "  Linux config refresh reason: missing generated config files"; \
			NEED_CONFIG=1; \
		elif [ ! -f "$(LINUX_CONFIG_STAMP)" ]; then \
			echo "  Linux config refresh reason: missing config stamp"; \
			NEED_CONFIG=1; \
		elif ! grep -qx "intent=$$INTENT_HASH" "$(LINUX_CONFIG_STAMP)" || ! grep -qx "config=$$CONFIG_HASH" "$(LINUX_CONFIG_STAMP)"; then \
			echo "  Linux config refresh reason: config intent or .config changed"; \
			NEED_CONFIG=1; \
		fi && \
		if [ "$$NEED_CONFIG" = "1" ]; then \
			echo "$$(date '+[fw %F %T %z] START configure-linux')"; \
			cp $(WORKLOAD_BUILD_ENV_HOME)/configs/xiangshan_defconfig arch/riscv/configs/xiangshan_defconfig && \
			$(MAKE) xiangshan_defconfig && \
			[ -n "$(RISCV_LD_SO)" ] && [ -n "$(RISCV_LIBC_SO)" ] && \
			[ -n "$(RISCV_LIBRESOLV_SO)" ] && [ -n "$(RISCV_LIBM_SO)" ] && \
			[ -n "$(RISCV_LIBDL_SO)" ] && [ -n "$(RISCV_LIBPTHREAD_SO)" ] && \
			./scripts/config --enable CONFIG_BLOCK && \
			./scripts/config --enable CONFIG_BLK_DEV && \
			./scripts/config --enable CONFIG_VIRTIO_MENU && \
			./scripts/config --enable CONFIG_VIRTIO_MMIO && \
			./scripts/config --enable CONFIG_VIRTIO_BLK && \
			./scripts/config --enable CONFIG_SYSFS && \
			./scripts/config --enable CONFIG_TMPFS && \
			./scripts/config --enable CONFIG_DEVTMPFS && \
			./scripts/config --enable CONFIG_EXT4_FS && \
			./scripts/config --enable CONFIG_BINFMT_SCRIPT && \
			./scripts/config --enable CONFIG_RISCV_ISA_V && \
			./scripts/config --enable CONFIG_RISCV_ISA_V_DEFAULT_ENABLE && \
			./scripts/config --set-val CONFIG_RISCV_ISA_V_UCOPY_THRESHOLD 768 && \
			./scripts/config --enable CONFIG_RISCV_ISA_V_PREEMPTIVE && \
			./scripts/config --disable CONFIG_RISCV_ISA_ZICBOZ && \
			./scripts/config --disable CONFIG_RISCV_ISA_ZICBOP && \
			./scripts/config --disable CONFIG_RISCV_ISA_ZICBOM && \
			./scripts/config --disable CONFIG_SMP && \
			./scripts/config --enable CONFIG_DEVMEM && \
			./scripts/config --disable CONFIG_STRICT_DEVMEM && \
			./scripts/config --disable CONFIG_IO_STRICT_DEVMEM && \
			./scripts/config --set-str CONFIG_INITRAMFS_SOURCE "" && \
			./scripts/config --enable CONFIG_BLK_DEV_INITRD && \
			./scripts/config --disable CONFIG_FLATMEM_MANUAL && \
			./scripts/config --enable CONFIG_SPARSEMEM_MANUAL && \
			./scripts/config --enable CONFIG_SPARSEMEM_VMEMMAP && \
			./scripts/config --enable CONFIG_DEFERRED_STRUCT_PAGE_INIT && \
			./scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE && \
			./scripts/config --disable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS && \
			./scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_MADVISE && \
			./scripts/config --enable CONFIG_PERF_EVENTS && \
			./scripts/config --enable CONFIG_RISCV_PMU_SBI && \
			$(MAKE) olddefconfig && \
			$(MAKE) prepare && \
			CONFIG_HASH=$$(sha256sum .config | awk '{print $$1}') && \
			printf 'intent=%s\nconfig=%s\n' "$$INTENT_HASH" "$$CONFIG_HASH" > "$(LINUX_CONFIG_STAMP)" && \
			echo "$$(date '+[fw %F %T %z] END configure-linux')"; \
		else \
			echo "✓ Linux config up to date; skipping defconfig/olddefconfig/prepare"; \
		fi
	@echo "Building Linux kernel..."
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_LINUX_BUILD_LOG)" = "1" ]; then \
		echo "$$(date '+[fw %F %T %z] START build-linux jobs=$(LINUX_MAKE_JOBS)')"; \
		cd $(RISCV_LINUX_HOME) && $(MAKE) -j$(LINUX_MAKE_JOBS); \
		echo "$$(date '+[fw %F %T %z] END build-linux')"; \
	else \
		( echo "$$(date '+[fw %F %T %z] START build-linux jobs=$(LINUX_MAKE_JOBS)')" && \
		  cd $(RISCV_LINUX_HOME) && $(MAKE) -j$(LINUX_MAKE_JOBS) && \
		  echo "$$(date '+[fw %F %T %z] END build-linux')" ) > "$(LINUX_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ Linux kernel build failed. Full log: $(LINUX_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(LINUX_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(LINUX_BUILD_LOG)"; \
			exit $$status; \
		}; \
		echo "  Linux build log: $(LINUX_BUILD_LOG)"; \
	fi
	@echo "✓ Linux kernel built: $(LINUX_IMAGE)"

$(INITRAMFS_BASE_CPIO): $(INITRAMFS_BASE_SOURCES) | build-rootfs
	@echo "Building base initramfs..."
	@mkdir -p $(INITRAMFS_BUILD_DIR)
	@if [ ! -f "$(GEN_INIT_CPIO)" ]; then \
		echo "  Compiling gen_init_cpio..."; \
		cd $(RISCV_LINUX_HOME) && $(MAKE) usr/gen_init_cpio; \
	fi
	@cat $(INITRAMFS_BASE_SOURCES) | $(GEN_INIT_CPIO) -o $@ -
	@echo "  Size: $$(stat -c%s $@) bytes"
	@echo "✓ Initramfs-base built: $@"

build-initramfs-base: $(INITRAMFS_BASE_CPIO)

build-initramfs: $(INITRAMFS_BASE_CPIO) build-rootfs
	@echo "Building initramfs..."
	@mkdir -p $(INITRAMFS_BUILD_DIR)
	@if [ ! -f "$(GEN_INIT_CPIO)" ]; then \
		echo "  Compiling gen_init_cpio..."; \
		cd $(RISCV_LINUX_HOME) && $(MAKE) usr/gen_init_cpio; \
	fi
	@cat $(INITRAMFS_WORKLOAD_SOURCE) | $(GEN_INIT_CPIO) -o $(INITRAMFS_WORKLOAD_CPIO) -
	@cat $(INITRAMFS_BASE_CPIO) $(INITRAMFS_WORKLOAD_CPIO) > $(INITRAMFS_CPIO)
	@echo "  Size: $$(stat -c%s $(INITRAMFS_CPIO)) bytes"
	@echo "✓ Initramfs built: $(INITRAMFS_CPIO)"

build-combined-payload: $(COMBINED_PAYLOAD)

$(COMBINED_PAYLOAD): $(LINUX_IMAGE) $(INITRAMFS_CPIO)
	@echo "Building combined payload (kernel + initramfs)..."
	@mkdir -p $(INITRAMFS_BUILD_DIR)
	@KERNEL_SIZE=$$(stat -c%s $(LINUX_IMAGE)) && \
	 ALIGN=$(INITRAMFS_ALIGN) && \
	 ALIGNED_KERNEL=$$(python3 -c "ks=$$KERNEL_SIZE; a=$$ALIGN; print(((ks+a-1)//a)*a)") && \
	 INITRD_GAP=$$((2 * 1024 * 1024)) && \
	 PAD_SIZE=$$(($$ALIGNED_KERNEL + $$INITRD_GAP - $$KERNEL_SIZE)) && \
	 cp $(LINUX_IMAGE) $@ && \
	 head -c $$PAD_SIZE /dev/zero >> $@ && \
	 cat $(INITRAMFS_CPIO) >> $@ && \
	 echo "✓ Combined payload: $$(stat -c%s $@) bytes"

build-dtb-std: setup-submodules
	@echo "Building device tree blob..."
	@cd $(WORKLOAD_BUILD_ENV_HOME)/dts && \
		mkdir -p build && \
		python3 DTSGen.py \
			--nr-harts 1 \
			--rva-profile rva23u64 \
			$(DTS_DIRECT_MAP_ARGS) \
			--bootargs "console=hvc0 earlycon=sbi" \
			--mmu-type riscv,sv39 | \
		dtc -O dtb -o build/xiangshan.dtb - || exit $$?
	@echo "✓ Standard DTB built: $(STD_DTB_FILE)"

build-dtb: build-dtb-xsai
	@echo "✓ Default DTB built for XSAI: $(XSAI_DTB_FILE)"

build-dtb-xsai: setup-submodules build-linux build-initramfs
	@echo "Building XSAI device tree blob..."
	@echo "$$(date '+[fw %F %T %z] START build-dtb-xsai')"
	@KERNEL_SIZE=$$(stat -c%s $(LINUX_IMAGE)) && \
	 CPIO_SIZE=$$(stat -c%s $(INITRAMFS_CPIO)) && \
	 ALIGNED_KERNEL=$$(python3 -c "ks=$$KERNEL_SIZE; a=$(INITRAMFS_ALIGN); print(((ks+a-1)//a)*a)") && \
	 INITRD_START=$$(python3 -c "print(hex(0x80200000 + $$ALIGNED_KERNEL + 2*1024*1024))") && \
	 INITRD_END=$$(python3 -c "print(hex(0x80200000 + $$ALIGNED_KERNEL + 2*1024*1024 + $$CPIO_SIZE))") && \
	 cd $(WORKLOAD_BUILD_ENV_HOME)/dts && \
		mkdir -p build && \
		python3 DTSGen.py \
			--compatible $(XSAI_COMPATIBLE) \
			--model "$(XSAI_MODEL)" \
			--cpu-compatible xiangshan,ai riscv \
			--nr-harts 1 \
			--rva-profile rva23u64 \
			--isa-extensions $(XSAI_EXTRA_ISA_EXTENSIONS) \
			--direct-map-mem $(XSAI_DIRECT_MAP_MEM_START) $(XSAI_DIRECT_MAP_MEM_SIZE) \
			--bootargs "console=hvc0 earlycon=sbi rdinit=/init" \
			--memory-size $(XSAI_MEMORY_SIZE) \
			--mmu-type riscv,sv48 \
			--reserve-mem $(XSAI_RAM_BASE) $(XSAI_BOOT_RESERVE_SIZE) \
			--initrd-start $$INITRD_START \
			--initrd-end $$INITRD_END | \
		dtc -O dtb -o build/xiangshan_ai.dtb - || exit $$?
	@dtc -I dtb -O dts -o $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan_ai.dts \
		$(XSAI_DTB_FILE) || exit $$?
	@echo "✓ XSAI DTB built: $(XSAI_DTB_FILE)"
	@echo "  DTS dump:        $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan_ai.dts"
	@echo "$$(date '+[fw %F %T %z] END build-dtb-xsai')"

# build-opensbi: build-linux build-dtb
# FW_PAYLOAD_FDT_ADDR is computed dynamically from the Linux Image size so that
# the DTB is placed after the kernel image with no overlap.
# Formula (mirrors checkpoint_scripts/generate_bbl.py build_opensbi()):
#   fdt_addr = round_up(image_size + 0x800000, 0x100000) + 0x80000000
build-opensbi: build-opensbi-qemu
	@echo "✓ Default OpenSBI payload built for QEMU: $(OPENSBI_QEMU_PAYLOAD)"

build-opensbi-qemu: build-combined-payload
	@$(MAKE) _build-opensbi \
		OPENSBI_FW_PAYLOAD=$(COMBINED_PAYLOAD) \
		OPENSBI_BUILD_ROOT=$(OPENSBI_QEMU_BUILD_ROOT) \
		OPENSBI_PAYLOAD_OUT=$(OPENSBI_QEMU_PAYLOAD) \
		OPENSBI_EMBED_DTB=0 \
		OPENSBI_BUILD_LOG=$(OPENSBI_QEMU_BUILD_LOG)

build-opensbi-nemu: build-combined-payload
	@$(MAKE) _build-opensbi \
		OPENSBI_FW_PAYLOAD=$(COMBINED_PAYLOAD) \
		OPENSBI_BUILD_ROOT=$(OPENSBI_NEMU_BUILD_ROOT) \
		OPENSBI_PAYLOAD_OUT=$(OPENSBI_NEMU_PAYLOAD) \
		OPENSBI_EMBED_DTB=1 \
		OPENSBI_BUILD_LOG=$(OPENSBI_NEMU_BUILD_LOG)

# Keep OpenSBI O= build roots for incremental rebuilds. The previous
# rm -rf "$(OPENSBI_BUILD_ROOT)" workaround avoided occasional stale firmware
# link artifacts, but it forced full QEMU/NEMU OpenSBI rebuilds on every run.
# Clean the affected build root explicitly if the stale-link issue reappears.
_build-opensbi:
	@echo "Building OpenSBI firmware..."
	@if [ ! -f "$(OPENSBI)/Makefile" ]; then \
		echo "Initializing opensbi submodule with checkout mode..."; \
		git -c submodule.firmware/opensbi.update=checkout submodule update --init --checkout opensbi; \
	fi
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ ! -f "$(OPENSBI)/Makefile" ]; then \
		echo "Initializing OpenSBI submodule..."; \
		git -C "$(XS_PROJECT_ROOT)" -c submodule.firmware/opensbi.update=checkout submodule update --init --checkout firmware/opensbi; \
		git -C "$(XS_PROJECT_ROOT)" -c submodule.firmware/opensbi.update=checkout submodule update --init --checkout --recursive firmware/opensbi; \
	fi
	@FW_SIZE=$$(stat -c%s $(OPENSBI_FW_PAYLOAD)) && \
	 FW_FDT_ADDR=$$(python3 -c \
	   "sz=$$FW_SIZE; print(hex(((sz+0x800000+0xfffff)//0x100000)*0x100000+0x80000000))") && \
	 echo "  Image size     : $$FW_SIZE bytes" && \
	 echo "  FW_PAYLOAD_FDT_ADDR: $$FW_FDT_ADDR" && \
	 EXTRA_FW_ARGS=(); \
	 if [ "$(OPENSBI_EMBED_DTB)" = "1" ]; then \
	 	EXTRA_FW_ARGS+=(FW_FDT_PATH=$(DTB_FILE)); \
	 fi; \
	 if [ "$(SHOW_OPENSBI_BUILD_LOG)" = "1" ]; then \
		echo "$$(date '+[fw %F %T %z] START build-opensbi jobs=$(OPENSBI_MAKE_JOBS) root=$(OPENSBI_BUILD_ROOT)')"; \
		cd $(OPENSBI) && $(MAKE) O="$(OPENSBI_BUILD_ROOT)" PLATFORM=generic \
			FW_PAYLOAD_PATH=$(OPENSBI_FW_PAYLOAD) \
			FW_PAYLOAD_OFFSET=0x100000 \
			FW_PAYLOAD_FDT_ADDR=$$FW_FDT_ADDR \
			"$${EXTRA_FW_ARGS[@]}" \
			-j$(OPENSBI_MAKE_JOBS); \
		echo "$$(date '+[fw %F %T %z] END build-opensbi root=$(OPENSBI_BUILD_ROOT)')"; \
	 else \
		( echo "$$(date '+[fw %F %T %z] START build-opensbi jobs=$(OPENSBI_MAKE_JOBS) root=$(OPENSBI_BUILD_ROOT)')" && \
		  cd $(OPENSBI) && $(MAKE) O="$(OPENSBI_BUILD_ROOT)" PLATFORM=generic \
			FW_PAYLOAD_PATH=$(OPENSBI_FW_PAYLOAD) \
			FW_PAYLOAD_OFFSET=0x100000 \
			FW_PAYLOAD_FDT_ADDR=$$FW_FDT_ADDR \
			"$${EXTRA_FW_ARGS[@]}" \
			-j$(OPENSBI_MAKE_JOBS) && \
		  echo "$$(date '+[fw %F %T %z] END build-opensbi root=$(OPENSBI_BUILD_ROOT)')" ) > "$(OPENSBI_BUILD_LOG)" 2>&1 || { \
				status=$$?; \
				echo "✗ OpenSBI build failed. Full log: $(OPENSBI_BUILD_LOG)"; \
				echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(OPENSBI_BUILD_LOG) ---"; \
				tail -n $(BUILD_LOG_TAIL_LINES) "$(OPENSBI_BUILD_LOG)"; \
				exit $$status; \
			}; \
		echo "  OpenSBI build log: $(OPENSBI_BUILD_LOG)"; \
	 fi
	@echo "✓ OpenSBI payload built: $(OPENSBI_PAYLOAD_OUT)"

build-gcpt: build-gcpt-qemu
	@echo "✓ Default GCPT boot binary built for QEMU: $(GCPT_QEMU_BIN)"

build-gcpt-qemu: build-opensbi-qemu
	@$(MAKE) _build-gcpt \
		GCPT_BUILD_ROOT=$(GCPT_QEMU_BUILD_ROOT) \
		GCPT_PAYLOAD_SOURCE=$(OPENSBI_QEMU_PAYLOAD) \
		GCPT_OUTPUT=$(GCPT_QEMU_BIN) \
		GCPT_BUILD_LOG=$(GCPT_QEMU_BUILD_LOG)

build-gcpt-nemu: build-opensbi-nemu
	@$(MAKE) _build-gcpt \
		GCPT_BUILD_ROOT=$(GCPT_NEMU_BUILD_ROOT) \
		GCPT_PAYLOAD_SOURCE=$(OPENSBI_NEMU_PAYLOAD) \
		GCPT_OUTPUT=$(GCPT_NEMU_BIN) \
		GCPT_BUILD_LOG=$(GCPT_NEMU_BUILD_LOG)

_build-gcpt:
	@if [ ! -f "$(GCPT_RESTORE_HOME)/Makefile" ]; then \
		echo "Initializing gcpt_restore submodule..."; \
		cd $(WORK_DIR) && git submodule update --init --force gcpt_restore; \
	fi
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_GCPT_BUILD_LOG)" = "1" ]; then \
		echo "$$(date '+[fw %F %T %z] START build-gcpt jobs=$(GCPT_MAKE_JOBS) root=$(GCPT_BUILD_ROOT)')"; \
		cd $(GCPT_RESTORE_HOME) && $(MAKE) O=$(GCPT_BUILD_ROOT) clean && $(MAKE) O=$(GCPT_BUILD_ROOT) GCPT_PAYLOAD_PATH=$(GCPT_PAYLOAD_SOURCE) -j$(GCPT_MAKE_JOBS) && ls $(GCPT_OUTPUT); \
		echo "$$(date '+[fw %F %T %z] END build-gcpt root=$(GCPT_BUILD_ROOT)')"; \
	else \
		( echo "$$(date '+[fw %F %T %z] START build-gcpt jobs=$(GCPT_MAKE_JOBS) root=$(GCPT_BUILD_ROOT)')" && \
		  cd $(GCPT_RESTORE_HOME) && $(MAKE) O=$(GCPT_BUILD_ROOT) clean && $(MAKE) O=$(GCPT_BUILD_ROOT) GCPT_PAYLOAD_PATH=$(GCPT_PAYLOAD_SOURCE) -j$(GCPT_MAKE_JOBS) && ls $(GCPT_OUTPUT) && \
		  echo "$$(date '+[fw %F %T %z] END build-gcpt root=$(GCPT_BUILD_ROOT)')" ) > "$(GCPT_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ GCPT build failed. Full log: $(GCPT_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(GCPT_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(GCPT_BUILD_LOG)"; \
			exit $$status; \
		}; \
			echo "  GCPT build log: $(GCPT_BUILD_LOG)"; \
		fi
	@echo "✓ GCPT boot binary built: $(GCPT_OUTPUT)"

build-gcpt-restore:
	@if [ ! -f "$(GCPT_RESTORE_HOME)/Makefile" ]; then \
		echo "Initializing gcpt_restore submodule..."; \
		cd $(WORK_DIR) && git submodule update --init --force gcpt_restore; \
	fi
	@echo "$$(date '+[fw %F %T %z] START build-gcpt-restore jobs=$(GCPT_MAKE_JOBS) root=$(GCPT_RESTORE_BUILD_ROOT)')"
	cd $(GCPT_RESTORE_HOME) && $(MAKE) O=$(GCPT_RESTORE_BUILD_ROOT) clean && $(MAKE) O=$(GCPT_RESTORE_BUILD_ROOT) -j$(GCPT_MAKE_JOBS) && ls $(GCPT_RESTORE_BIN) || exit $$?
	@echo "$$(date '+[fw %F %T %z] END build-gcpt-restore root=$(GCPT_RESTORE_BUILD_ROOT)')"

# Force a clean rebuild of gcpt (useful after editing src/csr.h etc.)
build-gcpt-clean:
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_GCPT_BUILD_LOG)" = "1" ]; then \
		cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j$(GCPT_MAKE_JOBS) && ls build/gcpt.bin; \
	else \
		( cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j$(GCPT_MAKE_JOBS) && ls build/gcpt.bin ) > "$(GCPT_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ GCPT build failed. Full log: $(GCPT_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(GCPT_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(GCPT_BUILD_LOG)"; \
			exit $$status; \
		}; \
		echo "  GCPT build log: $(GCPT_BUILD_LOG)"; \
	fi
	@echo "✓ GCPT binary built: $(GCPT_BIN)"
build-gcpt-t1:
	@echo "Building GCPT checkpoint tool..."
# git checkout f8c33689cdf11aa2f8f25dbf99075dca148ecd44
	@cd $(GCPT_HOME) && \
		python3 -m venv .gcpt_venv && \
		.gcpt_venv/bin/pip install -q "setuptools<70" "protobuf>=3.20,<5" grpcio-tools && \
		git submodule update --init && \
		bash configure \
			--gcpt-payload=$(OPENSBI_PAYLOAD) \
			--mode=normal \
			--stop-cpu=1 && \
		PATH=$(GCPT_HOME)/.gcpt_venv/bin:$$PATH \
		$(MAKE) -j$(shell nproc) && \
		ls build/gcpt.bin || exit $$?
	@echo "✓ GCPT binary built: $(GCPT_BIN)"

clean:
	@echo "Cleaning build artifacts..."
	@[ -d "$(RISCV_LINUX_HOME)" ] && cd $(RISCV_LINUX_HOME) && $(MAKE) mrproper || true
	@[ -d "$(OPENSBI)" ] && cd $(OPENSBI) && $(MAKE) clean && rm -rf build || true
	@[ -d "$(GCPT_HOME)" ] && cd $(GCPT_HOME) && $(MAKE) clean || true
	@[ -d "$(GCPT_RESTORE_HOME)" ] && cd $(GCPT_RESTORE_HOME) && $(MAKE) clean || true
	@rm -rf $(GCPT_RESTORE_BUILD_ROOT)
	@[ -d "$(RISCV_ROOTFS_HOME)" ] && cd $(RISCV_ROOTFS_HOME) && $(MAKE) clean || true
	@rm -rf "$(INITRAMFS_BUILD_DIR)" "$(WORKLOAD_BUILD_ENV_HOME)/dts/build"
	@echo "✓ Clean complete"

distclean: clean
	@echo "Removing all generated files..."
	@[ -d "$(RISCV_ROOTFS_HOME)" ] && cd $(RISCV_ROOTFS_HOME) && $(MAKE) distclean || true
	@rm -rf $(RISCV_LINUX_HOME)
	@rm -f $(LINUX_TARBALL)
	@git submodule deinit -f --all
	@echo "✓ Deep clean complete"

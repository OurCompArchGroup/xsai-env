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
INITRAMFS_COMMON_SOURCES := $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-common-base.txt $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-common-libs.txt
INITRAMFS_SOURCE ?= $(RISCV_ROOTFS_HOME)/rootfsimg/initramfs-disk-xsai.txt
# Linux kernel version
LINUX_VERSION := 6.18
LINUX_TARBALL := linux-$(LINUX_VERSION).tar.xz
LINUX_URL := https://cdn.kernel.org/pub/linux/kernel/v6.x/$(LINUX_TARBALL)

# Build targets
LINUX_IMAGE := $(RISCV_LINUX_HOME)/arch/riscv/boot/Image
STD_DTB_FILE := $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan.dtb
DTB_FILE ?= $(XSAI_DTB_FILE)
OPENSBI_PAYLOAD := $(OPENSBI)/build/platform/generic/firmware/fw_payload.bin
GCPT_BOOT_BIN := $(GCPT_RESTORE_HOME)/build/gcpt.bin
GCPT_RESTORE_BUILD_ROOT := $(GCPT_RESTORE_HOME)/restore-only
GCPT_RESTORE_BIN := $(GCPT_RESTORE_BUILD_ROOT)/build/gcpt.bin
GCPT_BIN := $(GCPT_RESTORE_HOME)/build/gcpt.bin
FIRMWARE_LOG_DIR ?= $(XS_PROJECT_ROOT)/log
BUILD_LOG_TAIL_LINES ?= 50
ROOTFS_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/rootfs-build.log
LINUX_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/linux-build.log
OPENSBI_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/opensbi-build.log
GCPT_BUILD_LOG ?= $(FIRMWARE_LOG_DIR)/gcpt-build.log
SHOW_FIRMWARE_BUILD_LOGS ?= 0
SHOW_ROOTFS_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_LINUX_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_OPENSBI_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
SHOW_GCPT_BUILD_LOG ?= $(SHOW_FIRMWARE_BUILD_LOGS)
LINUX_MAKE_JOBS ?= $(shell nproc)

.PHONY: all check-env download-linux setup-submodules init init-force build-rootfs build-linux build-dtb build-dtb-std build-dtb-xsai build-opensbi build-gcpt build-gcpt-restore build-gcpt-clean clean distclean help

all:
	@$(MAKE) build-rootfs 
	@$(MAKE) build-linux
	@$(MAKE) build-dtb
	@$(MAKE) build-opensbi
	@$(MAKE) build-gcpt
	@$(MAKE) build-gcpt-restore
	@echo "✓ Build complete!"
	@echo "  Linux Image: $(LINUX_IMAGE)"
	@echo "  DTB: $(DTB_FILE)"
	@echo "  OpenSBI Payload: $(OPENSBI_PAYLOAD)"
	@echo "  GCPT Boot Binary: $(GCPT_BOOT_BIN)"
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
	@echo "  build-linux      - Build Linux kernel"
	@echo "                     SHOW_LINUX_BUILD_LOG=1 to stream full kernel build logs"
	@echo "                     INITRAMFS_SOURCE=$(INITRAMFS_SOURCE)"
	@echo "                     INITRAMFS_COMMON_SOURCES=$(INITRAMFS_COMMON_SOURCES)"
	@echo "  build-dtb        - Build XSAI device tree blob (default)"
	@echo "  build-dtb-std    - Build standard XiangShan device tree blob"
	@echo "                     Optional: DIRECT_MAP_MEM_START=0x100000000 DIRECT_MAP_MEM_SIZE=0x180000000"
	@echo "  build-dtb-xsai   - Build XSAI-specific device tree blob"
	@echo "  build-opensbi    - Build OpenSBI firmware"
	@echo "  build-gcpt       - Build bootable GCPT binary linked with the payload"
	@echo "  build-gcpt-restore - Build restore-only GCPT binary for checkpoint resume"
	@echo "                     SHOW_OPENSBI_BUILD_LOG=1 to stream full OpenSBI build logs"
	@echo "                     SHOW_GCPT_BUILD_LOG=1 to stream full GCPT build logs"
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
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_ROOTFS_BUILD_LOG)" = "1" ]; then \
		cd $(RISCV_ROOTFS_HOME) && $(MAKE) rootfsimg -j; \
	else \
		cd $(RISCV_ROOTFS_HOME) && $(MAKE) rootfsimg -j > "$(ROOTFS_BUILD_LOG)" 2>&1 || { \
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
	@cd $(RISCV_LINUX_HOME) && \
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
		./scripts/config --set-str CONFIG_INITRAMFS_SOURCE "$(INITRAMFS_COMMON_SOURCES) $(INITRAMFS_SOURCE)" && \
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
		$(MAKE) prepare
	@echo "Building Linux kernel..."
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_LINUX_BUILD_LOG)" = "1" ]; then \
		cd $(RISCV_LINUX_HOME) && $(MAKE) -j$(LINUX_MAKE_JOBS); \
	else \
		cd $(RISCV_LINUX_HOME) && $(MAKE) -j$(LINUX_MAKE_JOBS) > "$(LINUX_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ Linux kernel build failed. Full log: $(LINUX_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(LINUX_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(LINUX_BUILD_LOG)"; \
			exit $$status; \
		}; \
		echo "  Linux build log: $(LINUX_BUILD_LOG)"; \
	fi
	@echo "✓ Linux kernel built: $(LINUX_IMAGE)"

build-dtb-std: setup-submodules
	@echo "Building device tree blob..."
	@cd $(WORKLOAD_BUILD_ENV_HOME)/dts && \
		mkdir -p build && \
		python3 DTSGen.py \
			--nr-harts 1 \
			--virtio-mmio 0x10001000 5 \
			--virtio-mmio 0x10002000 6 \
			--rva-profile rva23u64 \
			$(DTS_DIRECT_MAP_ARGS) \
			--bootargs "console=hvc0 earlycon=sbi" \
			--mmu-type riscv,sv39 | \
		dtc -O dtb -o build/xiangshan.dtb - || exit $$?
	@echo "✓ Standard DTB built: $(STD_DTB_FILE)"

build-dtb: build-dtb-xsai
	@echo "✓ Default DTB built for XSAI: $(XSAI_DTB_FILE)"

build-dtb-xsai: setup-submodules
	@echo "Building XSAI device tree blob..."
	@cd $(WORKLOAD_BUILD_ENV_HOME)/dts && \
		mkdir -p build && \
		python3 DTSGen.py \
			--compatible $(XSAI_COMPATIBLE) \
			--model "$(XSAI_MODEL)" \
			--cpu-compatible xiangshan,ai riscv \
			--nr-harts 1 \
			--virtio-mmio 0x10001000 5 \
			--virtio-mmio 0x10002000 6 \
			--rva-profile rva23u64 \
			--isa-extensions $(XSAI_EXTRA_ISA_EXTENSIONS) \
			--direct-map-mem $(XSAI_DIRECT_MAP_MEM_START) $(XSAI_DIRECT_MAP_MEM_SIZE) \
			--bootargs "console=hvc0 earlycon=sbi" \
			--memory-size $(XSAI_MEMORY_SIZE) \
			--mmu-type riscv,sv48 \
			--reserve-mem 0x80000000 0x100000 | \
		dtc -O dtb -o build/xiangshan_ai.dtb - || exit $$?
	@dtc -I dtb -O dts -o $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan_ai.dts \
		$(XSAI_DTB_FILE) || exit $$?
	@echo "✓ XSAI DTB built: $(XSAI_DTB_FILE)"
	@echo "  DTS dump:        $(WORKLOAD_BUILD_ENV_HOME)/dts/build/xiangshan_ai.dts"

# build-opensbi: build-linux build-dtb
# FW_PAYLOAD_FDT_ADDR is computed dynamically from the Linux Image size so that
# the DTB is placed after the kernel image with no overlap.
# Formula (mirrors checkpoint_scripts/generate_bbl.py build_opensbi()):
#   fdt_addr = round_up(image_size + 0x800000, 0x100000) + 0x80000000
build-opensbi:
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
	@FW_SIZE=$$(stat -c%s $(LINUX_IMAGE)) && \
	 FW_FDT_ADDR=$$(python3 -c \
	   "sz=$$FW_SIZE; print(hex(((sz+0x800000+0xfffff)//0x100000)*0x100000+0x80000000))") && \
	 echo "  Image size     : $$FW_SIZE bytes" && \
	 echo "  FW_PAYLOAD_FDT_ADDR: $$FW_FDT_ADDR" && \
	 if [ "$(SHOW_OPENSBI_BUILD_LOG)" = "1" ]; then \
		cd $(OPENSBI) && rm -rf build && $(MAKE) PLATFORM=generic \
			FW_PAYLOAD_PATH=$(LINUX_IMAGE) \
			FW_FDT_PATH=$(DTB_FILE) \
			FW_PAYLOAD_OFFSET=0x100000 \
			FW_PAYLOAD_FDT_ADDR=$$FW_FDT_ADDR \
			-j$(shell nproc); \
	 else \
		cd $(OPENSBI) && rm -rf build && $(MAKE) PLATFORM=generic \
			FW_PAYLOAD_PATH=$(LINUX_IMAGE) \
			FW_FDT_PATH=$(DTB_FILE) \
			FW_PAYLOAD_OFFSET=0x100000 \
			FW_PAYLOAD_FDT_ADDR=$$FW_FDT_ADDR \
			-j$(shell nproc) > "$(OPENSBI_BUILD_LOG)" 2>&1 || { \
				status=$$?; \
				echo "✗ OpenSBI build failed. Full log: $(OPENSBI_BUILD_LOG)"; \
				echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(OPENSBI_BUILD_LOG) ---"; \
				tail -n $(BUILD_LOG_TAIL_LINES) "$(OPENSBI_BUILD_LOG)"; \
				exit $$status; \
			}; \
		echo "  OpenSBI build log: $(OPENSBI_BUILD_LOG)"; \
	 fi
	@echo "✓ OpenSBI payload built: $(OPENSBI_PAYLOAD)"

build-gcpt:
	@if [ ! -f "$(GCPT_RESTORE_HOME)/Makefile" ]; then \
		echo "Initializing gcpt_restore submodule..."; \
		cd $(WORK_DIR) && git submodule update --init --force gcpt_restore; \
	fi
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_GCPT_BUILD_LOG)" = "1" ]; then \
		cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j && ls build/gcpt.bin; \
	else \
		( cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j && ls build/gcpt.bin ) > "$(GCPT_BUILD_LOG)" 2>&1 || { \
			status=$$?; \
			echo "✗ GCPT build failed. Full log: $(GCPT_BUILD_LOG)"; \
			echo "--- Last $(BUILD_LOG_TAIL_LINES) lines of $(GCPT_BUILD_LOG) ---"; \
			tail -n $(BUILD_LOG_TAIL_LINES) "$(GCPT_BUILD_LOG)"; \
			exit $$status; \
		}; \
			echo "  GCPT build log: $(GCPT_BUILD_LOG)"; \
		fi
	@echo "✓ GCPT boot binary built: $(GCPT_BOOT_BIN)"

build-gcpt-restore:
	@if [ ! -f "$(GCPT_RESTORE_HOME)/Makefile" ]; then \
		echo "Initializing gcpt_restore submodule..."; \
		cd $(WORK_DIR) && git submodule update --init --force gcpt_restore; \
	fi
	cd $(GCPT_RESTORE_HOME) && $(MAKE) O=$(GCPT_RESTORE_BUILD_ROOT) clean && $(MAKE) O=$(GCPT_RESTORE_BUILD_ROOT) -j && ls $(GCPT_RESTORE_BIN) || exit $$?

# Force a clean rebuild of gcpt (useful after editing src/csr.h etc.)
build-gcpt-clean:
	@mkdir -p $(FIRMWARE_LOG_DIR)
	@if [ "$(SHOW_GCPT_BUILD_LOG)" = "1" ]; then \
		cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j && ls build/gcpt.bin; \
	else \
		( cd $(GCPT_RESTORE_HOME) && $(MAKE) clean && $(MAKE) GCPT_PAYLOAD_PATH=$(OPENSBI_PAYLOAD) -j && ls build/gcpt.bin ) > "$(GCPT_BUILD_LOG)" 2>&1 || { \
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
	@echo "✓ Clean complete"

distclean: clean
	@echo "Removing all generated files..."
	@[ -d "$(RISCV_ROOTFS_HOME)" ] && cd $(RISCV_ROOTFS_HOME) && $(MAKE) distclean || true
	@rm -rf $(RISCV_LINUX_HOME)
	@rm -f $(LINUX_TARBALL)
	@git submodule deinit -f --all
	@echo "✓ Deep clean complete"

# =============================================================================
# Memory Layout Configuration — single source of truth
# =============================================================================
# Included by:
#   root Makefile                              (QEMU -m flag)
#   firmware/Makefile                          (DTB generation)
#   firmware/riscv-rootfs/apps/llama.cpp/Makefile  (cmake -DRESERVED_* flags)
#
# Physical address map (NEMU/QEMU board, RAM base 0x80000000):
#
#   0x080000000  ┌──────────────────────────────┐
#                │  boot / firmware reserve     │  ← XSAI_BOOT_RESERVE_SIZE
#                ├──────────────────────────────┤
#                │  Kernel-visible system RAM   │
#                │  for Linux / userspace       │
#                │  (minus the reserved ranges) │
#                ├──────────────────────────────┤  ← XSAI_DIRECT_MAP_MEM_START (default)
#                │  XSAI DMA-coherent pool      │  ← XSAI_DIRECT_MAP_MEM_SIZE
#                └──────────────────────────────┘  ← 0x80000000 + XSAI_MEMORY_SIZE
#
# By default the pool is carved out of the top of system RAM so a 2 GB guest
# can still reserve an XSAI pool without requiring guest RAM above 4 GB.
# If XSAI_DIRECT_MAP_MEM_START is overridden to an address beyond system RAM,
# MEMORY automatically expands to cover it.
#
# Derived QEMU/NEMU RAM size:
#   MEMORY = max(XSAI_MEMORY_SIZE,
#                XSAI_DIRECT_MAP_MEM_START + XSAI_DIRECT_MAP_MEM_SIZE - 0x80000000)
# =============================================================================

# Memory sizes use human-readable GB/MB values and are converted to raw byte
# counts for compatibility. Addresses stay in hexadecimal.
# Accepted suffixes for size knobs: MB, GB (also M, G). Raw 0x... overrides
# still work unchanged for size variables when needed.
define _xsai_human_to_hex
$(strip \
	$(if $(filter 0x% 0X%,$(1)),$(1), \
		$(if $(filter %GB,$(1)),$(shell printf '0x%x\n' $$(( $(patsubst %GB,%,$(1)) * 1024 * 1024 * 1024 ))), \
			$(if $(filter %G,$(1)),$(shell printf '0x%x\n' $$(( $(patsubst %G,%,$(1)) * 1024 * 1024 * 1024 ))), \
				$(if $(filter %MB,$(1)),$(shell printf '0x%x\n' $$(( $(patsubst %MB,%,$(1)) * 1024 * 1024 ))), \
					$(if $(filter %M,$(1)),$(shell printf '0x%x\n' $$(( $(patsubst %M,%,$(1)) * 1024 * 1024 ))), \
						$(1)))))))
endef

define _xsai_qemu_memory_size
$(strip $(shell sys_ram=$$(( $(1) )); \
	direct_end=$$(( $(2) + $(3) )); \
	ram_base=$$(( $(4) )); \
	total=$$(( direct_end - ram_base )); \
	if [ $$total -lt $$sys_ram ]; then total=$$sys_ram; fi; \
	if [ $$((total % (1024 * 1024 * 1024))) -eq 0 ]; then \
		printf '%sG\n' $$((total / (1024 * 1024 * 1024))); \
	elif [ $$((total % (1024 * 1024))) -eq 0 ]; then \
		printf '%sM\n' $$((total / (1024 * 1024))); \
	else \
		printf '%sK\n' $$(((total + 1023) / 1024)); \
	fi))
endef

define _xsai_hex_math
$(strip $(shell printf '0x%x\n' $$(( $(1) ))))
endef

XSAI_RAM_BASE ?= 0x80000000
XSAI_BOOT_RESERVE_SIZE ?= 0x100000

# System RAM in the DTB /memory node (kernel-visible, starts at 0x80000000).
XSAI_MEMORY_SIZE_HUMAN ?= 2GB
XSAI_MEMORY_SIZE ?= $(call _xsai_human_to_hex,$(XSAI_MEMORY_SIZE_HUMAN))

# XSAI DMA-coherent tensor pool (reserved, not in kernel address space).
# Start address stays hexadecimal; only the size uses the human-readable knob.
# Exported so all sub-makes inherit the values without extra passthrough rules.
export XSAI_DIRECT_MAP_MEM_START ?= $(call _xsai_hex_math,$(XSAI_RAM_BASE) + $(XSAI_MEMORY_SIZE) - $(XSAI_DIRECT_MAP_MEM_SIZE))
# Examples:
#   XSAI_DIRECT_MAP_MEM_SIZE_HUMAN ?= 1GB
#   XSAI_DIRECT_MAP_MEM_SIZE_HUMAN ?= 100MB
XSAI_DIRECT_MAP_MEM_SIZE_HUMAN ?= 100MB
export XSAI_DIRECT_MAP_MEM_SIZE ?= $(call _xsai_human_to_hex,$(XSAI_DIRECT_MAP_MEM_SIZE_HUMAN))

# QEMU/NEMU physical RAM size passed to -m flag.
# Auto-derived so the guest RAM always reaches the end of the direct-map pool.
MEMORY ?= $(call _xsai_qemu_memory_size,$(XSAI_MEMORY_SIZE),$(XSAI_DIRECT_MAP_MEM_START),$(XSAI_DIRECT_MAP_MEM_SIZE),$(XSAI_RAM_BASE))
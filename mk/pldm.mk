# =============================================================================
# PLDM Build Configuration
# =============================================================================
# Include this file to use PLDM presets, or set PLDM_CI=1 for CI config.
# =============================================================================

# PLDM packaging options
PLDM_TAR_PREFIX         ?= XSAI-pldm
PLDM_BUILD_BACKUP_PREFIX ?= $(NOOP_HOME)/.pldm-build-backup
PLDM_NEMU_SO            ?= $(XS_PROJECT_ROOT)/local/riscv64-nemu-interpreter-so
PLDM_SKIP_BUILD         ?= 0
PLDM_COMPRESS           ?= 1
PLDM_KEEP_BUILD         ?= 0

# Default PLDM configuration (local development)
PLDM_CONFIG_DEFAULT := DefaultMatrixConfig
PLDM_FLAGS_DEFAULT  := CONFIG=$(PLDM_CONFIG_DEFAULT) \
                       PLDM=1 MFC=1 \
                       WITH_CHISELDB=0 WITH_CONSTANTIN=0 \
                       SIM_MEM_SIZE=8 \
                       DEBUG_ARGS="--difftest-config ZESNHP"

# CI/Nightly configuration (matches .github/workflows/fpga.yml)
PLDM_CONFIG_CI      := DefaultMatrixConfig
PLDM_FLAGS_CI       := CONFIG=$(PLDM_CONFIG_CI) \
                       PLDM=1 NUM_CORES=1 \
                       WITH_CHISELDB=0 WITH_CONSTANTIN=0 \
                       DEBUG_ARGS="--difftest-config ZESNHP"

# Select config based on PLDM_CI flag
ifeq ($(PLDM_CI),1)
  PLDM_BUILD_FLAGS := $(PLDM_FLAGS_CI) -j
else
  PLDM_BUILD_FLAGS := $(PLDM_FLAGS_DEFAULT) -j
endif

# =============================================================================
# PLDM Targets
# =============================================================================

.PHONY: pldm

pldm:
ifeq ($(PLDM_SKIP_BUILD),0)
	@echo "Building sim-verilog in $(NOOP_HOME)..."
	$(MAKE) -C $(NOOP_HOME) WITH_DRAMSIM3=1 sim-verilog $(PLDM_BUILD_FLAGS)
else
	@echo "Skipping build (PLDM_SKIP_BUILD=1)..."
endif
	@XS_PROJECT_ROOT="$(XS_PROJECT_ROOT)" \
	NOOP_HOME="$(NOOP_HOME)" \
	PLDM_TAR_PREFIX="$(PLDM_TAR_PREFIX)" \
	PLDM_BUILD_BACKUP_PREFIX="$(PLDM_BUILD_BACKUP_PREFIX)" \
	PLDM_NEMU_SO="$(PLDM_NEMU_SO)" \
	PLDM_COMPRESS="$(PLDM_COMPRESS)" \
	PLDM_KEEP_BUILD="$(PLDM_KEEP_BUILD)" \
	./scripts/pldm-package.sh

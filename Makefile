.PHONY: help deps init init-force llvm update test clean nemu xsai test-matrix qemu run-qemu firmware versions simpoint profile cluster ckpt _ensure_qemu _ensure_firmware docker-nemu-image nemu-matrix-ref-so-docker

GIT_FORCE_INIT ?= 0

XS_PROJECT_ROOT := $(shell pwd)
NEMU_HOME := $(XS_PROJECT_ROOT)/NEMU
AM_HOME := $(XS_PROJECT_ROOT)/nexus-am
NOOP_HOME := $(XS_PROJECT_ROOT)/XSAI
LLVM_HOME := $(XS_PROJECT_ROOT)/local/llvm
QEMU_HOME := $(XS_PROJECT_ROOT)/qemu
GCPT_RESTORE_HOME := $(XS_PROJECT_ROOT)/firmware/gcpt_restore
PAYLOAD := $(GCPT_RESTORE_HOME)/build/gcpt.bin
SIMPOINT_RESULT_ROOT := $(XS_PROJECT_ROOT)/firmware/simpoints
CHECKPOINT_RESULT_ROOT := $(XS_PROJECT_ROOT)/firmware/checkpoints
CHECKPOINT_CONFIG := build
WORKLOAD_NAME := app
DOCKER_NEMU_IMAGE ?= xsai-centos7-build
DOCKER_UID ?= $(shell id -u)
DOCKER_GID ?= $(shell id -g)
DOCKER_USER ?= $(DOCKER_UID):$(DOCKER_GID)

# Checkpoint / SimPoint settings
SIMPOINT_HOME := $(NEMU_HOME)/resource/simpoint/simpoint_repo
SIMPOINT_BIN  := $(SIMPOINT_HOME)/bin/simpoint
MODEL_IMG     ?=
CPT_INTERVAL  ?= 10000000
PROFILING_INTERVALS ?= 10000000
SIMPOINT_MAX_K      ?= 10
MEMORY        ?= 16G
SMP           ?= 1
# Pass extra args straight to checkpoint.sh, e.g. CKPT_ARGS="--config my-run"
CKPT_ARGS     ?=

help:
	@echo "XSAI Environment Manager"
	@echo "Usage:"
	@echo "  make deps        - Install system dependencies (requires sudo)"
	@echo "  make init        - Initialize submodules and environment"
	@echo "  make init-force  - Force initialize submodules to avoid empty folders"
	@echo "  make llvm        - Build custom LLVM toolchain"
	@echo "  make nemu        - Build NEMU simulator"
	@echo "  make docker-nemu-image       - Build NEMU Docker image from centos.Dockerfile"
	@echo "  make nemu-matrix-ref-so-docker - Build riscv64-matrix-xs-ref shared library in Docker"
	@echo "  make xsai        - Build XSAI RTL simulation (Verilator)"
	@echo "  make test-matrix - Run matrix simple test"
	@echo "  make update      - Update submodules to latest"
	@echo "  make versions    - Regenerate VERSIONS file from current submodule state"
	@echo "  make test        - Test the environment"
	@echo "  make run-qemu    - Run QEMU simulation with GCPT payload"
	@echo "  make clean       - Clean build artifacts"
	@echo ""
	@echo "SimPoint Checkpoint targets (require MODEL_IMG=<path/to/disk.img>):"
	@echo "  make simpoint    - Build the SimPoint clustering binary"
	@echo "  make profile     - Phase 1: QEMU profiling (BBV collection)"
	@echo "  make cluster     - Phase 2: SimPoint clustering"
	@echo "  make ckpt        - Full 3-phase checkpoint flow (profile→cluster→checkpoint)"
	@echo "  make ckpt PHASE=profile|cluster|checkpoint  - Run a single phase"
	@echo "  Knobs: WORKLOAD_NAME CPT_INTERVAL PROFILING_INTERVALS SIMPOINT_MAX_K"
	@echo "         MEMORY SMP CHECKPOINT_CONFIG MODEL_IMG CKPT_ARGS"

deps:
	./scripts/setup-tools.sh

init:
	GIT_FORCE_INIT=$(GIT_FORCE_INIT) ./scripts/setup.sh

init-force:
	$(MAKE) init GIT_FORCE_INIT=1

llvm:
	./scripts/build-llvm.sh

qemu:
	cd qemu && mkdir -p build && cd build && ../configure --target-list=riscv64-softmmu,riscv64-linux-user \
	--enable-debug --enable-zstd --enable-plugins && make -j && cd ../..

nemu:
	$(MAKE) -C $(NEMU_HOME) riscv64-matrix-xs_defconfig
	$(MAKE) -C $(NEMU_HOME) -j

docker-nemu-image:
	docker build -f centos.Dockerfile -t $(DOCKER_NEMU_IMAGE) .

nemu-matrix-ref-so-docker:
	docker run --rm --user "$(DOCKER_USER)" -e HOME=/tmp -v "$(XS_PROJECT_ROOT)":/work -w /work $(DOCKER_NEMU_IMAGE) bash -lc 'source /etc/profile && export NEMU_HOME=/work/NEMU && make -C "$$NEMU_HOME" distclean && make -C "$$NEMU_HOME" riscv64-matrix-xs-ref_defconfig && make -C "$$NEMU_HOME" -j"$$(nproc)" && cp "$$NEMU_HOME"/build/riscv64-nemu-interpreter-so /work/local/riscv64-nemu-interpreter-so && make -C "$$NEMU_HOME" distclean'

emu-verilator:
	$(MAKE) -C $(NOOP_HOME) emu -j8 CONFIG=DefaultMatrixConfig WITH_CHISELDB=1 WITH_CONSTANTIN=0 EMU_THREADS=8 EMU_TRACE=fst

emu-gsim:
	$(MAKE) -C $(NOOP_HOME) gsim -j CONFIG=DefaultMatrixConfig EMU_TRACE="fst" GSIM=1

test-matrix:
	$(NEMU_HOME)/build/riscv64-nemu-interpreter -b $(AM_HOME)/apps/llama/llama-riscv64-xs.bin

update:
	./scripts/update-submodule.sh

versions:
	./scripts/update-versions.sh

test:
	./scripts/env-test.sh
firmware:
	$(MAKE) -C firmware all

DIFF      ?= 0
LOG       ?= 0
EMU_SCRIPT := ./scripts/run-emu.sh
EMU_FLAGS   = $(if $(filter 1,$(LOG)),--log,) $(if $(filter 1,$(DIFF)),--diff,)

run-emu:
	$(EMU_SCRIPT) $(EMU_FLAGS) $(PAYLOAD)

run-nemu:
	$(NEMU_HOME)/build/riscv64-nemu-interpreter -b $(PAYLOAD)

# export QEMU_LD_PREFIX=sysroot_path
# Setting QEMU_LD_PREFIX is necessary to avoid "Could not open '/lib/ld-linux-riscv64-lp64d.so.1': No such file or directory"
# The sysroot_path should be set to your compiler's sysroot path, for example: QEMU_LD_PREFIX=/opt/riscv/sysroot
run-user:
	@$(QEMU_HOME)/build/qemu-riscv64 -cpu rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 firmware/riscv-rootfs/rootfsimg/build/hello_xsai

run-qemu:
	@echo "Running QEMU simulation with GCPT payload..."
	@mkdir -p $(CHECKPOINT_RESULT_ROOT)/$(CHECKPOINT_CONFIG)
	@$(QEMU_HOME)/build/qemu-system-riscv64 \
		-bios $(PAYLOAD) \
		-nographic -m 24G -smp 1 \
		-serial mon:stdio \
		-cpu rv64,v=true,vlen=128,h=true,sstc=true,svpbmt=true,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32,sv39=true,sv48=true,sv57=false,sv64=false \
		-M nemu
# 		,workload=$(WORKLOAD_NAME),cpt-interval=100000000,output-base-dir=$(CHECKPOINT_RESULT_ROOT),config-name=$(CHECKPOINT_CONFIG),checkpoint-mode=UniformCheckpoint
	@echo "✓ QEMU simulation completed"
	@echo "Checkpoints saved to: $(CHECKPOINT_RESULT_ROOT)/$(CHECKPOINT_CONFIG)/$(WORKLOAD_NAME)/"
# 	@ls $(CHECKPOINT_RESULT_ROOT)/$(CHECKPOINT_CONFIG)/$(WORKLOAD_NAME)/ 2>/dev/null || echo "(directory empty or not found)"
# 		-device virtio-blk-device,drive=drv0 \
# 		-drive file=llama.img,if=none,id=drv0,format=raw 

# ---------------------------------------------------------------------------
# SimPoint — init nested submodule (if needed) then build the binary
# ---------------------------------------------------------------------------
simpoint: $(SIMPOINT_BIN)

$(SIMPOINT_BIN):
	@echo "Initializing SimPoint submodule..."
	git -C $(NEMU_HOME) submodule update --init resource/simpoint/simpoint_repo
	@echo "Building SimPoint binary..."
	$(MAKE) -C $(SIMPOINT_HOME) simpoint
	@echo "✓ SimPoint binary: $(SIMPOINT_BIN)"

# ---------------------------------------------------------------------------
# Checkpoint phases — delegate to scripts/checkpoint.sh
#
# Dependency chain:
#   profile    → qemu (libprofiling.so) + firmware (gcpt.bin)  [only if missing]
#   cluster    → simpoint binary
#   checkpoint → qemu + firmware (gcpt.bin)                    [only if missing]
#   ckpt (all) → all of the above
#
# Knobs (all optional, have defaults):
#   WORKLOAD_NAME CHECKPOINT_CONFIG CPT_INTERVAL PROFILING_INTERVALS
#   SIMPOINT_MAX_K MEMORY SMP MODEL_IMG CKPT_ARGS
# ---------------------------------------------------------------------------
PROFILING_PLUGIN := $(QEMU_HOME)/build/contrib/plugins/libprofiling.so
CKPT_SCRIPT := ./scripts/checkpoint.sh
# RESUME_CHECKPOINT: optional path to an existing checkpoint to warm-start profiling
# Leave empty (default) for a cold-start profiling run.
RESUME_CHECKPOINT ?=
CKPT_COMMON_FLAGS = \
	--workload $(WORKLOAD_NAME) \
	--config $(CHECKPOINT_CONFIG) \
	--cpt-interval $(CPT_INTERVAL) \
	--intervals $(PROFILING_INTERVALS) \
	--max-k $(SIMPOINT_MAX_K) \
	--memory $(MEMORY) \
	--smp $(SMP) \
	--payload $(PAYLOAD) \
	--result-root $(CHECKPOINT_RESULT_ROOT) \
	$(if $(MODEL_IMG),--img $(MODEL_IMG),) \
	$(if $(RESUME_CHECKPOINT),--resume $(RESUME_CHECKPOINT),) \
	$(CKPT_ARGS)

# Only build qemu/firmware when the output files are actually missing.
# Using shell guards here avoids triggering PHONY targets on every invocation.
_ensure_qemu:
	@test -f $(PROFILING_PLUGIN) || $(MAKE) qemu

_ensure_firmware:
	@test -f $(PAYLOAD) || $(MAKE) firmware

profile: _ensure_qemu _ensure_firmware
	$(CKPT_SCRIPT) profile $(CKPT_COMMON_FLAGS)

cluster: $(SIMPOINT_BIN)
	$(CKPT_SCRIPT) cluster $(CKPT_COMMON_FLAGS)

PHASE ?= all
ckpt: $(SIMPOINT_BIN) _ensure_qemu _ensure_firmware
	$(CKPT_SCRIPT) $(PHASE) $(CKPT_COMMON_FLAGS)

# Dump every N instructions across the whole execution, no SimPoint needed
uniform: _ensure_qemu _ensure_firmware
	$(CKPT_SCRIPT) uniform $(CKPT_COMMON_FLAGS)


clean:
	rm -rf build
	rm -rf local/llvm

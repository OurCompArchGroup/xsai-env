.PHONY: help deps init init-force llvm gsim nix-shell nix-init nix-test nix-firmware smoke test-smoke nix-smoke update test clean distclean nemu xsai test-matrix qemu run-qemu firmware versions simpoint profile cluster ckpt uniform ccdb ccdb-append pldm _ensure_qemu _ensure_firmware docker-nemu-image nemu-matrix-ref-so-docker

SHELL := /bin/bash

GIT_FORCE_INIT ?= 1

XS_PROJECT_ROOT ?= $(shell pwd)
NEMU_HOME ?= $(XS_PROJECT_ROOT)/NEMU
AM_HOME ?= $(XS_PROJECT_ROOT)/nexus-am
NOOP_HOME ?= $(XS_PROJECT_ROOT)/XSAI
LLVM_HOME ?= $(XS_PROJECT_ROOT)/local/llvm
QEMU_HOME ?= $(XS_PROJECT_ROOT)/qemu
QEMU_HOST_CC ?= gcc
QEMU_HOST_CXX ?= g++
GCPT_RESTORE_HOME ?= $(XS_PROJECT_ROOT)/firmware/gcpt_restore
export XS_PROJECT_ROOT NEMU_HOME AM_HOME NOOP_HOME LLVM_HOME QEMU_HOME GCPT_RESTORE_HOME
NIX_DEVSHELL ?= .\#default
NIX_DEVELOP ?= nix develop $(NIX_DEVSHELL) -c
# LibCheckpoint for multicore flows

PAYLOAD := $(GCPT_RESTORE_HOME)/build/gcpt.bin

# Canonical QEMU CPU flags — keep in sync with scripts/checkpoint.sh CPU_FLAGS
QEMU_CPU_FLAGS ?= rv64,v=true,vlen=128,h=true,sstc=true,svpbmt=true,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32,sv39=true,sv48=true,sv57=false,sv64=false

QEMU_CPU_FLAGS := rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32,sv39=true,sv48=false,sv57=false,sv64=false
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
CPT_INTERVAL  ?= 100000
PROFILING_INTERVALS ?= $(CPT_INTERVAL)
SIMPOINT_MAX_K      ?= 10
MEMORY        ?= 4G
SMP           ?= 1
# Pass extra args straight to checkpoint.sh, e.g. CKPT_ARGS="--config my-run"
CKPT_ARGS     ?=
CCDB          ?= $(XS_PROJECT_ROOT)/local/compile_commands.json
CCDB_MAKE     ?= firmware
CCDB_SCRIPT   := ./scripts/update-compile-commands.sh
PLDM_TAR_PREFIX ?= XSAI-pldm
PLDM_BUILD_TARGET ?= verilog
PLDM_BUILD_FLAGS ?= WITH_CHISELDB=0 WITH_CONSTANTIN=0 MFC=1 PLDM=1
PLDM_BUILD_BACKUP_PREFIX ?= $(NOOP_HOME)/.pldm-build-backup
PLDM_NEMU_SO ?= $(XS_PROJECT_ROOT)/local/riscv64-nemu-interpreter-so
PLDM_SKIP_BUILD ?= 0
PLDM_COMPRESS ?= 0

help:
	@echo "XSAI Environment Manager"
	@echo "Usage:"
	@echo "  make deps        - Install system dependencies (requires sudo)"
	@echo "  make init        - Initialize submodules and environment"
	@echo "  make init-force  - Force initialize submodules to avoid empty folders"
	@echo "  make llvm        - Build custom LLVM toolchain"
	@echo "  make gsim        - Install the latest gsim binary to local/bin"
	@echo "  make nix-shell   - Enter the reproducible Nix devshell"
	@echo "  make nix-init    - Run make init-force inside the Nix devshell"
	@echo "  make nix-test    - Run make test inside the Nix devshell"
	@echo "  make test-smoke  - Run fast non-build smoke checks"
	@echo "  make nix-smoke   - Run smoke checks inside the Nix devshell"
	@echo "  make nemu        - Build NEMU simulator"
	@echo "  make docker-nemu-image       - Build NEMU Docker image from centos.Dockerfile"
	@echo "  make nemu-matrix-ref-so-docker - Build riscv64-matrix-xs-ref shared library in Docker"
	@echo "  make xsai        - Build XSAI RTL simulation (Verilator)"
	@echo "  make test-matrix - Run matrix simple test"
	@echo "  make update      - Update submodules to latest"
	@echo "  make versions    - Regenerate VERSIONS file from current submodule state"
	@echo "  make pldm        - Build XSAI verilog, package it, then restore build/"
	@echo "                     PLDM_SKIP_BUILD=1 skips make; PLDM_COMPRESS=0 writes .tar"
	@echo "  make test        - Test the environment"
	@echo "  make run-qemu    - Run QEMU simulation with GCPT payload"
	@echo "  make ccdb        - Rebuild unified compile_commands.json via bear"
	@echo "  make ccdb-append - Append a build to compile_commands.json and deduplicate"
	@echo "  make run-emu-debug PAYLOAD=<p> DIFF=1 WAVE_BEGIN=50000 WAVE_END=180000"
	@echo "                   - RTL debug: FST wave + ChiselDB (set FORK=1 to skip wave)"
	@echo "  make clean       - Clean build artifacts (NEMU, AM, firmware, build/)"
	@echo "  make distclean   - Deep clean including LLVM, qemu build, firmware submodules"
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

gsim:
	./scripts/install-gsim.sh

nix-shell:
	nix develop $(NIX_DEVSHELL)

nix-init:
	$(NIX_DEVELOP) make init-force

nix-test:
	$(NIX_DEVELOP) make test

nix-firmware:
	$(NIX_DEVELOP) make firmware

test-smoke:
	./scripts/smoke-test.sh --mode manual

smoke: test-smoke

nix-smoke:
	$(NIX_DEVELOP) ./scripts/smoke-test.sh --mode nix

qemu:
	cd qemu && mkdir -p build && cd build && \
	env \
	  -u CROSS_COMPILE -u CC -u CXX -u AR -u AS -u LD -u NM -u OBJCOPY -u OBJDUMP -u RANLIB -u STRIP \
	  NIX_HARDENING_ENABLE="$${NIX_HARDENING_ENABLE//fortify/}" \
	  ../configure \
	    --cc=$(QEMU_HOST_CC) \
	    --host-cc=$(QEMU_HOST_CC) \
	    --cross-prefix= \
	    --target-list=riscv64-softmmu,riscv64-linux-user \
	    --disable-sdl --disable-gtk --disable-opengl --disable-slirp \
	    --enable-zstd --enable-plugins && \
	$(MAKE) -j

nemu:
	$(MAKE) -C $(NEMU_HOME) riscv64-matrix-xs_defconfig
	$(MAKE) -C $(NEMU_HOME) -j

docker-nemu-image:
	docker build -f centos.Dockerfile -t $(DOCKER_NEMU_IMAGE) .

nemu-matrix-ref-so-docker:
	docker run --rm --user "$(DOCKER_USER)" -e HOME=/tmp -v "$(XS_PROJECT_ROOT)":/work -w /work $(DOCKER_NEMU_IMAGE) bash -lc 'source /etc/profile && export NEMU_HOME=/work/NEMU && make -C "$$NEMU_HOME" distclean && make -C "$$NEMU_HOME" riscv64-matrix-xs-ref_defconfig && make -C "$$NEMU_HOME" -j"$$(nproc)" && cp "$$NEMU_HOME"/build/riscv64-nemu-interpreter-so /work/local/riscv64-nemu-interpreter-so && make -C "$$NEMU_HOME" distclean'

emu-verilator:
	$(MAKE) -C $(NOOP_HOME) emu -j8 CONFIG=DefaultMatrixConfig WITH_CHISELDB=1 WITH_CONSTANTIN=0 EMU_THREADS=8 EMU_TRACE=fst

xsai: emu-verilator

emu-gsim:
	$(MAKE) -C $(NOOP_HOME) gsim -j CONFIG=DefaultMatrixConfig EMU_TRACE="fst" GSIM=1

test-matrix:
	$(MAKE) -C ${AM_HOME}/tests/ame0.6 TOOLCHAIN=LLVM
	$(MAKE) -C ${AM_HOME}/tests/ame0.6 TOOLCHAIN=LLVM  run-emu

update:
	./scripts/update-submodule.sh

versions:
	./scripts/update-versions.sh

pldm:
	@XS_PROJECT_ROOT="$(XS_PROJECT_ROOT)" \
	NOOP_HOME="$(NOOP_HOME)" \
	PLDM_TAR_PREFIX="$(PLDM_TAR_PREFIX)" \
	PLDM_BUILD_TARGET="$(PLDM_BUILD_TARGET)" \
	PLDM_BUILD_FLAGS="$(PLDM_BUILD_FLAGS)" \
	PLDM_BUILD_BACKUP_PREFIX="$(PLDM_BUILD_BACKUP_PREFIX)" \
	PLDM_NEMU_SO="$(PLDM_NEMU_SO)" \
	PLDM_SKIP_BUILD="$(PLDM_SKIP_BUILD)" \
	PLDM_COMPRESS="$(PLDM_COMPRESS)" \
	./scripts/pldm-package.sh
test:
	./scripts/env-test.sh
firmware:
	$(MAKE) -C firmware all

ccdb:
	$(CCDB_SCRIPT) --db "$(CCDB)" -- make $(CCDB_MAKE)

ccdb-append:
	$(CCDB_SCRIPT) --append --db "$(CCDB)" -- make $(CCDB_MAKE)

DIFF      ?= 0
LOG       ?= 0
EMU_SCRIPT := ./scripts/run-emu.sh
EMU_FLAGS   = $(if $(filter 1,$(LOG)),--log,) $(if $(filter 1,$(DIFF)),--diff,)

run-emu: _ensure_emu
	$(EMU_SCRIPT) $(EMU_FLAGS) $(PAYLOAD)

# RTL debug shortcut — captures both FST waveform and ChiselDB in one pass.
# Usage: make run-emu-debug PAYLOAD=<path> DIFF=1 WAVE_BEGIN=50000 WAVE_END=180000
#        make run-emu-debug PAYLOAD=<path> DIFF=1 FORK=1  # no wave, DB only (faster)
WAVE_BEGIN  ?=
WAVE_END    ?=
WARMUP      ?=
MAX_INSTR   ?=
FORK        ?= 0
DB_SELECT   ?= lifetime
_WAVE_FLAGS  = $(if $(filter 0,$(FORK)),--wave $(if $(WAVE_BEGIN),-b $(WAVE_BEGIN)) $(if $(WAVE_END),-e $(WAVE_END)))
_FORK_FLAG   = $(if $(filter 1,$(FORK)),--fork)
_W_FLAG      = $(if $(WARMUP),-W $(WARMUP))
_I_FLAG      = $(if $(MAX_INSTR),-I $(MAX_INSTR))

run-emu-debug: _ensure_emu
	$(EMU_SCRIPT) $(EMU_FLAGS) --log \
	  $(if $(WARMUP),-W $(WARMUP)) \
	  $(if $(MAX_INSTR),-I $(MAX_INSTR)) \
	  $(_WAVE_FLAGS) $(_FORK_FLAG) \
	  --db --db-select "$(DB_SELECT)" \
	  $(PAYLOAD)

RESTORER  ?= $(GCPT_RESTORE_HOME)/build/gcpt.bin

run-nemu: _ensure_nemu
	@case "$(PAYLOAD)" in \
	  *.gz|*.zstd|*.zst) \
	    $(NEMU_HOME)/build/riscv64-nemu-interpreter -b $(PAYLOAD) -r $(RESTORER) ;; \
	  *) \
	    $(NEMU_HOME)/build/riscv64-nemu-interpreter -b $(PAYLOAD) ;; \
	esac

# export QEMU_LD_PREFIX=sysroot_path
# Setting QEMU_LD_PREFIX is necessary to avoid "Could not open '/lib/ld-linux-riscv64-lp64d.so.1': No such file or directory"
# The sysroot_path should be set to your compiler's sysroot path, for example: QEMU_LD_PREFIX=/opt/riscv/sysroot
run-user:
	@$(QEMU_HOME)/build/qemu-riscv64 -cpu $(QEMU_CPU_FLAGS) firmware/riscv-rootfs/rootfsimg/build/hello_xsai

run-qemu: _ensure_qemu
	@echo "Running QEMU simulation..."
	@case "$(PAYLOAD)" in \
	  *.gz|*.zstd|*.zst) \
	    $(QEMU_HOME)/build/qemu-system-riscv64 \
	      -M nemu,checkpoint=$(PAYLOAD),gcpt-restore=$(RESTORER) \
	      -nographic -m $(MEMORY) -smp $(SMP) \
	      -serial mon:stdio \
	      -cpu $(QEMU_CPU_FLAGS) ;; \
	  *) \
	    $(QEMU_HOME)/build/qemu-system-riscv64 \
	      -bios $(PAYLOAD) \
	      -nographic -m $(MEMORY) -smp $(SMP) \
	      -serial mon:stdio \
	      -cpu $(QEMU_CPU_FLAGS) \
	      -M nemu ;; \
	esac
	@echo "✓ QEMU simulation completed"

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
CKPT_SCRIPT := CPU_FLAGS='$(QEMU_CPU_FLAGS)' ./scripts/checkpoint.sh
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

_ensure_emu:
	@test -f $(NOOP_HOME)/build/emu || $(MAKE) emu-verilator

_ensure_nemu:
	@test -f $(NEMU_HOME)/build/riscv64-nemu-interpreter || $(MAKE) nemu

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
	$(MAKE) -C $(NEMU_HOME) clean
	$(MAKE) -C firmware clean

distclean:
	$(MAKE) -C $(NEMU_HOME) distclean
	$(MAKE) -C firmware distclean
	@rm -rf local/llvm
	@[ -d qemu/build ] && $(MAKE) -C qemu/build distclean || true

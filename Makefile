.PHONY: help deps init init-force llvm gsim nix-shell nix-init nix-test smoke test-smoke nix-smoke update test clean distclean nemu xsai test-matrix qemu run-qemu firmware versions simpoint profile cluster ckpt uniform ccdb ccdb-append pldm _ensure_qemu _ensure_firmware docker-nemu-image nemu-matrix-ref-so-docker

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
CPT_INTERVAL  ?= 100
PROFILING_INTERVALS ?= $(CPT_INTERVAL)
SIMPOINT_MAX_K      ?= 10
SMP           ?= 1
# Pass extra args straight to checkpoint.sh, e.g. CKPT_ARGS="--config my-run"
CKPT_ARGS     ?=
# llama.cpp model selection (passed through to firmware/riscv-rootfs/apps/llama.cpp)
LLAMA_MODEL_PRESET  ?= stories15M
LLAMA_MODEL_KIND    ?=
LLAMA_MODEL_NAME    ?=
LLAMA_MODEL_PATH    ?=
LLAMA_MODEL_QUANTIZE ?=

CCDB          ?= $(XS_PROJECT_ROOT)/local/compile_commands.json
CCDB_MAKE     ?= firmware
CCDB_SCRIPT   := ./scripts/update-compile-commands.sh

help:
	@echo "XSAI Environment Manager"
	@echo "Usage:"
	@echo "  make deps        - Install system dependencies (requires sudo)"
	@echo "  make init        - Initialize submodules and environment"
	@echo "  make init-force  - Force initialize submodules to avoid empty folders"
	@echo "  make llvm        - Build custom LLVM toolchain (uses system compiler)"
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
	@echo "                     Optional: MODEL_IMG=<path/to/disk.img> attaches /dev/vda via virtio-blk"
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

# Include PLDM build configurations
include mk/pldm.mk
# Memory layout defaults (QEMU size, DTB node, XSAI pool)
include mk/memory.mk

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

test:
	./scripts/env-test.sh
# Build model passthrough flags (only override when user set non-default values)
_LLAMA_EXTRA :=
ifneq ($(LLAMA_MODEL_PRESET),stories15M)
_LLAMA_EXTRA += MODEL_PRESET=$(LLAMA_MODEL_PRESET)
endif
ifneq ($(LLAMA_MODEL_KIND),)
_LLAMA_EXTRA += MODEL_KIND=$(LLAMA_MODEL_KIND)
endif
ifneq ($(LLAMA_MODEL_NAME),)
_LLAMA_EXTRA += MODEL_NAME=$(LLAMA_MODEL_NAME)
endif
ifneq ($(LLAMA_MODEL_PATH),)
_LLAMA_EXTRA += MODEL_SOURCE_PATH=$(abspath $(LLAMA_MODEL_PATH))
endif
ifneq ($(LLAMA_MODEL_QUANTIZE),)
_LLAMA_EXTRA += MODEL_QUANTIZE=$(LLAMA_MODEL_QUANTIZE)
endif

firmware:
	$(MAKE) -C firmware all $(_LLAMA_EXTRA)

ccdb:
	$(CCDB_SCRIPT) --db "$(CCDB)" -- make $(CCDB_MAKE)

ccdb-append:
	$(CCDB_SCRIPT) --append --db "$(CCDB)" -- make $(CCDB_MAKE)

DIFF      ?= 1
LOG       ?= 0
EMU_SCRIPT := ./scripts/run-emu.sh
EMU_FLAGS   = $(if $(filter 1,$(LOG)),--log,) $(if $(filter 1,$(DIFF)),--diff,)

run-emu: _ensure_payload _ensure_emu
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

run-nemu: _ensure_payload _ensure_nemu
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

run-qemu: _ensure_payload _ensure_qemu _ensure_model_img
	@echo "Running QEMU simulation..."
	@set -- $(QEMU_HOME)/build/qemu-system-riscv64 \
		-nographic -m $(MEMORY) -smp $(SMP) \
		-serial mon:stdio \
		-cpu "$(QEMU_CPU_FLAGS)"; \
	if [ -n "$(MODEL_IMG)" ]; then \
		drive_opts='file=$(abspath $(MODEL_IMG)),if=none,id=drv0,format=raw'; \
		echo "  Disk image: $(abspath $(MODEL_IMG))"; \
		if [ ! -w "$(MODEL_IMG)" ]; then \
			drive_opts="$$drive_opts,readonly=on"; \
			echo "  Disk image access: read-only"; \
		fi; \
		set -- "$$@" \
			-device virtio-blk-device,drive=drv0 \
			-drive "$$drive_opts"; \
	fi; \
	case "$(PAYLOAD)" in \
	  *.gz|*.zstd|*.zst) \
	    set -- "$$@" -M nemu,checkpoint=$(PAYLOAD),gcpt-restore=$(RESTORER) ;; \
	  *) \
	    set -- "$$@" -bios "$(PAYLOAD)" -M nemu ;; \
	esac; \
	"$$@"
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

_ensure_model_img:
	@if [ -n "$(MODEL_IMG)" ] && [ ! -f "$(MODEL_IMG)" ]; then \
		echo "Disk image not found: $(MODEL_IMG)" >&2; \
		exit 1; \
	fi

_ensure_payload:
	@case "$(PAYLOAD)" in \
	  "$(GCPT_RESTORE_HOME)/build/gcpt.bin") \
	    if [ ! -f "$(PAYLOAD)" ]; then \
	      echo "[payload] gcpt.bin not found, building firmware..."; \
	      $(MAKE) firmware; \
	    fi ;; \
	  *) \
	    test -f "$(PAYLOAD)" || { echo "Payload not found: $(PAYLOAD)" >&2; exit 1; } ;; \
	esac

_ensure_firmware:
	@$(MAKE) _ensure_payload

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

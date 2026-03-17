.PHONY: help deps init init-force llvm update test clean nemu xsai test-matrix qemu run-qemu firmware

GIT_FORCE_INIT ?= 0

XS_PROJECT_ROOT := $(shell pwd)
NEMU_HOME := $(XS_PROJECT_ROOT)/NEMU
AM_HOME := $(XS_PROJECT_ROOT)/nexus-am
NOOP_HOME := $(XS_PROJECT_ROOT)/XSAI
LLVM_HOME := $(XS_PROJECT_ROOT)/local/llvm
QEMU_HOME := $(XS_PROJECT_ROOT)/qemu
PAYLOAD := $(XS_PROJECT_ROOT)/NEMU/resource/gcpt_restore/build/gcpt.bin
SIMPOINT_RESULT_ROOT := $(XS_PROJECT_ROOT)/firmware/simpoints
CHECKPOINT_RESULT_ROOT := $(XS_PROJECT_ROOT)/firmware/checkpoints
CHECKPOINT_CONFIG := build
WORKLOAD_NAME := app

help:
	@echo "XSAI Environment Manager"
	@echo "Usage:"
	@echo "  make deps        - Install system dependencies (requires sudo)"
	@echo "  make init        - Initialize submodules and environment"
	@echo "  make init-force  - Force initialize submodules to avoid empty folders"
	@echo "  make llvm        - Build custom LLVM toolchain"
	@echo "  make nemu        - Build NEMU simulator"
	@echo "  make xsai        - Build XSAI RTL simulation (Verilator)"
	@echo "  make test-matrix - Run matrix simple test"
	@echo "  make update      - Update submodules to latest"
	@echo "  make test        - Test the environment"
	@echo "  make run-qemu    - Run QEMU simulation with GCPT payload"
	@echo "  make clean       - Clean build artifacts"

deps:
	./scripts/setup-tools.sh

init:
	GIT_FORCE_INIT=$(GIT_FORCE_INIT) ./scripts/setup.sh

init-force:
	$(MAKE) init GIT_FORCE_INIT=1

llvm:
	./scripts/build-llvm.sh

qemu:
	cd qemu && mkdir -p build && cd build && ../configure --target-list=riscv64-softmmu,riscv64-linux-user --enable-debug --enable-zstd && make -j && cd ../..

nemu:
	$(MAKE) -C $(NEMU_HOME) riscv64-matrix-xs_defconfig
	$(MAKE) -C $(NEMU_HOME) -j

emu-verilator:
	$(MAKE) -C $(NOOP_HOME) emu -j8 CONFIG=DefaultMatrixConfig WITH_CHISELDB=1 WITH_CONSTANTIN=0 EMU_THREADS=8 EMU_TRACE=fst

emu-gsim:
	$(MAKE) -C $(NOOP_HOME) gsim GSIM=1 -j8 CONFIG=DefaultMatrixConfig WITH_CHISELDB=1 WITH_CONSTANTIN=0 EMU_THREADS=8 EMU_TRACE=fst

test-matrix:
	$(NEMU_HOME)/build/riscv64-nemu-interpreter -b $(AM_HOME)/apps/llama/llama-riscv64-xs.bin

update:
	./scripts/update-submodule.sh

test:
	./scripts/env-test.sh
firmware:
	$(MAKE) -C firmware all

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
		-nographic -m 16G -smp 1 \
		-serial mon:stdio \
		-cpu rv64,v=true,vlen=128,h=false,sstc=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32,sv39=true,sv48=true,sv57=false,sv64=false \
		-M nemu
## ,workload=$(WORKLOAD_NAME),cpt-interval=10000,output-base-dir=$(CHECKPOINT_RESULT_ROOT),config-name=$(CHECKPOINT_CONFIG),checkpoint-mode=SimpointCheckpoint,simpoint-path=$(SIMPOINT_RESULT_ROOT)
	@echo "✓ QEMU simulation completed"
# 		-device virtio-blk-device,drive=drv0 \
# 		-drive file=llama.img,if=none,id=drv0,format=raw 

clean:
	rm -rf build
	rm -rf local/llvm

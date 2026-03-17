# XSAI Development Environment

This repository provides an out-of-the-box development environment for XSAI (XiangShan AI), including simulation, firmware, custom LLVM toolchain, and AME (Advanced Matrix Extension) support.

## Quick Start

### 1. Setup

Clone the repository and initialize the environment. This only needs to be done once.

```bash
git clone https://github.com/Gs-ygc/xsai-env
cd xsai-env
sudo make deps        # Install system dependencies (Ubuntu/Debian)
make init             # Initialize submodules
make init-force       # Force checkout submodules (recommended for CI / self-hosted runners)
```

### 2. Environment Variables

Load the environment before working. We recommend [direnv](https://direnv.net/) for automatic loading:

```bash
# Option A: direnv (auto-loads on cd)
direnv allow

# Option B: manual
source env.sh
```

Key variables set by `.envrc` / `env.sh`:

| Variable | Value |
|---|---|
| `XS_PROJECT_ROOT` | repo root |
| `NEMU_HOME` | `./NEMU` |
| `AM_HOME` | `./nexus-am` |
| `NOOP_HOME` | `./XSAI` |
| `LLVM_HOME` | `./local/llvm` |
| `RISCV_ROOTFS_HOME` | `./firmware/riscv-rootfs` |
| `RISCV` | `/opt/riscv/` |

## Build Targets

All targets are available via `make <target>` from the repo root.

### Toolchain

```bash
make llvm            # Build custom LLVM/Clang with AME support → local/llvm
```

To install the latest [gsim](https://github.com/OpenXiangShan/gsim) simulator binary:

```bash
bash scripts/install-gsim.sh   # installs to local/bin/gsim
```

### Simulation

```bash
make nemu            # Build NEMU (RISC-V instruction set simulator)
make emu-verilator   # Build Verilator RTL simulation (XSAI)
make emu-gsim        # Build gsim-based RTL simulation (XSAI)
make qemu            # Build QEMU (riscv64-softmmu + riscv64-linux-user)
```

### Firmware

```bash
make firmware        # Build all firmware:
                     #   Linux kernel (linux-6.10.7)
                     #   Root filesystem (riscv-rootfs)
                     #   OpenSBI payload
                     #   Device tree blob (DTB)
                     #   GCPT checkpoint binary
```

### Running

```bash
make run-nemu        # Run NEMU with GCPT payload (bare-metal boot)
make run-qemu        # Run QEMU system simulation with GCPT payload
make run-user        # Run hello_xsai directly via qemu-riscv64 (user mode)
make test-matrix     # Run matrix test via NEMU
make test            # Run environment sanity check
```

### Maintenance

```bash
make update          # Update all submodules to latest
make clean           # Remove build artifacts and local/llvm
sudo make deps       # Re-install system dependencies
```

## Directory Structure

```
.
├── NEMU/                  # RISC-V Instruction Set Simulator
├── XSAI/                  # XiangShan AI RTL source (Chisel)
├── llvm-project-ame/      # LLVM/Clang source with AME extension support
├── nexus-am/              # Abstract Machine layer and test applications
├── qemu/                  # QEMU source (riscv64 target)
├── DRAMsim3/              # DRAM simulator (used by NEMU)
├── NutShell/              # NutShell reference processor
├── riscv-matrix-spec/     # RISC-V Matrix extension specification
├── firmware/
│   ├── linux-6.10.7/      # Linux kernel source
│   ├── riscv-rootfs/      # Root filesystem & userspace apps (hello_xsai, etc.)
│   ├── opensbi/           # OpenSBI firmware
│   ├── nemu_board/        # Board configs, DTS generator
│   ├── LibCheckpoint/     # GCPT checkpoint library
│   └── checkpoints/       # Simpoint checkpoint outputs
├── local/
│   ├── llvm/              # Built LLVM toolchain (generated)
│   └── bin/               # Installed binaries (gsim, etc.)
├── scripts/               # Build & setup helper scripts
│   ├── setup.sh           # Submodule initialization
│   ├── setup-tools.sh     # System dependency installation
│   ├── build-llvm.sh      # LLVM build script
│   ├── install-gsim.sh    # gsim auto-installer (latest GitHub release)
│   ├── install-verilator.sh
│   └── update-submodule.sh
├── .envrc                 # direnv environment variables
├── env.sh                 # Manual environment setup
├── Makefile               # Top-level build orchestration
└── flake.nix              # Nix flake for reproducible environment
```

## Firmware: hello_xsai

The main AME test application lives in `firmware/riscv-rootfs/apps/hello_xsai/`. It validates the AME GEMM kernel using a custom memory allocator and fuzzing tests.

```bash
cd firmware/riscv-rootfs/apps/hello_xsai
make          # build
make disasm-ame  # disassemble AME kernel object
```

The custom allocator (`mem.c`) uses `mmap` of physical address `0x100000000` (6 GB, matching the DTS `direct-map-mem` region) when `/dev/mem` is available, and falls back to anonymous `mmap` otherwise.

# XSAI Development Environment

This repository provides an out-of-the-box development environment for XSAI (XiangShan AI), including simulation, firmware, custom LLVM toolchain, and AME (Advanced Matrix Extension) support.

## Quick Start

Troubleshooting notes for common build/runtime issues live under `docs/`.
See `docs/troubleshooting.md` for mixed Nix/non-Nix rootfs artifacts and similar environment-specific failures.

### 1. Setup

Clone the repository and initialize the environment. This only needs to be done once.

```bash
git clone https://github.com/Gs-ygc/xsai-env
cd xsai-env
make nix-init         # Recommended: reproducible bootstrap inside the Nix devshell

# Or, if you prefer the non-Nix Ubuntu/Debian path:
sudo make deps        # Install system dependencies
make init-force       # Initialize submodules
```

### 2. Choose an environment entrypoint

Use one of the following workflows before building.

```bash
# Option A (recommended): direnv + Nix devshell
# Requires: nix + direnv
# When you cd into the repo, `.envrc` will:
#   - enter the flake devshell
#   - load shared env vars
#   - apply `.envrc.local` overrides if present
#   - show submodule freshness hints
direnv allow

# Option B: plain Nix without direnv
nix develop .#default

# Option C: lightweight fallback for CI / non-direnv users
# This only sets core environment variables.
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
| `RISCV` | resolved from Nix shell, explicit env, `/opt/riscv`, or compiler on `PATH` |
| `CROSS_COMPILE` | not set globally; firmware/software flows provide their own cross toolchain prefix |

## Build Targets

All targets are available via `make <target>` from the repo root.

### Toolchain

```bash
make llvm            # Build custom LLVM/Clang with AME support → local/llvm
make gsim            # Install the latest gsim release → local/bin/gsim
make nix-shell       # Enter the reproducible Nix devshell
make nix-init        # Run make init-force inside the Nix devshell
make nix-test        # Run make test inside the Nix devshell
make test-smoke      # Fast static / dry-run smoke checks
make nix-smoke       # Run smoke checks inside the Nix devshell
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
# QEMU depends on glib-2.0 / pixman / libslirp in the active environment
# The default repo build disables SDL/GTK/OpenGL because the common workflows use `-nographic`
# It also disables libslirp because the default XiangShan/QEMU flow does not use user-mode networking
# In the Nix devshell, the Makefile also disables fortify for QEMU debug builds to avoid `_FORTIFY_SOURCE` vs `-O0` conflicts
make xsai            # Alias for emu-verilator
```

### Firmware

```bash
make firmware        # Build all firmware:
                     #   Linux kernel (linux-6.18)
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
make test            # Run heavy environment sanity check
make test-smoke      # Run fast smoke checks without heavy builds
```

### Maintenance

```bash
make update          # Update all submodules to latest
make clean           # Remove build artifacts and local/llvm
sudo make deps       # Re-install system dependencies
```

## Troubleshooting

- See `docs/troubleshooting.md` for common failure logs, root causes, and recovery steps.
- If you switch between Nix and non-Nix builds, clean `firmware/riscv-rootfs` app artifacts before rebuilding firmware.
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
│   ├── linux-6.18/        # Linux kernel source
│   ├── riscv-rootfs/      # Root filesystem & userspace apps (hello_xsai, etc.)
│   ├── opensbi/           # OpenSBI firmware
│   ├── nemu_board/        # Board configs, DTS generator
│   ├── LibCheckpoint/     # GCPT checkpoint library
│   └── checkpoints/       # Simpoint checkpoint outputs
├── docs/                  # Troubleshooting and workflow notes
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

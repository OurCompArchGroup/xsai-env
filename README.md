# XSAI Environment

`xsai-env` is an integration workspace for XSAI (XiangShan AI). It pulls together RTL, simulators, firmware, rootfs, toolchains, and validation flows behind a single top-level `Makefile`.

Treat the repo root as the default entrypoint. Most day-to-day setup, build, and run commands should start here instead of inside individual submodules.

For a subsystem-by-subsystem ownership and dependency map, see `docs/workstreams.md`.

## What This Repo Contains

- XSAI RTL and its nested submodules
- NEMU and QEMU based simulation flows
- Linux, OpenSBI, GCPT restore, and rootfs firmware flows
- AM tests and userspace workloads
- A custom LLVM/Clang build path for AME work
- Top-level environment, smoke-test, issue-reporting, and automation scripts

## Recommended Setup

The supported workflow is the shared shell environment.

### 1. Clone and initialize

```bash
git clone https://github.com/OurCompArchGroup/xsai-env
cd xsai-env

# Optional on fresh Ubuntu/Debian hosts:
# sudo make deps

make init-force
```

`make init-force` initializes the main submodules, runs the nested XSAI and firmware setup steps, and may take a while on a fresh checkout.

### 2. Load the environment

Use one of these entrypoints before building:

```bash
# Recommended default for manual shells and CI
source env.sh
```

```bash
# Optional convenience if you already use direnv
direnv allow
```

Notes:

- `env.sh` is the baseline workflow and shares the same environment logic as `.envrc.base`.
- `.envrc` adds shared env loading, optional `.envrc.local` overrides, and submodule freshness hints.
- If `direnv` is not installed yet, follow the official installation guide: <https://direnv.net/docs/installation.html>
- `direnv` also needs to be hooked into your shell before `direnv allow` will work correctly. The official setup guide is here: <https://direnv.net/docs/hook.html>
- For Bash, the usual setup step is adding `eval "$(direnv hook bash)"` to `~/.bashrc`, then restarting the shell.
- If you need machine-local overrides such as a custom `RISCV` or `LLVM_HOME`, copy `.envrc.local.example` to `.envrc.local` and edit it there.

### 3. Smoke-check the top-level wiring

```bash
make test-smoke
```

This is the fastest top-level validation path. It checks the environment scripts and exported Make targets without kicking off a full rebuild.

## Environment Variables

`env.sh` and `.envrc.base` both use `scripts/env-common.sh` to populate the shared environment.

| Variable | Meaning |
|---|---|
| `XS_PROJECT_ROOT` | repo root |
| `NEMU_HOME` | `./NEMU` |
| `QEMU_HOME` | `./qemu` |
| `AM_HOME` | `./nexus-am` |
| `NOOP_HOME` | `./XSAI` |
| `LLVM_HOME` | `./local/llvm` by default |
| `RISCV_LINUX_HOME` | `./firmware/riscv-linux` |
| `RISCV_ROOTFS_HOME` | `./firmware/riscv-rootfs` |
| `RISCV` | resolved from explicit env, known shared installs, `/opt/riscv`, or a compiler on `PATH` |
| `RISCV_SYSROOT` | resolved from the selected toolchain when available |
| `QEMU_LD_PREFIX` | defaults to the detected RISC-V sysroot when available |
| `CROSS_COMPILE` | intentionally not exported at the top level; firmware/software flows set their own toolchain prefix |

## Common Targets

All targets are available as `make <target>` from the repo root.

### Setup and checks

```bash
make deps            # Install Ubuntu/Debian host dependencies (requires sudo)
make init-force      # Initialize submodules and nested setup flows
make test-smoke      # Fast smoke check for scripts and top-level targets
make test            # Heavier manual-environment sanity test
```

### Toolchains and simulators

```bash
make llvm            # Build custom LLVM/Clang with AME support -> local/llvm
make nemu            # Build NEMU
make qemu            # Build qemu-system-riscv64 and qemu-riscv64
make xsai            # Build XSAI Verilator simulation
make emu-gsim        # Build the gsim-based XSAI simulation path
make gsim            # Download the latest gsim release -> local/bin/gsim
```

Notes:

- `make gsim` fetches the latest upstream release and is therefore not a deterministic bootstrap step.
- The top-level QEMU build intentionally clears host-side cross-compilation variables before running `configure`.

### Firmware and end-to-end runs

```bash
make firmware        # Build rootfs, Linux, DTB, QEMU/NEMU GCPT payloads, and restore-only GCPT
make run-qemu        # Boot the default QEMU flow with the GCPT payload
make run-nemu        # Run the GCPT payload on NEMU
make fpga-reset      # Reset FPGA CPU on remote host through Vivado/VIO (no bitstream programming)
make run-fpga        # Upload PAYLOAD and execute XDMA-based FPGA run on remote host
make test-matrix     # Build and run the AME matrix simple test
```

Notes:

- `make run-qemu` is the main end-to-end validation path for this repo.
- `MODEL_IMG=/path/to/disk.img make run-qemu` attaches a virtio block device.
- `make run-qemu` and `make run-nemu` auto-build missing payload pieces such as QEMU, DTB, or GCPT binaries when needed.
- `make run-fpga PAYLOAD=firmware/gcpt_restore/build-nemu/build/gcpt.bin` runs the XDMA FPGA flow against a preconfigured remote board.
- `make run-fpga` does not build or write bitstreams; it uses `FPGA_LTX` for Vivado VIO reset and then runs remote `xdma_process`.
- Optional FPGA knobs: `FPGA_HOST`, `FPGA_REMOTE_PAYLOAD`, `FPGA_DRIVER`, `FPGA_XDMA_PROCESS`, `FPGA_LTX`, `FPGA_TIMEOUT`, `FPGA_UART_CMD`, `FPGA_PASS_PATTERN`, `FPGA_FAIL_PATTERN`, `FPGA_PCIE_REMOVE_CMD`, `FPGA_PCIE_RESCAN_CMD`.
- `make run-user` exists, but it is currently a local `llama.cpp` convenience target with a hard-coded model path and should not be treated as a general validation entrypoint.

### Analysis and maintenance

```bash
make simpoint                          # Build the SimPoint clustering binary
make ckpt MODEL_IMG=/path/to/disk.img  # Run the checkpoint flow
make ccdb                             # Rebuild local/compile_commands.json via bear
make versions                         # Refresh VERSIONS from submodule state
make update                           # Update submodules
make clean                            # Clean main build artifacts
make distclean                        # Deep clean, including local LLVM and QEMU build output
```

## Repository Layout

```text
.
├── Makefile               # Top-level orchestration entrypoint
├── scripts/               # Setup, environment, smoke-test, reporting, and helper scripts
├── docs/                  # Troubleshooting and workflow notes
├── firmware/
│   ├── linux-6.18/        # Pinned Linux kernel source
│   ├── riscv-linux -> linux-6.18
│   ├── riscv-rootfs/      # Rootfs, initramfs, and userspace apps
│   ├── opensbi/           # OpenSBI source and build output
│   ├── nemu_board/        # DTS generation and board configs
│   ├── gcpt_restore/      # GCPT boot/restore binaries
│   ├── LibCheckpoint/     # Checkpoint library
│   └── checkpoints/       # Generated checkpoint outputs
├── XSAI/                  # XiangShan AI RTL source
├── NEMU/                  # NEMU source
├── qemu/                  # QEMU source
├── nexus-am/              # AM layer, tests, and apps
├── llvm-project-ame/      # LLVM/Clang source with AME support
├── DRAMsim3/              # DRAM simulator
├── NutShell/              # Reference processor used by some validation flows
├── riscv-matrix-spec/     # Matrix extension specification
├── local/                 # Local tools and generated binaries
├── log/                   # Build and runtime logs
├── .envrc                 # direnv entrypoint
└── env.sh                 # Manual environment entrypoint
```

Generated artifacts commonly live under `local/`, `build/`, `log/`, and `firmware/checkpoints/`.

## Troubleshooting

- Start with `docs/troubleshooting.md` for common build and runtime failures.
- If you switch compilers or sysroots, stale rootfs artifacts are a common source of confusing failures.
- `make clean` is the first cleanup step; use `make distclean` when you intentionally want a deeper reset.

## Issue Reporting

- `bash scripts/bug-report.sh` generates an environment and repository bundle for bug reports.
- `bash scripts/create-issue.sh` provides a terminal-first issue workflow using GitHub CLI.
- If the root cause clearly belongs to an upstream component such as `XSAI`, `NEMU`, `qemu`, or `riscv-rootfs`, file the issue upstream as well and link the integration context from `xsai-env`.

## Development Workflow

- Use `docs/git-workflow.md` for the issue-first Git flow, branch naming, PR review, and merge rules.
- Open or link an issue before non-trivial work, then create a scoped branch such as `fix/123-checkpoint-replay` or `feat/123-rootfs-app`.
- PRs should link the issue, summarize the touched workstream, list validation commands, and call out coupled-subsystem risk.
- Submodule code changes should land in the owning submodule repository first; `xsai-env` then carries a separate gitlink bump PR that also runs `make versions` and includes the resulting `VERSIONS` update.

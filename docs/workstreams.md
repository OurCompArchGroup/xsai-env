# XSAI Env Workstreams

`xsai-env` is not a flat monorepo. It is an integration workspace for XiangShan CPU + AI matrix-unit development, and each subsystem keeps its own source of truth, toolchain assumptions, and validation path.

This document is the map for both humans and AI agents:

- which directory owns which problem
- which subsystems depend on which others
- which changes can be parallelized
- which changes must be serialized and integrated carefully

## Operating Principles

1. One task should have one primary write scope.
2. Cross-subsystem changes are allowed, but only when the interface itself is the thing being changed.
3. If A changes B's contract, update A first, then integrate B in a second step instead of letting unrelated agents edit both at once.
4. Prefer the repo root `Makefile` and shared environment entrypoints over ad hoc commands inside submodules.
5. Tests and tools should validate or automate flows; they should not quietly become the only source of truth for a subsystem contract.

## Workstream Map

| Workstream | Primary paths | Owns | Typical entrypoints |
|---|---|---|---|
| `xsai-env` base | `Makefile`, `scripts/`, `mk/`, `env.sh`, `.envrc*`, `README.md`, `AGENTS.md`, `docs/`, `.gitmodules` | Top-level orchestration, shared environment, repository conventions, integration docs | `make init-force`, `make test-smoke`, `make help` |
| RTL / hardware model | `XSAI/` | XiangShan AI RTL, generated Verilog, emulator build, difftest integration on the DUT side; the main matrix-core hotspot is `XSAI/CUTE/` | `make xsai`, `make emu-gsim`, `make run-emu`, `make run-emu-debug` |
| Golden model / ISA reference | `NEMU/` | Golden ISA behavior, difftest reference `.so`, standalone profiling/checkpoint support, debug monitor | `make nemu`, NEMU defconfigs, `build/riscv64-nemu-interpreter-so` |
| System and user-mode simulator | `qemu/` | Linux/user-mode simulation, QEMU machine support, profiling plugin used by the repo checkpoint flow | `make qemu`, `make run-qemu` |
| Firmware / boot flow | `firmware/` | Linux, rootfs, OpenSBI, DTB, GCPT boot payloads, restore-only payload, board boot flow | `make firmware`, `make -C firmware build-dtb`, `make run-qemu` |
| Runtime and logical program library | `nexus-am/` | AM runtime, bare-metal libraries, AM apps/tests used by NEMU and RTL flows | `make -C nexus-am/...`, `make test-matrix` |
| Compiler / low-level codegen | `llvm-project-ame/`, `local/llvm`, `scripts/build-llvm.sh` | AME-aware LLVM/Clang, disassembly, low-level codegen semantics | `make llvm` |
| DSL compilers | `DSL/` | High-level compiler frontends such as Triton/TileLang/TVM that eventually lower to supported kernels or binaries | workspace-specific commands under `DSL/` |
| Software / workloads | `software/`, `firmware/riscv-rootfs/apps/`, `nexus-am/apps/` | User workloads, Linux-side apps, benchmarks, demos, AM apps; key rootfs hotspots are `hello_xsai`, `gemm_precomp`, and `llama.cpp` | `make -C firmware/riscv-rootfs/apps/<app> install`, `make firmware`, app-local builds |
| Checkpoint / profiling flow | `scripts/checkpoint.sh`, `firmware/gcpt_restore/`, `firmware/checkpoints/`, `firmware/simpoints/`, `NEMU/resource/simpoint/` | SimPoint flow wiring, BBV generation, clustering, checkpoint dumping, restore path | `make simpoint`, `make profile`, `make cluster`, `make ckpt` |
| Tests | `tests/`, `nexus-am/tests/`, component-local tests | Regression coverage, end-to-end validation, bring-up checks | `make test-smoke`, `make test`, component-local test targets |
| Tools | `tools/`, `scripts/` | Developer tooling, automation helpers, packaging, reporting | script-local commands, `make ccdb`, `bash scripts/...` |

## Reserved Namespace Notes

Some top-level directories are currently more like namespaces than mature product trees:

- `DSL/` is the umbrella for higher-level compiler projects, even if specific DSL code is still sparse today.
- `software/` is the umbrella for workload projects, but active software also lives under `firmware/riscv-rootfs/apps/` and `nexus-am/apps/`.
- `tests/` and `tools/` are top-level coordination points; many real tests/tools still live inside component repos.

Do not conclude that a top-level directory is unimportant just because it is currently light. In this repo, several namespaces are intentionally reserved for future growth and cleaner ownership.

## Current Hotspots

These are the most important day-to-day development hotspots in the current tree.

### Rootfs smoke-test apps

The two most important Linux/rootfs smoke tests today are:

- `firmware/riscv-rootfs/apps/hello_xsai/`
- `firmware/riscv-rootfs/apps/gemm_precomp/`

These are not just standalone binaries. Their boot-time validation path is closed by three layers together:

- `firmware/riscv-rootfs/Makefile` must build and install them through `APPS`
- `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt` must pack them into the initramfs image
- `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh` must invoke the intended workload or smoke-test sequence

Treat rootfs smoke-test changes as integration changes across build, packaging, and boot flow.

### AI software stack hotspot

The main AI-software development point is:

- `firmware/riscv-rootfs/apps/llama.cpp/`

The most important software modification surfaces there are:

- `ggml` AME operators
- `llama-simple-xsai`
- `llama-bench`

This path is where software inference adaptation for XSAI most often lands.

## Default Software Validation Ladder

For software changes, the current default validation order should be:

1. `make run-qemu`
2. `make run-nemu`
3. `make ckpt`
4. `make run-nemu PAYLOAD=<checkpoint.zstd>`
5. `make run-emu PAYLOAD=<checkpoint.zstd>`

Why this order:

- QEMU is roughly an order of magnitude faster than NEMU for bring-up and easier to use for software bug analysis.
- NEMU is roughly two orders of magnitude faster than RTL and is the preferred golden-model step before touching RTL.
- RTL should be used after the software path is already narrowed down, mainly for realistic performance behavior or workload-level ST validation.

Checkpoint defaults differ by entrypoint.

Top-level `make ckpt` currently uses the SimPoint sampling defaults from `Makefile`:

- `CHECKPOINT_CONFIG=build`
- `WORKLOAD_NAME=app`
- `CPT_INTERVAL=100000`
- `PROFILING_INTERVALS=CPT_INTERVAL`
- `SIMPOINT_MAX_K=30`
- `SMP=1`

Direct `scripts/checkpoint.sh` invocation keeps faster single-slice script defaults:

- `CHECKPOINT_CONFIG=build`
- `WORKLOAD_NAME=app`
- `CPT_INTERVAL=100`
- `PROFILING_INTERVALS=CPT_INTERVAL`
- `SIMPOINT_MAX_K=10`
- `SMP=1`

Checkpoint payload paths depend on the generated SimPoint/checkpoint index as well as `WORKLOAD_NAME` and `CHECKPOINT_CONFIG`. Treat `firmware/checkpoints/build/app/1/_1_1.zstd` as a common example, not a universal constant.

There are two common checkpointing modes in this repo:

- Fast single-slice mode:
  use `no_simpoint + do_checkpoint`, typically with small `CPT_INTERVAL=100`.
  This usually emits one checkpoint and is useful when you want to skip firmware/OS startup and jump quickly into the target region.
- SimPoint sampling mode:
  use `do_profile + do_cluster + do_checkpoint`, for example with `CPT_INTERVAL=100000` and `SIMPOINT_MAX_K=30`.
  This can produce multiple representative fragments that can be replayed in parallel on NEMU or RTL emu for hardware-side performance studies.

### RTL matrix-core hotspot

The main RTL development point is:

- `XSAI/CUTE/`

The CUTE design documentation is available locally under:

- `docs/XiangShan-Design-Doc/`

That directory is tracked as a git submodule so both humans and AI agents can consult the design docs from within this workspace.

## Dependency Directions

The most important dependency directions are:

### ISA and codegen contract

`riscv-matrix-spec` -> `llvm-project-ame` / `DSL/` -> `software/` + `nexus-am/` -> `NEMU/`, `qemu/`, `XSAI/`

If the Matrix ISA, CSR behavior, codegen assumptions, or instruction encoding changes, these layers usually need coordinated updates.

### Linux userspace bring-up

toolchain -> `firmware/riscv-rootfs/apps/` -> `firmware/` image assembly -> `qemu/` runtime -> optional `XSAI/` or checkpoint consumers

This is the main path for Linux-side workloads such as `hello_xsai`, `llama.cpp`, `redis`, or benchmark apps.

For the current repo, `hello_xsai` and `gemm_precomp` are the primary smoke-test apps on this path, and `llama.cpp` is the main inference-framework development path.

### Bare-metal / AM flow

toolchain -> `nexus-am/` runtime + apps/tests -> `NEMU/` or `XSAI/`

This is the main path for AM tests, matrix ISA tests, and lightweight workload validation without the Linux rootfs stack.

### RTL difftest flow

`NEMU/` reference `.so` -> `XSAI/difftest` -> `XSAI/build/emu`

If difftest mismatches appear, the root cause may live in RTL, NEMU semantics, payload assumptions, or the test image itself.

### Repo checkpoint flow

`firmware/` payload + DTB -> `qemu/` profiling plugin -> `NEMU/resource/simpoint/` clustering binary -> `scripts/checkpoint.sh` orchestration -> `firmware/checkpoints/`

At the repo root, checkpoint production is an integration flow, not a single-subsystem feature.

There is one more repo-specific requirement: the workload itself must cooperate with the simulator by emitting custom `nemu_signal(...)` markers such as:

- `DISABLE_TIME_INTR`
- `NOTIFY_PROFILER`
- `NOTIFY_PROFILE_EXIT`
- `GOOD_TRAP`

So in practice, slicing depends on both:

- outer orchestration parameters such as interval sizes and clustering knobs
- workload-side marker placement that defines the region of interest

This is especially important because `DISABLE_TIME_INTR` changes runtime behavior: software that still depends on timer interrupts or normal multithread scheduling is not a good candidate for direct profiling after that point.

## What Each Workstream Should Avoid Owning

- `xsai-env` base should not duplicate complex logic that already belongs in `firmware/`, `NEMU/`, `qemu/`, or `XSAI/`.
- `tools/` should not silently define architectural truth that the runtime, firmware, or RTL cannot derive elsewhere.
- `tests/` should not be the only place where required setup or interface rules are documented.
- `software/` should not embed private copies of runtime/ABI contracts that really belong in `nexus-am/`, firmware manifests, or toolchain flags.
- `DSL/` should not become a second source of truth for ISA semantics without matching updates to toolchain, simulator, and hardware consumers.

## Change Coordination Rules

### Safe to parallelize

These are usually safe for separate humans or agents to work on in parallel:

- A documentation-only task under `docs/`, `README.md`, `AGENTS.md`, or `.agents/skills/`
- A self-contained app change under one `firmware/riscv-rootfs/apps/<app>/` directory when no shared rootfs manifest, init script, or common runtime is changing
- A self-contained AM app/test change under one `nexus-am/apps/<app>/` or `nexus-am/tests/<test>/` directory when no shared runtime or ISA contract changes
- A standalone helper under `tools/` or `scripts/` that does not change component contracts

### Must be serialized

These changes should not be edited concurrently by multiple agents unless there is a very explicit split of write ownership:

- Matrix ISA semantics, CSR behavior, instruction encoding, or ABI expectations
- Difftest/reference-model alignment between `NEMU/` and `XSAI/`
- Memory map, DTB, reserved-memory, or DMA window changes
- Checkpoint format, restore behavior, or profile/cluster/dump orchestration
- Shared runtime/library changes in `nexus-am/` that fan out to many apps/tests
- Top-level environment and build entrypoint changes under `Makefile`, `scripts/`, `env.sh`, or `.envrc*`

## Common Coupling Examples

### 1. Matrix ISA or intrinsic change

Likely impact:

- `llvm-project-ame/`
- `DSL/`
- `nexus-am/` matrix tests
- `firmware/riscv-rootfs/apps/hello_xsai/`
- `firmware/riscv-rootfs/apps/gemm_precomp/`
- `firmware/riscv-rootfs/apps/llama.cpp/`
- `NEMU/`
- `qemu/`
- `XSAI/`

Recommendation:

- Land the source-of-truth change first.
- Then update consumers one by one with explicit validation at each layer.

### 2. Memory-map or reserved-memory change

Likely impact:

- `XSAI/CUTE/`
- `mk/memory.mk`
- `firmware/nemu_board/`
- `firmware/linux-6.18/` config assumptions
- `firmware/riscv-rootfs/apps/hello_xsai/mem.c`
- `firmware/riscv-rootfs/apps/llama.cpp/` reserved-memory allocator settings
- `Makefile` QEMU run parameters

Recommendation:

- Treat this as a firmware/platform contract change, not an app-only edit.

### 3. Checkpoint flow change

Likely impact:

- `scripts/checkpoint.sh`
- `Makefile` checkpoint targets
- `qemu/` profiling plugin or machine behavior
- `firmware/gcpt_restore/`
- `firmware/checkpoints/`
- `NEMU/resource/simpoint/`

Recommendation:

- Keep one integrator in charge, because the failure mode is often only visible end to end.

### 4. Rootfs boot workload change

Likely impact:

- `firmware/riscv-rootfs/apps/hello_xsai/`
- `firmware/riscv-rootfs/apps/gemm_precomp/`
- `firmware/riscv-rootfs/apps/llama.cpp/`
- `firmware/riscv-rootfs/Makefile`
- `firmware/riscv-rootfs/rootfsimg/initramfs-*.txt`
- `firmware/riscv-rootfs/rootfsimg/init-*.sh`

Recommendation:

- Treat build, packaging, and boot invocation as one change, not three unrelated edits.

## Validation by Workstream

| Workstream | Fast validation | Integration validation |
|---|---|---|
| `xsai-env` base | `make test-smoke` | `make test` |
| RTL / `XSAI/` | `make xsai`, `make run-emu-debug PAYLOAD=...` | targeted workload on RTL with difftest |
| `NEMU/` | `make nemu` | run the intended workload or reference-mode flow |
| `qemu/` | `make qemu` | `make run-qemu` |
| firmware | `make -C firmware build-dtb`, app-local/rootfs-local build | `make firmware`, `make run-qemu` |
| `nexus-am/` | app/test-local build | `make test-matrix` or targeted AM run |
| compiler/toolchain | targeted app rebuild, `llvm-objdump` | downstream software/runtime execution |
| checkpoint flow | script sanity and target existence | `make simpoint`, `make profile`, `make cluster`, `make ckpt MODEL_IMG=...` |

For software-heavy changes, do not jump to RTL first. The default repo ladder is:

- `make run-qemu`
- `make run-nemu`
- `make ckpt`
- `make run-nemu PAYLOAD=<checkpoint.zstd>`
- `make run-emu PAYLOAD=<checkpoint.zstd>`

## Routing Advice for Humans and AI

When a request arrives:

1. Identify the primary workstream first.
2. List the exact paths that are likely sources of truth.
3. Mark downstream consumers that may need validation but should not be edited yet.
4. If more than one source of truth must change, split the work into serial phases.
5. Prefer minimal, localized edits and validate on the narrowest path that proves the change.

If you are unsure where a change belongs, start from the subsystem that defines the interface, not the one that happens to fail first.

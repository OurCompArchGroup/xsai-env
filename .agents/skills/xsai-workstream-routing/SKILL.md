---
name: xsai-workstream-routing
description: Guide for routing work inside xsai-env. Use this when a request asks where code should live, how the repo is partitioned, how to split work across agents, or when a task spans XSAI RTL, NEMU, QEMU, firmware, nexus-am, software, DSL, tests, or tools.
---

# XSAI Workstream Routing

Use this skill before broad repo edits or when a task may cross subsystem boundaries.

## First step

Read `docs/workstreams.md` and classify the task into one primary workstream:

- top-level `xsai-env` base
- `XSAI/` RTL
- `NEMU/` golden model / ISA reference
- `qemu/` system and user-mode simulator
- `firmware/`
- `nexus-am/`
- compiler / `llvm-project-ame/`
- `DSL/`
- `software/`
- `tests/`
- `tools/`

## Routing rules

1. Pick one primary source of truth.
2. List downstream consumers separately from owners.
3. Prefer changing the owner of an interface instead of hiding the issue in a downstream workaround.
4. If more than one source of truth must change, split the work into serial phases.

## Important repo-specific facts

- `DSL/`, `software/`, `tests/`, and `tools/` are umbrella namespaces, not the only places where those concerns live.
- Linux/rootfs apps live under `firmware/riscv-rootfs/apps/`.
- AM apps and tests live under `nexus-am/apps/` and `nexus-am/tests/`.
- The repo checkpoint flow is an integration of `Makefile`, `scripts/checkpoint.sh`, `qemu/`, firmware payloads, and the SimPoint binary under `NEMU/resource/simpoint/`.
- Difftest is a coupled `XSAI` + `NEMU` flow.
- The most important rootfs software hotspots today are `hello_xsai`, `gemm_precomp`, and `llama.cpp`.
- The main AI inference-framework development path is `firmware/riscv-rootfs/apps/llama.cpp/`.
- The main RTL matrix-core hotspot is `XSAI/CUTE/`, with local design docs under `docs/CUTE-Design-Doc/`.

## Fast routing hints

- If the request mentions `hello_xsai`, `gemm_precomp`, `initramfs-disk-xsai.txt`, or `init-disk-xsai.sh`, route first to the rootfs software / firmware boundary.
- If the request mentions `llama.cpp`, `ggml`, `llama-simple-xsai`, or `llama-bench`, route first to the rootfs software path under `firmware/riscv-rootfs/apps/llama.cpp/`.
- If the request mentions `CUTE`, matrix core, or matrix RTL, route first to `XSAI/CUTE/` and consult `docs/CUTE-Design-Doc/`.

## Parallel work rules

- One task should have one primary write scope.
- Safe parallel work requires disjoint paths and no shared contract.
- Do not parallelize edits across coupled areas such as ISA semantics, difftest contracts, memory-map changes, or checkpoint/restore interfaces unless the split is explicit.

## Validation mapping

- Base/orchestration: `make test-smoke`
- Firmware/QEMU: `make firmware`, `make run-qemu`
- RTL: `make xsai`, `make run-emu-debug PAYLOAD=...`
- NEMU: intended defconfig or reference build
- AM/runtime: target-local `nexus-am` build or test
- Rootfs apps: app-local build first, then firmware/QEMU validation

For software-heavy changes, the default repo ladder is:

- `make run-qemu`
- `make run-nemu`
- `make ckpt`
- `make run-nemu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`
- `make run-emu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`

Use the checkpoint path above as the default example for the current defaults, and adjust it if `WORKLOAD_NAME` or `CHECKPOINT_CONFIG` changes.

If the task starts broad and ambiguous, this skill's job is to narrow it to one write scope before coding begins.

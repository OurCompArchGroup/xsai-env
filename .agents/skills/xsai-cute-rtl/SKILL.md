---
name: xsai-cute-rtl
description: Guide for working on the XSAI/CUTE matrix core. Use this when asked to modify or analyze the main matrix RTL block under XSAI/CUTE, or when the task needs the CUTE design documentation shipped under docs/CUTE-Design-Doc.
---

# XSAI CUTE RTL

Use this skill when the task is primarily about the matrix core under:

- `XSAI/CUTE/`

## Current repo role

`XSAI/CUTE/` is the main RTL development hotspot for the XSAI matrix unit.

Local design documentation is available under:

- `docs/CUTE-Design-Doc/`

That documentation is tracked as a submodule so it can be read from the same workspace as the RTL source.

## Common modified files

The most common edit points are:

- `XSAI/CUTE/src/main/`
- `XSAI/CUTE/src/test/`
- `XSAI/CUTE/Makefile`
- `XSAI/CUTE/build.sc`
- `XSAI/CUTE/common.sc`

The most useful local documentation roots are:

- `docs/CUTE-Design-Doc/docs/hardware/`
- `docs/CUTE-Design-Doc/docs/instruction-set/`
- `docs/CUTE-Design-Doc/docs/software/`

## How to approach tasks

1. Read the relevant design-doc section under `docs/CUTE-Design-Doc/` first.
2. Identify the exact block or interface under `XSAI/CUTE/` that owns the behavior.
3. Treat toolchain, simulator, and software regressions as downstream consumers unless the interface itself is changing.
4. Validate the change on the narrowest RTL path first, then on the full difftest or workload path if needed.

## Coupled areas

Changes in `XSAI/CUTE/` often couple to:

- `NEMU/` difftest behavior
- matrix ISA assumptions
- software kernels such as `hello_xsai`, `gemm_precomp`, and `llama.cpp`
- memory-layout or DMA assumptions used by matrix software paths

Do not edit all of these at once unless the task is explicitly an interface change and one integrator is managing the rollout.

## Validation entrypoints

Start from the existing repo RTL wrappers:

```bash
make xsai
make run-emu PAYLOAD=<payload>
make run-emu-debug PAYLOAD=<payload> DIFF=1
```

Use the generic `xsai-rtl-debug` skill alongside this one when you need waveform, ChiselDB, or difftest capture details.

For software-driven validation, do not start with RTL first. The current repo ladder is:

1. `make run-qemu`
2. `make run-nemu`
3. `make ckpt`
4. `make run-nemu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`
5. `make run-emu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`

RTL should usually be the last gate, after the software path is already narrowed down.

## Easy mistakes

- Jumping into waveform debugging before reproducing on QEMU and NEMU
- Treating a software or DTB problem as a CUTE bug too early
- Editing the matrix core without checking the relevant design-doc section first
- Making interface changes in `XSAI/CUTE/` without planning downstream updates to difftest, software kernels, or checkpoint consumers

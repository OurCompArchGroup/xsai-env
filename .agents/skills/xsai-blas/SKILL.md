---
name: xsai-blas
description: Guide for using, integrating, and debugging xsai-blas in xsai-env. Use when a task adds GEMM/attention/norm/quantize kernels, decides whether xsai-blas or a framework kernel should own an op, triages xsai-blas or Q8 MUL_MAT failures, or wires xsai-blas into llama.cpp, MNN, or another framework.
---

# xsai-blas

Use this skill when the task is about the shared XSAI BLAS/GEMM library rather
than one framework or one rootfs app.

## What layer it belongs to

`software/xsai-blas/` is a pinned software-workstream submodule, not a
framework, rootfs app, AM runtime, or RTL component.

- It is a kernel library: generic C, scalar RISC-V, RVV, and AME objects in one
  unified archive, selected at runtime through a framework-neutral C plan ABI.
- It owns GEMM (FP32/BF16/int8 group32/int8 whole-K), FlashAttention, softmax,
  RMSNorm, quantization, and elementwise kernels, plus prepared-weight and
  workspace planning.
- It does not own graph construction, tensor allocation, rootfs packaging,
  boot/init flow, ISA semantics, or emulator/RTL behavior.
- Upstream dependencies are the AME-capable LLVM toolchain and the Matrix ISA
  (RVV and AME). Downstream consumers are framework adapters and test runners:
  - `software/llama.cpp/ggml/src/ggml-cpu/arch/riscv/xsai/` — ggml adapter;
  - `software/MNN/source/backend/cpu/CPUMatMul.cpp` — MNN MatMul hook;
  - `firmware/riscv-rootfs/apps/xsai-blas-test/` — Linux test runner;
  - `nexus-am/apps/xsai-blas-test/` — AM test runner;
  - `firmware/riscv-rootfs/apps/llama.cpp/` — Linux inference wrapper.

The gitlink in `xsai-env` is the source of truth. The library repository ships
only libraries and tests; target runners live in `xsai-env`.

`XSAI_BLAS_HOME` points at `software/xsai-blas` and is exported by the top-level
`Makefile` and `scripts/env-common.sh`. Use it instead of hard-coding a path.

## When to use xsai-blas

Use it when:

- An AI workload needs an operator family the library already implements.
- A framework adapter should own a node only when the library can validate and
  plan it, and otherwise leave the framework's own kernel in place.
- A change is in the shared prepared-weight/plan/workspace contract rather than
  one framework's graph or memory model.
- You need correctness or performance evidence for a kernel on RVV or AME.
- You need Qwen3-shaped workload samples from `software/xsai-blas/testcase-suite/`.

Do not use it when:

- The task changes Matrix ISA semantics, instruction encoding, CSR behavior, or
  the emulator/RTL contract. Route to `XSAI/`, `NEMU/`, `qemu/`, or
  `llvm-project-ame/` instead.
- The task is only graph placement, allocator policy, model loading, or
  packaging. Those stay in the framework adapter, rootfs wrapper, or firmware.
- The operator has no exact xsai-blas mapping. Do not approximate it in the
  adapter; keep the framework kernel.

## Integration into a framework

Read `software/xsai-blas/docs/integration.md` before writing an adapter. The
short version:

1. Claim only exact mappings. At graph planning, build an `xsai_op_call_t` with
   borrowed DLPack `DLTensor`s and call `xsai_op_plan_create()`.
   `XSAI_STATUS_SUCCESS` means the library owns the node; any other result
   means keep the framework implementation. Nothing was written on failure.
2. Preserve layout without copies. Use `strides` for transposed/`[N, K]`
   weights and `byte_offset` for views. CPU tensors only, compact layouts only.
3. Cache plans by `xsai_op_call_fingerprint()`. It ignores data pointers and
   workspace, so it works before storage exists. Any metadata change needs a
   new plan; execute does not revalidate metadata.
4. Treat create-time and execute-time outcomes differently. Fallback is valid
   only before `plan_create` succeeds. After that, an execute error is a real
   runtime error; do not rerun a different kernel over a partially written
   output.
5. Size workspace from `xsai_op_plan_get_requirements()` per execute call.
   It must be aligned, disjoint from tensors, and separate for concurrent
   executes of the same plan.
6. Prepare quantized weights once with `xsai_weight_plan_*`, bind the prepared
   weight to the call, and invalidate plans and the weight plan on a generation
   change. Prepared arenas require 64-byte alignment. Never free an arena while
   a dependent plan is executing.
7. Build through the stable CMake target `xsai-blas::xsai-blas` (subdirectory or
   installed `find_package`), or pass `-DXSAI_BLAS_HOME=...` and the archive
   path from the app wrapper. Never copy kernels into a framework tree.

Reference implementations to read first:

- `software/llama.cpp/ggml/src/ggml-cpu/arch/riscv/xsai/xsai-plan.h`
- the adapter unit tests described in
  `firmware/riscv-rootfs/apps/llama.cpp/BENCHMARKS.md`
- `software/xsai-blas/docs/integration.md` (MNN section shows a narrower
  execution-level hook)

## Debugging: classify the layer first

Do not start by editing the framework adapter. Narrow the failure in this
order.

### 1. Reproduce with the library runner

```bash
cd firmware/riscv-rootfs/apps/xsai-blas-test
make
qemu-riscv64 -cpu rv64,v=true,vlen=128,h=true,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 \
  -L "$RISCV_SYSROOT" build/xsai-blas-test test
```

Narrow with `--kernel NAME` and `--case ID`; an unknown kernel lists every
group and case. Use `perf` mode only for timing. For a quick selection:

```bash
qemu-riscv64 ... build/xsai-blas-test test --kernel gemm_i8_group32 --case 17
qemu-riscv64 ... build/xsai-blas-test test --kernel contract
```

The Makefile builds the library with `-DXSAI_BLAS_BUILD_TEST_CASES=ON`; one
library build exists per i8 GEMM tile (`TILE_M`/`TILE_N`).

### 2. Isolate the implementation

Comparison cases run both the selected implementation and the reference through
the same plan API. If the reference path fails, the bug is in the generic
implementation, ABI validation, or the test call itself. If only one optimized
path fails, force it explicitly:

- RVV-only failure: suspect the RVV kernel, compiler flags/toolchain, or the
  emulator's vector model. Route to the toolchain or `qemu/` owner.
- AME-only failure: suspect tile/pack constraints, AME availability, or the
  emulator/RTL model. Remember `XSAI_GEMM_AME_MIN_M = 64`; an explicit
  `XSAI_CAP_AME` bypasses that threshold.
- Wrong only with prepared weights: check the canonical payload/scale layout,
  the native pack, generation invalidation, and arena lifetime.

### 3. If the library passes but the framework fails

The bug is in the adapter, not the kernel. Check, in order:

- node claim and ownership: a `plan_create` failure must fall back; an execute
  failure must not;
- DLTensor strides and `byte_offset` versus the framework's real layout;
- plan cache key and invalidation on metadata or weight generation;
- workspace size/alignment/disjointness;
- buffer type placement (for llama.cpp, `XSAI_GGML_BACKEND` and
  `XSAI_GGML_Q8` select placement and trait ownership, not different kernels);
- adapter-side allocator hooks that notify on host-buffer writes/frees.

Compare route counters and plan counters before and after the change. For
llama.cpp, `llama-simple` on a Matrix-enabled QEMU user-mode build is the
host-side runtime check; `llama-simple-xsai` emits a NEMU performance-probe
signal and belongs on NEMU/RTL.

### 4. If QEMU passes and NEMU/RTL fails

Treat it as a simulator/ISA/RTL question and route to `xsai-software-debug` or
`xsai-rtl-debug`:

- `XSAI_BLAS_ENABLE_VFEXP2=ON` needs an emulator that decodes `Zvamesfexp2`;
  the repository NEMU may not, so a temporary upstream-master NEMU build is the
  functional check.
- A 64-wide i8 tile is validated on the QEMU matrix model. The CUTE RTL
  configuration has a fixed 128-wide physical tensor and rejects a 64-wide
  store; do not report that as an xsai-blas kernel bug.
- Matrix CSR probes from a consumer can be blocked by the
  `CONFIG_RVH`/`CONFIG_RV_SMSTATEEN` gate in NEMU even when the kernel path is
  fine. Separate probe failures from kernel failures.
- `rdcycle`/`rdinstret` under QEMU user-mode reflect host TSC, not guest
  instruction counts. Do not use qemu-user numbers as a performance claim.

## Validation ladder

Use the narrowest layer that can answer the question:

1. Library correctness: rootfs `xsai-blas-test` on QEMU user-mode, `test` mode.
2. Adapter correctness: adapter unit tests on the host, then `llama-simple` on
   Matrix-enabled QEMU user-mode with route counters; compare output hashes
   across `xsai`/`q8` on/off configurations.
3. Workload-shaped behavior: `software/xsai-blas/testcase-suite/`:
   ```bash
   cd software/xsai-blas/testcase-suite
   make check
   make build-linux
   make run-qemu ARGS="--tag rvv"
   ```
4. Bare metal / golden model: `nexus-am/apps/xsai-blas-test` with
   `ARCH=riscv64-xs TOOLCHAIN=LLVM KERNEL=... CASE=...`, then NEMU.
5. RTL: the same AM image on `make run-emu PAYLOAD=...`, after the software
   issue is narrowed down.

For framework-level end-to-end validation, follow the repo ladder in
`docs/workstreams.md`: QEMU, NEMU, checkpoint, then RTL.

## Gitlink and ABI hygiene

- The library is a pinned submodule. Land changes in the xsai-blas repository
  first, then update the `software/xsai-blas` gitlink and `VERSIONS` in the
  same parent commit.
- `make software-init` initializes it; `make test-ai-software` is the host-only
  gate that checks the pin and wrapper sources.
- Public ABI changes require matching updates in the public headers,
  `test/` contract cases, and every adapter in the same integration change.
- `make versions` regenerates `VERSIONS` for intentional submodule bumps.
- Do not add app-local clones of xsai-blas; pass `XSAI_BLAS_HOME` or the
  wrapper's explicit override instead.

## Easy mistakes

- Treating xsai-blas as a framework and putting graph or allocator policy in it.
- Claiming a node when `plan_create` returned a non-success status.
- Falling back after a failed execute, which can hide corruption.
- Reusing a plan after shape, stride, dtype, params, or weight generation
  changed.
- Forgetting that workspace is per execute and must be disjoint from tensors.
- Hard-coding `xsai-blas` paths instead of using `XSAI_BLAS_HOME`.
- Debugging an adapter before reproducing the same case in `xsai-blas-test`.
- Reporting qemu-user cycle counts or a 64-tile CUTE abort as library bugs.

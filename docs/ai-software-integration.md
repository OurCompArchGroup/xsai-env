# AI software integration

Integration work is tracked by xsai-env issue #40. Framework code belongs to
the pinned `software/{MNN,ncnn,llama.cpp}` submodules; appliance wrappers belong
to `firmware/riscv-rootfs/apps/`. The rootfs repository has issues disabled, so
this integration issue also tracks its wrapper branch and published revision.
The rootfs gitlink and `VERSIONS` select that revision, not a local experiment.
Published rootfs branch: `feat/40-ai-framework-rootfs`, commit
`c37bd8f2c530b1dc9f1ed283c42b99523e65cd10` (independent remote fetch verified).
Rootfs review: `OurCompArchGroup/riscv-rootfs#2`. The parent integration remains
a separately reviewed change. That rootfs PR was merged on 2026-10-14 as
`78535eee6989dd2959bd8dbc435fa28f9aac603f`; the parent gitlink selects the merged
revision, whose tree matches the validated wrapper commit.

The current parent release closure is:

* xsai-env #41: framework/rootfs wrapper integration (merged);
* xsai-env #43: reproducible openRuyi/PyTorch userspace recipe (merged);
* xsai-env #45: opt-in external-initramfs firmware flow (merged as
  `480167c4aca9a863c7cc28a6dbf4c50e283b503b`);
* xsai-env #44: fixed Triton/xscpu AOT bundle contract (merged as
  `4b49b4f`, after rebasing onto #45);
* xsai-env #42: maintained FPGA programming/runtime flow (merged).

The old external-initramfs PR #22, FPGA mega-PR #32, and
`nemu_board#8` were closed as superseded. They are not release dependencies.

## Setup and host gate

From the repository root:

```sh
source env.sh
make software-init
make test-smoke
make test-ai-software
```

`software-init` initializes the three framework submodules, the top-level
`xsai-blas` library, and rootfs, at their recorded gitlinks. It does not update
to branch tips or reset dirty worktrees. Use the normal `make init-force`
workflow before heavy full-stack builds on a fresh checkout; Nix is not needed
for these software entrypoints.

The host gate checks selected revisions, missing-source diagnostics, explicit
source overrides, MNN allocator wiring without source writes, model checksum
checks, additive manifests, workload exit propagation and differential-output
validation. Local dirty sources are reported, not certified by this host gate.

NCNN links the MNN AME kernel and allocator; llama.cpp replaces its allocator
in the CMake build graph using the MNN source. Neither wrapper fetches a hidden
app-local clone or copies code into managed framework source.

## xsai-blas and the llama.cpp adapter

`xsai-blas/` is a top-level pinned submodule rather than a `software/` child:
several apps consume the same GEMM kernels plus the prepared-weight and plan
runtime, not just the llama.cpp wrapper. The llama.cpp ggml
adapter lives in `software/llama.cpp` under
`ggml/src/ggml-cpu/arch/riscv/xsai/`. In a combined AME + XSAI build the XSAI
buffer type claims Q8_0 `MUL_MAT` weight probes and dispatches them to the
xsai-blas group32 GEMM; other weight types remain with the AME backend or the
ggml CPU path.

`XSAI_GGML_BACKEND=0` keeps ggml on the CPU path. `XSAI_GGML_Q8=0` leaves Q8_0
weights on AME buffers while the rest of the XSAI backend stays enabled. The
AME Q8 path in the current llama.cpp branch already delegates to the same xsai
plan runtime, so this switch selects placement and trait ownership, not a
second kernel. The rootfs wrapper exposes both switches as `--xsai on|off` and
`--q8 on|off`.

`firmware/riscv-rootfs/apps/xsai-blas-test/` links the same archive and runs the
library test cases on RISC-V Linux. On a Matrix-enabled QEMU user-mode build,
`llama-simple` is the host-side runtime check: `llama-simple-xsai` emits a NEMU
performance-probe signal that this QEMU does not decode, so keep it for in-system
NEMU/RTL runs. The adapter unit tests build on a non-RISC-V host as described in
`firmware/riscv-rootfs/apps/llama.cpp/BENCHMARKS.md`.

## Build gates and profiles

With an AME-aware LLVM/Clang toolchain and a matching GNU RISC-V sysroot:

```sh
make -C firmware/riscv-rootfs/apps/mnn install-binaries NPROC=2
make -C firmware/riscv-rootfs/apps/ncnn install NPROC=2
make -C firmware/riscv-rootfs/apps/llama.cpp riscv NPROC=2
```

The first two commands build and install model-free test binaries. The third
builds the llama tools without model downloads. `ROOTFS_BUILD_DIR`,
`HOST_BUILD_DIR` and `TARGET_BUILD_DIR` can select isolated output directories.
Configure `RISCV`, `RISCV_SYSROOT` and `LLVM_HOME` through the shared environment
or explicit overrides, not a private path embedded in a wrapper.

The default image stays llama-based. MNN and NCNN are opt-in apps with additive
initramfs descriptors; see `firmware/riscv-rootfs/apps/AI-INTEGRATION.md`.
MNN inference additionally requires an explicit ONNX input or fixed URL plus
SHA256 and host conversion tools. SqueezeNet/BF16/NCNN external-model caches
are not implicit dependencies of the minimal installation.

Pass the exact descriptor list to rootfs `verify-manifest` before packaging.
The firmware's common base/library descriptors must be included when validating
the complete image, not just the additive MNN/NCNN descriptors.

## openRuyi/PyTorch userspace recipe

`firmware/ruyi/examples/openruyi-pytorch-current.json` is schema version 2 and
records one OCI rootfs plus 30 RPM inputs with fixed SHA-256 values and public
HTTPS URLs. The recipe verifies every input before staging, uses an atomic
digest-keyed cache, rejects unsafe tar members, supports the RPM fallback
extractor, and applies the tracked overlay. The closure validation passed the
eight recipe unit tests and a complete local assembly produced a
199,329,300-byte initramfs.

This recipe deliberately stops at the userspace/initramfs boundary. Kernel,
DTB, OpenSBI/GCPT and physical initramfs placement remain firmware-owned; use
the firmware external-initramfs flow below rather than treating a local board
payload as a portable recipe input.

## Triton/xscpu AOT contract

`DSL/triton-xscpu` records the fixed precompiled
`triton-xscpu-riscv64-20260918` bundle. Its archive SHA-256 is
`763a86a8dc952462dcec120c29148b1f37d72bfad3e72869cdd64666d9b0beb5`, and the
integration verifies the bundle manifest, compiler tools, runtime libraries,
Triton wheels, bootstrap wheels and metadata before staging. The supported
release claim is the documented int8-to-int32 ZAMES/ZMASYNC proposal-12 AOT
path. BF16, floating-point hardware correctness, generic JIT, and
source-reproducible backend builds are not claimed.

## External initramfs and FPGA boundaries

The default firmware path remains kernel-embedded initramfs. The opt-in path
is:

```sh
make -C firmware build-external INITRAMFS_MODE=external
```

It builds a standalone CPIO from the current complete manifest, checks aligned
guest-RAM/direct-map placement, emits `linux,initrd-start/end` through the
merged `firmware/nemu_board` commit
`12b0322f0edcc19b64c79ca54f1c1494d0966902`, and passes the combined
kernel+initramfs payload to OpenSBI. The firmware `VERSIONS` table records that
fetchable gitlink and the merged rootfs revision.

The maintained FPGA path is the explicit reset/program/run flow documented in
`docs/fpga-workflow.md`; `make test-fpga` is an offline gate. Neither that gate
nor the software closure claims a new bitstream boot, model accuracy,
performance result, or unresolved historical llama-bench timing issue.

## Validation boundary

This integration records host regression and clean fixed-source cross-build
gates. It does not assert a newly boot-tested image, end-to-end model accuracy,
performance, or FPGA compatibility. App-local `run-user*` helpers are local-only
diagnostics requiring a compatible Matrix-enabled QEMU; they are not portable
release acceptance tests. Full runtime acceptance still follows QEMU → NEMU →
checkpoint → RTL where needed. The existing master simulator, toolchain and
platform pins are unchanged; their compatibility with these workloads still
needs a separate runtime gate.

Metadata-only `.gguf.om` / fake-like tests are not real inference. The existing
openRuyi/PyTorch, Triton, firmware packaging, and FPGA evidence remain
separately scoped gates as described above. No simulator, ISA, RTL or FPGA
bitstream source changes, Nix-specific work, large models, binaries or
generated artifacts are included in this integration.

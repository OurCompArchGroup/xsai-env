# Software Workstream

`software/` is the umbrella namespace for workload projects in `xsai-env`.

Today, active software also lives in:

- `firmware/riscv-rootfs/apps/` for Linux/rootfs userspace programs
- `nexus-am/apps/` for AM-style bare-metal apps

Framework source is kept here as pinned submodules:

- `software/MNN/` — AME kernels and shared allocator
- `software/ncnn/` — NCNN framework and XSAI convolution glue
- `software/llama.cpp/` — llama.cpp, the ggml AME backend, and the ggml xsai adapter

The shared XSAI BLAS/GEMM library is pinned at the repository root as
`xsai-blas/`, not under `software/`: several apps (llama.cpp and the rootfs test
app) consume the same prepared-weight and kernel code, and the rootfs wrappers
resolve it through `XS_PROJECT_ROOT`. Treat the top-level gitlink as the source
of truth.

The source submodules and the `xsai-blas` gitlink are the single source of
truth. The matching
`firmware/riscv-rootfs/apps/{mnn,ncnn,llama.cpp}/` directories contain only
rootfs build/install wrappers and tests. They must receive an explicit
`*_SRC` override when a different checkout is intended; they do not silently
fall back to an app-local clone.

## Key Paths

The current high-priority software paths are:

- `firmware/riscv-rootfs/apps/hello_xsai/`
- `firmware/riscv-rootfs/apps/gemm_precomp/`
- `firmware/riscv-rootfs/apps/llama.cpp/`

`hello_xsai` and `gemm_precomp` are the main Linux/rootfs smoke tests.

`llama.cpp` is the main AI software adaptation path for XSAI.
The most important development points there are:

- `ggml` AME operators
- `ggml` xsai adapter (Q8_0 `MUL_MAT` to xsai-blas)
- `llama-simple-xsai`
- `llama-bench`

## Scope

- Benchmarks, demos, applications, and workload integration
- Linux-side user programs and AM-side workload code
- Performance or functionality validation of Matrix-enabled software stacks

## Rules

- Prefer keeping platform/runtime setup in the owning subsystem rather than copying it into every app.
- Rootfs packaging belongs with `firmware/riscv-rootfs/`.
- Bare-metal runtime/library semantics belong with `nexus-am/`.
- Toolchain or ISA contract changes should be pushed down into `llvm-project-ame/`, `DSL/`, `NEMU/`, `qemu/`, or `XSAI/` as appropriate, not hidden in app-local workarounds.

The current pinned framework revisions are recorded by the top-level Git
submodules. Generated models, build directories, rootfs images, and board
payloads remain local artifacts rather than framework source.

For rootfs smoke tests, remember that "the software path works" only when all three layers line up:

- `firmware/riscv-rootfs/Makefile`
- `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt`
- `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh`

## Validation

- `make software-init` initializes the framework sources, `xsai-blas`, and
  rootfs at the pinned gitlinks. `make test-ai-software` runs the host-only
  integration gates.
  See `../docs/ai-software-integration.md` for build gates and claim boundaries.
- For rootfs apps, start with app-local builds under `firmware/riscv-rootfs/apps/<app>/`, then validate via `make firmware` and `make run-qemu`.
- For AM apps, use app-local or test-local `nexus-am` targets first, then validate on the intended simulator or RTL path.

For the current smoke path, explicitly check that `hello_xsai` and `gemm_precomp` are still built, packed, and reachable from init.

See `../docs/workstreams.md` for the full dependency map.

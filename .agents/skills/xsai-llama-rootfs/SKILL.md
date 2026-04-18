---
name: xsai-llama-rootfs
description: Guide for developing the XSAI llama.cpp rootfs integration. Use this when asked to modify firmware/riscv-rootfs/apps/llama.cpp, especially ggml AME operators, llama-simple-xsai, llama-bench, model packaging, or init/rootfs integration for AI inference workloads.
---

# XSAI Llama Rootfs

Use this skill when the task is primarily about:

- `firmware/riscv-rootfs/apps/llama.cpp/`
- `ggml` AME operator adaptation
- `llama-simple-xsai`
- `llama-bench`
- model packaging for rootfs or fake-like benchmark inputs

## Current repo role

`firmware/riscv-rootfs/apps/llama.cpp/` is the main AI software adaptation path in this repo.

The most important code and workflow surfaces are:

- `ggml` AME-related changes in the imported `llama.cpp` source tree
- `llama-simple-xsai` as the simple inference path
- `llama-bench` as the main benchmarking path
- the rootfs packaging path that installs the binaries into `firmware/riscv-rootfs/rootfsimg/build/`

## Primary files

- `firmware/riscv-rootfs/apps/llama.cpp/Makefile`
- `firmware/riscv-rootfs/apps/llama.cpp/llama-xsai.sh`
- `firmware/riscv-rootfs/apps/llama.cpp/BENCHMARKS.md`
- `firmware/riscv-rootfs/apps/llama.cpp/gguf-metadata-only.sh`
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/`
- `firmware/riscv-rootfs/apps/llama.cpp/repo/examples/`
- `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt`
- `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh`

## Build flow

Prefer the app-local Makefile first:

```bash
make -C firmware/riscv-rootfs/apps/llama.cpp print-config
make -C firmware/riscv-rootfs/apps/llama.cpp install
```

For full integration:

```bash
make firmware
make run-qemu
```

## Repo-specific facts

- The app Makefile builds host and RISC-V targets separately.
- The target path explicitly enables AME-related options such as `-DGGML_RV_AME=ON`.
- The installed rootfs binaries include `llama-simple-xsai`, `llama-bench`, `llama-batched-bench`, and the wrapper `llama-xsai`.
- The initramfs manifest already includes `llama-simple-xsai` and `llama-bench`.
- The current init script also contains explicit `llama-bench` benchmark invocations.

## Typical task routing

- If the change is in matrix kernels or `ggml` AME code, stay in `firmware/riscv-rootfs/apps/llama.cpp/` first.
- If the change is about boot-time selection, packaging, or default model wiring, inspect the rootfs manifest and init script together.
- If the change needs ISA, toolchain, or RTL support, treat `llama.cpp` as a downstream consumer and coordinate with the owning subsystem.

## Validation advice

- Use app-local builds for the fastest iteration.
- Use `make firmware` and `make run-qemu` when validating the real rootfs path.
- If benchmarking with metadata-only models, keep the `.gguf.om` / `--fake-like` path distinct from full inference runs.
- Read `docs/workstreams.md` when the change may actually belong to compiler, firmware, simulator, or RTL layers.

The current default repo ladder for software validation is:

1. `make run-qemu`
2. `make run-nemu`
3. `make ckpt`
4. `make run-nemu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`
5. `make run-emu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`

Adjust the checkpoint path if `WORKLOAD_NAME` or `CHECKPOINT_CONFIG` changes.

## Easy mistakes

- Editing `llama.cpp` source but forgetting the rootfs integration layer in `initramfs-disk-xsai.txt` or `init-disk-xsai.sh`
- Mixing up metadata-only `.gguf.om` benchmark inputs with real inference models
- Validating only on RTL first instead of QEMU and NEMU
- Treating `llama-bench` benchmark issues as pure app bugs when the model-packaging or boot-time model path is wrong
- Forgetting that `ggml` AME changes may also need smoke-test revalidation through `hello_xsai` or `gemm_precomp`

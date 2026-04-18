---
name: xsai-software-debug
description: Guide for building, disassembling, and debugging XSAI RISC-V software with the repository's custom LLVM toolchain and Matrix extension support. Use this when asked to analyze crashes, inspect Matrix instructions, or debug XSAI user programs.
---

# XSAI Software Debug

This skill helps you debug XSAI RISC-V software that is built with the repository's custom LLVM toolchain and uses the Matrix extension.

## When to use this skill

Use this skill when you need to:
- Build XSAI software with the repository's custom LLVM toolchain
- Disassemble binaries or object files that contain Matrix instructions
- Debug runtime failures in XSAI user programs such as `hello_xsai`
- Correlate crash addresses with disassembly and symbols
- Consult the Matrix ISA specification while analyzing generated instructions

## Repository assumptions

This repository already provides the required environment variables. Do not add setup steps unless the user explicitly asks for them.

Use the existing variables directly:
- `XS_PROJECT_ROOT` for the workspace root
- `LLVM_HOME` for the custom LLVM installation
- `RISCV_ROOTFS_HOME` for Linux/rootfs-side apps
- `AM_HOME` for AM apps and tests
- `QEMU_LD_PREFIX` when a dynamically linked binary needs a RISC-V sysroot at runtime

The Matrix ISA reference lives in `riscv-matrix-spec/`.

Do not assume the repo exports a stable top-level `ARCH` or `CROSS_COMPILE`. The current repo deliberately avoids exporting a single global cross toolchain prefix.

## Building XSAI software

There are two common software paths in this repo:

- Linux/rootfs apps under `firmware/riscv-rootfs/apps/`
- AM apps/tests under `nexus-am/apps/` and `nexus-am/tests/`

The most important rootfs software hotspots today are:

- `firmware/riscv-rootfs/apps/hello_xsai/`
- `firmware/riscv-rootfs/apps/gemm_precomp/`
- `firmware/riscv-rootfs/apps/llama.cpp/`

For `llama.cpp`, the main development surfaces are:

- `ggml` AME operators
- `llama-simple-xsai`
- `llama-bench`

Prefer the existing Makefiles for the owning path before crafting ad hoc commands.

## Common modified files

For the main rootfs smoke and software hotspots, the most common edit points are:

- `firmware/riscv-rootfs/apps/hello_xsai/Makefile`
- `firmware/riscv-rootfs/apps/hello_xsai/ame.h`
- `firmware/riscv-rootfs/apps/hello_xsai/ggml_ame_gemm_tile_i8_i32_bT.c`
- `firmware/riscv-rootfs/apps/hello_xsai/auto_test.c`
- `firmware/riscv-rootfs/apps/hello_xsai/mem.c`
- `firmware/riscv-rootfs/apps/hello_xsai/hello_xsai.c`
- `firmware/riscv-rootfs/apps/gemm_precomp/Makefile`
- `firmware/riscv-rootfs/apps/gemm_precomp/main.c`
- `firmware/riscv-rootfs/apps/gemm_precomp/precomp_test.c`
- `firmware/riscv-rootfs/apps/gemm_precomp/test_data.h`
- `firmware/riscv-rootfs/apps/llama.cpp/Makefile`
- `firmware/riscv-rootfs/apps/llama.cpp/llama-xsai.sh`
- `firmware/riscv-rootfs/apps/llama.cpp/BENCHMARKS.md`
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/`
- `firmware/riscv-rootfs/apps/llama.cpp/repo/examples/`
- `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt`
- `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh`

Shared-coupling note:

- `gemm_precomp` reuses AME kernel code from `hello_xsai`, so AME-kernel edits often require both smoke apps to be revalidated.

## Default validation ladder

For software changes, prefer this order:

1. `make run-qemu`
2. `make run-nemu`
3. `make ckpt`
4. `make run-nemu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`
5. `make run-emu PAYLOAD=firmware/checkpoints/build/app/1/_1_1.zstd`

Why:

- QEMU is the fastest and usually easiest place to diagnose software bugs.
- NEMU is the golden-model gate before RTL.
- RTL is much slower and should usually only be used after the software path is already narrowed down.

The checkpoint payload path above matches the current defaults. If `WORKLOAD_NAME` or `CHECKPOINT_CONFIG` changes, update the path accordingly.

For Matrix-enabled rootfs builds, use the same flags as the repository Makefiles:

```bash
AME_TARGET="-target riscv64-unknown-linux-gnu"
AME_ARCH="-march=rv64g_v_zvfh_zame_zvl128b_zicbop_zihintpause"
AME_FEATURE="-Xclang -target-feature -Xclang +matrix-xuantie-0.6"
```

Apply those flags consistently to both compile and link steps.

Prefer the repository LLVM tools over system tools when Matrix instructions are involved.

Representative build pattern:

```bash
$(LLVM_HOME)/bin/clang \
	-target riscv64-unknown-linux-gnu \
	-march=rv64g_v_zvfh_zame_zvl128b_zicbop_zihintpause \
	-Xclang -target-feature -Xclang +matrix-xuantie-0.6 \
	-c auto_test.c -o auto_test.o
```

## Disassembling Matrix binaries

1. Use `llvm-objdump`, not GNU `objdump`, for Matrix-aware disassembly.
2. Pass `--mattr=+matrix-xuantie-0.6` so Matrix instructions decode correctly.
3. Disassemble either the final binary or the relevant object file, depending on whether you are debugging code generation or runtime layout.

Example commands:

```bash
$(LLVM_HOME)/bin/llvm-objdump -d binary_file --mattr=+matrix-xuantie-0.6
```

```bash
$(LLVM_HOME)/bin/llvm-objdump -d auto_test.o --mattr=+matrix-xuantie-0.6 > auto_test.S
```

## Debugging crashes

1. Capture the failing command and the exact crash output.
2. Extract the important runtime addresses such as `epc` and `ra` from the kernel or simulator logs.
3. Determine whether the binary is PIE:

```bash
readelf -h binary_file | grep Type
```

4. Extract symbols to map offsets back to functions:

```bash
readelf -s binary_file
```

5. Generate disassembly with `llvm-objdump` and inspect the instructions around the computed offset.
6. If Matrix instructions are involved, cross-check instruction intent against `$(XS_PROJECT_ROOT)/riscv-matrix-spec`.
7. Focus first on concrete failure classes:
- Buffer overflows or out-of-bounds accesses
- Corrupted return addresses or function pointers
- Incorrect assumptions about PIE load addresses
- Missing or broken Matrix kernel/runtime initialization

When the failure only reproduces after packaging into the rootfs or booting Linux, include the firmware/rootfs path in the investigation instead of treating it as a pure app bug.

## Common commands

Build a rootfs app:

```bash
make -C firmware/riscv-rootfs/apps/hello_xsai install
```

Build the second smoke app:

```bash
make -C firmware/riscv-rootfs/apps/gemm_precomp install
```

Build an AM test:

```bash
make -C nexus-am/tests/ame0.6 TOOLCHAIN=LLVM
```

Generate Matrix-aware disassembly:

```bash
$(LLVM_HOME)/bin/llvm-objdump -d firmware/riscv-rootfs/apps/hello_xsai/build/hello_xsai --mattr=+matrix-xuantie-0.6
```

Inspect symbols:

```bash
readelf -s firmware/riscv-rootfs/apps/hello_xsai/build/hello_xsai
```

Run the user-mode test path:

```bash
make run-user
```

Treat `make run-user` as a repo-local convenience path, not the universal validation entrypoint. For most Linux-side integration issues, `make firmware` and `make run-qemu` are the more representative paths.

For the current smoke path, remember that `hello_xsai` and `gemm_precomp` only exercise the real boot path when they are also packed by `initramfs-disk-xsai.txt` and reachable from `init-disk-xsai.sh`.

## Best practices

- Reuse existing repository variables instead of reintroducing environment setup steps.
- Prefer repository Makefiles before crafting ad hoc compile commands.
- Use `llvm-objdump` from `$(LLVM_HOME)/bin` whenever Matrix instructions may appear.
- When debugging crashes, map addresses to symbols before speculating about root cause.
- Check the Matrix ISA specification when an instruction sequence is unclear.
- Keep analysis focused on the actual failing binary and runtime path the user executed.
- Distinguish Linux/rootfs-side failures from AM-side failures before choosing the build and run path.
- Read `docs/workstreams.md` when the bug may cross software, firmware, runtime, or simulator boundaries.
- If the task is specifically about `llama.cpp`, `llama-simple-xsai`, `llama-bench`, or `ggml` AME adaptation, prefer the dedicated `xsai-llama-rootfs` skill.

## Easy mistakes

- Editing a rootfs app and forgetting the boot-path closure in `firmware/riscv-rootfs/Makefile`, `initramfs-disk-xsai.txt`, and `init-disk-xsai.sh`
- Jumping straight to RTL before reproducing on QEMU and NEMU
- Treating `make run-user` as equivalent to the real rootfs boot path
- Changing shared AME code under `hello_xsai` and forgetting to revalidate `gemm_precomp`
- Treating a `llama.cpp` integration bug as purely app-local when the rootfs packaging or init script is actually wrong

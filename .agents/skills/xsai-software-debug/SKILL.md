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
- `$(XS_PROJECT_ROOT)` for the workspace root
- `$(LLVM_HOME)` for the custom LLVM installation
- `$(ARCH)` for the target architecture
- `$(CROSS_COMPILE)` for the GNU toolchain prefix

The Matrix ISA reference lives in `$(XS_PROJECT_ROOT)/riscv-matrix-spec`.

## Building XSAI software

1. Prefer the existing app Makefiles under `firmware/riscv-rootfs/apps/` when they already encode the right toolchain behavior.
2. For Matrix-enabled builds, use the same flags as the repository Makefiles:

```bash
AME_TARGET="-target riscv64-unknown-linux-gnu"
AME_ARCH="-march=rv64g_v_zvfh_zame_zvl128b_zicbop_zihintpause"
AME_FEATURE="-Xclang -target-feature -Xclang +matrix-xuantie-0.6"
```

3. Apply those flags consistently to both compile and link steps.
4. Prefer the repository LLVM tools over system tools when Matrix instructions are involved.

Example build pattern:

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

## Common commands

Build an app:

```bash
make -C firmware/riscv-rootfs/apps/hello_xsai all
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

## Best practices

- Reuse existing repository variables instead of reintroducing environment setup steps.
- Prefer repository Makefiles before crafting ad hoc compile commands.
- Use `llvm-objdump` from `$(LLVM_HOME)/bin` whenever Matrix instructions may appear.
- When debugging crashes, map addresses to symbols before speculating about root cause.
- Check the Matrix ISA specification when an instruction sequence is unclear.
- Keep analysis focused on the actual failing binary and runtime path the user executed.

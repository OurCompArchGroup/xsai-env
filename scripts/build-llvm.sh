#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Detect RISC-V cross compiler
# Priority: 1) RISCV toolchain root  2) RISCV_TOOLCHAIN_PREFIX  3) compiler on PATH
# ---------------------------------------------------------------------------
if [[ -n "${RISCV:-}" && -x "$RISCV/bin/riscv64-unknown-linux-gnu-gcc" ]]; then
  RISCV_TOOLCHAIN_PREFIX="$RISCV/bin/riscv64-unknown-linux-gnu-"
  echo "Using RISC-V toolchain: $RISCV_TOOLCHAIN_PREFIX"
elif [[ -n "${RISCV_TOOLCHAIN_PREFIX:-}" ]] && command -v "${RISCV_TOOLCHAIN_PREFIX}gcc" >/dev/null 2>&1; then
  echo "Using RISCV_TOOLCHAIN_PREFIX: $RISCV_TOOLCHAIN_PREFIX"
else
  RISCV_TOOLCHAIN_PREFIX="riscv64-linux-gnu-"
  if ! command -v "${RISCV_TOOLCHAIN_PREFIX}gcc" >/dev/null 2>&1; then
    echo "Error: RISC-V cross compiler not found." >&2
    echo "  Install: sudo apt install gcc-riscv64-linux-gnu g++-riscv64-linux-gnu" >&2
    echo "  Or set: export RISCV=<toolchain-prefix>" >&2
    exit 1
  fi
fi

INSTALL_PREFIX="${LLVM_HOME:-$ROOT/local/llvm}"
mkdir -p "$INSTALL_PREFIX"
export PATH="$INSTALL_PREFIX/bin:$PATH"

# Use ninja if available (much faster for LLVM)
if command -v ninja >/dev/null 2>&1; then
  BUILD_CMD="ninja"
  INSTALL_CMD="ninja install"
  GEN_FLAGS=("-GNinja")
else
  BUILD_CMD="make -j$(nproc)"
  INSTALL_CMD="make install"
  GEN_FLAGS=()
fi

cd "$ROOT/llvm-project-ame"

# Clean stale build dir if the generator changed (e.g. Ninja <-> Unix Makefiles)
if [[ -f build/CMakeCache.txt ]]; then
  CACHED_GENERATOR=$(grep -s "^CMAKE_GENERATOR:INTERNAL=" build/CMakeCache.txt | cut -d= -f2 || true)
  if command -v ninja >/dev/null 2>&1 && [[ "$CACHED_GENERATOR" != "Ninja" ]]; then
    echo "Cleaning stale build dir (generator changed to Ninja)"
    rm -rf build
  elif ! command -v ninja >/dev/null 2>&1 && [[ "$CACHED_GENERATOR" == "Ninja" ]]; then
    echo "Cleaning stale build dir (generator changed to Unix Makefiles)"
    rm -rf build
  fi
fi
mkdir -p build
cd build

cmake -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_THREADS=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=On \
  -DLLVM_ENABLE_PROJECTS="clang;lld;clang-tools-extra" \
  -DLLVM_LINK_LLVM_DYLIB=On \
  -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-linux-gnu" \
  -DLLVM_TARGETS_TO_BUILD="RISCV;X86" \
  "${GEN_FLAGS[@]}" \
  ../llvm

$BUILD_CMD
$INSTALL_CMD

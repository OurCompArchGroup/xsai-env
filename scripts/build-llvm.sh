#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RISCV_TOOLCHAIN_PREFIX="${RISCV_TOOLCHAIN_PREFIX:-riscv64-linux-gnu-}"
INSTALL_PREFIX="${LLVM_HOME:-$ROOT/local/llvm}"

if ! command -v "${RISCV_TOOLCHAIN_PREFIX}gcc" >/dev/null 2>&1; then
  echo "Error: RISC-V cross compiler ${RISCV_TOOLCHAIN_PREFIX}gcc was not found"
  echo "Install the RISC-V cross toolchain first:"
  echo "  sudo apt-get install gcc-riscv64-linux-gnu g++-riscv64-linux-gnu"
  exit 1
fi

mkdir -p "$INSTALL_PREFIX"
export PATH="$INSTALL_PREFIX/bin:$PATH"

cd "$ROOT/llvm-project-ame"
mkdir -p build
cd build

cmake -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_OPTIMIZED_TABLEGEN=On \
  -DLLVM_ENABLE_PROJECTS="clang;lld;clang-tools-extra" \
  -DLLVM_LINK_LLVM_DYLIB=On \
  -DLLVM_DEFAULT_TARGET_TRIPLE="riscv64-unknown-linux-gnu" \
  -DLLVM_TARGETS_TO_BUILD="RISCV" \
  ../llvm

make -j"$(nproc)"
make install

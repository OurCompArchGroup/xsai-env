#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/env.sh"
export NOOP_HOME="$ROOT/NutShell"

cd "$NEMU_HOME"

CPT_CROSS_COMPILE=""
CPT_CROSS_COMPILE_LIST='riscv64-linux-gnu- riscv64-unknown-linux-gnu-'
for COMPILE in $CPT_CROSS_COMPILE_LIST; do
  if command -v "${COMPILE}gcc" >/dev/null 2>&1 && echo | "${COMPILE}gcc" -S -march=rv64gcbkvh -o /dev/null -x c -; then
    CPT_CROSS_COMPILE="$COMPILE"
    break
  fi
done

if [[ -z "$CPT_CROSS_COMPILE" ]]; then
  echo 'No supported RISC-V compiler found! riscv64[-unknown]-linux-gnu-gcc with -march=rv64gcbkvh support needed.'
  exit 1
fi

make riscv64-nutshell-ref_defconfig CPT_CROSS_COMPILE="$CPT_CROSS_COMPILE"
make

cd "$NOOP_HOME"
make init
make clean
make verilog
make emu
./build/emu -b 0 -e 0 -i ./ready-to-run/microbench.bin

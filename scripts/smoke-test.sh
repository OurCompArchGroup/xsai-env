#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "$#" -ne 0 ]]; then
  echo "usage: $0" >&2
  exit 2
fi

printf '[smoke] mode=manual\n'

for script in \
  env.sh \
  scripts/env-common.sh \
  scripts/setup.sh \
  scripts/build-llvm.sh \
  scripts/env-test.sh \
  scripts/setup-tools.sh \
  scripts/install-gsim.sh \
  scripts/update-submodule.sh \
  scripts/update-versions.sh \
  scripts/fpga-run-ai.sh \
  scripts/smoke-test.sh; do
  bash -n "$script"
done

env -u XS_PROJECT_ROOT -u RISCV -u QEMU_LD_PREFIX -u CROSS_COMPILE -u ARCH bash -lc '
  source ./env.sh >/dev/null
  [[ "$XS_PROJECT_ROOT" = "'"$ROOT"'" ]]
  [[ -n "$NEMU_HOME" ]]
  [[ -n "$QEMU_HOME" ]]
  [[ -z "${CROSS_COMPILE:-}" ]]
  [[ -z "${ARCH:-}" ]]
'

make_db="$(mktemp)"
trap 'rm -f "$make_db"' EXIT
make -qp >"$make_db" 2>/dev/null || true

declared_targets=(firmware qemu xsai gsim run-fpga fpga-reset test test-smoke)
for target in "${declared_targets[@]}"; do
  grep -q "^${target}:" "$make_db"
done

safe_dry_run_targets=(gsim test-smoke)
for target in "${safe_dry_run_targets[@]}"; do
  make -n "$target" >/dev/null
done

printf '[smoke] ok\n'

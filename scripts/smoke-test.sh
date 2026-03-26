#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:-manual}"
if [[ "$MODE" == "--mode" ]]; then
  MODE="${2:-manual}"
fi

printf '[smoke] mode=%s\n' "$MODE"

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

declared_targets=(firmware qemu xsai gsim nix-shell nix-init nix-test test test-smoke nix-smoke)
for target in "${declared_targets[@]}"; do
  grep -q "^${target}:" "$make_db"
done

safe_dry_run_targets=(gsim nix-shell nix-init nix-test test-smoke nix-smoke)
for target in "${safe_dry_run_targets[@]}"; do
  make -n "$target" >/dev/null
 done

if [[ "$MODE" == "nix" ]]; then
  command -v nix >/dev/null
  command -v riscv64-unknown-linux-gnu-gcc >/dev/null
  nix flake show --no-write-lock-file >/dev/null
fi

printf '[smoke] ok\n'

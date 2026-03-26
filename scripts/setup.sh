#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GIT_FORCE_INIT="${GIT_FORCE_INIT:-0}"
FORCE_ARGS=()
if [[ "$GIT_FORCE_INIT" == "1" ]]; then
  FORCE_ARGS=(--force)
fi

init_dev() {
  git submodule update --init "${FORCE_ARGS[@]}" DRAMsim3 NEMU NutShell nexus-am riscv-matrix-spec qemu
  git submodule update --init "${FORCE_ARGS[@]}" --depth 1 llvm-project-ame
  git submodule update --init "${FORCE_ARGS[@]}" XSAI
  $(command -v make) -C XSAI init-force
  $(command -v make) -C firmware init GIT_FORCE_INIT="$GIT_FORCE_INIT"
}

init_user() {
  git submodule update --init "${FORCE_ARGS[@]}" qemu
  $(command -v make) -C firmware init GIT_FORCE_INIT="$GIT_FORCE_INIT"
}

case "${1:-dev}" in
  dev)
    init_dev
    ;;
  user)
    init_user
    ;;
  *)
    echo "Usage: $0 [dev|user]" >&2
    exit 1
    ;;
esac

source "$ROOT/env.sh"
echo XS_PROJECT_ROOT: ${XS_PROJECT_ROOT}
echo NEMU_HOME: ${NEMU_HOME}
echo AM_HOME: ${AM_HOME}
echo NOOP_HOME: ${NOOP_HOME}

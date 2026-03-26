#!/usr/bin/env bash

# Adapted for xsai-env from the XiangShan bug report helper:
# https://github.com/OpenXiangShan/XiangShan/blob/kunminghu-v3/scripts/bug-report.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_ROOT="${ROOT}/bug-report"
REPORT_FILE="${REPORT_ROOT}.tar.gz"
ONLY_BASIC=false
BUILD_CMD=""
RUN_CMD=""
NOTE=""

append_block() {
  local file="$1"
  local title="$2"
  local value="$3"
  {
    printf '=== %s ===\n' "$title"
    printf '%s\n\n' "$value"
  } >>"${REPORT_ROOT}/${file}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

capture_cmd() {
  local file="$1"
  local title="$2"
  local cmd="$3"
  local output
  echo "  -> ${title}"
  output="$(bash -lc "$cmd" 2>&1 || true)"
  append_block "$file" "$title" "$output"
}

init_report() {
  echo "Generating xsai-env bug report..."
  rm -rf "$REPORT_ROOT"
  rm -f "$REPORT_FILE"
  mkdir -p "$REPORT_ROOT"
  append_block meta.txt generated-at "$(date --iso-8601=seconds 2>/dev/null || date)"
}

collect_host_info() {
  echo
  echo "Collecting host information..."

  capture_cmd host.txt uname "uname -a"
  capture_cmd host.txt os-release "cat /etc/os-release 2>/dev/null || cat /usr/lib/os-release 2>/dev/null || echo 'os-release unavailable'"

  if command_exists lscpu; then
    capture_cmd hardware.txt cpu "lscpu"
  fi
  if command_exists free; then
    capture_cmd hardware.txt memory "free -h"
  fi
  if command_exists df; then
    capture_cmd hardware.txt disk "df -h '${ROOT}'"
  fi

  for tool in git make bash python3 gcc clang ldd java mill nix direnv patchelf qemu-system-riscv64 qemu-riscv64; do
    if command_exists "$tool"; then
      capture_cmd tools.txt "$tool" "$tool --version | head -n 3"
    else
      append_block tools.txt "$tool" "not found"
    fi
  done

  capture_cmd env.txt selected-environment "source '${ROOT}/env.sh' >/dev/null 2>&1 || true; env | grep -E '^(XS_PROJECT_ROOT|NEMU_HOME|QEMU_HOME|AM_HOME|NOOP_HOME|LLVM_HOME|RISCV|RISCV_ROOTFS_HOME|QEMU_LD_PREFIX|IN_NIX_SHELL|XSAI_ENV_QUIET)=' | sort"
}

collect_repo_info() {
  echo
  echo "Collecting repository information..."

  capture_cmd repo.txt branch "git -C '${ROOT}' branch --show-current"
  capture_cmd repo.txt head "git -C '${ROOT}' log -1 --oneline --no-abbrev-commit"
  capture_cmd repo.txt status "git -C '${ROOT}' status --short"
  capture_cmd repo.txt submodules "git -C '${ROOT}' submodule status"
  capture_cmd repo.txt recent-log "git -C '${ROOT}' log --oneline -n 10"
  capture_cmd repo.txt diff-stat "git -C '${ROOT}' diff --stat && echo && git -C '${ROOT}' diff --cached --stat"

  if [[ -f "${ROOT}/VERSIONS" ]]; then
    capture_cmd repo.txt versions-file "cat '${ROOT}/VERSIONS'"
  fi
}

collect_runtime_info() {
  echo
  echo "Collecting build and runtime context..."

  if [[ -z "$BUILD_CMD" ]]; then
    read -r -p "Build command (press Enter to skip): " BUILD_CMD
  fi
  if [[ -z "$RUN_CMD" ]]; then
    read -r -p "Run command (press Enter to skip): " RUN_CMD
  fi
  if [[ -z "$NOTE" ]]; then
    read -r -p "Short issue summary (press Enter to skip): " NOTE
  fi

  append_block runtime.txt build-command "$BUILD_CMD"
  append_block runtime.txt run-command "$RUN_CMD"
  append_block runtime.txt note "$NOTE"

  echo
  echo "If you have logs, screenshots, or minimal reproducer files, copy them into:"
  echo "  ${REPORT_ROOT}"
  read -r -p "Press Enter after you have finished copying extra files..." _unused
}

finalize_report() {
  echo
  echo "Compressing report..."
  tar -czf "$REPORT_FILE" -C "$REPORT_ROOT" .
  echo
  echo "Bug report bundle generated at:"
  echo "  ${REPORT_FILE}"
  echo "Attach this archive when opening an issue in this repository."
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --basic)
      ONLY_BASIC=true
      shift
      ;;
    --build-cmd)
      BUILD_CMD="${2:-}"
      shift 2
      ;;
    --run-cmd)
      RUN_CMD="${2:-}"
      shift 2
      ;;
    --note)
      NOTE="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--basic] [--build-cmd <cmd>] [--run-cmd <cmd>] [--note <text>]" >&2
      exit 1
      ;;
  esac
done

init_report
collect_host_info
collect_repo_info
if [[ "$ONLY_BASIC" == false ]]; then
  collect_runtime_info
fi
finalize_report
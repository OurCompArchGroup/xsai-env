#!/usr/bin/env bash

_xsai_env_root() {
  local script_path="${BASH_SOURCE[0]:-${(%):-%x}}"
  cd "$(dirname "$script_path")/.." && pwd
}

xsai_env_prepend_path() {
  local path_entry="$1"
  [[ -n "$path_entry" && -d "$path_entry" ]] || return 0
  case ":${PATH}:" in
    *":${path_entry}:"*) ;;
    *) export PATH="${path_entry}:${PATH}" ;;
  esac
}

xsai_env_detect_riscv_root() {
  local prefix="${CROSS_COMPILE:-}"
  local candidates=()
  if [[ -n "$prefix" ]]; then
    candidates+=("$prefix")
  fi
  candidates+=("riscv64-unknown-linux-gnu-" "riscv64-linux-gnu-")
  local known_server="/nfs/share/riscv-toolchain-gcc15-250103"
  local known_host="/opt/riscv"
  local candidate gcc_path

  if [[ -n "${RISCV:-}" && -d "${RISCV}" ]]; then
    printf '%s\n' "$RISCV"
    return 0
  fi

  if [[ -n "${IN_NIX_SHELL:-}" ]]; then
    for candidate in "${candidates[@]}"; do
      if gcc_path="$(command -v "${candidate}gcc" 2>/dev/null)"; then
        cd "$(dirname "$gcc_path")/.." && pwd
        return 0
      fi
    done
  fi

  for candidate in "$known_server" "$known_host"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for candidate in "${candidates[@]}"; do
    if gcc_path="$(command -v "${candidate}gcc" 2>/dev/null)"; then
      cd "$(dirname "$gcc_path")/.." && pwd
      return 0
    fi
  done

  return 1
}

xsai_env_init() {
  export XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(_xsai_env_root)}"
  export NEMU_HOME="${NEMU_HOME:-$XS_PROJECT_ROOT/NEMU}"
  export QEMU_HOME="${QEMU_HOME:-$XS_PROJECT_ROOT/qemu}"
  export AM_HOME="${AM_HOME:-$XS_PROJECT_ROOT/nexus-am}"
  export NOOP_HOME="${NOOP_HOME:-$XS_PROJECT_ROOT/XSAI}"
  export DRAMSIM3_HOME="${DRAMSIM3_HOME:-$XS_PROJECT_ROOT/DRAMsim3}"
  export LLVM_HOME="${LLVM_HOME:-$XS_PROJECT_ROOT/local/llvm}"

  export XSAI_FIRMWARE_HOME="${XSAI_FIRMWARE_HOME:-$XS_PROJECT_ROOT/firmware}"
  export GCPT_RESTORE_HOME="${GCPT_RESTORE_HOME:-$XSAI_FIRMWARE_HOME/gcpt_restore}"
  export RISCV_LINUX_HOME="${RISCV_LINUX_HOME:-$XSAI_FIRMWARE_HOME/riscv-linux}"
  export RISCV_ROOTFS_HOME="${RISCV_ROOTFS_HOME:-$XSAI_FIRMWARE_HOME/riscv-rootfs}"
  export WORKLOAD_BUILD_ENV_HOME="${WORKLOAD_BUILD_ENV_HOME:-$XSAI_FIRMWARE_HOME/nemu_board}"
  export OPENSBI_HOME="${OPENSBI_HOME:-$XSAI_FIRMWARE_HOME/opensbi}"
  export LibCheckpoint="${LibCheckpoint:-$XSAI_FIRMWARE_HOME/LibCheckpoint}"

  if riscv_root="$(xsai_env_detect_riscv_root 2>/dev/null)"; then
    export RISCV="$riscv_root"
  fi

  xsai_env_prepend_path "$XS_PROJECT_ROOT/local/bin"
  xsai_env_prepend_path "$LLVM_HOME/bin"
  if [[ -n "${RISCV:-}" ]]; then
    xsai_env_prepend_path "$RISCV/bin"
  fi

  local sysroot=""
  local sysroot_prefix="${CROSS_COMPILE:-}"
  local sysroot_candidates=()
  if [[ -n "$sysroot_prefix" ]]; then
    sysroot_candidates+=("$sysroot_prefix")
  fi
  sysroot_candidates+=("riscv64-unknown-linux-gnu-" "riscv64-linux-gnu-")
  for candidate in "${sysroot_candidates[@]}"; do
    if command -v "${candidate}gcc" >/dev/null 2>&1; then
      sysroot="$("${candidate}gcc" -print-sysroot 2>/dev/null || true)"
      [[ -n "$sysroot" ]] && break
    fi
  done
  if [[ -n "$sysroot" && -d "$sysroot" ]]; then
    sysroot="$(cd "$sysroot" && pwd)"
    export QEMU_LD_PREFIX="${QEMU_LD_PREFIX:-$sysroot}"
  elif [[ -n "${RISCV:-}" && -d "$RISCV/sysroot" ]]; then
    export QEMU_LD_PREFIX="${QEMU_LD_PREFIX:-$RISCV/sysroot}"
  fi
}

xsai_env_print_summary() {
  echo SET XS_PROJECT_ROOT: "${XS_PROJECT_ROOT}"
  echo SET NOOP_HOME \(XSAI RTL Home\): "${NOOP_HOME}"
  echo SET NEMU_HOME: "${NEMU_HOME}"
  echo SET QEMU_HOME: "${QEMU_HOME}"
  echo SET AM_HOME: "${AM_HOME}"
  echo SET DRAMSIM3_HOME: "${DRAMSIM3_HOME}"
  echo SET LLVM_HOME: "${LLVM_HOME}"
  if [[ -n "${RISCV:-}" ]]; then
    echo SET RISCV: "${RISCV}"
  else
    echo WARN RISCV: not resolved, expect compiler on PATH or set RISCV manually
  fi
}

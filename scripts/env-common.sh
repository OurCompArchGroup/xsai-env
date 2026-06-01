#!/usr/bin/env bash

_xsai_env_root() {
  local script_path="${BASH_SOURCE[0]:-${(%):-%x}}"
  cd "$(dirname "$script_path")/.." && pwd
}

xsai_env_resolver() {
  printf '%s/scripts/resolve-riscv-env.sh\n' "$(_xsai_env_root)"
}

xsai_env_prepend_path() {
  local path_entry="$1"
  [[ -n "$path_entry" && -d "$path_entry" ]] || return 0
  case ":${PATH}:" in
    *":${path_entry}:"*) ;;
    *) export PATH="${path_entry}:${PATH}" ;;
  esac
}

xsai_env_source_local_overrides() {
  local root="$1"
  local added_path_add=0

  [[ "${XSAI_ENV_LOAD_LOCAL:-1}" == "1" ]] || return 0
  [[ -f "$root/.envrc.local" ]] || return 0

  if ! declare -F PATH_add >/dev/null 2>&1; then
    PATH_add() {
      xsai_env_prepend_path "$1"
    }
    added_path_add=1
  fi

  # shellcheck source=/dev/null
  source "$root/.envrc.local"

  if [[ "$added_path_add" == "1" ]]; then
    unset -f PATH_add
  fi
}

xsai_env_detect_riscv_root() {
  local resolver
  resolver="$(xsai_env_resolver)"

  if [[ -x "$resolver" ]]; then
    "$resolver" root
    return $?
  fi

  if [[ -n "${RISCV:-}" && -d "${RISCV}" ]]; then
    printf '%s\n' "$RISCV"
    return 0
  fi

  return 1
}

xsai_env_detect_riscv_sysroot() {
  local resolver
  resolver="$(xsai_env_resolver)"

  if [[ -x "$resolver" ]]; then
    "$resolver" sysroot
    return $?
  fi

  if [[ -n "${RISCV_SYSROOT:-}" && -d "${RISCV_SYSROOT}" ]]; then
    printf '%s\n' "$RISCV_SYSROOT"
    return 0
  fi

  if [[ -n "${QEMU_LD_PREFIX:-}" && -d "${QEMU_LD_PREFIX}" ]]; then
    printf '%s\n' "$QEMU_LD_PREFIX"
    return 0
  fi

  if [[ -n "${RISCV:-}" && -d "${RISCV}/sysroot" ]]; then
    printf '%s\n' "${RISCV}/sysroot"
    return 0
  fi

  return 1
}

xsai_env_init() {
  export XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(_xsai_env_root)}"
  xsai_env_source_local_overrides "$XS_PROJECT_ROOT"

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
  if [[ -n "${RISCV:-}" ]]; then
    xsai_env_prepend_path "$RISCV/bin"
  fi

  local sysroot=""
  if sysroot="$(xsai_env_detect_riscv_sysroot 2>/dev/null)"; then
    export RISCV_SYSROOT="${RISCV_SYSROOT:-$sysroot}"
    export QEMU_LD_PREFIX="${QEMU_LD_PREFIX:-$sysroot}"
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
  if [[ -n "${RISCV_SYSROOT:-}" ]]; then
    echo SET RISCV_SYSROOT: "${RISCV_SYSROOT}"
  fi
  if [[ -n "${QEMU_LD_PREFIX:-}" ]]; then
    echo SET QEMU_LD_PREFIX: "${QEMU_LD_PREFIX}"
  fi
}

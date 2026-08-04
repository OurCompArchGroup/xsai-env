#!/usr/bin/env bash

set -euo pipefail

mode="${1:-}"

canonical_dir() {
  local dir="$1"
  [[ -n "$dir" && -d "$dir" ]] || return 1
  (cd "$dir" && pwd -P)
}

candidate_prefixes() {
  if [[ -n "${CROSS_COMPILE:-}" ]]; then
    printf '%s\n' "$CROSS_COMPILE"
  fi
  printf '%s\n' "riscv64-unknown-linux-gnu-"
  printf '%s\n' "riscv64-linux-gnu-"
}

resolve_sysroot_from_root() {
  local root="$1"
  [[ -n "$root" && -d "$root" ]] || return 1

  if [[ -d "$root/sysroot" ]]; then
    canonical_dir "$root/sysroot"
    return 0
  fi

  return 1
}

derive_sysroot_from_runtime() {
  local runtime_path="$1"
  local runtime_dir=""
  local prefix_dir=""

  [[ -n "$runtime_path" && -f "$runtime_path" ]] || return 1

  runtime_dir="$(dirname "$runtime_path")"
  prefix_dir="$(dirname "$runtime_dir")"
  [[ -d "$prefix_dir" ]] || return 1
  canonical_dir "$prefix_dir"
}

resolve_sysroot_from_gcc() {
  local gcc_path="$1"
  local sysroot=""
  local runtime_path=""

  [[ -n "$gcc_path" && -x "$gcc_path" ]] || return 1

  sysroot="$($gcc_path -print-sysroot 2>/dev/null || true)"
  if [[ -n "$sysroot" && "$sysroot" != "/" && -d "$sysroot" ]]; then
    canonical_dir "$sysroot"
    return 0
  fi

  for runtime_name in ld-linux-riscv64-lp64d.so.1 libc.so libc.so.6; do
    runtime_path="$($gcc_path -print-file-name="$runtime_name" 2>/dev/null || true)"
    if [[ "$runtime_path" == /* ]] && derive_sysroot_from_runtime "$runtime_path" >/dev/null 2>&1; then
      derive_sysroot_from_runtime "$runtime_path"
      return 0
    fi
  done

  if [[ -n "$sysroot" && -d "$sysroot" ]]; then
    canonical_dir "$sysroot"
    return 0
  fi

  return 1
}

resolve_gcc_path() {
  local prefix=""
  while IFS= read -r prefix; do
    [[ -n "$prefix" ]] || continue
    if command -v "${prefix}gcc" >/dev/null 2>&1; then
      command -v "${prefix}gcc"
      return 0
    fi
  done < <(candidate_prefixes)
  return 1
}

resolve_riscv_root() {
  local gcc_path=""
  local known_root=""

  if [[ -n "${RISCV:-}" && -d "${RISCV}" ]]; then
    canonical_dir "$RISCV"
    return 0
  fi

  # Prefer dedicated toolchain roots over the generic apt cross-compiler at /usr
  for known_root in "/nfs/share/riscv-toolchain-gcc15-250103" "/opt/riscv"; do
    if [[ -d "$known_root" ]]; then
      canonical_dir "$known_root"
      return 0
    fi
  done

  if gcc_path="$(resolve_gcc_path 2>/dev/null)"; then
    canonical_dir "$(dirname "$gcc_path")/.."
    return 0
  fi

  return 1
}

resolve_riscv_sysroot() {
  local gcc_path=""
  local gcc_root=""
  local sysroot=""

  if [[ -n "${RISCV_SYSROOT:-}" && -d "${RISCV_SYSROOT}" ]]; then
    canonical_dir "$RISCV_SYSROOT"
    return 0
  fi

  if [[ -n "${QEMU_LD_PREFIX:-}" && -d "${QEMU_LD_PREFIX}" ]]; then
    canonical_dir "$QEMU_LD_PREFIX"
    return 0
  fi

  if [[ -n "${RISCV:-}" ]] && resolve_sysroot_from_root "$RISCV" >/dev/null 2>&1; then
    resolve_sysroot_from_root "$RISCV"
    return 0
  fi

  if gcc_path="$(resolve_gcc_path 2>/dev/null)"; then
    if resolve_sysroot_from_gcc "$gcc_path" >/dev/null 2>&1; then
      resolve_sysroot_from_gcc "$gcc_path"
      return 0
    fi

    gcc_root="$(canonical_dir "$(dirname "$gcc_path")/..")"
    if resolve_sysroot_from_root "$gcc_root" >/dev/null 2>&1; then
      resolve_sysroot_from_root "$gcc_root"
      return 0
    fi
  fi

  return 1
}

case "$mode" in
  root)
    resolve_riscv_root
    ;;
  sysroot)
    resolve_riscv_sysroot
    ;;
  *)
    echo "usage: $0 {root|sysroot}" >&2
    exit 2
    ;;
esac

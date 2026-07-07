#!/usr/bin/env bash
#
# Sync and program an xsai-env FPGA bitstream bundle.
# The flow mirrors env-scripts/fpga_diff: PCIe remove, Vivado program, PCIe
# rescan, then hold the CPU in reset for the subsequent workload load step.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

HOST="${FPGA_HOST:-fpga}"
BIT_HOME="${FPGA_BIT_HOME:-}"
REMOTE_BIT_HOME="${FPGA_REMOTE_BIT_HOME:-/home/fpga/xsai-bitstream/current}"
REMOTE_SETUP="${FPGA_REMOTE_SETUP:-source /tools/Xilinx/Vivado_Lab/2020.2/settings64.sh}"
REMOTE_SUDO="${FPGA_REMOTE_SUDO-}"
PCIE_SUDO="${FPGA_PCIE_SUDO-sudo -n}"
LTX_OVERRIDE="${FPGA_LTX:-}"
PCIE_REMOVE_CMD="${FPGA_PCIE_REMOVE_CMD:-}"
PCIE_RESCAN_CMD="${FPGA_PCIE_RESCAN_CMD:-}"
PROGRAM_PCIE_RESET="${FPGA_PROGRAM_PCIE_RESET:-1}"
PROGRAM_ASSERT_RESET="${FPGA_PROGRAM_ASSERT_RESET:-1}"
XDMA_REQUIRED_DEVICES="${FPGA_XDMA_REQUIRED_DEVICES:-/dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_bypass}"
XDMA_RELOAD_ON_MISSING="${FPGA_XDMA_RELOAD_ON_MISSING:-1}"
XDMA_MODULE="${FPGA_XDMA_MODULE:-xdma}"
XDMA_WAIT_SECS="${FPGA_XDMA_WAIT_SECS:-10}"

SYNC_ONLY=0
PROGRAM_ONLY=0

usage() {
  cat <<'EOF'
Usage:
  scripts/fpga-program-bitstream.sh [--sync-only|--program-only]

Environment knobs:
  FPGA_HOST                 Remote FPGA host. Default: fpga
  FPGA_BIT_HOME             Local directory containing .bit/.ltx.
                            If empty, uses the newest local/fpga-vivado/*/artifacts.
  FPGA_REMOTE_BIT_HOME      Remote directory for .bit/.ltx.
                            Default: /home/fpga/xsai-bitstream/current
  FPGA_REMOTE_SETUP         Remote Vivado setup command.
  FPGA_REMOTE_SUDO          Optional sudo command, e.g. "sudo -n".
  FPGA_PCIE_SUDO            Optional sudo command for PCIe sysfs writes only.
                            Default: "sudo -n". Set to empty to disable sudo.
  FPGA_LTX                  Remote .ltx path used by --program-only reset.
  FPGA_PCIE_REMOVE_CMD      Optional custom remote PCIe remove command.
  FPGA_PCIE_RESCAN_CMD      Optional custom remote PCIe rescan command.
  FPGA_PROGRAM_PCIE_RESET   1 removes/rescans PCIe around programming. Default: 1
  FPGA_PROGRAM_ASSERT_RESET 1 asserts CPU reset after programming. Default: 1
  FPGA_XDMA_REQUIRED_DEVICES Space-separated XDMA device nodes required after rescan.
  FPGA_XDMA_RELOAD_ON_MISSING 1 reloads XDMA module if required nodes are missing.
  FPGA_XDMA_MODULE          XDMA kernel module name. Default: xdma
  FPGA_XDMA_WAIT_SECS       Seconds to wait for XDMA device nodes. Default: 10
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sync-only)
      SYNC_ONLY=1
      shift
      ;;
    --program-only)
      PROGRAM_ONLY=1
      shift
      ;;
    --no-pcie-reset)
      PROGRAM_PCIE_RESET=0
      shift
      ;;
    --no-reset)
      PROGRAM_ASSERT_RESET=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$SYNC_ONLY" -eq 1 && "$PROGRAM_ONLY" -eq 1 ]]; then
  echo "--sync-only and --program-only are mutually exclusive" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required command not found: $1" >&2
    exit 1
  }
}

run_remote() {
  local cmd="$1"
  ssh "$HOST" "bash -lc $(printf '%q' "$cmd")"
}

run_remote_with_setup() {
  local cmd="$1"
  run_remote "${REMOTE_SETUP}; ${cmd}"
}

run_remote_script() {
  local script="$1"
  ssh "$HOST" "FPGA_PCIE_SUDO=$(printf '%q' "$PCIE_SUDO") FPGA_REMOTE_SUDO=$(printf '%q' "$REMOTE_SUDO") FPGA_XDMA_REQUIRED_DEVICES=$(printf '%q' "$XDMA_REQUIRED_DEVICES") FPGA_XDMA_RELOAD_ON_MISSING=$(printf '%q' "$XDMA_RELOAD_ON_MISSING") FPGA_XDMA_MODULE=$(printf '%q' "$XDMA_MODULE") FPGA_XDMA_WAIT_SECS=$(printf '%q' "$XDMA_WAIT_SECS") bash -s" < "$script"
}

shell_quote() {
  printf '%q' "$1"
}

find_latest_bit_home() {
  local root="${XS_PROJECT_ROOT}/local/fpga-vivado"
  [[ -d "$root" ]] || return 1
  find "$root" -type d -name artifacts -print | while IFS= read -r dir; do
    compgen -G "${dir}/*.bit" >/dev/null || continue
    compgen -G "${dir}/*.ltx" >/dev/null || continue
    printf '%s\n' "$dir"
  done | sort | tail -n 1
}

resolve_bit_home() {
  if [[ -z "$BIT_HOME" ]]; then
    BIT_HOME="$(find_latest_bit_home || true)"
  fi
  [[ -n "$BIT_HOME" ]] || {
    echo "No FPGA bitstream artifacts found. Run make fpga-bitstream or set FPGA_BIT_HOME." >&2
    exit 1
  }
  [[ -d "$BIT_HOME" ]] || {
    echo "FPGA_BIT_HOME is not a directory: $BIT_HOME" >&2
    exit 1
  }
  BIT_HOME="$(cd "$BIT_HOME" && pwd)"
}

pick_one_file() {
  local pattern="$1"
  local kind="$2"
  local preferred="${3:-}"
  local -a files=()
  local file
  while IFS= read -r file; do
    files+=("$file")
  done < <(find "$BIT_HOME" -maxdepth 1 -type f -name "$pattern" | sort)
  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "No ${kind} file matching ${pattern} in ${BIT_HOME}" >&2
    exit 1
  fi
  if [[ -n "$preferred" ]]; then
    for file in "${files[@]}"; do
      if [[ "$(basename "$file")" == "$preferred" ]]; then
        printf '%s\n' "$file"
        return 0
      fi
    done
  fi
  if [[ "${#files[@]}" -gt 1 ]]; then
    echo "Warning: multiple ${kind} files found; using ${files[0]}" >&2
  fi
  printf '%s\n' "${files[0]}"
}

require_cmd ssh
require_cmd scp

PROGRAM_TCL_LOCAL="${XS_PROJECT_ROOT}/scripts/fpga/program_bitstream.tcl"
RESET_TCL_LOCAL="${XS_PROJECT_ROOT}/scripts/fpga/reset_cpu.tcl"
PCIE_REMOVE_LOCAL="${XS_PROJECT_ROOT}/scripts/fpga/pcie-remove.sh"
PCIE_RESCAN_LOCAL="${XS_PROJECT_ROOT}/scripts/fpga/pcie-rescan.sh"

[[ -f "$PROGRAM_TCL_LOCAL" ]] || { echo "Missing program helper: $PROGRAM_TCL_LOCAL" >&2; exit 1; }
[[ -f "$RESET_TCL_LOCAL" ]] || { echo "Missing reset helper: $RESET_TCL_LOCAL" >&2; exit 1; }
[[ -f "$PCIE_REMOVE_LOCAL" ]] || { echo "Missing PCIe remove helper: $PCIE_REMOVE_LOCAL" >&2; exit 1; }
[[ -f "$PCIE_RESCAN_LOCAL" ]] || { echo "Missing PCIe rescan helper: $PCIE_RESCAN_LOCAL" >&2; exit 1; }

remote_bit_dir="${REMOTE_BIT_HOME%/}"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
remote_program_tcl="/tmp/xsai-program-bitstream-${run_id}.tcl"
remote_reset_tcl="/tmp/xsai-reset-cpu-${run_id}.tcl"
bit_file=""
ltx_file=""
remote_bit_file=""
remote_ltx_file="${LTX_OVERRIDE:-${remote_bit_dir}/pcie_part_gating_wrapper.ltx}"

cleanup() {
  run_remote "rm -f $(shell_quote "$remote_program_tcl") $(shell_quote "$remote_reset_tcl")" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if [[ "$PROGRAM_ONLY" -eq 0 ]]; then
  resolve_bit_home
  bit_file="$(pick_one_file '*.bit' bitstream)"
  ltx_file="$(pick_one_file '*.ltx' probes pcie_part_gating_wrapper.ltx)"
  remote_bit_file="${remote_bit_dir}/$(basename "$bit_file")"
  remote_ltx_file="${remote_bit_dir}/$(basename "$ltx_file")"

  echo "[fpga-program] local bitstream dir: ${BIT_HOME}"
  echo "[fpga-program] remote bitstream dir: ${HOST}:${remote_bit_dir}"
  run_remote "mkdir -p $(shell_quote "$remote_bit_dir")"
  run_remote "rm -f $(shell_quote "$remote_bit_dir")/*.bit $(shell_quote "$remote_bit_dir")/*.ltx"
  scp "$bit_file" "${HOST}:${remote_bit_file}"
  scp "$ltx_file" "${HOST}:${remote_ltx_file}"
  echo "[fpga-program] uploaded bit: ${remote_bit_file}"
  echo "[fpga-program] uploaded ltx: ${remote_ltx_file}"
fi

if [[ "$SYNC_ONLY" -eq 1 ]]; then
  echo "[fpga-program] sync-only complete"
  exit 0
fi

scp "$PROGRAM_TCL_LOCAL" "${HOST}:${remote_program_tcl}"
scp "$RESET_TCL_LOCAL" "${HOST}:${remote_reset_tcl}"

if [[ "$PROGRAM_PCIE_RESET" -eq 1 ]]; then
  if [[ -n "$PCIE_REMOVE_CMD" ]]; then
    echo "[fpga-program] running custom PCIe remove command"
    run_remote "$PCIE_REMOVE_CMD"
  else
    echo "[fpga-program] removing existing PCIe device"
    run_remote_script "$PCIE_REMOVE_LOCAL"
  fi
fi

echo "[fpga-program] programming FPGA via Vivado"
if [[ "$PROGRAM_ONLY" -eq 0 ]]; then
  run_remote "test -f $(shell_quote "$remote_bit_file") && test -f $(shell_quote "$remote_ltx_file")"
fi
run_remote_with_setup "vivado -mode batch -source $(shell_quote "$remote_program_tcl") -tclargs $(shell_quote "$remote_bit_dir")"

if [[ "$PROGRAM_PCIE_RESET" -eq 1 ]]; then
  if [[ -n "$PCIE_RESCAN_CMD" ]]; then
    echo "[fpga-program] running custom PCIe rescan command"
    run_remote "$PCIE_RESCAN_CMD"
  else
    echo "[fpga-program] rescanning PCIe"
    run_remote_script "$PCIE_RESCAN_LOCAL"
  fi
fi

if [[ "$PROGRAM_ASSERT_RESET" -eq 1 ]]; then
  echo "[fpga-program] asserting CPU reset via LTX: ${remote_ltx_file}"
  run_remote_with_setup "vivado -mode batch -source $(shell_quote "$remote_reset_tcl") -tclargs $(shell_quote "$remote_ltx_file") 1"
fi

echo "[fpga-program] complete"
echo "[fpga-program] use FPGA_LTX=${remote_ltx_file} for run-fpga/fpga-reset"

#!/usr/bin/env bash
#
# FPGA run helper for xsai-env.
# Inspired by OpenXiangShan/env-scripts and OpenXiangShan/minjie-playground FPGA flows.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

HOST="${FPGA_HOST:-fpga}"
REMOTE_PAYLOAD="${FPGA_REMOTE_PAYLOAD:-}"
LTX="${FPGA_LTX:-/home/fpga/xsai.ltx}"
DRIVER="${FPGA_DRIVER:-~/nexus-am/apps/dse-driver-ai/build/dse-driver-ai-riscv64-xs-driver.bin}"
XDMA_PROCESS="${FPGA_XDMA_PROCESS:-~/ai/xdma_process/build/xdma_process}"
TIMEOUT="${FPGA_TIMEOUT:-720}"
REMOTE_SUDO="${FPGA_REMOTE_SUDO-}"
UART_CMD="${FPGA_UART_CMD:-}"
KILL_UART_READERS="${FPGA_KILL_UART_READERS:-1}"
PASS_PATTERN="${FPGA_PASS_PATTERN-"[xsai-init] launching after_workload with status"}"
FAIL_PATTERN="${FPGA_FAIL_PATTERN:-}"
PCIE_REMOVE_CMD="${FPGA_PCIE_REMOVE_CMD:-}"
PCIE_RESCAN_CMD="${FPGA_PCIE_RESCAN_CMD:-}"
REMOTE_SETUP="${FPGA_REMOTE_SETUP:-source /tools/Xilinx/Vivado_Lab/2020.2/settings64.sh}"

RESET_ONLY=0
PAYLOAD=""

usage() {
  cat <<'EOF'
Usage:
  scripts/fpga-run-ai.sh --payload <local-payload>
  scripts/fpga-run-ai.sh --reset-only

Environment knobs:
  FPGA_HOST, FPGA_REMOTE_PAYLOAD, FPGA_LTX, FPGA_DRIVER, FPGA_XDMA_PROCESS
  FPGA_TIMEOUT, FPGA_UART_CMD, FPGA_KILL_UART_READERS, FPGA_PASS_PATTERN, FPGA_FAIL_PATTERN
  FPGA_PCIE_REMOVE_CMD, FPGA_PCIE_RESCAN_CMD, FPGA_REMOTE_SETUP, FPGA_REMOTE_SUDO
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --payload)
      PAYLOAD="${2:-}"
      shift 2
      ;;
    --reset-only)
      RESET_ONLY=1
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

run_remote_best_effort() {
  local cmd="$1"
  timeout 10s ssh "$HOST" "bash -lc $(printf '%q' "$cmd")"
}

run_remote_with_setup() {
  local cmd="$1"
  run_remote "${REMOTE_SETUP}; ${cmd}"
}

with_remote_sudo() {
  if [[ -n "$REMOTE_SUDO" ]]; then
    printf '%s %s' "$REMOTE_SUDO" "$*"
  else
    printf '%s' "$*"
  fi
}

require_cmd ssh
require_cmd scp
require_cmd timeout

if [[ "$RESET_ONLY" -eq 0 ]]; then
  [[ -n "$PAYLOAD" ]] || { echo "Missing --payload" >&2; exit 1; }
  [[ -f "$PAYLOAD" ]] || { echo "Payload not found: $PAYLOAD" >&2; exit 1; }
fi

RESET_TCL_LOCAL="$XS_PROJECT_ROOT/scripts/fpga/reset_cpu.tcl"
[[ -f "$RESET_TCL_LOCAL" ]] || { echo "Missing reset helper: $RESET_TCL_LOCAL" >&2; exit 1; }

run_id="$(date +%Y%m%d-%H%M%S)-$$"
if [[ -z "$REMOTE_PAYLOAD" ]]; then
  payload_ext="${PAYLOAD##*.}"
  if [[ "$payload_ext" == "$PAYLOAD" ]]; then
    payload_ext="bin"
  fi
  REMOTE_PAYLOAD="/tmp/xsai-payload-${run_id}.${payload_ext}"
fi
if [[ -z "$UART_CMD" ]]; then
  UART_CMD="$(with_remote_sudo '~/xdma_work/tools/proto/pcie-util' /dev/xdma0_user uart 0x10000)"
fi
remote_tcl="/tmp/xsai-reset-cpu-${run_id}.tcl"
local_uart_log="$XS_PROJECT_ROOT/log/fpga-uart-${run_id}.log"
local_vivado_reset_log="$XS_PROJECT_ROOT/log/fpga-vivado-reset-${run_id}.log"
uart_started=0
uart_stream_pid=""
reset_tcl_uploaded=0

stream_uart() {
  local fifo="${TMPDIR:-/tmp}/xsai-fpga-uart-${run_id}-$$.fifo"
  local ssh_pid=""
  local line
  local stream_rc=0
  local saw_terminal_pattern=0
  local ssh_rc=0

  cleanup_stream() {
    if [[ -n "$ssh_pid" ]]; then
      kill "$ssh_pid" >/dev/null 2>&1 || true
      wait "$ssh_pid" >/dev/null 2>&1 || true
      ssh_pid=""
    fi
    rm -f "$fifo"
  }

  rm -f "$fifo"
  mkfifo "$fifo" || return 1
  trap 'cleanup_stream; exit 143' TERM INT
  trap cleanup_stream EXIT

  ssh "$HOST" "bash -lc $(printf '%q' "$UART_CMD")" > "$fifo" &
  ssh_pid="$!"

  while IFS= read -r line; do
    line="${line%$'\r'}"
    printf '%s\n' "$line"
    printf '%s\n' "$line" >> "$local_uart_log"
    if [[ -n "$FAIL_PATTERN" && "$line" =~ $FAIL_PATTERN ]]; then
      stream_rc=42
      saw_terminal_pattern=1
      break
    fi
    if [[ -n "$PASS_PATTERN" && "$line" == *"$PASS_PATTERN"* ]]; then
      stream_rc=0
      saw_terminal_pattern=1
      break
    fi
  done < "$fifo"

  if [[ "$saw_terminal_pattern" -eq 1 ]]; then
    cleanup_stream
    trap - TERM INT EXIT
    return "$stream_rc"
  fi

  wait "$ssh_pid"
  ssh_rc=$?
  ssh_pid=""
  rm -f "$fifo"
  trap - TERM INT EXIT
  return "$ssh_rc"
}

cleanup() {
  if [[ -n "$uart_stream_pid" ]]; then
    kill "$uart_stream_pid" >/dev/null 2>&1 || true
    wait "$uart_stream_pid" >/dev/null 2>&1 || true
  fi
  if [[ "$uart_started" -eq 1 && "$KILL_UART_READERS" -eq 1 ]]; then
    run_remote_best_effort "pkill -f '[p]cie-util .*uart' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  fi
  run_remote_best_effort "rm -f ${remote_tcl}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

set_reset_vio() {
  local value="$1"
  local action="Setting"
  if [[ "$value" == "1" ]]; then
    action="Asserting"
  elif [[ "$value" == "0" ]]; then
    action="Releasing"
  fi
  if [[ "$reset_tcl_uploaded" -eq 0 ]]; then
    echo "[fpga] Uploading reset helper to ${HOST}:${remote_tcl}"
    scp "$RESET_TCL_LOCAL" "${HOST}:${remote_tcl}"
    reset_tcl_uploaded=1
  fi

  echo "[fpga] ${action} reset VIO (${value}) via Vivado with LTX: ${LTX}"
  if [[ "$value" == "0" && "$uart_started" -eq 1 ]]; then
    mkdir -p "$XS_PROJECT_ROOT/log"
    echo "[fpga] Vivado reset log: ${local_vivado_reset_log}"
    {
      run_remote "test -f ${LTX}"
      run_remote_with_setup "vivado -mode batch -source ${remote_tcl} -tclargs ${LTX} ${value}"
    } > "$local_vivado_reset_log" 2>&1 || {
      cat "$local_vivado_reset_log" >&2
      return 1
    }
  else
    run_remote "test -f ${LTX}"
    run_remote_with_setup "vivado -mode batch -source ${remote_tcl} -tclargs ${LTX} ${value}"
  fi
}

if [[ "$RESET_ONLY" -eq 0 ]]; then
  echo "[fpga] Uploading payload: ${PAYLOAD} -> ${HOST}:${REMOTE_PAYLOAD}"
  scp "$PAYLOAD" "${HOST}:${REMOTE_PAYLOAD}"
fi

set_reset_vio 1

if [[ -n "$PCIE_REMOVE_CMD" ]]; then
  echo "[fpga] Running optional PCIe remove hook"
  run_remote "$PCIE_REMOVE_CMD"
fi

if [[ -n "$PCIE_RESCAN_CMD" ]]; then
  echo "[fpga] Running optional PCIe rescan hook"
  run_remote "$PCIE_RESCAN_CMD"
fi

if [[ "$RESET_ONLY" -eq 1 ]]; then
  echo "[fpga] Reset-only flow complete"
  exit 0
fi

echo "[fpga] Running XDMA loader"
run_remote "$(with_remote_sudo "${XDMA_PROCESS}" -i "${REMOTE_PAYLOAD}" -d "${DRIVER}")"

if [[ -n "$UART_CMD" ]]; then
  require_cmd mkfifo
  mkdir -p "$XS_PROJECT_ROOT/log"
  if [[ "$KILL_UART_READERS" -eq 1 ]]; then
    echo "[fpga] Killing stale UART readers on ${HOST}"
    run_remote_best_effort "pkill -f '[p]cie-util .*uart' >/dev/null 2>&1 || true" >/dev/null 2>&1 || true
  fi
  echo "[fpga] Starting UART stream from ${HOST}"
  : > "$local_uart_log"
  set +e
  stream_uart &
  uart_stream_pid="$!"
  set -e
  uart_started=1
  echo "[fpga] Streaming UART output (timeout=${TIMEOUT}s pass=${PASS_PATTERN:-disabled})"
fi

set_reset_vio 0

if [[ "$uart_started" -eq 1 ]]; then
  set +e
  uart_rc=0
  deadline=$((SECONDS + TIMEOUT))
  while kill -0 "$uart_stream_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      kill "$uart_stream_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -0 "$uart_stream_pid" >/dev/null 2>&1 && kill -9 "$uart_stream_pid" >/dev/null 2>&1 || true
      wait "$uart_stream_pid" >/dev/null 2>&1 || true
      uart_rc=124
      break
    fi
    sleep 1
  done
  if [[ "${uart_rc:-}" != 124 ]]; then
    wait "$uart_stream_pid"
    uart_rc=$?
  fi
  uart_stream_pid=""
  set -e
  if [[ "$uart_rc" -eq 124 ]]; then
    echo "[fpga] UART observation window expired after ${TIMEOUT}s; workload may still be running" >&2
    exit 124
  elif [[ "$uart_rc" -eq 42 ]]; then
    echo "[fpga] FAIL pattern matched: ${FAIL_PATTERN}" >&2
    exit 1
  elif [[ "$uart_rc" -ne 0 ]]; then
    if [[ -n "$PASS_PATTERN" ]] && grep -Fq "$PASS_PATTERN" "$local_uart_log"; then
      echo "[fpga] UART stream exited with ${uart_rc} after PASS pattern; treating as complete"
    else
      echo "[fpga] UART stream failed with exit code ${uart_rc}" >&2
      exit "$uart_rc"
    fi
  fi
  if [[ -n "$PASS_PATTERN" ]] && ! grep -Fq "$PASS_PATTERN" "$local_uart_log"; then
    echo "[fpga] PASS pattern not found: ${PASS_PATTERN}" >&2
    exit 1
  fi
  echo "[fpga] UART log saved to ${local_uart_log}"
fi

echo "[fpga] Run completed"

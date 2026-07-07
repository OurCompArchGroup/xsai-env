#!/usr/bin/env bash
set -euo pipefail

sudo_cmd="${FPGA_PCIE_SUDO:-${FPGA_REMOTE_SUDO:-}}"
required_devices="${FPGA_XDMA_REQUIRED_DEVICES:-/dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_bypass}"
reload_on_missing="${FPGA_XDMA_RELOAD_ON_MISSING:-1}"
xdma_module="${FPGA_XDMA_MODULE:-xdma}"
wait_secs="${FPGA_XDMA_WAIT_SECS:-10}"

run_privileged() {
  if [[ -n "$sudo_cmd" ]]; then
    # Intentional word splitting allows values such as "sudo -n".
    $sudo_cmd "$@"
  else
    "$@"
  fi
}

rescan_pcie() {
  printf '1\n' | run_privileged tee /sys/bus/pci/rescan >/dev/null
  command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=5 >/dev/null 2>&1 || true
}

print_xdma_status() {
  echo "[fpga-pcie] Xilinx PCI devices:"
  lspci -Dnn | awk 'BEGIN{IGNORECASE=1} /xilinx|\[10ee:/ {print "  " $0}' || true
  echo "[fpga-pcie] XDMA device nodes:"
  shopt -s nullglob
  local devs=(/dev/xdma*)
  shopt -u nullglob
  if [[ "${#devs[@]}" -eq 0 ]]; then
    echo "  <none>"
  else
    ls -l "${devs[@]}" | sed 's/^/  /'
  fi
  echo "[fpga-pcie] XDMA modules:"
  lsmod | awk -v m="$xdma_module" '$1 == m || $1 ~ /^xdma/ {print "  " $0}' || true
}

missing_required_devices() {
  local -a required=()
  local dev
  read -r -a required <<< "$required_devices"
  for dev in "${required[@]}"; do
    [[ -e "$dev" ]] || printf '%s\n' "$dev"
  done
}

wait_for_required_devices() {
  local label="$1"
  local deadline=$((SECONDS + wait_secs))
  local missing=""

  while true; do
    missing="$(missing_required_devices)"
    if [[ -z "$missing" ]]; then
      echo "[fpga-pcie] required XDMA devices are ready (${label})"
      return 0
    fi
    (( SECONDS >= deadline )) && break
    sleep 1
  done

  echo "[fpga-pcie] missing required XDMA devices after ${label}:"
  sed 's/^/  /' <<< "$missing"
  return 1
}

find_xilinx_bdfs() {
  lspci -Dnn | awk 'BEGIN{IGNORECASE=1} /xilinx|\[10ee:/ {print $1}'
}

remove_xilinx_devices() {
  local bdf device driver
  while IFS= read -r bdf; do
    [[ -n "$bdf" ]] || continue
    device="/sys/bus/pci/devices/${bdf}"
    [[ -e "$device" ]] || continue
    if [[ -e "${device}/driver" ]]; then
      driver="$(basename "$(readlink "${device}/driver")")"
      echo "[fpga-pcie] unbinding ${bdf} from ${driver}"
      printf '%s\n' "$bdf" | run_privileged tee "/sys/bus/pci/drivers/${driver}/unbind" >/dev/null || true
      sleep 1
    fi
    echo "[fpga-pcie] removing ${bdf}"
    printf '1\n' | run_privileged tee "${device}/remove" >/dev/null || true
  done < <(find_xilinx_bdfs)
}

reload_xdma_module() {
  echo "[fpga-pcie] reloading ${xdma_module} because required XDMA nodes are missing"
  remove_xilinx_devices
  if lsmod | awk -v m="$xdma_module" '$1 == m {found=1} END{exit !found}'; then
    run_privileged modprobe -r "$xdma_module"
  fi
  run_privileged modprobe "$xdma_module"
}

echo "[fpga-pcie] rescanning PCIe"
rescan_pcie

if wait_for_required_devices "initial rescan"; then
  exit 0
fi

print_xdma_status

if [[ "$reload_on_missing" != "1" ]]; then
  echo "[fpga-pcie] XDMA reload is disabled (FPGA_XDMA_RELOAD_ON_MISSING=${reload_on_missing})" >&2
  exit 1
fi

reload_xdma_module

echo "[fpga-pcie] rescanning PCIe after ${xdma_module} reload"
rescan_pcie

if wait_for_required_devices "xdma reload and rescan"; then
  print_xdma_status
  exit 0
fi

print_xdma_status
exit 1

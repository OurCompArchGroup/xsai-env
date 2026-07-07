#!/usr/bin/env bash
set -euo pipefail

sudo_cmd="${FPGA_PCIE_SUDO:-${FPGA_REMOTE_SUDO:-}}"

run_privileged() {
  if [[ -n "$sudo_cmd" ]]; then
    # Intentional word splitting allows values such as "sudo -n".
    $sudo_cmd "$@"
  else
    "$@"
  fi
}

bdf="$(lspci -D | awk 'BEGIN{IGNORECASE=1} /xilinx/ {print $1; exit}')"
if [[ -z "$bdf" ]]; then
  echo "[fpga-pcie] no Xilinx PCI device found; skip remove"
  exit 0
fi

device="/sys/bus/pci/devices/${bdf}"
if [[ ! -e "$device" ]]; then
  echo "[fpga-pcie] PCI sysfs device not found: $device"
  exit 0
fi

if [[ -e "${device}/driver" ]]; then
  driver="$(basename "$(readlink "${device}/driver")")"
  echo "[fpga-pcie] unbinding ${bdf} from ${driver}"
  printf '%s\n' "$bdf" | run_privileged tee "/sys/bus/pci/drivers/${driver}/unbind" >/dev/null
  sleep 1
fi

echo "[fpga-pcie] removing ${bdf}"
printf '1\n' | run_privileged tee "${device}/remove" >/dev/null

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pack="${FPGA_SYNTH_PACK:-${repo_root}/tools/fpga/vivado-build-pack}"
rtl_dir="${FPGA_SYNTH_RTL_DIR:-${repo_root}/XSAI/build/rtl}"
out_root="${FPGA_SYNTH_OUT_ROOT:-${repo_root}/local/fpga-vivado}"
out_dir="${FPGA_SYNTH_OUT:-}"
project="${FPGA_SYNTH_PROJECT:-xsai_fpga}"
jobs="${FPGA_SYNTH_JOBS:-8}"
run_to="${FPGA_SYNTH_RUN_TO:-synth}"
host="${FPGA_SYNTH_HOST:-}"
setup="${FPGA_SYNTH_SETUP:-${FPGA_SYNTH_REMOTE_SETUP:-}}"

if [[ -z "${out_dir}" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  out_dir="${out_root}/${project}-${run_to}-${ts}"
fi

build_script="${pack}/build_vivado_project.sh"

if [[ ! -x "${build_script}" ]]; then
  echo "error: Vivado build pack entry is not executable: ${build_script}" >&2
  exit 1
fi

if [[ ! -d "${rtl_dir}" ]]; then
  echo "error: RTL directory does not exist: ${rtl_dir}" >&2
  echo "hint: run 'make fpga-rtl' first, or set FPGA_SYNTH_RTL_DIR" >&2
  exit 1
fi

if ! find "${rtl_dir}" -type f \( -name '*.v' -o -name '*.sv' -o -name '*.vh' -o -name '*.svh' \) -print -quit | grep -q .; then
  echo "error: RTL directory has no Verilog/SystemVerilog files: ${rtl_dir}" >&2
  exit 1
fi

case "${run_to}" in
  project|synth|impl|bitstream) ;;
  *)
    echo "error: FPGA_SYNTH_RUN_TO must be one of: project, synth, impl, bitstream" >&2
    exit 1
    ;;
esac

mkdir -p "${out_dir}"

{
  echo "created_at=$(date -R)"
  echo "repo_root=${repo_root}"
  echo "repo_head=$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || true)"
  echo "xsai_head=$(git -C "${repo_root}/XSAI" rev-parse HEAD 2>/dev/null || true)"
  echo "rtl_dir=${rtl_dir}"
  echo "out_dir=${out_dir}"
  echo "project=${project}"
  echo "jobs=${jobs}"
  echo "run_to=${run_to}"
  echo "host=${host:-local}"
  echo "pack=${pack}"
} > "${out_dir}/xsai-env-build-info.txt"

cmd=(
  "${build_script}"
  --rtl "${rtl_dir}"
  --out "${out_dir}"
  --name "${project}"
  --jobs "${jobs}"
  --run-to "${run_to}"
)

echo "[fpga-synth] output: ${out_dir}"
echo "[fpga-synth] run-to: ${run_to}"

if [[ -z "${host}" ]]; then
  if [[ -n "${setup}" ]]; then
    # shellcheck disable=SC1090
    source <(printf '%s\n' "${setup}")
  fi
  exec "${cmd[@]}"
fi

printf -v remote_cmd '%q ' "${cmd[@]}"
if [[ -n "${setup}" ]]; then
  remote_cmd="${setup}; ${remote_cmd}"
fi

ssh "${host}" "bash -lc $(printf '%q' "${remote_cmd}")"

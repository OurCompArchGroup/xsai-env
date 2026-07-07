#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/build_vivado_project.sh --rtl <rtl_dir> --out <output_dir> [options]

Options:
  --template <dir>           Golden Vivado template project root. Default: auto-detect kmh_mini_ai_raw_bigddr8g_0522.
  --name <project_name>      Vivado project name. Default: cpu_fpga_build
  --jobs <N>                 Vivado run job count. Default: 8
  --run-to <stage>           project, synth, impl, or bitstream. Default: synth
  --skip-vivado-check        Skip the `vivado -version` environment precheck.
  -h, --help                 Show this help.

The default stops after synth_1 because this project is large. Use
`--run-to impl` or `--run-to bitstream` only when a long implementation run is intended.
If <output_dir>/<project_name>/<project_name>.xpr already exists, the Tcl flow opens
that project and resumes the requested stage instead of recreating the project.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TCL_SCRIPT="${SCRIPT_DIR}/create_and_run_project.tcl"
DEFAULT_TEMPLATE_NAME="kmh_mini_ai_raw_bigddr8g_0522"

RTL_DIR=""
OUT_DIR=""
TEMPLATE_ROOT=""
PROJECT_NAME="cpu_fpga_build"
JOBS="8"
RUN_TO="synth"
SKIP_VIVADO_CHECK="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rtl)
      [[ $# -ge 2 ]] || die "--rtl requires a value"
      RTL_DIR="$2"
      shift 2
      ;;
    --out)
      [[ $# -ge 2 ]] || die "--out requires a value"
      OUT_DIR="$2"
      shift 2
      ;;
    --template)
      [[ $# -ge 2 ]] || die "--template requires a value"
      TEMPLATE_ROOT="$2"
      shift 2
      ;;
    --name)
      [[ $# -ge 2 ]] || die "--name requires a value"
      PROJECT_NAME="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || die "--jobs requires a value"
      JOBS="$2"
      shift 2
      ;;
    --run-to)
      [[ $# -ge 2 ]] || die "--run-to requires a value"
      RUN_TO="$2"
      shift 2
      ;;
    --skip-vivado-check)
      SKIP_VIVADO_CHECK="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "${RTL_DIR}" ]] || die "--rtl is required"
[[ -n "${OUT_DIR}" ]] || die "--out is required"
[[ -d "${RTL_DIR}" ]] || die "RTL directory does not exist: ${RTL_DIR}"
[[ -f "${TCL_SCRIPT}" ]] || die "Tcl script not found: ${TCL_SCRIPT}"

if [[ -z "${TEMPLATE_ROOT}" ]]; then
  if [[ -d "${SCRIPT_DIR}/../${DEFAULT_TEMPLATE_NAME}.srcs" ]]; then
    TEMPLATE_ROOT="${SCRIPT_DIR}/.."
  elif [[ -d "${SCRIPT_DIR}/../${DEFAULT_TEMPLATE_NAME}/${DEFAULT_TEMPLATE_NAME}.srcs" ]]; then
    TEMPLATE_ROOT="${SCRIPT_DIR}/../${DEFAULT_TEMPLATE_NAME}"
  else
    die "could not auto-detect template root; pass --template <dir>"
  fi
fi

[[ -d "${TEMPLATE_ROOT}" ]] || die "template root does not exist: ${TEMPLATE_ROOT}"

case "${RUN_TO}" in
  project|synth|impl|bitstream) ;;
  *) die "--run-to must be one of: project, synth, impl, bitstream" ;;
esac

if ! [[ "${JOBS}" =~ ^[0-9]+$ ]] || [[ "${JOBS}" -lt 1 ]]; then
  die "--jobs must be a positive integer"
fi

RTL_DIR="$(cd "${RTL_DIR}" && pwd)"
TEMPLATE_ROOT="$(cd "${TEMPLATE_ROOT}" && pwd)"
mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

VIVADO_COMPAT_DIR="${TEMPLATE_ROOT}/.vivado_compat"
if [[ -d "${VIVADO_COMPAT_DIR}" ]]; then
  export LD_LIBRARY_PATH="${VIVADO_COMPAT_DIR}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

if [[ "${SKIP_VIVADO_CHECK}" != "1" ]]; then
  VIVADO_CHECK_LOG="${OUT_DIR}/vivado_version_check.log"
  if ! vivado -version >"${VIVADO_CHECK_LOG}" 2>&1; then
    cat >&2 <<EOF
ERROR: Vivado precheck failed. See:
  ${VIVADO_CHECK_LOG}

If the log contains:
  libtinfo.so.5: cannot open shared object file
install/provide libtinfo.so.5 or source the correct Vivado/runtime environment, then rerun.
Use --skip-vivado-check only if Vivado is known to work in your launch environment.
EOF
    exit 1
  fi
fi

VIVADO_BATCH_LOG="${OUT_DIR}/vivado_batch.log"
VIVADO_BATCH_JOU="${OUT_DIR}/vivado_batch.jou"

exec vivado -mode batch \
  -log "${VIVADO_BATCH_LOG}" \
  -journal "${VIVADO_BATCH_JOU}" \
  -source "${TCL_SCRIPT}" -tclargs \
  --template "${TEMPLATE_ROOT}" \
  --rtl "${RTL_DIR}" \
  --out "${OUT_DIR}" \
  --name "${PROJECT_NAME}" \
  --jobs "${JOBS}" \
  --run-to "${RUN_TO}"

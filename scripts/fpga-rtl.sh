#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
xsai_home="${NOOP_HOME:-${repo_root}/XSAI}"
patch_dir="${repo_root}/scripts/fpga/patches"
xsai_patch="${patch_dir}/xsai-fpga-rtl.patch"
utility_patch="${patch_dir}/utility-bypass-clockgate.patch"

rtl_config="${FPGA_RTL_CONFIG:-FpgaMinimalMatrixConfig}"
rtl_num_cores="${FPGA_RTL_NUM_CORES:-1}"
rtl_jobs="${FPGA_RTL_JOBS:--j}"
make_bin="${FPGA_RTL_MAKE:-make}"
tar_prefix="${FPGA_RTL_TAR_PREFIX:-xsai-fpga-rtl}"
compress="${FPGA_RTL_COMPRESS:-1}"
out_root="${FPGA_RTL_OUT_ROOT:-${repo_root}/local/fpga-rtl}"
build_dir="${FPGA_RTL_BUILD_DIR:-${out_root}/build}"
clean_build="${FPGA_RTL_CLEAN:-1}"
rtl_dir="${build_dir}/rtl"
archive_root="${FPGA_RTL_ARCHIVE_ROOT:-${out_root}}"
package_work="${out_root}/.package"

xsai_applied=0
utility_applied=0

cleanup() {
  local status=$?

  if [[ "$utility_applied" == "1" ]]; then
    if ! git -C "${xsai_home}/utility" apply -R "${utility_patch}"; then
      echo "warning: failed to revert ${utility_patch}" >&2
      status=1
    fi
  fi

  if [[ "$xsai_applied" == "1" ]]; then
    if ! git -C "${xsai_home}" apply -R "${xsai_patch}"; then
      echo "warning: failed to revert ${xsai_patch}" >&2
      status=1
    fi
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM

git -C "${xsai_home}" apply --check "${xsai_patch}"
git -C "${xsai_home}/utility" apply --check "${utility_patch}"

git -C "${xsai_home}" apply "${xsai_patch}"
xsai_applied=1

git -C "${xsai_home}/utility" apply "${utility_patch}"
utility_applied=1

if [[ "${clean_build}" == "1" ]]; then
  rm -rf "${build_dir}"
fi
mkdir -p "${build_dir}"

make_args=(
  verilog
  "BUILD_DIR=${build_dir}"
  "CONFIG=${rtl_config}"
  FPGA=1
  MFC=1
  RELEASE=1
  WITH_CHISELDB=0
  WITH_CONSTANTIN=0
  "NUM_CORES=${rtl_num_cores}"
)

if [[ -n "$rtl_jobs" ]]; then
  make_args+=("$rtl_jobs")
fi

"${make_bin}" -C "${xsai_home}" "${make_args[@]}" "$@"

mkdir -p "${archive_root}"
rm -rf "${package_work}"
mkdir -p "${package_work}/build" "${package_work}/patches"

if [[ ! -d "${rtl_dir}" ]]; then
  echo "error: RTL output directory not found: ${rtl_dir}" >&2
  exit 1
fi

cp -a "${rtl_dir}" "${package_work}/build/rtl"
cp -a "${xsai_patch}" "${utility_patch}" "${package_work}/patches/"

ts="$(date +%Y%m%d-%H%M%S)"
archive_ext=".tar.gz"
tar_opts="-czf"
if [[ "${compress}" == "0" ]]; then
  archive_ext=".tar"
  tar_opts="-cf"
fi
archive="${archive_root}/${tar_prefix}-${ts}${archive_ext}"

{
  echo "created_at=$(date -R)"
  echo "repo_root=${repo_root}"
  echo "xsai_home=${xsai_home}"
  echo "xsai_head=$(git -C "${xsai_home}" rev-parse HEAD)"
  echo "utility_head=$(git -C "${xsai_home}/utility" rev-parse HEAD)"
  echo "build_dir=${build_dir}"
  echo "rtl_dir=${rtl_dir}"
  echo "archive=${archive}"
  echo "config=${rtl_config}"
  echo "num_cores=${rtl_num_cores}"
  echo "make_args=${make_args[*]} $*"
  echo "patches=patches/$(basename "${xsai_patch}") patches/$(basename "${utility_patch}")"
} > "${package_work}/MANIFEST.txt"
cp -a "${package_work}/MANIFEST.txt" "${out_root}/MANIFEST.txt"

tar ${tar_opts} "${archive}" -C "${package_work}" .
rm -rf "${package_work}"

echo "FPGA RTL directory ready: ${rtl_dir}"
echo "FPGA RTL package ready: ${archive}"

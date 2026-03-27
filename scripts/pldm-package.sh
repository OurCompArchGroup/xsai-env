#!/usr/bin/env bash
set -euo pipefail

xs_project_root="${XS_PROJECT_ROOT:?XS_PROJECT_ROOT is required}"
work_dir="${NOOP_HOME:?NOOP_HOME is required}"
pldm_tar_prefix="${PLDM_TAR_PREFIX:-XSAI-pldm}"
pldm_build_target="${PLDM_BUILD_TARGET:-verilog}"
pldm_build_flags="${PLDM_BUILD_FLAGS:-WITH_CHISELDB=0 WITH_CONSTANTIN=0 MFC=1 PLDM=1 -j8}"
pldm_build_backup_prefix="${PLDM_BUILD_BACKUP_PREFIX:-${work_dir}/.pldm-build-backup}"
pldm_nemu_so="${PLDM_NEMU_SO:-${xs_project_root}/local/riscv64-nemu-interpreter-so}"
pldm_skip_build="${PLDM_SKIP_BUILD:-0}"
pldm_compress="${PLDM_COMPRESS:-1}"

backup_dir="${pldm_build_backup_prefix}-$(date +%Y%m%d-%H%M%S)-$$"
had_build=0
remove_generated_build=0

cleanup() {
  local status=$?
  if [[ "$had_build" == "1" && -e "$backup_dir" ]]; then
    rm -rf "$work_dir/build"
    mv "$backup_dir" "$work_dir/build"
  elif [[ "$remove_generated_build" == "1" ]]; then
    rm -rf "$work_dir/build"
  fi
  exit "$status"
}
trap cleanup EXIT

mkdir -p "${xs_project_root}/local"

read -r -a build_flag_array <<< "$pldm_build_flags"

if [[ "$pldm_skip_build" == "1" ]]; then
  echo "Skipping build; packaging current XSAI tree including existing build/..."
else
  if [[ -d "$work_dir/build" ]]; then
    echo "Moving $work_dir/build -> $backup_dir..."
    mv "$work_dir/build" "$backup_dir"
    had_build=1
  else
    remove_generated_build=1
  fi
  echo "Building ${pldm_build_target} in $work_dir..."
  make -C "$work_dir" "$pldm_build_target" "${build_flag_array[@]}"
fi

if [[ -f "$pldm_nemu_so" ]]; then
  echo "Updating ready-to-run/riscv64-nemu-interpreter-so from $pldm_nemu_so..."
  cp -f "$pldm_nemu_so" "$work_dir/ready-to-run/riscv64-nemu-interpreter-so"
else
  echo "warning: $pldm_nemu_so not found; keeping existing ready-to-run/riscv64-nemu-interpreter-so"
fi

ts="$(date +%Y%m%d-%H%M%S)"
archive_ext='.tar.gz'
if [[ "$pldm_compress" == "0" ]]; then
  archive_ext='.tar'
fi
archive="${xs_project_root}/local/${pldm_tar_prefix}-${ts}${archive_ext}"

echo "Packaging $archive..."
python3 - "$xs_project_root" "$archive" "$pldm_compress" <<'PYTHON'
import os
import sys
import tarfile
from pathlib import Path

root = Path(sys.argv[1])
archive = Path(sys.argv[2])
compress = sys.argv[3] != "0"
source = root / "XSAI"

skip_dir_names = {"out", ".bloop", ".metals", ".idea", ".vscode"}
skip_prefixes = ("build-", ".pldm-build-backup-")

def is_hidden(parts):
    return any(part.startswith('.') for part in parts)

def should_skip_dir(parts):
    if not parts:
        return False
    name = parts[-1]
    if name in skip_dir_names:
        return True
    if name.startswith(skip_prefixes):
        return True
    if is_hidden(parts):
        return True
    return False

def should_skip_file(parts):
    if not parts:
        return False
    name = parts[-1]
    if is_hidden(parts):
        return True
    if name.startswith(skip_prefixes):
        return True
    if "out" in parts:
        return True
    if any(part in skip_dir_names for part in parts[:-1]):
        return True
    return False

mode = "w:gz" if compress else "w"
with tarfile.open(archive, mode) as tf:
    tf.add(source, arcname="XSAI", recursive=False)
    for current_root, dirnames, filenames in os.walk(source):
        current = Path(current_root)
        rel_dir = current.relative_to(source)
        rel_parts = rel_dir.parts
        kept_dirs = []
        for dirname in dirnames:
            cand_parts = rel_parts + (dirname,)
            if should_skip_dir(cand_parts):
                continue
            kept_dirs.append(dirname)
            tf.add(current / dirname, arcname=str(Path("XSAI") / Path(*cand_parts)), recursive=False)
        dirnames[:] = kept_dirs
        for filename in filenames:
            cand_parts = rel_parts + (filename,)
            if should_skip_file(cand_parts):
                continue
            tf.add(current / filename, arcname=str(Path("XSAI") / Path(*cand_parts)), recursive=False)
PYTHON

echo "✓ PLDM package ready: $archive"

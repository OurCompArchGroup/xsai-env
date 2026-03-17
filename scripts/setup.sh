#!/bin/bash

set -euo pipefail

# This script will setup XiangShan develop environment automatically

# Init submodules
# Setup XiangShan environment variables

GIT_FORCE_INIT="${GIT_FORCE_INIT:-0}"
FORCE_ARGS=()
if [[ "$GIT_FORCE_INIT" == "1" ]]; then
    FORCE_ARGS=(--force)
fi

dev(){
    git submodule update --init "${FORCE_ARGS[@]}" DRAMsim3 NEMU NutShell nexus-am riscv-matrix-spec qemu
    git submodule update --init "${FORCE_ARGS[@]}" --depth 1 llvm-project-ame
    # cd nexus-am && git lfs pull; cd -; # LFS files are too large, we don't use them in the init flow
    git submodule update --init "${FORCE_ARGS[@]}" XSAI && make -C XSAI init-force;
    cd firmware && make init GIT_FORCE_INIT="$GIT_FORCE_INIT"; cd -;
}
user(){
    git submodule update --init "${FORCE_ARGS[@]}" qemu
    cd firmware && make init GIT_FORCE_INIT="$GIT_FORCE_INIT"; cd -;
}
# Install gsim to local/bin
$XS_PROJECT_ROOT/scripts/install-gsim.sh

dev
source $(dirname "$0")/../env.sh
# OPTIONAL: export them to .bashrc
echo XS_PROJECT_ROOT: ${XS_PROJECT_ROOT}
echo NEMU_HOME: ${NEMU_HOME}
echo AM_HOME: ${AM_HOME}
echo NOOP_HOME: ${NOOP_HOME}

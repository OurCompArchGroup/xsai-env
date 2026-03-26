#!/usr/bin/env bash

set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "Please run this script as root, e.g. 'sudo make deps'." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  bear \
  bison \
  ca-certificates \
  clang \
  cmake \
  curl \
  default-jre \
  direnv \
  device-tree-compiler \
  flex \
  g++ \
  g++-riscv64-linux-gnu \
  git \
  git-lfs \
  libcap-ng-dev \
  libglib2.0-dev \
  libpixman-1-dev \
  libreadline-dev \
  libsdl2-dev \
  libslirp-dev \
  libsqlite3-dev \
  libzstd-dev \
  llvm \
  make \
  ninja-build \
  proxychains4 \
  python-is-python3 \
  python3-grpc-tools \
  python3-protobuf \
  python3-venv \
  sqlite3 \
  time \
  tmux \
  vim \
  wget \
  zlib1g-dev \
  zstd

curl -fsSL https://repo1.maven.org/maven2/com/lihaoyi/mill-dist/1.0.4/mill-dist-1.0.4-mill.sh -o /usr/local/bin/mill
chmod +x /usr/local/bin/mill

INSTALL_VERILATOR=true
if command -v verilator >/dev/null 2>&1; then
  CURRENT_VER=$(verilator --version | head -n1 | awk '{print $2}')
  REQUIRED_VER="4.204"
  if [[ "$(printf '%s\n' "$REQUIRED_VER" "$CURRENT_VER" | sort -V | head -n1)" == "$REQUIRED_VER" ]]; then
    echo "Verilator $CURRENT_VER is already installed."
    INSTALL_VERILATOR=false
  fi
fi

if [[ "$INSTALL_VERILATOR" == true ]]; then
  source "$(dirname "$0")/install-verilator.sh"
fi

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XSAI_ENV_QUIET=1
source "$ROOT/env.sh"

OUT_DIR="${ROOT}/local/release"
RELEASE_DATE="$(date -u +%Y%m%d)"
RELEASE_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NAME="release_${RELEASE_DATE}_$(git -C "${ROOT}" rev-parse --short=8 HEAD 2>/dev/null || echo unknown)"
STAGE=""
DRY_RUN=false
STRICT=false
KEEP_STAGE=false
RTL_RELEASE_PACKAGE_DIR="Release-XSAI-${RELEASE_DATE}"
XSAI_CONFIG="DefaultMatrixConfig"
XSAI_NUM_CORES="1"
XSAI_ISSUE="E.b"
XSAI_RTL_TOP="XSTop"
XSAI_RTL_FILELIST="XSAI.f"
XSAI_RTL_BUILD_DIR="$ROOT/XSAI/build/release-${XSAI_CONFIG}"
XSAI_RTL_DIR="$XSAI_RTL_BUILD_DIR/rtl"
TOOLCHAIN_PACKAGE_DIR="toolchain"
LLVM_INSTALL_DIR="${LLVM_HOME:-$ROOT/local/llvm}"
RISCV_SYSROOT_DIR="${RISCV_SYSROOT:-}"
RISCV_GCC="$(command -v riscv64-linux-gnu-gcc || true)"
GCC_RUNTIME_DIR=""
if [[ -n "$RISCV_GCC" ]]; then
  GCC_RUNTIME_DIR="$(dirname "$("$RISCV_GCC" -print-libgcc-file-name)")"
fi
LLVM_TOOLS=(
  clang clang++ ld.lld
  llc opt
  llvm-ar llvm-ranlib llvm-nm
  llvm-mc llvm-objcopy llvm-strip
  llvm-objdump llvm-readelf llvm-readobj
  llvm-size llvm-strings llvm-symbolizer llvm-addr2line
)

CASES_DIR=""
GENERATED_SRC_DIR=""
SIM_DIR=""
SRAM_TB_DIR=""
SRAM_TB_MK=""
OPENOCD_DIR=""

usage() {
  cat <<'EOF'
Usage: scripts/export-release.sh [options]

Create an XSAI customer release archive:
  <name>/Makefile
  <name>/Release-XSAI-YYYYMMDD/
    RELEASE-METADATA
    XSAI.f
    rtl/XSTop.sv
  <name>/NEMU/
  <name>/nexus-am/
  <name>/env/difftest/
  <name>/env/generated-src/
  <name>/env/sim/
  <name>/env/sram_tb/
  <name>/cases/
  <name>/riscv-openocd/
  <name>/toolchain/
    bin/xsai-clang
    llvm/bin/clang
    riscv64-linux-gnu/

Options:
  --name <name>              Release directory/archive basename.
  --output-dir <dir>         Directory for the tar.gz archive. Default: local/release.
  --stage-dir <dir>          Existing/created staging parent. Default: mktemp under output dir.
  --cases-dir <dir>          Source test binary directory. Default: cases, then XSAI/ready-to-run.
  --generated-src-dir <dir>  Source generated difftest headers/C++ directory.
  --sim-dir <dir>            Source generated simulation Verilog directory.
  --sram-tb-dir <dir>        Source SRAM testbench helper directory.
  --sram-tb-mk <file>        Source top-level sram_tb.mk.
  --openocd-dir <dir>        Source riscv-openocd directory.
  --strict                   Fail if optional release inputs are missing.
  --dry-run                  Print the resolved manifest without copying or archiving.
  --keep-stage               Keep staging directory after archive creation.
  -h, --help                 Show this help.

The script always builds synthesis RTL from the current XSAI checkout with
CONFIG=DefaultMatrixConfig and NUM_CORES=1. It also packages the repository's
custom LLVM plus a RISC-V Linux sysroot. Neither required input can be replaced
with an external release directory.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

warn() {
  echo "warning: $*" >&2
}

abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT" "$path"
  fi
}

arg_value() {
  local flag="$1"
  local value="${2:-}"
  [[ -n "$value" ]] || die "$flag requires a value"
  printf '%s\n' "$value"
}

first_existing_dir() {
  local path
  for path in "$@"; do
    [[ -n "$path" && -d "$path" ]] && printf '%s\n' "$path" && return 0
  done
  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        NAME="$(arg_value "$1" "${2:-}")"
        shift 2
        ;;
      --output-dir)
        OUT_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --stage-dir)
        STAGE="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --cases-dir)
        CASES_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --generated-src-dir)
        GENERATED_SRC_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --sim-dir)
        SIM_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --sram-tb-dir)
        SRAM_TB_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --sram-tb-mk)
        SRAM_TB_MK="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --openocd-dir)
        OPENOCD_DIR="$(abs_path "$(arg_value "$1" "${2:-}")")"
        shift 2
        ;;
      --strict)
        STRICT=true
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --keep-stage)
        KEEP_STAGE=true
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
}

resolve_inputs() {
  [[ -n "$CASES_DIR" ]] || CASES_DIR="$(first_existing_dir "$ROOT/cases" "$ROOT/XSAI/ready-to-run" || true)"
  [[ -n "$GENERATED_SRC_DIR" ]] || GENERATED_SRC_DIR="$(first_existing_dir "$ROOT/env/generated-src" "$ROOT/XSAI/generated-src" "$ROOT/XSAI/build/generated-src" || true)"
  [[ -n "$SIM_DIR" ]] || SIM_DIR="$(first_existing_dir "$ROOT/env/sim" "$ROOT/XSAI/sim" "$ROOT/XSAI/build/sim" || true)"
  [[ -n "$SRAM_TB_DIR" ]] || SRAM_TB_DIR="$(first_existing_dir "$ROOT/env/sram_tb" "$ROOT/XSAI/env/sram_tb" "$ROOT/XSAI/sram_tb" || true)"
  [[ -n "$SRAM_TB_MK" ]] || [[ ! -f "$ROOT/sram_tb.mk" ]] || SRAM_TB_MK="$ROOT/sram_tb.mk"
  [[ -n "$OPENOCD_DIR" ]] || OPENOCD_DIR="$(first_existing_dir "$ROOT/riscv-openocd" "$ROOT/tools/riscv-openocd" "$ROOT/local/riscv-openocd" || true)"
}

require_dir() {
  local path="$1"
  local label="$2"
  [[ -d "$path" ]] || die "$label is required but not found: $path"
}

require_file() {
  local path="$1"
  local label="$2"
  [[ -f "$path" ]] || die "$label is required but not found: $path"
}

handle_optional_dir() {
  local path="$1"
  local label="$2"
  local hint="$3"
  if [[ -d "$path" ]]; then
    return 0
  fi
  if [[ "$STRICT" == true ]]; then
    die "$label not found. $hint"
  fi
  warn "$label not found; skipping. $hint"
  return 1
}

handle_optional_file() {
  local path="$1"
  local label="$2"
  local hint="$3"
  if [[ -f "$path" ]]; then
    return 0
  fi
  if [[ "$STRICT" == true ]]; then
    die "$label not found. $hint"
  fi
  warn "$label not found; skipping. $hint"
  return 1
}

print_manifest() {
  cat <<EOF
Release name: $NAME
Output dir:   $OUT_DIR

Required inputs:
  XSAI RTL:    $ROOT/XSAI
               CONFIG=$XSAI_CONFIG NUM_CORES=$XSAI_NUM_CORES ISSUE=$XSAI_ISSUE TOP=$XSAI_RTL_TOP
               build: $XSAI_RTL_DIR -> $RTL_RELEASE_PACKAGE_DIR/rtl
  NEMU:        $ROOT/NEMU
  nexus-am:    $ROOT/nexus-am
  difftest:    $ROOT/XSAI/difftest -> env/difftest
  LLVM:        $LLVM_INSTALL_DIR -> $TOOLCHAIN_PACKAGE_DIR/llvm
  sysroot:     ${RISCV_SYSROOT_DIR:-<missing>} -> $TOOLCHAIN_PACKAGE_DIR/riscv64-linux-gnu
  GCC runtime: ${GCC_RUNTIME_DIR:-<missing>} -> $TOOLCHAIN_PACKAGE_DIR/lib/gcc

Optional release inputs:
  cases:           ${CASES_DIR:-<missing>}
  generated-src:   ${GENERATED_SRC_DIR:-<missing>}
  sim:             ${SIM_DIR:-<missing>}
  sram_tb:         ${SRAM_TB_DIR:-<missing>}
  sram_tb.mk:      ${SRAM_TB_MK:-<missing>}
  riscv-openocd:   ${OPENOCD_DIR:-<missing>}
EOF
}

copy_tree() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  tar -C "$src" \
    --exclude='./build' \
    --exclude='./build-*' \
    --exclude='./out' \
    --exclude='./.bloop' \
    --exclude='./.metals' \
    --exclude='./.idea' \
    --exclude='./.vscode' \
    --exclude='./*.log' \
    -cf - . | tar -C "$dst" -xf -
}

build_xsai_rtl() {
  echo "Building XSAI synthesis RTL"
  echo "  CONFIG=$XSAI_CONFIG NUM_CORES=$XSAI_NUM_CORES ISSUE=$XSAI_ISSUE TOP=$XSAI_RTL_TOP"
  make -C "$ROOT/XSAI" \
    BUILD_DIR="$XSAI_RTL_BUILD_DIR" \
    CONFIG="$XSAI_CONFIG" \
    NUM_CORES="$XSAI_NUM_CORES" \
    ISSUE="$XSAI_ISSUE" \
    XSTOP_PREFIX= \
    CHISEL_TARGET=systemverilog \
    verilog

  require_dir "$XSAI_RTL_DIR" "XSAI generated RTL directory"
  require_file "$XSAI_RTL_DIR/$XSAI_RTL_TOP.sv" "XSAI generated top RTL"
}

stage_xsai_rtl() {
  local dst="$1"
  local rtl_dst="$dst/rtl"
  local src rel
  local xsai_commit xsai_dirty

  mkdir -p "$rtl_dst"
  while IFS= read -r -d '' src; do
    rel="${src#"$XSAI_RTL_DIR/"}"
    mkdir -p "$rtl_dst/$(dirname "$rel")"
    cp -a "$src" "$rtl_dst/$rel"
  done < <(find "$XSAI_RTL_DIR" -type f \( -name '*.v' -o -name '*.sv' \) -print0)

  require_file "$rtl_dst/$XSAI_RTL_TOP.sv" "staged XSAI top RTL"
  (
    cd "$rtl_dst"
    find . -type f \( -name '*.v' -o -name '*.sv' \) -printf '%P\n' \
      | LC_ALL=C sort \
      | sed 's|^|$release_path/rtl/|'
  ) >"$dst/$XSAI_RTL_FILELIST"
  [[ -s "$dst/$XSAI_RTL_FILELIST" ]] || die "generated XSAI RTL filelist is empty"

  xsai_commit="$(git -C "$ROOT/XSAI" rev-parse HEAD 2>/dev/null || echo unknown)"
  xsai_dirty=false
  [[ -z "$(git -C "$ROOT/XSAI" status --porcelain --untracked-files=no 2>/dev/null)" ]] || xsai_dirty=true
  cat >"$dst/RELEASE-METADATA" <<EOF
config=$XSAI_CONFIG
num_cores=$XSAI_NUM_CORES
issue=$XSAI_ISSUE
top=$XSAI_RTL_TOP
xsai_commit=$xsai_commit
xsai_dirty=$xsai_dirty
generated_at_utc=$RELEASE_TIMESTAMP
EOF
}

validate_toolchain_inputs() {
  require_dir "$LLVM_INSTALL_DIR" "custom LLVM installation"
  require_file "$LLVM_INSTALL_DIR/bin/clang" "custom clang"
  require_file "$LLVM_INSTALL_DIR/bin/llvm-objdump" "custom llvm-objdump"
  require_dir "$RISCV_SYSROOT_DIR" "RISC-V Linux sysroot"
  [[ -n "$RISCV_GCC" ]] || die "riscv64-linux-gnu-gcc is required to locate the GCC runtime"
  require_dir "$GCC_RUNTIME_DIR" "RISC-V GCC runtime"
}

copy_llvm_tool() {
  local name="$1"
  local dst="$2"
  local src="$LLVM_INSTALL_DIR/bin/$name"
  local target base

  [[ -e "$src" || -L "$src" ]] || die "required LLVM tool not found: $src"
  while true; do
    base="$(basename "$src")"
    if [[ ! -e "$dst/$base" && ! -L "$dst/$base" ]]; then
      cp -a "$src" "$dst/$base"
    fi
    [[ -L "$src" ]] || break
    target="$(readlink "$src")"
    [[ "$target" != /* ]] || die "LLVM tool symlink must be relative: $src -> $target"
    src="$(dirname "$src")/$target"
  done
}

stage_llvm_toolchain() {
  local dst="$1"
  local llvm_dst="$dst/llvm"
  local tool src resource_dir resource_rel
  local gcc_target gcc_version llvm_commit llvm_dirty clang_version host_glibc

  mkdir -p "$dst/bin" "$dst/LICENSES" "$llvm_dst/bin" "$llvm_dst/lib"
  for tool in "${LLVM_TOOLS[@]}"; do
    copy_llvm_tool "$tool" "$llvm_dst/bin"
  done

  for src in "$LLVM_INSTALL_DIR"/lib/libLLVM.so* "$LLVM_INSTALL_DIR"/lib/libclang-cpp.so*; do
    [[ -e "$src" || -L "$src" ]] || continue
    cp -a "$src" "$llvm_dst/lib/"
  done

  resource_dir="$("$LLVM_INSTALL_DIR/bin/clang" -print-resource-dir)"
  case "$resource_dir/" in
    "$LLVM_INSTALL_DIR"/*) ;;
    *) die "clang resource directory is outside the LLVM installation: $resource_dir" ;;
  esac
  require_dir "$resource_dir" "clang resource directory"
  resource_rel="${resource_dir#"$LLVM_INSTALL_DIR/"}"
  copy_tree "$resource_dir" "$llvm_dst/$resource_rel"

  copy_tree "$RISCV_SYSROOT_DIR/include" "$dst/riscv64-linux-gnu/include"
  copy_tree "$RISCV_SYSROOT_DIR/lib" "$dst/riscv64-linux-gnu/lib"
  mkdir -p "$dst/riscv64-linux-gnu/usr/riscv64-linux-gnu"
  ln -s ../../include "$dst/riscv64-linux-gnu/usr/riscv64-linux-gnu/include"
  ln -s ../../lib "$dst/riscv64-linux-gnu/usr/riscv64-linux-gnu/lib"
  gcc_target="$("$RISCV_GCC" -dumpmachine)"
  gcc_version="$(basename "$GCC_RUNTIME_DIR")"
  copy_tree "$GCC_RUNTIME_DIR" "$dst/lib/gcc/$gcc_target/$gcc_version"

  cp -a "$ROOT/llvm-project-ame/LICENSE.TXT" "$dst/LICENSES/LLVM-LICENSE.TXT"
  [[ ! -f /usr/share/doc/gcc-15-cross-base/copyright ]] || \
    cp -a /usr/share/doc/gcc-15-cross-base/copyright "$dst/LICENSES/GCC-COPYRIGHT"
  [[ ! -f /usr/share/doc/libc6-dev-riscv64-cross/copyright ]] || \
    cp -a /usr/share/doc/libc6-dev-riscv64-cross/copyright "$dst/LICENSES/GLIBC-DEV-COPYRIGHT"
  [[ ! -f /usr/share/doc/libc6-riscv64-cross/copyright ]] || \
    cp -a /usr/share/doc/libc6-riscv64-cross/copyright "$dst/LICENSES/GLIBC-RUNTIME-COPYRIGHT"
  [[ ! -f /usr/share/doc/linux-libc-dev-riscv64-cross/copyright ]] || \
    cp -a /usr/share/doc/linux-libc-dev-riscv64-cross/copyright "$dst/LICENSES/LINUX-HEADERS-COPYRIGHT"

  cat >"$dst/bin/xsai-clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$TOOLCHAIN_ROOT/llvm/bin/clang" \
  --target=riscv64-unknown-linux-gnu \
  --sysroot="$TOOLCHAIN_ROOT/riscv64-linux-gnu" \
  --gcc-toolchain="$TOOLCHAIN_ROOT" \
  -fuse-ld=lld \
  -Wno-unused-command-line-argument \
  "$@"
EOF
  cat >"$dst/bin/xsai-clang++" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$TOOLCHAIN_ROOT/llvm/bin/clang++" \
  --target=riscv64-unknown-linux-gnu \
  --sysroot="$TOOLCHAIN_ROOT/riscv64-linux-gnu" \
  --gcc-toolchain="$TOOLCHAIN_ROOT" \
  -fuse-ld=lld \
  -Wno-unused-command-line-argument \
  "$@"
EOF
  chmod +x "$dst/bin/xsai-clang" "$dst/bin/xsai-clang++"

  cat >"$dst/README.md" <<'EOF'
# XSAI LLVM toolchain

This is a relocatable x86_64 GNU/Linux host toolchain for XSAI RISC-V software.
Use `bin/xsai-clang` or `bin/xsai-clang++` to compile and link against the
bundled RISC-V Linux sysroot. The wrappers select the bundled LLD linker.

Example:

```bash
toolchain/bin/xsai-clang \
  -march=rv64g_v_zvfh_zames_zmasync_zvl128b_zicbop_zihintpause \
  hello.c -o hello

toolchain/llvm/bin/llvm-objdump -d hello --mattr=+zames,+zmasync
```

The host must provide compatible x86_64 versions of glibc, libstdc++, zlib,
zstd, and libxml2. The bundled sysroot and GCC runtime are RISC-V target files;
they do not make the compiler portable to a different host OS or architecture.
EOF

  llvm_commit="$(git -C "$ROOT/llvm-project-ame" rev-parse HEAD 2>/dev/null || echo unknown)"
  llvm_dirty=false
  [[ -z "$(git -C "$ROOT/llvm-project-ame" status --porcelain --untracked-files=no 2>/dev/null)" ]] || llvm_dirty=true
  clang_version="$("$LLVM_INSTALL_DIR/bin/clang" --version | sed -n '1p')"
  host_glibc="$(ldd --version 2>/dev/null | sed -n '1p' || echo unknown)"
  cat >"$dst/TOOLCHAIN-METADATA" <<EOF
llvm_commit=$llvm_commit
llvm_dirty=$llvm_dirty
clang_version=$clang_version
host_arch=$(uname -m)
host_glibc=$host_glibc
target_triple=riscv64-unknown-linux-gnu
gcc_target=$gcc_target
gcc_version=$gcc_version
sysroot_source=$RISCV_SYSROOT_DIR
generated_at_utc=$RELEASE_TIMESTAMP
EOF
}

write_release_makefile() {
  local file="$1"
  local rtl_release_package_dir="$2"
  local xsai_num_cores="$3"
  cat >"$file" <<'EOF'
ABS_WORK_DIR = $(shell pwd)
RELEASE_DIR = $(ABS_WORK_DIR)/@RTL_RELEASE_PACKAGE_DIR@
LLVM_HOME = $(ABS_WORK_DIR)/toolchain/llvm
XSAI_CLANG = $(ABS_WORK_DIR)/toolchain/bin/xsai-clang
XSAI_CLANGXX = $(ABS_WORK_DIR)/toolchain/bin/xsai-clang++
SIM_DIR = $(ABS_WORK_DIR)/sim
NEMU_DIR = $(ABS_WORK_DIR)/NEMU
CASES_DIR = $(ABS_WORK_DIR)/cases

CFG_CIR           = $(ABS_WORK_DIR)/env/difftest/config
SIM_CSRC_DIR      = $(ABS_WORK_DIR)/env/difftest/src/test/csrc/common
PLUGIN_CHEAD_DIR  = $(ABS_WORK_DIR)/env/difftest/src/test/csrc/plugin/include
PLUGIN_CSRC_DIR   = $(ABS_WORK_DIR)/env/difftest/src/test/csrc/plugin/spikedasm
DIFFTEST_CSRC_DIR = $(ABS_WORK_DIR)/env/difftest/src/test/csrc/difftest
VCS_CSRC_DIR      = $(ABS_WORK_DIR)/env/difftest/src/test/csrc/vcs
GEN_CSRC_DIR      = $(ABS_WORK_DIR)/env/generated-src

SIM_COMMON_DIR    = $(ABS_WORK_DIR)/env/difftest/src/test/vsrc/common
SIM_ST_DIR        = $(ABS_WORK_DIR)/env/difftest/src/test/vsrc/st
VCS_TOP_DIR       = $(ABS_WORK_DIR)/env/difftest/src/test/vsrc/vcs
SIMTOP_DIR        = $(ABS_WORK_DIR)/env/sim

ifndef VERDI_HOME
$(error VERDI_HOME is not set. Try whereis verdi, abandon /bin/verdi and set VERDI_HOME manually)
else
NOVAS_HOME = $(VERDI_HOME)
NOVAS = $(NOVAS_HOME)/share/PLI/VCS/LINUX64
EXTRA += +define+CONSIDER_FSDB -P $(NOVAS)/novas.tab $(NOVAS)/pli.a
endif

VCS_FLAGS += -full64 +v2k -timescale=1ns/10ps -sverilog -debug_access+all +lint=TFIPC-L
VCS_FLAGS += -l vcs.log -top tb_top -fgp -lca -kdb +nospecify +notimingcheck -no_save -xprop
VCS_FLAGS += +define+DIFFTEST +define+ASSERT_VERBOSE_COND_=1 +define+PRINTF_COND_=1
VCS_FLAGS += +define+STOP_COND_=1 +define+VCS +incdir+$(GEN_CSRC_DIR)
VCS_FLAGS += -CFLAGS "$(VCS_CXXFLAGS)" -LDFLAGS "$(VCS_LDFLAGS)" -j200
VCS_FLAGS += $(EXTRA)

VCS_CXXFLAGS += -std=c++17 -static -Wall -DREF_PROXY=NemuProxy -DNUM_CORES=@XSAI_NUM_CORES@
VCS_CXXFLAGS += -I$(CFG_CIR) -I$(GEN_CSRC_DIR) -I$(VCS_CSRC_DIR) -I$(SIM_CSRC_DIR)
VCS_CXXFLAGS += -I$(PLUGIN_CHEAD_DIR) -I$(PLUGIN_CSRC_DIR) -I$(DIFFTEST_CSRC_DIR)
VCS_LDFLAGS += -Wl,--no-as-needed -lpthread -lSDL2 -ldl -lz -lzstd

DUT_FILELIST = $(SIM_DIR)/dut.f
ENV_FILELIST = $(SIM_DIR)/env.f

FORCE:

$(DUT_FILELIST): FORCE
	@mkdir -p $(SIM_DIR)
	@test -d "$(RELEASE_DIR)" || { echo "RTL release directory not found: $(RELEASE_DIR)"; exit 1; }
	@cat $(RELEASE_DIR)/XSAI.f | sort -u > $(DUT_FILELIST)
	sed -i 's|$$release_path|$(RELEASE_DIR)|g' $(DUT_FILELIST)

$(ENV_FILELIST): FORCE
	@mkdir -p $(SIM_DIR)
	@find $(SIM_CSRC_DIR) -name "*.cpp" > $(ENV_FILELIST)
	@find $(PLUGIN_CSRC_DIR) -name "*.cpp" >> $(ENV_FILELIST)
	@find $(DIFFTEST_CSRC_DIR) -name "*.cpp" >> $(ENV_FILELIST)
	@find $(GEN_CSRC_DIR) -name "*.cpp" >> $(ENV_FILELIST)
	@find $(VCS_CSRC_DIR) -name "*.cpp" -or -name "*.c" >> $(ENV_FILELIST)
	@find $(SIM_COMMON_DIR) -name "*.v" -or -name "*.sv" >> $(ENV_FILELIST)
	@find $(SIM_ST_DIR) -name "*.v" -or -name "*.sv" >> $(ENV_FILELIST)
	@find $(SIMTOP_DIR) -name "*.v" -or -name "*.sv" >> $(ENV_FILELIST)
	@find $(VCS_TOP_DIR) -name "*.v" -or -name "*.sv" >> $(ENV_FILELIST)

simv: $(DUT_FILELIST) $(ENV_FILELIST)
	@mkdir -p $(SIM_DIR)/comp
	cd $(SIM_DIR)/comp && vcs $(VCS_FLAGS) -f $(DUT_FILELIST) -f $(ENV_FILELIST)
	rm $(ENV_FILELIST)

libnemu := $(NEMU_DIR)/build/riscv64-nemu-interpreter-so

$(libnemu):
	NEMU_HOME=$(NEMU_DIR) make -C $(NEMU_DIR) riscv64-nhv5-multi-ref_defconfig
	NEMU_HOME=$(NEMU_DIR) make -C $(NEMU_DIR) -j

RUN_BIN_DIR = $(CASES_DIR)
RUN_BIN  ?= dhrystone.bin
RUN_OPTS += -fgp=num_threads:4,num_fsdb_threads:4
RUN_OPTS += -assert finish_maxfail=30 -assert global_finish_maxfail=10000
RUN_OPTS += +dump-wave=fsdb +workload=$(RUN_BIN_DIR)/$(RUN_BIN)
RUN_OPTS += $(if $(filter 0,$(DIFF)),+no-diff,+diff=$(libnemu))

run: $(libnemu)
	@mkdir -p $(SIM_DIR)/$(RUN_BIN)
	@touch $(SIM_DIR)/$(RUN_BIN)/sim.log
	@rm -f $(SIM_DIR)/$(RUN_BIN)/simv
	@rm -rf $(SIM_DIR)/$(RUN_BIN)/simv.daidir
	@ln -s $(SIM_DIR)/comp/simv $(SIM_DIR)/$(RUN_BIN)/simv
	@ln -s $(SIM_DIR)/comp/simv.daidir $(SIM_DIR)/$(RUN_BIN)/simv.daidir
	cd $(SIM_DIR)/$(RUN_BIN) && (./simv $(RUN_OPTS) 2> assert.log | tee sim.log)

clean:
	rm -rf $(SIM_DIR)
	make -C NEMU clean
	make -C NEMU clean-softfloat
EOF
  sed -i "s|@RTL_RELEASE_PACKAGE_DIR@|$rtl_release_package_dir|g" "$file"
  sed -i "s|@XSAI_NUM_CORES@|$xsai_num_cores|g" "$file"
}

create_release() {
  require_dir "$ROOT/XSAI" "XSAI"
  require_dir "$ROOT/NEMU" "NEMU"
  require_dir "$ROOT/nexus-am" "nexus-am"
  require_dir "$ROOT/XSAI/difftest" "XSAI/difftest"
  validate_toolchain_inputs
  build_xsai_rtl

  mkdir -p "$OUT_DIR"
  if [[ -z "$STAGE" ]]; then
    STAGE="$(mktemp -d "$OUT_DIR/.${NAME}.stage.XXXXXX")"
  else
    rm -rf "$STAGE"
    mkdir -p "$STAGE"
  fi

  local release_root="$STAGE/$NAME"
  mkdir -p "$release_root/env"

  echo "Staging release at $release_root"
  write_release_makefile "$release_root/Makefile" "$RTL_RELEASE_PACKAGE_DIR" "$XSAI_NUM_CORES"

  echo "  -> $RTL_RELEASE_PACKAGE_DIR (CONFIG=$XSAI_CONFIG)"
  stage_xsai_rtl "$release_root/$RTL_RELEASE_PACKAGE_DIR"

  echo "  -> $TOOLCHAIN_PACKAGE_DIR (custom LLVM + RISC-V sysroot)"
  stage_llvm_toolchain "$release_root/$TOOLCHAIN_PACKAGE_DIR"

  echo "  -> NEMU"
  copy_tree "$ROOT/NEMU" "$release_root/NEMU"
  echo "  -> nexus-am"
  copy_tree "$ROOT/nexus-am" "$release_root/nexus-am"
  echo "  -> env/difftest"
  copy_tree "$ROOT/XSAI/difftest" "$release_root/env/difftest"

  if handle_optional_dir "$CASES_DIR" "cases directory" "Pass --cases-dir with customer test binaries."; then
    echo "  -> cases"
    copy_tree "$CASES_DIR" "$release_root/cases"
  fi
  if handle_optional_dir "$GENERATED_SRC_DIR" "generated-src directory" "Pass --generated-src-dir from the generated difftest output."; then
    echo "  -> env/generated-src"
    copy_tree "$GENERATED_SRC_DIR" "$release_root/env/generated-src"
  fi
  if handle_optional_dir "$SIM_DIR" "sim directory" "Pass --sim-dir with generated simulation Verilog."; then
    echo "  -> env/sim"
    copy_tree "$SIM_DIR" "$release_root/env/sim"
  fi
  if handle_optional_dir "$SRAM_TB_DIR" "sram_tb directory" "Pass --sram-tb-dir if SRAM testbench helpers are available."; then
    echo "  -> env/sram_tb"
    copy_tree "$SRAM_TB_DIR" "$release_root/env/sram_tb"
  fi
  if handle_optional_file "$SRAM_TB_MK" "sram_tb.mk" "Pass --sram-tb-mk if this top-level helper is available."; then
    echo "  -> sram_tb.mk"
    cp -a "$SRAM_TB_MK" "$release_root/sram_tb.mk"
  fi
  if handle_optional_dir "$OPENOCD_DIR" "riscv-openocd directory" "Pass --openocd-dir if OpenOCD should be included."; then
    echo "  -> riscv-openocd"
    copy_tree "$OPENOCD_DIR" "$release_root/riscv-openocd"
  fi

  local archive="$OUT_DIR/$NAME.tar.gz"
  rm -f "$archive"
  echo "Creating archive $archive"
  tar -C "$STAGE" -czf "$archive" "$NAME"

  if [[ "$KEEP_STAGE" == true ]]; then
    echo "Kept staging directory: $release_root"
  else
    rm -rf "$STAGE"
  fi
  echo "Release archive ready: $archive"
}

parse_args "$@"
resolve_inputs
print_manifest

if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi

create_release

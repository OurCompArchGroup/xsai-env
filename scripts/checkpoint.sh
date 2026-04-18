#!/usr/bin/env bash
# =============================================================================
# checkpoint.sh — SimPoint-based checkpoint generation for XSAI workloads
#
# Three-phase workflow:
#   1. profile    — Run QEMU with the profiling plugin to collect BBV data
#   2. cluster    — Run SimPoint clustering on the BBV data
#   3. checkpoint — Re-run QEMU in SimpointCheckpoint mode to dump checkpoints
#
# Common repo usage patterns:
#   - Fast single-slice path:
#       use no_simpoint + do_checkpoint, typically with small CPT_INTERVAL=100.
#       This usually emits a single checkpoint .zstd.
#   - SimPoint sampling path:
#       do_profile + do_cluster + do_checkpoint, for example with
#       CPT_INTERVAL=100000 and SIMPOINT_MAX_K=30.
#       This can produce multiple representative checkpoint slices that can be
#       replayed in parallel on emu/NEMU for hardware-oriented analysis.
#
# Usage:
#   ./scripts/checkpoint.sh [profile|cluster|checkpoint|all] [OPTIONS]
#
# Key environment variables (all have defaults):
#   XS_PROJECT_ROOT       — repo root (auto-detected if sourced from root)
#   WORKLOAD_NAME         — logical name for the workload        [default: app]
#   MODEL_IMG             — path to the disk image (qcow2/raw)
#   CHECKPOINT_CONFIG     — sub-dir / tag for this checkpoint run [default: build]
#   CPT_INTERVAL          — instructions per checkpoint slice     [default: 100]
#   PROFILING_INTERVALS   — BBV interval size (instructions)      [default: CPT_INTERVAL]
#   SIMPOINT_MAX_K        — max clusters for SimPoint             [default: 10]
#   MEMORY                — QEMU guest memory                     [default: 8G]
#   SMP                   — QEMU SMP hart count                   [default: 1]
#   CKPT_VIRTIO_SERIAL    — enable host_guest virtio-serial port  [default: 0]
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve project root
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# ---------------------------------------------------------------------------
# Defaults — override via environment or command-line flags
# ---------------------------------------------------------------------------
WORKLOAD_NAME="${WORKLOAD_NAME:-app}"
CHECKPOINT_CONFIG="${CHECKPOINT_CONFIG:-build}"
CPT_INTERVAL="${CPT_INTERVAL:-100}"
PROFILING_INTERVALS="${PROFILING_INTERVALS:-$CPT_INTERVAL}"
SIMPOINT_MAX_K="${SIMPOINT_MAX_K:-10}"
MEMORY="${MEMORY:-8G}"
SMP="${SMP:-1}"
RESUME_CHECKPOINT="${RESUME_CHECKPOINT:-}"  # optional: resume from an existing checkpoint before profiling
CKPT_VIRTIO_SERIAL="${CKPT_VIRTIO_SERIAL:-0}"

# Derived paths
QEMU_HOME="${QEMU_HOME:-$XS_PROJECT_ROOT/qemu}"
NEMU_HOME="${NEMU_HOME:-$XS_PROJECT_ROOT/NEMU}"
GCPT_RESTORE_HOME="${GCPT_RESTORE_HOME:-$XS_PROJECT_ROOT/firmware/LibCheckpoint}"
PAYLOAD="${PAYLOAD:-$GCPT_RESTORE_HOME/build/gcpt.bin}"
MODEL_IMG="${MODEL_IMG:-}"   # caller MUST set this or pass --img <path>
QEMU_DTB="${QEMU_DTB:-$XS_PROJECT_ROOT/firmware/nemu_board/dts/build/xiangshan_ai.dtb}"

CHECKPOINT_RESULT_ROOT="${CHECKPOINT_RESULT_ROOT:-$XS_PROJECT_ROOT/firmware/checkpoints}"
SIMPOINT_BIN="${SIMPOINT_BIN:-$NEMU_HOME/resource/simpoint/simpoint_repo/bin/simpoint}"

QEMU_BIN="$QEMU_HOME/build/qemu-system-riscv64"
PROFILING_PLUGIN="$QEMU_HOME/build/contrib/plugins/libprofiling.so"

# QEMU CPU flags shared between profiling and checkpointing runs.
# Can be overridden by the caller: CPU_FLAGS=... ./scripts/checkpoint.sh
# The Makefile passes QEMU_CPU_FLAGS via: $(MAKE) ... CPU_FLAGS='$(QEMU_CPU_FLAGS)'
CPU_FLAGS="${CPU_FLAGS:-rv64,v=true,vlen=128,h=true,sstc=true,svpbmt=true,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32,sv39=true,sv48=true,sv57=false,sv64=false}"

# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------
log()  { echo "[ckpt] $*"; }
die()  { echo "[ckpt] ERROR: $*" >&2; exit 1; }
need() { command -v "$1" &>/dev/null || die "Required command not found: $1"; }

# Parse named args (--key value pairs) that override defaults
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --workload)    WORKLOAD_NAME="$2";        shift 2 ;;
            --img)         MODEL_IMG="$2";            shift 2 ;;
            --config)      CHECKPOINT_CONFIG="$2";   shift 2 ;;
            --resume)      RESUME_CHECKPOINT="$2";   shift 2 ;;
            --cpt-interval) CPT_INTERVAL="$2";       shift 2 ;;
            --intervals)   PROFILING_INTERVALS="$2"; shift 2 ;;
            --max-k)       SIMPOINT_MAX_K="$2";      shift 2 ;;
            --memory)      MEMORY="$2";              shift 2 ;;
            --smp)         SMP="$2";                 shift 2 ;;
            --payload)     PAYLOAD="$2";             shift 2 ;;
            --result-root) CHECKPOINT_RESULT_ROOT="$2"; shift 2 ;;
            -*)            die "Unknown flag: $1" ;;
            *)             break ;;
        esac
    done
}

check_prereqs() {
    need dtc
    [[ -x "$QEMU_BIN" ]]        || die "QEMU not found: $QEMU_BIN  (run: make qemu)"
    [[ -f "$PAYLOAD" ]]         || die "GCPT payload not found: $PAYLOAD  (run: make firmware or make build-gcpt)"
    [[ -f "$QEMU_DTB" ]]        || die "DTB not found: $QEMU_DTB  (run: make -C firmware build-dtb)"
}

check_profiling_prereqs() {
    check_prereqs
    [[ -f "$PROFILING_PLUGIN" ]] || die "libprofiling.so not found: $PROFILING_PLUGIN  (run: make qemu)"
    [[ -z "$MODEL_IMG" ]] || [[ -f "$MODEL_IMG" ]] || die "Disk image not found: $MODEL_IMG"
}

check_cluster_prereqs() {
    [[ -x "$SIMPOINT_BIN" ]] || die "SimPoint binary not found: $SIMPOINT_BIN  (run: make simpoint)"
    local bbv="$CHECKPOINT_RESULT_ROOT/profiling-0-0/$WORKLOAD_NAME/simpoint_bbv.gz"
    [[ -f "$bbv" ]] || die "BBV file not found: $bbv  (run: make profile first)"
}

check_checkpoint_prereqs() {
    check_prereqs
    [[ -z "$MODEL_IMG" ]] || [[ -f "$MODEL_IMG" ]] || die "Disk image not found: $MODEL_IMG"
    local cluster_dir="$CHECKPOINT_RESULT_ROOT/cluster-0-0/$WORKLOAD_NAME"
    [[ -f "$cluster_dir/simpoints0" ]] || die "Cluster results not found: $cluster_dir/simpoints0  (run: make cluster first)"
}

build_drive_args() {
    DRIVE_ARGS=()
    if [[ -n "$MODEL_IMG" ]]; then
        local drive_spec="file=$MODEL_IMG,if=none,id=drv0,format=raw"
        if [[ ! -w "$MODEL_IMG" ]]; then
            log "  Disk image access: read-only"
            drive_spec+=",readonly=on"
        fi

        DRIVE_ARGS=(
            -device virtio-blk-device,drive=drv0
            -drive "$drive_spec"
        )
    fi
}

build_virtio_serial_args() {
    VIRTIO_SERIAL_ARGS=()

    case "$CKPT_VIRTIO_SERIAL" in
        1|true|TRUE|yes|YES|on|ON)
            if [[ -n "$MODEL_IMG" ]]; then
                die "CKPT_VIRTIO_SERIAL=1 conflicts with MODEL_IMG on the nemu machine: only one virtio-mmio slot is available"
            fi

            VIRTIO_SERIAL_ARGS=(
                -device virtio-serial-device
                -device virtserialport,chardev=char0,id=port0,name=host_guest
                -chardev socket,id=char0,path=/tmp/virtio-serial-ckpt.sock,server=on,wait=off
            )
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Phase 1 — Profiling
# ---------------------------------------------------------------------------
do_profile() {
    check_profiling_prereqs

    local out_dir="$CHECKPOINT_RESULT_ROOT/profiling-0-0/$WORKLOAD_NAME"
    mkdir -p "$out_dir"

    log "=== Phase 1: Profiling ==="
    log "  Workload  : $WORKLOAD_NAME"
    log "  Disk image: ${MODEL_IMG:-(none)}"
    log "  Resume from: ${RESUME_CHECKPOINT:-(cold start)}"
    log "  BBV dir   : $out_dir"
    log "  Intervals : $PROFILING_INTERVALS instructions"

    build_drive_args
    build_virtio_serial_args

    # Build -M nemu option: only add checkpoint= when resuming from an existing snapshot
    local nemu_opts="nemu"
    [[ -n "$RESUME_CHECKPOINT" ]] && nemu_opts="nemu,checkpoint=$RESUME_CHECKPOINT"

    "$QEMU_BIN" \
        -bios "$PAYLOAD" \
        -dtb "$QEMU_DTB" \
        -M "$nemu_opts" \
        -nographic -m "$MEMORY" -smp "$SMP" \
        -cpu "$CPU_FLAGS" \
        -plugin "$PROFILING_PLUGIN,workload=$WORKLOAD_NAME,intervals=$PROFILING_INTERVALS,target=$out_dir" \
        -serial mon:stdio \
        "${VIRTIO_SERIAL_ARGS[@]}" \
        "${DRIVE_ARGS[@]}"

    log "✓ Profiling complete — BBV: $out_dir/simpoint_bbv.gz"
}

# ---------------------------------------------------------------------------
# Phase 2 — SimPoint Clustering
# ---------------------------------------------------------------------------
do_cluster() {
    check_cluster_prereqs

    local bbv_file="$CHECKPOINT_RESULT_ROOT/profiling-0-0/$WORKLOAD_NAME/simpoint_bbv.gz"
    local cluster_dir="$CHECKPOINT_RESULT_ROOT/cluster-0-0/$WORKLOAD_NAME"
    mkdir -p "$cluster_dir"

    local random1 random2
    random1=$(head -20 /dev/urandom | cksum | cut -c 1-6)
    random2=$(head -20 /dev/urandom | cksum | cut -c 1-6)

    log "=== Phase 2: Clustering ==="
    log "  BBV file : $bbv_file"
    log "  Output   : $cluster_dir"
    log "  maxK     : $SIMPOINT_MAX_K"

    "$SIMPOINT_BIN" \
        -loadFVFile "$bbv_file" \
        -saveSimpoints "$cluster_dir/simpoints0" \
        -saveSimpointWeights "$cluster_dir/weights0" \
        -inputVectorsGzipped \
        -maxK "$SIMPOINT_MAX_K" \
        -numInitSeeds 2 \
        -iters 1000 \
        -seedkm "$random1" \
        -seedproj "$random2" \
        > "$CHECKPOINT_RESULT_ROOT/cluster.out" \
        2> "$CHECKPOINT_RESULT_ROOT/cluster.err"

    log "✓ Clustering complete"
    log "  Simpoints : $cluster_dir/simpoints0"
    log "  Weights   : $cluster_dir/weights0"
}

no_simpoint() {
    local cluster_dir="$CHECKPOINT_RESULT_ROOT/cluster-0-0/$WORKLOAD_NAME"
    mkdir -p "$cluster_dir"
    echo "1 0" > $cluster_dir/weights0
    echo "1 0" > $cluster_dir/simpoints0
}

# ---------------------------------------------------------------------------
# Phase 3 — SimPoint Checkpointing
# ---------------------------------------------------------------------------
do_checkpoint() {
    check_checkpoint_prereqs

    local cluster_dir="$CHECKPOINT_RESULT_ROOT/cluster-0-0"

    local out_dir="$CHECKPOINT_RESULT_ROOT/$CHECKPOINT_CONFIG/$WORKLOAD_NAME"
    if [[ -d "$out_dir" ]]; then
        log "Removing existing checkpoint dir: $out_dir"
        rm -rf "$out_dir"
    fi

    log "=== Phase 3: Checkpointing ==="
    log "  Workload      : $WORKLOAD_NAME"
    log "  Config        : $CHECKPOINT_CONFIG"
    log "  cpt-interval  : $CPT_INTERVAL instructions"
    log "  Output root   : $CHECKPOINT_RESULT_ROOT"
    log "  Disk image    : ${MODEL_IMG:-(none)}"

    build_drive_args
    build_virtio_serial_args

    "$QEMU_BIN" \
        -bios "$PAYLOAD" \
        -dtb "$QEMU_DTB" \
        -M "nemu,simpoint-path=$cluster_dir,workload=$WORKLOAD_NAME,cpt-interval=$CPT_INTERVAL,output-base-dir=$CHECKPOINT_RESULT_ROOT,config-name=$CHECKPOINT_CONFIG,checkpoint-mode=SimpointCheckpoint" \
        -nographic -m "$MEMORY" -smp "$SMP" \
        -cpu "$CPU_FLAGS" \
        -serial mon:stdio \
        "${VIRTIO_SERIAL_ARGS[@]}" \
        "${DRIVE_ARGS[@]}"

    log "✓ Checkpoint dump complete"
    log "  Results: $out_dir"
    ls "$out_dir" 2>/dev/null \
        || log "  (directory empty or not yet created)"
}

# ---------------------------------------------------------------------------
# Phase — Uniform Checkpointing (dump every N instructions, no SimPoint)
# ---------------------------------------------------------------------------
do_uniform() {
    check_prereqs
    [[ -z "$MODEL_IMG" ]] || [[ -f "$MODEL_IMG" ]] || die "Disk image not found: $MODEL_IMG"

    local out_dir="$CHECKPOINT_RESULT_ROOT/$CHECKPOINT_CONFIG/$WORKLOAD_NAME"
    if [[ -d "$out_dir" ]]; then
        log "Removing existing checkpoint dir: $out_dir"
        rm -rf "$out_dir"
    fi

    log "=== Uniform Checkpointing ==="
    log "  Workload      : $WORKLOAD_NAME"
    log "  Config        : $CHECKPOINT_CONFIG"
    log "  cpt-interval  : $CPT_INTERVAL instructions"
    log "  Output root   : $CHECKPOINT_RESULT_ROOT"
    log "  Disk image    : ${MODEL_IMG:-(none)}"

    build_drive_args
    build_virtio_serial_args

    "$QEMU_BIN" \
        -bios "$PAYLOAD" \
        -dtb "$QEMU_DTB" \
        -M "nemu,workload=$WORKLOAD_NAME,cpt-interval=$CPT_INTERVAL,output-base-dir=$CHECKPOINT_RESULT_ROOT,config-name=$CHECKPOINT_CONFIG,checkpoint-mode=UniformCheckpoint" \
        -nographic -m "$MEMORY" -smp "$SMP" \
        -cpu "$CPU_FLAGS" \
        -serial mon:stdio \
        "${VIRTIO_SERIAL_ARGS[@]}" \
        "${DRIVE_ARGS[@]}"

    log "✓ Uniform checkpoint dump complete"
    log "  Results: $out_dir"
    ls "$out_dir" 2>/dev/null \
        || log "  (directory empty or not yet created)"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
PHASE="${1:-all}"
shift || true
parse_args "$@"

case "$PHASE" in
    profile)    do_profile ;;
    cluster)    do_cluster ;;
    checkpoint) do_checkpoint ;;
    uniform)    do_uniform ;;
    all)
        # do_profile
        # do_cluster
        no_simpoint
        do_checkpoint
        ;;
    *)
        echo "Usage: $0 [profile|cluster|checkpoint|uniform|all] [--workload NAME] [--img PATH] ..."
        echo "       --config NAME       checkpoint config tag  (default: build)"
        echo "       --resume PATH       resume profiling from an existing checkpoint file"
        echo "                           (omit for cold-start profiling)"
        echo "       --cpt-interval N    instructions per slice (default: 100)"
        echo "       --intervals N       BBV interval size      (default: CPT_INTERVAL)"
        echo "       --max-k N           SimPoint max clusters  (default: 10)"
        echo "       --memory SIZE       QEMU memory            (default: 8G)"
        echo "       --smp N             QEMU SMP count         (default: 1)"
        echo "       --payload PATH      GCPT binary path"
        echo "       --result-root PATH  checkpoint output root"
        exit 1
        ;;
esac

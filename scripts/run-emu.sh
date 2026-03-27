#!/usr/bin/env bash
# =============================================================================
# run-emu.sh — Run XSAI RTL emulator with optional logging and diff mode
#
# Usage:
#   ./scripts/run-emu.sh [OPTIONS] <payload>
#
# Options:
#   --log              Save output to log/<name>_<timestamp>.log (and tee to stdout)
#   --diff             Enable diff mode (compare against NEMU reference)
#   --log-dir DIR      Log directory (default: log/)
#   --diff-so PATH     Path to reference .so (default: auto-detected)
#
# Debug / wave / ChiselDB options:
#   --wave             Enable FST waveform dump (requires emu built with EMU_TRACE=fst)
#   --wave-path PATH   Waveform output file (default: log/<name>_<ts>.fst)
#   -b CYCLE           Waveform start cycle  (default: 0)
#   -e CYCLE           Waveform end cycle    (default: none)
#   -W WARMUP          Warm-up instruction count  passed to emu -W
#   -I MAX_INSTR       Max instruction count       passed to emu -I
#   --fork             Enable LightSSS fork-based snapshot (--enable-fork)
#   --db               Enable ChiselDB dump (--dump-db)
#   --db-select TABLE  --dump-select-db argument (default: "lifetime")
#   --db-path PATH     Move generated .db to PATH after run (emu always writes to NOOP_HOME/build/)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XS_PROJECT_ROOT="${XS_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
NOOP_HOME="${NOOP_HOME:-$XS_PROJECT_ROOT/XSAI}"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
ENABLE_LOG=0
ENABLE_DIFF=0
LOG_DIR="$XS_PROJECT_ROOT/log"
DIFF_SO="$NOOP_HOME/ready-to-run/riscv64-nemu-interpreter-so"
RESTORER=""
# "${GCPT_RESTORE_HOME}/build/gcpt.bin"
PAYLOAD=""

# Debug / wave / ChiselDB
ENABLE_WAVE=0
WAVE_PATH=""
WAVE_BEGIN=""
WAVE_END=""
WARMUP=""
MAX_INSTR=""
ENABLE_FORK=0
ENABLE_DB=0
DB_DEST=""      # where to move the .db after run (empty = leave in NOOP_HOME/build/)
DB_SELECT="lifetime"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log)         ENABLE_LOG=1;        shift ;;
        --diff)        ENABLE_DIFF=1;       shift ;;
        --log-dir)     LOG_DIR="$2";        shift 2 ;;
        --diff-so)     DIFF_SO="$2";        shift 2 ;;
        --restorer)    RESTORER="$2";       shift 2 ;;
        --wave)        ENABLE_WAVE=1;       shift ;;
        --wave-path)   WAVE_PATH="$2";      shift 2 ;;
        -b)            WAVE_BEGIN="$2";     shift 2 ;;
        -e)            WAVE_END="$2";       shift 2 ;;
        -W)            WARMUP="$2";         shift 2 ;;
        -I)            MAX_INSTR="$2";      shift 2 ;;
        --fork)        ENABLE_FORK=1;       shift ;;
        --db)          ENABLE_DB=1;         shift ;;
        --db-dest)     DB_DEST="$2";        shift 2 ;;
        --db-select)   DB_SELECT="$2";      shift 2 ;;
        --db-path)     DB_DEST="$2";        shift 2 ;;  # alias
        -*)            echo "Unknown flag: $1" >&2; exit 1 ;;
        *)             PAYLOAD="$1";        shift ;;
    esac
done

[[ -n "$PAYLOAD" ]] || { echo "Usage: $0 [--log] [--diff] <payload>" >&2; exit 1; }
[[ -f "$PAYLOAD" ]] || { echo "Payload not found: $PAYLOAD" >&2; exit 1; }
[[ -x "$NOOP_HOME/build/emu" ]] || { echo "emu not found: $NOOP_HOME/build/emu" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Derive a clean program name from the payload path
# ---------------------------------------------------------------------------
prog_name="$(basename "$(dirname "$PAYLOAD")")"
if [[ -z "$prog_name" || "$prog_name" == "." || "$prog_name" == "/" ]]; then
    prog_name="$(basename "$PAYLOAD")"
    prog_name="${prog_name%.gz}"
    prog_name="${prog_name%.*}"
fi

# ---------------------------------------------------------------------------
# Build emu argument list
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"
ts="$(date +%Y%m%d-%H%M%S)"

# Determine restorer flag
restorer_args=()
if [[ -f "$RESTORER" ]]; then
    restorer_args=(-r "$RESTORER")
fi

if [[ "$ENABLE_DIFF" == "1" ]]; then
    [[ -f "$DIFF_SO" ]] || { echo "diff .so not found: $DIFF_SO" >&2; exit 1; }
    emu_args=(-i "$PAYLOAD" --diff="$DIFF_SO" "${restorer_args[@]}")
else
    emu_args=(-i "$PAYLOAD" --no-diff "${restorer_args[@]}")
fi

# -W / -I instruction window
[[ -n "$WARMUP"    ]] && emu_args+=(-W "$WARMUP")
[[ -n "$MAX_INSTR" ]] && emu_args+=(-I "$MAX_INSTR")

# LightSSS fork snapshot
[[ "$ENABLE_FORK" == "1" ]] && emu_args+=(--enable-fork)

# FST waveform
if [[ "$ENABLE_WAVE" == "1" ]]; then
    [[ -z "$WAVE_PATH" ]] && WAVE_PATH="$LOG_DIR/${prog_name}_${ts}.fst"
    emu_args+=(--dump-wave --wave-path "$WAVE_PATH")
    [[ -n "$WAVE_BEGIN" ]] && emu_args+=(-b "$WAVE_BEGIN")
    [[ -n "$WAVE_END"   ]] && emu_args+=(-e "$WAVE_END")
fi

# ChiselDB
if [[ "$ENABLE_DB" == "1" ]]; then
    emu_args+=(--dump-db --dump-select-db "$DB_SELECT")
fi

# ---------------------------------------------------------------------------
# Run with or without logging
# ---------------------------------------------------------------------------
_run_emu() {
    if [[ "$ENABLE_LOG" == "1" ]]; then
        local log_file="$LOG_DIR/${prog_name}_${ts}.log"
        local err_log_file="${log_file%.log}.err.log"
        echo "[run-emu] payload : $PAYLOAD"
        echo "[run-emu] log     : $log_file"
        echo "[run-emu] err-log : $err_log_file"
        [[ "$ENABLE_DIFF" == "1" ]] && echo "[run-emu] diff    : $DIFF_SO"
        [[ "$ENABLE_WAVE" == "1" ]] && echo "[run-emu] wave    : $WAVE_PATH"
        [[ "$ENABLE_DB"   == "1" ]] && echo "[run-emu] db-dest : ${DB_DEST:-$LOG_DIR/${prog_name}_${ts}.db}"
        echo "[run-emu] cmd     : $NOOP_HOME/build/emu ${emu_args[*]}"
        "$NOOP_HOME/build/emu" "${emu_args[@]}" 2> "$err_log_file" | tee "$log_file"
    else
        local err_log_file="$LOG_DIR/emu-error.log"
        echo "[run-emu] err-log : $err_log_file"
        echo "[run-emu] cmd     : $NOOP_HOME/build/emu ${emu_args[*]}"
        "$NOOP_HOME/build/emu" "${emu_args[@]}" 2> "$err_log_file"
    fi
}

_run_emu

# Move the generated .db from NOOP_HOME/build/ to a friendlier location
if [[ "$ENABLE_DB" == "1" ]]; then
    # emu names files by timestamp; find the newest .db in the build dir
    local_db="$(ls -t "$NOOP_HOME/build/"*.db 2>/dev/null | head -1)"
    if [[ -n "$local_db" ]]; then
        dest="${DB_DEST:-$LOG_DIR/${prog_name}_${ts}.db}"
        mv "$local_db" "$dest"
        echo "[run-emu] db saved : $dest"
    fi
fi

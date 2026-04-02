#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <linux-source-dir>"
  exit 1
fi

LINUX_DIR="$1"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$LINUX_DIR" ]]; then
  echo "Error: linux source dir not found: $LINUX_DIR"
  exit 1
fi

cd "$LINUX_DIR"

PATCH_FILES=("$PATCH_DIR"/[0-9][0-9][0-9][0-9]-*.patch)
if [[ ${#PATCH_FILES[@]} -eq 0 ]]; then
  echo "Error: no patch files found in $PATCH_DIR"
  exit 1
fi

declare -a TO_APPLY=()

is_semantically_applied() {
  local patch_file="$1"
  case "$(basename "$patch_file")" in
    0001-riscv-matrix-first-use-support.patch)
      [[ -f arch/riscv/include/asm/matrix.h ]] && \
      grep -q '^#define SR_MS' arch/riscv/include/asm/csr.h && \
      grep -q 'riscv_m_first_use_handler' arch/riscv/include/asm/matrix.h && \
      grep -q 'matrix\.o' arch/riscv/kernel/Makefile && \
      grep -q 'riscv_m_first_use_handler' arch/riscv/kernel/traps.c
      ;;
    *)
      return 1
      ;;
  esac
}

for PATCH_FILE in "${PATCH_FILES[@]}"; do
  if patch --forward --dry-run --silent --reject-file=- -l -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
    TO_APPLY+=("$PATCH_FILE")
    continue
  fi

  if patch --reverse --dry-run --silent -l -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "Already applied: $PATCH_FILE"
    continue
  fi

  if is_semantically_applied "$PATCH_FILE"; then
    echo "Already applied (semantic check): $PATCH_FILE"
    continue
  fi

  echo "Error: patch cannot be applied cleanly (likely partially applied or source mismatch): $PATCH_FILE" >&2
  echo "Detail from dry-run:" >&2
  patch --forward --dry-run --reject-file=- -l -p1 < "$PATCH_FILE" || true
  exit 1
done

for PATCH_FILE in "${TO_APPLY[@]}"; do
  patch --forward --reject-file=- -l -p1 < "$PATCH_FILE"
  echo "Applied: $PATCH_FILE"
done

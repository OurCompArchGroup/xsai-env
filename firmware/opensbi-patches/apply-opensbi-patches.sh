#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <opensbi-source-dir>"
  exit 1
fi

OPENSBI_DIR="$1"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$OPENSBI_DIR" ]]; then
  echo "Error: OpenSBI source dir not found: $OPENSBI_DIR"
  exit 1
fi

cd "$OPENSBI_DIR"

PATCH_FILES=("$PATCH_DIR"/[0-9][0-9][0-9][0-9]-*.patch)
if [[ ${#PATCH_FILES[@]} -eq 0 ]]; then
  echo "Error: no patch files found in $PATCH_DIR"
  exit 1
fi

declare -a TO_APPLY=()

is_semantically_applied() {
  local patch_file="$1"
  case "$(basename "$patch_file")" in
    0001-lib-sbi-allow-xsai-ame-custom-csrs.patch)
      grep -q 'mstateen_val |= SMSTATEEN0_CS;' lib/sbi/sbi_hart.c && \
      grep -q 'csr_write(CSR_SSTATEEN0, SMSTATEEN0_CS);' lib/sbi/sbi_hart.c
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

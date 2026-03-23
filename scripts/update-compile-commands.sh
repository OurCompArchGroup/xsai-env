#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  update-compile-commands.sh [--append] [--db PATH] -- <build command...>

Examples:
  ./scripts/update-compile-commands.sh --db local/compile_commands.json -- make firmware
  ./scripts/update-compile-commands.sh --append --db local/compile_commands.json -- make -C firmware/riscv-rootfs/apps/hello_xsai
EOF
}

append=0
db_path="local/compile_commands.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --append)
      append=1
      shift
      ;;
    --db)
      db_path="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Missing build command after --" >&2
  usage >&2
  exit 1
fi

command -v bear >/dev/null || {
  echo "bear is not installed or not in PATH" >&2
  exit 1
}

command -v python3 >/dev/null || {
  echo "python3 is required to deduplicate compile_commands.json" >&2
  exit 1
}

db_dir="$(dirname "$db_path")"
mkdir -p "$db_dir"

temp_db="$(mktemp "${TMPDIR:-/tmp}/compile_commands.XXXXXX.json")"
trap 'rm -f "$temp_db"' EXIT

if [[ "$append" == "1" && -f "$db_path" ]]; then
  cp "$db_path" "$temp_db"
  bear --append --output "$temp_db" -- "$@"
else
  bear --output "$temp_db" -- "$@"
fi

python3 - "$temp_db" "$db_path" <<'PY'
import json
import os
import sys

src_path, dst_path = sys.argv[1], sys.argv[2]

with open(src_path, 'r', encoding='utf-8') as source_file:
    entries = json.load(source_file)

deduped = {}
for entry in entries:
    directory = entry.get('directory', '')
    file_path = entry.get('file')
    if not file_path:
        continue
    if os.path.isabs(file_path):
        key = os.path.normpath(file_path)
    else:
        key = os.path.normpath(os.path.join(directory, file_path))
    deduped.pop(key, None)
    deduped[key] = entry

result = list(deduped.values())

os.makedirs(os.path.dirname(dst_path) or '.', exist_ok=True)
tmp_path = dst_path + '.tmp'
with open(tmp_path, 'w', encoding='utf-8') as output_file:
    json.dump(result, output_file, indent=2)
    output_file.write('\n')
os.replace(tmp_path, dst_path)

print(f'wrote {len(result)} entries to {dst_path}')
PY
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/scripts/build_vivado_project.sh" --template "${SCRIPT_DIR}/kmh_mini_ai_raw_bigddr8g_0522" "$@"

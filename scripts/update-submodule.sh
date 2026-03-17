#!/usr/bin/env bash
# update-submodule.sh
# Updates submodules listed in UPDATE_LIST by reading path/url/branch
# directly from .gitmodules. Edit .gitmodules to change targets.
#
# Usage:
#   bash scripts/update-submodule.sh           # update all in whitelist
#   bash scripts/update-submodule.sh NEMU XSAI # update specific ones

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# ── Whitelist ────────────────────────────────────────────────────────────────
# Names must match the submodule name (first field in [submodule "NAME"])
# Add/remove entries here to control what gets updated.
UPDATE_LIST=(
    XSAI
    NEMU
    nexus-am
    llvm-project-ame
    qemu
)

# Override whitelist with CLI args if provided
if [[ $# -gt 0 ]]; then
    UPDATE_LIST=("$@")
fi

# ── Helper: parse a field from .gitmodules for a given submodule name ────────
gitmodules_get() {
    local name="$1" field="$2"
    git config -f "$ROOT/.gitmodules" "submodule.${name}.${field}" 2>/dev/null || echo ""
}

# ── Update one submodule ─────────────────────────────────────────────────────
update_one() {
    local name="$1"
    local path branch shallow

    path=$(gitmodules_get "$name" path)
    branch=$(gitmodules_get "$name" branch)
    shallow=$(gitmodules_get "$name" shallow)

    if [[ -z "$path" ]]; then
        echo "[update] WARNING: submodule '$name' not found in .gitmodules, skipping."
        return
    fi

    local depth_flag=""
    [[ "$shallow" == "true" ]] && depth_flag="--depth=1"

    echo "[update] ── $name  (path=$path  branch=${branch:-(default)}  shallow=${shallow:-false})"

    cd "$ROOT/$path"

    if [[ -n "$branch" ]]; then
        git fetch $depth_flag origin "$branch"
        git checkout "$branch"
        # Only pull --rebase for non-shallow (shallow histories can't rebase cleanly)
        [[ -z "$depth_flag" ]] && git pull --rebase || true
    else
        # No branch pinned: just update to whatever the parent repo has locked
        git fetch $depth_flag origin
    fi

    cd "$ROOT"
    echo "[update] ✓ $name"
}

# ── Main ─────────────────────────────────────────────────────────────────────
echo "[update] Updating submodules: ${UPDATE_LIST[*]}"
echo ""

for name in "${UPDATE_LIST[@]}"; do
    update_one "$name"
done

echo ""
echo "[update] Refreshing VERSIONS..."
bash "$ROOT/scripts/update-versions.sh"

echo "[update] Done."

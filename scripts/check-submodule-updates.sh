#!/usr/bin/env bash
# check-submodule-updates.sh
#
# Two functions:
#   check_submodule_updates [root]
#       Instantly compares local HEAD vs already-fetched origin/<branch>.
#       No network I/O — safe to call from .envrc without blocking.
#
#   fetch_submodules_bg [root]
#       Fires off background fetches for all tracked submodules (detached
#       from the shell, survives after direnv exits).  Call this manually
#       or from a cron/alias when you want to refresh the remote refs.
#
# Typical .envrc usage:
#   source "${XS_PROJECT_ROOT}/scripts/check-submodule-updates.sh"
#   check_submodule_updates "$XS_PROJECT_ROOT"

# ── internal helper ────────────────────────────────────────────────────────────
_submodule_list() {
  # prints "path branch" pairs, one per line
  local root="$1" gitmodules="$1/.gitmodules"
  [[ -f "$gitmodules" ]] || return
  git -C "$root" config --file "$gitmodules" --get-regexp 'submodule\..*\.path' \
  | awk '{print $2}' \
  | while read -r path; do
      local subdir="$root/$path"
      [[ -d "$subdir/.git" || -f "$subdir/.git" ]] || continue
      # skip submodules marked with update=none
      local update_mode
      update_mode=$(git -C "$root" config --file "$gitmodules" \
                   --get "submodule.${path}.update" 2>/dev/null)
      [[ "$update_mode" == "none" ]] && continue
      local branch
      branch=$(git -C "$root" config --file "$gitmodules" \
               --get "submodule.${path}.branch" 2>/dev/null)
      if [[ -n "$branch" ]] && ! git -C "$subdir" rev-parse --verify -q "refs/remotes/origin/$branch^{commit}" >/dev/null 2>&1; then
        branch=""
      fi
      if [[ -z "$branch" ]]; then
        # not on a named branch (detached HEAD): try origin/HEAD → main → master
        branch=$(git -C "$subdir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
                 | sed 's|origin/||')
      fi
      if [[ -z "$branch" ]]; then
        for candidate in main master; do
          git -C "$subdir" rev-parse --verify "origin/$candidate" &>/dev/null \
            && branch="$candidate" && break
        done
      fi
      [[ -z "$branch" ]] && continue
      echo "$path $branch"
    done
}

# ── public: instant local check (no network) ──────────────────────────────────
check_submodule_updates() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  local has_update=0
  local rel_root
  if [[ -n "${XS_PROJECT_ROOT:-}" && "$root" == "$XS_PROJECT_ROOT"* ]]; then
    rel_root="${XS_PROJECT_ROOT}${root#$XS_PROJECT_ROOT}"
  else
    rel_root="${root/#$HOME/~}"
  fi

  while read -r path branch; do
    local subdir="$root/$path"
    local local_sha remote_sha behind
    local_sha=$(git -C "$subdir" rev-parse HEAD 2>/dev/null)
    remote_sha=$(git -C "$subdir" rev-parse --verify -q "refs/remotes/origin/$branch^{commit}" 2>/dev/null)
    [[ -z "$local_sha" || -z "$remote_sha" ]] && continue
    [[ "$local_sha" == "$remote_sha" ]] && continue

    read -r _ behind < <(git -C "$subdir" rev-list --left-right --count "HEAD...origin/$branch" 2>/dev/null)
    [[ -z "$behind" || "$behind" == "0" ]] && continue

    # Print header once before the first result
    if [[ "$has_update" == "0" ]]; then
      echo -e "\033[2m[submodule check] $rel_root\033[0m"
    fi

    echo -e "  \033[33m[submodule]\033[0m $path  \033[1m${behind} commit(s)\033[0m behind origin/$branch"
    has_update=1
  done < <(_submodule_list "$root")

  if [[ "$has_update" == "1" ]]; then
    echo -e "  \033[36mRun: git submodule update --remote <path>  (or: fetch_submodules_bg to refresh)\033[0m"
  fi
}

# ── public: background fetch (call manually, not from .envrc) ─────────────────
fetch_submodules_bg() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null)}"
  echo "[submodule] Starting background fetch..."
  (
    while read -r path branch; do
      local subdir="$root/$path"
      # use --depth=1 only for already-shallow repos to avoid corrupting rev-list counts
    local _is_shallow
    _is_shallow=$(git -C "$subdir" rev-parse --is-shallow-repository 2>/dev/null)
    if [[ "$_is_shallow" == "true" ]]; then
      timeout 30 git -C "$subdir" fetch --quiet --no-tags --depth=1 \
        origin "$branch" 2>/dev/null &
    else
      timeout 30 git -C "$subdir" fetch --quiet --no-tags \
        origin "$branch" 2>/dev/null &
    fi
    done < <(_submodule_list "$root")
    wait
    echo "[submodule] Background fetch done."
  ) &disown
}

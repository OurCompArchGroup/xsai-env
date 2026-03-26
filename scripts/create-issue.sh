#!/usr/bin/env bash

# Built for xsai-env alongside issue templates adapted from the XiangShan issue reporting flow:
# https://github.com/OpenXiangShan/XiangShan/tree/kunminghu-v3/.github/ISSUE_TEMPLATE

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_REPO="OurCompArchGroup/xsai-env"
REPO="$DEFAULT_REPO"
ISSUE_TYPE=""
TITLE=""
AREA=""
BUILD_CMD=""
RUN_CMD=""
GENERATE_REPORT=true
DRY_RUN=false
SUMMARY=""
EXPECTED=""
REPRODUCE=""
ADDITIONAL=""
LOG_SNIPPET=""

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local value="${!var_name}"
  if [[ -z "$value" ]]; then
    read -r -p "$prompt" value
    printf -v "$var_name" '%s' "$value"
  fi
}

repo_from_remote() {
  local remote_url path
  remote_url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  case "$remote_url" in
    git@github.com:*)
      path="${remote_url#git@github.com:}"
      path="${path%.git}"
      ;;
    https://github.com/*)
      path="${remote_url#https://github.com/}"
      path="${path%.git}"
      ;;
    *)
      path="$DEFAULT_REPO"
      ;;
  esac
  printf '%s\n' "$path"
}

issue_label() {
  case "$1" in
    bug) printf '%s\n' 'bug' ;;
    problem) printf '%s\n' 'problem' ;;
    feature) printf '%s\n' 'enhancement' ;;
    question) printf '%s\n' 'question' ;;
    *) printf '%s\n' '' ;;
  esac
}

repo_has_label() {
  local repo="$1"
  local label="$2"
  [[ -n "$label" ]] || return 1
  gh label list --repo "$repo" --limit 200 --json name --jq '.[].name' 2>/dev/null | grep -Fxq "$label"
}

collect_summary_block() {
  local title="$1"
  shift
  {
    printf '### %s\n\n' "$title"
    printf '```text\n'
    "$@" 2>&1 || true
    printf '\n```\n\n'
  }
}

build_issue_body() {
  local body_file="$1"
  local branch head status env_summary tool_summary buildrun_summary area_line report_note
  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  head="$(git -C "$ROOT" log -1 --oneline --no-abbrev-commit 2>/dev/null || true)"
  status="$(git -C "$ROOT" status --short 2>/dev/null || true)"
  area_line="${AREA:-Unspecified}"
  report_note='Not generated.'
  if [[ "$GENERATE_REPORT" == true && -f "$ROOT/bug-report.tar.gz" ]]; then
    report_note="Generated locally at $ROOT/bug-report.tar.gz. GitHub CLI cannot attach local files automatically, so upload it manually later if needed."
  fi

  {
    printf '## Summary\n\n'
    printf '%s\n\n' "$SUMMARY"

    case "$ISSUE_TYPE" in
      bug)
        printf '## Expected Behavior\n\n%s\n\n' "$EXPECTED"
        printf '## Steps To Reproduce\n\n%s\n\n' "$REPRODUCE"
        ;;
      problem)
        printf '## What Happened Before The Failure\n\n%s\n\n' "$REPRODUCE"
        ;;
      feature)
        printf '## Motivation\n\n%s\n\n' "$EXPECTED"
        printf '## Proposed Approach\n\n%s\n\n' "$REPRODUCE"
        ;;
      question)
        printf '## Context\n\n%s\n\n' "$REPRODUCE"
        ;;
    esac

    printf '## Metadata\n\n'
    printf -- '- Issue type: %s\n' "$ISSUE_TYPE"
    printf -- '- Area: %s\n' "$area_line"
    printf -- '- Branch: %s\n' "$branch"
    printf -- '- HEAD: %s\n' "$head"
    if [[ -n "$BUILD_CMD" ]]; then
      printf -- '- Build command: `%s`\n' "$BUILD_CMD"
    fi
    if [[ -n "$RUN_CMD" ]]; then
      printf -- '- Run command: `%s`\n' "$RUN_CMD"
    fi
    printf -- '- Report bundle: %s\n\n' "$report_note"

    collect_summary_block "Environment Summary" bash -lc "source '$ROOT/env.sh' >/dev/null 2>&1 || true; env | grep -E '^(XS_PROJECT_ROOT|NEMU_HOME|QEMU_HOME|AM_HOME|NOOP_HOME|LLVM_HOME|RISCV|RISCV_ROOTFS_HOME|QEMU_LD_PREFIX|IN_NIX_SHELL)=' | sort"
    collect_summary_block "Tool Versions" bash -lc "for tool in git make bash python3 gcc clang java mill nix direnv gh; do if command -v \"\$tool\" >/dev/null 2>&1; then echo \"[\$tool]\"; \"\$tool\" --version 2>&1 | head -n 2; echo; fi; done"
    collect_summary_block "Repository Status" bash -lc "printf 'status:\n'; git -C '$ROOT' status --short; printf '\nsubmodules:\n'; git -C '$ROOT' submodule status"
    if [[ -n "$LOG_SNIPPET" ]]; then
      printf '## Relevant Log Snippet\n\n```text\n%s\n```\n\n' "$LOG_SNIPPET"
    fi
    if [[ -n "$ADDITIONAL" ]]; then
      printf '## Additional Context\n\n%s\n' "$ADDITIONAL"
    fi
  } >"$body_file"
}

create_issue() {
  local body_file="$1"
  local label args=()
  label="$(issue_label "$ISSUE_TYPE")"
  if repo_has_label "$REPO" "$label"; then
    args+=(--label "$label")
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: issue body written to $body_file"
    return 0
  fi
  gh issue create --repo "$REPO" --title "$TITLE" --body-file "$body_file" "${args[@]}"
}

usage() {
  cat <<'EOF'
Usage: scripts/create-issue.sh [options]

Options:
  --type <bug|problem|feature|question>
  --title <title>
  --area <area>
  --summary <text>
  --expected <text>
  --details <text>
  --log-snippet <text>
  --additional <text>
  --build-cmd <command>
  --run-cmd <command>
  --repo <owner/name>
  --no-report
  --dry-run

The script prompts for any missing fields and creates a GitHub issue via `gh issue create`.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      ISSUE_TYPE="${2:-}"
      shift 2
      ;;
    --title)
      TITLE="${2:-}"
      shift 2
      ;;
    --area)
      AREA="${2:-}"
      shift 2
      ;;
    --summary)
      SUMMARY="${2:-}"
      shift 2
      ;;
    --expected)
      EXPECTED="${2:-}"
      shift 2
      ;;
    --details)
      REPRODUCE="${2:-}"
      shift 2
      ;;
    --log-snippet)
      LOG_SNIPPET="${2:-}"
      shift 2
      ;;
    --additional)
      ADDITIONAL="${2:-}"
      shift 2
      ;;
    --build-cmd)
      BUILD_CMD="${2:-}"
      shift 2
      ;;
    --run-cmd)
      RUN_CMD="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --no-report)
      GENERATE_REPORT=false
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_cmd gh
require_cmd git

if [[ "$DRY_RUN" == false ]] && ! gh auth status >/dev/null 2>&1; then
  echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' first." >&2
  exit 1
fi

REPO="${REPO:-$(repo_from_remote)}"
prompt_if_empty ISSUE_TYPE "Issue type (bug/problem/feature/question): "
case "$ISSUE_TYPE" in
  bug|problem|feature|question) ;;
  *)
    echo "Error: unsupported issue type '$ISSUE_TYPE'" >&2
    exit 1
    ;;
esac

prompt_if_empty TITLE "Title: "
prompt_if_empty AREA "Area: "
prompt_if_empty BUILD_CMD "Build command (optional): "
prompt_if_empty RUN_CMD "Run command (optional): "
prompt_if_empty SUMMARY "Summary: "

case "$ISSUE_TYPE" in
  bug)
    prompt_if_empty EXPECTED "Expected behavior: "
    prompt_if_empty REPRODUCE "Steps to reproduce: "
    ;;
  problem)
    prompt_if_empty REPRODUCE "What did you do before the failure?: "
    ;;
  feature)
    prompt_if_empty EXPECTED "Motivation: "
    prompt_if_empty REPRODUCE "Proposed approach: "
    ;;
  question)
    prompt_if_empty REPRODUCE "Relevant context: "
    ;;
esac

prompt_if_empty LOG_SNIPPET "Relevant log snippet (optional, one line or short paste): "
prompt_if_empty ADDITIONAL "Additional context (optional): "

if [[ "$GENERATE_REPORT" == true ]]; then
  "$ROOT/scripts/bug-report.sh" --basic --build-cmd "$BUILD_CMD" --run-cmd "$RUN_CMD" --note "$SUMMARY" >/dev/null
fi

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
build_issue_body "$BODY_FILE"
create_issue "$BODY_FILE"
# This script sets up the core XiangShan environment variables.
# It is the lightweight fallback for CI and for developers who do not use direnv.
# The richer direnv workflow lives in `.envrc` and additionally enables the Nix
# devshell, local overrides, and submodule freshness checks.

source "$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)/scripts/env-common.sh"
xsai_env_init

if [[ "${XSAI_ENV_QUIET:-0}" != "1" ]]; then
  xsai_env_print_summary
fi

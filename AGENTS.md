# Repository Agent Notes

## Preferred entrypoints
- Use the top-level `Makefile` from the repo root.
- Prefer the Nix workflow when possible: `make nix-shell`, `make nix-init`, `make nix-test`.
- Run `make init-force` before the first heavy build on a fresh checkout if you are not already using `make nix-init`.
- Use `make gsim` only when the task explicitly needs the latest `gsim` binary.

## Environment
- `.envrc` is the richer developer workflow: it enters the flake devshell, loads shared env, applies `.envrc.local`, and checks submodule freshness.
- `env.sh` is the lightweight fallback for CI and for users who do not use direnv.
- Global env no longer forces `CROSS_COMPILE`; only firmware/software flows should opt into cross compilation.
- `local/`, `build/`, `log/`, and `firmware/checkpoints/` are generated artifacts.

## Validation
- Start with `make -n <target>` for integration entrypoints.
- Prefer `make nix-smoke` for the fast reproducible smoke test.
- Use `make nix-test` for the heavier reproducible environment test.
- Use `make test` when you intentionally want to validate the non-direnv/manual environment path.
- Avoid full RTL rebuilds unless the task requires them; they are expensive.

## Agent workflow
- Prefer editing root scripts over duplicating logic in CI or Docker files.
- Keep CI, docs, and Nix entrypoints aligned with the top-level `Makefile` targets.
- When adding automation, favor deterministic inputs over `latest` downloads unless explicitly requested.

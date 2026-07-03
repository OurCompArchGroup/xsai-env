---
name: xsai-submodule-git-flow
description: Guide for developing and bumping xsai-env Git submodules. Use when a task modifies code inside submodules such as firmware/riscv-rootfs, qemu, NEMU, XSAI, nexus-am, firmware/LibCheckpoint, firmware/gcpt_restore, docs/CUTE-Design-Doc, or nested submodules; when updating gitlinks, running make versions, preparing submodule bump PRs, or deciding inside-out PR order for nested submodules.
---

# XSAI Submodule Git Flow

Use this skill whenever the work touches a Git submodule or updates a submodule pointer in `xsai-env`.

## Core rule

Separate the two commits:

- submodule code commit: lives in the owning submodule repository
- parent gitlink bump: lives in `xsai-env` and points at the submodule commit

Never leave the parent repo pointing at a local-only submodule commit. Other developers and CI must be able to fetch the target commit from the submodule remote.

## First checks

1. Read `.gitmodules` for the submodule path, remote URL, configured branch, `shallow`, and `update = none`.
2. Check current state:

```bash
git status --short
git submodule status --recursive
git diff --submodule=log
```

3. Classify the primary workstream using `docs/workstreams.md`.
4. If the change belongs in the submodule, open or link the issue/PR in that owning repository.
5. When opening issues or PRs, also use `xsai-issue-pr-flow` so template selection, title prefixes, branch naming, and PR body rules stay consistent.

## Normal submodule development

Work inside the submodule first:

```bash
git submodule update --init <path>
git -C <path> fetch origin
git -C <path> switch -c <type>/<issue>-topic origin/<configured-branch>
```

After edits and submodule-local validation:

```bash
git -C <path> status --short
git -C <path> add <paths>
git -C <path> commit -m "<type>(<scope>): <subject>"
git -C <path> push -u origin <branch>
```

Open the submodule PR first. Keep the root `xsai-env` PR as draft if it depends on an unmerged submodule PR.

## Parent gitlink bump

After the submodule commit is merged or otherwise stable and fetchable:

```bash
git -C <path> fetch origin
git -C <path> checkout <merged-submodule-sha>
git diff --submodule=log <path>
git add <path>
make versions
git add VERSIONS
git commit -m "bump(<component>): <reason>"
```

`make versions` is part of the standard root bump flow. If `VERSIONS` does not change when expected, inspect `scripts/update-versions.sh` and the current submodule state before committing.

### XSAI nested submodules

When updating the top-level `XSAI` gitlink, do not use an external recursive
submodule update to initialize or move XSAI's nested submodules. After checking
out the intended `XSAI` commit, run XSAI's own initialization target from inside
that submodule:

```bash
git -C XSAI fetch origin
git -C XSAI checkout <target-xsai-sha>
make -C XSAI init-force
git -C XSAI status --short
```

Use the resulting clean `XSAI` worktree as the parent gitlink target, then run
the normal root `make versions` flow.

The root bump PR must include:

- submodule path
- old SHA and new SHA
- linked submodule issue/PR
- reason the new commit is needed by `xsai-env`
- root-level validation, usually from `AGENTS.md` or `docs/workstreams.md`

## Rootfs issue-disabled exception

`firmware/riscv-rootfs` may use an `xsai-env` integration issue when the
rootfs repository cannot accept issues.

For this exception:

1. Commit and push the rootfs change to the rootfs remote first.
2. Create or link an `xsai-env` issue using `xsai-issue-pr-flow` title prefixes
   and template fields.
3. In the `xsai-env` issue, state that the code change lives in
   `firmware/riscv-rootfs`, rootfs issues are unavailable, and list the rootfs
   branch plus pushed commit SHA.
4. Update the root gitlink only after the rootfs commit is fetchable.
5. Run `make versions`, stage `VERSIONS`, and include both the issue and rootfs
   commit/PR in the parent PR body.

This exception does not apply to local-only rootfs commits.

## Nested submodules

Submit from the inside out.

Example for `XSAI/CUTE`:

1. Merge the code change in `XSAI/CUTE`.
2. Update the `XSAI/CUTE` gitlink in `XSAI`, validate, and merge the `XSAI` PR.
3. Update the top-level `XSAI` gitlink in `xsai-env`, run `make versions`, validate, and open the root bump PR.

Each layer should point to a committed, pushed, reviewable revision from the layer below.

## Avoid broad updates

Do not run broad submodule updates by default:

```bash
git submodule update --remote --recursive
```

Use explicit path updates instead. This repo has shallow submodules, non-default branches, and `update = none` entries, so broad remote updates can move unrelated dependencies.

## Useful root validation

- For docs-only or workflow-only bumps: `make test-smoke`
- For firmware/rootfs bumps: app-local build, then `make firmware` or `make run-qemu`
- For qemu bumps: `make qemu`, then the relevant `make run-qemu` or checkpoint phase
- For NEMU bumps: `make nemu`, then the intended NEMU workload/defconfig flow
- For XSAI bumps: narrow `make xsai` or `make run-emu-debug PAYLOAD=...` only when needed

Prefer the narrowest validation that proves the integration behavior.

---
name: xsai-rtl-debug
description: Guide for building and debugging the XSAI RTL emulator with difftest, waveform, and ChiselDB support. Use this when asked to investigate RTL failures, difftest mismatches, or to capture wave/db artifacts from the XSAI emu flow.
---

# XSAI RTL Debug

Use this skill when the task lives primarily in `XSAI/`, `XSAI/difftest/`, or the top-level RTL run wrappers.

The main RTL matrix-core hotspot in the current repo is `XSAI/CUTE/`.
Design documents for that block are available locally under `docs/CUTE-Design-Doc/`.

## What this skill is for

- Building the XSAI RTL emulator from the repo root
- Running workloads on `XSAI/build/emu`
- Turning difftest on against the NEMU reference `.so`
- Capturing FST waveform windows and ChiselDB snapshots
- Narrowing whether a failure is in RTL, the NEMU reference, or the payload itself

## Primary entrypoints

Prefer the repo-root wrappers first:

```bash
make xsai
make run-emu PAYLOAD=<payload>
make run-emu-debug PAYLOAD=<payload> DIFF=1 WAVE_BEGIN=<cycle> WAVE_END=<cycle>
```

The top-level wrapper around `XSAI/build/emu` lives in `scripts/run-emu.sh`.

## Build and run flow

1. Build the RTL emulator with `make xsai`.
2. Use `make run-emu PAYLOAD=<payload>` for a normal run.
3. Use `make run-emu-debug` when you need waveform or database artifacts.

Example:

```bash
make run-emu-debug \
  PAYLOAD=/path/to/workload-or-checkpoint \
  DIFF=1 \
  WARMUP=20000000 \
  MAX_INSTR=40000000 \
  WAVE_BEGIN=20000000 \
  WAVE_END=40000000
```

Important knobs:

- `DIFF=1` enables difftest against the NEMU reference
- `FORK=1` skips waveform dumping and keeps DB-only debugging faster
- `DB_SELECT=lifetime` is the current default for ChiselDB capture

## Difftest expectations

- The default diff reference is `XSAI/ready-to-run/riscv64-nemu-interpreter-so`.
- If the mismatch may actually be in the reference build, validate the intended NEMU defconfig and `.so` separately.
- Treat difftest bugs as potentially cross-subsystem: RTL, NEMU semantics, payload contents, or boot/runtime assumptions can all be at fault.

## Waveform and DB capture

Use `make run-emu-debug` instead of retyping raw `build/emu` flags whenever possible.

Typical modes:

- Wave + DB:

```bash
make run-emu-debug PAYLOAD=<payload> DIFF=1 WAVE_BEGIN=<b> WAVE_END=<e>
```

- DB only, faster:

```bash
make run-emu-debug PAYLOAD=<payload> DIFF=1 FORK=1
```

Artifacts are routed through `log/` and the `XSAI/build/` directory by `scripts/run-emu.sh`.

## How to narrow failures

1. Confirm the payload path and boot mode are the intended ones.
2. Reproduce with difftest enabled if correctness is the problem.
3. If the issue is localized in time, rerun with a narrow `WARMUP` / `MAX_INSTR` window.
4. If you need signal-level evidence, capture wave + DB around the failing window.
5. If the same payload also fails in QEMU or NEMU standalone mode, suspect the payload or firmware stack before blaming RTL.
6. If only difftest disagrees, inspect whether the disagreement comes from RTL state, NEMU semantics, or unsupported debug assumptions.

## Related subsystems

Read `docs/workstreams.md` when the issue may cross subsystem boundaries. The most common coupled areas are:

- `NEMU/` reference behavior
- firmware payloads and checkpoint restorer binaries
- memory-map or DTB assumptions
- matrix ISA/toolchain changes that alter the executed instruction stream

If the task is specifically about the matrix core implementation rather than general waveform/debug flow, prefer the dedicated `xsai-cute-rtl` skill.

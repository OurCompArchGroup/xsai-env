---
name: xsai-xuantie-to-zames
description: Migrate XSAI RISC-V matrix-extension assembly from the Xuantie 0.6 dialect (e.g. mlae8, mmacc.w.b, msyncreset, llvm-mc -mattr=+zame,+matrix-xuantie-0.6) to the Zames proposal-12 spec (mla/mlb/mlc, single mmacc, msetcfg/mcfg, proposal-12 whole-register rs2 stride, msyncregreset sync0..sync15, -march=...zames_zmasync via clang). Use when porting AM or rootfs matrix tests/apps under nexus-am/apps, nexus-am/tests, or firmware/riscv-rootfs/apps, or when old-dialect AME code fails to assemble with the current toolchain.
---

# Xuantie 0.6 -> Zames proposal-12 migration

The Zames spec drops type encoding from instruction mnemonics. Element width and
signedness are programmed into `mcfgN` configuration registers and shared across
loads, stores, and `mmacc`. For the common fixed `i8*i8->i32` kernels, program
the tile and accumulator register types once in the matrix init path and reuse
that state; reprogram `mcfgN` only when the physical matrix register's type or
signedness changes. The accompanying Zmasync extension renames sync primitives
and swaps `macquire` operand order.

## Toolchain

| Aspect | Xuantie 0.6 | Zames |
|---|---|---|
| llvm-mc attrs | `+zame,+matrix-xuantie-0.6` | `+zames,+zmasync` |
| Driving the assembler | custom `llvm-mc` rule in Makefile | `clang` (set `MARCH = rv64gc..._zames_zmasync`) |
| MARCH suffix | n/a (used llvm-mc directly) | append `_zames_zmasync` |

Drop the `llvm-mc-rule` block in the per-app Makefile and let `Makefile.app`
drive `clang -c matop.S`. This also fixes the `cannot link object files with
different floating-point ABI` linker error caused by llvm-mc emitting an
ABI-less object next to `lp64d` C objects.

For Linux/rootfs apps that compile inline asm with clang, use the same extension
names in `-march`, for example `rv64g_v_zvfh_zames_zmasync_zvl128b_zicbop_zihintpause`,
and pass `--mattr=+zames,+zmasync` to `llvm-objdump`.

## Mnemonic Rename

| Xuantie 0.6 | Zames | Notes |
|---|---|---|
| `msettilem/n/k`, `msettile{m,n,k}i` | unchanged | |
| `mlae8` / `mlbe8` / `mlce32` | `mla` / `mlb` / `mlc` | width comes from `mcfg(md)` |
| `msce32` and friends | `msc` or `msa`/`msb` | width comes from `mcfg(ms3)` |
| transposed loads | `mlat`/`mlbt`/`mlct`, `msat`/`msbt`/`msct` | |
| whole-register | `mla.whole md, (rs1), rs2` etc. | proposal-12 keeps `rs2` as the row stride for raw-register save/restore |
| `mmacc.w.b`, `mmaccu.w.b`, `mmaccsu.w.b`, `mmaccus.w.b` | `mmacc md, ms2, ms1` | sign/width from `mcfg(ms1)` and `mcfg(ms2)`; operand order is ms2 before ms1 |
| `mzero` family | `mzero md` | no type suffix |
| n/a | `minit` | sets `mstatus.MS = 01` |

`mmacc md, ms2, ms1` semantics: `md = md + ms1 * ms2`. When porting
`mmacc.w.b acc, trA, trB` (acc += trA * trB), write `mmacc acc, trB, trA`.

## mcfg Programming

Every tile and accumulator register used by a load/store/`mmacc` must have its
`mcfgN` programmed first. `msetcfg mcfgN, rs1` writes `x[rs1]` into the selected
mcfg. The 3-bit `mcfg_d1` selector reuses the matrix-register numbering:
`mcfg0..mcfg3` configure `tr0..tr3`, and `mcfg4..mcfg7` configure
`acc0..acc3`. `mgetcfg rd, mcfgN` reads it back.

`type_code[3:0]` when `table_sel = 0`:

| code | type | code | type |
|---|---|---|---|
| `0000` | int4 | `1000` | fp8e4m3 |
| `0001` | uint4 | `1001` | fp16 |
| `0010` | int8 | `1010` | bf16 |
| `0011` | uint8 | `1011` | tf32 |
| `0100` | int32 | `1100` | fp32 |
| `0101` | nvfp4 | `1101` | fp2pack4 |
| `0110` | mxfp4 | `1110` | fp2pack5 |
| `0111` | fp8e5m2 | `1111` | reserved |

Default fixed-kernel init pattern:

```asm
.equ MCFG_INT8,  0x02
.equ MCFG_UINT8, 0x03
.equ MCFG_INT32, 0x04

.macro SETCFG mcfg_sel, type_code
    li      t6, \type_code
    msetcfg \mcfg_sel, t6
.endm

    # Common proposal-12 default for i8*i8->i32 kernels:
    # tr0..tr3 are int8, acc0..acc3 are int32.
    SETCFG  mcfg0, MCFG_INT8
    SETCFG  mcfg1, MCFG_INT8
    SETCFG  mcfg2, MCFG_INT8
    SETCFG  mcfg3, MCFG_INT8
    SETCFG  mcfg4, MCFG_INT32
    SETCFG  mcfg5, MCFG_INT32
    SETCFG  mcfg6, MCFG_INT32
    SETCFG  mcfg7, MCFG_INT32
```

For sign-mixed multiplies, the operand `mcfg` dictates signedness, not the
mnemonic. To translate the four old mmacc variants when A is in `tr_a` and B is
in `tr_b` (so `ms1 = tr_a`, `ms2 = tr_b`):

| old mnemonic | mcfg(tr_a) | mcfg(tr_b) | new |
|---|---|---|---|
| `mmacc.w.b` | int8 | int8 | `mmacc acc, tr_b, tr_a` |
| `mmaccu.w.b` | uint8 | uint8 | `mmacc acc, tr_b, tr_a` |
| `mmaccsu.w.b` | int8 | uint8 | `mmacc acc, tr_b, tr_a` |
| `mmaccus.w.b` | uint8 | int8 | `mmacc acc, tr_b, tr_a` |

If a test intentionally reuses the same physical tile register with different
signedness across phases, re-issue `msetcfg` before the phase that changes that
register's type. Do not re-issue `msetcfg` in the hot loop of a fixed-shape
kernel just because a matrix operation is about to run.

For C code, keep per-instruction inline-asm helpers as small macros in a header
so the matrix register names remain explicit, but implement high-level kernels
as C functions rather than large `do { ... } while (0)` macros.

## Proposal-12 Whole-Register Note

Proposal-12 whole-register load/store keeps the normal third operand:

```asm
mla.whole tr0,  (rs1), rs2
mlb.whole tr1,  (rs1), rs2
mlc.whole acc0, (rs1), rs2
msa.whole tr0,  (rs1), rs2
msb.whole tr1,  (rs1), rs2
msc.whole acc0, (rs1), rs2
```

For proposal-12 in this tree, `rs2` is the inter-row byte stride. Passing `x0`
does not mean "contiguous whole image"; it collapses all rows onto the base row.
Proposal-14 later changed whole-register access to a stride-less form with `rs2`
forced to `x0`, but that is not the target for this environment.

## Zmasync Sync Primitives

| Xuantie | Zames Zmasync | Notes |
|---|---|---|
| `msyncreset tok1` | `msyncregreset sync1` | rename plus register naming `sync0..sync15` |
| `mrelease tok1` | `mrelease sync1` | rename only |
| `macquire a0, tok1` | `macquire sync1, a0` | operand order is sync register first, then rs1 threshold |
| n/a | `mfence` | visibility barrier from non-matrix code into the matrix engine |

Encodings live under `func3=100` in the custom-1 opcode space (`0101011`).
LLVM requires `+zmasync` in addition to `+zames`.

## mstatus / MS Bit

MS occupies bits `[26:25]` in `mstatus`/`sstatus`. In AM / machine-mode tests,
the Xuantie matrix-init boilerplate still works:

```asm
lui   a0, 8194
addiw a0, a0, 512
csrs  mstatus, a0
```

This also toggles FS and VS so vector/FP state is enabled. Do not copy this
`csrs mstatus` sequence into Linux userspace rootfs apps; userspace must rely on
the kernel/runtime environment enabling the required state. Zames also adds the
`minit` instruction as a shorthand for forcing MS = Initial.

## Capability Discovery

`misa` no longer carries Zames. Discover via the device tree:

```dts
riscv,isa-extensions = "zames";
riscv,matrix-isa-caps = "i8i8i32", "bf16bf16fp32", "fp8e4m3fp8e4m3fp32";
```

The capability string follows `<input_a><input_b><output_c>`. Integer tokens
are `i<W>` / `u<W>`; float tokens use direct names such as `bf16`, `fp32`, and
`fp8e4m3`. Programming an unsupported `mcfg` raises an illegal instruction
exception at `msetcfg` time.

## Reference Ports

Use `nexus-am/apps/ame-mmacc/` as the main assembly reference. It mirrors the
old Xuantie MMACC coverage with expected results `131`, `4145283`, `-16253`,
and `-32637`, but uses proposal-12 end to end.

Use `nexus-am/tests/ame0.6/` and `firmware/riscv-rootfs/apps/hello_xsai/` as
the C inline-asm references. They keep instruction helpers in headers and call
a one-time AME init helper before the hot GEMM path.

For whole-register behavior, use `nexus-am/apps/ame-ls-whole/`; it documents
the proposal-12 `rs2` stride semantics and calls out the proposal-14 difference.

## Quick Conversion Checklist

1. Replace the custom `llvm-mc-rule` in the Makefile with `MARCH = ..._zames_zmasync`.
2. For every typed load/store, drop the type suffix: `mlae8 -> mla`, etc.
3. Insert `msetcfg mcfgN, rsN` for each tile/acc used before first access.
4. For the fixed i8/i32 path, prefer one matrix-init helper that sets
   `mcfg0..mcfg3 = int8` and `mcfg4..mcfg7 = int32`.
5. Collapse the four `mmacc*` mnemonics into `mmacc md, ms2, ms1`, swapping the
   operand order and encoding signedness in `mcfg(ms1)` / `mcfg(ms2)`.
6. Change `msyncreset` to `msyncregreset`, use `sync0..sync15`, and change
   `macquire` to `macquire sync, rs1`.
7. For whole-register load/store, keep the proposal-12 `rs2` stride operand.
8. Build through the owning Makefile and inspect disassembly with
   `llvm-objdump --mattr=+zames,+zmasync`.

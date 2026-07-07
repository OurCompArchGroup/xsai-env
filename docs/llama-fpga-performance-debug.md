# llama.cpp FPGA Performance Debug Guide

This note summarizes how to locate the llama.cpp hot path on XSAI FPGA, how to
separate AME matmul bottlenecks from CPU overhead, and how to decide whether a
run is limited by the 8 TOPS matrix engine or by the approximately 6 GB/s
single-channel DDR4 bandwidth.

## Current Workload Path

The default FPGA llama path is:

1. `make firmware` builds the rootfs image and the llama.cpp binaries.
2. `make run-fpga` boots the FPGA image and enters
   `firmware/riscv-rootfs/rootfsimg/xsai-workloads.sh`.
3. `run_llama_fake_bench_suite` runs:

   ```sh
   /bin/llama-bench --fake-like /root/stories15M-q8_0.gguf.om \
       -t 1 -p 128 -n 128 -r 1 \
       --estimate-layers 1 \
       --estimate-decode-tokens 1 \
       --no-warmup
   ```

The printed backend column may still say `CPU`. That does not prove AME is not
used: the current AME path is implemented as a ggml CPU backend extra buffer
type named `RISCV_AME`. Use AME logs or counters to confirm actual dispatch.

## Code Hot Path

The important source files are:

- `firmware/riscv-rootfs/apps/llama.cpp/repo/tools/llama-bench/llama-bench.cpp`
  - reads `rdcycle` and `rdinstret`;
  - prints `cyc`, `ipc`, and derived `t/s`;
  - implements `--estimate-layers`;
  - supports `LLAMA_BENCH_PRINT_LAYERS_01=1` to dump layer-0/layer-1 graph
    nodes and tensor shapes.
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/src/ggml-cpu/arch/riscv/ame/ame-backend.cpp`
  - dispatches eligible `GGML_OP_MUL_MAT` nodes to AME;
  - supports `GGML_AME_LOG=1`;
  - accepts only `src0=Q8_0`, `src1=F32`, and shapes accepted by
    `ggml_ame_can_use`.
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/src/ggml-cpu/arch/riscv/ame/ame.h`
  - current AME eligibility is `M >= 128`, `N >= 128`, `K % 32 == 0`.
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/src/ggml-cpu/arch/riscv/ame/ame-matmul.c`
  - performs Q8/F32 tiling, activation quantization, AME tile calls, and
    int32-to-float output scaling.
- `firmware/riscv-rootfs/apps/llama.cpp/repo/ggml/src/ggml-cpu/arch/riscv/ame/ame_gemm_tile_i8_i32_bT.c`
  - issues one 128x128x64 AME tile:
    `MLAE8`, `MLBE8`, `MQMA`, `MSCE32`, `mrelease`, `macquire`.

For prompt processing with `-p 128`, most useful LLM work should be dense
projection/FFN matmul. For decode with one token, many shapes have `N < 128`
and will not use the current AME path, so decode can be CPU dominated even when
prefill uses AME.

## First Checks On FPGA

Run the same benchmark with AME dispatch logging enabled. These knobs are
written into `/etc/xsai-init.conf`, so rebuild the firmware image before
running the FPGA payload:

```sh
make firmware XSAI_GGML_AME_LOG=1
make run-fpga
```

Look for messages from `ame-backend.cpp`:

- `dispatching to packed Q8_64 kernel`: expected fast path.
- `dispatching to baseline Q8_0 kernel`: AME is used, but the older packing
  path is avoided.
- fallback messages from `supports_op`: the node stayed on CPU.

For graph shape visibility:

```sh
make firmware XSAI_GGML_AME_LOG=1 XSAI_LLAMA_BENCH_PRINT_LAYERS_01=1
make run-fpga
```

This prints the layer-0/layer-1 tensor names, op types, element types, and
dimensions. The first thing to verify is that the large `GGML_OP_MUL_MAT`
nodes have `Q8_0 x F32`, `M >= 128`, `N >= 128`, and `K` divisible by 32.

To isolate prompt and decode:

```sh
make firmware \
  XSAI_GGML_AME_LOG=1 \
  XSAI_LLAMA_FAKE_BENCH_ARGS="-t 1 -p 128 -n 0 -r 1 --estimate-layers 1 --no-warmup"
make run-fpga

make firmware \
  XSAI_GGML_AME_LOG=1 \
  XSAI_LLAMA_FAKE_BENCH_ARGS="-t 1 -p 0 -n 128 -r 1 --estimate-layers 1 --estimate-decode-tokens 1 --no-warmup"
make run-fpga
```

Prompt is the right path for checking matrix throughput. Decode is the right
path for checking whether the AME eligibility threshold is leaving small-N work
on the scalar/RVV CPU path.

## Interpreting `llama-bench` Numbers

`llama-bench` prints real cycle and instruction counters from `rdcycle` and
`rdinstret`. The `t/s` and `avg_ns` fields are derived from a hard-coded
2 GHz assumption in `llama-bench.cpp`:

```c++
LLAMA_BENCH_ASSUMED_CPU_FREQ_HZ = 2000000000ull
```

Therefore:

```text
tokens_per_second_real = tokens * fpga_cpu_freq_hz / cycles
seconds_real           = cycles / fpga_cpu_freq_hz
```

The sample row:

```text
pp128 e[0,1)/6, cyc = 341M, t/s = 750.8
```

means `llama-bench` estimated the full 6-layer prompt from the `[0,1)` output
layer window. At 2 GHz, `128 tokens / (341M cycles / 2GHz) = 750.7 tok/s`.
If the FPGA CPU clock is not 2 GHz, keep the cycle count and rescale the token
rate.

## Confirming The Hotspot

Use this sequence:

1. Enable `LLAMA_BENCH_PRINT_LAYERS_01=1` and identify the large
   `GGML_OP_MUL_MAT` nodes.
2. Enable `GGML_AME_LOG=1` and confirm those nodes dispatch to the packed
   AME Q8_64 kernel.
3. Compare prompt-only and decode-only runs.
4. Add or enable AME-side counters for:
   - number of AME matmul calls;
   - packed vs baseline calls;
   - fallback count and fallback reason;
   - total `M * N * K` MACs;
   - cycles in `ggml_backend_ame_mul_mat`;
   - cycles in packing/activation quantization;
   - cycles around `ggml_ame_gemm_tile_i8_i32_bT`;
   - cycles in int32 accumulator scale-out to F32.

Without those AME-side counters, the benchmark can prove that the workload is
slow or fast, but it cannot prove whether time is spent in matrix compute,
packing, CPU scale-out, graph overhead, or non-matmul operators.

## Hardware-Limit Math

The current CUTE matrix engine configuration used by both minimal and default
matrix configs is the 128x128x64 INT8 tile shape.

One AME tile computes:

```text
MACs = 128 * 128 * 64 = 1,048,576 MAC
Ops  = 2 * MACs       = 2,097,152 ops
```

The 8 TOPS label corresponds to approximately:

```text
2048 MAC/cycle = 4096 ops/cycle
4096 ops/cycle * 2 GHz = 8.192 TOPS
```

So the pure compute lower bound for one full tile is:

```text
1,048,576 MAC / 2048 MAC/cycle = 512 cycles
```

Minimum explicit AME tile traffic is:

```text
A tile read  = 128 * 64 * 1B = 8 KiB
B tile read  = 128 * 64 * 1B = 8 KiB
C tile write = 128 * 128 * 4B = 64 KiB
minimum      = 80 KiB
```

At 6 GB/s DDR bandwidth and 2 GHz, just moving 80 KiB costs:

```text
81920 B / 6e9 B/s * 2e9 cycle/s = about 27.3K cycles
```

Current software also reads the int32 accumulator tile and writes F32 output
during scale-out, adding roughly another 128 KiB per full output tile:

```text
tile_c CPU read = 64 KiB
dst F32 write   = 64 KiB
practical floor = about 208 KiB per 128x128x64 tile, before metadata/scale traffic
```

At 6 GB/s and 2 GHz, 208 KiB costs about 71K cycles. That is far larger than
the 512-cycle compute lower bound. Therefore, if these tile buffers are really
served from FPGA DDR, this kernel is bandwidth-bound, not 8-TOPS-bound.

The roofline ridge point is:

```text
8e12 ops/s / 6e9 B/s = 1333 ops/B
```

The current tile arithmetic intensity is only:

```text
2,097,152 ops / 80 KiB  = 25.6 ops/B  best case
2,097,152 ops / 208 KiB = 9.85 ops/B  with CPU scale-out traffic
```

That is much lower than 1333 ops/B. Reaching 8 TOPS is impossible if the main
tile movement goes through 6 GB/s DDR for every tile. The optimization target
should first be reducing DDR traffic, improving reuse, and removing CPU-side
scale-out traffic from the critical path.

## Achieved TOPS And Bandwidth Formulas

For each benchmark window:

```text
elapsed_s = cycles / fpga_cpu_freq_hz
ops       = sum_over_AME_matmul_nodes(2 * M * N * K)
TOPS      = ops / elapsed_s / 1e12
```

For AME tile counters:

```text
bytes_min = tiles * 80 KiB
bytes_sw  = tiles * 208 KiB + packing_and_scale_metadata_bytes
GBps_min  = bytes_min / elapsed_s / 1e9
GBps_sw   = bytes_sw  / elapsed_s / 1e9
```

Interpretation:

- `TOPS` near 8 and `GBps` below 6: compute-bound and close to matrix peak.
- `GBps` near 6 and `TOPS` far below 8: DDR bandwidth-bound.
- both far below peak: software overhead, cache misses, AME underfill,
  fallback-to-CPU, or synchronization overhead.
- high fallback count: graph/tensor placement or shape eligibility issue.

## Likely Bottlenecks In The Current Kernel

The current AME Q8 path has several software-visible costs:

1. F32 activations are quantized to Q8 tiles before AME compute.
2. Packed Q8 weights are preferred, but the kernel still copies tiles into
   AME tile buffers.
3. AME stores int32 accumulator tiles.
4. CPU code scales int32 accumulators back to F32 output.
5. Decode and small matrix shapes often miss `M >= 128` and `N >= 128`, so they
   stay on CPU.

For prefill, start with packed Q8 dispatch rate, tile-copy bandwidth, and
scale-out cycles. For decode, start with shape eligibility and small-N fallback.

## Packed-B Panel Hang Snapshot: 1B Fake Bench

This snapshot records the current reproducible FPGA hang found on 2026-05-16.
The important point is that the synthetic `ame_panel_probe` workload is not the
primary evidence. The faithful reproducer is the real `llama-bench --fake-like`
path using the 1B metadata-only model.

### Timeout Behavior

`FPGA_TIMEOUT` is working as a host-side UART observation timeout. Runs with
`FPGA_TIMEOUT=900` and `FPGA_TIMEOUT=300` both exited with:

```text
[fpga] UART observation window expired after <N>s; workload may still be running
make: *** [Makefile:332: run-fpga] Error 124
```

This timeout does not prove that the FPGA workload has stopped. It only bounds
the local UART streaming window.

### Faithful Minimal Reproducer

Build a payload that runs only the 1B fake-like benchmark, skips the smaller
model and backend precheck, and enables AME/panel progress logs:

```sh
source env.sh
make firmware \
  XSAI_INIT_MODE=ci \
  XSAI_WORKLOAD=llama-fake-bench-suite \
  XSAI_AUTO_EXIT=1 \
  XSAI_DROP_SHELL=0 \
  XSAI_RUN_AFTER_WORKLOAD=1 \
  XSAI_DUMP_THP=0 \
  XSAI_TRACE_WORKLOAD=1 \
  XSAI_LLAMA_TEST_BACKEND_OPS=0 \
  XSAI_LLAMA_FAKE_BENCH_MODELS=/root/llama3.2_1b_q8.gguf.om \
  XSAI_GGML_AME_LOG=1 \
  XSAI_GGML_AME_PANEL_LOG=1 \
  XSAI_GGML_AME_PANEL_PROGRESS_LOG=1 \
  XSAI_AME_USE_PACKED_B_PANEL=1 \
  XSAI_AME_SKIP_TILE_C_ZERO=1 \
  XSAI_AME_SKIP_TILE_B_ZERO=1

make run-fpga FPGA_TIMEOUT=900
```

The workload command inside the guest is:

```sh
/bin/llama-bench --fake-like /root/llama3.2_1b_q8.gguf.om \
  -t 1 -p 128 -n 0 -r 1 --estimate-layers 1 -fa 0 --no-warmup
```

This is the current smallest faithful reproducer because it preserves the real
llama graph/backend setup while removing unrelated precheck and small-model
work.

### Observed Stop Point

`stories15M` completes. The 1B-only workload reaches AME execution and the
packed-B panel branch. The following shapes complete:

```text
M=2048 N=128 K=2048 nb64=32 panel_bytes=262144
M=512  N=128 K=2048 nb64=32 panel_bytes=262144
M=8192 N=128 K=2048 nb64=32 panel_bytes=262144
```

The hang reproduces at:

```text
M=2048 N=128 K=8192 nb64=128 panel_bytes=1048576
```

The panel-B packing itself completes:

```text
[AME_PANEL] ame64 packed_b_panel: M=2048 N=128 K=8192 nb64=128 panel_bytes=1048576
[AME_PANEL] ame64 packed_b_panel: j0=0 jmax=128 packed
```

With sparse inner-loop progress logging enabled, the last visible lines in the
1B faithful reproducer were:

```text
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 begin
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=0/128
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=8/128
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=16/128
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=24/128
```

There was no `kb=32/128`, no `i0=0 done`, and no `j0=0 done` before the UART
observation window expired. This narrows the faithful 1B failure to the first
output tile (`i0=0`) in the K accumulation loop, shortly after `kb=24/128`.

### Standalone Shape Check

A smaller standalone workload exists:

```sh
make firmware \
  XSAI_INIT_MODE=ci \
  XSAI_WORKLOAD=llama-ame-k8192-matmul \
  XSAI_AUTO_EXIT=1 \
  XSAI_DROP_SHELL=0 \
  XSAI_RUN_AFTER_WORKLOAD=1 \
  XSAI_DUMP_THP=0 \
  XSAI_TRACE_WORKLOAD=1 \
  XSAI_GGML_AME_LOG=1 \
  XSAI_GGML_AME_PANEL_LOG=1 \
  XSAI_GGML_AME_PANEL_PROGRESS_LOG=1 \
  XSAI_AME_USE_PACKED_B_PANEL=1 \
  XSAI_AME_SKIP_TILE_C_ZERO=1 \
  XSAI_AME_SKIP_TILE_B_ZERO=1 \
  XSAI_AME_M=2048 \
  XSAI_AME_N=128 \
  XSAI_AME_K=8192 \
  XSAI_AME_REPEAT=1

make run-fpga FPGA_TIMEOUT=300
```

This runs:

```sh
/bin/test-backend-ops perf -o MUL_MAT --buft RISCV_AME \
  -p 'type_a=q8_0,type_b=f32,m=2048,n=128,k=8192,bs=\[1,1\],nr=\[1,1\]'
```

It did not reproduce the exact 1B stop point within the 300s window. It reached
at least:

```text
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=88/128
```

Therefore the standalone shape is useful for probing, but it is not yet the
minimum faithful reproducer. The 1B fake-like path remains the authoritative
repro case.

### Why Same Shape Is Not Sufficient

`M=2048,N=128,K=8192,nb64=128,panel_bytes=1048576` is a necessary condition for
the observed stop, but the current evidence shows it is not sufficient.

The faithful llama path and the standalone probes differ in several important
ways:

- real llama first runs earlier AME ops before the failing op, including
  `K=2048` shapes that complete. This can change AME, cache, DMA, memory-system,
  or allocator state before the `K=8192` op starts;
- real llama uses the ggml graph allocator and backend scheduling. The workspace,
  source tensors, quantized activation cache, scale arrays, and destination
  tensor can land at different virtual and physical addresses than in a fresh
  single-op test;
- the packed-B kernel quantizes and caches `src1` through
  `ame_prepare_x_q64_cache()`. A synthetic panel probe does not exercise this
  path at all, and `test-backend-ops` exercises it with isolated synthetic input
  rather than the 1B graph's activation tensor and cache history;
- the model-weight side (`src0`) is a prepacked Q8_64 tensor in the real llama
  graph. `ame_panel_probe` uses its own deterministic byte patterns and malloc
  layout, so it validates raw tile-loop mechanics but not the real tensor
  layout/content path;
- the last faithful log is before `kb=32/128`, while the standalone same-shape
  `test-backend-ops` run reached `kb=88/128`. That directly proves that loop
  bounds and `panel_bytes=1048576` alone do not recreate the failing state.

The practical conclusion is that `ame_panel_probe` is a low-level tile-kernel
stress tool, and `test-backend-ops` is a closer ggml single-op shape tool, but
neither is currently a faithful minimizer. The next minimization step should
preserve more llama context instead of reducing only by shape: replay the
preceding 1B AME op sequence, or log and replay the failing op's addresses,
cache generation, input checksums, and scale checksums.

### Checkpoint Before The Failing Packed-B Accumulation

For RTL waveform debug, the llama AME path has an optional checkpoint ROI marker
guarded by:

```text
GGML_AME_CKPT_ON_SHAPE=1
GGML_AME_CKPT_M=2048
GGML_AME_CKPT_N=128
GGML_AME_CKPT_K=8192
```

When enabled, the marker fires once after the failing op's packed-B panel has
been built and before the `i0/kb` accumulation loop starts. The expected log is:

```text
[AME_CKPT] start ROI before packed-B accumulation: M=2048 N=128 K=8192 j0=0
```

This preserves the real llama graph, allocator, quantized activation cache,
packed 1 MiB B panel, and source/destination tensor layout. It does not preserve
the internal state of an already hung FPGA run; it creates a software/memory
snapshot that can be restored in NEMU or RTL emu.

Build the same 1B fake-like rootfs configuration with the checkpoint marker
enabled:

```sh
source env.sh
make firmware \
  XSAI_INIT_MODE=ci \
  XSAI_WORKLOAD=llama-fake-bench-suite \
  XSAI_AUTO_EXIT=1 \
  XSAI_DROP_SHELL=0 \
  XSAI_RUN_AFTER_WORKLOAD=1 \
  XSAI_DUMP_THP=0 \
  XSAI_TRACE_WORKLOAD=1 \
  XSAI_LLAMA_TEST_BACKEND_OPS=0 \
  XSAI_LLAMA_FAKE_BENCH_MODELS=/root/llama3.2_1b_q8.gguf.om \
  XSAI_GGML_AME_LOG=1 \
  XSAI_GGML_AME_PANEL_LOG=1 \
  XSAI_GGML_AME_PANEL_PROGRESS_LOG=1 \
  XSAI_GGML_AME_CKPT_ON_SHAPE=1 \
  XSAI_GGML_AME_CKPT_M=2048 \
  XSAI_GGML_AME_CKPT_N=128 \
  XSAI_GGML_AME_CKPT_K=8192 \
  XSAI_AME_USE_PACKED_B_PANEL=1 \
  XSAI_AME_SKIP_TILE_C_ZERO=1 \
  XSAI_AME_SKIP_TILE_B_ZERO=1
```

Then use the no-SimPoint one-slice checkpoint flow. Omit `MODEL_IMG` if the
model is already packaged in the initramfs; pass it if the model comes from a
virtio disk image:

```sh
make ckpt-nosimpoint \
  WORKLOAD_NAME=llama-ame-panel-k8192 \
  CHECKPOINT_CONFIG=llama-1b-panel \
  CPT_INTERVAL=1
```

The resulting checkpoint should appear under:

```text
firmware/checkpoints/llama-1b-panel/llama-ame-panel-k8192/
```

Use the generated `.zstd` as the RTL debug payload:

```sh
make run-emu-debug \
  PAYLOAD=firmware/checkpoints/llama-1b-panel/llama-ame-panel-k8192/1/_1_1.zstd \
  DIFF=1 \
  WAVE_BEGIN=0 \
  WAVE_END=2000000
```

Adjust the checkpoint filename if the dump index differs. For the first debug
pass, keep `CPT_INTERVAL=1` so the snapshot is as close as possible to the
marker. If restore starts slightly before or after the desired tile call, widen
the wave window first, then tune `CPT_INTERVAL`.

Validated on 2026-05-16: the no-SimPoint flow reached the marker, printed the
`[AME_CKPT] start ROI` line, dumped `_1_1.zstd`, and completed. The generated
file was:

```text
firmware/checkpoints/llama-1b-panel/llama-ame-panel-k8192/1/_1_1.zstd
```

`zstd -t` reported an uncompressed checkpoint size of 8589934592 bytes.

### RTL Emu No-Debug Replay Result

The checkpoint was replayed without waveform/DB debug:

```sh
timeout 7200 make run-emu \
  PAYLOAD=firmware/checkpoints/llama-1b-panel/llama-ame-panel-k8192/1/_1_1.zstd \
  DIFF=1
```

`run-emu` initially failed because the default difftest reference
`XSAI/ready-to-run/riscv64-nemu-interpreter-so` was missing. A local NEMU
reference shared library was built with `riscv64-matrix-xs-ref_defconfig`; stale
non-PIC softfloat objects had to be cleaned before rebuilding the shared object.

The replay then restored correctly into the failing region:

```text
The first instruction of core 0 has commited. Difftest enabled.
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 begin
[AME_PANEL_PROGRESS] ame64 packed_b_panel: M=2048 N=128 K=8192 j0=0 i0=0 kb=0/128
```

It did not run silently for the two-hour timeout. Instead, emu aborted after
about 105 seconds of host time:

```text
No instruction of core 0 commits for 120000 cycles, maybe get stuck
Let REF run one more instruction.
[.../NEMU/src/isa/riscv64/instr/rvmatrix/mcfg.h:108,exec_macquire]
Value(5377) in token register 0 is not enough.
Core 0: ABORT at pc = 0x2ab3f80fcc
Core-0 instrCnt = 34449, cycleCnt = 257684, IPC = 0.133687
```

This makes the checkpoint useful for RTL debug: the no-debug replay reaches the
same first-tile packed-B accumulation region and then hits a forward-progress
failure immediately around the first AME tile sequence, rather than completing
or timing out at the outer two-hour limit.

### Current Inference

The current evidence rules out several earlier hypotheses:

- the small `stories15M` workload is not the trigger;
- `M=8192,N=128,K=2048` can complete;
- packed-B panel construction completes before the hang;
- the hang is before the final store path because `i0=0 done` is never printed.

The strongest current hypothesis is that the packed-B panel path has a
workload-dependent issue when the B panel is large enough to cover
`K=8192`:

```text
nb64 = 128
panel_bytes = 128 * 128 * 64 = 1048576 bytes
```

The failing region is inside the K accumulation loop over the already-packed B
panel, in the first output tile of the real 1B graph. This points at the
interaction among packed-B panel memory access, repeated AME tile calls, and
the surrounding FPGA memory/cache behavior rather than a pure packing bug.

Keep future minimization tied to the 1B `llama-bench --fake-like` path unless a
standalone reproducer can be shown to stop at the same `i0/kb` boundary.

## Optimization Order

Recommended order for operator optimization:

1. Add AME profile counters guarded by an env var such as `GGML_AME_PROFILE=1`.
2. Verify that large prompt matmuls use `RISCV_AME` and the packed Q8_64 path.
3. Measure cycles split into packing, activation quantization, AME tile call,
   and CPU scale-out.
4. If DDR bandwidth is saturated, reduce memory movement before tuning compute:
   - keep packed Q8 weights persistent;
   - avoid repacking or recopying tiles when possible;
   - fuse scale-out or write the final dtype directly from the accelerator;
   - increase reuse across the `N` dimension for prompt batches;
   - avoid writing full int32 accumulator tiles to DDR if they are immediately
     consumed by CPU scale-out.
5. If AME tile cycles are high but bandwidth is low, inspect matrix instruction
   issue, `mrelease/macquire` wait time, SCP/local-memory behavior, and tile
   underfill.
6. If fallback dominates, relax or add specialized kernels for small `N`,
   especially decode.

The existing benchmark output is enough to say the run is much slower than the
nominal 8 TOPS peak, but it is not enough to assign blame. The missing evidence
is per-op MAC count, AME dispatch count, and byte/cycle accounting inside the
AME matmul path.

## FPGA Profile Snapshot: Prompt `pp128 n0`

This snapshot is from the prompt-only fake-like run:

```text
llama-bench --fake-like /root/stories15M-q8_0.gguf.om \
    -t 1 -p 128 -n 0 -r 1 --estimate-layers 1 --no-warmup
```

The run enabled both AME-internal profiling and ggml op profiling:

```sh
GGML_AME_PROFILE=1
GGML_XSAI_OP_PROFILE=1
```

### Raw AME Counters

```text
calls baseline=0 packed=14 tiles=312 edge_tiles=104
logical_macs=254803968 logical_ops=509607936

cycles total=48774731
baseline_total=0
packed_total=48774731
prepare_cache=16394764
pack_a=2658506
pack_b=2252318
zero_c=0
gemm=986704
scale=18975482
store=5906374

derived ops_per_cycle=10.45
derived macs_per_cycle=5.22
min_bytes=25559040
sw_bytes_floor=66453504
min_B_per_cycle=0.5240
sw_B_per_cycle=1.3625
```

Interpretation:

- All AME calls used the packed path; no baseline Q8 path was used.
- `gemm` is only about `0.99M` cycles, so synchronous AME matrix compute is not
  the dominant bottleneck.
- The largest AME-internal costs are:
  - `scale = 18.98M`
  - `prepare_cache = 16.39M`
  - `store = 5.91M`
- `scale + store` is about `24.88M` cycles, larger than all AME tile compute by
  more than 25x. Optimizing the post-processing path has higher expected return
  than tuning the raw `MQMA` issue path.

### Raw ggml Op Profile

The top ggml op totals were:

```text
MUL_MAT   calls=18 cycles=74733094
SOFT_MAX  calls=2  cycles=10651658
ROPE      calls=4  cycles=6769497
GLU       calls=2  cycles=4350267
SET_ROWS  calls=4  cycles=4195351
ADD       calls=4  cycles=2198128
RMS_NORM  calls=4  cycles=1506671
MUL       calls=4  cycles=1444203
CONT      calls=2  cycles=375065
GET_ROWS  calls=1  cycles=327084
```

The top module/name rows with shape and type were:

```text
attn_core MUL_MAT calls=4 cycles=25851005
  mixed shapes, src0=f16 src1=f32 dst=f32, ame_candidate=no

attn_qkv MUL_MAT calls=6 cycles=12691861
  M=288 N=128 K=288, src0=q8_0 src1=f32 dst=f32, ame_candidate=yes

ffn_out MUL_MAT calls=2 cycles=12666942
  M=288 N=128 K=768, src0=q8_0 src1=f32 dst=f32, ame_candidate=yes

ffn_gate MUL_MAT calls=2 cycles=9948482
  M=768 N=128 K=288, src0=q8_0 src1=f32 dst=f32, ame_candidate=yes

ffn_up MUL_MAT calls=2 cycles=8258290
  M=768 N=128 K=288, src0=q8_0 src1=f32 dst=f32, ame_candidate=yes

out_proj MUL_MAT calls=2 cycles=5316514
  M=288 N=128 K=288, src0=q8_0 src1=f32 dst=f32, ame_candidate=yes

kq MUL_MAT calls=2 cycles=12805628
  M=256 N=128 K=48, src0=f16 src1=f32 dst=f32, ame_candidate=no

kqv MUL_MAT calls=2 cycles=13045377
  M=48 N=128 K=256, src0=f16 src1=f32 dst=f32, ame_candidate=no
```

### Route Conclusion

The sum of AME-candidate `q8_0 x f32` matrix cycles is approximately:

```text
attn_qkv  12.69M
ffn_out   12.67M
ffn_gate   9.95M
ffn_up     8.26M
out_proj   5.32M
----------------
total     48.88M
```

This matches the AME profile total:

```text
AME total 48.77M
```

Therefore the current prompt run is not mainly missing AME dispatch for
eligible `q8_0 x f32` matmuls. The eligible weight-projection and FFN matmuls
are effectively accounted for by the AME path.

The largest remaining `MUL_MAT` hotspot is attention core:

```text
kq   M=256 N=128 K=48  src0=f16 src1=f32  cycles=12.81M
kqv  M=48  N=128 K=256 src0=f16 src1=f32  cycles=13.05M
```

These are not AME candidates under the current backend because the AME path is
implemented for `q8_0 x f32` weight matmul and ultimately uses INT8 x INT8 to
INT32 matrix instructions. `kq` and `kqv` are activation attention matmuls with
`f16 x f32` inputs. Accelerating them with the existing AME path would require
either a new F16/F32-capable path or an explicit quantization strategy, and the
latter changes the numerical path and needs strict correctness validation.

### Current Optimization Priority

Based on this snapshot:

1. Optimize AME post-processing first:
   - `scale` is `18.98M` cycles.
   - `store` is `5.91M` cycles.
   - The next concrete target is to merge and/or RVV-vectorize `scale + store`
     while preserving exact output behavior.
2. Optimize `prepare_cache`:
   - `prepare_cache` is `16.39M` cycles.
   - Measure cache hit rate and then tighten activation quantization/packing for
     fixed prompt shapes such as `N=128`.
3. Treat attention core as a separate CPU/RVV or new-kernel problem:
   - `kq + kqv` is `25.85M` cycles.
   - Current AME route does not support these `f16 x f32` shapes.
4. Optimize scalar/vector CPU ops after that:
   - `SOFT_MAX = 10.65M`
   - `ROPE = 6.77M`
   - `SET_ROWS = 4.20M`
   - `GLU = 4.35M`

The immediate software conclusion is: continue improving the AME
`q8_0 x f32` path, but do not expect route fixes alone to remove the largest
non-AME `MUL_MAT` hotspot. Attention core needs a distinct implementation
strategy.

## Updated FPGA/Host Comparison

The later FPGA run in `log/fpga-uart-20260513-035109-1364794.log` used the
same prompt-only workload and is the cleaner baseline for cross-platform
comparison:

```text
clean FPGA pp128 n0:   254M rdcycle, 1008.4 tok/s
profile FPGA pp128 n0: 256M rdcycle, 1001.9 tok/s
```

The profile overhead is small for this run:

```text
(256M - 254M) / 254M = about 0.8%
```

The corresponding AME counters were:

```text
[AME_PROFILE] calls baseline=0 packed=14 tiles=312 edge_tiles=104
[AME_PROFILE] logical_macs=254803968 logical_ops=509607936
[AME_PROFILE] cycles total=27429211
[AME_PROFILE] prepare_cache=2509687 pack_a=2735302 pack_b=2166541
[AME_PROFILE] gemm=1000970 scale=11629455 store=5897491
[AME_PROFILE] derived ops_per_cycle=18.58 macs_per_cycle=9.29
[AME_PROFILE] min_bytes=25559040 sw_bytes_floor=66453504
[AME_PROFILE] min_B_per_cycle=0.9318 sw_B_per_cycle=2.4227
```

The top FPGA ggml profile rows were:

```text
summary graphs=2 nodes=45 cycles=85778205

MUL_MAT   calls=18 cycles=53371543
SOFT_MAX  calls=2  cycles=10702391
ROPE      calls=4  cycles=6812535
SET_ROWS  calls=4  cycles=4776330
GLU       calls=2  cycles=4324256
ADD       calls=4  cycles=2178653
RMS_NORM  calls=4  cycles=1487427
MUL       calls=4  cycles=1429939
```

The same fake-like model on the host build, measured with
`GGML_XSAI_OP_PROFILE=1`, produced:

```text
host AMD Zen5 pp128 n0: 7305.2 tok/s
summary timer=rdtscp graphs=2 nodes=45 cycles=27053796

MUL_MAT   calls=18 cycles=22781850
SOFT_MAX  calls=2  cycles=1423254
SET_ROWS  calls=4  cycles=982254
RMS_NORM  calls=4  cycles=609840
ROPE      calls=4  cycles=501606
GET_ROWS  calls=1  cycles=299964
GLU       calls=2  cycles=295344
```

The profile `cycles` are not a direct wall-clock comparison because FPGA uses
RISC-V `rdcycle`, while the host profile uses x86 `rdtscp`. They are still
useful as per-platform tick counts and hotspot ratios.

### Why AMD Zen5 Is Much Faster Here

The host is faster for several concrete reasons:

1. The host CPU runs at a much higher clock than the FPGA soft/hard RISC-V
   pipeline used by the workload.
2. Zen5 has wide out-of-order execution, aggressive branch prediction, large
   caches, and high memory-level parallelism. The FPGA CPU side is much less
   able to hide scalar loops, cache misses, and pointer-heavy ggml graph code.
3. The host llama.cpp CPU kernels use mature x86 SIMD and optimized memory
   paths. For this model, many hot ops are not pure AME GEMM:
   - FPGA `SOFT_MAX`: `10.70M` rdcycle vs host `1.42M` rdtscp
   - FPGA `ROPE`: `6.81M` rdcycle vs host `0.50M` rdtscp
   - FPGA `SET_ROWS`: `4.78M` rdcycle vs host `0.98M` rdtscp
   - FPGA `GLU`: `4.32M` rdcycle vs host `0.30M` rdtscp
4. Zen5 keeps the small 15M model working set in a much stronger cache and
   DDR hierarchy. The FPGA platform has a single-channel DDR4 path around
   6 GB/s, so tile movement and CPU-side post-processing are expensive.
5. The current AME path accelerates only the eligible `q8_0 x f32` projection
   and FFN matmuls. Attention-core `f16 x f32` matmuls remain CPU/RVV work:

   ```text
   FPGA kq   M=256 N=128 K=48  f16 x f32: 12.81M
   FPGA kqv  M=48  N=128 K=256 f16 x f32: 13.02M

   host kq:  4.28M
   host kqv: 2.09M
   ```

So the host advantage is not surprising: it is not competing only against AME
raw TOPS. It is competing against the combined AME post-processing path, RISC-V
CPU/RVV fallback kernels, ggml graph overhead, and the FPGA DDR subsystem.

### What The FPGA Numbers Say About The Current Bottleneck

The AME matrix core is not the dominant measured cost in the current prompt
profile:

```text
AME gemm  = 1.00M cycles
AME scale = 11.63M cycles
AME store = 5.90M cycles
```

`scale + store = 17.53M cycles`, which is about 17.5x the measured AME GEMM
issue time. Even if async GEMM completely hid the `gemm` bucket, the best
possible win from hiding only that bucket is about 1M cycles. The larger win is
removing or fusing the post-processing traffic.

At the graph level, the remaining non-AME/vector-side costs are also large:

```text
attn_core f16/f32 MUL_MAT = 25.83M cycles
SOFT_MAX                 = 10.70M cycles
ROPE                     =  6.81M cycles
SET_ROWS                 =  4.78M cycles
GLU                      =  4.32M cycles
```

This is the basis for saying the next bottleneck is vector/CPU fallback
kernels, not AME dispatch coverage for the existing `q8_0 x f32` matmuls.

## ISA And Microarchitecture Recommendations

These recommendations are ordered by measured payoff on the current
`stories15M-q8_0 pp128 n0` workload.

### 1. AME Fused Scaled Store

Add an AME instruction or microcoded sequence that consumes an int32 C matrix
slot and writes the final output dtype directly:

```text
C_i32 * scale_a * scale_b -> f32/f16 store
```

Required features:

- read C matrix slot without spilling it through CPU-visible memory;
- read per-block or per-tile quantization scales;
- multiply by the combined scale;
- store to ggml destination layout as F32 initially, optionally F16 later;
- support partial edge tiles.

Why this is first priority:

```text
AME gemm  = 1.00M cycles
AME scale = 11.63M cycles
AME store = 5.90M cycles
```

The current matrix core has already made raw GEMM small. The expensive part is
getting from AME int32 accumulators back to the ggml tensor format.

### 2. AME F16/BF16 Attention Matmul

Add matrix support for attention-core activation matmuls:

```text
f16 x f16 -> f32
bf16 x bf16 -> f32
f16 x f32 -> f32, if the datapath can support it economically
```

The current missed hot ops are:

```text
kq   M=256 N=128 K=48  src0=f16 src1=f32 dst=f32 cycles=12.81M
kqv  M=48  N=128 K=256 src0=f16 src1=f32 dst=f32 cycles=13.02M
```

Together they cost about `25.83M` FPGA cycles. This is the largest remaining
`MUL_MAT` bucket and cannot be fixed by improving `q8_0 x f32` routing.

If a native `f16 x f32` matrix path is too expensive, the next-best hardware
option is `f16 x f16 -> f32` plus a software or RVV cast/pack path for the F32
operand. Explicitly quantizing these attention matmuls to INT8 is more risky
because it changes the numerical path and needs model-quality validation.

### 3. AME Async Issue/Wait ABI

Expose the existing async AME capability with a stable software contract:

```text
mma.issue slot_a, slot_b, slot_c
mma.test  slot_c
mma.wait  slot_c
mma.fence
```

This should include clear ownership rules for the 4 A slots, 4 B slots, and 4
C slots:

- software can double-buffer A/B while AME computes;
- C slots can ping-pong between compute and scale/store;
- issue/wait does not implicitly clobber matrix slots;
- fences define when CPU/RVV may read or overwrite buffers.

Expected standalone payoff is limited by the profile:

```text
gemm = about 1.00M cycles
```

The async ABI becomes much more valuable after fused scaled-store exists,
because software can overlap prepare/pack and residual vector work with AME
compute and output conversion.

### 4. Hardware F32-to-Q8 Tile Quantize/Pack

Current AME input preparation still has measurable cost:

```text
prepare_cache = 2.51M cycles
pack_a        = 2.74M cycles
pack_b        = 2.17M cycles
```

For Q8 weight matmuls, B is the F32 activation side that must be quantized into
INT8 tiles. A hardware helper should support:

- vector or matrix-tile absmax reduction;
- `f32 -> int8` conversion with scale generation;
- direct fill of AME B matrix slots;
- edge-tile zero fill without separate software memset.

This is lower priority than fused scaled-store because the measured cost is
smaller, but it reduces CPU/RVV work and tile memory traffic.

### 5. C Slot Operations For Reuse And Partial Accumulation

The 4 C matrix slots should be first-class ISA resources, not only implicit
GEMM destinations. Useful operations:

```text
C.clear slot, mask/shape
C.add dst, src
C.scale_store slot, dst, scales, dtype
C.copy or C.move between slots
```

This helps software avoid unnecessary C spills and makes multi-stage or
partial-K scheduling possible. It also gives the compiler/runtime a clean way
to use all 4 C matrices for ping-pong output and partial accumulation.

### 6. RVV/Vector Improvements For Softmax

`SOFT_MAX` costs `10.70M` FPGA cycles versus `1.42M` host ticks. The current
ggml path has RVV in the exponential/sum core, but the full operator still does
several memory passes:

```text
copy -> scale -> mask add -> max -> exp/sum -> normalize
```

Useful vector ISA or microarchitecture support:

- high-throughput approximate vector `exp`;
- fast vector reciprocal;
- high-throughput horizontal max/sum reductions;
- efficient F16 mask load and widen to F32;
- enough load/store bandwidth to keep these passes from serializing.

Software has already started reducing this by fusing `copy + scale + mask +
max` into one RVV prepare pass for RISC-V/ZVFH. Hardware should make this kind
of fused vector loop cheap.

### 7. RVV/Vector Improvements For ROPE

`ROPE` costs `6.81M` FPGA cycles versus `0.50M` host ticks. The inspected ggml
implementation is mostly scalar:

```text
build sin/cos cache
for each pair: x0,x1,cos,sin -> rotated pair
```

Useful hardware support:

- vector F16 load, F32 convert, rotate, and F16/F32 store;
- strided/interleaved pair load-store;
- vector sin/cos or a fast sincos approximation path;
- pairwise rotate primitive if adding a special vector operation is acceptable.

This does not need to be a full "ROPE instruction" initially. Making the
common pair-rotation loop efficient is enough.

### 8. Indexed/Streaming Store For KV Cache

`SET_ROWS` costs `4.78M` FPGA cycles versus `0.98M` host ticks. The hot names
are KV-cache writes:

```text
cache_v_l1 (reshaped) (view)
cache_v_l0 (reshaped) (view)
cache_k_l1 (view)
cache_k_l0 (view)
```

Useful support:

- contiguous row copy acceleration;
- indexed row store;
- F32/F16 convert-store;
- streaming stores that do not pollute limited CPU caches.

This is a memory-path optimization and should be evaluated against the 6 GB/s
DDR limit.

## Final Priority List

For RTL/ISA planning, the practical order is:

1. AME fused `C_i32 -> scaled F32/F16 store`.
2. AME `f16/bf16` attention matmul support.
3. AME async `issue/test/wait/fence` ABI using the 4 A, 4 B, and 4 C slots.
4. Hardware F32-to-Q8 tile quantize/pack into AME B slots.
5. C-slot clear/add/scale-store operations for reuse and partial accumulation.
6. RVV softmax support: exp, reciprocal, reductions, F16 mask widen.
7. RVV ROPE support: pairwise rotate, vector sincos, strided pair access.
8. KV-cache indexed/streaming row store.

The main design lesson from the profile is that current performance is not
limited by nominal AME 8 TOPS peak. The measured limits are AME output
conversion/store, attention-core matmuls that do not match the current AME
datatype contract, and vector/CPU fallback kernels.

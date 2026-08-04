---
name: xsai-fpga-flow
description: Guide for using and maintaining the xsai-env FPGA execution flow. Use this when working on make fpga-reset, make run-fpga, scripts/fpga-run-ai.sh, scripts/fpga/reset_cpu.tcl, remote Vivado/VIO reset, XDMA workload loading, or FPGA UART capture.
---

# XSAI FPGA Flow

Use this skill for the top-level FPGA bring-up and workload execution path:

- `make fpga-sync-bitstream`
- `make fpga-program`
- `make fpga-run-bitstream`
- `make fpga-reset`
- `make run-fpga`
- `scripts/fpga-program-bitstream.sh`
- `scripts/fpga-run-ai.sh`
- `scripts/fpga/program_bitstream.tcl`
- `scripts/fpga/reset_cpu.tcl`

This is a top-level orchestration flow, with remote dependencies on the `fpga`
host.

## Current Sequence

`make fpga-program` mirrors the better-separated `env-scripts/fpga_diff` flow:

1. Find the latest local `local/fpga-vivado/*/artifacts` with `.bit` and `.ltx`
   unless `FPGA_BIT_HOME` is set.
2. Upload only `.bit` and `.ltx` to `FPGA_HOST:FPGA_REMOTE_BIT_HOME`.
3. Remove the current XDMA PCIe function unless `FPGA_PROGRAM_PCIE_RESET=0`.
4. Program the FPGA with `scripts/fpga/program_bitstream.tcl`.
5. Rescan PCIe unless `FPGA_PROGRAM_PCIE_RESET=0`; then wait for required
   XDMA device nodes. If they are missing and
   `FPGA_XDMA_RELOAD_ON_MISSING=1`, reload the XDMA module and rescan again.
6. Assert the CPU reset probe through the uploaded `.ltx` unless
   `FPGA_PROGRAM_ASSERT_RESET=0`.

`make fpga-sync-bitstream` performs only step 1-2.

`make fpga-run-bitstream` runs `fpga-program` first, then `run-fpga`.

`make fpga-reset` only drives the reset VIO to `1`.

`make run-fpga` runs this sequence:

1. Select the payload with `RUN_NEMU_PAYLOAD`.
2. Copy the payload to the remote host. If `FPGA_REMOTE_PAYLOAD` is empty, the
   script creates `/tmp/xsai-payload-<timestamp>-<pid>.<ext>`.
3. Upload `scripts/fpga/reset_cpu.tcl`.
4. Set the reset VIO to `1` through Vivado.
5. Run optional PCIe remove/rescan hooks.
6. Load the workload with `xdma_process`.
7. Kill stale UART readers unless `FPGA_KILL_UART_READERS=0`.
8. Start the remote UART capture.
9. Set the reset VIO to `0` to release the workload.
10. Stream the remote UART log locally for `FPGA_TIMEOUT` seconds.

The timeout only bounds the host-side UART observation window. It does not prove
the FPGA workload has finished. When the timeout expires, the script prints that
the workload may still be running.

## Payload Choice

Do not pass the QEMU GCPT payload to FPGA by default.

The top-level Makefile maps the default `PAYLOAD=$(QEMU_PAYLOAD)` to
`RUN_NEMU_PAYLOAD=$(NEMU_PAYLOAD)`, so `make run-fpga` normally uses:

```text
firmware/gcpt_restore/build-nemu/build/gcpt.bin
```

If that file is missing, `_ensure_fpga_payload` builds it with:

```bash
make -C firmware build-gcpt-nemu
```

Explicit `PAYLOAD=<path>` values are still respected through `RUN_NEMU_PAYLOAD`.

## Important Knobs

Common defaults:

```make
FPGA_HOST ?= fpga
FPGA_REMOTE_PAYLOAD ?=
FPGA_BIT_HOME ?=
FPGA_REMOTE_BIT_HOME ?= /home/fpga/xsai-bitstream/current
FPGA_LTX ?= /home/fpga/xsai-bitstream/current/pcie_part_gating_wrapper.ltx
FPGA_DRIVER ?= ~/nexus-am/apps/dse-driver-ai/build/dse-driver-ai-riscv64-xs-driver.bin
FPGA_XDMA_PROCESS ?= ~/ai/xdma_process/build/xdma_process
FPGA_TIMEOUT ?= 120
FPGA_UART_CMD ?=
FPGA_KILL_UART_READERS ?= 1
FPGA_PCIE_SUDO ?= sudo -n
FPGA_XDMA_REQUIRED_DEVICES ?= /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_bypass
FPGA_XDMA_RELOAD_ON_MISSING ?= 1
FPGA_XDMA_MODULE ?= xdma
FPGA_XDMA_WAIT_SECS ?= 10
FPGA_REMOTE_SETUP ?= source /tools/Xilinx/Vivado_Lab/2020.2/settings64.sh
FPGA_REMOTE_SUDO ?=
FPGA_PROGRAM_PCIE_RESET ?= 1
FPGA_PROGRAM_ASSERT_RESET ?= 1
```

Default UART command when `FPGA_UART_CMD` is empty:

```bash
~/xdma_work/tools/proto/pcie-util /dev/xdma0_user uart 0x10000
```

Keep the leading `~` quoted inside the local script so it expands on the remote
`fpga` host, not on the local machine.

`FPGA_PCIE_SUDO` is used only by `make fpga-program` for PCIe sysfs remove and
rescan operations. It defaults to `sudo -n` because `/sys/bus/pci/rescan` and
related sysfs files are normally root-writable only.

`make fpga-program` must not treat a bare `/sys/bus/pci/rescan` as sufficient.
Warm bitstream programming can leave the driver partially probed, where
`/dev/xdma0_c2h_0` exists but `/dev/xdma0_user` or `/dev/xdma0_bypass` is
missing. Keep `scripts/fpga/pcie-rescan.sh` checking
`FPGA_XDMA_REQUIRED_DEVICES`; on failure it should print `lspci`, `/dev/xdma*`,
and XDMA module status, then reload `FPGA_XDMA_MODULE` and rescan again when
`FPGA_XDMA_RELOAD_ON_MISSING=1`.

Set `FPGA_REMOTE_SUDO='sudo -n'` only on hosts that still need sudo for XDMA or
UART device access. The current expected setup grants device permissions for
those runtime paths, so the default `FPGA_REMOTE_SUDO` is empty.

## Vivado And VIO

Remote SSH shells do not inherit interactive Vivado setup. Prefer
`FPGA_REMOTE_SETUP` over sourcing `~/.zshrc` from bash.

The current `scripts/fpga/reset_cpu.tcl` accepts:

```text
vivado -mode batch -source reset_cpu.tcl -tclargs <xsai.ltx> <0|1>
```

For the current bit/LTX, the reset probe is:

```text
pcie_part_gating_i/vio_0_probe_out0
```

Meaning:

- `1`: reset asserted
- `0`: reset released

If Vivado reports `Required VIO probe not found`, inspect the remote hardware
objects before editing the Tcl:

```bash
ssh fpga 'bash -lc '\''source /tools/Xilinx/Vivado_Lab/2020.2/settings64.sh; vivado -mode batch -source <list-vio.tcl>'\'''
```

The old `vio_sw4`/`vio_sw5`/`vio_sw6` flow is not valid for the current bit
unless the programmed design and `.ltx` are changed back to one exposing those
probes.

The default remote `current` bundle may be real files uploaded by
`make fpga-program` or symlinks to a manually provisioned board image. The
current fpga host uses:

```text
/home/fpga/xsai-bitstream/current/pcie_part_gating_wrapper.bit -> /home/fpga/ai/bits/bigddr8g_0522.bit
/home/fpga/xsai-bitstream/current/pcie_part_gating_wrapper.ltx -> /home/fpga/xsai.ltx
```

Keep plain `make run-fpga` using the `current` `.ltx` path so direct workload
runs and newly programmed bitstreams use the same bundle layout.

## UART Capture Pitfalls

Only one UART reader should run at a time. Multiple `pcie-util ... uart ...`
processes reading the same device can corrupt output or appear as repeated
`0xff` bytes.

The run script defaults to:

```bash
pkill -f '[p]cie-util .*uart' >/dev/null 2>&1 || true
```

The bracketed pattern avoids killing the `pkill` command itself or its SSH
shell. Do not change it back to `pkill -f 'pcie-util .*uart'`.

UART logs are saved locally under:

```text
log/fpga-uart-<timestamp>-<pid>.log
```

After UART capture starts, the reset-release Vivado batch log is saved
separately so Vivado trace lines do not interleave with workload UART output:

```text
log/fpga-vivado-reset-<timestamp>-<pid>.log
```

`FPGA_PASS_PATTERN` and `FPGA_FAIL_PATTERN` are matched against this saved log
after the observation window ends.

## Validation

For script edits:

```bash
bash -n scripts/fpga-program-bitstream.sh
bash -n scripts/fpga-run-ai.sh
make -n fpga-program
make -n run-fpga
make fpga-reset
```

Use `make run-fpga` only when the FPGA host, bit/LTX, XDMA devices, and intended
payload are ready. It will load the workload and release reset.

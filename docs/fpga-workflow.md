# XSAI FPGA Workflow

This flow keeps generated artifacts under `local/` and keeps board-side actions
split into small steps.

## Build Artifacts

Generate FPGA RTL:

```sh
make fpga-rtl
```

Run Vivado through bitstream generation:

```sh
source /nfs/tools/xilinx/2020.2/Vivado/2020.2/settings64.sh
make fpga-bitstream
```

The default output locations are:

```text
local/fpga-rtl/build/rtl
local/fpga-vivado/<project-run>/artifacts/
```

The artifacts directory contains the files needed for board programming:

```text
pcie_part_gating_wrapper.bit
pcie_part_gating_wrapper.ltx
```

## Program The FPGA

Program the latest local bitstream bundle:

```sh
make fpga-program
```

This target:

1. Finds the newest `local/fpga-vivado/*/artifacts` containing `.bit` and
   `.ltx`, unless `FPGA_BIT_HOME` is set.
2. Uploads only `.bit` and `.ltx` to `FPGA_HOST:FPGA_REMOTE_BIT_HOME`.
3. Removes the existing XDMA PCIe function.
4. Runs Vivado Hardware Manager to program the FPGA.
5. Rescans PCIe and waits for the required XDMA device nodes.
6. Asserts CPU reset through the programmed `.ltx`.

Useful overrides:

```sh
make fpga-program \
  FPGA_HOST=fpga \
  FPGA_BIT_HOME=local/fpga-vivado/xsai_fpga-synth-20260704-123937/artifacts \
  FPGA_REMOTE_BIT_HOME=/home/fpga/xsai-bitstream/current \
  FPGA_PCIE_SUDO='sudo -n'
```

`FPGA_PCIE_SUDO` is used only for PCIe sysfs remove/rescan. Runtime commands in
`make run-fpga`, such as `xdma_process` and UART capture, still use
`FPGA_REMOTE_SUDO`, whose default is empty.

After the post-program PCIe rescan, the flow requires these XDMA nodes by
default:

```text
/dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_bypass
```

If only part of the device appears, for example `/dev/xdma0_c2h_0` exists but
`/dev/xdma0_user` or `/dev/xdma0_bypass` is missing, `make fpga-program`
prints the PCIe/XDMA state, reloads the `xdma` module, rescans PCIe again, and
rechecks the nodes. Tune this with:

```sh
make fpga-program \
  FPGA_XDMA_REQUIRED_DEVICES='/dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_user /dev/xdma0_bypass' \
  FPGA_XDMA_RELOAD_ON_MISSING=1 \
  FPGA_XDMA_MODULE=xdma \
  FPGA_XDMA_WAIT_SECS=10
```

For a sync-only step:

```sh
make fpga-sync-bitstream FPGA_BIT_HOME=<artifacts-dir>
```

If PCIe remove/rescan is managed externally:

```sh
make fpga-program FPGA_PROGRAM_PCIE_RESET=0
```

## Run A Workload

After programming, run the default FPGA payload:

```sh
make run-fpga
```

For a single command that programs first and then runs:

```sh
make fpga-run-bitstream
```

`run-fpga` uploads the payload, asserts reset, loads the image through XDMA,
starts UART capture, releases reset, and watches the UART log for
`FPGA_PASS_PATTERN` or `FPGA_FAIL_PATTERN`.

The default `.ltx` path is:

```text
$(FPGA_REMOTE_BIT_HOME)/pcie_part_gating_wrapper.ltx
```

On the shared FPGA host, the initial `current` bundle is compatible with the
existing manually provisioned files:

```text
/home/fpga/xsai-bitstream/current/pcie_part_gating_wrapper.bit -> /home/fpga/ai/bits/bigddr8g_0522.bit
/home/fpga/xsai-bitstream/current/pcie_part_gating_wrapper.ltx -> /home/fpga/xsai.ltx
```

`make fpga-program` can later replace this `current` bundle with uploaded files
from a new local Vivado artifact directory.

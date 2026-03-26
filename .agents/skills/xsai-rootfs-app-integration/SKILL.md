---
name: xsai-rootfs-app-integration
description: Guide for adding a new user program to the XSAI rootfs image and optionally invoking it during init. Use this when asked to add a binary such as after_workload into the rootfs build and boot flow.
---

# XSAI Rootfs App Integration

This skill helps you add a new program to the XSAI rootfs so it is built, packed into initramfs, and optionally executed during boot.

## When to use this skill

Use this skill when you need to:
- Add a new app under `firmware/riscv-rootfs/apps/`
- Make sure the app is built by the rootfs build system
- Include the generated binary in the initramfs image
- Invoke the app from the init script after or before another workload
- Build and test a single app directly from its rootfs app directory
- Run the generated binary with `qemu-riscv64` before full rootfs boot validation
- Verify that the rootfs boot flow can see and execute the new binary

## Integration workflow

### 1. Confirm the app exists

1. Check that the app directory exists under `firmware/riscv-rootfs/apps/`.
2. Check that the app's own Makefile supports the `install` target expected by the rootfs build.
3. Confirm the installed output path matches `firmware/riscv-rootfs/rootfsimg/build/<app_name>`.
4. If the app is intended for standalone testing, confirm the built binary can run directly from `rootfsimg/build/`.

## 2. Add the app to the rootfs build list

Update `firmware/riscv-rootfs/Makefile` so the app appears in `APPS`.

Example:

```makefile
APPS = hello_xsai after_workload busybox before_workload trap qemu_trap dtc lkvm-static
```

This ensures `make firmware` descends into the app directory and runs its `install` target.

You can also build a single app directly during development:

```bash
make -C firmware/riscv-rootfs/apps/after_workload
```

If the app Makefile supports `install`, prefer:

```bash
make -C firmware/riscv-rootfs/apps/after_workload install
```

This is useful for quick iteration before rebuilding the full rootfs.

## 3. Add the binary to the initramfs manifest

Update `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt` to include the binary in the generated image.

Example:

```text
file /bin/after_workload ${RISCV_ROOTFS_HOME}/rootfsimg/build/after_workload 755 0 0
```

Place the entry near the other user binaries in `/bin`.

## 4. Invoke the app from init if required

If the new program should run automatically during boot, update `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh`.

Example pattern:

```sh
echo "[xsai-init] launching after_workload"
if [ -x /bin/after_workload ]; then
  /bin/after_workload || true
fi
```

If the new app should consume the previous workload's return code, capture the exit status explicitly and pass it as an argument.

Example pattern:

```sh
hello_status=0

echo "[xsai-init] launching hello_xsai"
if [ -x /bin/hello_xsai ]; then
  if /bin/hello_xsai; then
    hello_status=0
  else
    hello_status=$?
  fi
fi

echo "[xsai-init] launching after_workload"
if [ -x /bin/after_workload ]; then
  /bin/after_workload "$hello_status" || true
fi
```

Follow the existing script style:
- Print a log line before execution
- Check executability with `-x`
- Use `|| true` when the boot flow should continue even if the app fails
- If return-code chaining is needed, use an `if cmd; then ... else ... fi` pattern so exit codes are preserved safely under `set -e`

## 5. Test the app directly before full boot

Before validating the whole rootfs, you can run the generated binary directly with `qemu-riscv64`.

Example pattern:

```makefile
run-user:
  @$(QEMU_HOME)/build/qemu-riscv64 -cpu rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 firmware/riscv-rootfs/rootfsimg/build/hello_xsai
```

For a newly added app, swap the final binary path to the new output, for example:

```bash
$(QEMU_HOME)/build/qemu-riscv64 -cpu rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 firmware/riscv-rootfs/rootfsimg/build/after_workload
```

Use this path when you want to validate the binary itself without involving initramfs boot.

## 6. Verify the full path is closed

After editing, verify all three layers are aligned:
- `firmware/riscv-rootfs/Makefile` builds the app
- `firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt` packs the binary
- `firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh` runs it if needed

Then rebuild and test.

For full image rebuild:

```bash
make firmware
```

For standalone binary verification:

```bash
make -C firmware/riscv-rootfs/apps/after_workload install
$(QEMU_HOME)/build/qemu-riscv64 -cpu rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 firmware/riscv-rootfs/rootfsimg/build/after_workload
```

For boot-flow verification, run the rootfs path and inspect logs for the expected launch message.

## Common checks

Build inclusion:

```bash
grep '^APPS =' firmware/riscv-rootfs/Makefile
```

Initramfs inclusion:

```bash
grep '/bin/after_workload' firmware/riscv-rootfs/rootfsimg/initramfs-disk-xsai.txt
```

Init invocation:

```bash
grep 'after_workload' firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh
```

Return-code forwarding:

```bash
grep 'hello_status\|after_workload' firmware/riscv-rootfs/rootfsimg/init-disk-xsai.sh
```

Single-app build:

```bash
make -C firmware/riscv-rootfs/apps/after_workload install
```

Direct user-mode run:

```bash
$(QEMU_HOME)/build/qemu-riscv64 -cpu rv64,v=true,vlen=128,h=false,zvfh=true,zvfhmin=true,x-matrix=true,rlen=512,mlen=65536,melen=32 firmware/riscv-rootfs/rootfsimg/build/after_workload
```

## Best practices

- Keep the app name consistent across app directory, build output, initramfs entry, and init script.
- Do not update only one layer; rootfs integration requires build, packaging, and boot-flow changes together.
- During development, verify the app first with a direct `make -C firmware/riscv-rootfs/apps/<app> install` path before rebuilding the full rootfs.
- Use `qemu-riscv64` on `firmware/riscv-rootfs/rootfsimg/build/<app>` for the fastest smoke test.
- Follow the existing init script's logging and failure-tolerance style.
- When chaining workloads, pass explicit exit codes instead of relying on shell-global `$?` across unrelated commands.
- Prefer minimal edits near existing `hello_xsai` or related workload entries so the boot order stays clear.
- Rebuild the firmware after making rootfs integration changes before testing runtime behavior.

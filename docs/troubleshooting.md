# Troubleshooting

Common failures, with logs and fixes.

## Rootfs artifacts from another toolchain

### Log

```text
error: patchelf is required to rewrite interpreter /old/toolchain/lib/ld-linux-riscv64-lp64d.so.1 -> /lib/ld-linux-riscv64-lp64d.so.1
make[4]: *** [firmware/riscv-rootfs/Makefile.app:24: install] Error 1
make[3]: *** [Makefile:13: apps/busybox] Error 2
make[2]: *** [Makefile:139: build-rootfs] Error 2
```

### Cause

Rootfs app binaries built with a different compiler or sysroot were reused after the environment changed.

### Recovery

Clean rootfs app artifacts, then rebuild.

```bash
source env.sh
make -C firmware/riscv-rootfs clean
make firmware
```

Optional check:

```bash
make run-qemu
```

## Kernel panic: No working init found

### Log

```text
[    0.689174] Failed to execute /init (error -2)
[    0.696213] Kernel panic - not syncing: No working init found.
```

### Cause

The initramfs contained `/init`, but `busybox` pointed to a loader path that was not present in the image.

### Recovery

Rebuild the rootfs.

```bash
make firmware
make run-qemu
```

If this happened after switching environments, clean old rootfs app artifacts first:

```bash
make -C firmware/riscv-rootfs clean
make firmware
```

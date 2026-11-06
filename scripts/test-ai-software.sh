#!/usr/bin/env bash
# Host-only integration gate. No downloads, model conversion, simulator or board.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
rootfs="$root/firmware/riscv-rootfs"
export XSAI_ENV_ROOT="$root"

for component in software/MNN software/ncnn software/llama.cpp firmware/riscv-rootfs xsai-blas; do
    if [[ ! -e "$root/$component/.git" ]]; then
        echo "error: $component is not initialized; run make software-init" >&2
        exit 1
    fi
    expected=$(git -C "$root" rev-parse "HEAD:$component")
    actual=$(git -C "$root/$component" rev-parse HEAD)
    if [[ "$actual" != "$expected" ]]; then
        echo "error: $component HEAD=$actual, parent pins $expected" >&2
        exit 1
    fi
    if ! git -C "$root/$component" diff --quiet HEAD --; then
        echo "warning: $component has local edits; this host gate does not validate their runtime behavior" >&2
    fi
done

for app in mnn ncnn llama.cpp; do
    make -C "$rootfs/apps/$app" source-ready
done
bash "$rootfs/apps/llama.cpp/tests/test-source-selection.sh"
python3 "$rootfs/rootfsimg/tests/test-ai-manifests.py" -v
python3 "$rootfs/rootfsimg/tests/test-ai-workloads.py" -v
python3 "$rootfs/apps/ncnn/tests/test-compare.py" -v
bash -n "$rootfs/rootfsimg/xsai-workloads.sh"
echo "[ai-software] host integration gates passed (no runtime/hardware claim)"

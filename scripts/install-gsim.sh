#!/usr/bin/env bash
# install-gsim.sh
# Downloads the latest gsim binary from OpenXiangShan/gsim releases
# and installs it to $XS_PROJECT_ROOT/local/bin (or $1 if provided).
#
# Usage:
#   ./scripts/install-gsim.sh              # installs to $XS_PROJECT_ROOT/local/bin
#   ./scripts/install-gsim.sh /custom/bin  # installs to /custom/bin

set -euo pipefail

REPO="OpenXiangShan/gsim"
INSTALL_DIR="${1:-${XS_PROJECT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}/local/bin}"

echo "[gsim] Fetching latest release info from github.com/${REPO} ..."

DOWNLOAD_URL=$(curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep '"browser_download_url"' \
    | head -1 \
    | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')

if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "[gsim] ERROR: could not parse download URL from GitHub API" >&2
    exit 1
fi

TAG=$(echo "$DOWNLOAD_URL" | sed 's|.*/download/\([^/]*\)/.*|\1|')
echo "[gsim] Latest release : ${TAG}"
echo "[gsim] Download URL   : ${DOWNLOAD_URL}"

mkdir -p "$INSTALL_DIR"
DEST="${INSTALL_DIR}/gsim"

# Skip download if already up-to-date (compare tag stored in a stamp file)
STAMP="${INSTALL_DIR}/.gsim-version"
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$TAG" && -x "$DEST" ]]; then
    echo "[gsim] Already up-to-date (${TAG}), skipping download."
    exit 0
fi

TMP=$(mktemp)
echo "[gsim] Downloading to ${DEST} ..."
curl -fSL --progress-bar --retry 5 --retry-delay 3 -o "$TMP" -L "$DOWNLOAD_URL"
chmod +x "$TMP"
mv "$TMP" "$DEST"
echo "$TAG" > "$STAMP"

echo "[gsim] Installed gsim ${TAG} -> ${DEST}"
"$DEST" --version 2>/dev/null || true

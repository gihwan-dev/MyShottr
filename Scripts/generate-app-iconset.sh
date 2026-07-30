#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${REPO_ROOT}/Assets/AppIcon/QuickInk-1024.png"
DESTINATION="${REPO_ROOT}/Resources/Assets.xcassets/AppIcon.appiconset"

test -f "${SOURCE}"
mkdir -p "${DESTINATION}"

sips -z 16 16 "${SOURCE}" --out "${DESTINATION}/icon_16x16.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${DESTINATION}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "${SOURCE}" --out "${DESTINATION}/icon_32x32.png" >/dev/null
sips -z 64 64 "${SOURCE}" --out "${DESTINATION}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "${SOURCE}" --out "${DESTINATION}/icon_128x128.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${DESTINATION}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "${SOURCE}" --out "${DESTINATION}/icon_256x256.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${DESTINATION}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "${SOURCE}" --out "${DESTINATION}/icon_512x512.png" >/dev/null
cp "${SOURCE}" "${DESTINATION}/icon_512x512@2x.png"
cp "${REPO_ROOT}/Assets/StatusBar/QuickInkStatus.svg" \
  "${REPO_ROOT}/Resources/Assets.xcassets/StatusBarIcon.imageset/QuickInkStatus.svg"

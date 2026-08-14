#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY_FILE="${ROOT}/Config/SparklePublicEDKey.txt"
CHANNEL="${INKBEAM_RELEASE_CHANNEL:-stable}"

test -f "${KEY_FILE}"
KEY="$(tr -d '\r\n' < "${KEY_FILE}")"
[[ "${KEY}" =~ '^[A-Za-z0-9+/]{43}=$' ]]

case "${CHANNEL}" in
  beta)
    FEED='https://gihwan-dev.github.io/inkbeam/appcast-beta.xml'
    CHANNEL_NAME='Release Candidate'
    ;;
  stable)
    FEED='https://gihwan-dev.github.io/inkbeam/appcast.xml'
    CHANNEL_NAME='Stable'
    ;;
  *)
    echo 'INKBEAM_RELEASE_CHANNEL must be beta or stable' >&2
    exit 64
    ;;
esac

cd "${ROOT}"
INKBEAM_GENERATED_APPCAST_URL="${FEED}" \
INKBEAM_SPARKLE_PUBLIC_KEY="${KEY}" \
INKBEAM_GENERATED_CHANNEL_NAME="${CHANNEL_NAME}" \
xcodegen generate

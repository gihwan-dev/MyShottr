#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

openssl genrsa -out "${TEMP_DIR}/extension-private.pem" 2048
openssl rsa -in "${TEMP_DIR}/extension-private.pem" \
  -pubout -outform DER 2>/dev/null \
  | openssl base64 -A \
  > "${REPO_ROOT}/Config/chrome-extension-key.b64"

chmod 0644 "${REPO_ROOT}/Config/chrome-extension-key.b64"

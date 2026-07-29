#!/bin/zsh
set -euo pipefail

REPO_ROOT="${SRCROOT}"
EDITOR_DIR="${REPO_ROOT}/Packages/editor"
OUTPUT_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Editor"

cd "${EDITOR_DIR}"
pnpm build
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
cp -R dist/. "${OUTPUT_DIR}/"

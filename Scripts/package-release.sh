#!/bin/zsh
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  echo "package-release: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command '${command_name}' is unavailable"
}

verify_no_distribution_signature() {
  local target_path="$1"
  local label="$2"
  local signature_details=""

  if signature_details="$(
    codesign --display --verbose=4 "${target_path}" 2>&1
  )"; then
    [[ "${signature_details}" == *"Signature=adhoc"* ]] \
      || fail "${label} has an unexpected non-ad-hoc signature"
    [[ "${signature_details}" != *$'\nAuthority='* ]] \
      || fail "${label} unexpectedly has a signing authority"
    [[ "${signature_details}" == *"TeamIdentifier=not set"* ]] \
      || fail "${label} unexpectedly has a signing team"
  fi
}

normalize_zip_timestamps() {
  local archive_path="$1"

  node --input-type=module - "${archive_path}" <<'NODE'
import { readFileSync, renameSync, writeFileSync } from "node:fs";

const archivePath = process.argv[2];
const normalizedPath = `${archivePath}.normalized`;
const archive = readFileSync(archivePath);
const eocdSignature = 0x06054b50;
const centralSignature = 0x02014b50;
const localSignature = 0x04034b50;
const fixedUnixTime = 946684800;
const fixedDosTime = 0;
const fixedDosDate = ((2000 - 1980) << 9) | (1 << 5) | 1;

function fail(message) {
  process.stderr.write(`package-release: ${message}\n`);
  process.exit(1);
}

function locateEndOfCentralDirectory() {
  const minimum = Math.max(0, archive.length - 65_557);
  for (let offset = archive.length - 22; offset >= minimum; offset -= 1) {
    if (archive.readUInt32LE(offset) === eocdSignature) return offset;
  }
  fail(`could not locate ZIP central directory in ${archivePath}`);
}

function normalizeExtraFields(offset, length) {
  const end = offset + length;
  let cursor = offset;
  while (cursor < end) {
    if (cursor + 4 > end) fail(`malformed ZIP extra field in ${archivePath}`);
    const identifier = archive.readUInt16LE(cursor);
    const size = archive.readUInt16LE(cursor + 2);
    const dataOffset = cursor + 4;
    const next = dataOffset + size;
    if (next > end) fail(`malformed ZIP extra field in ${archivePath}`);

    if (identifier === 0x5855 && size >= 8) {
      archive.writeUInt32LE(fixedUnixTime, dataOffset);
      archive.writeUInt32LE(fixedUnixTime, dataOffset + 4);
    } else if (identifier === 0x5455 && size >= 5) {
      const flags = archive.readUInt8(dataOffset);
      let timeOffset = dataOffset + 1;
      for (const flag of [1, 2, 4]) {
        if ((flags & flag) !== 0) {
          if (timeOffset + 4 > next) {
            fail(`malformed ZIP timestamp field in ${archivePath}`);
          }
          archive.writeUInt32LE(fixedUnixTime, timeOffset);
          timeOffset += 4;
        }
      }
    }
    cursor = next;
  }
}

const eocdOffset = locateEndOfCentralDirectory();
const entryCount = archive.readUInt16LE(eocdOffset + 10);
const centralSize = archive.readUInt32LE(eocdOffset + 12);
const centralOffset = archive.readUInt32LE(eocdOffset + 16);
if (
  entryCount === 0xffff
  || centralSize === 0xffffffff
  || centralOffset === 0xffffffff
) {
  fail("ZIP64 release archives are not supported");
}

let centralCursor = centralOffset;
for (let index = 0; index < entryCount; index += 1) {
  if (
    centralCursor + 46 > archive.length
    || archive.readUInt32LE(centralCursor) !== centralSignature
  ) {
    fail(`malformed ZIP central entry in ${archivePath}`);
  }

  archive.writeUInt16LE(fixedDosTime, centralCursor + 12);
  archive.writeUInt16LE(fixedDosDate, centralCursor + 14);

  const filenameLength = archive.readUInt16LE(centralCursor + 28);
  const extraLength = archive.readUInt16LE(centralCursor + 30);
  const commentLength = archive.readUInt16LE(centralCursor + 32);
  const localOffset = archive.readUInt32LE(centralCursor + 42);
  normalizeExtraFields(centralCursor + 46 + filenameLength, extraLength);

  if (
    localOffset + 30 > archive.length
    || archive.readUInt32LE(localOffset) !== localSignature
  ) {
    fail(`malformed ZIP local entry in ${archivePath}`);
  }
  archive.writeUInt16LE(fixedDosTime, localOffset + 10);
  archive.writeUInt16LE(fixedDosDate, localOffset + 12);
  const localFilenameLength = archive.readUInt16LE(localOffset + 26);
  const localExtraLength = archive.readUInt16LE(localOffset + 28);
  normalizeExtraFields(
    localOffset + 30 + localFilenameLength,
    localExtraLength,
  );

  centralCursor +=
    46 + filenameLength + extraLength + commentLength;
}
if (centralCursor !== centralOffset + centralSize) {
  fail(`ZIP central directory size mismatch in ${archivePath}`);
}

writeFileSync(normalizedPath, archive, { mode: 0o644 });
renameSync(normalizedPath, archivePath);
NODE
}

VERSION="${1:-}"
if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo 'version must match [0-9]+\.[0-9]+\.[0-9]+' >&2
  exit 64
fi

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h}"
EXPECTED_OUTPUT_ROOT="${REPO_ROOT}/dist/release/${VERSION}"
OUTPUT_PARENT="${REPO_ROOT}/dist/release"
TEMP_PARENT="${${TMPDIR:-/tmp}:A}"
TEMP_ROOT=""

cleanup() {
  [[ -n "${TEMP_ROOT}" ]] || return 0
  case "${TEMP_ROOT}" in
    "${TEMP_PARENT%/}/myshottr-release."*)
      rm -rf "${TEMP_ROOT}"
      ;;
    *)
      echo "package-release: refusing to clean unexpected temporary path: ${TEMP_ROOT}" >&2
      return 1
      ;;
  esac
}

remove_existing_output() {
  local target_path="$1"
  [[ "${target_path}" == "${EXPECTED_OUTPUT_ROOT}" ]] \
    || fail "refusing to clean unexpected output path: ${target_path}"
  [[ ! -L "${target_path}" ]] \
    || fail "refusing to replace symbolic-link output path: ${target_path}"
  if [[ -e "${target_path}" ]]; then
    [[ -d "${target_path}" ]] \
      || fail "release output path exists and is not a directory: ${target_path}"
    rm -rf "${target_path}"
  fi
}

[[ -f "${REPO_ROOT}/pnpm-lock.yaml" ]] \
  || fail "repository root could not be resolved from ${SCRIPT_PATH}"

require_command git
require_command node

GIT_ROOT="$(
  git -C "${REPO_ROOT}" rev-parse --show-toplevel 2>/dev/null
)" || fail "release packaging requires a Git worktree"
[[ "${GIT_ROOT:A}" == "${REPO_ROOT:A}" ]] \
  || fail "release packaging must run from the MyShottr Git root"

DIRTY_SOURCE="$(
  git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all
)"
[[ -z "${DIRTY_SOURCE}" ]] \
  || fail "source tree must be clean; ignored release output is the only allowed local output"

node --input-type=module - \
  "${REPO_ROOT}/project.yml" \
  "${REPO_ROOT}/Config/MyShottr-Info.plist" \
  "${REPO_ROOT}/Packages/chrome-extension/public/manifest.json" \
  "${VERSION}" <<'NODE'
import { readFileSync } from "node:fs";

const [projectPath, plistPath, manifestPath, version] = process.argv.slice(2);
const project = readFileSync(projectPath, "utf8");
const plist = readFileSync(plistPath, "utf8");
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));

function fail(message) {
  process.stderr.write(`package-release: ${message}\n`);
  process.exit(1);
}

const projectVersions = [
  ...project.matchAll(/CFBundleShortVersionString:\s*"([^"]+)"/g),
].map((match) => match[1]);
if (projectVersions.length !== 1 || projectVersions[0] !== version) {
  fail(`project.yml version does not equal ${version}`);
}

const plistMatch = plist.match(
  /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/,
);
if (plistMatch?.[1] !== version) {
  fail(`Config/MyShottr-Info.plist version does not equal ${version}`);
}
if (manifest.version !== version) {
  fail(`Chrome manifest version does not equal ${version}`);
}
NODE

for command_name in \
  pnpm xcodegen xcodebuild ditto shasum plutil codesign spctl find touch \
  mktemp mkdir mv rm; do
  require_command "${command_name}"
done

for path_component in \
  "${REPO_ROOT}/dist" \
  "${OUTPUT_PARENT}" \
  "${EXPECTED_OUTPUT_ROOT}"; do
  if [[ -e "${path_component}" || -L "${path_component}" ]]; then
    [[ ! -L "${path_component}" ]] \
      || fail "release output path contains a symbolic link: ${path_component}"
    [[ -d "${path_component}" ]] \
      || fail "release output path component is not a directory: ${path_component}"
  fi
done

TEMP_ROOT="$(
  mktemp -d "${TEMP_PARENT%/}/myshottr-release.XXXXXX"
)" || fail "could not create a temporary release root"
trap cleanup EXIT

BUILD_ROOT="${TEMP_ROOT}/build"
STAGING_ROOT="${TEMP_ROOT}/staging"
PACKAGE_ROOT="${TEMP_ROOT}/package"
mkdir -p "${BUILD_ROOT}" "${STAGING_ROOT}" "${PACKAGE_ROOT}"

cd "${REPO_ROOT}"

echo "==> Build production editor"
pnpm --filter @myshottr/editor build

echo "==> Build production Chrome extension"
pnpm --filter @myshottr/chrome-extension build

echo "==> Generate Xcode project"
xcodegen generate

echo "==> Build unsigned Release app"
xcodebuild build \
  -project "${REPO_ROOT}/MyShottr.xcodeproj" \
  -scheme MyShottr \
  -configuration Release \
  -derivedDataPath "${BUILD_ROOT}/DerivedData" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  GCC_GENERATE_DEBUGGING_SYMBOLS=NO \
  DEBUG_INFORMATION_FORMAT=

BUILT_APP="${BUILD_ROOT}/DerivedData/Build/Products/Release/MyShottr.app"
BUILT_EXTENSION="${REPO_ROOT}/Packages/chrome-extension/dist"
[[ -d "${BUILT_APP}" ]] || fail "Release app was not produced"
[[ -d "${BUILT_EXTENSION}" ]] || fail "Chrome extension was not produced"
[[ -x "${BUILT_APP}/Contents/MacOS/MyShottr" ]] \
  || fail "Release app main executable is missing"
[[ -x "${BUILT_APP}/Contents/Helpers/MyShottrNativeHost" ]] \
  || fail "Release app Native Messaging helper is missing"
[[ -f "${BUILT_EXTENSION}/manifest.json" ]] \
  || fail "built Chrome manifest is missing"
[[ -f "${BUILT_EXTENSION}/service-worker.js" ]] \
  || fail "built Chrome service worker is missing"

verify_no_distribution_signature "${BUILT_APP}" "Release app"
verify_no_distribution_signature \
  "${BUILT_APP}/Contents/Helpers/MyShottrNativeHost" \
  "embedded Native Messaging helper"
if spctl --assess --type execute "${BUILT_APP}" >/dev/null 2>&1; then
  fail "unsigned and unnotarized Release app was unexpectedly accepted by Gatekeeper"
fi

STAGED_APP="${STAGING_ROOT}/MyShottr.app"
STAGED_EXTENSION="${STAGING_ROOT}/MyShottr-Chrome-${VERSION}"
ditto --rsrc --extattr "${BUILT_APP}" "${STAGED_APP}"
ditto --norsrc --noextattr "${BUILT_EXTENSION}" "${STAGED_EXTENSION}"

find "${STAGED_APP}" "${STAGED_EXTENSION}" \
  -exec touch -h -t 200001010000 {} +

APP_ARCHIVE="${PACKAGE_ROOT}/MyShottr-${VERSION}-macos.zip"
EXTENSION_ARCHIVE="${PACKAGE_ROOT}/MyShottr-Chrome-${VERSION}.zip"
CHECKSUMS="${PACKAGE_ROOT}/SHA256SUMS.txt"

(
  cd "${STAGING_ROOT}"
  ditto -c -k --sequesterRsrc --keepParent \
    "MyShottr.app" "${APP_ARCHIVE}"
  ditto -c -k --norsrc --noextattr --keepParent \
    "MyShottr-Chrome-${VERSION}" "${EXTENSION_ARCHIVE}"
)

normalize_zip_timestamps "${APP_ARCHIVE}"
normalize_zip_timestamps "${EXTENSION_ARCHIVE}"

(
  cd "${PACKAGE_ROOT}"
  shasum -a 256 \
    "MyShottr-${VERSION}-macos.zip" \
    "MyShottr-Chrome-${VERSION}.zip" \
    >"${CHECKSUMS}"
)

"${REPO_ROOT}/Scripts/verify-release-artifacts.sh" \
  "${VERSION}" "${PACKAGE_ROOT}"

mkdir -p "${OUTPUT_PARENT}"
remove_existing_output "${EXPECTED_OUTPUT_ROOT}"
mv "${PACKAGE_ROOT}" "${EXPECTED_OUTPUT_ROOT}"

"${REPO_ROOT}/Scripts/verify-release-artifacts.sh" \
  "${VERSION}" "${EXPECTED_OUTPUT_ROOT}"

echo
echo "Release artifacts: ${EXPECTED_OUTPUT_ROOT}"
echo "WARNING: MyShottr ${VERSION} has no Developer ID identity and is not notarized."
echo "Link-time ad-hoc executable signatures may be present."

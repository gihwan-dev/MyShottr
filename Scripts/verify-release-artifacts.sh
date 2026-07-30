#!/bin/zsh
set -euo pipefail

export LC_ALL=C

fail() {
  echo "verify-release-artifacts: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command '${command_name}' is unavailable"
}

VERSION="${1:-}"
DIRECTORY_INPUT="${2:-}"
if [[ ! "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo 'version must match [0-9]+\.[0-9]+\.[0-9]+' >&2
  exit 64
fi
[[ -n "${DIRECTORY_INPUT}" ]] \
  || fail "usage: verify-release-artifacts.sh VERSION DIRECTORY"
[[ -d "${DIRECTORY_INPUT}" && ! -L "${DIRECTORY_INPUT}" ]] \
  || fail "artifact directory is missing, not a directory, or symbolic"

for command_name in node shasum ditto plutil codesign find cmp zipinfo; do
  require_command "${command_name}"
done

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h}"
DIRECTORY="${DIRECTORY_INPUT:A}"
APP_ARCHIVE="${DIRECTORY}/MyShottr-${VERSION}-macos.zip"
EXTENSION_ARCHIVE="${DIRECTORY}/MyShottr-Chrome-${VERSION}.zip"
CHECKSUMS="${DIRECTORY}/SHA256SUMS.txt"
SOURCE_EXTENSION_KEY="${REPO_ROOT}/Config/chrome-extension-key.b64"
TEMP_PARENT="${${TMPDIR:-/tmp}:A}"
TEMP_ROOT=""

cleanup() {
  [[ -n "${TEMP_ROOT}" ]] || return 0
  case "${TEMP_ROOT}" in
    "${TEMP_PARENT%/}/myshottr-release-verify."*)
      rm -rf "${TEMP_ROOT}"
      ;;
    *)
      echo "verify-release-artifacts: refusing to clean unexpected path: ${TEMP_ROOT}" >&2
      return 1
      ;;
  esac
}

for expected_file in \
  "${APP_ARCHIVE}" \
  "${EXTENSION_ARCHIVE}" \
  "${CHECKSUMS}" \
  "${SOURCE_EXTENSION_KEY}"; do
  [[ -f "${expected_file}" && ! -L "${expected_file}" ]] \
    || fail "required regular file is missing or symbolic: ${expected_file}"
done

ACTUAL_TOP_LEVEL="$(
  find "${DIRECTORY}" -mindepth 1 -maxdepth 1 -print \
    | LC_ALL=C sort
)"
EXPECTED_TOP_LEVEL="$(
  printf '%s\n' \
    "${APP_ARCHIVE}" \
    "${EXTENSION_ARCHIVE}" \
    "${CHECKSUMS}" \
    | LC_ALL=C sort
)"
[[ "${ACTUAL_TOP_LEVEL}" == "${EXPECTED_TOP_LEVEL}" ]] \
  || fail "artifact directory must contain exactly the two archives and SHA256SUMS.txt"

node --input-type=module - \
  "${CHECKSUMS}" \
  "MyShottr-${VERSION}-macos.zip" \
  "MyShottr-Chrome-${VERSION}.zip" <<'NODE'
import { readFileSync } from "node:fs";

const [checksumPath, appName, extensionName] = process.argv.slice(2);
const content = readFileSync(checksumPath, "utf8");
const lines = content.endsWith("\n")
  ? content.slice(0, -1).split("\n")
  : content.split("\n");
const expectedNames = [appName, extensionName];

function fail(message) {
  process.stderr.write(`verify-release-artifacts: ${message}\n`);
  process.exit(1);
}

if (lines.length !== 2) {
  fail("SHA256SUMS.txt must contain exactly two checksums");
}
for (const [index, line] of lines.entries()) {
  const match = line.match(/^([0-9a-f]{64})  ([A-Za-z0-9.-]+)$/);
  if (!match || match[2] !== expectedNames[index]) {
    fail("SHA256SUMS.txt contains an unexpected entry");
  }
}
NODE

(
  cd "${DIRECTORY}"
  shasum -a 256 -c SHA256SUMS.txt
)

inspect_archive() {
  local archive="$1"
  local expected_root="$2"
  local archive_kind="$3"

  node --input-type=module - \
    "${archive}" "${expected_root}" "${archive_kind}" <<'NODE'
import { spawnSync } from "node:child_process";

const [archive, expectedRoot, archiveKind] = process.argv.slice(2);

function fail(message) {
  process.stderr.write(`verify-release-artifacts: ${message}\n`);
  process.exit(1);
}

function runZipinfo(args) {
  const result = spawnSync("/usr/bin/zipinfo", args, {
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.status !== 0) {
    fail(`could not inspect ${archiveKind} archive`);
  }
  return result.stdout;
}

const entries = runZipinfo(["-1", archive])
  .split("\n")
  .filter((entry) => entry.length > 0);
if (entries.length === 0) {
  fail(`${archiveKind} archive is empty`);
}
if (new Set(entries).size !== entries.length) {
  fail("archive contains duplicate entries");
}

for (const entry of entries) {
  if (
    entry.startsWith("/")
    || entry.includes("\\")
    || entry.includes("//")
    || /[\u0000-\u001f\u007f]/.test(entry)
  ) {
    fail("archive contains unsafe path");
  }
  const components = entry.split("/");
  if (components.some((component) => component === "." || component === "..")) {
    fail("archive contains unsafe path");
  }

  const basename = components.at(-1) || components.at(-2) || "";
  if (
    basename === ".DS_Store"
    || basename === "Thumbs.db"
    || basename === ".Spotlight-V100"
  ) {
    fail("archive contains prohibited junk");
  }

  if (archiveKind === "extension") {
    if (components[0] !== expectedRoot || components[0] === "__MACOSX") {
      fail("extension archive has an unexpected root");
    }
    const lowercase = entry.toLowerCase();
    if (
      lowercase.endsWith(".pem")
      || lowercase.endsWith(".key")
      || lowercase.includes("private-key")
      || lowercase.includes("private_key")
    ) {
      fail("extension archive contains private key material");
    }
  } else if (components[0] === "__MACOSX") {
    if (
      (entry !== "__MACOSX/" && components[1] !== expectedRoot)
      || (!entry.endsWith("/") && !basename.startsWith("._"))
    ) {
      fail("app archive contains unexpected metadata");
    }
  } else if (components[0] !== expectedRoot) {
    fail("app archive has an unexpected root");
  }
}

const longListing = runZipinfo(["-l", archive]);
if (
  longListing
    .split("\n")
    .some((line) => /^l[rwx-]{9}\s/.test(line))
) {
  fail("archive contains symbolic link");
}
NODE
}

inspect_archive "${APP_ARCHIVE}" "MyShottr.app" "app"
inspect_archive \
  "${EXTENSION_ARCHIVE}" "MyShottr-Chrome-${VERSION}" "extension"

TEMP_ROOT="$(
  mktemp -d "${TEMP_PARENT%/}/myshottr-release-verify.XXXXXX"
)" || fail "could not create a temporary verification root"
trap cleanup EXIT

mkdir -p "${TEMP_ROOT}/app" "${TEMP_ROOT}/extension"
ditto -x -k "${APP_ARCHIVE}" "${TEMP_ROOT}/app"
ditto -x -k "${EXTENSION_ARCHIVE}" "${TEMP_ROOT}/extension"

APP="${TEMP_ROOT}/app/MyShottr.app"
EXTENSION="${TEMP_ROOT}/extension/MyShottr-Chrome-${VERSION}"
[[ -d "${APP}" && ! -L "${APP}" ]] \
  || fail "app archive did not contain the expected bundle root"
[[ -d "${EXTENSION}" && ! -L "${EXTENSION}" ]] \
  || fail "extension archive did not contain the expected root"

if find "${APP}" "${EXTENSION}" -type l -print -quit | grep -q .; then
  fail "archive contains symbolic link"
fi

APP_EXECUTABLE="${APP}/Contents/MacOS/MyShottr"
HELPER="${APP}/Contents/Helpers/MyShottrNativeHost"
INFO_PLIST="${APP}/Contents/Info.plist"
EDITOR_ROOT="${APP}/Contents/Resources/Editor"
EDITOR_INDEX="${EDITOR_ROOT}/index.html"
APP_EXTENSION_KEY="${APP}/Contents/Resources/chrome-extension-key.b64"
EXTENSION_MANIFEST="${EXTENSION}/manifest.json"
EXTENSION_WORKER="${EXTENSION}/service-worker.js"

for executable in "${APP_EXECUTABLE}" "${HELPER}"; do
  [[ -f "${executable}" && ! -L "${executable}" && -x "${executable}" ]] \
    || fail "app executable is missing, symbolic, or not executable: ${executable}"
done
for resource in \
  "${INFO_PLIST}" \
  "${APP}/Contents/Resources/Assets.car" \
  "${APP}/Contents/Resources/AppIcon.icns" \
  "${EDITOR_INDEX}" \
  "${APP_EXTENSION_KEY}" \
  "${EXTENSION_MANIFEST}" \
  "${EXTENSION_WORKER}"; do
  [[ -f "${resource}" && ! -L "${resource}" && -s "${resource}" ]] \
    || fail "required release resource is missing, symbolic, or empty: ${resource}"
done

MAIN_COUNT="$(
  find "${APP}" -type f -name MyShottr -print | wc -l | tr -d ' '
)"
HELPER_COUNT="$(
  find "${APP}" -type f -name MyShottrNativeHost -print | wc -l | tr -d ' '
)"
[[ "${MAIN_COUNT}" == "1" ]] \
  || fail "app archive must contain exactly one MyShottr executable"
[[ "${HELPER_COUNT}" == "1" ]] \
  || fail "app archive must contain exactly one Native Messaging helper"

[[ "$(
  plutil -extract CFBundleIdentifier raw "${INFO_PLIST}"
)" == "com.myshottr.app" ]] || fail "unexpected app bundle identifier"
[[ "$(
  plutil -extract CFBundleExecutable raw "${INFO_PLIST}"
)" == "MyShottr" ]] || fail "unexpected app executable name"
[[ "$(
  plutil -extract CFBundlePackageType raw "${INFO_PLIST}"
)" == "APPL" ]] || fail "unexpected app package type"
[[ "$(
  plutil -extract CFBundleShortVersionString raw "${INFO_PLIST}"
)" == "${VERSION}" ]] || fail "app version does not equal ${VERSION}"
[[ "$(
  plutil -extract LSMinimumSystemVersion raw "${INFO_PLIST}"
)" == "15.0" ]] || fail "minimum macOS version is not 15.0"
[[ "$(
  plutil -extract LSMultipleInstancesProhibited raw "${INFO_PLIST}"
)" == "true" ]] || fail "single-instance app contract is missing"

[[ ! -e "${APP}/Contents/_CodeSignature" ]] \
  || fail "unsigned release app unexpectedly contains a code signature"
[[ ! -e "${APP}/Contents/embedded.provisionprofile" ]] \
  || fail "unsigned release app unexpectedly contains a provisioning profile"
if codesign --display --verbose=2 "${APP}" >/dev/null 2>&1; then
  fail "release app is unexpectedly signed"
fi
if codesign --display --verbose=2 "${HELPER}" >/dev/null 2>&1; then
  fail "Native Messaging helper is unexpectedly signed"
fi

cmp -s "${SOURCE_EXTENSION_KEY}" "${APP_EXTENSION_KEY}" \
  || fail "app-bundled extension key differs from the committed public key"

node --input-type=module - \
  "${EDITOR_ROOT}" \
  "${EDITOR_INDEX}" \
  "${SOURCE_EXTENSION_KEY}" \
  "${APP_EXTENSION_KEY}" \
  "${EXTENSION_MANIFEST}" \
  "${EXTENSION_WORKER}" \
  "${VERSION}" <<'NODE'
import {
  lstatSync,
  readFileSync,
  realpathSync,
  readdirSync,
} from "node:fs";
import { dirname, relative, resolve, sep } from "node:path";

const [
  editorRoot,
  editorIndex,
  sourceKeyPath,
  appKeyPath,
  manifestPath,
  workerPath,
  version,
] = process.argv.slice(2);

function fail(message) {
  process.stderr.write(`verify-release-artifacts: ${message}\n`);
  process.exit(1);
}

function walk(directory) {
  const result = [];
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = resolve(directory, entry.name);
    if (entry.isSymbolicLink()) fail("release resource contains a symbolic link");
    if (entry.isDirectory()) result.push(...walk(path));
    else if (entry.isFile()) result.push(path);
    else fail("release resource contains a non-regular file");
  }
  return result;
}

const editorFiles = walk(editorRoot);
if (editorFiles.some((path) => path.endsWith(".map"))) {
  fail("editor bundle contains a source map");
}
const index = readFileSync(editorIndex, "utf8");
if (/https?:|data:|javascript:/i.test(index)) {
  fail("editor entrypoint contains a remote or inline resource URL");
}
const references = [
  ...index.matchAll(/\b(?:src|href)=["']([^"']+)["']/g),
].map((match) => match[1]);
if (
  !references.some((reference) => reference.endsWith(".js"))
  || !references.some((reference) => reference.endsWith(".css"))
) {
  fail("editor entrypoint must reference bundled JavaScript and CSS");
}
const rootRealPath = realpathSync(editorRoot);
for (const reference of references) {
  if (
    !reference.startsWith("./")
    || reference.includes("?")
    || reference.includes("#")
    || reference.includes("\\")
  ) {
    fail("editor entrypoint contains a non-canonical resource path");
  }
  const resourcePath = resolve(dirname(editorIndex), reference);
  const relativePath = relative(rootRealPath, realpathSync(resourcePath));
  if (relativePath.startsWith(`..${sep}`) || relativePath === "..") {
    fail("editor resource escapes its bundle root");
  }
  const stat = lstatSync(resourcePath);
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("editor resource is missing, non-regular, or symbolic");
  }
}

const sourceKey = readFileSync(sourceKeyPath, "utf8").trim();
const appKey = readFileSync(appKeyPath, "utf8").trim();
const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
const worker = readFileSync(workerPath, "utf8");
const exactCSP =
  "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-src 'none'; img-src 'self'; style-src 'self'";

if (manifest.manifest_version !== 3) fail("extension is not Manifest V3");
if (manifest.version !== version) fail("extension version mismatch");
if (
  JSON.stringify(manifest.permissions)
  !== JSON.stringify(["activeTab", "nativeMessaging"])
) {
  fail("extension permissions changed");
}
for (const forbiddenKey of [
  "optional_permissions",
  "host_permissions",
  "optional_host_permissions",
  "content_scripts",
]) {
  if (Object.hasOwn(manifest, forbiddenKey)) {
    fail(`extension contains prohibited ${forbiddenKey}`);
  }
}
if (
  manifest.content_security_policy?.extension_pages !== exactCSP
) {
  fail("extension CSP changed");
}
if (
  manifest.background?.service_worker !== "service-worker.js"
  || manifest.background?.type !== "module"
) {
  fail("extension service worker contract changed");
}
if (!sourceKey || manifest.key !== sourceKey || appKey !== sourceKey) {
  fail("extension identity key mismatch");
}
if (
  /__myshottrE2E|MYSHOTTR_E2E|E2E seam|TEST_PNG_DATA_URL/.test(worker)
) {
  fail("production extension contains a test seam");
}
NODE

EXTENSION_FILES="$(
  find "${EXTENSION}" -type f -print \
    | sed "s#^${EXTENSION}/##" \
    | LC_ALL=C sort
)"
[[ "${EXTENSION_FILES}" == $'manifest.json\nservice-worker.js' ]] \
  || fail "extension archive must contain only manifest.json and service-worker.js"

echo "Release artifact verification passed."
echo "WARNING: MyShottr ${VERSION} is intentionally unsigned and unnotarized."

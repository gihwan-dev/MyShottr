#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h}"
STABLE_DERIVED_DATA="${REPO_ROOT}/DerivedData/VerifyInkbeam-Stable"
RC_DERIVED_DATA="${REPO_ROOT}/DerivedData/VerifyInkbeam-RC"
APP_TEST_DERIVED_DATA="${REPO_ROOT}/DerivedData/VerifyInkbeam-AppTests"
TEST_BUILD_ROOT=""
PROJECT_NEEDS_STABLE_RESTORE=0

fail() {
  echo "verify-inkbeam: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  local install_hint="$2"

  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command '${command_name}' is unavailable. ${install_hint}"
}

require_minimum_major() {
  local label="$1"
  local version="$2"
  local minimum="$3"
  local major="${version%%.*}"

  [[ "${major}" == <-> ]] \
    || fail "could not parse ${label} version '${version}'."
  (( major >= minimum )) \
    || fail "${label} ${minimum}+ is required; found ${version}."
}

clean_derived_data() {
  local target_path="$1"

  case "${target_path}" in
    "${REPO_ROOT}/DerivedData/VerifyInkbeam-Stable"|\
    "${REPO_ROOT}/DerivedData/VerifyInkbeam-RC"|\
    "${REPO_ROOT}/DerivedData/VerifyInkbeam-AppTests")
      ;;
    *)
      fail "refusing to clean unexpected DerivedData path: ${target_path}"
      ;;
  esac
  rm -rf "${target_path}"
}

cleanup_test_build_root() {
  [[ -n "${TEST_BUILD_ROOT}" ]] || return 0
  case "${TEST_BUILD_ROOT}" in
    "${TEMP_PARENT%/}/inkbeam-verify."*)
      rm -rf "${TEST_BUILD_ROOT}"
      ;;
    *)
      echo "verify-inkbeam: refusing to clean unexpected temporary path: ${TEST_BUILD_ROOT}" >&2
      return 1
      ;;
  esac
}

restore_stable_project() {
  local generation_exit_code
  (( PROJECT_NEEDS_STABLE_RESTORE == 1 )) || return 0
  echo
  echo "==> Restore the generated Stable Xcode project"
  INKBEAM_RELEASE_CHANNEL=stable \
    "${REPO_ROOT}/Scripts/generate-project.sh" || {
      generation_exit_code="$?"
      return "${generation_exit_code}"
    }
  PROJECT_NEEDS_STABLE_RESTORE=0
}

cleanup() {
  local original_status="$?"
  local cleanup_status=0

  cleanup_test_build_root || cleanup_status=1
  restore_stable_project || cleanup_status=1

  if (( original_status != 0 )); then
    return "${original_status}"
  fi
  return "${cleanup_status}"
}

run_step() {
  local label="$1"
  local step_exit_code
  shift
  echo
  echo "==> ${label}"
  "$@" || {
    step_exit_code="$?"
    exit "${step_exit_code}"
  }
}

[[ -f "${REPO_ROOT}/pnpm-lock.yaml" ]] \
  || fail "repository root could not be resolved from ${SCRIPT_PATH}."

require_command node "Install Node.js 22 or newer."
require_command pnpm "Install pnpm 10 or newer."
require_command xcodegen "Install XcodeGen (for example: brew install xcodegen)."
require_command xcodebuild "Install Xcode 26 or newer and select it with xcode-select."
require_command codesign "Install the Xcode command-line tools."
require_command plutil "Install the macOS command-line tools."
require_command mktemp "Install the macOS command-line tools."
require_command pgrep "Install the macOS command-line tools."

NODE_VERSION="$(node --version)"
NODE_VERSION="${NODE_VERSION#v}"
PNPM_VERSION="$(pnpm --version)"
XCODE_VERSION="$(
  xcodebuild -version \
    | awk '/^Xcode / { print $2 }'
)"
MACOS_VERSION="$(sw_vers -productVersion)"

require_minimum_major "Node.js" "${NODE_VERSION}" 22
require_minimum_major "pnpm" "${PNPM_VERSION}" 10
require_minimum_major "Xcode" "${XCODE_VERSION}" 26
require_minimum_major "macOS" "${MACOS_VERSION}" 15

if RUNNING_INKBEAM_PIDS="$(pgrep -x Inkbeam)"; then
  RUNNING_INKBEAM_PIDS="${RUNNING_INKBEAM_PIDS//$'\n'/, }"
  fail "quit every running Inkbeam app before verification (PIDs: ${RUNNING_INKBEAM_PIDS})."
fi

TEMP_PARENT="${TMPDIR:-/tmp}"
TEST_BUILD_ROOT="$(
  mktemp -d "${TEMP_PARENT%/}/inkbeam-verify.XXXXXX"
)" || fail "could not create the temporary test build root."
HOST_TEST_DERIVED_DATA="${TEST_BUILD_ROOT}/HostTests"
trap cleanup EXIT

echo "Inkbeam automated verification"
echo "Repository: ${REPO_ROOT}"
echo "Node.js: ${NODE_VERSION}"
echo "pnpm: ${PNPM_VERSION}"
echo "Xcode: ${XCODE_VERSION}"
echo "macOS: ${MACOS_VERSION}"

cd "${REPO_ROOT}"

PROJECT_NEEDS_STABLE_RESTORE=1
run_step "Generate the Stable Xcode project" \
  env INKBEAM_RELEASE_CHANNEL=stable \
  "${REPO_ROOT}/Scripts/generate-project.sh"
run_step "Install locked JavaScript dependencies" \
  pnpm install --frozen-lockfile
run_step "Run TypeScript unit tests" pnpm test
run_step "Type-check TypeScript packages" pnpm typecheck
run_step "Build editor and production Chrome extension" pnpm build
run_step "Install the pinned Playwright Chromium runtime" \
  pnpm --filter @inkbeam/chrome-extension exec playwright install chromium
run_step "Run editor visual and accessibility tests" \
  pnpm --filter @inkbeam/editor test:visual
run_step "Run Chrome extension integration tests" \
  pnpm --filter @inkbeam/chrome-extension exec playwright test
run_step "Verify the Inkbeam clean cutover" \
  node "${REPO_ROOT}/Scripts/verify-clean-cutover.mjs"
run_step "Run release workflow, packaging, and documentation contracts" \
  pnpm test:release

clean_derived_data "${STABLE_DERIVED_DATA}"
clean_derived_data "${RC_DERIVED_DATA}"
clean_derived_data "${APP_TEST_DERIVED_DATA}"

run_step "Run Inkbeam app tests" \
  xcodebuild test \
    -project "${REPO_ROOT}/Inkbeam.xcodeproj" \
    -scheme Inkbeam \
    -destination "platform=macOS" \
    -derivedDataPath "${APP_TEST_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO

run_step "Run Native Messaging host tests" \
  xcodebuild test \
    -project "${REPO_ROOT}/Inkbeam.xcodeproj" \
    -scheme InkbeamNativeHost \
    -destination "platform=macOS" \
    -derivedDataPath "${HOST_TEST_DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    GENERATE_INFOPLIST_FILE=YES

run_step "Build a clean signed Stable Debug app" \
  xcodebuild build \
    -project "${REPO_ROOT}/Inkbeam.xcodeproj" \
    -scheme Inkbeam \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "${STABLE_DERIVED_DATA}"

APP="${STABLE_DERIVED_DATA}/Build/Products/Debug/Inkbeam.app"
APP_EXECUTABLE="${APP}/Contents/MacOS/Inkbeam"
HELPER="${APP}/Contents/Helpers/InkbeamNativeHost"
EDITOR_ENTRYPOINT="${APP}/Contents/Resources/Editor/index.html"
APP_EXTENSION_KEY="${APP}/Contents/Resources/chrome-extension-key.b64"
SOURCE_EXTENSION_KEY="${REPO_ROOT}/Config/chrome-extension-key.b64"
EXTENSION_MANIFEST="${REPO_ROOT}/Packages/chrome-extension/dist/manifest.json"
EXTENSION_WORKER="${REPO_ROOT}/Packages/chrome-extension/dist/service-worker.js"

run_step "Verify the effective Stable updater and privacy configuration" \
  "${REPO_ROOT}/Scripts/verify-privacy.sh" stable "${APP}"

echo
echo "==> Verify signed app, helper, editor, and extension artifacts"
[[ -d "${APP}" ]] || fail "signed Debug app is missing: ${APP}"
[[ -x "${APP_EXECUTABLE}" ]] \
  || fail "app executable is missing or not executable: ${APP_EXECUTABLE}"
[[ -x "${HELPER}" ]] \
  || fail "embedded Native Messaging helper is missing or not executable: ${HELPER}"
[[ -f "${APP}/Contents/Resources/Assets.car" ]] \
  || fail "compiled app assets are missing."
[[ -f "${EDITOR_ENTRYPOINT}" ]] \
  || fail "bundled editor entrypoint is missing."
[[ -f "${APP_EXTENSION_KEY}" ]] \
  || fail "bundled Chrome extension key is missing."
[[ -f "${EXTENSION_MANIFEST}" ]] \
  || fail "built Chrome extension manifest is missing."
[[ -f "${EXTENSION_WORKER}" ]] \
  || fail "built Chrome extension service worker is missing."

cmp -s "${SOURCE_EXTENSION_KEY}" "${APP_EXTENSION_KEY}" \
  || fail "the app-bundled Chrome extension key differs from the committed key."

[[ "$(
  plutil -extract CFBundleIdentifier raw "${APP}/Contents/Info.plist"
)" == "dev.gihwan.inkbeam" ]] || fail "unexpected app bundle identifier."
[[ "$(
  plutil -extract CFBundleShortVersionString raw "${APP}/Contents/Info.plist"
)" == "0.2.0" ]] || fail "unexpected app version."
[[ "$(
  plutil -extract LSMinimumSystemVersion raw "${APP}/Contents/Info.plist"
)" == "15.0" ]] || fail "unexpected minimum macOS version."

node --input-type=module - \
  "${SOURCE_EXTENSION_KEY}" \
  "${EXTENSION_MANIFEST}" <<'NODE'
import { promises as fs } from "node:fs";

const [keyPath, manifestPath] = process.argv.slice(2);
const expectedKey = (await fs.readFile(keyPath, "utf8")).trim();
const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

assert(manifest.manifest_version === 3, "built extension is not Manifest V3");
assert(manifest.version === "0.2.0", "built extension version is not 0.2.0");
assert(
  JSON.stringify(manifest.permissions) ===
    JSON.stringify(["activeTab", "nativeMessaging"]),
  "built extension permissions changed",
);
for (const forbiddenKey of [
  "optional_permissions",
  "host_permissions",
  "optional_host_permissions",
  "content_scripts",
]) {
  assert(!Object.hasOwn(manifest, forbiddenKey), `built extension contains ${forbiddenKey}`);
}
assert(manifest.key === expectedKey, "built extension key differs from committed key");
assert(
  manifest.background?.service_worker === "service-worker.js"
    && manifest.background?.type === "module",
  "built extension service worker contract changed",
);
NODE

codesign --verify --deep --strict --verbose=2 "${APP}"
codesign --verify --strict --verbose=2 "${HELPER}"
codesign --display --verbose=2 "${APP}" >/dev/null
codesign --display --verbose=2 "${HELPER}" >/dev/null

run_step "Generate the Release Candidate Xcode project" \
  env INKBEAM_RELEASE_CHANNEL=beta \
  "${REPO_ROOT}/Scripts/generate-project.sh"

run_step "Build a clean Release Candidate Debug app" \
  xcodebuild build \
    -project "${REPO_ROOT}/Inkbeam.xcodeproj" \
    -scheme Inkbeam \
    -configuration Debug \
    -destination "platform=macOS" \
    -derivedDataPath "${RC_DERIVED_DATA}"

RC_APP="${RC_DERIVED_DATA}/Build/Products/Debug/Inkbeam.app"
run_step "Verify the effective Release Candidate updater and privacy configuration" \
  "${REPO_ROOT}/Scripts/verify-privacy.sh" beta "${RC_APP}"

restore_stable_project || {
  stable_restore_exit_code="$?"
  exit "${stable_restore_exit_code}"
}

echo
echo "Inkbeam automated verification passed."
echo "Signed Stable Debug app: ${APP}"
echo "Release Candidate Debug app: ${RC_APP}"

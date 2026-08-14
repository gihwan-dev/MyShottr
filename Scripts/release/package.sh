#!/bin/zsh
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  echo "package: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command '${command_name}' is unavailable"
}

assert_safe_directory_surface() {
  local candidate_path="$1"
  local label="$2"
  local relative_path=""
  local component=""
  local current_path=""

  [[ "${candidate_path}" == "${REPO_ROOT}/"* ]] \
    || fail "${label} must stay inside the repository: ${candidate_path}"
  relative_path="${candidate_path#${REPO_ROOT}/}"
  [[ -n "${relative_path}" && "${relative_path}" != *".."* ]] \
    || fail "${label} must stay inside the repository: ${candidate_path}"

  current_path="${REPO_ROOT}"
  for component in "${(@s:/:)relative_path}"; do
    [[ -n "${component}" && "${component}" != "." && "${component}" != ".." ]] \
      || fail "${label} contains an unsafe path component: ${candidate_path}"
    current_path="${current_path}/${component}"
    if [[ -L "${current_path}" ]]; then
      fail "${label} cannot traverse a symbolic link: ${candidate_path}"
    fi
    if [[ -e "${current_path}" && ! -d "${current_path}" ]]; then
      fail "${label} must resolve to directories only: ${candidate_path}"
    fi
  done
}

prepare_directory() {
  local directory_path="$1"
  local label="$2"
  assert_safe_directory_surface "${directory_path}" "${label}"
  if [[ -e "${directory_path}" ]]; then
    [[ -d "${directory_path}" && ! -L "${directory_path}" ]] \
      || fail "${label} is not a safe directory: ${directory_path}"
    rm -rf "${directory_path}"
  fi
  mkdir -p "${directory_path}"
}

parse_contract_field() {
  local field_name="$1"
  node --input-type=module - "${REPO_ROOT}" "${TAG}" "${field_name}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag, field] = process.argv.slice(2);
const { contractFor, releaseChannelLabel } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-contract.mjs`).href
);
const contract = contractFor(tag);
if (field === "channelLabel") {
  process.stdout.write(`${releaseChannelLabel(contract.channel)}\n`);
} else if (field === "chromeRoot") {
  process.stdout.write(`${contract.chromeZip.replace(/\.zip$/, "")}\n`);
} else {
  process.stdout.write(`${contract[field]}\n`);
}
NODE
}

read_submission_receipt_id() {
  local receipt_path="$1"
  [[ -f "${receipt_path}" ]] || return 1
  node --input-type=module - "${receipt_path}" <<'NODE'
import fs from "node:fs";

const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const submissionID = payload.id ?? payload.submissionId ?? payload.submissionID;
if (typeof submissionID !== "string" || submissionID.length === 0) {
  process.exit(1);
}
process.stdout.write(`${submissionID}\n`);
NODE
}

load_or_create_state_json() {
  local state_path="$1"
  if [[ -f "${state_path}" ]]; then
    node --input-type=module - "${REPO_ROOT}" "${TAG}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag] = process.argv.slice(2);
const { loadReleaseState } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
process.stdout.write(`${JSON.stringify(loadReleaseState(repoRoot, tag))}\n`);
NODE
  else
    node --input-type=module - "${REPO_ROOT}" "${TAG}" "${VERSION}" "${BUILD}" "${CHANNEL}" "${DMG_NAME}" "${CHROME_ZIP_NAME}" "${RELEASE_TITLE}" "${EXPECTED_BRANCH}" "${EXPECTED_SHA}" "${INKBEAM_TEAM_ID}" "${INKBEAM_SIGNING_IDENTITY}" <<'NODE'
import { pathToFileURL } from "node:url";

const [
  repoRoot,
  tag,
  version,
  build,
  channel,
  dmg,
  chromeZip,
  releaseTitle,
  branch,
  sha,
  teamID,
  signingIdentity,
] = process.argv.slice(2);
const { createReleaseState } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
process.stdout.write(`${JSON.stringify(createReleaseState({
  contract: {
    tag,
    version,
    build: Number(build),
    channel,
    dmg,
    chromeZip,
    releaseTitle,
    prerelease: true,
  },
  source: { branch, sha },
  identity: {
    teamID,
    signingIdentity,
    appBundleID: "dev.gihwan.inkbeam",
    helperBundleID: "dev.gihwan.inkbeam.nativehost",
  },
}))}\n`);
NODE
  fi
}

advance_state_json() {
  local state_json="$1"
  local action="$2"
  local payload="${3:-}"
  STATE_JSON_INPUT="${state_json}" node --input-type=module - "${REPO_ROOT}" "${action}" "${payload}" <<'NODE'
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [repoRoot, action, payload] = process.argv.slice(2);
const state = JSON.parse(process.env.STATE_JSON_INPUT ?? "");
const {
  completePhase,
  recordNotarizationSubmission,
} = await import(pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href);

let next;
switch (action) {
  case "ensure-preflight":
    next = state.phases.preflight ? state : completePhase(state, "preflight");
    break;
  case "packaged":
    next = completePhase(state, "packaged");
    break;
  case "notarization-submitted":
    next = recordNotarizationSubmission(state, payload);
    break;
  default:
    throw new Error(`unsupported state action: ${action}`);
}
process.stdout.write(`${JSON.stringify(next)}\n`);
NODE
}

save_state_json() {
  local state_json="$1"
  STATE_JSON_INPUT="${state_json}" node --input-type=module - "${REPO_ROOT}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot] = process.argv.slice(2);
const { saveReleaseState } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
saveReleaseState(repoRoot, JSON.parse(process.env.STATE_JSON_INPUT ?? ""));
NODE
}

verify_signed_target() {
  local target_path="$1"
  local expected_identifier="$2"
  local label="$3"
  local details=""

  codesign --verify --strict --verbose=4 "${target_path}" >/dev/null 2>&1 \
    || fail "${label} failed codesign verification"
  details="$(codesign --display --verbose=4 "${target_path}" 2>&1)" \
    || fail "${label} does not expose a readable code signature"
  [[ "${details}" == *"Authority=${INKBEAM_SIGNING_IDENTITY}"* ]] \
    || fail "${label} must use ${INKBEAM_SIGNING_IDENTITY}"
  [[ "${details}" == *"TeamIdentifier=${INKBEAM_TEAM_ID}"* ]] \
    || fail "${label} must use team ${INKBEAM_TEAM_ID}"
  [[ "${details}" == *"Identifier=${expected_identifier}"* ]] \
    || fail "${label} must use bundle identifier ${expected_identifier}"
  [[ "${details}" == *"Timestamp="* ]] \
    || fail "${label} must contain a secure timestamp"
  [[ "${details}" == *"runtime"* || "${details}" == *"Runtime Version="* ]] \
    || fail "${label} must enable hardened runtime"
}

SCRIPT_PATH="${0:A}"
RELEASE_DIR="${SCRIPT_PATH:h}"
REPO_ROOT="${RELEASE_DIR:h:h}"
TAG="${1:-}"
EXPECTED_BRANCH="${2:-}"
EXPECTED_SHA="${3:-}"

[[ -n "${TAG}" && -n "${EXPECTED_BRANCH}" && -n "${EXPECTED_SHA}" ]] \
  || fail "usage: package.sh TAG EXPECTED_BRANCH EXPECTED_SHA"

for command_name in node xcodebuild codesign hdiutil xcrun ditto; do
  require_command "${command_name}"
done

: "${INKBEAM_TEAM_ID:?INKBEAM_TEAM_ID is required}"
: "${INKBEAM_SIGNING_IDENTITY:?INKBEAM_SIGNING_IDENTITY is required}"

VERSION="$(parse_contract_field version)"
BUILD="$(parse_contract_field build)"
CHANNEL="$(parse_contract_field channel)"
CHANNEL_NAME="$(parse_contract_field channelLabel)" || exit 1
DMG_NAME="$(parse_contract_field dmg)"
CHROME_ZIP_NAME="$(parse_contract_field chromeZip)"
CHROME_ROOT_NAME="$(parse_contract_field chromeRoot)"
RELEASE_TITLE="$(parse_contract_field releaseTitle)"

"${RELEASE_DIR}/preflight.sh" "${TAG}" "${EXPECTED_BRANCH}" "${EXPECTED_SHA}"

STATE_PATH="$(
  node --input-type=module - "${REPO_ROOT}" "${TAG}" <<'NODE'
import { pathToFileURL } from "node:url";
const [repoRoot, tag] = process.argv.slice(2);
const { statePathFor } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
process.stdout.write(`${statePathFor(repoRoot, tag)}\n`);
NODE
)"
STATE_JSON="$(load_or_create_state_json "${STATE_PATH}")"
if STATE_JSON_INPUT="${STATE_JSON}" node --input-type=module - <<'NODE'
const state = JSON.parse(process.env.STATE_JSON_INPUT ?? "");
process.exit(state.notarization?.submissionID ? 0 : 1);
NODE
then
  fail "notarization submission already recorded; use resume-notarization"
fi
STATE_JSON="$(advance_state_json "${STATE_JSON}" "ensure-preflight")"

PRIVATE_ROOT="${REPO_ROOT}/build/release-evidence/${TAG}/private"
assert_safe_directory_surface "${PRIVATE_ROOT}" "private evidence root"
mkdir -p "${PRIVATE_ROOT}"
SUBMISSION_RESULT="${PRIVATE_ROOT}/notary-submit.json"

if STATE_JSON_INPUT="${STATE_JSON}" node --input-type=module - <<'NODE'
const state = JSON.parse(process.env.STATE_JSON_INPUT ?? "");
process.exit(state.phases?.packaged ? 0 : 1);
NODE
then
  if RECOVERED_SUBMISSION_ID="$(read_submission_receipt_id "${SUBMISSION_RESULT}")"; then
    STATE_JSON="$(
      advance_state_json "${STATE_JSON}" "notarization-submitted" "${RECOVERED_SUBMISSION_ID}"
    )"
    save_state_json "${STATE_JSON}"
    echo "notarization receipt recovered; use resume-notarization" >&2
    exit 0
  fi
  fail "package phase already completed without a durable notarization receipt"
fi

OUTPUT_ROOT="${REPO_ROOT}/dist/release/${TAG}"
ARCHIVE_PATH="${OUTPUT_ROOT}/Inkbeam.xcarchive"
DMG_ROOT="${OUTPUT_ROOT}/dmg-root"
DMG_PATH="${OUTPUT_ROOT}/${DMG_NAME}"
CHROME_STAGE="${OUTPUT_ROOT}/${CHROME_ROOT_NAME}"
CHROME_ZIP_PATH="${OUTPUT_ROOT}/${CHROME_ZIP_NAME}"
assert_safe_directory_surface "${REPO_ROOT}/dist" "release output root"
mkdir -p "${REPO_ROOT}/dist/release"
prepare_directory "${OUTPUT_ROOT}" "release output root"
mkdir -p "${ARCHIVE_PATH:h}"

INKBEAM_RELEASE_CHANNEL="${CHANNEL}" "${REPO_ROOT}/Scripts/generate-project.sh"

xcodebuild archive \
  -project Inkbeam.xcodeproj \
  -scheme Inkbeam \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD}" \
  INKBEAM_RELEASE_CHANNEL_NAME="${CHANNEL_NAME}" \
  DEVELOPMENT_TEAM="${INKBEAM_TEAM_ID}" \
  CODE_SIGN_IDENTITY="${INKBEAM_SIGNING_IDENTITY}" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO

APP_PATH="${ARCHIVE_PATH}/Products/Applications/Inkbeam.app"
HELPER_PATH="${APP_PATH}/Contents/Helpers/InkbeamNativeHost"
SPARKLE_FRAMEWORK="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
SPARKLE_AUTOUPDATE="${SPARKLE_FRAMEWORK}/Versions/B/Autoupdate"
SPARKLE_UPDATER="${SPARKLE_FRAMEWORK}/Versions/B/Updater.app"
SPARKLE_DOWNLOADER="${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc"
SPARKLE_INSTALLER="${SPARKLE_FRAMEWORK}/Versions/B/XPCServices/Installer.xpc"

[[ -d "${APP_PATH}" ]] || fail "archived Inkbeam.app is missing"
verify_signed_target "${HELPER_PATH}" "dev.gihwan.inkbeam.nativehost" "native host"
verify_signed_target "${SPARKLE_AUTOUPDATE}" "Autoupdate-fixture" "Sparkle autoupdate"
verify_signed_target "${SPARKLE_UPDATER}" "org.sparkle-project.Sparkle.Updater" "Sparkle updater"
verify_signed_target "${SPARKLE_INSTALLER}" "org.sparkle-project.InstallerLauncher" "Sparkle installer"
verify_signed_target "${SPARKLE_FRAMEWORK}" "org.sparkle-project.Sparkle" "Sparkle framework"
verify_signed_target "${SPARKLE_DOWNLOADER}" "org.sparkle-project.DownloaderService" "Sparkle downloader"
verify_signed_target "${APP_PATH}" "dev.gihwan.inkbeam" "Inkbeam app"

prepare_directory "${DMG_ROOT}" "DMG staging root"
cp -R "${APP_PATH}" "${DMG_ROOT}/Inkbeam.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
  -volname Inkbeam \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"
codesign --force --timestamp --sign "${INKBEAM_SIGNING_IDENTITY}" "${DMG_PATH}" >/dev/null

EXTENSION_DIST="${REPO_ROOT}/Packages/chrome-extension/dist"
[[ -d "${EXTENSION_DIST}" ]] || fail "Chrome extension dist is missing"
prepare_directory "${CHROME_STAGE}" "Chrome staging root"
cp -R "${EXTENSION_DIST}/." "${CHROME_STAGE}/"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent \
  "${CHROME_STAGE}" "${CHROME_ZIP_PATH}"

STATE_JSON="$(advance_state_json "${STATE_JSON}" "packaged")"
save_state_json "${STATE_JSON}"

xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile inkbeam-notary \
  --output-format json > "${SUBMISSION_RESULT}"
SUBMISSION_ID="$(
  node --input-type=module - "${SUBMISSION_RESULT}" <<'NODE'
import fs from "node:fs";
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const submissionID = payload.id ?? payload.submissionId ?? payload.submissionID;
if (typeof submissionID !== "string" || submissionID.length === 0) {
  process.stderr.write("package: notarization submission did not return an id\n");
  process.exit(1);
}
process.stdout.write(`${submissionID}\n`);
NODE
)" || exit 1
STATE_JSON="$(
  advance_state_json "${STATE_JSON}" "notarization-submitted" "${SUBMISSION_ID}"
)"
save_state_json "${STATE_JSON}"

echo "packaged ${RELEASE_TITLE}" >&2

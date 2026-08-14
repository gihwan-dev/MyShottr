#!/bin/zsh
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  echo "resume-notarization: $*" >&2
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

parse_contract_field() {
  local field_name="$1"
  node --input-type=module - "${REPO_ROOT}" "${TAG}" "${field_name}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag, field] = process.argv.slice(2);
const { contractFor } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-contract.mjs`).href
);
const contract = contractFor(tag);
process.stdout.write(`${contract[field]}\n`);
NODE
}

update_state_status() {
  local notary_status="$1"
  node --input-type=module - "${REPO_ROOT}" "${TAG}" "${notary_status}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag, status] = process.argv.slice(2);
const {
  loadReleaseState,
  recordNotarizationStatus,
  saveReleaseState,
} = await import(pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href);
const updated = recordNotarizationStatus(loadReleaseState(repoRoot, tag), status);
saveReleaseState(repoRoot, updated);
process.stdout.write(`${JSON.stringify(updated)}\n`);
NODE
}

SCRIPT_PATH="${0:A}"
RELEASE_DIR="${SCRIPT_PATH:h}"
REPO_ROOT="${RELEASE_DIR:h:h}"
TAG="${1:-}"
[[ -n "${TAG}" ]] || fail "usage: resume-notarization.sh TAG"

for command_name in node xcrun codesign spctl; do
  require_command "${command_name}"
done

STATE_JSON="$(
  node --input-type=module - "${REPO_ROOT}" "${TAG}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag] = process.argv.slice(2);
const { loadReleaseState } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
process.stdout.write(`${JSON.stringify(loadReleaseState(repoRoot, tag))}\n`);
NODE
)" || exit 1
SUBMISSION_ID="$(
  STATE_JSON_INPUT="${STATE_JSON}" node --input-type=module - <<'NODE'
import fs from "node:fs";
const state = JSON.parse(process.env.STATE_JSON_INPUT ?? "");
if (typeof state.notarization?.submissionID !== "string" || state.notarization.submissionID.length === 0) {
  process.stderr.write("resume-notarization: notarization submission ID is missing\n");
  process.exit(1);
}
process.stdout.write(`${state.notarization.submissionID}\n`);
NODE
)" || exit 1

OUTPUT_ROOT="${REPO_ROOT}/dist/release/${TAG}"
DMG_NAME="$(parse_contract_field dmg)"
DMG_PATH="${OUTPUT_ROOT}/${DMG_NAME}"
APP_PATH="${OUTPUT_ROOT}/Inkbeam.xcarchive/Products/Applications/Inkbeam.app"
PRIVATE_ROOT="${REPO_ROOT}/build/release-evidence/${TAG}/private"
assert_safe_directory_surface "${PRIVATE_ROOT}" "private notarization log root"
mkdir -p "${PRIVATE_ROOT}"
INFO_PATH="${PRIVATE_ROOT}/notary-info.json"
LOG_PATH="${PRIVATE_ROOT}/notary-log.json"

xcrun notarytool info "${SUBMISSION_ID}" \
  --keychain-profile inkbeam-notary \
  --output-format json > "${INFO_PATH}"
STATUS="$(
  node --input-type=module - "${INFO_PATH}" <<'NODE'
import fs from "node:fs";
const payload = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const status = payload.status ?? payload.Status;
if (typeof status !== "string" || status.length === 0) {
  process.stderr.write("resume-notarization: notarization status is missing\n");
  process.exit(1);
}
process.stdout.write(`${status}\n`);
NODE
)" || exit 1

case "${STATUS}" in
  Submitted|"In Progress")
    update_state_status "${STATUS}" >/dev/null
    exit 0
    ;;
  Accepted|Invalid|Rejected)
    xcrun notarytool log "${SUBMISSION_ID}" \
      --keychain-profile inkbeam-notary \
      --output-format json > "${LOG_PATH}"
    ;;
  *)
    fail "unsupported notarization status: ${STATUS}"
    ;;
esac

update_state_status "${STATUS}" >/dev/null
[[ "${STATUS}" == "Accepted" ]] || fail "notarization status is ${STATUS}"

xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
codesign --verify --deep --strict --verbose=4 "${APP_PATH}" >/dev/null 2>&1 \
  || fail "accepted app failed deep codesign verification"
spctl --assess --type execute --verbose=4 "${APP_PATH}" >/dev/null 2>&1 \
  || fail "accepted app failed execute Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature \
  --verbose=4 "${DMG_PATH}" >/dev/null 2>&1 \
  || fail "accepted DMG failed open Gatekeeper assessment"

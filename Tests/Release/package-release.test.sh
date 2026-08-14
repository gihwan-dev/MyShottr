#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h:h}"
SOURCE_RELEASE_DIR="${REPO_ROOT}/Scripts/release"
TEST_ROOT="$(mktemp -d -t inkbeam-release-task3)"
[[ -d "${TEST_ROOT}" && ! -L "${TEST_ROOT}" ]] \
  || {
    echo "package-release.test: mktemp did not create a safe directory" >&2
    exit 1
  }
TEST_ROOT="${TEST_ROOT:A}"
TEST_ROOT_PARENT="${TEST_ROOT:h}"
BIN_ROOT="${TEST_ROOT}/bin"
TEMPLATE_REPO="${TEST_ROOT}/template-repo"
LOG_ROOT="${TEST_ROOT}/logs"

fail() {
  echo "package-release.test: $*" >&2
  exit 1
}

cleanup() {
  [[ "${INKBEAM_TEST_KEEP:-0}" == "1" ]] && return 0
  case "${TEST_ROOT:t}" in
    inkbeam-release-task3.*)
      [[ "${TEST_ROOT:h}" == "${TEST_ROOT_PARENT}" ]] \
        || {
          echo "package-release.test: refusing to clean moved path" >&2
          return 1
        }
      rm -rf "${TEST_ROOT}"
      ;;
    *)
      echo "package-release.test: refusing to clean unexpected path: ${TEST_ROOT}" >&2
      return 1
      ;;
  esac
}

expect_failure() {
  local label="$1"
  local expected_message="$2"
  local log_path="$3"
  shift 3
  if "$@" >"${log_path}" 2>&1; then
    fail "${label} unexpectedly succeeded"
  fi
  grep -Fq "${expected_message}" "${log_path}" \
    || {
      cat "${log_path}" >&2
      fail "${label} did not report '${expected_message}'"
    }
}

reset_logs() {
  rm -rf "${LOG_ROOT}"
  mkdir -p "${LOG_ROOT}"
}

make_fixture_repo() {
  local destination="$1"
  cp -R "${TEMPLATE_REPO}" "${destination}"
}

state_path_for() {
  local repo="$1"
  local tag="$2"
  node --input-type=module - "${repo}" "${tag}" <<'NODE'
import { pathToFileURL } from "node:url";
const [repoRoot, tag] = process.argv.slice(2);
const { statePathFor } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-state.mjs`).href
);
process.stdout.write(`${statePathFor(repoRoot, tag)}\n`);
NODE
}

read_state_field() {
  local state_path="$1"
  local expression="$2"
  node --input-type=module - "${state_path}" "${expression}" <<'NODE'
import fs from "node:fs";
const [statePath, expression] = process.argv.slice(2);
const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
const value = Function("state", `return (${expression});`)(state);
process.stdout.write(`${String(value)}\n`);
NODE
}

assert_log_absent() {
  local needle="$1"
  local log_path="$2"
  if grep -Fq "${needle}" "${log_path}" 2>/dev/null; then
    cat "${log_path}" >&2
    fail "unexpected log entry '${needle}'"
  fi
}

trap cleanup EXIT

mkdir -p "${BIN_ROOT}" "${LOG_ROOT}" "${TEMPLATE_REPO}/Scripts/release" \
  "${TEMPLATE_REPO}/Scripts" "${TEMPLATE_REPO}/Config" \
  "${TEMPLATE_REPO}/Packages/chrome-extension/dist"

cp "${SOURCE_RELEASE_DIR}/package.sh" "${TEMPLATE_REPO}/Scripts/release/package.sh"
cp "${SOURCE_RELEASE_DIR}/resume-notarization.sh" "${TEMPLATE_REPO}/Scripts/release/resume-notarization.sh"
cp "${SOURCE_RELEASE_DIR}/release-contract.mjs" "${TEMPLATE_REPO}/Scripts/release/release-contract.mjs"
cp "${SOURCE_RELEASE_DIR}/release-state.mjs" "${TEMPLATE_REPO}/Scripts/release/release-state.mjs"

cat > "${TEMPLATE_REPO}/Scripts/release/preflight.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'preflight %s %s %s\n' "$1" "$2" "$3" >> "${INKBEAM_TEST_LOG_ROOT}/preflight.log"
if [[ "${INKBEAM_TEST_PREFLIGHT_FAIL:-0}" == "1" ]]; then
  echo "preflight: synthetic failure" >&2
  exit 1
fi
EOF

cat > "${TEMPLATE_REPO}/Scripts/generate-project.sh" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'channel=%s\n' "${INKBEAM_RELEASE_CHANNEL:-missing}" >> "${INKBEAM_TEST_LOG_ROOT}/generate-project.log"
EOF

cat > "${TEMPLATE_REPO}/Packages/chrome-extension/dist/manifest.json" <<'EOF'
{"manifest_version":3,"name":"Inkbeam","version":"0.2.0"}
EOF
printf 'console.log("worker");\n' > "${TEMPLATE_REPO}/Packages/chrome-extension/dist/service-worker.js"
printf 'stale build must be replaced\n' \
  > "${TEMPLATE_REPO}/Packages/chrome-extension/dist/stale-sentinel.txt"

cat > "${BIN_ROOT}/xcodebuild" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'xcodebuild %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/xcodebuild.log"
[[ "${1:-}" == "archive" ]] || exit 1
archive_path=""
for (( index = 1; index <= $#; index += 1 )); do
  if [[ "${@[index]}" == "-archivePath" ]]; then
    archive_path="${@[index+1]}"
    break
  fi
done
[[ -n "${archive_path}" ]] || exit 1
app="${archive_path}/Products/Applications/Inkbeam.app"
sparkle="${app}/Contents/Frameworks/Sparkle.framework/Versions/B"
mkdir -p \
  "${app}/Contents/MacOS" \
  "${app}/Contents/Helpers" \
  "${sparkle}/Updater.app/Contents/MacOS" \
  "${sparkle}/XPCServices/Downloader.xpc/Contents/MacOS" \
  "${sparkle}/XPCServices/Installer.xpc/Contents/MacOS"
printf 'app\n' > "${app}/Contents/MacOS/Inkbeam"
printf 'helper\n' > "${app}/Contents/Helpers/InkbeamNativeHost"
printf 'autoupdate\n' > "${sparkle}/Autoupdate"
printf 'updater\n' > "${sparkle}/Updater.app/Contents/MacOS/Updater"
printf 'downloader\n' > "${sparkle}/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
if [[ "${INKBEAM_TEST_ARCHIVE_MODE:-complete}" != "missing-installer" ]]; then
  printf 'installer\n' > "${sparkle}/XPCServices/Installer.xpc/Contents/MacOS/Installer"
fi
chmod +x \
  "${app}/Contents/MacOS/Inkbeam" \
  "${app}/Contents/Helpers/InkbeamNativeHost" \
  "${sparkle}/Autoupdate" \
  "${sparkle}/Updater.app/Contents/MacOS/Updater" \
  "${sparkle}/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
[[ "${INKBEAM_TEST_ARCHIVE_MODE:-complete}" == "missing-installer" ]] \
  || chmod +x "${sparkle}/XPCServices/Installer.xpc/Contents/MacOS/Installer"
EOF

cat > "${BIN_ROOT}/codesign" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'codesign %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/codesign.log"
if [[ "$*" == *"--entitlements :-"* ]]; then
  if [[ "${INKBEAM_TEST_ENTITLEMENTS_MODE:-minimal}" == "debug" ]]; then
    printf '<plist><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>\n'
  else
    printf '<plist><dict/></plist>\n'
  fi
elif [[ "${1:-}" == "--display" ]]; then
  target="${@: -1}"
  case "${target}" in
    */Contents/Helpers/InkbeamNativeHost)
      if [[ "${INKBEAM_TEST_SIGNATURE_MODE:-valid}" == "wrong-helper-identifier" ]]; then
        identifier="dev.gihwan.inkbeam.nativehost.evil"
      else
        identifier="dev.gihwan.inkbeam.nativehost"
      fi
      ;;
    */Contents/XPCServices/Downloader.xpc)
      identifier="org.sparkle-project.Downloader"
      ;;
    */Contents/XPCServices/Installer.xpc)
      identifier="org.sparkle-project.InstallerLauncher"
      ;;
    */Sparkle.framework)
      identifier="org.sparkle-project.Sparkle"
      ;;
    */Inkbeam.app)
      identifier="dev.gihwan.inkbeam"
      ;;
    *.dmg)
      identifier="com.apple.disk-image"
      ;;
    *)
      identifier="unexpected"
      ;;
  esac
  cat <<OUT
Authority=${INKBEAM_SIGNING_IDENTITY}
TeamIdentifier=${INKBEAM_TEAM_ID}
Identifier=${identifier}
OUT
  if [[ "${INKBEAM_TEST_SIGNATURE_MODE:-valid}" == "duplicate-team" ]]; then
    printf 'TeamIdentifier=%s\n' "${INKBEAM_TEAM_ID}"
  fi
  [[ "${INKBEAM_TEST_SIGNATURE_MODE:-valid}" == "missing-timestamp" ]] \
    || printf 'Timestamp=2026-08-14T00:00:00Z\n'
  [[ "${INKBEAM_TEST_SIGNATURE_MODE:-valid}" == "missing-runtime" ]] \
    || printf 'flags=0x10000(runtime)\n'
fi
EOF

cat > "${BIN_ROOT}/lipo" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'lipo %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/lipo.log"
target="${@: -1}"
if [[ "${INKBEAM_TEST_ARCH_MODE:-universal}" == "thin-helper" \
  && "${target}" == */Contents/Helpers/InkbeamNativeHost ]]; then
  printf 'arm64\n'
else
  printf 'arm64 x86_64\n'
fi
EOF

cat > "${BIN_ROOT}/pnpm" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'pnpm version-name=%s %s\n' \
  "${INKBEAM_CHROME_VERSION_NAME:-missing}" "$*" \
  >> "${INKBEAM_TEST_LOG_ROOT}/pnpm.log"
[[ "$*" == "--filter @inkbeam/chrome-extension build" ]] || exit 1
[[ "${INKBEAM_TEST_CHROME_BUILD_MODE:-pass}" == "pass" ]] || exit 91
dist="${INKBEAM_TEST_REPO}/Packages/chrome-extension/dist"
rm -rf "${dist}"
mkdir -p "${dist}"
printf '{"manifest_version":3,"name":"Inkbeam","version":"0.2.0","version_name":"%s"}\n' \
  "${INKBEAM_CHROME_VERSION_NAME}" > "${dist}/manifest.json"
printf 'console.log("rebuilt worker");\n' > "${dist}/service-worker.js"
EOF

cat > "${BIN_ROOT}/hdiutil" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'hdiutil %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/hdiutil.log"
[[ "${1:-}" == "create" ]] || exit 1
srcfolder=""
output_path="${@: -1}"
for (( index = 1; index <= $#; index += 1 )); do
  if [[ "${@[index]}" == "-srcfolder" ]]; then
    srcfolder="${@[index+1]}"
    break
  fi
done
[[ -n "${srcfolder}" ]] || exit 1
entries=($(find "${srcfolder}" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort))
printf '%s\n' "${entries[@]}" > "${INKBEAM_TEST_LOG_ROOT}/dmg-entries.log"
if [[ -L "${srcfolder}/Applications" ]]; then
  printf 'Applications->%s\n' "$(readlink "${srcfolder}/Applications")" >> "${INKBEAM_TEST_LOG_ROOT}/dmg-entries.log"
fi
printf 'dmg\n' > "${output_path}"
EOF

cat > "${BIN_ROOT}/ditto" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'ditto %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/ditto.log"
if [[ "${1:-}" == "-c" ]]; then
  source_path="${@: -2:1}"
  output_path="${@: -1}"
  printf 'zip-root=%s\n' "$(basename "${source_path}")" >> "${INKBEAM_TEST_LOG_ROOT}/zip-root.log"
  printf 'zip\n' > "${output_path}"
else
  cp -R "${@: -2:1}" "${@: -1}"
fi
EOF

cat > "${BIN_ROOT}/xcrun" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'xcrun %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/xcrun.log"
if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then
  submit_count_path="${INKBEAM_TEST_LOG_ROOT}/notary-submit-count"
  submit_count=0
  [[ ! -f "${submit_count_path}" ]] \
    || submit_count="$(<"${submit_count_path}")"
  printf '%d\n' "$(( submit_count + 1 ))" > "${submit_count_path}"
  cat <<JSON
{"id":"${INKBEAM_TEST_SUBMISSION_ID}"}
JSON
  if [[ "${INKBEAM_TEST_BLOCK_STATE_AFTER_SUBMIT:-0}" == "1" ]]; then
    state_path="${INKBEAM_TEST_REPO}/build/release-evidence/${INKBEAM_TEST_TAG}/release-state.json"
    mv "${state_path}" "${state_path}.before-submit"
    ln -s "${state_path}.before-submit" "${state_path}"
  fi
elif [[ "${1:-}" == "notarytool" && "${2:-}" == "info" ]]; then
  cat <<JSON
{"id":"${INKBEAM_TEST_SUBMISSION_ID}","status":"${INKBEAM_TEST_NOTARY_STATUS}"}
JSON
elif [[ "${1:-}" == "notarytool" && "${2:-}" == "log" ]]; then
  cat <<JSON
{"log":"${INKBEAM_TEST_NOTARY_STATUS}"}
JSON
elif [[ "${1:-}" == "stapler" ]]; then
  if [[ "${2:-}" == "staple" \
    && "${INKBEAM_TEST_STAPLER_MODE:-pass}" == "fail" ]]; then
    echo "synthetic staple failure" >&2
    exit 1
  fi
  exit 0
else
  exit 1
fi
EOF

cat > "${BIN_ROOT}/spctl" <<'EOF'
#!/bin/zsh
set -euo pipefail
printf 'spctl %s\n' "$*" >> "${INKBEAM_TEST_LOG_ROOT}/spctl.log"
EOF

chmod +x \
  "${TEMPLATE_REPO}/Scripts/release/preflight.sh" \
  "${TEMPLATE_REPO}/Scripts/generate-project.sh" \
  "${BIN_ROOT}/xcodebuild" \
  "${BIN_ROOT}/codesign" \
  "${BIN_ROOT}/lipo" \
  "${BIN_ROOT}/pnpm" \
  "${BIN_ROOT}/hdiutil" \
  "${BIN_ROOT}/ditto" \
  "${BIN_ROOT}/xcrun" \
  "${BIN_ROOT}/spctl"

chmod +x \
  "${TEMPLATE_REPO}/Scripts/release/package.sh" \
  "${TEMPLATE_REPO}/Scripts/release/resume-notarization.sh"

(
  cd "${TEMPLATE_REPO}"
  git init -q
  git config user.email "release@example.invalid"
  git config user.name "Release Test"
  git checkout -qb fixture-release
  git add .
  git commit -qm "fixture"
)

run_package() {
  local repo="$1"
  local tag="$2"
  local branch="$3"
  local sha="$4"
  PATH="${BIN_ROOT}:$PATH" \
    INKBEAM_TEAM_ID="SLVS4WF9U2" \
    INKBEAM_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)" \
    INKBEAM_TEST_LOG_ROOT="${LOG_ROOT}" \
    INKBEAM_TEST_REPO="${repo}" \
    INKBEAM_TEST_TAG="${tag}" \
    INKBEAM_TEST_BLOCK_STATE_AFTER_SUBMIT="${INKBEAM_TEST_BLOCK_STATE_AFTER_SUBMIT:-0}" \
    INKBEAM_TEST_ARCHIVE_MODE="${INKBEAM_TEST_ARCHIVE_MODE:-complete}" \
    INKBEAM_TEST_ARCH_MODE="${INKBEAM_TEST_ARCH_MODE:-universal}" \
    INKBEAM_TEST_SIGNATURE_MODE="${INKBEAM_TEST_SIGNATURE_MODE:-valid}" \
    INKBEAM_TEST_ENTITLEMENTS_MODE="${INKBEAM_TEST_ENTITLEMENTS_MODE:-minimal}" \
    INKBEAM_TEST_CHROME_BUILD_MODE="${INKBEAM_TEST_CHROME_BUILD_MODE:-pass}" \
    INKBEAM_TEST_SUBMISSION_ID="12345678-1234-1234-1234-1234567890ab" \
    "${repo}/Scripts/release/package.sh" "${tag}" "${branch}" "${sha}"
}

run_resume() {
  local repo="$1"
  local tag="$2"
  local notary_status="$3"
  PATH="${BIN_ROOT}:$PATH" \
    INKBEAM_TEST_NOTARY_STATUS="${notary_status}" \
    INKBEAM_TEAM_ID="SLVS4WF9U2" \
    INKBEAM_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)" \
    INKBEAM_TEST_LOG_ROOT="${LOG_ROOT}" \
    INKBEAM_TEST_SUBMISSION_ID="12345678-1234-1234-1234-1234567890ab" \
    INKBEAM_TEST_STAPLER_MODE="${INKBEAM_TEST_STAPLER_MODE:-pass}" \
    "${repo}/Scripts/release/resume-notarization.sh" "${tag}"
}

FIXTURE_BRANCH="fixture-release"
FIXTURE_SHA="$(git -C "${TEMPLATE_REPO}" rev-parse HEAD)"

reset_logs
SUCCESS_REPO="${TEST_ROOT}/success-repo"
make_fixture_repo "${SUCCESS_REPO}"
run_package "${SUCCESS_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > "${TEST_ROOT}/package-success.log" 2>&1

grep -Fq "preflight v0.2.0-rc.1 ${FIXTURE_BRANCH} ${FIXTURE_SHA}" "${LOG_ROOT}/preflight.log" \
  || fail "package did not call preflight with the exact contract"
grep -Fq "channel=beta" "${LOG_ROOT}/generate-project.log" \
  || fail "package did not propagate beta channel to generate-project.sh"
grep -Fq "MARKETING_VERSION=0.2.0" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not set MARKETING_VERSION"
grep -Fq "CURRENT_PROJECT_VERSION=2" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not set CURRENT_PROJECT_VERSION"
grep -Fq "INKBEAM_RELEASE_CHANNEL_NAME=Release Candidate" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not map beta to Release Candidate"
grep -Fq "CODE_SIGN_STYLE=Manual" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not force manual signing"
grep -Fq "ENABLE_HARDENED_RUNTIME=YES" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not enable hardened runtime"
grep -Fq "OTHER_CODE_SIGN_FLAGS=--timestamp" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not require secure timestamps"
grep -Fq "ARCHS=arm64 x86_64" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not require a universal build"
assert_log_absent "CODE_SIGNING_ALLOWED=NO" "${LOG_ROOT}/xcodebuild.log"
assert_log_absent "CODE_SIGN_IDENTITY=-" "${LOG_ROOT}/xcodebuild.log"
grep -Fq "pnpm version-name=v0.2.0-rc.1 --filter @inkbeam/chrome-extension build" \
  "${LOG_ROOT}/pnpm.log" \
  || fail "package did not build Chrome with the contract version_name"
[[ ! -e "${SUCCESS_REPO}/Packages/chrome-extension/dist/stale-sentinel.txt" ]] \
  || fail "package reused stale Chrome dist instead of rebuilding it"
[[ "$(grep -c 'lipo -archs' "${LOG_ROOT}/lipo.log")" == "2" ]] \
  || fail "package did not inspect both app and helper architectures"
grep -Fxq "Applications" "${LOG_ROOT}/dmg-entries.log" \
  || fail "DMG staging did not include Applications symlink"
grep -Fxq "Inkbeam.app" "${LOG_ROOT}/dmg-entries.log" \
  || fail "DMG staging did not include Inkbeam.app"
grep -Fq "Applications->/Applications" "${LOG_ROOT}/dmg-entries.log" \
  || fail "DMG staging symlink target is wrong"
grep -Fq "zip-root=Inkbeam-Chrome-0.2.0-rc.1" "${LOG_ROOT}/zip-root.log" \
  || fail "Chrome ZIP root directory is wrong"
SUCCESS_APP="${SUCCESS_REPO}/build/release-evidence/v0.2.0-rc.1/private/Inkbeam.xcarchive/Products/Applications/Inkbeam.app"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify Sparkle Autoupdate"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify Sparkle Updater"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify Sparkle downloader"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify Sparkle installer"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Frameworks/Sparkle.framework" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify Sparkle framework"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}/Contents/Helpers/InkbeamNativeHost" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify the native helper"
grep -Fq "codesign --verify --strict --verbose=4 ${SUCCESS_APP}" "${LOG_ROOT}/codesign.log" \
  || fail "package did not verify the outer app"
grep -Fq "codesign --display --entitlements :- ${SUCCESS_APP}" "${LOG_ROOT}/codesign.log" \
  || fail "package did not inspect release entitlements"
PUBLIC_OUTPUT="${SUCCESS_REPO}/dist/release/v0.2.0-rc.1"
PUBLIC_ENTRIES="$(find "${PUBLIC_OUTPUT}" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)"
[[ "${PUBLIC_ENTRIES}" == $'Inkbeam-0.2.0-rc.1.dmg\nInkbeam-Chrome-0.2.0-rc.1.zip' ]] \
  || fail "public release output did not contain exactly the DMG and Chrome ZIP"
if grep -Eiq 'control[- ]click|right[- ]click|bypass|unsigned|ad[- ]hoc|\.app\.zip' \
  "${TEST_ROOT}/package-success.log"; then
  cat "${TEST_ROOT}/package-success.log" >&2
  fail "official package output contained prohibited distribution guidance"
fi
STATE_PATH="$(state_path_for "${SUCCESS_REPO}" "v0.2.0-rc.1")"
[[ -f "${STATE_PATH}" ]] || fail "package did not persist release state"
[[ "$(read_state_field "${STATE_PATH}" 'state.notarization.submissionID')" == "12345678-1234-1234-1234-1234567890ab" ]] \
  || fail "package did not atomically persist the notarization submission id"
[[ "$(read_state_field "${STATE_PATH}" 'Boolean(state.phases.packaged)')" == "true" ]] \
  || fail "package did not record the packaged phase"
[[ "$(read_state_field "${STATE_PATH}" 'Boolean(state.phases.notarizationSubmitted)')" == "true" ]] \
  || fail "package did not record the notarizationSubmitted phase"

expect_failure \
  "second package submission" \
  "notarization submission already recorded; use resume-notarization" \
  "${TEST_ROOT}/package-repeat.log" \
  run_package "${SUCCESS_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
submit_count="$(grep -c "notarytool submit" "${LOG_ROOT}/xcrun.log")"
[[ "${submit_count}" == "1" ]] || fail "package submitted notarization more than once"

reset_logs
RECOVERY_REPO="${TEST_ROOT}/submission-recovery-repo"
make_fixture_repo "${RECOVERY_REPO}"
INKBEAM_TEST_BLOCK_STATE_AFTER_SUBMIT=1 expect_failure \
  "state save failure after successful submit" \
  "release state target is a symbolic link" \
  "${TEST_ROOT}/submit-state-failure.log" \
  run_package "${RECOVERY_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
RECOVERY_STATE="$(state_path_for "${RECOVERY_REPO}" "v0.2.0-rc.1")"
[[ "$(<"${LOG_ROOT}/notary-submit-count")" == "1" ]] \
  || fail "failed state persistence did not issue exactly one notarization submit"
[[ -L "${RECOVERY_STATE}" && -f "${RECOVERY_STATE}.before-submit" ]] \
  || fail "fixture did not interrupt the authoritative state save after submit"
rm "${RECOVERY_STATE}"
mv "${RECOVERY_STATE}.before-submit" "${RECOVERY_STATE}"

if ! run_package \
  "${RECOVERY_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > "${TEST_ROOT}/submit-recovery.log" 2>&1; then
  cat "${TEST_ROOT}/submit-recovery.log" >&2
  fail "package did not recover the durable notarization receipt"
fi
grep -Fq "resume-notarization" "${TEST_ROOT}/submit-recovery.log" \
  || fail "recovered notarization did not direct the operator to resume-notarization"
[[ "$(<"${LOG_ROOT}/notary-submit-count")" == "1" ]] \
  || fail "package resubmitted notarization instead of recovering the durable receipt"
[[ "$(read_state_field "${RECOVERY_STATE}" 'state.notarization.submissionID')" \
  == "12345678-1234-1234-1234-1234567890ab" ]] \
  || fail "package did not recover the durable submission id into release state"
RECOVERY_RECEIPT="${RECOVERY_REPO}/build/release-evidence/v0.2.0-rc.1/private/notary-submit.json"
[[ -f "${RECOVERY_RECEIPT}" && ! -L "${RECOVERY_RECEIPT}" ]] \
  || fail "notarization receipt was not durably stored in private evidence"
[[ ! -e "${RECOVERY_REPO}/dist/release/v0.2.0-rc.1/notary-submit.json" ]] \
  || fail "private notarization receipt leaked into public release output"

reset_logs
UNSAFE_RECEIPT_REPO="${TEST_ROOT}/unsafe-receipt-repo"
make_fixture_repo "${UNSAFE_RECEIPT_REPO}"
mkdir -p "${UNSAFE_RECEIPT_REPO}/build/release-evidence/v0.2.0-rc.1/private"
printf 'outside must remain unchanged\n' > "${TEST_ROOT}/outside-receipt.json"
ln -s "${TEST_ROOT}/outside-receipt.json" \
  "${UNSAFE_RECEIPT_REPO}/build/release-evidence/v0.2.0-rc.1/private/notary-submit.json"
expect_failure \
  "symbolic notarization receipt" \
  "notarization receipt must be a regular file" \
  "${TEST_ROOT}/unsafe-receipt.log" \
  run_package "${UNSAFE_RECEIPT_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
[[ "$(<"${TEST_ROOT}/outside-receipt.json")" == "outside must remain unchanged" ]] \
  || fail "symbolic notarization receipt target was mutated"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
AMBIGUOUS_RECEIPT_REPO="${TEST_ROOT}/ambiguous-receipt-repo"
make_fixture_repo "${AMBIGUOUS_RECEIPT_REPO}"
mkdir -p "${AMBIGUOUS_RECEIPT_REPO}/build/release-evidence/v0.2.0-rc.1/private"
printf '{"id":"not-a-uuid"}\n' \
  > "${AMBIGUOUS_RECEIPT_REPO}/build/release-evidence/v0.2.0-rc.1/private/notary-submit.json"
expect_failure \
  "ambiguous notarization receipt" \
  "notarization receipt is ambiguous; refusing to resubmit" \
  "${TEST_ROOT}/ambiguous-receipt.log" \
  run_package "${AMBIGUOUS_RECEIPT_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
PREFLIGHT_FAIL_REPO="${TEST_ROOT}/preflight-fail-repo"
make_fixture_repo "${PREFLIGHT_FAIL_REPO}"
expect_failure \
  "preflight early failure" \
  "preflight: synthetic failure" \
  "${TEST_ROOT}/preflight-failure.log" \
  env PATH="${BIN_ROOT}:$PATH" \
    INKBEAM_TEAM_ID="SLVS4WF9U2" \
    INKBEAM_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)" \
    INKBEAM_TEST_LOG_ROOT="${LOG_ROOT}" \
    INKBEAM_TEST_PREFLIGHT_FAIL="1" \
    INKBEAM_TEST_SUBMISSION_ID="12345678-1234-1234-1234-1234567890ab" \
    "${PREFLIGHT_FAIL_REPO}/Scripts/release/package.sh" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "xcodebuild" "${LOG_ROOT}/xcodebuild.log"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
UNKNOWN_CHANNEL_REPO="${TEST_ROOT}/unknown-channel-repo"
make_fixture_repo "${UNKNOWN_CHANNEL_REPO}"
node --input-type=module - "${UNKNOWN_CHANNEL_REPO}/Scripts/release/release-contract.mjs" <<'NODE'
import fs from "node:fs";
const file = process.argv[2];
const source = fs.readFileSync(file, "utf8").replace('channel: "beta"', 'channel: "preview"');
fs.writeFileSync(file, source);
NODE
expect_failure \
  "unknown channel" \
  "unsupported release channel: preview" \
  "${TEST_ROOT}/unknown-channel.log" \
  run_package "${UNKNOWN_CHANNEL_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "xcodebuild" "${LOG_ROOT}/xcodebuild.log"

reset_logs
SYMLINK_REPO="${TEST_ROOT}/symlink-repo"
make_fixture_repo "${SYMLINK_REPO}"
mkdir -p "${TEST_ROOT}/escape"
ln -s "${TEST_ROOT}/escape" "${SYMLINK_REPO}/dist"
expect_failure \
  "unsafe output symlink" \
  "release output root cannot traverse a symbolic link" \
  "${TEST_ROOT}/symlink-output.log" \
  run_package "${SYMLINK_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "xcodebuild" "${LOG_ROOT}/xcodebuild.log"

reset_logs
MISSING_SPARKLE_REPO="${TEST_ROOT}/missing-sparkle-repo"
make_fixture_repo "${MISSING_SPARKLE_REPO}"
INKBEAM_TEST_ARCHIVE_MODE=missing-installer expect_failure \
  "missing Sparkle installer" \
  "Sparkle Installer.xpc is missing" \
  "${TEST_ROOT}/missing-sparkle.log" \
  run_package "${MISSING_SPARKLE_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
THIN_HELPER_REPO="${TEST_ROOT}/thin-helper-repo"
make_fixture_repo "${THIN_HELPER_REPO}"
INKBEAM_TEST_ARCH_MODE=thin-helper expect_failure \
  "thin native helper" \
  "native host must contain exactly arm64 and x86_64" \
  "${TEST_ROOT}/thin-helper.log" \
  run_package "${THIN_HELPER_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
DEBUG_ENTITLEMENT_REPO="${TEST_ROOT}/debug-entitlement-repo"
make_fixture_repo "${DEBUG_ENTITLEMENT_REPO}"
INKBEAM_TEST_ENTITLEMENTS_MODE=debug expect_failure \
  "debug entitlement" \
  "get-task-allow entitlement is forbidden" \
  "${TEST_ROOT}/debug-entitlement.log" \
  run_package "${DEBUG_ENTITLEMENT_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
WRONG_HELPER_REPO="${TEST_ROOT}/wrong-helper-identifier-repo"
make_fixture_repo "${WRONG_HELPER_REPO}"
INKBEAM_TEST_SIGNATURE_MODE=wrong-helper-identifier expect_failure \
  "wrong helper identifier suffix" \
  "native host must use bundle identifier dev.gihwan.inkbeam.nativehost" \
  "${TEST_ROOT}/wrong-helper-identifier.log" \
  run_package "${WRONG_HELPER_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
DUPLICATE_TEAM_REPO="${TEST_ROOT}/duplicate-team-repo"
make_fixture_repo "${DUPLICATE_TEAM_REPO}"
INKBEAM_TEST_SIGNATURE_MODE=duplicate-team expect_failure \
  "duplicate signing team" \
  "must expose exactly one TeamIdentifier=SLVS4WF9U2" \
  "${TEST_ROOT}/duplicate-team.log" \
  run_package "${DUPLICATE_TEAM_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
CHROME_FAILURE_REPO="${TEST_ROOT}/chrome-failure-repo"
make_fixture_repo "${CHROME_FAILURE_REPO}"
INKBEAM_TEST_CHROME_BUILD_MODE=fail expect_failure \
  "Chrome production build failure" \
  "Chrome extension build failed" \
  "${TEST_ROOT}/chrome-build-failure.log" \
  run_package "${CHROME_FAILURE_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}"
assert_log_absent "notarytool submit" "${LOG_ROOT}/xcrun.log"

reset_logs
STABLE_REPO="${TEST_ROOT}/stable-repo"
make_fixture_repo "${STABLE_REPO}"
run_package "${STABLE_REPO}" "v0.2.0" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > "${TEST_ROOT}/stable-package.log" 2>&1
grep -Fq "channel=stable" "${LOG_ROOT}/generate-project.log" \
  || fail "package did not propagate stable channel"
grep -Fq "CURRENT_PROJECT_VERSION=4" "${LOG_ROOT}/xcodebuild.log" \
  || fail "stable package did not use contract build 4"
grep -Fq "INKBEAM_RELEASE_CHANNEL_NAME=Stable" "${LOG_ROOT}/xcodebuild.log" \
  || fail "package did not map stable to Stable"
grep -Fq "pnpm version-name=v0.2.0 --filter @inkbeam/chrome-extension build" \
  "${LOG_ROOT}/pnpm.log" \
  || fail "stable Chrome build did not use the stable version_name"

reset_logs
NONTERMINAL_REPO="${TEST_ROOT}/nonterminal-repo"
make_fixture_repo "${NONTERMINAL_REPO}"
run_package "${NONTERMINAL_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > /dev/null 2>&1
run_resume "${NONTERMINAL_REPO}" "v0.2.0-rc.1" "In Progress" \
  > "${TEST_ROOT}/resume-progress.log" 2>&1
NONTERMINAL_STATE="$(state_path_for "${NONTERMINAL_REPO}" "v0.2.0-rc.1")"
[[ "$(read_state_field "${NONTERMINAL_STATE}" 'state.notarization.status')" == "In Progress" ]] \
  || fail "resume-notarization did not record a nonterminal status"
assert_log_absent "stapler staple" "${LOG_ROOT}/xcrun.log"
assert_log_absent "spctl --assess" "${LOG_ROOT}/spctl.log"

reset_logs
REJECTED_REPO="${TEST_ROOT}/rejected-repo"
make_fixture_repo "${REJECTED_REPO}"
run_package "${REJECTED_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > /dev/null 2>&1
expect_failure \
  "rejected notarization" \
  "notarization status is Rejected" \
  "${TEST_ROOT}/resume-rejected.log" \
  run_resume "${REJECTED_REPO}" "v0.2.0-rc.1" "Rejected"
REJECTED_STATE="$(state_path_for "${REJECTED_REPO}" "v0.2.0-rc.1")"
[[ "$(read_state_field "${REJECTED_STATE}" 'state.notarization.status')" == "Rejected" ]] \
  || fail "resume-notarization did not persist a rejected status"
[[ -f "${REJECTED_REPO}/build/release-evidence/v0.2.0-rc.1/private/notary-log.json" ]] \
  || fail "resume-notarization did not write a private notary log for terminal status"
assert_log_absent "stapler staple" "${LOG_ROOT}/xcrun.log"

reset_logs
ACCEPTED_REPO="${TEST_ROOT}/accepted-repo"
make_fixture_repo "${ACCEPTED_REPO}"
run_package "${ACCEPTED_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > /dev/null 2>&1
run_resume "${ACCEPTED_REPO}" "v0.2.0-rc.1" "Accepted" \
  > "${TEST_ROOT}/resume-accepted.log" 2>&1
ACCEPTED_STATE="$(state_path_for "${ACCEPTED_REPO}" "v0.2.0-rc.1")"
[[ "$(read_state_field "${ACCEPTED_STATE}" 'state.notarization.status')" == "Accepted" ]] \
  || fail "resume-notarization did not persist Accepted status"
[[ "$(read_state_field "${ACCEPTED_STATE}" 'Boolean(state.phases.notarized)')" == "true" ]] \
  || fail "resume-notarization did not complete the notarized phase"
[[ -f "${ACCEPTED_REPO}/build/release-evidence/v0.2.0-rc.1/private/notary-log.json" ]] \
  || fail "resume-notarization did not write a private notary log"
grep -Fq "stapler staple ${ACCEPTED_REPO}/dist/release/v0.2.0-rc.1/Inkbeam-0.2.0-rc.1.dmg" "${LOG_ROOT}/xcrun.log" \
  || fail "resume-notarization did not staple the accepted DMG"
grep -Fq "stapler validate ${ACCEPTED_REPO}/dist/release/v0.2.0-rc.1/Inkbeam-0.2.0-rc.1.dmg" "${LOG_ROOT}/xcrun.log" \
  || fail "resume-notarization did not validate the stapled DMG"
grep -Fq "codesign --verify --deep --strict --verbose=4 ${ACCEPTED_REPO}/build/release-evidence/v0.2.0-rc.1/private/Inkbeam.xcarchive/Products/Applications/Inkbeam.app" "${LOG_ROOT}/codesign.log" \
  || fail "resume-notarization did not deep-verify the accepted app"
grep -Fq "spctl --assess --type execute --verbose=4 ${ACCEPTED_REPO}/build/release-evidence/v0.2.0-rc.1/private/Inkbeam.xcarchive/Products/Applications/Inkbeam.app" "${LOG_ROOT}/spctl.log" \
  || fail "resume-notarization did not Gatekeeper-assess the app"
grep -Fq "spctl --assess --type open --context context:primary-signature --verbose=4 ${ACCEPTED_REPO}/dist/release/v0.2.0-rc.1/Inkbeam-0.2.0-rc.1.dmg" "${LOG_ROOT}/spctl.log" \
  || fail "resume-notarization did not Gatekeeper-assess the DMG"

reset_logs
RETRY_REPO="${TEST_ROOT}/accepted-retry-repo"
make_fixture_repo "${RETRY_REPO}"
run_package "${RETRY_REPO}" "v0.2.0-rc.1" "${FIXTURE_BRANCH}" "${FIXTURE_SHA}" \
  > /dev/null 2>&1
INKBEAM_TEST_STAPLER_MODE=fail expect_failure \
  "accepted staple interruption" \
  "stapler staple failed" \
  "${TEST_ROOT}/resume-staple-failure.log" \
  run_resume "${RETRY_REPO}" "v0.2.0-rc.1" "Accepted"
RETRY_STATE="$(state_path_for "${RETRY_REPO}" "v0.2.0-rc.1")"
[[ "$(read_state_field "${RETRY_STATE}" 'state.notarization.status')" == "Accepted" ]] \
  || fail "accepted status was not persisted before the staple interruption"
[[ "$(read_state_field "${RETRY_STATE}" 'Boolean(state.phases.notarized)')" == "true" ]] \
  || fail "notarized phase was not persisted before the staple interruption"
if ! run_resume "${RETRY_REPO}" "v0.2.0-rc.1" "Accepted" \
  > "${TEST_ROOT}/resume-staple-retry.log" 2>&1; then
  cat "${TEST_ROOT}/resume-staple-retry.log" >&2
  fail "Accepted notarization could not retry staple and Gatekeeper verification"
fi
[[ "$(grep -c 'stapler staple' "${LOG_ROOT}/xcrun.log")" == "2" ]] \
  || fail "resume did not retry stapling exactly once after interruption"

echo "PASS"

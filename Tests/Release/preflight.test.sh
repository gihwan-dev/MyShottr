#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h:h}"
TEST_ROOT="$(mktemp -d -t inkbeam-preflight)"
[[ -d "${TEST_ROOT}" && ! -L "${TEST_ROOT}" ]] || {
  echo "preflight.test: mktemp did not create a safe directory" >&2
  exit 1
}
TEST_ROOT="${TEST_ROOT:A}"
TEST_ROOT_PARENT="${TEST_ROOT:h}"
FIXTURE_REPO="${TEST_ROOT}/fixture-repo"
FIXTURE_BIN="${TEST_ROOT}/bin"
FIXTURE_BIN_NO_GH="${TEST_ROOT}/bin-no-gh"
REAL_GIT="$(command -v git)"
REAL_NODE="$(command -v node)"
EXPECTED_TEAM_ID="SLVS4WF9U2"
EXPECTED_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (${EXPECTED_TEAM_ID})"

fail() {
  echo "preflight.test: $*" >&2
  exit 1
}

cleanup() {
  case "${TEST_ROOT:t}" in
    inkbeam-preflight.*)
      [[ "${TEST_ROOT:h}" == "${TEST_ROOT_PARENT}" ]] || {
        echo "preflight.test: refusing to clean moved directory" >&2
        return 1
      }
      rm -rf "${TEST_ROOT}"
      ;;
    *)
      echo "preflight.test: refusing to clean unexpected path: ${TEST_ROOT}" >&2
      return 1
      ;;
  esac
}

trap cleanup EXIT

mkdir -p \
  "${FIXTURE_REPO}/Scripts/release" \
  "${FIXTURE_REPO}/Packages/chrome-extension/public" \
  "${FIXTURE_REPO}/Config" \
  "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin" \
  "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages" \
  "${FIXTURE_BIN}" \
  "${FIXTURE_BIN_NO_GH}"

cp "${REPO_ROOT}/Scripts/release/preflight.sh" "${FIXTURE_REPO}/Scripts/release/preflight.sh"
cp "${REPO_ROOT}/Scripts/release/inkbeam-release" "${FIXTURE_REPO}/Scripts/release/inkbeam-release"
cp "${REPO_ROOT}/Scripts/release/release-contract.mjs" "${FIXTURE_REPO}/Scripts/release/release-contract.mjs"
cp "${REPO_ROOT}/Scripts/release/release-state.mjs" "${FIXTURE_REPO}/Scripts/release/release-state.mjs"
cp "${REPO_ROOT}/Scripts/verify-release-metadata.mjs" "${FIXTURE_REPO}/Scripts/verify-release-metadata.mjs"
chmod +x "${FIXTURE_REPO}/Scripts/release/inkbeam-release"

cat > "${FIXTURE_REPO}/package.json" <<'JSON'
{
  "name": "inkbeam",
  "private": true,
  "packageManager": "pnpm@10.14.0"
}
JSON

cat > "${FIXTURE_REPO}/project.yml" <<'YAML'
targets:
  Inkbeam:
    settings:
      base:
        MARKETING_VERSION: "0.2.0"
        CURRENT_PROJECT_VERSION: "1"
        INKBEAM_RELEASE_CHANNEL_NAME: "Development"
    info:
      properties:
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        InkbeamReleaseChannel: $(INKBEAM_RELEASE_CHANNEL_NAME)
YAML

cat > "${FIXTURE_REPO}/Config/Inkbeam-Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>$(MARKETING_VERSION)</string>
  <key>CFBundleVersion</key>
  <string>$(CURRENT_PROJECT_VERSION)</string>
  <key>InkbeamReleaseChannel</key>
  <string>$(INKBEAM_RELEASE_CHANNEL_NAME)</string>
</dict>
</plist>
PLIST

cat > "${FIXTURE_REPO}/Packages/chrome-extension/package.json" <<'JSON'
{
  "name": "@inkbeam/chrome-extension"
}
JSON

cat > "${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'JSON'
{
  "manifest_version": 3,
  "name": "Inkbeam",
  "version": "0.2.0"
}
JSON

printf 'lockfileVersion: 9.0\n' > "${FIXTURE_REPO}/pnpm-lock.yaml"
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"

cat > "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/workspace-state.json" <<'JSON'
{
  "object": {
    "dependencies": [
      {
        "packageRef": {
          "identity": "sparkle"
        },
        "state": {
          "version": "2.9.4"
        }
      }
    ]
  }
}
JSON

cat > "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys" <<'SH'
#!/bin/zsh
set -euo pipefail
printf 'generate_keys %s\n' "$*" >> "${INVOKE_LOG}"
if [[ "${1:-}" == "--account" && "${2:-}" == "inkbeam" ]]; then
  [[ "${3:-}" == "-p" ]] || exit 1
  if [[ "${STUB_SPARKLE_KEY_MODE:-present}" == "ambiguous" ]]; then
    printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n'
    printf 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=\n'
    exit 0
  fi
  if [[ "${STUB_SPARKLE_KEY_MODE:-present}" == "malformed" ]]; then
    printf 'not-a-public-key\n'
    exit 0
  fi
  if [[ "${STUB_SPARKLE_KEY_MODE:-present}" == "error" ]]; then
    echo "fixture keychain failure" >&2
    exit 1
  fi
  printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n'
  exit 0
fi
echo "unexpected generate_keys invocation: $*" >&2
exit 1
SH
chmod +x "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"

cat > "${FIXTURE_BIN}/git" <<'SH'
#!/bin/zsh
set -euo pipefail
[[ -n "${REAL_GIT:-}" ]] || { echo "REAL_GIT is required" >&2; exit 1; }
if [[ "${1:-}" == "push" || ( "${1:-}" == "-C" && "${3:-}" == "push" ) ]]; then
  printf 'git push %s\n' "$*" >> "${INVOKE_LOG}"
fi
exec "${REAL_GIT}" "$@"
SH

cat > "${FIXTURE_BIN}/node" <<'SH'
#!/bin/zsh
set -euo pipefail
[[ -n "${REAL_NODE:-}" ]] || { echo "REAL_NODE is required" >&2; exit 1; }
if [[ "${1:-}" == "-p" && "${2:-}" == "process.version.slice(1)" ]]; then
  printf '%s\n' "${STUB_NODE_VERSION:-22.12.0}"
  exit 0
fi
printf 'node-runtime %s\n' "$*" >> "${INVOKE_LOG}"
exec "${REAL_NODE}" "$@"
SH

cat > "${FIXTURE_BIN}/pnpm" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "${1:-}" == "-v" ]]; then
  printf '%s\n' "${STUB_PNPM_VERSION:-10.14.0}"
  exit 0
fi
if [[ "${1:-}" == "install" && "${2:-}" == "--frozen-lockfile" && "${3:-}" == "--lockfile-only" && "${4:-}" == "--ignore-scripts" ]]; then
  printf 'pnpm %s\n' "$*" >> "${INVOKE_LOG}"
  if [[ "${STUB_PNPM_LOCK_MODE:-pass}" == "fail" ]]; then
    exit 1
  fi
  exit 0
fi
echo "unexpected pnpm invocation: $*" >&2
exit 1
SH

cat > "${FIXTURE_BIN}/xcodebuild" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "${1:-}" == "-version" ]]; then
  printf 'Xcode %s\nBuild version 26A000\n' "${STUB_XCODE_VERSION:-26.0}"
  exit 0
fi
printf 'xcodebuild %s\n' "$*" >> "${INVOKE_LOG}"
echo "unexpected xcodebuild invocation: $*" >&2
exit 97
SH

cat > "${FIXTURE_BIN}/xcodegen" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  if [[ "${STUB_XCODEGEN_MODE:-present}" == "missing" ]]; then
    exit 1
  fi
  printf '2.42.0\n'
  exit 0
fi
echo "unexpected xcodegen invocation: $*" >&2
exit 1
SH

cat > "${FIXTURE_BIN}/security" <<'SH'
#!/bin/zsh
set -euo pipefail
case "${1:-}" in
  find-identity)
    [[ "$*" == "find-identity -v -p codesigning" ]] || exit 1
    if [[ "${STUB_SECURITY_IDENTITY_MODE:-present}" == "missing" ]]; then
      exit 1
    fi
    printf '  1) FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE "Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)"\n'
    if [[ "${STUB_SECURITY_IDENTITY_MODE:-present}" == "duplicate" ]]; then
      printf '  2) FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAK2 "Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)"\n'
    fi
    ;;
  find-generic-password)
    [[ "$*" == "find-generic-password -s https://sparkle-project.org -a inkbeam" ]] || exit 1
    if [[ "${STUB_SECURITY_SPARKLE_MODE:-present}" == "missing" ]]; then
      exit 1
    fi
    ;;
  *)
    echo "unexpected security invocation: $*" >&2
    exit 1
    ;;
esac
SH

cat > "${FIXTURE_BIN}/xcrun" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "${1:-}" == "notarytool" && "${2:-}" == "history" ]]; then
  [[ "$*" == "notarytool history --keychain-profile inkbeam-notary --output-format json" ]] || exit 1
  if [[ "${STUB_NOTARY_MODE:-present}" == "missing" ]]; then
    exit 1
  fi
  printf '{"history":[]}\n'
  exit 0
fi
if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then
  printf 'xcrun notarytool submit %s\n' "$*" >> "${INVOKE_LOG}"
  exit 97
fi
echo "unexpected xcrun invocation: $*" >&2
exit 1
SH

cat > "${FIXTURE_BIN}/gh" <<'SH'
#!/bin/zsh
set -euo pipefail
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
  [[ "$*" == "auth status --hostname github.com" ]] || exit 1
  if [[ "${STUB_GH_MODE:-present}" == "missing" ]]; then
    exit 1
  fi
  printf 'github.com\n'
  exit 0
fi
if [[ "${1:-}" == "release" ]]; then
  printf 'gh release %s\n' "$*" >> "${INVOKE_LOG}"
  exit 97
fi
echo "unexpected gh invocation: $*" >&2
exit 1
SH

chmod +x "${FIXTURE_BIN}/git" "${FIXTURE_BIN}/node" "${FIXTURE_BIN}/pnpm" \
  "${FIXTURE_BIN}/xcodebuild" "${FIXTURE_BIN}/xcodegen" "${FIXTURE_BIN}/security" \
  "${FIXTURE_BIN}/xcrun" "${FIXTURE_BIN}/gh"
for command_name in git node pnpm xcodebuild xcodegen security xcrun; do
  ln -s "${FIXTURE_BIN}/${command_name}" "${FIXTURE_BIN_NO_GH}/${command_name}"
done

(
  cd "${FIXTURE_REPO}"
  git init -q
  git config user.email "preflight@example.invalid"
  git config user.name "Preflight Fixture"
  git add .
  git commit -qm "fixture"
  git branch -M worktree/official-release-pipeline
  git remote add origin https://github.com/gihwan-dev/inkbeam.git
)

assert_no_dangerous_commands() {
  local label="$1"
  local log_path="$2"
  if grep -Eq 'xcodebuild|notarytool submit|gh release|git push' "${log_path}"; then
    cat "${log_path}" >&2
    fail "${label} invoked a dangerous command unexpectedly"
  fi
}

assert_no_mutating_release_commands() {
  local label="$1"
  local log_path="$2"
  if grep -Eq 'notarytool submit|gh release|git push' "${log_path}"; then
    cat "${log_path}" >&2
    fail "${label} invoked a mutating release command unexpectedly"
  fi
}

run_failure_case() {
  local label="$1"
  local expected_message="$2"
  shift 2
  local invoke_log="${TEST_ROOT}/${label// /-}.invoke.log"
  local output_log="${TEST_ROOT}/${label// /-}.output.log"
  : > "${invoke_log}"
  if (
    export PATH="${FIXTURE_BIN}:${PATH}"
    export REAL_GIT="${REAL_GIT}"
    export REAL_NODE="${REAL_NODE}"
    export INVOKE_LOG="${invoke_log}"
    export INKBEAM_TEAM_ID="${EXPECTED_TEAM_ID}"
    export INKBEAM_SIGNING_IDENTITY="${EXPECTED_SIGNING_IDENTITY}"
    "$@"
  ) > "${output_log}" 2>&1; then
    fail "${label} unexpectedly succeeded"
  fi
  grep -Fq "${expected_message}" "${output_log}" || {
    cat "${output_log}" >&2
    fail "${label} did not report '${expected_message}'"
  }
  assert_no_dangerous_commands "${label}" "${invoke_log}"
}

refresh_precheck() {
  CURRENT_SHA="$(git -C "${FIXTURE_REPO}" rev-parse HEAD)"
  PRECHECK_CMD=("${FIXTURE_REPO}/Scripts/release/inkbeam-release" "preflight" "v0.2.0-rc.1" "worktree/official-release-pipeline" "${CURRENT_SHA}")
}

refresh_precheck

run_failure_case \
  "missing team id" \
  "INKBEAM_TEAM_ID is required" \
  env -u INKBEAM_TEAM_ID "${PRECHECK_CMD[@]}"

run_failure_case \
  "missing signing identity" \
  "INKBEAM_SIGNING_IDENTITY is required" \
  env -u INKBEAM_SIGNING_IDENTITY "${PRECHECK_CMD[@]}"

run_failure_case \
  "missing gh command" \
  "required command 'gh' is unavailable" \
  env PATH="${FIXTURE_BIN_NO_GH}:/usr/bin:/bin" "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong node version" \
  "Node.js 22 is required" \
  env STUB_NODE_VERSION=21.7.0 "${PRECHECK_CMD[@]}"
if grep -Fq 'node-runtime --input-type' "${TEST_ROOT}/wrong-node-version.invoke.log"; then
  fail "wrong node version loaded release JavaScript before checking Node.js"
fi

run_failure_case \
  "wrong pnpm version" \
  "pnpm 10.14.0 is required" \
  env STUB_PNPM_VERSION=10.15.0 "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong team id" \
  "INKBEAM_TEAM_ID must equal SLVS4WF9U2" \
  env \
    INKBEAM_TEAM_ID=AAAAAAAAAA \
    INKBEAM_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (AAAAAAAAAA)" \
    "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong full signing identity" \
  "INKBEAM_SIGNING_IDENTITY must equal ${EXPECTED_SIGNING_IDENTITY}" \
  env \
    INKBEAM_SIGNING_IDENTITY="Developer ID Application: SOMEONE ELSE (${EXPECTED_TEAM_ID})" \
    "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong branch" \
  "expected branch worktree/official-release-pipeline, found wrong-branch" \
  sh -c 'git -C "$1" checkout -q -b wrong-branch >/dev/null 2>&1 && shift && exec "$@"' \
    _ "${FIXTURE_REPO}" "${PRECHECK_CMD[@]}"

git -C "${FIXTURE_REPO}" checkout -q worktree/official-release-pipeline

run_failure_case \
  "wrong sha" \
  "expected SHA 0000000000000000000000000000000000000000" \
  "${FIXTURE_REPO}/Scripts/release/inkbeam-release" "preflight" "v0.2.0-rc.1" "worktree/official-release-pipeline" "0000000000000000000000000000000000000000"

printf '\n# dirty\n' >> "${FIXTURE_REPO}/project.yml"
run_failure_case \
  "dirty worktree" \
  "source tree must be clean" \
  "${PRECHECK_CMD[@]}"
git -C "${FIXTURE_REPO}" checkout -- project.yml

git -C "${FIXTURE_REPO}" tag v0.2.0-rc.1
run_failure_case \
  "existing tag" \
  "tag v0.2.0-rc.1 already exists; preflight requires an unpublished contract tag" \
  "${PRECHECK_CMD[@]}"
git -C "${FIXTURE_REPO}" tag -d v0.2.0-rc.1 >/dev/null

git -C "${FIXTURE_REPO}" remote set-url origin https://github.com/gihwan-dev/inkbeam-private.git
run_failure_case \
  "wrong remote" \
  "origin remote must be https://github.com/gihwan-dev/inkbeam.git" \
  "${PRECHECK_CMD[@]}"
git -C "${FIXTURE_REPO}" remote set-url origin https://github.com/gihwan-dev/inkbeam.git

run_failure_case \
  "wrong tag contract" \
  "unsupported release tag: v0.2.1" \
  "${FIXTURE_REPO}/Scripts/release/inkbeam-release" "preflight" "v0.2.1" "worktree/official-release-pipeline" "${CURRENT_SHA}"

run_failure_case \
  "missing github authentication" \
  "GitHub CLI must be authenticated for github.com" \
  env STUB_GH_MODE=missing "${PRECHECK_CMD[@]}"

run_failure_case \
  "missing exact identity" \
  "missing exact signing identity: Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)" \
  env STUB_SECURITY_IDENTITY_MODE=missing "${PRECHECK_CMD[@]}"

run_failure_case \
  "duplicate exact identity" \
  "expected exactly one signing identity: ${EXPECTED_SIGNING_IDENTITY}" \
  env STUB_SECURITY_IDENTITY_MODE=duplicate "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong notary profile" \
  "missing notary profile inkbeam-notary" \
  env STUB_NOTARY_MODE=missing "${PRECHECK_CMD[@]}"

run_failure_case \
  "missing sparkle account" \
  "missing Sparkle account inkbeam" \
  env STUB_SECURITY_SPARKLE_MODE=missing "${PRECHECK_CMD[@]}"
if grep -Fq 'generate_keys' "${TEST_ROOT}/missing-sparkle-account.invoke.log"; then
  fail "missing Sparkle account invoked generate_keys unexpectedly"
fi

printf 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=\n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "key mismatch"
refresh_precheck
run_failure_case \
  "public key mismatch" \
  "Sparkle public key mismatch" \
  "${PRECHECK_CMD[@]}"
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "restore key"
refresh_precheck

printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "non-canonical key file"
refresh_precheck
run_failure_case \
  "noncanonical public key file" \
  "Config/SparklePublicEDKey.txt must contain exactly one canonical 32-byte public key" \
  "${PRECHECK_CMD[@]}"
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "restore canonical key file"
refresh_precheck

printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=\n' \
  > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "ambiguous key file"
refresh_precheck
run_failure_case \
  "ambiguous public key file" \
  "Config/SparklePublicEDKey.txt must contain exactly one canonical 32-byte public key" \
  "${PRECHECK_CMD[@]}"
printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n' > "${FIXTURE_REPO}/Config/SparklePublicEDKey.txt"
git -C "${FIXTURE_REPO}" add Config/SparklePublicEDKey.txt
git -C "${FIXTURE_REPO}" commit -qm "restore one key line"
refresh_precheck

run_failure_case \
  "ambiguous public key output" \
  "Sparkle key tool must emit exactly one canonical 32-byte public key" \
  env STUB_SPARKLE_KEY_MODE=ambiguous "${PRECHECK_CMD[@]}"

run_failure_case \
  "malformed public key output" \
  "Sparkle key tool must emit exactly one canonical 32-byte public key" \
  env STUB_SPARKLE_KEY_MODE=malformed "${PRECHECK_CMD[@]}"

run_failure_case \
  "sparkle key tool failure" \
  "Sparkle key tool failed in read-only mode" \
  env STUB_SPARKLE_KEY_MODE=error "${PRECHECK_CMD[@]}"

run_failure_case \
  "lockfile validation failure" \
  "pnpm lockfile validation failed" \
  env STUB_PNPM_LOCK_MODE=fail "${PRECHECK_CMD[@]}"

"${REAL_NODE}" --input-type=module - "${FIXTURE_REPO}/package.json" <<'NODE'
import fs from "node:fs";

const path = process.argv[2];
const packageJson = JSON.parse(fs.readFileSync(path, "utf8"));
packageJson.packageManager = "pnpm@10.15.0";
fs.writeFileSync(path, `${JSON.stringify(packageJson, null, 2)}\n`);
NODE
git -C "${FIXTURE_REPO}" add package.json
git -C "${FIXTURE_REPO}" commit -qm "wrong package manager contract"
refresh_precheck
run_failure_case \
  "wrong package manager contract" \
  "packageManager must equal pnpm@10.14.0" \
  "${PRECHECK_CMD[@]}"
"${REAL_NODE}" --input-type=module - "${FIXTURE_REPO}/package.json" <<'NODE'
import fs from "node:fs";

const path = process.argv[2];
const packageJson = JSON.parse(fs.readFileSync(path, "utf8"));
packageJson.packageManager = "pnpm@10.14.0";
fs.writeFileSync(path, `${JSON.stringify(packageJson, null, 2)}\n`);
NODE
git -C "${FIXTURE_REPO}" add package.json
git -C "${FIXTURE_REPO}" commit -qm "restore package manager contract"
refresh_precheck

cat > "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/workspace-state.json" <<'JSON'
{
  "object": {
    "dependencies": [
      {
        "packageRef": {
          "identity": "sparkle"
        },
        "state": {
          "version": "2.9.5"
        }
      }
    ]
  }
}
JSON
git -C "${FIXTURE_REPO}" add build/sparkle-tools/DerivedData/SourcePackages/workspace-state.json
git -C "${FIXTURE_REPO}" commit -qm "sparkle drift"
refresh_precheck
run_failure_case \
  "sparkle version drift" \
  "Sparkle version drift detected: 2.9.5" \
  "${PRECHECK_CMD[@]}"
cat > "${FIXTURE_REPO}/build/sparkle-tools/DerivedData/SourcePackages/workspace-state.json" <<'JSON'
{
  "object": {
    "dependencies": [
      {
        "packageRef": {
          "identity": "sparkle"
        },
        "state": {
          "version": "2.9.4"
        }
      }
    ]
  }
}
JSON
git -C "${FIXTURE_REPO}" add build/sparkle-tools/DerivedData/SourcePackages/workspace-state.json
git -C "${FIXTURE_REPO}" commit -qm "restore sparkle"
refresh_precheck

"${REAL_NODE}" --input-type=module - \
  "${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'NODE'
import fs from "node:fs";

const path = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.name = "Wrong Name";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
git -C "${FIXTURE_REPO}" add Packages/chrome-extension/public/manifest.json
git -C "${FIXTURE_REPO}" commit -qm "wrong manifest name"
refresh_precheck
run_failure_case \
  "wrong chrome manifest name" \
  "unexpected Chrome manifest name: Wrong Name" \
  "${PRECHECK_CMD[@]}"
"${REAL_NODE}" --input-type=module - \
  "${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'NODE'
import fs from "node:fs";

const path = process.argv[2];
const manifest = JSON.parse(fs.readFileSync(path, "utf8"));
manifest.name = "Inkbeam";
manifest.version = "0.2.1";
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
git -C "${FIXTURE_REPO}" add Packages/chrome-extension/public/manifest.json
git -C "${FIXTURE_REPO}" commit -qm "wrong manifest version"
refresh_precheck
run_failure_case \
  "wrong chrome manifest version" \
  "Chrome manifest version is 0.2.1, expected 0.2.0" \
  "${PRECHECK_CMD[@]}"

cat > "${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'JSON'
{
  "manifest_version": 3,
  "name": "Inkbeam",
  "version": "0.2.0"
}
JSON
git -C "${FIXTURE_REPO}" add Packages/chrome-extension/public/manifest.json
git -C "${FIXTURE_REPO}" commit -qm "restore manifest"
refresh_precheck

run_failure_case \
  "missing xcodegen" \
  "xcodegen must be installed" \
  env STUB_XCODEGEN_MODE=missing "${PRECHECK_CMD[@]}"

run_failure_case \
  "wrong xcode version" \
  "Xcode 26 is required" \
  env STUB_XCODE_VERSION=25.4 "${PRECHECK_CMD[@]}"

if ! (
  export PATH="${FIXTURE_BIN}:${PATH}"
  export REAL_GIT="${REAL_GIT}"
  export REAL_NODE="${REAL_NODE}"
  export INVOKE_LOG="${TEST_ROOT}/green.invoke.log"
  export INKBEAM_TEAM_ID="${EXPECTED_TEAM_ID}"
  export INKBEAM_SIGNING_IDENTITY="${EXPECTED_SIGNING_IDENTITY}"
  "${PRECHECK_CMD[@]}"
) > "${TEST_ROOT}/green.output.log" 2>&1; then
  cat "${TEST_ROOT}/green.output.log" >&2
  fail "synthetic green preflight unexpectedly failed"
fi

assert_no_mutating_release_commands "synthetic green" "${TEST_ROOT}/green.invoke.log"
grep -Fq 'preflight: v0.2.0-rc.1 worktree/official-release-pipeline' "${TEST_ROOT}/green.output.log" \
  || fail "synthetic green preflight did not print the contract summary"
printf 'preflight.test: PASS\n'

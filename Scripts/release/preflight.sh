#!/bin/zsh
set -euo pipefail

export LC_ALL=C
export TZ=UTC

fail() {
  echo "preflight: $*" >&2
  exit 1
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command '${command_name}' is unavailable"
}

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h:h}"
TAG="${1:-}"
EXPECTED_BRANCH="${2:-}"
EXPECTED_SHA="${3:-}"

[[ -n "${TAG}" && -n "${EXPECTED_BRANCH}" && -n "${EXPECTED_SHA}" ]] \
  || fail "usage: preflight.sh TAG EXPECTED_BRANCH EXPECTED_SHA"

CONTRACT_JSON="$(
  node --input-type=module - "${REPO_ROOT}" "${TAG}" <<'NODE'
import { pathToFileURL } from "node:url";

const [repoRoot, tag] = process.argv.slice(2);
const { contractFor } = await import(
  pathToFileURL(`${repoRoot}/Scripts/release/release-contract.mjs`).href
);
process.stdout.write(`${JSON.stringify(contractFor(tag))}\n`);
NODE
)" || exit 1

VERSION="$(
  node --input-type=module - "${CONTRACT_JSON}" <<'NODE'
const contract = JSON.parse(process.argv[2]);
process.stdout.write(`${contract.version}\n`);
NODE
)"

COMMANDS=(
  git
  node
  pnpm
  xcodebuild
  xcodegen
  security
  xcrun
  gh
)
for command_name in "${COMMANDS[@]}"; do
  require_command "${command_name}"
done

: "${INKBEAM_TEAM_ID:?INKBEAM_TEAM_ID is required}"
: "${INKBEAM_SIGNING_IDENTITY:?INKBEAM_SIGNING_IDENTITY is required}"
[[ "${INKBEAM_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] \
  || fail "INKBEAM_TEAM_ID must be a 10-character uppercase alphanumeric team id"

GIT_ROOT="$(
  git -C "${REPO_ROOT}" rev-parse --show-toplevel 2>/dev/null
)" || fail "preflight requires a Git worktree"
[[ "${GIT_ROOT:A}" == "${REPO_ROOT:A}" ]] \
  || fail "preflight must run from the Inkbeam Git root"

CURRENT_BRANCH="$(
  git -C "${REPO_ROOT}" branch --show-current
)"
[[ "${CURRENT_BRANCH}" == "${EXPECTED_BRANCH}" ]] \
  || fail "expected branch ${EXPECTED_BRANCH}, found ${CURRENT_BRANCH}"

CURRENT_SHA="$(
  git -C "${REPO_ROOT}" rev-parse HEAD
)"
[[ "${CURRENT_SHA}" == "${EXPECTED_SHA}" ]] \
  || fail "expected SHA ${EXPECTED_SHA}, found ${CURRENT_SHA}"

[[ -z "$(
  git -C "${REPO_ROOT}" status --porcelain=v1 --untracked-files=all
)" ]] \
  || fail "source tree must be clean"

if git -C "${REPO_ROOT}" show-ref --tags --verify --quiet "refs/tags/${TAG}"; then
  fail "tag ${TAG} already exists; preflight requires an unpublished contract tag"
fi

[[ "$(git -C "${REPO_ROOT}" remote get-url origin)" == "https://github.com/gihwan-dev/inkbeam.git" ]] \
  || fail "origin remote must be https://github.com/gihwan-dev/inkbeam.git"

gh auth status --hostname github.com >/dev/null \
  || fail "GitHub CLI must be authenticated for github.com"

node "${REPO_ROOT}/Scripts/verify-release-metadata.mjs" "${VERSION}"

APP_PACKAGE_JSON="${REPO_ROOT}/Packages/chrome-extension/package.json"
MANIFEST_JSON="${REPO_ROOT}/Packages/chrome-extension/public/manifest.json"
node --input-type=module - "${APP_PACKAGE_JSON}" "${MANIFEST_JSON}" "${VERSION}" <<'NODE'
import fs from "node:fs";

const [packageJsonPath, manifestPath, expectedVersion] = process.argv.slice(2);
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

function fail(message) {
  process.stderr.write(`preflight: ${message}\n`);
  process.exit(1);
}

if (packageJson.name !== "@inkbeam/chrome-extension") {
  fail(`unexpected Chrome package name: ${packageJson.name}`);
}
if (manifest.name !== "Inkbeam") {
  fail(`unexpected Chrome manifest name: ${manifest.name}`);
}
if (manifest.version !== expectedVersion) {
  fail(`unexpected Chrome manifest version: ${manifest.version}`);
}
NODE

node --input-type=module - "${REPO_ROOT}/project.yml" "${REPO_ROOT}/Config/Inkbeam-Info.plist" "${EXPECTED_SHA}" <<'NODE'
import fs from "node:fs";

const [projectPath, plistPath] = process.argv.slice(2);
const project = fs.readFileSync(projectPath, "utf8");
const plist = fs.readFileSync(plistPath, "utf8");

function fail(message) {
  process.stderr.write(`preflight: ${message}\n`);
  process.exit(1);
}

for (const [label, source, pattern] of [
  ["project MARKETING_VERSION", project, /MARKETING_VERSION:\s*"0\.2\.0"/],
  ["project CFBundleShortVersionString", project, /CFBundleShortVersionString:\s*\$\((MARKETING_VERSION)\)/],
  ["project CFBundleVersion", project, /CFBundleVersion:\s*\$\((CURRENT_PROJECT_VERSION)\)/],
  ["project release channel", project, /InkbeamReleaseChannel:\s*\$\((INKBEAM_RELEASE_CHANNEL_NAME)\)/],
  ["plist CFBundleShortVersionString", plist, /<string>\$\((MARKETING_VERSION)\)<\/string>/],
  ["plist CFBundleVersion", plist, /<string>\$\((CURRENT_PROJECT_VERSION)\)<\/string>/],
  ["plist release channel", plist, /<key>InkbeamReleaseChannel<\/key>\s*<string>\$\((INKBEAM_RELEASE_CHANNEL_NAME)\)<\/string>/],
]) {
  if (!pattern.test(source)) {
    fail(`${label} is not configured as a build setting placeholder`);
  }
}
NODE

[[ "$(node -p 'process.version.slice(1)')" == 22.* ]] \
  || fail "Node.js 22 is required"
[[ "$(pnpm -v)" == "10.14.0" ]] \
  || fail "pnpm 10.14.0 is required"

require_command xcodegen
[[ -n "$(xcodegen --version)" ]] \
  || fail "xcodegen must be installed"

security find-identity -v -p codesigning | grep -F -- "${INKBEAM_SIGNING_IDENTITY}" >/dev/null \
  || fail "missing exact signing identity: ${INKBEAM_SIGNING_IDENTITY}"

xcrun notarytool history --keychain-profile inkbeam-notary --output-format json >/dev/null \
  || fail "missing notary profile inkbeam-notary"

security find-generic-password -s 'https://sparkle-project.org' -a inkbeam >/dev/null \
  || fail "missing Sparkle account inkbeam"

SPARKLE_TOOLS_ROOT="${REPO_ROOT}/build/sparkle-tools/DerivedData"
SPARKLE_BIN="${SPARKLE_TOOLS_ROOT}/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "${SPARKLE_BIN}/generate_keys" ]] \
  || fail "Sparkle 2.9.4 tools are missing at ${SPARKLE_BIN}"

SPARKLE_WORKSPACE_STATE="${SPARKLE_TOOLS_ROOT}/SourcePackages/workspace-state.json"
[[ -f "${SPARKLE_WORKSPACE_STATE}" ]] \
  || fail "Sparkle workspace state is missing at ${SPARKLE_WORKSPACE_STATE}"

node --input-type=module - "${SPARKLE_WORKSPACE_STATE}" <<'NODE'
import fs from "node:fs";

const workspaceStatePath = process.argv[2];
const workspaceState = JSON.parse(fs.readFileSync(workspaceStatePath, "utf8"));
const dependencies = Array.isArray(workspaceState.object?.dependencies)
  ? workspaceState.object.dependencies
  : [];
const sparkle = dependencies.find((dependency) => {
  const identity = dependency.packageRef?.identity ?? dependency.identity;
  return identity === "sparkle";
});

if (!sparkle) {
  process.stderr.write("preflight: Sparkle dependency is missing from workspace state\n");
  process.exit(1);
}

const resolvedVersion = sparkle.state?.version;
if (resolvedVersion !== "2.9.4") {
  process.stderr.write(
    `preflight: Sparkle version drift detected: ${String(resolvedVersion)}\n`,
  );
  process.exit(1);
}
NODE

SPARKLE_PUBLIC_KEY="$(
  "${SPARKLE_BIN}/generate_keys" --account inkbeam | awk 'NF { print; exit }'
)"
[[ -n "${SPARKLE_PUBLIC_KEY}" ]] \
  || fail "Sparkle key tool did not emit a public key"

SPARKLE_KEY_FILE="${REPO_ROOT}/Config/SparklePublicEDKey.txt"
[[ -f "${SPARKLE_KEY_FILE}" ]] \
  || fail "Config/SparklePublicEDKey.txt is missing"
[[ "$(tr -d '\n\r' < "${SPARKLE_KEY_FILE}")" == "${SPARKLE_PUBLIC_KEY}" ]] \
  || fail "Sparkle public key mismatch"

XCODE_MAJOR="$(
  xcodebuild -version | awk '/^Xcode / { split($2, parts, "."); print parts[1]; exit }'
)"
[[ "${XCODE_MAJOR}" == 26 ]] \
  || fail "Xcode 26 is required"

if git -C "${REPO_ROOT}" show-ref --tags --verify --quiet "refs/tags/${TAG}"; then
  fail "tag ${TAG} already exists; preflight requires an unpublished contract tag"
fi

process_outcome="PASS"
printf 'preflight: %s %s %s\n' "${TAG}" "${EXPECTED_BRANCH}" "${EXPECTED_SHA}"
printf '%s\n' "${process_outcome}"

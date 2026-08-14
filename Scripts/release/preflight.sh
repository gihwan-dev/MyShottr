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
EXPECTED_TEAM_ID="SLVS4WF9U2"
EXPECTED_SIGNING_IDENTITY="Developer ID Application: GIHWAN CHOI (${EXPECTED_TEAM_ID})"

[[ -n "${TAG}" && -n "${EXPECTED_BRANCH}" && -n "${EXPECTED_SHA}" ]] \
  || fail "usage: preflight.sh TAG EXPECTED_BRANCH EXPECTED_SHA"

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
[[ "$(node -p 'process.version.slice(1)')" == 22.* ]] \
  || fail "Node.js 22 is required"
[[ "$(pnpm -v)" == "10.14.0" ]] \
  || fail "pnpm 10.14.0 is required"
[[ "${INKBEAM_TEAM_ID}" == "${EXPECTED_TEAM_ID}" ]] \
  || fail "INKBEAM_TEAM_ID must equal ${EXPECTED_TEAM_ID}"
[[ "${INKBEAM_SIGNING_IDENTITY}" == "${EXPECTED_SIGNING_IDENTITY}" ]] \
  || fail "INKBEAM_SIGNING_IDENTITY must equal ${EXPECTED_SIGNING_IDENTITY}"

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

ROOT_PACKAGE_JSON="${REPO_ROOT}/package.json"
APP_PACKAGE_JSON="${REPO_ROOT}/Packages/chrome-extension/package.json"
MANIFEST_JSON="${REPO_ROOT}/Packages/chrome-extension/public/manifest.json"
node --input-type=module - \
  "${ROOT_PACKAGE_JSON}" \
  "${APP_PACKAGE_JSON}" \
  "${MANIFEST_JSON}" \
  "${VERSION}" <<'NODE'
import fs from "node:fs";

const [rootPackageJsonPath, appPackageJsonPath, manifestPath, expectedVersion] =
  process.argv.slice(2);
const rootPackageJson = JSON.parse(fs.readFileSync(rootPackageJsonPath, "utf8"));
const appPackageJson = JSON.parse(fs.readFileSync(appPackageJsonPath, "utf8"));
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

function fail(message) {
  process.stderr.write(`preflight: ${message}\n`);
  process.exit(1);
}

if (rootPackageJson.packageManager !== "pnpm@10.14.0") {
  fail(`packageManager must equal pnpm@10.14.0`);
}
if (appPackageJson.name !== "@inkbeam/chrome-extension") {
  fail(`unexpected Chrome package name: ${appPackageJson.name}`);
}
if (manifest.name !== "Inkbeam") {
  fail(`unexpected Chrome manifest name: ${manifest.name}`);
}
if (manifest.version !== expectedVersion) {
  fail(`unexpected Chrome manifest version: ${manifest.version}`);
}
NODE

pnpm install --frozen-lockfile --lockfile-only --ignore-scripts >/dev/null \
  || fail "pnpm lockfile validation failed"

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

require_command xcodegen
[[ -n "$(xcodegen --version)" ]] \
  || fail "xcodegen must be installed"

IDENTITY_OUTPUT="$(
  security find-identity -v -p codesigning 2>/dev/null || true
)"
IDENTITY_MATCH_COUNT="$(
  printf '%s\n' "${IDENTITY_OUTPUT}" | awk -v expected="\"${INKBEAM_SIGNING_IDENTITY}\"" '
    index($0, expected) > 0 { count += 1 }
    END { print count + 0 }
  '
)"
[[ "${IDENTITY_MATCH_COUNT}" == "1" ]] \
  || {
    if [[ "${IDENTITY_MATCH_COUNT}" == "0" ]]; then
      fail "missing exact signing identity: ${EXPECTED_SIGNING_IDENTITY}"
    fi
    fail "expected exactly one signing identity: ${EXPECTED_SIGNING_IDENTITY}"
  }

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

SPARKLE_KEY_FILE="${REPO_ROOT}/Config/SparklePublicEDKey.txt"
[[ -f "${SPARKLE_KEY_FILE}" ]] \
  || fail "Config/SparklePublicEDKey.txt is missing"
SPARKLE_PUBLIC_KEY="$(
  node --input-type=module - "${SPARKLE_BIN}/generate_keys" "${SPARKLE_KEY_FILE}" <<'NODE'
import { execFileSync } from "node:child_process";
import fs from "node:fs";

const [generateKeysPath, keyFilePath] = process.argv.slice(2);

function isCanonical32ByteBase64(value) {
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
  const decoded = Buffer.from(value, "base64");
  return decoded.byteLength === 32 && decoded.toString("base64") === value;
}

let toolOutput;
try {
  toolOutput = execFileSync(generateKeysPath, ["--account", "inkbeam", "-p"], {
    encoding: "utf8",
  });
} catch {
  process.stderr.write("preflight: Sparkle key tool failed in read-only mode\n");
  process.exit(1);
}

const toolLines = toolOutput
  .split(/\r?\n/)
  .filter((line) => isCanonical32ByteBase64(line));
if (toolLines.length !== 1) {
  process.stderr.write(
    "preflight: Sparkle key tool must emit exactly one canonical 32-byte public key\n",
  );
  process.exit(1);
}

const fileLines = fs.readFileSync(keyFilePath, "utf8").split("\n");
if (fileLines.at(-1) === "") fileLines.pop();
if (fileLines.length !== 1 || !isCanonical32ByteBase64(fileLines[0])) {
  process.stderr.write(
    "preflight: Config/SparklePublicEDKey.txt must contain exactly one canonical 32-byte public key\n",
  );
  process.exit(1);
}
if (fileLines[0] !== toolLines[0]) {
  process.stderr.write("preflight: Sparkle public key mismatch\n");
  process.exit(1);
}
process.stdout.write(`${toolLines[0]}\n`);
NODE
)" || exit 1
[[ -n "${SPARKLE_PUBLIC_KEY}" ]] \
  || fail "Sparkle key tool did not emit a public key"

XCODE_MAJOR="$(
  xcodebuild -version | awk '/^Xcode / { split($2, parts, "."); print parts[1]; exit }'
)"
[[ "${XCODE_MAJOR}" == 26 ]] \
  || fail "Xcode 26 is required"

process_outcome="PASS"
printf 'preflight: %s %s %s\n' "${TAG}" "${EXPECTED_BRANCH}" "${EXPECTED_SHA}"
printf '%s\n' "${process_outcome}"

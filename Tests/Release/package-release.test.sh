#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h:h}"
PACKAGE_SCRIPT="${REPO_ROOT}/Scripts/package-release.sh"
VERIFY_SCRIPT="${REPO_ROOT}/Scripts/verify-release-artifacts.sh"
TEMP_PARENT="${TMPDIR:-/tmp}"
TEST_ROOT="$(
  mktemp -d "${TEMP_PARENT%/}/myshottr-release-contract.XXXXXX"
)"

fail() {
  echo "package-release.test: $*" >&2
  exit 1
}

cleanup() {
  case "${TEST_ROOT}" in
    "${TEMP_PARENT%/}/myshottr-release-contract."*)
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
    || fail "${label} did not report '${expected_message}'"
}

trap cleanup EXIT

[[ -x "${PACKAGE_SCRIPT}" ]] \
  || fail "package script is missing or not executable"
[[ -x "${VERIFY_SCRIPT}" ]] \
  || fail "artifact verifier is missing or not executable"

expect_failure \
  "invalid package version" \
  'version must match [0-9]+\.[0-9]+\.[0-9]+' \
  "${TEST_ROOT}/invalid-package.log" \
  "${PACKAGE_SCRIPT}" "1.0"

expect_failure \
  "invalid verifier version" \
  'version must match [0-9]+\.[0-9]+\.[0-9]+' \
  "${TEST_ROOT}/invalid-verifier.log" \
  "${VERIFY_SCRIPT}" "1.0" "${TEST_ROOT}/artifacts"

FIXTURE_REPO="${TEST_ROOT}/fixture-repo"
mkdir -p \
  "${FIXTURE_REPO}/Scripts" \
  "${FIXTURE_REPO}/Packages/chrome-extension/public" \
  "${FIXTURE_REPO}/Config"
cp "${PACKAGE_SCRIPT}" "${FIXTURE_REPO}/Scripts/package-release.sh"
printf 'lockfileVersion: 9.0\n' >"${FIXTURE_REPO}/pnpm-lock.yaml"
cat >"${FIXTURE_REPO}/project.yml" <<'YAML'
targets:
  MyShottr:
    info:
      properties:
        CFBundleShortVersionString: "0.1.0"
YAML
cat >"${FIXTURE_REPO}/Config/MyShottr-Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
</dict>
</plist>
PLIST
cat >"${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'JSON'
{
  "manifest_version": 3,
  "version": "0.1.0"
}
JSON
(
  cd "${FIXTURE_REPO}"
  git init -q
  git config user.email "release-contract@example.invalid"
  git config user.name "Release Contract"
  git add .
  git commit -qm "fixture"
)

expect_failure \
  "version drift" \
  "project.yml version does not equal 0.1.1" \
  "${TEST_ROOT}/version-drift.log" \
  "${FIXTURE_REPO}/Scripts/package-release.sh" "0.1.1"

printf '\n# dirty\n' >>"${FIXTURE_REPO}/project.yml"
expect_failure \
  "dirty source" \
  "source tree must be clean" \
  "${TEST_ROOT}/dirty-source.log" \
  "${FIXTURE_REPO}/Scripts/package-release.sh" "0.1.0"

ARTIFACT_DIRECTORY="${TEST_ROOT}/artifacts"
APP_STAGING="${TEST_ROOT}/app-staging/MyShottr.app"
EXTENSION_STAGING="${TEST_ROOT}/extension-staging/MyShottr-Chrome-0.1.0"
mkdir -p \
  "${ARTIFACT_DIRECTORY}" \
  "${APP_STAGING}/Contents/MacOS" \
  "${APP_STAGING}/Contents/Helpers" \
  "${APP_STAGING}/Contents/Resources/Editor/assets" \
  "${EXTENSION_STAGING}"
printf '#!/bin/zsh\nexit 0\n' >"${APP_STAGING}/Contents/MacOS/MyShottr"
printf '#!/bin/zsh\nexit 0\n' >"${APP_STAGING}/Contents/Helpers/MyShottrNativeHost"
chmod 0755 \
  "${APP_STAGING}/Contents/MacOS/MyShottr" \
  "${APP_STAGING}/Contents/Helpers/MyShottrNativeHost"
printf 'compiled assets\n' >"${APP_STAGING}/Contents/Resources/Assets.car"
printf 'app icon\n' >"${APP_STAGING}/Contents/Resources/AppIcon.icns"
cp \
  "${REPO_ROOT}/Config/chrome-extension-key.b64" \
  "${APP_STAGING}/Contents/Resources/chrome-extension-key.b64"
cat >"${APP_STAGING}/Contents/Resources/Editor/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <link rel="stylesheet" href="./assets/editor.css">
  </head>
  <body>
    <script type="module" src="./assets/editor.js"></script>
  </body>
</html>
HTML
printf 'body { color: black; }\n' \
  >"${APP_STAGING}/Contents/Resources/Editor/assets/editor.css"
printf 'globalThis.myshottr = true;\n' \
  >"${APP_STAGING}/Contents/Resources/Editor/assets/editor.js"
cat >"${APP_STAGING}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MyShottr</string>
  <key>CFBundleIdentifier</key>
  <string>com.myshottr.app</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
</dict>
</plist>
PLIST

PUBLIC_KEY="$(
  tr -d '\r\n' <"${REPO_ROOT}/Config/chrome-extension-key.b64"
)"
node --input-type=module - \
  "${EXTENSION_STAGING}/manifest.json" \
  "${PUBLIC_KEY}" <<'NODE'
import { writeFileSync } from "node:fs";

const [manifestPath, key] = process.argv.slice(2);
const manifest = {
  manifest_version: 3,
  name: "MyShottr Web Capture",
  version: "0.1.0",
  permissions: ["activeTab", "nativeMessaging"],
  content_security_policy: {
    extension_pages:
      "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-src 'none'; img-src 'self'; style-src 'self'",
  },
  background: {
    service_worker: "service-worker.js",
    type: "module",
  },
  key,
};
writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
NODE
printf 'chrome.action.onClicked.addListener(() => {});\n' \
  >"${EXTENSION_STAGING}/service-worker.js"

APP_ARCHIVE="${ARTIFACT_DIRECTORY}/MyShottr-0.1.0-macos.zip"
EXTENSION_ARCHIVE="${ARTIFACT_DIRECTORY}/MyShottr-Chrome-0.1.0.zip"
(
  cd "${APP_STAGING:h}"
  ditto -c -k --sequesterRsrc --keepParent \
    "${APP_STAGING:t}" "${APP_ARCHIVE}"
)
(
  cd "${EXTENSION_STAGING:h}"
  ditto -c -k --keepParent \
    "${EXTENSION_STAGING:t}" "${EXTENSION_ARCHIVE}"
)
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)

if ! "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}" \
  >"${TEST_ROOT}/valid-artifacts.log" 2>&1; then
  cat "${TEST_ROOT}/valid-artifacts.log" >&2
  /usr/bin/zipinfo -1 "${APP_ARCHIVE}" >&2
  fail "valid synthetic release artifacts were rejected"
fi

cp "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/valid-extension.zip"
node - "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/test-seam-extension" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const [archive, temporary] = process.argv.slice(2);
fs.mkdirSync(temporary);
execFileSync("ditto", ["-x", "-k", archive, temporary]);
const worker = path.join(
  temporary,
  "MyShottr-Chrome-0.1.0",
  "service-worker.js",
);
fs.appendFileSync(worker, "\nglobalThis.__myshottrE2E = {};\n");
fs.unlinkSync(archive);
execFileSync(
  "ditto",
  [
    "-c",
    "-k",
    "--keepParent",
    path.join(temporary, "MyShottr-Chrome-0.1.0"),
    archive,
  ],
);
NODE
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "production test seam" \
  "production extension contains a test seam" \
  "${TEST_ROOT}/test-seam.log" \
  "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
TRAVERSAL_ROOT="${TEST_ROOT}/traversal"
mkdir -p "${TRAVERSAL_ROOT}/nested"
printf 'escape\n' >"${TRAVERSAL_ROOT}/escape"
(
  cd "${TRAVERSAL_ROOT}/nested"
  /usr/bin/zip -q "${EXTENSION_ARCHIVE}" ../escape
)
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive traversal" \
  "archive contains unsafe path" \
  "${TEST_ROOT}/traversal.log" \
  "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
SYMLINK_ROOT="${TEST_ROOT}/symlink-extension"
ditto -x -k "${EXTENSION_ARCHIVE}" "${SYMLINK_ROOT}"
ln -s manifest.json \
  "${SYMLINK_ROOT}/MyShottr-Chrome-0.1.0/manifest-link.json"
rm "${EXTENSION_ARCHIVE}"
ditto -c -k --keepParent \
  "${SYMLINK_ROOT}/MyShottr-Chrome-0.1.0" "${EXTENSION_ARCHIVE}"
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive symlink" \
  "archive contains symbolic link" \
  "${TEST_ROOT}/symlink.log" \
  "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
JUNK_ROOT="${TEST_ROOT}/junk-extension"
ditto -x -k "${EXTENSION_ARCHIVE}" "${JUNK_ROOT}"
printf 'junk\n' >"${JUNK_ROOT}/MyShottr-Chrome-0.1.0/.DS_Store"
rm "${EXTENSION_ARCHIVE}"
ditto -c -k --keepParent \
  "${JUNK_ROOT}/MyShottr-Chrome-0.1.0" "${EXTENSION_ARCHIVE}"
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive junk" \
  "archive contains prohibited junk" \
  "${TEST_ROOT}/junk.log" \
  "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
node - "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/private-key-extension" <<'NODE'
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");

const [archive, temporary] = process.argv.slice(2);
fs.mkdirSync(temporary);
execFileSync("ditto", ["-x", "-k", archive, temporary]);
fs.writeFileSync(
  `${temporary}/MyShottr-Chrome-0.1.0/private-key.pem`,
  "not a real key\n",
);
fs.unlinkSync(archive);
execFileSync(
  "ditto",
  [
    "-c",
    "-k",
    "--keepParent",
    `${temporary}/MyShottr-Chrome-0.1.0`,
    archive,
  ],
);
NODE
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "MyShottr-0.1.0-macos.zip" \
    "MyShottr-Chrome-0.1.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "private key material" \
  "extension archive contains private key material" \
  "${TEST_ROOT}/private-key.log" \
  "${VERIFY_SCRIPT}" "0.1.0" "${ARTIFACT_DIRECTORY}"

echo "Release artifact verifier mutation checks passed."
echo "Release packaging contract passed."

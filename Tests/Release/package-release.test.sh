#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
REPO_ROOT="${SCRIPT_PATH:h:h:h}"
PACKAGE_SCRIPT="${REPO_ROOT}/Scripts/package-release.sh"
VERIFY_SCRIPT="${REPO_ROOT}/Scripts/verify-release-artifacts.sh"
TEST_ROOT="$(
  mktemp -d -t inkbeam-release-contract
)"
[[ -d "${TEST_ROOT}" && ! -L "${TEST_ROOT}" ]] \
  || {
    echo "package-release.test: mktemp did not create a safe directory" >&2
    exit 1
  }
TEST_ROOT="${TEST_ROOT:A}"
[[ "${TEST_ROOT:t}" == inkbeam-release-contract.* ]] \
  || {
    echo "package-release.test: mktemp returned an unexpected directory" >&2
    exit 1
  }
TEST_ROOT_PARENT="${TEST_ROOT:h}"

fail() {
  echo "package-release.test: $*" >&2
  exit 1
}

cleanup() {
  case "${TEST_ROOT:t}" in
    inkbeam-release-contract.*)
      [[ "${TEST_ROOT:h}" == "${TEST_ROOT_PARENT}" ]] \
        || {
          echo "package-release.test: refusing to clean moved directory" >&2
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
  if ! grep -Fq "${expected_message}" "${log_path}"; then
    cat "${log_path}" >&2
    fail "${label} did not report '${expected_message}'"
  fi
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
  "leading-zero package version" \
  'version must match [0-9]+\.[0-9]+\.[0-9]+ without leading zeros' \
  "${TEST_ROOT}/leading-zero-package.log" \
  "${PACKAGE_SCRIPT}" "01.0.0"

expect_failure \
  "invalid verifier version" \
  'version must match [0-9]+\.[0-9]+\.[0-9]+' \
  "${TEST_ROOT}/invalid-verifier.log" \
  "${VERIFY_SCRIPT}" "1.0" "${TEST_ROOT}/artifacts"

expect_failure \
  "leading-zero verifier version" \
  'version must match [0-9]+\.[0-9]+\.[0-9]+ without leading zeros' \
  "${TEST_ROOT}/leading-zero-verifier.log" \
  "${VERIFY_SCRIPT}" "0.01.0" "${TEST_ROOT}/artifacts"

FIXTURE_REPO="${TEST_ROOT}/fixture-repo"
mkdir -p \
  "${FIXTURE_REPO}/Scripts" \
  "${FIXTURE_REPO}/Packages/editor" \
  "${FIXTURE_REPO}/Packages/chrome-extension/public" \
  "${FIXTURE_REPO}/Config"
cp "${PACKAGE_SCRIPT}" "${FIXTURE_REPO}/Scripts/package-release.sh"
cp \
  "${REPO_ROOT}/Scripts/verify-release-metadata.mjs" \
  "${FIXTURE_REPO}/Scripts/verify-release-metadata.mjs"
cat >"${FIXTURE_REPO}/.gitignore" <<'IGNORE'
/Packages/editor/dist/
/Packages/chrome-extension/dist/
/Inkbeam.xcodeproj/
/dist/
IGNORE
printf 'lockfileVersion: 9.0\n' >"${FIXTURE_REPO}/pnpm-lock.yaml"
cat >"${FIXTURE_REPO}/project.yml" <<'YAML'
targets:
  Inkbeam:
    settings:
      base:
        MARKETING_VERSION: "0.2.0"
    info:
      properties:
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        InkbeamReleaseChannel: $(INKBEAM_RELEASE_CHANNEL_NAME)
YAML
cat >"${FIXTURE_REPO}/Config/Inkbeam-Info.plist" <<'PLIST'
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
cat >"${FIXTURE_REPO}/Packages/chrome-extension/public/manifest.json" <<'JSON'
{
  "manifest_version": 3,
  "version": "0.2.0"
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
  "project.yml MARKETING_VERSION is 0.2.0, expected 0.2.1" \
  "${TEST_ROOT}/version-drift.log" \
  "${FIXTURE_REPO}/Scripts/package-release.sh" "0.2.1"

printf '\n# dirty\n' >>"${FIXTURE_REPO}/project.yml"
expect_failure \
  "dirty source" \
  "source tree must be clean" \
  "${TEST_ROOT}/dirty-source.log" \
  "${FIXTURE_REPO}/Scripts/package-release.sh" "0.2.0"

git -C "${FIXTURE_REPO}" restore project.yml
EXTERNAL_SENTINEL="${TEST_ROOT}/external-sentinel"
mkdir -p "${EXTERNAL_SENTINEL}"
printf 'must remain unchanged\n' >"${EXTERNAL_SENTINEL}/sentinel.txt"
SENTINEL_BEFORE="$(
  shasum -a 256 "${EXTERNAL_SENTINEL}/sentinel.txt"
)"
ln -s "${EXTERNAL_SENTINEL}" "${FIXTURE_REPO}/Packages/editor/dist"
expect_failure \
  "ignored build-output symlink" \
  "generated path must be a canonical repository-contained directory" \
  "${TEST_ROOT}/build-output-symlink.log" \
  "${FIXTURE_REPO}/Scripts/package-release.sh" "0.2.0"
SENTINEL_AFTER="$(
  shasum -a 256 "${EXTERNAL_SENTINEL}/sentinel.txt"
)"
[[ "${SENTINEL_AFTER}" == "${SENTINEL_BEFORE}" ]] \
  || fail "build-output symlink target was mutated"
[[ -L "${FIXTURE_REPO}/Packages/editor/dist" ]] \
  || fail "build-output symlink was replaced before rejection"

ARTIFACT_DIRECTORY="${TEST_ROOT}/artifacts"
APP_STAGING="${TEST_ROOT}/app-staging/Inkbeam.app"
EXTENSION_STAGING="${TEST_ROOT}/extension-staging/Inkbeam-Chrome-0.2.0"
mkdir -p \
  "${ARTIFACT_DIRECTORY}" \
  "${APP_STAGING}/Contents/MacOS" \
  "${APP_STAGING}/Contents/Helpers" \
  "${APP_STAGING}/Contents/Resources/Editor/assets" \
  "${EXTENSION_STAGING}"
cat >"${TEST_ROOT}/fixture-executable.c" <<'C'
int main(void) {
  return 0;
}
C
FIXTURE_MAIN="${TEST_ROOT}/Inkbeam.fixture"
FIXTURE_HELPER="${TEST_ROOT}/InkbeamNativeHost.fixture"
xcrun clang \
  -arch x86_64 \
  -arch arm64 \
  -mmacosx-version-min=15.0 \
  -Os \
  "${TEST_ROOT}/fixture-executable.c" \
  -o "${FIXTURE_MAIN}"
xcrun clang \
  -arch x86_64 \
  -arch arm64 \
  -mmacosx-version-min=15.0 \
  -Os \
  "${TEST_ROOT}/fixture-executable.c" \
  -o "${FIXTURE_HELPER}"
codesign --force --sign - --timestamp=none "${FIXTURE_MAIN}"
codesign --force --sign - --timestamp=none "${FIXTURE_HELPER}"
mv "${FIXTURE_MAIN}" "${APP_STAGING}/Contents/MacOS/Inkbeam"
mv "${FIXTURE_HELPER}" \
  "${APP_STAGING}/Contents/Helpers/InkbeamNativeHost"
printf 'compiled assets\n' >"${APP_STAGING}/Contents/Resources/Assets.car"
printf 'app icon\n' >"${APP_STAGING}/Contents/Resources/AppIcon.icns"
printf 'APPL????' >"${APP_STAGING}/Contents/PkgInfo"
cp \
  "${REPO_ROOT}/Config/chrome-extension-key.b64" \
  "${APP_STAGING}/Contents/Resources/chrome-extension-key.b64"
cat >"${APP_STAGING}/Contents/Resources/Editor/index.html" <<'HTML'
<!doctype html>
<html>
  <head>
    <link rel="stylesheet" href="./assets/index-fixture.css">
  </head>
  <body>
    <script type="module" src="./assets/index-fixture.js"></script>
  </body>
</html>
HTML
printf 'body { color: black; }\n' \
  >"${APP_STAGING}/Contents/Resources/Editor/assets/index-fixture.css"
printf 'globalThis.inkbeam = true;\n' \
  >"${APP_STAGING}/Contents/Resources/Editor/assets/index-fixture.js"
cat >"${APP_STAGING}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Inkbeam</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>dev.gihwan.inkbeam</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
</dict>
</plist>
PLIST

xattr -w dev.gihwan.inkbeam.release-fixture custom \
  "${APP_STAGING}/Contents/Resources/AppIcon.icns"
xattr -w com.apple.quarantine '0081;00000000;InkbeamReleaseTest;' \
  "${APP_STAGING}/Contents/Resources/Assets.car"

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
  name: "Inkbeam Web Capture",
  version: "0.2.0",
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

APP_ARCHIVE="${ARTIFACT_DIRECTORY}/Inkbeam-0.2.0-macos.zip"
EXTENSION_ARCHIVE="${ARTIFACT_DIRECTORY}/Inkbeam-Chrome-0.2.0.zip"
(
  cd "${APP_STAGING:h}"
  ditto -c -k \
    --norsrc --noextattr --noqtn --noacl --keepParent \
    "${APP_STAGING:t}" "${APP_ARCHIVE}"
)
(
  cd "${EXTENSION_STAGING:h}"
  ditto -c -k \
    --norsrc --noextattr --noqtn --noacl --keepParent \
    "${EXTENSION_STAGING:t}" "${EXTENSION_ARCHIVE}"
)
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)

if ! "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}" \
  >"${TEST_ROOT}/valid-artifacts.log" 2>&1; then
  cat "${TEST_ROOT}/valid-artifacts.log" >&2
  /usr/bin/zipinfo -1 "${APP_ARCHIVE}" >&2
  mkdir -p "${TEST_ROOT}/valid-artifact-diagnostic"
  ditto -x -k \
    "${APP_ARCHIVE}" "${TEST_ROOT}/valid-artifact-diagnostic"
  xattr -lr "${TEST_ROOT}/valid-artifact-diagnostic" >&2 || true
  fail "valid synthetic release artifacts were rejected"
fi

NO_XATTR_EXTRACTION="${TEST_ROOT}/no-xattr-extraction"
ditto -x -k "${APP_ARCHIVE}" "${NO_XATTR_EXTRACTION}"
while IFS= read -r extracted_path; do
  XATTR_NAMES="$(
    xattr "${extracted_path}" 2>/dev/null
  )"
  while IFS= read -r xattr_name; do
    [[ -z "${xattr_name}" || "${xattr_name}" == "com.apple.provenance" ]] \
      || fail "validated public app archive restored extended attributes"
  done <<<"${XATTR_NAMES}"
done < <(find "${NO_XATTR_EXTRACTION}/Inkbeam.app" -print)

cp "${APP_ARCHIVE}" "${TEST_ROOT}/valid-app.zip"
cp "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/valid-extension.zip"

refresh_checksums() {
  (
    cd "${ARTIFACT_DIRECTORY}"
    shasum -a 256 \
      "Inkbeam-0.2.0-macos.zip" \
      "Inkbeam-Chrome-0.2.0.zip" \
      >SHA256SUMS.txt
  )
}

repack_app_without_metadata() {
  local app_root="$1"
  rm "${APP_ARCHIVE}"
  ditto -c -k \
    --norsrc --noextattr --noqtn --noacl --keepParent \
    "${app_root}/Inkbeam.app" "${APP_ARCHIVE}"
  refresh_checksums
}

UNEXPECTED_EXECUTABLE_ROOT="${TEST_ROOT}/unexpected-executable-app"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${UNEXPECTED_EXECUTABLE_ROOT}"
cp \
  "${UNEXPECTED_EXECUTABLE_ROOT}/Inkbeam.app/Contents/MacOS/Inkbeam" \
  "${UNEXPECTED_EXECUTABLE_ROOT}/Inkbeam.app/Contents/MacOS/UnexpectedExecutable"
repack_app_without_metadata "${UNEXPECTED_EXECUTABLE_ROOT}"
expect_failure \
  "unexpected app executable" \
  "app contains an unexpected executable" \
  "${TEST_ROOT}/unexpected-executable.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

UNEXPECTED_ICON_NAME_ROOT="${TEST_ROOT}/unexpected-icon-name"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${UNEXPECTED_ICON_NAME_ROOT}"
plutil -replace CFBundleIconName -string WrongIcon \
  "${UNEXPECTED_ICON_NAME_ROOT}/Inkbeam.app/Contents/Info.plist"
repack_app_without_metadata "${UNEXPECTED_ICON_NAME_ROOT}"
expect_failure \
  "unexpected app icon name" \
  "app icon name is not AppIcon" \
  "${TEST_ROOT}/unexpected-icon-name.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

UNEXPECTED_ICON_FILE_ROOT="${TEST_ROOT}/unexpected-icon-file"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${UNEXPECTED_ICON_FILE_ROOT}"
plutil -replace CFBundleIconFile -string WrongIcon \
  "${UNEXPECTED_ICON_FILE_ROOT}/Inkbeam.app/Contents/Info.plist"
repack_app_without_metadata "${UNEXPECTED_ICON_FILE_ROOT}"
expect_failure \
  "unexpected app icon file" \
  "app icon file is not AppIcon" \
  "${TEST_ROOT}/unexpected-icon-file.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

APP_PRIVATE_KEY_ROOT="${TEST_ROOT}/app-private-key"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${APP_PRIVATE_KEY_ROOT}"
cat >"${APP_PRIVATE_KEY_ROOT}/Inkbeam.app/Contents/Resources/private-key.pem" <<'PEM'
-----BEGIN PRIVATE KEY-----
not-a-real-private-key
-----END PRIVATE KEY-----
PEM
repack_app_without_metadata "${APP_PRIVATE_KEY_ROOT}"
expect_failure \
  "app private key material" \
  "release artifact contains private key material" \
  "${TEST_ROOT}/app-private-key.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

APP_XATTR_ROOT="${TEST_ROOT}/app-xattr"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${APP_XATTR_ROOT}"
xattr -w dev.gihwan.inkbeam.release-mutation custom \
  "${APP_XATTR_ROOT}/Inkbeam.app/Contents/Resources/AppIcon.icns"
rm "${APP_ARCHIVE}"
ditto -c -k --sequesterRsrc --keepParent \
  "${APP_XATTR_ROOT}/Inkbeam.app" "${APP_ARCHIVE}"
refresh_checksums
expect_failure \
  "app AppleDouble metadata" \
  "app archive contains prohibited AppleDouble metadata" \
  "${TEST_ROOT}/app-appledouble.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

THIN_HELPER_ROOT="${TEST_ROOT}/thin-helper"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${THIN_HELPER_ROOT}"
lipo -thin arm64 \
  "${THIN_HELPER_ROOT}/Inkbeam.app/Contents/Helpers/InkbeamNativeHost" \
  -output "${THIN_HELPER_ROOT}/InkbeamNativeHost.thin"
mv \
  "${THIN_HELPER_ROOT}/InkbeamNativeHost.thin" \
  "${THIN_HELPER_ROOT}/Inkbeam.app/Contents/Helpers/InkbeamNativeHost"
repack_app_without_metadata "${THIN_HELPER_ROOT}"
expect_failure \
  "thin Native Messaging helper" \
  "app executable must contain exactly arm64 and x86_64" \
  "${TEST_ROOT}/thin-helper.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

APP_TEST_SEAM_ROOT="${TEST_ROOT}/app-test-seam"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${APP_TEST_SEAM_ROOT}"
printf '\n__inkbeamE2E\n' \
  >>"${APP_TEST_SEAM_ROOT}/Inkbeam.app/Contents/Resources/Assets.car"
repack_app_without_metadata "${APP_TEST_SEAM_ROOT}"
expect_failure \
  "app test seam" \
  "release artifact contains a test seam" \
  "${TEST_ROOT}/app-test-seam.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

APP_INLINE_SOURCE_MAP_ROOT="${TEST_ROOT}/app-inline-source-map"
ditto -x -k "${TEST_ROOT}/valid-app.zip" "${APP_INLINE_SOURCE_MAP_ROOT}"
printf '\n//# sourceMappingURL=data:application/json;base64,e30=\n' \
  >>"${APP_INLINE_SOURCE_MAP_ROOT}/Inkbeam.app/Contents/Resources/Editor/assets/index-fixture.js"
repack_app_without_metadata "${APP_INLINE_SOURCE_MAP_ROOT}"
expect_failure \
  "app inline source map" \
  "release artifact JavaScript contains source map metadata" \
  "${TEST_ROOT}/app-inline-source-map.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-app.zip" "${APP_ARCHIVE}"
refresh_checksums

node - "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/test-seam-extension" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const [archive, temporary] = process.argv.slice(2);
fs.mkdirSync(temporary);
execFileSync("ditto", ["-x", "-k", archive, temporary]);
const worker = path.join(
  temporary,
  "Inkbeam-Chrome-0.2.0",
  "service-worker.js",
);
fs.appendFileSync(worker, "\nglobalThis.__inkbeamE2E = {};\n");
fs.unlinkSync(archive);
execFileSync(
  "ditto",
  [
    "-c",
    "-k",
    "--norsrc",
    "--noextattr",
    "--noqtn",
    "--noacl",
    "--keepParent",
    path.join(temporary, "Inkbeam-Chrome-0.2.0"),
    archive,
  ],
);
NODE
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "production test seam" \
  "release artifact contains a test seam" \
  "${TEST_ROOT}/test-seam.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
EXTENSION_INLINE_SOURCE_MAP_ROOT="${TEST_ROOT}/extension-inline-source-map"
ditto -x -k \
  "${EXTENSION_ARCHIVE}" "${EXTENSION_INLINE_SOURCE_MAP_ROOT}"
printf '\nglobalThis.embeddedMap = {"sourcesContent":["source"]};\n' \
  >>"${EXTENSION_INLINE_SOURCE_MAP_ROOT}/Inkbeam-Chrome-0.2.0/service-worker.js"
rm "${EXTENSION_ARCHIVE}"
ditto -c -k \
  --norsrc --noextattr --noqtn --noacl --keepParent \
  "${EXTENSION_INLINE_SOURCE_MAP_ROOT}/Inkbeam-Chrome-0.2.0" \
  "${EXTENSION_ARCHIVE}"
refresh_checksums
expect_failure \
  "extension inline source map" \
  "release artifact JavaScript contains source map metadata" \
  "${TEST_ROOT}/extension-inline-source-map.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

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
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive traversal" \
  "archive contains unsafe path" \
  "${TEST_ROOT}/traversal.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
SYMLINK_ROOT="${TEST_ROOT}/symlink-extension"
ditto -x -k "${EXTENSION_ARCHIVE}" "${SYMLINK_ROOT}"
ln -s manifest.json \
  "${SYMLINK_ROOT}/Inkbeam-Chrome-0.2.0/manifest-link.json"
rm "${EXTENSION_ARCHIVE}"
ditto -c -k \
  --norsrc --noextattr --noqtn --noacl --keepParent \
  "${SYMLINK_ROOT}/Inkbeam-Chrome-0.2.0" "${EXTENSION_ARCHIVE}"
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive symlink" \
  "archive contains symbolic link" \
  "${TEST_ROOT}/symlink.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
JUNK_ROOT="${TEST_ROOT}/junk-extension"
ditto -x -k "${EXTENSION_ARCHIVE}" "${JUNK_ROOT}"
printf 'junk\n' >"${JUNK_ROOT}/Inkbeam-Chrome-0.2.0/.DS_Store"
rm "${EXTENSION_ARCHIVE}"
ditto -c -k \
  --norsrc --noextattr --noqtn --noacl --keepParent \
  "${JUNK_ROOT}/Inkbeam-Chrome-0.2.0" "${EXTENSION_ARCHIVE}"
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "archive junk" \
  "archive contains prohibited junk" \
  "${TEST_ROOT}/junk.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

cp "${TEST_ROOT}/valid-extension.zip" "${EXTENSION_ARCHIVE}"
node - "${EXTENSION_ARCHIVE}" "${TEST_ROOT}/private-key-extension" <<'NODE'
const fs = require("node:fs");
const { execFileSync } = require("node:child_process");

const [archive, temporary] = process.argv.slice(2);
fs.mkdirSync(temporary);
execFileSync("ditto", ["-x", "-k", archive, temporary]);
fs.writeFileSync(
  `${temporary}/Inkbeam-Chrome-0.2.0/private-key.pem`,
  "not a real key\n",
);
fs.unlinkSync(archive);
execFileSync(
  "ditto",
  [
    "-c",
    "-k",
    "--norsrc",
    "--noextattr",
    "--noqtn",
    "--noacl",
    "--keepParent",
    `${temporary}/Inkbeam-Chrome-0.2.0`,
    archive,
  ],
);
NODE
(
  cd "${ARTIFACT_DIRECTORY}"
  shasum -a 256 \
    "Inkbeam-0.2.0-macos.zip" \
    "Inkbeam-Chrome-0.2.0.zip" \
    >SHA256SUMS.txt
)
expect_failure \
  "private key material" \
  "extension archive contains private key material" \
  "${TEST_ROOT}/private-key.log" \
  "${VERIFY_SCRIPT}" "0.2.0" "${ARTIFACT_DIRECTORY}"

echo "Release artifact verifier mutation checks passed."
echo "Release packaging contract passed."

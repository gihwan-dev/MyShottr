# MyShottr Public GitHub Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the completed MyShottr v1 as a documented MIT-licensed public repository with reproducible CI, unsigned macOS and unpacked Chrome packages, checksums, and a live verified `v0.1.0` GitHub Release.

**Architecture:** Build and test the product from one exact commit, package the Release app and extension with deterministic names, and let a tag-triggered GitHub Actions workflow publish only after the complete gate passes. Keep signing and notarization absent and explicit. Verify the uploaded artifacts by downloading them again and testing their checksums and install structure.

**Tech Stack:** GitHub Actions, GitHub CLI, zsh, XcodeGen, Xcode, pnpm 10.14, Node 22, Vite, Playwright, SHA-256, Markdown

## Global Constraints

- Execute this plan only after the editor-polish, native-capture, Chrome-capture, and recovery-hardening plans pass their completion gates.
- Repository name is exactly `gihwan-dev/MyShottr`.
- Repository visibility is public.
- License is exactly MIT.
- Initial release tag and version are exactly `v0.1.0` and `0.1.0`.
- Release artifacts are exactly `MyShottr-0.1.0-macos.zip`, `MyShottr-Chrome-0.1.0.zip`, and `SHA256SUMS.txt`.
- `v0.1.0` is unsigned and unnotarized; do not claim otherwise.
- Chrome distribution is an unpacked extension ZIP, not a Chrome Web Store package.
- Do not publish from a dirty worktree or from a commit different from the tested and manually accepted SHA.
- A failed test, build, validation, package, checksum, upload, or downloaded-artifact smoke test stops deployment.
- Do not add telemetry, update services, signing credentials, or secrets.
- Use TDD for scripts and commit after every task before repository publication.

---

## Repository Map for This Plan

```text
.github/workflows/
├── ci.yml
└── release.yml
docs/
├── images/
│   └── editor-quick-ink.png
├── releases/
│   └── v0.1.0.md
└── testing/
    └── release-installation.md
Scripts/
├── package-release.sh
├── verify-release-artifacts.sh
└── verify-v1.sh
LICENSE
README.md
```

## Shared Release Contract

```text
tag: v0.1.0
version: 0.1.0
repository: gihwan-dev/MyShottr
app archive: MyShottr-0.1.0-macos.zip
extension archive: MyShottr-Chrome-0.1.0.zip
checksum file: SHA256SUMS.txt
```

### Task 1: Reproducible Release Packaging

**Files:**
- Create: `Scripts/package-release.sh`
- Create: `Scripts/verify-release-artifacts.sh`
- Create: `Tests/Release/package-release.test.sh`
- Modify: `.gitignore`
- Modify: `package.json`

**Interfaces:**
- Consumes: a clean source tree, version `0.1.0`, built editor, built Chrome extension, generated Xcode project, and Release app.
- Produces: `dist/release/0.1.0/MyShottr-0.1.0-macos.zip`, `MyShottr-Chrome-0.1.0.zip`, and `SHA256SUMS.txt`.

- [ ] **Step 1: Write a failing packaging contract test**

Create `Tests/Release/package-release.test.sh`:

```bash
#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="${REPO_ROOT}/Scripts/package-release.sh"
VERIFY="${REPO_ROOT}/Scripts/verify-release-artifacts.sh"

test -x "${SCRIPT}"
test -x "${VERIFY}"

if "${SCRIPT}" 1.0 >/tmp/myshottr-package-invalid.log 2>&1; then
  echo "invalid semantic version unexpectedly succeeded" >&2
  exit 1
fi

grep -Fq 'version must match [0-9]+\.[0-9]+\.[0-9]+' \
  /tmp/myshottr-package-invalid.log

grep -q 'MyShottr-${VERSION}-macos.zip' "${SCRIPT}"
grep -q 'MyShottr-Chrome-${VERSION}.zip' "${SCRIPT}"
grep -q 'SHA256SUMS.txt' "${SCRIPT}"
grep -q 'CODE_SIGNING_ALLOWED=NO' "${SCRIPT}"
```

- [ ] **Step 2: Run the packaging contract and verify failure**

Run:

```bash
zsh Tests/Release/package-release.test.sh
```

Expected: FAIL because the scripts do not exist.

- [ ] **Step 3: Implement the packaging script**

Create `Scripts/package-release.sh`:

```bash
#!/bin/zsh
set -euo pipefail

VERSION="${1:-}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'version must match [0-9]+\.[0-9]+\.[0-9]+' >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${REPO_ROOT}/dist/release/${VERSION}"
BUILD_ROOT="$(mktemp -d)"
STAGING_ROOT="$(mktemp -d)"
trap 'rm -rf "${BUILD_ROOT}" "${STAGING_ROOT}"' EXIT

cd "${REPO_ROOT}"

node - "${VERSION}" <<'NODE'
const fs = require("node:fs");
const version = process.argv[2];
const project = fs.readFileSync("project.yml", "utf8");
const manifest = JSON.parse(
  fs.readFileSync("Packages/chrome-extension/public/manifest.json", "utf8")
);
if (!project.includes(`CFBundleShortVersionString: "${version}"`)) {
  throw new Error(`project.yml version does not equal ${version}`);
}
if (manifest.version !== version) {
  throw new Error(`Chrome manifest version does not equal ${version}`);
}
NODE

pnpm --filter @myshottr/editor build
pnpm --filter @myshottr/chrome-extension build
xcodegen generate
xcodebuild build \
  -project MyShottr.xcodeproj \
  -scheme MyShottr \
  -configuration Release \
  -derivedDataPath "${BUILD_ROOT}/DerivedData" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

APP="${BUILD_ROOT}/DerivedData/Build/Products/Release/MyShottr.app"
EXTENSION="${REPO_ROOT}/Packages/chrome-extension/dist"
APP_ARCHIVE="${OUTPUT_ROOT}/MyShottr-${VERSION}-macos.zip"
EXTENSION_ARCHIVE="${OUTPUT_ROOT}/MyShottr-Chrome-${VERSION}.zip"
CHECKSUMS="${OUTPUT_ROOT}/SHA256SUMS.txt"

test -d "${APP}"
test -x "${APP}/Contents/MacOS/MyShottr"
test -x "${APP}/Contents/Helpers/MyShottrNativeHost"
test -f "${EXTENSION}/manifest.json"

rm -rf "${OUTPUT_ROOT}"
mkdir -p "${OUTPUT_ROOT}"

ditto -c -k --sequesterRsrc --keepParent "${APP}" "${APP_ARCHIVE}"

EXTENSION_PACKAGE="${STAGING_ROOT}/MyShottr-Chrome-${VERSION}"
ditto "${EXTENSION}" "${EXTENSION_PACKAGE}"
ditto -c -k --keepParent "${EXTENSION_PACKAGE}" "${EXTENSION_ARCHIVE}"

(
  cd "${OUTPUT_ROOT}"
  shasum -a 256 \
    "MyShottr-${VERSION}-macos.zip" \
    "MyShottr-Chrome-${VERSION}.zip" \
    > "${CHECKSUMS}"
)

"${REPO_ROOT}/Scripts/verify-release-artifacts.sh" \
  "${VERSION}" "${OUTPUT_ROOT}"
```

The only recursive deletion target is the validated, version-specific
`dist/release/<semver>` directory.

- [ ] **Step 4: Implement artifact verification**

Create `Scripts/verify-release-artifacts.sh`:

```bash
#!/bin/zsh
set -euo pipefail

VERSION="${1:?usage: verify-release-artifacts.sh VERSION DIRECTORY}"
DIRECTORY="${2:?usage: verify-release-artifacts.sh VERSION DIRECTORY}"
APP_ARCHIVE="${DIRECTORY}/MyShottr-${VERSION}-macos.zip"
EXTENSION_ARCHIVE="${DIRECTORY}/MyShottr-Chrome-${VERSION}.zip"
CHECKSUMS="${DIRECTORY}/SHA256SUMS.txt"
TEMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEMP_ROOT}"' EXIT

test -f "${APP_ARCHIVE}"
test -f "${EXTENSION_ARCHIVE}"
test -f "${CHECKSUMS}"

(
  cd "${DIRECTORY}"
  shasum -a 256 -c SHA256SUMS.txt
)

ditto -x -k "${APP_ARCHIVE}" "${TEMP_ROOT}/app"
ditto -x -k "${EXTENSION_ARCHIVE}" "${TEMP_ROOT}/extension"

APP="${TEMP_ROOT}/app/MyShottr.app"
EXTENSION="${TEMP_ROOT}/extension/MyShottr-Chrome-${VERSION}"

test -x "${APP}/Contents/MacOS/MyShottr"
test -x "${APP}/Contents/Helpers/MyShottrNativeHost"
test -f "${APP}/Contents/Resources/Assets.car"
test -f "${EXTENSION}/manifest.json"

plutil -extract CFBundleShortVersionString raw \
  "${APP}/Contents/Info.plist" | grep -qx "${VERSION}"

node - "${EXTENSION}/manifest.json" "${VERSION}" <<'NODE'
const fs = require("node:fs");
const [manifestPath, version] = process.argv.slice(2);
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
if (manifest.version !== version) throw new Error("extension version mismatch");
if (JSON.stringify(manifest.permissions) !==
    JSON.stringify(["activeTab", "nativeMessaging"])) {
  throw new Error("extension permissions changed");
}
if (manifest.host_permissions || manifest.content_scripts) {
  throw new Error("extension contains prohibited access");
}
if (typeof manifest.key !== "string" || manifest.key.length === 0) {
  throw new Error("extension identity key missing");
}
NODE
```

- [ ] **Step 5: Wire scripts into the workspace and run them**

Add to root `package.json`:

```json
{
  "scripts": {
    "package:release": "Scripts/package-release.sh"
  }
}
```

Preserve the existing scripts. Add `/dist/release/` to `.gitignore`, then run:

```bash
chmod +x Scripts/package-release.sh \
  Scripts/verify-release-artifacts.sh \
  Tests/Release/package-release.test.sh
zsh Tests/Release/package-release.test.sh
Scripts/package-release.sh 0.1.0
```

Expected: the contract test passes and the three expected files exist under
`dist/release/0.1.0`.

- [ ] **Step 6: Commit release packaging**

```bash
git add .gitignore package.json Scripts/package-release.sh \
  Scripts/verify-release-artifacts.sh Tests/Release/package-release.test.sh
git commit -m "build: add reproducible release packaging"
```

### Task 2: CI and Tag-Triggered Release Workflow

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Create: `Tests/Release/workflows.test.mjs`
- Modify: `package.json`

**Interfaces:**
- Consumes: `Scripts/verify-v1.sh`, `Scripts/package-release.sh`, a
  `v<semver>` tag, and GitHub's built-in `GITHUB_TOKEN`.
- Produces: blocking public CI and an automated GitHub Release containing the
  exact three approved files.

- [ ] **Step 1: Write failing workflow contract tests**

Create:

```js
import fs from "node:fs";
import assert from "node:assert/strict";

const ci = fs.readFileSync(".github/workflows/ci.yml", "utf8");
const release = fs.readFileSync(".github/workflows/release.yml", "utf8");

assert.match(ci, /macos-15/);
assert.match(ci, /Scripts\/verify-v1\.sh/);
assert.match(release, /tags:/);
assert.match(release, /v\*/);
assert.match(release, /permissions:\s*\n\s*contents: write/);
assert.match(release, /Scripts\/package-release\.sh/);
assert.match(release, /gh release create/);
assert.doesNotMatch(release, /APPLE_|NOTARY|SIGNING|CERTIFICATE/);
```

- [ ] **Step 2: Run the contract and verify failure**

Run:

```bash
node Tests/Release/workflows.test.mjs
```

Expected: ENOENT for the missing workflow files.

- [ ] **Step 3: Create branch and pull-request CI**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main, "worktree/**"]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  verify:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with:
          version: 10.14.0
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Verify v1
        run: Scripts/verify-v1.sh
```

- [ ] **Step 4: Create the release workflow**

Create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-15
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: pnpm/action-setup@v4
        with:
          version: 10.14.0
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: pnpm
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Validate tag
        run: |
          set -euo pipefail
          VERSION="${GITHUB_REF_NAME#v}"
          [[ "${GITHUB_REF_NAME}" == "v${VERSION}" ]]
          [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
      - name: Verify exact source
        run: Scripts/verify-v1.sh
      - name: Package release
        run: Scripts/package-release.sh "${GITHUB_REF_NAME#v}"
      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          VERSION="${GITHUB_REF_NAME#v}"
          OUTPUT="dist/release/${VERSION}"
          gh release create "${GITHUB_REF_NAME}" \
            "${OUTPUT}/MyShottr-${VERSION}-macos.zip" \
            "${OUTPUT}/MyShottr-Chrome-${VERSION}.zip" \
            "${OUTPUT}/SHA256SUMS.txt" \
            --repo "${GITHUB_REPOSITORY}" \
            --title "MyShottr ${GITHUB_REF_NAME}" \
            --notes-file "docs/releases/${GITHUB_REF_NAME}.md" \
            --verify-tag
```

- [ ] **Step 5: Run workflow contracts and local complete gate**

Add:

```json
{
  "scripts": {
    "test:release": "node Tests/Release/workflows.test.mjs && zsh Tests/Release/package-release.test.sh"
  }
}
```

Preserve other scripts, then run:

```bash
pnpm test:release
Scripts/verify-v1.sh
Scripts/package-release.sh 0.1.0
```

Expected: all commands exit `0`.

- [ ] **Step 6: Commit CI and release automation**

```bash
git add .github package.json Tests/Release/workflows.test.mjs
git commit -m "ci: verify and publish tagged releases"
```

### Task 3: Public README, License, Release Notes, and Real Screenshots

**Files:**
- Create: `LICENSE`
- Rewrite: `README.md`
- Create: `docs/images/editor-quick-ink.png`
- Create: `docs/releases/v0.1.0.md`
- Create: `docs/testing/release-installation.md`
- Create: `Tests/Release/documentation.test.mjs`

**Interfaces:**
- Consumes: the completed app, extension, Quick Ink identity, real capture
  workflow, and approved v1 limitations.
- Produces: public installation, use, development, privacy, and release
  documentation backed by a screenshot of the real release candidate.

- [ ] **Step 1: Write a failing documentation contract**

Create:

```js
import fs from "node:fs";
import assert from "node:assert/strict";

const readme = fs.readFileSync("README.md", "utf8");
const license = fs.readFileSync("LICENSE", "utf8");
const notes = fs.readFileSync("docs/releases/v0.1.0.md", "utf8");

for (const text of [
  "macOS 15", "Command-Shift-2", "Chrome", "Developer mode",
  "unsigned", "unnotarized", "MIT", "viewport", "full-page",
  "desktop mockup", "No telemetry",
]) {
  assert.ok(readme.includes(text), `README missing: ${text}`);
}
assert.ok(readme.includes("docs/images/editor-quick-ink.png"));
assert.ok(license.includes("MIT License"));
assert.ok(license.includes("Copyright (c) 2026 gihwan-dev"));
assert.ok(notes.includes("MyShottr-0.1.0-macos.zip"));
assert.ok(notes.includes("MyShottr-Chrome-0.1.0.zip"));
assert.ok(fs.statSync("docs/images/editor-quick-ink.png").size > 10_000);
```

- [ ] **Step 2: Run the documentation contract and verify failure**

Run:

```bash
node Tests/Release/documentation.test.mjs
```

Expected: missing or incomplete public documentation.

- [ ] **Step 3: Add the MIT License**

Create `LICENSE`:

```text
MIT License

Copyright (c) 2026 gihwan-dev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Write the public README**

Rewrite `README.md` with this exact section order and content contract:

```markdown
# MyShottr

Fast, local screenshot capture and Excalidraw-style annotation for macOS.

![MyShottr Quick Ink editor](docs/images/editor-quick-ink.png)

MyShottr captures a macOS region or the visible content of the active Chrome
tab, then opens it in one editable canvas. Captures stay on your Mac.

## Features

- Native region capture with `Command-Shift-2`
- Clean Chrome viewport capture without tabs, address bar, or toolbars
- Rectangle, arrow, line, text, freehand, highlighter, blur, redaction, and
  numbered-marker annotations
- Copy Image, PNG export, and editable `.myshottr` projects
- Crash recovery for unsaved documents
- No account, upload, analytics, or telemetry

## 한국어 빠른 설치

MyShottr는 macOS 15 이상에서 동작합니다. `v0.1.0`은 unsigned 및
unnotarized 빌드이므로 아래의 첫 실행 안내가 필요합니다.

1. GitHub Releases에서 `MyShottr-0.1.0-macos.zip`을 내려받아 압축을 풉니다.
2. `MyShottr.app`을 `/Applications`로 옮깁니다.
3. 앱을 Control-클릭하여 **열기**를 선택합니다. 차단되면 **시스템 설정
   → 개인정보 보호 및 보안 → 확인 없이 열기**를 사용합니다.
4. 앱을 한 번 실행하여 Chrome Native Messaging Host를 등록합니다.
5. `MyShottr-Chrome-0.1.0.zip`을 풀고 `chrome://extensions`에서 개발자
   모드를 켠 뒤 **압축해제된 확장 프로그램을 로드합니다**.
6. 화면 기록 권한을 허용한 뒤 MyShottr를 다시 실행합니다.

Control-클릭 실행이 제공되지 않는 환경에서만 다음 명령으로 다운로드
격리 속성을 제거할 수 있습니다.

```bash
xattr -dr com.apple.quarantine /Applications/MyShottr.app
```

## Install

MyShottr requires macOS 15 or newer. Version `v0.1.0` is unsigned and
unnotarized, so macOS Gatekeeper requires the first-launch steps above.

Download both ZIP files from the
[latest GitHub Release](https://github.com/gihwan-dev/MyShottr/releases).
Move `MyShottr.app` to `/Applications`, open it once, and load the extracted
Chrome directory from `chrome://extensions` with Developer mode enabled.

## Use

- Press `Command-Shift-2` or choose **Capture Area** from the menu bar.
- Click the Chrome extension or press `Option-Shift-2` for the active viewport.
- Press `Command-Shift-C` to copy the composed image.
- Press `Command-S` to save an editable project.
- Press `Command-E` to export a PNG.

## Annotation shortcuts

| Tool | Key |
| --- | --- |
| Select | `V` |
| Rectangle | `R` |
| Arrow | `A` |
| Line | `L` |
| Text | `T` |
| Freehand | `P` |
| Highlighter | `H` |
| Blur | `B` |
| Redaction | `X` |
| Number marker | `N` |

Blur is a visual effect, not secure redaction. Use Redaction when pixels must
be fully covered.

## Privacy

Captures, projects, recovery files, and exports stay on the Mac. MyShottr has
no account, cloud upload, analytics, or telemetry. The Chrome extension uses
only `activeTab` and `nativeMessaging`.

## Development

Prerequisites: macOS 15+, Xcode with Swift 6, Node 22+, pnpm 10.14+, and
XcodeGen.

```bash
pnpm install --frozen-lockfile
Scripts/verify-v1.sh
```

Generate and open the Xcode project:

```bash
xcodegen generate
open MyShottr.xcodeproj
```

## v1 limitations and roadmap

- Chrome captures the visible viewport only; full-page scrolling capture is
  planned behind the existing capture-mode boundary.
- Desktop mockup and presentation frames are planned behind the existing
  presentation layer.
- Safari and Firefox are not supported in v1.
- The app has no automatic updater and is not distributed through an app
  store.
- Developer ID signing and notarization are planned after `v0.1.0`.

## License

MyShottr is available under the MIT License.
```

- [ ] **Step 5: Capture a real Quick Ink product screenshot**

Build and launch the exact candidate:

```bash
Scripts/verify-v1.sh
DOC_BUILD_ROOT="$(mktemp -d)"
xcodebuild build -project MyShottr.xcodeproj -scheme MyShottr \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "${DOC_BUILD_ROOT}/DerivedData" \
  CODE_SIGNING_ALLOWED=NO
open "${DOC_BUILD_ROOT}/DerivedData/Build/Products/Release/MyShottr.app"
```

Use MyShottr to capture a neutral sample window, add one rectangle, arrow,
line, text label, and blur region, then export a PNG. Crop only empty desktop
outside the MyShottr editor window; do not alter the product UI. Save the final
image at `docs/images/editor-quick-ink.png`. Verify it is at least 1200 pixels
wide, contains no personal data, and reflects the same commit being documented.

- [ ] **Step 6: Write release and install verification documents**

Create `docs/releases/v0.1.0.md`:

```markdown
# MyShottr v0.1.0

The first public MyShottr release adds local macOS region capture, clean Chrome
viewport capture, editable Quick Ink annotations, PNG output, project files,
and crash recovery.

## Downloads

- `MyShottr-0.1.0-macos.zip` — unsigned and unnotarized macOS 15+ app
- `MyShottr-Chrome-0.1.0.zip` — unpacked Chrome extension
- `SHA256SUMS.txt` — SHA-256 checksums for both archives

## Important installation note

Move MyShottr to `/Applications` and open it once before loading the Chrome
extension. Because this build is unsigned and unnotarized, follow the
Gatekeeper instructions in the README.

## Known limitations

- Chrome captures only the visible viewport.
- The extension requires Developer mode.
- Full-page capture, desktop mockups, signing, notarization, and automatic
  updates are not included.
```

Create `docs/testing/release-installation.md` with fields for the tag, exact
commit, workflow URL, downloaded artifact sizes, SHA-256 result, app launch,
region capture, Chrome capture, project reopen, extension manifest permissions,
and Gatekeeper behavior. Each field has `PASS / FAIL` and an evidence line.

- [ ] **Step 7: Run documentation checks and commit**

Run:

```bash
node Tests/Release/documentation.test.mjs
Scripts/verify-v1.sh
git diff --check
```

Expected: all checks pass.

```bash
git add LICENSE README.md docs/images docs/releases \
  docs/testing/release-installation.md Tests/Release/documentation.test.mjs
git commit -m "docs: prepare MyShottr v0.1.0 release"
```

### Task 4: Create the Public Repository and Push the Tested Main Branch

**Files:**
- No source files change in this task.

**Interfaces:**
- Consumes: clean accepted local HEAD, authenticated GitHub CLI user
  `gihwan-dev`, and no existing `origin`.
- Produces: public `gihwan-dev/MyShottr`, remote `main`, pushed Git notes, and a
  successful main-branch CI run.

- [ ] **Step 1: Verify exact local preconditions**

Run:

```bash
test "$(git branch --show-current)" = "worktree/myshottr-v1"
test -z "$(git status --short)"
gh auth status
test -z "$(git remote)"
if gh repo view gihwan-dev/MyShottr >/dev/null 2>&1; then
  echo "gihwan-dev/MyShottr already exists; stop before changing it" >&2
  exit 1
fi
Scripts/verify-v1.sh
git notes --ref=myshottr-acceptance show HEAD
```

Expected: authenticated account is `gihwan-dev`, the repository does not
exist, the worktree is clean, automated verification passes, and the exact HEAD
has complete manual acceptance evidence.

- [ ] **Step 2: Create the public repository**

Run:

```bash
gh repo create gihwan-dev/MyShottr \
  --public \
  --description "Local-first macOS screenshot capture and Excalidraw-style annotation" \
  --source=. \
  --remote=origin
```

Expected: GitHub creates one empty public repository and configures
`origin`. Do not use `--push` in this command.

- [ ] **Step 3: Push the complete candidate as main**

Run:

```bash
git push -u origin HEAD:main
gh repo edit gihwan-dev/MyShottr --default-branch main
git push origin refs/notes/myshottr-acceptance
```

Expected: the remote default branch is `main`, points to the local tested HEAD,
and includes the acceptance note.

- [ ] **Step 4: Verify remote SHA and CI**

Run:

```bash
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
test "${LOCAL_SHA}" = "${REMOTE_SHA}"
RUN_ID="$(gh run list --repo gihwan-dev/MyShottr --branch main \
  --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "${RUN_ID}" --repo gihwan-dev/MyShottr --exit-status
gh run view "${RUN_ID}" --repo gihwan-dev/MyShottr \
  --json headSha,conclusion,url
```

Expected: `headSha` equals `LOCAL_SHA` and conclusion is `success`.

### Task 5: Publish and Verify the Live v0.1.0 Release

**Files:**
- No source files change in this task.

**Interfaces:**
- Consumes: green remote `main`, exact-SHA manual evidence, and the release
  workflow.
- Produces: annotated tag `v0.1.0`, live GitHub Release, downloadable verified
  app and extension archives, and completed install evidence.

- [ ] **Step 1: Create and push the exact release tag**

Run:

```bash
test -z "$(git status --short)"
test "$(git rev-parse HEAD)" = \
  "$(git ls-remote origin refs/heads/main | awk '{print $1}')"
git notes --ref=myshottr-acceptance show HEAD
git tag -a v0.1.0 -m "MyShottr v0.1.0"
git push origin v0.1.0
```

Expected: the tag points to the accepted main SHA.

- [ ] **Step 2: Wait for the release workflow**

Run:

```bash
RUN_ID="$(gh run list --repo gihwan-dev/MyShottr \
  --workflow Release --limit 1 --json databaseId,headBranch \
  --jq 'map(select(.headBranch == "v0.1.0"))[0].databaseId')"
gh run watch "${RUN_ID}" --repo gihwan-dev/MyShottr --exit-status
gh run view "${RUN_ID}" --repo gihwan-dev/MyShottr \
  --json headSha,conclusion,url
```

Expected: `headSha` equals `git rev-list -n 1 v0.1.0` and conclusion is
`success`.

- [ ] **Step 3: Download and verify published artifacts**

Run:

```bash
DOWNLOAD_ROOT="$(mktemp -d)"
gh release download v0.1.0 \
  --repo gihwan-dev/MyShottr \
  --dir "${DOWNLOAD_ROOT}"
Scripts/verify-release-artifacts.sh 0.1.0 "${DOWNLOAD_ROOT}"
gh release view v0.1.0 \
  --repo gihwan-dev/MyShottr \
  --json url,isDraft,isPrerelease,tagName,targetCommitish,assets
```

Expected: verification passes, the release is neither draft nor prerelease,
and the asset list contains exactly the three approved files.

- [ ] **Step 4: Perform install smoke tests from the downloaded files**

Extract both downloaded ZIPs into a new temporary directory. Verify:

1. the app reports version `0.1.0`;
2. the app icon appears in Finder and the Dock;
3. `spctl --assess` rejects the app as unsigned, matching documentation;
4. the documented Control-click or Privacy & Security flow opens the app;
5. first launch registers the host manifest with an absolute path into the
   downloaded app;
6. the extracted extension loads in Chrome Developer mode;
7. native region capture opens a Quick Ink editor;
8. Chrome viewport capture contains no browser UI;
9. Save Project, reopen, Copy Image, and Export PNG succeed.

Complete `docs/testing/release-installation.md` in a temporary copy and attach
it to the release commit:

```bash
RELEASE_SHA="$(git rev-list -n 1 v0.1.0)"
REPORT="/tmp/myshottr-v0.1.0-install-${RELEASE_SHA}.md"
cp docs/testing/release-installation.md "${REPORT}"
open -e "${REPORT}"
git notes --ref=myshottr-release-install add -F "${REPORT}" "${RELEASE_SHA}"
git push origin refs/notes/myshottr-release-install
```

Expected: all nine checks are PASS before the note is added.

- [ ] **Step 5: Verify deployment from GitHub**

Run:

```bash
RELEASE_SHA="$(git rev-list -n 1 v0.1.0)"
REMOTE_TAG_SHA="$(git ls-remote origin 'refs/tags/v0.1.0^{}' | awk '{print $1}')"
test "${RELEASE_SHA}" = "${REMOTE_TAG_SHA}"
git notes --ref=myshottr-release-install show "${RELEASE_SHA}"
gh release view v0.1.0 --repo gihwan-dev/MyShottr --web
```

Expected: the remote tag, accepted SHA, workflow result, downloaded artifacts,
and release-install note all identify the same commit.

## Completion Gate

Deployment is complete only when:

- the public repository is reachable at `https://github.com/gihwan-dev/MyShottr`;
- remote `main` equals the tested local commit;
- CI and Release workflows are green for that commit and tag;
- the MIT License and public README render correctly;
- `v0.1.0` contains exactly the app ZIP, extension ZIP, and checksum file;
- downloaded checksums and package validation pass;
- install smoke tests from the downloaded artifacts pass;
- Git notes contain both exact-SHA product acceptance and release-install
  evidence;
- `git status --short` is empty.

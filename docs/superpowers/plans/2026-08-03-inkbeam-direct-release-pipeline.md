# Inkbeam Direct Release Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Inkbeam RC and final releases on one local release Mac as universal, Developer ID signed, hardened, notarized, stapled DMGs with signed Sparkle feeds, locally published GitHub releases, immutable checksums, and resumable non-secret phase evidence.

**Architecture:** Replace the unsigned ZIP-era pipeline with one fail-closed `Scripts/release/inkbeam-release` command that resolves an immutable tag contract, verifies local Keychain authority, archives and signs inside-out, submits one notarization job, resumes by recorded submission ID, seals final bytes, publishes candidates locally with `gh`, and atomically publishes signed Pages feeds. GitHub Actions remains validation-only and receives no signing, notarization, Sparkle, or publication authority.

**Tech Stack:** zsh, Node 22, Xcode 26, XcodeGen, Swift Package Manager, Developer ID, Hardened Runtime, `codesign`, `hdiutil`, `notarytool`, `stapler`, `spctl`, Sparkle 2.9.4 tools, GitHub CLI, GitHub Pages, SHA-256

## Global Constraints

- Execute after the clean-cut and Sparkle updater plans pass. All names and paths below are Inkbeam-only.
- This plan creates tooling and tests. It does not publish RC/final artifacts; real publication belongs to `2026-08-03-inkbeam-v0.2.0-rollout.md`.
- The release Mac is the only official signing and publication authority. GitHub Actions may validate source and metadata only.
- Required local authority is exact: `INKBEAM_TEAM_ID`, `INKBEAM_SIGNING_IDENTITY`, Keychain notary profile `inkbeam-notary`, Sparkle Keychain account `inkbeam`, and authenticated local `gh` access to `gihwan-dev/inkbeam`.
- `INKBEAM_TEAM_ID` and `INKBEAM_SIGNING_IDENTITY` have no defaults. The notary profile and Sparkle account are fixed constants, not overrideable variables.
- Never export or log Developer ID, notary, Sparkle private, Apple, or GitHub credentials. `Config/SparklePublicEDKey.txt` and the Chrome manifest public key are public material.
- There is no unsigned, ad-hoc, `--deep` signing, skipped-notarization, alternate-asset, alternate-feed, lower-build, or credential-file mode. `--deep` is permitted only for verification after deterministic inside-out signing.
- Official DMGs contain exactly `Inkbeam.app` and a symlink to `/Applications`. Public assets contain no dSYM, notary log, credential export, build log, source map, test seam, or junk file.
- Final stapled DMG bytes are immutable. EdDSA enclosure signature, byte length, and SHA-256 are calculated only after stapling.
- A notarization submission ID is persisted before polling. Resume polls that ID; it never automatically submits a duplicate.
- Delta updates remain disabled with Sparkle `generate_appcast --maximum-deltas 0`. Release notes are embedded and no `releaseNotesLink` is emitted.
- Every external mutation command has a preceding read-only state assertion and a recorded expected transition. Failures stop without claiming the phase passed.
- Commit after every task. The implementation worktree must be clean before any release preflight.

---

## Stable CLI Contract Consumed by the Rollout Plan

```text
Scripts/release/inkbeam-release contract TAG
Scripts/release/inkbeam-release status TAG
Scripts/release/inkbeam-release preflight TAG EXPECTED_BRANCH EXPECTED_SHA
Scripts/release/inkbeam-release package TAG EXPECTED_BRANCH EXPECTED_SHA
Scripts/release/inkbeam-release resume-notarization TAG
Scripts/release/inkbeam-release publish-candidate TAG
Scripts/release/inkbeam-release verify-public TAG
Scripts/release/inkbeam-release prepare-feed TAG beta|stable
Scripts/release/inkbeam-release publish-feed TAG beta|stable
Scripts/release/inkbeam-release withdraw-candidate TAG
Scripts/release/inkbeam-release record-acceptance TAG PATH
Scripts/release/inkbeam-release promote-final
Scripts/release/inkbeam-release rollback-final
Scripts/release/inkbeam-release deprecate-v0.1.0
Scripts/release/inkbeam-release complete TAG
```

State lives only at `build/release-evidence/TAG/release-state.json`. Commands accept only the exact tag contract, consume verified output from prior phases, and refuse to skip phases.

## Release Contract

| Tag | Short version | Build | Channel | DMG | Chrome ZIP | Candidate title |
| --- | --- | --- | --- | --- | --- | --- |
| `v0.2.0-rc.1` | `0.2.0` | `2` | `beta` | `Inkbeam-0.2.0-rc.1.dmg` | `Inkbeam-Chrome-0.2.0-rc.1.zip` | `Inkbeam v0.2.0-rc.1` |
| `v0.2.0-rc.2` | `0.2.0` | `3` | `beta` | `Inkbeam-0.2.0-rc.2.dmg` | `Inkbeam-Chrome-0.2.0-rc.2.zip` | `Inkbeam v0.2.0-rc.2` |
| `v0.2.0` | `0.2.0` | `4` | `stable` | `Inkbeam-0.2.0.dmg` | `Inkbeam-Chrome-0.2.0.zip` | `Inkbeam v0.2.0 (Final Candidate)` |

### Task 1: Encode Immutable Tag and Phase-State Contracts

**Files:**
- Create: `Scripts/release/release-contract.mjs`
- Create: `Scripts/release/release-state.mjs`
- Create: `Scripts/release/inkbeam-release`
- Create: `Tests/Release/release-contract.test.mjs`
- Create: `Tests/Release/release-state.test.mjs`
- Modify: `.gitignore`, `package.json`

- [ ] **Step 1: Write failing contract tests**

```js
import assert from "node:assert/strict";
import test from "node:test";
import { contractFor } from "../../Scripts/release/release-contract.mjs";

test("maps every approved tag exactly", () => {
  assert.deepEqual(contractFor("v0.2.0-rc.1"), {
    tag: "v0.2.0-rc.1",
    version: "0.2.0",
    build: 2,
    channel: "beta",
    dmg: "Inkbeam-0.2.0-rc.1.dmg",
    chromeZip: "Inkbeam-Chrome-0.2.0-rc.1.zip",
    releaseTitle: "Inkbeam v0.2.0-rc.1",
    prerelease: true,
  });
  assert.equal(contractFor("v0.2.0").build, 4);
  assert.throws(() => contractFor("v0.2.1"), /unsupported release tag/);
});
```

State tests must reject unknown keys, phase skips, a second notarization ID, secrets, and a tag/contract mismatch.

- [ ] **Step 2: Run RED**

```bash
node --test Tests/Release/release-contract.test.mjs Tests/Release/release-state.test.mjs
```

Expected: FAIL because the modules do not exist.

- [ ] **Step 3: Implement the exact release map**

```js
const contracts = new Map([
  ["v0.2.0-rc.1", { version: "0.2.0", build: 2, channel: "beta",
    dmg: "Inkbeam-0.2.0-rc.1.dmg", chromeZip: "Inkbeam-Chrome-0.2.0-rc.1.zip",
    releaseTitle: "Inkbeam v0.2.0-rc.1", prerelease: true }],
  ["v0.2.0-rc.2", { version: "0.2.0", build: 3, channel: "beta",
    dmg: "Inkbeam-0.2.0-rc.2.dmg", chromeZip: "Inkbeam-Chrome-0.2.0-rc.2.zip",
    releaseTitle: "Inkbeam v0.2.0-rc.2", prerelease: true }],
  ["v0.2.0", { version: "0.2.0", build: 4, channel: "stable",
    dmg: "Inkbeam-0.2.0.dmg", chromeZip: "Inkbeam-Chrome-0.2.0.zip",
    releaseTitle: "Inkbeam v0.2.0 (Final Candidate)", prerelease: true }],
]);

export function contractFor(tag) {
  const contract = contracts.get(tag);
  if (!contract) throw new Error(`unsupported release tag: ${tag}`);
  return Object.freeze({ tag, ...contract });
}
```

The state schema permits only identity, non-secret phase timestamps, exact SHA/branch, notarization ID/status, final artifact metadata, public URLs, GitHub state, Pages commit IDs, and acceptance path/result.

- [ ] **Step 4: Implement the dispatcher with exact verbs**

`Scripts/release/inkbeam-release` validates argument count, resolves the repository root, and dispatches to one script/module per verb. Unknown verbs exit 64. It never interprets arbitrary shell from state or arguments.

- [ ] **Step 5: Ignore only generated release evidence and add tests to the gate**

Add `/build/release-evidence/`, `/build/release-cache/`,
`/build/release-feeds/`, `/build/release-clone/`, and `/dist/release/` to
`.gitignore`. The exact release-clone path is reserved for the persistent clean
`main` checkout used by the rollout plan. Do not ignore `Config`,
`docs/testing/releases`, or appcast fixtures. Add both tests to
`pnpm test:release`.

- [ ] **Step 6: Run GREEN and commit**

```bash
node --test Tests/Release/release-contract.test.mjs Tests/Release/release-state.test.mjs
Scripts/release/inkbeam-release contract v0.2.0-rc.1
git add Scripts/release Tests/Release package.json .gitignore
git commit -m "build(release): define immutable Inkbeam release phases"
```

### Task 2: Implement Credential, Version, and Public-Key Preflight

**Files:**
- Create: `Scripts/release/preflight.sh`
- Create: `Tests/Release/preflight.test.sh`
- Modify: `project.yml`, `Config/Inkbeam-Info.plist`, `Packages/chrome-extension/vite.config.ts`

- [ ] **Step 1: Write failing preflight fixture tests**

Test missing Team ID, missing exact identity, wrong notary profile, missing Sparkle account, public-key mismatch, dirty worktree, wrong branch/SHA, wrong repo remote, wrong tag contract, wrong Chrome version/name, and Sparkle version drift. Each case must fail before `xcodebuild`, `notarytool submit`, `gh release`, or Git push is invoked.

- [ ] **Step 2: Make version/build/channel values build settings**

Set the app metadata to:

```yaml
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        InkbeamReleaseChannel: $(INKBEAM_RELEASE_CHANNEL_NAME)
```

The release packager passes all three from `release-contract.mjs`. Chrome `manifest.version` remains `0.2.0`; its build copies `version_name` as `0.2.0-rc.1`, `0.2.0-rc.2`, or `0.2.0` from the contract.

- [ ] **Step 3: Require exact local trust inputs without reading secrets**

The preflight begins:

```bash
: "${INKBEAM_TEAM_ID:?INKBEAM_TEAM_ID is required}"
: "${INKBEAM_SIGNING_IDENTITY:?INKBEAM_SIGNING_IDENTITY is required}"
[[ "${INKBEAM_TEAM_ID}" =~ '^[A-Z0-9]{10}$' ]]
security find-identity -v -p codesigning | grep -F -- "${INKBEAM_SIGNING_IDENTITY}"
xcrun notarytool history --keychain-profile inkbeam-notary --output-format json >/dev/null
security find-generic-password \
  -s 'https://sparkle-project.org' -a inkbeam >/dev/null
gh auth status --hostname github.com
test "$(git remote get-url origin)" = 'https://github.com/gihwan-dev/inkbeam.git'
```

Use a fixed DerivedData path to find the pinned Sparkle 2.9.4 tools. First
require the read-only `security find-generic-password` probe for account
`inkbeam` to succeed. If it is absent, stop preflight and never invoke
`generate_keys`. Only after that existing-account proof, run
`generate_keys --account inkbeam` to print the corresponding public key,
extract only the public base64 line, and compare it byte-for-byte with
`Config/SparklePublicEDKey.txt`. Never call `security ... -w`,
`generate_keys -x`, or any key-creation path from preflight.

- [ ] **Step 4: Enforce repository and version provenance**

Require `git status --porcelain` empty, exact branch argument, exact SHA argument, local HEAD equal expected SHA, tag absent before packaging, locked dependencies, Node 22, pnpm 10.14, Xcode 26, XcodeGen present, Sparkle exact 2.9.4, and contract values in generated app/Chrome metadata.

The currently observed release Mac has zero valid code-signing identities; therefore the real preflight must remain RED until the Developer ID Application certificate and private key are installed. Do not weaken the test or add an unsigned mode.

- [ ] **Step 5: Run synthetic GREEN and real expected blocker**

```bash
zsh Tests/Release/preflight.test.sh
Scripts/release/inkbeam-release preflight \
  v0.2.0-rc.1 worktree/myshottr-v1 "$(git rev-parse HEAD)"
```

Expected now: synthetic fixture tests PASS; real preflight exits before build with the exact missing Developer ID identity until operator setup is complete.

- [ ] **Step 6: Commit**

```bash
git add Scripts/release Tests/Release project.yml Config Packages/chrome-extension
git commit -m "build(release): fail closed on local release authority"
```

### Task 3: Archive, Sign Inside-Out, Create DMG, and Resume Notarization

**Files:**
- Create: `Scripts/release/package.sh`
- Create: `Scripts/release/resume-notarization.sh`
- Create: `Tests/Release/package-release.test.sh` replacing unsigned ZIP assertions
- Modify: `Config/Inkbeam.entitlements`, `project.yml`

- [ ] **Step 1: Replace the unsigned packaging contract with failing official-release assertions**

Require universal app/helper, hardened runtime, secure timestamps, no `get-task-allow`, exact bundle IDs, a DMG with two root entries, and a persisted notarization ID. Reject `CODE_SIGNING_ALLOWED=NO`, ad-hoc signatures, `.app.zip`, and Gatekeeper-bypass wording.

- [ ] **Step 2: Configure manual Developer ID archive settings**

Set `ENABLE_HARDENED_RUNTIME: YES`, `CODE_SIGN_STYLE: Manual` for Release, and keep `Config/Inkbeam.entitlements` minimal. Do not add app sandbox, network client, app groups, or `get-task-allow` unless a separately approved requirement exists.

- [ ] **Step 3: Build one exact archive**

`package.sh` runs the full preflight, then:

Before invoking Xcode, map contract channel `beta` to the literal
`Release Candidate` and `stable` to `Stable`; reject every other value. Pass
that result as `CHANNEL_NAME` below.

```bash
INKBEAM_RELEASE_CHANNEL="${CHANNEL}" Scripts/generate-project.sh
xcodebuild archive \
  -project Inkbeam.xcodeproj -scheme Inkbeam -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD}" \
  INKBEAM_RELEASE_CHANNEL_NAME="${CHANNEL_NAME}" \
  DEVELOPMENT_TEAM="${INKBEAM_TEAM_ID}" \
  CODE_SIGN_IDENTITY="${INKBEAM_SIGNING_IDENTITY}" \
  CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS='--timestamp' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO
```

Xcode signs embedded Sparkle services/frameworks and helper before the outer app. Immediately verify each nested executable and the outer app from the inside out.

- [ ] **Step 4: Build and sign the exact DMG**

Stage only `Inkbeam.app` and an `/Applications` symlink, then:

```bash
hdiutil create -volname Inkbeam -srcfolder "${DMG_ROOT}" \
  -ov -format UDZO "${DMG_PATH}"
codesign --force --timestamp \
  --sign "${INKBEAM_SIGNING_IDENTITY}" "${DMG_PATH}"
```

Build the Chrome ZIP separately from the production extension `dist`, with its root directory named from the release contract. Do not put Chrome files inside the DMG.

- [ ] **Step 5: Submit exactly once and persist the ID**

```bash
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile inkbeam-notary \
  --output-format json > "${SUBMISSION_RESULT}"
```

Parse a non-empty submission ID, atomically store it in `release-state.json`, and return. If the state already contains an ID, refuse a second submission and instruct the operator to use `resume-notarization`.

- [ ] **Step 6: Resume, inspect, staple, and assess**

`resume-notarization.sh` reads only the recorded ID, polls:

```bash
xcrun notarytool info "${SUBMISSION_ID}" \
  --keychain-profile inkbeam-notary --output-format json
```

It records terminal status, requires `Accepted`, saves the full notary log privately under the ignored evidence directory, then runs:

```bash
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"
codesign --verify --deep --strict --verbose=4 "${APP_PATH}"
spctl --assess --type execute --verbose=4 "${APP_PATH}"
spctl --assess --type open --context context:primary-signature \
  --verbose=4 "${DMG_PATH}"
```

Any non-Accepted result stops before stapling and publication.

- [ ] **Step 7: Run fixture tests and commit**

```bash
zsh Tests/Release/package-release.test.sh
git add Scripts/release Tests/Release project.yml Config/Inkbeam.entitlements
git commit -m "build(release): package notarized Developer ID DMG"
```

### Task 4: Verify and Seal Final Artifact Bytes

**Files:**
- Create: `Scripts/release/verify-artifacts.sh`
- Create: `Scripts/release/seal-artifacts.mjs`
- Modify: packaging tests

- [ ] **Step 1: Add mutation-based artifact tests**

Starting from synthetic fixtures, make each mutation fail: wrong Team ID, missing timestamp/runtime, debug entitlement, one missing architecture, extra DMG root file, wrong helper path, altered Chrome key/permissions, secret-like file, source map, invalid staple response, Gatekeeper rejection, wrong `SUPublicEDKey`, and checksum mismatch.

- [ ] **Step 2: Verify nested code and exact identities**

Mount the DMG read-only, require exactly `Inkbeam.app` plus `Applications -> /Applications`, and verify:

```text
app ID: dev.gihwan.inkbeam
helper ID: dev.gihwan.inkbeam.nativehost
app/helper architectures: arm64 x86_64
short version/build/channel: release contract
SUPublicEDKey: committed public key
SUFeedURL: exact beta or stable URL
TeamIdentifier: INKBEAM_TEAM_ID
runtime/timestamp: present
get-task-allow: absent
```

Extract printable strings and text metadata from the mounted app, helper,
Chrome ZIP, DMG file list, and generated appcast, and apply the same banned-token
set as `Scripts/verify-clean-cutover.mjs`. No artifact-level exception is
allowed: `MyShottr`, `.myshottr`, `com.myshottr`, `MyShottrNativeHost`,
`myshottr-editor`, `QuickInk`, and `Quick Ink` must all be absent.

- [ ] **Step 3: Seal only after staple validation**

Run Sparkle's pinned `sign_update --account inkbeam DMG`, obtain EdDSA signature and length, compute `shasum -a 256`, and write `SHA256SUMS.txt` for the DMG and Chrome ZIP. Store signature, byte length, SHA-256, and verification summaries in state. A later byte/size/hash change invalidates the phase and blocks publication.

- [ ] **Step 4: Run tests and commit**

```bash
zsh Tests/Release/package-release.test.sh
node --test Tests/Release/release-state.test.mjs
git add Scripts/release Tests/Release
git commit -m "test(release): verify and seal final artifact bytes"
```

### Task 5: Generate Signed Embedded-Notes Beta and Stable Feeds

**Files:**
- Create: `Scripts/release/prepare-feed.sh`
- Create: `Scripts/release/compose-feed.mjs`
- Create: `Scripts/release/verify-feed.mjs`
- Create: `Tests/Release/feed.test.mjs`
- Create: `docs/releases/v0.2.0-rc.1.md`, `v0.2.0-rc.2.md`, `v0.2.0.md`

- [ ] **Step 1: Write failing feed-shape and mutation tests**

Assert beta order build 4, 3, 2 as available; stable contains only final builds; every enclosure is HTTPS and points to the exact GitHub release asset; every item has short version `0.2.0`, increasing numerical build, exact length/EdDSA signature, embedded notes, and no `releaseNotesLink` or delta.

Mutate one feed byte, embedded-note byte, enclosure signature, build number, and URL. Each validation must fail before metadata is presented or an archive download starts in the integration harness.

Add a withdrawn-candidate fixture where a previously public RC remains on GitHub but is marked withdrawn. The beta feed must exclude its item entirely.

- [ ] **Step 2: Generate one signed item per tag from verified cached DMGs**

For each verified public stage, place its exact DMG and same-basename Markdown notes in an isolated directory and run the pinned tool:

```bash
generate_appcast --account inkbeam --maximum-deltas 0 \
  --maximum-versions 0 --embed-release-notes \
  --download-url-prefix "https://github.com/gihwan-dev/inkbeam/releases/download/${TAG}/" \
  --output-path "${ITEM_FEED}" "${ITEM_DIRECTORY}"
```

Do not supply `--ed-key-file`, `-s`, or an external release-notes prefix.

- [ ] **Step 3: Compose the channel feed and sign it last**

`compose-feed.mjs` copies verified `<item>` nodes only, sorts by numerical build descending, excludes any release state marked `withdrawn`, applies the channel membership rules, and writes deterministic XML. Then:

```bash
sign_update --account inkbeam "${COMPOSED_FEED}"
sign_update --verify --account inkbeam "${COMPOSED_FEED}"
```

No byte may change after the final sign command.

- [ ] **Step 4: Run GREEN and commit**

```bash
node --test Tests/Release/feed.test.mjs
pnpm test:release
git add Scripts/release Tests/Release docs/releases
git commit -m "build(update): generate signed Inkbeam appcasts"
```

### Task 6: Add Local GitHub and GitHub Pages Publication State Machines

**Files:**
- Create: `Scripts/release/publish-github.sh`
- Create: `Scripts/release/verify-public.sh`
- Create: `Scripts/release/publish-feed.sh`
- Create: `Scripts/release/withdraw-candidate.sh`
- Create: `Scripts/release/promote-final.sh`
- Create: `Scripts/release/rollback-final.sh`
- Create: `Scripts/release/deprecate-v0.1.0.sh`
- Create: `Tests/Release/publication.test.mjs`

- [ ] **Step 1: Test every allowed external transition against fake CLIs**

Freeze the exact transitions: RC candidate and final candidate are published/non-draft/prerelease/not-latest; a withdrawn RC remains non-draft/prerelease/not-latest with title prefix `Withdrawn —` and is removed from the newly signed beta feed; final promotion edits the same release to non-prerelease/latest; rollback restores prerelease/not-latest/final-candidate title; first Pages publication creates the one approved `gh-pages` root and later publications require it; feed publication records the previous `gh-pages` SHA and can revert it; v0.1.0 becomes deprecated prerelease/not-latest without replacing assets. Add a negative fake-CLI case proving `publish-feed TAG stable` refuses a draft, prerelease, or non-latest GitHub release, while `prepare-feed TAG stable` remains valid before promotion.

- [ ] **Step 2: Publish candidate assets only after the seal**

Read `gh release view TAG --json` first and require absence. Push the exact tag pointing to the recorded SHA, then call `gh release create` with exactly DMG, Chrome ZIP, and checksum file plus rendered notes, `--prerelease`, and `--verify-tag`. Final uses title `Inkbeam v0.2.0 (Final Candidate)`.

- [ ] **Step 3: Re-download and verify public bytes**

Use `gh release download TAG --dir build/release-cache/TAG`, compare SHA-256 to the sealed local state, then rerun signature, staple, Gatekeeper, public-key, architecture, DMG contents, and Chrome identity checks. Only this command marks `publicVerified`.

- [ ] **Step 4: Publish feeds atomically from local authority**

First query `refs/heads/gh-pages` and the repository Pages configuration. If
the branch already exists, fetch it, record its exact SHA, create an isolated
temporary worktree, and replace only `appcast-beta.xml` or `appcast.xml` with
the already signed feed. If it is absent during the first RC1 beta publication,
require Pages to be absent too, create one orphan branch containing only
`.nojekyll` and the signed `appcast-beta.xml`, push it, and configure GitHub
Pages to serve the root of `gh-pages` through the GitHub API. Every later
absence or configuration mismatch is an error, not an alternate hosting path.
Commit and push `HEAD:gh-pages`, fetch the public URL, and byte-compare it with
the signed local feed. Before any stable push, query the referenced GitHub
release and require `draft=false`, `prerelease=false`, and `make_latest=true`;
the final-candidate state must fail before `gh-pages` is mutated. Do not publish
via Actions.

- [ ] **Step 5: Implement final promotion and rollback**

Promotion requires final public verification, beta-feed final item, recorded RC2-to-final acceptance, and locally verified stable feed. It calls `gh release edit v0.2.0 --prerelease=false --latest --title 'Inkbeam v0.2.0'` and verifies state.

`withdraw-candidate` first requires a public RC tag, a release-critical failure record, and a newly prepared beta feed without that RC item. It publishes the updated beta feed, verifies the public beta bytes, then runs:

```bash
gh release edit "${TAG}" \
  --title "Withdrawn — Inkbeam ${TAG}" \
  --notes-file "${WITHDRAWN_NOTES}"
```

It keeps the release non-draft/prerelease/not-latest, adds the required withdrawal banner and reason, and never deletes or replaces the original assets.

If stable publication or verification then fails, `rollback-final` first restores the recorded previous stable feed commit on `gh-pages`, verifies the previous public bytes, then runs:

```bash
gh release edit v0.2.0 \
  --prerelease --latest=false \
  --title 'Inkbeam v0.2.0 (Final Candidate)'
```

It verifies the rollback and records failure. It does not announce stable.

- [ ] **Step 6: Preserve and deprecate the historical v0.1.0 release**

Read and record the existing tag, asset names/IDs/checksums, and body before any
edit. Create a notes file whose first paragraph says the release is an unsigned,
pre-Inkbeam prototype, then appends the existing body unchanged. Run:

```bash
gh release edit v0.1.0 --repo gihwan-dev/inkbeam \
  --prerelease --latest=false \
  --title 'Deprecated — pre-Inkbeam prototype' \
  --notes-file "${DEPRECATED_NOTES}"
```

Verify `draft=false`, `prerelease=true`, `make_latest=false`, the title prefix,
body banner, and byte-identical tag/assets. Refuse to delete, upload, or replace
anything, and assert neither updater feed contains v0.1.0.

- [ ] **Step 7: Run fake-CLI tests and commit**

```bash
node --test Tests/Release/publication.test.mjs
git add Scripts/release Tests/Release
git commit -m "build(release): orchestrate local publication and rollback"
```

### Task 7: Make CI Validation-Only and Document the Operator Boundary

**Files:**
- Delete: `.github/workflows/release.yml`
- Modify: `.github/workflows/ci.yml`
- Modify: `Scripts/validate-release-evidence.mjs`
- Modify: `Tests/Release/evidence-validator.test.mjs`, `workflows.test.mjs`, `documentation.test.mjs`
- Create: `docs/releasing/v0.2.0-direct-release.md`
- Modify: `README.md`, `package.json`

- [ ] **Step 1: Replace v0.1 evidence validation with staged Inkbeam validation**

Add the exact CLI mode:

```text
node Scripts/validate-release-evidence.mjs staged-release REPORT_PATH EXPECTED_SHA TAG SHA256SUMS_PATH candidate|complete
```

It resolves the immutable tag contract and validates every field and required
environment/gate from sections 15, 15.1, 16, and 18 of the approved design.
For RC tags, `candidate` already requires every RC gate PASS. For final,
`candidate` permits `NOT RUN` only for the GitHub-promotion and public-stable-
feed rows that cannot exist before promotion; every runtime, clean-install,
RC2-to-final, artifact, beta-feed, and environment row must already PASS.
`complete` requires those remaining rows PASS too. FAIL or any other NOT RUN
blocks acceptance. Test malformed SHAs, wrong tag/build/channel, checksum
mismatch, missing environment, forged PASS without evidence, and every allowed
versus disallowed final-candidate pending row.

`record-acceptance` runs `candidate`; `complete` runs `complete` against the
same path again. This makes the provisional final gate explicit without
misreporting the official release as complete.

- [ ] **Step 2: Rewrite workflow tests**

Require no workflow contains `gh release`, `notarytool`, `stapler`, `codesign --sign`, `generate_appcast`, `sign_update`, Pages push, release secrets, signing identities, certificates, or artifact publication. Require pinned audited actions, read-only permissions, locked installs, product tests, clean-cut scan, release metadata tests, and unsigned non-published test builds only.

- [ ] **Step 3: Delete tag-triggered publication and keep one blocking CI job**

Remove `.github/workflows/release.yml`. Keep `.github/workflows/ci.yml` on main, pull requests, and manual dispatch with `contents: read`. It may build a test product but must not upload or publish it.

- [ ] **Step 4: Write the release-Mac runbook**

Document exact environment variable names, fixed Keychain profiles/accounts, read-only preflight commands, the stable CLI contract, private/public evidence boundaries, notarization resume behavior, RC/final phase order, feed rollback, and the fact that current real preflight is blocked until a valid Developer ID identity exists.

Also encode the post-stable incident policy: Inkbeam never automatically
downgrades. If a bad stable item has already reached the signed feed, publish a
newly signed feed without that item to stop new installs, document impact on the
unchanged GitHub release, ship the correction only as `v0.2.1` with a higher
build through the normal pipeline, and provide official-GitHub manual recovery
instructions only if the affected app cannot launch. Never replace the
`v0.2.0` asset in place. Add documentation contract assertions for every clause.

- [ ] **Step 5: Run the complete pipeline test gate**

```bash
pnpm install --frozen-lockfile
pnpm test:release
node Scripts/verify-clean-cutover.mjs
Scripts/verify-privacy.sh
Scripts/generate-project.sh
xcodebuild test -project Inkbeam.xcodeproj -scheme Inkbeam -destination 'platform=macOS'
xcodebuild test -project Inkbeam.xcodeproj -scheme InkbeamNativeHost -destination 'platform=macOS'
git diff --check
```

Expected: all source/fixture tests pass. Real `preflight` may still report the explicit certificate operator blocker; that is not converted to a pass.

- [ ] **Step 6: Commit**

```bash
git add .github Tests/Release docs/releasing README.md package.json Scripts project.yml Config
git commit -m "ci(release): keep official publication on the release Mac"
```

## Completion Gate

- One tested CLI implements the exact contract consumed by the staged rollout plan.
- All three tags map to exact versions, builds, channels, titles, and assets.
- Local preflight is fail-closed on exact identity, Team ID, notary profile, Sparkle account/public key, repo, branch, SHA, and clean state.
- Universal app/helper code is hardened, securely timestamped, signed inside-out, notarized once, stapled, Gatekeeper accepted, and sealed after stapling.
- DMG and Chrome ZIP have immutable SHA-256; the DMG contains exactly app plus Applications symlink.
- Signed feeds have embedded notes, no external notes link, no delta, exact HTTPS URLs, and strict beta/stable membership.
- GitHub candidate/public verification, Pages publication, final promotion, and rollback are state-tested.
- GitHub Actions has no official release, credential, signing, notarization, feed-signing, or publication path.
- No real publication has been claimed by completing this tooling plan.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const CI_PATH = ".github/workflows/ci.yml";
const RELEASE_PATH = ".github/workflows/release.yml";

const AUDITED_ACTIONS = Object.freeze({
  "actions/checkout": Object.freeze({
    sha: "3d3c42e5aac5ba805825da76410c181273ba90b1",
    tag: "v7.0.1",
  }),
  "actions/setup-node": Object.freeze({
    sha: "820762786026740c76f36085b0efc47a31fe5020",
    tag: "v7.0.0",
  }),
  "pnpm/action-setup": Object.freeze({
    sha: "0ebf47130e4866e96fce0953f49152a61190b271",
    tag: "v6.0.9",
  }),
});

const XCODE_REQUIREMENT_RUN = `set -euo pipefail
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2 }')"
XCODE_MAJOR="\${XCODE_VERSION%%.*}"
[[ "\${XCODE_MAJOR}" == <-> ]]
(( XCODE_MAJOR >= 26 ))
`;

const RELEASE_VALIDATION_RUN = `set -euo pipefail
[[ "\${TAG}" =~ ^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$ ]]
VERSION="\${TAG#v}"
[[ -f "docs/releases/\${TAG}.md" ]]
git fetch --no-tags --prune origin \\
  "+refs/heads/main:refs/remotes/origin/main" \\
  "+refs/notes/myshottr-acceptance:refs/notes/myshottr-acceptance"
TAG_COMMIT="$(git rev-parse --verify "\${TAG}^{commit}")"
[[ "\${TAG_COMMIT}" == "\${EXPECTED_SHA}" ]]
MAIN_COMMIT="$(git rev-parse --verify "origin/main^{commit}")"
[[ "\${MAIN_COMMIT}" == "\${EXPECTED_SHA}" ]]
git notes --ref=myshottr-acceptance show "\${EXPECTED_SHA}" >/dev/null
printf 'version=%s\\n' "\${VERSION}" >> "\${GITHUB_OUTPUT}"
`;

const RELEASE_CHECKSUM_LOCK_RUN = `set -euo pipefail
[[ "\${TAG}" =~ ^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$ ]]
[[ "\${VERSION}" == "\${TAG#v}" ]]
node --input-type=module - \\
  "dist/release/\${VERSION}/SHA256SUMS.txt" \\
  "docs/releases/\${TAG}.md" \\
  "MyShottr-\${VERSION}-macos.zip" \\
  "MyShottr-Chrome-\${VERSION}.zip" <<'NODE'
import { readFileSync } from "node:fs";

const [checksumPath, notesPath, appName, extensionName] = process.argv.slice(2);
const expectedNames = [appName, extensionName];
const checksumLinePattern = /^([0-9a-f]{64})  ([A-Za-z0-9.-]+)$/;

function fail(message) {
  process.stderr.write("release-checksums: " + message + "\\n");
  process.exit(1);
}

function parseExactEntries(content, label) {
  const normalized = content.endsWith("\\n") ? content.slice(0, -1) : content;
  const lines = normalized.split("\\n");
  if (lines.length !== expectedNames.length) {
    fail(label + " must contain exactly two checksum entries");
  }
  return lines.map((line, index) => {
    const match = line.match(checksumLinePattern);
    if (!match || match[2] !== expectedNames[index]) {
      fail(label + " contains an unexpected checksum entry");
    }
    return line;
  });
}

if (
  !checksumPath ||
  !notesPath ||
  expectedNames.length !== 2 ||
  expectedNames.some((name) => !name)
) {
  fail("expected checksum path, release notes path, and two artifact names");
}

const checksumLines = parseExactEntries(
  readFileSync(checksumPath, "utf8"),
  "SHA256SUMS.txt",
);
const notes = readFileSync(notesPath, "utf8");
const checksumSections = [
  ...notes.matchAll(
    /^## SHA-256 checksums\\n\\n\`\`\`text\\n([\\s\\S]*?)\\n\`\`\`$/gm,
  ),
];
if (checksumSections.length !== 1) {
  fail("release notes must contain exactly one SHA-256 checksum section");
}
const notesLines = parseExactEntries(
  checksumSections[0][1],
  "release notes checksum section",
);
const allNotesChecksumLines = notes
  .split("\\n")
  .filter((line) => /^[0-9A-Fa-f]{64}  /.test(line));
if (JSON.stringify(allNotesChecksumLines) !== JSON.stringify(notesLines)) {
  fail("release notes contain an extra checksum entry");
}
if (JSON.stringify(notesLines) !== JSON.stringify(checksumLines)) {
  fail("release notes checksums do not match SHA256SUMS.txt");
}
NODE
`;

const RELEASE_PUBLISH_RUN = `set -euo pipefail
[[ "\${TAG}" =~ ^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$ ]]
[[ "\${VERSION}" == "\${TAG#v}" ]]
OUTPUT="dist/release/\${VERSION}"
test -f "\${OUTPUT}/MyShottr-\${VERSION}-macos.zip"
test -f "\${OUTPUT}/MyShottr-Chrome-\${VERSION}.zip"
test -f "\${OUTPUT}/SHA256SUMS.txt"
gh release create "\${TAG}" \\
  "\${OUTPUT}/MyShottr-\${VERSION}-macos.zip" \\
  "\${OUTPUT}/MyShottr-Chrome-\${VERSION}.zip" \\
  "\${OUTPUT}/SHA256SUMS.txt" \\
  --repo "\${REPOSITORY}" \\
  --title "MyShottr \${TAG}" \\
  --notes-file "docs/releases/\${TAG}.md" \\
  --verify-tag
`;

const YAML_PARSER = String.raw`
require "json"
require "yaml"

document = YAML.safe_load(
  STDIN.read,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
STDOUT.write(JSON.generate(document))
`;

function parseYaml(source, label) {
  const result = spawnSync("/usr/bin/ruby", ["-e", YAML_PARSER], {
    input: source,
    encoding: "utf8",
  });
  assert.equal(
    result.status,
    0,
    `could not parse ${label} as YAML:\n${result.stderr}`,
  );
  return JSON.parse(result.stdout);
}

function assertExactKeys(object, keys, label) {
  assert.deepEqual(Object.keys(object).sort(), [...keys].sort(), label);
}

function pinnedUses(action) {
  return `${action}@${AUDITED_ACTIONS[action].sha}`;
}

function actionStep(name, action, inputs) {
  return {
    name,
    uses: pinnedUses(action),
    with: inputs,
  };
}

function assertAuditedActionComments(source) {
  for (const [action, audit] of Object.entries(AUDITED_ACTIONS)) {
    const escapedAction = action.replaceAll("/", String.raw`\/`);
    assert.match(
      source,
      new RegExp(
        String.raw`uses:\s*${escapedAction}@${audit.sha}\s+#\s+${audit.tag}(?:\s|$)`,
      ),
      `${action} must use the audited SHA and exact upstream tag comment`,
    );
  }
}

function assertNoProhibitedWorkflowSurface(ciSource, releaseSource) {
  const combined = `${ciSource}\n${releaseSource}`;

  assert.doesNotMatch(combined, /pull_request_target/);
  assert.doesNotMatch(combined, /\$\{\{\s*secrets\./);
  assert.doesNotMatch(combined, /persist-credentials:\s*true/i);
  assert.doesNotMatch(combined, /actions\/upload-artifact/i);
  assert.doesNotMatch(
    combined,
    /\b(?:curl|wget|scp|rsync|ftp|aws|gcloud|az)\b/i,
    "workflows must not contain an external publication path",
  );
  assert.doesNotMatch(
    combined,
    /APPLE_|NOTARY|SIGNING|CERTIFICATE/i,
    "workflows must not contain distribution credentials or operations",
  );

  const actionUses = [...combined.matchAll(/\buses:\s*([^\s#]+)/g)].map(
    (match) => match[1],
  );
  assert.ok(actionUses.length > 0, "workflows must contain audited setup actions");
  for (const uses of actionUses) {
    const separator = uses.lastIndexOf("@");
    assert.notEqual(separator, -1, `action is missing a ref: ${uses}`);
    const action = uses.slice(0, separator);
    const ref = uses.slice(separator + 1);
    assert.ok(
      Object.hasOwn(AUDITED_ACTIONS, action),
      `workflow uses unapproved action ${action}`,
    );
    assert.equal(ref, AUDITED_ACTIONS[action].sha, `${action} pin changed`);
  }
}

function assertReleaseCommandSurface(releaseSource, publishRun) {
  const allReleaseInvocations = [
    ...releaseSource.matchAll(/\bgh\s+release\s+([a-z-]+)/g),
  ];
  assert.deepEqual(
    allReleaseInvocations.map((match) => match[1]),
    ["create"],
    "the workflow must contain exactly one gh release invocation and it must create",
  );
  assert.doesNotMatch(
    releaseSource,
    /\bgh\s+release\s+(?:upload|edit|delete)\b/,
  );

  const createCommand = publishRun.match(
    /gh release create "\$\{TAG\}"[\s\S]*?\s+--repo /,
  )?.[0];
  assert.ok(createCommand, "could not isolate the GitHub release command");
  const createCommandLines = createCommand
    .split("\n")
    .map((line) => line.trim().replace(/\s*\\$/, ""))
    .filter(Boolean);
  assert.deepEqual(createCommandLines, [
    'gh release create "${TAG}"',
    '"${OUTPUT}/MyShottr-${VERSION}-macos.zip"',
    '"${OUTPUT}/MyShottr-Chrome-${VERSION}.zip"',
    '"${OUTPUT}/SHA256SUMS.txt"',
    "--repo",
  ]);
  assert.doesNotMatch(publishRun, /(?:\*|\?|\[[^\]]+\])\.zip/);
}

function validateCI(ciSource) {
  const ci = parseYaml(ciSource, "CI workflow");

  assertExactKeys(ci, ["name", "on", "permissions", "jobs"], "CI schema changed");
  assert.equal(ci.name, "CI");
  assert.deepEqual(ci.on, {
    push: { branches: ["main"] },
    pull_request: {},
    workflow_dispatch: {},
  });
  assert.deepEqual(ci.permissions, { contents: "read" });
  assertExactKeys(ci.jobs, ["verify"], "CI must expose one blocking job");
  assertExactKeys(
    ci.jobs.verify,
    ["runs-on", "timeout-minutes", "steps"],
    "CI verify job schema changed",
  );
  assert.equal(ci.jobs.verify["runs-on"], "macos-15");
  assert.equal(ci.jobs.verify["timeout-minutes"], 45);
  assert.deepEqual(ci.jobs.verify.steps, [
    actionStep("Check out source", "actions/checkout", {
      "persist-credentials": false,
    }),
    actionStep("Set up pnpm", "pnpm/action-setup", {
      version: "10.14.0",
    }),
    actionStep("Set up Node.js", "actions/setup-node", {
      "node-version": 22,
      cache: "pnpm",
    }),
    {
      name: "Install XcodeGen",
      run: "brew install xcodegen",
    },
    {
      name: "Verify project Xcode requirement",
      shell: "zsh",
      run: XCODE_REQUIREMENT_RUN,
    },
    {
      name: "Verify v1",
      shell: "zsh",
      run: "Scripts/verify-v1.sh",
    },
  ]);
  assertAuditedActionComments(ciSource);
}

function validateRelease(releaseSource) {
  const release = parseYaml(releaseSource, "release workflow");

  assertExactKeys(
    release,
    ["name", "on", "permissions", "jobs"],
    "release schema changed",
  );
  assert.equal(release.name, "Release");
  assert.deepEqual(release.on, {
    push: { tags: ["v*.*.*"] },
  });
  assert.deepEqual(release.permissions, { contents: "write" });
  assertExactKeys(release.jobs, ["release"], "release must expose one job");
  assertExactKeys(
    release.jobs.release,
    ["runs-on", "timeout-minutes", "steps"],
    "release job schema changed",
  );
  assert.equal(release.jobs.release["runs-on"], "macos-15");
  assert.equal(release.jobs.release["timeout-minutes"], 60);

  const expectedSteps = [
    actionStep("Check out tagged source", "actions/checkout", {
      "fetch-depth": 0,
      "persist-credentials": false,
    }),
    actionStep("Set up pnpm", "pnpm/action-setup", {
      version: "10.14.0",
    }),
    actionStep("Set up Node.js", "actions/setup-node", {
      "node-version": 22,
      cache: "pnpm",
    }),
    {
      name: "Install XcodeGen",
      run: "brew install xcodegen",
    },
    {
      name: "Verify project Xcode requirement",
      shell: "zsh",
      run: XCODE_REQUIREMENT_RUN,
    },
    {
      name: "Validate release contract",
      id: "release-contract",
      shell: "zsh",
      env: {
        TAG: "${{ github.ref_name }}",
        EXPECTED_SHA: "${{ github.sha }}",
      },
      run: RELEASE_VALIDATION_RUN,
    },
    {
      name: "Verify exact source",
      shell: "zsh",
      run: "Scripts/verify-v1.sh",
    },
    {
      name: "Package release",
      shell: "zsh",
      env: {
        VERSION: "${{ steps.release-contract.outputs.version }}",
      },
      run: 'Scripts/package-release.sh "${VERSION}"',
    },
    {
      name: "Verify release artifacts",
      shell: "zsh",
      env: {
        VERSION: "${{ steps.release-contract.outputs.version }}",
      },
      run: 'Scripts/verify-release-artifacts.sh "${VERSION}" "dist/release/${VERSION}"',
    },
    {
      name: "Verify release notes checksums",
      shell: "zsh",
      env: {
        TAG: "${{ github.ref_name }}",
        VERSION: "${{ steps.release-contract.outputs.version }}",
      },
      run: RELEASE_CHECKSUM_LOCK_RUN,
    },
    {
      name: "Publish GitHub Release",
      shell: "zsh",
      env: {
        GH_TOKEN: "${{ github.token }}",
        REPOSITORY: "${{ github.repository }}",
        TAG: "${{ github.ref_name }}",
        VERSION: "${{ steps.release-contract.outputs.version }}",
      },
      run: RELEASE_PUBLISH_RUN,
    },
  ];
  assert.deepEqual(
    release.jobs.release.steps,
    expectedSteps,
    "release step order or schema changed",
  );
  assertAuditedActionComments(releaseSource);
  assertReleaseCommandSurface(
    releaseSource,
    release.jobs.release.steps.at(-1).run,
  );
}

function validateWorkflows(ciSource, releaseSource) {
  validateCI(ciSource);
  validateRelease(releaseSource);
  assertNoProhibitedWorkflowSurface(ciSource, releaseSource);
}

function replaceOnce(source, before, after, mutation) {
  assert.ok(source.includes(before), `${mutation} mutation fixture is stale`);
  const mutated = source.replace(before, after);
  assert.notEqual(mutated, source, `${mutation} mutation did not change source`);
  return mutated;
}

function swapBlocks(source, first, second) {
  const sentinel = "__MYSHOTTR_WORKFLOW_STEP_SWAP__";
  assert.ok(!source.includes(sentinel));
  return replaceOnce(
    replaceOnce(
      replaceOnce(source, first, sentinel, "first reordered step"),
      second,
      first,
      "second reordered step",
    ),
    sentinel,
    second,
    "reordered step sentinel",
  );
}

function expectRejected(label, ciSource, releaseSource) {
  assert.throws(
    () => validateWorkflows(ciSource, releaseSource),
    assert.AssertionError,
    label,
  );
}

function workflowStepBlock(source, name, nextName) {
  const startNeedle = `      - name: ${name}\n`;
  const start = source.indexOf(startNeedle);
  assert.notEqual(start, -1, `${name} step fixture is stale`);
  if (!nextName) {
    return source.slice(start);
  }
  const end = source.indexOf(`      - name: ${nextName}\n`, start + 1);
  assert.notEqual(end, -1, `${nextName} step fixture is stale`);
  return source.slice(start, end);
}

function checksumNotes(lines) {
  return [
    "# Test release",
    "",
    "## SHA-256 checksums",
    "",
    "```text",
    ...lines,
    "```",
    "",
  ].join("\n");
}

function runChecksumVerifier(run, checksumSource, notesSource) {
  const verifierMatch = run.match(/<<'NODE'\n([\s\S]*?)\nNODE\n?$/);
  assert.ok(verifierMatch, "could not isolate the release checksum verifier");
  const temporaryDirectory = mkdtempSync(
    join(tmpdir(), "myshottr-release-checksums."),
  );
  const checksumPath = join(temporaryDirectory, "SHA256SUMS.txt");
  const notesPath = join(temporaryDirectory, "v0.1.0.md");
  writeFileSync(checksumPath, checksumSource, "utf8");
  writeFileSync(notesPath, notesSource, "utf8");
  try {
    return spawnSync(
      process.execPath,
      [
        "--input-type=module",
        "-",
        checksumPath,
        notesPath,
        "MyShottr-0.1.0-macos.zip",
        "MyShottr-Chrome-0.1.0.zip",
      ],
      {
        input: verifierMatch[1],
        encoding: "utf8",
      },
    );
  } finally {
    rmSync(temporaryDirectory, { recursive: true, force: true });
  }
}

const ciSource = readFileSync(CI_PATH, "utf8");
const releaseSource = readFileSync(RELEASE_PATH, "utf8");

validateWorkflows(ciSource, releaseSource);

const parsedRelease = parseYaml(releaseSource, "release workflow");
const checksumStep = parsedRelease.jobs.release.steps.find(
  (step) => step.name === "Verify release notes checksums",
);
assert.ok(checksumStep, "release checksum step is missing");

const checksumLines = [
  "2601c96dd5f8d3d674333c94754e522748a95bb88f051bfd26b2be1371c828f6  MyShottr-0.1.0-macos.zip",
  "b5e8f91b31eaa3d5674954bcd1d63774be51f5a5ad595ee2542efed8458e2f3f  MyShottr-Chrome-0.1.0.zip",
];
const validChecksumSource = `${checksumLines.join("\n")}\n`;
const validNotesSource = checksumNotes(checksumLines);
const validChecksumResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  validNotesSource,
);
assert.equal(
  validChecksumResult.status,
  0,
  `valid release checksums must pass:\n${validChecksumResult.stderr}`,
);

const mismatchResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  checksumNotes([
    `0601c96dd5f8d3d674333c94754e522748a95bb88f051bfd26b2be1371c828f6  MyShottr-0.1.0-macos.zip`,
    checksumLines[1],
  ]),
);
assert.notEqual(mismatchResult.status, 0, "a checksum mismatch must fail closed");

const removedChecksumResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  checksumNotes([checksumLines[0]]),
);
assert.notEqual(
  removedChecksumResult.status,
  0,
  "a removed checksum must fail closed",
);

const reorderedChecksumsResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  checksumNotes([checksumLines[1], checksumLines[0]]),
);
assert.notEqual(
  reorderedChecksumsResult.status,
  0,
  "reordered checksums must fail closed",
);

const duplicateChecksumResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  checksumNotes([checksumLines[0], checksumLines[0]]),
);
assert.notEqual(
  duplicateChecksumResult.status,
  0,
  "a duplicate checksum must fail closed",
);

const extraChecksumResult = runChecksumVerifier(
  checksumStep.run,
  validChecksumSource,
  checksumNotes([...checksumLines, checksumLines[0]]),
);
assert.notEqual(
  extraChecksumResult.status,
  0,
  "an extra checksum must fail closed",
);

const extraReleaseUpload = replaceOnce(
  releaseSource,
  "          --verify-tag",
  `          --verify-tag
          gh release upload "\${TAG}" "\${OUTPUT}/unexpected.zip"`,
  "extra release upload",
);
expectRejected("extra release uploads must be rejected", ciSource, extraReleaseUpload);

const verifySourceBlock = `      - name: Verify exact source
        shell: zsh
        run: Scripts/verify-v1.sh`;
const packageBlock = `      - name: Package release
        shell: zsh
        env:
          VERSION: \${{ steps.release-contract.outputs.version }}
        run: Scripts/package-release.sh "\${VERSION}"`;
expectRejected(
  "packaging before source verification must be rejected",
  ciSource,
  swapBlocks(releaseSource, verifySourceBlock, packageBlock),
);

const checksumLockBlock = workflowStepBlock(
  releaseSource,
  "Verify release notes checksums",
  "Publish GitHub Release",
);
const publishBlock = workflowStepBlock(
  releaseSource,
  "Publish GitHub Release",
);
expectRejected(
  "removing checksum verification must be rejected",
  ciSource,
  replaceOnce(
    releaseSource,
    checksumLockBlock,
    "",
    "removed checksum verification",
  ),
);
expectRejected(
  "publishing before checksum verification must be rejected",
  ciSource,
  swapBlocks(releaseSource, checksumLockBlock, publishBlock),
);

const mutableCheckout = replaceOnce(
  ciSource,
  `actions/checkout@${AUDITED_ACTIONS["actions/checkout"].sha}`,
  "actions/checkout@v7",
  "mutable action",
);
expectRejected("mutable actions must be rejected", mutableCheckout, releaseSource);

const persistedCredentials = replaceOnce(
  releaseSource,
  "persist-credentials: false",
  "persist-credentials: true",
  "persisted credentials",
);
expectRejected(
  "checkout credential persistence must be rejected",
  ciSource,
  persistedCredentials,
);

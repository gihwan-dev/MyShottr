import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const CI_PATH = ".github/workflows/ci.yml";
const RELEASE_PATH = ".github/workflows/release.yml";
const FULL_SHA = /^[0-9a-f]{40}$/;
const STRICT_SEMVER_SOURCE =
  String.raw`\^v\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\\\.\(0\|\[1-9\]\[0-9\]\*\)\$`;

function parseYaml(path) {
  const parser = String.raw`
require "json"
require "yaml"

document = YAML.safe_load(
  File.read(ARGV.fetch(0)),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
STDOUT.write(JSON.generate(document))
`;
  const result = spawnSync("/usr/bin/ruby", ["-e", parser, path], {
    encoding: "utf8",
  });
  assert.equal(
    result.status,
    0,
    `could not parse ${path} as YAML:\n${result.stderr}`,
  );
  return JSON.parse(result.stdout);
}

function assertExactKeys(object, keys, label) {
  assert.deepEqual(Object.keys(object).sort(), [...keys].sort(), label);
}

function getUses(step) {
  if (typeof step.uses !== "string") return null;
  const separator = step.uses.lastIndexOf("@");
  assert.notEqual(separator, -1, `action is missing a ref: ${step.uses}`);
  return {
    action: step.uses.slice(0, separator),
    ref: step.uses.slice(separator + 1),
  };
}

function assertPinnedActions(workflow, source) {
  const steps = Object.values(workflow.jobs).flatMap((job) => job.steps);
  const actionSteps = steps.filter((step) => typeof step.uses === "string");
  assert.ok(actionSteps.length > 0, "workflow must use pinned setup actions");

  for (const step of actionSteps) {
    const { action, ref } = getUses(step);
    assert.match(ref, FULL_SHA, `${action} must use an immutable commit SHA`);
    assert.match(
      source,
      new RegExp(
        String.raw`uses:\s*${action.replaceAll("/", String.raw`\/`)}@${ref}\s+#\s+v[0-9]`,
      ),
      `${action} pin must document its upstream version`,
    );
  }
}

const ciSource = readFileSync(CI_PATH, "utf8");
const releaseSource = readFileSync(RELEASE_PATH, "utf8");
const ci = parseYaml(CI_PATH);
const release = parseYaml(RELEASE_PATH);

assert.equal(ci.name, "CI");
assertExactKeys(
  ci.on,
  ["push", "pull_request", "workflow_dispatch"],
  "CI must run only for main pushes, pull requests, and manual dispatches",
);
assert.deepEqual(ci.on.push.branches, ["main"]);
assert.deepEqual(ci.on.pull_request, {});
assert.deepEqual(ci.on.workflow_dispatch, {});
assert.deepEqual(ci.permissions, { contents: "read" });
assertExactKeys(ci.jobs, ["verify"], "CI must expose one blocking verify job");
assert.equal(ci.jobs.verify["runs-on"], "macos-15");

const ciSteps = ci.jobs.verify.steps;
assert.deepEqual(
  ciSteps
    .filter((step) => typeof step.uses === "string")
    .map((step) => getUses(step).action),
  ["actions/checkout", "pnpm/action-setup", "actions/setup-node"],
);
assert.equal(
  ciSteps.find((step) => getUses(step)?.action === "pnpm/action-setup").with
    .version,
  "10.14.0",
);
assert.equal(
  ciSteps.find((step) => getUses(step)?.action === "actions/setup-node").with[
    "node-version"
  ],
  22,
);
assert.ok(
  ciSteps.some(
    (step) =>
      step.name === "Verify project Xcode requirement" &&
      step.shell === "zsh" &&
      step.run.includes("xcodebuild -version") &&
      step.run.includes("XCODE_MAJOR >= 26"),
  ),
  "CI must reject runners below the project's Xcode 26 requirement",
);
assert.deepEqual(
  ciSteps
    .filter((step) => step.run?.includes("Scripts/verify-v1.sh"))
    .map((step) => ({ name: step.name, shell: step.shell, run: step.run })),
  [{ name: "Verify v1", shell: "zsh", run: "Scripts/verify-v1.sh" }],
  "CI must run the canonical v1 gate exactly once",
);
assertPinnedActions(ci, ciSource);

assert.equal(release.name, "Release");
assertExactKeys(
  release.on,
  ["push"],
  "release workflow must be tag-push-only",
);
assert.deepEqual(release.on.push.tags, ["v[0-9]+.[0-9]+.[0-9]+"]);
assert.deepEqual(release.permissions, { contents: "write" });
assertExactKeys(
  release.jobs,
  ["release"],
  "release workflow must expose one publishing job",
);
assert.equal(release.jobs.release["runs-on"], "macos-15");

const releaseSteps = release.jobs.release.steps;
assert.deepEqual(
  releaseSteps
    .filter((step) => typeof step.uses === "string")
    .map((step) => getUses(step).action),
  ["actions/checkout", "pnpm/action-setup", "actions/setup-node"],
);
assert.equal(
  releaseSteps.find((step) => getUses(step)?.action === "actions/checkout")
    .with["fetch-depth"],
  0,
);
assert.equal(
  releaseSteps.find((step) => getUses(step)?.action === "pnpm/action-setup")
    .with.version,
  "10.14.0",
);
assert.equal(
  releaseSteps.find((step) => getUses(step)?.action === "actions/setup-node")
    .with["node-version"],
  22,
);
assertPinnedActions(release, releaseSource);

const stepNames = releaseSteps.map((step) => step.name).filter(Boolean);
const validateIndex = stepNames.indexOf("Validate release contract");
const sourceGateIndex = stepNames.indexOf("Verify exact source");
const packageIndex = stepNames.indexOf("Package release");
const artifactGateIndex = stepNames.indexOf("Verify release artifacts");
const publishIndex = stepNames.indexOf("Publish GitHub Release");
assert.ok(validateIndex >= 0, "release contract validation step is missing");
assert.ok(
  validateIndex < sourceGateIndex &&
    sourceGateIndex < packageIndex &&
    packageIndex < artifactGateIndex &&
    artifactGateIndex < publishIndex,
  "release validation, source gate, packaging, artifact gate, and publish must be ordered",
);

const validateStep = releaseSteps[validateIndex];
assert.equal(validateStep.shell, "zsh");
assert.match(validateStep.run, new RegExp(STRICT_SEMVER_SOURCE));
assert.match(validateStep.run, /git merge-base --is-ancestor/);
assert.match(validateStep.run, /origin\/main/);
assert.match(validateStep.run, /docs\/releases\/\$\{TAG\}\.md/);
assert.match(validateStep.run, /git rev-parse --verify/);

assert.equal(releaseSteps[sourceGateIndex].run, "Scripts/verify-v1.sh");
assert.equal(releaseSteps[sourceGateIndex].shell, "zsh");

const packageStep = releaseSteps[packageIndex];
assert.equal(packageStep.shell, "zsh");
assert.match(packageStep.run, /^Scripts\/package-release\.sh "\$\{VERSION\}"$/);
assert.deepEqual(Object.keys(packageStep.env), ["VERSION"]);

const artifactGateStep = releaseSteps[artifactGateIndex];
assert.equal(artifactGateStep.shell, "zsh");
assert.match(
  artifactGateStep.run,
  /^Scripts\/verify-release-artifacts\.sh "\$\{VERSION\}" "dist\/release\/\$\{VERSION\}"$/,
);

const publishStep = releaseSteps[publishIndex];
assert.equal(publishStep.shell, "zsh");
assert.equal(publishStep.env.GH_TOKEN, "${{ github.token }}");
assert.match(publishStep.run, /gh release create "\$\{TAG\}"/);
assert.match(publishStep.run, /--verify-tag/);
assert.match(
  publishStep.run,
  /--notes-file "docs\/releases\/\$\{TAG\}\.md"/,
);

const expectedAssets = [
  '"${OUTPUT}/MyShottr-${VERSION}-macos.zip"',
  '"${OUTPUT}/MyShottr-Chrome-${VERSION}.zip"',
  '"${OUTPUT}/SHA256SUMS.txt"',
];
const createCommand = publishStep.run.match(
  /gh release create "\$\{TAG\}"[\s\S]*?\s+--repo /,
)?.[0];
assert.ok(createCommand, "could not isolate the GitHub release command");
const createCommandLines = createCommand
  .split("\n")
  .map((line) => line.trim().replace(/\s*\\$/, ""))
  .filter(Boolean);
assert.equal(createCommandLines[0], 'gh release create "${TAG}"');
assert.deepEqual(
  createCommandLines.slice(1, -1),
  expectedAssets,
  "release must upload exactly the three approved files",
);
assert.doesNotMatch(publishStep.run, /(?:\*|\?|\[[^\]]+\])\.zip/);
assert.doesNotMatch(releaseSource, /actions\/upload-artifact/);

for (const [label, source] of [
  ["CI", ciSource],
  ["release", releaseSource],
]) {
  assert.doesNotMatch(source, /pull_request_target/);
  assert.doesNotMatch(source, /\$\{\{\s*secrets\./);
  assert.doesNotMatch(
    source,
    /APPLE_|NOTARY|SIGNING|CERTIFICATE/i,
    `${label} workflow must not contain distribution credentials or operations`,
  );
}

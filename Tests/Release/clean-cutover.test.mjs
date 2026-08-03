import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";

import { collectCleanCutoverViolations } from "../../Scripts/verify-clean-cutover.mjs";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const scannerSourcePath = path.join(repositoryRoot, "Scripts/verify-clean-cutover.mjs");
const execFileAsync = promisify(execFile);

const bannedTokens = [
  ["My", "Shottr"].join(""),
  [".", "my", "shottr"].join(""),
  ["com", ".", "my", "shottr"].join(""),
  ["My", "Shottr", "NativeHost"].join(""),
  ["my", "shottr", "-editor"].join(""),
  ["Quick", "Ink"].join(""),
  ["Quick", " Ink"].join(""),
];

async function writeFixtureFile(root, relativePath, contents = "clean\n") {
  const absolutePath = path.join(root, relativePath);
  await fs.mkdir(path.dirname(absolutePath), { recursive: true });
  await fs.writeFile(absolutePath, contents);
}

async function makeRepositoryFixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "inkbeam-clean-cutover-test."));
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  await Promise.all([
    writeFixtureFile(root, "project.yml"),
    writeFixtureFile(root, "Inkbeam.xcodeproj/project.pbxproj"),
    writeFixtureFile(root, "package.json", "{}\n"),
    writeFixtureFile(root, "pnpm-lock.yaml"),
    writeFixtureFile(root, "Config/.keep"),
    writeFixtureFile(root, "Sources/.keep"),
    writeFixtureFile(root, "Packages/.keep"),
    writeFixtureFile(root, "Tests/.keep"),
    writeFixtureFile(root, "README.md", "# Inkbeam\n"),
    writeFixtureFile(root, "docs/.keep"),
    writeFixtureFile(
      root,
      "Scripts/verify-clean-cutover.mjs",
      await fs.readFile(scannerSourcePath, "utf8"),
    ),
  ]);
  await execFileAsync("git", ["init", "-q"], { cwd: root });

  return root;
}

test("accepts a clean repository with the generated Inkbeam project", async (t) => {
  const root = await makeRepositoryFixture(t);

  assert.deepEqual(await collectCleanCutoverViolations(root), []);
});

test("fails when the generated project file is absent", async (t) => {
  const root = await makeRepositoryFixture(t);
  await fs.rm(path.join(root, "Inkbeam.xcodeproj/project.pbxproj"));

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    "Inkbeam.xcodeproj/project.pbxproj: missing required generated project",
  ]);
});

test("reports every banned token in UTF-8 contents with deterministic locations", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "Sources/LegacyTokens.txt",
    `clean line\n${bannedTokens.join(" | ")}\n`,
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `Sources/LegacyTokens.txt:2:1: banned token ${bannedTokens[0]}`,
    `Sources/LegacyTokens.txt:2:12: banned token ${bannedTokens[1]}`,
    `Sources/LegacyTokens.txt:2:24: banned token ${bannedTokens[2]}`,
    `Sources/LegacyTokens.txt:2:27: banned token ${bannedTokens[1]}`,
    `Sources/LegacyTokens.txt:2:39: banned token ${bannedTokens[0]}`,
    `Sources/LegacyTokens.txt:2:39: banned token ${bannedTokens[3]}`,
    `Sources/LegacyTokens.txt:2:60: banned token ${bannedTokens[4]}`,
    `Sources/LegacyTokens.txt:2:78: banned token ${bannedTokens[5]}`,
    `Sources/LegacyTokens.txt:2:89: banned token ${bannedTokens[6]}`,
  ]);
});

test("reports banned tokens in relative paths", async (t) => {
  const root = await makeRepositoryFixture(t);
  const legacyPath = `Sources/${bannedTokens[0]}Feature/clean.txt`;
  await writeFixtureFile(root, legacyPath);

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `${legacyPath}: path contains banned token ${bannedTokens[0]}`,
  ]);
});

test("allows only exact historical files", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "docs/superpowers/plans/2026-07-29-myshottr-chrome-capture.md",
    `${bannedTokens[0]} ${bannedTokens[6]} ${bannedTokens[1]}\n`,
  );
  const copiedPath = `docs/superpowers/plans/copied-${bannedTokens[4]}-chrome-capture.md`;
  await writeFixtureFile(
    root,
    copiedPath,
    `${bannedTokens[0]}\n`,
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `${copiedPath}: path contains banned token ${bannedTokens[4]}`,
    `${copiedPath}:1:1: banned token ${bannedTokens[0]}`,
  ]);
});

test("allows README legacy wording only inside one exact historical marker pair", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "README.md",
    [
      "# Inkbeam",
      "<!-- historical-v0.1.0:start -->",
      `${bannedTokens[0]} used ${bannedTokens[1]} and ${bannedTokens[6]}.`,
      "<!-- historical-v0.1.0:end -->",
      `${bannedTokens[0]} is live again.`,
      "",
    ].join("\n"),
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `README.md:5:1: banned token ${bannedTokens[0]}`,
  ]);
});

test("rejects malformed or repeated README historical markers", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "README.md",
    [
      "# Inkbeam",
      "<!-- historical-v0.1.0:start -->",
      "<!-- historical-v0.1.0:start -->",
      "<!-- historical-v0.1.0:end -->",
      "",
    ].join("\n"),
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    "README.md: malformed historical-v0.1.0 marker section",
  ]);
});

test("exempts only scanner declarations and detects an appended scanner violation", async (t) => {
  const root = await makeRepositoryFixture(t);
  await fs.appendFile(
    path.join(root, "Scripts/verify-clean-cutover.mjs"),
    `\nconst obsoleteProductLabel = "${bannedTokens[0]}";\n`,
  );

  const violations = await collectCleanCutoverViolations(root);
  assert.equal(violations.length, 1);
  assert.match(
    violations[0],
    new RegExp(
      `^Scripts/verify-clean-cutover\\.mjs:\\d+:31: banned token ${bannedTokens[0]}$`,
    ),
  );
});

test("does not scan non-UTF-8 file contents", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "Sources/Binary.dat",
    Buffer.from([0xff, ...Buffer.from(bannedTokens[0], "utf8")]),
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), []);
});

test("does not scan Git-ignored dependency and build outputs", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(root, ".gitignore", "Packages/generated/\n");
  await writeFixtureFile(
    root,
    "Packages/generated/bundle.js",
    `${bannedTokens[0]}\n`,
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), []);
});

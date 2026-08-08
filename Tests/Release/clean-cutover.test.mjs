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

function expectedNonRegularViolation(relativePath, kind) {
  return `${relativePath}: repository entry is not a regular file (${kind})`;
}

function fileSystemFailing(operation, absolutePath, injectedError) {
  return new Proxy(fs, {
    get(target, property) {
      if (property === operation) {
        return async (candidatePath, ...args) => {
          if (path.resolve(candidatePath) === absolutePath) throw injectedError;
          return target[property](candidatePath, ...args);
        };
      }
      const value = Reflect.get(target, property);
      return typeof value === "function" ? value.bind(target) : value;
    },
  });
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

test("rejects a symlinked generated project instead of following it", async (t) => {
  const root = await makeRepositoryFixture(t);
  const projectPath = path.join(root, "Inkbeam.xcodeproj/project.pbxproj");
  await fs.rm(projectPath);
  await writeFixtureFile(root, "generated-project-target.pbxproj");
  await fs.symlink("../generated-project-target.pbxproj", projectPath);

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    expectedNonRegularViolation(
      "Inkbeam.xcodeproj/project.pbxproj",
      "symbolic link",
    ),
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

test("reports every banned token in relative paths", async (t) => {
  const root = await makeRepositoryFixture(t);
  const legacyPaths = bannedTokens.map(
    (token, index) => `Sources/path-${index}-${token}-case.txt`,
  );
  await Promise.all(legacyPaths.map((legacyPath) => writeFixtureFile(root, legacyPath)));

  const violations = await collectCleanCutoverViolations(root);
  for (let index = 0; index < bannedTokens.length; index += 1) {
    assert.ok(
      violations.includes(
        `${legacyPaths[index]}: path contains banned token ${bannedTokens[index]}`,
      ),
      `missing path diagnostic for ${bannedTokens[index]}`,
    );
  }
});

test("scans banned content inside the required generated project", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "Inkbeam.xcodeproj/project.pbxproj",
    `${bannedTokens[5]}\n`,
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `Inkbeam.xcodeproj/project.pbxproj:1:1: banned token ${bannedTokens[5]}`,
  ]);
});

test("scans tracked and non-ignored untracked files", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(root, "Sources/A-Tracked.txt", `${bannedTokens[5]}\n`);
  await execFileAsync("git", ["add", "--", "Sources/A-Tracked.txt"], { cwd: root });
  await writeFixtureFile(root, "Sources/B-Untracked.txt", `${bannedTokens[6]}\n`);

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `Sources/A-Tracked.txt:1:1: banned token ${bannedTokens[5]}`,
    `Sources/B-Untracked.txt:1:1: banned token ${bannedTokens[6]}`,
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
      `${bannedTokens[5]} before history.`,
      "<!-- historical-v0.1.0:start -->",
      `${bannedTokens[0]} used ${bannedTokens[1]} and ${bannedTokens[6]}.`,
      "<!-- historical-v0.1.0:end -->",
      `${bannedTokens[6]} after history.`,
      "",
    ].join("\n"),
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `README.md:2:1: banned token ${bannedTokens[5]}`,
    `README.md:6:1: banned token ${bannedTokens[6]}`,
  ]);
});

const readmeStartMarker = "<!-- historical-v0.1.0:start -->";
const readmeEndMarker = "<!-- historical-v0.1.0:end -->";
const malformedReadmeCases = [
  {
    name: "rejects reversed README historical markers",
    lines: [readmeEndMarker, bannedTokens[5], readmeStartMarker],
  },
  {
    name: "rejects a duplicate README historical start marker",
    lines: [readmeStartMarker, readmeStartMarker, bannedTokens[5], readmeEndMarker],
  },
  {
    name: "rejects a duplicate README historical end marker",
    lines: [readmeStartMarker, bannedTokens[5], readmeEndMarker, readmeEndMarker],
  },
  {
    name: "rejects nested README historical marker pairs",
    lines: [
      readmeStartMarker,
      readmeStartMarker,
      bannedTokens[5],
      readmeEndMarker,
      readmeEndMarker,
    ],
  },
  {
    name: "rejects repeated README historical marker pairs",
    lines: [
      readmeStartMarker,
      bannedTokens[5],
      readmeEndMarker,
      readmeStartMarker,
      bannedTokens[6],
      readmeEndMarker,
    ],
  },
  {
    name: "rejects a README historical end marker without a start",
    lines: [bannedTokens[5], readmeEndMarker],
  },
  {
    name: "rejects a README historical start marker without an end",
    lines: [readmeStartMarker, bannedTokens[5]],
  },
  {
    name: "rejects README marker tricks that are not standalone lines",
    lines: [
      `prefix ${readmeStartMarker}`,
      bannedTokens[5],
      `${readmeEndMarker} suffix`,
    ],
  },
];

for (const readmeCase of malformedReadmeCases) {
  test(readmeCase.name, async (t) => {
    const root = await makeRepositoryFixture(t);
    await writeFixtureFile(
      root,
      "README.md",
      ["# Inkbeam", ...readmeCase.lines, ""].join("\n"),
    );

    const violations = await collectCleanCutoverViolations(root);
    assert.equal(
      violations[0],
      "README.md: malformed historical-v0.1.0 marker section",
    );
    assert.ok(
      violations.some((violation) => violation.includes("banned token")),
      "malformed markers must not hide banned content",
    );
  });
}

test("rejects a symlinked in-scope file", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(root, "linked-file-target.txt", `${bannedTokens[5]}\n`);
  await fs.symlink("../linked-file-target.txt", path.join(root, "Sources/Linked.txt"));

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    expectedNonRegularViolation("Sources/Linked.txt", "symbolic link"),
  ]);
});

test("rejects a symlinked in-scope directory without traversing it", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "linked-directory-target/Hidden.txt",
    `${bannedTokens[5]}\n`,
  );
  await fs.symlink(
    "../linked-directory-target",
    path.join(root, "Sources/LinkedDirectory"),
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    expectedNonRegularViolation("Sources/LinkedDirectory", "symbolic link"),
  ]);
});

test("rejects a non-regular in-scope FIFO", async (t) => {
  const root = await makeRepositoryFixture(t);
  const fifoPath = path.join(root, "Sources/LegacyPipe");
  await execFileAsync("mkfifo", [fifoPath]);

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    expectedNonRegularViolation("Sources/LegacyPipe", "FIFO"),
  ]);
});

test("fails closed when lstat cannot inspect an in-scope file", async (t) => {
  const root = await makeRepositoryFixture(t);
  const absolutePath = path.join(root, "Sources/Unreadable.txt");
  await writeFixtureFile(root, "Sources/Unreadable.txt");
  const injectedError = Object.assign(new Error("injected lstat failure"), {
    code: "EACCES",
  });

  await assert.rejects(
    collectCleanCutoverViolations(root, {
      fileSystem: fileSystemFailing("lstat", absolutePath, injectedError),
    }),
    (error) => error === injectedError,
  );
});

test("fails closed when readFile cannot read an in-scope file", async (t) => {
  const root = await makeRepositoryFixture(t);
  const absolutePath = path.join(root, "Sources/Unreadable.txt");
  await writeFixtureFile(root, "Sources/Unreadable.txt");
  const injectedError = Object.assign(new Error("injected read failure"), {
    code: "EIO",
  });

  await assert.rejects(
    collectCleanCutoverViolations(root, {
      fileSystem: fileSystemFailing("readFile", absolutePath, injectedError),
    }),
    (error) => error === injectedError,
  );
});

test("orders multi-file and multi-token diagnostics deterministically", async (t) => {
  const root = await makeRepositoryFixture(t);
  await writeFixtureFile(
    root,
    "Sources/Z-Last.txt",
    `clean\n${bannedTokens[3]}\n`,
  );
  await writeFixtureFile(
    root,
    "Sources/A-First.txt",
    `${bannedTokens[6]}\n${bannedTokens[5]}\n`,
  );

  assert.deepEqual(await collectCleanCutoverViolations(root), [
    `Sources/A-First.txt:1:1: banned token ${bannedTokens[6]}`,
    `Sources/A-First.txt:2:1: banned token ${bannedTokens[5]}`,
    `Sources/Z-Last.txt:2:1: banned token ${bannedTokens[0]}`,
    `Sources/Z-Last.txt:2:1: banned token ${bannedTokens[3]}`,
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

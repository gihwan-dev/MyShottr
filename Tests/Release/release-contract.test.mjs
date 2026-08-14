import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

import { contractFor } from "../../Scripts/release/release-contract.mjs";

const TEST_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(TEST_DIRECTORY, "../..");
const RELEASE_CLI = path.join(REPOSITORY_ROOT, "Scripts/release/inkbeam-release");

function makeDispatcherFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-dispatcher-"));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const releaseDirectory = path.join(root, "Scripts/release");
  fs.mkdirSync(releaseDirectory, { recursive: true });
  for (const name of [
    "inkbeam-release",
    "release-contract.mjs",
    "release-state.mjs",
  ]) {
    fs.copyFileSync(path.join(REPOSITORY_ROOT, "Scripts/release", name), path.join(releaseDirectory, name));
  }
  fs.chmodSync(path.join(releaseDirectory, "inkbeam-release"), 0o755);

  const scripts = [
    "preflight.sh",
    "package.sh",
    "resume-notarization.sh",
    "publish-github.sh",
    "verify-public.sh",
    "prepare-feed.sh",
    "publish-feed.sh",
    "withdraw-candidate.sh",
    "record-acceptance.sh",
    "promote-final.sh",
    "rollback-final.sh",
    "deprecate-v0.1.0.sh",
    "complete.sh",
  ];
  for (const name of scripts) {
    const script = path.join(releaseDirectory, name);
    fs.writeFileSync(script, "#!/bin/zsh\nexit 23\n", { mode: 0o755 });
  }
  return {
    cli: path.join(releaseDirectory, "inkbeam-release"),
    root,
  };
}

test("maps every approved release tag exactly", () => {
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
  assert.deepEqual(contractFor("v0.2.0-rc.2"), {
    tag: "v0.2.0-rc.2",
    version: "0.2.0",
    build: 3,
    channel: "beta",
    dmg: "Inkbeam-0.2.0-rc.2.dmg",
    chromeZip: "Inkbeam-Chrome-0.2.0-rc.2.zip",
    releaseTitle: "Inkbeam v0.2.0-rc.2",
    prerelease: true,
  });
  assert.deepEqual(contractFor("v0.2.0"), {
    tag: "v0.2.0",
    version: "0.2.0",
    build: 4,
    channel: "stable",
    dmg: "Inkbeam-0.2.0.dmg",
    chromeZip: "Inkbeam-Chrome-0.2.0.zip",
    releaseTitle: "Inkbeam v0.2.0 (Final Candidate)",
    prerelease: true,
  });
});

test("rejects every unapproved release tag", () => {
  for (const tag of ["v0.2.1", "0.2.0", "v0.2.0-rc.3", "", undefined]) {
    assert.throws(() => contractFor(tag), /unsupported release tag/);
  }
});

test("returns immutable contracts without exposing the stored release map", () => {
  const contract = contractFor("v0.2.0-rc.1");

  assert.throws(() => {
    contract.build = 99;
  }, TypeError);
  assert.equal(contractFor("v0.2.0-rc.1").build, 2);
});

test("dispatcher prints the exact contract as JSON", () => {
  const result = spawnSync(RELEASE_CLI, ["contract", "v0.2.0-rc.1"], {
    cwd: REPOSITORY_ROOT,
    encoding: "utf8",
  });

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), contractFor("v0.2.0-rc.1"));
});

test("dispatcher fails closed for unknown verbs and invalid argument counts", () => {
  const unknown = spawnSync(RELEASE_CLI, ["run-anything", "v0.2.0"], {
    cwd: REPOSITORY_ROOT,
    encoding: "utf8",
  });
  assert.equal(unknown.status, 64);
  assert.match(unknown.stderr, /unknown release verb/);

  const extraArgument = spawnSync(
    RELEASE_CLI,
    ["contract", "v0.2.0", "unexpected"],
    { cwd: REPOSITORY_ROOT, encoding: "utf8" },
  );
  assert.equal(extraArgument.status, 64);
  assert.match(extraArgument.stderr, /usage:/i);
});

test("dispatcher validates the tag before every tag-scoped command", () => {
  const result = spawnSync(
    RELEASE_CLI,
    ["record-acceptance", "v0.2.1", "/tmp/acceptance.md"],
    { cwd: REPOSITORY_ROOT, encoding: "utf8" },
  );

  assert.equal(result.status, 65);
  assert.match(result.stderr, /unsupported release tag/);
  assert.doesNotMatch(result.stderr, /not implemented/);
});

test("dispatcher pins the exact argument count for every public verb", (t) => {
  const fixture = makeDispatcherFixture(t);
  const sha = "0123456789abcdef0123456789abcdef01234567";
  const commands = [
    ["contract", ["v0.2.0-rc.1"], 0],
    ["status", ["v0.2.0-rc.1"], 65],
    ["preflight", ["v0.2.0-rc.1", "main", sha], 23],
    ["package", ["v0.2.0-rc.1", "main", sha], 23],
    ["resume-notarization", ["v0.2.0-rc.1"], 23],
    ["publish-candidate", ["v0.2.0-rc.1"], 23],
    ["verify-public", ["v0.2.0-rc.1"], 23],
    ["prepare-feed", ["v0.2.0-rc.1", "beta"], 23],
    ["publish-feed", ["v0.2.0-rc.1", "beta"], 23],
    ["withdraw-candidate", ["v0.2.0-rc.1"], 23],
    ["record-acceptance", ["v0.2.0-rc.1", "/tmp/acceptance.md"], 23],
    ["promote-final", [], 23],
    ["rollback-final", [], 23],
    ["deprecate-v0.1.0", [], 23],
    ["complete", ["v0.2.0-rc.1"], 23],
  ];

  for (const [verb, parameters, expectedStatus] of commands) {
    const exact = spawnSync(fixture.cli, [verb, ...parameters], {
      cwd: fixture.root,
      encoding: "utf8",
    });
    assert.equal(exact.status, expectedStatus, `${verb}: ${exact.stderr}`);

    if (parameters.length > 0) {
      const tooFew = spawnSync(fixture.cli, [verb, ...parameters.slice(0, -1)], {
        cwd: fixture.root,
        encoding: "utf8",
      });
      assert.equal(tooFew.status, 64, `${verb} accepted too few arguments`);
    }

    const tooMany = spawnSync(fixture.cli, [verb, ...parameters, "unexpected"], {
      cwd: fixture.root,
      encoding: "utf8",
    });
    assert.equal(tooMany.status, 64, `${verb} accepted too many arguments`);
  }
});

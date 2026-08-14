import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import test from "node:test";

import { contractFor } from "../../Scripts/release/release-contract.mjs";

const TEST_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const REPOSITORY_ROOT = path.resolve(TEST_DIRECTORY, "../..");
const RELEASE_CLI = path.join(REPOSITORY_ROOT, "Scripts/release/inkbeam-release");

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

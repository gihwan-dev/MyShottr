import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");

test("the real checkout has one common 0.2.0 release version", () => {
  const result = spawnSync(
    process.execPath,
    ["Scripts/verify-release-metadata.mjs", "0.2.0"],
    { cwd: repositoryRoot, encoding: "utf8" },
  );

  assert.equal(
    result.status,
    0,
    `release metadata preflight failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`,
  );
});

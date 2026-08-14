import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const project = readFileSync(path.join(repositoryRoot, "project.yml"), "utf8");
const plist = readFileSync(path.join(repositoryRoot, "Config/Inkbeam-Info.plist"), "utf8");
const manifest = JSON.parse(readFileSync(
  path.join(repositoryRoot, "Packages/chrome-extension/public/manifest.json"),
  "utf8",
));

test("the real checkout exposes the release metadata build settings", () => {
  assert.match(project, /MARKETING_VERSION:\s*"0\.2\.0"/m);
  assert.match(project, /CFBundleShortVersionString:\s*\$\(MARKETING_VERSION\)/m);
  assert.match(project, /CFBundleVersion:\s*\$\(CURRENT_PROJECT_VERSION\)/m);
  assert.match(project, /InkbeamReleaseChannel:\s*\$\(INKBEAM_RELEASE_CHANNEL_NAME\)/m);
  assert.match(plist, /<string>\$\(MARKETING_VERSION\)<\/string>/);
  assert.match(plist, /<string>\$\(CURRENT_PROJECT_VERSION\)<\/string>/);
  assert.match(plist, /<key>InkbeamReleaseChannel<\/key>\s*<string>\$\(INKBEAM_RELEASE_CHANNEL_NAME\)<\/string>/);
  assert.equal(manifest.version, "0.2.0");

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

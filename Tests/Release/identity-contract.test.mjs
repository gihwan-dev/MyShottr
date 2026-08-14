import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const read = (path) => fs.readFileSync(path, "utf8");

test("the build graph exposes only Inkbeam identities", () => {
  const project = read("project.yml");
  const appInfo = read("Config/Inkbeam-Info.plist");
  const rootPackage = JSON.parse(read("package.json"));
  const editorPackage = JSON.parse(read("Packages/editor/package.json"));
  const chromePackage = JSON.parse(read("Packages/chrome-extension/package.json"));

  assert.match(project, /^name: Inkbeam$/m);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER: dev\.gihwan\.inkbeam$/m);
  assert.match(project, /PRODUCT_BUNDLE_IDENTIFIER: dev\.gihwan\.inkbeam\.nativehost$/m);
  assert.match(project, /DEVELOPMENT_TEAM: SLVS4WF9U2$/m);
  assert.match(project, /CFBundleTypeExtensions: \[inkbeam\]/);
  assert.match(project, /UTTypeIdentifier: dev\.gihwan\.inkbeam\.project/);
  assert.match(appInfo, /dev\.gihwan\.inkbeam\.project/);
  assert.match(appInfo, /<string>inkbeam<\/string>/);
  assert.equal(rootPackage.name, "inkbeam");
  assert.equal(editorPackage.name, "@inkbeam/editor");
  assert.equal(chromePackage.name, "@inkbeam/chrome-extension");

  const obsoleteGenerator = ["generate", "extension", "identity.sh"].join("-");
  const obsoleteGeneratorPath = path.join("Scripts", obsoleteGenerator);
  assert.equal(fs.existsSync(obsoleteGeneratorPath), false);
  const activeAutomationFiles = execFileSync(
    "git",
    ["ls-files", "package.json", "project.yml", ".github", "Scripts"],
    { encoding: "utf8" },
  ).trim().split("\n").filter(
    (file) => file && file !== obsoleteGeneratorPath,
  );
  for (const file of activeAutomationFiles) {
    assert.doesNotMatch(read(file), new RegExp(obsoleteGenerator));
  }
});

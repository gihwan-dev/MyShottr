import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const read = (filePath) => fs.readFileSync(filePath, "utf8");
const readSwiftTree = (directory) => fs.readdirSync(directory, { recursive: true })
  .filter((entry) => entry.endsWith(".swift"))
  .map((entry) => read(path.join(directory, entry)))
  .join("\n");

test("executable build consumers use Inkbeam project products and test module", () => {
  const packageRelease = read("Scripts/package-release.sh");
  const verifier = read("Scripts/verify-v1.sh");
  const appTests = readSwiftTree("Tests/InkbeamTests");
  const nativeHostProcessTests = read("Tests/InkbeamNativeHostTests/NativeHostProcessTests.swift");
  const appConfigurationTests = read("Tests/InkbeamTests/AppConfigurationTests.swift");

  for (const script of [packageRelease, verifier]) {
    assert.match(script, /Inkbeam\.xcodeproj/);
    assert.match(script, /-scheme Inkbeam/);
    assert.match(script, /Inkbeam\.app/);
    assert.match(script, /InkbeamNativeHost/);
    assert.doesNotMatch(script, /MyShottr\.xcodeproj|scheme MyShottr|MyShottr\.app|MyShottrNativeHost/);
  }
  assert.match(packageRelease, /Config\/Inkbeam-Info\.plist/);
  assert.doesNotMatch(packageRelease, /Config\/MyShottr-Info\.plist/);
  assert.doesNotMatch(appTests, /@testable import MyShottr/);
  assert.match(appTests, /@testable import Inkbeam/);
  assert.match(appConfigurationTests, /extensions\.contains\("inkbeam"\)/);
  assert.doesNotMatch(appConfigurationTests, /extensions\.contains\("myshottr"\)/);
  assert.match(nativeHostProcessTests, /appendingPathComponent\("InkbeamNativeHost"\)/);
  assert.doesNotMatch(nativeHostProcessTests, /appendingPathComponent\("MyShottrNativeHost"\)/);
});

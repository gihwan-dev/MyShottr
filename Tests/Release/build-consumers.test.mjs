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
  const metadataPreflight = read("Scripts/verify-release-metadata.mjs");
  const verifier = read("Scripts/verify-inkbeam.sh");
  const artifactVerifier = read("Scripts/verify-release-artifacts.sh");
  const appTests = readSwiftTree("Tests/InkbeamTests");
  const nativeHostProcessTests = read("Tests/InkbeamNativeHostTests/NativeHostProcessTests.swift");
  const appConfigurationTests = read("Tests/InkbeamTests/AppConfigurationTests.swift");

  for (const script of [packageRelease, verifier]) {
    assert.match(script, /Inkbeam\.xcodeproj/);
    assert.match(script, /-scheme Inkbeam/);
    assert.match(script, /Inkbeam\.app/);
    assert.match(script, /InkbeamNativeHost/);
  }
  assert.match(metadataPreflight, /Config\/Inkbeam-Info\.plist/);
  assert.match(metadataPreflight, /Packages\/chrome-extension\/public\/manifest\.json/);
  assert.match(
    packageRelease,
    /node "\$\{REPO_ROOT\}\/Scripts\/verify-release-metadata\.mjs" "\$\{VERSION\}"/,
  );
  assert.match(
    verifier,
    /SOURCE_EXTENSION_KEY="\$\{REPO_ROOT\}\/Config\/chrome-extension-key\.b64"/,
  );
  assert.match(
    verifier,
    /APP_EXTENSION_KEY="\$\{APP\}\/Contents\/Resources\/chrome-extension-key\.b64"/,
  );
  assert.match(
    verifier,
    /cmp -s "\$\{SOURCE_EXTENSION_KEY\}" "\$\{APP_EXTENSION_KEY\}"/,
  );
  assert.match(
    verifier,
    /manifest\.version === "0\.2\.0", "built extension version is not 0\.2\.0"/,
  );
  assert.match(
    verifier,
    /CFBundleShortVersionString raw "\$\{APP\}\/Contents\/Info\.plist"\s*\n\)" == "0\.2\.0"/,
  );
  assert.match(artifactVerifier, /inspect_archive "\$\{APP_ARCHIVE\}" "Inkbeam\.app" "app"/);
  assert.match(artifactVerifier, /Contents\/Helpers\/InkbeamNativeHost/);
  assert.match(artifactVerifier, /Contents\/MacOS\/Inkbeam/);
  assert.match(
    artifactVerifier,
    /\)" == "dev\.gihwan\.inkbeam" \]\] \|\| fail "unexpected app bundle identifier"/,
  );
  assert.match(appTests, /@testable import Inkbeam/);
  assert.match(appConfigurationTests, /extensions\.contains\("inkbeam"\)/);
  assert.match(nativeHostProcessTests, /appendingPathComponent\("InkbeamNativeHost"\)/);
});

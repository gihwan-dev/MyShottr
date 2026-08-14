import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const verifierSourcePath = path.join(repositoryRoot, "Scripts/verify-inkbeam.sh");
const privacyVerifierSourcePath = path.join(repositoryRoot, "Scripts/verify-privacy.sh");

async function writeFixtureFile(root, relativePath, contents = "fixture\n", mode) {
  const absolutePath = path.join(root, relativePath);
  await fs.mkdir(path.dirname(absolutePath), { recursive: true });
  await fs.writeFile(absolutePath, contents);
  if (mode !== undefined) await fs.chmod(absolutePath, mode);
}

test("canonical verification inspects separate Stable and RC artifacts before reporting success", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "inkbeam-verifier-order-test."));
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const eventsPath = path.join(root, "events.log");
  const binPath = path.join(root, "bin");
  const temporaryPath = path.join(root, "tmp");
  const verifierPath = path.join(root, "Scripts/verify-inkbeam.sh");
  const generatedProjectPath = path.join(root, "Inkbeam.xcodeproj/project.pbxproj");
  await Promise.all([
    writeFixtureFile(root, "pnpm-lock.yaml"),
    writeFixtureFile(root, "Config/chrome-extension-key.b64", "stable-key\n"),
    writeFixtureFile(
      root,
      "Packages/chrome-extension/dist/manifest.json",
      '{"manifest_version":3,"version":"0.2.0","permissions":["activeTab","nativeMessaging"],"key":"stable-key","background":{"service_worker":"service-worker.js","type":"module"}}\n',
    ),
    writeFixtureFile(root, "Packages/chrome-extension/dist/service-worker.js"),
    writeFixtureFile(root, "Scripts/verify-clean-cutover.mjs"),
    writeFixtureFile(
      root,
      "Scripts/verify-privacy.sh",
      `#!/bin/zsh
set -eu
case "\${2:-}" in
  */VerifyInkbeam-Stable/*) artifact=stable ;;
  */VerifyInkbeam-RC/*) artifact=beta ;;
  *) exit 96 ;;
esac
print "privacy:\${1:-missing}:\${artifact}" >>"\${INKBEAM_ORDER_EVENTS}"
if [[ "\${artifact}" == beta && "\${INKBEAM_ORDER_BETA_FAILURE_STAGE:-}" == privacy ]]; then
  exit 73
fi
`,
      0o755,
    ),
    writeFixtureFile(
      root,
      "Scripts/generate-project.sh",
      `#!/bin/zsh
set -eu
channel="\${INKBEAM_RELEASE_CHANNEL:-stable}"
print "generate:\${channel}" >>"\${INKBEAM_ORDER_EVENTS}"
if [[ "\${channel}" == beta && "\${INKBEAM_ORDER_BETA_FAILURE_STAGE:-}" == generate ]]; then
  exit 71
fi
if [[ "\${channel}" == stable \
  && "\${INKBEAM_ORDER_BETA_FAILURE_STAGE:-}" == restore \
  && -f "\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/channel" \
  && "$(<"\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/channel")" == beta \
  && ! -f "\${INKBEAM_TEST_REPO_ROOT}/restore-failed-once" ]]; then
  : >"\${INKBEAM_TEST_REPO_ROOT}/restore-failed-once"
  exit 74
fi
mkdir -p "\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj"
print '// generated' >"\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/project.pbxproj"
print "\${channel}" >"\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/channel"
`,
      0o755,
    ),
    writeFixtureFile(
      root,
      "Scripts/verify-inkbeam.sh",
      await fs.readFile(verifierSourcePath, "utf8"),
      0o755,
    ),
  ]);
  await Promise.all([
    fs.mkdir(binPath, { recursive: true }),
    fs.mkdir(temporaryPath, { recursive: true }),
  ]);
  await writeFixtureFile(
    root,
    "bin/tool-stub",
    `#!/bin/zsh
set -eu

tool="\${0:t}"
case "\${tool}" in
  node)
    if [[ "\${1:-}" == "--version" ]]; then
      print 'v22.0.0'
      exit 0
    fi
    if [[ "\${1:-}" == */Scripts/verify-clean-cutover.mjs ]]; then
      print 'scanner' >>"\${INKBEAM_ORDER_EVENTS}"
      [[ -f "\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/project.pbxproj" ]] || exit 91
      if [[ -n "\${INKBEAM_ORDER_SCANNER_FAILURE:-}" ]]; then
        exit "\${INKBEAM_ORDER_SCANNER_FAILURE}"
      fi
    fi
    exit 0
    ;;
  pnpm)
    if [[ "\${1:-}" == "--version" ]]; then
      print '10.14.0'
      exit 0
    fi
    if [[ "\${*}" == "test:release" ]]; then
      print 'pnpm-test-release' >>"\${INKBEAM_ORDER_EVENTS}"
      [[ -f "\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/project.pbxproj" ]] || exit 92
    fi
    exit 0
    ;;
  xcodegen)
    [[ "\${*}" == "generate" ]] || exit 93
    print 'xcodegen-direct' >>"\${INKBEAM_ORDER_EVENTS}"
    mkdir -p "\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj"
    print '// generated' >"\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/project.pbxproj"
    ;;
  xcodebuild)
    if [[ "\${1:-}" == "-version" ]]; then
      print 'Xcode 26.0'
      print 'Build version 17A000'
      exit 0
    fi
    if [[ "\${1:-}" == "build" ]]; then
      derived_data=''
      previous=''
      for argument in "\${@}"; do
        if [[ "\${previous}" == '-derivedDataPath' ]]; then
          derived_data="\${argument}"
          break
        fi
        previous="\${argument}"
      done
      [[ -n "\${derived_data}" ]] || exit 97
      channel="$(<"\${INKBEAM_TEST_REPO_ROOT}/Inkbeam.xcodeproj/channel")"
      case "\${derived_data}" in
        */VerifyInkbeam-Stable) artifact=stable ;;
        */VerifyInkbeam-RC) artifact=beta ;;
        *) exit 98 ;;
      esac
      print "build:\${channel}:\${artifact}" >>"\${INKBEAM_ORDER_EVENTS}"
      if [[ "\${artifact}" == beta && "\${INKBEAM_ORDER_BETA_FAILURE_STAGE:-}" == build ]]; then
        exit 72
      fi
      app="\${derived_data}/Build/Products/Debug/Inkbeam.app"
      mkdir -p "\${app}/Contents/MacOS" "\${app}/Contents/Helpers" "\${app}/Contents/Resources/Editor"
      print '#!/bin/zsh' >"\${app}/Contents/MacOS/Inkbeam"
      print '#!/bin/zsh' >"\${app}/Contents/Helpers/InkbeamNativeHost"
      chmod +x "\${app}/Contents/MacOS/Inkbeam" "\${app}/Contents/Helpers/InkbeamNativeHost"
      : >"\${app}/Contents/Resources/Assets.car"
      : >"\${app}/Contents/Resources/Editor/index.html"
      : >"\${app}/Contents/Info.plist"
      cp "\${INKBEAM_TEST_REPO_ROOT}/Config/chrome-extension-key.b64" "\${app}/Contents/Resources/chrome-extension-key.b64"
    fi
    ;;
  rm)
    cleanup_target="\${@[-1]}"
    case "\${cleanup_target}" in
      "\${INKBEAM_TEST_REPO_ROOT}/tmp/inkbeam-verify."*)
        print 'cleanup:attempt' >>"\${INKBEAM_ORDER_EVENTS}"
        if [[ "\${INKBEAM_ORDER_BETA_FAILURE_STAGE:-}" == cleanup \
          && ! -f "\${INKBEAM_TEST_REPO_ROOT}/cleanup-failed-once" ]]; then
          : >"\${INKBEAM_TEST_REPO_ROOT}/cleanup-failed-once"
          print 'cleanup:failed' >>"\${INKBEAM_ORDER_EVENTS}"
          exit 75
        fi
        /bin/rm "\${@}"
        print 'cleanup:removed' >>"\${INKBEAM_ORDER_EVENTS}"
        print 'temporary-cleanup-complete'
        ;;
      *)
        /bin/rm "\${@}"
        ;;
    esac
    ;;
  sw_vers)
    print '15.0'
    ;;
  pgrep)
    exit 1
    ;;
  plutil)
    case "\${2:-}" in
      CFBundleIdentifier) print 'dev.gihwan.inkbeam' ;;
      CFBundleShortVersionString) print '0.2.0' ;;
      LSMinimumSystemVersion) print '15.0' ;;
      *) exit 94 ;;
    esac
    ;;
  codesign)
    exit 0
    ;;
  *)
    exit 95
    ;;
esac
`,
    0o755,
  );

  for (const command of [
    "node",
    "pnpm",
    "xcodegen",
    "xcodebuild",
    "rm",
    "sw_vers",
    "pgrep",
    "plutil",
    "codesign",
  ]) {
    await fs.symlink("tool-stub", path.join(binPath, command));
  }

  assert.equal((await fs.stat(verifierPath)).isFile(), true);
  await assert.rejects(fs.lstat(generatedProjectPath), { code: "ENOENT" });

  const execution = spawnSync("/bin/zsh", [verifierPath], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${binPath}:${process.env.PATH}`,
      TMPDIR: temporaryPath,
      INKBEAM_ORDER_EVENTS: eventsPath,
      INKBEAM_TEST_REPO_ROOT: root,
    },
  });

  assert.equal(
    execution.status,
    0,
    `fresh canonical verification failed\nstdout:\n${execution.stdout}\nstderr:\n${execution.stderr}`,
  );
  const events = (await fs.readFile(eventsPath, "utf8")).trim().split("\n");
  assert.deepEqual(events, [
    "generate:stable",
    "scanner",
    "pnpm-test-release",
    "build:stable:stable",
    "privacy:stable:stable",
    "generate:beta",
    "build:beta:beta",
    "privacy:beta:beta",
    "generate:stable",
    "cleanup:attempt",
    "cleanup:removed",
  ]);
  const restoreOutputIndex = execution.stdout.lastIndexOf(
    "==> Restore the generated Stable Xcode project",
  );
  const successOutputIndex = execution.stdout.indexOf(
    "Inkbeam automated verification passed.",
  );
  const cleanupOutputIndex = execution.stdout.indexOf("temporary-cleanup-complete");
  assert.ok(restoreOutputIndex >= 0, "Stable restore output is missing");
  assert.ok(successOutputIndex > restoreOutputIndex, "success was printed before Stable restore");
  assert.ok(cleanupOutputIndex > restoreOutputIndex, "temporary cleanup output is missing");
  assert.ok(successOutputIndex > cleanupOutputIndex, "success was printed before temporary cleanup");
  assert.equal(events.filter((event) => event === "cleanup:removed").length, 1);
  assert.equal((await fs.lstat(generatedProjectPath)).isFile(), true);

  await fs.rm(generatedProjectPath);
  await fs.writeFile(eventsPath, "");
  const failedExecution = spawnSync("/bin/zsh", [verifierPath], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${binPath}:${process.env.PATH}`,
      TMPDIR: temporaryPath,
      INKBEAM_ORDER_EVENTS: eventsPath,
      INKBEAM_ORDER_SCANNER_FAILURE: "73",
      INKBEAM_TEST_REPO_ROOT: root,
    },
  });

  assert.equal(failedExecution.status, 73);
  assert.deepEqual(
    (await fs.readFile(eventsPath, "utf8")).trim().split("\n"),
    [
      "generate:stable",
      "scanner",
      "cleanup:attempt",
      "cleanup:removed",
      "generate:stable",
    ],
  );

  for (const [failureStage, expectedStatus, expectedTail] of [
    ["generate", 71, [
      "generate:beta",
      "cleanup:attempt",
      "cleanup:removed",
      "generate:stable",
    ]],
    ["build", 72, [
      "generate:beta",
      "build:beta:beta",
      "cleanup:attempt",
      "cleanup:removed",
      "generate:stable",
    ]],
    ["privacy", 73, [
      "generate:beta",
      "build:beta:beta",
      "privacy:beta:beta",
      "cleanup:attempt",
      "cleanup:removed",
      "generate:stable",
    ]],
    ["restore", 74, [
      "generate:stable",
      "cleanup:attempt",
      "cleanup:removed",
      "generate:stable",
    ]],
  ]) {
    await fs.writeFile(eventsPath, "");
    const betaFailure = spawnSync("/bin/zsh", [verifierPath], {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${binPath}:${process.env.PATH}`,
        TMPDIR: temporaryPath,
        INKBEAM_ORDER_EVENTS: eventsPath,
        INKBEAM_ORDER_BETA_FAILURE_STAGE: failureStage,
        INKBEAM_TEST_REPO_ROOT: root,
      },
    });

    assert.equal(betaFailure.status, expectedStatus, `${failureStage} status was not preserved`);
    const failureEvents = (await fs.readFile(eventsPath, "utf8")).trim().split("\n");
    assert.deepEqual(
      failureEvents.slice(-expectedTail.length),
      expectedTail,
      `${failureStage} did not restore Stable\nstdout:\n${betaFailure.stdout}\nstderr:\n${betaFailure.stderr}`,
    );
    assert.doesNotMatch(betaFailure.stdout, /Inkbeam automated verification passed/);
  }

  await fs.writeFile(eventsPath, "");
  const cleanupFailure = spawnSync("/bin/zsh", [verifierPath], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      PATH: `${binPath}:${process.env.PATH}`,
      TMPDIR: temporaryPath,
      INKBEAM_ORDER_EVENTS: eventsPath,
      INKBEAM_ORDER_BETA_FAILURE_STAGE: "cleanup",
      INKBEAM_TEST_REPO_ROOT: root,
    },
  });
  assert.equal(cleanupFailure.status, 75, "temporary cleanup failure status was not preserved");
  assert.doesNotMatch(cleanupFailure.stdout, /Inkbeam automated verification passed/);
  assert.equal(
    cleanupFailure.stdout.match(/temporary-cleanup-complete/g)?.length ?? 0,
    1,
    "only the successful fallback cleanup may report completion",
  );
  const cleanupFailureEvents = (await fs.readFile(eventsPath, "utf8")).trim().split("\n");
  assert.deepEqual(cleanupFailureEvents.slice(-5), [
    "generate:stable",
    "cleanup:attempt",
    "cleanup:failed",
    "cleanup:attempt",
    "cleanup:removed",
  ]);
});

test("privacy verification preserves source mode and pins each built artifact channel", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "inkbeam-privacy-channel-test."));
  t.after(() => fs.rm(root, { recursive: true, force: true }));

  const stableApp = path.join(root, "Stable.app");
  const betaApp = path.join(root, "ReleaseCandidate.app");
  const privacyVerifierPath = path.join(root, "Scripts/verify-privacy.sh");
  const sourceInfoPlistPath = path.join(root, "Config/Inkbeam-Info.plist");
  const extensionManifest = JSON.stringify({
    manifest_version: 3,
    permissions: ["activeTab", "nativeMessaging"],
    background: { service_worker: "service-worker.js", type: "module" },
    content_security_policy: {
      extension_pages: "default-src 'none'; script-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-src 'none'; img-src 'self'; style-src 'self'",
    },
  });
  await Promise.all([
    writeFixtureFile(
      root,
      "Scripts/verify-privacy.sh",
      await fs.readFile(privacyVerifierSourcePath, "utf8"),
      0o755,
    ),
    writeFixtureFile(
      root,
      "Packages/editor/dist/index.html",
      `<!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; connect-src 'none'; object-src 'none'; base-uri 'none'; frame-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'"><script src="./assets/index-fixture.js"></script><link rel="stylesheet" href="./assets/index-fixture.css">`,
    ),
    writeFixtureFile(root, "Packages/editor/dist/assets/index-fixture.js", "export {};\n"),
    writeFixtureFile(root, "Packages/editor/dist/assets/index-fixture.css", "body {}\n"),
    writeFixtureFile(root, "Packages/chrome-extension/public/manifest.json", extensionManifest),
    writeFixtureFile(root, "Packages/chrome-extension/dist/manifest.json", extensionManifest),
    writeFixtureFile(root, "Packages/chrome-extension/dist/service-worker.js", "export {};\n"),
    fs.mkdir(path.join(root, "Packages/editor/src"), { recursive: true }),
    fs.mkdir(path.join(root, "Packages/chrome-extension/src"), { recursive: true }),
    writeUpdaterInfoPlistFile(
      sourceInfoPlistPath,
      "$(INKBEAM_RELEASE_CHANNEL_NAME)",
      "$(INKBEAM_APPCAST_URL)",
      "$(INKBEAM_SPARKLE_PUBLIC_KEY)",
    ),
    writeUpdaterInfoPlist(
      stableApp,
      "Stable",
      "https://gihwan-dev.github.io/inkbeam/appcast.xml",
    ),
    writeUpdaterInfoPlist(
      betaApp,
      "Release Candidate",
      "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml",
    ),
  ]);

  const source = runPrivacyVerifier(privacyVerifierPath, root);
  assert.equal(source.status, 0, source.stderr);
  const stable = runPrivacyVerifier(privacyVerifierPath, root, "stable", stableApp);
  assert.equal(stable.status, 0, stable.stderr);
  const beta = runPrivacyVerifier(privacyVerifierPath, root, "beta", betaApp);
  assert.equal(beta.status, 0, beta.stderr);

  for (const [expectedChannel, artifact] of [
    ["stable", betaApp],
    ["beta", stableApp],
  ]) {
    const swapped = runPrivacyVerifier(privacyVerifierPath, root, expectedChannel, artifact);
    assert.notEqual(swapped.status, 0, "swapped channel/artifact must fail closed");
    assert.match(swapped.stderr, /Unexpected effective Inkbeam release channel\/feed/);
  }

  for (const malformedArguments of [
    [stableApp],
    ["nightly", stableApp],
    ["stable", stableApp, "extra"],
  ]) {
    const malformed = runPrivacyVerifier(privacyVerifierPath, root, ...malformedArguments);
    assert.equal(malformed.status, 64, `malformed arguments must fail 64: ${malformedArguments}`);
  }

  for (const [releaseChannel, feedURL, publicKey, expectedError] of [
    [
      "Stable",
      "$(INKBEAM_APPCAST_URL)",
      "$(INKBEAM_SPARKLE_PUBLIC_KEY)",
      /Unexpected source InkbeamReleaseChannel/,
    ],
    [
      "$(INKBEAM_RELEASE_CHANNEL_NAME)",
      "https://example.invalid/appcast.xml",
      "$(INKBEAM_SPARKLE_PUBLIC_KEY)",
      /Unexpected source SUFeedURL/,
    ],
    [
      "$(INKBEAM_RELEASE_CHANNEL_NAME)",
      "$(INKBEAM_APPCAST_URL)",
      "not-the-build-placeholder",
      /Unexpected source SUPublicEDKey/,
    ],
  ]) {
    await writeUpdaterInfoPlistFile(
      sourceInfoPlistPath,
      releaseChannel,
      feedURL,
      publicKey,
    );
    const malformedSource = runPrivacyVerifier(privacyVerifierPath, root);
    assert.notEqual(malformedSource.status, 0, "malformed source placeholder must fail");
    assert.match(malformedSource.stderr, expectedError);
  }
});

async function writeUpdaterInfoPlist(appPath, releaseChannel, feedURL) {
  await writeUpdaterInfoPlistFile(
    path.join(appPath, "Contents/Info.plist"),
    releaseChannel,
    feedURL,
    "fixture-public-key",
  );
}

async function writeUpdaterInfoPlistFile(infoPlistPath, releaseChannel, feedURL, publicKey) {
  await fs.mkdir(path.dirname(infoPlistPath), { recursive: true });
  await fs.writeFile(infoPlistPath, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>InkbeamReleaseChannel</key><string>${releaseChannel}</string>
<key>SUFeedURL</key><string>${feedURL}</string>
<key>SUPublicEDKey</key><string>${publicKey}</string>
<key>SUScheduledCheckInterval</key><integer>86400</integer>
<key>SUAutomaticallyUpdate</key><false/>
<key>SUAllowsAutomaticUpdates</key><false/>
<key>SUEnableSystemProfiling</key><false/>
<key>SUEnableJavaScript</key><false/>
<key>SUShowReleaseNotes</key><true/>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
</dict></plist>
`);
}

function runPrivacyVerifier(verifierPath, cwd, ...arguments_) {
  return spawnSync("/bin/zsh", [verifierPath, ...arguments_], {
    cwd,
    encoding: "utf8",
  });
}

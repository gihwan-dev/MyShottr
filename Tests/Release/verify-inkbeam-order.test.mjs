import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const repositoryRoot = path.resolve(import.meta.dirname, "../..");
const verifierSourcePath = path.join(repositoryRoot, "Scripts/verify-inkbeam.sh");

async function writeFixtureFile(root, relativePath, contents = "fixture\n", mode) {
  const absolutePath = path.join(root, relativePath);
  await fs.mkdir(path.dirname(absolutePath), { recursive: true });
  await fs.writeFile(absolutePath, contents);
  if (mode !== undefined) await fs.chmod(absolutePath, mode);
}

test("fresh canonical verification generates the project once before every scanner path", async (t) => {
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
    writeFixtureFile(root, "Scripts/verify-privacy.sh", "#!/bin/zsh\nexit 0\n", 0o755),
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
    print 'xcodegen' >>"\${INKBEAM_ORDER_EVENTS}"
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
      app="\${INKBEAM_TEST_REPO_ROOT}/DerivedData/VerifyInkbeam/Build/Products/Debug/Inkbeam.app"
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
  assert.deepEqual(events, ["xcodegen", "scanner", "pnpm-test-release"]);
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
    ["xcodegen", "scanner"],
  );
});

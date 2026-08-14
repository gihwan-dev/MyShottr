import assert from "node:assert/strict";
import childProcess, { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

import { contractFor } from "../../Scripts/release/release-contract.mjs";
import {
  completePhase,
  createReleaseState,
  loadReleaseState,
  recordNotarizationStatus,
  recordNotarizationSubmission,
  saveReleaseState,
  statePathFor,
  validateReleaseState,
} from "../../Scripts/release/release-state.mjs";

const SHA = "0123456789abcdef0123456789abcdef01234567";
const OTHER_SHA = "89abcdef0123456789abcdef0123456789abcdef";
const THIRD_SHA = "fedcba9876543210fedcba9876543210fedcba98";
const FOURTH_SHA = "456789abcdef0123456789abcdef0123456789ab";
const FIFTH_SHA = "56789abcdef0123456789abcdef0123456789abc";
const SIXTH_SHA = "6789abcdef0123456789abcdef0123456789abcd";
const DMG_SIGNATURE = Buffer.alloc(64, 7).toString("base64");
const STATE_MODULE_URL = new URL(
  "../../Scripts/release/release-state.mjs",
  import.meta.url,
).href;
const STATE_MODULE_PATH = fileURLToPath(STATE_MODULE_URL);
const INTERNAL_WRITE_MODE = "--internal-write";
const INTERNAL_WRITE_GUARD_ENV = "INKBEAM_RELEASE_STATE_INTERNAL_GUARD";
const TIMESTAMPS = {
  preflight: "2026-08-14T01:00:00.000Z",
  packaged: "2026-08-14T01:01:00.000Z",
  submitted: "2026-08-14T01:02:00.000Z",
  notarized: "2026-08-14T01:03:00.000Z",
  sealed: "2026-08-14T01:04:00.000Z",
  candidatePublished: "2026-08-14T01:05:00.000Z",
  publicVerified: "2026-08-14T01:06:00.000Z",
  betaFeedPrepared: "2026-08-14T01:07:00.000Z",
  betaFeedPublished: "2026-08-14T01:08:00.000Z",
  acceptanceRecorded: "2026-08-14T01:09:00.000Z",
  completed: "2026-08-14T01:10:00.000Z",
  stableFeedPrepared: "2026-08-14T01:10:00.000Z",
  finalPromoted: "2026-08-14T01:11:00.000Z",
  stableFeedPublished: "2026-08-14T01:12:00.000Z",
  stableCompleted: "2026-08-14T01:13:00.000Z",
};

function initialState(tag = "v0.2.0-rc.1") {
  return createReleaseState({
    contract: contractFor(tag),
    source: {
      branch: "worktree/official-release-pipeline",
      sha: SHA,
    },
    identity: {
      teamID: "SLVS4WF9U2",
      signingIdentity: "Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)",
      appBundleID: "dev.gihwan.inkbeam",
      helperBundleID: "dev.gihwan.inkbeam.nativehost",
    },
  });
}

function readyForNotarization(tag = "v0.2.0-rc.1") {
  return completePhase(
    completePhase(initialState(tag), "preflight", TIMESTAMPS.preflight),
    "packaged",
    TIMESTAMPS.packaged,
  );
}

function acceptedNotarizationState(tag = "v0.2.0-rc.1") {
  return recordNotarizationStatus(
    recordNotarizationSubmission(
      readyForNotarization(tag),
      "11111111-2222-3333-4444-555555555555",
      TIMESTAMPS.submitted,
    ),
    "Accepted",
    TIMESTAMPS.notarized,
  );
}

function exactArtifacts(tag = "v0.2.0-rc.1") {
  const contract = contractFor(tag);
  return {
    dmg: {
      fileName: contract.dmg,
      byteLength: 12_345_678,
      sha256: "a".repeat(64),
      edSignature: DMG_SIGNATURE,
      verificationSummary:
        "codesign=PASS; notarization=PASS; staple=PASS; gatekeeper=PASS",
    },
    chromeZip: {
      fileName: contract.chromeZip,
      byteLength: 234_567,
      sha256: "b".repeat(64),
      verificationSummary: "identity=PASS; contents=PASS",
    },
  };
}

function sealedState(tag = "v0.2.0-rc.1") {
  const state = structuredClone(acceptedNotarizationState(tag));
  state.artifacts = exactArtifacts(tag);
  return completePhase(state, "sealed", TIMESTAMPS.sealed);
}

function candidatePublishedState(tag = "v0.2.0-rc.1") {
  const contract = contractFor(tag);
  const state = structuredClone(sealedState(tag));
  state.publication = {
    github: {
      candidate: {
        releaseID: 123456,
        tagCommitID: SHA,
        url: `https://github.com/gihwan-dev/inkbeam/releases/tag/${tag}`,
        draft: false,
        prerelease: true,
        makeLatest: false,
        title: contract.releaseTitle,
      },
    },
  };
  return completePhase(
    state,
    "candidatePublished",
    TIMESTAMPS.candidatePublished,
  );
}

function publiclyVerifiedState(tag = "v0.2.0-rc.1") {
  const contract = contractFor(tag);
  const state = structuredClone(candidatePublishedState(tag));
  state.publication.publicURLs = {
    release: `https://github.com/gihwan-dev/inkbeam/releases/tag/${tag}`,
    dmg: `https://github.com/gihwan-dev/inkbeam/releases/download/${tag}/${contract.dmg}`,
    chromeZip: `https://github.com/gihwan-dev/inkbeam/releases/download/${tag}/${contract.chromeZip}`,
    checksums: `https://github.com/gihwan-dev/inkbeam/releases/download/${tag}/SHA256SUMS.txt`,
  };
  return completePhase(state, "publicVerified", TIMESTAMPS.publicVerified);
}

function betaFeedPublishedState(tag = "v0.2.0-rc.1") {
  let state = completePhase(
    publiclyVerifiedState(tag),
    "betaFeedPrepared",
    TIMESTAMPS.betaFeedPrepared,
  );
  state = structuredClone(state);
  state.publication.publicURLs.betaFeed =
    "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml";
  state.publication.pages = {
    beta: [{
      previousCommitID: OTHER_SHA,
      publishedCommitID: THIRD_SHA,
    }],
  };
  return completePhase(state, "betaFeedPublished", TIMESTAMPS.betaFeedPublished);
}

function acceptedCandidateState(tag = "v0.2.0-rc.1") {
  const state = structuredClone(betaFeedPublishedState(tag));
  state.acceptance = {
    candidate: {
      path: `docs/testing/releases/${tag}.md`,
      result: "PASS",
    },
  };
  return completePhase(
    state,
    "acceptanceRecorded",
    TIMESTAMPS.acceptanceRecorded,
  );
}

function completedRCState() {
  const state = structuredClone(acceptedCandidateState());
  state.acceptance.complete = {
    path: "docs/testing/releases/v0.2.0-rc.1.md",
    result: "PASS",
  };
  return completePhase(state, "completed", TIMESTAMPS.completed);
}

function stableReleaseStates() {
  const accepted = acceptedCandidateState("v0.2.0");
  let state = completePhase(
    accepted,
    "stableFeedPrepared",
    TIMESTAMPS.stableFeedPrepared,
  );
  const prepared = state;
  state = structuredClone(state);
  state.publication.github.promoted = {
    releaseID: 123456,
    tagCommitID: SHA,
    url: "https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0",
    draft: false,
    prerelease: false,
    makeLatest: true,
    title: "Inkbeam v0.2.0",
  };
  state = completePhase(state, "finalPromoted", TIMESTAMPS.finalPromoted);
  const promoted = state;
  state = structuredClone(state);
  state.publication.publicURLs.stableFeed =
    "https://gihwan-dev.github.io/inkbeam/appcast.xml";
  state.publication.pages.stable = [{
    previousCommitID: FOURTH_SHA,
    publishedCommitID: FIFTH_SHA,
  }];
  state = completePhase(
    state,
    "stableFeedPublished",
    TIMESTAMPS.stableFeedPublished,
  );
  const published = state;
  state = structuredClone(state);
  state.acceptance.complete = {
    path: "docs/testing/releases/v0.2.0.md",
    result: "PASS",
  };
  const completed = completePhase(state, "completed", TIMESTAMPS.stableCompleted);
  return { accepted, prepared, promoted, published, completed };
}

function stableCompletedState() {
  return stableReleaseStates().completed;
}

function writeStateFixture(filePath, state) {
  fs.writeFileSync(filePath, `${JSON.stringify(state)}\n`);
}

function writePreload(filePath, source) {
  fs.writeFileSync(filePath, source, { mode: 0o600 });
  return `--import=${pathToFileURL(filePath).href}`;
}

function withEnvironmentVariable(key, value, operation) {
  const previous = process.env[key];
  process.env[key] = value;
  try {
    return operation();
  } finally {
    if (previous === undefined) delete process.env[key];
    else process.env[key] = previous;
  }
}

function runInternalWriter({
  repositoryRoot,
  payload,
  token = "test-internal-token",
  argv = [],
  environment = {},
}) {
  return spawnSync(
    process.execPath,
    [STATE_MODULE_PATH, INTERNAL_WRITE_MODE, token, ...argv],
    {
      encoding: "utf8",
      input: typeof payload === "string" ? payload : JSON.stringify(payload),
      env: {
        ...process.env,
        [INTERNAL_WRITE_GUARD_ENV]: token,
        ...environment,
      },
      cwd: repositoryRoot,
    },
  );
}

function surfaceIdentityFor(repositoryRoot, tag = "v0.2.0-rc.1") {
  const evidenceDirectory = path.dirname(statePathFor(repositoryRoot, tag));
  const directoryPaths = [
    repositoryRoot,
    path.join(repositoryRoot, "build"),
    path.join(repositoryRoot, "build/release-evidence"),
    evidenceDirectory,
  ];
  const identity = (surfacePath) => {
    const stats = fs.lstatSync(surfacePath);
    return { device: String(stats.dev), inode: String(stats.ino) };
  };
  return {
    evidenceDirectories: directoryPaths.map(identity),
    writerLock: identity(path.join(evidenceDirectory, "release-state.lock")),
  };
}

function pausingWriterPreload({ repositoryRoot, readySignal, releaseSignal, label }) {
  const preloadPath = path.join(repositoryRoot, `${label}-pause-preload.mjs`);
  return writePreload(preloadPath, `
import fs from "node:fs";
import path from "node:path";
const originalRenameSync = fs.renameSync;
let paused = false;
fs.renameSync = function(source, destination, ...rest) {
  if (
    !paused &&
    path.basename(destination) === "release-state.json" &&
    path.basename(source).startsWith(".release-state.")
  ) {
    paused = true;
    fs.writeFileSync(${JSON.stringify(readySignal)}, String(process.pid));
    const waiter = new Int32Array(new SharedArrayBuffer(4));
    const deadline = Date.now() + 5_000;
    while (!fs.existsSync(${JSON.stringify(releaseSignal)})) {
      if (Date.now() >= deadline) throw new Error("test preload timed out");
      Atomics.wait(waiter, 0, 0, 10);
    }
  }
  return originalRenameSync.call(this, source, destination, ...rest);
};
`);
}

function interferencePreload({ repositoryRoot, destination, scenario }) {
  const preloadPath = path.join(repositoryRoot, `${scenario}-interference-preload.mjs`);
  return writePreload(preloadPath, `
import fs from "node:fs";
import path from "node:path";
const destination = ${JSON.stringify(destination)};
const evidenceDirectory = path.dirname(destination);
const originalFsyncSync = fs.fsyncSync;
let interfered = false;
fs.fsyncSync = function(descriptor) {
  const result = originalFsyncSync.call(this, descriptor);
  if (
    !interfered &&
    fs.readdirSync(evidenceDirectory).some(
      (entry) => entry.startsWith(".release-state.") && entry.endsWith(".tmp"),
    )
  ) {
    interfered = true;
    if (${JSON.stringify(scenario)} === "changes") {
      fs.renameSync(destination, destination + ".displaced");
    }
    fs.writeFileSync(destination, "foreign writer contents\\n", { mode: 0o600 });
  }
  return result;
};
`);
}

async function waitForFile(filePath, timeoutMilliseconds = 5_000) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (!fs.existsSync(filePath)) {
    if (Date.now() >= deadline) {
      throw new Error(`timed out waiting for ${filePath}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

function saveProcessSource({ repositoryRoot, stateFixture }) {
  return `
import fs from "node:fs";
const { saveReleaseState } = await import(${JSON.stringify(STATE_MODULE_URL)});
const state = JSON.parse(fs.readFileSync(${JSON.stringify(stateFixture)}, "utf8"));
try {
  saveReleaseState(${JSON.stringify(repositoryRoot)}, state);
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
`;
}

async function killWriterHoldingLock({ repositoryRoot, state, t, label }) {
  const stateFixture = path.join(repositoryRoot, `${label}-state.json`);
  const readySignal = path.join(repositoryRoot, `${label}-ready`);
  const releaseSignal = path.join(repositoryRoot, `${label}-release`);
  const preloadOption = pausingWriterPreload({
    repositoryRoot,
    readySignal,
    releaseSignal,
    label,
  });
  writeStateFixture(stateFixture, state);

  const writer = spawn(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      saveProcessSource({
        repositoryRoot,
        stateFixture,
      }),
    ],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        NODE_OPTIONS: [process.env.NODE_OPTIONS, preloadOption]
          .filter(Boolean)
          .join(" "),
      },
    },
  );
  let writerError = "";
  writer.stderr.setEncoding("utf8");
  writer.stderr.on("data", (chunk) => { writerError += chunk; });
  let exited = false;
  t.after(() => {
    if (!exited) writer.kill("SIGKILL");
  });
  const exit = once(writer, "exit");

  await waitForFile(readySignal);
  const ownerPID = Number(fs.readFileSync(readySignal, "utf8"));
  assert.equal(Number.isSafeInteger(ownerPID), true);
  process.kill(ownerPID, "SIGKILL");
  const [status, signal] = await exit;
  exited = true;
  assert.equal(status, 1, writerError);
  assert.equal(signal, null, writerError);
  assert.match(writerError, /release state internal writer terminated abnormally/i);

  const evidenceDirectory = path.dirname(
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  return {
    evidenceDirectory,
    lockPath: path.join(evidenceDirectory, "release-state.lock"),
    ownerPID,
  };
}

test("creates a state containing only approved release identity and source evidence", () => {
  const state = initialState();

  assert.deepEqual(state, {
    schemaVersion: 1,
    contract: contractFor("v0.2.0-rc.1"),
    source: {
      branch: "worktree/official-release-pipeline",
      sha: SHA,
    },
    identity: {
      teamID: "SLVS4WF9U2",
      signingIdentity: "Developer ID Application: GIHWAN CHOI (SLVS4WF9U2)",
      appBundleID: "dev.gihwan.inkbeam",
      helperBundleID: "dev.gihwan.inkbeam.nativehost",
    },
    phases: {},
  });
  assert.equal(validateReleaseState(state, contractFor("v0.2.0-rc.1")), true);
});

test("rejects unknown state keys at every schema level", () => {
  const submitted = recordNotarizationSubmission(
    readyForNotarization(),
    "11111111-2222-3333-4444-555555555555",
    TIMESTAMPS.submitted,
  );
  const mutations = [
    ["state", "command", initialState(), (state) => { state.command = "echo unexpected"; }],
    ["contract", "extra", initialState(), (state) => { state.contract.extra = true; }],
    ["source", "extra", initialState(), (state) => { state.source.extra = true; }],
    ["identity", "profile", initialState(), (state) => { state.identity.profile = "alternate"; }],
    ["notarization", "extra", submitted, (state) => { state.notarization.extra = true; }],
  ];

  for (const [level, key, source, mutate] of mutations) {
    const state = structuredClone(source);
    mutate(state);
    assert.throws(
      () => validateReleaseState(state),
      new RegExp(`unknown ${level} key.*${key}`, "i"),
    );
  }

  const phaseMutation = structuredClone(initialState());
  phaseMutation.phases.uploadedSomewhere = TIMESTAMPS.packaged;
  assert.throws(
    () => validateReleaseState(phaseMutation),
    /unknown release phase.*uploadedSomewhere/i,
  );
});

test("rejects phase skips and unknown phases", () => {
  const state = initialState();

  assert.throws(
    () => completePhase(state, "packaged", TIMESTAMPS.packaged),
    /cannot complete phase packaged before preflight/i,
  );
  assert.throws(
    () => completePhase(state, "uploadedSomewhere", TIMESTAMPS.packaged),
    /unknown release phase/i,
  );

  const malformedPersistedState = structuredClone(state);
  malformedPersistedState.phases.finalPromoted = TIMESTAMPS.packaged;
  assert.throws(
    () => validateReleaseState(malformedPersistedState),
    /cannot complete phase finalPromoted before betaFeedPublished/i,
  );
});

test("records one notarization submission ID and never permits another", () => {
  const submitted = recordNotarizationSubmission(
    readyForNotarization(),
    "11111111-2222-3333-4444-555555555555",
    TIMESTAMPS.submitted,
  );

  assert.deepEqual(submitted.notarization, {
    submissionID: "11111111-2222-3333-4444-555555555555",
    status: "Submitted",
  });
  assert.equal(submitted.phases.notarizationSubmitted, TIMESTAMPS.submitted);
  assert.throws(
    () =>
      recordNotarizationSubmission(
        submitted,
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        TIMESTAMPS.notarized,
      ),
    /notarization submission ID already exists/i,
  );
});

test("an accepted notarization completes the phase but non-terminal status does not", () => {
  const submitted = recordNotarizationSubmission(
    readyForNotarization(),
    "11111111-2222-3333-4444-555555555555",
    TIMESTAMPS.submitted,
  );
  const processing = recordNotarizationStatus(submitted, "In Progress");
  assert.equal(processing.notarization.status, "In Progress");
  assert.equal(processing.phases.notarized, undefined);

  const accepted = recordNotarizationStatus(
    processing,
    "Accepted",
    TIMESTAMPS.notarized,
  );
  assert.equal(accepted.notarization.status, "Accepted");
  assert.equal(accepted.phases.notarized, TIMESTAMPS.notarized);
});

test("rejects secret material before it can be persisted", () => {
  const rootSecret = structuredClone(initialState());
  rootSecret.githubToken = "ghp_do-not-store-this";
  assert.throws(() => validateReleaseState(rootSecret), /secret material.*githubToken/i);

  const nestedSecret = structuredClone(initialState());
  nestedSecret.identity.certificatePassword = "do-not-store-this";
  assert.throws(
    () => validateReleaseState(nestedSecret),
    /secret material.*certificatePassword/i,
  );
});

test("rejects a tag or immutable contract mismatch", () => {
  const wrongBuild = structuredClone(initialState());
  wrongBuild.contract.build = 99;
  assert.throws(() => validateReleaseState(wrongBuild), /release contract mismatch/i);

  assert.throws(
    () => validateReleaseState(initialState(), contractFor("v0.2.0-rc.2")),
    /release contract mismatch/i,
  );
});

test("accepts the exact immutable contract independent of JSON key order", () => {
  const state = structuredClone(initialState());
  state.contract = {
    prerelease: true,
    releaseTitle: "Inkbeam v0.2.0-rc.1",
    chromeZip: "Inkbeam-Chrome-0.2.0-rc.1.zip",
    dmg: "Inkbeam-0.2.0-rc.1.dmg",
    channel: "beta",
    build: 2,
    version: "0.2.0",
    tag: "v0.2.0-rc.1",
  };

  assert.equal(validateReleaseState(state), true);
});

test("accepts only exact final DMG and Chrome ZIP metadata", () => {
  assert.equal(validateReleaseState(sealedState()), true);

  const mutations = [
    ["unknown artifact key", (state) => { state.artifacts.dmg.extra = true; }, /unknown DMG artifact key.*extra/i],
    ["wrong DMG filename", (state) => { state.artifacts.dmg.fileName = "other.dmg"; }, /DMG filename must match release contract/i],
    ["wrong Chrome filename", (state) => { state.artifacts.chromeZip.fileName = "other.zip"; }, /Chrome ZIP filename must match release contract/i],
    ["zero bytes", (state) => { state.artifacts.dmg.byteLength = 0; }, /byte length must be a positive integer/i],
    ["uppercase hash", (state) => { state.artifacts.chromeZip.sha256 = "A".repeat(64); }, /SHA-256 must be 64 lowercase hexadecimal/i],
    ["invalid EdDSA signature", (state) => { state.artifacts.dmg.edSignature = "not-base64"; }, /DMG EdDSA signature/i],
    ["missing verification summary", (state) => { state.artifacts.chromeZip.verificationSummary = ""; }, /verification summary is required/i],
    ["Chrome-only extra signature", (state) => { state.artifacts.chromeZip.edSignature = DMG_SIGNATURE; }, /unknown Chrome ZIP artifact key.*edSignature/i],
  ];

  for (const [label, mutate, expected] of mutations) {
    const state = structuredClone(sealedState());
    mutate(state);
    assert.throws(() => validateReleaseState(state), expected, label);
  }
});

test("accepts only exact GitHub and Pages public surfaces", () => {
  assert.equal(validateReleaseState(betaFeedPublishedState()), true);

  const mutations = [
    ["unknown publication key", (state) => { state.publication.other = {}; }, /unknown publication key.*other/i],
    ["wrong release origin", (state) => { state.publication.publicURLs.release = "https://example.com/v0.2.0-rc.1"; }, /public release URL does not match release contract/i],
    ["wrong asset tag", (state) => { state.publication.publicURLs.dmg = state.publication.publicURLs.dmg.replace("v0.2.0-rc.1", "v0.2.0-rc.2"); }, /public DMG URL does not match release contract/i],
    ["wrong asset filename", (state) => { state.publication.publicURLs.chromeZip = state.publication.publicURLs.chromeZip.replace("Inkbeam-Chrome-0.2.0-rc.1.zip", "other.zip"); }, /public Chrome ZIP URL does not match release contract/i],
    ["wrong Pages URL", (state) => { state.publication.publicURLs.betaFeed = "https://example.com/appcast-beta.xml"; }, /public beta feed URL does not match Inkbeam Pages/i],
    ["invalid Pages commit", (state) => { state.publication.pages.beta[0].publishedCommitID = "ABC123"; }, /Pages commit ID must be 40 lowercase hexadecimal/i],
    ["candidate is a draft", (state) => { state.publication.github.candidate.draft = true; }, /GitHub candidate must be non-draft, prerelease, and not latest/i],
    ["candidate title drift", (state) => { state.publication.github.candidate.title = "Inkbeam latest"; }, /GitHub candidate title must match release contract/i],
    ["unknown GitHub key", (state) => { state.publication.github.candidate.body = "extra"; }, /unknown GitHub release key.*body/i],
  ];

  for (const [label, mutate, expected] of mutations) {
    const state = structuredClone(betaFeedPublishedState());
    mutate(state);
    assert.throws(() => validateReleaseState(state), expected, label);
  }
});

test("accepts only the real release acceptance path and PASS result", () => {
  assert.equal(validateReleaseState(completedRCState()), true);

  const wrongPath = structuredClone(completedRCState());
  wrongPath.acceptance.candidate.path = "/tmp/acceptance.md";
  assert.throws(
    () => validateReleaseState(wrongPath),
    /acceptance path must be docs\/testing\/releases\/v0\.2\.0-rc\.1\.md/i,
  );

  const wrongResult = structuredClone(completedRCState());
  wrongResult.acceptance.complete.result = "SUCCESS";
  assert.throws(() => validateReleaseState(wrongResult), /acceptance result must be PASS/i);

  const unknown = structuredClone(completedRCState());
  unknown.acceptance.candidate.notes = "extra";
  assert.throws(
    () => validateReleaseState(unknown),
    /unknown acceptance record key.*notes/i,
  );
});

test("release phases require their matching persisted evidence", () => {
  assert.throws(
    () => completePhase(acceptedNotarizationState(), "sealed", TIMESTAMPS.sealed),
    /sealed phase requires exact final artifact metadata/i,
  );
  assert.throws(
    () => completePhase(sealedState(), "candidatePublished", TIMESTAMPS.candidatePublished),
    /candidatePublished phase requires GitHub candidate state/i,
  );
  assert.throws(
    () => completePhase(candidatePublishedState(), "publicVerified", TIMESTAMPS.publicVerified),
    /publicVerified phase requires exact public artifact URLs/i,
  );

  const betaPrepared = completePhase(
    publiclyVerifiedState(),
    "betaFeedPrepared",
    TIMESTAMPS.betaFeedPrepared,
  );
  assert.throws(
    () => completePhase(betaPrepared, "betaFeedPublished", TIMESTAMPS.betaFeedPublished),
    /betaFeedPublished phase requires Pages commit IDs and beta feed URL/i,
  );
  assert.throws(
    () => completePhase(betaFeedPublishedState(), "acceptanceRecorded", TIMESTAMPS.acceptanceRecorded),
    /acceptanceRecorded phase requires candidate acceptance PASS/i,
  );
  assert.throws(
    () => completePhase(acceptedCandidateState(), "completed", TIMESTAMPS.completed),
    /completed phase requires complete acceptance PASS/i,
  );
});

test("save rejects stale or rewritten release evidence", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-monotonic-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  const fullState = completedRCState();
  saveReleaseState(repositoryRoot, fullState);

  const regressions = [
    ["contract", (() => { const state = structuredClone(fullState); state.contract.build = 3; return state; })()],
    ["source", (() => {
      const state = structuredClone(fullState);
      state.source.sha = OTHER_SHA;
      state.publication.github.candidate.tagCommitID = OTHER_SHA;
      return state;
    })()],
    ["identity", (() => { const state = structuredClone(fullState); state.identity.teamID = "ABCDEFGHIJ"; return state; })()],
    ["phases", (() => { const state = structuredClone(fullState); state.phases.preflight = "2026-08-14T00:59:00.000Z"; return state; })()],
    ["artifacts", (() => { const state = structuredClone(fullState); state.artifacts.dmg.sha256 = "c".repeat(64); return state; })()],
    ["publication", sealedState()],
    ["acceptance", betaFeedPublishedState()],
  ];

  for (const [label, staleState] of regressions) {
    assert.throws(
      () => saveReleaseState(repositoryRoot, staleState),
      /release state (?:cannot remove|cannot change|cannot regress)|release contract mismatch/i,
      label,
    );
    assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), fullState);
  }
});

test("save rejects notarization status regression but permits verified append-only progress", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-progress-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  const submitted = recordNotarizationSubmission(
    readyForNotarization(),
    "11111111-2222-3333-4444-555555555555",
    TIMESTAMPS.submitted,
  );
  const processing = recordNotarizationStatus(submitted, "In Progress");
  saveReleaseState(repositoryRoot, submitted);
  saveReleaseState(repositoryRoot, processing);
  assert.throws(
    () => saveReleaseState(repositoryRoot, submitted),
    /release state cannot regress notarization status/i,
  );

  const states = [
    acceptedNotarizationState(),
    sealedState(),
    candidatePublishedState(),
    publiclyVerifiedState(),
    betaFeedPublishedState(),
    acceptedCandidateState(),
    completedRCState(),
  ];
  for (const state of states) saveReleaseState(repositoryRoot, state);
  saveReleaseState(repositoryRoot, completedRCState());

  assert.deepEqual(
    loadReleaseState(repositoryRoot, "v0.2.0-rc.1"),
    completedRCState(),
  );
});

test("Pages publication history permits a linked append but rejects rewrites and arbitrary SHAs", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-pages-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  const firstPublication = betaFeedPublishedState();
  saveReleaseState(repositoryRoot, firstPublication);

  const secondPublication = structuredClone(firstPublication);
  secondPublication.publication.pages.beta.push({
    previousCommitID: THIRD_SHA,
    publishedCommitID: FOURTH_SHA,
  });
  assert.equal(saveReleaseState(repositoryRoot, secondPublication), statePathFor(
    repositoryRoot,
    "v0.2.0-rc.1",
  ));

  const rewrittenHistory = structuredClone(secondPublication);
  rewrittenHistory.publication.pages.beta[0].publishedCommitID = FOURTH_SHA;
  rewrittenHistory.publication.pages.beta[1].previousCommitID = FOURTH_SHA;
  assert.throws(
    () => saveReleaseState(repositoryRoot, rewrittenHistory),
    /release state cannot change publication\.pages\.beta\.0\.publishedCommitID/i,
  );

  const disconnectedHistory = structuredClone(secondPublication);
  disconnectedHistory.publication.pages.beta.push({
    previousCommitID: OTHER_SHA,
    publishedCommitID: "c".repeat(40),
  });
  assert.throws(
    () => saveReleaseState(repositoryRoot, disconnectedHistory),
    /Pages beta transition must start from the previous published commit ID/i,
  );
});

test("exclusive writer lock lets only one concurrent process commit and cleans up", async (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-lock-race-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  saveReleaseState(repositoryRoot, initialState());
  const writerAState = completePhase(
    initialState(),
    "preflight",
    TIMESTAMPS.preflight,
  );
  const writerBState = completePhase(
    initialState(),
    "preflight",
    "2026-08-14T01:00:00.500Z",
  );
  const writerAFixture = path.join(repositoryRoot, "writer-a.json");
  const writerBFixture = path.join(repositoryRoot, "writer-b.json");
  const readySignal = path.join(repositoryRoot, "writer-a-ready");
  const releaseSignal = path.join(repositoryRoot, "writer-a-release");
  const preloadOption = pausingWriterPreload({
    repositoryRoot,
    readySignal,
    releaseSignal,
    label: "writer-a",
  });
  writeStateFixture(writerAFixture, writerAState);
  writeStateFixture(writerBFixture, writerBState);

  const writerA = spawn(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      saveProcessSource({
        repositoryRoot,
        stateFixture: writerAFixture,
      }),
    ],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      env: {
        ...process.env,
        NODE_OPTIONS: [process.env.NODE_OPTIONS, preloadOption]
          .filter(Boolean)
          .join(" "),
      },
    },
  );
  let writerAError = "";
  writerA.stderr.setEncoding("utf8");
  writerA.stderr.on("data", (chunk) => { writerAError += chunk; });
  const writerAExit = once(writerA, "exit");

  await waitForFile(readySignal);
  const writerB = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      saveProcessSource({ repositoryRoot, stateFixture: writerBFixture }),
    ],
    { encoding: "utf8" },
  );
  fs.writeFileSync(releaseSignal, "release");
  const [writerAStatus] = await writerAExit;

  assert.equal(writerAStatus, 0, writerAError);
  assert.equal(writerB.status, 1, writerB.stderr);
  assert.match(writerB.stderr, /release state writer lock is already held/i);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), writerAState);

  const staleRetry = spawnSync(
    process.execPath,
    [
      "--input-type=module",
      "-e",
      saveProcessSource({ repositoryRoot, stateFixture: writerBFixture }),
    ],
    { encoding: "utf8" },
  );
  assert.equal(staleRetry.status, 1, staleRetry.stderr);
  assert.match(staleRetry.stderr, /release state cannot change phases\.preflight/i);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), writerAState);

  const evidenceDirectory = path.dirname(
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  const lockStats = fs.lstatSync(path.join(evidenceDirectory, "release-state.lock"));
  assert.equal(lockStats.isFile(), true);
  assert.deepEqual(
    fs.readdirSync(evidenceDirectory).filter((entry) => entry.endsWith(".tmp")),
    [],
  );
});

test("a writer killed while holding the lock releases the kernel lock and the save resumes", async (t) => {
  const repositoryRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "inkbeam-lock-crash-"),
  );
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  saveReleaseState(repositoryRoot, initialState());

  const crashedState = completePhase(
    initialState(),
    "preflight",
    TIMESTAMPS.preflight,
  );
  const orphan = await killWriterHoldingLock({
    repositoryRoot,
    state: crashedState,
    t,
    label: "crashed-writer",
  });

  const lockStats = fs.lstatSync(orphan.lockPath);
  assert.equal(lockStats.isFile(), true);
  assert.equal(
    fs.readdirSync(orphan.evidenceDirectory).filter(
      (entry) => entry.endsWith(".tmp"),
    ).length,
    1,
  );

  const resumedState = completePhase(
    initialState(),
    "preflight",
    "2026-08-14T01:00:00.500Z",
  );
  assert.equal(
    saveReleaseState(repositoryRoot, resumedState),
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), resumedState);
  assert.equal(fs.lstatSync(orphan.lockPath).isFile(), true);
  assert.deepEqual(
    fs.readdirSync(orphan.evidenceDirectory).filter(
      (entry) => entry.endsWith(".tmp"),
    ),
    [],
  );
});

test("kernel writer lock is released when validation fails inside the critical section", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-lock-cleanup-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  const advanced = completePhase(initialState(), "preflight", TIMESTAMPS.preflight);
  saveReleaseState(repositoryRoot, advanced);
  assert.throws(
    () => saveReleaseState(repositoryRoot, initialState()),
    /release state cannot remove phases\.preflight/i,
  );

  const evidenceDirectory = path.dirname(
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  assert.equal(
    fs.lstatSync(path.join(evidenceDirectory, "release-state.lock")).isFile(),
    true,
  );
  assert.deepEqual(
    fs.readdirSync(evidenceDirectory).filter((entry) => entry.endsWith(".tmp")),
    [],
  );

  const resumed = completePhase(
    advanced,
    "packaged",
    TIMESTAMPS.packaged,
  );
  assert.equal(
    saveReleaseState(repositoryRoot, resumed),
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), resumed);
});

test("lockf launch and abnormal-exit failures are distinct and never mutate state", async (t) => {
  const fixtures = [
    {
      label: "missing",
      result: {
        error: Object.assign(new Error("spawn /usr/bin/lockf ENOENT"), {
          code: "ENOENT",
        }),
        status: null,
        signal: null,
        stdout: "",
        stderr: "",
      },
      expected: /release state lockf is unavailable/i,
    },
    {
      label: "empty failure",
      result: { status: 1, signal: null, stdout: "", stderr: "" },
      expected: /release state lockf failed with status 1/i,
    },
    {
      label: "stderr failure",
      result: {
        status: 64,
        signal: null,
        stdout: "",
        stderr: "fixture lockf failure\n",
      },
      expected: /fixture lockf failure/i,
    },
    {
      label: "signal",
      result: {
        status: null,
        signal: "SIGTERM",
        stdout: "",
        stderr: "",
      },
      expected: /release state lockf process terminated by signal SIGTERM/i,
    },
  ];

  for (const fixture of fixtures) {
    await t.test(fixture.label, (subtest) => {
      const repositoryRoot = fs.mkdtempSync(
        path.join(os.tmpdir(), `inkbeam-lockf-${fixture.label.replaceAll(" ", "-")}-`),
      );
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const before = initialState();
      const after = completePhase(before, "preflight", TIMESTAMPS.preflight);
      saveReleaseState(repositoryRoot, before);
      const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
      const beforeContents = fs.readFileSync(destination, "utf8");
      subtest.mock.method(childProcess, "spawnSync", () => fixture.result);

      assert.throws(
        () => saveReleaseState(repositoryRoot, after),
        fixture.expected,
      );
      assert.equal(fs.readFileSync(destination, "utf8"), beforeContents);
      assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), before);
      assert.deepEqual(
        fs.readdirSync(path.dirname(destination)).filter(
          (entry) => entry.endsWith(".tmp"),
        ),
        [],
      );
    });
  }
});

test("private writer rejects a bad guard or malformed input without state mutation", async (t) => {
  const fixtures = [
    {
      label: "bad guard",
      run: (repositoryRoot) => runInternalWriter({
        repositoryRoot,
        payload: { repositoryRoot, state: initialState() },
        environment: { [INTERNAL_WRITE_GUARD_ENV]: "different-guard" },
      }),
      expected: /internal writer guard mismatch/i,
    },
    {
      label: "malformed JSON",
      run: (repositoryRoot) => runInternalWriter({
        repositoryRoot,
        payload: "{not-json",
      }),
      expected: /internal writer input is invalid/i,
    },
    {
      label: "non-object payload",
      run: (repositoryRoot) => runInternalWriter({
        repositoryRoot,
        payload: [],
      }),
      expected: /internal payload must contain exactly repositoryRoot, state, and surfaceIdentity/i,
    },
    {
      label: "extra payload key",
      run: (repositoryRoot) => runInternalWriter({
        repositoryRoot,
        payload: { repositoryRoot, state: initialState(), extra: true },
      }),
      expected: /internal payload must contain exactly repositoryRoot, state, and surfaceIdentity/i,
    },
    {
      label: "extra argv",
      run: (repositoryRoot) => runInternalWriter({
        repositoryRoot,
        payload: { repositoryRoot, state: initialState() },
        argv: ["unexpected"],
      }),
      expected: /internal writer invocation is invalid/i,
    },
  ];

  for (const fixture of fixtures) {
    await t.test(fixture.label, () => {
      const repositoryRoot = fs.mkdtempSync(
        path.join(os.tmpdir(), `inkbeam-internal-${fixture.label.replaceAll(" ", "-")}-`),
      );
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const result = fixture.run(repositoryRoot);
      assert.equal(result.status, 1, result.stderr);
      assert.equal(result.signal, null, result.stderr);
      assert.match(result.stderr, fixture.expected);
      assert.equal(
        fs.existsSync(statePathFor(repositoryRoot, "v0.2.0-rc.1")),
        false,
      );
      const evidenceDirectory = path.dirname(
        statePathFor(repositoryRoot, "v0.2.0-rc.1"),
      );
      if (fs.existsSync(evidenceDirectory)) {
        assert.deepEqual(
          fs.readdirSync(evidenceDirectory).filter(
            (entry) => entry.endsWith(".tmp"),
          ),
          [],
        );
      }
    });
  }
});

test("private writer cannot bypass the kernel writer lock", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-internal-lock-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const before = initialState();
  const after = completePhase(before, "preflight", TIMESTAMPS.preflight);
  saveReleaseState(repositoryRoot, before);

  const result = runInternalWriter({
    repositoryRoot,
    payload: {
      repositoryRoot,
      state: after,
      surfaceIdentity: surfaceIdentityFor(repositoryRoot),
    },
  });
  assert.equal(result.status, 1, result.stderr);
  assert.match(result.stderr, /internal writer requires the kernel writer lock/i);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), before);
  assert.deepEqual(
    fs.readdirSync(path.dirname(statePathFor(repositoryRoot, "v0.2.0-rc.1")))
      .filter((entry) => entry.endsWith(".tmp")),
    [],
  );
});

test("public save invokes lockf once and does not recurse through the public writer", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-lockf-once-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const realSpawnSync = childProcess.spawnSync.bind(childProcess);
  let publicInvocations = 0;
  t.mock.method(childProcess, "spawnSync", (...args) => {
    publicInvocations += 1;
    return realSpawnSync(...args);
  });
  saveReleaseState(repositoryRoot, initialState());

  assert.equal(publicInvocations, 1);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), initialState());
});

test("writer refuses a lock pathname replaced before lockf acquisition", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-lock-replaced-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const before = initialState();
  const after = completePhase(before, "preflight", TIMESTAMPS.preflight);
  saveReleaseState(repositoryRoot, before);
  const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
  const lockPath = path.join(path.dirname(destination), "release-state.lock");
  const realSpawnSync = childProcess.spawnSync.bind(childProcess);
  let replaced = false;
  t.mock.method(childProcess, "spawnSync", (command, args, options) => {
    if (!replaced && command === "/usr/bin/lockf") {
      replaced = true;
      assert.equal(args[5], lockPath);
      fs.renameSync(lockPath, `${lockPath}.original`);
      fs.writeFileSync(lockPath, "", { mode: 0o600 });
    }
    return realSpawnSync(command, args, options);
  });

  assert.throws(
    () => saveReleaseState(repositoryRoot, after),
    /release state writer lock identity changed/i,
  );
  assert.equal(replaced, true);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), before);
  assert.deepEqual(
    fs.readdirSync(path.dirname(destination)).filter(
      (entry) => entry.endsWith(".tmp"),
    ),
    [],
  );
});

test("mere lock-file existence does not block a save after the kernel lock is released", (t) => {
  const repositoryRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "inkbeam-lock-exists-"),
  );
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const first = initialState();
  const second = completePhase(first, "preflight", TIMESTAMPS.preflight);
  saveReleaseState(repositoryRoot, first);
  assert.equal(
    saveReleaseState(repositoryRoot, second),
    statePathFor(repositoryRoot, "v0.2.0-rc.1"),
  );
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), second);
});

test("save refuses a state target that appears or changes before commit", async (t) => {
  for (const scenario of ["appears", "changes"]) {
    await t.test(scenario, () => {
      const repositoryRoot = fs.mkdtempSync(
        path.join(os.tmpdir(), `inkbeam-state-${scenario}-`),
      );
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
      if (scenario === "changes") saveReleaseState(repositoryRoot, initialState());
      const preloadOption = interferencePreload({
        repositoryRoot,
        destination,
        scenario,
      });

      assert.throws(
        () => withEnvironmentVariable(
          "NODE_OPTIONS",
          [process.env.NODE_OPTIONS, preloadOption].filter(Boolean).join(" "),
          () => saveReleaseState(
            repositoryRoot,
            scenario === "appears"
              ? initialState()
              : completePhase(initialState(), "preflight", TIMESTAMPS.preflight),
          ),
        ),
        /release state target (?:appeared|changed) before commit/i,
      );

      assert.equal(fs.readFileSync(destination, "utf8"), "foreign writer contents\n");
      assert.equal(
        fs.lstatSync(path.join(path.dirname(destination), "release-state.lock")).isFile(),
        true,
      );
      assert.deepEqual(
        fs.readdirSync(path.dirname(destination)).filter(
          (entry) => entry.endsWith(".tmp"),
        ),
        [],
      );
    });
  }
});

test("load and save refuse symlinked repository and evidence directory components", async (t) => {
  for (const operation of ["load", "save"]) {
    for (const component of ["repositoryRoot", "build", "release-evidence", "tag"]) {
      await t.test(`${operation}-${component}`, () => {
        const fixtureRoot = fs.mkdtempSync(
          path.join(os.tmpdir(), `inkbeam-path-${component}-`),
        );
        t.after(() => fs.rmSync(fixtureRoot, { recursive: true, force: true }));
        const outside = path.join(fixtureRoot, "outside");
        const realRepository = path.join(fixtureRoot, "repository");
        fs.mkdirSync(outside);
        fs.mkdirSync(realRepository);

        let repositoryRoot = realRepository;
        if (component === "repositoryRoot") {
          repositoryRoot = path.join(fixtureRoot, "repository-link");
          fs.symlinkSync(outside, repositoryRoot, "dir");
        } else if (component === "build") {
          fs.symlinkSync(outside, path.join(realRepository, "build"), "dir");
        } else if (component === "release-evidence") {
          fs.mkdirSync(path.join(realRepository, "build"));
          fs.symlinkSync(
            outside,
            path.join(realRepository, "build/release-evidence"),
            "dir",
          );
        } else {
          fs.mkdirSync(path.join(realRepository, "build/release-evidence"), {
            recursive: true,
          });
          fs.symlinkSync(
            outside,
            path.join(realRepository, "build/release-evidence/v0.2.0-rc.1"),
            "dir",
          );
        }

        assert.throws(
          () => operation === "load"
            ? loadReleaseState(repositoryRoot, "v0.2.0-rc.1")
            : saveReleaseState(repositoryRoot, initialState()),
          /unsafe release state path.*symbolic link/i,
        );
        assert.equal(
          fs.readdirSync(outside, { recursive: true }).some(
            (entry) => path.basename(String(entry)) === "release-state.json",
          ),
          false,
        );
      });
    }
  }
});

test("load and save refuse symlinked state targets without touching the outside file", async (t) => {
  for (const operation of ["load", "save"]) {
    await t.test(operation, () => {
      const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), `inkbeam-state-link-${operation}-`));
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
      fs.mkdirSync(path.dirname(destination), { recursive: true });
      const outsideState = path.join(repositoryRoot, "outside-state.json");
      const originalContents = `${JSON.stringify(initialState(), null, 2)}\n`;
      fs.writeFileSync(outsideState, originalContents);
      fs.symlinkSync(outsideState, destination, "file");

      assert.throws(
        () => operation === "load"
          ? loadReleaseState(repositoryRoot, "v0.2.0-rc.1")
          : saveReleaseState(repositoryRoot, initialState()),
        /unsafe release state target.*symbolic link/i,
      );
      assert.equal(fs.readFileSync(outsideState, "utf8"), originalContents);
      assert.equal(fs.lstatSync(destination).isSymbolicLink(), true);
    });
  }
});

test("load and save refuse a non-regular state target", async (t) => {
  for (const operation of ["load", "save"]) {
    await t.test(operation, () => {
      const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), `inkbeam-state-directory-${operation}-`));
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
      fs.mkdirSync(destination, { recursive: true });

      assert.throws(
        () => operation === "load"
          ? loadReleaseState(repositoryRoot, "v0.2.0-rc.1")
          : saveReleaseState(repositoryRoot, initialState()),
        /unsafe release state target is not a regular file/i,
      );
      assert.equal(fs.lstatSync(destination).isDirectory(), true);
    });
  }
});

test("load and save refuse non-directory evidence path components", async (t) => {
  for (const operation of ["load", "save"]) {
    for (const component of ["build", "release-evidence", "tag"]) {
      await t.test(`${operation}-${component}`, () => {
        const repositoryRoot = fs.mkdtempSync(
          path.join(os.tmpdir(), `inkbeam-path-file-${component}-`),
        );
        t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
        const componentPath = component === "build"
          ? path.join(repositoryRoot, "build")
          : component === "release-evidence"
            ? path.join(repositoryRoot, "build/release-evidence")
            : path.join(repositoryRoot, "build/release-evidence/v0.2.0-rc.1");
        fs.mkdirSync(path.dirname(componentPath), { recursive: true });
        fs.writeFileSync(componentPath, "not a directory");

        assert.throws(
          () => operation === "load"
            ? loadReleaseState(repositoryRoot, "v0.2.0-rc.1")
            : saveReleaseState(repositoryRoot, initialState()),
          /unsafe release state path is not a directory/i,
        );
      });
    }
  }
});

test("save refuses symlinked or non-regular lock and temporary targets", async (t) => {
  for (const [surface, kind] of [
    ["lock", "symlink"],
    ["lock", "directory"],
    ["temporary", "symlink"],
    ["temporary", "directory"],
  ]) {
    await t.test(`${surface}-${kind}`, () => {
      const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), `inkbeam-${surface}-${kind}-`));
      t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
      const destination = statePathFor(repositoryRoot, "v0.2.0-rc.1");
      const evidenceDirectory = path.dirname(destination);
      fs.mkdirSync(evidenceDirectory, { recursive: true });
      const outside = path.join(repositoryRoot, "outside-sentinel");
      fs.writeFileSync(outside, "unchanged");
      const target = surface === "lock"
        ? path.join(evidenceDirectory, "release-state.lock")
        : path.join(evidenceDirectory, ".release-state.attack.tmp");
      if (kind === "symlink") fs.symlinkSync(outside, target, "file");
      else fs.mkdirSync(target);
      assert.throws(
        () => saveReleaseState(repositoryRoot, initialState()),
        new RegExp(`unsafe release state ${surface} target`, "i"),
      );
      assert.equal(fs.readFileSync(outside, "utf8"), "unchanged");
      assert.equal(fs.existsSync(destination), false);
    });
  }
});

test("accepts the complete stable promotion, Pages publication, and completion state", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-stable-positive-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const states = stableReleaseStates();

  for (const state of Object.values(states)) {
    assert.equal(validateReleaseState(state), true);
    assert.equal(saveReleaseState(repositoryRoot, state), statePathFor(
      repositoryRoot,
      "v0.2.0",
    ));
  }
  assert.equal(states.completed.publication.pages.beta[0].previousCommitID, OTHER_SHA);
  assert.equal(states.completed.publication.pages.stable[0].previousCommitID, FOURTH_SHA);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0"), states.completed);
});

test("accepts RC withdrawal with a linked beta Pages append", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-withdraw-positive-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const candidate = betaFeedPublishedState();
  saveReleaseState(repositoryRoot, candidate);
  const withdrawn = structuredClone(candidate);
  withdrawn.publication.github.withdrawn = {
    releaseID: 123456,
    tagCommitID: SHA,
    url: "https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0-rc.1",
    draft: false,
    prerelease: true,
    makeLatest: false,
    title: "Withdrawn — Inkbeam v0.2.0-rc.1",
  };
  withdrawn.publication.pages.beta.push({
    previousCommitID: THIRD_SHA,
    publishedCommitID: FOURTH_SHA,
  });

  assert.equal(validateReleaseState(withdrawn), true);
  assert.equal(saveReleaseState(repositoryRoot, withdrawn), statePathFor(
    repositoryRoot,
    "v0.2.0-rc.1",
  ));
});

test("accepts append-only stable rollback evidence", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-rollback-positive-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));
  const promoted = stableCompletedState();
  saveReleaseState(repositoryRoot, promoted);
  const rolledBack = structuredClone(promoted);
  rolledBack.publication.github.rollback = {
    releaseID: 123456,
    tagCommitID: SHA,
    url: "https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0",
    draft: false,
    prerelease: true,
    makeLatest: false,
    title: "Inkbeam v0.2.0 (Final Candidate)",
  };
  rolledBack.publication.pages.rollback = [{
    previousCommitID: FIFTH_SHA,
    publishedCommitID: SIXTH_SHA,
  }];

  assert.equal(validateReleaseState(rolledBack), true);
  assert.equal(saveReleaseState(repositoryRoot, rolledBack), statePathFor(
    repositoryRoot,
    "v0.2.0",
  ));
});

test("writes atomically to the exact ignored evidence path and validates on load", (t) => {
  const repositoryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "inkbeam-state-"));
  t.after(() => fs.rmSync(repositoryRoot, { recursive: true, force: true }));

  const state = completePhase(initialState(), "preflight", TIMESTAMPS.preflight);
  const expectedPath = path.join(
    repositoryRoot,
    "build/release-evidence/v0.2.0-rc.1/release-state.json",
  );

  assert.equal(statePathFor(repositoryRoot, "v0.2.0-rc.1"), expectedPath);
  assert.equal(saveReleaseState(repositoryRoot, state), expectedPath);
  assert.deepEqual(loadReleaseState(repositoryRoot, "v0.2.0-rc.1"), state);

  const persisted = JSON.parse(fs.readFileSync(expectedPath, "utf8"));
  persisted.contract.tag = "v0.2.0-rc.2";
  fs.writeFileSync(expectedPath, `${JSON.stringify(persisted)}\n`);
  assert.throws(
    () => loadReleaseState(repositoryRoot, "v0.2.0-rc.1"),
    /release contract mismatch/i,
  );
});

import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

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
const DMG_SIGNATURE = Buffer.alloc(64, 7).toString("base64");
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

function readyForNotarization() {
  return completePhase(
    completePhase(initialState(), "preflight", TIMESTAMPS.preflight),
    "packaged",
    TIMESTAMPS.packaged,
  );
}

function acceptedNotarizationState() {
  return recordNotarizationStatus(
    recordNotarizationSubmission(
      readyForNotarization(),
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

function sealedState() {
  const state = structuredClone(acceptedNotarizationState());
  state.artifacts = exactArtifacts();
  return completePhase(state, "sealed", TIMESTAMPS.sealed);
}

function candidatePublishedState() {
  const state = structuredClone(sealedState());
  state.publication = {
    github: {
      candidate: {
        releaseID: 123456,
        tagCommitID: SHA,
        url: "https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0-rc.1",
        draft: false,
        prerelease: true,
        makeLatest: false,
        title: "Inkbeam v0.2.0-rc.1",
      },
    },
  };
  return completePhase(
    state,
    "candidatePublished",
    TIMESTAMPS.candidatePublished,
  );
}

function publiclyVerifiedState() {
  const state = structuredClone(candidatePublishedState());
  state.publication.publicURLs = {
    release: "https://github.com/gihwan-dev/inkbeam/releases/tag/v0.2.0-rc.1",
    dmg: "https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0-rc.1/Inkbeam-0.2.0-rc.1.dmg",
    chromeZip:
      "https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0-rc.1/Inkbeam-Chrome-0.2.0-rc.1.zip",
    checksums:
      "https://github.com/gihwan-dev/inkbeam/releases/download/v0.2.0-rc.1/SHA256SUMS.txt",
  };
  return completePhase(state, "publicVerified", TIMESTAMPS.publicVerified);
}

function betaFeedPublishedState() {
  let state = completePhase(
    publiclyVerifiedState(),
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

function acceptedCandidateState() {
  const state = structuredClone(betaFeedPublishedState());
  state.acceptance = {
    candidate: {
      path: "docs/testing/releases/v0.2.0-rc.1.md",
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

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
const TIMESTAMPS = {
  preflight: "2026-08-14T01:00:00.000Z",
  packaged: "2026-08-14T01:01:00.000Z",
  submitted: "2026-08-14T01:02:00.000Z",
  notarized: "2026-08-14T01:03:00.000Z",
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
  const rootMutation = structuredClone(initialState());
  rootMutation.command = "echo unexpected";
  assert.throws(() => validateReleaseState(rootMutation), /unknown state key.*command/i);

  const nestedMutation = structuredClone(initialState());
  nestedMutation.identity.profile = "alternate";
  assert.throws(
    () => validateReleaseState(nestedMutation),
    /unknown identity key.*profile/i,
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

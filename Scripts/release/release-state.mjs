import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

import { contractFor } from "./release-contract.mjs";

const ROOT_KEYS = new Set([
  "schemaVersion",
  "contract",
  "source",
  "identity",
  "phases",
  "notarization",
]);
const CONTRACT_KEYS = new Set([
  "tag",
  "version",
  "build",
  "channel",
  "dmg",
  "chromeZip",
  "releaseTitle",
  "prerelease",
]);
const SOURCE_KEYS = new Set(["branch", "sha"]);
const IDENTITY_KEYS = new Set([
  "teamID",
  "signingIdentity",
  "appBundleID",
  "helperBundleID",
]);
const NOTARIZATION_KEYS = new Set(["submissionID", "status"]);
const SECRET_KEY_PATTERN = /(password|secret|token|privateKey|credential)/i;
const SECRET_VALUE_PATTERN = /(?:gh[pousr]_[A-Za-z0-9_]{8,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)/;
const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;
const SUBMISSION_ID_PATTERN = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const NOTARIZATION_STATUSES = new Set([
  "Submitted",
  "In Progress",
  "Accepted",
  "Invalid",
  "Rejected",
]);

export const releasePhaseDependencies = Object.freeze({
  preflight: [],
  packaged: ["preflight"],
  notarizationSubmitted: ["packaged"],
  notarized: ["notarizationSubmitted"],
  sealed: ["notarized"],
  candidatePublished: ["sealed"],
  publicVerified: ["candidatePublished"],
  betaFeedPrepared: ["publicVerified"],
  betaFeedPublished: ["betaFeedPrepared"],
  stableFeedPrepared: ["publicVerified"],
  acceptanceRecorded: ["publicVerified"],
  finalPromoted: ["betaFeedPublished", "stableFeedPrepared", "acceptanceRecorded"],
  stableFeedPublished: ["finalPromoted"],
  completed: ["publicVerified"],
});

function clone(value) {
  return structuredClone(value);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return false;
  }
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function requirePlainObject(value, label) {
  if (!isPlainObject(value)) throw new Error(`${label} must be an object`);
}

function rejectSecretMaterial(value, keyPath = []) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => rejectSecretMaterial(child, [...keyPath, String(index)]));
    return;
  }
  if (!value || typeof value !== "object") {
    if (typeof value === "string" && SECRET_VALUE_PATTERN.test(value)) {
      throw new Error(`secret material is forbidden at ${keyPath.join(".")}`);
    }
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (SECRET_KEY_PATTERN.test(key)) {
      throw new Error(`secret material is forbidden in ${key}`);
    }
    rejectSecretMaterial(child, [...keyPath, key]);
  }
}

function rejectUnknownKeys(value, allowed, label) {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new Error(`unknown ${label} key: ${key}`);
  }
}

function assertExactContract(actual, expected = contractFor(actual?.tag)) {
  requirePlainObject(actual, "release contract");
  rejectUnknownKeys(actual, CONTRACT_KEYS, "contract");
  for (const key of CONTRACT_KEYS) {
    if (!Object.hasOwn(actual, key) || actual[key] !== expected[key]) {
      throw new Error("release contract mismatch");
    }
  }
}

function validateTimestamp(timestamp, label) {
  if (typeof timestamp !== "string" || !ISO_TIMESTAMP_PATTERN.test(timestamp)) {
    throw new Error(`${label} must be an ISO-8601 UTC timestamp`);
  }
  if (Number.isNaN(Date.parse(timestamp))) {
    throw new Error(`${label} is not a valid timestamp`);
  }
}

function validatePhases(phases) {
  requirePlainObject(phases, "phases");
  for (const [phase, timestamp] of Object.entries(phases)) {
    const dependencies = releasePhaseDependencies[phase];
    if (!dependencies) throw new Error(`unknown release phase: ${phase}`);
    validateTimestamp(timestamp, `phase ${phase}`);
    for (const dependency of dependencies) {
      if (!phases[dependency]) {
        throw new Error(`cannot complete phase ${phase} before ${dependency}`);
      }
    }
  }
}

export function validateReleaseState(state, expectedContract) {
  requirePlainObject(state, "release state");
  rejectSecretMaterial(state);
  rejectUnknownKeys(state, ROOT_KEYS, "state");
  if (state.schemaVersion !== 1) {
    throw new Error("unsupported release state schema version");
  }
  assertExactContract(state.contract, expectedContract ?? contractFor(state.contract?.tag));

  requirePlainObject(state.source, "source");
  rejectUnknownKeys(state.source, SOURCE_KEYS, "source");
  if (typeof state.source.branch !== "string" || state.source.branch.length === 0) {
    throw new Error("source branch is required");
  }
  if (!SHA_PATTERN.test(state.source.sha)) {
    throw new Error("source SHA must be exactly 40 lowercase hexadecimal characters");
  }

  requirePlainObject(state.identity, "identity");
  rejectUnknownKeys(state.identity, IDENTITY_KEYS, "identity");
  if (!/^[A-Z0-9]{10}$/.test(state.identity.teamID)) {
    throw new Error("identity Team ID must be exactly 10 uppercase alphanumeric characters");
  }
  if (
    typeof state.identity.signingIdentity !== "string" ||
    !state.identity.signingIdentity.startsWith("Developer ID Application: ")
  ) {
    throw new Error("Developer ID Application signing identity is required");
  }
  if (state.identity.appBundleID !== "dev.gihwan.inkbeam") {
    throw new Error("unexpected Inkbeam app bundle identifier");
  }
  if (state.identity.helperBundleID !== "dev.gihwan.inkbeam.nativehost") {
    throw new Error("unexpected Inkbeam helper bundle identifier");
  }
  validatePhases(state.phases);

  if (state.notarization !== undefined) {
    requirePlainObject(state.notarization, "notarization");
    rejectUnknownKeys(state.notarization, NOTARIZATION_KEYS, "notarization");
    if (!SUBMISSION_ID_PATTERN.test(state.notarization.submissionID)) {
      throw new Error("notarization submission ID must use UUID syntax");
    }
    if (!NOTARIZATION_STATUSES.has(state.notarization.status)) {
      throw new Error(`unsupported notarization status: ${String(state.notarization.status)}`);
    }
    if (!state.phases.notarizationSubmitted) {
      throw new Error("notarization evidence requires notarizationSubmitted phase");
    }
    if (state.notarization.status === "Accepted" && !state.phases.notarized) {
      throw new Error("accepted notarization requires notarized phase");
    }
  } else if (state.phases.notarizationSubmitted || state.phases.notarized) {
    throw new Error("notarization phase requires a submission ID");
  }

  return true;
}

export function createReleaseState({ contract, source, identity }) {
  const state = {
    schemaVersion: 1,
    contract: clone(contract),
    source: clone(source),
    identity: clone(identity),
    phases: {},
  };
  validateReleaseState(state, contract);
  return deepFreeze(state);
}

export function completePhase(state, phase, timestamp = new Date().toISOString()) {
  if (!Object.hasOwn(releasePhaseDependencies, phase)) {
    throw new Error(`unknown release phase: ${phase}`);
  }
  if (state.phases?.[phase]) {
    throw new Error(`release phase already completed: ${phase}`);
  }
  const next = clone(state);
  next.phases[phase] = timestamp;
  validateReleaseState(next);
  return deepFreeze(next);
}

export function recordNotarizationSubmission(state, submissionID, timestamp) {
  if (state.notarization?.submissionID) {
    throw new Error("notarization submission ID already exists");
  }
  if (!state.phases?.packaged) {
    throw new Error("cannot submit notarization before packaged phase");
  }
  const next = clone(state);
  next.notarization = { submissionID, status: "Submitted" };
  next.phases.notarizationSubmitted = timestamp ?? new Date().toISOString();
  validateReleaseState(next);
  return deepFreeze(next);
}

export function recordNotarizationStatus(state, status, timestamp) {
  if (!state.notarization?.submissionID) {
    throw new Error("notarization submission ID is missing");
  }
  if (!NOTARIZATION_STATUSES.has(status)) {
    throw new Error(`unsupported notarization status: ${String(status)}`);
  }
  const next = clone(state);
  next.notarization.status = status;
  if (status === "Accepted") {
    if (next.phases.notarized) {
      throw new Error("release phase already completed: notarized");
    }
    next.phases.notarized = timestamp ?? new Date().toISOString();
  }
  validateReleaseState(next);
  return deepFreeze(next);
}

export function statePathFor(repositoryRoot, tag) {
  contractFor(tag);
  if (typeof repositoryRoot !== "string" || repositoryRoot.length === 0) {
    throw new Error("repository root is required");
  }
  return path.join(
    path.resolve(repositoryRoot),
    "build",
    "release-evidence",
    tag,
    "release-state.json",
  );
}

export function saveReleaseState(repositoryRoot, state) {
  validateReleaseState(state);
  const destination = statePathFor(repositoryRoot, state.contract.tag);
  const directory = path.dirname(destination);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const temporary = path.join(
    directory,
    `.release-state.${process.pid}.${crypto.randomUUID()}.tmp`,
  );
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(state, null, 2)}\n`, {
      encoding: "utf8",
      flag: "wx",
      mode: 0o600,
    });
    fs.renameSync(temporary, destination);
  } finally {
    fs.rmSync(temporary, { force: true });
  }
  return destination;
}

export function loadReleaseState(repositoryRoot, tag) {
  const expectedContract = contractFor(tag);
  const state = JSON.parse(fs.readFileSync(statePathFor(repositoryRoot, tag), "utf8"));
  validateReleaseState(state, expectedContract);
  return deepFreeze(state);
}

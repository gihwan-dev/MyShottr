import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { isDeepStrictEqual } from "node:util";

import { contractFor } from "./release-contract.mjs";

const ROOT_KEYS = new Set([
  "schemaVersion",
  "contract",
  "source",
  "identity",
  "phases",
  "notarization",
  "artifacts",
  "publication",
  "acceptance",
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
const ARTIFACT_KEYS = new Set(["dmg", "chromeZip"]);
const DMG_ARTIFACT_KEYS = new Set([
  "fileName",
  "byteLength",
  "sha256",
  "edSignature",
  "verificationSummary",
]);
const CHROME_ARTIFACT_KEYS = new Set([
  "fileName",
  "byteLength",
  "sha256",
  "verificationSummary",
]);
const PUBLICATION_KEYS = new Set(["publicURLs", "github", "pages"]);
const PUBLIC_URL_KEYS = new Set([
  "release",
  "dmg",
  "chromeZip",
  "checksums",
  "betaFeed",
  "stableFeed",
]);
const GITHUB_KEYS = new Set(["candidate", "promoted", "withdrawn", "rollback"]);
const GITHUB_RELEASE_KEYS = new Set([
  "releaseID",
  "tagCommitID",
  "url",
  "draft",
  "prerelease",
  "makeLatest",
  "title",
]);
const PAGES_KEYS = new Set(["beta", "stable", "rollback"]);
const PAGES_COMMIT_KEYS = new Set(["previousCommitID", "publishedCommitID"]);
const ACCEPTANCE_KEYS = new Set(["candidate", "complete"]);
const ACCEPTANCE_RECORD_KEYS = new Set(["path", "result"]);
const SECRET_KEY_PATTERN = /(password|secret|token|privateKey|credential)/i;
const SECRET_VALUE_PATTERN = /(?:gh[pousr]_[A-Za-z0-9_]{8,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)/;
const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const SHA_PATTERN = /^[0-9a-f]{40}$/;
const SHA256_PATTERN = /^[0-9a-f]{64}$/;
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
  stableFeedPrepared: ["acceptanceRecorded"],
  acceptanceRecorded: ["betaFeedPublished"],
  finalPromoted: ["betaFeedPublished", "stableFeedPrepared", "acceptanceRecorded"],
  stableFeedPublished: ["finalPromoted"],
  completed: ["acceptanceRecorded"],
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
      if (Date.parse(timestamp) < Date.parse(phases[dependency])) {
        throw new Error(`phase ${phase} timestamp cannot precede ${dependency}`);
      }
    }
  }
}

function validateArtifactMetadata(artifacts, contract) {
  requirePlainObject(artifacts, "artifacts");
  rejectUnknownKeys(artifacts, ARTIFACT_KEYS, "artifact");
  for (const key of ARTIFACT_KEYS) {
    if (!Object.hasOwn(artifacts, key)) {
      throw new Error("final artifact metadata requires both DMG and Chrome ZIP");
    }
  }

  const definitions = [
    ["dmg", "DMG", DMG_ARTIFACT_KEYS, contract.dmg],
    ["chromeZip", "Chrome ZIP", CHROME_ARTIFACT_KEYS, contract.chromeZip],
  ];
  for (const [key, label, allowedKeys, expectedFileName] of definitions) {
    const artifact = artifacts[key];
    requirePlainObject(artifact, `${label} artifact`);
    rejectUnknownKeys(artifact, allowedKeys, `${label} artifact`);
    if (artifact.fileName !== expectedFileName) {
      throw new Error(`${label} filename must match release contract`);
    }
    if (!Number.isSafeInteger(artifact.byteLength) || artifact.byteLength <= 0) {
      throw new Error(`${label} byte length must be a positive integer`);
    }
    if (!SHA256_PATTERN.test(artifact.sha256)) {
      throw new Error(`${label} SHA-256 must be 64 lowercase hexadecimal characters`);
    }
    if (
      typeof artifact.verificationSummary !== "string" ||
      artifact.verificationSummary.length === 0 ||
      artifact.verificationSummary.length > 1_000 ||
      /[\r\n]/.test(artifact.verificationSummary)
    ) {
      throw new Error(`${label} verification summary is required on one line`);
    }
  }

  const signature = artifacts.dmg.edSignature;
  if (
    typeof signature !== "string" ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(signature) ||
    Buffer.from(signature, "base64").byteLength !== 64 ||
    Buffer.from(signature, "base64").toString("base64") !== signature
  ) {
    throw new Error("DMG EdDSA signature must be canonical base64 for 64 bytes");
  }
}

function expectedPublicURLs(contract) {
  const releaseBase = `https://github.com/gihwan-dev/inkbeam/releases`;
  const downloadBase = `${releaseBase}/download/${contract.tag}`;
  return {
    release: `${releaseBase}/tag/${contract.tag}`,
    dmg: `${downloadBase}/${contract.dmg}`,
    chromeZip: `${downloadBase}/${contract.chromeZip}`,
    checksums: `${downloadBase}/SHA256SUMS.txt`,
    betaFeed: "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml",
    stableFeed: "https://gihwan-dev.github.io/inkbeam/appcast.xml",
  };
}

function validatePublicURLs(publicURLs, contract) {
  requirePlainObject(publicURLs, "public URLs");
  rejectUnknownKeys(publicURLs, PUBLIC_URL_KEYS, "public URL");
  const expected = expectedPublicURLs(contract);
  for (const key of ["release", "dmg", "chromeZip", "checksums"]) {
    if (publicURLs[key] !== expected[key]) {
      const label = key === "chromeZip" ? "Chrome ZIP" : key;
      throw new Error(`public ${label} URL does not match release contract`);
    }
  }
  for (const [key, label] of [["betaFeed", "beta"], ["stableFeed", "stable"]]) {
    if (publicURLs[key] !== undefined && publicURLs[key] !== expected[key]) {
      throw new Error(`public ${label} feed URL does not match Inkbeam Pages`);
    }
  }
}

function validateGitHubRelease(release, kind, contract, source) {
  requirePlainObject(release, `GitHub ${kind} release`);
  rejectUnknownKeys(release, GITHUB_RELEASE_KEYS, "GitHub release");
  if (!Number.isSafeInteger(release.releaseID) || release.releaseID <= 0) {
    throw new Error("GitHub release ID must be a positive integer");
  }
  if (release.tagCommitID !== source.sha) {
    throw new Error("GitHub tag commit ID must match recorded source SHA");
  }
  if (release.url !== expectedPublicURLs(contract).release) {
    throw new Error("GitHub release URL does not match release contract");
  }

  const candidateShape =
    release.draft === false &&
    release.prerelease === true &&
    release.makeLatest === false;
  if (kind === "candidate" || kind === "rollback") {
    if (!candidateShape) {
      throw new Error("GitHub candidate must be non-draft, prerelease, and not latest");
    }
    if (release.title !== contract.releaseTitle) {
      throw new Error("GitHub candidate title must match release contract");
    }
  } else if (kind === "withdrawn") {
    if (!candidateShape) {
      throw new Error("withdrawn GitHub release must remain non-draft, prerelease, and not latest");
    }
    if (release.title !== `Withdrawn — Inkbeam ${contract.tag}`) {
      throw new Error("withdrawn GitHub release title does not match release contract");
    }
  } else {
    if (contract.channel !== "stable") {
      throw new Error("only the stable release can record GitHub promotion state");
    }
    if (
      release.draft !== false ||
      release.prerelease !== false ||
      release.makeLatest !== true
    ) {
      throw new Error("promoted GitHub release must be non-draft, stable, and latest");
    }
    if (release.title !== "Inkbeam v0.2.0") {
      throw new Error("promoted GitHub release title must be Inkbeam v0.2.0");
    }
  }
}

function validatePages(pages) {
  requirePlainObject(pages, "Pages state");
  rejectUnknownKeys(pages, PAGES_KEYS, "Pages");
  for (const [kind, history] of Object.entries(pages)) {
    if (!Array.isArray(history) || history.length === 0) {
      throw new Error(`Pages ${kind} history must be a non-empty array`);
    }
    for (const [index, commits] of history.entries()) {
      requirePlainObject(commits, `Pages ${kind} commit transition`);
      rejectUnknownKeys(commits, PAGES_COMMIT_KEYS, "Pages commit");
      if (
        commits.previousCommitID !== undefined &&
        !SHA_PATTERN.test(commits.previousCommitID)
      ) {
        throw new Error("Pages commit ID must be 40 lowercase hexadecimal characters");
      }
      if (!SHA_PATTERN.test(commits.publishedCommitID)) {
        throw new Error("Pages commit ID must be 40 lowercase hexadecimal characters");
      }
      if (
        index > 0 &&
        commits.previousCommitID !== history[index - 1].publishedCommitID
      ) {
        throw new Error(
          `Pages ${kind} transition must start from the previous published commit ID`,
        );
      }
    }
  }
}

function validatePublication(publication, contract, source) {
  requirePlainObject(publication, "publication");
  rejectUnknownKeys(publication, PUBLICATION_KEYS, "publication");
  if (publication.publicURLs !== undefined) {
    validatePublicURLs(publication.publicURLs, contract);
  }
  if (publication.github !== undefined) {
    requirePlainObject(publication.github, "GitHub state");
    rejectUnknownKeys(publication.github, GITHUB_KEYS, "GitHub");
    for (const [kind, release] of Object.entries(publication.github)) {
      validateGitHubRelease(release, kind, contract, source);
    }
  }
  if (publication.pages !== undefined) validatePages(publication.pages);
}

function validateAcceptance(acceptance, contract) {
  requirePlainObject(acceptance, "acceptance");
  rejectUnknownKeys(acceptance, ACCEPTANCE_KEYS, "acceptance");
  const expectedPath = `docs/testing/releases/${contract.tag}.md`;
  for (const [kind, record] of Object.entries(acceptance)) {
    requirePlainObject(record, `${kind} acceptance record`);
    rejectUnknownKeys(record, ACCEPTANCE_RECORD_KEYS, "acceptance record");
    if (record.path !== expectedPath) {
      throw new Error(`acceptance path must be ${expectedPath}`);
    }
    if (record.result !== "PASS") {
      throw new Error("acceptance result must be PASS");
    }
  }
}

function validatePhaseEvidence(state) {
  if (state.phases.sealed && !state.artifacts) {
    throw new Error("sealed phase requires exact final artifact metadata");
  }
  if (state.phases.candidatePublished && !state.publication?.github?.candidate) {
    throw new Error("candidatePublished phase requires GitHub candidate state");
  }
  if (state.phases.publicVerified && !state.publication?.publicURLs) {
    throw new Error("publicVerified phase requires exact public artifact URLs");
  }
  if (
    state.phases.betaFeedPublished &&
    (!state.publication?.pages?.beta?.length || !state.publication?.publicURLs?.betaFeed)
  ) {
    throw new Error("betaFeedPublished phase requires Pages commit IDs and beta feed URL");
  }
  if (
    state.phases.stableFeedPublished &&
    (!state.publication?.pages?.stable?.length || !state.publication?.publicURLs?.stableFeed)
  ) {
    throw new Error("stableFeedPublished phase requires Pages commit IDs and stable feed URL");
  }
  if (state.phases.acceptanceRecorded && state.acceptance?.candidate?.result !== "PASS") {
    throw new Error("acceptanceRecorded phase requires candidate acceptance PASS");
  }
  if (state.phases.finalPromoted && !state.publication?.github?.promoted) {
    throw new Error("finalPromoted phase requires promoted GitHub release state");
  }
  if (state.phases.completed && state.acceptance?.complete?.result !== "PASS") {
    throw new Error("completed phase requires complete acceptance PASS");
  }
  if (
    state.phases.completed &&
    state.contract.channel === "stable" &&
    !state.phases.stableFeedPublished
  ) {
    throw new Error("stable completed phase requires stableFeedPublished");
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

  if (state.phases.notarized && state.notarization?.status !== "Accepted") {
    throw new Error("notarized phase requires Accepted notarization status");
  }

  if (state.artifacts !== undefined) {
    validateArtifactMetadata(state.artifacts, state.contract);
  }
  if (state.publication !== undefined) {
    validatePublication(state.publication, state.contract, state.source);
  }
  if (state.acceptance !== undefined) {
    validateAcceptance(state.acceptance, state.contract);
  }
  validatePhaseEvidence(state);

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
  assertNotarizationStatusAdvance(state.notarization.status, status);
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

function lstatIfExists(surfacePath) {
  try {
    return fs.lstatSync(surfacePath);
  } catch (error) {
    if (error?.code === "ENOENT") return undefined;
    throw error;
  }
}

function assertSafeDirectory(surfacePath) {
  const stats = lstatIfExists(surfacePath);
  if (!stats) throw new Error(`release state path does not exist: ${surfacePath}`);
  if (stats.isSymbolicLink()) {
    throw new Error(`unsafe release state path is a symbolic link: ${surfacePath}`);
  }
  if (!stats.isDirectory()) {
    throw new Error(`unsafe release state path is not a directory: ${surfacePath}`);
  }
  return stats;
}

function evidenceDirectoryFor(repositoryRoot, tag, { create }) {
  contractFor(tag);
  if (typeof repositoryRoot !== "string" || repositoryRoot.length === 0) {
    throw new Error("repository root is required");
  }
  const root = path.resolve(repositoryRoot);
  const surfaces = [
    root,
    path.join(root, "build"),
    path.join(root, "build", "release-evidence"),
    path.join(root, "build", "release-evidence", tag),
  ];

  const identities = [{ surfacePath: root, stats: assertSafeDirectory(root) }];
  for (const surfacePath of surfaces.slice(1)) {
    if (!lstatIfExists(surfacePath)) {
      if (!create) {
        throw new Error(`release state path does not exist: ${surfacePath}`);
      }
      try {
        fs.mkdirSync(surfacePath, { mode: 0o700 });
      } catch (error) {
        if (error?.code !== "EEXIST") throw error;
      }
    }
    identities.push({ surfacePath, stats: assertSafeDirectory(surfacePath) });
  }
  return { directory: surfaces.at(-1), identities };
}

function assertSafeFileTarget(surfacePath, label, { required = false } = {}) {
  const description = label === "state"
    ? "release state target"
    : `release state ${label} target`;
  const stats = lstatIfExists(surfacePath);
  if (!stats) {
    if (required) throw new Error(`${description} does not exist`);
    return undefined;
  }
  if (stats.isSymbolicLink()) {
    throw new Error(`unsafe ${description} is a symbolic link`);
  }
  if (!stats.isFile()) {
    throw new Error(`unsafe ${description} is not a regular file`);
  }
  return stats;
}

function sameFileIdentity(left, right) {
  return left.dev === right.dev && left.ino === right.ino;
}

function assertEvidencePathUnchanged(evidencePath) {
  for (const { surfacePath, stats } of evidencePath.identities) {
    const current = assertSafeDirectory(surfacePath);
    if (!sameFileIdentity(current, stats)) {
      throw new Error(`unsafe release state path changed: ${surfacePath}`);
    }
  }
}

function openRegularFile(surfacePath, label) {
  const expectedStats = assertSafeFileTarget(surfacePath, label, {
    required: true,
  });
  let descriptor;
  try {
    descriptor = fs.openSync(
      surfacePath,
      fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0),
    );
    const openedStats = fs.fstatSync(descriptor);
    if (!openedStats.isFile() || !sameFileIdentity(expectedStats, openedStats)) {
      throw new Error(`unsafe release state ${label} target changed during read`);
    }
    return { descriptor, stats: openedStats };
  } catch (error) {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    throw error;
  }
}

function readRegularFile(surfacePath, label) {
  const opened = openRegularFile(surfacePath, label);
  try {
    return {
      contents: fs.readFileSync(opened.descriptor, "utf8"),
      stats: opened.stats,
    };
  } finally {
    fs.closeSync(opened.descriptor);
  }
}

function removeOwnedFile(surfacePath, expectedStats, label) {
  const current = lstatIfExists(surfacePath);
  if (!current) return;
  if (
    current.isSymbolicLink() ||
    !current.isFile() ||
    !sameFileIdentity(current, expectedStats)
  ) {
    throw new Error(`unsafe release state ${label} target changed before cleanup`);
  }
  fs.unlinkSync(surfacePath);
}

function serializeLockMetadata(pid) {
  return `${JSON.stringify({ schemaVersion: 1, pid })}\n`;
}

function parseLockMetadata(contents) {
  let metadata;
  try {
    metadata = JSON.parse(contents);
  } catch {
    throw new Error("invalid release state lock metadata");
  }
  if (
    !isPlainObject(metadata) ||
    Object.keys(metadata).length !== 2 ||
    !Object.hasOwn(metadata, "schemaVersion") ||
    !Object.hasOwn(metadata, "pid") ||
    metadata.schemaVersion !== 1 ||
    !Number.isSafeInteger(metadata.pid) ||
    metadata.pid <= 0
  ) {
    throw new Error("invalid release state lock metadata");
  }
  return metadata;
}

function lockOwnerIsStale(pid) {
  try {
    process.kill(pid, 0);
    return false;
  } catch (error) {
    return error?.code === "ESRCH";
  }
}

function removeStaleOwnerTemporaryFiles(evidencePath, ownerPID) {
  assertEvidencePathUnchanged(evidencePath);
  const prefix = `.release-state.${ownerPID}.`;
  for (const entry of fs.readdirSync(evidencePath.directory)) {
    if (!entry.startsWith(prefix) || !entry.endsWith(".tmp")) continue;
    const temporaryPath = path.join(evidencePath.directory, entry);
    const stats = assertSafeFileTarget(temporaryPath, "temporary");
    if (!stats) continue;
    removeOwnedFile(temporaryPath, stats, "temporary");
  }
  assertEvidencePathUnchanged(evidencePath);
}

function assertReclaimLockIdentity(lockPath, expectedStats) {
  const current = assertSafeFileTarget(lockPath, "lock");
  if (!current) {
    throw new Error("release state writer lock is already held");
  }
  if (!sameFileIdentity(current, expectedStats)) {
    throw new Error("release state writer lock changed during stale reclaim");
  }
}

function reclaimStaleWriterLock(evidencePath, lockPath) {
  let opened;
  try {
    opened = openRegularFile(lockPath, "lock");
  } catch (error) {
    if (!lstatIfExists(lockPath)) {
      throw new Error("release state writer lock is already held");
    }
    throw error;
  }
  try {
    const metadata = parseLockMetadata(
      fs.readFileSync(opened.descriptor, "utf8"),
    );
    if (!lockOwnerIsStale(metadata.pid)) {
      throw new Error("release state writer lock is already held");
    }

    assertEvidencePathUnchanged(evidencePath);
    assertReclaimLockIdentity(lockPath, opened.stats);
    removeStaleOwnerTemporaryFiles(evidencePath, metadata.pid);
    assertReclaimLockIdentity(lockPath, opened.stats);

    try {
      fs.unlinkSync(lockPath);
    } catch (error) {
      if (error?.code === "ENOENT") {
        throw new Error("release state writer lock is already held");
      }
      throw error;
    }
    if (fs.fstatSync(opened.descriptor).nlink !== 0) {
      installFailClosedLock(lockPath);
      throw new Error("release state writer lock changed during stale reclaim");
    }
  } finally {
    fs.closeSync(opened.descriptor);
  }
}

function acquireWriterLock(evidencePath) {
  assertEvidencePathUnchanged(evidencePath);
  const lockPath = path.join(evidencePath.directory, "release-state.lock");
  const existing = lstatIfExists(lockPath);
  if (existing) {
    assertSafeFileTarget(lockPath, "lock");
    reclaimStaleWriterLock(evidencePath, lockPath);
    assertEvidencePathUnchanged(evidencePath);
  }

  let descriptor;
  try {
    descriptor = fs.openSync(
      lockPath,
      fs.constants.O_WRONLY |
        fs.constants.O_CREAT |
        fs.constants.O_EXCL |
        (fs.constants.O_NOFOLLOW ?? 0),
      0o600,
    );
  } catch (error) {
    if (error?.code === "EEXIST" || error?.code === "ELOOP") {
      const raced = lstatIfExists(lockPath);
      if (raced?.isSymbolicLink() || (raced && !raced.isFile())) {
        assertSafeFileTarget(lockPath, "lock");
      }
      throw new Error("release state writer lock is already held");
    }
    throw error;
  }

  let stats;
  try {
    stats = fs.fstatSync(descriptor);
    if (!stats.isFile()) {
      throw new Error("unsafe release state lock target is not a regular file");
    }
    assertEvidencePathUnchanged(evidencePath);
    fs.writeFileSync(descriptor, serializeLockMetadata(process.pid), {
      encoding: "utf8",
    });
    fs.fsyncSync(descriptor);
    return { descriptor, evidencePath, lockPath, stats };
  } catch (error) {
    fs.closeSync(descriptor);
    if (stats) removeOwnedFile(lockPath, stats, "lock");
    throw error;
  }
}

function installFailClosedLock(lockPath) {
  let descriptor;
  try {
    descriptor = fs.openSync(
      lockPath,
      fs.constants.O_WRONLY |
        fs.constants.O_CREAT |
        fs.constants.O_EXCL |
        (fs.constants.O_NOFOLLOW ?? 0),
      0o600,
    );
    fs.writeFileSync(descriptor, "unsafe previous lock replacement detected\n", {
      encoding: "utf8",
    });
    fs.fsyncSync(descriptor);
  } catch (error) {
    if (error?.code !== "EEXIST" && error?.code !== "ELOOP") throw error;
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
  }
}

function releaseWriterLock(lock) {
  try {
    assertEvidencePathUnchanged(lock.evidencePath);
    const current = lstatIfExists(lock.lockPath);
    const opened = fs.fstatSync(lock.descriptor);
    if (
      !current ||
      current.isSymbolicLink() ||
      !current.isFile() ||
      !sameFileIdentity(current, opened) ||
      !sameFileIdentity(opened, lock.stats)
    ) {
      throw new Error("unsafe release state lock target changed while held");
    }
    fs.unlinkSync(lock.lockPath);
    if (fs.fstatSync(lock.descriptor).nlink !== 0) {
      installFailClosedLock(lock.lockPath);
      throw new Error("unsafe release state lock target changed before unlink");
    }
  } finally {
    fs.closeSync(lock.descriptor);
  }
}

function createTemporaryStateFile(temporaryPath, contents) {
  if (lstatIfExists(temporaryPath)) {
    assertSafeFileTarget(temporaryPath, "temporary");
    throw new Error("unsafe release state temporary target already exists");
  }

  let descriptor;
  try {
    descriptor = fs.openSync(
      temporaryPath,
      fs.constants.O_WRONLY |
        fs.constants.O_CREAT |
        fs.constants.O_EXCL |
        (fs.constants.O_NOFOLLOW ?? 0),
      0o600,
    );
  } catch (error) {
    if (error?.code === "EEXIST" || error?.code === "ELOOP") {
      throw new Error("unsafe release state temporary target already exists");
    }
    throw error;
  }

  let stats;
  try {
    stats = fs.fstatSync(descriptor);
    if (!stats.isFile()) {
      throw new Error("unsafe release state temporary target is not a regular file");
    }
    fs.writeFileSync(descriptor, contents, { encoding: "utf8" });
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    const current = assertSafeFileTarget(temporaryPath, "temporary", {
      required: true,
    });
    if (!sameFileIdentity(current, stats)) {
      throw new Error("unsafe release state temporary target changed while writing");
    }
    return stats;
  } catch (error) {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (stats) removeOwnedFile(temporaryPath, stats, "temporary");
    throw error;
  }
}

function removeOwnedTemporary(temporaryPath, expectedStats) {
  removeOwnedFile(temporaryPath, expectedStats, "temporary");
}

function assertNotarizationStatusAdvance(previous, next) {
  const allowed = {
    Submitted: new Set(["Submitted", "In Progress", "Accepted", "Invalid", "Rejected"]),
    "In Progress": new Set(["In Progress", "Accepted", "Invalid", "Rejected"]),
    Accepted: new Set(["Accepted"]),
    Invalid: new Set(["Invalid"]),
    Rejected: new Set(["Rejected"]),
  };
  if (!allowed[previous]?.has(next)) {
    throw new Error(`release state cannot regress notarization status from ${previous} to ${next}`);
  }
}

function assertUnchanged(previous, next, label) {
  if (!isDeepStrictEqual(previous, next)) {
    throw new Error(`release state cannot change ${label}`);
  }
}

function assertPreserved(previous, next, keyPath) {
  if (previous === undefined) return;
  if (Array.isArray(previous)) {
    if (!Array.isArray(next) || next.length < previous.length) {
      throw new Error(`release state cannot remove ${keyPath} history`);
    }
    for (const [index, value] of previous.entries()) {
      assertPreserved(value, next[index], `${keyPath}.${index}`);
    }
    return;
  }
  if (isPlainObject(previous)) {
    if (!isPlainObject(next)) {
      throw new Error(`release state cannot remove ${keyPath}`);
    }
    for (const [key, value] of Object.entries(previous)) {
      const childPath = `${keyPath}.${key}`;
      if (!Object.hasOwn(next, key)) {
        throw new Error(`release state cannot remove ${childPath}`);
      }
      assertPreserved(value, next[key], childPath);
    }
    return;
  }
  if (!isDeepStrictEqual(previous, next)) {
    throw new Error(`release state cannot change ${keyPath}`);
  }
}

function assertMonotonicAdvance(previous, next) {
  assertUnchanged(previous.schemaVersion, next.schemaVersion, "schemaVersion");
  assertUnchanged(previous.contract, next.contract, "contract");
  assertUnchanged(previous.source, next.source, "source");
  assertUnchanged(previous.identity, next.identity, "identity");

  if (previous.notarization !== undefined) {
    if (next.notarization === undefined) {
      throw new Error("release state cannot remove notarization");
    }
    assertUnchanged(
      previous.notarization.submissionID,
      next.notarization.submissionID,
      "notarization submission ID",
    );
    assertNotarizationStatusAdvance(
      previous.notarization.status,
      next.notarization.status,
    );
  }

  for (const key of ["phases", "artifacts", "publication", "acceptance"]) {
    assertPreserved(previous[key], next[key], key);
  }
}

export function saveReleaseState(repositoryRoot, state) {
  validateReleaseState(state);
  const destination = statePathFor(repositoryRoot, state.contract.tag);
  const evidencePath = evidenceDirectoryFor(repositoryRoot, state.contract.tag, {
    create: true,
  });
  const lock = acquireWriterLock(evidencePath);
  const { directory } = evidencePath;
  let previousStateStats;
  let temporaryStats;
  const temporaryPath = path.join(
    directory,
    `.release-state.${process.pid}.${crypto.randomUUID()}.tmp`,
  );
  try {
    assertEvidencePathUnchanged(evidencePath);
    if (assertSafeFileTarget(destination, "state")) {
      const previousFile = readRegularFile(destination, "state");
      const previous = JSON.parse(previousFile.contents);
      previousStateStats = previousFile.stats;
      validateReleaseState(previous, state.contract);
      assertMonotonicAdvance(previous, state);
    }
    assertEvidencePathUnchanged(evidencePath);
    temporaryStats = createTemporaryStateFile(
      temporaryPath,
      `${JSON.stringify(state, null, 2)}\n`,
    );
    assertEvidencePathUnchanged(evidencePath);
    const currentStateStats = assertSafeFileTarget(destination, "state");
    if (previousStateStats) {
      if (
        !currentStateStats ||
        !sameFileIdentity(currentStateStats, previousStateStats)
      ) {
        throw new Error("release state target changed before commit");
      }
    } else if (currentStateStats) {
      throw new Error("release state target appeared before commit");
    }
    fs.renameSync(temporaryPath, destination);
    temporaryStats = undefined;
    assertEvidencePathUnchanged(evidencePath);
    assertSafeFileTarget(destination, "state", { required: true });
  } finally {
    try {
      if (temporaryStats) removeOwnedTemporary(temporaryPath, temporaryStats);
    } finally {
      releaseWriterLock(lock);
    }
  }
  return destination;
}

export function loadReleaseState(repositoryRoot, tag) {
  const expectedContract = contractFor(tag);
  const evidencePath = evidenceDirectoryFor(repositoryRoot, tag, { create: false });
  assertEvidencePathUnchanged(evidencePath);
  const stateFile = readRegularFile(statePathFor(repositoryRoot, tag), "state");
  assertEvidencePathUnchanged(evidencePath);
  const state = JSON.parse(stateFile.contents);
  validateReleaseState(state, expectedContract);
  return deepFreeze(state);
}

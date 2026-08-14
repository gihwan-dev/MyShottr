#!/usr/bin/env node
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const semverPattern = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
const expectedVersion = process.argv[2] ?? "";

function fail(message, status = 1) {
  process.stderr.write(`release-metadata: ${message}\n`);
  process.exit(status);
}

if (!semverPattern.test(expectedVersion)) {
  fail("version must match [0-9]+\\.[0-9]+\\.[0-9]+ without leading zeros", 64);
}

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const project = readFileSync(path.join(repositoryRoot, "project.yml"), "utf8");
const plist = readFileSync(
  path.join(repositoryRoot, "Config/Inkbeam-Info.plist"),
  "utf8",
);
const manifest = JSON.parse(readFileSync(
  path.join(repositoryRoot, "Packages/chrome-extension/public/manifest.json"),
  "utf8",
));

const marketingVersions = [
  ...project.matchAll(/^\s*MARKETING_VERSION:\s*"?([^"\s#]+)"?\s*$/gm),
].map((match) => match[1]);
const projectBundleVersions = [
  ...project.matchAll(/^\s*CFBundleShortVersionString:\s*"?([^"\s#]+)"?\s*$/gm),
].map((match) => match[1]);
const projectBundleBuildVersions = [
  ...project.matchAll(/^\s*CFBundleVersion:\s*"?([^"\s#]+)"?\s*$/gm),
].map((match) => match[1]);
const projectReleaseChannels = [
  ...project.matchAll(/^\s*InkbeamReleaseChannel:\s*"?([^"\s#]+)"?\s*$/gm),
].map((match) => match[1]);
const plistBundleVersions = [
  ...plist.matchAll(
    /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/g,
  ),
].map((match) => match[1]);
const plistBundleBuildVersions = [
  ...plist.matchAll(/<key>CFBundleVersion<\/key>\s*<string>([^<]+)<\/string>/g),
].map((match) => match[1]);
const plistReleaseChannels = [
  ...plist.matchAll(/<key>InkbeamReleaseChannel<\/key>\s*<string>([^<]+)<\/string>/g),
].map((match) => match[1]);
const manifestVersions = Object.hasOwn(manifest, "version")
  && typeof manifest.version === "string"
  ? [manifest.version]
  : [];

const surfaces = [
  ["project.yml MARKETING_VERSION", marketingVersions],
  ["project.yml CFBundleShortVersionString", projectBundleVersions],
  ["project.yml CFBundleVersion", projectBundleBuildVersions],
  ["project.yml InkbeamReleaseChannel", projectReleaseChannels],
  ["Config/Inkbeam-Info.plist CFBundleShortVersionString", plistBundleVersions],
  ["Config/Inkbeam-Info.plist CFBundleVersion", plistBundleBuildVersions],
  ["Config/Inkbeam-Info.plist InkbeamReleaseChannel", plistReleaseChannels],
  ["Chrome manifest version", manifestVersions],
];
const failures = surfaces.flatMap(([label, versions]) => {
  if (versions.length !== 1) {
    return `${label} must appear exactly once (found ${versions.length})`;
  }
  if (label.endsWith("MARKETING_VERSION") || label.endsWith("Chrome manifest version")) {
    return versions[0] === expectedVersion
      ? []
      : `${label} is ${versions[0]}, expected ${expectedVersion}`;
  }
  if (label.endsWith("CFBundleShortVersionString")) {
    return versions[0] === "$(MARKETING_VERSION)"
      ? []
      : `${label} is ${versions[0]}, expected $(MARKETING_VERSION)`;
  }
  if (label.endsWith("CFBundleVersion")) {
    return versions[0] === "$(CURRENT_PROJECT_VERSION)"
      ? []
      : `${label} is ${versions[0]}, expected $(CURRENT_PROJECT_VERSION)`;
  }
  if (label.endsWith("InkbeamReleaseChannel")) {
    return versions[0] === "$(INKBEAM_RELEASE_CHANNEL_NAME)"
      ? []
      : `${label} is ${versions[0]}, expected $(INKBEAM_RELEASE_CHANNEL_NAME)`;
  }
  return [];
});

if (failures.length > 0) {
  fail(`release graph does not expose one common ${expectedVersion} version\n- ${failures.join("\n- ")}`);
}

process.stdout.write(`release-metadata: PASS (${expectedVersion})\n`);

#!/usr/bin/env node

import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export class ReleaseNotesError extends Error {
  constructor(message) {
    super(message);
    this.name = "ReleaseNotesError";
  }
}

export const COMMIT_MARKER = "<!-- INKBEAM_RELEASE_COMMIT -->";
export const CHECKSUM_MARKER = "<!-- INKBEAM_RELEASE_CHECKSUMS -->";

function fail(message) {
  throw new ReleaseNotesError(message);
}

function occurrences(source, needle) {
  return source.split(needle).length - 1;
}

function validateVersion(version) {
  if (!/^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(version)) {
    fail("version must be an exact semantic version without a v prefix");
  }
}

function validateCommitSHA(commitSHA) {
  if (!/^[0-9a-f]{40}$/.test(commitSHA)) {
    fail("release commit must be one lowercase 40-hex SHA");
  }
}

function parseChecksums(checksumSource, version) {
  const expectedNames = [
    `Inkbeam-${version}-macos.zip`,
    `Inkbeam-Chrome-${version}.zip`,
  ];
  const normalized = checksumSource.endsWith("\n")
    ? checksumSource.slice(0, -1)
    : checksumSource;
  const lines = normalized.split("\n");
  if (lines.length !== expectedNames.length) {
    fail("SHA256SUMS.txt must contain exactly two entries");
  }
  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(/^([0-9a-f]{64})  ([A-Za-z0-9.-]+)$/);
    if (!match || match[2] !== expectedNames[index]) {
      fail("SHA256SUMS.txt contains an unexpected or reordered entry");
    }
  }
  return lines;
}

export function renderReleaseNotes(template, checksumSource, version, commitSHA) {
  validateVersion(version);
  validateCommitSHA(commitSHA);
  const checksumLines = parseChecksums(checksumSource, version);

  if (!template.startsWith(`# Inkbeam v${version}\n`)) {
    fail("release-note title does not match the requested version");
  }
  for (const name of [
    `Inkbeam-${version}-macos.zip`,
    `Inkbeam-Chrome-${version}.zip`,
    "SHA256SUMS.txt",
  ]) {
    if (!template.includes(name)) {
      fail(`release-note template is missing asset ${name}`);
    }
  }
  for (const marker of [COMMIT_MARKER, CHECKSUM_MARKER]) {
    if (occurrences(template, marker) !== 1) {
      fail(`release-note template must contain ${marker} exactly once`);
    }
  }
  if (/^[0-9a-fA-F]{64}  [A-Za-z0-9.-]+$/m.test(template)) {
    fail("release-note template must not commit environment-specific archive hashes");
  }
  const screenshotProvenanceStart = template.indexOf(
    "\n## Documentation screenshot provenance\n",
  );
  const screenshotProvenanceEnd = screenshotProvenanceStart === -1
    ? -1
    : template.indexOf("\n## ", screenshotProvenanceStart + 1);
  const releaseIdentityRegion = screenshotProvenanceStart === -1
    ? template
    : template.slice(0, screenshotProvenanceStart)
      + template.slice(
        screenshotProvenanceEnd === -1 ? template.length : screenshotProvenanceEnd,
      );
  if (/[0-9a-fA-F]{40}/.test(releaseIdentityRegion)) {
    fail("release-note template must not pin a release commit outside the dynamic marker");
  }
  if (screenshotProvenanceStart !== -1) {
    const screenshotProvenance = template.slice(
      screenshotProvenanceStart,
      screenshotProvenanceEnd === -1 ? template.length : screenshotProvenanceEnd,
    );
    if ((screenshotProvenance.match(/[0-9a-fA-F]{40}/g) ?? []).length !== 1) {
      fail("documentation screenshot provenance must contain exactly one source commit");
    }
  }

  const rendered = template
    .replace(COMMIT_MARKER, `Tagged commit: \`${commitSHA}\``)
    .replace(
      CHECKSUM_MARKER,
      ["```text", ...checksumLines, "```"].join("\n"),
    );

  if (rendered.includes(COMMIT_MARKER) || rendered.includes(CHECKSUM_MARKER)) {
    fail("release-note markers remain after rendering");
  }
  if (!rendered.includes(`Tagged commit: \`${commitSHA}\``)) {
    fail("rendered release notes lost the exact tagged commit");
  }
  if ((rendered.match(/^Tagged commit: `[0-9a-f]{40}`$/gm) ?? []).length !== 1) {
    fail("rendered release notes must contain exactly one tagged commit line");
  }
  const renderedChecksumLines = rendered
    .split("\n")
    .filter((line) => /^[0-9a-f]{64}  [A-Za-z0-9.-]+$/.test(line));
  if (JSON.stringify(renderedChecksumLines) !== JSON.stringify(checksumLines)) {
    fail("rendered release-note checksums differ from SHA256SUMS.txt");
  }
  return rendered;
}

function runCLI(argv) {
  if (argv.length !== 4) {
    process.stderr.write(
      "Usage: node Scripts/render-release-notes.mjs <template> <SHA256SUMS.txt> <version> <commit-sha>\n",
    );
    process.exitCode = 2;
    return;
  }
  const [templatePath, checksumsPath, version, commitSHA] = argv;
  process.stdout.write(
    renderReleaseNotes(
      readFileSync(templatePath, "utf8"),
      readFileSync(checksumsPath, "utf8"),
      version,
      commitSHA,
    ),
  );
}

if (
  process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    runCLI(process.argv.slice(2));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`release-notes: ${message}\n`);
    process.exitCode = 1;
  }
}

#!/usr/bin/env node

import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

export class ReleaseEvidenceError extends Error {
  constructor(message) {
    super(message);
    this.name = "ReleaseEvidenceError";
  }
}

export const ACCEPTANCE_CHECKS = Object.freeze([
  "1. Native region shortcut",
  "2. Capture cancellation",
  "3. Retina source dimensions",
  "4. Overlay exclusion",
  "5. Chrome visible viewport",
  "6. Chrome keyboard command",
  "7. Drawing tools and live preview",
  "8. Annotation editing and shortcut ownership",
  "9. Clipboard PNG",
  "10. Export dimensions",
  "11. Project round trip and migration",
  "12. Modified-document close",
  "13. Direct capture launch",
  "14. Screen Recording denial",
  "15. Missing Chrome host",
  "16. Unsupported project version",
  "17. Failed export",
  "18. Save terminal truthfulness and exact-artifact privacy gate",
]);

export const RELEASE_INSTALL_CHECKS = Object.freeze([
  "SHA-256 verification",
  "App launch",
  "Native region capture",
  "Chrome visible-viewport capture",
  "Project reopen",
  "Extension manifest permissions",
  "Gatekeeper behavior",
]);

const ACCEPTANCE_CANDIDATE_FIELDS = Object.freeze([
  "Date",
  "macOS version",
  "Google Chrome version",
  "Tested commit SHA",
  "`Scripts/verify-v1.sh` result",
  "`Scripts/verify-v1.sh` evidence",
]);

const RELEASE_INSTALL_CANDIDATE_FIELDS = Object.freeze([
  "Tag",
  "Exact release commit SHA",
  "CI workflow URL",
  "Release workflow URL",
  "Live release URL",
  "Download source URL",
  "Test date and timezone",
  "macOS version",
  "Google Chrome version",
  "Tester",
]);

const RELEASE_INSTALL_FINAL_FIELDS = Object.freeze([
  "Overall result",
  "Exact release commit SHA rechecked",
  "Remote tag dereference SHA",
  "Downloaded release URL rechecked",
  "Git note attachment SHA",
  "Reviewer",
  "Notes",
]);

function fail(message) {
  throw new ReleaseEvidenceError(message);
}

function requireExactSHA(value, label) {
  if (!/^[0-9a-f]{40}$/.test(value)) {
    fail(`${label} must be one lowercase 40-hex commit SHA`);
  }
  return value;
}

function requireExactSHA256(value, label) {
  if (!/^[0-9a-f]{64}$/.test(value)) {
    fail(`${label} must be one lowercase 64-hex SHA-256`);
  }
  return value;
}

function unwrapCode(value) {
  if (value.startsWith("`") && value.endsWith("`") && value.length >= 2) {
    return value.slice(1, -1);
  }
  return value;
}

function markdownHeadings(source, level) {
  const marker = "#".repeat(level);
  return [...source.matchAll(new RegExp(`^${marker} ([^\\n]+)$`, "gm"))].map(
    (match) => match[1],
  );
}

function normalizeMarkdown(source, label) {
  if (source.includes("\r") && !source.includes("\r\n")) {
    fail(`${label} contains an unsupported carriage return`);
  }
  return source.replaceAll("\r\n", "\n");
}

function sectionAfterHeading(source, heading, level, nextLevel = level) {
  const marker = "#".repeat(level);
  const needle = `${marker} ${heading}`;
  const start = source.indexOf(needle);
  if (start === -1 || source.indexOf(needle, start + needle.length) !== -1) {
    fail(`expected exactly one ${needle} section`);
  }
  const bodyStart = source.indexOf("\n", start);
  if (bodyStart === -1) {
    fail(`${needle} has no body`);
  }
  const nextMarker = "#".repeat(nextLevel);
  const next = source.indexOf(`\n${nextMarker} `, bodyStart + 1);
  return source.slice(bodyStart + 1, next === -1 ? source.length : next);
}

function parseListFields(section, expectedLabels, label) {
  const lines = section.split("\n");
  const entries = [];

  for (let index = 0; index < lines.length; index += 1) {
    const match = lines[index].match(/^- ([^:\n]+):(.*)$/);
    if (!match) continue;

    const continuation = [];
    let cursor = index + 1;
    while (cursor < lines.length && /^(?:  |\t)\S/.test(lines[cursor])) {
      continuation.push(lines[cursor].trim());
      cursor += 1;
    }
    entries.push({
      name: match[1],
      value: [match[2].trim(), ...continuation].filter(Boolean).join(" "),
    });
  }

  const actualLabels = entries.map((entry) => entry.name);
  if (JSON.stringify(actualLabels) !== JSON.stringify(expectedLabels)) {
    fail(
      `${label} fields changed: expected ${expectedLabels.join(", ")}; got ${actualLabels.join(", ")}`,
    );
  }

  const values = Object.fromEntries(entries.map((entry) => [entry.name, entry.value]));
  for (const field of expectedLabels) {
    if (!values[field]) {
      fail(`${label} field '${field}' is empty`);
    }
    if (!/[\p{L}\p{N}]/u.test(values[field])) {
      fail(`${label} field '${field}' has no substantive value`);
    }
    if (/\b(?:FAIL|BLOCKED)\b/.test(values[field])) {
      fail(`${label} field '${field}' contains a non-passing status token`);
    }
  }
  return values;
}

function rejectPlaceholders(source, label) {
  const placeholder = source.match(/<[^>\n]+>/)?.[0];
  if (placeholder) {
    fail(`${label} contains placeholder ${placeholder}`);
  }
  if (/<!--[\s\S]*?-->/.test(source)) {
    fail(`${label} contains an HTML placeholder comment`);
  }
  if (/\b(?:TODO|TBD|TBC|FIXME|PLACEHOLDER)\b/.test(source)) {
    fail(`${label} contains an unfinished placeholder token`);
  }
  if (/\[ \]/.test(source)) {
    fail(`${label} contains an incomplete checklist item`);
  }
}

function validateDate(value, label) {
  if (!/^\d{4}-\d{2}-\d{2}(?:[ T].+)?$/.test(unwrapCode(value))) {
    fail(`${label} must begin with an ISO date`);
  }
}

function validatePassingCheckSection(section, label) {
  const fields = parseListFields(section, ["Result", "Evidence"], label);
  if (unwrapCode(fields.Result) !== "PASS") {
    fail(`${label} result must be PASS`);
  }
  return fields.Evidence;
}

function exactSection(source, heading, allHeadings, level) {
  const marker = "#".repeat(level);
  const index = allHeadings.indexOf(heading);
  if (index === -1) fail(`missing ${marker} ${heading}`);
  const startNeedle = `${marker} ${heading}`;
  const start = source.indexOf(startNeedle);
  const bodyStart = source.indexOf("\n", start);
  const remaining = source.slice(bodyStart + 1);
  const nextHeadingMatch = remaining.match(
    new RegExp(`^#{1,${level}} `, "m"),
  );
  const next = nextHeadingMatch?.index === undefined
    ? source.length
    : bodyStart + 1 + nextHeadingMatch.index;
  return source.slice(bodyStart + 1, next);
}

export function validateAcceptanceReport(source, expectedSHA) {
  source = normalizeMarkdown(source, "acceptance report");
  requireExactSHA(expectedSHA, "expected SHA");
  rejectPlaceholders(source, "acceptance report");

  const h1 = markdownHeadings(source, 1);
  if (JSON.stringify(h1) !== JSON.stringify(["MyShottr v1 manual acceptance record"])) {
    fail("acceptance report must contain the exact H1 title");
  }

  const h2 = markdownHeadings(source, 2);
  const expectedH2 = ["Candidate", "Checks", "Final decision"];
  if (JSON.stringify(h2) !== JSON.stringify(expectedH2)) {
    fail(`acceptance report H2 sections changed: ${h2.join(", ")}`);
  }

  const h3 = markdownHeadings(source, 3);
  if (JSON.stringify(h3) !== JSON.stringify(ACCEPTANCE_CHECKS)) {
    fail(`acceptance report must contain the exact 18 checks in order`);
  }

  const candidate = parseListFields(
    sectionAfterHeading(source, "Candidate", 2),
    ACCEPTANCE_CANDIDATE_FIELDS,
    "acceptance candidate",
  );
  validateDate(candidate.Date, "acceptance date");
  if (unwrapCode(candidate["Tested commit SHA"]) !== expectedSHA) {
    fail("acceptance tested commit SHA does not match the expected SHA");
  }
  if (unwrapCode(candidate["`Scripts/verify-v1.sh` result"]) !== "PASS") {
    fail("Scripts/verify-v1.sh result must be PASS");
  }

  if ((source.match(/^- Result:/gm) ?? []).length !== ACCEPTANCE_CHECKS.length) {
    fail("acceptance report must contain exactly 18 Result fields");
  }
  if ((source.match(/^- Evidence:/gm) ?? []).length !== ACCEPTANCE_CHECKS.length) {
    fail("acceptance report must contain exactly 18 Evidence fields");
  }

  for (const check of ACCEPTANCE_CHECKS) {
    validatePassingCheckSection(
      exactSection(source, check, h3, 3),
      `acceptance check '${check}'`,
    );
  }

  const decision = parseListFields(
    sectionAfterHeading(source, "Final decision", 2),
    ["Overall result", "Reviewer", "Notes"],
    "acceptance final decision",
  );
  if (unwrapCode(decision["Overall result"]) !== "PASS") {
    fail("acceptance overall result must be PASS");
  }

  return Object.freeze({
    kind: "acceptance",
    expectedSHA,
    checkCount: ACCEPTANCE_CHECKS.length,
  });
}

function parseChecksumEntries(source, version) {
  const expectedNames = [
    `MyShottr-${version}-macos.zip`,
    `MyShottr-Chrome-${version}.zip`,
  ];
  const normalized = source.endsWith("\n") ? source.slice(0, -1) : source;
  const lines = normalized.split("\n");
  if (lines.length !== expectedNames.length) {
    fail("SHA256SUMS.txt must contain exactly two entries");
  }
  const entries = lines.map((line, index) => {
    const match = line.match(/^([0-9a-f]{64})  ([A-Za-z0-9.-]+)$/);
    if (!match || match[2] !== expectedNames[index]) {
      fail("SHA256SUMS.txt contains an unexpected or reordered entry");
    }
    return [match[2], match[1]];
  });
  return Object.fromEntries(entries);
}

function validateWorkflowURL(value, label) {
  if (!/^https:\/\/github\.com\/gihwan-dev\/MyShottr\/actions\/runs\/[1-9][0-9]*$/.test(value)) {
    fail(`${label} must be an exact MyShottr GitHub Actions run URL`);
  }
}

function parseArtifactRows(section, expectedArtifacts) {
  const rows = section
    .split("\n")
    .filter((line) => /^\| `/.test(line));
  if (rows.length !== expectedArtifacts.length) {
    fail("release-install artifact table must contain exactly three data rows");
  }

  return rows.map((line, index) => {
    const match = line.match(
      /^\| `([^`]+)` \| `([0-9a-f]{64})` \| `([1-9][0-9]*)` \| `PASS` \|$/,
    );
    if (!match) {
      fail("release-install artifact rows require exact hashes, positive sizes, and PASS");
    }
    if (match[1] !== expectedArtifacts[index].name) {
      fail("release-install artifact rows are missing, unexpected, or reordered");
    }
    if (match[2] !== expectedArtifacts[index].sha256) {
      fail(`release-install hash mismatch for ${match[1]}`);
    }
    return Object.freeze({
      name: match[1],
      sha256: match[2],
      size: Number(match[3]),
    });
  });
}

export function validateReleaseInstallReport(
  source,
  expectedSHA,
  expectedTag,
  checksumSource,
  checksumAssetSHA,
) {
  source = normalizeMarkdown(source, "release-install report");
  requireExactSHA(expectedSHA, "expected SHA");
  requireExactSHA256(checksumAssetSHA, "SHA256SUMS.txt SHA-256");
  if (!/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/.test(expectedTag)) {
    fail("expected tag must be an exact semantic release tag");
  }
  rejectPlaceholders(source, "release-install report");

  const h1 = markdownHeadings(source, 1);
  if (JSON.stringify(h1) !== JSON.stringify([
    `MyShottr ${expectedTag} release-installation record`,
  ])) {
    fail("release-install report must contain the exact H1 title");
  }

  const version = expectedTag.slice(1);
  const checksumEntries = parseChecksumEntries(checksumSource, version);
  const liveReleaseURL = `https://github.com/gihwan-dev/MyShottr/releases/tag/${expectedTag}`;
  const downloadURL = `https://github.com/gihwan-dev/MyShottr/releases/download/${expectedTag}/`;

  const h2 = markdownHeadings(source, 2);
  const expectedH2 = [
    "Candidate and live release",
    "Downloaded artifacts",
    "Installation and product checks",
    "Final decision",
  ];
  if (JSON.stringify(h2) !== JSON.stringify(expectedH2)) {
    fail(`release-install report H2 sections changed: ${h2.join(", ")}`);
  }

  const h3 = markdownHeadings(source, 3);
  const expectedH3 = ["Downloaded artifact sizes", ...RELEASE_INSTALL_CHECKS];
  if (JSON.stringify(h3) !== JSON.stringify(expectedH3)) {
    fail("release-install report must contain the exact checks in order");
  }
  if ((source.match(/^- Result:/gm) ?? []).length !== RELEASE_INSTALL_CHECKS.length) {
    fail("release-install report must contain exactly seven Result fields");
  }
  if ((source.match(/^- Evidence:/gm) ?? []).length !== RELEASE_INSTALL_CHECKS.length + 1) {
    fail("release-install report must contain exactly eight Evidence fields");
  }

  const candidate = parseListFields(
    sectionAfterHeading(source, "Candidate and live release", 2),
    RELEASE_INSTALL_CANDIDATE_FIELDS,
    "release-install candidate",
  );
  if (unwrapCode(candidate.Tag) !== expectedTag) {
    fail("release-install tag does not match the expected tag");
  }
  if (unwrapCode(candidate["Exact release commit SHA"]) !== expectedSHA) {
    fail("release-install commit SHA does not match the expected SHA");
  }
  validateWorkflowURL(unwrapCode(candidate["CI workflow URL"]), "CI workflow URL");
  validateWorkflowURL(
    unwrapCode(candidate["Release workflow URL"]),
    "Release workflow URL",
  );
  if (unwrapCode(candidate["Live release URL"]) !== liveReleaseURL) {
    fail("release-install live release URL does not match the expected tag");
  }
  if (unwrapCode(candidate["Download source URL"]) !== downloadURL) {
    fail("release-install download URL does not match the expected tag");
  }
  validateDate(candidate["Test date and timezone"], "release-install test date");

  const artifactSection = exactSection(
    source,
    "Downloaded artifact sizes",
    h3,
    3,
  );
  const artifacts = parseArtifactRows(artifactSection, [
    {
      name: `MyShottr-${version}-macos.zip`,
      sha256: checksumEntries[`MyShottr-${version}-macos.zip`],
    },
    {
      name: `MyShottr-Chrome-${version}.zip`,
      sha256: checksumEntries[`MyShottr-Chrome-${version}.zip`],
    },
    { name: "SHA256SUMS.txt", sha256: checksumAssetSHA },
  ]);
  parseListFields(artifactSection, ["Evidence"], "release-install artifact evidence");

  const appLaunchSection = exactSection(source, "App launch", h3, 3);
  if (!appLaunchSection.includes(`reports version \`${version}\``)) {
    fail("release-install app launch check does not name the expected app version");
  }

  for (const check of RELEASE_INSTALL_CHECKS) {
    validatePassingCheckSection(
      exactSection(source, check, h3, 3),
      `release-install check '${check}'`,
    );
  }

  const decision = parseListFields(
    sectionAfterHeading(source, "Final decision", 2),
    RELEASE_INSTALL_FINAL_FIELDS,
    "release-install final decision",
  );
  if (unwrapCode(decision["Overall result"]) !== "PASS") {
    fail("release-install overall result must be PASS");
  }
  for (const field of [
    "Exact release commit SHA rechecked",
    "Remote tag dereference SHA",
    "Git note attachment SHA",
  ]) {
    if (unwrapCode(decision[field]) !== expectedSHA) {
      fail(`release-install field '${field}' does not match the expected SHA`);
    }
  }
  if (unwrapCode(decision["Downloaded release URL rechecked"]) !== liveReleaseURL) {
    fail("release-install rechecked release URL does not match the expected tag");
  }

  return Object.freeze({
    kind: "release-install",
    expectedSHA,
    expectedTag,
    checkCount: RELEASE_INSTALL_CHECKS.length,
    artifacts,
  });
}

function readReport(path) {
  return readFileSync(path === "-" ? 0 : path, "utf8");
}

function printUsage() {
  process.stderr.write(
    "Usage:\n"
      + "  node Scripts/validate-release-evidence.mjs acceptance <report-path|-> <expected-sha>\n"
      + "  node Scripts/validate-release-evidence.mjs release-install <report-path|-> <expected-sha> <tag> <downloaded-SHA256SUMS.txt>\n",
  );
}

function runCLI(argv) {
  const [mode, reportPath, expectedSHA, expectedTag, checksumsPath] = argv;
  if (mode === "acceptance" && argv.length === 3) {
    const result = validateAcceptanceReport(readReport(reportPath), expectedSHA);
    process.stdout.write(
      `release-evidence: accepted ${result.checkCount} checks for ${result.expectedSHA}\n`,
    );
    return;
  }
  if (mode === "release-install" && argv.length === 5) {
    const checksumBytes = readFileSync(checksumsPath);
    const result = validateReleaseInstallReport(
      readReport(reportPath),
      expectedSHA,
      expectedTag,
      checksumBytes.toString("utf8"),
      createHash("sha256").update(checksumBytes).digest("hex"),
    );
    process.stdout.write(
      `release-evidence: accepted ${result.checkCount} install checks and ${result.artifacts.length} artifacts for ${result.expectedSHA}\n`,
    );
    return;
  }
  printUsage();
  process.exitCode = 2;
}

if (
  process.argv[1]
  && import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    runCLI(process.argv.slice(2));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`release-evidence: ${message}\n`);
    process.exitCode = 1;
  }
}

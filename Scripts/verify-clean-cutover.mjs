#!/usr/bin/env node

import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const requiredGeneratedProject = "Inkbeam.xcodeproj/project.pbxproj";
const scannedSurfaces = [
  "project.yml",
  requiredGeneratedProject,
  "package.json",
  "pnpm-lock.yaml",
  "Config",
  "Sources",
  "Packages",
  "Scripts",
  "Tests",
  "README.md",
  "docs",
];

const readmeStartMarker = "<!-- historical-v0.1.0:start -->";
const readmeEndMarker = "<!-- historical-v0.1.0:end -->";
const scannerDeclarationStart = ["/* clean-cutover-declarations", "start */"].join(":");
const scannerDeclarationEnd = ["/* clean-cutover-declarations", "end */"].join(":");

/* clean-cutover-declarations:start */
const banned = [
  "MyShottr",
  ".myshottr",
  "com.myshottr",
  "MyShottrNativeHost",
  "myshottr-editor",
  "QuickInk",
  "Quick Ink",
];

const exactHistoricalFiles = new Set([
  "docs/releases/v0.1.0.md",
  "docs/testing/historical/v0.1.0/release-installation.md",
  "docs/testing/historical/v0.1.0/v1-acceptance.md",
  "docs/superpowers/plans/2026-07-29-myshottr-chrome-capture.md",
  "docs/superpowers/plans/2026-07-29-myshottr-foundation-editor.md",
  "docs/superpowers/plans/2026-07-29-myshottr-native-capture.md",
  "docs/superpowers/plans/2026-07-29-myshottr-recovery-hardening.md",
  "docs/superpowers/plans/2026-07-29-myshottr-v1-roadmap.md",
  "docs/superpowers/plans/2026-07-30-myshottr-editor-public-polish.md",
  "docs/superpowers/plans/2026-07-30-myshottr-public-distribution.md",
  "docs/superpowers/plans/2026-07-30-myshottr-v1-public-release-roadmap.md",
  "docs/superpowers/plans/2026-07-31-myshottr-editor-ux-polish.md",
  "docs/superpowers/specs/2026-07-29-myshottr-v1-design.md",
  "docs/superpowers/specs/2026-07-30-myshottr-v1-public-release-design.md",
  "docs/superpowers/specs/2026-07-31-myshottr-editor-ux-polish-design.md",
  "docs/superpowers/specs/2026-08-02-inkbeam-rename-design.md",
  "docs/superpowers/specs/2026-08-03-inkbeam-v0.2.0-official-release-design.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-clean-cutover.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-sparkle-updater.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-direct-release-pipeline.md",
  "docs/superpowers/plans/2026-08-03-inkbeam-v0.2.0-rollout.md",
  "Scripts/verify-clean-cutover.mjs",
]);
/* clean-cutover-declarations:end */

function occurrencesOf(text, needle) {
  const offsets = [];
  let offset = text.indexOf(needle);
  while (offset !== -1) {
    offsets.push(offset);
    offset = text.indexOf(needle, offset + 1);
  }
  return offsets;
}

function maskRange(text, startOffset, endOffset) {
  return `${text.slice(0, startOffset)}${text
    .slice(startOffset, endOffset)
    .replace(/[^\n]/g, " ")}${text.slice(endOffset)}`;
}

function maskSingleSection(text, startMarker, endMarker) {
  const starts = occurrencesOf(text, startMarker);
  const ends = occurrencesOf(text, endMarker);
  if (starts.length === 0 && ends.length === 0) {
    return { text, malformed: false };
  }
  if (starts.length !== 1 || ends.length !== 1) {
    return { text, malformed: true };
  }

  const startOffset = starts[0];
  const endOffset = ends[0] + endMarker.length;
  if (startOffset >= ends[0]) {
    return { text, malformed: true };
  }
  return { text: maskRange(text, startOffset, endOffset), malformed: false };
}

function scanText(relativePath, text) {
  let scannedText = text;
  const violations = [];

  if (relativePath === "README.md") {
    const readme = maskSingleSection(scannedText, readmeStartMarker, readmeEndMarker);
    scannedText = readme.text;
    if (readme.malformed) {
      violations.push({
        relativePath,
        line: 0,
        column: 0,
        tokenIndex: -1,
        message: `${relativePath}: malformed historical-v0.1.0 marker section`,
      });
    }
  }

  if (relativePath === "Scripts/verify-clean-cutover.mjs") {
    const declarations = maskSingleSection(
      scannedText,
      scannerDeclarationStart,
      scannerDeclarationEnd,
    );
    if (declarations.malformed) {
      violations.push({
        relativePath,
        line: 0,
        column: 0,
        tokenIndex: -1,
        message: `${relativePath}: malformed scanner declaration section`,
      });
    } else {
      scannedText = declarations.text;
    }
  }

  const lines = scannedText.split("\n");
  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    for (let tokenIndex = 0; tokenIndex < banned.length; tokenIndex += 1) {
      const token = banned[tokenIndex];
      for (const offset of occurrencesOf(lines[lineIndex], token)) {
        const line = lineIndex + 1;
        const column = offset + 1;
        violations.push({
          relativePath,
          line,
          column,
          tokenIndex,
          message: `${relativePath}:${line}:${column}: banned token ${token}`,
        });
      }
    }
  }
  return violations;
}

function scanPath(relativePath) {
  const violations = [];
  for (let tokenIndex = 0; tokenIndex < banned.length; tokenIndex += 1) {
    const token = banned[tokenIndex];
    if (relativePath.includes(token)) {
      violations.push({
        relativePath,
        line: -1,
        column: -1,
        tokenIndex,
        message: `${relativePath}: path contains banned token ${token}`,
      });
    }
  }
  return violations;
}

async function collectRepositorySurfaceFiles(repositoryRoot) {
  const { stdout } = await execFileAsync(
    "git",
    [
      "ls-files",
      "--cached",
      "--others",
      "--exclude-standard",
      "-z",
      "--",
      ...scannedSurfaces,
    ],
    { cwd: repositoryRoot, encoding: "utf8", maxBuffer: 16 * 1024 * 1024 },
  );
  const relativePaths = stdout.split("\0").filter(Boolean);
  if (!relativePaths.includes(requiredGeneratedProject)) {
    relativePaths.push(requiredGeneratedProject);
  }
  return [...new Set(relativePaths)].sort((left, right) => (
    left < right ? -1 : Number(left > right)
  ));
}

function compareViolations(left, right) {
  const pathOrder = left.relativePath < right.relativePath
    ? -1
    : Number(left.relativePath > right.relativePath);
  return pathOrder
    || left.line - right.line
    || left.column - right.column
    || left.tokenIndex - right.tokenIndex
    || (left.message < right.message ? -1 : Number(left.message > right.message));
}

export async function collectCleanCutoverViolations(repositoryRoot) {
  const generatedProjectPath = path.join(repositoryRoot, requiredGeneratedProject);
  try {
    const generatedProject = await fs.stat(generatedProjectPath);
    if (!generatedProject.isFile()) throw Object.assign(new Error("not a file"), { code: "ENOENT" });
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    return [`${requiredGeneratedProject}: missing required generated project`];
  }

  const violations = [];
  const relativePaths = await collectRepositorySurfaceFiles(repositoryRoot);
  for (const relativePath of relativePaths) {
    const isScanner = relativePath === "Scripts/verify-clean-cutover.mjs";
    if (exactHistoricalFiles.has(relativePath) && !isScanner) continue;

    violations.push(...scanPath(relativePath));
    const stats = await fs.lstat(path.join(repositoryRoot, relativePath));
    if (!stats.isFile()) continue;

    const bytes = await fs.readFile(path.join(repositoryRoot, relativePath));
    let text;
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      continue;
    }
    violations.push(...scanText(relativePath, text));
  }

  return violations.sort(compareViolations).map(({ message }) => message);
}

async function main() {
  const scriptPath = fileURLToPath(import.meta.url);
  const repositoryRoot = path.dirname(path.dirname(scriptPath));
  const violations = await collectCleanCutoverViolations(repositoryRoot);

  if (violations.length > 0) {
    console.error(`clean-cutover: FAIL (${violations.length} violations)`);
    for (const violation of violations) console.error(`- ${violation}`);
    process.exitCode = 1;
    return;
  }
  console.log("clean-cutover: PASS");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}

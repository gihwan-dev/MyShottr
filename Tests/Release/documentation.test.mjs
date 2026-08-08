import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";

const paths = {
  readme: "README.md",
  license: "LICENSE",
  currentAcceptance: "docs/testing/inkbeam-acceptance.md",
  currentInstallation: "docs/testing/release-installation.md",
  historicalNotes: "docs/releases/v0.1.0.md",
  historicalAcceptance: "docs/testing/historical/v0.1.0/v1-acceptance.md",
  historicalInstallation:
    "docs/testing/historical/v0.1.0/release-installation.md",
  screenshot: "docs/images/editor-inkbeam.png",
};

for (const filePath of Object.values(paths)) {
  assert.ok(existsSync(filePath), `required documentation is missing: ${filePath}`);
}

const readme = readFileSync(paths.readme, "utf8");
const license = readFileSync(paths.license, "utf8");
const currentAcceptance = readFileSync(paths.currentAcceptance, "utf8");
const currentInstallation = readFileSync(paths.currentInstallation, "utf8");
const historicalNotes = readFileSync(paths.historicalNotes, "utf8");
const historicalAcceptance = readFileSync(paths.historicalAcceptance, "utf8");
const historicalInstallation = readFileSync(paths.historicalInstallation, "utf8");
const screenshot = readFileSync(paths.screenshot);

assert.deepEqual(markdownSections(readme, 2), [
  "Features",
  "Release status",
  "Use",
  "Annotation shortcuts",
  "Privacy",
  "Development",
  "Current limitations",
  "License",
]);
assert.match(readme, /^# Inkbeam\n\nCapture fast\. Mark freely\.\n/m);
assert.match(readme, /!\[Inkbeam editor\]\(docs\/images\/editor-inkbeam\.png\)/);

for (const contractText of [
  "macOS 15+",
  "Command-Shift-2",
  "Option-Shift-2",
  "Command-Shift-C",
  "Command-S",
  "Command-E",
  "Chrome",
  "visible-viewport only",
  "activeTab",
  "nativeMessaging",
  "Scripts/verify-inkbeam.sh",
  "open Inkbeam.xcodeproj",
  "docs/testing/inkbeam-acceptance.md",
]) {
  assert.ok(readme.includes(contractText), `README missing current contract: ${contractText}`);
}

for (const tool of [
  ["Select", "V"],
  ["Rectangle", "R"],
  ["Arrow", "A"],
  ["Line", "L"],
  ["Text", "T"],
  ["Freehand", "P"],
  ["Highlighter", "H"],
  ["Blur", "B"],
  ["Redaction", "X"],
  ["Number marker", "N"],
]) {
  assert.ok(readme.includes(`| ${tool[0]} | \`${tool[1]}\` |`));
}

for (const interaction of [
  /`Command-0` sets 100%/,
  /`Shift-1` fits the complete\s+image/,
  /`Shift-2` fits the current selection/,
  /drag empty canvas to preview a marquee/,
  /`Shift`-click toggles one annotation/,
  /differing multi-selection values labeled `Mixed`/,
  /toolbar order is Copy Image, Undo, Redo, flexible space, Save\s+Project, and Export PNG/,
  /hides the window without closing the\s+document/,
  /Light or Dark appearance[\s\S]*Reduce\s+Motion/,
]) {
  assert.match(readme, interaction);
}

assert.match(readme, /no account, cloud upload, analytics, or telemetry/i);
assert.match(readme, /Blur is a visual effect, not secure redaction/);
assert.match(readme, /does not claim.*signing, notarization,[\s\S]*public-release acceptance/i);
assert.doesNotMatch(readme, /\bsudo\b|\bcurl\b[^\n]*\|\s*(?:sh|bash|zsh)\b/);

const startMarker = "<!-- historical-v0.1.0:start -->";
const endMarker = "<!-- historical-v0.1.0:end -->";
assert.equal(readme.split(startMarker).length - 1, 1);
assert.equal(readme.split(endMarker).length - 1, 1);
const historicalStart = readme.indexOf(startMarker);
const historicalEnd = readme.indexOf(endMarker);
assert.ok(historicalStart < historicalEnd);
const historicalReadmeSection = readme.slice(historicalStart, historicalEnd);
for (const historicalPath of [
  paths.historicalNotes,
  paths.historicalAcceptance,
  paths.historicalInstallation,
]) {
  assert.ok(historicalReadmeSection.includes(historicalPath));
}

assert.deepEqual(markdownSections(currentAcceptance, 1), [
  "Inkbeam manual acceptance record",
]);
assert.deepEqual(markdownSections(currentAcceptance, 2), [
  "Candidate",
  "Checks",
  "Final decision",
]);
assert.equal(markdownSections(currentAcceptance, 3).length, 18);
assert.match(currentAcceptance, /refs\/notes\/inkbeam-acceptance/);
assert.match(currentAcceptance, /`Scripts\/verify-inkbeam\.sh` result/);
assert.match(currentAcceptance, /\.inkbeam` save and reopen/);
assert.match(currentAcceptance, /Older extensions and annotation schemas are rejected/);

assert.deepEqual(markdownSections(currentInstallation, 2), [
  "Candidate and live release",
  "Downloaded artifacts",
  "Installation and product checks",
  "Final decision",
]);
assert.match(
  currentInstallation,
  /https:\/\/github\.com\/gihwan-dev\/inkbeam\/actions\/runs\/<run-id>/,
);
assert.match(currentInstallation, /Inkbeam-0\.2\.0-macos\.zip/);
assert.match(currentInstallation, /Inkbeam-Chrome-0\.2\.0\.zip/);
assert.match(currentInstallation, /- Result: `<PASS\|FAIL\|BLOCKED>`/);

const legacyProduct = ["My", "Shottr"].join("");
const legacyProjectExtension = [".", "my", "shottr"].join("");
const legacyInterface = ["Quick", " Ink"].join("");
assert.ok(historicalNotes.startsWith(`# ${legacyProduct} v0.1.0\n`));
assert.ok(historicalAcceptance.startsWith(`# ${legacyProduct} v1 manual acceptance record\n`));
assert.ok(historicalInstallation.startsWith(`# ${legacyProduct} v0.1.0 release-installation record\n`));
assert.ok(historicalNotes.includes(`${legacyProduct}-0.1.0-macos.zip`));
assert.ok(historicalNotes.includes(`${legacyProduct}-Chrome-0.1.0.zip`));
assert.ok(historicalNotes.includes(legacyInterface));
assert.ok(historicalAcceptance.includes(legacyProjectExtension));
assert.equal(
  historicalNotes.split("<!-- MYSHOTTR_RELEASE_CHECKSUMS -->").length - 1,
  1,
);
assert.equal(
  historicalNotes.split("<!-- MYSHOTTR_RELEASE_COMMIT -->").length - 1,
  1,
);

const expectedLicense = `MIT License

Copyright (c) 2026 gihwan-dev

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
`;
assert.equal(license, expectedLicense);

const screenshotSHA256 =
  "2cd57f83c6afddc53bcbb004842e202501f273bca03034bb061402d733e79d3e";
assert.equal(createHash("sha256").update(screenshot).digest("hex"), screenshotSHA256);
const png = decodePng(screenshot);
assert.ok(png.width >= 1280 && png.height >= 800);
assert.ok(png.width / png.height >= 1.3 && png.width / png.height <= 2.2);
const colors = analyzeColors(png);
assert.ok(colors.unique >= 1_000);
assert.ok(colors.opaqueRatio > 0.999);
for (const [color, minimum] of [
  [[247, 241, 232], 5_000],
  [[255, 107, 95], 100],
  [[255, 77, 79], 80],
  [[22, 119, 255], 80],
  [[250, 219, 20], 80],
  [[0, 0, 0], 80],
]) {
  assert.ok(colors.count(color) >= minimum);
}

console.log(`Public documentation contract passed (${png.width}x${png.height}).`);

function markdownSections(source, level) {
  const prefix = "#".repeat(level);
  return [...source.matchAll(new RegExp(`^${prefix} (.+)$`, "gm"))]
    .map((match) => match[1]);
}

function decodePng(buffer) {
  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  assert.ok(buffer.subarray(0, 8).equals(signature));
  let offset = 8;
  let header;
  const idat = [];
  while (offset < buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    assert.ok(dataEnd + 4 <= buffer.length, `truncated PNG ${type} chunk`);
    if (type === "IHDR") {
      header = {
        width: buffer.readUInt32BE(dataStart),
        height: buffer.readUInt32BE(dataStart + 4),
        bitDepth: buffer[dataStart + 8],
        colorType: buffer[dataStart + 9],
        interlace: buffer[dataStart + 12],
      };
    } else if (type === "IDAT") {
      idat.push(buffer.subarray(dataStart, dataEnd));
    }
    offset = dataEnd + 4;
  }
  assert.ok(header);
  assert.equal(header.bitDepth, 8);
  assert.ok(header.colorType === 2 || header.colorType === 6);
  assert.equal(header.interlace, 0);
  const bytesPerPixel = header.colorType === 6 ? 4 : 3;
  const stride = header.width * bytesPerPixel;
  const raw = inflateSync(Buffer.concat(idat));
  const pixels = Buffer.alloc(header.height * stride);
  let rawOffset = 0;
  for (let row = 0; row < header.height; row += 1) {
    const filter = raw[rawOffset];
    rawOffset += 1;
    const outputOffset = row * stride;
    for (let column = 0; column < stride; column += 1) {
      const value = raw[rawOffset + column];
      const left = column >= bytesPerPixel ? pixels[outputOffset + column - bytesPerPixel] : 0;
      const up = row > 0 ? pixels[outputOffset + column - stride] : 0;
      const upLeft = row > 0 && column >= bytesPerPixel
        ? pixels[outputOffset + column - stride - bytesPerPixel]
        : 0;
      pixels[outputOffset + column] = unfilter(filter, value, left, up, upLeft);
    }
    rawOffset += stride;
  }
  return { ...header, bytesPerPixel, pixels };
}

function unfilter(filter, value, left, up, upLeft) {
  if (filter === 0) return value;
  if (filter === 1) return (value + left) & 0xff;
  if (filter === 2) return (value + up) & 0xff;
  if (filter === 3) return (value + Math.floor((left + up) / 2)) & 0xff;
  if (filter === 4) return (value + paeth(left, up, upLeft)) & 0xff;
  assert.fail(`unsupported PNG filter ${filter}`);
}

function paeth(left, up, upLeft) {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);
  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) return left;
  return upDistance <= upLeftDistance ? up : upLeft;
}

function analyzeColors(png) {
  const counts = new Map();
  let opaque = 0;
  const pixelCount = png.width * png.height;
  for (let index = 0; index < png.pixels.length; index += png.bytesPerPixel) {
    const red = png.pixels[index];
    const green = png.pixels[index + 1];
    const blue = png.pixels[index + 2];
    const alpha = png.bytesPerPixel === 4 ? png.pixels[index + 3] : 255;
    if (alpha === 255) opaque += 1;
    const key = (red << 16) | (green << 8) | blue;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return {
    unique: counts.size,
    opaqueRatio: opaque / pixelCount,
    count: ([red, green, blue]) => counts.get((red << 16) | (green << 8) | blue) ?? 0,
  };
}
